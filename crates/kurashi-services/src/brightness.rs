//! `svc.brightness` — backlight via sysfs (read) and logind `SetBrightness` (write).
//!
//! Deviation, by design: this service is **read-on-demand**. sysfs offers no cheap change
//! notification without a udev netlink socket (needs libudev bindings), and polling is forbidden
//! (rule 5). So the document is emitted at start and after our own `set_percent`/`refresh`;
//! changes made by other tools show up on the next `refresh()` (e.g. when the panel opens).
//! The key actions go through [`plan`] and [`Plan::apply`] instead, which need no subscription.
//!
//! Writes go to the user's graphical session, resolved the way `svc.session` resolves it, and not
//! to `session/auto`: a `systemd --user` daemon belongs to no session, so `auto` answers nothing.

use std::path::{Path, PathBuf};
use std::sync::{Arc, Mutex, PoisonError};

use anyhow::Result;
use serde_json::{Value, json};
use zbus::Connection;

use crate::session::{DEST, SESSION, SESSION_IF, resolve_session_path};
use crate::util::{self, DocSink, Emitter, ServiceHandle};

pub const DEFAULT_DIR: &str = "/sys/class/backlight";

#[derive(Clone)]
pub struct Commands {
    conn: Connection,
    dir: PathBuf,
    em: Arc<Emitter>,
}

impl Commands {
    /// Re-read sysfs and emit (no-op if unchanged).
    pub fn refresh(&self) {
        self.em.emit(read(&self.dir));
    }
    /// Set brightness through logind (no root needed), then emit the level now in effect.
    /// Without a device there is nothing to set.
    pub async fn set_percent(&self, percent: f64) -> zbus::Result<()> {
        if let Some(p) = plan(&self.dir, Change::To(percent / 100.0)) {
            self.em.emit(p.apply(&self.conn).await?);
        }
        Ok(())
    }
}

pub async fn start(conn: Connection, sink: Arc<dyn DocSink>) -> Result<(ServiceHandle, Commands)> {
    start_at(conn, sink, DEFAULT_DIR.into()).await
}

/// Like [`start`] with an alternative backlight directory (tests).
pub async fn start_at(
    conn: Connection,
    sink: Arc<dyn DocSink>,
    dir: PathBuf,
) -> Result<(ServiceHandle, Commands)> {
    let em = Emitter::new(sink);
    em.emit(read(&dir));
    Ok((ServiceHandle::inert(), Commands { conn, dir, em }))
}

/// A requested change, as fractions of the device maximum: `To` sets the level, `By` moves it
/// (negative = darker).
#[derive(Debug, Clone, Copy, PartialEq)]
pub enum Change {
    To(f64),
    By(f64),
}

/// A change resolved against the level as it is now, not yet written.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Plan {
    dir: PathBuf,
    device: String,
    value: u32,
}

/// Resolve `change` against the backlight as it is now (one sysfs read). `None`: no device.
pub fn plan(dir: &Path, change: Change) -> Option<Plan> {
    let (device, current, max) = find(dir)?;
    Some(Plan {
        dir: dir.to_owned(),
        device,
        value: target(current, max, change),
    })
}

impl Plan {
    /// One logind `SetBrightness`, then one sysfs re-read. The document is the level now in
    /// effect, which is what the OSD and `svc.brightness` must show (Shōjiki).
    pub async fn apply(&self, conn: &Connection) -> zbus::Result<Value> {
        let xdg = std::env::var("XDG_SESSION_ID").ok();
        self.apply_with(conn, &SHARED, xdg.as_deref()).await
    }

    /// [`Plan::apply`] with the cache and `$XDG_SESSION_ID` passed in. Tests use it: edition 2024
    /// makes `set_var` unsafe, and a test run must not pick up the session it happens to run in.
    #[doc(hidden)]
    pub async fn apply_with(
        &self,
        conn: &Connection,
        cache: &SessionCache,
        xdg_session_id: Option<&str>,
    ) -> zbus::Result<Value> {
        let bus = conn.server_guid().to_string();
        let session = match cache.get(&bus) {
            Some(session) => session,
            None => resolve(conn, &bus, cache, xdg_session_id).await,
        };
        match self.set_on(conn, &session).await {
            // The session went away (logind dropped it, or restarted), so the cached path is
            // stale. Resolve once more; whatever that write answers is the answer.
            Err(e) if session_gone(&e) => {
                let session = resolve(conn, &bus, cache, xdg_session_id).await;
                self.set_on(conn, &session).await
            }
            done => done,
        }
    }

    async fn set_on(&self, conn: &Connection, session: &str) -> zbus::Result<Value> {
        util::call(
            conn,
            DEST,
            session,
            SESSION_IF,
            "SetBrightness",
            &("backlight", self.device.as_str(), self.value),
        )
        .await?;
        Ok(read(&self.dir))
    }
}

/// The logind session `SetBrightness` goes to, kept between writes. A write is one key press and
/// resolving costs several calls. The key is the bus: the daemon opens a new system-bus connection
/// per write, and a private test bus must never be answered with another bus's session.
#[derive(Default)]
pub struct SessionCache(Mutex<Option<(String, String)>>);

/// The cache the daemon's writes share (see [`Plan::apply`]).
static SHARED: SessionCache = SessionCache(Mutex::new(None));

impl SessionCache {
    fn get(&self, bus: &str) -> Option<String> {
        let slot = self.0.lock().unwrap_or_else(PoisonError::into_inner);
        slot.as_ref()
            .filter(|(b, _)| b == bus)
            .map(|(_, session)| session.clone())
    }

    /// Keeps `session` for the next write, replacing the entry. The `session/auto` fallback is not
    /// kept, which clears the entry: it means no session was found, so the next write asks again.
    fn remember(&self, bus: &str, session: &str) {
        let keep = (session != SESSION).then(|| (bus.to_owned(), session.to_owned()));
        *self.0.lock().unwrap_or_else(PoisonError::into_inner) = keep;
    }
}

/// Resolves the session writes go to, and remembers it.
async fn resolve(
    conn: &Connection,
    bus: &str,
    cache: &SessionCache,
    xdg_session_id: Option<&str>,
) -> String {
    let session = resolve_session_path(conn, xdg_session_id).await;
    cache.remember(bus, &session);
    tracing::debug!(session = %session, "backlight writes go to this session");
    session
}

/// The session object a write found gone: logind names it `UnknownObject` (no such object path)
/// or `NoSuchSession` (no such session id).
fn session_gone(e: &zbus::Error) -> bool {
    matches!(
        e,
        zbus::Error::MethodError(name, _, _)
            if matches!(
                name.as_str(),
                "org.freedesktop.DBus.Error.UnknownObject" | "org.freedesktop.login1.NoSuchSession"
            )
    )
}

/// Raw level a change lands on, within `0..=max`. A relative step always moves at least one
/// unit, so a coarse backlight (`max` of 7 or 15) never stalls on rounding.
fn target(current: u32, max: u32, change: Change) -> u32 {
    let max_f = f64::from(max);
    let value = match change {
        Change::To(f) if f.is_finite() => (f.clamp(0.0, 1.0) * max_f).round(),
        Change::By(d) if d.is_finite() => {
            let units = (d * max_f).round();
            let step = if d > 0.0 {
                units.max(1.0)
            } else if d < 0.0 {
                units.min(-1.0)
            } else {
                0.0
            };
            f64::from(current) + step
        }
        _ => f64::from(current),
    };
    value.clamp(0.0, max_f) as u32
}

/// First device by name: (name, current, max).
fn find(dir: &Path) -> Option<(String, u32, u32)> {
    let mut names: Vec<_> = std::fs::read_dir(dir)
        .ok()?
        .filter_map(|e| e.ok())
        .collect();
    names.sort_by_key(|e| e.file_name());
    names.into_iter().find_map(|e| {
        let num = |f: &str| {
            std::fs::read_to_string(e.path().join(f))
                .ok()?
                .trim()
                .parse::<u32>()
                .ok()
        };
        let max = num("max_brightness").filter(|m| *m > 0)?;
        Some((
            e.file_name().to_string_lossy().into_owned(),
            num("brightness")?,
            max,
        ))
    })
}

fn read(dir: &Path) -> Value {
    match find(dir) {
        None => json!({"present": false}),
        Some((device, value, max)) => doc(&device, value, max),
    }
}

fn doc(device: &str, value: u32, max: u32) -> Value {
    json!({
        "present": true, "device": device, "value": value, "max": max,
        "percent": (f64::from(value) / f64::from(max) * 1000.0).round() / 10.0,
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn relative_steps_move_at_least_one_unit_and_stay_in_range() {
        assert_eq!(target(50, 100, Change::By(0.05)), 55);
        assert_eq!(target(50, 100, Change::By(-0.05)), 45);
        assert_eq!(target(50, 100, Change::By(0.001)), 51);
        // Half a unit rounds away from zero, so a 10-unit backlight still moves in both ways.
        assert_eq!(target(5, 10, Change::By(0.05)), 6);
        assert_eq!(target(5, 10, Change::By(-0.05)), 4);
        assert_eq!(target(98, 100, Change::By(0.5)), 100);
        assert_eq!(target(0, 15, Change::By(-0.5)), 0);
        assert_eq!(target(50, 100, Change::By(0.0)), 50);
    }

    #[test]
    fn absolute_levels_round_and_clamp() {
        assert_eq!(target(0, 255, Change::To(0.5)), 128);
        assert_eq!(target(0, 100, Change::To(2.0)), 100);
        assert_eq!(target(40, 100, Change::To(f64::NAN)), 40);
    }

    #[test]
    fn plan_reads_the_first_device_and_none_without_one() {
        let dir = tempfile::tempdir().unwrap();
        let dev = dir.path().join("intel_backlight");
        std::fs::create_dir(&dev).unwrap();
        std::fs::write(dev.join("max_brightness"), "100\n").unwrap();
        std::fs::write(dev.join("brightness"), "50\n").unwrap();
        let p = plan(dir.path(), Change::By(0.05)).unwrap();
        assert_eq!((p.device.as_str(), p.value), ("intel_backlight", 55));
        let empty = tempfile::tempdir().unwrap();
        assert_eq!(plan(empty.path(), Change::By(0.05)), None);
    }
}
