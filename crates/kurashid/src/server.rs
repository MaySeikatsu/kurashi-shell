//! Per-connection protocol handling (PROTOCOL §2–§7).

use std::collections::HashSet;
use std::sync::{Arc, Mutex};

use kurashi_ipc::{ClientMsg, LineReader, PROTOCOL_VERSION, ServerMsg, write_msg};
use tokio::net::{UnixListener, UnixStream};
use tokio::sync::{broadcast, mpsc};

use crate::Daemon;

/// Accept clients until `shutdown` resolves, then tell connected clients `bye`.
pub async fn serve(
    listener: UnixListener,
    daemon: Arc<Daemon>,
    shutdown: impl Future<Output = ()>,
) {
    let (bye_tx, _) = broadcast::channel::<()>(1);
    tokio::pin!(shutdown);
    loop {
        tokio::select! {
            accepted = listener.accept() => {
                let Ok((stream, _)) = accepted else { continue };
                let (daemon, bye) = (daemon.clone(), bye_tx.subscribe());
                tokio::spawn(async move {
                    if let Err(e) = connection(stream, daemon, bye).await {
                        tracing::debug!(error = %e, "client closed");
                    }
                });
            }
            _ = &mut shutdown => break,
        }
    }
    let _ = bye_tx.send(());
    // Give writers a moment to flush `bye` before the runtime goes away.
    tokio::time::sleep(std::time::Duration::from_millis(50)).await;
}

fn err(id: Option<String>, kind: &str, msg: impl Into<String>) -> ServerMsg {
    ServerMsg::Err {
        id,
        kind: kind.into(),
        msg: msg.into(),
    }
}

async fn connection(
    stream: UnixStream,
    daemon: Arc<Daemon>,
    mut bye: broadcast::Receiver<()>,
) -> anyhow::Result<()> {
    let (rd, mut wr) = stream.into_split();
    let mut reader = LineReader::new(rd);
    let (out_tx, mut out_rx) = mpsc::unbounded_channel::<ServerMsg>();
    let subscribed: Arc<Mutex<HashSet<String>>> = Default::default();
    // Subscribe to hub events before any snapshot is taken so no patch can slip between.
    let mut events = daemon.hub.events();

    let subs = subscribed.clone();
    let writer = tokio::spawn(async move {
        loop {
            // biased: direct replies (snapshots) go out before queued patches, so a client never
            // sees a patch for a document before the snapshot it applies to.
            let msg: Arc<ServerMsg> = tokio::select! {
                biased;
                m = out_rx.recv() => match m { Some(m) => Arc::new(m), None => break },
                _ = bye.recv() => Arc::new(ServerMsg::Bye { reason: "shutdown".into() }),
                e = events.recv() => match e {
                    Ok(m) => {
                        let doc = match &*m {
                            ServerMsg::Patch { doc, .. } | ServerMsg::Snap { doc, .. } => doc,
                            _ => continue,
                        };
                        if !subs.lock().expect("subs lock").contains(doc) { continue }
                        m
                    }
                    // Missed patches: the client sees a revision gap and resyncs (PROTOCOL §3).
                    Err(broadcast::error::RecvError::Lagged(_)) => continue,
                    Err(_) => break,
                },
            };
            let is_bye = matches!(&*msg, ServerMsg::Bye { .. });
            if write_msg(&mut wr, &*msg).await.is_err() || is_bye {
                break;
            }
        }
    });

    let reply = |m: ServerMsg| {
        let _ = out_tx.send(m);
    };
    let mut greeted = false;
    let result = async {
        while let Some(msg) = reader.next_value::<ClientMsg>().await? {
            if !greeted && !matches!(msg, ClientMsg::Hello { .. } | ClientMsg::Ping) {
                reply(err(None, "invalid", "hello first"));
                continue;
            }
            match msg {
                ClientMsg::Hello { v, client, .. } => {
                    if v != PROTOCOL_VERSION {
                        reply(ServerMsg::Goodbye {
                            reason: "version".into(),
                            supported: vec![PROTOCOL_VERSION],
                        });
                        break;
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
                    let (daemon, out) = (daemon.clone(), out_tx.clone());
                    tokio::spawn(async move {
                        let m = match daemon.actions.invoke(&action, args).await {
                            Ok(data) => ServerMsg::Done { id, data },
                            Err(e) => err(Some(id), e.kind(), e.to_string()),
                        };
                        let _ = out.send(m);
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
                        let out = out_tx.clone();
                        tokio::task::spawn_blocking(move || {
                            let _ = out.send(ServerMsg::Results { id, items: f(&q) });
                        });
                    }
                    None => reply(err(
                        Some(id),
                        "invalid",
                        format!("no query provider {kind}"),
                    )),
                },
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
    }
    .await;

    // Disconnect releases every subscription so providers can stop (Ma).
    for doc in subscribed.lock().expect("subs lock").drain() {
        daemon.hub.unsubscribe(&doc);
    }
    drop(out_tx);
    let _ = writer.await;
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
