//! Lyrics native mod (K47; docs/ux/lyrics.md; card W23-auth-media). Linked into kurashid by `native::linked()`; its
//! manifest and QML live in `mods/lyrics/`. It registers what that manifest's `provides` lists for the daemon: the
//! service `mod.lyrics` and the actions `lyrics.track` and `lyrics.retry`. The media card's slot, the bar widget and the
//! desk card are QML: they send the track `svc.media` shows, read the document and map the playing position to the
//! current line themselves.

pub mod cache;
pub mod http;
pub mod lrc;
pub mod lrclib;
pub mod service;

use std::path::PathBuf;
use std::sync::Arc;
use std::time::{SystemTime, UNIX_EPOCH};

use kurashi_mod_api::{ModCtx, ModError, NativeMod};

pub use cache::{Answer, Cache, Lyrics};
pub use http::{Http, HttpError, Ureq};
pub use service::Clock;

use service::Shared;

/// A track as `svc.media` shows it.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Track {
    pub title: String,
    pub artist: String,
    pub album: Option<String>,
    pub length_us: Option<u64>,
}

/// The lyrics mod. `new()` is what the daemon links; `with` is for tests: a fake transport, a base URL, a temporary
/// cache dir, a fixed clock.
#[derive(Clone)]
pub struct LyricsMod {
    http: Arc<dyn Http>,
    base: String,
    cache_dir: PathBuf,
    clock: Clock,
}

impl LyricsMod {
    pub fn new() -> Self {
        Self::with(
            Arc::new(Ureq::new()),
            lrclib::base_from_env(),
            cache_dir(),
            Arc::new(system_clock),
        )
    }

    pub fn with(http: Arc<dyn Http>, base: String, cache_dir: PathBuf, clock: Clock) -> Self {
        Self {
            http,
            base,
            cache_dir,
            clock,
        }
    }
}

impl Default for LyricsMod {
    fn default() -> Self {
        Self::new()
    }
}

impl NativeMod for LyricsMod {
    fn id(&self) -> &'static str {
        "lyrics"
    }

    fn enable(&self, ctx: &mut ModCtx) -> Result<(), ModError> {
        let shared = Arc::new(Shared::new(
            self.http.clone(),
            self.base.clone(),
            Cache::new(self.cache_dir.clone()),
            self.clock.clone(),
        ));
        let s = shared.clone();
        ctx.service("lyrics", service::initial(), move |publish, settings| {
            service::run(s.clone(), publish, settings)
        })?;
        let s = shared.clone();
        ctx.action("lyrics.track", "mod-lyrics.action.track", move |args| {
            let r = service::set_track(&s, &args);
            async move { r }
        })?;
        let s = shared.clone();
        ctx.action("lyrics.retry", "mod-lyrics.action.retry", move |_args| {
            let r = service::retry(&s);
            async move { r }
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

/// `<cache>/kurashi/lyrics`: `$XDG_CACHE_HOME`, else `~/.cache` (the `{cache_dir}` of MODS.md "Host processes").
fn cache_dir() -> PathBuf {
    let base = std::env::var_os("XDG_CACHE_HOME")
        .filter(|v| !v.is_empty())
        .map(PathBuf::from)
        .unwrap_or_else(|| {
            PathBuf::from(std::env::var_os("HOME").unwrap_or_default()).join(".cache")
        });
    base.join("kurashi").join("lyrics")
}
