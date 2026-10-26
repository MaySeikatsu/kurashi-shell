//! The timer state (K73, docs/ux/timer.md "Design"): countdowns and the pomodoro cycle as pure functions of the state,
//! the settings in effect and the wall clock the caller passes in (`now_ms`, Unix milliseconds). Nothing here sleeps,
//! persists or sends: `crate::shared` drives it under its lock, and the job sleeps to `next_deadline`.
//!
//! Every operation first reconciles the ends that ran out (`reconcile`), so a timer that ran out while nothing looked
//! is ended (or a pomodoro advanced) before the operation sees it. The end is recorded as `pending_end`, which the job
//! turns into one notification and one island transient; the flag is persisted, so an end that passed while the
//! daemon was down is announced once on start.

use serde::{Deserialize, Serialize};
use serde_json::{Map, Value, json};

pub const MINUTE_MS: u64 = 60_000;
/// The longest timer that can be started (a day). A longer one is refused, not clamped (Shōjiki).
pub const MAX_DURATION_MS: u64 = 24 * 60 * MINUTE_MS;
/// Phases one reconcile pass may run through for a pomodoro that missed its ends. A cycle is 2 × rounds phases long,
/// so this is far beyond any real cycle; the bound keeps a corrupt state from looping.
const CATCH_UP_PHASES: u32 = 256;

#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum Kind {
    Countdown,
    Pomodoro,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum Phase {
    Focus,
    ShortBreak,
    LongBreak,
}

/// A timer's status. The deadline is absolute (`ends_at_ms`), so a running timer needs no tick: the views interpolate
/// from it, and the job sleeps to it.
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(tag = "state", rename_all = "snake_case")]
pub enum Status {
    Running {
        ends_at_ms: u64,
    },
    Paused {
        remaining_ms: u64,
    },
    /// Ran out and waits for the user (+1 min, Stop, Next phase). Stays listed until then.
    Ended {
        ended_at_ms: u64,
    },
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct Timer {
    pub id: u64,
    pub kind: Kind,
    /// The user's name for it; empty means the default ("Timer", or the phase's name).
    pub label: String,
    /// The length of the current countdown, or of the current pomodoro phase.
    pub duration_ms: u64,
    pub status: Status,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub phase: Option<Phase>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub round: Option<u32>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub rounds: Option<u32>,
    /// An end nobody has been told about yet. The job announces it and clears the flag.
    #[serde(default)]
    pub pending_end: bool,
}

#[derive(Clone, Debug, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct State {
    /// The last id handed out; ids are never reused.
    #[serde(default)]
    pub next_id: u64,
    #[serde(default)]
    pub timers: Vec<Timer>,
    /// The length of the last countdown started: the default of `timer.start` (the "last preset").
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub last_ms: Option<u64>,
}

/// The pomodoro cycle in effect (the settings, K73).
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct Cycle {
    pub focus_ms: u64,
    pub short_ms: u64,
    pub long_ms: u64,
    pub rounds: u32,
    pub auto_advance: bool,
}

/// Why an operation is refused. The actions map each to an i18n key under `mod-timer.error.`.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Refusal {
    /// No timer has that id (it was stopped, or never was).
    Gone,
    /// The timer is not running, so it cannot be paused or given a minute.
    NotRunning,
    /// The timer is not paused, so it cannot resume.
    NotPaused,
    /// Only a pomodoro has phases to skip.
    NotPomodoro,
    /// The change would leave no time on the timer (or a negative minute on an ended one).
    TooShort,
}

/// An end that `reconcile` found. `ended` says the timer now waits in `Ended`; a pomodoro that advanced by itself
/// keeps running with the phase it is in now.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct End {
    pub id: u64,
    /// When the phase (or the countdown) ran out, Unix ms. For a catch-up over several phases, the first of them.
    pub at_ms: u64,
    pub kind: Kind,
    pub phase: Option<Phase>,
    pub round: Option<u32>,
    pub ended: bool,
}

/// The phase after `phase`. The cycle is focus, a short break, focus, … and after the last round's focus a long break,
/// then round 1 again.
pub fn next_phase(phase: Phase, round: u32, rounds: u32) -> (Phase, u32) {
    match phase {
        Phase::Focus if round < rounds => (Phase::ShortBreak, round),
        Phase::Focus => (Phase::LongBreak, round),
        Phase::ShortBreak => (Phase::Focus, round + 1),
        Phase::LongBreak => (Phase::Focus, 1),
    }
}

pub fn phase_ms(phase: Phase, cycle: &Cycle) -> u64 {
    match phase {
        Phase::Focus => cycle.focus_ms,
        Phase::ShortBreak => cycle.short_ms,
        Phase::LongBreak => cycle.long_ms,
    }
}

impl State {
    fn new_id(&mut self) -> u64 {
        self.next_id += 1;
        self.next_id
    }

    fn get_mut(&mut self, id: u64) -> Result<&mut Timer, Refusal> {
        self.timers
            .iter_mut()
            .find(|t| t.id == id)
            .ok_or(Refusal::Gone)
    }

    pub fn timer(&self, id: u64) -> Option<&Timer> {
        self.timers.iter().find(|t| t.id == id)
    }

    /// A countdown that runs from `now`. It becomes the default of the next `timer.start`.
    pub fn start_countdown(&mut self, now: u64, duration_ms: u64, label: &str) -> u64 {
        let id = self.new_id();
        self.timers.push(Timer {
            id,
            kind: Kind::Countdown,
            label: label.to_owned(),
            duration_ms,
            status: Status::Running {
                ends_at_ms: now + duration_ms,
            },
            phase: None,
            round: None,
            rounds: None,
            pending_end: false,
        });
        self.last_ms = Some(duration_ms);
        id
    }

    /// A pomodoro that starts with round 1 of focus.
    pub fn start_pomodoro(&mut self, now: u64, cycle: &Cycle, label: &str) -> u64 {
        let id = self.new_id();
        let duration_ms = cycle.focus_ms;
        self.timers.push(Timer {
            id,
            kind: Kind::Pomodoro,
            label: label.to_owned(),
            duration_ms,
            status: Status::Running {
                ends_at_ms: now + duration_ms,
            },
            phase: Some(Phase::Focus),
            round: Some(1),
            rounds: Some(cycle.rounds),
            pending_end: false,
        });
        id
    }

    /// Running → paused, keeping what is left. A timer that ran out already is not running any more.
    pub fn pause(&mut self, now: u64, id: u64) -> Result<(), Refusal> {
        let t = self.get_mut(id)?;
        match t.status {
            Status::Running { ends_at_ms } if ends_at_ms > now => {
                t.status = Status::Paused {
                    remaining_ms: ends_at_ms - now,
                };
                Ok(())
            }
            _ => Err(Refusal::NotRunning),
        }
    }

    /// Paused → running, from `now` with what was left.
    pub fn resume(&mut self, now: u64, id: u64) -> Result<(), Refusal> {
        let t = self.get_mut(id)?;
        match t.status {
            Status::Paused { remaining_ms } => {
                t.status = Status::Running {
                    ends_at_ms: now + remaining_ms,
                };
                Ok(())
            }
            _ => Err(Refusal::NotPaused),
        }
    }

    /// Adds `delta_ms` (a minute, or a scroll step back) to a timer. A running or paused timer keeps its place and
    /// its length grows with it (a countdown's ring stays a fraction); an ended one starts again from `now` with
    /// `delta_ms` only, so "+1 min" on a timer that rang runs a minute more.
    pub fn add(&mut self, now: u64, id: u64, delta_ms: i64) -> Result<(), Refusal> {
        let t = self.get_mut(id)?;
        let shifted = |v: u64| -> Option<u64> {
            let n = v as i128 + delta_ms as i128;
            (n > 0).then_some(n as u64)
        };
        match t.status.clone() {
            Status::Running { ends_at_ms } => {
                let ends = shifted(ends_at_ms)
                    .filter(|e| *e > now)
                    .ok_or(Refusal::TooShort)?;
                t.status = Status::Running { ends_at_ms: ends };
                if t.kind == Kind::Countdown {
                    t.duration_ms = shifted(t.duration_ms).unwrap_or(t.duration_ms);
                }
            }
            Status::Paused { remaining_ms } => {
                let remaining = shifted(remaining_ms).ok_or(Refusal::TooShort)?;
                t.status = Status::Paused {
                    remaining_ms: remaining,
                };
                if t.kind == Kind::Countdown {
                    t.duration_ms = shifted(t.duration_ms).unwrap_or(t.duration_ms);
                }
            }
            Status::Ended { .. } => {
                if delta_ms <= 0 {
                    return Err(Refusal::TooShort);
                }
                let d = delta_ms as u64;
                t.status = Status::Running {
                    ends_at_ms: now + d,
                };
                t.pending_end = false;
                if t.kind == Kind::Countdown {
                    t.duration_ms = d;
                }
            }
        }
        Ok(())
    }

    /// The next phase of a pomodoro starts now, whatever is left of this one.
    pub fn skip(&mut self, now: u64, id: u64, cycle: &Cycle) -> Result<(), Refusal> {
        let t = self.get_mut(id)?;
        if t.kind != Kind::Pomodoro {
            return Err(Refusal::NotPomodoro);
        }
        let rounds = t.rounds.unwrap_or(cycle.rounds);
        let (phase, round) = next_phase(
            t.phase.unwrap_or(Phase::Focus),
            t.round.unwrap_or(1),
            rounds,
        );
        let duration_ms = phase_ms(phase, cycle);
        t.phase = Some(phase);
        t.round = Some(round);
        t.duration_ms = duration_ms;
        t.status = Status::Running {
            ends_at_ms: now + duration_ms,
        };
        t.pending_end = false;
        Ok(())
    }

    pub fn stop(&mut self, id: u64) -> Result<(), Refusal> {
        let before = self.timers.len();
        self.timers.retain(|t| t.id != id);
        if self.timers.len() == before {
            return Err(Refusal::Gone);
        }
        Ok(())
    }

    pub fn stop_all(&mut self) {
        self.timers.clear();
    }

    /// Ends whatever ran out by `now`. A countdown goes to `Ended`. A pomodoro with `auto_advance` moves on through
    /// the phases that ran out, each new phase starting where the last one ended, and keeps running; without it, it
    /// waits in `Ended` at its phase. Returns one `End` per timer that changed, and sets its `pending_end`.
    pub fn reconcile(&mut self, now: u64, cycle: &Cycle) -> Vec<End> {
        let mut ends = Vec::new();
        for t in self.timers.iter_mut() {
            let Status::Running { ends_at_ms } = t.status else {
                continue;
            };
            if ends_at_ms > now {
                continue;
            }
            t.pending_end = true;
            if t.kind == Kind::Countdown || !cycle.auto_advance {
                t.status = Status::Ended {
                    ended_at_ms: ends_at_ms,
                };
                ends.push(End {
                    id: t.id,
                    at_ms: ends_at_ms,
                    kind: t.kind,
                    phase: t.phase,
                    round: t.round,
                    ended: true,
                });
                continue;
            }
            let rounds = t.rounds.unwrap_or(cycle.rounds);
            let (mut phase, mut round) = (t.phase.unwrap_or(Phase::Focus), t.round.unwrap_or(1));
            let mut start = ends_at_ms;
            let mut steps = 0;
            loop {
                let (next, next_round) = next_phase(phase, round, rounds);
                let len = phase_ms(next, cycle);
                phase = next;
                round = next_round;
                t.duration_ms = len;
                let ends = start + len;
                steps += 1;
                if ends > now || steps >= CATCH_UP_PHASES {
                    t.status = Status::Running {
                        ends_at_ms: ends.max(now + 1),
                    };
                    break;
                }
                start = ends;
            }
            t.phase = Some(phase);
            t.round = Some(round);
            ends.push(End {
                id: t.id,
                at_ms: ends_at_ms,
                kind: Kind::Pomodoro,
                phase: Some(phase),
                round: Some(round),
                ended: false,
            });
        }
        ends
    }

    /// The earliest end of a running timer: the one deadline the daemon sleeps to. None while nothing runs.
    pub fn next_deadline(&self) -> Option<u64> {
        self.timers
            .iter()
            .filter_map(|t| match t.status {
                Status::Running { ends_at_ms } => Some(ends_at_ms),
                _ => None,
            })
            .min()
    }

    pub fn running(&self) -> usize {
        self.timers
            .iter()
            .filter(|t| matches!(t.status, Status::Running { .. }))
            .count()
    }

    /// The ids of the ends nobody has been told about, oldest first.
    pub fn pending(&self) -> Vec<u64> {
        let mut out: Vec<(u64, u64)> = self
            .timers
            .iter()
            .filter(|t| t.pending_end)
            .map(|t| (end_time(t), t.id))
            .collect();
        out.sort();
        out.into_iter().map(|(_, id)| id).collect()
    }

    /// The document `mod.timer` (no nulls, PROTOCOL): timers nearest end first (running, then paused, then ended),
    /// with the settings the views need to draw them and to offer the presets.
    pub fn document(&self, cycle: &Cycle, presets: &[u64], background: bool) -> Value {
        let mut order: Vec<&Timer> = self.timers.iter().collect();
        order.sort_by_key(|t| (rank(t), end_time(t), t.id));
        let timers: Vec<Value> = order.into_iter().map(timer_json).collect();
        let mut doc = Map::new();
        doc.insert("available".into(), json!(true));
        doc.insert("background".into(), json!(background));
        doc.insert("timers".into(), json!(timers));
        doc.insert("presets".into(), json!(presets));
        doc.insert(
            "pomodoro".into(),
            json!({
                "focus_ms": cycle.focus_ms,
                "short_ms": cycle.short_ms,
                "long_ms": cycle.long_ms,
                "rounds": cycle.rounds,
                "auto_advance": cycle.auto_advance,
            }),
        );
        if let Some(ms) = self.last_ms {
            doc.insert("last_ms".into(), json!(ms));
        }
        Value::Object(doc)
    }
}

/// The moment a timer is due: its end while it runs, the moment it ended, and its remaining time after its end when
/// paused (sorting only; a paused timer is not due).
fn end_time(t: &Timer) -> u64 {
    match t.status {
        Status::Running { ends_at_ms } => ends_at_ms,
        Status::Paused { remaining_ms } => remaining_ms,
        Status::Ended { ended_at_ms } => ended_at_ms,
    }
}

fn rank(t: &Timer) -> u8 {
    match t.status {
        Status::Running { .. } => 0,
        Status::Paused { .. } => 1,
        Status::Ended { .. } => 2,
    }
}

fn timer_json(t: &Timer) -> Value {
    let mut o = Map::new();
    o.insert("id".into(), json!(t.id));
    o.insert(
        "kind".into(),
        json!(match t.kind {
            Kind::Countdown => "countdown",
            Kind::Pomodoro => "pomodoro",
        }),
    );
    o.insert("label".into(), json!(t.label));
    o.insert("duration_ms".into(), json!(t.duration_ms));
    match t.status {
        Status::Running { ends_at_ms } => {
            o.insert("state".into(), json!("running"));
            o.insert("ends_at_ms".into(), json!(ends_at_ms));
        }
        Status::Paused { remaining_ms } => {
            o.insert("state".into(), json!("paused"));
            o.insert("remaining_ms".into(), json!(remaining_ms));
        }
        Status::Ended { ended_at_ms } => {
            o.insert("state".into(), json!("ended"));
            o.insert("ended_at_ms".into(), json!(ended_at_ms));
        }
    }
    if let Some(p) = t.phase {
        o.insert(
            "phase".into(),
            json!(match p {
                Phase::Focus => "focus",
                Phase::ShortBreak => "short_break",
                Phase::LongBreak => "long_break",
            }),
        );
    }
    if let Some(r) = t.round {
        o.insert("round".into(), json!(r));
    }
    if let Some(r) = t.rounds {
        o.insert("rounds".into(), json!(r));
    }
    Value::Object(o)
}

#[cfg(test)]
mod tests {
    use super::*;

    const T0: u64 = 1_800_000_000_000;

    fn cycle() -> Cycle {
        Cycle {
            focus_ms: 25 * MINUTE_MS,
            short_ms: 5 * MINUTE_MS,
            long_ms: 15 * MINUTE_MS,
            rounds: 4,
            auto_advance: true,
        }
    }

    fn pomodoro(now: u64) -> (State, u64) {
        let mut s = State::default();
        let id = s.start_pomodoro(now, &cycle(), "");
        (s, id)
    }

    fn phase_of(s: &State, id: u64) -> (Option<Phase>, Option<u32>) {
        let t = s.timer(id).expect("timer");
        (t.phase, t.round)
    }

    #[test]
    fn pomodoro_phases_follow_the_cycle_and_the_long_break_comes_after_round_four() {
        let c = cycle();
        let (mut s, id) = pomodoro(T0);
        let mut seen = vec![phase_of(&s, id)];
        for _ in 0..9 {
            s.skip(T0, id, &c).unwrap();
            seen.push(phase_of(&s, id));
        }
        use Phase::*;
        let want = [
            (Some(Focus), Some(1)),
            (Some(ShortBreak), Some(1)),
            (Some(Focus), Some(2)),
            (Some(ShortBreak), Some(2)),
            (Some(Focus), Some(3)),
            (Some(ShortBreak), Some(3)),
            (Some(Focus), Some(4)),
            (Some(LongBreak), Some(4)),
            (Some(Focus), Some(1)),
            (Some(ShortBreak), Some(1)),
        ];
        assert_eq!(seen, want);
    }

    #[test]
    fn skip_refuses_a_countdown_and_unknown_ids() {
        let c = cycle();
        let mut s = State::default();
        let id = s.start_countdown(T0, MINUTE_MS, "");
        assert_eq!(s.skip(T0, id, &c), Err(Refusal::NotPomodoro));
        assert_eq!(s.skip(T0, 99, &c), Err(Refusal::Gone));
    }

    #[test]
    fn a_countdown_ends_once_and_is_pending_until_announced() {
        let c = cycle();
        let mut s = State::default();
        let id = s.start_countdown(T0, 60_000, "tea");
        assert!(s.reconcile(T0 + 59_999, &c).is_empty(), "not yet");
        let ends = s.reconcile(T0 + 60_000, &c);
        assert_eq!(ends.len(), 1);
        assert_eq!(ends[0].id, id);
        assert!(ends[0].ended);
        assert_eq!(ends[0].at_ms, T0 + 60_000);
        assert_eq!(s.pending(), vec![id]);
        assert!(
            s.reconcile(T0 + 120_000, &c).is_empty(),
            "an end is reported once"
        );
        assert_eq!(
            s.timer(id).unwrap().status,
            Status::Ended {
                ended_at_ms: T0 + 60_000
            }
        );
    }

    #[test]
    fn auto_advance_starts_the_break_at_the_old_end_not_at_the_reconcile() {
        let c = cycle();
        let (mut s, id) = pomodoro(T0);
        let ends = s.reconcile(T0 + 25 * MINUTE_MS + 10_000, &c);
        assert_eq!(ends.len(), 1);
        assert!(!ends[0].ended, "auto-advance keeps the timer running");
        assert_eq!(ends[0].phase, Some(Phase::ShortBreak));
        let t = s.timer(id).unwrap();
        assert_eq!(
            t.status,
            Status::Running {
                ends_at_ms: T0 + 30 * MINUTE_MS
            },
            "the break runs from the focus' end: 5 minutes after it, not after the reconcile"
        );
        assert_eq!(t.duration_ms, 5 * MINUTE_MS);
        assert!(t.pending_end);
    }

    #[test]
    fn a_pomodoro_that_missed_several_phases_catches_up_once() {
        let c = cycle();
        let (mut s, id) = pomodoro(T0);
        // Two hours later: focus (25), break (5), focus (25), break (5), focus (25), break (5) … still in the cycle.
        let now = T0 + 2 * 60 * MINUTE_MS + 7 * MINUTE_MS;
        let ends = s.reconcile(now, &c);
        assert_eq!(ends.len(), 1, "one notification for the catch-up");
        assert_eq!(
            ends[0].at_ms,
            T0 + 25 * MINUTE_MS,
            "the first end that was missed"
        );
        let t = s.timer(id).unwrap();
        let Status::Running { ends_at_ms } = t.status else {
            panic!("running after the catch-up");
        };
        assert!(ends_at_ms > now, "the phase it is in now runs on");
        assert!(
            ends_at_ms <= now + 25 * MINUTE_MS,
            "and is at most one phase long from now"
        );
    }

    #[test]
    fn without_auto_advance_a_pomodoro_waits_at_its_phase_until_next_phase() {
        let mut c = cycle();
        c.auto_advance = false;
        let (mut s, id) = pomodoro(T0);
        let ends = s.reconcile(T0 + 25 * MINUTE_MS, &c);
        assert_eq!(ends.len(), 1);
        assert!(ends[0].ended);
        assert_eq!(ends[0].phase, Some(Phase::Focus));
        assert_eq!(s.timer(id).unwrap().phase, Some(Phase::Focus));
        s.skip(T0 + 30 * MINUTE_MS, id, &c).unwrap();
        assert_eq!(phase_of(&s, id), (Some(Phase::ShortBreak), Some(1)));
        assert!(
            s.pending().is_empty(),
            "a user's skip clears the end: nothing to announce"
        );
        assert!(!s.timer(id).unwrap().pending_end);
    }

    #[test]
    fn pause_keeps_what_is_left_and_resume_runs_it_from_now() {
        let c = cycle();
        let mut s = State::default();
        let id = s.start_countdown(T0, 100_000, "");
        s.pause(T0 + 40_000, id).unwrap();
        assert_eq!(
            s.timer(id).unwrap().status,
            Status::Paused {
                remaining_ms: 60_000
            }
        );
        assert_eq!(s.pause(T0 + 41_000, id), Err(Refusal::NotRunning));
        assert!(
            s.reconcile(T0 + 10_000_000, &c).is_empty(),
            "a paused timer never ends"
        );
        s.resume(T0 + 70_000, id).unwrap();
        assert_eq!(
            s.timer(id).unwrap().status,
            Status::Running {
                ends_at_ms: T0 + 130_000
            }
        );
        assert_eq!(s.resume(T0 + 71_000, id), Err(Refusal::NotPaused));
    }

    #[test]
    fn plus_one_minute_moves_a_running_end_and_grows_the_countdown() {
        let mut s = State::default();
        let id = s.start_countdown(T0, 5 * MINUTE_MS, "");
        s.add(T0 + MINUTE_MS, id, MINUTE_MS as i64).unwrap();
        let t = s.timer(id).unwrap();
        assert_eq!(
            t.status,
            Status::Running {
                ends_at_ms: T0 + 6 * MINUTE_MS
            }
        );
        assert_eq!(t.duration_ms, 6 * MINUTE_MS);
    }

    #[test]
    fn plus_one_minute_on_a_timer_that_rang_runs_a_minute_more() {
        let c = cycle();
        let mut s = State::default();
        let id = s.start_countdown(T0, MINUTE_MS, "");
        s.reconcile(T0 + MINUTE_MS, &c);
        s.add(T0 + 2 * MINUTE_MS, id, MINUTE_MS as i64).unwrap();
        let t = s.timer(id).unwrap();
        assert_eq!(
            t.status,
            Status::Running {
                ends_at_ms: T0 + 3 * MINUTE_MS
            }
        );
        assert!(!t.pending_end, "the new run's end will be announced again");
        assert_eq!(t.duration_ms, MINUTE_MS);
    }

    #[test]
    fn a_change_that_would_leave_no_time_is_refused() {
        let mut s = State::default();
        let id = s.start_countdown(T0, 60_000, "");
        assert_eq!(
            s.add(T0 + 30_000, id, -60_000),
            Err(Refusal::TooShort),
            "a running timer may not be cut to its end or past it"
        );
        s.pause(T0 + 30_000, id).unwrap();
        assert_eq!(s.add(T0 + 30_000, id, -30_000), Err(Refusal::TooShort));
        assert_eq!(
            s.timer(id).unwrap().status,
            Status::Paused {
                remaining_ms: 30_000
            },
            "a refused change leaves the timer as it was"
        );
    }

    #[test]
    fn the_deadline_is_the_earliest_running_end_and_none_while_idle_or_paused() {
        let mut s = State::default();
        assert_eq!(s.next_deadline(), None, "idle: nothing to sleep to");
        let a = s.start_countdown(T0, 10 * MINUTE_MS, "");
        let b = s.start_countdown(T0, 2 * MINUTE_MS, "");
        assert_eq!(s.next_deadline(), Some(T0 + 2 * MINUTE_MS));
        s.pause(T0, b).unwrap();
        assert_eq!(s.next_deadline(), Some(T0 + 10 * MINUTE_MS));
        s.pause(T0, a).unwrap();
        assert_eq!(s.next_deadline(), None, "all paused: no deadline");
        assert_eq!(s.running(), 0);
    }

    #[test]
    fn stop_removes_a_timer_and_refuses_it_again() {
        let mut s = State::default();
        let id = s.start_countdown(T0, MINUTE_MS, "");
        s.stop(id).unwrap();
        assert_eq!(s.stop(id), Err(Refusal::Gone));
        assert!(s.timers.is_empty());
        let _ = s.start_countdown(T0, MINUTE_MS, "");
        s.stop_all();
        assert!(s.timers.is_empty());
    }

    #[test]
    fn ids_are_never_reused_and_the_last_countdown_is_remembered() {
        let mut s = State::default();
        let a = s.start_countdown(T0, 5 * MINUTE_MS, "");
        s.stop(a).unwrap();
        let b = s.start_countdown(T0, 10 * MINUTE_MS, "");
        assert_ne!(a, b);
        assert_eq!(s.last_ms, Some(10 * MINUTE_MS));
    }

    #[test]
    fn document_lists_the_nearest_end_first_and_carries_no_nulls() {
        let c = cycle();
        let mut s = State::default();
        let far = s.start_countdown(T0, 30 * MINUTE_MS, "far");
        let near = s.start_countdown(T0, 2 * MINUTE_MS, "near");
        let paused = s.start_countdown(T0, MINUTE_MS, "paused");
        s.pause(T0, paused).unwrap();
        let ended = s.start_countdown(T0, 1, "ended");
        s.reconcile(T0 + 1, &c);
        let doc = s.document(&c, &[5, 10, 25], true);
        let ids: Vec<u64> = doc["timers"]
            .as_array()
            .unwrap()
            .iter()
            .map(|t| t["id"].as_u64().unwrap())
            .collect();
        assert_eq!(ids, vec![near, far, paused, ended]);
        assert!(!contains_null(&doc), "no nulls in the document: {doc}");
        assert_eq!(doc["timers"][0]["state"], "running");
        assert_eq!(doc["timers"][0]["ends_at_ms"], T0 + 2 * MINUTE_MS);
        assert_eq!(doc["timers"][2]["state"], "paused");
        assert_eq!(doc["timers"][3]["state"], "ended");
        assert_eq!(doc["presets"], json!([5, 10, 25]));
        assert_eq!(doc["background"], true);
        assert!(
            doc["timers"][0].get("phase").is_none(),
            "a countdown has no phase"
        );
    }

    #[test]
    fn a_pomodoro_document_shows_its_phase_round_and_rounds() {
        let c = cycle();
        let (s, id) = pomodoro(T0);
        let doc = s.document(&c, &[25], true);
        let t = doc["timers"]
            .as_array()
            .unwrap()
            .iter()
            .find(|t| t["id"] == id)
            .unwrap();
        assert_eq!(t["kind"], "pomodoro");
        assert_eq!(t["phase"], "focus");
        assert_eq!(t["round"], 1);
        assert_eq!(t["rounds"], 4);
    }

    fn contains_null(v: &Value) -> bool {
        match v {
            Value::Null => true,
            Value::Array(a) => a.iter().any(contains_null),
            Value::Object(o) => o.values().any(contains_null),
            _ => false,
        }
    }

    #[test]
    fn a_state_that_was_saved_and_loaded_reconciles_the_same_way() {
        let c = cycle();
        let (mut s, id) = pomodoro(T0);
        s.start_countdown(T0, 3 * MINUTE_MS, "tea");
        let text = serde_json::to_string(&s).unwrap();
        let mut back: State = serde_json::from_str(&text).unwrap();
        assert_eq!(back, s, "the file round-trips");
        // The daemon was down past both ends: the countdown ends once, the pomodoro advances once.
        let later = T0 + 30 * MINUTE_MS;
        let ends = back.reconcile(later, &c);
        assert_eq!(ends.len(), 2);
        assert!(
            back.reconcile(later, &c).is_empty(),
            "nothing is reported twice after a restart"
        );
        assert_eq!(back.pending().len(), 2);
        assert!(back.timer(id).unwrap().pending_end);
    }
}
