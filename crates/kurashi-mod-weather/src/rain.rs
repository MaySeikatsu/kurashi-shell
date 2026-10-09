//! Rain soon (docs/ux/weather.md, "Beyond the basic job" 1): the 15-minute nowcast says whether it
//! rains now, or starts within the next hour, and the Island face is raised once per onset. Pure,
//! except `Watch`, the memory that makes the raise happen once.

use chrono::{Duration, NaiveDateTime, Timelike};

use crate::api::Step;

/// A 15-minute step counts as wet from 0.1 mm (the usual drizzle threshold).
pub const WET_MM: f64 = 0.1;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Intensity {
    Light,
    Moderate,
    Heavy,
}

impl Intensity {
    pub fn key(self) -> &'static str {
        match self {
            Self::Light => "light",
            Self::Moderate => "moderate",
            Self::Heavy => "heavy",
        }
    }

    /// From one step's mm, read as an hourly rate (x4), with the usual light/moderate/heavy cuts.
    pub fn of(step_mm: f64) -> Self {
        let rate = step_mm * 4.0;
        if rate < 2.5 {
            Self::Light
        } else if rate < 10.0 {
            Self::Moderate
        } else {
            Self::Heavy
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Nowcast {
    /// The steps do not cover the current step or the next hour: nothing is claimed.
    Unknown,
    /// Dry now and through the next hour.
    Dry,
    /// Wet at the current 15-minute step.
    Raining,
    /// Dry now, wet within the next hour. `in_min` counts from the current step's start.
    Soon {
        from: NaiveDateTime,
        in_min: u32,
        intensity: Intensity,
    },
}

/// The start of the 15-minute step that holds `now` (`now` is the place's local time).
pub fn step_start(now: NaiveDateTime) -> NaiveDateTime {
    let minute = now.minute() - now.minute() % 15;
    now.date().and_hms_opt(now.hour(), minute, 0).unwrap_or(now)
}

pub fn nowcast(steps: &[Step], now: NaiveDateTime) -> Nowcast {
    let bucket = step_start(now);
    let horizon = bucket + Duration::minutes(60);
    let Some(current) = steps.iter().find(|s| s.time == bucket) else {
        return Nowcast::Unknown;
    };
    if current.precip_mm >= WET_MM {
        return Nowcast::Raining;
    }
    let first_wet = steps
        .iter()
        .filter(|s| s.time > bucket && s.time <= horizon && s.precip_mm >= WET_MM)
        .min_by_key(|s| s.time);
    match first_wet {
        Some(s) => Nowcast::Soon {
            from: s.time,
            in_min: u32::try_from((s.time - bucket).num_minutes()).unwrap_or(0),
            intensity: Intensity::of(s.precip_mm),
        },
        None if steps.iter().any(|s| s.time == horizon) => Nowcast::Dry,
        None => Nowcast::Unknown,
    }
}

/// What the face does after one nowcast.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Edge {
    Raise,
    Clear,
    None,
}

/// Raises once per onset. Armed while dry; a raise disarms it; dry again (or no nowcast claim
/// about rain) re-arms it. While it rains nothing is raised, and a raised face is taken back
/// when the rain starts, because "rain in 15 min" would then be wrong.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Watch {
    armed: bool,
    raised: bool,
}

impl Default for Watch {
    fn default() -> Self {
        Self {
            armed: true,
            raised: false,
        }
    }
}

impl Watch {
    pub fn observe(&mut self, n: &Nowcast) -> Edge {
        match n {
            Nowcast::Soon { .. } if self.armed => {
                self.armed = false;
                self.raised = true;
                Edge::Raise
            }
            Nowcast::Soon { .. } | Nowcast::Unknown => Edge::None,
            Nowcast::Raining => self.take_back(),
            Nowcast::Dry => {
                self.armed = true;
                self.take_back()
            }
        }
    }

    /// The alerts were switched off: a raised face goes, and the next onset counts as new.
    pub fn reset(&mut self) -> Edge {
        let edge = self.take_back();
        *self = Self::default();
        edge
    }

    fn take_back(&mut self) -> Edge {
        if self.raised {
            self.raised = false;
            Edge::Clear
        } else {
            Edge::None
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use chrono::NaiveDate;

    fn at(h: u32, m: u32) -> NaiveDateTime {
        NaiveDate::from_ymd_opt(2026, 10, 9)
            .unwrap()
            .and_hms_opt(h, m, 0)
            .unwrap()
    }

    fn steps(mm: &[f64]) -> Vec<Step> {
        mm.iter()
            .enumerate()
            .map(|(i, &p)| Step {
                time: at(14, 0) + Duration::minutes(15 * i as i64),
                precip_mm: p,
            })
            .collect()
    }

    #[test]
    fn rain_in_an_hour_is_soon_with_its_step_and_intensity() {
        // 14:00 dry, 14:15 dry, 14:30 dry, 14:45 dry, 15:00 wet (light), 15:15 wet
        let s = steps(&[0.0, 0.0, 0.0, 0.0, 0.1, 0.3]);
        assert_eq!(
            nowcast(&s, at(14, 0)),
            Nowcast::Soon {
                from: at(15, 0),
                in_min: 60,
                intensity: Intensity::Light
            }
        );
        // Minutes inside the step do not move the step.
        assert_eq!(nowcast(&s, at(14, 7)), nowcast(&s, at(14, 0)));
    }

    #[test]
    fn rain_beyond_the_hour_is_not_soon_and_wet_now_is_raining() {
        let late = steps(&[0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.4]);
        assert_eq!(nowcast(&late, at(14, 0)), Nowcast::Dry);
        let now_wet = steps(&[0.2, 0.0, 0.0, 0.0, 0.0]);
        assert_eq!(nowcast(&now_wet, at(14, 0)), Nowcast::Raining);
    }

    #[test]
    fn missing_steps_claim_nothing() {
        assert_eq!(nowcast(&[], at(14, 0)), Nowcast::Unknown);
        // Covers only 14:00–14:30: the horizon (15:00) is not known to be dry.
        let short = steps(&[0.0, 0.0, 0.0]);
        assert_eq!(nowcast(&short, at(14, 0)), Nowcast::Unknown);
    }

    #[test]
    fn intensity_follows_the_hourly_rate() {
        assert_eq!(Intensity::of(0.2), Intensity::Light); // 0.8 mm/h
        assert_eq!(Intensity::of(1.0), Intensity::Moderate); // 4 mm/h
        assert_eq!(Intensity::of(3.0), Intensity::Heavy); // 12 mm/h
    }

    #[test]
    fn the_face_is_raised_once_per_onset() {
        let soon = Nowcast::Soon {
            from: at(15, 0),
            in_min: 60,
            intensity: Intensity::Light,
        };
        let mut w = Watch::default();
        assert_eq!(w.observe(&soon), Edge::Raise, "the onset raises");
        assert_eq!(w.observe(&soon), Edge::None, "still soon: not again");
        assert_eq!(w.observe(&soon), Edge::None);
    }

    #[test]
    fn it_never_repeats_while_it_rains_and_takes_the_face_back() {
        let soon = Nowcast::Soon {
            from: at(15, 0),
            in_min: 60,
            intensity: Intensity::Light,
        };
        let mut w = Watch::default();
        assert_eq!(w.observe(&soon), Edge::Raise);
        assert_eq!(
            w.observe(&Nowcast::Raining),
            Edge::Clear,
            "rain started: the face goes"
        );
        assert_eq!(w.observe(&Nowcast::Raining), Edge::None);
        assert_eq!(w.observe(&soon), Edge::None, "same episode: no repeat");
    }

    #[test]
    fn dry_again_rearms_and_a_new_onset_raises_again() {
        let soon = Nowcast::Soon {
            from: at(15, 0),
            in_min: 60,
            intensity: Intensity::Light,
        };
        let mut w = Watch::default();
        assert_eq!(w.observe(&soon), Edge::Raise);
        assert_eq!(
            w.observe(&Nowcast::Dry),
            Edge::Clear,
            "forecast cleared: the face goes"
        );
        assert_eq!(w.observe(&soon), Edge::Raise, "a new onset after dry");
    }

    #[test]
    fn unknown_keeps_the_state_and_reset_starts_over() {
        let soon = Nowcast::Soon {
            from: at(15, 0),
            in_min: 60,
            intensity: Intensity::Light,
        };
        let mut w = Watch::default();
        assert_eq!(w.observe(&soon), Edge::Raise);
        assert_eq!(w.observe(&Nowcast::Unknown), Edge::None);
        assert_eq!(w.observe(&soon), Edge::None, "unknown is not dry");
        assert_eq!(
            w.reset(),
            Edge::Clear,
            "switching the alerts off takes a raised face back"
        );
        assert_eq!(
            w.reset(),
            Edge::None,
            "and a second reset has nothing to take"
        );
        assert_eq!(
            w.observe(&soon),
            Edge::Raise,
            "after a reset the onset counts again"
        );
    }
}
