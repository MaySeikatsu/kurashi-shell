mod common;

use std::sync::{Arc, Mutex};
use std::time::Duration;

use common::{Rec, TestBus, assert_no_null};
use kurashi_services::session;

struct Manager {
    calls: Arc<Mutex<Vec<String>>>,
}
#[zbus::interface(name = "org.freedesktop.login1.Manager")]
impl Manager {
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
    async fn prepare_for_sleep(
        emitter: &zbus::object_server::SignalEmitter<'_>,
        start: bool,
    ) -> zbus::Result<()>;
}

struct Sess {
    idle: bool,
    locked: bool,
}
#[zbus::interface(name = "org.freedesktop.login1.Session")]
impl Sess {
    #[zbus(property)]
    fn idle_hint(&self) -> bool {
        self.idle
    }
    #[zbus(property)]
    fn locked_hint(&self) -> bool {
        self.locked
    }
}

const SESSION: &str = "/org/freedesktop/login1/session/auto";

#[tokio::test]
async fn session_lifecycle() {
    let bus = TestBus::start();
    let rec = Rec::new();
    let (handle, cmds) = session::start(bus.conn().await, rec.clone()).await.unwrap();
    let d = rec.wait("initial", |_| true).await;
    assert_eq!(
        d,
        serde_json::json!({"idle_hint": false, "locked_hint": false, "preparing_for_sleep": false})
    );

    let calls = Arc::new(Mutex::new(vec![]));
    let srv = bus.server("org.freedesktop.login1").await;
    srv.object_server()
        .at(
            "/org/freedesktop/login1",
            Manager {
                calls: calls.clone(),
            },
        )
        .await
        .unwrap();
    srv.object_server()
        .at(
            SESSION,
            Sess {
                idle: false,
                locked: false,
            },
        )
        .await
        .unwrap();

    let s = srv
        .object_server()
        .interface::<_, Sess>(SESSION)
        .await
        .unwrap();
    s.get_mut().await.locked = true;
    s.get()
        .await
        .locked_hint_changed(s.signal_emitter())
        .await
        .unwrap();
    let d = rec.wait("locked", |d| d["locked_hint"] == true).await;
    assert_no_null(&d);

    s.get_mut().await.idle = true;
    s.get()
        .await
        .idle_hint_changed(s.signal_emitter())
        .await
        .unwrap();
    rec.wait("idle", |d| d["idle_hint"] == true).await;

    let m = srv
        .object_server()
        .interface::<_, Manager>("/org/freedesktop/login1")
        .await
        .unwrap();
    Manager::prepare_for_sleep(m.signal_emitter(), true)
        .await
        .unwrap();
    rec.wait("preparing", |d| d["preparing_for_sleep"] == true)
        .await;
    Manager::prepare_for_sleep(m.signal_emitter(), false)
        .await
        .unwrap();
    rec.wait("resumed", |d| d["preparing_for_sleep"] == false)
        .await;

    // Commands (private bus only) and the inhibitor fd guard.
    cmds.lock().await.unwrap();
    cmds.suspend().await.unwrap();
    cmds.reboot().await.unwrap();
    cmds.poweroff().await.unwrap();
    let guard = cmds
        .inhibit("sleep", "kurashi", "test", "block")
        .await
        .unwrap();
    drop(guard);
    assert_eq!(
        *calls.lock().unwrap(),
        vec![
            "LockSessions",
            "Suspend false",
            "Reboot",
            "PowerOff",
            "Inhibit sleep block"
        ]
    );

    // Owner disappears -> defaults.
    drop((s, m));
    drop(srv);
    rec.wait("owner gone", |d| {
        d["idle_hint"] == false && d["locked_hint"] == false
    })
    .await;

    drop(handle);
    tokio::time::sleep(Duration::from_millis(100)).await;
    let n = rec.count();
    let srv = bus.server("org.freedesktop.login1").await;
    srv.object_server()
        .at(
            SESSION,
            Sess {
                idle: true,
                locked: true,
            },
        )
        .await
        .unwrap();
    tokio::time::sleep(Duration::from_millis(300)).await;
    assert_eq!(rec.count(), n, "sink called after handle drop");
}
