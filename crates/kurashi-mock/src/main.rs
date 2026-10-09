//! kurashi-mock — a fake daemon that serves the probe subset (docs/PROTOCOL.md §8).
//!
//! Ma: it only emits patches when something changes (clock on minute boundaries,
//! user intents/actions, mock.* control messages) so idle benches stay idle.

use std::collections::HashMap;
use std::sync::Arc;

use anyhow::Context;
use clap::Parser;
use kurashi_core::Rev;
use kurashi_ipc::{ClientMsg, LineReader, PROTOCOL_VERSION, ServerMsg, merge_patch, write_msg};
use serde_json::{Value, json};
use tokio::net::{UnixListener, UnixStream};
use tokio::sync::{Mutex, broadcast, mpsc};

#[derive(Parser, Debug)]
#[command(about = "Fake kurashid for frontend development and benchmarks")]
struct Args {
    /// Socket path (default: $KURASHI_SOCKET or $XDG_RUNTIME_DIR/kurashi/ipc.sock)
    #[arg(long)]
    socket: Option<std::path::PathBuf>,
    /// Comma-separated output names that get their own workspace lists
    #[arg(long, default_value = "HEADLESS-1,HEADLESS-2")]
    outputs: String,
}

struct Doc {
    rev: Rev,
    data: Value,
}

struct State {
    docs: HashMap<String, Doc>,
    tx: broadcast::Sender<ServerMsg>,
}

impl State {
    /// Apply a merge-patch to a document and broadcast it with the next revision.
    fn patch(&mut self, doc: &str, ops: Value, origin: Option<String>) {
        let d = self.docs.get_mut(doc).expect("known doc");
        merge_patch(&mut d.data, &ops);
        d.rev += 1;
        let _ = self.tx.send(ServerMsg::Patch {
            doc: doc.into(),
            rev: d.rev,
            ops,
            origin,
        });
    }
}

fn clock_doc() -> Value {
    let now = chrono::Local::now();
    json!({
        "hh": now.format("%H").to_string(),
        "mm": now.format("%M").to_string(),
        "date": now.format("%Y-%m-%d").to_string(),
        "weekday": now.format("%a").to_string(),
    })
}

fn workspaces_doc(outputs: &[String], focused_idx: u32) -> Value {
    let mut map = serde_json::Map::new();
    for name in outputs
        .iter()
        .map(String::as_str)
        .chain(std::iter::once("*"))
    {
        let list: Vec<Value> = (1..=5)
            .map(|i| json!({"id": i, "idx": i, "focused": i == focused_idx, "occupied": i <= 3}))
            .collect();
        map.insert(name.to_string(), Value::Array(list));
    }
    json!({ "outputs": map })
}

/// Wa-iro (和色) dark tokens — the probe's theme document (DESIGN-SYSTEM §6).
fn theme_doc() -> Value {
    json!({ "tokens": {
        "color.surface": "#1b1a1e",
        "color.surface_container": "#252329",
        "color.surface_container_high": "#2f2c33",
        "color.on_surface": "#e9e4d8",
        "color.on_surface_variant": "#b9b2a6",
        "color.outline": "#5a5560",
        "color.accent": "#c9404b",
        "color.on_accent": "#fff6f1",
        "color.secondary": "#5b7fa6",
        "color.tertiary": "#8fa868",
        "color.surface_alpha": 0.82,
        "radius.sm": 6, "radius.md": 12, "radius.lg": 18, "radius.full": 999,
        "space.xs": 4, "space.sm": 8, "space.md": 12, "space.lg": 16, "space.xl": 24,
        "font.family": "Inter", "font.family_jp": "Noto Sans CJK JP",
        "font.size.caption": 11, "font.size.label": 12, "font.size.body": 13, "font.size.title": 16,
        "bar.height": 36,
        "motion.quick_ms": 120, "motion.standard_ms": 220, "motion.emphasized_ms": 320,
        "motion.easing.enter": [0.05, 0.7, 0.1, 1.0],
        "motion.easing.exit": [0.3, 0.0, 0.8, 0.15],
        "blur": true
    }})
}

fn initial_docs(outputs: &[String]) -> HashMap<String, Doc> {
    let docs = [
        ("theme", theme_doc()),
        ("svc.clock", clock_doc()),
        ("svc.workspaces", workspaces_doc(outputs, 1)),
        ("svc.audio", json!({"volume": 0.5, "muted": false})),
        (
            "svc.media",
            json!({"title": "夜に駆ける", "artist": "YOASOBI", "playing": true}),
        ),
        (
            "runtime.island.main",
            json!({"face": "clock", "faces": ["clock", "media"], "reason": "default", "pinned": false}),
        ),
        ("runtime.ui", json!({"popup": false})),
        (
            "mods.probe",
            json!({"widgets": [{
                "id": "hello",
                "ui": {"type": "row", "children": [
                    {"type": "icon", "name": "leaf"},
                    {"type": "text", "bind": "text"}
                ]},
                "state": {"text": "こんにちは"}
            }]}),
        ),
    ];
    docs.into_iter()
        .map(|(k, v)| (k.to_string(), Doc { rev: 1, data: v }))
        .collect()
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
    let (tx, _) = broadcast::channel(256);
    let state = Arc::new(Mutex::new(State {
        docs: initial_docs(&outputs),
        tx,
    }));
    let focused = Arc::new(Mutex::new(1u32));

    // Clock: wake exactly at the next minute boundary, never more often.
    {
        let state = state.clone();
        tokio::spawn(async move {
            loop {
                let secs = 60 - chrono::Local::now().timestamp() % 60;
                tokio::time::sleep(std::time::Duration::from_secs(secs as u64)).await;
                state.lock().await.patch("svc.clock", clock_doc(), None);
            }
        });
    }

    loop {
        let (stream, _) = listener.accept().await?;
        let (state, outputs, focused) = (state.clone(), outputs.clone(), focused.clone());
        tokio::spawn(async move {
            if let Err(e) = serve(stream, state, outputs, focused).await {
                tracing::debug!(error = %e, "client closed");
            }
        });
    }
}

async fn serve(
    stream: UnixStream,
    state: Arc<Mutex<State>>,
    outputs: Vec<String>,
    focused: Arc<Mutex<u32>>,
) -> anyhow::Result<()> {
    let (rd, mut wr) = stream.into_split();
    let mut reader = LineReader::new(rd);
    let (out_tx, mut out_rx) = mpsc::unbounded_channel::<ServerMsg>();
    let mut patches = state.lock().await.tx.subscribe();
    let subscribed: Arc<Mutex<std::collections::HashSet<String>>> = Default::default();

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
                    Err(broadcast::error::RecvError::Lagged(_)) => continue,
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
                    instance: String::new(),
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
            } => match key.as_str() {
                "audio.volume" => {
                    let v = value.as_f64().unwrap_or(0.5).clamp(0.0, 1.0);
                    state
                        .lock()
                        .await
                        .patch("svc.audio", json!({"volume": v}), origin);
                }
                _ => reply(ServerMsg::Err {
                    id: None,
                    kind: "invalid".into(),
                    msg: format!("unknown intent {key}"),
                }),
            },
            ClientMsg::Act { id, action, .. } => {
                let mut st = state.lock().await;
                let ok = match action.as_str() {
                    "island.next" | "island.prev" => {
                        let cur = st.docs["runtime.island.main"].data["face"]
                            .as_str()
                            .unwrap_or("clock")
                            .to_string();
                        let next = if cur == "clock" { "media" } else { "clock" };
                        st.patch(
                            "runtime.island.main",
                            json!({"face": next, "reason": "user"}),
                            None,
                        );
                        true
                    }
                    "island.pin" => {
                        let pinned = !st.docs["runtime.island.main"].data["pinned"]
                            .as_bool()
                            .unwrap_or(false);
                        st.patch("runtime.island.main", json!({"pinned": pinned}), None);
                        true
                    }
                    "probe.popup.toggle" => {
                        let open = !st.docs["runtime.ui"].data["popup"]
                            .as_bool()
                            .unwrap_or(false);
                        st.patch("runtime.ui", json!({"popup": open}), None);
                        true
                    }
                    "audio.mute.toggle" => {
                        let m = !st.docs["svc.audio"].data["muted"]
                            .as_bool()
                            .unwrap_or(false);
                        st.patch("svc.audio", json!({"muted": m}), None);
                        true
                    }
                    _ => false,
                };
                drop(st);
                reply(if ok {
                    ServerMsg::Done { id, data: None }
                } else {
                    ServerMsg::Err {
                        id: Some(id),
                        kind: "unknown_action".into(),
                        msg: format!("no action {action}"),
                    }
                });
            }
            ClientMsg::MockTick => state.lock().await.patch("svc.clock", clock_doc(), None),
            ClientMsg::MockFace { face } => state.lock().await.patch(
                "runtime.island.main",
                json!({"face": face, "reason": "event"}),
                None,
            ),
            ClientMsg::MockWorkspace { idx } => {
                *focused.lock().await = idx;
                state
                    .lock()
                    .await
                    .patch("svc.workspaces", workspaces_doc(&outputs, idx), None);
            }
            ClientMsg::Ping => reply(ServerMsg::Pong),
            ClientMsg::CfgGet { id, .. }
            | ClientMsg::CfgExplain { id, .. }
            | ClientMsg::Apply { id, .. }
            | ClientMsg::Undo { id }
            | ClientMsg::Redo { id }
            | ClientMsg::Query { id, .. } => reply(ServerMsg::Err {
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
    subscribed: &Arc<Mutex<std::collections::HashSet<String>>>,
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
        None => reply(ServerMsg::Err {
            id: Some(id),
            kind: "unknown_doc".into(),
            msg: format!("no document {doc}"),
        }),
    }
}
