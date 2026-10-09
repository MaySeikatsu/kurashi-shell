//! The wallpaper: the first native mod (K26, docs/MODS.md "First native mod: wallpaper",
//! docs/ux/wallpaper.md). It drives an external daemon, awww (default) or swww, and keeps the
//! picture, the library, the favourites and the rotation in its own state.
//!
//! Lifetime: the supervisor ([`supervisor`]) runs while the mod is enabled, not while a document has
//! a subscriber. Wallpapers stay set and rotation keeps going with the picker closed, so the service
//! is enabled-scoped; it is started from `enable` (the daemon runs `enable` inside its runtime) and
//! ends when the mod's settings feed closes at disable. The document `mod.wallpaper` is served from a
//! watch channel the supervisor fills, so a subscriber always gets the current state at once.
//!
//! The backend's daemon is not stopped on disable: it keeps the last image on screen, which is what
//! a disabled wallpaper mod should leave behind. It is stopped when the backend is switched or on
//! `wallpaper.backend.restart`.
//!
//! Shōjiki: nothing is reported as applied before the backend accepted it; a missing binary, a
//! daemon that does not answer and a failed call are states of `mod.wallpaper`, with reasons.

mod backend;
mod browse;
mod config;
mod exec;
mod library;
mod rotate;
mod state;
mod supervisor;
mod thumbs;

use std::path::{Path, PathBuf};
use std::sync::{Arc, Mutex};

use kurashi_mod_api::{
    ActionError, Choice, ModCtx, ModError, NativeMod, Publish, Settings,
};
use serde_json::{Value, json};
use tokio::sync::{mpsc, oneshot, watch};

pub use backend::{BACKENDS, BackendId};
pub use exec::{Exec, ExecError, ExecOutput, SystemExec};

use config::Config;
use supervisor::{Cmd, Reply, Shared, Supervisor};

/// Where the mod keeps its files: the state file and the thumbnail cache, both under kurashi's own
/// XDG directories (`$XDG_STATE_HOME/kurashi`, `$XDG_CACHE_HOME/kurashi`).
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Dirs {
    pub state: PathBuf,
    pub cache: PathBuf,
}

impl Dirs {
    pub fn from_env() -> Self {
        Self {
            state: xdg("XDG_STATE_HOME", ".local/state"),
            cache: xdg("XDG_CACHE_HOME", ".cache"),
        }
    }

    /// Both directories under `root` (tests).
    pub fn rooted(root: &Path) -> Self {
        Self {
            state: root.join("state"),
            cache: root.join("cache"),
        }
    }

    pub fn state_file(&self) -> PathBuf {
        self.state.join(state::FILE)
    }

    pub fn thumbs(&self) -> PathBuf {
        self.cache.join("wallpaper").join("thumbs")
    }
}

fn xdg(var: &str, fallback: &str) -> PathBuf {
    let base = std::env::var_os(var)
        .filter(|v| !v.is_empty())
        .map(PathBuf::from)
        .unwrap_or_else(|| {
            PathBuf::from(std::env::var_os("HOME").unwrap_or_default()).join(fallback)
        });
    base.join("kurashi")
}

/// The wallpaper mod. Linked into kurashid by `native::linked()`.
pub struct Wallpaper {
    exec: Arc<dyn Exec>,
    dirs: Dirs,
}

impl Wallpaper {
    /// The daemon's configuration: the PATH it was started with, the XDG directories.
    pub fn new() -> Self {
        Self::with(Arc::new(SystemExec::from_env()), Dirs::from_env())
    }

    /// Any executor and directories (tests use a fake backend on a temporary PATH).
    pub fn with(exec: Arc<dyn Exec>, dirs: Dirs) -> Self {
        Self { exec, dirs }
    }
}

impl Default for Wallpaper {
    fn default() -> Self {
        Self::new()
    }
}

impl NativeMod for Wallpaper {
    fn id(&self) -> &'static str {
        "wallpaper"
    }

    fn enable(&self, ctx: &mut ModCtx) -> Result<(), ModError> {
        // `enable` runs in the daemon's runtime (main's `block_on`, or a task that reloads config);
        // without one the supervisor cannot run, and the enable is refused rather than half-done.
        let runtime = tokio::runtime::Handle::try_current()
            .map_err(|_| ModError::Failed("mod-wallpaper.error.runtime".into()))?;
        let settings: Settings = ctx.settings().clone();
        let cfg = Config::read(&settings);
        // Installed: a PATH lookup only (no process), so the quick tile's readiness is known now.
        let installed = BackendId::parse(&cfg.backend)
            .is_some_and(|b| self.exec.find(b.cli()).is_some());
        let initial = initial_doc(&cfg, installed);

        let (doc_tx, _) = watch::channel(initial.clone());
        let (cmd_tx, cmd_rx) = mpsc::unbounded_channel();
        let shared = Arc::new(Shared {
            doc: doc_tx,
            cmd: cmd_tx,
            settings: settings.clone(),
            exec: self.exec.clone(),
            dirs: self.dirs.clone(),
            scans: Mutex::new(None),
        });

        // The document: served while subscribed, from the supervisor's current state. A subscriber
        // asks for a refresh (backend check, library count) when it arrives.
        let serve = shared.clone();
        ctx.service("wallpaper", initial, move |publish: Publish, _settings| {
            let serve = serve.clone();
            async move {
                let _ = serve.cmd.send(Cmd::Refresh);
                let mut rx = serve.doc.subscribe();
                loop {
                    let doc = rx.borrow_and_update().clone();
                    publish(doc);
                    if rx.changed().await.is_err() {
                        break;
                    }
                }
            }
        })?;

        let backends = self.exec.clone();
        let choices = ctx.choices("wallpaper.backends", move || {
            BACKENDS
                .into_iter()
                .map(|b| {
                    let c = Choice::new(b.id(), b.id());
                    if backends.find(b.cli()).is_some() {
                        c
                    } else {
                        c.unavailable("mod-wallpaper.backend.missing")
                    }
                })
                .collect()
        })?;

        register_actions(ctx, &shared)?;

        // Spawned last: a refused registration returns before anything runs. The task ends on its
        // own when the mod is disabled (the settings feed closes).
        let supervisor = Supervisor::new(shared, cmd_rx, choices);
        let _task = runtime.spawn(supervisor.run());
        Ok(())
    }
}

fn register_actions(ctx: &mut ModCtx, shared: &Arc<Shared>) -> Result<(), ModError> {
    let s = shared.clone();
    ctx.action("wallpaper.set", "action.wallpaper.set", move |args| {
        let s = s.clone();
        async move {
            let path = args["path"]
                .as_str()
                .filter(|p| !p.is_empty())
                .ok_or_else(|| ActionError::Invalid("mod-wallpaper.error.path".into()))?;
            let path = expand(path);
            if !path.is_absolute() {
                return Err(ActionError::Invalid("mod-wallpaper.error.path".into()));
            }
            let outputs = target_outputs(&args);
            ask(&s, |reply| Cmd::Set {
                path,
                outputs,
                reply,
            })
            .await
        }
    })?;

    for (id, label, forward, random) in [
        ("wallpaper.next", "action.wallpaper.next", true, false),
        ("wallpaper.prev", "action.wallpaper.prev", false, false),
        ("wallpaper.random", "action.wallpaper.random", true, true),
    ] {
        let s = shared.clone();
        ctx.action(id, label, move |args| {
            let s = s.clone();
            async move {
                let output = target_outputs(&args).into_iter().next();
                ask(&s, |reply| Cmd::Step {
                    forward,
                    random,
                    output,
                    reply,
                })
                .await
            }
        })?;
    }

    let s = shared.clone();
    ctx.action(
        "wallpaper.favourite",
        "action.wallpaper.favourite",
        move |args| {
            let s = s.clone();
            async move {
                let path = args["path"]
                    .as_str()
                    .filter(|p| !p.is_empty())
                    .map(expand)
                    .ok_or_else(|| ActionError::Invalid("mod-wallpaper.error.path".into()))?;
                let scheme = args["scheme"].as_str().map(str::to_string);
                let palette = args["palette"].as_str().map(str::to_string);
                ask(&s, |reply| Cmd::Favourite {
                    path,
                    scheme,
                    palette,
                    reply,
                })
                .await
            }
        },
    )?;

    let s = shared.clone();
    ctx.action(
        "wallpaper.rotation.pause",
        "action.wallpaper.rotation.pause",
        move |args| {
            let s = s.clone();
            async move {
                let on = args["on"].as_bool();
                ask(&s, |reply| Cmd::Pause { on, reply }).await
            }
        },
    )?;

    let s = shared.clone();
    ctx.action(
        "wallpaper.backend.restart",
        "action.wallpaper.backend.restart",
        move |_| {
            let s = s.clone();
            async move { ask(&s, |reply| Cmd::Restart { reply }).await }
        },
    )?;

    let s = shared.clone();
    ctx.action(
        "wallpaper.thumbs",
        "action.wallpaper.thumbs",
        move |args| {
            let s = s.clone();
            async move { browse::thumbs(&s, args).await }
        },
    )?;

    let s = shared.clone();
    ctx.action(
        "wallpaper.cache.clear",
        "action.wallpaper.cache.clear",
        move |_| {
            let s = s.clone();
            async move { browse::clear_cache(&s).await }
        },
    )?;
    Ok(())
}

/// Sends one command to the supervisor and waits for its answer. The mod being off in between is
/// an answer too: the command channel is gone.
async fn ask(
    shared: &Shared,
    make: impl FnOnce(Reply) -> Cmd,
) -> Result<Option<Value>, ActionError> {
    let (reply, answer) = oneshot::channel();
    let off = || ActionError::Unavailable("mod-wallpaper.error.off".to_string());
    if shared.cmd.send(make(reply)).is_err() {
        return Err(off());
    }
    answer.await.unwrap_or_else(|_| Err(off()))
}

/// `output` (one name) or `outputs` (a list) of an action's arguments; none = every output.
fn target_outputs(args: &Value) -> Vec<String> {
    if let Some(name) = args["output"].as_str().filter(|n| !n.is_empty()) {
        return vec![name.to_string()];
    }
    args["outputs"]
        .as_array()
        .into_iter()
        .flatten()
        .filter_map(|v| v.as_str().map(str::to_string))
        .collect()
}

fn expand(path: &str) -> PathBuf {
    match (path.strip_prefix("~/"), std::env::var_os("HOME")) {
        (Some(rest), Some(home)) => PathBuf::from(home).join(rest),
        _ => PathBuf::from(path),
    }
}

/// What the document says before the supervisor has looked: the backend is `starting` when it is
/// installed, `missing` when it is not. `loaded` stays false until the first look is done.
fn initial_doc(cfg: &Config, installed: bool) -> Value {
    json!({
        "loaded": false,
        "available": installed,
        "backend": {
            "id": cfg.backend,
            "available": false,
            "reason": if installed { "mod-wallpaper.backend.starting" } else { "mod-wallpaper.backend.missing" },
        },
        "outputs": {},
        "library": {"count": 0, "folders": []},
        "rotation": {
            "on": false,
            "interval_min": cfg.rotate_min,
            "paused": false,
            "order": cfg.order_name(),
            "per_output": cfg.per_output,
            "next_at": null,
        },
        "favourites": [],
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn target_outputs_takes_one_name_or_a_list_or_none() {
        assert_eq!(target_outputs(&json!({"output": "DP-1"})), ["DP-1"]);
        assert_eq!(target_outputs(&json!({"outputs": ["A", "B"]})), ["A", "B"]);
        assert!(target_outputs(&json!({})).is_empty(), "none = all outputs");
    }

    #[test]
    fn a_home_relative_path_expands_and_others_do_not() {
        assert_eq!(expand("/x/y.png"), PathBuf::from("/x/y.png"));
        assert_eq!(expand("relative.png"), PathBuf::from("relative.png"));
    }

    #[test]
    fn the_cache_and_state_live_under_kurashis_own_directories() {
        let d = Dirs::rooted(Path::new("/r"));
        assert_eq!(d.state_file(), PathBuf::from("/r/state/wallpaper.json"));
        assert_eq!(d.thumbs(), PathBuf::from("/r/cache/wallpaper/thumbs"));
    }
}
