//! Timer and pomodoro native mod (K73; docs/ux/timer.md; card W43-timer). Linked into kurashid by `native::linked()`; its
//! manifest and QML live in `mods/timer/`. It registers what that manifest's `provides` lists: the document `mod.timer`,
//! the actions `timer.*`, the deadline job (one daemon timer, the earliest end) and the island face. The views are QML:
//! they read the document and send the actions, and they interpolate from `ends_at_ms`.

pub mod actions;
mod job;
pub mod model;
pub mod notify;
mod service;
pub mod settings;
pub mod shared;
pub mod store;
pub mod texts;

use std::path::PathBuf;
use std::sync::Arc;

use kurashi_mod_api::{FaceSpec, ModCtx, ModError, NativeMod};

pub use model::State;
pub use settings::Cfg;

use shared::{Clock, Shared};

/// The timer mod. `new()` is what the daemon links; `with` is for the tests (a state file, a clock, a notifier).
#[derive(Clone)]
pub struct TimerMod {
    state_path: Option<PathBuf>,
    clock: Clock,
    notifier: Arc<dyn notify::Notifier>,
    texts: Option<texts::Texts>,
}

impl TimerMod {
    pub fn new() -> Self {
        Self {
            state_path: None,
            clock: shared::system_clock(),
            notifier: Arc::new(notify::DbusNotifier),
            texts: None,
        }
    }

    pub fn with(
        state_path: PathBuf,
        clock: Clock,
        notifier: Arc<dyn notify::Notifier>,
        texts: texts::Texts,
    ) -> Self {
        Self {
            state_path: Some(state_path),
            clock,
            notifier,
            texts: Some(texts),
        }
    }
}

impl Default for TimerMod {
    fn default() -> Self {
        Self::new()
    }
}

impl NativeMod for TimerMod {
    fn id(&self) -> &'static str {
        "timer"
    }

    fn enable(&self, ctx: &mut ModCtx) -> Result<(), ModError> {
        let face = ctx.face(
            "timer",
            FaceSpec {
                transient: false,
                ttl_s: 0,
            },
        )?;
        let settings = ctx.settings().clone();
        let cfg = Cfg::read(&settings);
        let path = self.state_path.clone().unwrap_or_else(store::default_path);
        let texts = self.texts.clone().unwrap_or_else(texts::Texts::from_env);
        let loaded = store::load(&path);
        let shared = Arc::new(Shared::new(
            path,
            self.clock.clone(),
            texts,
            self.notifier.clone(),
            Some(face),
            loaded,
        ));
        // The ends that passed while the daemon was down are reconciled now; the job announces them once it runs.
        shared.tick(&cfg);
        let initial = shared.document(&cfg);

        let s = shared.clone();
        ctx.service("timer", initial, move |publish, settings| {
            service::run(s.clone(), publish, settings)
        })?;

        macro_rules! act {
            ($id:literal, $label:literal, $f:path) => {{
                let s = shared.clone();
                let settings = settings.clone();
                ctx.action($id, $label, move |args| {
                    let r = $f(&s, &settings, &args);
                    async move { r }
                })?;
            }};
        }
        act!("timer.start", "mod-timer.action.start", actions::start);
        act!(
            "timer.pomodoro.start",
            "mod-timer.action.pomodoro",
            actions::pomodoro_start
        );
        act!("timer.pause", "mod-timer.action.pause", actions::pause);
        act!("timer.resume", "mod-timer.action.resume", actions::resume);
        act!("timer.add", "mod-timer.action.add", actions::add);
        act!("timer.skip", "mod-timer.action.next", actions::skip);
        act!("timer.stop", "mod-timer.action.stop", actions::stop);
        act!(
            "timer.stop_all",
            "mod-timer.action.stop_all",
            actions::stop_all
        );

        let s = shared.clone();
        ctx.background("deadline", "mods.running.timer", "background", move |job| {
            let s = s.clone();
            async move { job::run(s, job).await }
        })?;
        Ok(())
    }
}
