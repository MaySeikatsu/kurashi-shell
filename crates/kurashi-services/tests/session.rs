mod common;

use std::sync::{Arc, Mutex};
use std::time::Duration;

use common::{
    FakeManager, FakeSession, FakeUser, LOGIND, LOGIND_MANAGER, Rec, SESSION_AUTO, TestBus,
    USER_SELF, assert_no_null, opath,
};
use kurashi_services::{ServiceHandle, session};
use serde_json::{Value, json};
use zbus::Connection;

const S1: &str = "/org/freedesktop/login1/session/_31";
const S2: &str = "/org/freedesktop/login1/session/_32";
const S3: &str = "/org/freedesktop/login1/session/_33";

fn unavailable_doc() -> Value {
    json!({"available": false, "idle_hint": false, "locked_hint": false, "preparing_for_sleep": false})
}

/// The document for an available session with the given idle hint.
fn doc(idle: bool) -> Value {
    json!({"available": true, "idle_hint": idle, "locked_hint": false, "preparing_for_sleep": false})
}

/// Serves the fake logind on the private bus. The returned connection keeps it alive.
async fn serve(
    bus: &TestBus,
    manager: FakeManager,
    user: FakeUser,
    sessions: &[(&str, FakeSession)],
) -> Connection {
    let srv = bus.server(LOGIND).await;
    srv.object_server()
        .at(LOGIND_MANAGER, manager)
        .await
        .unwrap();
    srv.object_server().at(USER_SELF, user).await.unwrap();
    for (path, session) in sessions {
        srv.object_server()
            .at(*path, session.clone())
            .await
            .unwrap();
    }
    srv
}

/// Starts the session document, with `xdg` as the caller's XDG_SESSION_ID.
async fn start(bus: &TestBus, xdg: Option<&str>) -> (ServiceHandle, Arc<Rec>) {
    let rec = Rec::new();
    let (handle, _cmds) =
        session::start_with_session_id(bus.conn().await, rec.clone(), xdg.map(str::to_owned))
            .await
            .unwrap();
    (handle, rec)
}

async fn set_idle(srv: &Connection, path: &str, idle: bool) {
    let s = srv
        .object_server()
        .interface::<_, FakeSession>(path)
        .await
        .unwrap();
    s.get_mut().await.idle = idle;
    s.get()
        .await
        .idle_hint_changed(s.signal_emitter())
        .await
        .unwrap();
}

async fn set_display(srv: &Connection, path: &str) {
    let u = srv
        .object_server()
        .interface::<_, FakeUser>(USER_SELF)
        .await
        .unwrap();
    u.get_mut().await.display = (String::new(), opath(path));
    u.get()
        .await
        .display_changed(u.signal_emitter())
        .await
        .unwrap();
}

#[tokio::test]
async fn session_lifecycle() {
    let bus = TestBus::start();
    let rec = Rec::new();
    let (handle, cmds) = session::start_with_session_id(bus.conn().await, rec.clone(), None)
        .await
        .unwrap();
    let d = rec.wait("initial", |_| true).await;
    assert_eq!(d, unavailable_doc());

    let calls = Arc::new(Mutex::new(vec![]));
    let srv = bus.server(LOGIND).await;
    srv.object_server()
        .at(
            LOGIND_MANAGER,
            FakeManager {
                calls: calls.clone(),
                ..Default::default()
            },
        )
        .await
        .unwrap();
    srv.object_server()
        .at(SESSION_AUTO, FakeSession::graphical(false))
        .await
        .unwrap();

    let s = srv
        .object_server()
        .interface::<_, FakeSession>(SESSION_AUTO)
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
    assert_eq!(d["available"], true);

    set_idle(&srv, SESSION_AUTO, true).await;
    rec.wait("idle", |d| d["idle_hint"] == true).await;

    let m = srv
        .object_server()
        .interface::<_, FakeManager>(LOGIND_MANAGER)
        .await
        .unwrap();
    FakeManager::prepare_for_sleep(m.signal_emitter(), true)
        .await
        .unwrap();
    rec.wait("preparing", |d| d["preparing_for_sleep"] == true)
        .await;
    FakeManager::prepare_for_sleep(m.signal_emitter(), false)
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

    // Owner disappears -> unavailable, not a session that is merely unlocked and active.
    drop((s, m));
    drop(srv);
    rec.wait("owner gone", |d| d["available"] == false).await;

    drop(handle);
    tokio::time::sleep(Duration::from_millis(100)).await;
    let n = rec.count();
    let srv = bus.server(LOGIND).await;
    srv.object_server()
        .at(
            SESSION_AUTO,
            FakeSession {
                locked: true,
                ..FakeSession::graphical(true)
            },
        )
        .await
        .unwrap();
    tokio::time::sleep(Duration::from_millis(300)).await;
    assert_eq!(rec.count(), n, "sink called after handle drop");
}

#[tokio::test]
async fn logind_without_our_session_is_unavailable() {
    // logind answers on the bus but has no session object for us: the hints are unknown, so the
    // document must not report idle=false as a fact. PrepareForSleep is a real signal from the
    // Manager, so it still shows.
    let bus = TestBus::start();
    let srv = bus.server(LOGIND).await;
    srv.object_server()
        .at(LOGIND_MANAGER, FakeManager::default())
        .await
        .unwrap();
    let m = srv
        .object_server()
        .interface::<_, FakeManager>(LOGIND_MANAGER)
        .await
        .unwrap();
    let (handle, rec) = start(&bus, None).await;
    let d = rec.wait("no session object", |_| true).await;
    assert_eq!(d["available"], false);

    FakeManager::prepare_for_sleep(m.signal_emitter(), true)
        .await
        .unwrap();
    let d = rec
        .wait("sleep without a session", |d| {
            d["preparing_for_sleep"] == true
        })
        .await;
    assert_eq!(d["available"], false);
    assert_eq!(d["idle_hint"], false);

    srv.object_server()
        .at(SESSION_AUTO, FakeSession::graphical(false))
        .await
        .unwrap();
    FakeManager::prepare_for_sleep(m.signal_emitter(), false)
        .await
        .unwrap();
    rec.wait("session readable", |d| {
        d["available"] == true && d["preparing_for_sleep"] == false
    })
    .await;
    drop(handle);
}

#[tokio::test]
async fn bus_gone_marks_unavailable() {
    // The daemon dies while logind is up: the signal stream ends, and the document must not keep
    // reporting a live session.
    let mut bus = TestBus::start();
    let srv = bus.server(LOGIND).await;
    srv.object_server()
        .at(SESSION_AUTO, FakeSession::graphical(true))
        .await
        .unwrap();
    let (handle, rec) = start(&bus, None).await;
    rec.wait("idle and available", |d| {
        d["available"] == true && d["idle_hint"] == true
    })
    .await;

    // The last live value (idle) must not survive into the unavailable document.
    bus.kill();
    let d = rec.wait("bus gone", |d| d["available"] == false).await;
    assert_eq!(d["idle_hint"], false);
    assert_no_null(&d);
    drop(handle);
}

#[tokio::test]
async fn display_session_is_used_without_xdg_session_id() {
    // (a) systemd --user: no XDG_SESSION_ID and no session/auto. The user's Display session answers.
    let bus = TestBus::start();
    let _srv = serve(
        &bus,
        FakeManager::default(),
        FakeUser::new(Some(S1), &[]),
        &[(S1, FakeSession::graphical(true))],
    )
    .await;
    let (handle, rec) = start(&bus, None).await;
    assert_eq!(rec.last().unwrap(), doc(true));
    drop(handle);
}

#[tokio::test]
async fn sessions_list_is_used_when_session_auto_is_unknown() {
    // (b) No Display session and no session/auto: the one graphical session in the list is found.
    let bus = TestBus::start();
    let _srv = serve(
        &bus,
        FakeManager::default(),
        FakeUser::new(None, &[S1]),
        &[(S1, FakeSession::graphical(true))],
    )
    .await;
    let (handle, rec) = start(&bus, None).await;
    assert_eq!(rec.last().unwrap(), doc(true));
    drop(handle);
}

#[tokio::test]
async fn nothing_matching_stays_unavailable() {
    // (c) No Display session. The listed sessions are a tty, a remote one and a greeter: none
    // qualifies, and session/auto is unknown, so the document is unavailable, as it was before.
    let bus = TestBus::start();
    let tty = FakeSession {
        kind: "tty".into(),
        ..FakeSession::graphical(false)
    };
    let remote = FakeSession {
        remote: true,
        ..FakeSession::graphical(false)
    };
    let greeter = FakeSession {
        class: "greeter".into(),
        ..FakeSession::graphical(false)
    };
    let _srv = serve(
        &bus,
        FakeManager::default(),
        FakeUser::new(None, &[S1, S2, S3]),
        &[(S1, tty), (S2, remote), (S3, greeter)],
    )
    .await;
    let (handle, rec) = start(&bus, None).await;
    assert_eq!(rec.last().unwrap(), unavailable_doc());
    drop(handle);
}

#[tokio::test]
async fn display_change_moves_the_document_to_the_new_session() {
    // (d) Display moves from S1 to S2. The document then follows S2's hints. Changes to the session
    // that is not shown do not change the document.
    let bus = TestBus::start();
    let srv = serve(
        &bus,
        FakeManager::default(),
        FakeUser::new(Some(S1), &[S1, S2]),
        &[
            (S1, FakeSession::graphical(false)),
            (S2, FakeSession::graphical(false)),
        ],
    )
    .await;
    let (handle, rec) = start(&bus, None).await;
    assert_eq!(rec.last().unwrap(), doc(false));

    set_idle(&srv, S2, true).await;
    tokio::time::sleep(Duration::from_millis(150)).await;
    assert_eq!(
        rec.last().unwrap(),
        doc(false),
        "S2 is not the session shown"
    );

    set_display(&srv, S2).await;
    rec.wait("S2 after Display moved", |d| d == &doc(true))
        .await;
    set_idle(&srv, S2, false).await;
    rec.wait("S2 changes followed", |d| d == &doc(false)).await;
    drop(handle);
}

#[tokio::test]
async fn xdg_session_id_wins_when_logind_knows_it() {
    // (e) $XDG_SESSION_ID comes first when logind knows it. An id logind does not know falls
    // through to the display session.
    let bus = TestBus::start();
    let manager = FakeManager::default();
    manager.known.lock().unwrap().insert("7".into(), S1.into());
    let _srv = serve(
        &bus,
        manager,
        FakeUser::new(Some(S2), &[S2]),
        &[
            (S1, FakeSession::graphical(true)),
            (S2, FakeSession::graphical(false)),
        ],
    )
    .await;

    let (known, rec) = start(&bus, Some("7")).await;
    assert_eq!(rec.last().unwrap(), doc(true));
    drop(known);

    let (unknown, rec) = start(&bus, Some("9")).await;
    assert_eq!(rec.last().unwrap(), doc(false));
    drop(unknown);
}

#[tokio::test]
async fn active_graphical_session_is_preferred_in_the_list() {
    // (f) Display unset. The tty is not graphical and the wayland session is not active. The
    // active x11 session is the one, although it comes last in the list.
    let bus = TestBus::start();
    let tty = FakeSession {
        kind: "tty".into(),
        ..FakeSession::graphical(false)
    };
    let inactive = FakeSession {
        active: false,
        ..FakeSession::graphical(false)
    };
    let active_x11 = FakeSession {
        kind: "x11".into(),
        ..FakeSession::graphical(true)
    };
    let _srv = serve(
        &bus,
        FakeManager::default(),
        FakeUser::new(None, &[S1, S2, S3]),
        &[(S1, tty), (S2, inactive), (S3, active_x11)],
    )
    .await;
    let (handle, rec) = start(&bus, None).await;
    assert_eq!(rec.last().unwrap(), doc(true));
    drop(handle);
}
