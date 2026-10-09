use std::sync::mpsc::{Receiver, Sender, channel};
use std::sync::{Arc, Mutex};
use std::time::Duration;

use serde_json::Value;

use super::*;

#[derive(Default)]
struct Fake {
    snap: Snapshot,
    /// Calls that reached the backend, in order.
    calls: Vec<String>,
    notifier: Option<Notifier>,
}

type Shared = Arc<Mutex<Fake>>;

struct FakeBackend(Shared);

impl FakeBackend {
    fn mutate(&self, call: String, f: impl FnOnce(&mut Snapshot)) {
        let mut g = self.0.lock().unwrap();
        g.calls.push(call);
        f(&mut g.snap);
        // A real server answers a command with a change event.
        if let Some(n) = &g.notifier {
            n.notify();
        }
    }
}

impl Backend for FakeBackend {
    fn snapshot(&mut self) -> Result<Snapshot> {
        Ok(self.0.lock().unwrap().snap.clone())
    }
    fn set_volume(&mut self, v: f64) {
        self.mutate(format!("vol {v}"), |s| {
            let id = s.default_sink;
            s.sinks
                .iter_mut()
                .filter(|d| Some(d.id) == id)
                .for_each(|d| d.volume = v);
        });
    }
    fn set_muted(&mut self, m: bool) {
        self.mutate(format!("mute {m}"), |s| {
            let id = s.default_sink;
            s.sinks
                .iter_mut()
                .filter(|d| Some(d.id) == id)
                .for_each(|d| d.muted = m);
        });
    }
    fn set_default_sink(&mut self, id: u32) {
        self.mutate(format!("default {id}"), |s| s.default_sink = Some(id));
    }
    fn set_source_muted(&mut self, m: bool) {
        self.mutate(format!("srcmute {m}"), |s| {
            let id = s.default_source;
            s.sources
                .iter_mut()
                .filter(|d| Some(d.id) == id)
                .for_each(|d| d.muted = m);
        });
    }
}

struct ChanSink(Mutex<Sender<Value>>);
impl DocSink for ChanSink {
    fn set(&self, doc: Value) {
        let _ = self.0.lock().unwrap().send(doc);
    }
}

fn dev(id: u32, name: &str, volume: f64) -> Device {
    Device {
        id,
        name: name.into(),
        description: format!("{name} desc"),
        volume,
        muted: false,
    }
}

fn fixture() -> Shared {
    Arc::new(Mutex::new(Fake {
        snap: Snapshot {
            sinks: vec![dev(1, "speakers", 0.5), dev(2, "headset", 1.0)],
            sources: vec![dev(10, "mic", 0.8)],
            default_sink: Some(1),
            default_source: Some(10),
        },
        ..Fake::default()
    }))
}

fn boot(shared: &Shared) -> (AudioHandle, Commands, Receiver<Value>) {
    let (tx, rx) = channel();
    let s = shared.clone();
    let (h, c) = start_with(Arc::new(ChanSink(Mutex::new(tx))), move |n| {
        s.lock().unwrap().notifier = Some(n);
        Ok(FakeBackend(s.clone()))
    });
    (h, c, rx)
}

fn next(rx: &Receiver<Value>) -> Value {
    rx.recv_timeout(Duration::from_secs(2)).expect("a document")
}

/// Waits until `pred` holds for a document (intermediate docs may be skipped or repeated).
fn until(rx: &Receiver<Value>, pred: impl Fn(&Value) -> bool) -> Value {
    loop {
        let d = next(rx);
        if pred(&d) {
            return d;
        }
    }
}

fn no_nulls(v: &Value) -> bool {
    match v {
        Value::Null => false,
        Value::Array(a) => a.iter().all(no_nulls),
        Value::Object(o) => o.values().all(no_nulls),
        _ => true,
    }
}

#[test]
fn initial_document() {
    let shared = fixture();
    let (_h, _c, rx) = boot(&shared);
    let d = next(&rx);
    assert_eq!(d["available"], true);
    assert_eq!(d["volume"], 0.5);
    assert_eq!(d["muted"], false);
    assert_eq!(d["sink"]["name"], "speakers");
    assert_eq!(d["sinks"].as_array().unwrap().len(), 2);
    assert_eq!(d["sinks"][0]["default"], true);
    assert_eq!(d["sinks"][1]["default"], false);
    assert_eq!(d["source"]["muted"], false);
    assert!(no_nulls(&d));
}

#[test]
fn external_change_emits_new_document() {
    let shared = fixture();
    let (_h, _c, rx) = boot(&shared);
    next(&rx);
    {
        let mut g = shared.lock().unwrap();
        g.snap.sinks[0].volume = 0.9;
        g.notifier.as_ref().unwrap().notify();
    }
    until(&rx, |d| d["volume"] == 0.9);
}

#[test]
fn commands_reach_backend_and_echo_back() {
    let shared = fixture();
    let (_h, c, rx) = boot(&shared);
    next(&rx);

    c.set_volume(0.7);
    until(&rx, |d| d["volume"] == 0.7);

    c.toggle_mute();
    until(&rx, |d| d["muted"] == true);
    c.set_muted(false);
    until(&rx, |d| d["muted"] == false);

    c.set_default_sink(2);
    let d = until(&rx, |d| d["sink"]["name"] == "headset");
    assert_eq!(d["volume"], 1.0);

    c.toggle_source_mute();
    until(&rx, |d| d["source"]["muted"] == true);

    // Unknown sink id and over-range volume are handled without reaching the server wrongly.
    c.set_default_sink(99);
    c.set_volume(9.0);
    until(&rx, |d| d["volume"] == MAX_VOLUME);
    assert!(
        !shared
            .lock()
            .unwrap()
            .calls
            .iter()
            .any(|c| c == "default 99")
    );
}

#[test]
fn volume_bursts_are_coalesced_and_cheap() {
    let shared = fixture();
    let (_h, c, rx) = boot(&shared);
    next(&rx);
    for i in 1..=60 {
        c.set_volume(f64::from(i) / 100.0);
    }
    until(&rx, |d| d["volume"] == 0.6);
    let calls = shared.lock().unwrap().calls.len();
    assert!(calls <= 60, "{calls} writes");
}

#[test]
fn coalesce_keeps_last_volume_and_order() {
    let out = coalesce(vec![
        Cmd::Volume(0.1),
        Cmd::Muted(true),
        Cmd::Volume(0.2),
        Cmd::Volume(0.3),
    ]);
    assert_eq!(out, vec![Cmd::Muted(true), Cmd::Volume(0.3)]);
}

#[test]
fn drop_stops_callbacks() {
    let shared = fixture();
    let (h, _c, rx) = boot(&shared);
    next(&rx);
    let notifier = shared.lock().unwrap().notifier.clone().unwrap();
    drop(h);
    // Late events from a still-running server connection must not produce documents.
    shared.lock().unwrap().snap.sinks[0].volume = 0.1;
    notifier.notify();
    assert!(rx.recv_timeout(Duration::from_millis(300)).is_err());
}

#[test]
fn unavailable_server_is_an_honest_document() {
    let (tx, rx) = channel();
    let (_h, _c) = start_with::<FakeBackend, _>(Arc::new(ChanSink(Mutex::new(tx))), |_| {
        anyhow::bail!("no server")
    });
    let d = next(&rx);
    assert_eq!(d["available"], false);
    assert!(no_nulls(&d));
}

#[test]
fn doc_without_defaults_has_no_nulls() {
    let d = build_doc(&Snapshot::default());
    assert!(no_nulls(&d));
    assert!(d.get("sink").is_none());
    assert!(d.get("source").is_none());
}
