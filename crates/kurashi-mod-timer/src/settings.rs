//! The mod's settings in effect (K22, `mods.timer.*`), read the way the operations need them (K73, "Settings").
//! Each value is checked against the range the manifest declares, and falls back to its default when it is out of
//! range: the Settings page refuses such a value, so only a hand-edited file can get here.

use kurashi_mod_api::Settings;

use crate::model::{Cycle, MINUTE_MS};

/// The presets when the setting holds nothing usable (minutes).
pub const DEFAULT_PRESETS: [u64; 3] = [5, 10, 25];
/// Most presets offered: the row must fit a Stage card.
pub const MAX_PRESETS: usize = 8;

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Cfg {
    /// Presets in minutes, in the order the user gave them.
    pub presets: Vec<u64>,
    pub cycle: Cycle,
    /// The notification plays its sound (the `suppress-sound` hint is its negation).
    pub sound: bool,
}

impl Cfg {
    pub fn read(settings: &Settings) -> Self {
        let int = |key: &str, default: u64, min: u64, max: u64| -> u64 {
            settings
                .get(key)
                .and_then(|v| v.as_u64())
                .filter(|n| (min..=max).contains(n))
                .unwrap_or(default)
        };
        let flag = |key: &str, default: bool| -> bool {
            settings
                .get(key)
                .and_then(|v| v.as_bool())
                .unwrap_or(default)
        };
        let presets = settings
            .get("presets")
            .and_then(|v| v.as_str().map(parse_presets))
            .unwrap_or_else(|| DEFAULT_PRESETS.to_vec());
        Cfg {
            presets,
            cycle: Cycle {
                focus_ms: int("focus_minutes", 25, 1, 180) * MINUTE_MS,
                short_ms: int("short_break_minutes", 5, 1, 60) * MINUTE_MS,
                long_ms: int("long_break_minutes", 15, 1, 120) * MINUTE_MS,
                rounds: int("rounds", 4, 1, 12) as u32,
                auto_advance: flag("auto_advance", true),
            },
            sound: flag("sound", true),
        }
    }

    /// The minutes `timer.start` uses without an argument: the last countdown's length, else the first preset.
    pub fn default_minutes(&self, last_ms: Option<u64>) -> u64 {
        match last_ms {
            Some(ms) if ms >= MINUTE_MS && ms % MINUTE_MS == 0 => ms / MINUTE_MS,
            _ => self.presets.first().copied().unwrap_or(DEFAULT_PRESETS[0]),
        }
    }
}

/// "5, 10, 25" → `[5, 10, 25]`: whole minutes from 1 to 1440, in the order given, each once, at most [`MAX_PRESETS`].
/// Anything else is dropped, and no usable entry means the defaults.
pub fn parse_presets(text: &str) -> Vec<u64> {
    let mut out: Vec<u64> = Vec::new();
    for part in text.split(',') {
        let Ok(n) = part.trim().parse::<u64>() else {
            continue;
        };
        if (1..=1440).contains(&n) && !out.contains(&n) {
            out.push(n);
        }
        if out.len() == MAX_PRESETS {
            break;
        }
    }
    if out.is_empty() {
        DEFAULT_PRESETS.to_vec()
    } else {
        out
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn presets_keep_their_order_and_drop_what_is_not_a_minute() {
        assert_eq!(parse_presets("5, 10,25"), vec![5, 10, 25]);
        assert_eq!(
            parse_presets("25,5,25,0,x,1441,7"),
            vec![25, 5, 7],
            "once each, no 0, no 1441"
        );
        assert_eq!(
            parse_presets(""),
            DEFAULT_PRESETS.to_vec(),
            "nothing usable: the defaults"
        );
        assert_eq!(parse_presets("1,2,3,4,5,6,7,8,9,10").len(), MAX_PRESETS);
    }

    #[test]
    fn the_default_countdown_is_the_last_one_started_or_the_first_preset() {
        let cfg = Cfg {
            presets: vec![15, 5],
            cycle: Cycle {
                focus_ms: 25 * MINUTE_MS,
                short_ms: 5 * MINUTE_MS,
                long_ms: 15 * MINUTE_MS,
                rounds: 4,
                auto_advance: true,
            },
            sound: true,
        };
        assert_eq!(cfg.default_minutes(None), 15);
        assert_eq!(cfg.default_minutes(Some(3 * MINUTE_MS)), 3);
        assert_eq!(
            cfg.default_minutes(Some(90_000)),
            15,
            "a length that is not whole minutes is not a default"
        );
    }
}
