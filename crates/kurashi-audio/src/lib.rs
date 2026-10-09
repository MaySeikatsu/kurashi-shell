//! `svc.audio`: default sink/source state from the sound server, event-driven.
//!
//! Backend choice: `libpulse-binding` against the PulseAudio protocol. PipeWire serves it via
//! pipewire-pulse, so one backend covers both, it has a safe API (workspace forbids `unsafe`),
//! needs no bindgen/libclang, and its subscribe callback gives change events without polling.
//!
//! Shape: a worker thread owns the [`Backend`] (which need not be `Send`), serialises snapshots
//! and commands, and emits the *full* document on every change (the hub diffs, K-protocol §3).
//! Dropping the [`AudioHandle`] joins the thread, so nothing runs while nobody subscribes (Ma).

mod pulse;

use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::mpsc::{self, Receiver, Sender};
use std::sync::{Arc, Mutex};
use std::thread::JoinHandle;

use anyhow::Result;
use kurashi_services::DocSink;
use serde_json::{Value, json};

pub use pulse::PulseBackend;

/// Upper bound of the linear volume (150 %), matching PulseAudio's soft over-amplification.
pub const MAX_VOLUME: f64 = 1.5;

/// One sink or source.
#[derive(Debug, Clone, PartialEq)]
pub struct Device {
    pub id: u32,
    pub name: String,
    pub description: String,
    /// Linear, `1.0` = 100 %.
    pub volume: f64,
    pub muted: bool,
}

/// Everything the document is built from.
#[derive(Debug, Clone, Default, PartialEq)]
pub struct Snapshot {
    pub sinks: Vec<Device>,
    pub sources: Vec<Device>,
    pub default_sink: Option<u32>,
    pub default_source: Option<u32>,
}

/// The sound server. Lives on the worker thread only; commands are fire-and-forget and the
/// resulting change must come back through the [`Notifier`] (no optimistic doc edits: Shōjiki).
pub trait Backend: 'static {
    fn snapshot(&mut self) -> Result<Snapshot>;
    fn set_volume(&mut self, linear: f64);
    fn set_muted(&mut self, muted: bool);
    fn set_default_sink(&mut self, id: u32);
    fn set_source_muted(&mut self, muted: bool);
}

enum Msg {
    Changed,
    Cmd(Cmd),
    Quit,
}

#[derive(Debug, Clone, Copy, PartialEq)]
enum Cmd {
    Volume(f64),
    Muted(bool),
    ToggleMute,
    DefaultSink(u32),
    SourceMuted(bool),
    ToggleSourceMute,
}

/// Backends call this (from any thread) when the server reports a change.
#[derive(Clone)]
pub struct Notifier(Sender<Msg>);

impl Notifier {
    pub fn notify(&self) {
        let _ = self.0.send(Msg::Changed);
    }
}

/// Command side of the service; cheap to clone, never blocks.
#[derive(Clone)]
pub struct Commands(Sender<Msg>);

impl Commands {
    /// Linear volume, clamped to `0..=MAX_VOLUME`. Idempotent; the worker coalesces bursts.
    pub fn set_volume(&self, v: f64) {
        self.send(Cmd::Volume(v));
    }
    pub fn set_muted(&self, m: bool) {
        self.send(Cmd::Muted(m));
    }
    pub fn toggle_mute(&self) {
        self.send(Cmd::ToggleMute);
    }
    pub fn set_default_sink(&self, id: u32) {
        self.send(Cmd::DefaultSink(id));
    }
    pub fn set_source_muted(&self, m: bool) {
        self.send(Cmd::SourceMuted(m));
    }
    pub fn toggle_source_mute(&self) {
        self.send(Cmd::ToggleSourceMute);
    }
    fn send(&self, c: Cmd) {
        let _ = self.0.send(Msg::Cmd(c));
    }
}

/// Drop = stop: signals the worker, joins it (which drops the backend and its server connection).
pub struct AudioHandle {
    tx: Sender<Msg>,
    alive: Arc<AtomicBool>,
    thread: Option<JoinHandle<()>>,
}

impl Drop for AudioHandle {
    fn drop(&mut self) {
        self.alive.store(false, Ordering::SeqCst);
        let _ = self.tx.send(Msg::Quit);
        if let Some(t) = self.thread.take() {
            let _ = t.join();
        }
    }
}

/// Start against the real sound server.
pub fn start(sink: Arc<dyn DocSink>) -> (AudioHandle, Commands) {
    start_with(sink, PulseBackend::connect)
}

/// Start with any backend; `factory` runs on the worker thread so non-`Send` backends work.
pub fn start_with<B, F>(sink: Arc<dyn DocSink>, factory: F) -> (AudioHandle, Commands)
where
    B: Backend,
    F: FnOnce(Notifier) -> Result<B> + Send + 'static,
{
    let (tx, rx) = mpsc::channel();
    let alive = Arc::new(AtomicBool::new(true));
    let notifier = Notifier(tx.clone());
    let thread = {
        let alive = alive.clone();
        std::thread::Builder::new()
            .name("kurashi-audio".into())
            .spawn(move || run(rx, sink, alive, notifier, factory))
            .expect("spawn audio thread")
    };
    (
        AudioHandle {
            tx: tx.clone(),
            alive,
            thread: Some(thread),
        },
        Commands(tx),
    )
}

fn run<B: Backend>(
    rx: Receiver<Msg>,
    sink: Arc<dyn DocSink>,
    alive: Arc<AtomicBool>,
    notifier: Notifier,
    factory: impl FnOnce(Notifier) -> Result<B>,
) {
    let mut backend = match factory(notifier) {
        Ok(b) => b,
        Err(e) => {
            tracing::warn!("audio backend unavailable: {e:#}");
            if alive.load(Ordering::SeqCst) {
                sink.set(unavailable_doc());
            }
            // Park until dropped so the handle semantics stay identical.
            while !matches!(rx.recv(), Ok(Msg::Quit) | Err(_)) {}
            return;
        }
    };
    let last = Mutex::new(Snapshot::default());
    let mut last_doc: Option<Value> = None;
    let mut refresh = |backend: &mut B| {
        if !alive.load(Ordering::SeqCst) {
            return;
        }
        match backend.snapshot() {
            Ok(s) => {
                let doc = build_doc(&s);
                *last.lock().unwrap() = s;
                // Server events fire for unrelated properties; identical docs would wake the hub.
                if alive.load(Ordering::SeqCst) && last_doc.as_ref() != Some(&doc) {
                    last_doc = Some(doc.clone());
                    sink.set(doc);
                }
            }
            Err(e) => tracing::warn!("audio snapshot failed: {e:#}"),
        }
    };
    refresh(&mut backend);

    while let Ok(first) = rx.recv() {
        // Drain the burst: one snapshot per wakeup, and only the latest of each command kind.
        let mut batch = vec![first];
        batch.extend(rx.try_iter());
        let mut changed = false;
        let mut cmds: Vec<Cmd> = Vec::new();
        for m in batch {
            match m {
                Msg::Quit => return,
                Msg::Changed => changed = true,
                Msg::Cmd(c) => cmds.push(c),
            }
        }
        if !alive.load(Ordering::SeqCst) {
            return;
        }
        let snap = last.lock().unwrap().clone();
        for c in coalesce(cmds) {
            apply(&mut backend, &snap, c);
        }
        // Commands report back through the notifier; plain `changed` needs the refresh now.
        if changed {
            refresh(&mut backend);
        }
    }
}

/// Keep the last `Volume` only; other commands are order-sensitive and kept as-is.
fn coalesce(cmds: Vec<Cmd>) -> Vec<Cmd> {
    let last_vol = cmds.iter().rposition(|c| matches!(c, Cmd::Volume(_)));
    cmds.into_iter()
        .enumerate()
        .filter(|(i, c)| !matches!(c, Cmd::Volume(_)) || Some(*i) == last_vol)
        .map(|(_, c)| c)
        .collect()
}

fn apply<B: Backend>(b: &mut B, cached: &Snapshot, c: Cmd) {
    match c {
        // Writes are unconditional: comparing against a cached snapshot could drop a real change
        // (0.5 -> 0.6 -> 0.5 inside one round-trip). The server ignores equal writes itself.
        Cmd::Volume(v) => {
            if v.is_finite() {
                b.set_volume(v.clamp(0.0, MAX_VOLUME));
            }
        }
        Cmd::Muted(m) => b.set_muted(m),
        Cmd::SourceMuted(m) => b.set_source_muted(m),
        // Toggles and id lookups need current state: re-read instead of trusting the cache.
        Cmd::ToggleMute | Cmd::ToggleSourceMute | Cmd::DefaultSink(_) => {
            let snap = b.snapshot().unwrap_or_else(|_| cached.clone());
            match c {
                Cmd::ToggleMute => {
                    if let Some(d) = default_of(&snap.sinks, snap.default_sink) {
                        b.set_muted(!d.muted);
                    }
                }
                Cmd::ToggleSourceMute => {
                    if let Some(d) = default_of(&snap.sources, snap.default_source) {
                        b.set_source_muted(!d.muted);
                    }
                }
                Cmd::DefaultSink(id)
                    if snap.default_sink != Some(id) && snap.sinks.iter().any(|s| s.id == id) =>
                {
                    b.set_default_sink(id);
                }
                _ => {}
            }
        }
    }
}

fn default_of(devs: &[Device], id: Option<u32>) -> Option<&Device> {
    devs.iter().find(|d| Some(d.id) == id)
}

/// 4 decimals: stable against float jitter from the server's integer volume scale.
fn round(v: f64) -> f64 {
    (v * 10_000.0).round() / 10_000.0
}

fn dev_json(d: &Device, default: bool) -> Value {
    json!({"id": d.id, "name": d.name, "description": d.description, "default": default})
}

/// The `svc.audio` document. No nulls (PROTOCOL §3): absent default sink/source = absent keys.
pub fn build_doc(s: &Snapshot) -> Value {
    let sink = default_of(&s.sinks, s.default_sink);
    let mut doc = json!({
        "available": true,
        "volume": round(sink.map_or(0.0, |d| d.volume).clamp(0.0, MAX_VOLUME)),
        "muted": sink.is_some_and(|d| d.muted),
        "sinks": s.sinks.iter().map(|d| dev_json(d, Some(d.id) == s.default_sink)).collect::<Vec<_>>(),
    });
    let obj = doc.as_object_mut().expect("object");
    if let Some(d) = sink {
        obj.insert("sink".into(), dev_json(d, true));
    }
    if let Some(d) = default_of(&s.sources, s.default_source) {
        let mut src = dev_json(d, true);
        src["muted"] = json!(d.muted);
        src["volume"] = json!(round(d.volume.clamp(0.0, MAX_VOLUME)));
        obj.insert("source".into(), src);
    }
    doc
}

/// Server unreachable: still a valid, honest document (Shōjiki), the slider shows it is inert.
fn unavailable_doc() -> Value {
    json!({"available": false, "volume": 0.0, "muted": false, "sinks": []})
}

#[cfg(test)]
mod tests;
