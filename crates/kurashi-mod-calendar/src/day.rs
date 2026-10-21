//! Civil days as plain numbers (days since 1970-01-01), so the recurrence rules count, step and compare dates without
//! a calendar library. The two conversions are Howard Hinnant's `days_from_civil` / `civil_from_days`
//! (<https://howardhinnant.github.io/date_algorithms.html>); the time zone work is jiff's (`tz.rs`).

use jiff::Timestamp;
use jiff::civil::DateTime;
use jiff::tz::TimeZone;

/// Days since 1970-01-01 of a proleptic Gregorian date.
pub fn from_civil(y: i32, m: u32, d: u32) -> i32 {
    let y = if m <= 2 { y - 1 } else { y };
    let era = y.div_euclid(400);
    let yoe = y.rem_euclid(400);
    let m = m as i32;
    let doy = (153 * (if m > 2 { m - 3 } else { m + 9 }) + 2) / 5 + d as i32 - 1;
    let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy;
    era * 146_097 + doe - 719_468
}

/// The date of a day number: (year, month 1..=12, day 1..=31).
pub fn to_civil(z: i32) -> (i32, u32, u32) {
    let z = z + 719_468;
    let era = z.div_euclid(146_097);
    let doe = z.rem_euclid(146_097);
    let yoe = (doe - doe / 1460 + doe / 36_524 - doe / 146_096) / 365;
    let y = yoe + era * 400;
    let doy = doe - (365 * yoe + yoe / 4 - yoe / 100);
    let mp = (5 * doy + 2) / 153;
    let d = (doy - (153 * mp + 2) / 5 + 1) as u32;
    let m = if mp < 10 { mp + 3 } else { mp - 9 } as u32;
    (if m <= 2 { y + 1 } else { y }, m, d)
}

/// Weekday of a day number, 0 = Monday … 6 = Sunday (1970-01-01 was a Thursday).
pub fn weekday(z: i32) -> u32 {
    (z + 3).rem_euclid(7) as u32
}

pub fn is_leap(y: i32) -> bool {
    (y % 4 == 0 && y % 100 != 0) || y % 400 == 0
}

pub fn days_in_month(y: i32, m: u32) -> u32 {
    match m {
        1 | 3 | 5 | 7 | 8 | 10 | 12 => 31,
        4 | 6 | 9 | 11 => 30,
        _ if is_leap(y) => 29,
        _ => 28,
    }
}

/// `YYYY-MM-DD`.
pub fn iso(z: i32) -> String {
    let (y, m, d) = to_civil(z);
    format!("{y:04}-{m:02}-{d:02}")
}

/// A valid date's day number, or None (31 February, month 13).
pub fn checked(y: i32, m: u32, d: u32) -> Option<i32> {
    ((1..=12).contains(&m) && d >= 1 && d <= days_in_month(y, m)).then(|| from_civil(y, m, d))
}

/// The unix second of a civil moment (day + seconds of the day) in `tz`. A time that the zone skips (spring forward)
/// or repeats (fall back) resolves as RFC 5545 and jiff's "compatible" rule do: later in a gap, earlier in a fold.
pub fn instant(tz: &TimeZone, day: i32, secs: u32) -> Option<i64> {
    let (y, m, d) = to_civil(day);
    let dt = DateTime::new(
        i16::try_from(y).ok()?,
        m as i8,
        d as i8,
        (secs / 3600) as i8,
        (secs / 60 % 60) as i8,
        (secs % 60) as i8,
        0,
    )
    .ok()?;
    tz.to_timestamp(dt).ok().map(|t| t.as_second())
}

/// The local day (and seconds into it) of a unix second in `tz`.
pub fn civil_of(tz: &TimeZone, ts: i64) -> (i32, u32) {
    let Ok(t) = Timestamp::from_second(ts) else {
        return (ts.div_euclid(86_400) as i32, 0);
    };
    let dt = tz.to_datetime(t);
    let day = from_civil(i32::from(dt.year()), dt.month() as u32, dt.day() as u32);
    let secs = dt.hour() as u32 * 3600 + dt.minute() as u32 * 60 + dt.second() as u32;
    (day, secs)
}

/// Local midnight of `day` in `tz`.
pub fn midnight(tz: &TimeZone, day: i32) -> i64 {
    instant(tz, day, 0).unwrap_or(i64::from(day) * 86_400)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn round_trips_and_weekdays() {
        assert_eq!(from_civil(1970, 1, 1), 0);
        assert_eq!(to_civil(0), (1970, 1, 1));
        let z = from_civil(2026, 10, 21);
        assert_eq!(to_civil(z), (2026, 10, 21));
        assert_eq!(weekday(z), 2, "2026-10-21 is a Wednesday");
        assert_eq!(iso(from_civil(2024, 2, 29)), "2024-02-29");
        assert_eq!(checked(2026, 2, 29), None);
        assert_eq!(days_in_month(2000, 2), 29);
        assert_eq!(days_in_month(1900, 2), 28);
        for z in [-800_000, -1, 0, 1, 20_000, 2_000_000] {
            let (y, m, d) = to_civil(z);
            assert_eq!(from_civil(y, m, d), z);
        }
    }
}
