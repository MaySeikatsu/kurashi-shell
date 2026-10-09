mod common;

use std::collections::HashMap;
use std::sync::{Arc, Mutex};
use std::time::Duration;

use common::{Rec, TestBus, assert_no_null};
use kurashi_services::media;
use zbus::zvariant::{OwnedValue, Value};

struct Root;
#[zbus::interface(name = "org.mpris.MediaPlayer2")]
impl Root {
    #[zbus(property)]
    fn identity(&self) -> String {
        "Fake".into()
    }
}

struct Player {
    status: String,
    title: String,
    log: Arc<Mutex<Vec<String>>>,
}
#[zbus::interface(name = "org.mpris.MediaPlayer2.Player")]
impl Player {
    #[zbus(property)]
    fn playback_status(&self) -> String {
        self.status.clone()
    }
    #[zbus(property)]
    fn metadata(&self) -> HashMap<String, OwnedValue> {
        let mut m = HashMap::new();
        m.insert(
            "xesam:title".into(),
            Value::from(self.title.as_str()).try_into().unwrap(),
        );
        m.insert(
            "xesam:artist".into(),
            Value::from(vec!["A".to_string(), "B".to_string()])
                .try_into()
                .unwrap(),
        );
        m.insert("xesam:album".into(), Value::from("Alb").try_into().unwrap());
        m.insert(
            "mpris:length".into(),
            Value::from(1_000_000i64).try_into().unwrap(),
        );
        m
    }
    #[zbus(property)]
    fn can_go_next(&self) -> bool {
        true
    }
    #[zbus(property)]
    fn can_go_previous(&self) -> bool {
        false
    }
    #[zbus(property)]
    fn can_seek(&self) -> bool {
        true
    }
    fn play_pause(&self) {
        self.log.lock().unwrap().push("PlayPause".into());
    }
    fn next(&self) {
        self.log.lock().unwrap().push("Next".into());
    }
    fn seek(&self, off: i64) {
        self.log.lock().unwrap().push(format!("Seek {off}"));
    }
}

async fn serve(
    bus: &TestBus,
    name: &str,
    status: &str,
    title: &str,
    log: Arc<Mutex<Vec<String>>>,
) -> zbus::Connection {
    let c = bus.server(name).await;
    let os = c.object_server();
    os.at("/org/mpris/MediaPlayer2", Root).await.unwrap();
    os.at(
        "/org/mpris/MediaPlayer2",
        Player {
            status: status.into(),
            title: title.into(),
            log,
        },
    )
    .await
    .unwrap();
    c
}

async fn set_status(c: &zbus::Connection, status: &str) {
    let r = c
        .object_server()
        .interface::<_, Player>("/org/mpris/MediaPlayer2")
        .await
        .unwrap();
    r.get_mut().await.status = status.into();
    r.get()
        .await
        .playback_status_changed(r.signal_emitter())
        .await
        .unwrap();
}

#[tokio::test]
async fn media_lifecycle() {
    let bus = TestBus::start();
    let rec = Rec::new();
    let (handle, cmds) = media::start(bus.conn().await, rec.clone()).await.unwrap();

    // No players: empty but well-formed, and the stream is alive, so available.
    let d = rec.wait("empty", |_| true).await;
    assert_eq!(d["players"], serde_json::json!([]));
    assert_eq!(d["playing"], false);
    assert_eq!(d["available"], true);
    assert_no_null(&d);

    // Player appears (paused).
    let log = Arc::new(Mutex::new(vec![]));
    let a = serve(
        &bus,
        "org.mpris.MediaPlayer2.aaa",
        "Paused",
        "One",
        log.clone(),
    )
    .await;
    let d = rec
        .wait("a appears", |d| {
            d["players"].as_array().is_some_and(|p| p.len() == 1)
        })
        .await;
    assert_eq!(d["title"], "One");
    assert_eq!(d["artist"], "A, B");
    assert_eq!(d["album"], "Alb");
    assert_eq!(d["length_us"], 1_000_000);
    assert_eq!(d["player"], "Fake");
    assert_eq!(d["playing"], false);
    assert_eq!(
        (
            d["can_next"].clone(),
            d["can_prev"].clone(),
            d["can_seek"].clone()
        ),
        (true.into(), false.into(), true.into())
    );
    assert_no_null(&d);

    // Property change -> new document.
    set_status(&a, "Playing").await;
    rec.wait("a playing", |d| d["playing"] == true).await;

    // A second player starts playing and becomes active.
    let b = serve(
        &bus,
        "org.mpris.MediaPlayer2.bbb",
        "Playing",
        "Two",
        Arc::default(),
    )
    .await;
    let d = rec.wait("b active", |d| d["title"] == "Two").await;
    assert_eq!(d["players"].as_array().unwrap().len(), 2);

    // Commands hit the active player (b), then select a explicitly.
    cmds.select_player("org.mpris.MediaPlayer2.aaa");
    rec.wait("a selected", |d| d["title"] == "One").await;
    cmds.play_pause().await.unwrap();
    cmds.next().await.unwrap();
    cmds.seek(5).await.unwrap();
    assert_eq!(*log.lock().unwrap(), vec!["PlayPause", "Next", "Seek 5"]);

    // Active player vanishes -> falls back to the other one.
    drop(a);
    let d = rec
        .wait("a gone", |d| {
            d["players"].as_array().is_some_and(|p| p.len() == 1)
        })
        .await;
    assert_eq!(d["title"], "Two");

    // Last one vanishes -> empty again. That is "no players", so still available.
    drop(b);
    let d = rec
        .wait("all gone", |d| d["players"] == serde_json::json!([]))
        .await;
    assert_eq!(d["title"], "");
    assert_eq!(d["available"], true);

    // Dropping the handle stops all signal handling.
    drop(handle);
    tokio::time::sleep(Duration::from_millis(100)).await;
    let n = rec.count();
    let _c = serve(
        &bus,
        "org.mpris.MediaPlayer2.ccc",
        "Playing",
        "Three",
        Arc::default(),
    )
    .await;
    tokio::time::sleep(Duration::from_millis(300)).await;
    assert_eq!(rec.count(), n, "sink called after handle drop");
}

#[tokio::test]
async fn bus_gone_marks_unavailable() {
    // The daemon dies with a player on the bus. The empty list it leaves behind would read as
    // "nothing playing", so the document must say the MPRIS stream is gone instead.
    let mut bus = TestBus::start();
    let _a = serve(
        &bus,
        "org.mpris.MediaPlayer2.aaa",
        "Playing",
        "One",
        Arc::default(),
    )
    .await;
    let rec = Rec::new();
    let (handle, _cmds) = media::start(bus.conn().await, rec.clone()).await.unwrap();
    rec.wait("player seen", |d| {
        d["title"] == "One" && d["available"] == true
    })
    .await;

    bus.kill();
    let d = rec.wait("bus gone", |d| d["available"] == false).await;
    assert_eq!(d["players"], serde_json::json!([]));
    assert_eq!(d["playing"], false);
    assert_no_null(&d);
    drop(handle);
}

#[tokio::test]
async fn dropped_commands_keep_following_players() {
    // The ServiceHandle owns the service's lifetime; losing the command handle must not stop it.
    let bus = TestBus::start();
    let rec = Rec::new();
    let (handle, cmds) = media::start(bus.conn().await, rec.clone()).await.unwrap();
    drop(cmds);

    let _a = serve(
        &bus,
        "org.mpris.MediaPlayer2.aaa",
        "Playing",
        "One",
        Arc::default(),
    )
    .await;
    rec.wait("player seen", |d| d["title"] == "One").await;
    drop(handle);
}
