//! A careful small iCalendar reader (RFC 5545): no ICS crate is in the lock, and the shell needs only the events.
//! Content lines are unfolded (CRLF or LF, a leading space or tab continues), parameters may be quoted, text values are
//! unescaped. Read: `VCALENDAR` (`X-WR-CALNAME`, `NAME`, `COLOR`, `X-APPLE-CALENDAR-COLOR`), `VEVENT` (UID, SUMMARY,
//! LOCATION, DTSTART, DTEND, DURATION, RRULE, RDATE, EXDATE, RECURRENCE-ID, STATUS) and `VTIMEZONE` (STANDARD and
//! DAYLIGHT with their offsets and yearly rules, for `tz.rs`). An event without a usable DTSTART is skipped and
//! counted; a text that is not a calendar at all is an error the source shows.

use std::collections::BTreeMap;

use crate::day;
use crate::rrule::{self, Rule};

/// Where a date-time's wall clock is.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Zone {
    Utc,
    /// No zone given: the session's local time.
    Floating,
    Id(String),
}

/// A DTSTART-like value.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Stamp {
    /// An all-day date (VALUE=DATE).
    Date(i32),
    /// A wall-clock moment: civil day, seconds into it, and its zone.
    Time { day: i32, secs: u32, zone: Zone },
}

impl Stamp {
    pub fn day(&self) -> i32 {
        match self {
            Self::Date(d) | Self::Time { day: d, .. } => *d,
        }
    }
}

/// An ISO 8601 duration as RFC 5545 has it: nominal days (weeks are 7) plus exact seconds.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
pub struct Duration {
    pub days: i64,
    pub secs: i64,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Event {
    pub uid: String,
    pub summary: String,
    pub location: Option<String>,
    pub description: Option<String>,
    pub start: Stamp,
    pub end: Option<Stamp>,
    pub duration: Option<Duration>,
    pub rrule: Option<Rule>,
    /// The RRULE was there but is not one `rrule.rs` expands: only the first instance is shown.
    pub rrule_unsupported: bool,
    pub rdates: Vec<Stamp>,
    pub exdates: Vec<Stamp>,
    pub recurrence_id: Option<Stamp>,
    pub cancelled: bool,
}

/// One STANDARD or DAYLIGHT part of a VTIMEZONE.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ZonePart {
    pub daylight: bool,
    /// DTSTART: the local wall clock (in the `from` offset) the part begins at.
    pub start_day: i32,
    pub start_secs: u32,
    pub from: i32,
    pub to: i32,
    pub rrule: Option<Rule>,
}

#[derive(Debug, Clone, PartialEq, Eq, Default)]
pub struct VTimezone {
    pub parts: Vec<ZonePart>,
}

#[derive(Debug, Clone, PartialEq, Eq, Default)]
pub struct Calendar {
    pub name: Option<String>,
    pub color: Option<String>,
    pub events: Vec<Event>,
    pub zones: BTreeMap<String, VTimezone>,
    /// Events left out because their DTSTART could not be read.
    pub skipped: usize,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Error {
    /// No `BEGIN:VCALENDAR`: an HTML login page, a JSON error, an empty file.
    NotCalendar,
}

/// One content line: NAME;PARAM=VALUE:value, the name and parameter names upper-cased.
struct Line<'a> {
    name: String,
    params: Vec<(String, String)>,
    value: &'a str,
}

impl Line<'_> {
    fn param(&self, key: &str) -> Option<&str> {
        self.params
            .iter()
            .find(|(k, _)| k == key)
            .map(|(_, v)| v.as_str())
    }
}

/// Splits `s` at `sep` outside double quotes.
fn split_unquoted(s: &str, sep: char) -> Vec<&str> {
    let mut out = Vec::new();
    let mut quoted = false;
    let mut from = 0;
    for (i, c) in s.char_indices() {
        if c == '"' {
            quoted = !quoted;
        } else if c == sep && !quoted {
            out.push(&s[from..i]);
            from = i + c.len_utf8();
        }
    }
    out.push(&s[from..]);
    out
}

fn parse_line(raw: &str) -> Option<Line<'_>> {
    let mut quoted = false;
    let mut colon = None;
    for (i, c) in raw.char_indices() {
        if c == '"' {
            quoted = !quoted;
        } else if c == ':' && !quoted {
            colon = Some(i);
            break;
        }
    }
    let colon = colon?;
    let head = &raw[..colon];
    let value = &raw[colon + 1..];
    let mut parts = split_unquoted(head, ';').into_iter();
    let name = parts.next()?.trim().to_ascii_uppercase();
    if name.is_empty() {
        return None;
    }
    let params = parts
        .filter_map(|p| {
            let (k, v) = p.split_once('=')?;
            Some((
                k.trim().to_ascii_uppercase(),
                v.trim().trim_matches('"').to_owned(),
            ))
        })
        .collect();
    Some(Line {
        name,
        params,
        value,
    })
}

/// Unfolds content lines (RFC 5545 §3.1): a line that begins with a space or a tab continues the previous one.
fn unfold(text: &str) -> Vec<String> {
    let mut out: Vec<String> = Vec::new();
    for line in text.split('\n') {
        let line = line.strip_suffix('\r').unwrap_or(line);
        if let Some(rest) = line.strip_prefix([' ', '\t']) {
            if let Some(last) = out.last_mut() {
                last.push_str(rest);
                continue;
            }
        }
        if !line.trim().is_empty() {
            out.push(line.to_owned());
        }
    }
    out
}

/// TEXT unescaping (§3.3.11): `\n`, `\N`, `\,`, `\;`, `\\`.
pub fn unescape(s: &str) -> String {
    let mut out = String::with_capacity(s.len());
    let mut chars = s.chars();
    while let Some(c) = chars.next() {
        if c != '\\' {
            out.push(c);
            continue;
        }
        match chars.next() {
            Some('n' | 'N') => out.push('\n'),
            Some(o) => out.push(o),
            None => {}
        }
    }
    out
}

fn digits(s: &str) -> bool {
    !s.is_empty() && s.bytes().all(|b| b.is_ascii_digit())
}

/// `YYYYMMDD` → a day number.
fn parse_date(s: &str) -> Option<i32> {
    if s.len() != 8 || !digits(s) {
        return None;
    }
    day::checked(
        s[0..4].parse().ok()?,
        s[4..6].parse().ok()?,
        s[6..8].parse().ok()?,
    )
}

/// `HHMMSS` → seconds of the day (a leap second 60 reads as 59).
fn parse_time(s: &str) -> Option<u32> {
    if s.len() != 6 || !digits(s) {
        return None;
    }
    let (h, m, sec): (u32, u32, u32) = (
        s[0..2].parse().ok()?,
        s[2..4].parse().ok()?,
        s[4..6].parse().ok()?,
    );
    (h < 24 && m < 60 && sec <= 60).then(|| h * 3600 + m * 60 + sec.min(59))
}

/// One DATE or DATE-TIME value with the line's VALUE and TZID parameters.
fn parse_stamp(v: &str, value_type: Option<&str>, tzid: Option<&str>) -> Option<Stamp> {
    let v = v.trim();
    let is_date = value_type.is_some_and(|t| t.eq_ignore_ascii_case("DATE"))
        || (v.len() == 8 && !v.contains('T'));
    if is_date {
        // Some writers put a date-time on a VALUE=DATE line: its date part is meant.
        return parse_date(v.get(0..8)?).map(Stamp::Date);
    }
    let (d, t) = v.split_once('T')?;
    let day = parse_date(d)?;
    let (t, utc) = match t.strip_suffix('Z') {
        Some(t) => (t, true),
        None => (t, false),
    };
    let secs = parse_time(t)?;
    let zone = if utc {
        Zone::Utc
    } else {
        match tzid.map(str::trim).filter(|z| !z.is_empty()) {
            Some(z) => Zone::Id(z.to_owned()),
            None => Zone::Floating,
        }
    };
    Some(Stamp::Time { day, secs, zone })
}

fn stamp_of(line: &Line<'_>) -> Option<Stamp> {
    parse_stamp(line.value, line.param("VALUE"), line.param("TZID"))
}

fn stamps_of(line: &Line<'_>) -> Vec<Stamp> {
    if line
        .param("VALUE")
        .is_some_and(|v| v.eq_ignore_ascii_case("PERIOD"))
    {
        return line
            .value
            .split(',')
            .filter_map(|p| parse_stamp(p.split('/').next()?, None, line.param("TZID")))
            .collect();
    }
    line.value
        .split(',')
        .filter_map(|v| parse_stamp(v, line.param("VALUE"), line.param("TZID")))
        .collect()
}

/// `[+-]P[nW][nD][T[nH][nM][nS]]`.
pub fn parse_duration(s: &str) -> Option<Duration> {
    let s = s.trim();
    let (neg, s) = match s.strip_prefix('-') {
        Some(r) => (true, r),
        None => (false, s.strip_prefix('+').unwrap_or(s)),
    };
    let s = s.strip_prefix('P')?;
    let mut d = Duration::default();
    let mut num = String::new();
    let mut in_time = false;
    let mut any = false;
    for c in s.chars() {
        match c {
            '0'..='9' => num.push(c),
            'T' => in_time = true,
            'W' | 'D' | 'H' | 'M' | 'S' => {
                let n: i64 = num.parse().ok()?;
                num.clear();
                any = true;
                match (c, in_time) {
                    ('W', false) => d.days += n * 7,
                    ('D', false) => d.days += n,
                    ('H', true) => d.secs += n * 3600,
                    ('M', true) => d.secs += n * 60,
                    ('S', true) => d.secs += n,
                    _ => return None,
                }
            }
            _ => return None,
        }
    }
    if !any || !num.is_empty() {
        return None;
    }
    if neg {
        d.days = -d.days;
        d.secs = -d.secs;
    }
    Some(d)
}

/// `+HHMM[SS]` → seconds east of UTC.
fn parse_offset(s: &str) -> Option<i32> {
    let s = s.trim();
    let (sign, rest) = match s.as_bytes().first()? {
        b'+' => (1, &s[1..]),
        b'-' => (-1, &s[1..]),
        _ => return None,
    };
    if !(rest.len() == 4 || rest.len() == 6) || !digits(rest) {
        return None;
    }
    let h: i32 = rest[0..2].parse().ok()?;
    let m: i32 = rest[2..4].parse().ok()?;
    let sec: i32 = if rest.len() == 6 {
        rest[4..6].parse().ok()?
    } else {
        0
    };
    Some(sign * (h * 3600 + m * 60 + sec))
}

#[derive(Default)]
struct EventDraft {
    uid: Option<String>,
    summary: Option<String>,
    location: Option<String>,
    description: Option<String>,
    start: Option<Stamp>,
    end: Option<Stamp>,
    duration: Option<Duration>,
    rrule: Option<Rule>,
    rrule_unsupported: bool,
    rdates: Vec<Stamp>,
    exdates: Vec<Stamp>,
    recurrence_id: Option<Stamp>,
    cancelled: bool,
}

#[derive(Default)]
struct PartDraft {
    daylight: bool,
    start: Option<Stamp>,
    from: Option<i32>,
    to: Option<i32>,
    rrule: Option<Rule>,
}

/// Reads a calendar. Lenient where writers differ (LF line ends, a missing END at the end of the file, unknown
/// properties), strict where a guess would show a wrong time (a DTSTART that cannot be read skips the event).
pub fn parse(text: &str) -> Result<Calendar, Error> {
    let text = text.strip_prefix('\u{feff}').unwrap_or(text);
    let lines = unfold(text);
    let mut cal = Calendar::default();
    let mut seen_calendar = false;
    // The component stack, innermost last.
    let mut stack: Vec<String> = Vec::new();
    let mut ev: Option<EventDraft> = None;
    let mut tz_id: Option<String> = None;
    let mut tz = VTimezone::default();
    let mut part: Option<PartDraft> = None;
    let mut anon = 0usize;

    for raw in &lines {
        let Some(line) = parse_line(raw) else {
            continue;
        };
        let value = line.value.trim();
        match line.name.as_str() {
            "BEGIN" => {
                let comp = value.to_ascii_uppercase();
                match comp.as_str() {
                    "VCALENDAR" => seen_calendar = true,
                    "VEVENT" if stack.last().is_some_and(|c| c == "VCALENDAR") => {
                        ev = Some(EventDraft::default())
                    }
                    "VTIMEZONE" => {
                        tz_id = None;
                        tz = VTimezone::default();
                    }
                    "STANDARD" | "DAYLIGHT" if stack.last().is_some_and(|c| c == "VTIMEZONE") => {
                        part = Some(PartDraft {
                            daylight: comp == "DAYLIGHT",
                            ..PartDraft::default()
                        });
                    }
                    _ => {}
                }
                stack.push(comp);
                continue;
            }
            "END" => {
                let comp = value.to_ascii_uppercase();
                // Pop to the matching BEGIN; an END without one is ignored.
                if let Some(pos) = stack.iter().rposition(|c| *c == comp) {
                    stack.truncate(pos);
                } else {
                    continue;
                }
                match comp.as_str() {
                    "VEVENT" => {
                        if let Some(d) = ev.take() {
                            finish_event(&mut cal, d, &mut anon);
                        }
                    }
                    "STANDARD" | "DAYLIGHT" => {
                        if let Some(p) = part.take() {
                            if let (Some(start), Some(from), Some(to)) = (p.start, p.from, p.to) {
                                let (start_day, start_secs) = match start {
                                    Stamp::Date(d) => (d, 0),
                                    Stamp::Time { day, secs, .. } => (day, secs),
                                };
                                tz.parts.push(ZonePart {
                                    daylight: p.daylight,
                                    start_day,
                                    start_secs,
                                    from,
                                    to,
                                    rrule: p.rrule,
                                });
                            }
                        }
                    }
                    "VTIMEZONE" => {
                        if let Some(id) = tz_id.take() {
                            cal.zones.insert(id, std::mem::take(&mut tz));
                        }
                    }
                    _ => {}
                }
                continue;
            }
            _ => {}
        }
        let inner = stack.last().map(String::as_str);
        if let (Some(p), Some("STANDARD" | "DAYLIGHT")) = (part.as_mut(), inner) {
            match line.name.as_str() {
                "DTSTART" => p.start = stamp_of(&line),
                "TZOFFSETFROM" => p.from = parse_offset(value),
                "TZOFFSETTO" => p.to = parse_offset(value),
                "RRULE" => p.rrule = rrule::parse(value),
                _ => {}
            }
        } else if inner == Some("VTIMEZONE") {
            if line.name == "TZID" {
                tz_id = Some(value.to_owned());
            }
        } else if let (Some(d), Some("VEVENT")) = (ev.as_mut(), inner) {
            match line.name.as_str() {
                "UID" => d.uid = Some(value.to_owned()),
                "SUMMARY" => d.summary = Some(unescape(value)),
                "LOCATION" => d.location = Some(unescape(value)).filter(|l| !l.trim().is_empty()),
                "DESCRIPTION" => {
                    d.description = Some(unescape(value)).filter(|s| !s.trim().is_empty())
                }
                "DTSTART" => d.start = stamp_of(&line),
                "DTEND" => d.end = stamp_of(&line),
                "DURATION" => d.duration = parse_duration(value),
                "RRULE" => {
                    d.rrule = rrule::parse(value);
                    d.rrule_unsupported = d.rrule.is_none();
                }
                "RDATE" => d.rdates.extend(stamps_of(&line)),
                "EXDATE" => d.exdates.extend(stamps_of(&line)),
                "RECURRENCE-ID" => d.recurrence_id = stamp_of(&line),
                "STATUS" => d.cancelled = value.eq_ignore_ascii_case("CANCELLED"),
                _ => {}
            }
        } else if inner == Some("VCALENDAR") {
            match line.name.as_str() {
                "X-WR-CALNAME" | "NAME" => {
                    cal.name = Some(unescape(value)).filter(|n| !n.trim().is_empty());
                }
                "COLOR" | "X-APPLE-CALENDAR-COLOR" => cal.color = normalize_color(value),
                _ => {}
            }
        }
    }
    // A file cut short still yields the event it was in.
    if let Some(d) = ev.take() {
        finish_event(&mut cal, d, &mut anon);
    }
    if !seen_calendar {
        return Err(Error::NotCalendar);
    }
    Ok(cal)
}

fn finish_event(cal: &mut Calendar, d: EventDraft, anon: &mut usize) {
    let Some(start) = d.start else {
        cal.skipped += 1;
        return;
    };
    let uid = d.uid.unwrap_or_else(|| {
        *anon += 1;
        format!("anon-{anon}")
    });
    cal.events.push(Event {
        uid,
        summary: d.summary.unwrap_or_default(),
        location: d.location,
        description: d.description,
        start,
        end: d.end,
        duration: d.duration,
        rrule: d.rrule,
        rrule_unsupported: d.rrule_unsupported,
        rdates: d.rdates,
        exdates: d.exdates,
        recurrence_id: d.recurrence_id,
        cancelled: d.cancelled,
    });
}

/// `#rrggbb` (or `#rrggbbaa`, Apple's form), lower-case; a CSS colour name (RFC 7986 COLOR) is passed on as written.
pub fn normalize_color(v: &str) -> Option<String> {
    let v = v.trim();
    if let Some(hex) = v.strip_prefix('#') {
        let ok = (hex.len() == 6 || hex.len() == 8) && hex.bytes().all(|b| b.is_ascii_hexdigit());
        return ok.then(|| format!("#{}", hex[..6].to_ascii_lowercase()));
    }
    (!v.is_empty() && v.bytes().all(|b| b.is_ascii_alphabetic())).then(|| v.to_ascii_lowercase())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn unfolds_unescapes_and_reads_params() {
        let text = "BEGIN:VCALENDAR\r\nX-WR-CALNAME:Work\r\nBEGIN:VEVENT\r\nUID:1\r\nSUMMARY:Lunch\\, then a\r\n  long walk\\nbye\r\nDTSTART;TZID=\"Europe/Berlin\":20261021T120000\r\nDTEND;TZID=Europe/Berlin:20261021T130000\r\nLOCATION:Café \"Ume\"\r\nDESCRIPTION:Bring the deck\\nsee https://example.test/a\\, b\r\nEND:VEVENT\r\nEND:VCALENDAR\r\n";
        let c = parse(text).unwrap();
        assert_eq!(c.name.as_deref(), Some("Work"));
        let e = &c.events[0];
        assert_eq!(e.summary, "Lunch, then a long walk\nbye");
        assert_eq!(e.location.as_deref(), Some("Café \"Ume\""));
        assert_eq!(
            e.description.as_deref(),
            Some("Bring the deck\nsee https://example.test/a, b")
        );
        assert_eq!(
            e.start,
            Stamp::Time {
                day: day::from_civil(2026, 10, 21),
                secs: 12 * 3600,
                zone: Zone::Id("Europe/Berlin".into())
            }
        );
    }

    #[test]
    fn durations_offsets_colors() {
        assert_eq!(
            parse_duration("PT1H30M"),
            Some(Duration {
                days: 0,
                secs: 5400
            })
        );
        assert_eq!(parse_duration("P1W"), Some(Duration { days: 7, secs: 0 }));
        assert_eq!(
            parse_duration("P1DT2H"),
            Some(Duration {
                days: 1,
                secs: 7200
            })
        );
        assert_eq!(parse_duration("P"), None);
        assert_eq!(parse_duration("PT5"), None);
        assert_eq!(parse_offset("+0530"), Some(19_800));
        assert_eq!(parse_offset("-0800"), Some(-28_800));
        assert_eq!(normalize_color("#FF8800FF").as_deref(), Some("#ff8800"));
        assert_eq!(normalize_color("turquoise").as_deref(), Some("turquoise"));
        assert_eq!(normalize_color("#12"), None);
    }

    #[test]
    fn not_a_calendar_and_broken_events() {
        assert_eq!(parse("<html>login</html>"), Err(Error::NotCalendar));
        assert_eq!(parse(""), Err(Error::NotCalendar));
        let c = parse("BEGIN:VCALENDAR\nBEGIN:VEVENT\nSUMMARY:no start\nEND:VEVENT\nBEGIN:VEVENT\nDTSTART:2026BAD\nEND:VEVENT\nBEGIN:VEVENT\nDTSTART;VALUE=DATE:20261021\nSUMMARY:ok\n").unwrap();
        assert_eq!(c.skipped, 2);
        assert_eq!(
            c.events.len(),
            1,
            "the event cut off at the end of the file is kept"
        );
        assert_eq!(
            c.events[0].start,
            Stamp::Date(day::from_civil(2026, 10, 21))
        );
        assert!(c.events[0].uid.starts_with("anon-"));
    }
}
