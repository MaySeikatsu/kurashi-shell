//! NDJSON client: reader thread with reconnect backoff (250 ms -> 4 s). Wakes the main poll loop
//! through a pipe; the thread blocks in read(2) otherwise (no timers, no polling).
use serde_json::{json, Value};
use std::io::{BufRead, BufReader, Write};
use std::os::fd::RawFd;
use std::os::unix::net::UnixStream;
use std::sync::mpsc::{channel, Receiver, Sender};
use std::sync::{Arc, Mutex};
use std::time::Duration;

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

pub enum Ev {
    Connected,
    Disconnected,
    Msg(Value),
}

pub struct Ipc {
    pub rx: Receiver<Ev>,
    pub wake_rd: RawFd,
    writer: Arc<Mutex<Option<UnixStream>>>,
}

impl Ipc {
    pub fn send(&self, v: Value) {
        if let Some(w) = self.writer.lock().unwrap().as_mut() {
            let mut line = v.to_string();
            line.push('\n');
            let _ = w.write_all(line.as_bytes());
        }
    }
    pub fn drain_wake(&self) {
        let mut buf = [0u8; 64];
        unsafe { libc::read(self.wake_rd, buf.as_mut_ptr().cast(), buf.len()) };
    }
}

pub fn spawn(path: String) -> Ipc {
    let (tx, rx) = channel();
    let mut fds = [0i32; 2];
    unsafe { libc::pipe2(fds.as_mut_ptr(), libc::O_NONBLOCK | libc::O_CLOEXEC) };
    let (wake_rd, wake_wr) = (fds[0], fds[1]);
    let writer: Arc<Mutex<Option<UnixStream>>> = Arc::new(Mutex::new(None));
    let w2 = writer.clone();
    std::thread::spawn(move || run(path, tx, wake_wr, w2));
    Ipc { rx, wake_rd, writer }
}

fn wake(fd: RawFd) {
    unsafe { libc::write(fd, [1u8].as_ptr().cast(), 1) };
}

fn run(path: String, tx: Sender<Ev>, wake_wr: RawFd, writer: Arc<Mutex<Option<UnixStream>>>) {
    let mut backoff = 250u64;
    loop {
        if let Ok(stream) = UnixStream::connect(&path) {
            let mut w = stream.try_clone().expect("clone");
            let mut hello = vec![json!({"t":"hello","v":1,"client":"frontend","caps":["intents","resync"]})];
            for (i, d) in DOCS.iter().enumerate() {
                hello.push(json!({"t":"sub","id":(i+1).to_string(),"doc":d}));
            }
            for m in hello {
                let _ = writeln!(w, "{m}");
            }
            *writer.lock().unwrap() = Some(w);
            let _ = tx.send(Ev::Connected);
            wake(wake_wr);
            backoff = 250;
            for line in BufReader::new(stream).lines() {
                let Ok(line) = line else { break };
                if let Ok(v) = serde_json::from_str::<Value>(&line) {
                    let _ = tx.send(Ev::Msg(v));
                    wake(wake_wr);
                }
            }
            *writer.lock().unwrap() = None;
            let _ = tx.send(Ev::Disconnected);
            wake(wake_wr);
        }
        std::thread::sleep(Duration::from_millis(backoff));
        backoff = (backoff * 2).min(4000);
    }
}

/// RFC 7396 JSON merge-patch.
pub fn merge_patch(target: &mut Value, patch: &Value) {
    if let Value::Object(p) = patch {
        if !target.is_object() {
            *target = json!({});
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
