//! `kurashi-launcher`: the data side of the launcher (no UI).
//!
//! Index `.desktop` files, answer `{"t":"query","kind":"launcher"}` with ranked results, learn
//! from launches (frecency) and start apps per the Desktop Entry spec. The daemon owns the
//! `Launcher`; the frontend only sends queries and a launch intent.

pub mod calc;
pub mod extras;
pub mod desktop;
pub mod exec;
pub mod frecency;
pub mod index;
pub mod matcher;
pub mod watch;

use std::path::PathBuf;
use std::sync::{Arc, Mutex, RwLock};
use std::time::{Duration, SystemTime, UNIX_EPOCH};

pub use exec::LaunchOptions;
pub use frecency::Frecency;
pub use index::{Index, IndexConfig, Kind, QueryResult};
pub use watch::Watcher;

#[derive(Debug, thiserror::Error)]
pub enum LaunchError {
    #[error("unknown launcher id: {0}")]
    UnknownId(String),
    #[error("invalid Exec: {0}")]
    BadExec(String),
    #[error("entry needs a terminal but no terminal command is configured")]
    NoTerminal,
    #[error("failed to start {0}: {1}")]
    Spawn(String, std::io::Error),
}

fn unix_now() -> u64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map_or(0, |d| d.as_secs())
}

struct Inner {
    cfg: IndexConfig,
    opts: LaunchOptions,
    index: RwLock<Arc<Index>>,
    frecency: Mutex<Frecency>,
}

/// Cheap to clone; all clones share the index and frecency state.
#[derive(Clone)]
pub struct Launcher(Arc<Inner>);

impl Launcher {
    pub fn new(cfg: IndexConfig, opts: LaunchOptions, frecency: Frecency) -> Self {
        let index = Arc::new(Index::build(&cfg));
        Self(Arc::new(Inner {
            cfg,
            opts,
            index: RwLock::new(index),
            frecency: Mutex::new(frecency),
        }))
    }

    /// Frecency persisted at `state_file` (e.g. `~/.local/state/kurashi/launcher.json`).
    pub fn with_state_file(cfg: IndexConfig, opts: LaunchOptions, state_file: PathBuf) -> Self {
        Self::new(cfg, opts, Frecency::load(state_file))
    }

    /// Rebuild the index from disk. Queries in flight keep the old snapshot.
    pub fn reindex(&self) {
        let fresh = Arc::new(Index::build(&self.0.cfg));
        *self.0.index.write().unwrap() = fresh;
    }

    pub fn len(&self) -> usize {
        self.0.index.read().unwrap().len()
    }

    pub fn is_empty(&self) -> bool {
        self.len() == 0
    }

    pub fn query(&self, q: &str, limit: usize) -> Vec<QueryResult> {
        self.query_at(q, limit, unix_now())
    }

    pub fn query_at(&self, q: &str, limit: usize, now: u64) -> Vec<QueryResult> {
        let index = self.0.index.read().unwrap().clone();
        let fr = self.0.frecency.lock().unwrap();
        index.query(q, limit, &fr, now)
    }

    /// Re-index (debounced) whenever the applications dirs change, then call `on_change`
    /// so the daemon can push a fresh result set to subscribers. No polling.
    pub fn watch(
        &self,
        debounce: Duration,
        on_change: impl Fn() + Send + 'static,
    ) -> std::io::Result<Watcher> {
        let me = self.clone();
        Watcher::new(&self.0.cfg.dirs, debounce, move || {
            me.reindex();
            on_change();
        })
    }

    /// The argv that `launch` would run. Pure; what the tests assert.
    pub fn command_for(&self, id: &str, files: &[String]) -> Result<Vec<String>, LaunchError> {
        let index = self.0.index.read().unwrap().clone();
        let (app_id, action_id) = match id.split_once(':') {
            Some((a, b)) => (a, Some(b)),
            None => (id, None),
        };
        let app = index
            .app(app_id)
            .ok_or_else(|| LaunchError::UnknownId(id.into()))?;
        let e = &app.entry;
        let path = app.path.to_string_lossy();
        let target = match action_id {
            None => exec::Target {
                exec: e.exec.as_deref().unwrap_or_default(),
                name: &e.name,
                icon: e.icon.as_deref(),
                desktop_path: &path,
                terminal: e.terminal,
            },
            Some(aid) => {
                let a = e
                    .actions
                    .iter()
                    .find(|a| a.id == aid)
                    .ok_or_else(|| LaunchError::UnknownId(id.into()))?;
                exec::Target {
                    exec: &a.exec,
                    name: &e.name,
                    icon: a.icon.as_deref().or(e.icon.as_deref()),
                    desktop_path: &path,
                    // Actions of a Terminal=true app still run in a terminal.
                    terminal: e.terminal,
                }
            }
        };
        exec::build_command(&target, files, &self.0.opts)
    }

    /// Start the app detached and record the launch. Returns the pid.
    pub fn launch(&self, id: &str, files: &[String]) -> Result<u32, LaunchError> {
        let argv = self.command_for(id, files)?;
        let pid = exec::spawn(&argv)?;
        self.0.frecency.lock().unwrap().record(id, unix_now());
        Ok(pid)
    }
}

#[cfg(test)]
mod tests;
