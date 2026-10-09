//! The mod's daemon side (K26, K28): two documents, the watch, the trouble face and the process actions.
//!
//! Ma (docs/ux/sysmon.md, "Fit"): `mod.sysmon` samples only while something subscribes to it (bar, panel
//! or the face), `mod.sysmon.procs` only while the panel lists processes, and the watch task only while
//! the opt-in `watch` setting is on, every 10 s. Pause stops all three. A stopped summary clears a trouble
//! that nothing else keeps alive, so the face never shows a value that is no longer measured.

use crate::doc::{self, History, TroubleDoc};
use crate::procs::{self, Row};
use crate::roots::Roots;
use crate::sampler::{Memory, Sample, Sampler};
use crate::trouble::{Kind, Limits, Readings, Transition, Trouble};
use kurashi_mod_api::{
    ActionError, FaceHandle, FaceSpec, ModCtx, ModError, NativeMod, Publish, Settings,
};
use serde_json::{Value, json};
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Arc, Mutex};
use std::time::Duration;
use tokio::runtime::Handle;
// tokio's Instant, so the sustain window and the rates follow the paused clock in tests.
use tokio::sync::watch;
use tokio::time::Instant;

/// Relevance of the trouble face (0..=100): above the clock and media faces, below a notification
/// the user asked for. Fixed: the arbiter orders faces, the trouble only needs to be shown.
const FACE_RELEVANCE: u8 = 70;
/// The first CPU percentage needs a second read; this is how long after the first one it comes.
const BASELINE: Duration = Duration::from_millis(250);
/// The watch samples this often while it is on (docs/ux/sysmon.md: "a slow 10 s sampler").
const WATCH_EVERY: Duration = Duration::from_secs(10);

/// The settings in effect (`mods.sysmon.*`, the defaults of mod.toml). Clamped to the ranges the
/// manifest declares, so a value the config holds outside them still means something defined.
#[derive(Clone, Debug, PartialEq)]
pub struct Cfg {
    pub interval: Duration,
    /// The stats the bar shows, in its order.
    pub bar: Vec<&'static str>,
    pub sensor: String,
    pub watch: bool,
    pub sustain: Duration,
    pub limits: Limits,
}

impl Cfg {
    pub fn of(s: &Settings) -> Self {
        let int = |key: &str, default: i64, lo: i64, hi: i64| {
            s.get(key)
                .and_then(|v| v.as_i64())
                .unwrap_or(default)
                .clamp(lo, hi)
        };
        let flag =
            |key: &str, default: bool| s.get(key).and_then(|v| v.as_bool()).unwrap_or(default);
        let limit = |stat: &str, activity: i64, critical: i64, max: i64| crate::trouble::Limit {
            activity: int(&format!("{stat}_activity"), activity, 0, max) as f64,
            critical: int(&format!("{stat}_critical"), critical, 0, max) as f64,
        };
        let bar = [
            ("show_cpu", "cpu", true),
            ("show_mem", "mem", true),
            ("show_temp", "temp", false),
            ("show_load", "load", false),
        ]
        .into_iter()
        .filter(|(key, _, default)| flag(key, *default))
        .map(|(_, stat, _)| stat)
        .collect();
        let sensor = s
            .get("temp_sensor")
            .and_then(|v| v.as_str().map(|t| t.trim().to_string()))
            .filter(|t| !t.is_empty())
            .unwrap_or_else(|| "auto".into());
        Self {
            interval: Duration::from_secs(int("interval", 2, 1, 60) as u64),
            bar,
            sensor,
            watch: flag("watch", false),
            sustain: Duration::from_secs(int("sustain", 30, 5, 600) as u64),
            limits: Limits {
                cpu: limit("cpu", 50, 90, 100),
                mem: limit("mem", 60, 90, 100),
                temp: limit("temp", 60, 85, 120),
            },
        }
    }
}

/// A signal the mod sends: End is SIGTERM (the program may save first), Force quit is SIGKILL.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Sig {
    Term,
    Kill,
}

impl Sig {
    pub fn name(self) -> &'static str {
        match self {
            Sig::Term => "TERM",
            Sig::Kill => "KILL",
        }
    }
}

/// Sends a signal to a process. The daemon uses [`Kernel`]; tests record instead, so they never signal
/// a real process.
pub trait Signaller: Send + Sync {
    fn send(&self, pid: i32, sig: Sig) -> std::io::Result<()>;
}

/// `kill(2)` through rustix.
pub struct Kernel;

impl Signaller for Kernel {
    fn send(&self, pid: i32, sig: Sig) -> std::io::Result<()> {
        let pid = rustix::process::Pid::from_raw(pid)
            .ok_or_else(|| std::io::Error::from(std::io::ErrorKind::InvalidInput))?;
        let signal = match sig {
            Sig::Term => rustix::process::Signal::TERM,
            Sig::Kill => rustix::process::Signal::KILL,
        };
        Ok(rustix::process::kill_process(pid, signal)?)
    }
}

pub struct Sysmon {
    roots: Roots,
    signaller: Arc<dyn Signaller>,
    /// The daemon's runtime, captured where it is known to exist: the watch task is spawned from `enable`,
    /// which the config store may call from a thread that is not part of the runtime.
    runtime: Option<Handle>,
    self_pid: u32,
}

impl Sysmon {
    /// The live system, signalled through kill(2), on the runtime that is current here.
    pub fn new() -> Self {
        Self::with(
            Roots::system(),
            Arc::new(Kernel),
            Handle::try_current().ok(),
        )
    }

    pub fn with(roots: Roots, signaller: Arc<dyn Signaller>, runtime: Option<Handle>) -> Self {
        Self {
            roots,
            signaller,
            runtime,
            self_pid: std::process::id(),
        }
    }
}

impl Default for Sysmon {
    fn default() -> Self {
        Self::new()
    }
}

/// What one enable shares between its documents, its actions and its watch.
struct Shared {
    roots: Roots,
    face: FaceHandle,
    pause: watch::Sender<bool>,
    /// The process list's sort: true = by memory, false = by CPU.
    sort: watch::Sender<bool>,
    /// The watch task samples now (reported in `mod.sysmon`).
    watching: AtomicBool,
    trouble: Mutex<Trouble>,
    self_pid: u32,
}

/// The face is raised while any kind is sustained, and cleared when none is. Both calls happen under the
/// trouble lock, so two samplers (the summary and the watch) cannot reorder a raise and a clear.
impl Shared {
    fn feed(&self, now: Instant, readings: Readings, limits: &Limits, sustain: Duration) {
        let mut trouble = self.trouble.lock().expect("trouble lock");
        match trouble.update(now, readings, limits, sustain) {
            Transition::Raised => self.face.raise(FACE_RELEVANCE),
            Transition::Cleared => self.face.clear(),
            Transition::Unchanged => {}
        }
    }

    /// The shown trouble and how long it has lasted.
    fn active(&self, now: Instant) -> Option<(Kind, Duration)> {
        let trouble = self.trouble.lock().expect("trouble lock");
        Some((trouble.active()?, trouble.since(now)?))
    }

    /// Nothing measures now: a trouble that was shown goes, and the next one starts from zero.
    fn reset(&self) {
        let mut trouble = self.trouble.lock().expect("trouble lock");
        if trouble.active().is_some() {
            self.face.clear();
        }
        *trouble = Trouble::default();
    }

    fn set_paused(&self, on: bool) {
        self.pause.send_replace(on);
        if on {
            self.reset();
        }
    }
}

/// Clears a trouble when the summary stops, unless the watch keeps measuring.
struct StopGuard(Arc<Shared>);

impl Drop for StopGuard {
    fn drop(&mut self) {
        if !self.0.watching.load(Ordering::SeqCst) {
            self.0.reset();
        }
    }
}

fn readings_of(s: &Sample) -> Readings {
    Readings {
        cpu: s.cpu,
        mem: s.mem.as_ref().map(mem_pct),
        temp: s.temp.as_ref().map(|t| t.c),
    }
}

fn mem_pct(m: &Memory) -> f64 {
    100.0 * m.used as f64 / m.total as f64
}

/// Whether a level above normal is shown: then the process list is worth reading for a culprit.
fn is_hot(cfg: &Cfg, s: &Sample) -> bool {
    s.cpu.is_some_and(|c| cfg.limits.cpu.level(c) != "normal")
        || s.mem
            .as_ref()
            .is_some_and(|m| cfg.limits.mem.level(mem_pct(m)) != "normal")
}

/// The process the trouble names: the hottest by CPU or memory. None when the kind has no process (temperature),
/// or when no CPU delta exists yet.
fn culprit(kind: Kind, rows: &[Row]) -> Option<doc::Culprit> {
    if kind == Kind::Temp || rows.is_empty() {
        return None;
    }
    if kind == Kind::Cpu && rows.iter().all(|r| r.cpu.is_none()) {
        return None;
    }
    let by_mem = kind == Kind::Mem;
    procs::hottest(rows, by_mem).map(|r| doc::Culprit {
        pid: r.pid,
        name: r.name.clone(),
        cpu: r.cpu,
        mem_pct: r.mem_pct,
    })
}

/// `mod.sysmon`: samples while subscribed, feeds the trouble, publishes the summary.
async fn summary(shared: Arc<Shared>, publish: Publish, mut settings: Settings) {
    let _stop = StopGuard(shared.clone());
    let mut pause = shared.pause.subscribe();
    let mut sampler = Sampler::new(shared.roots.clone(), "auto");
    let mut hist = History::default();
    let mut shown: Option<Value> = None;
    let mut hot = false;
    loop {
        if *pause.borrow_and_update() {
            if let Some(doc) = shown.as_mut() {
                doc["paused"] = json!(true);
                doc["stale"] = json!(true);
                publish(doc.clone());
            }
            if pause.changed().await.is_err() {
                return;
            }
            // A resumed sampler starts from a fresh baseline, not from the reads before the pause.
            sampler = Sampler::new(shared.roots.clone(), "auto");
            continue;
        }
        let cfg = Cfg::of(&settings);
        sampler.set_sensor(&cfg.sensor);
        let now = Instant::now();
        let trouble_now = shared.active(now);
        let s = sampler.sample(now, hot || trouble_now.is_some());
        shared.feed(now, readings_of(&s), &cfg.limits, cfg.sustain);
        let trouble = shared.active(now).map(|(kind, since)| TroubleDoc {
            kind,
            since,
            culprit: s.procs.as_deref().and_then(|rows| culprit(kind, rows)),
        });
        hot = is_hot(&cfg, &s);
        hist.push(
            s.cpu,
            s.mem.as_ref().map(mem_pct),
            s.temp.as_ref().map(|t| t.c),
        );
        let view = doc::View {
            cfg: &cfg,
            paused: false,
            watching: shared.watching.load(Ordering::SeqCst),
            trouble,
        };
        let value = doc::summary(&s, &hist, &view);
        shown = Some(value.clone());
        publish(value);

        // The first CPU percentage waits for a second read; afterwards the configured interval.
        let wait = if s.baseline && s.available {
            BASELINE
        } else {
            cfg.interval
        };
        tokio::select! {
            _ = tokio::time::sleep(wait) => {}
            _ = pause.changed() => {}
            changed = settings.changed() => {
                if !changed {
                    return;
                }
            }
        }
    }
}

fn publish_procs(
    shared: &Shared,
    publish: &Publish,
    scan: &[Row],
    by_mem: bool,
    paused: bool,
) -> Value {
    let rows = procs::top(&shared.roots, scan.to_vec(), by_mem);
    let value = doc::procs(
        &rows,
        by_mem,
        scan.len(),
        paused,
        shared.roots.uid,
        shared.self_pid,
    );
    publish(value.clone());
    value
}

/// `mod.sysmon.procs`: the process scan while subscribed. A sort change re-orders the last scan at once.
async fn procs_service(shared: Arc<Shared>, publish: Publish, mut settings: Settings) {
    let mut pause = shared.pause.subscribe();
    let mut sort = shared.sort.subscribe();
    let mut sampler = Sampler::new(shared.roots.clone(), "auto");
    let mut scan: Vec<Row> = Vec::new();
    let mut shown: Option<Value> = None;
    loop {
        if *pause.borrow_and_update() {
            if let Some(doc) = shown.as_mut() {
                doc["paused"] = json!(true);
                doc["stale"] = json!(true);
                publish(doc.clone());
            }
            if pause.changed().await.is_err() {
                return;
            }
            sampler = Sampler::new(shared.roots.clone(), "auto");
            continue;
        }
        let cfg = Cfg::of(&settings);
        let s = sampler.sample(Instant::now(), true);
        if let Some(rows) = s.procs {
            scan = rows;
        }
        let by_mem = *sort.borrow_and_update();
        shown = Some(publish_procs(&shared, &publish, &scan, by_mem, false));
        let wait = if s.baseline && s.available {
            BASELINE
        } else {
            cfg.interval
        };
        let deadline = tokio::time::Instant::now() + wait;
        loop {
            tokio::select! {
                _ = tokio::time::sleep_until(deadline) => break,
                _ = pause.changed() => break,
                _ = sort.changed() => {
                    let by_mem = *sort.borrow_and_update();
                    shown = Some(publish_procs(&shared, &publish, &scan, by_mem, false));
                }
                changed = settings.changed() => {
                    if !changed {
                        return;
                    }
                    break;
                }
            }
        }
    }
}

/// The watch: the trouble is measured while the opt-in `watch` setting is on and the mod is not paused,
/// every [`WATCH_EVERY`], with nothing published. Off, it waits on the settings and costs nothing.
async fn watch(shared: Arc<Shared>, mut settings: Settings) {
    let mut pause = shared.pause.subscribe();
    let mut sampler = Sampler::new(shared.roots.clone(), "auto");
    loop {
        let cfg = Cfg::of(&settings);
        let on = cfg.watch && !*pause.borrow_and_update();
        shared.watching.store(on, Ordering::SeqCst);
        if !on {
            tokio::select! {
                changed = settings.changed() => {
                    if !changed {
                        return;
                    }
                }
                _ = pause.changed() => {}
            }
            continue;
        }
        sampler.set_sensor(&cfg.sensor);
        let now = Instant::now();
        let s = sampler.sample(now, false);
        shared.feed(now, readings_of(&s), &cfg.limits, cfg.sustain);
        tokio::select! {
            _ = tokio::time::sleep(WATCH_EVERY) => {}
            _ = pause.changed() => {}
            changed = settings.changed() => {
                if !changed {
                    shared.watching.store(false, Ordering::SeqCst);
                    return;
                }
            }
        }
    }
}

fn pause_action(shared: &Shared, args: &Value) -> Result<Option<Value>, ActionError> {
    let on = args
        .get("paused")
        .and_then(Value::as_bool)
        .unwrap_or_else(|| !*shared.pause.borrow());
    shared.set_paused(on);
    Ok(Some(json!({"paused": on})))
}

fn sort_action(shared: &Shared, args: &Value) -> Result<Option<Value>, ActionError> {
    let by_mem = match args.get("by").and_then(Value::as_str) {
        Some("mem") => true,
        Some("cpu") => false,
        _ => return Err(ActionError::Invalid("sysmon.error.invalid".into())),
    };
    shared.sort.send_replace(by_mem);
    Ok(Some(json!({"by": if by_mem { "mem" } else { "cpu" }})))
}

/// End or Force quit. Refused unless the process is still the one the list showed (same pid and start
/// time, so a reused pid is never signalled), belongs to the daemon's user, and is not pid 1 or the daemon.
pub(crate) fn end_process(
    roots: &Roots,
    signaller: &dyn Signaller,
    args: &Value,
    sig: Sig,
    self_pid: u32,
) -> Result<Option<Value>, ActionError> {
    let invalid = || ActionError::Invalid("sysmon.error.no_process".into());
    let pid = args
        .get("pid")
        .and_then(Value::as_i64)
        .and_then(|p| i32::try_from(p).ok())
        .ok_or_else(invalid)?;
    let start = args
        .get("start")
        .and_then(Value::as_u64)
        .ok_or_else(invalid)?;
    if pid <= 1 || i64::from(pid) == i64::from(self_pid) {
        return Err(ActionError::Unavailable("sysmon.error.protected".into()));
    }
    let stat = procs::read_stat(roots, pid)
        .ok_or_else(|| ActionError::Unavailable("sysmon.error.gone".into()))?;
    if stat.start != start {
        return Err(ActionError::Unavailable("sysmon.error.changed".into()));
    }
    if procs::read_uid(roots, pid) != Some(roots.uid) {
        return Err(ActionError::Unavailable("sysmon.error.not_yours".into()));
    }
    match signaller.send(pid, sig) {
        Ok(()) => Ok(Some(json!({"pid": pid, "signal": sig.name()}))),
        Err(e) => Err(match e.kind() {
            std::io::ErrorKind::PermissionDenied => {
                ActionError::Unavailable("sysmon.error.not_yours".into())
            }
            std::io::ErrorKind::NotFound => ActionError::Unavailable("sysmon.error.gone".into()),
            _ => ActionError::Internal("sysmon.error.failed".into()),
        }),
    }
}

impl NativeMod for Sysmon {
    fn id(&self) -> &'static str {
        "sysmon"
    }

    fn enable(&self, ctx: &mut ModCtx) -> Result<(), ModError> {
        let runtime = self
            .runtime
            .clone()
            .or_else(|| Handle::try_current().ok())
            .ok_or_else(|| ModError::Failed("the daemon runtime is not running".into()))?;
        let face = ctx.face(
            "sysmon",
            FaceSpec {
                transient: false,
                ttl_s: 0,
            },
        )?;
        let shared = Arc::new(Shared {
            roots: self.roots.clone(),
            face,
            pause: watch::channel(false).0,
            sort: watch::channel(false).0,
            watching: AtomicBool::new(false),
            trouble: Mutex::default(),
            self_pid: self.self_pid,
        });
        let s = shared.clone();
        ctx.service("sysmon", doc::loading(), move |publish, settings| {
            summary(s.clone(), publish, settings)
        })?;
        let s = shared.clone();
        ctx.service(
            "sysmon.procs",
            doc::loading_procs(),
            move |publish, settings| procs_service(s.clone(), publish, settings),
        )?;
        let s = shared.clone();
        ctx.action("sysmon.pause", "action.sysmon.pause", move |args| {
            let r = pause_action(&s, &args);
            async move { r }
        })?;
        let s = shared.clone();
        ctx.action("sysmon.sort", "action.sysmon.sort", move |args| {
            let r = sort_action(&s, &args);
            async move { r }
        })?;
        for (id, label, sig) in [
            (
                "sysmon.process.term",
                "action.sysmon.process.term",
                Sig::Term,
            ),
            (
                "sysmon.process.kill",
                "action.sysmon.process.kill",
                Sig::Kill,
            ),
        ] {
            let (roots, signaller, self_pid) =
                (self.roots.clone(), self.signaller.clone(), self.self_pid);
            ctx.action(id, label, move |args| {
                let r = end_process(&roots, signaller.as_ref(), &args, sig, self_pid);
                async move { r }
            })?;
        }
        // Lives while the mod does: the settings feed ends with the enable, and so does the watch.
        runtime.spawn(watch(shared, ctx.settings().clone()));
        Ok(())
    }
}
