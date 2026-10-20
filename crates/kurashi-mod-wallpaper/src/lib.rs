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
//!
//! Wallhaven (K48 (3), [`wallhaven`]): search and download on request, from the picker's Wallhaven tab.

mod backend;
mod browse;
mod config;
mod exec;
mod library;
mod preview;
mod rotate;
mod state;
mod supervisor;
mod thumbs;
pub mod wallhaven;

use std::path::{Path, PathBuf};
use std::sync::{Arc, Mutex};

use kurashi_mod_api::{ActionError, Choice, ModCtx, ModError, NativeMod, Publish, Settings};
use serde_json::{Value, json};
use tokio::sync::{mpsc, oneshot, watch};

pub use backend::{BACKENDS, BackendId};
pub use exec::{Exec, ExecError, ExecFuture, ExecOutput, SystemExec};

use config::Config;
use supervisor::{Cmd, Reply, Shared, Supervisor};

/// Where the mod keeps its files: the state file, the thumbnail cache and the Wallhaven downloads, under kurashi's
/// own XDG directories (`$XDG_STATE_HOME/kurashi`, `$XDG_CACHE_HOME/kurashi`, `$XDG_DATA_HOME/kurashi`).
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Dirs {
    pub state: PathBuf,
    pub cache: PathBuf,
    pub data: PathBuf,
}

impl Dirs {
    pub fn from_env() -> Self {
        Self {
            state: xdg("XDG_STATE_HOME", ".local/state"),
            cache: xdg("XDG_CACHE_HOME", ".cache"),
            data: xdg("XDG_DATA_HOME", ".local/share"),
        }
    }

    /// Both directories under `root` (tests).
    pub fn rooted(root: &Path) -> Self {
        Self {
            state: root.join("state"),
            cache: root.join("cache"),
            data: root.join("data"),
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
        let installed =
            BackendId::parse(&cfg.backend).is_some_and(|b| self.exec.find(b.cli()).is_some());
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
            let origin = origin_of(&args);
            let theme = args["theme"].as_bool().unwrap_or(false);
            ask(&s, |reply| Cmd::Set {
                path,
                outputs,
                origin,
                theme,
                reply,
            })
            .await
        }
    })?;

    // A dry run: no state, so it needs no supervisor (docs/ux/wallpaper.md, the theme diff).
    ctx.action(
        "wallpaper.preview",
        "action.wallpaper.preview",
        |args| async move { preview::run(args).await },
    )?;

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
                // `image` is the look's picture (`path` is accepted too); `variant` the palette
                // it uses (`palette` too).
                let path = args["image"]
                    .as_str()
                    .or_else(|| args["path"].as_str())
                    .filter(|p| !p.is_empty())
                    .map(expand)
                    .ok_or_else(|| ActionError::Invalid("mod-wallpaper.error.path".into()))?;
                let scheme = args["scheme"].as_str().map(str::to_string);
                let variant = args["variant"]
                    .as_str()
                    .or_else(|| args["palette"].as_str())
                    .map(str::to_string);
                ask(&s, |reply| Cmd::Favourite {
                    path,
                    scheme,
                    variant,
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
    ctx.action("wallpaper.thumbs", "action.wallpaper.thumbs", move |args| {
        let s = s.clone();
        async move { browse::thumbs(&s, args).await }
    })?;

    // Wallhaven (K48): on request only; the API base can point at a fixture server (KURASHI_WALLHAVEN_API).
    let base = Arc::new(wallhaven::base_from_env());
    let (s, b) = (shared.clone(), base.clone());
    ctx.action(
        "wallpaper.wallhaven.search",
        "action.wallpaper.wallhaven.search",
        move |args| {
            let (s, b) = (s.clone(), b.clone());
            async move { wallhaven::search(&s.settings, &s.dirs, &b, args).await }
        },
    )?;
    let s = shared.clone();
    ctx.action(
        "wallpaper.wallhaven.download",
        "action.wallpaper.wallhaven.download",
        move |args| {
            let (s, b) = (s.clone(), base.clone());
            async move { wallhaven::download(&s.settings, &s.dirs, &b, args).await }
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

/// `origin: {x, y}` of an action's arguments: the picker tile a request came from, in output-local
/// pixels. Negative coordinates are clamped: a tile cannot sit left of or above its output.
fn origin_of(args: &Value) -> Option<(i64, i64)> {
    let x = args["origin"]["x"].as_i64()?;
    let y = args["origin"]["y"].as_i64()?;
    Some((x.max(0), y.max(0)))
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
/// installed, `missing` when it is not. `loaded` stays false until the first look is done. Absent
/// values are left out, never null (PROTOCOL §3; B25): no `next_at` and no `theme.image` yet.
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
        },
        "favourites": [],
        "theme": {},
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
        assert_eq!(d.wallhaven(), PathBuf::from("/r/data/wallpaper/wallhaven"));
        assert_eq!(
            d.wallhaven_thumbs(),
            PathBuf::from("/r/cache/wallpaper/wallhaven")
        );
    }

    /// Every null in a document, by its path (B25: documents never contain null, PROTOCOL §3).
    fn nulls_in(v: &Value, at: &str, found: &mut Vec<String>) {
        match v {
            Value::Null => found.push(at.to_owned()),
            Value::Object(map) => map
                .iter()
                .for_each(|(k, c)| nulls_in(c, &format!("{at}.{k}"), found)),
            Value::Array(items) => items
                .iter()
                .enumerate()
                .for_each(|(i, c)| nulls_in(c, &format!("{at}[{i}]"), found)),
            _ => {}
        }
    }

    #[test]
    fn the_initial_document_holds_no_null_whether_or_not_the_backend_is_installed() {
        for installed in [false, true] {
            let mut found = Vec::new();
            nulls_in(
                &initial_doc(&Config::default(), installed),
                "mod.wallpaper",
                &mut found,
            );
            assert_eq!(found, Vec::<String>::new(), "installed: {installed}");
        }
    }
}
