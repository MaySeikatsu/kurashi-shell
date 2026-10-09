mod common;

use std::collections::HashMap;
use std::sync::atomic::{AtomicUsize, Ordering};
use std::sync::{Arc, Mutex};
use std::time::{Duration, SystemTime, UNIX_EPOCH};

use common::{Rec, TestBus, assert_no_null};
use kurashi_services::media::{self, CommandError};
use zbus::zvariant::{OwnedObjectPath, OwnedValue, Value};

const OBJ: &str = "/org/mpris/MediaPlayer2";

struct Root;
#[zbus::interface(name = "org.mpris.MediaPlayer2")]
impl Root {
    #[zbus(property)]
    fn identity(&self) -> String {
        "Fake".into()
    }
}

/// A fake MPRIS player. A test changes its fields and emits the signal a player would emit.
/// `Position` is not signalled, so a change of it is seen only by the next read.
struct Player {
    status: String,
    title: String,
    /// `mpris:trackid` in the metadata; the metadata has none when this is None.
    track: Option<String>,
    /// Microseconds.
    position: i64,
    rate: f64,
    can_seek: bool,
    can_next: bool,
    volume: f64,
    /// How often the service read `Position`.
    position_reads: Arc<AtomicUsize>,
    /// Commands the player received, in order.
    log: Arc<Mutex<Vec<String>>>,
}

impl Player {
    fn new(status: &str, title: &str, track: &str, log: Arc<Mutex<Vec<String>>>) -> Self {
        Self {
            status: status.into(),
            title: title.into(),
            track: Some(track.into()),
            position: 0,
            rate: 1.0,
            can_seek: true,
            can_next: true,
            volume: 0.5,
            position_reads: Arc::default(),
            log,
        }
    }
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
        if let Some(track) = &self.track {
            let path = zbus::zvariant::ObjectPath::try_from(track.as_str()).unwrap();
            m.insert(
                "mpris:trackid".into(),
                Value::from(path).try_into().unwrap(),
            );
        }
        m
    }
    #[zbus(property)]
    fn rate(&self) -> f64 {
        self.rate
    }
    #[zbus(property)]
    fn position(&self) -> i64 {
        self.position_reads.fetch_add(1, Ordering::SeqCst);
        self.position
    }
    #[zbus(property)]
    fn can_seek(&self) -> bool {
        self.can_seek
    }
    #[zbus(property)]
    fn can_go_next(&self) -> bool {
        self.can_next
    }
    #[zbus(property)]
    fn can_go_previous(&self) -> bool {
        false
    }
    #[zbus(property)]
    fn can_play(&self) -> bool {
        true
    }
    #[zbus(property)]
    fn can_pause(&self) -> bool {
        true
    }
    #[zbus(property)]
    fn volume(&self) -> f64 {
        self.volume
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
    fn set_position(&self, track: OwnedObjectPath, us: i64) {
        self.log
            .lock()
            .unwrap()
            .push(format!("SetPosition {} {us}", track.as_str()));
    }
    #[zbus(signal)]
    async fn seeked(
        emitter: &zbus::object_server::SignalEmitter<'_>,
        position: i64,
    ) -> zbus::Result<()>;
}

async fn serve(bus: &TestBus, name: &str, player: Player) -> zbus::Connection {
    let c = bus.server(name).await;
    let os = c.object_server();
    os.at(OBJ, Root).await.unwrap();
    os.at(OBJ, player).await.unwrap();
    c
}

/// The fake served on `c`: its state through `get_mut`, its signals through `signal_emitter`.
async fn fake(c: &zbus::Connection) -> zbus::object_server::InterfaceRef<Player> {
    c.object_server().interface::<_, Player>(OBJ).await.unwrap()
}

/// How often the service has read the position of the player on `c`.
async fn reads(c: &zbus::Connection) -> usize {
    let r = fake(c).await;
    let player = r.get().await;
    player.position_reads.load(Ordering::SeqCst)
}

// Each helper changes one property and emits the `PropertiesChanged` a player emits for it.

async fn set_status(c: &zbus::Connection, status: &str) {
    let r = fake(c).await;
    r.get_mut().await.status = status.into();
    r.get()
        .await
        .playback_status_changed(r.signal_emitter())
        .await
        .unwrap();
}

async fn set_track(c: &zbus::Connection, title: &str, track: &str) {
    let r = fake(c).await;
    r.get_mut().await.title = title.into();
    r.get_mut().await.track = Some(track.into());
    r.get()
        .await
        .metadata_changed(r.signal_emitter())
        .await
        .unwrap();
}

async fn set_rate(c: &zbus::Connection, rate: f64) {
    let r = fake(c).await;
    r.get_mut().await.rate = rate;
    r.get()
        .await
        .rate_changed(r.signal_emitter())
        .await
        .unwrap();
}

async fn set_can_seek(c: &zbus::Connection, on: bool) {
    let r = fake(c).await;
    r.get_mut().await.can_seek = on;
    r.get()
        .await
        .can_seek_changed(r.signal_emitter())
        .await
        .unwrap();
}

async fn set_can_next(c: &zbus::Connection, on: bool) {
    let r = fake(c).await;
    r.get_mut().await.can_next = on;
    r.get()
        .await
        .can_go_next_changed(r.signal_emitter())
        .await
        .unwrap();
}

async fn set_volume(c: &zbus::Connection, volume: f64) {
    let r = fake(c).await;
    r.get_mut().await.volume = volume;
    r.get()
        .await
        .volume_changed(r.signal_emitter())
        .await
        .unwrap();
}

/// The player moves to `us` and says so with `Seeked`.
async fn seek_to(c: &zbus::Connection, us: i64) {
    let r = fake(c).await;
    r.get_mut().await.position = us;
    Player::seeked(r.signal_emitter(), us).await.unwrap();
}

fn now_ms() -> i64 {
    i64::try_from(
        SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap()
            .as_millis(),
    )
    .unwrap()
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
    assert_eq!(d["can"]["seek"], false);
    assert_no_null(&d);
    assert!(matches!(cmds.seek(1).await, Err(CommandError::NoPlayer)));

    // Player appears (paused).
    let log = Arc::new(Mutex::new(vec![]));
    let a = serve(
        &bus,
        "org.mpris.MediaPlayer2.aaa",
        Player::new("Paused", "One", "/t/1", log.clone()),
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
    assert_eq!(d["rate"], 1.0);
    assert_eq!(
        d["can"],
        serde_json::json!({"seek": true, "next": true, "prev": false, "play": true, "pause": true})
    );
    assert_eq!(d["players"][0]["active"], true);
    assert_no_null(&d);

    // Property change -> new document.
    set_status(&a, "Playing").await;
    rec.wait("a playing", |d| d["playing"] == true).await;

    // A second player starts playing and becomes active.
    let b = serve(
        &bus,
        "org.mpris.MediaPlayer2.bbb",
        Player::new("Playing", "Two", "/t/2", Arc::default()),
    )
    .await;
    let d = rec.wait("b active", |d| d["title"] == "Two").await;
    assert_eq!(d["players"].as_array().unwrap().len(), 2);
    assert_eq!(d["players"][1]["active"], true);

    // Commands hit the shown player (b), then select a explicitly.
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
        Player::new("Playing", "Three", "/t/3", Arc::default()),
    )
    .await;
    tokio::time::sleep(Duration::from_millis(300)).await;
    assert_eq!(rec.count(), n, "sink called after handle drop");
}

#[tokio::test]
async fn position_is_read_on_events_only() {
    let bus = TestBus::start();
    let a = serve(
        &bus,
        "org.mpris.MediaPlayer2.aaa",
        Player::new("Paused", "One", "/t/1", Arc::default()),
    )
    .await;
    fake(&a).await.get_mut().await.position = 5_000_000;

    let rec = Rec::new();
    let before = now_ms();
    let (handle, _cmds) = media::start(bus.conn().await, rec.clone()).await.unwrap();

    // The subscriber's start reads the position once, and publishes the time of that read.
    let d = rec
        .wait("initial read", |d| d["position_us"] == 5_000_000)
        .await;
    let first_at = d["position_at_ms"].as_i64().unwrap();
    assert!(
        before <= first_at && first_at <= now_ms(),
        "position_at_ms is the wall clock of the read"
    );
    assert_eq!(reads(&a).await, 1);

    // Nothing happens: no read and no new document (no timer).
    let docs = rec.count();
    tokio::time::sleep(Duration::from_millis(300)).await;
    assert_eq!(reads(&a).await, 1);
    assert_eq!(rec.count(), docs);

    // The player moves on without a signal: the document keeps the last read.
    fake(&a).await.get_mut().await.position = 9_000_000;
    tokio::time::sleep(Duration::from_millis(300)).await;
    assert_eq!(reads(&a).await, 1);
    assert_eq!(rec.count(), docs);

    // An unrelated property changes: the service looks at the player, but reads no position.
    set_volume(&a, 0.8).await;
    tokio::time::sleep(Duration::from_millis(300)).await;
    assert_eq!(reads(&a).await, 1);

    // Play: the play state changed, so the position is read once, and it is the current one.
    let before_play = now_ms();
    set_status(&a, "Playing").await;
    let d = rec.wait("playing read", |d| d["playing"] == true).await;
    assert_eq!(d["position_us"], 9_000_000);
    assert!(d["position_at_ms"].as_i64().unwrap() >= before_play);
    assert_eq!(reads(&a).await, 2);

    // Seeked: the position is read at once.
    seek_to(&a, 30_000_000).await;
    rec.wait("seeked", |d| d["position_us"] == 30_000_000).await;
    assert_eq!(reads(&a).await, 3);

    // A rate change is a state change.
    set_rate(&a, 2.0).await;
    rec.wait("rate", |d| d["rate"] == 2.0).await;
    assert_eq!(reads(&a).await, 4);

    // Another track: its position is read.
    fake(&a).await.get_mut().await.position = 0;
    set_track(&a, "Two", "/t/2").await;
    rec.wait("new track", |d| {
        d["title"] == "Two" && d["position_us"] == 0
    })
    .await;
    assert_eq!(reads(&a).await, 5);

    // Pause: the play state changed, so the position is read again.
    set_status(&a, "Paused").await;
    rec.wait("paused", |d| d["playing"] == false).await;
    assert_eq!(reads(&a).await, 6);

    // Idle: no reads and no documents.
    let docs = rec.count();
    tokio::time::sleep(Duration::from_millis(300)).await;
    assert_eq!(reads(&a).await, 6);
    assert_eq!(rec.count(), docs);
    drop(handle);
}

#[tokio::test]
async fn can_follows_the_player_and_gates_seek() {
    let bus = TestBus::start();
    let log = Arc::new(Mutex::new(vec![]));
    let mut player = Player::new("Paused", "One", "/t/1", log.clone());
    player.can_seek = false;
    let a = serve(&bus, "org.mpris.MediaPlayer2.aaa", player).await;
    let rec = Rec::new();
    let (handle, cmds) = media::start(bus.conn().await, rec.clone()).await.unwrap();

    let d = rec.wait("a", |d| d["title"] == "One").await;
    assert_eq!(d["can"]["seek"], false);
    assert_eq!(d["can"]["next"], true);

    // Refused by the daemon's view of the player: nothing reaches the player.
    assert!(matches!(cmds.seek(5).await, Err(CommandError::CannotSeek)));
    assert!(matches!(
        cmds.set_position(1_000).await,
        Err(CommandError::CannotSeek)
    ));
    assert!(log.lock().unwrap().is_empty());

    // The player allows it: the document says so, and the commands go through.
    set_can_seek(&a, true).await;
    rec.wait("seek allowed", |d| d["can"]["seek"] == true).await;
    cmds.seek(5).await.unwrap();
    cmds.set_position(1_000).await.unwrap();
    assert_eq!(
        *log.lock().unwrap(),
        vec!["Seek 5", "SetPosition /t/1 1000"]
    );

    // Back again; CanGoNext follows its property too.
    set_can_seek(&a, false).await;
    set_can_next(&a, false).await;
    let d = rec
        .wait("seek refused again", |d| d["can"]["seek"] == false)
        .await;
    assert_eq!(d["can"]["next"], false);
    assert!(matches!(cmds.seek(5).await, Err(CommandError::CannotSeek)));
    assert_eq!(log.lock().unwrap().len(), 2);
    drop(handle);
}

#[tokio::test]
async fn set_position_needs_a_track_id() {
    let bus = TestBus::start();
    let log = Arc::new(Mutex::new(vec![]));
    let mut player = Player::new("Playing", "One", "/t/1", log.clone());
    player.track = None;
    let _a = serve(&bus, "org.mpris.MediaPlayer2.aaa", player).await;
    let rec = Rec::new();
    let (handle, cmds) = media::start(bus.conn().await, rec.clone()).await.unwrap();

    rec.wait("a", |d| d["title"] == "One").await;
    // SetPosition names the track; without a track id there is nothing to name.
    assert!(matches!(
        cmds.set_position(1_000).await,
        Err(CommandError::NoTrack)
    ));
    // A relative seek needs no track id.
    cmds.seek(5).await.unwrap();
    assert_eq!(*log.lock().unwrap(), vec!["Seek 5"]);
    drop(handle);
}

#[tokio::test]
async fn select_switches_the_shown_player_and_reads_its_position() {
    let bus = TestBus::start();
    let (log_a, log_b) = (Arc::new(Mutex::new(vec![])), Arc::new(Mutex::new(vec![])));
    let mut pa = Player::new("Paused", "One", "/t/1", log_a.clone());
    pa.position = 1_000_000;
    let mut pb = Player::new("Playing", "Two", "/t/2", log_b.clone());
    pb.position = 2_000_000;
    let a = serve(&bus, "org.mpris.MediaPlayer2.aaa", pa).await;
    let b = serve(&bus, "org.mpris.MediaPlayer2.bbb", pb).await;
    let rec = Rec::new();
    let (handle, cmds) = media::start(bus.conn().await, rec.clone()).await.unwrap();

    // b plays, so b is shown; only the shown player's position is read.
    let d = rec.wait("b shown", |d| d["title"] == "Two").await;
    assert_eq!(d["position_us"], 2_000_000);
    assert_eq!(d["players"][0]["active"], false);
    assert_eq!(d["players"][1]["active"], true);
    assert_eq!((reads(&a).await, reads(&b).await), (0, 1));

    cmds.select_player("org.mpris.MediaPlayer2.aaa");
    let d = rec.wait("a shown", |d| d["title"] == "One").await;
    assert_eq!(d["position_us"], 1_000_000);
    assert_eq!(d["players"][0]["active"], true);
    assert_eq!(d["players"][1]["active"], false);
    assert_eq!((reads(&a).await, reads(&b).await), (1, 1));

    // Commands follow the shown player.
    cmds.play_pause().await.unwrap();
    assert_eq!(*log_a.lock().unwrap(), vec!["PlayPause"]);
    assert!(log_b.lock().unwrap().is_empty());

    // A selection that is not on the bus changes nothing.
    cmds.select_player("org.mpris.MediaPlayer2.zzz");
    tokio::time::sleep(Duration::from_millis(300)).await;
    assert_eq!(rec.last().unwrap()["title"], "One");
    assert_eq!(reads(&a).await, 1);
    drop(handle);
}

#[tokio::test]
async fn bus_gone_marks_unavailable() {
    // The daemon dies with a player on the bus. The empty list it leaves behind would read as
    // "nothing playing", so the document must say the MPRIS stream is gone instead.
    let mut bus = TestBus::start();
    let _a = serve(
        &bus,
        "org.mpris.MediaPlayer2.aaa",
        Player::new("Playing", "One", "/t/1", Arc::default()),
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
    assert_eq!(d["can"]["seek"], false);
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
        Player::new("Playing", "One", "/t/1", Arc::default()),
    )
    .await;
    rec.wait("player seen", |d| d["title"] == "One").await;
    drop(handle);
}
