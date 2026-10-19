//! Where the readers look. The daemon reads `/proc` and `/sys`; tests point both at fixture trees, and so does the
//! live check of the states (`KURASHI_SYSMON_ROOT`, see `Sysmon::new`). Every file read goes through [`Roots::read`]
//! (or its siblings), so tests can count reads (no sampling without a subscriber, no read of a suspended GPU) and the
//! daemon never reads a file it did not mean to.

use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicUsize, Ordering};
use std::sync::{Arc, Mutex};
use std::time::SystemTime;

#[derive(Clone, Debug)]
pub struct Roots {
    pub proc: PathBuf,
    pub sys: PathBuf,
    /// The desktop-entry directories names are read from (I61), in precedence order.
    pub apps: Vec<PathBuf>,
    /// The language the names are read in: the daemon's (`LC_ALL`, `LC_MESSAGES`, `LANG`), so `Name[ja]` wins in ja.
    pub lang: String,
    /// The daemon's real uid. Processes of other users are listed, but never signalled (EPERM, shown).
    pub uid: u32,
    reads: Arc<AtomicUsize>,
    trace: Option<Arc<Mutex<Vec<PathBuf>>>>,
}

impl Roots {
    pub fn new(proc: impl Into<PathBuf>, sys: impl Into<PathBuf>, uid: u32) -> Self {
        Self {
            proc: proc.into(),
            sys: sys.into(),
            apps: Vec::new(),
            lang: "en".into(),
            uid,
            reads: Arc::default(),
            trace: None,
        }
    }

    /// The live system: `/proc`, `/sys`, the XDG desktop-entry directories, the session's language and this daemon's uid.
    pub fn system() -> Self {
        let mut roots = Self::new("/proc", "/sys", rustix::process::getuid().as_raw());
        roots.apps = xdg_application_dirs();
        roots.lang = language_from_env();
        roots
    }

    /// A fixture tree in place of the live system: `proc/`, `sys/` and `share/applications/` under `root`, owned by
    /// `uid`, named in the session's language. The states check serves its processes and devices this way; nothing
    /// is read outside the tree.
    pub fn fixture(root: &Path, uid: u32) -> Self {
        let mut roots = Self::new(root.join("proc"), root.join("sys"), uid);
        roots.apps = vec![root.join("share/applications")];
        roots.lang = language_from_env();
        roots
    }

    /// Keeps the list of paths read from now on (tests).
    pub fn traced(mut self) -> Self {
        self.trace = Some(Arc::default());
        self
    }

    /// Contents of a file, or None when it cannot be read (absent, vanished, not permitted).
    pub fn read(&self, path: impl AsRef<Path>) -> Option<String> {
        let path = path.as_ref();
        self.note(path);
        std::fs::read_to_string(path).ok()
    }

    /// The raw contents of a file (`cmdline` is NUL-separated and need not be UTF-8).
    pub fn read_bytes(&self, path: impl AsRef<Path>) -> Option<Vec<u8>> {
        let path = path.as_ref();
        self.note(path);
        std::fs::read(path).ok()
    }

    /// Where a symbolic link points (`exe`, `cwd`), or None when it is not readable.
    pub fn link(&self, path: impl AsRef<Path>) -> Option<PathBuf> {
        let path = path.as_ref();
        self.note(path);
        std::fs::read_link(path).ok()
    }

    /// When a directory's entries last changed (added, removed or renamed), or None when it cannot be seen.
    pub fn modified(&self, dir: impl AsRef<Path>) -> Option<SystemTime> {
        let dir = dir.as_ref();
        self.note(dir);
        std::fs::metadata(dir).and_then(|m| m.modified()).ok()
    }

    /// Entries of a directory in name order (procfs and sysfs do not promise one). Empty when unreadable.
    pub fn list(&self, dir: impl AsRef<Path>) -> Vec<PathBuf> {
        let mut out: Vec<PathBuf> = std::fs::read_dir(dir)
            .map(|rd| rd.filter_map(|e| e.ok().map(|e| e.path())).collect())
            .unwrap_or_default();
        out.sort();
        out
    }

    /// Number of file reads made through this root (and its clones).
    pub fn reads(&self) -> usize {
        self.reads.load(Ordering::SeqCst)
    }

    /// Paths read, in order, when [`Roots::traced`] was set.
    pub fn trace(&self) -> Vec<PathBuf> {
        self.trace
            .as_ref()
            .map(|t| t.lock().expect("trace lock").clone())
            .unwrap_or_default()
    }

    fn note(&self, path: &Path) {
        self.reads.fetch_add(1, Ordering::SeqCst);
        if let Some(trace) = &self.trace {
            trace.lock().expect("trace lock").push(path.to_path_buf());
        }
    }
}

/// The name of a directory entry, or "" when it has none.
pub fn name_of(path: &Path) -> &str {
    path.file_name().and_then(|n| n.to_str()).unwrap_or("")
}

/// The language of the session, as the daemon's i18n reads it (`kurashid::i18n::locale_from_env`): the first of
/// `LC_ALL`, `LC_MESSAGES`, `LANG` that is set, cut at `_`, `.` or `@`; `C` and `POSIX` are English.
pub fn language_from_env() -> String {
    let raw = ["LC_ALL", "LC_MESSAGES", "LANG"]
        .iter()
        .filter_map(|k| std::env::var(k).ok())
        .find(|v| !v.is_empty())
        .unwrap_or_default();
    let lang = raw.split(['_', '.', '@']).next().unwrap_or("");
    if lang.is_empty() || lang == "C" || lang == "POSIX" {
        "en".into()
    } else {
        lang.to_ascii_lowercase()
    }
}

/// `applications/` under the user's data home, then under each XDG data dir (the freedesktop lookup order).
fn xdg_application_dirs() -> Vec<PathBuf> {
    let non_empty = |name: &str| std::env::var_os(name).filter(|v| !v.is_empty());
    let home = non_empty("XDG_DATA_HOME")
        .map(PathBuf::from)
        .or_else(|| non_empty("HOME").map(|h| PathBuf::from(h).join(".local/share")));
    let dirs = non_empty("XDG_DATA_DIRS")
        .map(|v| v.to_string_lossy().into_owned())
        .unwrap_or_else(|| "/usr/local/share:/usr/share".into());
    home.into_iter()
        .chain(dirs.split(':').filter(|d| !d.is_empty()).map(PathBuf::from))
        .map(|d| d.join("applications"))
        .collect()
}
