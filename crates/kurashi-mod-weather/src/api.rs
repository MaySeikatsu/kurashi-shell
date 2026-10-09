//! Open-Meteo wire format (docs/ux/weather.md, card W12-weather): request URLs, parsing, the WMO
//! mapping and unit conversion. Pure: no I/O and no clock, so every rule here is unit-tested on
//! fixtures. Times are the place's local clock (`timezone=auto`); the offset suffix, if a server
//! sends one, is ignored, because the naive part is already local.

use chrono::{NaiveDate, NaiveDateTime};
use serde::Deserialize;
use thiserror::Error;

use crate::places::Place;

pub const FORECAST_URL: &str = "https://api.open-meteo.com/v1/forecast";
pub const GEOCODE_URL: &str = "https://geocoding-api.open-meteo.com/v1/search";

/// The two endpoints. Tests point them at a local mock server; nothing else changes.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Endpoints {
    pub forecast: String,
    pub geocode: String,
}

impl Default for Endpoints {
    fn default() -> Self {
        Self {
            forecast: FORECAST_URL.into(),
            geocode: GEOCODE_URL.into(),
        }
    }
}

/// One request serves the panel, the bar widget and the rain-soon alert: `minutely_15` is
/// the rain nowcast (precipitation only; Open-Meteo does not offer a probability there).
/// Metric units are requested and converted in the daemon, so the cache holds one unit system.
const FORECAST_QUERY: &str = "current=temperature_2m,relative_humidity_2m,apparent_temperature,is_day,weather_code,wind_speed_10m,wind_gusts_10m\
&hourly=temperature_2m,apparent_temperature,precipitation_probability,weather_code,is_day,uv_index\
&daily=weather_code,temperature_2m_max,temperature_2m_min,precipitation_probability_max,sunrise,sunset,daylight_duration,uv_index_max\
&minutely_15=precipitation&forecast_minutely_15=8&forecast_days=7\
&timezone=auto&timeformat=iso8601&wind_speed_unit=kmh&temperature_unit=celsius&precipitation_unit=mm";

pub fn forecast_url(base: &str, lat: f64, lon: f64) -> String {
    format!("{base}?latitude={lat:.4}&longitude={lon:.4}&{FORECAST_QUERY}")
}

/// Geocoding search. The name is percent-encoded here; it never reaches a shell (rule: no
/// place name is passed to a shell or concatenated unescaped).
pub fn geocode_url(base: &str, query: &str, lang: &str) -> String {
    format!(
        "{base}?name={}&count=10&language={}&format=json",
        encode(query.trim()),
        lang_tag(lang)
    )
}

/// A two-letter language code for the geocoder's `language` (`ja`, `en`, …). Anything else
/// falls back to English, so a locale string can never inject a query parameter.
pub fn lang_tag(lang: &str) -> String {
    let head: String = lang.chars().take(2).collect();
    if head.len() == 2 && head.chars().all(|c| c.is_ascii_lowercase()) {
        head
    } else {
        "en".into()
    }
}

/// RFC 3986 percent-encoding of everything but the unreserved set.
pub fn encode(s: &str) -> String {
    let mut out = String::with_capacity(s.len());
    for b in s.bytes() {
        match b {
            b'A'..=b'Z' | b'a'..=b'z' | b'0'..=b'9' | b'-' | b'.' | b'_' | b'~' => {
                out.push(char::from(b))
            }
            _ => out.push_str(&format!("%{b:02X}")),
        }
    }
    out
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Units {
    Metric,
    Imperial,
}

impl Units {
    pub fn key(self) -> &'static str {
        match self {
            Self::Metric => "metric",
            Self::Imperial => "imperial",
        }
    }

    pub fn temp(self, celsius: f64) -> f64 {
        match self {
            Self::Metric => celsius,
            Self::Imperial => celsius * 9.0 / 5.0 + 32.0,
        }
    }

    pub fn wind(self, kmh: f64) -> f64 {
        match self {
            Self::Metric => kmh,
            Self::Imperial => kmh * 0.621_371,
        }
    }
}

/// The unit system of a locale such as `en_US.UTF-8` (`LC_MEASUREMENT`, else `LC_ALL`, `LANG`):
/// the regions that use imperial units by default. Anything unknown is metric.
pub fn units_from_locale(locale: &str) -> Units {
    let region = locale
        .split_once('_')
        .map(|(_, rest)| rest.split(['.', '@']).next().unwrap_or(""))
        .unwrap_or("");
    match region {
        "US" | "LR" | "MM" => Units::Imperial,
        _ => Units::Metric,
    }
}

/// WMO weather code → the condition the frontend maps to a glyph and an i18n key (`mod-weather.
/// condition.<key>`). Codes outside the WMO table are `Unknown`, shown as "—", never guessed.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Condition {
    Clear,
    MainlyClear,
    PartlyCloudy,
    Overcast,
    Fog,
    Drizzle,
    FreezingDrizzle,
    Rain,
    FreezingRain,
    Snow,
    SnowGrains,
    Showers,
    SnowShowers,
    Thunder,
    ThunderHail,
    Unknown,
}

impl Condition {
    pub fn key(self) -> &'static str {
        match self {
            Self::Clear => "clear",
            Self::MainlyClear => "mainly_clear",
            Self::PartlyCloudy => "partly_cloudy",
            Self::Overcast => "overcast",
            Self::Fog => "fog",
            Self::Drizzle => "drizzle",
            Self::FreezingDrizzle => "freezing_drizzle",
            Self::Rain => "rain",
            Self::FreezingRain => "freezing_rain",
            Self::Snow => "snow",
            Self::SnowGrains => "snow_grains",
            Self::Showers => "showers",
            Self::SnowShowers => "snow_showers",
            Self::Thunder => "thunder",
            Self::ThunderHail => "thunder_hail",
            Self::Unknown => "unknown",
        }
    }
}

pub fn condition(wmo: u32) -> Condition {
    match wmo {
        0 => Condition::Clear,
        1 => Condition::MainlyClear,
        2 => Condition::PartlyCloudy,
        3 => Condition::Overcast,
        45 | 48 => Condition::Fog,
        51 | 53 | 55 => Condition::Drizzle,
        56 | 57 => Condition::FreezingDrizzle,
        61 | 63 | 65 => Condition::Rain,
        66 | 67 => Condition::FreezingRain,
        71 | 73 | 75 => Condition::Snow,
        77 => Condition::SnowGrains,
        80..=82 => Condition::Showers,
        85 | 86 => Condition::SnowShowers,
        95 => Condition::Thunder,
        96 | 99 => Condition::ThunderHail,
        _ => Condition::Unknown,
    }
}

#[derive(Debug, Error, PartialEq)]
pub enum ParseError {
    #[error("not JSON: {0}")]
    Json(String),
    #[error("missing or unreadable field {0}")]
    Missing(&'static str),
}

/// `YYYY-MM-DDTHH:MM`, optionally with seconds and an offset suffix (the offset is ignored).
pub fn local_time(s: &str) -> Option<NaiveDateTime> {
    let naive = s.get(..16)?;
    NaiveDateTime::parse_from_str(naive, "%Y-%m-%dT%H:%M").ok()
}

pub fn local_date(s: &str) -> Option<NaiveDate> {
    NaiveDate::parse_from_str(s.get(..10)?, "%Y-%m-%d").ok()
}

#[derive(Debug, Clone, PartialEq)]
pub struct Now {
    pub time: NaiveDateTime,
    pub temp: f64,
    pub feels: f64,
    pub humidity: Option<f64>,
    pub is_day: bool,
    pub wmo: u32,
    pub wind_kmh: f64,
    pub gust_kmh: Option<f64>,
}

#[derive(Debug, Clone, PartialEq)]
pub struct Hour {
    pub time: NaiveDateTime,
    pub temp: f64,
    pub feels: Option<f64>,
    pub wmo: u32,
    pub is_day: bool,
    pub pop: Option<f64>,
    pub uv: Option<f64>,
}

#[derive(Debug, Clone, PartialEq)]
pub struct Day {
    pub date: NaiveDate,
    pub min: f64,
    pub max: f64,
    pub wmo: u32,
    pub pop: Option<f64>,
    pub sunrise: Option<NaiveDateTime>,
    pub sunset: Option<NaiveDateTime>,
    pub daylight_s: Option<f64>,
    pub uv_max: Option<f64>,
}

/// Precipitation of one 15-minute step, in mm (the preceding 15 minutes, per Open-Meteo).
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct Step {
    pub time: NaiveDateTime,
    pub precip_mm: f64,
}

/// A parsed forecast in the place's local clock. Missing optional values stay `None`:
/// Shōjiki, a value the API did not send is not shown as zero.
#[derive(Debug, Clone, PartialEq)]
pub struct Forecast {
    pub timezone: String,
    pub utc_offset_s: i64,
    pub now: Now,
    pub hours: Vec<Hour>,
    pub days: Vec<Day>,
    pub steps: Vec<Step>,
}

#[derive(Deserialize)]
struct RawForecast {
    timezone: Option<String>,
    utc_offset_seconds: i64,
    current: RawCurrent,
    hourly: RawHourly,
    daily: RawDaily,
    #[serde(default)]
    minutely_15: Option<RawMinutely>,
}

#[derive(Deserialize)]
struct RawCurrent {
    time: String,
    temperature_2m: f64,
    #[serde(default)]
    apparent_temperature: Option<f64>,
    #[serde(default)]
    relative_humidity_2m: Option<f64>,
    #[serde(default)]
    is_day: Option<u8>,
    weather_code: u32,
    wind_speed_10m: f64,
    #[serde(default)]
    wind_gusts_10m: Option<f64>,
}

#[derive(Deserialize)]
struct RawHourly {
    time: Vec<String>,
    temperature_2m: Vec<Option<f64>>,
    #[serde(default)]
    apparent_temperature: Vec<Option<f64>>,
    #[serde(default)]
    precipitation_probability: Vec<Option<f64>>,
    #[serde(default)]
    weather_code: Vec<Option<u32>>,
    #[serde(default)]
    is_day: Vec<Option<u8>>,
    #[serde(default)]
    uv_index: Vec<Option<f64>>,
}

#[derive(Deserialize)]
struct RawDaily {
    time: Vec<String>,
    #[serde(default)]
    weather_code: Vec<Option<u32>>,
    temperature_2m_max: Vec<Option<f64>>,
    temperature_2m_min: Vec<Option<f64>>,
    #[serde(default)]
    precipitation_probability_max: Vec<Option<f64>>,
    #[serde(default)]
    sunrise: Vec<Option<String>>,
    #[serde(default)]
    sunset: Vec<Option<String>>,
    #[serde(default)]
    daylight_duration: Vec<Option<f64>>,
    #[serde(default)]
    uv_index_max: Vec<Option<f64>>,
}

#[derive(Deserialize)]
struct RawMinutely {
    time: Vec<String>,
    precipitation: Vec<Option<f64>>,
}

fn at<T: Clone>(v: &[T], i: usize) -> Option<T> {
    v.get(i).cloned()
}

fn flat<T>(v: Option<Option<T>>) -> Option<T> {
    v.flatten()
}

pub fn parse_forecast(body: &str) -> Result<Forecast, ParseError> {
    let raw: RawForecast =
        serde_json::from_str(body).map_err(|e| ParseError::Json(e.to_string()))?;
    let now_time = local_time(&raw.current.time).ok_or(ParseError::Missing("current.time"))?;
    let now = Now {
        time: now_time,
        temp: raw.current.temperature_2m,
        feels: raw
            .current
            .apparent_temperature
            .unwrap_or(raw.current.temperature_2m),
        humidity: raw.current.relative_humidity_2m,
        is_day: raw.current.is_day.unwrap_or(1) == 1,
        wmo: raw.current.weather_code,
        wind_kmh: raw.current.wind_speed_10m,
        gust_kmh: raw.current.wind_gusts_10m,
    };

    let h = &raw.hourly;
    let hours = h
        .time
        .iter()
        .enumerate()
        .filter_map(|(i, t)| {
            let time = local_time(t)?;
            let temp = flat(h.temperature_2m.get(i).cloned())?;
            Some(Hour {
                time,
                temp,
                feels: flat(at(&h.apparent_temperature, i)),
                wmo: flat(at(&h.weather_code, i)).unwrap_or(0),
                is_day: flat(at(&h.is_day, i)).unwrap_or(1) == 1,
                pop: flat(at(&h.precipitation_probability, i)),
                uv: flat(at(&h.uv_index, i)),
            })
        })
        .collect();

    let d = &raw.daily;
    let days = d
        .time
        .iter()
        .enumerate()
        .filter_map(|(i, t)| {
            let date = local_date(t)?;
            let min = flat(at(&d.temperature_2m_min, i))?;
            let max = flat(at(&d.temperature_2m_max, i))?;
            Some(Day {
                date,
                min,
                max,
                wmo: flat(at(&d.weather_code, i)).unwrap_or(0),
                pop: flat(at(&d.precipitation_probability_max, i)),
                sunrise: flat(at(&d.sunrise, i)).as_deref().and_then(local_time),
                sunset: flat(at(&d.sunset, i)).as_deref().and_then(local_time),
                daylight_s: flat(at(&d.daylight_duration, i)),
                uv_max: flat(at(&d.uv_index_max, i)),
            })
        })
        .collect();

    let steps = raw
        .minutely_15
        .map(|m| {
            m.time
                .iter()
                .enumerate()
                .filter_map(|(i, t)| {
                    Some(Step {
                        time: local_time(t)?,
                        precip_mm: flat(m.precipitation.get(i).cloned())?,
                    })
                })
                .collect()
        })
        .unwrap_or_default();

    Ok(Forecast {
        timezone: raw.timezone.unwrap_or_default(),
        utc_offset_s: raw.utc_offset_seconds,
        now,
        hours,
        days,
        steps,
    })
}

#[derive(Deserialize)]
struct RawGeocode {
    #[serde(default)]
    results: Vec<RawPlace>,
}

#[derive(Deserialize)]
struct RawPlace {
    id: u64,
    name: String,
    latitude: f64,
    longitude: f64,
    #[serde(default)]
    admin1: Option<String>,
    #[serde(default)]
    country: Option<String>,
    #[serde(default)]
    country_code: Option<String>,
    #[serde(default)]
    timezone: Option<String>,
}

/// Geocoding results. A search with no match has no `results` key, which is an empty list, not
/// an error.
pub fn parse_geocode(body: &str) -> Result<Vec<Place>, ParseError> {
    let raw: RawGeocode =
        serde_json::from_str(body).map_err(|e| ParseError::Json(e.to_string()))?;
    Ok(raw
        .results
        .into_iter()
        .map(|r| Place {
            id: r.id.to_string(),
            name: r.name,
            admin: r.admin1.filter(|s| !s.is_empty()),
            country: r.country.filter(|s| !s.is_empty()),
            country_code: r.country_code.filter(|s| !s.is_empty()),
            lat: r.latitude,
            lon: r.longitude,
            tz: r.timezone.unwrap_or_default(),
        })
        .collect())
}

#[cfg(test)]
mod tests {
    use super::*;

    const FORECAST: &str = include_str!("../tests/fixtures/forecast_tokyo.json");
    const GEOCODE_JA: &str = include_str!("../tests/fixtures/geocode_tokyo_ja.json");
    const GEOCODE_NONE: &str = include_str!("../tests/fixtures/geocode_none.json");

    #[test]
    fn forecast_parses_now_hours_days_and_steps() {
        let f = parse_forecast(FORECAST).unwrap();
        assert_eq!(f.timezone, "Asia/Tokyo");
        assert_eq!(f.utc_offset_s, 32400);
        assert_eq!(f.now.time, local_time("2026-10-09T14:00").unwrap());
        assert_eq!(f.now.temp, 21.4);
        assert_eq!(f.now.feels, 20.1);
        assert_eq!(f.now.humidity, Some(58.0));
        assert!(f.now.is_day);
        assert_eq!(condition(f.now.wmo), Condition::PartlyCloudy);
        assert_eq!(f.hours.len(), 24);
        assert_eq!(f.hours[2].pop, Some(10.0));
        assert_eq!(f.days.len(), 7);
        assert_eq!(f.days[0].date, local_date("2026-10-09").unwrap());
        assert_eq!(f.days[0].sunrise, local_time("2026-10-09T05:43"));
        assert_eq!(f.days[0].daylight_s, Some(41340.0));
        assert_eq!(f.steps.len(), 8);
        assert_eq!(f.steps[4].precip_mm, 0.1);
    }

    #[test]
    fn times_with_offset_suffix_keep_their_local_clock() {
        assert_eq!(
            local_time("2026-10-09T14:00+09:00"),
            local_time("2026-10-09T14:00")
        );
        assert_eq!(
            local_time("2026-10-09T14:00:00"),
            local_time("2026-10-09T14:00")
        );
        assert_eq!(local_time("garbage"), None);
    }

    #[test]
    fn a_missing_current_time_is_an_error_not_a_zero() {
        let broken = FORECAST.replace("\"time\": \"2026-10-09T14:00\"", "\"time\": \"\"");
        assert_eq!(
            parse_forecast(&broken),
            Err(ParseError::Missing("current.time"))
        );
        assert!(matches!(parse_forecast("{}"), Err(ParseError::Json(_))));
    }

    #[test]
    fn null_daily_sun_times_stay_absent() {
        let polar = FORECAST.replace("\"2026-10-09T05:43\"", "null");
        let f = parse_forecast(&polar).unwrap();
        assert_eq!(f.days[0].sunrise, None);
        assert!(f.days[0].sunset.is_some());
    }

    #[test]
    fn geocode_results_keep_names_admin_and_zone() {
        let places = parse_geocode(GEOCODE_JA).unwrap();
        assert_eq!(places.len(), 2);
        assert_eq!(places[0].id, "1850147");
        assert_eq!(places[0].name, "東京");
        assert_eq!(places[0].admin.as_deref(), Some("東京都"));
        assert_eq!(places[0].country_code.as_deref(), Some("JP"));
        assert_eq!(places[0].tz, "Asia/Tokyo");
        assert_eq!(places[1].country.as_deref(), Some("アメリカ合衆国"));
    }

    #[test]
    fn a_geocode_without_matches_is_an_empty_list() {
        assert_eq!(parse_geocode(GEOCODE_NONE), Ok(Vec::new()));
    }

    #[test]
    fn wmo_codes_map_to_conditions_and_unknown_stays_unknown() {
        assert_eq!(condition(0), Condition::Clear);
        assert_eq!(condition(3), Condition::Overcast);
        assert_eq!(condition(48), Condition::Fog);
        assert_eq!(condition(63), Condition::Rain);
        assert_eq!(condition(81), Condition::Showers);
        assert_eq!(condition(86), Condition::SnowShowers);
        assert_eq!(condition(99), Condition::ThunderHail);
        assert_eq!(condition(4), Condition::Unknown);
        assert_eq!(Condition::FreezingRain.key(), "freezing_rain");
    }

    #[test]
    fn units_convert_and_locale_picks_the_system() {
        assert_eq!(Units::Metric.temp(20.0), 20.0);
        assert!((Units::Imperial.temp(20.0) - 68.0).abs() < 1e-9);
        assert!((Units::Imperial.wind(10.0) - 6.21371).abs() < 1e-6);
        assert_eq!(units_from_locale("en_US.UTF-8"), Units::Imperial);
        assert_eq!(units_from_locale("en_GB.UTF-8"), Units::Metric);
        assert_eq!(units_from_locale("ja_JP.UTF-8"), Units::Metric);
        assert_eq!(units_from_locale("C"), Units::Metric);
        assert_eq!(units_from_locale(""), Units::Metric);
    }

    #[test]
    fn query_text_is_encoded_and_language_is_sanitised() {
        assert_eq!(encode("東京 & Co?"), "%E6%9D%B1%E4%BA%AC%20%26%20Co%3F");
        let url = geocode_url(GEOCODE_URL, " Tokyo&language=xx ", "ja-JP.UTF-8");
        assert!(url.contains("name=Tokyo%26language%3Dxx&"), "{url}");
        assert!(url.ends_with("&language=ja&format=json"), "{url}");
        assert_eq!(lang_tag("ZZ9"), "en");
        assert_eq!(lang_tag(""), "en");
    }

    #[test]
    fn forecast_url_asks_for_metric_and_local_times() {
        let url = forecast_url(FORECAST_URL, 35.6895, 139.69171);
        assert!(url.starts_with(
            "https://api.open-meteo.com/v1/forecast?latitude=35.6895&longitude=139.6917&"
        ));
        assert!(url.contains("minutely_15=precipitation&forecast_minutely_15=8"));
        assert!(url.contains("timezone=auto&timeformat=iso8601"));
        assert!(url.contains("temperature_unit=celsius&precipitation_unit=mm"));
    }
}
