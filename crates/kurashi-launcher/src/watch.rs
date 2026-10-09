//! inotify watcher with debounce. Event-driven: both threads block (no polling, Ma).

use std::collections::HashMap;
use std::io;
use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Arc, mpsc};
use std::thread::{self, JoinHandle};
use std::time::Duration;

use inotify::{EventMask, Inotify, WatchDescriptor, WatchMask, Watches};

const MASK: WatchMask = WatchMask::CLOSE_WRITE
    .union(WatchMask::CREATE)
    .union(WatchMask::DELETE)
    .union(WatchMask::MOVED_FROM)
    .union(WatchMask::MOVED_TO)
    .union(WatchMask::DELETE_SELF)
    .union(WatchMask::MOVE_SELF);

/// Dropping the watcher stops both threads.
pub struct Watcher {
    stop: Arc<AtomicBool>,
    watches: Watches,
    roots: Vec<WatchDescriptor>,
    threads: Vec<JoinHandle<()>>,
}

impl Watcher {
    /// Watch `dirs` (existing ones; subdirectories included) and call `on_change` once per burst
    /// of changes, `debounce` after the last event.
    pub fn new(
        dirs: &[PathBuf],
        debounce: Duration,
        mut on_change: impl FnMut() + Send + 'static,
    ) -> io::Result<Self> {
        let inotify = Inotify::init()?;
        let mut watches = inotify.watches();
        let mut map: HashMap<WatchDescriptor, PathBuf> = HashMap::new();
        let mut roots = Vec::new();
        for d in dirs.iter().filter(|d| d.is_dir()) {
            roots.push(add_tree(&mut watches, &mut map, d)?);
        }

        if roots.is_empty() {
            // Nothing to watch would leave the reader blocked forever.
            return Err(io::Error::new(
                io::ErrorKind::NotFound,
                "no existing directory to watch",
            ));
        }

        let stop = Arc::new(AtomicBool::new(false));
        let (tx, rx) = mpsc::channel::<()>();

        let reader = {
            let stop = stop.clone();
            let mut watches = watches.clone();
            let mut inotify = inotify;
            thread::Builder::new()
                .name("launcher-inotify".into())
                .spawn(move || {
                    let mut buf = [0u8; 4096];
                    while !stop.load(Ordering::Acquire) {
                        let Ok(events) = inotify.read_events_blocking(&mut buf) else {
                            break;
                        };
                        let mut relevant = false;
                        for ev in events {
                            if ev.mask.contains(EventMask::IGNORED) {
                                map.remove(&ev.wd);
                                continue;
                            }
                            let is_dir = ev.mask.contains(EventMask::ISDIR);
                            if is_dir
                                && ev.mask.intersects(EventMask::CREATE | EventMask::MOVED_TO)
                                && let (Some(parent), Some(name)) = (map.get(&ev.wd), ev.name)
                            {
                                let p = parent.join(name);
                                let _ = add_tree(&mut watches, &mut map, &p);
                            }
                            relevant |= is_dir
                                || ev.name.is_none() // self events
                                || ev.name.is_some_and(|n| n.as_encoded_bytes().ends_with(b".desktop"));
                        }
                        if relevant && tx.send(()).is_err() {
                            break;
                        }
                    }
                })?
        };

        let debouncer = thread::Builder::new()
            .name("launcher-debounce".into())
            .spawn(move || {
                // Block until the first event, then absorb the burst.
                while rx.recv().is_ok() {
                    loop {
                        match rx.recv_timeout(debounce) {
                            Ok(()) => continue,
                            Err(mpsc::RecvTimeoutError::Timeout) => break,
                            Err(mpsc::RecvTimeoutError::Disconnected) => return,
                        }
                    }
                    on_change();
                }
            })?;

        Ok(Self {
            stop,
            watches,
            roots,
            threads: vec![reader, debouncer],
        })
    }
}

fn add_tree(
    watches: &mut Watches,
    map: &mut HashMap<WatchDescriptor, PathBuf>,
    dir: &Path,
) -> io::Result<WatchDescriptor> {
    let wd = watches.add(dir, MASK)?;
    map.insert(wd.clone(), dir.to_path_buf());
    if let Ok(rd) = std::fs::read_dir(dir) {
        for e in rd.flatten() {
            if e.file_type().is_ok_and(|t| t.is_dir()) {
                let _ = add_tree(watches, map, &e.path());
            }
        }
    }
    Ok(wd)
}

impl Drop for Watcher {
    fn drop(&mut self) {
        self.stop.store(true, Ordering::Release);
        // Removing a watch queues IN_IGNORED, which wakes the blocked reader so it can exit.
        for wd in self.roots.drain(..) {
            let _ = self.watches.remove(wd);
        }
        for t in self.threads.drain(..) {
            let _ = t.join();
        }
    }
}
