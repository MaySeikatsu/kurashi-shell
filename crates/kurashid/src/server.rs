//! Per-connection protocol handling (PROTOCOL §2–§7).

use std::collections::{HashMap, HashSet, VecDeque};
use std::sync::{Arc, Mutex};
use std::time::Duration;

use kurashi_core::Rev;
use kurashi_ipc::{ClientMsg, LineReader, PROTOCOL_VERSION, ServerMsg, write_msg};
use tokio::net::{UnixListener, UnixStream};
use tokio::sync::{broadcast, mpsc, watch};

use crate::Daemon;
use crate::native::hosts::{ScopeHold, ScopeRefused, connect_scope};
use crate::native::served;

/// Replies queued per connection before the client is dropped (review finding 11). The hub's own
/// patches go through its broadcast ring, so this bounds what one client's requests can pile up.
const REPLY_QUEUE: usize = 1024;
/// How long a finished connection's writer may keep flushing before its socket is abandoned.
const FLUSH_GRACE: Duration = Duration::from_secs(1);
/// Pause after a failed accept (EMFILE and friends) so a persistent failure can't spin the loop
/// at full CPU (review finding 4).
const ACCEPT_BACKOFF: Duration = Duration::from_millis(100);

/// Where client connections come from: the listener in production, a scripted fake in tests.
pub trait Acceptor: Send {
    fn accept(&mut self) -> impl Future<Output = std::io::Result<UnixStream>> + Send;
}

impl Acceptor for UnixListener {
    async fn accept(&mut self) -> std::io::Result<UnixStream> {
        UnixListener::accept(self).await.map(|(stream, _)| stream)
    }
}

/// Accept clients until `shutdown` resolves, then tell connected clients `bye`.
pub async fn serve(
    mut acceptor: impl Acceptor,
    daemon: Arc<Daemon>,
    shutdown: impl Future<Output = ()>,
) {
    let (bye_tx, _) = broadcast::channel::<()>(1);
    tokio::pin!(shutdown);
    let mut failing = false;
    loop {
        tokio::select! {
            accepted = acceptor.accept() => match accepted {
                Ok(stream) => {
                    failing = false;
                    let (daemon, bye) = (daemon.clone(), bye_tx.subscribe());
                    tokio::spawn(async move {
                        if let Err(e) = connection(stream, daemon, bye).await {
                            tracing::debug!(error = %e, "client closed");
                        }
                    });
                }
                Err(e) => {
                    // One warning per burst of failures, not one per failed accept.
                    if !failing {
                        tracing::warn!(error = %e, "accept failed; backing off");
                        failing = true;
                    }
                    tokio::select! {
                        () = tokio::time::sleep(ACCEPT_BACKOFF) => {}
                        _ = &mut shutdown => break,
                    }
                }
            },
            _ = &mut shutdown => break,
        }
    }
    let _ = bye_tx.send(());
    // Give writers a moment to flush `bye` before the runtime goes away.
    tokio::time::sleep(Duration::from_millis(50)).await;
}

fn err(id: Option<String>, kind: &str, msg: impl Into<String>) -> ServerMsg {
    ServerMsg::Err {
        id,
        kind: kind.into(),
        msg: msg.into(),
    }
}

/// What a scoped connection of `mod_id` may send (PROTOCOL §2): `ping`, `sub` / `unsub` / `resync` of the documents and
/// `act` of the actions its mod's contract reaches (W91: its own, the base set, its `uses`). Everything else is `forbidden`.
fn scoped_allows(mod_id: &str, hold: &ScopeHold, msg: &ClientMsg) -> bool {
    match msg {
        ClientMsg::Ping => true,
        ClientMsg::Sub { doc, .. } | ClientMsg::Unsub { doc } | ClientMsg::Resync { doc } => {
            hold.allows_doc(mod_id, doc)
        }
        ClientMsg::Act { action, .. } => hold.allows_action(mod_id, action),
        // K155 (W93): a host program's own messages; what each may name is checked where it is handled.
        ClientMsg::Pub { .. }
        | ClientMsg::Serve { .. }
        | ClientMsg::Done { .. }
        | ClientMsg::Err { .. } => true,
        _ => false,
    }
}

/// Numbers the connections (K155, W93: a host's calls belong to the connection that took the action).
static NEXT_CONN: std::sync::atomic::AtomicU64 = std::sync::atomic::AtomicU64::new(1);

/// The `id` a request carries, so that its refusal reaches the right request.
fn request_id(msg: &ClientMsg) -> Option<String> {
    match msg {
        ClientMsg::Sub { id, .. }
        | ClientMsg::CfgGet { id, .. }
        | ClientMsg::CfgExplain { id, .. }
        | ClientMsg::Apply { id, .. }
        | ClientMsg::Undo { id }
        | ClientMsg::Redo { id }
        | ClientMsg::Act { id, .. }
        | ClientMsg::Serve { id, .. }
        | ClientMsg::Query { id, .. } => Some(id.clone()),
        ClientMsg::Pub { id, .. } => id.clone(),
        _ => None,
    }
}

/// The connection's reply queue. Sends never wait: a full queue flags the connection as overflowed
/// and the connection ends with a `bye` instead of growing memory (review finding 11).
#[derive(Clone)]
struct Outbox {
    tx: mpsc::Sender<ServerMsg>,
    overflow: Arc<watch::Sender<bool>>,
}

impl Outbox {
    fn push(&self, msg: ServerMsg) {
        if let Err(mpsc::error::TrySendError::Full(_)) = self.tx.try_send(msg) {
            self.overflow.send_replace(true);
        }
    }
}

/// Resolves once the reply queue has overflowed.
async fn overflowed(rx: &mut watch::Receiver<bool>) {
    // The sender outlives both tasks that use this, so `Err` can't happen; it must not read as an
    // overflow if it ever did.
    if rx.wait_for(|full| *full).await.is_err() {
        std::future::pending::<()>().await;
    }
}

async fn connection(
    stream: UnixStream,
    daemon: Arc<Daemon>,
    mut bye: broadcast::Receiver<()>,
) -> anyhow::Result<()> {
    let (rd, mut wr) = stream.into_split();
    let mut reader = LineReader::new(rd);
    let (queue_tx, mut queue_rx) = mpsc::channel::<ServerMsg>(REPLY_QUEUE);
    let overflow_tx = Arc::new(watch::channel(false).0);
    let mut overflow = overflow_tx.subscribe();
    let out = Outbox {
        tx: queue_tx,
        overflow: overflow_tx.clone(),
    };
    let subscribed: Arc<Mutex<HashSet<String>>> = Default::default();
    // Subscribe to hub events before any snapshot is taken so no patch can slip between.
    let mut events = daemon.hub.events();

    let subs = subscribed.clone();
    let hub = daemon.hub.clone();
    let mut writer = tokio::spawn(async move {
        // Subscribed to the same sender that `out` feeds, and holds it open while writing.
        let mut overflow_rx = overflow_tx.subscribe();
        // Highest revision written per document. Patches at or below it are already reflected in
        // what the client holds, so they are dropped (review finding 6).
        let mut written: HashMap<String, Rev> = HashMap::new();
        // Snapshots queued after the hub's ring dropped messages; they go out before anything else.
        let mut resync: VecDeque<Arc<ServerMsg>> = VecDeque::new();
        loop {
            let msg: Arc<ServerMsg> = match resync.pop_front() {
                Some(m) => m,
                None => tokio::select! {
                    // Overflow first: whatever is still queued is stale, so only the bye goes out.
                    biased;
                    () = overflowed(&mut overflow_rx) => {
                        Arc::new(ServerMsg::Bye { reason: "overflow".into() })
                    }
                    // biased: direct replies (snapshots) go out before queued patches, so a client
                    // never sees a patch for a document before the snapshot it applies to.
                    m = queue_rx.recv() => match m {
                        Some(m) => Arc::new(m),
                        None => break,
                    },
                    _ = bye.recv() => Arc::new(ServerMsg::Bye { reason: "shutdown".into() }),
                    e = events.recv() => match e {
                        Ok(m) => {
                            let (doc, rev) = match &*m {
                                ServerMsg::Patch { doc, rev, .. }
                                | ServerMsg::Snap { doc, rev, .. } => (doc, *rev),
                                _ => continue,
                            };
                            let is_sub = subs.lock().expect("subs lock").contains(doc);
                            if !is_sub || written.get(doc).is_some_and(|&w| rev <= w) {
                                continue;
                            }
                            m
                        }
                        // The ring dropped messages, possibly a document's last patch, and no
                        // later patch would reveal the gap. Re-send every subscribed document in
                        // full; clients adopt the revision they carry.
                        Err(broadcast::error::RecvError::Lagged(_)) => {
                            let docs: Vec<String> =
                                subs.lock().expect("subs lock").iter().cloned().collect();
                            for doc in docs {
                                if let Ok((rev, data)) = hub.snapshot(&doc) {
                                    resync.push_back(Arc::new(ServerMsg::Snap {
                                        id: None,
                                        doc,
                                        rev,
                                        data,
                                    }));
                                }
                            }
                            continue;
                        }
                        Err(_) => break,
                    },
                },
            };
            let is_bye = matches!(&*msg, ServerMsg::Bye { .. });
            if write_msg(&mut wr, &*msg).await.is_err() || is_bye {
                break;
            }
            if let ServerMsg::Patch { doc, rev, .. } | ServerMsg::Snap { doc, rev, .. } = &*msg {
                let w = written.entry(doc.clone()).or_insert(0);
                *w = (*w).max(*rev);
            }
        }
    });

    // This connection among a mod's hosts (K155, W93: the one that serves, and the one that closed), and the mod it
    // speaks for once its scoped hello was taken.
    let conn_id = NEXT_CONN.fetch_add(1, std::sync::atomic::Ordering::Relaxed);
    let scoped_mod: std::sync::Mutex<Option<String>> = std::sync::Mutex::new(None);
    let session = async {
        let reply = |m: ServerMsg| out.push(m);
        let mut greeted = false;
        // A host process's connection (K38, PROTOCOL §2): the mod it speaks for, and the hold on its token.
        let mut host_scope: Option<(String, ScopeHold)> = None;
        while let Some(msg) = reader.next_value::<ClientMsg>().await? {
            if !greeted && !matches!(msg, ClientMsg::Hello { .. } | ClientMsg::Ping) {
                reply(err(None, "invalid", "hello first"));
                continue;
            }
            if let Some((mod_id, hold)) = &host_scope
                && !scoped_allows(mod_id, hold, &msg)
            {
                reply(err(
                    request_id(&msg),
                    "forbidden",
                    "outside the host's scope",
                ));
                continue;
            }
            match msg {
                ClientMsg::Hello {
                    v, client, scope, ..
                } => {
                    if v != PROTOCOL_VERSION {
                        reply(ServerMsg::Goodbye {
                            reason: "version".into(),
                            supported: vec![PROTOCOL_VERSION],
                        });
                        break;
                    }
                    if let Some(scope) = scope {
                        // Only the first hello of a connection can scope it.
                        if greeted {
                            reply(err(None, "forbidden", "a scope comes with the first hello"));
                            continue;
                        }
                        match connect_scope(&scope) {
                            Ok(hold) => {
                                *scoped_mod.lock().expect("scope lock") =
                                    Some(scope.mod_id.clone());
                                host_scope = Some((scope.mod_id, hold));
                            }
                            Err(ScopeRefused) => {
                                reply(ServerMsg::Goodbye {
                                    reason: "scope".into(),
                                    supported: vec![PROTOCOL_VERSION],
                                });
                                break;
                            }
                        }
                    }
                    tracing::info!(%client, "hello");
                    greeted = true;
                    reply(ServerMsg::Welcome {
                        v: PROTOCOL_VERSION,
                        server: format!("kurashid {}", env!("CARGO_PKG_VERSION")),
                        caps: daemon.caps.clone(),
                        instance: daemon.instance.clone(),
                    });
                }
                ClientMsg::Sub { id, doc } => {
                    let fresh = subscribed.lock().expect("subs lock").insert(doc.clone());
                    // Re-subscribing doesn't count twice toward the provider refcount.
                    let snap = if fresh {
                        daemon.hub.subscribe(&doc)
                    } else {
                        daemon.hub.snapshot(&doc)
                    };
                    match snap {
                        Ok((rev, data)) => reply(ServerMsg::Snap {
                            id: Some(id),
                            doc,
                            rev,
                            data,
                        }),
                        Err(e) => {
                            subscribed.lock().expect("subs lock").remove(&doc);
                            reply(err(Some(id), "unknown_doc", e.to_string()));
                        }
                    }
                }
                ClientMsg::Resync { doc } => match daemon.hub.snapshot(&doc) {
                    Ok((rev, data)) => reply(ServerMsg::Snap {
                        id: Some(format!("resync:{doc}")),
                        doc,
                        rev,
                        data,
                    }),
                    Err(e) => reply(err(None, "unknown_doc", e.to_string())),
                },
                ClientMsg::Unsub { doc } => {
                    if subscribed.lock().expect("subs lock").remove(&doc) {
                        daemon.hub.unsubscribe(&doc);
                    }
                }
                ClientMsg::Intent {
                    key,
                    value,
                    origin,
                    coalesce,
                } => {
                    if let Err(e) = daemon.intents.submit(&key, value, origin, coalesce) {
                        reply(err(None, "invalid", e.to_string()));
                    }
                }
                ClientMsg::Act { id, action, args } => {
                    // Actions may be slow (D-Bus, compositor); never block the read loop.
                    let (daemon, out) = (daemon.clone(), out.clone());
                    tokio::spawn(async move {
                        let m = match daemon.actions.invoke(&action, args).await {
                            Ok(data) => ServerMsg::Done { id, data },
                            Err(e) => err(Some(id), e.kind(), e.to_string()),
                        };
                        out.push(m);
                    });
                }
                ClientMsg::CfgGet { id, key, output } => match &daemon.config {
                    Some(c) => match c.get(&key, output.as_deref()) {
                        Some(v) => reply(ServerMsg::CfgVal { id, key, v }),
                        None => reply(err(Some(id), "invalid", format!("unknown key {key}"))),
                    },
                    None => reply(err(Some(id), "unavailable", "no config store")),
                },
                ClientMsg::CfgExplain { id, key, output } => match &daemon.config {
                    Some(c) => {
                        let layers = c.explain(&key, output.as_deref());
                        reply(ServerMsg::CfgWhy {
                            id,
                            key,
                            output,
                            layers,
                        });
                    }
                    None => reply(err(Some(id), "unavailable", "no config store")),
                },
                ClientMsg::Apply { id, ops, dry_run } => match &daemon.config {
                    Some(c) if dry_run => match c.preview(&ops) {
                        Ok(diff) => reply(ServerMsg::Preview { id, diff }),
                        Err(errors) => reply(ServerMsg::Rejected { id, errors }),
                    },
                    Some(c) => match c.apply(&ops) {
                        Ok(done) => reply(ServerMsg::Applied {
                            id,
                            rev: done.rev,
                            undo: done.undo,
                        }),
                        Err(errors) => reply(ServerMsg::Rejected { id, errors }),
                    },
                    None => reply(err(Some(id), "unavailable", "no config store")),
                },
                ClientMsg::Undo { id } => step(&daemon, id, false, &reply),
                ClientMsg::Redo { id } => step(&daemon, id, true, &reply),
                ClientMsg::Query { id, kind, q } => match daemon.queries.get(&kind).cloned() {
                    // Off the read loop: providers are fast but may touch the filesystem.
                    Some(f) => {
                        let out = out.clone();
                        tokio::task::spawn_blocking(move || {
                            out.push(ServerMsg::Results { id, items: f(&q) });
                        });
                    }
                    None => reply(err(
                        Some(id),
                        "invalid",
                        format!("no query provider {kind}"),
                    )),
                },
                // K155 (W93; PROTOCOL §2 "Host programs"): a mod's own program publishes the mod's documents and takes
                // its actions. Only a scoped connection speaks for a mod.
                ClientMsg::Pub { id, doc, data } => {
                    let Some((mod_id, _)) = &host_scope else {
                        reply(err(id, "forbidden", "only a mod's host program publishes"));
                        continue;
                    };
                    let served = served::of(mod_id);
                    let refused = if !served.may_pub(&doc) {
                        tracing::warn!(%mod_id, %doc, "a host published a document its manifest does not provide");
                        Some(("forbidden", "not a document this mod provides".to_string()))
                    } else if !data.is_object() {
                        Some(("invalid", "a document is an object".to_string()))
                    } else if data.to_string().len() > served::PUB_MAX {
                        Some(("invalid", served::TOO_LARGE.to_string()))
                    } else {
                        None
                    };
                    match refused {
                        Some((kind, msg)) => reply(err(id, kind, msg)),
                        None => {
                            let set = daemon.hub.set(&doc, data, None);
                            if let Some(id) = id {
                                match set {
                                    Ok(()) => reply(ServerMsg::Done { id, data: None }),
                                    Err(e) => reply(err(Some(id), "unknown_doc", e.to_string())),
                                }
                            }
                        }
                    }
                }
                ClientMsg::Serve { id, actions } => {
                    let Some((mod_id, _)) = &host_scope else {
                        reply(err(
                            Some(id),
                            "forbidden",
                            "only a mod's host program serves actions",
                        ));
                        continue;
                    };
                    let out = out.clone();
                    let push: Arc<dyn Fn(ServerMsg) + Send + Sync> = Arc::new(move |m| out.push(m));
                    match served::of(mod_id).serve(conn_id, push, actions) {
                        Ok(()) => reply(ServerMsg::Done { id, data: None }),
                        Err(action) => {
                            tracing::warn!(%mod_id, %action, "a host asked for an action its manifest does not declare");
                            reply(err(
                                Some(id),
                                "forbidden",
                                format!("{action} is not an action this mod provides"),
                            ));
                        }
                    }
                }
                ClientMsg::Done { id, data } => {
                    if let Some((mod_id, _)) = &host_scope {
                        served::of(mod_id).answer(conn_id, &id, Ok(data));
                    }
                }
                ClientMsg::Err { id, kind, msg } => {
                    if let Some((mod_id, _)) = &host_scope {
                        use kurashi_mod_api::ActionError as E;
                        let e = match kind.as_str() {
                            "invalid" => E::Invalid(msg),
                            "unavailable" => E::Unavailable(msg),
                            _ => E::Internal(msg),
                        };
                        served::of(mod_id).answer(conn_id, &id, Err(e));
                    }
                }
                ClientMsg::Ping => reply(ServerMsg::Pong),
                ClientMsg::MockTick
                | ClientMsg::MockFace { .. }
                | ClientMsg::MockWorkspace { .. } => {
                    reply(err(
                        None,
                        "invalid",
                        "mock control messages go to kurashi-mock",
                    ));
                }
            }
        }
        anyhow::Ok(())
    };

    // The read loop ends at EOF, on a protocol error, or when the reply queue overflows (the writer
    // then sends `bye`); the rest of the connection is torn down either way.
    let result = tokio::select! {
        r = session => r,
        () = overflowed(&mut overflow) => {
            tracing::warn!("reply queue overflowed; dropping the client");
            Ok(())
        }
    };

    // K155 (W93): a host program is gone, however its connection ended — its calls fail, and its documents say so
    // instead of showing what it last published.
    if let Some(mod_id) = scoped_mod.lock().expect("scope lock").take() {
        let served = served::of(&mod_id);
        served.closed(conn_id);
        for doc in served.docs() {
            let _ = daemon.hub.set(
                &doc,
                serde_json::json!({ "available": false, "reason": served::STARTING }),
                None,
            );
        }
    }
    // Disconnect releases every subscription so providers can stop (Ma).
    for doc in subscribed.lock().expect("subs lock").drain() {
        daemon.hub.unsubscribe(&doc);
    }
    drop(out);
    // A client that stopped reading can leave the writer blocked on its socket: allow a short flush
    // (the queued replies or the `bye`), then abandon it.
    if tokio::time::timeout(FLUSH_GRACE, &mut writer)
        .await
        .is_err()
    {
        writer.abort();
    }
    result
}

fn step(daemon: &Daemon, id: String, redo: bool, reply: &impl Fn(ServerMsg)) {
    let Some(c) = &daemon.config else {
        reply(err(Some(id), "unavailable", "no config store"));
        return;
    };
    match c.undo(redo) {
        Ok(done) => reply(ServerMsg::Applied {
            id,
            rev: done.rev,
            undo: done.undo,
        }),
        Err(errors) => reply(ServerMsg::Rejected { id, errors }),
    }
}
