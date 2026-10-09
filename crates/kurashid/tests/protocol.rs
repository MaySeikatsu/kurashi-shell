//! End-to-end protocol tests over a real unix socket (PROTOCOL §2–§7).

use std::sync::Arc;
use std::sync::atomic::{AtomicUsize, Ordering};
use std::time::Duration;

use kurashi_ipc::{ClientMsg, LineReader, ServerMsg, merge_patch, write_msg};
use kurashid::{ActionError, ActionRegistry, Daemon, Hub, Intents, Provider};
use serde_json::{Value, json};
use tokio::net::UnixStream;
use tokio::net::unix::{OwnedReadHalf, OwnedWriteHalf};
use tokio::sync::oneshot;

struct Client {
    rd: LineReader<OwnedReadHalf>,
    wr: OwnedWriteHalf,
}

impl Client {
    async fn connect(path: &std::path::Path) -> Client {
        let (rd, wr) = UnixStream::connect(path).await.unwrap().into_split();
        let mut c = Client {
            rd: LineReader::new(rd),
            wr,
        };
        c.send(ClientMsg::Hello {
            v: 1,
            client: "test".into(),
            caps: vec![],
        })
        .await;
        assert!(matches!(c.recv().await, ServerMsg::Welcome { .. }));
        c
    }
    async fn send(&mut self, m: ClientMsg) {
        write_msg(&mut self.wr, &m).await.unwrap();
    }
    async fn recv(&mut self) -> ServerMsg {
        tokio::time::timeout(Duration::from_secs(2), self.rd.next_value())
            .await
            .expect("timed out waiting for server")
            .unwrap()
            .expect("server closed")
    }
    /// Nothing arrives within `ms`.
    async fn quiet(&mut self, ms: u64) -> bool {
        tokio::time::timeout(Duration::from_millis(ms), self.rd.next_value::<ServerMsg>())
            .await
            .is_err()
    }
    async fn sub(&mut self, doc: &str) -> (u64, Value) {
        self.send(ClientMsg::Sub {
            id: "s".into(),
            doc: doc.into(),
        })
        .await;
        match self.recv().await {
            ServerMsg::Snap { rev, data, .. } => (rev, data),
            other => panic!("expected snap, got {other:?}"),
        }
    }
}

#[derive(Default)]
struct CountingProvider {
    starts: AtomicUsize,
    stops: AtomicUsize,
}

impl Provider for CountingProvider {
    fn start(&self, hub: Arc<Hub>) {
        self.starts.fetch_add(1, Ordering::SeqCst);
        hub.update("svc.counted", None, |d| d["live"] = json!(true))
            .unwrap();
    }
    fn stop(&self) {
        self.stops.fetch_add(1, Ordering::SeqCst);
    }
}

struct Fixture {
    path: std::path::PathBuf,
    hub: Arc<Hub>,
    provider: Arc<CountingProvider>,
    intent_calls: Arc<AtomicUsize>,
    _stop: oneshot::Sender<()>,
}

async fn start() -> Fixture {
    static N: AtomicUsize = AtomicUsize::new(0);
    let path = std::env::temp_dir().join(format!(
        "kurashid-test-{}-{}.sock",
        std::process::id(),
        N.fetch_add(1, Ordering::SeqCst)
    ));
    let _ = std::fs::remove_file(&path);
    let listener = tokio::net::UnixListener::bind(&path).unwrap();

    let hub = Hub::new();
    let provider = Arc::new(CountingProvider::default());
    hub.register("svc.audio", json!({"volume": 0.5, "muted": false}), None);
    hub.register(
        "svc.counted",
        json!({"live": false}),
        Some(provider.clone()),
    );

    let mut actions = ActionRegistry::default();
    let h = hub.clone();
    actions.register("audio.mute.toggle", "action.audio.mute.toggle", move |_| {
        let h = h.clone();
        async move {
            h.update("svc.audio", None, |d| {
                d["muted"] = json!(!d["muted"].as_bool().unwrap_or(false))
            })
            .map_err(|e| ActionError::Internal(e.to_string()))?;
            Ok(Some(json!({"ok": true})))
        }
    });

    let intent_calls = Arc::new(AtomicUsize::new(0));
    let mut intents = Intents::default();
    let (h, calls) = (hub.clone(), intent_calls.clone());
    intents.register("audio.volume", move |v, origin| {
        calls.fetch_add(1, Ordering::SeqCst);
        h.update("svc.audio", origin, |d| d["volume"] = v).unwrap();
    });

    let mut daemon = Daemon::new(hub.clone(), actions, intents);
    daemon.queries.insert(
        "echo".into(),
        Arc::new(|q: &str| vec![json!({"id": q, "score": 1.0})]),
    );
    let daemon = Arc::new(daemon);
    let (stop_tx, stop_rx) = oneshot::channel::<()>();
    tokio::spawn(kurashid::server::serve(listener, daemon, async {
        let _ = stop_rx.await;
    }));
    Fixture {
        path,
        hub,
        provider,
        intent_calls,
        _stop: stop_tx,
    }
}

#[tokio::test]
async fn hello_required_and_version_checked() {
    let f = start().await;
    let (rd, wr) = UnixStream::connect(&f.path).await.unwrap().into_split();
    let mut c = Client {
        rd: LineReader::new(rd),
        wr,
    };
    c.send(ClientMsg::Sub {
        id: "1".into(),
        doc: "svc.audio".into(),
    })
    .await;
    assert!(matches!(c.recv().await, ServerMsg::Err { kind, .. } if kind == "invalid"));
    c.send(ClientMsg::Hello {
        v: 99,
        client: "old".into(),
        caps: vec![],
    })
    .await;
    assert!(matches!(c.recv().await, ServerMsg::Goodbye { supported, .. } if supported == vec![1]));
}

#[tokio::test]
async fn snapshot_then_patches_with_consecutive_revs() {
    let f = start().await;
    let mut c = Client::connect(&f.path).await;
    let (rev, mut data) = c.sub("svc.audio").await;
    f.hub
        .update("svc.audio", None, |d| d["volume"] = json!(0.7))
        .unwrap();
    f.hub
        .update("svc.audio", None, |d| d["volume"] = json!(0.8))
        .unwrap();
    for expect in [rev + 1, rev + 2] {
        match c.recv().await {
            ServerMsg::Patch { rev, ops, .. } => {
                assert_eq!(rev, expect);
                merge_patch(&mut data, &ops);
            }
            other => panic!("{other:?}"),
        }
    }
    assert_eq!(data, f.hub.snapshot("svc.audio").unwrap().1);
    // Unchanged data produces no patch (Ma).
    f.hub
        .update("svc.audio", None, |d| d["volume"] = json!(0.8))
        .unwrap();
    assert!(c.quiet(100).await);
}

#[tokio::test]
async fn unsubscribed_docs_stay_silent_and_resync_returns_current() {
    let f = start().await;
    let mut c = Client::connect(&f.path).await;
    f.hub
        .update("svc.audio", None, |d| d["muted"] = json!(true))
        .unwrap();
    assert!(c.quiet(100).await, "no patch without subscription");
    c.send(ClientMsg::Resync {
        doc: "svc.audio".into(),
    })
    .await;
    match c.recv().await {
        ServerMsg::Snap { data, .. } => assert_eq!(data["muted"], json!(true)),
        other => panic!("{other:?}"),
    }
}

#[tokio::test]
async fn provider_refcount_starts_and_stops() {
    let f = start().await;
    let mut a = Client::connect(&f.path).await;
    let mut b = Client::connect(&f.path).await;
    a.sub("svc.counted").await;
    b.sub("svc.counted").await;
    b.sub("svc.counted").await; // re-subscribe must not double count
    assert_eq!(f.provider.starts.load(Ordering::SeqCst), 1);
    assert_eq!(f.hub.subscribers("svc.counted"), 2);
    a.send(ClientMsg::Unsub {
        doc: "svc.counted".into(),
    })
    .await;
    drop(b); // disconnect releases its subscription
    for _ in 0..50 {
        if f.provider.stops.load(Ordering::SeqCst) == 1 {
            break;
        }
        tokio::time::sleep(Duration::from_millis(10)).await;
    }
    assert_eq!(f.provider.stops.load(Ordering::SeqCst), 1);
    assert_eq!(f.hub.subscribers("svc.counted"), 0);
}

#[tokio::test]
async fn coalesced_intents_flush_once_per_frame_with_origin() {
    let f = start().await;
    let mut c = Client::connect(&f.path).await;
    let (rev, _) = c.sub("svc.audio").await;
    for i in 0..10 {
        c.send(ClientMsg::Intent {
            key: "audio.volume".into(),
            value: json!(i as f64 / 10.0),
            origin: Some("fe:slider".into()),
            coalesce: true,
        })
        .await;
    }
    match c.recv().await {
        ServerMsg::Patch {
            rev: r,
            ops,
            origin,
            ..
        } => {
            assert_eq!(r, rev + 1);
            assert_eq!(ops["volume"], json!(0.9));
            assert_eq!(origin.as_deref(), Some("fe:slider"));
        }
        other => panic!("{other:?}"),
    }
    assert!(c.quiet(60).await);
    assert!(f.intent_calls.load(Ordering::SeqCst) <= 2, "coalesced");
}

#[tokio::test]
async fn actions_return_done_or_typed_error() {
    let f = start().await;
    let mut c = Client::connect(&f.path).await;
    c.send(ClientMsg::Act {
        id: "a1".into(),
        action: "audio.mute.toggle".into(),
        args: Value::Null,
    })
    .await;
    assert!(
        matches!(c.recv().await, ServerMsg::Done { id, data: Some(d) } if id == "a1" && d["ok"] == json!(true))
    );
    c.send(ClientMsg::Act {
        id: "a2".into(),
        action: "nope".into(),
        args: Value::Null,
    })
    .await;
    assert!(
        matches!(c.recv().await, ServerMsg::Err { id: Some(id), kind, .. } if id == "a2" && kind == "unknown_action")
    );
    assert_eq!(f.hub.snapshot("svc.audio").unwrap().1["muted"], json!(true));
}

#[tokio::test]
async fn pushed_snapshot_has_no_id() {
    let f = start().await;
    let mut c = Client::connect(&f.path).await;
    let (rev, _) = c.sub("svc.audio").await;
    f.hub
        .push_snapshot("svc.audio", json!({"volume": 0.1, "muted": false}))
        .unwrap();
    match c.recv().await {
        ServerMsg::Snap {
            id, rev: r, data, ..
        } => {
            assert!(id.is_none());
            assert_eq!(r, rev + 1);
            assert_eq!(data["volume"], json!(0.1));
        }
        other => panic!("{other:?}"),
    }
}

#[tokio::test]
async fn queries_route_by_kind() {
    let f = start().await;
    let mut c = Client::connect(&f.path).await;
    c.send(ClientMsg::Query {
        id: "q1".into(),
        kind: "echo".into(),
        q: "fire".into(),
    })
    .await;
    assert!(
        matches!(c.recv().await, ServerMsg::Results { id, items } if id == "q1" && items[0]["id"] == "fire")
    );
    c.send(ClientMsg::Query {
        id: "q2".into(),
        kind: "nope".into(),
        q: String::new(),
    })
    .await;
    assert!(matches!(c.recv().await, ServerMsg::Err { kind, .. } if kind == "invalid"));
}
