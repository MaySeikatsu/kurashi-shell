//! Tasks and notes native mod (K46; docs/ux/tasks.md; card W22-tasks). Linked into kurashid by `native::linked()`; its
//! manifest and QML live in `mods/tasks/`. It registers what that manifest's `provides` lists for the daemon: the
//! service `mod.tasks` and the actions `tasks.*`. The desk cards, the panel and the bar widget are QML; they read the
//! document and send the actions. The data is two Markdown files the user owns (a checklist and a note), by default
//! under `$XDG_DATA_HOME/kurashi/`, or anywhere the settings point (an Obsidian vault).

pub mod actions;
pub mod doc;
pub mod markdown;
pub mod service;
pub mod store;

use std::sync::Arc;

use kurashi_mod_api::{ModCtx, ModError, NativeMod};

pub use service::{Config, Today};
pub use store::Paths;

use service::Shared;

/// The tasks mod. `new()` is what the daemon links; `with` is for tests (a temporary data dir, a fixed today).
#[derive(Clone)]
pub struct TasksMod {
    paths: Paths,
    today: Today,
}

impl TasksMod {
    pub fn new() -> Self {
        Self::with(Paths::from_env(), Arc::new(local_today))
    }

    pub fn with(paths: Paths, today: Today) -> Self {
        Self { paths, today }
    }
}

impl Default for TasksMod {
    fn default() -> Self {
        Self::new()
    }
}

/// Today's local date, `YYYY-MM-DD`.
pub fn local_today() -> String {
    chrono::Local::now().format("%Y-%m-%d").to_string()
}

impl NativeMod for TasksMod {
    fn id(&self) -> &'static str {
        "tasks"
    }

    fn enable(&self, ctx: &mut ModCtx) -> Result<(), ModError> {
        let shared = Arc::new(Shared::new(self.paths.clone(), self.today.clone()));
        let settings = ctx.settings().clone();

        // The first snapshot is the files as they are now (one read), so a subscriber never sees a state that is not true.
        let initial = shared.document(&Config::read(&settings, &shared.paths));
        let s = shared.clone();
        ctx.service("tasks", initial, move |publish, settings| {
            service::run(s.clone(), publish, settings)
        })?;

        macro_rules! act {
            ($id:literal, $label:literal, $f:expr) => {{
                let s = shared.clone();
                let settings = settings.clone();
                ctx.action($id, $label, move |args| {
                    let r = $f(&s, &settings, &args);
                    async move { r }
                })?;
            }};
        }
        act!("tasks.add", "mod-tasks.action.add", actions::add);
        act!("tasks.toggle", "mod-tasks.action.toggle", actions::toggle);
        act!("tasks.edit", "mod-tasks.action.edit", actions::edit);
        act!("tasks.remove", "mod-tasks.action.remove", actions::remove);
        act!(
            "tasks.clear_done",
            "mod-tasks.action.clear_done",
            |s: &Shared, settings: &kurashi_mod_api::Settings, _args: &serde_json::Value| {
                actions::clear_done(s, settings)
            }
        );
        act!(
            "tasks.notes.set",
            "mod-tasks.action.notes_set",
            actions::notes_set
        );
        Ok(())
    }
}
