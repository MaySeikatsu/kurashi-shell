//! RFC 5545 recurrence rules (§3.3.10, §3.8.5.3), the part calendars actually send: FREQ DAILY / WEEKLY / MONTHLY /
//! YEARLY with INTERVAL, COUNT, UNTIL, BYDAY (with ordinals: `2MO`, `-1FR`), BYMONTHDAY, BYMONTH, BYSETPOS and WKST.
//! Expansion works on civil days (`day.rs`); the time of day and the zone are the event's (`expand.rs`). A rule this
//! does not understand (an unknown FREQ, BYHOUR, BYWEEKNO, BYYEARDAY) is not guessed at: `parse` answers None and the
//! event shows its first instance only.

use crate::day;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Freq {
    Daily,
    Weekly,
    Monthly,
    Yearly,
}

/// UNTIL as written: a date, or a date-time (`Z` = UTC, else the event's own zone, per RFC 5545).
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Until {
    Date(i32),
    Utc(i64),
    Local(i32, u32),
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Rule {
    pub freq: Freq,
    pub interval: u32,
    pub count: Option<u32>,
    pub until: Option<Until>,
    /// (ordinal, weekday 0 = Monday): ordinal 0 means every such weekday of the period.
    pub by_day: Vec<(i32, u32)>,
    pub by_month_day: Vec<i32>,
    pub by_month: Vec<u32>,
    pub by_set_pos: Vec<i32>,
    /// The week's first day for WEEKLY (default Monday).
    pub wkst: u32,
}

/// Periods walked at most (a daily rule over 130 years); past it the series simply stops.
const MAX_PERIODS: usize = 50_000;

pub fn weekday_code(s: &str) -> Option<u32> {
    Some(match s {
        "MO" => 0,
        "TU" => 1,
        "WE" => 2,
        "TH" => 3,
        "FR" => 4,
        "SA" => 5,
        "SU" => 6,
        _ => return None,
    })
}

/// Parses a basic date or date-time (`YYYYMMDD[THHMMSS[Z]]`) for UNTIL.
fn parse_until(v: &str) -> Option<Until> {
    let (date, time) = match v.split_once('T') {
        Some((d, t)) => (d, Some(t)),
        None => (v, None),
    };
    if date.len() != 8 || !date.bytes().all(|b| b.is_ascii_digit()) {
        return None;
    }
    let y: i32 = date[0..4].parse().ok()?;
    let m: u32 = date[4..6].parse().ok()?;
    let d: u32 = date[6..8].parse().ok()?;
    let z = day::checked(y, m, d)?;
    let Some(t) = time else {
        return Some(Until::Date(z));
    };
    let utc = t.ends_with('Z');
    let t = t.trim_end_matches('Z');
    if t.len() != 6 || !t.bytes().all(|b| b.is_ascii_digit()) {
        return None;
    }
    let secs = t[0..2].parse::<u32>().ok()? * 3600
        + t[2..4].parse::<u32>().ok()? * 60
        + t[4..6].parse::<u32>().ok()?;
    if utc {
        Some(Until::Utc(i64::from(z) * 86_400 + i64::from(secs)))
    } else {
        Some(Until::Local(z, secs))
    }
}

fn ints(v: &str) -> Option<Vec<i32>> {
    v.split(',').map(|s| s.trim().parse().ok()).collect()
}

/// A rule from its value (`FREQ=WEEKLY;BYDAY=MO,WE`), or None when it is not one this expands faithfully.
pub fn parse(value: &str) -> Option<Rule> {
    let mut rule = Rule {
        freq: Freq::Daily,
        interval: 1,
        count: None,
        until: None,
        by_day: Vec::new(),
        by_month_day: Vec::new(),
        by_month: Vec::new(),
        by_set_pos: Vec::new(),
        wkst: 0,
    };
    let mut freq = None;
    for part in value.trim().split(';').filter(|p| !p.is_empty()) {
        let (k, v) = part.split_once('=')?;
        match k.trim().to_ascii_uppercase().as_str() {
            "FREQ" => {
                freq = Some(match v.trim().to_ascii_uppercase().as_str() {
                    "DAILY" => Freq::Daily,
                    "WEEKLY" => Freq::Weekly,
                    "MONTHLY" => Freq::Monthly,
                    "YEARLY" => Freq::Yearly,
                    _ => return None,
                });
            }
            "INTERVAL" => rule.interval = v.trim().parse().ok().filter(|n| *n >= 1)?,
            "COUNT" => rule.count = Some(v.trim().parse().ok()?),
            "UNTIL" => rule.until = Some(parse_until(v.trim())?),
            "BYDAY" => {
                for d in v.split(',') {
                    let d = d.trim().to_ascii_uppercase();
                    if d.len() < 2 {
                        return None;
                    }
                    let (ord, code) = d.split_at(d.len() - 2);
                    let ord = if ord.is_empty() { 0 } else { ord.parse().ok()? };
                    rule.by_day.push((ord, weekday_code(code)?));
                }
            }
            "BYMONTHDAY" => rule.by_month_day = ints(v)?,
            "BYMONTH" => {
                rule.by_month = ints(v)?
                    .into_iter()
                    .map(|m| u32::try_from(m).ok().filter(|m| (1..=12).contains(m)))
                    .collect::<Option<_>>()?;
            }
            "BYSETPOS" => rule.by_set_pos = ints(v)?,
            "WKST" => rule.wkst = weekday_code(&v.trim().to_ascii_uppercase())?,
            // Sub-day and week-number parts change which instants exist: not expanded rather than expanded wrong.
            "BYHOUR" | "BYMINUTE" | "BYSECOND" | "BYWEEKNO" | "BYYEARDAY" => return None,
            _ => {}
        }
    }
    rule.freq = freq?;
    Some(rule)
}

/// The days of month (y, m) the rule's BYMONTHDAY / BYDAY pick, or the series' own day of the month.
fn month_days(rule: &Rule, y: i32, m: u32, start_dom: u32) -> Vec<i32> {
    let len = day::days_in_month(y, m) as i32;
    let first = day::from_civil(y, m, 1);
    let doms: Option<Vec<i32>> = (!rule.by_month_day.is_empty()).then(|| {
        rule.by_month_day
            .iter()
            .filter_map(|&d| {
                let d = if d < 0 { len + d + 1 } else { d };
                (1..=len).contains(&d).then_some(first + d - 1)
            })
            .collect()
    });
    let wds: Option<Vec<i32>> = (!rule.by_day.is_empty()).then(|| {
        let mut out = Vec::new();
        for &(ord, wd) in &rule.by_day {
            let all: Vec<i32> = (0..len)
                .map(|i| first + i)
                .filter(|z| day::weekday(*z) == wd)
                .collect();
            match ord {
                0 => out.extend(all),
                n if n > 0 => out.extend(all.get(n as usize - 1)),
                n => out.extend(
                    all.len()
                        .checked_sub(n.unsigned_abs() as usize)
                        .map(|i| all[i]),
                ),
            }
        }
        out
    });
    let mut days = match (doms, wds) {
        (Some(a), Some(b)) => a.into_iter().filter(|d| b.contains(d)).collect(),
        (Some(a), None) | (None, Some(a)) => a,
        (None, None) => day::checked(y, m, start_dom).into_iter().collect(),
    };
    days.sort_unstable();
    days.dedup();
    days
}

/// BYSETPOS over one period's sorted candidates.
fn set_pos(rule: &Rule, days: Vec<i32>) -> Vec<i32> {
    if rule.by_set_pos.is_empty() {
        return days;
    }
    let n = days.len() as i32;
    let mut out: Vec<i32> = rule
        .by_set_pos
        .iter()
        .filter_map(|&p| {
            let i = if p < 0 { n + p } else { p - 1 };
            (0..n).contains(&i).then(|| days[i as usize])
        })
        .collect();
    out.sort_unstable();
    out.dedup();
    out
}

/// The candidate days of the `k`-th period (k = 0 is the series' own period).
fn period(rule: &Rule, start: i32, k: i64) -> (i32, Vec<i32>) {
    let step = i64::from(rule.interval) * k;
    let (sy, sm, sd) = day::to_civil(start);
    let wd_ok =
        |z: i32| rule.by_day.is_empty() || rule.by_day.iter().any(|&(_, w)| w == day::weekday(z));
    let month_ok = |z: i32| rule.by_month.is_empty() || rule.by_month.contains(&day::to_civil(z).1);
    match rule.freq {
        Freq::Daily => {
            let z = start + step as i32;
            let (_, _, d) = day::to_civil(z);
            let len = day::days_in_month(day::to_civil(z).0, day::to_civil(z).1) as i32;
            let dom_ok = rule.by_month_day.is_empty()
                || rule
                    .by_month_day
                    .iter()
                    .any(|&m| m == d as i32 || len + m + 1 == d as i32);
            (
                z,
                if wd_ok(z) && month_ok(z) && dom_ok {
                    vec![z]
                } else {
                    Vec::new()
                },
            )
        }
        Freq::Weekly => {
            let back = (day::weekday(start) + 7 - rule.wkst) % 7;
            let ws = start - back as i32 + (step * 7) as i32;
            let own = day::weekday(start);
            let days: Vec<i32> = (0..7)
                .map(|i| ws + i)
                .filter(|z| {
                    let w = day::weekday(*z);
                    (if rule.by_day.is_empty() {
                        w == own
                    } else {
                        rule.by_day.iter().any(|&(_, x)| x == w)
                    }) && month_ok(*z)
                })
                .collect();
            (ws, set_pos(rule, days))
        }
        Freq::Monthly => {
            let months = i64::from(sm) - 1 + step;
            let y = sy + months.div_euclid(12) as i32;
            let m = months.rem_euclid(12) as u32 + 1;
            let days = if rule.by_month.is_empty() || rule.by_month.contains(&m) {
                month_days(rule, y, m, sd)
            } else {
                Vec::new()
            };
            (day::from_civil(y, m, 1), set_pos(rule, days))
        }
        Freq::Yearly => {
            let y = sy + step as i32;
            let mut days = Vec::new();
            if !rule.by_month.is_empty() {
                let mut months = rule.by_month.clone();
                months.sort_unstable();
                for m in months {
                    if rule.by_day.is_empty() && rule.by_month_day.is_empty() {
                        days.extend(day::checked(y, m, sd));
                    } else {
                        days.extend(month_days(rule, y, m, sd));
                    }
                }
            } else if !rule.by_month_day.is_empty() {
                for m in 1..=12 {
                    days.extend(month_days(rule, y, m, sd));
                }
            } else if !rule.by_day.is_empty() {
                // Ordinals count within the year when no month narrows it (`FREQ=YEARLY;BYDAY=20MO`).
                let first = day::from_civil(y, 1, 1);
                let len = if day::is_leap(y) { 366 } else { 365 };
                for &(ord, wd) in &rule.by_day {
                    let all: Vec<i32> = (0..len)
                        .map(|i| first + i)
                        .filter(|z| day::weekday(*z) == wd)
                        .collect();
                    match ord {
                        0 => days.extend(all),
                        n if n > 0 => days.extend(all.get(n as usize - 1)),
                        n => days.extend(
                            all.len()
                                .checked_sub(n.unsigned_abs() as usize)
                                .map(|i| all[i]),
                        ),
                    }
                }
            } else {
                days.extend(day::checked(y, sm, sd));
            }
            days.sort_unstable();
            days.dedup();
            (day::from_civil(y, 1, 1), set_pos(rule, days))
        }
    }
}

/// The days the series falls on, in order, from `start` (always the first instance, RFC 5545 §3.8.5.3) up to `stop`
/// (exclusive). COUNT counts from the start, so instances before a window still use up the count. UNTIL is the
/// caller's (it compares instants); `stop` should not lie past it.
pub fn days(rule: &Rule, start: i32, stop: i32) -> Vec<i32> {
    let mut out = vec![start];
    let max = rule.count.map_or(usize::MAX, |c| c as usize);
    if start >= stop || out.len() >= max {
        out.retain(|d| *d < stop);
        return out;
    }
    for k in 0..MAX_PERIODS as i64 {
        let (first, candidates) = period(rule, start, k);
        if first >= stop {
            break;
        }
        for z in candidates {
            if z <= start {
                continue;
            }
            if z >= stop {
                return out;
            }
            out.push(z);
            if out.len() >= max {
                return out;
            }
        }
    }
    out
}

#[cfg(test)]
mod tests {
    use super::*;

    fn d(y: i32, m: u32, dd: u32) -> i32 {
        day::from_civil(y, m, dd)
    }

    fn isos(v: &[i32]) -> Vec<String> {
        v.iter().map(|z| day::iso(*z)).collect()
    }

    #[test]
    fn weekly_byday_with_count() {
        let r = parse("FREQ=WEEKLY;BYDAY=MO,WE;COUNT=5").unwrap();
        // 2026-10-19 is a Monday.
        let got = days(&r, d(2026, 10, 19), d(2027, 1, 1));
        assert_eq!(
            isos(&got),
            [
                "2026-10-19",
                "2026-10-21",
                "2026-10-26",
                "2026-10-28",
                "2026-11-02"
            ]
        );
    }

    #[test]
    fn biweekly_interval() {
        let r = parse("FREQ=WEEKLY;INTERVAL=2").unwrap();
        let got = days(&r, d(2026, 10, 1), d(2026, 11, 15));
        assert_eq!(
            isos(&got),
            ["2026-10-01", "2026-10-15", "2026-10-29", "2026-11-12"]
        );
    }

    #[test]
    fn monthly_last_friday_and_31st() {
        let r = parse("FREQ=MONTHLY;BYDAY=-1FR").unwrap();
        let got = days(&r, d(2026, 10, 30), d(2027, 1, 1));
        assert_eq!(isos(&got), ["2026-10-30", "2026-11-27", "2026-12-25"]);
        // The 31st skips the months that have none (RFC 5545: invalid dates are ignored).
        let r = parse("FREQ=MONTHLY").unwrap();
        let got = days(&r, d(2026, 1, 31), d(2026, 6, 1));
        assert_eq!(isos(&got), ["2026-01-31", "2026-03-31", "2026-05-31"]);
        // The last weekday of the month (Outlook's "last working day").
        let r = parse("FREQ=MONTHLY;BYDAY=MO,TU,WE,TH,FR;BYSETPOS=-1").unwrap();
        let got = days(&r, d(2026, 10, 30), d(2027, 1, 1));
        assert_eq!(isos(&got), ["2026-10-30", "2026-11-30", "2026-12-31"]);
    }

    #[test]
    fn yearly_birthday_and_us_thanksgiving() {
        let r = parse("FREQ=YEARLY").unwrap();
        let got = days(&r, d(2024, 2, 29), d(2033, 1, 1));
        assert_eq!(isos(&got), ["2024-02-29", "2028-02-29", "2032-02-29"]);
        let r = parse("FREQ=YEARLY;BYMONTH=11;BYDAY=4TH").unwrap();
        let got = days(&r, d(2025, 11, 27), d(2028, 1, 1));
        assert_eq!(isos(&got), ["2025-11-27", "2026-11-26", "2027-11-25"]);
    }

    #[test]
    fn daily_until_and_unsupported() {
        let r = parse("FREQ=DAILY;UNTIL=20261023T235959Z").unwrap();
        assert_eq!(
            r.until,
            Some(Until::Utc(i64::from(d(2026, 10, 23)) * 86_400 + 86_399))
        );
        let r = parse("FREQ=DAILY;INTERVAL=3;BYDAY=MO,TU,WE,TH,FR").unwrap();
        let got = days(&r, d(2026, 10, 19), d(2026, 11, 1));
        assert_eq!(isos(&got), ["2026-10-19", "2026-10-22", "2026-10-28"]);
        assert!(parse("FREQ=HOURLY").is_none());
        assert!(parse("FREQ=WEEKLY;BYHOUR=9").is_none());
        assert!(parse("BYDAY=MO").is_none());
    }
}
