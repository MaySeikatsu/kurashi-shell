//! The media actions (`media.seek`, `media.set_position`, `media.player.select` and the transport)
//! through the daemon's own wiring: `svc.media` over a private dbus-daemon with a fake MPRIS player.
//! Nothing here touches the user's session bus.

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
    ARGS_INVALID, MEDIA_CANNOT_SEEK, MEDIA_NO_PLAYER, MEDIA_NO_SUCH_PLAYER, SERVICE_NOT_RUNNING,
};
use serde_json::json;
use zbus::Connection;
use zbus::zvariant::{OwnedObjectPath, OwnedValue, Value};

const UNTIL: Duration = Duration::from_secs(10);
const OBJ: &str = "/org/mpris/MediaPlayer2";
const PLAYER_NAME: &str = "org.mpris.MediaPlayer2.fake";

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
        let dir = std::env::temp_dir().join(format!("kurashid-media-{tag}-{}", std::process::id()));
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

/// Opens the private bus at `addr` each time the service starts, as the daemon opens the session bus.
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

struct Root;

#[zbus::interface(name = "org.mpris.MediaPlayer2")]
impl Root {
    #[zbus(property)]
    fn identity(&self) -> String {
        "Fake".into()
    }
}

/// A playing track; `can_seek` is the one thing a test changes. The log records what it received.
struct Player {
    can_seek: bool,
    log: Arc<Mutex<Vec<String>>>,
}

#[zbus::interface(name = "org.mpris.MediaPlayer2.Player")]
impl Player {
    #[zbus(property)]
    fn playback_status(&self) -> String {
        "Playing".into()
    }
    #[zbus(property)]
    fn metadata(&self) -> HashMap<String, OwnedValue> {
        let mut m = HashMap::new();
        m.insert(
            "xesam:title".into(),
            Value::from("Song").try_into().unwrap(),
        );
        let track = zbus::zvariant::ObjectPath::try_from("/t/1").unwrap();
        m.insert(
            "mpris:trackid".into(),
            Value::from(track).try_into().unwrap(),
        );
        m
    }
    #[zbus(property)]
    fn position(&self) -> i64 {
        1_000_000
    }
    #[zbus(property)]
    fn rate(&self) -> f64 {
        1.0
    }
    #[zbus(property)]
    fn can_seek(&self) -> bool {
        self.can_seek
    }
    #[zbus(property)]
    fn can_go_next(&self) -> bool {
        true
    }
    #[zbus(property)]
    fn can_go_previous(&self) -> bool {
        true
    }
    #[zbus(property)]
    fn can_play(&self) -> bool {
        true
    }
    #[zbus(property)]
    fn can_pause(&self) -> bool {
        true
    }
    fn play_pause(&self) {
        self.log.lock().unwrap().push("PlayPause".into());
    }
    fn next(&self) {
        self.log.lock().unwrap().push("Next".into());
    }
    fn previous(&self) {
        self.log.lock().unwrap().push("Previous".into());
    }
    fn seek(&self, off: i64) {
        self.log.lock().unwrap().push(format!("Seek {off}"));
    }
    fn set_position(&self, track: OwnedObjectPath, us: i64) {
        self.log
            .lock()
            .unwrap()
            .push(format!("SetPosition {} {us}", track.as_str()));
    }
}

/// A connection that owns the fake player's name and serves its objects.
async fn serve(addr: &str, can_seek: bool, log: Arc<Mutex<Vec<String>>>) -> Connection {
    let conn = zbus::connection::Builder::address(addr)
        .unwrap()
        .build()
        .await
        .unwrap();
    conn.request_name(PLAYER_NAME).await.unwrap();
    let os = conn.object_server();
    os.at(OBJ, Root).await.unwrap();
    os.at(OBJ, Player { can_seek, log }).await.unwrap();
    conn
}

async fn set_can_seek(conn: &Connection, on: bool) {
    let r = conn
        .object_server()
        .interface::<_, Player>(OBJ)
        .await
        .unwrap();
    r.get_mut().await.can_seek = on;
    r.get()
        .await
        .can_seek_changed(r.signal_emitter())
        .await
        .unwrap();
}

#[tokio::test]
async fn media_actions_refuse_what_the_player_does_not_allow_and_send_the_rest() {
    let scratch = Scratch::new("actions");
    let _bus = PrivateBus::start(&scratch);
    let log = Arc::new(Mutex::new(vec![]));
    let player = serve(&scratch.addr(), false, log.clone()).await;

    let hub = Hub::new();
    let mut actions = ActionRegistry::default();
    kurashid::wiring::media_with(&hub, &mut actions, bus_at(scratch.addr()));

    // Not subscribed: nothing runs and nothing starts.
    assert_eq!(
        actions.invoke("media.seek", json!({"offset_us": 5})).await,
        Err(ActionError::Unavailable(SERVICE_NOT_RUNNING.into()))
    );

    hub.subscribe("svc.media").unwrap();
    until("the shown player", || {
        hub.snapshot("svc.media").unwrap().1["title"] == "Song"
    })
    .await;

    // Refused before anything reaches the player: a seek it does not allow, and bad arguments.
    assert_eq!(
        actions.invoke("media.seek", json!({"offset_us": 5})).await,
        Err(ActionError::Unavailable(MEDIA_CANNOT_SEEK.into()))
    );
    assert_eq!(
        actions.invoke("media.set_position", json!({"us": 5})).await,
        Err(ActionError::Unavailable(MEDIA_CANNOT_SEEK.into()))
    );
    assert_eq!(
        actions.invoke("media.seek", json!({})).await,
        Err(ActionError::Invalid(ARGS_INVALID.into()))
    );
    assert_eq!(
        actions
            .invoke("media.set_position", json!({"us": -1}))
            .await,
        Err(ActionError::Invalid(ARGS_INVALID.into()))
    );
    assert_eq!(
        actions
            .invoke(
                "media.player.select",
                json!({"id": "org.mpris.MediaPlayer2.nope"})
            )
            .await,
        Err(ActionError::Invalid(MEDIA_NO_SUCH_PLAYER.into()))
    );
    assert!(log.lock().unwrap().is_empty());

    // The player allows seeking: the document says so, and the actions reach the player.
    set_can_seek(&player, true).await;
    until("seek allowed", || {
        hub.snapshot("svc.media").unwrap().1["can"]["seek"] == true
    })
    .await;
    assert_eq!(
        actions.invoke("media.seek", json!({"offset_us": 5})).await,
        Ok(None)
    );
    assert_eq!(
        actions
            .invoke("media.set_position", json!({"us": 2000}))
            .await,
        Ok(None)
    );
    assert_eq!(
        actions.invoke("media.play_pause", json!({})).await,
        Ok(None)
    );
    assert_eq!(
        actions
            .invoke(
                "media.player.select",
                json!({"id": "org.mpris.MediaPlayer2.fake"})
            )
            .await,
        Ok(None)
    );
    assert_eq!(
        *log.lock().unwrap(),
        vec!["Seek 5", "SetPosition /t/1 2000", "PlayPause"]
    );

    // The player goes away: no player is shown, and a seek says so.
    drop(player);
    until("no player", || {
        hub.snapshot("svc.media").unwrap().1["players"] == json!([])
    })
    .await;
    assert_eq!(
        actions.invoke("media.seek", json!({"offset_us": 5})).await,
        Err(ActionError::Unavailable(MEDIA_NO_PLAYER.into()))
    );
    hub.unsubscribe("svc.media");
}
