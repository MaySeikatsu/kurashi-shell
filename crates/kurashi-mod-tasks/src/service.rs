//! The service of `mod.tasks` (K46, docs/ux/tasks.md "Fit"). It runs only while the document has a subscriber (rule 5):
//! it reads both files, publishes, and then waits for one of four things — a change of either file in its folder (an
//! inotify watch through `notify`, made here and dropped with the service), an action that wrote, a settings change
//! (another file), or local midnight (today's done items and the due chips roll over). Nothing polls.

use std::collections::BTreeSet;
use std::ffi::OsString;
use std::path::{Path, PathBuf};
use std::sync::{Arc, Mutex, MutexGuard};
use std::time::Duration;

use kurashi_mod_api::{Publish, Settings};
use serde_json::Value;
use tokio::sync::{Notify, mpsc};

use crate::doc;
use crate::store::{self, Paths};

/// Today's local date as `YYYY-MM-DD`. Tests pass a fixed one.
pub type Today = Arc<dyn Fn() -> String + Send + Sync>;

/// Editors write in bursts (temp file, rename, chmod): the service settles this long, then reads once.
const SETTLE: Duration = Duration::from_millis(120);

/// The settings in effect, as paths.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Config {
    pub file: PathBuf,
    pub notes: PathBuf,
    pub show_done: bool,
}

impl Config {
    pub fn read(s: &Settings, paths: &Paths) -> Self {
        let text = |key: &str| {
            s.get(key)
                .and_then(|v| v.as_str().map(str::to_owned))
                .unwrap_or_default()
        };
        Self {
            file: paths.resolve(&text("file"), "tasks.md"),
            notes: paths.resolve(&text("notes_file"), "notes.md"),
            show_done: s.get("show_done").and_then(|v| v.as_bool()).unwrap_or(true),
        }
    }
}

/// What the service and the actions share, per enable.
pub struct Shared {
    pub paths: Paths,
    pub today: Today,
    /// One read-modify-write at a time: two actions never interleave on the file.
    write: Mutex<()>,
    /// An action wrote: publish now (the watch would see it too, but not when the folder was only just made).
    pub wake: Notify,
}

impl Shared {
    pub fn new(paths: Paths, today: Today) -> Self {
        Self {
            paths,
            today,
            write: Mutex::new(()),
            wake: Notify::new(),
        }
    }

    pub fn write_lock(&self) -> MutexGuard<'_, ()> {
        self.write.lock().unwrap_or_else(|e| e.into_inner())
    }

    pub fn document(&self, cfg: &Config) -> Value {
        doc::build(
            &cfg.file,
            &store::read(&cfg.file),
            &cfg.notes,
            &store::read(&cfg.notes),
            cfg.show_done,
            &(self.today)(),
        )
    }
}

/// The folders to watch (those of both files that exist) and the file names that matter in them. A symlinked file is
/// watched where it points too, so an edit through the vault's real path is seen.
fn targets(cfg: &Config) -> (BTreeSet<PathBuf>, BTreeSet<OsString>) {
    let mut dirs = BTreeSet::new();
    let mut names = BTreeSet::new();
    for f in [&cfg.file, &cfg.notes] {
        let mut add = |p: &Path| {
            if let (Some(dir), Some(name)) = (p.parent(), p.file_name()) {
                if dir.is_dir() {
                    dirs.insert(dir.to_path_buf());
                }
                names.insert(name.to_os_string());
            }
        };
        add(f);
        if let Ok(real) = std::fs::canonicalize(f) {
            add(&real);
        }
    }
    (dirs, names)
}

fn watch(
    dirs: &BTreeSet<PathBuf>,
    names: BTreeSet<OsString>,
    tx: mpsc::UnboundedSender<()>,
) -> Option<notify::RecommendedWatcher> {
    use notify::{RecursiveMode, Watcher};
    let mut w = notify::recommended_watcher(move |res: notify::Result<notify::Event>| {
        let Ok(ev) = res else { return };
        if ev.kind.is_access() {
            return;
        }
        if ev
            .paths
            .iter()
            .any(|p| p.file_name().is_some_and(|n| names.contains(n)))
        {
            let _ = tx.send(());
        }
    })
    .ok()?;
    for d in dirs {
        let _ = w.watch(d, RecursiveMode::NonRecursive);
    }
    Some(w)
}

/// How long until one second past the next local midnight.
fn until_midnight() -> Duration {
    use chrono::{Local, TimeZone};
    let now = Local::now();
    let next = now
        .date_naive()
        .succ_opt()
        .and_then(|d| d.and_hms_opt(0, 0, 1))
        .and_then(|t| Local.from_local_datetime(&t).earliest());
    next.and_then(|n| (n - now).to_std().ok())
        .unwrap_or(Duration::from_secs(3600))
}

/// `mod.tasks`'s service body: runs while subscribed; the watch lives exactly as long as this future.
pub async fn run(shared: Arc<Shared>, publish: Publish, mut settings: Settings) {
    let mut last = Value::Null;
    loop {
        let cfg = Config::read(&settings, &shared.paths);
        let (tx, mut rx) = mpsc::unbounded_channel();
        let (mut dirs, names) = targets(&cfg);
        let mut watcher = watch(&dirs, names.clone(), tx.clone());
        loop {
            let value = shared.document(&cfg);
            if value != last {
                publish(value.clone());
                last = value;
            }
            tokio::select! {
                Some(()) = rx.recv() => {
                    tokio::time::sleep(SETTLE).await;
                    while rx.try_recv().is_ok() {}
                }
                () = shared.wake.notified() => {}
                () = tokio::time::sleep(until_midnight()) => {}
                changed = settings.changed() => {
                    if !changed {
                        return;
                    }
                    break;
                }
            }
            // A folder that did not exist (the first add makes it) is watched from now on.
            let (now_dirs, _) = targets(&cfg);
            if now_dirs != dirs {
                drop(watcher.take());
                watcher = watch(&now_dirs, names.clone(), tx.clone());
                dirs = now_dirs;
            }
        }
        drop(watcher);
    }
}
