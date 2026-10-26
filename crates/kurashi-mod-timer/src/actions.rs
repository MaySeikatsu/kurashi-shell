//! The actions `timer.*` (K73, docs/ux/timer.md "Design"). Each one reads the settings in effect, runs one operation under
//! the shared state (which reconciles the ends first, saves and tells the document), and answers with an i18n key when
//! it refuses. Arguments are minutes (or seconds, for a short timer): whole numbers, checked here.

use kurashi_mod_api::{ActionError, Settings};
use serde_json::{Value, json};

use crate::model::{MAX_DURATION_MS, MINUTE_MS, Refusal};
use crate::settings::Cfg;
use crate::shared::Shared;

pub const ERR_ARGS: &str = "mod-timer.error.args";
pub const ERR_DURATION: &str = "mod-timer.error.duration";
pub const ERR_LABEL: &str = "mod-timer.error.label";
pub const ERR_BACKGROUND: &str = "mod-timer.error.background_off";
pub const ERR_GONE: &str = "mod-timer.error.gone";
pub const ERR_NOT_RUNNING: &str = "mod-timer.error.not_running";
pub const ERR_NOT_PAUSED: &str = "mod-timer.error.not_paused";
pub const ERR_NOT_POMODORO: &str = "mod-timer.error.not_pomodoro";
pub const ERR_TOO_SHORT: &str = "mod-timer.error.too_short";

/// Longest label kept, in characters: a Stage card's title line.
const MAX_LABEL: usize = 60;

type Reply = Result<Option<Value>, ActionError>;

fn invalid(key: &str) -> ActionError {
    ActionError::Invalid(key.into())
}

fn refusal(r: Refusal) -> ActionError {
    match r {
        Refusal::Gone => ActionError::Unavailable(ERR_GONE.into()),
        Refusal::NotRunning => invalid(ERR_NOT_RUNNING),
        Refusal::NotPaused => invalid(ERR_NOT_PAUSED),
        Refusal::NotPomodoro => invalid(ERR_NOT_POMODORO),
        Refusal::TooShort => invalid(ERR_TOO_SHORT),
    }
}

fn id_arg(args: &Value) -> Result<u64, ActionError> {
    args["id"].as_u64().ok_or_else(|| invalid(ERR_ARGS))
}

fn label_arg(args: &Value) -> Result<String, ActionError> {
    let label = args["label"].as_str().unwrap_or("").trim();
    if label.chars().count() > MAX_LABEL {
        return Err(invalid(ERR_LABEL));
    }
    Ok(label.to_owned())
}

/// The length an argument pair names, in milliseconds: `minutes` or `seconds`, whole numbers. `None` when neither is
/// given. A bad type or an overflow is a duration error.
fn amount(args: &Value) -> Result<Option<i64>, ActionError> {
    let bad = || invalid(ERR_DURATION);
    let (key, unit) = if args.get("minutes").is_some() {
        ("minutes", MINUTE_MS as i64)
    } else if args.get("seconds").is_some() {
        ("seconds", 1_000)
    } else {
        return Ok(None);
    };
    let n = args[key].as_i64().ok_or_else(bad)?;
    n.checked_mul(unit).map(Some).ok_or_else(bad)
}

/// `timer.start {minutes?, seconds?, label?}`: a countdown from now. Without a length, the last one started (or the first
/// preset). Refused while the background count is off: a timer that cannot end must not start (K73).
pub fn start(s: &Shared, settings: &Settings, args: &Value) -> Reply {
    let cfg = Cfg::read(settings);
    if !cfg.background {
        return Err(ActionError::Unavailable(ERR_BACKGROUND.into()));
    }
    let label = label_arg(args)?;
    let requested = amount(args)?;
    let id = s.with_state(&cfg, |inner, now| {
        let ms = match requested {
            Some(ms) => ms,
            None => cfg.default_minutes(inner.state.last_ms) as i64 * MINUTE_MS as i64,
        };
        if ms <= 0 || ms as u64 > MAX_DURATION_MS {
            return Err(invalid(ERR_DURATION));
        }
        Ok(inner.state.start_countdown(now, ms as u64, &label))
    })?;
    Ok(Some(json!({ "id": id })))
}

/// `timer.pomodoro.start {label?}`: a pomodoro from round 1 of focus, with the cycle in the settings.
pub fn pomodoro_start(s: &Shared, settings: &Settings, args: &Value) -> Reply {
    let cfg = Cfg::read(settings);
    if !cfg.background {
        return Err(ActionError::Unavailable(ERR_BACKGROUND.into()));
    }
    let label = label_arg(args)?;
    let id = s.with_state(&cfg, |inner, now| {
        inner.state.start_pomodoro(now, &cfg.cycle, &label)
    });
    Ok(Some(json!({ "id": id })))
}

/// `timer.pause {id}` and `timer.resume {id}`.
pub fn pause(s: &Shared, settings: &Settings, args: &Value) -> Reply {
    let (cfg, id) = (Cfg::read(settings), id_arg(args)?);
    s.with_state(&cfg, |inner, now| inner.state.pause(now, id))
        .map_err(refusal)?;
    Ok(None)
}

pub fn resume(s: &Shared, settings: &Settings, args: &Value) -> Reply {
    let (cfg, id) = (Cfg::read(settings), id_arg(args)?);
    s.with_state(&cfg, |inner, now| inner.state.resume(now, id))
        .map_err(refusal)?;
    Ok(None)
}

/// `timer.add {id, minutes?, seconds?}`: one minute by default. A negative amount takes time off (the scroll on the
/// glance); a timer that would be left with none is refused, never ended by a change of the user's.
pub fn add(s: &Shared, settings: &Settings, args: &Value) -> Reply {
    let (cfg, id) = (Cfg::read(settings), id_arg(args)?);
    let delta = amount(args)?.unwrap_or(MINUTE_MS as i64);
    if delta == 0 || delta.unsigned_abs() > MAX_DURATION_MS {
        return Err(invalid(ERR_DURATION));
    }
    s.with_state(&cfg, |inner, now| inner.state.add(now, id, delta))
        .map_err(refusal)?;
    Ok(None)
}

/// `timer.skip {id}`: a pomodoro's next phase starts now.
pub fn skip(s: &Shared, settings: &Settings, args: &Value) -> Reply {
    let (cfg, id) = (Cfg::read(settings), id_arg(args)?);
    s.with_state(&cfg, |inner, now| inner.state.skip(now, id, &cfg.cycle))
        .map_err(refusal)?;
    Ok(None)
}

/// `timer.stop {id}` and `timer.stop_all`.
pub fn stop(s: &Shared, settings: &Settings, args: &Value) -> Reply {
    let (cfg, id) = (Cfg::read(settings), id_arg(args)?);
    s.with_state(&cfg, |inner, _| inner.state.stop(id))
        .map_err(refusal)?;
    Ok(None)
}

pub fn stop_all(s: &Shared, settings: &Settings, _args: &Value) -> Reply {
    let cfg = Cfg::read(settings);
    s.with_state(&cfg, |inner, _| inner.state.stop_all());
    Ok(None)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn an_amount_is_minutes_or_seconds_and_a_bad_one_is_refused() {
        assert_eq!(amount(&json!({})).unwrap(), None);
        assert_eq!(amount(&json!({"minutes": 2})).unwrap(), Some(120_000));
        assert_eq!(amount(&json!({"seconds": 3})).unwrap(), Some(3_000));
        assert_eq!(amount(&json!({"minutes": -1})).unwrap(), Some(-60_000));
        assert_eq!(amount(&json!({"minutes": "2"})), Err(invalid(ERR_DURATION)));
        assert_eq!(
            amount(&json!({"minutes": i64::MAX})),
            Err(invalid(ERR_DURATION))
        );
    }

    #[test]
    fn a_label_is_trimmed_and_capped() {
        assert_eq!(label_arg(&json!({"label": "  tea "})).unwrap(), "tea");
        assert_eq!(label_arg(&json!({})).unwrap(), "");
        let long = "x".repeat(MAX_LABEL + 1);
        assert_eq!(label_arg(&json!({"label": long})), Err(invalid(ERR_LABEL)));
    }

    #[test]
    fn every_refusal_has_a_key_and_a_missing_timer_is_unavailable() {
        assert_eq!(
            refusal(Refusal::Gone),
            ActionError::Unavailable(ERR_GONE.into())
        );
        assert_eq!(refusal(Refusal::NotPaused), invalid(ERR_NOT_PAUSED));
        assert_eq!(id_arg(&json!({})), Err(invalid(ERR_ARGS)));
        assert_eq!(id_arg(&json!({"id": 7})).unwrap(), 7);
    }
}
