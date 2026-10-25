//! A calendar's events as the instances that touch a window of days: recurrences expanded in the event's own zone (so
//! a 09:00 meeting stays at 09:00 across a DST change), EXDATE and cancelled instances removed, moved instances
//! (RECURRENCE-ID) shown where they were moved to. Times are unix seconds; all-day events run from local midnight to
//! local midnight (end exclusive).

use std::collections::{BTreeMap, BTreeSet};

use jiff::tz::TimeZone;

use crate::day;
use crate::ics::{Calendar, Event, Stamp, Zone};
use crate::rrule::Until;
use crate::tz::Resolver;

/// One instance of an event.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Occ {
    pub uid: String,
    pub title: String,
    pub location: Option<String>,
    pub description: Option<String>,
    pub start: i64,
    pub end: i64,
    pub all_day: bool,
}

/// The days the document covers, `[from_day, to_day)`, and their bounds as instants in the session's zone.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct Window {
    pub from_day: i32,
    pub to_day: i32,
    pub from: i64,
    pub to: i64,
}

impl Window {
    /// `today - before` up to and including `today + after`.
    pub fn around(local: &TimeZone, today: i32, before: i32, after: i32) -> Self {
        let (from_day, to_day) = (today - before, today + after + 1);
        Self {
            from_day,
            to_day,
            from: day::midnight(local, from_day),
            to: day::midnight(local, to_day),
        }
    }

    fn touches(&self, start: i64, end: i64) -> bool {
        if end > start {
            end > self.from && start < self.to
        } else {
            start >= self.from && start < self.to
        }
    }
}

struct Ctx<'a> {
    r: Resolver<'a>,
}

impl Ctx<'_> {
    fn zone(&mut self, z: &Zone) -> TimeZone {
        match z {
            Zone::Utc => TimeZone::UTC,
            Zone::Floating => self.r.local().clone(),
            Zone::Id(id) => self.r.get(id),
        }
    }

    /// The instant of a value; a date is its local midnight.
    fn at(&mut self, s: &Stamp) -> Option<i64> {
        match s {
            Stamp::Date(d) => Some(day::midnight(self.r.local(), *d)),
            Stamp::Time { day, secs, zone } => {
                let tz = self.zone(zone);
                day::instant(&tz, *day, *secs)
            }
        }
    }
}

/// The length of each instance: whole days for an all-day event, seconds otherwise.
enum Len {
    Days(i32),
    Secs(i64),
}

fn length(cx: &mut Ctx<'_>, e: &Event) -> Len {
    match &e.start {
        Stamp::Date(s) => {
            let days = match (&e.end, e.duration) {
                (Some(end), _) => end.day() - s,
                (None, Some(d)) => (d.days + d.secs / 86_400) as i32,
                (None, None) => 1,
            };
            Len::Days(days.max(1))
        }
        Stamp::Time { .. } => {
            let start = cx.at(&e.start);
            let secs = match (&e.end, e.duration) {
                (Some(end), _) => cx.at(end).zip(start).map_or(0, |(b, a)| b - a),
                (None, Some(d)) => d.days * 86_400 + d.secs,
                (None, None) => 0,
            };
            Len::Secs(secs.max(0))
        }
    }
}

/// The instances of a calendar that touch `win`, in no particular order.
pub fn expand(cal: &Calendar, local: &TimeZone, win: &Window) -> Vec<Occ> {
    let mut cx = Ctx {
        r: Resolver::new(&cal.zones, local),
    };
    let cancelled: BTreeSet<&str> = cal
        .events
        .iter()
        .filter(|e| e.cancelled && e.recurrence_id.is_none())
        .map(|e| e.uid.as_str())
        .collect();
    // Moved or cancelled instances by the instant they replace.
    let mut overrides: BTreeMap<&str, Vec<(Option<i64>, i32)>> = BTreeMap::new();
    for e in cal.events.iter().filter(|e| e.recurrence_id.is_some()) {
        let rid = e.recurrence_id.as_ref().expect("filtered");
        let at = cx.at(rid);
        overrides
            .entry(e.uid.as_str())
            .or_default()
            .push((at, rid.day()));
    }

    let mut out = Vec::new();
    for e in &cal.events {
        if cancelled.contains(e.uid.as_str()) {
            continue;
        }
        if e.recurrence_id.is_some() {
            if !e.cancelled {
                push_single(&mut cx, e, win, &mut out);
            }
            continue;
        }
        let Some(rule) = e.rrule.as_ref() else {
            push_single(&mut cx, e, win, &mut out);
            continue;
        };
        let all_day = matches!(e.start, Stamp::Date(_));
        let (secs, tz) = match &e.start {
            Stamp::Date(_) => (0, local.clone()),
            Stamp::Time { secs, zone, .. } => (*secs, cx.zone(zone)),
        };
        // Expand two days past the window in the event's zone: a zone far from ours can still land inside.
        let mut stop = day::civil_of(&tz, win.to).0 + 2;
        match &rule.until {
            Some(Until::Date(d)) => stop = stop.min(d + 1),
            Some(Until::Utc(t)) => stop = stop.min(day::civil_of(&tz, *t).0 + 1),
            Some(Until::Local(d, _)) => stop = stop.min(d + 1),
            None => {}
        }
        let until_at = match &rule.until {
            Some(Until::Utc(t)) => Some(*t),
            Some(Until::Local(d, s)) => day::instant(&tz, *d, *s),
            _ => None,
        };
        let until_day = match &rule.until {
            Some(Until::Date(d)) => Some(*d),
            _ => None,
        };
        let mut starts: Vec<(i32, Option<i64>)> = crate::rrule::days(rule, e.start.day(), stop)
            .into_iter()
            .filter(|d| until_day.is_none_or(|u| *d <= u))
            .map(|d| {
                let at = if all_day {
                    Some(day::midnight(local, d))
                } else {
                    day::instant(&tz, d, secs)
                };
                (d, at)
            })
            .filter(|(_, at)| until_at.is_none_or(|u| at.is_some_and(|a| a <= u)))
            .collect();
        for rd in &e.rdates {
            let at = cx.at(rd);
            if !starts.iter().any(|(_, a)| *a == at) {
                starts.push((rd.day(), at));
            }
        }
        let ex: Vec<(Option<i64>, i32, bool)> = e
            .exdates
            .iter()
            .map(|x| (cx.at(x), x.day(), matches!(x, Stamp::Date(_))))
            .collect();
        let moved = overrides.get(e.uid.as_str());
        let len = length(&mut cx, e);
        for (d, at) in starts {
            let Some(at) = at else { continue };
            let hit = |list: &[(Option<i64>, i32, bool)]| {
                list.iter()
                    .any(|(xa, xd, is_date)| if *is_date { *xd == d } else { *xa == Some(at) })
            };
            if hit(&ex) {
                continue;
            }
            if moved.is_some_and(|m| {
                m.iter()
                    .any(|(ra, rd)| *ra == Some(at) || (all_day && *rd == d))
            }) {
                continue;
            }
            let end = match len {
                Len::Days(n) => day::midnight(local, d + n),
                Len::Secs(s) => at + s,
            };
            if win.touches(at, end) {
                out.push(Occ {
                    uid: e.uid.clone(),
                    title: e.summary.clone(),
                    location: e.location.clone(),
                    description: e.description.clone(),
                    start: at,
                    end,
                    all_day,
                });
            }
        }
    }
    out
}

fn push_single(cx: &mut Ctx<'_>, e: &Event, win: &Window, out: &mut Vec<Occ>) {
    let Some(start) = cx.at(&e.start) else {
        return;
    };
    let all_day = matches!(e.start, Stamp::Date(_));
    let end = match length(cx, e) {
        Len::Days(n) => day::midnight(cx.r.local(), e.start.day() + n),
        Len::Secs(s) => start + s,
    };
    if win.touches(start, end) {
        out.push(Occ {
            uid: e.uid.clone(),
            title: e.summary.clone(),
            location: e.location.clone(),
            description: e.description.clone(),
            start,
            end,
            all_day,
        });
    }
}
