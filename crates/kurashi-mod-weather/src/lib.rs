//! Weather native mod (K26, K28; docs/ux/weather.md; card W12-weather). Linked into kurashid by
//! `native::linked()`; its manifest and QML live in `mods/weather/`. What it registers is exactly
//! what that manifest's `provides` lists: the service `mod.weather`, the actions `weather.*`, the
//! island face `weather` (rain soon), the choice source `weather.places`. The bar widget, the panel
//! and the clock aside are QML; they talk to the daemon only through the document and the actions.

pub mod actions;
pub mod api;
pub mod doc;
pub mod http;
pub mod places;
pub mod rain;
pub mod service;

use std::path::PathBuf;
use std::sync::Arc;
use std::time::{SystemTime, UNIX_EPOCH};

use kurashi_mod_api::{FaceSpec, ModCtx, ModError, NativeMod};
use serde_json::json;

pub use api::{Endpoints, Units};
pub use http::{Http, HttpError, Ureq};
pub use service::Clock;

use service::{RAIN_FACE_TTL_S, Shared};

/// The weather mod. `new()` is what the daemon links; `with` is for tests: a fake or local
/// transport, a clock that follows the paused runtime, a temporary state dir.
#[derive(Clone)]
pub struct WeatherMod {
    http: Arc<dyn Http>,
    endpoints: Endpoints,
    clock: Clock,
    state_dir: PathBuf,
    locale: Units,
}

impl WeatherMod {
    pub fn new() -> Self {
        Self::with(
            Arc::new(Ureq::new()),
            Endpoints::from_env(),
            Arc::new(system_clock),
            state_dir(),
            locale_units(),
        )
    }

    pub fn with(
        http: Arc<dyn Http>,
        endpoints: Endpoints,
        clock: Clock,
        state_dir: PathBuf,
        locale: Units,
    ) -> Self {
        Self {
            http,
            endpoints,
            clock,
            state_dir,
            locale,
        }
    }
}

impl Default for WeatherMod {
    fn default() -> Self {
        Self::new()
    }
}

impl NativeMod for WeatherMod {
    fn id(&self) -> &'static str {
        "weather"
    }

    fn enable(&self, ctx: &mut ModCtx) -> Result<(), ModError> {
        let shared = Arc::new(Shared::new(
            self.http.clone(),
            self.endpoints.clone(),
            self.clock.clone(),
            &self.state_dir,
            self.locale,
        ));

        let s = shared.clone();
        ctx.service(
            "weather",
            json!({"available": false, "reason": "mod-weather.no_location"}),
            move |publish, settings| {
                let s = s.clone();
                async move { service::run(s, publish, settings).await }
            },
        )?;

        let s = shared.clone();
        ctx.action(
            "weather.refresh",
            "mod-weather.action.refresh",
            move |_args| {
                let s = s.clone();
                async move { Ok(Some(actions::refresh(&s))) }
            },
        )?;
        let s = shared.clone();
        ctx.action(
            "weather.place.search",
            "mod-weather.action.search",
            move |args| actions::search(s.clone(), args),
        )?;
        let s = shared.clone();
        ctx.action("weather.place.add", "mod-weather.action.add", move |args| {
            let s = s.clone();
            async move { actions::add(&s, args) }
        })?;
        let s = shared.clone();
        ctx.action(
            "weather.place.remove",
            "mod-weather.action.remove",
            move |args| {
                let s = s.clone();
                async move { actions::remove(&s, args) }
            },
        )?;
        let s = shared.clone();
        ctx.action(
            "weather.place.move",
            "mod-weather.action.move",
            move |args| {
                let s = s.clone();
                async move { actions::move_place(&s, args) }
            },
        )?;
        let s = shared.clone();
        ctx.action(
            "weather.place.next",
            "mod-weather.action.next",
            move |_args| {
                let s = s.clone();
                async move { Ok(Some(actions::next(&s))) }
            },
        )?;

        let face = ctx.face(
            "weather",
            FaceSpec {
                transient: true,
                ttl_s: RAIN_FACE_TTL_S,
            },
        )?;
        shared.set_face(face);

        let s = shared.clone();
        let choices = ctx.choices("weather.places", move || s.choice_offers())?;
        shared.set_choices(choices);

        // Rain alerts need a job while nothing subscribes. The daemon runs it while `rain_alerts` is on
        // and the mod is enabled, cancels it on disable, and reports it as running (I23).
        let s = shared.clone();
        ctx.background(
            "rain",
            "mods.running.rain_alerts",
            "rain_alerts",
            move |job| {
                let s = s.clone();
                let settings = job.settings().clone();
                async move { service::rain_job(s, settings).await }
            },
        )?;
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

/// `<state>/kurashi/weather`: the state home as kurashid resolves it (`$XDG_STATE_HOME`, else
/// `~/.local/state`).
fn state_dir() -> PathBuf {
    let base = std::env::var_os("XDG_STATE_HOME")
        .filter(|v| !v.is_empty())
        .map(PathBuf::from)
        .unwrap_or_else(|| {
            PathBuf::from(std::env::var_os("HOME").unwrap_or_default()).join(".local/state")
        });
    base.join("kurashi").join("weather")
}

/// The unit system of the session's locale (`LC_ALL`, `LC_MEASUREMENT`, `LANG`, in that order).
fn locale_units() -> Units {
    ["LC_ALL", "LC_MEASUREMENT", "LANG"]
        .iter()
        .find_map(|key| std::env::var(key).ok().filter(|v| !v.is_empty()))
        .map_or(Units::Metric, |v| api::units_from_locale(&v))
}
