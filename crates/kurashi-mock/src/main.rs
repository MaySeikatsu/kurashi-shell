//! kurashi-mock — a fake daemon serving the probe subset (docs/PROTOCOL.md §8) and the parity set
//! frontend work relies on: `runtime.ui` panels, `bindings` + `input.dispatch`, `svc.brightness`
//! with `brightness.up/down`, the session actions, `svc.notifications` with the notify commands
//! (plus `mock.notify` to add one), and the launcher `query`. Documents and actions live in
//! `state.rs`.
//!
//! Ma: it only emits patches when something changes (user intents and actions), so idle benches
//! stay idle. The clock (minute boundaries) and the mock.* controls emit whenever they fire; under
//! `--fixed-time` the clock never fires on its own.

mod documents;
mod state;

use std::collections::HashSet;
use std::sync::Arc;

use anyhow::Context;
use chrono::NaiveTime;
use clap::Parser;
use kurashi_ipc::{ClientMsg, LineReader, PROTOCOL_VERSION, ServerMsg, write_msg};
use tokio::net::{UnixListener, UnixStream};
use tokio::sync::{Mutex, mpsc};

use state::State;

#[derive(Parser, Debug)]
#[command(about = "Fake kurashid for frontend development and benchmarks")]
struct Args {
    /// Socket path (default: $KURASHI_SOCKET or $XDG_RUNTIME_DIR/kurashi/ipc.sock)
    #[arg(long)]
    socket: Option<std::path::PathBuf>,
    /// Comma-separated output names that get their own workspace lists
    #[arg(long, default_value = "HEADLESS-1,HEADLESS-2")]
    outputs: String,
    /// Report this local time (HH:MM, 24 h) on 2026-10-09 and never tick: deterministic
    /// screenshots for golden tests
    #[arg(long, value_parser = parse_hhmm)]
    fixed_time: Option<NaiveTime>,
}

/// `--fixed-time`: strictly `HH:MM` in 24-hour form.
fn parse_hhmm(s: &str) -> Result<NaiveTime, String> {
    NaiveTime::parse_from_str(s, "%H:%M").map_err(|e| format!("expected HH:MM (24 h): {e}"))
}

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    tracing_subscriber::fmt()
        .with_env_filter(
            tracing_subscriber::EnvFilter::try_from_default_env().unwrap_or_else(|_| "info".into()),
        )
        .with_writer(std::io::stderr)
        .init();
    let args = Args::parse();
    let path = args
        .socket
        .unwrap_or_else(kurashi_core::default_socket_path);
    if let Some(dir) = path.parent() {
        std::fs::create_dir_all(dir).with_context(|| format!("create {}", dir.display()))?;
    }
    let _ = std::fs::remove_file(&path);
    let listener = UnixListener::bind(&path).with_context(|| format!("bind {}", path.display()))?;
    tracing::info!(socket = %path.display(), "kurashi-mock listening");

    let outputs: Vec<String> = args
        .outputs
        .split(',')
        .filter(|s| !s.is_empty())
        .map(String::from)
        .collect();
    let state = Arc::new(Mutex::new(State::new(&outputs, args.fixed_time)));

    // Clock: wake exactly at the next minute boundary, never more often. Not started under
    // --fixed-time, where the clock only moves on an explicit mock.tick.
    if state.lock().await.clock_ticks() {
        let state = state.clone();
        tokio::spawn(async move {
            loop {
                let secs = 60 - chrono::Local::now().timestamp() % 60;
                tokio::time::sleep(std::time::Duration::from_secs(secs as u64)).await;
                state.lock().await.mock_tick();
            }
        });
    }

    loop {
        let (stream, _) = listener.accept().await?;
        let state = state.clone();
        tokio::spawn(async move {
            if let Err(e) = serve(stream, state).await {
                tracing::debug!(error = %e, "client closed");
            }
        });
    }
}

async fn serve(stream: UnixStream, state: Arc<Mutex<State>>) -> anyhow::Result<()> {
    let (rd, mut wr) = stream.into_split();
    let mut reader = LineReader::new(rd);
    let (out_tx, mut out_rx) = mpsc::unbounded_channel::<ServerMsg>();
    let mut patches = state.lock().await.tx.subscribe();
    let subscribed: Arc<Mutex<HashSet<String>>> = Default::default();

    // Writer: direct replies + patches for subscribed documents.
    let subs = subscribed.clone();
    let writer = tokio::spawn(async move {
        loop {
            // biased: replies (snapshots) before broadcast patches, so a client never sees
            // a patch for a document before the snapshot it applies to.
            let msg = tokio::select! {
                biased;
                m = out_rx.recv() => match m { Some(m) => m, None => break },
                p = patches.recv() => match p {
                    Ok(ServerMsg::Patch { ref doc, .. }) if !subs.lock().await.contains(doc) => continue,
                    Ok(m) => m,
                    Err(tokio::sync::broadcast::error::RecvError::Lagged(_)) => continue,
                    Err(_) => break,
                },
            };
            if write_msg(&mut wr, &msg).await.is_err() {
                break;
            }
        }
    });

    while let Some(msg) = reader.next_value::<ClientMsg>().await? {
        let reply = |m: ServerMsg| {
            let _ = out_tx.send(m);
        };
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
                reply(ServerMsg::Welcome {
                    v: PROTOCOL_VERSION,
                    server: format!("kurashi-mock {}", env!("CARGO_PKG_VERSION")),
                    caps: vec!["island".into(), "mock".into()],
                    instance: state.lock().await.instance.clone(),
                });
            }
            ClientMsg::Sub { id, doc } => snapshot(&state, &subscribed, &reply, id, doc).await,
            ClientMsg::Resync { doc } => {
                snapshot(&state, &subscribed, &reply, format!("resync:{doc}"), doc).await
            }
            ClientMsg::Unsub { doc } => {
                subscribed.lock().await.remove(&doc);
            }
            ClientMsg::Intent {
                key, value, origin, ..
            } => {
                if let Err(f) = state.lock().await.intent(&key, &value, origin) {
                    reply(ServerMsg::Err {
                        id: None,
                        kind: f.kind.into(),
                        msg: f.msg,
                    });
                }
            }
            ClientMsg::Act { id, action, args } => {
                let res = state.lock().await.act(&action, &args);
                reply(match res {
                    Ok(data) => ServerMsg::Done { id, data },
                    Err(f) => {
                        if f.kind == "unknown_action" {
                            tracing::warn!(kind = f.kind, %action, "not served by kurashi-mock");
                        }
                        ServerMsg::Err {
                            id: Some(id),
                            kind: f.kind.into(),
                            msg: f.msg,
                        }
                    }
                });
            }
            ClientMsg::MockTick => state.lock().await.mock_tick(),
            ClientMsg::MockFace { face } => state.lock().await.mock_face(&face),
            ClientMsg::MockWorkspace { idx } => state.lock().await.mock_workspace(idx),
            ClientMsg::Ping => reply(ServerMsg::Pong),
            ClientMsg::Query { id, kind, q } => {
                let res = state.lock().await.query(&kind, &q);
                reply(match res {
                    Ok(items) => ServerMsg::Results { id, items },
                    Err(f) => ServerMsg::Err {
                        id: Some(id),
                        kind: f.kind.into(),
                        msg: f.msg,
                    },
                });
            }
            ClientMsg::CfgGet { id, .. }
            | ClientMsg::CfgExplain { id, .. }
            | ClientMsg::Apply { id, .. }
            | ClientMsg::Undo { id }
            | ClientMsg::Redo { id } => reply(ServerMsg::Err {
                id: Some(id),
                kind: "unavailable".into(),
                msg: "not part of the probe subset".into(),
            }),
        }
    }
    drop(out_tx);
    let _ = writer.await;
    Ok(())
}

async fn snapshot(
    state: &Arc<Mutex<State>>,
    subscribed: &Arc<Mutex<HashSet<String>>>,
    reply: &impl Fn(ServerMsg),
    id: String,
    doc: String,
) {
    let st = state.lock().await;
    match st.docs.get(&doc) {
        Some(d) => {
            subscribed.lock().await.insert(doc.clone());
            reply(ServerMsg::Snap {
                id: Some(id),
                doc,
                rev: d.rev,
                data: d.data.clone(),
            });
        }
        None => {
            tracing::warn!(kind = "unknown_doc", %doc, "not served by kurashi-mock");
            reply(ServerMsg::Err {
                id: Some(id),
                kind: "unknown_doc".into(),
                msg: format!("no document {doc}"),
            });
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn fixed_time_is_24_hour_hh_mm_and_nothing_else() {
        let t = |h, m| NaiveTime::from_hms_opt(h, m, 0).expect("time");
        assert_eq!(parse_hhmm("14:07"), Ok(t(14, 7)));
        assert_eq!(parse_hhmm("00:00"), Ok(t(0, 0)));
        assert_eq!(parse_hhmm("23:59"), Ok(t(23, 59)));
        assert!(parse_hhmm("24:00").is_err());
        assert!(parse_hhmm("14:60").is_err());
        assert!(parse_hhmm("2pm").is_err());
        assert!(parse_hhmm("14:07:30").is_err());
    }
}
