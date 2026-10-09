//! The quick settings pages' daemon side (W13): `svc.network.scan` and the `network.*` actions over
//! a private bus with a fake NetworkManager. Nothing here touches the user's session or system bus.

use std::collections::HashMap;
use std::io::{BufRead, BufReader};
use std::path::PathBuf;
use std::process::{Child, Command, Stdio};
use std::sync::{Arc, Mutex};
use std::time::{Duration, Instant};

use kurashid::actions::{ActionError, ActionRegistry};
use kurashid::hub::Hub;
use kurashid::services::ConnectFn;
use kurashid::wiring::{
    ARGS_INVALID, NETWORK_NEEDS_SECRET, NETWORK_NOT_FOUND, NETWORK_NOT_SAVED, NETWORK_REFUSED,
    NO_SUCH_SOURCE, NO_SUCH_STREAM, SERVICE_NOT_RUNNING,
};
use serde_json::{Value, json};
use zbus::Connection;
use zbus::zvariant::{OwnedObjectPath, OwnedValue};

const UNTIL: Duration = Duration::from_secs(10);
/// How often a test's subscription rescans: fast enough to count rescans in a second.
const SCAN_EVERY: Duration = Duration::from_millis(100);

/// Polls `ok` until it holds; the test fails when `UNTIL` runs out first.
async fn until(what: &str, mut ok: impl FnMut() -> bool) {
    let deadline = Instant::now() + UNTIL;
    while !ok() {
        assert!(Instant::now() < deadline, "timed out waiting for {what}");
        tokio::time::sleep(Duration::from_millis(25)).await;
    }
}

/// A directory for one test's bus, removed when the test ends. Declared before the bus so it
/// outlives it.
struct Scratch(PathBuf);

impl Scratch {
    fn new(tag: &str) -> Self {
        let dir = std::env::temp_dir().join(format!("kurashid-pages-{tag}-{}", std::process::id()));
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

// ---- svc.network and svc.network.scan -----------------------------------------------------------

const NM: &str = "/org/freedesktop/NetworkManager";
const DEV: &str = "/org/freedesktop/NetworkManager/Devices/1";
const SETTINGS: &str = "/org/freedesktop/NetworkManager/Settings";
const ACTIVE: &str = "/org/freedesktop/NetworkManager/ActiveConnection/1";
const HOME_PROFILE: &str = "/org/freedesktop/NetworkManager/Settings/1";

/// Access points in range: (path, ssid, strength, secured). Two entries share "Home" (the second is
/// weaker); the first is the one the wifi device is connected to.
const APS: [(&str, &str, u8, bool); 4] = [
    (
        "/org/freedesktop/NetworkManager/AccessPoint/1",
        "Home",
        60,
        true,
    ),
    (
        "/org/freedesktop/NetworkManager/AccessPoint/2",
        "Home",
        40,
        true,
    ),
    (
        "/org/freedesktop/NetworkManager/AccessPoint/3",
        "Cafe",
        80,
        false,
    ),
    (
        "/org/freedesktop/NetworkManager/AccessPoint/4",
        "Office",
        30,
        true,
    ),
];
const ACTIVE_AP: &str = "/org/freedesktop/NetworkManager/AccessPoint/1";

/// What the fake NetworkManager holds. The test changes it, and its objects answer from it.
struct World {
    wifi: bool,
    wwan: bool,
    /// The primary connection's path, `/` when nothing is active.
    primary: String,
    /// Every rescan request the wifi device received.
    scans: usize,
    /// Each call that changed something, in order.
    log: Vec<String>,
    /// Every change is answered with polkit's refusal.
    refuse: bool,
}

type Shared = Arc<Mutex<World>>;

fn path(p: &str) -> OwnedObjectPath {
    OwnedObjectPath::try_from(p).unwrap()
}

fn refused() -> zbus::fdo::Error {
    zbus::fdo::Error::AccessDenied("Not authorized to control networking.".into())
}

/// `org.freedesktop.NetworkManager`: the switches, the primary connection and the connect calls.
struct Root(Shared);

#[zbus::interface(name = "org.freedesktop.NetworkManager")]
impl Root {
    #[zbus(property)]
    fn state(&self) -> u32 {
        70
    }
    #[zbus(property)]
    fn wireless_enabled(&self) -> bool {
        self.0.lock().unwrap().wifi
    }
    #[zbus(property)]
    fn set_wireless_enabled(&mut self, on: bool) -> zbus::fdo::Result<()> {
        let mut w = self.0.lock().unwrap();
        if w.refuse {
            return Err(refused());
        }
        w.wifi = on;
        Ok(())
    }
    #[zbus(property)]
    fn wwan_enabled(&self) -> bool {
        self.0.lock().unwrap().wwan
    }
    #[zbus(property)]
    fn set_wwan_enabled(&mut self, on: bool) -> zbus::fdo::Result<()> {
        let mut w = self.0.lock().unwrap();
        if w.refuse {
            return Err(refused());
        }
        w.wwan = on;
        Ok(())
    }
    #[zbus(property)]
    fn primary_connection(&self) -> OwnedObjectPath {
        path(&self.0.lock().unwrap().primary)
    }
    #[zbus(property)]
    fn devices(&self) -> Vec<OwnedObjectPath> {
        vec![path(DEV)]
    }
    fn deactivate_connection(&self, active: OwnedObjectPath) -> zbus::fdo::Result<()> {
        let mut w = self.0.lock().unwrap();
        if w.refuse {
            return Err(refused());
        }
        w.log.push(format!("deactivate {active}"));
        w.primary = "/".into();
        Ok(())
    }
    fn activate_connection(
        &self,
        connection: OwnedObjectPath,
        _device: OwnedObjectPath,
        _specific: OwnedObjectPath,
    ) -> zbus::fdo::Result<OwnedObjectPath> {
        let mut w = self.0.lock().unwrap();
        w.log.push(format!("activate {connection}"));
        Ok(path(ACTIVE))
    }
}

/// The wifi device: its access points, its active one, and the rescan request.
struct Wireless(Shared);

#[zbus::interface(name = "org.freedesktop.NetworkManager.Device.Wireless")]
impl Wireless {
    #[zbus(property)]
    fn access_points(&self) -> Vec<OwnedObjectPath> {
        APS.iter().map(|ap| path(ap.0)).collect()
    }
    #[zbus(property)]
    fn active_access_point(&self) -> OwnedObjectPath {
        path(ACTIVE_AP)
    }
    fn request_scan(&self, _options: HashMap<String, zbus::zvariant::Value<'_>>) {
        self.0.lock().unwrap().scans += 1;
    }
}

/// The device itself: a wifi device.
struct Device;

#[zbus::interface(name = "org.freedesktop.NetworkManager.Device")]
impl Device {
    #[zbus(property)]
    fn device_type(&self) -> u32 {
        2
    }
    #[zbus(property)]
    fn interface(&self) -> String {
        "wlan0".into()
    }
}

/// One access point.
struct Ap {
    ssid: &'static str,
    strength: u8,
    secured: bool,
}

#[zbus::interface(name = "org.freedesktop.NetworkManager.AccessPoint")]
impl Ap {
    #[zbus(property)]
    fn ssid(&self) -> Vec<u8> {
        self.ssid.as_bytes().to_vec()
    }
    #[zbus(property)]
    fn strength(&self) -> u8 {
        self.strength
    }
    #[zbus(property)]
    fn flags(&self) -> u32 {
        u32::from(self.secured)
    }
    #[zbus(property)]
    fn wpa_flags(&self) -> u32 {
        0
    }
    #[zbus(property)]
    fn rsn_flags(&self) -> u32 {
        0
    }
}

/// `Settings`: the saved profiles.
struct SettingsRoot;

#[zbus::interface(name = "org.freedesktop.NetworkManager.Settings")]
impl SettingsRoot {
    fn list_connections(&self) -> Vec<OwnedObjectPath> {
        vec![path(HOME_PROFILE)]
    }
}

/// A saved wifi profile for `ssid`.
struct Profile {
    ssid: &'static str,
}

#[zbus::interface(name = "org.freedesktop.NetworkManager.Settings.Connection")]
impl Profile {
    fn get_settings(&self) -> HashMap<String, HashMap<String, OwnedValue>> {
        let value = |v: zbus::zvariant::Value<'_>| OwnedValue::try_from(v).unwrap();
        let connection = HashMap::from([("type".to_string(), value("802-11-wireless".into()))]);
        let wifi = HashMap::from([(
            "ssid".to_string(),
            value(self.ssid.as_bytes().to_vec().into()),
        )]);
        HashMap::from([
            ("connection".to_string(), connection),
            ("802-11-wireless".to_string(), wifi),
        ])
    }
}

/// Serves the fake NetworkManager on `addr` and returns its connection (keep it alive).
async fn serve_nm(addr: &str, world: Shared) -> Connection {
    let conn = zbus::connection::Builder::address(addr)
        .unwrap()
        .build()
        .await
        .unwrap();
    conn.request_name("org.freedesktop.NetworkManager")
        .await
        .unwrap();
    let os = conn.object_server();
    os.at(NM, Root(world.clone())).await.unwrap();
    os.at(DEV, Device).await.unwrap();
    os.at(DEV, Wireless(world.clone())).await.unwrap();
    for (p, ssid, strength, secured) in APS {
        os.at(
            p,
            Ap {
                ssid,
                strength,
                secured,
            },
        )
        .await
        .unwrap();
    }
    os.at(SETTINGS, SettingsRoot).await.unwrap();
    os.at(HOME_PROFILE, Profile { ssid: "Home" }).await.unwrap();
    conn
}

fn fresh_world() -> Shared {
    Arc::new(Mutex::new(World {
        wifi: true,
        wwan: true,
        primary: ACTIVE.into(),
        scans: 0,
        log: Vec::new(),
        refuse: false,
    }))
}

fn networks(hub: &Hub) -> Value {
    hub.snapshot("svc.network.scan").unwrap().1["networks"].clone()
}

#[tokio::test]
async fn scan_lists_each_network_once_and_rescans_only_while_subscribed() {
    let scratch = Scratch::new("scan");
    let _bus = PrivateBus::start(&scratch);
    let world = fresh_world();
    let _nm = serve_nm(&scratch.addr(), world.clone()).await;
    let hub = Hub::new();
    let mut actions = ActionRegistry::default();
    kurashid::wiring::network_paced(&hub, &mut actions, bus_at(scratch.addr()), SCAN_EVERY);
    let scans = || world.lock().unwrap().scans;

    // Not subscribed: nothing lists, nothing scans.
    tokio::time::sleep(Duration::from_millis(350)).await;
    assert_eq!(scans(), 0, "scanned without a subscriber");
    assert_eq!(hub.snapshot("svc.network.scan").unwrap().1, json!({}));

    hub.subscribe("svc.network.scan").unwrap();
    until("the networks in range", || networks(&hub).is_array()).await;
    // One row per SSID (its strongest access point), the active one first, then by strength.
    assert_eq!(
        networks(&hub),
        json!([
            {"ssid": "Home", "strength": 60, "secure": true, "known": true, "active": true},
            {"ssid": "Cafe", "strength": 80, "secure": false, "known": false, "active": false},
            {"ssid": "Office", "strength": 30, "secure": true, "known": false, "active": false},
        ])
    );
    until("several rescans", || scans() >= 3).await;

    // Wi-Fi switched off: the list is not claimed, and the reason says why.
    world.lock().unwrap().wifi = false;
    until("the wifi-off reason", || {
        hub.snapshot("svc.network.scan").unwrap().1["reason"] == "error.network.wifi_off"
    })
    .await;
    assert_eq!(
        hub.snapshot("svc.network.scan").unwrap().1,
        json!({"available": false, "reason": "error.network.wifi_off"})
    );
    world.lock().unwrap().wifi = true;

    // Last unsubscribe: the scans stop with the service.
    hub.unsubscribe("svc.network.scan");
    let at_stop = scans();
    tokio::time::sleep(Duration::from_millis(500)).await;
    assert_eq!(scans(), at_stop, "rescans after the last unsubscribe");
}

#[tokio::test]
async fn connect_joins_saved_networks_and_says_why_it_cannot_join_the_rest() {
    let scratch = Scratch::new("connect");
    let _bus = PrivateBus::start(&scratch);
    let world = fresh_world();
    let _nm = serve_nm(&scratch.addr(), world.clone()).await;
    let hub = Hub::new();
    let mut actions = ActionRegistry::default();
    kurashid::wiring::network_paced(&hub, &mut actions, bus_at(scratch.addr()), SCAN_EVERY);

    // Not subscribed: refused as not running, and nothing starts.
    assert_eq!(
        actions
            .invoke("network.connect", json!({"ssid": "Home"}))
            .await,
        Err(ActionError::Unavailable(SERVICE_NOT_RUNNING.into()))
    );

    hub.subscribe("svc.network").unwrap();
    until("NetworkManager's state", || {
        hub.snapshot("svc.network").unwrap().1["state"] == "connected"
    })
    .await;

    // A saved network joins; the document follows NetworkManager, not this call.
    assert_eq!(
        actions
            .invoke("network.connect", json!({"ssid": "Home"}))
            .await,
        Ok(None)
    );
    assert_eq!(
        world.lock().unwrap().log,
        vec![format!("activate {HOME_PROFILE}")]
    );

    // Refused, each with its key: secured but not saved, open but not saved, not in range.
    assert_eq!(
        actions
            .invoke("network.connect", json!({"ssid": "Office"}))
            .await,
        Err(ActionError::Unavailable(NETWORK_NEEDS_SECRET.into()))
    );
    assert_eq!(
        actions
            .invoke("network.connect", json!({"ssid": "Cafe"}))
            .await,
        Err(ActionError::Unavailable(NETWORK_NOT_SAVED.into()))
    );
    assert_eq!(
        actions
            .invoke("network.connect", json!({"ssid": "Nowhere"}))
            .await,
        Err(ActionError::Unavailable(NETWORK_NOT_FOUND.into()))
    );
    assert_eq!(
        actions.invoke("network.connect", json!({})).await,
        Err(ActionError::Invalid(ARGS_INVALID.into()))
    );
    assert_eq!(
        actions.invoke("network.connect", json!({"ssid": ""})).await,
        Err(ActionError::Invalid(ARGS_INVALID.into()))
    );
    assert_eq!(
        world.lock().unwrap().log.len(),
        1,
        "a refused join changed nothing"
    );

    hub.unsubscribe("svc.network");
}

#[tokio::test]
async fn disconnect_and_airplane_follow_networkmanager_and_refusals_come_back_as_keys() {
    let scratch = Scratch::new("airplane");
    let _bus = PrivateBus::start(&scratch);
    let world = fresh_world();
    let nm = serve_nm(&scratch.addr(), world.clone()).await;
    let hub = Hub::new();
    let mut actions = ActionRegistry::default();
    kurashid::wiring::network_paced(&hub, &mut actions, bus_at(scratch.addr()), SCAN_EVERY);
    hub.subscribe("svc.network").unwrap();
    until("NetworkManager's state", || {
        hub.snapshot("svc.network").unwrap().1["state"] == "connected"
    })
    .await;
    assert_eq!(hub.snapshot("svc.network").unwrap().1["airplane"], false);

    // Disconnect deactivates the primary connection; NetworkManager then reports no primary.
    assert_eq!(
        actions.invoke("network.disconnect", json!({})).await,
        Ok(None)
    );
    assert_eq!(
        world.lock().unwrap().log,
        vec![format!("deactivate {ACTIVE}")]
    );
    until("no primary connection", || {
        hub.snapshot("svc.network")
            .unwrap()
            .1
            .get("primary")
            .is_none()
    })
    .await;

    // Airplane mode: wifi and mobile broadband off together, so the document reports it.
    assert_eq!(
        actions
            .invoke("network.airplane", json!({"on": true}))
            .await,
        Ok(None)
    );
    until("airplane on", || {
        hub.snapshot("svc.network").unwrap().1["airplane"] == true
    })
    .await;
    assert_eq!(
        hub.snapshot("svc.network").unwrap().1["wifi_enabled"],
        false
    );
    assert_eq!(
        actions
            .invoke("network.airplane", json!({"on": false}))
            .await,
        Ok(None)
    );
    until("airplane off", || {
        hub.snapshot("svc.network").unwrap().1["airplane"] == false
    })
    .await;
    assert_eq!(hub.snapshot("svc.network").unwrap().1["wifi_enabled"], true);

    // Polkit refuses: the key comes back and the document keeps what NetworkManager reports.
    world.lock().unwrap().refuse = true;
    assert_eq!(
        actions
            .invoke("network.airplane", json!({"on": true}))
            .await,
        Err(ActionError::Unavailable(NETWORK_REFUSED.into()))
    );
    assert_eq!(hub.snapshot("svc.network").unwrap().1["wifi_enabled"], true);
    assert_eq!(
        actions.invoke("network.airplane", json!({})).await,
        Err(ActionError::Invalid(ARGS_INVALID.into()))
    );

    hub.unsubscribe("svc.network");
    drop(nm);
}

// ---- svc.audio: sources, playing streams, the mic ------------------------------------------------

/// The sound server's state: what the snapshot reports, and every write that reached it.
#[derive(Default)]
struct Mixer {
    snap: kurashi_audio::Snapshot,
    calls: Vec<String>,
}

/// A fake PulseAudio: writes change the state and report the change, as the server's subscription
/// does, so the worker publishes the new document.
struct FakeMixer {
    state: Arc<Mutex<Mixer>>,
    notifier: kurashi_audio::Notifier,
}

impl FakeMixer {
    fn edit(&self, call: String, f: impl FnOnce(&mut kurashi_audio::Snapshot)) {
        let mut m = self.state.lock().unwrap();
        m.calls.push(call);
        f(&mut m.snap);
        self.notifier.notify();
    }
}

impl kurashi_audio::Backend for FakeMixer {
    fn snapshot(&mut self) -> anyhow::Result<kurashi_audio::Snapshot> {
        Ok(self.state.lock().unwrap().snap.clone())
    }
    fn set_volume(&mut self, _linear: f64) {}
    fn set_muted(&mut self, _muted: bool) {}
    fn set_default_sink(&mut self, _id: u32) {}
    fn set_source_muted(&mut self, muted: bool) {
        self.edit(format!("source mute {muted}"), |s| {
            let id = s.default_source;
            for d in s.sources.iter_mut().filter(|d| Some(d.id) == id) {
                d.muted = muted;
            }
        });
    }
    fn set_default_source(&mut self, id: u32) {
        self.edit(format!("default source {id}"), |s| {
            s.default_source = Some(id)
        });
    }
    fn set_stream_volume(&mut self, id: u32, linear: f64) {
        self.edit(format!("stream volume {id} {linear}"), |s| {
            for st in s.streams.iter_mut().filter(|st| st.id == id) {
                st.volume = linear;
            }
        });
    }
    fn set_stream_muted(&mut self, id: u32, muted: bool) {
        self.edit(format!("stream mute {id} {muted}"), |s| {
            for st in s.streams.iter_mut().filter(|st| st.id == id) {
                st.muted = muted;
            }
        });
    }
}

fn mixer_device(id: u32, name: &str) -> kurashi_audio::Device {
    kurashi_audio::Device {
        id,
        name: name.into(),
        description: format!("{name} device"),
        volume: 0.5,
        muted: false,
    }
}

fn playing(id: u32, app: &str, volume: f64) -> kurashi_audio::Stream {
    kurashi_audio::Stream {
        id,
        app: app.into(),
        icon: None,
        volume,
        muted: false,
    }
}

#[tokio::test]
async fn audio_sources_streams_and_the_mic_follow_the_sound_server() {
    let state = Arc::new(Mutex::new(Mixer {
        snap: kurashi_audio::Snapshot {
            sinks: vec![mixer_device(1, "speakers")],
            sources: vec![mixer_device(10, "mic"), mixer_device(11, "webcam")],
            default_sink: Some(1),
            default_source: Some(10),
            streams: vec![playing(20, "Music", 0.6), playing(21, "Browser", 1.0)],
        },
        calls: Vec::new(),
    }));
    let hub = Hub::new();
    let mut actions = ActionRegistry::default();
    let shared = state.clone();
    let start = Arc::new(move |sink: Arc<dyn kurashi_services::DocSink>| {
        let shared = shared.clone();
        kurashi_audio::start_with(sink, move |notifier| {
            Ok(FakeMixer {
                state: shared,
                notifier,
            })
        })
    });
    kurashid::wiring::audio_with(
        &hub,
        &mut actions,
        &mut kurashid::Intents::default(),
        None,
        start,
    );
    let doc = |hub: &Hub| hub.snapshot("svc.audio").unwrap().1;

    // Not subscribed: nothing runs and nothing starts.
    assert_eq!(
        actions
            .invoke("audio.source.default", json!({"id": 11}))
            .await,
        Err(ActionError::Unavailable(SERVICE_NOT_RUNNING.into()))
    );

    hub.subscribe("svc.audio").unwrap();
    until("the playing streams", || {
        doc(&hub)["streams"]
            .as_array()
            .is_some_and(|s| s.len() == 2)
    })
    .await;
    assert_eq!(doc(&hub)["streams"][0]["app"], "Music");
    assert_eq!(doc(&hub)["sources"][0]["default"], true);

    // The input picker: a listed input becomes the default, anything else is refused.
    assert_eq!(
        actions
            .invoke("audio.source.default", json!({"id": 9}))
            .await,
        Err(ActionError::Invalid(NO_SUCH_SOURCE.into()))
    );
    assert_eq!(
        actions.invoke("audio.source.default", json!({})).await,
        Err(ActionError::Invalid(ARGS_INVALID.into()))
    );
    assert_eq!(
        actions
            .invoke("audio.source.default", json!({"id": 11}))
            .await,
        Ok(None)
    );
    until("the new default input", || doc(&hub)["source"]["id"] == 11).await;

    // The per-app mixer: a level within 0..=1.5 reaches the stream; unknown ids and levels do not.
    assert_eq!(
        actions
            .invoke("audio.stream.volume", json!({"id": 20, "value": 0.25}))
            .await,
        Ok(None)
    );
    until("the stream's level", || {
        doc(&hub)["streams"][0]["volume"] == 0.25
    })
    .await;
    assert_eq!(
        actions
            .invoke("audio.stream.volume", json!({"id": 99, "value": 0.25}))
            .await,
        Err(ActionError::Invalid(NO_SUCH_STREAM.into()))
    );
    assert_eq!(
        actions
            .invoke("audio.stream.volume", json!({"id": 20, "value": 2.0}))
            .await,
        Err(ActionError::Invalid(ARGS_INVALID.into()))
    );
    assert_eq!(
        actions
            .invoke("audio.stream.volume", json!({"id": 20}))
            .await,
        Err(ActionError::Invalid(ARGS_INVALID.into()))
    );

    // Mute: without `on` the stream's mute flips; with it, the value is set.
    assert_eq!(
        actions.invoke("audio.stream.mute", json!({"id": 21})).await,
        Ok(None)
    );
    until("the browser muted", || {
        doc(&hub)["streams"][1]["muted"] == true
    })
    .await;
    assert_eq!(
        actions
            .invoke("audio.stream.mute", json!({"id": 21, "on": false}))
            .await,
        Ok(None)
    );
    until("the browser unmuted", || {
        doc(&hub)["streams"][1]["muted"] == false
    })
    .await;
    assert_eq!(
        actions
            .invoke("audio.stream.mute", json!({"id": 21, "on": "yes"}))
            .await,
        Err(ActionError::Invalid(ARGS_INVALID.into()))
    );

    // The mic: the default input's mute flips.
    assert_eq!(
        actions.invoke("audio.mic.mute.toggle", json!({})).await,
        Ok(None)
    );
    until("the mic muted", || doc(&hub)["source"]["muted"] == true).await;

    let calls = state.lock().unwrap().calls.clone();
    assert!(
        calls.iter().all(|c| !c.contains("99")),
        "an unknown id reached the server: {calls:?}"
    );
    hub.unsubscribe("svc.audio");
}
