//! `svc.nightlight` (K47): night light as a supervised `wlsunset`, with Noctalia's command line
//! (`Services/NightLightService.qml`: `-t night -T day`, `-l lat -L lon` for the sun, `-S sunrise -s sunset` by hand, a
//! 15 min fade `-d 900`). Pure: the command, whether the night colours are on at a given minute, and when that changes.
//! The daemon runs the process while `night_light.enabled` (no refcount: an effect that is on runs; off = no process).
//!
//! "Always" is wlsunset with two almost equal temperatures (`-t T -T T+1`), so the colour is the same day and night.

/// Minutes since local midnight, `0..1440`.
pub type Minute = u32;

/// The day temperature wlsunset returns to (its own default).
pub const DAY_K: u32 = 6500;
/// Noctalia's fade at sunset and sunrise, in seconds.
pub const FADE_S: u32 = 900;

#[derive(Debug, Clone, Copy, PartialEq)]
pub enum Schedule {
    Always,
    /// From `start` to `end` (the end may be after midnight).
    Manual {
        start: Minute,
        end: Minute,
    },
    Sun {
        lat: f64,
        lon: f64,
    },
}

/// `HH:MM` → minutes since midnight. Anything else is `None` (never clamped).
pub fn parse_hhmm(s: &str) -> Option<Minute> {
    let (h, m) = s.trim().split_once(':')?;
    if h.is_empty() || h.len() > 2 || m.len() != 2 {
        return None;
    }
    let (h, m): (u32, u32) = (h.parse().ok()?, m.parse().ok()?);
    (h < 24 && m < 60).then_some(h * 60 + m)
}

pub fn hhmm(m: Minute) -> String {
    format!("{:02}:{:02}", (m / 60) % 24, m % 60)
}

/// wlsunset's arguments (after the program name).
pub fn command(temperature: u32, schedule: Schedule) -> Vec<String> {
    let t = temperature.to_string();
    let mut argv: Vec<String> = Vec::new();
    match schedule {
        Schedule::Always => {
            // Two temperatures one kelvin apart: the colour does not move; the times only keep wlsunset content.
            argv.extend(["-t".into(), t, "-T".into(), (temperature + 1).to_string()]);
            argv.extend(["-S".into(), "06:00".into(), "-s".into(), "18:00".into()]);
        }
        Schedule::Manual { start, end } => {
            argv.extend([
                "-t".into(),
                t,
                "-T".into(),
                DAY_K.max(temperature + 1).to_string(),
            ]);
            // wlsunset's sunrise is the end of the night, its sunset the start.
            argv.extend(["-S".into(), hhmm(end), "-s".into(), hhmm(start)]);
            argv.extend(["-d".into(), FADE_S.to_string()]);
        }
        Schedule::Sun { lat, lon } => {
            argv.extend([
                "-t".into(),
                t,
                "-T".into(),
                DAY_K.max(temperature + 1).to_string(),
            ]);
            argv.extend([
                "-l".into(),
                format!("{lat:.4}"),
                "-L".into(),
                format!("{lon:.4}"),
            ]);
        }
    }
    argv
}

/// Whether `now` is inside the night `[start, end)`, which may wrap midnight. `start == end` is no night.
pub fn in_night(now: Minute, start: Minute, end: Minute) -> bool {
    if start <= end {
        (start..end).contains(&now)
    } else {
        now >= start || now < end
    }
}

/// The night's `(start, end)` for a schedule: the times by hand, or sunset and sunrise from [`sun_times`]. `None`
/// for always, and for a sun that neither rises nor sets that day.
pub fn night_of(
    schedule: Schedule,
    day_of_year: u32,
    utc_offset_min: i32,
) -> Option<(Minute, Minute)> {
    match schedule {
        Schedule::Always => None,
        Schedule::Manual { start, end } => Some((start, end)),
        Schedule::Sun { lat, lon } => {
            sun_times(lat, lon, day_of_year, utc_offset_min).map(|(rise, set)| (set, rise))
        }
    }
}

/// `(active, next change)` at `now`: the night colours are on now, and the minute they change next (`None`: never).
pub fn state_at(
    schedule: Schedule,
    now: Minute,
    day_of_year: u32,
    utc_offset_min: i32,
) -> (bool, Option<Minute>) {
    match schedule {
        Schedule::Always => (true, None),
        _ => match night_of(schedule, day_of_year, utc_offset_min) {
            Some((start, end)) if start != end => {
                let on = in_night(now, start, end);
                (on, Some(if on { end } else { start }))
            }
            _ => (false, None),
        },
    }
}

/// Minutes from `now` until `then` (the next day when `then` is not later today), at least 1.
pub fn minutes_until(now: Minute, then: Minute) -> u32 {
    let d = (then + 1440 - now % 1440) % 1440;
    if d == 0 { 1440 } else { d }
}

/// Local sunrise and sunset `(rise, set)` in minutes since midnight, by the NOAA solar equations (fractional year,
/// equation of time, declination, hour angle at the 90.833° zenith). `None` in a polar day or night.
pub fn sun_times(
    lat: f64,
    lon: f64,
    day_of_year: u32,
    utc_offset_min: i32,
) -> Option<(Minute, Minute)> {
    use std::f64::consts::PI;
    let g = 2.0 * PI / 365.0 * (f64::from(day_of_year.max(1)) - 1.0 + 0.5);
    let eqtime = 229.18
        * (0.000075 + 0.001868 * g.cos()
            - 0.032077 * g.sin()
            - 0.014615 * (2.0 * g).cos()
            - 0.040849 * (2.0 * g).sin());
    let decl = 0.006918 - 0.399912 * g.cos() + 0.070257 * g.sin() - 0.006758 * (2.0 * g).cos()
        + 0.000907 * (2.0 * g).sin()
        - 0.002697 * (3.0 * g).cos()
        + 0.00148 * (3.0 * g).sin();
    let lat_r = lat.to_radians();
    let arg = 90.833f64.to_radians().cos() / (lat_r.cos() * decl.cos()) - lat_r.tan() * decl.tan();
    if !(-1.0..=1.0).contains(&arg) {
        return None;
    }
    let ha = arg.acos().to_degrees();
    let local = |utc: f64| -> Minute {
        let m = (utc + f64::from(utc_offset_min)).round() as i64;
        m.rem_euclid(1440) as Minute
    };
    let rise = 720.0 - 4.0 * (lon + ha) - eqtime;
    let set = 720.0 - 4.0 * (lon - ha) - eqtime;
    Some((local(rise), local(set)))
}

/// Reasons of `svc.nightlight.reason`.
pub const REASON_MISSING: &str = "power.nightlight.reason.missing";
pub const REASON_NO_PLACE: &str = "power.nightlight.reason.no_place";
pub const REASON_EXITED: &str = "power.nightlight.reason.exited";
pub const REASON_BAD_TIME: &str = "power.nightlight.reason.bad_time";

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn times_parse_strictly() {
        assert_eq!(parse_hhmm("20:00"), Some(1200));
        assert_eq!(parse_hhmm("7:05"), Some(425));
        assert_eq!(parse_hhmm("24:00"), None);
        assert_eq!(parse_hhmm("12:5"), None);
        assert_eq!(parse_hhmm("noon"), None);
        assert_eq!(hhmm(425), "07:05");
    }

    #[test]
    fn commands_are_noctalias() {
        let manual = Schedule::Manual {
            start: 1200,
            end: 420,
        };
        assert_eq!(
            command(4000, manual).join(" "),
            "-t 4000 -T 6500 -S 07:00 -s 20:00 -d 900"
        );
        assert_eq!(
            command(
                3000,
                Schedule::Sun {
                    lat: 35.6895,
                    lon: 139.6917
                }
            )
            .join(" "),
            "-t 3000 -T 6500 -l 35.6895 -L 139.6917"
        );
        assert_eq!(
            command(4000, Schedule::Always)[..4].join(" "),
            "-t 4000 -T 4001"
        );
        assert_eq!(
            command(6500, manual)[3],
            "6501",
            "wlsunset needs day > night"
        );
    }

    #[test]
    fn the_night_wraps_midnight() {
        let manual = Schedule::Manual {
            start: 1200,
            end: 420,
        };
        assert_eq!(state_at(manual, 1300, 1, 0), (true, Some(420)));
        assert_eq!(state_at(manual, 60, 1, 0), (true, Some(420)));
        assert_eq!(state_at(manual, 600, 1, 0), (false, Some(1200)));
        assert_eq!(state_at(Schedule::Always, 600, 1, 0), (true, None));
        assert_eq!(minutes_until(1300, 420), 560);
        assert_eq!(minutes_until(600, 600), 1440);
    }

    #[test]
    fn tokyo_sun_is_about_right() {
        // 21 June in Tokyo (UTC+9): sunrise ~04:25, sunset ~19:00.
        let (rise, set) = sun_times(35.6895, 139.6917, 172, 540).unwrap();
        assert!((255..=275).contains(&rise), "rise {}", hhmm(rise));
        assert!((1130..=1150).contains(&set), "set {}", hhmm(set));
        // Svalbard in June: the sun never sets.
        assert_eq!(sun_times(78.2, 15.6, 172, 120), None);
    }
}
