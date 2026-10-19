//! Connection-level resilience over a real unix socket (PROTOCOL §3, §7): a client that falls behind
//! the event stream is resynced with full snapshots (review finding 6), and a client that overflows
//! its reply queue is dropped with a `bye` instead of growing the daemon's memory (finding 11).

use std::collections::HashMap;
use std::path::{Path, PathBuf};
use std::sync::Arc;
use std::sync::atomic::{AtomicUsize, Ordering};
use std::time::Duration;

use kurashi_ipc::{ClientMsg, LineReader, ServerMsg, encode, merge_patch, write_msg};
use kurashid::server::Acceptor;
use kurashid::{ActionRegistry, Daemon, Hub, Intents};
use serde_json::{Value, json};
use tokio::io::AsyncWriteExt;
use tokio::net::UnixStream;
use tokio::net::unix::{OwnedReadHalf, OwnedWriteHalf};
use tokio::sync::oneshot;

struct Client {
    rd: LineReader<OwnedReadHalf>,
    wr: OwnedWriteHalf,
}

impl Client {
    async fn connect(path: &Path) -> Client {
        let (rd, wr) = UnixStream::connect(path).await.unwrap().into_split();
        let mut c = Client {
            rd: LineReader::new(rd),
            wr,
        };
        c.send(ClientMsg::Hello {
            v: 1,
            client: "test".into(),
            caps: vec![],
            scope: None,
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
}

/// Folds a snapshot or patch into the client's view of each document, as PROTOCOL §3 describes.
fn apply(docs: &mut HashMap<String, (u64, Value)>, msg: ServerMsg) {
    match msg {
        ServerMsg::Snap { doc, rev, data, .. } => {
            docs.insert(doc, (rev, data));
        }
        ServerMsg::Patch { doc, rev, ops, .. } => {
            let (have, data) = docs.get_mut(&doc).expect("patch for an unsubscribed doc");
            merge_patch(data, &ops);
            *have = rev;
        }
        other => panic!("unexpected {other:?}"),
    }
}

static N: AtomicUsize = AtomicUsize::new(0);

/// Serves `hub` on a fresh socket. The returned sender keeps the server alive; dropping it stops it.
async fn spawn_server(hub: Arc<Hub>) -> (PathBuf, oneshot::Sender<()>) {
    let path = std::env::temp_dir().join(format!(
        "kurashid-resilience-{}-{}.sock",
        std::process::id(),
        N.fetch_add(1, Ordering::SeqCst)
    ));
    let _ = std::fs::remove_file(&path);
    let listener = tokio::net::UnixListener::bind(&path).unwrap();
    let daemon = Arc::new(Daemon::new(
        hub,
        ActionRegistry::default(),
        Intents::default(),
    ));
    let (stop_tx, stop_rx) = oneshot::channel::<()>();
    tokio::spawn(kurashid::server::serve(listener, daemon, async {
        let _ = stop_rx.await;
    }));
    (path, stop_tx)
}

/// Runs on the default current_thread runtime on purpose: the flood below is synchronous, so the
/// connection task cannot drain its event receiver in the middle of it and the receiver lags
/// deterministically (the hub's broadcast ring holds 1024 messages).
#[tokio::test]
async fn lagged_client_gets_full_snapshots_for_every_subscription() {
    let hub = Hub::new();
    hub.register("svc.quiet", json!({"v": 1}), None);
    hub.register("svc.busy", json!({"i": -1}), None);
    let (path, _stop) = spawn_server(hub.clone()).await;
    let mut c = Client::connect(&path).await;
    let mut docs: HashMap<String, (u64, Value)> = HashMap::new();
    for (id, doc) in [("1", "svc.quiet"), ("2", "svc.busy")] {
        c.send(ClientMsg::Sub {
            id: id.into(),
            doc: doc.into(),
        })
        .await;
        apply(&mut docs, c.recv().await);
    }

    // The quiet document's only change is the one the lag would silently drop.
    hub.set("svc.quiet", json!({"v": 2}), None).unwrap();
    for i in 0..1100 {
        hub.set("svc.busy", json!({"i": i}), None).unwrap();
    }

    // Snapshots for the two documents may arrive in either order, so wait for both final revisions;
    // a stream that goes quiet ends the wait and the assertions say what is missing.
    loop {
        let settled = docs.get("svc.quiet").is_some_and(|(rev, _)| *rev == 2)
            && docs.get("svc.busy").is_some_and(|(rev, _)| *rev == 1101);
        if settled {
            break;
        }
        match tokio::time::timeout(Duration::from_secs(2), c.rd.next_value::<ServerMsg>()).await {
            Ok(msg) => apply(&mut docs, msg.expect("read").expect("server closed")),
            Err(_) => break,
        }
    }
    assert_eq!(
        docs["svc.quiet"],
        (2, json!({"v": 2})),
        "the quiet document's last patch was dropped by the lag and never resynced"
    );
    assert_eq!(docs["svc.busy"].0, 1101);
}

/// Same runtime reasoning as above: the connection task reads the whole burst in one turn, so its
/// reply queue overflows before the writer gets a turn, which is what a client that stops reading
/// produces.
#[tokio::test]
async fn client_that_overflows_its_reply_queue_is_dropped_with_bye() {
    let (path, _stop) = spawn_server(Hub::new()).await;
    let mut c = Client::connect(&path).await;

    let mut burst = Vec::new();
    for _ in 0..4 * 1024 {
        burst.extend_from_slice(encode(&ClientMsg::Ping).unwrap().as_bytes());
    }
    // The server may close the socket before the whole burst is read; the bye it wrote first is
    // still delivered, so a failed write is not what this test is about.
    let _ = c.wr.write_all(&burst).await;

    let mut pongs = 0usize;
    let bye = loop {
        match tokio::time::timeout(Duration::from_secs(2), c.rd.next_value::<ServerMsg>()).await {
            Ok(Ok(Some(ServerMsg::Pong))) => pongs += 1,
            Ok(Ok(Some(ServerMsg::Bye { reason }))) => break Some(reason),
            Ok(Ok(Some(other))) => panic!("unexpected {other:?}"),
            Ok(Ok(None) | Err(_)) => break None,
            Err(_) => panic!("connection stayed open after {pongs} pongs with no bye"),
        }
    };
    assert_eq!(
        bye.as_deref(),
        Some("overflow"),
        "pongs before the close: {pongs}"
    );
}

const EMFILE: i32 = 24;

/// A listener whose accept keeps failing, as it does once the process is out of file descriptors.
/// It starts succeeding (by pending forever) after 10 000 failures, so a spinning loop still hands
/// control back to the test's timer instead of hanging the test.
struct Exhausted {
    calls: Arc<AtomicUsize>,
}

impl Acceptor for Exhausted {
    fn accept(&mut self) -> impl Future<Output = std::io::Result<UnixStream>> + Send {
        let n = self.calls.fetch_add(1, Ordering::SeqCst);
        async move {
            if n < 10_000 {
                Err(std::io::Error::from_raw_os_error(EMFILE))
            } else {
                std::future::pending::<std::io::Result<UnixStream>>().await
            }
        }
    }
}

#[tokio::test]
async fn accept_failures_back_off_instead_of_spinning() {
    let calls = Arc::new(AtomicUsize::new(0));
    let daemon = Arc::new(Daemon::new(
        Hub::new(),
        ActionRegistry::default(),
        Intents::default(),
    ));
    let acceptor = Exhausted {
        calls: calls.clone(),
    };
    tokio::time::timeout(
        Duration::from_secs(5),
        kurashid::server::serve(
            acceptor,
            daemon,
            tokio::time::sleep(Duration::from_millis(350)),
        ),
    )
    .await
    .expect("serve did not return after shutdown");
    let attempts = calls.load(Ordering::SeqCst);
    assert!(
        attempts <= 10,
        "accept was retried {attempts} times in 350 ms: the loop is spinning"
    );
}
