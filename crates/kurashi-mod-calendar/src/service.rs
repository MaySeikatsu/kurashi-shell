//! The service of `mod.calendar` and the peek job (docs/ux/calendar.md "Motion, multi-output, budgets"). The service
//! runs only while the document has a subscriber (rule 5): it reads the sources, publishes, and then waits for a change
//! of a watched folder (inotify through `notify`, made here and dropped with the service), a feed falling due, local
//! midnight, a settings change or `calendar.refresh`. The peek job runs only while `peek` is on and the mod is
//! enabled: it raises the island face `peek_minutes` before each timed event. Nothing ticks per minute.

use std::collections::{BTreeMap, BTreeSet};
use std::path::{Path, PathBuf};
use std::sync::{Arc, Mutex, MutexGuard, OnceLock};
use std::time::Duration;

use jiff::tz::TimeZone;
use kurashi_mod_api::{FaceHandle, JobCtx, Publish, Settings, SlotHandle};
use serde_json::Value;
use tokio::sync::{Mutex as AsyncMutex, Notify, mpsc};

use crate::day;
use crate::doc::{self, Entry, Status};
use crate::expand::{self, Window};
use crate::http::{Http, HttpError};
use crate::ics;
use crate::khal;
use crate::sources::{self, Config, Read, Target};

/// The wall clock as unix seconds. Tests pass one of their own.
pub type Clock = Arc<dyn Fn() -> i64 + Send + Sync>;
/// The session's time zone, asked on each pass (a change of the system zone is seen at the next one).
pub type Zone = Arc<dyn Fn() -> TimeZone + Send + Sync>;

/// Days before today and after it that the document covers.
pub const DAYS_BEFORE: i32 = 7;
pub const DAYS_AFTER: i32 = 42;
/// Editors and sync tools write in bursts: settle this long after a change, then read once.
const SETTLE: Duration = Duration::from_millis(250);
/// The peek's transient lifetime on the island.
pub const PEEK_TTL_S: u32 = 30;
const PEEK_RELEVANCE: u8 = 60;

pub const REASON_OFFLINE: &str = "mod-calendar.source.offline";
pub const REASON_HTTP: &str = "mod-calendar.source.http";
pub const REASON_KHAL_MISSING: &str = "mod-calendar.khal.missing";
pub const REASON_KHAL_FAILED: &str = "mod-calendar.khal.failed";
pub const REASON_KHAL_FORMAT: &str = "mod-calendar.khal.format";

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum FeedError {
    Offline,
    Status,
    NotCalendar,
}

/// A feed's copy and its fetch history, per enable.
#[derive(Debug, Clone, Default)]
struct Feed {
    loaded: bool,
    text: Option<String>,
    fetched_at: Option<i64>,
    last_try: Option<i64>,
    failures: u32,
    error: Option<FeedError>,
}

/// Retry after 60 s, doubling, never later than one refresh.
fn backoff(failures: u32, refresh_s: i64) -> i64 {
    (60 * (1_i64 << failures.saturating_sub(1).min(10))).min(refresh_s)
}

impl Feed {
    fn due_at(&self, refresh_s: i64) -> i64 {
        match (self.last_try, self.error) {
            (None, _) => i64::MIN,
            (Some(t), Some(_)) => t + backoff(self.failures, refresh_s),
            (Some(t), None) => t + refresh_s,
        }
    }
}

fn fnv(s: &str) -> u64 {
    s.bytes().fold(0xcbf2_9ce4_8422_2325, |h, b| {
        (h ^ u64::from(b)).wrapping_mul(0x0100_0000_01b3)
    })
}

/// What the service, the job and the actions share, per enable.
pub struct Shared {
    pub http: Arc<dyn Http>,
    pub clock: Clock,
    pub zone: Zone,
    pub cache_dir: PathBuf,
    pub home: PathBuf,
    pub khal_bin: String,
    feeds: Mutex<BTreeMap<String, Feed>>,
    /// One fetch round at a time: the service and the job never fetch the same feed twice.
    gate: AsyncMutex<()>,
    /// `calendar.refresh` asked to fetch every feed now.
    force: Mutex<bool>,
    pub wake: Notify,
    pub job_wake: Notify,
    slot: OnceLock<SlotHandle>,
    slot_none: Mutex<Option<bool>>,
    face: OnceLock<FaceHandle>,
}

impl Shared {
    pub fn new(
        http: Arc<dyn Http>,
        clock: Clock,
        zone: Zone,
        cache_dir: PathBuf,
        home: PathBuf,
        khal_bin: String,
    ) -> Self {
        Self {
            http,
            clock,
            zone,
            cache_dir,
            home,
            khal_bin,
            feeds: Mutex::new(BTreeMap::new()),
            gate: AsyncMutex::new(()),
            force: Mutex::new(false),
            wake: Notify::new(),
            job_wake: Notify::new(),
            slot: OnceLock::new(),
            slot_none: Mutex::new(None),
            face: OnceLock::new(),
        }
    }

    fn feeds(&self) -> MutexGuard<'_, BTreeMap<String, Feed>> {
        self.feeds.lock().unwrap_or_else(|e| e.into_inner())
    }

    /// The slot's handle. Its reason is sent by the service and the job when they start, not here: the daemon takes
    /// slot reasons only once the enable is over.
    pub fn set_slot(&self, slot: SlotHandle) {
        let _ = self.slot.set(slot);
    }

    pub fn set_face(&self, face: FaceHandle) {
        let _ = self.face.set(face);
    }

    /// The agenda's slot says "No calendar connected" while no source is set (row 72); sent only when it changes.
    pub fn sync_slot(&self, cfg: &Config) {
        let Some(slot) = self.slot.get() else { return };
        let none = cfg.is_empty();
        let mut last = self.slot_none.lock().unwrap_or_else(|e| e.into_inner());
        if *last != Some(none) {
            *last = Some(none);
            slot.set_reason(none.then_some(doc::REASON_NO_SOURCE));
        }
    }

    /// `calendar.refresh`: fetch every feed on the next pass.
    pub fn refresh(&self) {
        *self.force.lock().unwrap_or_else(|e| e.into_inner()) = true;
        self.wake.notify_one();
        self.job_wake.notify_one();
    }

    fn cache_path(&self, url: &str) -> PathBuf {
        self.cache_dir.join(format!("feed-{:016x}.ics", fnv(url)))
    }

    /// The feed's state, with its cached copy read from disk on first use.
    fn feed(&self, url: &str) -> Feed {
        let mut feeds = self.feeds();
        let f = feeds.entry(url.to_owned()).or_default();
        if !f.loaded {
            f.loaded = true;
            let p = self.cache_path(url);
            if let Ok(text) = std::fs::read_to_string(&p) {
                f.fetched_at = std::fs::metadata(&p)
                    .and_then(|m| m.modified())
                    .ok()
                    .and_then(|t| t.duration_since(std::time::UNIX_EPOCH).ok())
                    .and_then(|d| i64::try_from(d.as_secs()).ok());
                f.text = Some(text);
            }
        }
        f.clone()
    }

    fn write_cache(&self, url: &str, body: &str) {
        let p = self.cache_path(url);
        let _ = std::fs::create_dir_all(&self.cache_dir);
        let tmp = p.with_extension("ics.tmp");
        if std::fs::write(&tmp, body).is_ok() {
            let _ = std::fs::rename(&tmp, &p);
        }
    }

    /// Fetches the feeds that are due (all of them after `calendar.refresh`). Returns whether any was fetched.
    async fn fetch_due(&self, cfg: &Config) -> bool {
        let _gate = self.gate.lock().await;
        let force = std::mem::take(&mut *self.force.lock().unwrap_or_else(|e| e.into_inner()));
        let mut any = false;
        for src in &cfg.sources {
            let Target::Feed(url) = &src.target else {
                continue;
            };
            let now = (self.clock)();
            if !force && self.feed(url).due_at(cfg.refresh_s) > now {
                continue;
            }
            any = true;
            let outcome = self.http.get(url.clone()).await;
            let now = (self.clock)();
            let error = match outcome {
                Ok(body) if ics::parse(&body).is_ok() => {
                    self.write_cache(url, &body);
                    let mut feeds = self.feeds();
                    let f = feeds.entry(url.clone()).or_default();
                    f.text = Some(body);
                    f.fetched_at = Some(now);
                    None
                }
                Ok(_) => Some(FeedError::NotCalendar),
                Err(HttpError::Status(_)) => Some(FeedError::Status),
                Err(HttpError::Offline(_) | HttpError::Body(_)) => Some(FeedError::Offline),
            };
            let mut feeds = self.feeds();
            let f = feeds.entry(url.clone()).or_default();
            f.last_try = Some(now);
            f.error = error;
            f.failures = if error.is_some() { f.failures + 1 } else { 0 };
        }
        any
    }

    /// Whether a feed is due now (so the first snapshot goes out before a slow fetch).
    fn any_due(&self, cfg: &Config) -> bool {
        let now = (self.clock)();
        let forced = *self.force.lock().unwrap_or_else(|e| e.into_inner());
        cfg.sources.iter().any(|s| match &s.target {
            Target::Feed(url) => forced || self.feed(url).due_at(cfg.refresh_s) <= now,
            Target::Path(_) => false,
        })
    }

    /// When the next feed falls due (unix), if any.
    fn next_due(&self, cfg: &Config) -> Option<i64> {
        cfg.sources
            .iter()
            .filter_map(|s| match &s.target {
                Target::Feed(url) => Some(self.feed(url).due_at(cfg.refresh_s)),
                Target::Path(_) => None,
            })
            .min()
    }

    /// Every source read now (no fetch): their states and the instances in the window.
    pub async fn collect(&self, cfg: &Config) -> (i32, Window, TimeZone, Vec<Status>, Vec<Entry>) {
        let local = (self.zone)();
        let today = day::civil_of(&local, (self.clock)()).0;
        let win = Window::around(&local, today, DAYS_BEFORE, DAYS_AFTER);
        let mut statuses = Vec::new();
        let mut entries = Vec::new();
        let add = |cals: Vec<sources::Named>, entries: &mut Vec<Entry>| {
            let mut n = 0;
            for c in cals {
                for occ in expand::expand(&c.cal, &local, &win) {
                    n += 1;
                    entries.push(Entry {
                        occ,
                        calendar: c.name.clone(),
                        color: c.color.clone(),
                    });
                }
            }
            n
        };
        for src in &cfg.sources {
            match &src.target {
                Target::Path(p) => {
                    let kind = if p.is_dir() { "folder" } else { "file" };
                    let fallback = if src.name.is_empty() {
                        stem(p)
                    } else {
                        src.name.clone()
                    };
                    let (state, reason, events) = match sources::read_path(src, p) {
                        Read::Missing => ("missing", Some(sources::REASON_MISSING), 0),
                        Read::Failed(r) => ("error", Some(r), 0),
                        Read::Calendars(cals) => ("ready", None, add(cals, &mut entries)),
                    };
                    statuses.push(Status {
                        name: fallback,
                        kind,
                        state,
                        reason,
                        events,
                        color: src.color.clone(),
                        fetched_at: None,
                    });
                }
                Target::Feed(url) => {
                    let f = self.feed(url);
                    let parsed = f.text.as_deref().and_then(|t| ics::parse(t).ok());
                    let name = [
                        Some(src.name.clone()).filter(|n| !n.is_empty()),
                        parsed.as_ref().and_then(|c| c.name.clone()),
                    ]
                    .into_iter()
                    .flatten()
                    .next()
                    .unwrap_or_else(|| host_of(url));
                    let color = src
                        .color
                        .clone()
                        .or_else(|| parsed.as_ref().and_then(|c| c.color.clone()));
                    let events = parsed.map_or(0, |cal| {
                        add(
                            vec![sources::Named {
                                name: name.clone(),
                                color: color.clone(),
                                cal,
                            }],
                            &mut entries,
                        )
                    });
                    let (state, reason) = match (f.error, f.text.is_some(), f.last_try) {
                        (Some(FeedError::Offline), _, _) => ("offline", Some(REASON_OFFLINE)),
                        (Some(FeedError::Status), _, _) => ("error", Some(REASON_HTTP)),
                        (Some(FeedError::NotCalendar), _, _) => {
                            ("error", Some(sources::REASON_NOT_CALENDAR))
                        }
                        (None, false, None) => ("loading", None),
                        (None, _, _) => ("ready", None),
                    };
                    statuses.push(Status {
                        name,
                        kind: "feed",
                        state,
                        reason,
                        events,
                        color,
                        fetched_at: f.text.as_ref().and(f.fetched_at),
                    });
                }
            }
        }
        if cfg.khal {
            let (state, reason, events) = match khal::list(&self.khal_bin, &local, &win).await {
                Ok(items) => {
                    let n = items.len();
                    entries.extend(items.into_iter().map(|i| Entry {
                        occ: i.occ,
                        calendar: i.calendar,
                        color: i.color,
                    }));
                    ("ready", None, n)
                }
                Err(khal::Error::Missing) => ("unavailable", Some(REASON_KHAL_MISSING), 0),
                Err(khal::Error::Failed) => ("error", Some(REASON_KHAL_FAILED), 0),
                Err(khal::Error::Format) => ("error", Some(REASON_KHAL_FORMAT), 0),
            };
            statuses.push(Status {
                name: "khal".into(),
                kind: "khal",
                state,
                reason,
                events,
                color: None,
                fetched_at: None,
            });
        }
        (today, win, local, statuses, entries)
    }

    pub async fn document(&self, cfg: &Config) -> Value {
        let (today, win, local, statuses, entries) = self.collect(cfg).await;
        doc::build(today, &win, &local, &statuses, &entries)
    }

    /// Seconds until one second past the next local midnight.
    fn until_midnight(&self) -> i64 {
        let local = (self.zone)();
        let now = (self.clock)();
        let today = day::civil_of(&local, now).0;
        (day::midnight(&local, today + 1) + 1 - now).max(1)
    }
}

fn stem(p: &Path) -> String {
    p.file_stem()
        .or_else(|| p.file_name())
        .map(|s| s.to_string_lossy().into_owned())
        .unwrap_or_default()
}

/// A feed's host, the name of a feed that has none of its own (the address itself is a secret).
fn host_of(url: &str) -> String {
    url.split("://")
        .nth(1)
        .and_then(|r| r.split(['/', '?', '#']).next())
        .map(|h| h.rsplit('@').next().unwrap_or(h).to_owned())
        .unwrap_or_default()
}

/// The folders of the path sources and whether to watch each recursively.
fn watch_targets(cfg: &Config) -> BTreeSet<(PathBuf, bool)> {
    cfg.sources
        .iter()
        .filter_map(|s| match &s.target {
            Target::Path(p) => sources::watch_dir(p),
            Target::Feed(_) => None,
        })
        .collect()
}

fn watch(
    targets: &BTreeSet<(PathBuf, bool)>,
    tx: mpsc::UnboundedSender<()>,
) -> Option<notify::RecommendedWatcher> {
    use notify::{RecursiveMode, Watcher};
    if targets.is_empty() {
        return None;
    }
    let mut w = notify::recommended_watcher(move |res: notify::Result<notify::Event>| {
        let Ok(ev) = res else { return };
        if !ev.kind.is_access() {
            let _ = tx.send(());
        }
    })
    .ok()?;
    for (dir, rec) in targets {
        let mode = if *rec {
            RecursiveMode::Recursive
        } else {
            RecursiveMode::NonRecursive
        };
        let _ = w.watch(dir, mode);
    }
    Some(w)
}

fn secs(n: i64) -> Duration {
    Duration::from_secs(u64::try_from(n.max(1)).unwrap_or(1))
}

/// `mod.calendar`'s service body: runs while subscribed; the watch lives exactly as long as this future.
pub async fn run(shared: Arc<Shared>, publish: Publish, mut settings: Settings) {
    let mut last = Value::Null;
    loop {
        let cfg = Config::read(&settings, &shared.home);
        shared.sync_slot(&cfg);
        let (tx, mut rx) = mpsc::unbounded_channel();
        let mut targets = watch_targets(&cfg);
        let mut watcher = watch(&targets, tx.clone());
        loop {
            // The cached copies go out first when a fetch is due: a slow feed never holds the local calendars back.
            if shared.any_due(&cfg) {
                let v = shared.document(&cfg).await;
                if v != last {
                    publish(v.clone());
                    last = v;
                }
                shared.fetch_due(&cfg).await;
            }
            let v = shared.document(&cfg).await;
            if v != last {
                publish(v.clone());
                last = v;
            }
            let now = (shared.clock)();
            let mut sleep = shared.until_midnight();
            if let Some(due) = shared.next_due(&cfg) {
                sleep = sleep.min(due - now);
            }
            tokio::select! {
                Some(()) = rx.recv() => {
                    tokio::time::sleep(SETTLE).await;
                    while rx.try_recv().is_ok() {}
                }
                () = shared.wake.notified() => {}
                () = tokio::time::sleep(secs(sleep)) => {}
                changed = settings.changed() => {
                    if !changed {
                        return;
                    }
                    break;
                }
            }
            // A file source whose folder appeared (or a folder that became a file) is watched from now on.
            let now_targets = watch_targets(&cfg);
            if now_targets != targets {
                drop(watcher.take());
                watcher = watch(&now_targets, tx.clone());
                targets = now_targets;
            }
        }
        drop(watcher);
    }
}

/// The peek job (`job:peek`, while `peek` is on): raises the island face `peek_minutes` before each timed event that
/// has not been peeked yet. Feeds are fetched when due here too, so the peek is not limited to what a view last saw.
pub async fn peek_job(shared: Arc<Shared>, job: JobCtx) {
    let mut settings = job.settings().clone();
    let mut peeked: BTreeSet<String> = BTreeSet::new();
    loop {
        let cfg = Config::read(&settings, &shared.home);
        job.set_active(!cfg.is_empty());
        shared.sync_slot(&cfg);
        shared.fetch_due(&cfg).await;
        let (_, _, _, _, entries) = shared.collect(&cfg).await;
        let now = (shared.clock)();
        peeked.retain(|k| {
            k.rsplit('-')
                .next()
                .and_then(|s| s.parse::<i64>().ok())
                .is_some_and(|t| t > now - 3600)
        });
        let mut upcoming: Vec<&Entry> = entries
            .iter()
            .filter(|e| !e.occ.all_day && e.occ.start > now)
            .collect();
        upcoming.sort_by_key(|e| e.occ.start);
        let mut wake = now + 3600;
        for e in upcoming {
            let id = doc::entry_id(e);
            let at = e.occ.start - cfg.peek_s;
            if at <= now {
                if peeked.insert(id) {
                    if let Some(face) = shared.face.get() {
                        face.raise(PEEK_RELEVANCE);
                    }
                }
                continue;
            }
            wake = wake.min(at);
            break;
        }
        wake = wake.min(now + shared.until_midnight());
        if let Some(due) = shared.next_due(&cfg) {
            wake = wake.min(due);
        }
        tokio::select! {
            () = tokio::time::sleep(secs(wake - now)) => {}
            () = shared.job_wake.notified() => {}
            changed = settings.changed() => {
                if !changed {
                    return;
                }
            }
        }
    }
}
