//! Brightness writes reach the graphical session, not `session/auto` (B3). Private bus, fake logind.
mod common;

use std::path::PathBuf;
use std::sync::atomic::{AtomicUsize, Ordering};
use std::sync::{Arc, Mutex};

use common::{LOGIND, SESSION_AUTO, TestBus, USER_SELF, opath};
use kurashi_services::brightness::{self, Change, SessionCache};
use serde_json::Value;
use zbus::Connection;
use zbus::zvariant::OwnedObjectPath;

const C2: &str = "/org/freedesktop/login1/session/c2";
const C3: &str = "/org/freedesktop/login1/session/c3";

/// A session that takes `SetBrightness` as logind does, and logs which session got the write. Its
/// properties make it a graphical session for the resolver.
struct Session {
    name: &'static str,
    dir: PathBuf,
    log: Arc<Mutex<Vec<String>>>,
}

#[zbus::interface(name = "org.freedesktop.login1.Session")]
impl Session {
    fn set_brightness(&self, subsystem: String, name: String, value: u32) {
        self.log
            .lock()
            .unwrap()
            .push(format!("{} {subsystem} {name} {value}", self.name));
        std::fs::write(self.dir.join(name).join("brightness"), value.to_string()).unwrap();
    }
    #[zbus(property, name = "Type")]
    fn kind(&self) -> String {
        "wayland".into()
    }
    #[zbus(property, name = "Class")]
    fn class(&self) -> String {
        "user".into()
    }
    #[zbus(property, name = "Remote")]
    fn remote(&self) -> bool {
        false
    }
    #[zbus(property, name = "Active")]
    fn active(&self) -> bool {
        true
    }
}

/// `user/self`: `Display` is whatever the test sets. Every GetAll of the object is counted. A
/// resolution that finds a display session makes exactly one, so the count tells it from a cache
/// hit.
struct User {
    display: Arc<Mutex<OwnedObjectPath>>,
    reads: Arc<AtomicUsize>,
}

#[zbus::interface(name = "org.freedesktop.login1.User")]
impl User {
    #[zbus(property, name = "Display")]
    fn display_prop(&self) -> (String, OwnedObjectPath) {
        self.reads.fetch_add(1, Ordering::SeqCst);
        (String::new(), self.display.lock().unwrap().clone())
    }
    #[zbus(property, name = "Sessions")]
    fn sessions_prop(&self) -> Vec<(String, OwnedObjectPath)> {
        Vec::new()
    }
}

/// A private bus with the fake logind (`user/self` shows `display`; `auto`, c2 and c3 take writes)
/// and a backlight at 50 of 100.
struct Rig {
    bus: TestBus,
    dir: PathBuf,
    _tmp: tempfile::TempDir,
    /// Keeps the fake logind on the bus.
    srv: Connection,
    log: Arc<Mutex<Vec<String>>>,
    display: Arc<Mutex<OwnedObjectPath>>,
    reads: Arc<AtomicUsize>,
}

impl Rig {
    async fn start(display: &str) -> Self {
        let bus = TestBus::start();
        let tmp = tempfile::tempdir().unwrap();
        let dev = tmp.path().join("intel_backlight");
        std::fs::create_dir(&dev).unwrap();
        std::fs::write(dev.join("max_brightness"), "100\n").unwrap();
        std::fs::write(dev.join("brightness"), "50\n").unwrap();
        let log = Arc::new(Mutex::new(Vec::new()));
        let display = Arc::new(Mutex::new(opath(display)));
        let reads = Arc::new(AtomicUsize::new(0));
        let srv = bus.server(LOGIND).await;
        srv.object_server()
            .at(
                USER_SELF,
                User {
                    display: display.clone(),
                    reads: reads.clone(),
                },
            )
            .await
            .unwrap();
        for (path, name) in [(SESSION_AUTO, "auto"), (C2, "c2"), (C3, "c3")] {
            let session = Session {
                name,
                dir: tmp.path().to_owned(),
                log: log.clone(),
            };
            srv.object_server().at(path, session).await.unwrap();
        }
        Self {
            bus,
            dir: tmp.path().to_owned(),
            _tmp: tmp,
            srv,
            log,
            display,
            reads,
        }
    }

    /// One write the way the daemon makes it: a fresh connection, then the plan's apply.
    async fn write(&self, cache: &SessionCache, fraction: f64) -> zbus::Result<Value> {
        let plan = brightness::plan(&self.dir, Change::To(fraction)).unwrap();
        plan.apply_with(&self.bus.conn().await, cache, None).await
    }
}

#[tokio::test]
async fn write_goes_to_the_display_session_not_auto() {
    let rig = Rig::start(C2).await;
    let doc = rig.write(&SessionCache::default(), 0.8).await.unwrap();
    assert_eq!(
        *rig.log.lock().unwrap(),
        ["c2 backlight intel_backlight 80"]
    );
    assert_eq!(doc["value"], 80);
}

#[tokio::test]
async fn cached_session_that_is_gone_is_resolved_once() {
    let rig = Rig::start(C2).await;
    let cache = SessionCache::default();

    rig.write(&cache, 0.8).await.unwrap();
    assert_eq!(rig.reads.load(Ordering::SeqCst), 1);

    // Display moves, but the cached session still answers: no resolution, the write stays on c2.
    *rig.display.lock().unwrap() = opath(C3);
    rig.write(&cache, 0.6).await.unwrap();
    assert_eq!(rig.reads.load(Ordering::SeqCst), 1);

    // c2 goes away: the write fails on it once, resolves once more to c3, and lands there.
    rig.srv
        .object_server()
        .remove::<Session, _>(C2)
        .await
        .unwrap();
    let doc = rig.write(&cache, 0.4).await.unwrap();
    assert_eq!(rig.reads.load(Ordering::SeqCst), 2);
    assert_eq!(doc["value"], 40);

    // c3 is the cached session now.
    rig.write(&cache, 0.2).await.unwrap();
    assert_eq!(rig.reads.load(Ordering::SeqCst), 2);
    assert_eq!(
        *rig.log.lock().unwrap(),
        [
            "c2 backlight intel_backlight 80",
            "c2 backlight intel_backlight 60",
            "c3 backlight intel_backlight 40",
            "c3 backlight intel_backlight 20",
        ]
    );
}

#[tokio::test]
async fn without_a_display_session_writes_fall_back_to_auto_and_ask_again() {
    let rig = Rig::start("/").await;
    let cache = SessionCache::default();

    // The fallback is not kept, so the write after a display session appears finds it. A kept
    // `auto` would send that write to auto too.
    rig.write(&cache, 0.8).await.unwrap();
    rig.write(&cache, 0.6).await.unwrap();
    *rig.display.lock().unwrap() = opath(C2);
    rig.write(&cache, 0.4).await.unwrap();
    assert_eq!(
        *rig.log.lock().unwrap(),
        [
            "auto backlight intel_backlight 80",
            "auto backlight intel_backlight 60",
            "c2 backlight intel_backlight 40",
        ]
    );
}
