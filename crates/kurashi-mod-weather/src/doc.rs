//! The `mod.weather` document (docs/ux/weather.md, "Contract notes"): what the views show, computed
//! by the daemon. The frontend maps the condition key to a glyph and formats; it never decides
//! freshness, units or which value is in effect (rule 1; Shōjiki: nothing stale looks fresh).

use chrono::{DateTime, NaiveDateTime, Timelike};
use serde_json::{Map, Value, json};

use crate::api::{self, Day, Forecast, Hour, Units};
use crate::places::Place;
use crate::rain::{self, Nowcast};

/// Past this age, temperatures are not sent: the panel says "last known … at HH:MM" only.
pub const VERY_STALE_AFTER_S: i64 = 6 * 3600;
/// Hours and days the document carries (the panel shows a 24 h strip and 7 days).
const HOURS: usize = 24;
const DAYS: usize = 7;
/// A day's polar note: daylight this long (seconds) means the sun never sets or never rises.
const POLAR_DAY_S: f64 = 86_000.0;
const POLAR_NIGHT_S: f64 = 60.0;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Tier {
    Fresh,
    Aging,
    Stale,
    VeryStale,
}

impl Tier {
    pub fn key(self) -> &'static str {
        match self {
            Self::Fresh => "fresh",
            Self::Aging => "aging",
            Self::Stale => "stale",
            Self::VeryStale => "very_stale",
        }
    }
}

/// Fresh up to one refresh, aging up to two, stale up to six hours, very stale after that.
pub fn tier(age_s: i64, refresh_s: i64) -> Tier {
    let aging_until = (2 * refresh_s).min(VERY_STALE_AFTER_S);
    if age_s <= refresh_s {
        Tier::Fresh
    } else if age_s <= aging_until {
        Tier::Aging
    } else if age_s <= VERY_STALE_AFTER_S {
        Tier::Stale
    } else {
        Tier::VeryStale
    }
}

/// The unix time at which data fetched at `fetched_at` changes tier next, after `now`.
pub fn next_tier_change(fetched_at: i64, refresh_s: i64, now: i64) -> Option<i64> {
    [
        refresh_s,
        (2 * refresh_s).min(VERY_STALE_AFTER_S),
        VERY_STALE_AFTER_S,
    ]
    .into_iter()
    .map(|age| fetched_at + age + 1)
    .find(|t| *t > now)
}

/// A forecast the daemon holds for one place, and the unix time it was fetched.
#[derive(Debug, Clone)]
pub struct Data {
    pub forecast: Forecast,
    pub fetched_at: i64,
}

/// Why the last fetch for a place failed. `reason` is an i18n key, `next_try_at` the unix time
/// of the retry (backoff), `count` the failures in a row.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Failure {
    pub reason: &'static str,
    pub count: u32,
    pub next_try_at: i64,
}

pub struct Input<'a> {
    pub place: Option<&'a Place>,
    pub data: Option<&'a Data>,
    pub failure: Option<&'a Failure>,
    pub now: i64,
    pub refresh_s: i64,
    pub units: Units,
    /// `setting` when the user picked the unit system, `locale` when it comes from the locale.
    pub units_from: &'static str,
    pub template: &'a str,
}

/// The document for the current state. Without a place there is nothing to show but the call to
/// action; without data the state says loading or why the first fetch failed.
pub fn build(i: &Input) -> Value {
    let mut doc = Map::new();
    doc.insert("template".into(), json!(i.template));
    doc.insert("refresh_min".into(), json!(i.refresh_s / 60));
    doc.insert("units".into(), json!(i.units.key()));
    doc.insert("units_from".into(), json!(i.units_from));
    let Some(place) = i.place else {
        doc.insert("available".into(), json!(false));
        doc.insert("reason".into(), json!("mod-weather.no_location"));
        return Value::Object(doc);
    };
    match i.data {
        None => {
            doc.insert("available".into(), json!(false));
            doc.insert("place".into(), place_json(place, &place.tz));
            match i.failure {
                Some(f) => {
                    doc.insert("reason".into(), json!(f.reason));
                    doc.insert("next_try_s".into(), json!((f.next_try_at - i.now).max(0)));
                }
                None => {
                    doc.insert("reason".into(), json!("mod-weather.loading"));
                }
            }
        }
        Some(d) => fill(&mut doc, d, i, place),
    }
    Value::Object(doc)
}

fn fill(doc: &mut Map<String, Value>, d: &Data, i: &Input, place: &Place) {
    let f = &d.forecast;
    let offset = f.utc_offset_s;
    let local_now = local_at(i.now, offset);
    let age_s = (i.now - d.fetched_at).max(0);
    let tier = tier(age_s, i.refresh_s);
    let u = i.units;

    doc.insert("available".into(), json!(true));
    doc.insert("place".into(), place_json(place, &f.timezone));
    doc.insert("updated_at".into(), json!(d.fetched_at));
    doc.insert(
        "updated_local".into(),
        json!(fmt(local_at(d.fetched_at, offset))),
    );
    doc.insert("age_s".into(), json!(age_s));
    doc.insert("tier".into(), json!(tier.key()));
    if let Some(fail) = i.failure {
        doc.insert("reason".into(), json!(fail.reason));
        doc.insert(
            "next_try_s".into(),
            json!((fail.next_try_at - i.now).max(0)),
        );
    }
    if tier == Tier::VeryStale {
        return;
    }

    let n = &f.now;
    let mut now = Map::new();
    now.insert("temp".into(), json!(u.temp(n.temp)));
    now.insert("feels".into(), json!(u.temp(n.feels)));
    now.insert("code".into(), json!(api::condition(n.wmo).key()));
    now.insert("is_day".into(), json!(n.is_day));
    now.insert("wind".into(), json!(u.wind(n.wind_kmh)));
    put(&mut now, "gust", n.gust_kmh.map(|g| u.wind(g)));
    put(&mut now, "humidity", n.humidity);
    let this_hour = floor_hour(local_now);
    put(
        &mut now,
        "uv",
        f.hours
            .iter()
            .find(|h| h.time == this_hour)
            .and_then(|h| h.uv),
    );
    doc.insert("now".into(), Value::Object(now));

    let hours: Vec<Value> = f
        .hours
        .iter()
        .filter(|h| h.time >= this_hour)
        .take(HOURS)
        .map(|h| hour_json(h, u))
        .collect();
    doc.insert("hours".into(), json!(hours));

    let today = local_now.date();
    let days: Vec<Value> = f
        .days
        .iter()
        .filter(|day| day.date >= today)
        .take(DAYS)
        .map(|day| day_json(day, u))
        .collect();
    doc.insert("days".into(), json!(days));

    if let Some(sun) = f.days.iter().find(|day| day.date == today).map(sun_json) {
        if !sun.is_empty() {
            doc.insert("sun".into(), Value::Object(sun));
        }
    }

    if let Nowcast::Soon {
        from,
        in_min,
        intensity,
    } = rain::nowcast(&f.steps, local_now)
    {
        doc.insert(
            "rain_soon".into(),
            json!({"from": fmt(from), "in_min": in_min, "intensity": intensity.key()}),
        );
    }
}

fn hour_json(h: &Hour, u: Units) -> Value {
    let mut m = Map::new();
    m.insert("t".into(), json!(fmt(h.time)));
    m.insert("temp".into(), json!(u.temp(h.temp)));
    m.insert("code".into(), json!(api::condition(h.wmo).key()));
    m.insert("is_day".into(), json!(h.is_day));
    put(&mut m, "pop", h.pop);
    Value::Object(m)
}

fn day_json(d: &Day, u: Units) -> Value {
    let mut m = Map::new();
    m.insert("date".into(), json!(d.date.format("%Y-%m-%d").to_string()));
    m.insert("min".into(), json!(u.temp(d.min)));
    m.insert("max".into(), json!(u.temp(d.max)));
    m.insert("code".into(), json!(api::condition(d.wmo).key()));
    put(&mut m, "pop", d.pop);
    put(&mut m, "sunrise", d.sunrise.map(fmt));
    put(&mut m, "sunset", d.sunset.map(fmt));
    put(&mut m, "uv_max", d.uv_max);
    Value::Object(m)
}

/// Today's sun row: the times, or the polar note when the API sends no times for the day.
fn sun_json(d: &Day) -> Map<String, Value> {
    let mut m = Map::new();
    put(&mut m, "sunrise", d.sunrise.map(fmt));
    put(&mut m, "sunset", d.sunset.map(fmt));
    if d.sunrise.is_none() && d.sunset.is_none() {
        match d.daylight_s {
            Some(s) if s >= POLAR_DAY_S => {
                m.insert("polar".into(), json!("day"));
            }
            Some(s) if s <= POLAR_NIGHT_S => {
                m.insert("polar".into(), json!("night"));
            }
            _ => {}
        }
    }
    m
}

fn place_json(p: &Place, tz: &str) -> Value {
    let mut m = Map::new();
    m.insert("id".into(), json!(p.id));
    m.insert("name".into(), json!(p.name));
    put(&mut m, "admin", p.admin.clone());
    put(&mut m, "country", p.country.clone());
    put(&mut m, "country_code", p.country_code.clone());
    m.insert("lat".into(), json!(p.lat));
    m.insert("lon".into(), json!(p.lon));
    m.insert(
        "tz".into(),
        json!(if tz.is_empty() { p.tz.as_str() } else { tz }),
    );
    Value::Object(m)
}

/// A value the API did not send stays out of the document (Shōjiki: absent, not zero).
fn put<T: serde::Serialize>(m: &mut Map<String, Value>, key: &str, value: Option<T>) {
    if let Some(v) = value {
        m.insert(key.into(), json!(v));
    }
}

/// The place's local clock at a unix time, from its UTC offset (the API sends the offset in
/// effect now; zones with DST are read with today's offset, which is what the panel needs).
pub fn local_at(unix: i64, offset_s: i64) -> NaiveDateTime {
    DateTime::from_timestamp(unix + offset_s, 0).map_or(NaiveDateTime::MIN, |d| d.naive_utc())
}

fn floor_hour(t: NaiveDateTime) -> NaiveDateTime {
    t.date().and_hms_opt(t.hour(), 0, 0).unwrap_or(t)
}

/// `YYYY-MM-DDTHH:MM` in the place's clock. The frontend reads the time as the substring 11..16.
pub fn fmt(t: NaiveDateTime) -> String {
    t.format("%Y-%m-%dT%H:%M").to_string()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn tiers_follow_the_refresh_and_the_six_hour_limit() {
        let r = 30 * 60;
        assert_eq!(tier(0, r), Tier::Fresh);
        assert_eq!(tier(r, r), Tier::Fresh);
        assert_eq!(tier(r + 1, r), Tier::Aging);
        assert_eq!(tier(2 * r, r), Tier::Aging);
        assert_eq!(tier(2 * r + 1, r), Tier::Stale);
        assert_eq!(tier(VERY_STALE_AFTER_S, r), Tier::Stale);
        assert_eq!(tier(VERY_STALE_AFTER_S + 1, r), Tier::VeryStale);
        // At the longest refresh the aging band reaches the six-hour mark: no empty stale band.
        assert_eq!(tier(VERY_STALE_AFTER_S, 180 * 60), Tier::Aging);
    }

    #[test]
    fn tier_changes_are_scheduled_after_now() {
        let fetched = 1_000_000;
        assert_eq!(
            next_tier_change(fetched, 1800, fetched),
            Some(fetched + 1801)
        );
        assert_eq!(
            next_tier_change(fetched, 1800, fetched + 1801),
            Some(fetched + 3601)
        );
        assert_eq!(
            next_tier_change(fetched, 1800, fetched + VERY_STALE_AFTER_S + 1),
            None
        );
    }

    #[test]
    fn a_polar_day_has_no_times_and_says_so() {
        let mut d = Day {
            date: chrono::NaiveDate::from_ymd_opt(2026, 6, 1).unwrap(),
            min: 3.0,
            max: 6.0,
            wmo: 3,
            pop: None,
            sunrise: None,
            sunset: None,
            daylight_s: Some(86_400.0),
            uv_max: None,
        };
        let m = sun_json(&d);
        assert_eq!(m["polar"], json!("day"));
        assert!(!m.contains_key("sunrise"));
        d.daylight_s = Some(0.0);
        assert_eq!(sun_json(&d)["polar"], json!("night"));
        d.daylight_s = Some(40_000.0);
        assert!(
            sun_json(&d).is_empty(),
            "no times and no polar reason: no sun row"
        );
    }

    #[test]
    fn local_clock_uses_the_place_offset() {
        // 2026-10-09T05:00:00Z in Tokyo (+9 h) is 14:00.
        let unix = DateTime::parse_from_rfc3339("2026-10-09T05:00:00Z")
            .unwrap()
            .timestamp();
        assert_eq!(fmt(local_at(unix, 32_400)), "2026-10-09T14:00");
    }
}
