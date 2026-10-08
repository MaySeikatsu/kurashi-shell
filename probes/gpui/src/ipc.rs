//! NDJSON client for kurashid/kurashi-mock. Blocking reader thread (zero wakeups when idle),
//! merged documents are forwarded to the gpui foreground via an unbounded channel.

use std::collections::HashMap;
use std::io::{BufRead, BufReader, Write};
use std::os::unix::net::UnixStream;
use std::sync::{Arc, Mutex};
use std::time::Duration;

use futures::channel::mpsc::UnboundedSender;
use serde_json::{Value, json};

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

pub enum Event {
    /// Full merged document after a snap/patch.
    Doc { name: String, data: Value, origin: Option<String> },
    Connected(bool),
}

pub struct Ipc {
    writer: Mutex<Option<UnixStream>>,
}

impl Ipc {
    pub fn send(&self, msg: Value) {
        if let Ok(mut g) = self.writer.lock() {
            if let Some(w) = g.as_mut() {
                let mut line = msg.to_string();
                line.push('\n');
                if w.write_all(line.as_bytes()).is_err() {
                    *g = None;
                }
            }
        }
    }

    pub fn act(&self, action: &str) {
        self.send(json!({"t":"act","id":format!("a-{action}"),"action":action}));
    }
}

pub fn merge_patch(target: &mut Value, patch: &Value) {
    if let Value::Object(p) = patch {
        if !target.is_object() {
            *target = Value::Object(Default::default());
        }
        let t = target.as_object_mut().unwrap();
        for (k, v) in p {
            if v.is_null() {
                t.remove(k);
            } else {
                merge_patch(t.entry(k.clone()).or_insert(Value::Null), v);
            }
        }
    } else {
        *target = patch.clone();
    }
}

pub fn spawn(tx: UnboundedSender<Event>) -> Arc<Ipc> {
    let ipc = Arc::new(Ipc { writer: Mutex::new(None) });
    let me = ipc.clone();
    std::thread::spawn(move || run(me, tx));
    ipc
}

fn socket_path() -> String {
    std::env::var("KURASHI_SOCKET").unwrap_or_else(|_| {
        format!("{}/kurashi/ipc.sock", std::env::var("XDG_RUNTIME_DIR").unwrap_or_default())
    })
}

fn run(ipc: Arc<Ipc>, tx: UnboundedSender<Event>) {
    let mut backoff = 250u64;
    loop {
        match UnixStream::connect(socket_path()) {
            Ok(stream) => {
                backoff = 250;
                *ipc.writer.lock().unwrap() = stream.try_clone().ok();
                let _ = tx.unbounded_send(Event::Connected(true));
                ipc.send(json!({"t":"hello","v":1,"client":"frontend","caps":["intents","resync"]}));
                for (i, d) in DOCS.iter().enumerate() {
                    ipc.send(json!({"t":"sub","id":i.to_string(),"doc":d}));
                }
                read_loop(&ipc, &tx, stream);
                *ipc.writer.lock().unwrap() = None;
                let _ = tx.unbounded_send(Event::Connected(false));
            }
            Err(_) => {}
        }
        std::thread::sleep(Duration::from_millis(backoff));
        backoff = (backoff * 2).min(4000);
    }
}

fn read_loop(ipc: &Arc<Ipc>, tx: &UnboundedSender<Event>, stream: UnixStream) {
    let mut docs: HashMap<String, (u64, Value)> = HashMap::new();
    for line in BufReader::new(stream).lines() {
        let Ok(line) = line else { return };
        let Ok(msg) = serde_json::from_str::<Value>(&line) else { continue };
        let doc = msg["doc"].as_str().unwrap_or("").to_string();
        match msg["t"].as_str() {
            Some("snap") => {
                let rev = msg["rev"].as_u64().unwrap_or(0);
                let data = msg["data"].clone();
                docs.insert(doc.clone(), (rev, data.clone()));
                let _ = tx.unbounded_send(Event::Doc { name: doc, data, origin: None });
            }
            Some("patch") => {
                let rev = msg["rev"].as_u64().unwrap_or(0);
                let Some((last, data)) = docs.get_mut(&doc) else { continue };
                if rev != *last + 1 {
                    ipc.send(json!({"t":"resync","doc":doc}));
                    continue;
                }
                *last = rev;
                merge_patch(data, &msg["ops"]);
                let origin = msg["origin"].as_str().map(String::from);
                let _ = tx.unbounded_send(Event::Doc { name: doc, data: data.clone(), origin });
            }
            Some("ping") => ipc.send(json!({"t":"pong"})),
            Some("goodbye") | Some("bye") => return,
            _ => {}
        }
    }
}
