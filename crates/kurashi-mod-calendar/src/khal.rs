//! khal as a source, the way DankMaterialShell's `CalendarKhalBackend.qml` does it: `khal printformats` tells the
//! date and time formats the user configured, `khal list --json <field>… <from> <to>` lists the window. Its JSON comes
//! in three shapes depending on the version — one array, one array per day, or one document per line —, all read
//! (shellseikatsu `CalendarService.qml`). khal lists a multi-day event on each of its days; one instance is kept.

use std::collections::BTreeSet;
use std::time::Duration;

use jiff::tz::TimeZone;
use serde_json::Value;

use crate::day;
use crate::expand::{Occ, Window};
use crate::ics::normalize_color;

pub const FIELDS: [&str; 9] = [
    "title",
    "location",
    "calendar",
    "calendar-color",
    "start-date-long",
    "start-time",
    "end-date-long",
    "end-time",
    "all-day",
];

const TIMEOUT: Duration = Duration::from_secs(15);

/// One khal event with its calendar.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Item {
    pub occ: Occ,
    pub calendar: String,
    pub color: Option<String>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Error {
    /// khal is not installed (not on PATH).
    Missing,
    /// It ran and failed, or its output could not be read.
    Failed,
    /// The configured date format names months by name: not read rather than misread.
    Format,
}

/// A date pattern from khal's example date (21 December 2013): `%d.%m.%Y`, `%m/%d/%Y`, `%Y-%m-%d`.
pub fn date_pattern(example: &str) -> Option<String> {
    let p = example.trim();
    let p = if p.contains("2013") {
        p.replace("2013", "%Y")
    } else {
        p.replace("13", "%y")
    };
    let p = p.replace("12", "%m").replace("21", "%d");
    (p.contains("%m")
        && p.contains("%d")
        && !p
            .chars()
            .any(|c| c.is_alphabetic() && !"YymdP%".contains(c)))
    .then_some(p)
}

/// The `longdateformat:` example of `khal printformats`.
pub fn pattern_from_printformats(out: &str) -> Option<String> {
    out.lines()
        .find_map(|l| l.trim().strip_prefix("longdateformat:"))
        .and_then(date_pattern)
}

pub fn format_date(pattern: &str, z: i32) -> String {
    let (y, m, d) = day::to_civil(z);
    pattern
        .replace("%Y", &format!("{y:04}"))
        .replace("%y", &format!("{:02}", y.rem_euclid(100)))
        .replace("%m", &format!("{m:02}"))
        .replace("%d", &format!("{d:02}"))
}

pub fn parse_date(pattern: &str, s: &str) -> Option<i32> {
    let (mut y, mut m, mut d) = (None, None, None);
    let mut rest = s.trim();
    let mut pat = pattern.chars().peekable();
    while let Some(c) = pat.next() {
        if c == '%' {
            let kind = pat.next()?;
            let max = if kind == 'Y' { 4 } else { 2 };
            let n = rest
                .chars()
                .take(max)
                .take_while(char::is_ascii_digit)
                .count();
            if n == 0 {
                return None;
            }
            let v: i32 = rest[..n].parse().ok()?;
            rest = &rest[n..];
            match kind {
                'Y' => y = Some(v),
                'y' => y = Some(2000 + v),
                'm' => m = Some(v as u32),
                'd' => d = Some(v as u32),
                _ => return None,
            }
        } else {
            rest = rest.strip_prefix(c)?;
        }
    }
    day::checked(y?, m?, d?)
}

/// `21:45`, `9:45 PM`, `09:45:00` → seconds of the day.
pub fn parse_time(s: &str) -> Option<u32> {
    let s = s.trim();
    let (clock, ampm) = match s.len().checked_sub(2).map(|i| s.split_at(i)) {
        Some((c, ap)) if ap.eq_ignore_ascii_case("am") || ap.eq_ignore_ascii_case("pm") => {
            (c.trim(), Some(ap.eq_ignore_ascii_case("pm")))
        }
        _ => (s, None),
    };
    let mut parts = clock.split(':');
    let mut h: u32 = parts.next()?.trim().parse().ok()?;
    let m: u32 = parts.next()?.trim().parse().ok()?;
    if let Some(pm) = ampm {
        if h == 12 {
            h = 0;
        }
        if pm {
            h += 12;
        }
    }
    (h < 24 && m < 60).then_some(h * 3600 + m * 60)
}

fn flatten(v: Value, out: &mut Vec<serde_json::Map<String, Value>>) {
    match v {
        Value::Array(a) => a.into_iter().for_each(|x| flatten(x, out)),
        Value::Object(o) => out.push(o),
        _ => {}
    }
}

/// khal's `list --json` output as instances in the session's zone.
pub fn parse_list(out: &str, pattern: &str, local: &TimeZone, win: &Window) -> Vec<Item> {
    let mut objs = Vec::new();
    match serde_json::from_str::<Value>(out) {
        Ok(v) => flatten(v, &mut objs),
        Err(_) => {
            for line in out.lines().map(str::trim).filter(|l| !l.is_empty()) {
                if let Ok(v) = serde_json::from_str::<Value>(line) {
                    flatten(v, &mut objs);
                }
            }
        }
    }
    let text = |o: &serde_json::Map<String, Value>, k: &str| {
        o.get(k).and_then(Value::as_str).unwrap_or("").to_owned()
    };
    let mut seen = BTreeSet::new();
    let mut items = Vec::new();
    for o in objs {
        let title = text(&o, "title");
        let Some(sd) = parse_date(pattern, &text(&o, "start-date-long")) else {
            continue;
        };
        let ed = parse_date(pattern, &text(&o, "end-date-long")).unwrap_or(sd);
        let all_day =
            text(&o, "all-day").eq_ignore_ascii_case("true") || text(&o, "start-time").is_empty();
        let (start, end) = if all_day {
            // khal writes an all-day event's last day; the document's end is the midnight after it.
            (
                day::midnight(local, sd),
                day::midnight(local, ed.max(sd) + 1),
            )
        } else {
            let st = parse_time(&text(&o, "start-time")).unwrap_or(0);
            let et = parse_time(&text(&o, "end-time")).unwrap_or(st);
            let s = day::instant(local, sd, st).unwrap_or_else(|| day::midnight(local, sd));
            let e = day::instant(local, ed, et).unwrap_or(s);
            (s, e.max(s))
        };
        let calendar = text(&o, "calendar");
        if !seen.insert((title.clone(), start, calendar.clone())) {
            continue;
        }
        if !(end > win.from && start < win.to)
            && !(end == start && start >= win.from && start < win.to)
        {
            continue;
        }
        items.push(Item {
            occ: Occ {
                uid: format!("khal:{title}:{start}"),
                title,
                location: Some(text(&o, "location")).filter(|l| !l.trim().is_empty()),
                description: None,
                start,
                end,
                all_day,
            },
            color: normalize_color(&text(&o, "calendar-color")),
            calendar,
        });
    }
    items
}

async fn run(bin: &str, args: &[String]) -> Result<String, Error> {
    let child = tokio::process::Command::new(bin)
        .args(args)
        .stdin(std::process::Stdio::null())
        .kill_on_drop(true)
        .output();
    match tokio::time::timeout(TIMEOUT, child).await {
        Err(_) => Err(Error::Failed),
        Ok(Err(e)) if e.kind() == std::io::ErrorKind::NotFound => Err(Error::Missing),
        Ok(Err(_)) => Err(Error::Failed),
        Ok(Ok(o)) if o.status.success() => Ok(String::from_utf8_lossy(&o.stdout).into_owned()),
        Ok(Ok(_)) => Err(Error::Failed),
    }
}

/// The window from khal (`bin` is `khal`, or a test's stand-in).
pub async fn list(bin: &str, local: &TimeZone, win: &Window) -> Result<Vec<Item>, Error> {
    let formats = run(bin, &["printformats".into()]).await?;
    let pattern = pattern_from_printformats(&formats).ok_or(Error::Format)?;
    let mut args: Vec<String> = vec!["list".into()];
    for f in FIELDS {
        args.push("--json".into());
        args.push(f.into());
    }
    args.push(format_date(&pattern, win.from_day));
    args.push(format_date(&pattern, win.to_day - 1));
    let out = run(bin, &args).await?;
    Ok(parse_list(&out, &pattern, local, win))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn formats_and_times() {
        assert_eq!(date_pattern("21.12.2013").as_deref(), Some("%d.%m.%Y"));
        assert_eq!(date_pattern("12/21/2013").as_deref(), Some("%m/%d/%Y"));
        assert_eq!(date_pattern("2013-12-21").as_deref(), Some("%Y-%m-%d"));
        assert_eq!(date_pattern("21 Dec 2013"), None);
        let out = "longdatetimeformat: 21.12.2013 21:45\ndateformat: 21.12.\nlongdateformat: 21.12.2013\n";
        let p = pattern_from_printformats(out).unwrap();
        let z = day::from_civil(2026, 10, 21);
        assert_eq!(format_date(&p, z), "21.10.2026");
        assert_eq!(parse_date(&p, "21.10.2026"), Some(z));
        assert_eq!(parse_date("%m/%d/%Y", "10/21/2026"), Some(z));
        assert_eq!(parse_date(&p, "garbage"), None);
        assert_eq!(parse_time("21:45"), Some(78_300));
        assert_eq!(parse_time("9:05 PM"), Some(21 * 3600 + 300));
        assert_eq!(parse_time("12:30 am"), Some(1800));
        assert_eq!(parse_time("25:00"), None);
    }

    #[test]
    fn reads_all_three_json_shapes_and_dedupes_multi_day() {
        let tz = TimeZone::fixed(jiff::tz::Offset::from_seconds(3600).unwrap());
        let today = day::from_civil(2026, 10, 21);
        let win = Window::around(&tz, today, 7, 42);
        let ev = |title: &str, sd: &str, st: &str, ed: &str, et: &str, all: &str| {
            format!(
                r##"{{"title":"{title}","location":"","calendar":"home","calendar-color":"#00AA00","start-date-long":"{sd}","start-time":"{st}","end-date-long":"{ed}","end-time":"{et}","all-day":"{all}"}}"##
            )
        };
        let a = ev(
            "Standup",
            "2026-10-21",
            "09:00",
            "2026-10-21",
            "09:15",
            "False",
        );
        let b = ev("Trip", "2026-10-22", "", "2026-10-24", "", "True");
        let flat = format!("[{a},{b}]");
        let per_day = format!("[[{a}],[{b}],[{b}],[{b}]]");
        let lines = format!("[{a}]\n[{b}]\n[{b}]\n");
        for out in [flat, per_day, lines] {
            let items = parse_list(&out, "%Y-%m-%d", &tz, &win);
            assert_eq!(items.len(), 2, "{out}");
            assert_eq!(items[0].occ.title, "Standup");
            assert_eq!(items[0].occ.end - items[0].occ.start, 900);
            assert_eq!(items[0].color.as_deref(), Some("#00aa00"));
            assert!(items[1].occ.all_day);
            assert_eq!(items[1].occ.end - items[1].occ.start, 3 * 86_400);
        }
    }
}
