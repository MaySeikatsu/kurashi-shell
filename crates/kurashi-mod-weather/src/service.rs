//! The mod's state and loops (docs/ux/weather.md, "Fit and constraints"). The service runs only while
//! `mod.weather` has a subscriber (rule 5): it fetches at most every `refresh`, republishes when the
//! age tier changes and once a minute while data is shown (so the age text stays true), and stops
//! with the last subscriber. The rain job runs only when rain alerts are on and nothing subscribes.

use std::collections::BTreeMap;
use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Arc, Mutex, MutexGuard, OnceLock};
use std::time::Duration;

use kurashi_mod_api::{Choice, ChoicesHandle, FaceHandle, Publish, Settings};
use serde_json::Value;
use tokio::sync::{Mutex as AsyncMutex, Notify};

use crate::api::{self, Endpoints, Units};
use crate::doc::{self, Data, Failure, Input};
use crate::http::{Http, HttpError};
use crate::places::{self, Place};
use crate::rain::{self, Edge, Watch};

/// The wall clock as unix seconds. Tests pass one that follows the paused runtime.
pub type Clock = Arc<dyn Fn() -> i64 + Send + Sync>;

/// The rain-soon face stays up this long after each raise (the arbiter's TTL, FaceSpec).
pub const RAIN_FACE_TTL_S: u32 = 60;
/// Relevance the rain-soon face is raised with (a transient ignores it for ordering).
const RAIN_RELEVANCE: u8 = 60;
/// Seconds between two manual refreshes (middle click, docs/ux/weather.md).
pub const MANUAL_COOLDOWN_S: i64 = 60;
/// The age text is republished this often while data is shown and the service runs.
const AGE_TICK_S: i64 = 60;
pub const MIN_REFRESH_MIN: i64 = 10;
pub const MAX_REFRESH_MIN: i64 = 180;
pub const DEFAULT_REFRESH_MIN: i64 = 30;

/// The settings in effect, read on every pass (a change of one wakes the loops).
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Config {
    pub place: String,
    pub units: String,
    pub refresh_s: i64,
    pub rain_alerts: bool,
    pub template: String,
}

impl Config {
    pub fn read(s: &Settings) -> Self {
        let text = |key: &str, default: &str| {
            s.get(key)
                .and_then(|v| v.as_str().map(str::to_owned))
                .unwrap_or_else(|| default.to_owned())
        };
        let refresh_min = s
            .get("refresh")
            .and_then(|v| v.as_i64())
            .unwrap_or(DEFAULT_REFRESH_MIN)
            .clamp(MIN_REFRESH_MIN, MAX_REFRESH_MIN);
        Self {
            place: text("place", ""),
            units: text("units", "auto"),
            refresh_s: refresh_min * 60,
            rain_alerts: s
                .get("rain_alerts")
                .and_then(|v| v.as_bool())
                .unwrap_or(false),
            template: text("bar_template", "{glyph} {temp}"),
        }
    }

    /// The unit system in effect and where it comes from: the locale unless the user chose one.
    pub fn units(&self, locale: Units) -> (Units, &'static str) {
        match self.units.as_str() {
            "metric" => (Units::Metric, "setting"),
            "imperial" => (Units::Imperial, "setting"),
            _ => (locale, "locale"),
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum Kind {
    Offline,
    RateLimited,
    Server,
    BadData,
}

impl Kind {
    fn key(self) -> &'static str {
        match self {
            Self::Offline => "mod-weather.error.offline",
            Self::RateLimited => "mod-weather.error.rate_limited",
            Self::Server => "mod-weather.error.server",
            Self::BadData => "mod-weather.error.bad_data",
        }
    }
}

/// Retry after 60 s, doubling, capped at one refresh; a rate limit waits a full refresh.
fn backoff(kind: Kind, count: u32, refresh_s: i64) -> i64 {
    match kind {
        Kind::RateLimited => refresh_s,
        _ => (60 * (1_i64 << count.saturating_sub(1).min(10))).min(refresh_s),
    }
}

/// When the next fetch is due: the backoff after a failure, else one refresh after the last success.
fn fetch_due(data: Option<&Data>, failure: Option<&Failure>, refresh_s: i64) -> Option<i64> {
    failure
        .map(|f| f.next_try_at)
        .or_else(|| data.map(|d| d.fetched_at + refresh_s))
}

/// The state the actions and both loops share, per enable. Lock scopes stay short and never span
/// an await, and the face is raised only after the lock is released.
pub struct Shared {
    pub http: Arc<dyn Http>,
    pub endpoints: Endpoints,
    pub clock: Clock,
    pub places_path: PathBuf,
    pub locale: Units,
    /// One forecast request at a time: the service and the rain job never race.
    gate: AsyncMutex<()>,
    state: Mutex<State>,
    /// Wakes the service: republish (scroll, places) or fetch now (manual refresh).
    pub wake: Notify,
    /// Wakes the rain job when the places change.
    pub bg_wake: Notify,
    pub subscribed: AtomicBool,
    face: OnceLock<FaceHandle>,
    choices: OnceLock<ChoicesHandle>,
}

#[derive(Default)]
pub struct State {
    pub places: Vec<Place>,
    /// The place scrolled to in this session; it wins over the setting until the setting changes.
    pub scrolled: Option<String>,
    cfg_place: Option<String>,
    /// The place the document showed last: where scrolling moves on from.
    pub shown: Option<String>,
    pub data: BTreeMap<String, Data>,
    pub failure: BTreeMap<String, Failure>,
    /// A manual refresh was asked for: the next pass fetches regardless of the cadence.
    pub force: bool,
    pub last_manual: Option<i64>,
    pub watch: Watch,
}

impl Shared {
    pub fn new(
        http: Arc<dyn Http>,
        endpoints: Endpoints,
        clock: Clock,
        state_dir: &Path,
        locale: Units,
    ) -> Self {
        let places_path = state_dir.join("places.json");
        let places = places::load(&places_path);
        Self {
            http,
            endpoints,
            clock,
            places_path,
            locale,
            gate: AsyncMutex::new(()),
            state: Mutex::new(State {
                places,
                ..State::default()
            }),
            wake: Notify::new(),
            bg_wake: Notify::new(),
            subscribed: AtomicBool::new(false),
            face: OnceLock::new(),
            choices: OnceLock::new(),
        }
    }

    pub fn with<T>(&self, f: impl FnOnce(&mut State) -> T) -> T {
        let mut guard: MutexGuard<'_, State> = self.state.lock().unwrap_or_else(|e| e.into_inner());
        f(&mut guard)
    }

    pub fn set_face(&self, face: FaceHandle) {
        let _ = self.face.set(face);
    }

    pub fn set_choices(&self, choices: ChoicesHandle) {
        let _ = self.choices.set(choices);
    }

    /// The options of `weather.places`: the first saved place (the default) and each saved place.
    pub fn choice_offers(&self) -> Vec<Choice> {
        self.with(|st| {
            let mut out = vec![Choice::new("", "mod-weather.place.first")];
            out.extend(st.places.iter().map(|p| Choice::new(&p.id, &p.label())));
            out
        })
    }

    /// The places changed: the settings that name the choice source are asked again, and both
    /// loops look again.
    pub fn places_changed(&self) {
        if let Some(c) = self.choices.get() {
            c.choices_changed();
        }
        self.poke();
    }

    /// Wakes whichever loop is running. A permit is kept, so a wake that comes early is not lost.
    pub fn poke(&self) {
        self.wake.notify_one();
        self.bg_wake.notify_one();
    }

    /// The place in effect now (also recorded as the one shown, for scrolling).
    fn resolve(&self, cfg: &Config) -> Option<Place> {
        self.with(|st| {
            if st.cfg_place.as_deref() != Some(cfg.place.as_str()) {
                st.cfg_place = Some(cfg.place.clone());
                st.scrolled = None;
            }
            let place = places::effective(&st.places, &cfg.place, st.scrolled.as_deref()).cloned();
            st.shown = place.as_ref().map(|p| p.id.clone());
            place
        })
    }

    fn due(&self, id: &str, refresh_s: i64, now: i64) -> bool {
        self.with(|st| {
            fetch_due(st.data.get(id), st.failure.get(id), refresh_s).is_none_or(|t| now >= t)
        })
    }

    /// One forecast request for `place`: the data on success, the failure and its backoff otherwise.
    /// The rain watch observes each successful forecast; its face change happens after the lock.
    pub async fn fetch(&self, place: &Place, cfg: &Config) {
        let _gate = self.gate.lock().await;
        let url = api::forecast_url(&self.endpoints.forecast, place.lat, place.lon);
        let outcome = match self.http.get(url).await {
            Ok(body) => api::parse_forecast(&body).map_err(|_| Kind::BadData),
            Err(HttpError::Status(429)) => Err(Kind::RateLimited),
            Err(HttpError::Status(_)) => Err(Kind::Server),
            Err(HttpError::Offline(_) | HttpError::Body(_)) => Err(Kind::Offline),
        };
        let now = (self.clock)();
        let edge = self.with(|st| match outcome {
            Ok(forecast) => {
                let local = doc::local_at(now, forecast.utc_offset_s);
                let edge = if cfg.rain_alerts {
                    st.watch.observe(&rain::nowcast(&forecast.steps, local))
                } else {
                    st.watch.reset()
                };
                st.data.insert(
                    place.id.clone(),
                    Data {
                        forecast,
                        fetched_at: now,
                    },
                );
                st.failure.remove(&place.id);
                edge
            }
            Err(kind) => {
                let count = st.failure.get(&place.id).map_or(0, |f| f.count) + 1;
                st.failure.insert(
                    place.id.clone(),
                    Failure {
                        reason: kind.key(),
                        count,
                        next_try_at: now + backoff(kind, count, cfg.refresh_s),
                    },
                );
                Edge::None
            }
        });
        self.apply(edge);
    }

    fn apply(&self, edge: Edge) {
        let Some(face) = self.face.get() else {
            return;
        };
        match edge {
            Edge::Raise => face.raise(RAIN_RELEVANCE),
            Edge::Clear => face.clear(),
            Edge::None => {}
        }
    }

    /// One pass of the service: fetch if due or asked, then the document and when to look again.
    async fn service_pass(&self, cfg: &Config) -> (Value, Option<i64>) {
        let Some(place) = self.resolve(cfg) else {
            return self.document(None, cfg, (self.clock)());
        };
        let now = (self.clock)();
        let forced = self.with(|st| std::mem::take(&mut st.force));
        if forced || self.due(&place.id, cfg.refresh_s, now) {
            self.fetch(&place, cfg).await;
        }
        self.document(Some(&place), cfg, (self.clock)())
    }

    fn document(&self, place: Option<&Place>, cfg: &Config, now: i64) -> (Value, Option<i64>) {
        let (units, units_from) = cfg.units(self.locale);
        self.with(|st| {
            let (data, failure) = match place {
                Some(p) => (st.data.get(&p.id), st.failure.get(&p.id)),
                None => (None, None),
            };
            let value = doc::build(&Input {
                place,
                data,
                failure,
                now,
                refresh_s: cfg.refresh_s,
                units,
                units_from,
                template: &cfg.template,
            });
            let wake = place.and_then(|_| {
                let fetch = fetch_due(data, failure, cfg.refresh_s).map(|t| t.max(now + 1));
                let tier =
                    data.and_then(|d| doc::next_tier_change(d.fetched_at, cfg.refresh_s, now));
                let tick = data.map(|_| now + AGE_TICK_S);
                [fetch, tier, tick].into_iter().flatten().min()
            });
            (value, wake)
        })
    }
}

/// Counts the service as subscribed while its future lives; the daemon drops it on the last
/// unsubscribe, which clears the flag again.
struct Subscription<'a>(&'a AtomicBool);

impl Drop for Subscription<'_> {
    fn drop(&mut self) {
        self.0.store(false, Ordering::SeqCst);
    }
}

async fn pause(d: Option<Duration>) {
    match d {
        Some(d) => tokio::time::sleep(d).await,
        None => std::future::pending().await,
    }
}

fn after(now: i64, at: Option<i64>) -> Option<Duration> {
    at.map(|t| Duration::from_secs(u64::try_from((t - now).max(1)).unwrap_or(1)))
}

/// `mod.weather`'s service body: runs while subscribed, publishes what the views show.
pub async fn run(shared: Arc<Shared>, publish: Publish, mut settings: Settings) {
    shared.subscribed.store(true, Ordering::SeqCst);
    let _subscription = Subscription(&shared.subscribed);
    loop {
        let cfg = Config::read(&settings);
        let (value, wake) = shared.service_pass(&cfg).await;
        publish(value);
        let sleep = after((shared.clock)(), wake);
        tokio::select! {
            () = pause(sleep) => {}
            () = shared.wake.notified() => {}
            changed = settings.changed() => {
                if !changed {
                    return;
                }
            }
        }
    }
}

/// The background job of rain alerts (docs/ux/weather.md, Fit): with alerts on and no subscriber,
/// one forecast request per refresh feeds the rain-soon face. Ends when the mod is disabled.
pub async fn rain_job(shared: Arc<Shared>, mut settings: Settings) {
    loop {
        let cfg = Config::read(&settings);
        let mut wake = None;
        if cfg.rain_alerts && !shared.subscribed.load(Ordering::SeqCst) {
            if let Some(place) = shared.resolve(&cfg) {
                let now = (shared.clock)();
                if shared.due(&place.id, cfg.refresh_s, now) {
                    shared.fetch(&place, &cfg).await;
                }
                let now = (shared.clock)();
                wake = shared.with(|st| {
                    fetch_due(
                        st.data.get(&place.id),
                        st.failure.get(&place.id),
                        cfg.refresh_s,
                    )
                });
                wake = wake.map(|t| t.max(now + 1));
            }
        }
        let sleep = after((shared.clock)(), wake);
        tokio::select! {
            () = pause(sleep) => {}
            () = shared.bg_wake.notified() => {}
            changed = settings.changed() => {
                if !changed {
                    return;
                }
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn backoff_doubles_and_rate_limits_wait_a_refresh() {
        assert_eq!(backoff(Kind::Offline, 1, 1800), 60);
        assert_eq!(backoff(Kind::Server, 2, 1800), 120);
        assert_eq!(backoff(Kind::Offline, 3, 1800), 240);
        assert_eq!(
            backoff(Kind::Offline, 9, 1800),
            1800,
            "capped at one refresh"
        );
        assert_eq!(backoff(Kind::RateLimited, 1, 900), 900);
    }

    #[test]
    fn config_reads_clamped_settings_and_the_unit_source() {
        let (_, rx) = tokio::sync::watch::channel(BTreeMap::from([
            ("refresh".to_owned(), serde_json::json!(500)),
            ("units".to_owned(), serde_json::json!("auto")),
            ("rain_alerts".to_owned(), serde_json::json!(true)),
        ]));
        let cfg = Config::read(&Settings::new(rx));
        assert_eq!(
            cfg.refresh_s,
            MAX_REFRESH_MIN * 60,
            "500 min is clamped to the maximum"
        );
        assert!(cfg.rain_alerts);
        assert_eq!(cfg.place, "");
        assert_eq!(cfg.template, "{glyph} {temp}");
        assert_eq!(cfg.units(Units::Imperial), (Units::Imperial, "locale"));
        let metric = Config {
            units: "metric".into(),
            ..cfg
        };
        assert_eq!(metric.units(Units::Imperial), (Units::Metric, "setting"));
    }

    #[test]
    fn fetch_due_prefers_the_backoff_over_the_cadence() {
        let data = Data {
            forecast: api::parse_forecast(include_str!("../tests/fixtures/forecast_tokyo.json"))
                .unwrap(),
            fetched_at: 1000,
        };
        let failure = Failure {
            reason: "mod-weather.error.offline",
            count: 1,
            next_try_at: 1100,
        };
        assert_eq!(fetch_due(Some(&data), None, 1800), Some(2800));
        assert_eq!(fetch_due(Some(&data), Some(&failure), 1800), Some(1100));
        assert_eq!(fetch_due(None, None, 1800), None);
    }
}
