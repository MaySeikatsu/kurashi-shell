//! The quick-settings actions (K24) through the daemon's own wiring: `audio.sink.default` on
//! `svc.audio` over a fake sound server, and `network.wifi` on `svc.network` over a private bus with
//! a fake NetworkManager. Nothing here touches the user's session or system bus.

use std::io::{BufRead, BufReader};
use std::path::PathBuf;
use std::process::{Child, Command, Stdio};
use std::sync::Arc;
use std::time::{Duration, Instant};

use kurashi_audio::{Backend, Device, Notifier, Snapshot};
use kurashi_services::DocSink;
use kurashid::Intents;
use kurashid::actions::{ActionError, ActionRegistry};
use kurashid::hub::Hub;
use kurashid::services::ConnectFn;
use kurashid::wiring::{
    ARGS_INVALID, NETWORK_REFUSED, NETWORK_UNAVAILABLE, NO_SUCH_SINK, SERVICE_NOT_RUNNING,
};
use serde_json::json;
use zbus::Connection;

const UNTIL: Duration = Duration::from_secs(10);

/// Polls `ok` until it holds; the test fails when `UNTIL` runs out first.
async fn until(what: &str, mut ok: impl FnMut() -> bool) {
    let deadline = Instant::now() + UNTIL;
    while !ok() {
        assert!(Instant::now() < deadline, "timed out waiting for {what}");
        tokio::time::sleep(Duration::from_millis(25)).await;
    }
}

// ---- svc.audio ----------------------------------------------------------------------------------

fn device(id: u32, name: &str) -> Device {
    Device {
        id,
        name: name.into(),
        description: format!("{name} output"),
        volume: 0.5,
        muted: false,
    }
}

/// A sound server with two sinks. A change of default is reported through the notifier, as the
/// PulseAudio subscription reports it, so the worker publishes the new document.
struct FakeSoundServer {
    snap: Snapshot,
    notifier: Notifier,
}

impl Backend for FakeSoundServer {
    fn snapshot(&mut self) -> anyhow::Result<Snapshot> {
        Ok(self.snap.clone())
    }
    fn set_volume(&mut self, _linear: f64) {}
    fn set_muted(&mut self, _muted: bool) {}
    fn set_default_sink(&mut self, id: u32) {
        self.snap.default_sink = Some(id);
        self.notifier.notify();
    }
    fn set_source_muted(&mut self, _muted: bool) {}
    fn set_default_source(&mut self, _id: u32) {}
    fn set_stream_volume(&mut self, _id: u32, _linear: f64) {}
    fn set_stream_muted(&mut self, _id: u32, _muted: bool) {}
}

#[tokio::test]
async fn audio_output_picker_switches_the_default_and_refuses_what_is_not_a_sink() {
    let hub = Hub::new();
    let mut actions = ActionRegistry::default();
    let start = Arc::new(|sink: Arc<dyn DocSink>| {
        kurashi_audio::start_with(sink, |notifier| {
            Ok(FakeSoundServer {
                snap: Snapshot {
                    sinks: vec![device(1, "speakers"), device(2, "hdmi")],
                    sources: vec![],
                    default_sink: Some(1),
                    default_source: None,
                    streams: vec![],
                },
                notifier,
            })
        })
    });
    kurashid::wiring::audio_with(&hub, &mut actions, &mut Intents::default(), None, start);
    let default_id = |hub: &Hub| hub.snapshot("svc.audio").unwrap().1["sink"]["id"].clone();

    // Not subscribed: nothing runs and nothing starts.
    assert_eq!(
        actions.invoke("audio.sink.default", json!({"id": 2})).await,
        Err(ActionError::Unavailable(SERVICE_NOT_RUNNING.into()))
    );

    hub.subscribe("svc.audio").unwrap();
    until("the default sink", || default_id(&hub) == 1).await;

    // Refused before anything changes: an id that is no sink, or no id at all.
    assert_eq!(
        actions.invoke("audio.sink.default", json!({"id": 9})).await,
        Err(ActionError::Invalid(NO_SUCH_SINK.into()))
    );
    assert_eq!(
        actions.invoke("audio.sink.default", json!({})).await,
        Err(ActionError::Invalid(ARGS_INVALID.into()))
    );
    assert_eq!(default_id(&hub), 1);

    // A sink of the list: the sound server switches, and the document follows its change event.
    assert_eq!(
        actions.invoke("audio.sink.default", json!({"id": 2})).await,
        Ok(None)
    );
    until("the new default sink", || default_id(&hub) == 2).await;
    let doc = hub.snapshot("svc.audio").unwrap().1;
    assert_eq!(doc["sinks"][1]["default"], true);
    assert_eq!(doc["sinks"][0]["default"], false);

    hub.unsubscribe("svc.audio");
}

// ---- svc.network --------------------------------------------------------------------------------

const NM: &str = "/org/freedesktop/NetworkManager";

/// NetworkManager's manager object: the state and the wifi switch the document is built from.
/// `refuse` makes every change come back as polkit denies it.
struct Nm {
    wifi: bool,
    refuse: bool,
}

#[zbus::interface(name = "org.freedesktop.NetworkManager")]
impl Nm {
    #[zbus(property)]
    fn state(&self) -> u32 {
        70
    }
    #[zbus(property)]
    fn wireless_enabled(&self) -> bool {
        self.wifi
    }
    #[zbus(property)]
    fn set_wireless_enabled(&mut self, on: bool) -> zbus::fdo::Result<()> {
        if self.refuse {
            return Err(zbus::fdo::Error::AccessDenied(
                "Not authorized to control networking.".into(),
            ));
        }
        self.wifi = on;
        Ok(())
    }
    #[zbus(property)]
    fn primary_connection(&self) -> zbus::zvariant::OwnedObjectPath {
        zbus::zvariant::OwnedObjectPath::try_from("/").unwrap()
    }
}

/// A directory for one test's bus, removed when the test ends. Declared before the bus so it
/// outlives it.
struct Scratch(PathBuf);

impl Scratch {
    fn new(tag: &str) -> Self {
        let dir = std::env::temp_dir().join(format!("kurashid-quick-{tag}-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&dir);
        std::fs::create_dir_all(&dir).unwrap();
        Scratch(dir)
    }

    fn addr(&self) -> String {
        format!("unix:path={}", self.0.join("bus").display())
    }
}

impl Drop for Scratch {
    fn drop(&mut self) {
        let _ = std::fs::remove_dir_all(&self.0);
    }
}

/// A session-type dbus-daemon on the scratch socket. Dropping it kills only this child.
struct PrivateBus(Child);

impl PrivateBus {
    fn start(scratch: &Scratch) -> Self {
        let socket = scratch.0.join("bus");
        let conf = scratch.0.join("bus.conf");
        std::fs::write(
            &conf,
            format!(
                r#"<busconfig><type>session</type>
<listen>unix:path={}</listen><auth>EXTERNAL</auth>
<policy context="default"><allow send_destination="*" eavesdrop="true"/><allow eavesdrop="true"/><allow own="*"/></policy>
</busconfig>"#,
                socket.display()
            ),
        )
        .unwrap();
        let mut child = Command::new("dbus-daemon")
            .arg(format!("--config-file={}", conf.display()))
            .args(["--nofork", "--print-address"])
            .stdout(Stdio::piped())
            .spawn()
            .expect("dbus-daemon (run inside nix develop)");
        let mut printed = String::new();
        BufReader::new(child.stdout.as_mut().unwrap())
            .read_line(&mut printed)
            .unwrap();
        assert!(
            printed.trim().starts_with(&scratch.addr()),
            "the daemon listens where the test expects: {printed}"
        );
        PrivateBus(child)
    }
}

impl Drop for PrivateBus {
    fn drop(&mut self) {
        let _ = self.0.kill();
        let _ = self.0.wait();
    }
}

/// Opens the private bus at `addr` each time the service starts, as the daemon opens the system bus.
fn bus_at(addr: String) -> ConnectFn {
    Arc::new(move || {
        let addr = addr.clone();
        Box::pin(async move {
            zbus::connection::Builder::address(addr.as_str())?
                .build()
                .await
        })
    })
}

/// A connection that owns NetworkManager's name and serves its manager object.
async fn serve_nm(addr: &str) -> Connection {
    let conn = zbus::connection::Builder::address(addr)
        .unwrap()
        .build()
        .await
        .unwrap();
    conn.request_name("org.freedesktop.NetworkManager")
        .await
        .unwrap();
    conn.object_server()
        .at(
            NM,
            Nm {
                wifi: true,
                refuse: false,
            },
        )
        .await
        .unwrap();
    conn
}

#[tokio::test]
async fn wifi_switch_follows_networkmanager_and_refusals_come_back_as_keys() {
    let scratch = Scratch::new("wifi");
    let _bus = PrivateBus::start(&scratch);
    let nm = serve_nm(&scratch.addr()).await;
    let hub = Hub::new();
    let mut actions = ActionRegistry::default();
    kurashid::wiring::network_with(&hub, &mut actions, bus_at(scratch.addr()));
    let wifi = |hub: &Hub| hub.snapshot("svc.network").unwrap().1["wifi_enabled"].clone();

    // Not subscribed: the switch is refused as not running, and nothing starts.
    assert_eq!(
        actions.invoke("network.wifi", json!({"on": false})).await,
        Err(ActionError::Unavailable(SERVICE_NOT_RUNNING.into()))
    );

    hub.subscribe("svc.network").unwrap();
    until("NetworkManager's state", || {
        hub.snapshot("svc.network").unwrap().1["state"] == "connected"
    })
    .await;
    assert_eq!(wifi(&hub), true);
    assert_eq!(
        actions.invoke("network.wifi", json!({})).await,
        Err(ActionError::Invalid(ARGS_INVALID.into()))
    );

    // The change goes to NetworkManager; the document follows its PropertiesChanged.
    assert_eq!(
        actions.invoke("network.wifi", json!({"on": false})).await,
        Ok(None)
    );
    until("wifi off", || wifi(&hub) == false).await;

    // A refusal comes back as its key, and the document keeps what NetworkManager reports.
    let manager = nm.object_server().interface::<_, Nm>(NM).await.unwrap();
    manager.get_mut().await.refuse = true;
    assert_eq!(
        actions.invoke("network.wifi", json!({"on": true})).await,
        Err(ActionError::Unavailable(NETWORK_REFUSED.into()))
    );
    assert_eq!(wifi(&hub), false);

    // NetworkManager leaves the bus: the document says so, and a switch says it cannot be done.
    drop(manager);
    drop(nm);
    until("the document unavailable", || {
        hub.snapshot("svc.network").unwrap().1["state"] == "unavailable"
    })
    .await;
    assert_eq!(
        actions.invoke("network.wifi", json!({"on": true})).await,
        Err(ActionError::Unavailable(NETWORK_UNAVAILABLE.into()))
    );

    hub.unsubscribe("svc.network");
}
