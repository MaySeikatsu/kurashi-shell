//! The `mod.calendar` document (docs/ux/calendar.md "Document"): `{available, state, reason?, today, from, to,
//! sources: [{name, kind, state, reason?, events, color?, fetched_at?}], days: {"YYYY-MM-DD": [{id, title, start, end,
//! all_day, location?, calendar, color?}]}}`. Times are unix seconds; the views compute "now" themselves, so the
//! document changes only when the events or the day do. A multi-day event is listed on each day it touches
//! (DankMaterialShell's `_rebuildEventsByDate`), with its whole span.

use std::collections::BTreeMap;

use jiff::tz::TimeZone;
use serde_json::{Map, Value, json};

use crate::day;
use crate::expand::{Occ, Window};

pub const STATE_NONE: &str = "none";
pub const STATE_LOADING: &str = "loading";
pub const STATE_READY: &str = "ready";
pub const STATE_ERROR: &str = "error";
pub const REASON_NO_SOURCE: &str = "mod-calendar.no_source";
pub const REASON_ALL_FAILED: &str = "mod-calendar.error.all";

/// A source as the document lists it.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Status {
    pub name: String,
    /// `file`, `folder`, `feed` or `khal`.
    pub kind: &'static str,
    /// `ready`, `loading`, `missing`, `offline`, `error`, `unavailable`.
    pub state: &'static str,
    pub reason: Option<&'static str>,
    pub events: usize,
    pub color: Option<String>,
    /// A feed's copy in use: when it was fetched.
    pub fetched_at: Option<i64>,
}

/// One instance with the calendar it belongs to.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Entry {
    pub occ: Occ,
    pub calendar: String,
    pub color: Option<String>,
}

/// FNV-1a: a short stable id from the calendar and the UID (UIDs are long and may be e-mail addresses).
fn fnv(s: &str) -> u64 {
    s.bytes().fold(0xcbf2_9ce4_8422_2325, |h, b| {
        (h ^ u64::from(b)).wrapping_mul(0x0100_0000_01b3)
    })
}

pub fn entry_id(e: &Entry) -> String {
    format!(
        "{:012x}-{}",
        fnv(&format!("{}\u{1f}{}", e.calendar, e.occ.uid)) & 0xffff_ffff_ffff,
        e.occ.start
    )
}

fn event(e: &Entry) -> Value {
    let mut m = Map::new();
    m.insert("id".into(), json!(entry_id(e)));
    m.insert("title".into(), json!(e.occ.title));
    m.insert("start".into(), json!(e.occ.start));
    m.insert("end".into(), json!(e.occ.end));
    m.insert("all_day".into(), json!(e.occ.all_day));
    if let Some(l) = &e.occ.location {
        m.insert("location".into(), json!(l));
    }
    m.insert("calendar".into(), json!(e.calendar));
    if let Some(c) = &e.color {
        m.insert("color".into(), json!(c));
    }
    Value::Object(m)
}

/// The local days an instance touches, clipped to the window.
pub fn days_of(occ: &Occ, local: &TimeZone, win: &Window) -> std::ops::Range<i32> {
    let first = day::civil_of(local, occ.start).0;
    let last = if occ.end > occ.start {
        day::civil_of(local, occ.end - 1).0
    } else {
        first
    };
    first.max(win.from_day)..(last + 1).min(win.to_day)
}

/// The days map, each day sorted: all-day first, then by start, then by title.
pub fn days(entries: &[Entry], local: &TimeZone, win: &Window) -> BTreeMap<String, Vec<Value>> {
    let mut by_day: BTreeMap<i32, Vec<&Entry>> = BTreeMap::new();
    for e in entries {
        for d in days_of(&e.occ, local, win) {
            by_day.entry(d).or_default().push(e);
        }
    }
    by_day
        .into_iter()
        .map(|(d, mut list)| {
            list.sort_by(|a, b| {
                (!a.occ.all_day, a.occ.start, &a.occ.title, a.occ.end).cmp(&(
                    !b.occ.all_day,
                    b.occ.start,
                    &b.occ.title,
                    b.occ.end,
                ))
            });
            list.dedup_by(|a, b| entry_id(a) == entry_id(b));
            (day::iso(d), list.into_iter().map(event).collect())
        })
        .collect()
}

pub fn build(
    today: i32,
    win: &Window,
    local: &TimeZone,
    sources: &[Status],
    entries: &[Entry],
) -> Value {
    let (state, reason) = if sources.is_empty() {
        (STATE_NONE, Some(REASON_NO_SOURCE))
    } else if sources.iter().all(|s| s.state == STATE_LOADING) {
        (STATE_LOADING, None)
    } else if entries.is_empty()
        && sources
            .iter()
            .all(|s| !matches!(s.state, STATE_READY | STATE_LOADING) && s.fetched_at.is_none())
    {
        (STATE_ERROR, Some(REASON_ALL_FAILED))
    } else {
        (STATE_READY, None)
    };
    let mut m = Map::new();
    m.insert("available".into(), json!(true));
    m.insert("state".into(), json!(state));
    if let Some(r) = reason {
        m.insert("reason".into(), json!(r));
    }
    m.insert("today".into(), json!(day::iso(today)));
    m.insert("from".into(), json!(day::iso(win.from_day)));
    m.insert("to".into(), json!(day::iso(win.to_day - 1)));
    let list: Vec<Value> = sources
        .iter()
        .map(|s| {
            let mut o = Map::new();
            o.insert("name".into(), json!(s.name));
            o.insert("kind".into(), json!(s.kind));
            o.insert("state".into(), json!(s.state));
            if let Some(r) = s.reason {
                o.insert("reason".into(), json!(r));
            }
            o.insert("events".into(), json!(s.events));
            if let Some(c) = &s.color {
                o.insert("color".into(), json!(c));
            }
            if let Some(t) = s.fetched_at {
                o.insert("fetched_at".into(), json!(t));
            }
            Value::Object(o)
        })
        .collect();
    m.insert("sources".into(), Value::Array(list));
    let days = days(entries, local, win);
    m.insert("days".into(), json!(days));
    Value::Object(m)
}
