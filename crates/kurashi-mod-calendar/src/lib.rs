//! Calendar native mod (card W27-calendar; docs/ux/calendar.md). Linked into kurashid by `native::linked()`; its
//! manifest and QML live in `mods/calendar/`. It registers what that manifest's `provides` lists for the daemon: the
//! service `mod.calendar`, the action `calendar.refresh`, the island face `calendar` with its peek job, and the agenda
//! slot's handle (`clock.expanded.day`, whose reason says that no calendar is set). The agenda, the day dots, the desk
//! card and the bar widget are QML; they read the document. Sources: local `.ics` files and folders (vdirsyncer/khal
//! storage), feed addresses (cached for offline use) and khal.

pub mod day;
pub mod doc;
pub mod expand;
pub mod http;
pub mod ics;
pub mod khal;
pub mod rrule;
pub mod service;
pub mod sources;
pub mod tz;

use std::path::PathBuf;
use std::sync::Arc;
use std::time::{SystemTime, UNIX_EPOCH};

use jiff::tz::TimeZone;
use kurashi_mod_api::{FaceSpec, ModCtx, ModError, NativeMod};
use serde_json::json;

pub use http::{Http, HttpError, Ureq};
pub use service::{Clock, Zone};

use service::{PEEK_TTL_S, Shared};

/// The calendar mod. `new()` is what the daemon links; `with` is for tests (a fake transport, a fixed clock and zone,
/// temporary folders, a stand-in for khal).
#[derive(Clone)]
pub struct CalendarMod {
    http: Arc<dyn Http>,
    clock: Clock,
    zone: Zone,
    cache_dir: PathBuf,
    home: PathBuf,
    khal_bin: String,
}

impl CalendarMod {
    pub fn new() -> Self {
        Self::with(
            Arc::new(Ureq::new()),
            Arc::new(system_clock),
            Arc::new(TimeZone::system),
            cache_dir(),
            PathBuf::from(std::env::var_os("HOME").unwrap_or_default()),
            "khal".into(),
        )
    }

    pub fn with(
        http: Arc<dyn Http>,
        clock: Clock,
        zone: Zone,
        cache_dir: PathBuf,
        home: PathBuf,
        khal_bin: String,
    ) -> Self {
        Self {
            http,
            clock,
            zone,
            cache_dir,
            home,
            khal_bin,
        }
    }
}

impl Default for CalendarMod {
    fn default() -> Self {
        Self::new()
    }
}

impl NativeMod for CalendarMod {
    fn id(&self) -> &'static str {
        "calendar"
    }

    fn enable(&self, ctx: &mut ModCtx) -> Result<(), ModError> {
        let shared = Arc::new(Shared::new(
            self.http.clone(),
            self.clock.clone(),
            self.zone.clone(),
            self.cache_dir.clone(),
            self.home.clone(),
            self.khal_bin.clone(),
        ));
        shared.set_slot(ctx.slot("clock.expanded.day")?);

        let s = shared.clone();
        ctx.service(
            "calendar",
            json!({"available": true, "state": "loading", "sources": [], "days": {}}),
            move |publish, settings| service::run(s.clone(), publish, settings),
        )?;

        let s = shared.clone();
        ctx.action(
            "calendar.refresh",
            "mod-calendar.action.refresh",
            move |_args| {
                s.refresh();
                async move { Ok(None) }
            },
        )?;

        let face = ctx.face(
            "calendar",
            FaceSpec {
                transient: true,
                ttl_s: PEEK_TTL_S,
            },
        )?;
        shared.set_face(face);

        let s = shared.clone();
        ctx.background("peek", "mods.running.calendar_peek", "peek", move |job| {
            service::peek_job(s.clone(), job)
        })?;
        Ok(())
    }
}

/// Unix seconds from the system clock. A clock before 1970 reads as 0, never as a panic.
pub fn system_clock() -> i64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .ok()
        .and_then(|d| i64::try_from(d.as_secs()).ok())
        .unwrap_or(0)
}

/// `$XDG_CACHE_HOME/kurashi/calendar` (else `~/.cache/kurashi/calendar`): the feeds' last good copies.
fn cache_dir() -> PathBuf {
    std::env::var_os("XDG_CACHE_HOME")
        .filter(|v| !v.is_empty())
        .map(PathBuf::from)
        .unwrap_or_else(|| {
            PathBuf::from(std::env::var_os("HOME").unwrap_or_default()).join(".cache")
        })
        .join("kurashi")
        .join("calendar")
}
