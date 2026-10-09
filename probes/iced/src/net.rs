//! NDJSON client for kurashi IPC + wl_output watcher (hotplug).

use crate::Message;
use futures::{SinkExt, Stream, channel::mpsc};
use serde_json::{Value, json};
use std::collections::HashMap;
use tokio::io::{AsyncBufReadExt, AsyncWriteExt, BufReader};
use tokio::net::UnixStream;
use tokio::sync::mpsc::{UnboundedSender, unbounded_channel};

pub const DOCS: &[&str] = &[
    "theme",
    "svc.clock",
    "svc.workspaces",
    "svc.audio",
    "svc.media",
    "runtime.island.main",
    "runtime.ui",
    "mods.probe",
];

#[derive(Debug, Clone)]
pub enum Net {
    Snap { doc: String, rev: u64, data: Value },
    Patch { doc: String, rev: u64, ops: Value, origin: Option<String> },
    Down,
}

pub type Tx = UnboundedSender<String>;

pub fn stream() -> impl Stream<Item = Message> {
    iced::stream::channel(64, async |mut out: mpsc::Sender<Message>| {
        let mut backoff = 250u64;
        loop {
            let path = std::env::var("KURASHI_SOCKET").unwrap_or_default();
            if let Ok(sock) = UnixStream::connect(&path).await {
                backoff = 250;
                session(sock, &mut out).await;
                let _ = out.send(Message::Net(Net::Down)).await;
            }
            tokio::time::sleep(std::time::Duration::from_millis(backoff)).await;
            backoff = (backoff * 2).min(4000);
        }
    })
}

async fn session(sock: UnixStream, out: &mut mpsc::Sender<Message>) {
    let (rd, mut wr) = sock.into_split();
    let (tx, mut rx) = unbounded_channel::<String>();
    let mut hello = json!({"t":"hello","v":1,"client":"frontend","caps":["intents","resync"]}).to_string();
    hello.push('\n');
    if wr.write_all(hello.as_bytes()).await.is_err() {
        return;
    }
    for d in DOCS {
        let mut l = json!({"t":"sub","id":format!("s-{d}"),"doc":d}).to_string();
        l.push('\n');
        if wr.write_all(l.as_bytes()).await.is_err() {
            return;
        }
    }
    let _ = out.send(Message::Connected(tx)).await;
    let mut lines = BufReader::new(rd).lines();
    loop {
        tokio::select! {
            line = lines.next_line() => {
                let Ok(Some(line)) = line else { return };
                let Ok(v) = serde_json::from_str::<Value>(&line) else { continue };
                let doc = v["doc"].as_str().unwrap_or("").to_string();
                let rev = v["rev"].as_u64().unwrap_or(0);
                let msg = match v["t"].as_str() {
                    Some("snap") => Net::Snap { doc, rev, data: v["data"].clone() },
                    Some("patch") => Net::Patch {
                        doc, rev, ops: v["ops"].clone(),
                        origin: v["origin"].as_str().map(String::from),
                    },
                    Some("ping") => {
                        let _ = wr.write_all(b"{\"t\":\"pong\"}\n").await;
                        continue;
                    }
                    _ => continue,
                };
                if out.send(Message::Net(msg)).await.is_err() { return; }
            }
            Some(mut l) = rx.recv() => {
                l.push('\n');
                if wr.write_all(l.as_bytes()).await.is_err() { return; }
            }
        }
    }
}

// ---------------------------------------------------------------- outputs

#[derive(Debug, Clone)]
pub enum OutEv {
    Added(String),
    Removed(String),
}

pub fn outputs_stream() -> impl Stream<Item = Message> {
    iced::stream::channel(16, async |out: mpsc::Sender<Message>| {
        let (tx, mut rx) = mpsc::channel::<OutEv>(16);
        std::thread::spawn(move || watch_outputs(tx));
        let mut out = out;
        use futures::StreamExt;
        while let Some(ev) = rx.next().await {
            if out.send(Message::Output(ev)).await.is_err() {
                break;
            }
        }
        std::future::pending::<()>().await;
    })
}

use wayland_client::{
    Connection, Dispatch, QueueHandle,
    globals::{GlobalListContents, registry_queue_init},
    protocol::{wl_output, wl_registry},
};

struct W {
    tx: mpsc::Sender<OutEv>,
    outs: HashMap<u32, (wl_output::WlOutput, Option<String>)>,
}

impl Dispatch<wl_registry::WlRegistry, GlobalListContents> for W {
    fn event(
        st: &mut Self,
        reg: &wl_registry::WlRegistry,
        ev: wl_registry::Event,
        _: &GlobalListContents,
        _: &Connection,
        qh: &QueueHandle<Self>,
    ) {
        match ev {
            wl_registry::Event::Global { name, interface, version } if interface == "wl_output" => {
                let o = reg.bind::<wl_output::WlOutput, _, _>(name, version.min(4), qh, name);
                st.outs.insert(name, (o, None));
            }
            wl_registry::Event::GlobalRemove { name } => {
                if let Some((_, Some(n))) = st.outs.remove(&name) {
                    let _ = st.tx.try_send(OutEv::Removed(n));
                }
            }
            _ => {}
        }
    }
}

impl Dispatch<wl_output::WlOutput, u32> for W {
    fn event(
        st: &mut Self,
        _: &wl_output::WlOutput,
        ev: wl_output::Event,
        name: &u32,
        _: &Connection,
        _: &QueueHandle<Self>,
    ) {
        if let wl_output::Event::Name { name: n } = ev {
            if let Some(e) = st.outs.get_mut(name) {
                e.1 = Some(n.clone());
            }
            let _ = st.tx.try_send(OutEv::Added(n));
        }
    }
}

fn watch_outputs(tx: mpsc::Sender<OutEv>) {
    let Ok(conn) = Connection::connect_to_env() else { return };
    let Ok((globals, mut q)) = registry_queue_init::<W>(&conn) else { return };
    let qh = q.handle();
    let mut w = W { tx, outs: HashMap::new() };
    // bind outputs that already exist
    let reg = globals.registry();
    for g in globals.contents().clone_list() {
        if g.interface == "wl_output" {
            let o = reg.bind::<wl_output::WlOutput, _, _>(g.name, g.version.min(4), &qh, g.name);
            w.outs.insert(g.name, (o, None));
        }
    }
    while q.blocking_dispatch(&mut w).is_ok() {}
}
