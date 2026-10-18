//! The mod's daemon side (K26, K28): two documents, the watch, the trouble face and the actions.
//!
//! Ma (docs/ux/sysmon.md, "Fit"): `mod.sysmon` samples only while something subscribes to it (bar, panel
//! or the face), `mod.sysmon.procs` only while the panel lists processes, and the watch task only while
//! the opt-in `watch` setting is on, every 10 s. Pause stops all three, whether the panel paused them or
//! the `paused` setting does. A stopped summary clears a trouble that nothing else keeps alive, so the face
//! never shows a value that is no longer measured.

use crate::doc::{self, History, TroubleDoc};
use crate::host::{self, Host};
use crate::launch::{self, Launcher, Spawn};
use crate::procs::{self, Row};
use crate::roots::Roots;
use crate::sampler::{Memory, Sample, Sampler};
use crate::thermal;
use crate::trouble::{Kind, Limits, Readings, Transition, Trouble};
use kurashi_mod_api::{
    ActionError, FaceHandle, FaceSpec, JobCtx, ModCtx, ModError, NativeMod, Publish, Settings,
};
use serde_json::{Value, json};
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Arc, Mutex};
use std::time::Duration;
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
/// A control value (Tctl) runs above the die on some Ryzen parts, and its own limit is 95 °C: its levels
/// are never below these, whatever the settings say (I29). A level the user turned off (0) stays off.
const TCTL_ACTIVITY_FLOOR: f64 = 75.0;
const TCTL_CRITICAL_FLOOR: f64 = 95.0;

/// The settings in effect (`mods.sysmon.*`, the defaults of mod.toml). Clamped to the ranges the
/// manifest declares, so a value the config holds outside them still means something defined.
#[derive(Clone, Debug, PartialEq)]
pub struct Cfg {
    pub interval: Duration,
    /// The stats the bar shows, in its order.
    pub bar: Vec<&'static str>,
    /// The bar draws a 30-sample sparkline beside the figures.
    pub bar_spark: bool,
    pub sensor: String,
    pub watch: bool,
    pub sustain: Duration,
    pub limits: Limits,
    /// Sampling is paused by the setting (the panel's Pause cannot resume it).
    pub paused: bool,
    /// The terminal "Open in btop" starts: one of [`launch::TERMINALS`].
    pub terminal: String,
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
        // The stats the bar shows (I26): a pick list, shown in the order the user picked, each once.
        const STATS: [&str; 4] = ["cpu", "mem", "temp", "load"];
        let shown = s
            .get("show")
            .and_then(|v| v.as_array().cloned())
            .unwrap_or_else(|| vec![json!("cpu"), json!("mem")]);
        let mut bar: Vec<&'static str> = Vec::new();
        for stat in shown.iter().filter_map(Value::as_str) {
            if let Some(known) = STATS.into_iter().find(|s| *s == stat) {
                if !bar.contains(&known) {
                    bar.push(known);
                }
            }
        }
        let text = |key: &str, default: &str| {
            s.get(key)
                .and_then(|v| v.as_str().map(|t| t.trim().to_string()))
                .filter(|t| !t.is_empty())
                .unwrap_or_else(|| default.into())
        };
        let terminal = text("terminal", "foot");
        Self {
            interval: Duration::from_secs(int("interval", 2, 1, 60) as u64),
            bar,
            bar_spark: flag("bar_spark", false),
            sensor: text("temp_sensor", "auto"),
            watch: flag("watch", false),
            sustain: Duration::from_secs(int("sustain", 30, 5, 600) as u64),
            limits: Limits {
                cpu: limit("cpu", 50, 90, 100),
                mem: limit("mem", 60, 90, 100),
                temp: limit("temp", 60, 85, 120),
            },
            paused: flag("paused", false),
            terminal,
        }
    }

    /// The thresholds a reading of `kind` is judged by (I29): the settings, with the control-value floors.
    pub fn limits_for(&self, kind: Option<thermal::Kind>) -> Limits {
        let mut l = self.limits;
        if kind == Some(thermal::Kind::Control) {
            if l.temp.activity > 0.0 {
                l.temp.activity = l.temp.activity.max(TCTL_ACTIVITY_FLOOR);
            }
            if l.temp.critical > 0.0 {
                l.temp.critical = l.temp.critical.max(TCTL_CRITICAL_FLOOR);
            }
        }
        l
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
    launcher: Arc<dyn Launcher>,
    self_pid: u32,
}

impl Sysmon {
    /// The live system, signalled through kill(2), terminals started from PATH.
    pub fn new() -> Self {
        Self::with(Roots::system(), Arc::new(Kernel))
    }

    pub fn with(roots: Roots, signaller: Arc<dyn Signaller>) -> Self {
        Self::with_launcher(roots, signaller, Arc::new(Spawn))
    }

    /// The seams the tests replace: where the files are, how a signal is sent, how a terminal is started.
    pub fn with_launcher(
        roots: Roots,
        signaller: Arc<dyn Signaller>,
        launcher: Arc<dyn Launcher>,
    ) -> Self {
        Self {
            roots,
            signaller,
            launcher,
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
    /// Whether the figures are the host's or the hypervisor's (read once).
    host: Host,
    face: FaceHandle,
    /// The panel's own pause. The `paused` setting is the other way to pause (see [`paused_by`]).
    pause: watch::Sender<bool>,
    /// The process list's sort: true = by memory, false = by CPU.
    sort: watch::Sender<bool>,
    /// The panel shows its action menu: set by the bar's click, cleared when the panel closes.
    menu: watch::Sender<bool>,
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

/// Why nothing is sampled now: the setting (only Settings resumes it) wins over the panel's Pause, so the
/// view can say which one to change. None while sampling is on.
fn paused_by(runtime: bool, cfg: &Cfg) -> Option<&'static str> {
    if cfg.paused {
        Some("settings")
    } else if runtime {
        Some("panel")
    } else {
        None
    }
}

/// A paused service's document: the last values marked stale and paused, or the empty document when
/// nothing was sampled yet, so the view says why there are no new figures.
fn stale_doc(shown: &mut Option<Value>, publish: &Publish, by: &str, empty: fn() -> Value) {
    let doc = shown.get_or_insert_with(empty);
    doc["paused"] = json!(true);
    doc["stale"] = json!(true);
    doc["paused_by"] = json!(by);
    publish(doc.clone());
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
    let mut menu = shared.menu.subscribe();
    let mut sampler = Sampler::new(shared.roots.clone(), "auto");
    let mut hist = History::default();
    let mut shown: Option<Value> = None;
    let mut hot = false;
    loop {
        let cfg = Cfg::of(&settings);
        let runtime = *pause.borrow_and_update();
        if let Some(by) = paused_by(runtime, &cfg) {
            shared.reset();
            // The stale values, marked paused, with the menu flag as it is: the menu opens while paused too
            // (Resume is in it), so a flag change is published from these values without sampling.
            let doc = shown.get_or_insert_with(doc::loading);
            doc["paused"] = json!(true);
            doc["stale"] = json!(true);
            doc["paused_by"] = json!(by);
            doc["menu"] = json!(*menu.borrow());
            publish(doc.clone());
            tokio::select! {
                changed = pause.changed() => {
                    if changed.is_err() {
                        return;
                    }
                }
                changed = settings.changed() => {
                    if !changed {
                        return;
                    }
                }
                changed = menu.changed() => {
                    if changed.is_err() {
                        return;
                    }
                    if let Some(doc) = shown.as_mut() {
                        doc["menu"] = json!(*menu.borrow());
                        publish(doc.clone());
                    }
                    continue;
                }
            }
            // A resumed sampler starts from a fresh baseline, not from the reads before the pause.
            sampler = Sampler::new(shared.roots.clone(), "auto");
            continue;
        }
        sampler.set_sensor(&cfg.sensor);
        let now = Instant::now();
        let trouble_now = shared.active(now);
        let s = sampler.sample(now, hot || trouble_now.is_some());
        let limits = cfg.limits_for(s.temp.as_ref().map(|t| t.kind));
        shared.feed(now, readings_of(&s), &limits, cfg.sustain);
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
            limits,
            paused: false,
            watching: shared.watching.load(Ordering::SeqCst),
            trouble,
            host: shared.host,
            menu: *menu.borrow(),
        };
        let value = doc::summary(&s, &hist, &view);
        shown = Some(value.clone());
        publish(value);

        // The first CPU percentage waits for a second read; afterwards the configured interval. A change of
        // the menu flag is shown at once from the last values (a click must not wait for the next sample).
        let wait = if s.baseline && s.available {
            BASELINE
        } else {
            cfg.interval
        };
        let deadline = tokio::time::Instant::now() + wait;
        loop {
            tokio::select! {
                _ = tokio::time::sleep_until(deadline) => break,
                changed = pause.changed() => {
                    if changed.is_err() {
                        return;
                    }
                    break;
                }
                changed = settings.changed() => {
                    if !changed {
                        return;
                    }
                    break;
                }
                changed = menu.changed() => {
                    if changed.is_err() {
                        return;
                    }
                    if let Some(doc) = shown.as_mut() {
                        doc["menu"] = json!(*menu.borrow());
                        publish(doc.clone());
                    }
                }
            }
        }
    }
}

fn publish_procs(shared: &Shared, publish: &Publish, scan: &[Row], by_mem: bool) -> Value {
    let rows = procs::top(&shared.roots, scan.to_vec(), by_mem);
    let value = doc::procs(
        &rows,
        by_mem,
        scan.len(),
        false,
        shared.roots.uid,
        shared.self_pid,
        procs::hottest(scan, false),
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
        let cfg = Cfg::of(&settings);
        let runtime = *pause.borrow_and_update();
        if let Some(by) = paused_by(runtime, &cfg) {
            stale_doc(&mut shown, &publish, by, doc::loading_procs);
            tokio::select! {
                changed = pause.changed() => {
                    if changed.is_err() {
                        return;
                    }
                }
                changed = settings.changed() => {
                    if !changed {
                        return;
                    }
                }
            }
            sampler = Sampler::new(shared.roots.clone(), "auto");
            continue;
        }
        let s = sampler.sample(Instant::now(), true);
        if let Some(rows) = s.procs {
            scan = rows;
        }
        let by_mem = *sort.borrow_and_update();
        shown = Some(publish_procs(&shared, &publish, &scan, by_mem));
        let wait = if s.baseline && s.available {
            BASELINE
        } else {
            cfg.interval
        };
        let deadline = tokio::time::Instant::now() + wait;
        loop {
            tokio::select! {
                _ = tokio::time::sleep_until(deadline) => break,
                changed = pause.changed() => {
                    if changed.is_err() {
                        return;
                    }
                    break;
                }
                changed = sort.changed() => {
                    if changed.is_err() {
                        return;
                    }
                    let by_mem = *sort.borrow_and_update();
                    shown = Some(publish_procs(&shared, &publish, &scan, by_mem));
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

/// The watch: the trouble is measured while the opt-in `watch` setting is on and sampling is not paused,
/// every [`WATCH_EVERY`], with nothing published. Off, it waits on the settings and costs nothing. Its job
/// has work only while it measures, so a paused watch is not reported as running (I48).
async fn watch(shared: Arc<Shared>, job: JobCtx) {
    let mut settings = job.settings().clone();
    let mut pause = shared.pause.subscribe();
    let mut sampler = Sampler::new(shared.roots.clone(), "auto");
    loop {
        let cfg = Cfg::of(&settings);
        let runtime = *pause.borrow_and_update();
        let by = paused_by(runtime, &cfg);
        let on = cfg.watch && by.is_none();
        shared.watching.store(on, Ordering::SeqCst);
        job.set_active(on);
        if !on {
            // A paused watch drops its trouble too: a face is never raised by a value no longer measured.
            if by.is_some() {
                shared.reset();
            }
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
        let limits = cfg.limits_for(s.temp.as_ref().map(|t| t.kind));
        shared.feed(now, readings_of(&s), &limits, cfg.sustain);
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

fn pause_action(
    shared: &Shared,
    settings: &Settings,
    args: &Value,
) -> Result<Option<Value>, ActionError> {
    if Cfg::of(settings).paused {
        // The setting pauses, and only Settings resumes: the panel says so, and the daemon refuses.
        return Err(ActionError::Unavailable(
            "sysmon.error.paused_in_settings".into(),
        ));
    }
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

/// The bar's click: the panel's action menu on (right click) or off (left click, and when the panel closes).
fn menu_action(shared: &Shared, args: &Value) -> Result<Option<Value>, ActionError> {
    let on = args
        .get("on")
        .and_then(Value::as_bool)
        .ok_or_else(|| ActionError::Invalid("sysmon.error.flag".into()))?;
    shared.menu.send_replace(on);
    Ok(Some(json!({"menu": on})))
}

/// "Open in btop": the terminal from the setting, running btop. A terminal outside the list, or a program that
/// is not on PATH, is refused with its reason; nothing is started then.
pub(crate) fn open_btop(
    launcher: &dyn Launcher,
    terminal: &str,
) -> Result<Option<Value>, ActionError> {
    let Some((name, args)) = launch::TERMINALS.iter().find(|(name, _)| *name == terminal) else {
        return Err(ActionError::Invalid("sysmon.error.terminal".into()));
    };
    if !launcher.on_path("btop") {
        return Err(ActionError::Unavailable("sysmon.error.no_btop".into()));
    }
    if !launcher.on_path(name) {
        return Err(ActionError::Unavailable("sysmon.error.no_terminal".into()));
    }
    launcher
        .spawn(name, args)
        .map_err(|_| ActionError::Internal("sysmon.error.failed".into()))?;
    Ok(Some(json!({"terminal": name})))
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
        let face = ctx.face(
            "sysmon",
            FaceSpec {
                transient: false,
                ttl_s: 0,
            },
        )?;
        let shared = Arc::new(Shared {
            roots: self.roots.clone(),
            host: host::detect(&self.roots),
            face,
            pause: watch::channel(false).0,
            sort: watch::channel(false).0,
            menu: watch::channel(false).0,
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
        let settings = ctx.settings().clone();
        ctx.action("sysmon.pause", "action.sysmon.pause", move |args| {
            let r = pause_action(&s, &settings, &args);
            async move { r }
        })?;
        let s = shared.clone();
        ctx.action("sysmon.menu", "action.sysmon.menu", move |args| {
            let r = menu_action(&s, &args);
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
        let launcher = self.launcher.clone();
        let settings = ctx.settings().clone();
        ctx.action(
            "sysmon.open_btop",
            "action.sysmon.open_btop",
            move |_args| {
                let r = open_btop(launcher.as_ref(), &Cfg::of(&settings).terminal);
                async move { r }
            },
        )?;
        // The watch samples while its setting is on (I23): the daemon runs it then, and cancels it on
        // disable. Pause stops it too, inside the task.
        let s = shared.clone();
        ctx.background("watch", "mods.running.watch", "watch", move |job| {
            let s = s.clone();
            async move { watch(s, job).await }
        })?;
        Ok(())
    }
}
