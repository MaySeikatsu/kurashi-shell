//! `svc.session` — logind session state, power commands, inhibitors.
//!
//! The document describes the user's graphical session. A `systemd --user` service (how the HM
//! module runs kurashid) belongs to no session, so `session/auto` answers nothing there. The session
//! is therefore resolved explicitly, in this order, and again when logind restarts or the user's
//! `Display` session moves:
//!   1. `$XDG_SESSION_ID`, when logind knows it (`GetSession`);
//!   2. the user's `Display` session (`/org/freedesktop/login1/user/self`);
//!   3. the first of the user's `Sessions` that is a local wayland/x11 user session, not remote,
//!      an active one preferred;
//!   4. `session/auto`, the caller's own session where logind can tell it.
//!
//! A candidate counts only if its Session object answers, so the document never describes a session
//! logind has already dropped.

use std::sync::Arc;

use anyhow::Result;
use futures_util::StreamExt;
use serde_json::{Value, json};
use zbus::message::Type as MsgType;
use zbus::zvariant::{OwnedFd, OwnedObjectPath};
use zbus::{Connection, MatchRule};

use crate::util::{self, DocSink, Emitter, ServiceHandle};

pub(crate) const DEST: &str = "org.freedesktop.login1";
pub(crate) const MANAGER: &str = "/org/freedesktop/login1";
const MANAGER_IF: &str = "org.freedesktop.login1.Manager";
pub(crate) const SESSION: &str = "/org/freedesktop/login1/session/auto";
pub(crate) const SESSION_IF: &str = "org.freedesktop.login1.Session";
/// The calling user's object; logind accepts `self` in place of the uid.
const USER_SELF: &str = "/org/freedesktop/login1/user/self";
const USER_NS: &str = "/org/freedesktop/login1/user";
const USER_IF: &str = "org.freedesktop.login1.User";

/// Held inhibitor lock; dropping it closes the fd and releases the lock.
pub struct InhibitorGuard(#[allow(dead_code)] OwnedFd);

#[derive(Clone)]
pub struct Commands {
    conn: Connection,
}

impl Commands {
    // These change real system state. Tests exercise them only against a private bus.
    pub async fn lock(&self) -> zbus::Result<()> {
        util::call(&self.conn, DEST, MANAGER, MANAGER_IF, "LockSessions", &()).await?;
        Ok(())
    }
    pub async fn suspend(&self) -> zbus::Result<()> {
        util::call(&self.conn, DEST, MANAGER, MANAGER_IF, "Suspend", &(false,)).await?;
        Ok(())
    }
    pub async fn reboot(&self) -> zbus::Result<()> {
        util::call(&self.conn, DEST, MANAGER, MANAGER_IF, "Reboot", &(false,)).await?;
        Ok(())
    }
    pub async fn poweroff(&self) -> zbus::Result<()> {
        util::call(&self.conn, DEST, MANAGER, MANAGER_IF, "PowerOff", &(false,)).await?;
        Ok(())
    }
    /// `what` e.g. "sleep:idle", `mode` "block" or "delay".
    pub async fn inhibit(
        &self,
        what: &str,
        who: &str,
        why: &str,
        mode: &str,
    ) -> zbus::Result<InhibitorGuard> {
        let reply = util::call(
            &self.conn,
            DEST,
            MANAGER,
            MANAGER_IF,
            "Inhibit",
            &(what, who, why, mode),
        )
        .await?;
        let fd: OwnedFd = reply.body().deserialize()?;
        Ok(InhibitorGuard(fd))
    }
}

/// Starts the session document. `XDG_SESSION_ID` is read once, here.
pub async fn start(conn: Connection, sink: Arc<dyn DocSink>) -> Result<(ServiceHandle, Commands)> {
    start_with_session_id(conn, sink, std::env::var("XDG_SESSION_ID").ok()).await
}

/// [`start`] with the caller's `XDG_SESSION_ID` passed in. Tests use this: edition 2024 makes
/// `set_var` unsafe, and a test run must not pick up the session it happens to run in.
#[doc(hidden)]
pub async fn start_with_session_id(
    conn: Connection,
    sink: Arc<dyn DocSink>,
    xdg_session_id: Option<String>,
) -> Result<(ServiceHandle, Commands)> {
    // The bus-wide rules are registered before the first resolution, so a change in between is
    // seen by the loop instead of lost (the rule util::watch states).
    let statics = util::watch(
        &conn,
        vec![
            sleep_rule()?,
            util::name_owner_changed(DEST)?,
            util::props_changed(USER_NS)?,
        ],
    )
    .await?;
    let (path, events) = attach(&conn, xdg_session_id.as_deref()).await?;
    let tracker = Tracker {
        conn: conn.clone(),
        em: Emitter::new(sink),
        xdg_session_id,
        statics,
        events,
        path,
        preparing: false,
    };
    tracker.emit().await;
    let task = tokio::spawn(tracker.run());
    Ok((ServiceHandle::new(task), Commands { conn }))
}

/// The session subscription and the state the document is built from. The task owns it. The
/// bus-wide rules live for its whole life; the session subscription is replaced when the resolved
/// session changes, so only that session's PropertiesChanged wakes the document (Ma).
struct Tracker {
    conn: Connection,
    em: Arc<Emitter>,
    xdg_session_id: Option<String>,
    /// PrepareForSleep, logind restarts, and the user's `Display` moving.
    statics: util::Events,
    /// PropertiesChanged of the resolved session object only.
    events: util::Events,
    path: String,
    preparing: bool,
}

impl Tracker {
    async fn run(mut self) {
        loop {
            let (bus_wide, ev) = tokio::select! {
                ev = self.statics.next() => (true, ev),
                ev = self.events.next() => (false, ev),
            };
            // An error or an ended stream: the bus is gone, and nothing past it is asked of the bus.
            let Some(Ok(msg)) = ev else { break };
            if bus_wide {
                match classify(&msg) {
                    Change::Ignore => continue,
                    Change::Sleep(preparing) => self.preparing = preparing,
                    Change::Reresolve => {
                        match attach(&self.conn, self.xdg_session_id.as_deref()).await {
                            // The new subscription exists before the old one is dropped, so a
                            // change between the two is not missed.
                            Ok((path, events)) => {
                                self.path = path;
                                self.events = events;
                            }
                            Err(_) => break,
                        }
                    }
                }
            }
            self.emit().await;
        }
        util::ended("session", &self.em, unavailable());
    }

    async fn emit(&self) {
        self.em
            .emit(read(&self.conn, &self.path, self.preparing).await);
    }
}

/// What a bus-wide signal means for the document.
enum Change {
    /// PrepareForSleep, with its new value.
    Sleep(bool),
    /// The resolved session may have moved: logind restarted, or the user's `Display` changed.
    Reresolve,
    /// Anything else (e.g. another user object's idle state): the document does not depend on it.
    Ignore,
}

fn classify(msg: &zbus::Message) -> Change {
    let Some(member) = msg.header().member().map(|m| m.as_str().to_owned()) else {
        return Change::Ignore;
    };
    match member.as_str() {
        "PrepareForSleep" => msg
            .body()
            .deserialize::<bool>()
            .map_or(Change::Ignore, Change::Sleep),
        "NameOwnerChanged" => Change::Reresolve,
        "PropertiesChanged" if display_changed(msg) => Change::Reresolve,
        _ => Change::Ignore,
    }
}

/// Whether a user object's PropertiesChanged moved `Display`, by value or by invalidation.
fn display_changed(msg: &zbus::Message) -> bool {
    let Ok((iface, changed, invalidated)) = msg
        .body()
        .deserialize::<(String, util::Props, Vec<String>)>()
    else {
        return false;
    };
    iface == USER_IF
        && (changed.contains_key("Display") || invalidated.iter().any(|p| p == "Display"))
}

/// Resolves the session and subscribes to its PropertiesChanged. The caller reads the document only
/// after this returns, so a change in between is seen by the subscription.
async fn attach(conn: &Connection, xdg_session_id: Option<&str>) -> Result<(String, util::Events)> {
    let path = resolve(conn, xdg_session_id).await;
    let events = util::watch(conn, vec![session_rule(&path)?]).await?;
    Ok((path, events))
}

fn sleep_rule() -> Result<MatchRule<'static>> {
    Ok(MatchRule::builder()
        .msg_type(MsgType::Signal)
        .interface(MANAGER_IF)?
        .member("PrepareForSleep")?
        .path(MANAGER)?
        .build())
}

/// PropertiesChanged of one session object: its hints, and nothing else.
fn session_rule(path: &str) -> Result<MatchRule<'static>> {
    Ok(MatchRule::builder()
        .msg_type(MsgType::Signal)
        .interface("org.freedesktop.DBus.Properties")?
        .member("PropertiesChanged")?
        .path(path.to_owned())?
        .build())
}

/// The session object the document describes (the order is in the module doc).
async fn resolve(conn: &Connection, xdg_session_id: Option<&str>) -> String {
    if !util::name_has_owner(conn, DEST).await {
        // Nothing to ask. `read` gives the unavailable document for this path.
        return SESSION.to_owned();
    }
    if let Some(path) = session_by_id(conn, xdg_session_id).await {
        return path;
    }
    if let Some(path) = display_session(conn).await {
        return path;
    }
    if let Some(path) = user_session(conn).await {
        return path;
    }
    SESSION.to_owned()
}

/// `GetSession` for `$XDG_SESSION_ID`. logind answers an error for an id it does not know.
async fn session_by_id(conn: &Connection, id: Option<&str>) -> Option<String> {
    let id = id.filter(|id| !id.is_empty())?;
    let reply = util::call(conn, DEST, MANAGER, MANAGER_IF, "GetSession", &(id,))
        .await
        .ok()?;
    let path: OwnedObjectPath = reply.body().deserialize().ok()?;
    if_answers(conn, path.as_str()).await
}

/// The user's `Display` session. logind reports "no display session" as the root path.
async fn display_session(conn: &Connection) -> Option<String> {
    let props = util::get_all(conn, DEST, USER_SELF, USER_IF).await?;
    let (_id, path): (String, OwnedObjectPath) = util::prop(&props, "Display")?;
    if path.as_str() == "/" {
        return None;
    }
    if_answers(conn, path.as_str()).await
}

/// The first of the user's sessions that is a local graphical user session; an active one wins.
async fn user_session(conn: &Connection) -> Option<String> {
    let props = util::get_all(conn, DEST, USER_SELF, USER_IF).await?;
    let sessions: Vec<(String, OwnedObjectPath)> = util::prop(&props, "Sessions")?;
    let mut first: Option<String> = None;
    for (_id, path) in sessions {
        let Some(s) = util::get_all(conn, DEST, path.as_str(), SESSION_IF).await else {
            continue;
        };
        let kind: String = util::prop(&s, "Type").unwrap_or_default();
        let class: String = util::prop(&s, "Class").unwrap_or_default();
        let remote: bool = util::prop(&s, "Remote").unwrap_or(true);
        if !matches!(kind.as_str(), "wayland" | "x11") || class != "user" || remote {
            continue;
        }
        if util::prop(&s, "Active").unwrap_or(false) {
            return Some(path.as_str().to_owned());
        }
        if first.is_none() {
            first = Some(path.as_str().to_owned());
        }
    }
    first
}

/// `path` if its Session object answers on the bus.
async fn if_answers(conn: &Connection, path: &str) -> Option<String> {
    util::get_all(conn, DEST, path, SESSION_IF)
        .await
        .map(|_| path.to_owned())
}

/// The unavailable document. Used while logind is not on the bus, or once its signal stream has
/// ended. Nothing is known then: `available:false` makes the values fillers, which must not read as
/// real states (rule 2).
fn unavailable() -> Value {
    json!({
        "available": false,
        "idle_hint": false,
        "locked_hint": false,
        "preparing_for_sleep": false,
    })
}

/// The document for the session at `path`. Only what logind answers is reported.
async fn read(conn: &Connection, path: &str, preparing: bool) -> Value {
    if !util::name_has_owner(conn, DEST).await {
        return unavailable();
    }
    let Some(p) = util::get_all(conn, DEST, path, SESSION_IF).await else {
        // logind is up but does not answer for this session. The hints are unknown, but
        // PrepareForSleep comes from the Manager and is real.
        return json!({
            "available": false,
            "idle_hint": false,
            "locked_hint": false,
            "preparing_for_sleep": preparing,
        });
    };
    let idle = util::prop(&p, "IdleHint").unwrap_or(false);
    let locked = util::prop(&p, "LockedHint").unwrap_or(false);
    json!({
        "available": true,
        "idle_hint": idle,
        "locked_hint": locked,
        "preparing_for_sleep": preparing,
    })
}
