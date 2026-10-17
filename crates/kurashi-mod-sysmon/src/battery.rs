//! The battery, when the machine has one (docs/ux/sysmon.md, "Battery meets sysmon"): charge, state, the
//! power it draws and what that means in time. Read from `power_supply` in the kernel's units: power in
//! µW (or current in µA times voltage in µV), energy in µWh. A desktop has none, and the panel row is hidden.

use crate::roots::Roots;
use std::path::Path;

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum State {
    Charging,
    Discharging,
    Full,
    NotCharging,
    Unknown,
}

impl State {
    pub fn name(self) -> &'static str {
        match self {
            State::Charging => "charging",
            State::Discharging => "discharging",
            State::Full => "full",
            State::NotCharging => "not_charging",
            State::Unknown => "unknown",
        }
    }
}

#[derive(Clone, Debug, PartialEq)]
pub struct Battery {
    /// Charge in per cent; None when the kernel does not report it.
    pub percent: Option<f64>,
    pub state: State,
    /// Power drawn from the battery (discharging) or put into it (charging), in W; None when not measured.
    pub watts: Option<f64>,
    /// Minutes until empty at the current draw, while discharging with a measured draw.
    pub minutes_left: Option<u64>,
}

fn number(roots: &Roots, dir: &Path, file: &str) -> Option<f64> {
    roots.read(dir.join(file))?.trim().parse::<f64>().ok()
}

fn state_of(text: &str) -> State {
    match text.trim() {
        "Charging" => State::Charging,
        "Discharging" => State::Discharging,
        "Full" => State::Full,
        "Not charging" => State::NotCharging,
        _ => State::Unknown,
    }
}

/// The first supply whose `type` is `Battery`, in name order. None when there is no battery.
pub fn read(roots: &Roots) -> Option<Battery> {
    let dir = roots
        .list(roots.sys.join("class/power_supply"))
        .into_iter()
        .find(|d| {
            roots
                .read(d.join("type"))
                .is_some_and(|t| t.trim() == "Battery")
        })?;
    let state = state_of(&roots.read(dir.join("status")).unwrap_or_default());
    let percent = number(roots, &dir, "capacity").filter(|p| (0.0..=100.0).contains(p));
    // Power as the kernel reports it, else current times voltage (µA × µV = pW, so 1e12 for W).
    let watts = number(roots, &dir, "power_now")
        .map(|uw| uw.abs() / 1e6)
        .or_else(|| {
            let ua = number(roots, &dir, "current_now")?;
            let uv = number(roots, &dir, "voltage_now")?;
            Some(ua.abs() * uv.abs() / 1e12)
        })
        .filter(|w| *w > 0.0);
    // Energy left in Wh: µWh as reported, else charge (µAh) times voltage.
    let energy_wh = number(roots, &dir, "energy_now")
        .map(|e| e / 1e6)
        .or_else(|| {
            let ah = number(roots, &dir, "charge_now")?;
            let uv = number(roots, &dir, "voltage_now")?;
            Some(ah * uv / 1e12)
        });
    let minutes_left = match (state, watts, energy_wh) {
        (State::Discharging, Some(w), Some(wh)) if wh > 0.0 => Some((wh / w * 60.0).round() as u64),
        _ => None,
    };
    Some(Battery {
        percent,
        state,
        watts,
        minutes_left,
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    fn supply(root: &Path, name: &str, files: &[(&str, &str)]) {
        let dir = root.join("sys/class/power_supply").join(name);
        std::fs::create_dir_all(&dir).unwrap();
        for (file, text) in files {
            std::fs::write(dir.join(file), format!("{text}\n")).unwrap();
        }
    }

    fn roots(dir: &Path) -> Roots {
        Roots::new(dir.join("proc"), dir.join("sys"), 1000)
    }

    #[test]
    fn a_discharging_battery_gives_watts_and_the_time_left() {
        let dir = tempfile::tempdir().unwrap();
        supply(dir.path(), "AC", &[("type", "Mains"), ("online", "0")]);
        supply(
            dir.path(),
            "BAT0",
            &[
                ("type", "Battery"),
                ("status", "Discharging"),
                ("capacity", "78"),
                ("power_now", "15000000"),
                ("energy_now", "30000000"),
            ],
        );
        let b = read(&roots(dir.path())).unwrap();
        assert_eq!(b.state, State::Discharging);
        assert_eq!(b.percent, Some(78.0));
        assert_eq!(b.watts, Some(15.0));
        assert_eq!(b.minutes_left, Some(120), "30 Wh at 15 W is two hours");
    }

    #[test]
    fn current_and_voltage_stand_in_for_power() {
        let dir = tempfile::tempdir().unwrap();
        supply(
            dir.path(),
            "BAT1",
            &[
                ("type", "Battery"),
                ("status", "Discharging"),
                ("capacity", "50"),
                ("current_now", "2000000"),
                ("voltage_now", "12000000"),
                ("charge_now", "2500000"),
            ],
        );
        let b = read(&roots(dir.path())).unwrap();
        assert_eq!(b.watts, Some(24.0), "2 A at 12 V");
        // 2.5 Ah at 12 V is 30 Wh, 30 Wh at 24 W is 75 minutes.
        assert_eq!(b.minutes_left, Some(75));
    }

    #[test]
    fn charging_and_no_draw_give_no_time_left() {
        let dir = tempfile::tempdir().unwrap();
        supply(
            dir.path(),
            "BAT0",
            &[
                ("type", "Battery"),
                ("status", "Charging"),
                ("capacity", "40"),
                ("power_now", "20000000"),
                ("energy_now", "10000000"),
            ],
        );
        let b = read(&roots(dir.path())).unwrap();
        assert_eq!(b.state, State::Charging);
        assert_eq!(b.minutes_left, None);
        assert_eq!(
            b.watts,
            Some(20.0),
            "the draw into the battery is still shown"
        );
    }

    #[test]
    fn a_desktop_without_a_battery_has_none() {
        let dir = tempfile::tempdir().unwrap();
        supply(dir.path(), "AC", &[("type", "Mains"), ("online", "1")]);
        assert_eq!(read(&roots(dir.path())), None);
        assert_eq!(
            read(&Roots::new(
                dir.path().join("proc"),
                dir.path().join("nope"),
                1000
            )),
            None
        );
    }

    #[test]
    fn an_implausible_charge_is_not_shown() {
        let dir = tempfile::tempdir().unwrap();
        supply(
            dir.path(),
            "BAT0",
            &[("type", "Battery"), ("status", "Full"), ("capacity", "140")],
        );
        let b = read(&roots(dir.path())).unwrap();
        assert_eq!(b.percent, None);
        assert_eq!(b.state, State::Full);
    }
}
