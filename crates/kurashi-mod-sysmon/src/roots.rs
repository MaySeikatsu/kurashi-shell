//! Where the readers look. The daemon reads `/proc` and `/sys`; tests point both at fixture trees.
//! Every file read goes through [`Roots::read`], so tests can count reads (no sampling without a
//! subscriber, no read of a suspended GPU) and the daemon never reads a file it did not mean to.

use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicUsize, Ordering};
use std::sync::{Arc, Mutex};

#[derive(Clone, Debug)]
pub struct Roots {
    pub proc: PathBuf,
    pub sys: PathBuf,
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
            uid,
            reads: Arc::default(),
            trace: None,
        }
    }

    /// The live system: `/proc`, `/sys` and this daemon's uid.
    pub fn system() -> Self {
        Self::new("/proc", "/sys", rustix::process::getuid().as_raw())
    }

    /// Keeps the list of paths read from now on (tests).
    pub fn traced(mut self) -> Self {
        self.trace = Some(Arc::default());
        self
    }

    /// Contents of a file, or None when it cannot be read (absent, vanished, not permitted).
    pub fn read(&self, path: impl AsRef<Path>) -> Option<String> {
        let path = path.as_ref();
        self.reads.fetch_add(1, Ordering::SeqCst);
        if let Some(trace) = &self.trace {
            trace.lock().expect("trace lock").push(path.to_path_buf());
        }
        std::fs::read_to_string(path).ok()
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
}

/// The name of a directory entry, or "" when it has none.
pub fn name_of(path: &Path) -> &str {
    path.file_name().and_then(|n| n.to_str()).unwrap_or("")
}
