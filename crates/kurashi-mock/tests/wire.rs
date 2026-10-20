//! Wire-level check of the parity set: the built `kurashi-mock` on a private socket, spoken to in
//! NDJSON the way the frontend's Store does (PROTOCOL §2–§7). Every read is bounded, so a silent
//! mock fails the test instead of hanging it.

use std::io::{BufRead, BufReader, Write};
use std::os::unix::net::UnixStream;
use std::path::{Path, PathBuf};
use std::process::{Child, Command, Stdio};
use std::time::{Duration, Instant};

use serde_json::{Value, json};

/// Kills the mock we started and removes its socket dir, even when an assertion fails.
struct Mock {
    child: Child,
    dir: PathBuf,
}

impl Drop for Mock {
    fn drop(&mut self) {
        let _ = self.child.kill();
        let _ = self.child.wait();
        let _ = std::fs::remove_dir_all(&self.dir);
    }
}

/// Starts a mock with `extra` arguments on a socket of its own. `tag` keeps the directories of
/// tests that run in parallel in this process apart.
fn start_with(tag: &str, extra: &[&str]) -> (Mock, PathBuf) {
    let dir = std::env::temp_dir().join(format!("kurashi-mock-wire-{}-{tag}", std::process::id()));
    let _ = std::fs::remove_dir_all(&dir);
    std::fs::create_dir_all(&dir).expect("socket dir");
    let sock = dir.join("ipc.sock");
    // The mock creates the web dock's profile and icon dirs under HOME at startup. Nix builds run
    // with a HOME that cannot be written, so the mock gets directories of its own.
    let child = Command::new(env!("CARGO_BIN_EXE_kurashi-mock"))
        .arg("--socket")
        .arg(&sock)
        .args(extra)
        .env("XDG_DATA_HOME", dir.join("data"))
        .env("XDG_CACHE_HOME", dir.join("cache"))
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .spawn()
        .expect("spawn kurashi-mock");
    let mock = Mock { child, dir };
    let deadline = Instant::now() + Duration::from_secs(10);
    while UnixStream::connect(&sock).is_err() {
        assert!(Instant::now() < deadline, "kurashi-mock did not listen");
        std::thread::sleep(Duration::from_millis(20));
    }
    (mock, sock)
}

fn start() -> (Mock, PathBuf) {
    start_with("parity", &[])
}

struct Client {
    tx: UnixStream,
    rx: BufReader<UnixStream>,
}

impl Client {
    fn connect(sock: &Path) -> Self {
        Self::connect_welcome(sock).0
    }

    /// Connects and says hello; returns the client and the `welcome` message.
    fn connect_welcome(sock: &Path) -> (Self, Value) {
        let tx = UnixStream::connect(sock).expect("connect");
        tx.set_read_timeout(Some(Duration::from_secs(5)))
            .expect("read timeout");
        let rx = BufReader::new(tx.try_clone().expect("clone socket"));
        let mut c = Client { tx, rx };
        c.send(
            &json!({"t": "hello", "v": 1, "client": "wire-test", "caps": ["intents", "resync"]}),
        );
        let welcome = c.recv();
        assert_eq!(welcome["t"], "welcome");
        (c, welcome)
    }

    fn send(&mut self, m: &Value) {
        writeln!(self.tx, "{m}").expect("write");
    }

    fn recv(&mut self) -> Value {
        let mut line = String::new();
        self.rx.read_line(&mut line).expect("a message within 5 s");
        serde_json::from_str(&line).expect("NDJSON line")
    }

    /// The reply to a request (matched by its `id`); patches for subscribed documents may arrive
    /// in between and are skipped.
    fn call(&mut self, m: Value) -> Value {
        let id = m["id"].clone();
        self.send(&m);
        loop {
            let r = self.recv();
            if r["id"] == id {
                return r;
            }
        }
    }

    /// The first message matching `pred`.
    fn until(&mut self, pred: impl Fn(&Value) -> bool) -> Value {
        loop {
            let m = self.recv();
            if pred(&m) {
                return m;
            }
        }
    }
}

#[test]
fn parity_set_over_the_wire() {
    let (_mock, sock) = start();
    let mut c = Client::connect(&sock);

    // runtime.ui starts closed, and the island's bindings are served as a document.
    let ui = c.call(json!({"t": "sub", "id": "ui", "doc": "runtime.ui"}));
    assert_eq!(ui["t"], "snap");
    assert_eq!(
        ui["data"],
        json!({"popup": false, "panel": "", "launcher": false, "tray": "", "face": ""})
    );
    let b = c.call(json!({"t": "sub", "id": "b", "doc": "bindings"}));
    assert_eq!(
        b["data"]["island.main"]["scroll_down"]["action"],
        "island.next"
    );

    // Panel actions, then input.dispatch: an unbound slot is done and inert, a bound one runs.
    let r = c.call(json!({"t": "act", "id": "a1", "action": "island.expand"}));
    assert_eq!(r["t"], "done");
    let r = c.call(json!({
        "t": "act", "id": "a2", "action": "input.dispatch",
        "args": {"component": "island.main", "slot": "middle"}
    }));
    assert_eq!(r["t"], "done");
    let r = c.call(json!({
        "t": "act", "id": "a3", "action": "input.dispatch",
        "args": {"component": "island.main", "slot": "right"}
    }));
    assert_eq!(r["t"], "done");
    let ui = c.call(json!({"t": "sub", "id": "ui2", "doc": "runtime.ui"}));
    assert_eq!(ui["data"]["panel"], "island");
    let isl = c.call(json!({"t": "sub", "id": "isl", "doc": "runtime.island.main"}));
    assert_eq!(isl["data"]["pinned"], true);

    // Brightness: the snapshot is 50 %, and a subscribed document gets the step as a patch.
    let s = c.call(json!({"t": "sub", "id": "br", "doc": "svc.brightness"}));
    assert_eq!(s["data"]["percent"], 50.0);
    let r = c.call(json!({"t": "act", "id": "a4", "action": "brightness.up"}));
    assert_eq!(r["t"], "done");
    let patch = c.until(|m| m["t"] == "patch" && m["doc"] == "svc.brightness");
    assert_eq!(patch["ops"]["percent"], 55.0);

    // Session: destructive calls fail with the confirm code in msg; confirmed calls are done.
    let r = c.call(json!({"t": "act", "id": "a5", "action": "session.suspend"}));
    assert_eq!(r["t"], "err");
    assert_eq!(r["kind"], "invalid");
    assert_eq!(r["msg"], "session.confirm_required");
    let r = c.call(json!({
        "t": "act", "id": "a6", "action": "session.suspend", "args": {"confirm": true}
    }));
    assert_eq!(r["t"], "done");
    let r = c.call(json!({"t": "act", "id": "a7", "action": "session.lock"}));
    assert_eq!(r["t"], "done");

    // Unknown documents and actions keep their error kinds.
    let r = c.call(json!({"t": "sub", "id": "x", "doc": "svc.nope"}));
    assert_eq!(r["t"], "err");
    assert_eq!(r["kind"], "unknown_doc");
    let r = c.call(json!({"t": "act", "id": "a8", "action": "no.such"}));
    assert_eq!(r["t"], "err");
    assert_eq!(r["kind"], "unknown_action");

    // The mock control for island faces reaches the document, transient faces included.
    c.send(&json!({"t": "mock.face", "face": "brightness"}));
    let isl = c.call(json!({"t": "sub", "id": "isl2", "doc": "runtime.island.main"}));
    assert_eq!(isl["data"]["face"], "brightness");
}

#[test]
fn instance_is_stable_within_a_process_and_new_for_the_next_one() {
    let (_mock, sock) = start_with("instance-a", &[]);
    let (_first, welcome) = Client::connect_welcome(&sock);
    let (_again, second) = Client::connect_welcome(&sock);
    let id = welcome["instance"].as_str().expect("instance").to_owned();
    assert!(!id.is_empty());
    assert_eq!(second["instance"], id.as_str());

    let (_other, sock_b) = start_with("instance-b", &[]);
    let (_, welcome_b) = Client::connect_welcome(&sock_b);
    assert_ne!(
        welcome_b["instance"],
        id.as_str(),
        "a new process, a new id"
    );
}

#[test]
fn fixed_time_serves_the_pinned_clock_and_nothing_ticks() {
    let (_mock, sock) = start_with("fixed", &["--fixed-time", "14:07"]);
    let mut c = Client::connect(&sock);
    let clock = c.call(json!({"t": "sub", "id": "clock", "doc": "svc.clock"}));
    assert_eq!(
        clock["data"],
        json!({"hh": "14", "mm": "07", "date": "2026-10-09", "weekday": "Fri"})
    );

    // Subscribed to the clock, the next patch this client sees must be the brightness step, so
    // no clock patch was queued behind it.
    c.call(json!({"t": "sub", "id": "br", "doc": "svc.brightness"}));
    c.send(&json!({"t": "act", "id": "b", "action": "brightness.up"}));
    let next = c.until(|m| m["t"] == "patch");
    assert_eq!(next["doc"], "svc.brightness");
}

#[test]
fn bad_fixed_time_is_refused_at_startup() {
    let sock = std::env::temp_dir().join(format!("kurashi-mock-badtime-{}", std::process::id()));
    let mut child = Command::new(env!("CARGO_BIN_EXE_kurashi-mock"))
        .arg("--socket")
        .arg(sock.join("ipc.sock"))
        .args(["--fixed-time", "25:00"])
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .spawn()
        .expect("spawn kurashi-mock");
    // Bounded: a mock that accepted the flag would run forever, so poll rather than wait.
    let deadline = Instant::now() + Duration::from_secs(10);
    let status = loop {
        if let Some(status) = child.try_wait().expect("poll kurashi-mock") {
            break status;
        }
        if Instant::now() > deadline {
            let _ = child.kill();
            let _ = child.wait();
            panic!("kurashi-mock kept running with --fixed-time 25:00");
        }
        std::thread::sleep(Duration::from_millis(20));
    };
    assert!(!status.success(), "a bad --fixed-time exits non-zero");
    let _ = std::fs::remove_dir_all(&sock);
}

#[test]
fn launcher_query_and_launch_over_the_wire() {
    let (_mock, sock) = start_with("launcher", &[]);
    let mut c = Client::connect(&sock);

    c.send(&json!({"t": "query", "id": "q1", "kind": "launcher", "q": "fire"}));
    let r = c.until(|m| m["id"] == "q1");
    assert_eq!(r["t"], "results");
    assert_eq!(r["items"][0]["id"], "firefox.desktop");

    let r = c.call(json!({"t": "query", "id": "q2", "kind": "nope", "q": ""}));
    assert_eq!(r["t"], "err");
    assert_eq!(r["kind"], "invalid");

    let r = c.call(json!({
        "t": "act", "id": "l1", "action": "launcher.launch", "args": {"id": "foot.desktop"}
    }));
    assert_eq!(r["t"], "done");
    let r = c.call(json!({
        "t": "act", "id": "l2", "action": "launcher.launch", "args": {"id": "nope.desktop"}
    }));
    assert_eq!(r["t"], "err");
    assert_eq!(r["kind"], "unavailable");
}

#[test]
fn notification_center_over_the_wire() {
    let (_mock, sock) = start_with("notify", &[]);
    // The watcher sees only what the document does, so its patch stream is easy to read.
    let mut watcher = Client::connect(&sock);
    let snap = watcher.call(json!({"t": "sub", "id": "n", "doc": "svc.notifications"}));
    assert_eq!(snap["t"], "snap");
    assert_eq!(snap["data"]["unread"], 2);

    let mut c = Client::connect(&sock);
    let r = c.call(json!({
        "t": "act", "id": "a1", "action": "mock.notify", "args": {"summary": "hello"}
    }));
    assert_eq!(r["t"], "done");
    assert_eq!(r["data"]["id"], 4);
    let patch = watcher.until(|m| m["t"] == "patch" && m["doc"] == "svc.notifications");
    assert_eq!(patch["ops"]["toasts"], json!([4]));

    let r = c.call(json!({
        "t": "act", "id": "a2", "action": "notify.dismiss", "args": {"id": 4}
    }));
    assert_eq!(r["t"], "done");
    let patch = watcher.until(|m| m["t"] == "patch" && m["doc"] == "svc.notifications");
    assert_eq!(patch["ops"]["toasts"], json!([]));
    assert_eq!(patch["ops"]["items"].as_array().map(Vec::len), Some(3));

    let r = c.call(json!({"t": "act", "id": "a3", "action": "notify.invoke", "args": {}}));
    assert_eq!(r["kind"], "invalid");
    assert_eq!(r["msg"], "notify.invoke needs id");
}

/// A host connection (MODS.md "Host processes", PROTOCOL §2): a token the daemon did not issue is
/// refused with `goodbye scope`; with a token it is limited to its mod, `theme` and `i18n`.
#[test]
fn a_host_connection_is_scoped_to_its_mod_over_the_wire() {
    let (_mock, sock) = start_with("scoped", &[]);
    let connect = |token: &str| {
        let tx = UnixStream::connect(&sock).expect("connect");
        tx.set_read_timeout(Some(Duration::from_secs(5)))
            .expect("read timeout");
        let rx = BufReader::new(tx.try_clone().expect("clone socket"));
        let mut c = Client { tx, rx };
        c.send(&json!({
            "t": "hello", "v": 1, "client": "webdock-host", "caps": ["intents"],
            "scope": {"mod": "webdock", "token": token}
        }));
        c
    };

    let mut refused = connect("bad");
    assert_eq!(
        refused.recv(),
        json!({"t": "goodbye", "reason": "scope", "supported": [1]})
    );

    let mut host = connect("6f1c2a9e4b7d0835");
    assert_eq!(host.recv()["t"], "welcome");
    assert_eq!(
        host.call(json!({"t": "sub", "id": "m", "doc": "mod.webdock"}))["t"],
        "snap"
    );
    assert_eq!(
        host.call(json!({"t": "sub", "id": "t", "doc": "theme"}))["t"],
        "snap"
    );
    let r = host.call(json!({"t": "sub", "id": "ui", "doc": "runtime.ui"}));
    assert_eq!(
        (r["t"].as_str(), r["kind"].as_str()),
        (Some("err"), Some("forbidden"))
    );
    let r = host.call(json!({"t": "act", "id": "a1", "action": "mock.webdock", "args": {}}));
    assert_eq!(r["kind"], "forbidden");
    let r = host.call(json!({"t": "act", "id": "a2", "action": "webdock.collapse", "args": {}}));
    assert_eq!(r["t"], "done", "its own actions pass");
    let snap = host.call(json!({"t": "sub", "id": "m2", "doc": "mod.webdock"}));
    assert_eq!(snap["data"]["mode"], "compact");
}

/// The web dock's document over the socket: a test sets pins (`mock.webdock`), the host's reports and
/// the shell's actions change it, and a bad target is refused with its key.
#[test]
fn the_web_dock_document_follows_the_actions_and_the_host_reports() {
    let (_mock, sock) = start_with("webdock", &[]);
    let mut c = Client::connect(&sock);
    let r = c.call(json!({"t": "act", "id": "a1", "action": "mock.webdock", "args": {
        "pins": [
            {"id": "mail", "kind": "web", "title": "Mail", "target": "file:///mail.html", "view": "mobile", "profile": "mail"},
            {"id": "weather", "kind": "view", "title": "Weather", "target": "mod:weather:weather"}
        ]
    }}));
    assert_eq!(r["t"], "done");
    let r =
        c.call(json!({"t": "act", "id": "a2", "action": "webdock.open", "args": {"pin": "mail"}}));
    assert_eq!(r["t"], "done");
    assert_eq!(
        c.call(json!({"t": "act", "id": "a3", "action": "webdock.host.loaded", "args": {"pin": "mail"}}))["t"],
        "done"
    );
    let snap = c.call(json!({"t": "sub", "id": "m", "doc": "mod.webdock"}));
    assert_eq!(snap["data"]["mode"], "extended");
    assert_eq!(snap["data"]["shown"], "mail");
    assert_eq!(snap["data"]["keep"], json!(["mail"]));
    assert_eq!(snap["data"]["pins"][0]["loaded"], true);
    let r =
        c.call(json!({"t": "act", "id": "a4", "action": "webdock.open", "args": {"pin": "nope"}}));
    assert_eq!(
        (r["kind"].as_str(), r["msg"].as_str()),
        (Some("invalid"), Some("webdock.error.unknown_pin"))
    );
}
