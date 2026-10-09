//! `svc.brightness` — backlight via sysfs (read) and logind `SetBrightness` (write).
//!
//! Deviation, by design: this service is **read-on-demand**. sysfs offers no cheap change
//! notification without a udev netlink socket (needs libudev bindings), and polling is forbidden
//! (rule 5). So the document is emitted at start and after our own `set_percent`/`refresh`;
//! changes made by other tools show up on the next `refresh()` (e.g. when the panel opens).

use std::path::{Path, PathBuf};
use std::sync::Arc;

use anyhow::Result;
use serde_json::{Value, json};
use zbus::Connection;

use crate::session::{DEST, SESSION, SESSION_IF};
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
    /// Set brightness through logind (no root needed), then re-emit.
    pub async fn set_percent(&self, percent: f64) -> zbus::Result<()> {
        let Some((device, _, max)) = find(&self.dir) else {
            return Ok(());
        };
        let value = ((percent.clamp(0.0, 100.0) / 100.0) * max as f64).round() as u32;
        util::call(
            &self.conn,
            DEST,
            SESSION,
            SESSION_IF,
            "SetBrightness",
            &("backlight", device, value),
        )
        .await?;
        self.refresh();
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
        Some((device, value, max)) => json!({
            "present": true, "device": device, "value": value, "max": max,
            "percent": (f64::from(value) / f64::from(max) * 1000.0).round() / 10.0,
        }),
    }
}
