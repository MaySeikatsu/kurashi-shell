//! Shared test helpers: enabling the mod the way the daemon does (a `ModCtx` with a settings feed
//! and a recording island), reaching its registrations, and forecast fixtures with chosen steps.

#![allow(dead_code)]

use std::collections::BTreeMap;
use std::path::{Path, PathBuf};
use std::sync::{Arc, Mutex};

use chrono::{Duration, NaiveDateTime};
use kurashi_mod_api::{
    ActionFn, ChoicesFn, FaceUpdate, Hooks, ModCtx, NativeMod, Registration, ServiceFn, Settings,
    Values,
};
use kurashi_mod_weather::{Endpoints, WeatherMod, places::Place};
use serde_json::{Value, json};
use tokio::sync::watch;

pub const FORECAST: &str = include_str!("../fixtures/forecast_tokyo.json");
pub const GEOCODE_JA: &str = include_str!("../fixtures/geocode_tokyo_ja.json");

/// 2026-10-09 14:00 in Tokyo (UTC+9): the fixture's `current` time.
pub const TOKYO_1400: i64 = 1_791_522_000;

/// Records what the mod asks of the island: one line per raise or clear.
#[derive(Default)]
pub struct Recorder {
    pub faces: Mutex<Vec<String>>,
}

impl Hooks for Recorder {
    fn face(&self, face: &str, update: FaceUpdate) {
        let line = match update {
            FaceUpdate::Raise { relevance, ttl } => format!(
                "{face} raise {relevance} {}",
                ttl.map_or(0, |t| t.as_secs())
            ),
            FaceUpdate::Clear => format!("{face} clear"),
        };
        self.faces.lock().expect("faces").push(line);
    }

    fn choices_changed(&self, _source: &str) {}
}

/// One enable of the mod. `tx` is the settings feed: dropping it ends the mod's settings feed
/// (what the daemon does on disable).
pub struct Enabled {
    pub regs: Vec<Registration>,
    pub tx: watch::Sender<Values>,
    pub recorder: Arc<Recorder>,
}

pub fn settings(pairs: &[(&str, Value)]) -> Values {
    pairs
        .iter()
        .map(|(k, v)| ((*k).to_owned(), v.clone()))
        .collect::<BTreeMap<_, _>>()
}

pub fn enable(m: &WeatherMod, values: Values) -> Enabled {
    let provides: Vec<String> = [
        "service:weather",
        "action:weather.*",
        "island-face:weather",
        "choices:weather.places",
    ]
    .iter()
    .map(|s| (*s).to_owned())
    .collect();
    let (tx, rx) = watch::channel(values);
    let recorder = Arc::new(Recorder::default());
    let mut ctx = ModCtx::new(&provides, Settings::new(rx), recorder.clone());
    m.enable(&mut ctx).expect("the mod enables");
    let regs = ctx.finish().expect("no refused registration");
    Enabled { regs, tx, recorder }
}

impl Enabled {
    pub fn service(&self) -> ServiceFn {
        self.regs
            .iter()
            .find_map(|r| match r {
                Registration::Service { run, .. } => Some(run.clone()),
                _ => None,
            })
            .expect("a service is registered")
    }

    pub fn action(&self, id: &str) -> ActionFn {
        self.regs
            .iter()
            .find_map(|r| match r {
                Registration::Action { id: i, handler, .. } if i == id => Some(handler.clone()),
                _ => None,
            })
            .unwrap_or_else(|| panic!("action {id} is registered"))
    }

    pub fn choices(&self) -> ChoicesFn {
        self.regs
            .iter()
            .find_map(|r| match r {
                Registration::Choices { options, .. } => Some(options.clone()),
                _ => None,
            })
            .expect("a choice source is registered")
    }

    /// A settings feed as the daemon gives a service at its start.
    pub fn feed(&self) -> Settings {
        Settings::new(self.tx.subscribe())
    }
}

pub async fn call(
    handler: &ActionFn,
    args: Value,
) -> Result<Option<Value>, kurashi_mod_api::ActionError> {
    handler(args).await
}

pub fn endpoints(base: &str) -> Endpoints {
    Endpoints {
        forecast: format!("{base}/v1/forecast"),
        geocode: format!("{base}/v1/search"),
    }
}

/// A fresh state dir per test, holding the mod's `places.json` with the given places.
pub fn state_dir(name: &str, places: &[Place]) -> PathBuf {
    let dir = std::env::temp_dir().join(format!("kmw-{}-{name}", std::process::id()));
    let _ = std::fs::remove_dir_all(&dir);
    std::fs::create_dir_all(&dir).expect("state dir");
    kurashi_mod_weather::places::save(&dir.join("places.json"), places).expect("places saved");
    dir
}

pub fn tokyo() -> Place {
    Place {
        id: "1850147".into(),
        name: "東京".into(),
        admin: Some("東京都".into()),
        country: Some("日本".into()),
        country_code: Some("JP".into()),
        lat: 35.6895,
        lon: 139.69171,
        tz: "Asia/Tokyo".into(),
    }
}

pub fn chicago() -> Place {
    Place {
        id: "4887398".into(),
        name: "シカゴ".into(),
        admin: Some("イリノイ州".into()),
        country: Some("アメリカ合衆国".into()),
        country_code: Some("US".into()),
        lat: 41.85003,
        lon: -87.65005,
        tz: "America/Chicago".into(),
    }
}

/// The fixture forecast with its 15-minute steps replaced: `precip` from local time `start`.
pub fn forecast_with_steps(start: &str, precip: &[f64]) -> String {
    let mut v: Value = serde_json::from_str(FORECAST).expect("fixture");
    let start = NaiveDateTime::parse_from_str(start, "%Y-%m-%dT%H:%M").expect("start");
    let times: Vec<String> = (0..precip.len())
        .map(|i| {
            (start + Duration::minutes(15 * i as i64))
                .format("%Y-%m-%dT%H:%M")
                .to_string()
        })
        .collect();
    v["minutely_15"]["time"] = json!(times);
    v["minutely_15"]["precipitation"] = json!(precip);
    v.to_string()
}

pub fn path_of(dir: &Path) -> PathBuf {
    dir.to_path_buf()
}
