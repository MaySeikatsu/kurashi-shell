//! Private bus + recording sink. Nothing here ever touches the user's real session/system bus.
#![allow(dead_code)]

use std::collections::HashMap;
use std::io::{BufRead, BufReader};
use std::process::{Child, Command, Stdio};
use std::sync::{Arc, Mutex};
use std::time::Duration;

use kurashi_services::DocSink;
use serde_json::Value;
use zbus::Connection;
use zbus::zvariant::OwnedObjectPath;

pub struct TestBus {
    child: Child,
    pub addr: String,
    _dir: tempfile::TempDir,
}

impl TestBus {
    pub fn start() -> Self {
        let dir = tempfile::tempdir().unwrap();
        let conf = dir.path().join("bus.conf");
        std::fs::write(
            &conf,
            format!(
                r#"<busconfig><type>session</type>
<listen>unix:tmpdir={}</listen><auth>EXTERNAL</auth>
<policy context="default"><allow send_destination="*" eavesdrop="true"/><allow eavesdrop="true"/><allow own="*"/></policy>
</busconfig>"#,
                dir.path().display()
            ),
        )
        .unwrap();
        let mut child = Command::new("dbus-daemon")
            .arg(format!("--config-file={}", conf.display()))
            .args(["--nofork", "--print-address"])
            .stdout(Stdio::piped())
            .spawn()
            .expect("dbus-daemon (run inside nix develop)");
        let mut addr = String::new();
        BufReader::new(child.stdout.as_mut().unwrap())
            .read_line(&mut addr)
            .unwrap();
        Self {
            child,
            addr: addr.trim().to_owned(),
            _dir: dir,
        }
    }

    pub async fn conn(&self) -> Connection {
        zbus::connection::Builder::address(self.addr.as_str())
            .unwrap()
            .build()
            .await
            .unwrap()
    }

    /// A connection that also owns `name`, for serving fake objects.
    pub async fn server(&self, name: &str) -> Connection {
        let c = self.conn().await;
        c.request_name(name.to_owned()).await.unwrap();
        c
    }
}

impl TestBus {
    /// Kills the daemon: every connection on this private bus sees its socket close.
    pub fn kill(&mut self) {
        let _ = self.child.kill();
        let _ = self.child.wait();
    }
}

impl Drop for TestBus {
    fn drop(&mut self) {
        self.kill();
    }
}

#[derive(Default)]
pub struct Rec(Mutex<Vec<Value>>);

impl DocSink for Rec {
    fn set(&self, doc: Value) {
        self.0.lock().unwrap().push(doc);
    }
}

impl Rec {
    pub fn new() -> Arc<Self> {
        Arc::default()
    }
    pub fn count(&self) -> usize {
        self.0.lock().unwrap().len()
    }
    pub fn last(&self) -> Option<Value> {
        self.0.lock().unwrap().last().cloned()
    }
    /// Wait until the latest document satisfies `pred`; panic with the last doc on timeout.
    pub async fn wait(&self, what: &str, pred: impl Fn(&Value) -> bool) -> Value {
        for _ in 0..200 {
            if let Some(d) = self.last().filter(|d| pred(d)) {
                return d;
            }
            tokio::time::sleep(Duration::from_millis(25)).await;
        }
        panic!("timed out waiting for {what}; last doc: {:?}", self.last());
    }
}

/// Documents must never contain null (PROTOCOL §3).
pub fn assert_no_null(v: &Value) {
    match v {
        Value::Null => panic!("null in document"),
        Value::Array(a) => a.iter().for_each(assert_no_null),
        Value::Object(o) => o.values().for_each(assert_no_null),
        _ => {}
    }
}

// ---- Fake logind (session tests) ------------------------------------------------------------------
// A Manager, the calling user's object (`user/self`) and Session objects, shaped like logind's
// answers. A test changes a field and emits the matching `*_changed` signal, as logind does.

pub const LOGIND: &str = "org.freedesktop.login1";
pub const LOGIND_MANAGER: &str = "/org/freedesktop/login1";
pub const SESSION_AUTO: &str = "/org/freedesktop/login1/session/auto";
pub const USER_SELF: &str = "/org/freedesktop/login1/user/self";

/// An object path from a test literal.
pub fn opath(path: &str) -> OwnedObjectPath {
    OwnedObjectPath::try_from(path.to_owned()).unwrap()
}

/// `org.freedesktop.login1.Manager`: records the commands; `GetSession` knows the ids in `known`.
#[derive(Default)]
pub struct FakeManager {
    pub calls: Arc<Mutex<Vec<String>>>,
    /// Session id -> object path. Any other id is an error, as in logind.
    pub known: Arc<Mutex<HashMap<String, String>>>,
}

#[zbus::interface(name = "org.freedesktop.login1.Manager")]
impl FakeManager {
    fn get_session(&self, id: String) -> zbus::fdo::Result<OwnedObjectPath> {
        match self.known.lock().unwrap().get(&id) {
            Some(path) => Ok(opath(path)),
            None => Err(zbus::fdo::Error::Failed(format!("No session '{id}' known"))),
        }
    }
    fn lock_sessions(&self) {
        self.calls.lock().unwrap().push("LockSessions".into());
    }
    fn suspend(&self, interactive: bool) {
        self.calls
            .lock()
            .unwrap()
            .push(format!("Suspend {interactive}"));
    }
    fn reboot(&self, _i: bool) {
        self.calls.lock().unwrap().push("Reboot".into());
    }
    fn power_off(&self, _i: bool) {
        self.calls.lock().unwrap().push("PowerOff".into());
    }
    fn inhibit(
        &self,
        what: String,
        _who: String,
        _why: String,
        mode: String,
    ) -> zbus::zvariant::OwnedFd {
        self.calls
            .lock()
            .unwrap()
            .push(format!("Inhibit {what} {mode}"));
        let f = std::fs::File::open("/dev/null").unwrap();
        zbus::zvariant::OwnedFd::from(std::os::fd::OwnedFd::from(f))
    }
    #[zbus(signal)]
    pub async fn prepare_for_sleep(
        emitter: &zbus::object_server::SignalEmitter<'_>,
        start: bool,
    ) -> zbus::Result<()>;
}

/// `org.freedesktop.login1.Session`. The fields are the properties.
#[derive(Clone, Debug)]
pub struct FakeSession {
    pub idle: bool,
    pub locked: bool,
    /// `Type`: "wayland", "x11", "tty", ...
    pub kind: String,
    /// `Class`: "user", "greeter", ...
    pub class: String,
    pub remote: bool,
    pub active: bool,
}

impl FakeSession {
    /// A local, active wayland user session: the kind of session the service should pick.
    pub fn graphical(idle: bool) -> Self {
        Self {
            idle,
            locked: false,
            kind: "wayland".into(),
            class: "user".into(),
            remote: false,
            active: true,
        }
    }
}

#[zbus::interface(name = "org.freedesktop.login1.Session")]
impl FakeSession {
    #[zbus(property)]
    fn idle_hint(&self) -> bool {
        self.idle
    }
    #[zbus(property)]
    fn locked_hint(&self) -> bool {
        self.locked
    }
    #[zbus(property, name = "Type")]
    fn kind_prop(&self) -> String {
        self.kind.clone()
    }
    #[zbus(property, name = "Class")]
    fn class_prop(&self) -> String {
        self.class.clone()
    }
    #[zbus(property, name = "Remote")]
    fn remote_prop(&self) -> bool {
        self.remote
    }
    #[zbus(property, name = "Active")]
    fn active_prop(&self) -> bool {
        self.active
    }
}

/// `org.freedesktop.login1.User` at `user/self`: the calling user's display session and sessions.
#[derive(Clone, Debug)]
pub struct FakeUser {
    /// `Display`: (session id, object path); the root path when there is no display session.
    pub display: (String, OwnedObjectPath),
    /// `Sessions`: (session id, object path) for each session of the user.
    pub sessions: Vec<(String, OwnedObjectPath)>,
}

impl FakeUser {
    /// `display` None is logind's "no display session".
    pub fn new(display: Option<&str>, sessions: &[&str]) -> Self {
        Self {
            display: (String::new(), opath(display.unwrap_or("/"))),
            sessions: sessions
                .iter()
                .map(|path| (String::new(), opath(path)))
                .collect(),
        }
    }
}

#[zbus::interface(name = "org.freedesktop.login1.User")]
impl FakeUser {
    #[zbus(property, name = "Display")]
    fn display_prop(&self) -> (String, OwnedObjectPath) {
        self.display.clone()
    }
    #[zbus(property, name = "Sessions")]
    fn sessions_prop(&self) -> Vec<(String, OwnedObjectPath)> {
        self.sessions.clone()
    }
}
