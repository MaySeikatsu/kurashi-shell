//! `svc.session` — logind session state, power commands, inhibitors.
//!
//! The session is addressed as `/org/freedesktop/login1/session/auto` (logind resolves it to the
//! caller's session), so we never need to look up the session id.

use std::sync::{Arc, Mutex};

use anyhow::Result;
use serde_json::{Value, json};
use zbus::message::Type as MsgType;
use zbus::zvariant::OwnedFd;
use zbus::{Connection, MatchRule};

use crate::util::{self, DocSink, Emitter, ServiceHandle};

pub(crate) const DEST: &str = "org.freedesktop.login1";
pub(crate) const MANAGER: &str = "/org/freedesktop/login1";
const MANAGER_IF: &str = "org.freedesktop.login1.Manager";
pub(crate) const SESSION: &str = "/org/freedesktop/login1/session/auto";
pub(crate) const SESSION_IF: &str = "org.freedesktop.login1.Session";

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

pub async fn start(conn: Connection, sink: Arc<dyn DocSink>) -> Result<(ServiceHandle, Commands)> {
    let sleep_rule = MatchRule::builder()
        .msg_type(MsgType::Signal)
        .interface(MANAGER_IF)?
        .member("PrepareForSleep")?
        .path(MANAGER)?
        .build();
    let events = util::watch(
        &conn,
        vec![
            util::props_changed("/org/freedesktop/login1")?,
            sleep_rule,
            util::name_owner_changed(DEST)?,
        ],
    )
    .await?;
    let em = Emitter::new(sink);
    let preparing = Arc::new(Mutex::new(false));
    em.emit(read(&conn, false).await);
    let task = {
        let conn = conn.clone();
        tokio::spawn(async move {
            util::follow(
                "session",
                &em,
                events,
                unavailable(),
                |msg: zbus::message::Message| {
                    let h = msg.header();
                    if h.member().is_some_and(|m| m.as_str() == "PrepareForSleep") {
                        if let Ok(b) = msg.body().deserialize::<bool>() {
                            *preparing.lock().unwrap() = b;
                        }
                    }
                    let p = *preparing.lock().unwrap();
                    read(&conn, p)
                },
            )
            .await;
        })
    };
    Ok((ServiceHandle::new(task), Commands { conn }))
}

/// The document while logind is not on the bus, does not answer for our session, or its signal
/// stream has ended. `available:false` says the hints are unknown: the values below are fillers and
/// must not read as real states (rule 2).
fn unavailable() -> Value {
    json!({
        "available": false,
        "idle_hint": false,
        "locked_hint": false,
        "preparing_for_sleep": false,
    })
}

async fn read(conn: &Connection, preparing: bool) -> Value {
    if !util::name_has_owner(conn, DEST).await {
        return unavailable();
    }
    let Some(p) = util::get_all(conn, DEST, SESSION, SESSION_IF).await else {
        return unavailable();
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
