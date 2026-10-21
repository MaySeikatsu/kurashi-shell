//! TZID → a time zone. In order: the IANA name (jiff's database: the system's zoneinfo, the bundled copy where the
//! system has none), the name's IANA tail (`/mozilla.org/20050126_1/Europe/Berlin`), the file's own VTIMEZONE (Outlook's
//! "W. Europe Standard Time" and friends) turned into a POSIX TZ rule, and finally the session's zone. Resolved once
//! per calendar and name.

use std::collections::BTreeMap;

use jiff::tz::{Offset, TimeZone};

use crate::ics::{VTimezone, ZonePart};
use crate::rrule::Freq;

pub struct Resolver<'a> {
    zones: &'a BTreeMap<String, VTimezone>,
    local: &'a TimeZone,
    cache: BTreeMap<String, TimeZone>,
}

impl<'a> Resolver<'a> {
    pub fn new(zones: &'a BTreeMap<String, VTimezone>, local: &'a TimeZone) -> Self {
        Self {
            zones,
            local,
            cache: BTreeMap::new(),
        }
    }

    pub fn local(&self) -> &TimeZone {
        self.local
    }

    pub fn get(&mut self, tzid: &str) -> TimeZone {
        if let Some(tz) = self.cache.get(tzid) {
            return tz.clone();
        }
        let tz = by_name(tzid)
            .or_else(|| self.zones.get(tzid).and_then(from_vtimezone))
            .unwrap_or_else(|| self.local.clone());
        self.cache.insert(tzid.to_owned(), tz.clone());
        tz
    }
}

/// The IANA zone of a TZID, also when a prefix wraps it (Mozilla, Evolution `/softwarestudio.org/…`).
fn by_name(tzid: &str) -> Option<TimeZone> {
    let name = tzid.trim().trim_matches('"');
    if let Ok(tz) = TimeZone::get(name) {
        return Some(tz);
    }
    let parts: Vec<&str> = name.split('/').filter(|p| !p.is_empty()).collect();
    (2..=3)
        .filter(|n| parts.len() > *n)
        .find_map(|n| TimeZone::get(&parts[parts.len() - n..].join("/")).ok())
}

/// `±hh[:mm[:ss]]` in POSIX's sign (west positive).
fn posix_offset(east: i32) -> String {
    let west = -east;
    let sign = if west < 0 { "-" } else { "" };
    let a = west.unsigned_abs();
    let (h, m, s) = (a / 3600, a / 60 % 60, a % 60);
    match (m, s) {
        (0, 0) => format!("{sign}{h}"),
        (_, 0) => format!("{sign}{h}:{m:02}"),
        _ => format!("{sign}{h}:{m:02}:{s:02}"),
    }
}

/// `Mm.w.d/time` of a yearly rule with one BYMONTH and one BYDAY (ordinal 1..4 or -1), the transition's local time.
fn posix_rule(p: &ZonePart) -> Option<String> {
    let r = p.rrule.as_ref()?;
    if r.freq != Freq::Yearly || r.by_month.len() != 1 || r.by_day.len() != 1 {
        return None;
    }
    let (ord, wd) = r.by_day[0];
    let week = match ord {
        1..=4 => ord as u32,
        -1 | 5 => 5,
        _ => return None,
    };
    // POSIX numbers days from Sunday = 0; ours start at Monday = 0.
    let d = (wd + 1) % 7;
    let t = p.start_secs;
    let time = format!("{}:{:02}:{:02}", t / 3600, t / 60 % 60, t % 60);
    Some(format!("M{}.{week}.{d}/{time}", r.by_month[0]))
}

/// A VTIMEZONE as a POSIX TZ rule from its latest STANDARD and DAYLIGHT parts; a zone without daylight saving (or
/// with rules POSIX cannot say) is the latest part's fixed offset.
pub fn from_vtimezone(z: &VTimezone) -> Option<TimeZone> {
    let latest = |daylight: bool| {
        z.parts
            .iter()
            .filter(|p| p.daylight == daylight)
            .max_by_key(|p| (p.start_day, p.start_secs))
    };
    let std = latest(false).or_else(|| latest(true))?;
    if let Some(dst) = latest(true).filter(|_| !std.daylight) {
        if let (Some(on), Some(off)) = (posix_rule(dst), posix_rule(std)) {
            let rule = format!(
                "STD{}DST{},{on},{off}",
                posix_offset(std.to),
                posix_offset(dst.to)
            );
            if let Ok(tz) = TimeZone::posix(&rule) {
                return Some(tz);
            }
        }
    }
    Offset::from_seconds(std.to).ok().map(TimeZone::fixed)
}

/// The zone's offset at a moment, for tests and the doc's sanity checks.
pub fn offset_at(tz: &TimeZone, unix: i64) -> i32 {
    jiff::Timestamp::from_second(unix).map_or(0, |t| tz.to_offset(t).seconds())
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::ics;

    const OUTLOOK: &str = "BEGIN:VCALENDAR\nBEGIN:VTIMEZONE\nTZID:W. Europe Standard Time\nBEGIN:STANDARD\nDTSTART:16010101T030000\nTZOFFSETFROM:+0200\nTZOFFSETTO:+0100\nRRULE:FREQ=YEARLY;BYDAY=-1SU;BYMONTH=10\nEND:STANDARD\nBEGIN:DAYLIGHT\nDTSTART:16010101T020000\nTZOFFSETFROM:+0100\nTZOFFSETTO:+0200\nRRULE:FREQ=YEARLY;BYDAY=-1SU;BYMONTH=3\nEND:DAYLIGHT\nEND:VTIMEZONE\nEND:VCALENDAR\n";

    #[test]
    fn outlook_vtimezone_becomes_a_dst_rule() {
        let cal = ics::parse(OUTLOOK).unwrap();
        let tz = from_vtimezone(&cal.zones["W. Europe Standard Time"]).unwrap();
        // 2026-07-01 12:00 UTC: summer time (+2); 2026-12-01: winter (+1).
        assert_eq!(offset_at(&tz, 1_782_907_200), 7200);
        assert_eq!(offset_at(&tz, 1_796_126_400), 3600);
        let local = TimeZone::UTC;
        let mut r = Resolver::new(&cal.zones, &local);
        assert_eq!(
            offset_at(&r.get("W. Europe Standard Time"), 1_782_907_200),
            7200
        );
        // An unknown name without a VTIMEZONE is the session's zone.
        assert_eq!(offset_at(&r.get("Nowhere/Special"), 1_782_907_200), 0);
    }

    #[test]
    fn iana_names_and_wrapped_names() {
        let local = TimeZone::UTC;
        let zones = BTreeMap::new();
        let mut r = Resolver::new(&zones, &local);
        assert_eq!(offset_at(&r.get("Asia/Tokyo"), 1_782_907_200), 9 * 3600);
        assert_eq!(
            offset_at(
                &r.get("/mozilla.org/20050126_1/America/New_York"),
                1_782_907_200
            ),
            -4 * 3600
        );
    }
}
