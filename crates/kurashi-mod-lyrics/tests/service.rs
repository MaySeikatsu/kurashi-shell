//! The lyrics service as the daemon runs it: enabled through a `ModCtx`, its service started with a publish sink and a
//! settings feed, the track sent by `lyrics.track`. The transport is in memory: each test says what LRCLIB answers.

use std::collections::BTreeMap;
use std::sync::{Arc, Mutex};
use std::time::Duration;

use kurashi_mod_api::{
    ActionFn, BoxFuture, FaceUpdate, Hooks, ModCtx, NativeMod, Registration, ServiceFn, Settings,
    Values,
};
use kurashi_mod_lyrics::{Http, HttpError, LyricsMod};
use serde_json::{Value, json};
use tokio::sync::{Notify, watch};

struct NoHooks;
impl Hooks for NoHooks {
    fn face(&self, _face: &str, _update: FaceUpdate) {}
    fn choices_changed(&self, _source: &str) {}
}

type Answer = Result<String, HttpError>;
type AnswerFn = Box<dyn Fn(&str) -> Answer + Send>;

/// LRCLIB in memory: `answer` decides per URL; every URL asked is logged. A URL containing `slow` waits for `gate`.
struct Fake {
    answer: Mutex<AnswerFn>,
    log: Mutex<Vec<String>>,
    gate: Arc<Notify>,
}

impl Fake {
    fn new(answer: impl Fn(&str) -> Answer + Send + 'static) -> Arc<Self> {
        Arc::new(Self {
            answer: Mutex::new(Box::new(answer)),
            log: Mutex::new(Vec::new()),
            gate: Arc::new(Notify::new()),
        })
    }
    fn set(&self, answer: impl Fn(&str) -> Answer + Send + 'static) {
        *self.answer.lock().unwrap() = Box::new(answer);
    }
    fn calls(&self) -> Vec<String> {
        self.log.lock().unwrap().clone()
    }
}

impl Http for Fake {
    fn get(&self, url: String) -> BoxFuture<Answer> {
        self.log.lock().unwrap().push(url.clone());
        let r = (self.answer.lock().unwrap())(&url);
        let gate = self.gate.clone();
        Box::pin(async move {
            if url.contains("slow") {
                gate.notified().await;
            }
            r
        })
    }
}

const LRC: &str = "[00:01.00]one\n[00:02.50]two";

fn found(lrc: &str) -> Answer {
    Ok(json!({"syncedLyrics": lrc, "plainLyrics": "one\ntwo", "instrumental": false}).to_string())
}

struct Running {
    service: ServiceFn,
    track: ActionFn,
    retry: ActionFn,
    docs: watch::Receiver<Vec<Value>>,
    sink: Arc<watch::Sender<Vec<Value>>>,
    settings: watch::Sender<Values>,
    task: Option<tokio::task::JoinHandle<()>>,
}

impl Running {
    fn start(&mut self) {
        let sink = self.sink.clone();
        let publish: kurashi_mod_api::Publish = Arc::new(move |v| sink.send_modify(|d| d.push(v)));
        self.task = Some(tokio::spawn((self.service)(
            publish,
            Settings::new(self.settings.subscribe()),
        )));
    }
    fn stop(&mut self) {
        if let Some(t) = self.task.take() {
            t.abort();
        }
    }
    async fn send(&self, args: Value) {
        (self.track)(args).await.expect("lyrics.track");
    }
    /// Waits until the last published document satisfies `ok`, and returns it.
    async fn until(&mut self, what: &str, ok: impl Fn(&Value) -> bool) -> Value {
        let r = tokio::time::timeout(Duration::from_secs(5), async {
            loop {
                if let Some(v) = self.docs.borrow_and_update().last().filter(|v| ok(v)) {
                    return v.clone();
                }
                self.docs.changed().await.expect("sink");
            }
        })
        .await;
        r.unwrap_or_else(|_| {
            panic!(
                "timed out waiting for {what}; got {:?}",
                self.docs.borrow().last()
            )
        })
    }
    fn published(&self) -> Vec<Value> {
        self.docs.borrow().clone()
    }
}

fn enable(fake: Arc<Fake>, dir: &std::path::Path, values: &[(&str, Value)]) -> Running {
    let m = LyricsMod::with(
        fake,
        "http://lrclib.test".into(),
        dir.to_path_buf(),
        Arc::new(|| 1_000_000),
    );
    let provides: Vec<String> = ["service:lyrics", "action:lyrics.*"]
        .iter()
        .map(|s| (*s).to_owned())
        .collect();
    let values: Values = values
        .iter()
        .map(|(k, v)| ((*k).to_owned(), v.clone()))
        .collect::<BTreeMap<_, _>>();
    let (settings, rx) = watch::channel(values);
    let mut ctx = ModCtx::new(&provides, Settings::new(rx), Arc::new(NoHooks));
    m.enable(&mut ctx).expect("the mod enables");
    let regs = ctx.finish().expect("no refused registration");
    let service = regs
        .iter()
        .find_map(|r| match r {
            Registration::Service { run, initial, .. } => {
                assert_eq!(initial["state"], "none");
                Some(run.clone())
            }
            _ => None,
        })
        .expect("service");
    let action = |id: &str| {
        regs.iter()
            .find_map(|r| match r {
                Registration::Action { id: i, handler, .. } if i == id => Some(handler.clone()),
                _ => None,
            })
            .expect("action")
    };
    let (sink, docs) = watch::channel(Vec::new());
    Running {
        service,
        track: action("lyrics.track"),
        retry: action("lyrics.retry"),
        docs,
        sink: Arc::new(sink),
        settings,
        task: None,
    }
}

fn song() -> Value {
    json!({"title": "夜に駆ける", "artist": "YOASOBI", "album": "THE BOOK", "length_us": 261_000_000})
}

#[tokio::test]
async fn a_track_is_looked_up_once_and_then_read_from_the_cache() {
    let dir = tempfile::tempdir().unwrap();
    let fake = Fake::new(|url| {
        assert!(url.starts_with("http://lrclib.test/api/get?"), "{url}");
        found(LRC)
    });
    let mut r = enable(fake.clone(), dir.path(), &[]);
    r.start();
    r.until("nothing plays", |d| {
        d["state"] == "none" && d.get("track").is_none()
    })
    .await;
    r.send(song()).await;
    let d = r.until("ready", |d| d["state"] == "ready").await;
    assert_eq!(d["synced"], true);
    assert_eq!(
        d["lines"],
        json!([{"t_ms": 1000, "text": "one"}, {"t_ms": 2500, "text": "two"}])
    );
    assert_eq!(d["track"]["title"], "夜に駆ける");
    assert!(
        r.published().iter().any(|d| d["state"] == "searching"),
        "searching was shown first"
    );
    assert_eq!(fake.calls().len(), 1);
    // The same track again (another view) changes nothing.
    r.send(song()).await;
    tokio::time::sleep(Duration::from_millis(50)).await;
    assert_eq!(fake.calls().len(), 1);

    // A new subscription (the service starts again) reads the cache: no request, no searching state.
    r.stop();
    let before = r.published().len();
    r.start();
    let d = r.until("ready from cache", |d| d["state"] == "ready").await;
    assert_eq!(d["lines"][1]["text"], "two");
    assert_eq!(fake.calls().len(), 1);
    assert!(
        r.published()[before..]
            .iter()
            .all(|d| d["state"] != "searching")
    );

    // Nothing plays: the document says so.
    r.send(json!({})).await;
    r.until("none", |d| d["state"] == "none" && d.get("track").is_none())
        .await;
}

#[tokio::test]
async fn a_miss_of_the_get_falls_back_to_the_search() {
    let dir = tempfile::tempdir().unwrap();
    let fake = Fake::new(|url| {
        if url.contains("/api/get?") {
            Err(HttpError::Status(404))
        } else {
            Ok(json!([
                {"duration": 100.0, "plainLyrics": "other"},
                {"duration": 260.0, "syncedLyrics": "[00:03.00]found", "plainLyrics": "found"}
            ])
            .to_string())
        }
    });
    let mut r = enable(fake.clone(), dir.path(), &[]);
    r.start();
    r.send(song()).await;
    let d = r.until("ready", |d| d["state"] == "ready").await;
    assert_eq!(d["lines"], json!([{"t_ms": 3000, "text": "found"}]));
    let calls = fake.calls();
    assert_eq!(calls.len(), 2);
    assert!(
        calls[1].starts_with("http://lrclib.test/api/search?track_name="),
        "{}",
        calls[1]
    );
}

#[tokio::test]
async fn no_lyrics_is_remembered_and_the_lookup_can_be_switched_off() {
    let dir = tempfile::tempdir().unwrap();
    let fake = Fake::new(|url| {
        if url.contains("/api/get?") {
            Err(HttpError::Status(404))
        } else {
            Ok("[]".into())
        }
    });
    let mut r = enable(fake.clone(), dir.path(), &[]);
    r.start();
    r.send(song()).await;
    let d = r
        .until("none", |d| d["state"] == "none" && d.get("track").is_some())
        .await;
    assert_eq!(d["reason"], "mod-lyrics.none");
    assert_eq!(fake.calls().len(), 2);
    r.stop();
    r.start();
    r.until("none from cache", |d| d["reason"] == "mod-lyrics.none")
        .await;
    assert_eq!(fake.calls().len(), 2, "the none answer came from the cache");

    // Lookup off: a track not in the cache is not asked for.
    r.settings.send_modify(|v| {
        v.insert("online".into(), json!(false));
    });
    r.send(json!({"title": "Other", "artist": "X", "length_us": 5_000_000}))
        .await;
    let d = r
        .until("online off", |d| d["reason"] == "mod-lyrics.online_off")
        .await;
    assert_eq!(d["track"]["title"], "Other");
    assert_eq!(fake.calls().len(), 2);
}

#[tokio::test]
async fn offline_and_server_errors_say_so_and_retry_asks_again() {
    let dir = tempfile::tempdir().unwrap();
    let fake = Fake::new(|_| Err(HttpError::Offline("no route".into())));
    let mut r = enable(fake.clone(), dir.path(), &[]);
    r.start();
    r.send(song()).await;
    let d = r.until("offline", |d| d["state"] == "offline").await;
    assert_eq!(d["reason"], "mod-lyrics.offline");

    fake.set(|_| Err(HttpError::Status(503)));
    (r.retry)(json!({})).await.expect("retry");
    let d = r.until("error", |d| d["state"] == "error").await;
    assert_eq!(d["reason"], "mod-lyrics.error.server");

    fake.set(|_| found(LRC));
    (r.retry)(json!({})).await.expect("retry");
    r.until("ready", |d| d["state"] == "ready").await;
    assert_eq!(fake.calls().len(), 3);
}

#[tokio::test]
async fn a_track_change_during_a_lookup_drops_the_old_answer() {
    let dir = tempfile::tempdir().unwrap();
    let fake = Fake::new(|url| {
        if url.contains("slow") {
            found("[00:01.00]stale")
        } else {
            found("[00:01.00]fresh")
        }
    });
    let mut r = enable(fake.clone(), dir.path(), &[]);
    r.start();
    r.send(json!({"title": "slow song", "artist": "A", "length_us": 10_000_000}))
        .await;
    r.until("searching", |d| d["state"] == "searching").await;
    r.send(json!({"title": "quick song", "artist": "A", "length_us": 10_000_000}))
        .await;
    let d = r.until("ready", |d| d["state"] == "ready").await;
    assert_eq!(d["track"]["title"], "quick song");
    assert_eq!(d["lines"][0]["text"], "fresh");
    fake.gate.notify_waiters();
    tokio::time::sleep(Duration::from_millis(50)).await;
    assert!(
        r.published()
            .iter()
            .all(|d| d["lines"].get(0).is_none_or(|l| l["text"] != "stale"))
    );
}

#[tokio::test]
async fn bad_arguments_are_refused() {
    let dir = tempfile::tempdir().unwrap();
    let r = enable(Fake::new(|_| found(LRC)), dir.path(), &[]);
    assert!((r.track)(json!({"title": 5})).await.is_err());
    assert!(
        (r.track)(json!({"title": "T", "length_us": "long"}))
            .await
            .is_err()
    );
}
