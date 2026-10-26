//! The state the entry points share (K73): the timer state under one lock, the file it is saved to, the version the
//! document service and the deadline job wait on, and the island face. Every change goes through [`Shared::with_state`]:
//! the ends that ran out are reconciled first, a change is saved, and the waiters are told. Nothing here sleeps; the job
//! sleeps to [`Shared::schedule`].

use std::collections::BTreeMap;
use std::path::PathBuf;
use std::sync::{Arc, Mutex, MutexGuard};

use chrono::TimeZone;
use kurashi_mod_api::FaceHandle;
use serde_json::Value;
use tokio::sync::watch;

use crate::model::{Kind, MINUTE_MS, Phase, State, Status, Timer, phase_ms};
use crate::notify::{Notice, Notifier, Signal};
use crate::settings::Cfg;
use crate::store;
use crate::texts::Texts;

/// Unix milliseconds from the clock the daemon uses (injected, so the tests set the time).
pub type Clock = Arc<dyn Fn() -> u64 + Send + Sync>;

/// The wall clock.
pub fn system_clock() -> Clock {
    Arc::new(|| {
        std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .map_or(0, |d| d.as_millis() as u64)
    })
}

/// How long the island's end face stays up after a timer ends (the arbiter's transient, K24), in ms.
pub const END_TTL_MS: u64 = 12_000;
/// The island face's relevance while a timer runs. Below a playing track, above the clock (K24).
pub const LIVE_RELEVANCE: u8 = 40;
/// The island face's relevance for the end, while it is still up (over the live face, which it replaces).
pub const END_RELEVANCE: u8 = 90;
/// An end found this long after it happened (the daemon was down) says when it ended.
const LATE_MS: u64 = 60_000;
/// Notifications whose buttons are still wired: the oldest are forgotten past this.
const MAX_NOTICES: usize = 64;

pub struct Inner {
    pub state: State,
    /// Notification id → timer id, for the buttons of the notices this mod posted.
    pub notices: BTreeMap<u32, u64>,
    /// The island's end face runs until this (Unix ms).
    pub face_until: Option<u64>,
}

pub struct Shared {
    pub path: PathBuf,
    pub clock: Clock,
    pub texts: Texts,
    pub notifier: Arc<dyn Notifier>,
    face: Option<FaceHandle>,
    inner: Mutex<Inner>,
    /// The relevance last raised on the face (`None`: cleared), so an unchanged face is not raised again.
    face_last: Mutex<Option<u8>>,
    version: watch::Sender<u64>,
}

impl Shared {
    /// `state` is what was loaded from the file; it is reconciled by the first [`Shared::tick`].
    pub fn new(
        path: PathBuf,
        clock: Clock,
        texts: Texts,
        notifier: Arc<dyn Notifier>,
        face: Option<FaceHandle>,
        state: State,
    ) -> Self {
        Self {
            path,
            clock,
            texts,
            notifier,
            face,
            inner: Mutex::new(Inner {
                state,
                notices: BTreeMap::new(),
                face_until: None,
            }),
            face_last: Mutex::new(None),
            version: watch::channel(0).0,
        }
    }

    pub fn now(&self) -> u64 {
        (self.clock)()
    }

    /// The document service and the job subscribe here: the version moves on every change of the state.
    pub fn subscribe(&self) -> watch::Receiver<u64> {
        self.version.subscribe()
    }

    fn lock(&self) -> MutexGuard<'_, Inner> {
        self.inner.lock().expect("timer state lock")
    }

    /// Runs `f` on the state under the lock, after the ends that ran out by now are reconciled. A change is saved and
    /// tells the waiters; the island face follows the state.
    pub fn with_state<T>(&self, cfg: &Cfg, f: impl FnOnce(&mut Inner, u64) -> T) -> T {
        let now = self.now();
        let (out, relevance, changed) = {
            let mut inner = self.lock();
            let before = inner.state.clone();
            let ends = inner.state.reconcile(now, &cfg.cycle);
            if !ends.is_empty() {
                inner.face_until = Some(now + END_TTL_MS);
            }
            let out = f(&mut inner, now);
            if inner.face_until.is_some_and(|until| until <= now) {
                inner.face_until = None;
            }
            let changed = inner.state != before;
            if changed {
                if let Err(e) = store::save(&self.path, &inner.state) {
                    tracing::warn!(file = %self.path.display(), error = %e, "timer state not saved");
                }
            }
            (out, relevance_of(&inner, now), changed)
        };
        self.apply_face(relevance);
        if changed {
            self.version.send_modify(|v| *v += 1);
        }
        out
    }

    /// Reconciles the ends that ran out, without a change of its own (the document service and the job call it).
    pub fn tick(&self, cfg: &Cfg) {
        self.with_state(cfg, |_, _| ());
    }

    /// The document `mod.timer` in effect now.
    pub fn document(&self, cfg: &Cfg) -> Value {
        self.lock().state.document(&cfg.cycle, &cfg.presets)
    }

    /// The next moment the job must wake (the earliest end, or the end face's time), and how many timers run now.
    pub fn schedule(&self) -> (Option<u64>, usize) {
        let inner = self.lock();
        let next = [inner.state.next_deadline(), inner.face_until]
            .into_iter()
            .flatten()
            .min();
        (next, inner.state.running())
    }

    fn apply_face(&self, want: Option<u8>) {
        let Some(face) = &self.face else {
            return;
        };
        {
            let mut last = self.face_last.lock().expect("face lock");
            if *last == want {
                return;
            }
            *last = want;
        }
        match want {
            Some(relevance) => face.raise(relevance),
            None => face.clear(),
        }
    }

    /// Tells the notification server about every end nobody has heard of, once each (K73: the end fires with every view
    /// closed; a restart announces an end that passed while down). An end whose notice cannot be shown still counts as
    /// told: the island and the state already show it.
    pub async fn announce(&self, cfg: &Cfg) {
        let now = self.now();
        let due: Vec<(u64, Notice, Status)> = {
            let inner = self.lock();
            inner
                .state
                .pending()
                .into_iter()
                .filter_map(|id| {
                    let t = inner.state.timer(id)?;
                    Some((id, self.notice_for(t, now, cfg), t.status.clone()))
                })
                .collect()
        };
        for (id, notice, status) in due {
            let shown = self.notifier.show(notice).await;
            self.with_state(cfg, |inner, _| {
                if let Some(t) = inner.state.timers.iter_mut().find(|t| t.id == id)
                    && t.status == status
                {
                    t.pending_end = false;
                }
                if let Some(nid) = shown {
                    inner.notices.insert(nid, id);
                    while inner.notices.len() > MAX_NOTICES {
                        let oldest = inner.notices.keys().next().copied();
                        if let Some(oldest) = oldest {
                            inner.notices.remove(&oldest);
                        }
                    }
                }
            });
        }
    }

    /// A signal of the notification server: a button of one of our notices runs the timer's operation (+1 min, Stop,
    /// Next phase); a refused one (the timer is gone) changes nothing.
    pub fn signal(&self, cfg: &Cfg, sig: Signal) {
        match sig {
            // An expired toast is not a closed notice: the centre keeps the item, and its buttons still act on it (the
            // server answers from its history). The mapping stays until a button is pressed or the oldest are forgotten.
            Signal::Closed { .. } => {}
            Signal::Invoked { id, key } => {
                let Some(timer) = self.lock().notices.remove(&id) else {
                    return;
                };
                let done = match key.as_str() {
                    "add" => self.with_state(cfg, |inner, now| {
                        inner.state.add(now, timer, MINUTE_MS as i64)
                    }),
                    "stop" => self.with_state(cfg, |inner, _| inner.state.stop(timer)),
                    "skip" => {
                        self.with_state(cfg, |inner, now| inner.state.skip(now, timer, &cfg.cycle))
                    }
                    _ => return,
                };
                if let Err(refusal) = done {
                    tracing::debug!(timer, ?refusal, key = %key, "timer notice button refused");
                }
            }
        }
    }

    /// The notice of a timer's end (or of a pomodoro's phase that has started): what the user reads and the buttons.
    fn notice_for(&self, t: &Timer, now: u64, cfg: &Cfg) -> Notice {
        let tx = &self.texts;
        let label = t.label.trim();
        let minutes = |ms: u64| (((ms + 30_000) / 60_000).max(1)).to_string();
        let app = tx.t("mods.timer.name", &[]);
        let mut actions = vec![("add".to_owned(), tx.t("mod-timer.action.add", &[]))];
        let (summary, body) = match t.kind {
            Kind::Countdown => {
                let summary = if label.is_empty() {
                    tx.t("mod-timer.name.timer", &[])
                } else {
                    label.to_owned()
                };
                let body = match t.status {
                    Status::Ended { ended_at_ms } if now.saturating_sub(ended_at_ms) > LATE_MS => {
                        tx.t(
                            "mod-timer.end.at",
                            &[("time", clock_text(ended_at_ms).as_str())],
                        )
                    }
                    _ => tx.t("mod-timer.end.up", &[]),
                };
                actions.push(("stop".to_owned(), tx.t("mod-timer.action.stop", &[])));
                (summary, body)
            }
            Kind::Pomodoro => {
                let summary = if label.is_empty() {
                    tx.t("mod-timer.name.pomodoro", &[])
                } else {
                    label.to_owned()
                };
                let phase = t.phase.unwrap_or(Phase::Focus);
                let body = match t.status {
                    Status::Ended { .. } => {
                        let name = tx.t(phase_key(phase), &[]);
                        tx.t("mod-timer.end.phase_over", &[("phase", name.as_str())])
                    }
                    _ => {
                        let min = minutes(phase_ms(phase, &cfg.cycle));
                        match phase {
                            Phase::Focus => {
                                let round = t.round.unwrap_or(1).to_string();
                                let rounds = t.rounds.unwrap_or(cfg.cycle.rounds).to_string();
                                tx.t(
                                    "mod-timer.phase.focus",
                                    &[
                                        ("round", round.as_str()),
                                        ("rounds", rounds.as_str()),
                                        ("min", min.as_str()),
                                    ],
                                )
                            }
                            Phase::ShortBreak => {
                                tx.t("mod-timer.phase.short", &[("min", min.as_str())])
                            }
                            Phase::LongBreak => {
                                tx.t("mod-timer.phase.long", &[("min", min.as_str())])
                            }
                        }
                    }
                };
                actions.push(("stop".to_owned(), tx.t("mod-timer.action.stop", &[])));
                actions.push(("skip".to_owned(), tx.t("mod-timer.action.next", &[])));
                (summary, body)
            }
        };
        Notice {
            app,
            summary,
            body,
            actions,
            sound: cfg.sound,
        }
    }
}

/// The relevance the island face should show now, or `None` to clear it: the end while its face is up, the live face
/// while a timer runs.
fn relevance_of(inner: &Inner, now: u64) -> Option<u8> {
    if inner.face_until.is_some_and(|until| until > now) {
        Some(END_RELEVANCE)
    } else if inner.state.running() > 0 {
        Some(LIVE_RELEVANCE)
    } else {
        None
    }
}

fn phase_key(phase: Phase) -> &'static str {
    match phase {
        Phase::Focus => "mod-timer.phase.name.focus",
        Phase::ShortBreak => "mod-timer.phase.name.short",
        Phase::LongBreak => "mod-timer.phase.name.long",
    }
}

/// The local clock time of a moment, `HH:MM`.
fn clock_text(ms: u64) -> String {
    chrono::Local
        .timestamp_millis_opt(ms as i64)
        .single()
        .map(|t| t.format("%H:%M").to_string())
        .unwrap_or_default()
}
