//! Sustained trouble (docs/ux/sysmon.md, "silent when fine, articulate when not"). A reading at or above
//! its critical level for `sustain` raises the trouble. It clears only after the reading stayed below
//! the critical level minus a hysteresis band for [`RECOVER`]; inside the band nothing changes. Both
//! clocks are measured in time, not in samples, so the 2 s panel sampler and the 10 s watch mix safely.

use std::time::Duration;
// tokio's Instant: the same clock in the daemon, and the paused clock in tests.
use tokio::time::Instant;

/// How long a reading must stay below the exit level before the trouble clears.
pub const RECOVER: Duration = Duration::from_secs(10);

#[derive(Clone, Copy, Debug, PartialEq, Eq, PartialOrd, Ord)]
pub enum Kind {
    Cpu = 0,
    Mem = 1,
    Temp = 2,
}

impl Kind {
    pub const ALL: [Kind; 3] = [Kind::Cpu, Kind::Mem, Kind::Temp];

    pub fn name(self) -> &'static str {
        match self {
            Kind::Cpu => "cpu",
            Kind::Mem => "mem",
            Kind::Temp => "temp",
        }
    }

    /// The band below the critical level inside which a trouble neither clears nor restarts its count.
    fn hysteresis(self) -> f64 {
        match self {
            Kind::Temp => 3.0,
            Kind::Cpu | Kind::Mem => 5.0,
        }
    }
}

/// One threshold pair. A level of 0 disables it (Settings: "0 disables").
#[derive(Clone, Copy, Debug, Default, PartialEq)]
pub struct Limit {
    pub activity: f64,
    pub critical: f64,
}

impl Limit {
    /// `normal`, `activity` or `critical`, for the view's tint (never colour alone: the glyph changes too).
    pub fn level(self, value: f64) -> &'static str {
        if self.critical > 0.0 && value >= self.critical {
            "critical"
        } else if self.activity > 0.0 && value >= self.activity {
            "activity"
        } else {
            "normal"
        }
    }
}

#[derive(Clone, Copy, Debug, Default, PartialEq)]
pub struct Limits {
    pub cpu: Limit,
    pub mem: Limit,
    pub temp: Limit,
}

impl Limits {
    pub fn of(&self, kind: Kind) -> Limit {
        match kind {
            Kind::Cpu => self.cpu,
            Kind::Mem => self.mem,
            Kind::Temp => self.temp,
        }
    }
}

/// What one sample measured. None = not measured this time: it changes nothing (not a 0).
#[derive(Clone, Copy, Debug, Default, PartialEq)]
pub struct Readings {
    pub cpu: Option<f64>,
    pub mem: Option<f64>,
    pub temp: Option<f64>,
}

impl Readings {
    fn of(&self, kind: Kind) -> Option<f64> {
        match kind {
            Kind::Cpu => self.cpu,
            Kind::Mem => self.mem,
            Kind::Temp => self.temp,
        }
    }
}

/// What changed in the face's terms: one face, raised while any kind is sustained.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Transition {
    Raised,
    Cleared,
    Unchanged,
}

#[derive(Clone, Copy, Debug, Default)]
struct Line {
    /// When the reading first reached the critical level in the current streak.
    over_since: Option<Instant>,
    /// When an active trouble's reading first fell below the exit level in the current streak.
    under_since: Option<Instant>,
    /// Set while the trouble is active: since when.
    active_since: Option<Instant>,
}

#[derive(Clone, Debug, Default)]
pub struct Trouble {
    lines: [Line; 3],
}

impl Trouble {
    pub fn update(
        &mut self,
        now: Instant,
        readings: Readings,
        limits: &Limits,
        sustain: Duration,
    ) -> Transition {
        let was = self.active().is_some();
        for kind in Kind::ALL {
            self.step(kind, now, readings.of(kind), limits.of(kind), sustain);
        }
        match (was, self.active().is_some()) {
            (false, true) => Transition::Raised,
            (true, false) => Transition::Cleared,
            _ => Transition::Unchanged,
        }
    }

    fn step(
        &mut self,
        kind: Kind,
        now: Instant,
        value: Option<f64>,
        limit: Limit,
        sustain: Duration,
    ) {
        let line = &mut self.lines[kind as usize];
        let Some(v) = value else {
            return;
        };
        if limit.critical <= 0.0 {
            *line = Line::default();
            return;
        }
        let exit = limit.critical - kind.hysteresis();
        if line.active_since.is_none() {
            // A streak starts at the critical level and survives the band; only a reading below the exit
            // level ends it. The window is checked on every reading, so the raise comes at the first
            // reading after `sustain`, whatever that reading is.
            if v >= limit.critical {
                line.over_since.get_or_insert(now);
            } else if v < exit {
                line.over_since = None;
            }
            if let Some(since) = line.over_since {
                if now.duration_since(since) >= sustain {
                    line.active_since = Some(now);
                    line.under_since = None;
                }
            }
        } else if v < exit {
            let since = *line.under_since.get_or_insert(now);
            if now.duration_since(since) >= RECOVER {
                *line = Line::default();
            }
        } else {
            line.under_since = None;
        }
    }

    /// The kind shown: the first active one in [`Kind::ALL`] order (CPU, memory, temperature).
    pub fn active(&self) -> Option<Kind> {
        Kind::ALL
            .into_iter()
            .find(|k| self.lines[*k as usize].active_since.is_some())
    }

    /// How long the shown trouble has lasted.
    pub fn since(&self, now: Instant) -> Option<Duration> {
        let kind = self.active()?;
        self.lines[kind as usize]
            .active_since
            .map(|at| now.duration_since(at))
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    const SUSTAIN: Duration = Duration::from_secs(30);

    fn limits() -> Limits {
        Limits {
            cpu: Limit {
                activity: 50.0,
                critical: 90.0,
            },
            mem: Limit {
                activity: 60.0,
                critical: 90.0,
            },
            temp: Limit {
                activity: 60.0,
                critical: 85.0,
            },
        }
    }

    fn cpu(v: f64) -> Readings {
        Readings {
            cpu: Some(v),
            ..Readings::default()
        }
    }

    /// Feeds one reading every 2 s (the panel's rate) and returns the transitions with their times.
    fn run(t: &mut Trouble, start: Instant, values: &[(u64, f64)]) -> Vec<(u64, Transition)> {
        let mut out = Vec::new();
        for &(secs, v) in values {
            let now = start + Duration::from_secs(secs);
            let tr = t.update(now, cpu(v), &limits(), SUSTAIN);
            if tr != Transition::Unchanged {
                out.push((secs, tr));
            }
        }
        out
    }

    fn every_2s(from: u64, to: u64, v: f64) -> Vec<(u64, f64)> {
        (from..=to).step_by(2).map(|s| (s, v)).collect()
    }

    #[test]
    fn sustained_load_raises_once_after_the_window_with_the_culprit_kind() {
        let start = Instant::now();
        let mut t = Trouble::default();
        let tr = run(&mut t, start, &every_2s(0, 60, 95.0));
        assert_eq!(
            tr,
            vec![(30, Transition::Raised)],
            "raised exactly at the sustain window"
        );
        assert_eq!(t.active(), Some(Kind::Cpu));
        assert_eq!(
            t.since(start + Duration::from_secs(40)),
            Some(Duration::from_secs(10))
        );
    }

    #[test]
    fn a_spike_shorter_than_the_window_never_raises() {
        let start = Instant::now();
        let mut t = Trouble::default();
        let mut values = every_2s(0, 20, 95.0);
        values.extend(every_2s(22, 60, 40.0));
        assert!(run(&mut t, start, &values).is_empty());
        assert_eq!(t.active(), None);
    }

    #[test]
    fn readings_hovering_around_the_critical_level_do_not_flap() {
        let start = Instant::now();
        let mut t = Trouble::default();
        // 88 and 92 alternate: both within the hysteresis band or above it, so the streak holds.
        let values: Vec<(u64, f64)> = (0..=120)
            .step_by(2)
            .map(|s| (s, if (s / 2) % 2 == 0 { 88.0 } else { 92.0 }))
            .collect();
        let tr = run(&mut t, start, &values);
        // The streak began at t=2 (the first 92): the window closes at t=32.
        assert_eq!(
            tr,
            vec![(32, Transition::Raised)],
            "one raise, no clear, no second raise"
        );
    }

    #[test]
    fn a_dip_into_the_band_does_not_clear_an_active_trouble() {
        let start = Instant::now();
        let mut t = Trouble::default();
        let mut values = every_2s(0, 40, 95.0);
        // 87 is inside the band [85, 90): the trouble holds.
        values.extend(every_2s(42, 80, 87.0));
        let tr = run(&mut t, start, &values);
        assert_eq!(tr, vec![(30, Transition::Raised)]);
        assert_eq!(t.active(), Some(Kind::Cpu));
    }

    #[test]
    fn it_clears_once_after_recovery_below_the_exit_level() {
        let start = Instant::now();
        let mut t = Trouble::default();
        let mut values = every_2s(0, 40, 95.0);
        values.extend(every_2s(42, 60, 40.0));
        let tr = run(&mut t, start, &values);
        // Below 85 from t=42; cleared when that has lasted RECOVER (10 s): at t=52.
        assert_eq!(
            tr,
            vec![(30, Transition::Raised), (52, Transition::Cleared)]
        );
        assert_eq!(t.active(), None);
    }

    #[test]
    fn a_missing_reading_changes_nothing() {
        let start = Instant::now();
        let mut t = Trouble::default();
        assert!(run(&mut t, start, &every_2s(0, 20, 95.0)).is_empty());
        // A failed read at t=22 is no reading at all: the streak keeps its start.
        let missing = t.update(
            start + Duration::from_secs(22),
            Readings::default(),
            &limits(),
            SUSTAIN,
        );
        assert_eq!(missing, Transition::Unchanged);
        let tr = run(&mut t, start, &every_2s(24, 40, 95.0));
        assert_eq!(tr, vec![(30, Transition::Raised)]);
    }

    #[test]
    fn a_zero_level_disables_that_kind_and_clears_it() {
        let start = Instant::now();
        let mut t = Trouble::default();
        run(&mut t, start, &every_2s(0, 40, 95.0));
        assert_eq!(t.active(), Some(Kind::Cpu));
        let mut off = limits();
        off.cpu.critical = 0.0;
        let tr = t.update(start + Duration::from_secs(42), cpu(99.0), &off, SUSTAIN);
        assert_eq!(tr, Transition::Cleared);
        assert_eq!(t.active(), None);
    }

    #[test]
    fn temperature_has_its_own_band_and_the_first_active_kind_is_shown() {
        let start = Instant::now();
        let mut t = Trouble::default();
        let hot = Readings {
            cpu: Some(95.0),
            mem: None,
            temp: Some(86.0),
        };
        for s in (0..=40).step_by(2) {
            t.update(start + Duration::from_secs(s), hot, &limits(), SUSTAIN);
        }
        assert_eq!(
            t.active(),
            Some(Kind::Cpu),
            "CPU is shown before temperature"
        );
        let cool_cpu = Readings {
            cpu: Some(10.0),
            mem: None,
            temp: Some(83.0),
        };
        // Temperature 83 is inside its band [82, 85): still active; CPU recovers and clears.
        for s in (42..=70).step_by(2) {
            t.update(start + Duration::from_secs(s), cool_cpu, &limits(), SUSTAIN);
        }
        assert_eq!(t.active(), Some(Kind::Temp));
    }

    #[test]
    fn levels_follow_the_thresholds() {
        let l = Limit {
            activity: 50.0,
            critical: 90.0,
        };
        assert_eq!(l.level(10.0), "normal");
        assert_eq!(l.level(50.0), "activity");
        assert_eq!(l.level(95.0), "critical");
        let off = Limit {
            activity: 0.0,
            critical: 0.0,
        };
        assert_eq!(off.level(99.0), "normal");
    }
}
