//! The mod through the registrations the daemon applies (K26): nothing samples without a subscriber, the
//! watch fires every 10 s and only while on, the face is raised and cleared with the trouble, pause stops
//! everything, and the process actions refuse what they must. Time is tokio's paused clock; the signaller
//! records instead of signalling, so no real process is touched.

use crate::roots::Roots;
use crate::sysmon::{Cfg, Sig, Signaller, Sysmon, end_process};
use kurashi_mod_api::{
    ActionError, ActionFn, FaceUpdate, Hooks, JobCtx, ModCtx, NativeMod, Publish, Registration,
    ServiceFn, Settings, Values,
};
use serde_json::{Value, json};
use std::io;
use std::path::Path;
use std::sync::{Arc, Mutex};
use std::time::Duration;
use tokio::sync::watch;
use tokio::task::JoinHandle;
use tokio::time::Instant;

/// What the manifest of `mods/sysmon` provides.
const PROVIDES: [&str; 7] = [
    "service:sysmon",
    "service:sysmon.procs",
    "widget:sysmon",
    "panel:sysmon",
    "island-face:sysmon",
    "action:sysmon.*",
    "job:watch",
];

#[derive(Default)]
struct Rec {
    calls: Mutex<Vec<String>>,
}

impl Rec {
    fn calls(&self) -> Vec<String> {
        self.calls.lock().unwrap().clone()
    }
}

impl Hooks for Rec {
    fn face(&self, face: &str, update: FaceUpdate) {
        let what = match update {
            FaceUpdate::Raise { relevance, .. } => format!("raise {relevance}"),
            FaceUpdate::Clear => "clear".to_string(),
        };
        self.calls.lock().unwrap().push(format!("{face} {what}"));
    }

    fn choices_changed(&self, _source: &str) {}
}

/// One enable of the mod: its registrations, the settings feed and what its documents published.
struct Enabled {
    summary: ServiceFn,
    procs: ServiceFn,
    actions: Vec<(String, ActionFn)>,
    settings: watch::Sender<Values>,
    rec: Arc<Rec>,
    summary_docs: Arc<Mutex<Vec<Value>>>,
    procs_docs: Arc<Mutex<Vec<Value>>>,
}

/// Calls one of the mod's actions the way the hub does.
async fn act(e: &Enabled, id: &str, args: Value) -> Result<Option<Value>, ActionError> {
    let handler: &ActionFn = &e.actions.iter().find(|(a, _)| a == id).unwrap().1;
    (handler.as_ref())(args).await
}

fn enable(sys: &Sysmon, values: Values) -> Enabled {
    let (settings, rx) = watch::channel(values);
    let rec = Arc::new(Rec::default());
    let provides: Vec<String> = PROVIDES.iter().map(|p| p.to_string()).collect();
    let mut ctx = ModCtx::new(&provides, Settings::new(rx.clone()), rec.clone());
    sys.enable(&mut ctx).unwrap();
    // The daemon starts the watch job while its setting wants it. The harness starts it on every
    // enable instead: the watch idles while `watch` is off, and the watch tests check that it does.
    for job in ctx.take_jobs() {
        tokio::spawn((job.run)(JobCtx::new(Settings::new(rx.clone()))));
    }
    let mut summary = None;
    let mut procs = None;
    let mut actions = Vec::new();
    for r in ctx.finish().unwrap() {
        match r {
            Registration::Service { id, run, .. } if id == "sysmon" => summary = Some(run),
            Registration::Service { id, run, .. } if id == "sysmon.procs" => procs = Some(run),
            Registration::Action { id, handler, .. } => actions.push((id, handler)),
            _ => {}
        }
    }
    Enabled {
        summary: summary.expect("summary service"),
        procs: procs.expect("procs service"),
        actions,
        settings,
        rec,
        summary_docs: Arc::default(),
        procs_docs: Arc::default(),
    }
}

/// Runs a service the way the hub does while it has a subscriber; aborting it is the last unsubscribe.
fn subscribe(
    run: &ServiceFn,
    docs: &Arc<Mutex<Vec<Value>>>,
    settings: &watch::Sender<Values>,
) -> JoinHandle<()> {
    let docs = docs.clone();
    let publish: Publish = Arc::new(move |v| docs.lock().unwrap().push(v));
    tokio::spawn(run(publish, Settings::new(settings.subscribe())))
}

fn values(pairs: &[(&str, Value)]) -> Values {
    pairs
        .iter()
        .map(|(k, v)| (k.to_string(), v.clone()))
        .collect()
}

fn write(path: &Path, text: &str) {
    std::fs::create_dir_all(path.parent().unwrap()).unwrap();
    std::fs::write(path, text).unwrap();
}

/// A fixture machine: `/proc` with the files the summary reads, uid 1000 for the daemon.
struct Machine {
    _dir: tempfile::TempDir,
    roots: Roots,
}

fn machine() -> Machine {
    let dir = tempfile::tempdir().unwrap();
    let proc = dir.path().join("proc");
    write(
        &proc.join("stat"),
        "cpu 0 0 0 0 0 0 0 0\ncpu0 0 0 0 0 0 0 0 0\n",
    );
    write(
        &proc.join("meminfo"),
        "MemTotal: 1000 kB\nMemAvailable: 400 kB\n",
    );
    write(&proc.join("loadavg"), "0.10 0.20 0.30 1/100 42\n");
    let roots = Roots::new(proc.clone(), dir.path().join("sys"), 1000).traced();
    Machine { _dir: dir, roots }
}

/// Writes one process: `/proc/<pid>/stat` with the given start time, and `status` with the owner.
fn process(roots: &Roots, pid: i32, start: u64, uid: u32) {
    let dir = roots.proc.join(pid.to_string());
    let stat = format!(
        "{pid} (proc{pid}) S 1 {pid} {pid} 0 -1 4194560 0 0 0 0 10 5 0 0 20 0 1 0 {start} 1000 50\n"
    );
    write(&dir.join("stat"), &stat);
    write(
        &dir.join("status"),
        &format!("Name:\tx\nUid:\t{uid}\t{uid}\t{uid}\t{uid}\n"),
    );
}

/// How many times `/proc/stat` was read.
fn stat_reads(roots: &Roots) -> usize {
    roots
        .trace()
        .iter()
        .filter(|p| **p == roots.proc.join("stat"))
        .count()
}

/// Rewrites the CPU counters as the paused clock advances: 100 % busy for `load_until` seconds, then idle.
fn load_writer(roots: Roots, start: Instant, load_until: u64) -> JoinHandle<()> {
    tokio::spawn(async move {
        loop {
            let t = start.elapsed().as_secs();
            let (busy, idle) = if t < load_until {
                (100 * t, 0)
            } else {
                (100 * load_until, 100 * (t - load_until))
            };
            write(
                &roots.proc.join("stat"),
                &format!("cpu {busy} 0 0 {idle} 0 0 0 0\ncpu0 {busy} 0 0 {idle} 0 0 0 0\n"),
            );
            tokio::time::sleep(Duration::from_secs(1)).await;
        }
    })
}

#[test]
fn settings_default_to_the_manifest_and_clamp_out_of_range_values() {
    let (_, rx) = watch::channel(Values::new());
    let d = Cfg::of(&Settings::new(rx));
    assert_eq!(d.interval, Duration::from_secs(2));
    assert_eq!(d.bar, vec!["cpu", "mem"]);
    assert_eq!(d.sensor, "auto");
    assert!(!d.watch);
    assert_eq!(d.sustain, Duration::from_secs(30));
    assert_eq!(d.limits.cpu.critical, 90.0);
    assert_eq!(d.limits.temp.critical, 85.0);

    let (_, rx) = watch::channel(values(&[
        ("interval", json!(500)),
        ("show", json!(["cpu", "mem", "temp"])),
        ("temp_sensor", json!("  ")),
        ("cpu_critical", json!(-4)),
        ("sustain", json!(1)),
    ]));
    let c = Cfg::of(&Settings::new(rx));
    assert_eq!(c.interval, Duration::from_secs(60));
    assert_eq!(c.bar, vec!["cpu", "mem", "temp"]);
    assert_eq!(c.sensor, "auto", "a blank sensor name is auto");
    assert_eq!(
        c.limits.cpu.critical, 0.0,
        "0 disables, negatives clamp to it"
    );
    assert_eq!(c.sustain, Duration::from_secs(5));
}

#[tokio::test(start_paused = true)]
async fn nothing_is_read_until_a_view_subscribes_and_nothing_after_the_last_unsubscribe() {
    let m = machine();
    let sys = Sysmon::with(m.roots.clone(), Arc::new(Sent::default()));
    let e = enable(&sys, Values::new());
    tokio::time::sleep(Duration::from_secs(60)).await;
    assert_eq!(stat_reads(&m.roots), 0, "enabling alone samples nothing");

    let task = subscribe(&e.summary, &e.summary_docs, &e.settings);
    tokio::time::sleep(Duration::from_secs(10)).await;
    let reads = stat_reads(&m.roots);
    // Baseline at 0 s, the first percentage at 0.25 s, then every 2 s.
    assert!((5..=7).contains(&reads), "{reads}");
    let docs = e.summary_docs.lock().unwrap().len();
    assert!(docs >= 5, "{docs}");

    task.abort();
    tokio::task::yield_now().await;
    tokio::time::sleep(Duration::from_secs(60)).await;
    assert_eq!(
        stat_reads(&m.roots),
        reads,
        "no sampling after the last unsubscribe"
    );
    assert_eq!(e.summary_docs.lock().unwrap().len(), docs);
}

#[tokio::test(start_paused = true)]
async fn the_summary_document_carries_cpu_from_the_second_read_and_the_bar_setting() {
    let m = machine();
    let sys = Sysmon::with(m.roots.clone(), Arc::new(Sent::default()));
    let e = enable(&sys, Values::new());
    let writer = load_writer(m.roots.clone(), Instant::now(), 1000);
    let task = subscribe(&e.summary, &e.summary_docs, &e.settings);
    tokio::time::sleep(Duration::from_secs(4)).await;
    task.abort();
    writer.abort();
    let docs = e.summary_docs.lock().unwrap();
    let first = &docs[0];
    assert_eq!(first["available"], json!(true));
    assert!(
        first["cpu"].get("pct").is_none(),
        "no percentage on the first read"
    );
    let later = docs.last().unwrap();
    assert_eq!(later["cpu"]["pct"], json!(100.0));
    assert_eq!(later["cpu"]["level"], json!("critical"));
    assert_eq!(later["mem"]["pct"], json!(60.0));
    assert_eq!(later["bar"], json!(["cpu", "mem"]));
    assert!(later.get("temp").is_none(), "no sensor is omitted, never 0");
    assert_eq!(later["gpus"], json!([]));
    assert!(later.get("trouble").is_none(), "nothing sustained yet");
}

#[tokio::test(start_paused = true)]
async fn pause_stops_sampling_and_resume_starts_a_fresh_baseline() {
    let m = machine();
    let sys = Sysmon::with(m.roots.clone(), Arc::new(Sent::default()));
    let e = enable(&sys, Values::new());
    let task = subscribe(&e.summary, &e.summary_docs, &e.settings);
    tokio::time::sleep(Duration::from_secs(3)).await;
    let paused = act(&e, "sysmon.pause", json!({"paused": true})).await;
    assert_eq!(paused, Ok(Some(json!({"paused": true}))));
    tokio::task::yield_now().await;
    let reads = stat_reads(&m.roots);
    tokio::time::sleep(Duration::from_secs(30)).await;
    assert_eq!(stat_reads(&m.roots), reads, "paused: no read");
    let last = e.summary_docs.lock().unwrap().last().cloned().unwrap();
    assert_eq!(last["paused"], json!(true));
    assert_eq!(last["stale"], json!(true));

    act(&e, "sysmon.pause", json!({"paused": false}))
        .await
        .unwrap();
    tokio::time::sleep(Duration::from_secs(5)).await;
    assert!(stat_reads(&m.roots) > reads, "resumed: reads again");
    task.abort();
}

#[tokio::test(start_paused = true)]
async fn the_watch_raises_the_face_after_sustained_load_and_clears_it_after_recovery() {
    let m = machine();
    let sys = Sysmon::with(m.roots.clone(), Arc::new(Sent::default()));
    let e = enable(&sys, values(&[("watch", json!(true))]));
    let writer = load_writer(m.roots.clone(), Instant::now(), 60);
    // Load from 0 to 60 s, idle after: raised at 40 s (30 s over 90 %), cleared at 80 s (10 s under 85 %).
    tokio::time::sleep(Duration::from_secs(90)).await;
    writer.abort();
    assert_eq!(e.rec.calls(), vec!["sysmon raise 70", "sysmon clear"]);
    assert!(
        e.summary_docs.lock().unwrap().is_empty(),
        "the watch publishes nothing"
    );
}

#[tokio::test(start_paused = true)]
async fn the_watch_is_off_until_its_setting_is_on_and_then_samples_every_ten_seconds() {
    let m = machine();
    let sys = Sysmon::with(m.roots.clone(), Arc::new(Sent::default()));
    let e = enable(&sys, Values::new());
    tokio::time::sleep(Duration::from_secs(60)).await;
    assert_eq!(stat_reads(&m.roots), 0, "watch off: no read");
    e.settings.send_replace(values(&[("watch", json!(true))]));
    tokio::time::sleep(Duration::from_secs(35)).await;
    // Baseline on switch-on, then every 10 s: 0, 10, 20, 30 s.
    assert_eq!(stat_reads(&m.roots), 4);
    e.settings.send_replace(values(&[("watch", json!(false))]));
    tokio::time::sleep(Duration::from_secs(60)).await;
    assert_eq!(stat_reads(&m.roots), 4, "switched off: no read");
}

#[tokio::test(start_paused = true)]
async fn leaving_the_summary_clears_a_trouble_that_nothing_else_measures() {
    let m = machine();
    let sys = Sysmon::with(m.roots.clone(), Arc::new(Sent::default()));
    let e = enable(&sys, Values::new());
    let writer = load_writer(m.roots.clone(), Instant::now(), 10_000);
    let task = subscribe(&e.summary, &e.summary_docs, &e.settings);
    tokio::time::sleep(Duration::from_secs(45)).await;
    let shown = e.summary_docs.lock().unwrap().last().cloned().unwrap();
    assert_eq!(
        shown["trouble"]["kind"],
        json!("cpu"),
        "raised while subscribed"
    );
    task.abort();
    tokio::time::sleep(Duration::from_millis(10)).await;
    writer.abort();
    assert_eq!(e.rec.calls(), vec!["sysmon raise 70", "sysmon clear"]);
}

#[tokio::test(start_paused = true)]
async fn the_process_list_says_why_an_end_is_not_offered() {
    let m = machine();
    process(&m.roots, 500, 100, 1000);
    process(&m.roots, 600, 200, 0);
    let sys = Sysmon::with(m.roots.clone(), Arc::new(Sent::default()));
    let e = enable(&sys, Values::new());
    let task = subscribe(&e.procs, &e.procs_docs, &e.settings);
    tokio::time::sleep(Duration::from_millis(10)).await;
    task.abort();
    let docs = e.procs_docs.lock().unwrap();
    let rows = docs[0]["procs"].as_array().unwrap();
    let own = rows.iter().find(|r| r["pid"] == json!(500)).unwrap();
    let theirs = rows.iter().find(|r| r["pid"] == json!(600)).unwrap();
    assert_eq!(own["can_end"], json!(true));
    assert_eq!(theirs["can_end"], json!(false));
    assert_eq!(theirs["end_reason"], json!("sysmon.error.not_yours"));
}

/// Records what the daemon would signal.
#[derive(Default)]
struct Sent(Mutex<Vec<(i32, Sig)>>);

impl Signaller for Sent {
    fn send(&self, pid: i32, sig: Sig) -> io::Result<()> {
        self.0.lock().unwrap().push((pid, sig));
        Ok(())
    }
}

/// Refuses every signal the way the kernel would.
struct Refuse(io::ErrorKind);

impl Signaller for Refuse {
    fn send(&self, _pid: i32, _sig: Sig) -> io::Result<()> {
        Err(io::Error::from(self.0))
    }
}

const SELF: u32 = 9999;

fn end_args(pid: i64, start: u64) -> Value {
    json!({"pid": pid, "start": start})
}

#[test]
fn end_and_force_quit_signal_only_the_process_the_list_showed() {
    let m = machine();
    process(&m.roots, 4242, 777, 1000);
    let sent = Sent::default();
    let term = end_process(&m.roots, &sent, &end_args(4242, 777), Sig::Term, SELF);
    assert_eq!(term, Ok(Some(json!({"pid": 4242, "signal": "TERM"}))));
    end_process(&m.roots, &sent, &end_args(4242, 777), Sig::Kill, SELF).unwrap();
    assert_eq!(
        *sent.0.lock().unwrap(),
        vec![(4242, Sig::Term), (4242, Sig::Kill)]
    );

    // A reused pid has another start time: nothing is sent.
    let reused = end_process(&m.roots, &sent, &end_args(4242, 778), Sig::Term, SELF);
    assert_eq!(
        reused,
        Err(ActionError::Unavailable("sysmon.error.changed".into()))
    );
    // Pid 1 and the daemon itself are never offered.
    let init = end_process(&m.roots, &sent, &end_args(1, 777), Sig::Kill, SELF);
    assert_eq!(
        init,
        Err(ActionError::Unavailable("sysmon.error.protected".into()))
    );
    let itself = end_process(
        &m.roots,
        &sent,
        &end_args(SELF as i64, 777),
        Sig::Term,
        SELF,
    );
    assert_eq!(
        itself,
        Err(ActionError::Unavailable("sysmon.error.protected".into()))
    );
    // Gone since the list was read.
    let gone = end_process(&m.roots, &sent, &end_args(5555, 1), Sig::Term, SELF);
    assert_eq!(
        gone,
        Err(ActionError::Unavailable("sysmon.error.gone".into()))
    );
    // Another user's process: listed, not signalled.
    process(&m.roots, 4343, 888, 0);
    let theirs = end_process(&m.roots, &sent, &end_args(4343, 888), Sig::Kill, SELF);
    assert_eq!(
        theirs,
        Err(ActionError::Unavailable("sysmon.error.not_yours".into()))
    );
    // A request without a pid is invalid.
    let bare = end_process(&m.roots, &sent, &json!({}), Sig::Term, SELF);
    assert_eq!(
        bare,
        Err(ActionError::Invalid("sysmon.error.no_process".into()))
    );
    assert_eq!(
        sent.0.lock().unwrap().len(),
        2,
        "only the two own signals were sent"
    );
}

#[test]
fn the_kernels_refusals_map_to_the_reasons_the_list_shows() {
    let m = machine();
    process(&m.roots, 4242, 777, 1000);
    let args = end_args(4242, 777);
    let eperm = end_process(
        &m.roots,
        &Refuse(io::ErrorKind::PermissionDenied),
        &args,
        Sig::Term,
        SELF,
    );
    assert_eq!(
        eperm,
        Err(ActionError::Unavailable("sysmon.error.not_yours".into()))
    );
    let esrch = end_process(
        &m.roots,
        &Refuse(io::ErrorKind::NotFound),
        &args,
        Sig::Term,
        SELF,
    );
    assert_eq!(
        esrch,
        Err(ActionError::Unavailable("sysmon.error.gone".into()))
    );
    let other = end_process(
        &m.roots,
        &Refuse(io::ErrorKind::Other),
        &args,
        Sig::Kill,
        SELF,
    );
    assert_eq!(
        other,
        Err(ActionError::Internal("sysmon.error.failed".into()))
    );
}

/// Records what the daemon would start, and answers PATH lookups from a fixed list: no terminal is started.
#[derive(Default)]
struct Launch {
    path: Vec<&'static str>,
    started: Mutex<Vec<(String, Vec<String>)>>,
}

impl crate::launch::Launcher for Launch {
    fn on_path(&self, program: &str) -> bool {
        self.path.contains(&program)
    }

    fn spawn(&self, program: &str, args: &[&str]) -> io::Result<()> {
        let args = args.iter().map(|a| a.to_string()).collect();
        self.started
            .lock()
            .unwrap()
            .push((program.to_string(), args));
        Ok(())
    }
}

#[tokio::test(start_paused = true)]
async fn the_setting_pauses_and_only_the_setting_resumes() {
    let m = machine();
    let sys = Sysmon::with(m.roots.clone(), Arc::new(Sent::default()));
    let e = enable(&sys, values(&[("paused", json!(true))]));
    let task = subscribe(&e.summary, &e.summary_docs, &e.settings);
    tokio::time::sleep(Duration::from_secs(10)).await;
    assert_eq!(
        stat_reads(&m.roots),
        0,
        "paused by the setting: nothing is read"
    );
    let first = e.summary_docs.lock().unwrap().last().cloned().unwrap();
    assert_eq!(first["paused"], json!(true));
    assert_eq!(first["paused_by"], json!("settings"));
    // The panel's Pause cannot resume a setting's pause; the refusal names the reason.
    let refused = act(&e, "sysmon.pause", json!({"paused": false})).await;
    assert!(
        matches!(refused, Err(ActionError::Unavailable(ref k)) if k == "sysmon.error.paused_in_settings"),
        "{refused:?}"
    );
    // Turning the setting off resumes sampling, from a fresh baseline.
    e.settings.send_replace(values(&[("paused", json!(false))]));
    tokio::time::sleep(Duration::from_secs(5)).await;
    assert!(stat_reads(&m.roots) > 0, "resumed: reads again");
    assert_eq!(
        e.summary_docs.lock().unwrap().last().unwrap()["paused"],
        json!(false)
    );
    task.abort();
}

#[tokio::test(start_paused = true)]
async fn the_menu_flag_reaches_the_panel_at_once_not_at_the_next_sample() {
    let m = machine();
    let sys = Sysmon::with(m.roots.clone(), Arc::new(Sent::default()));
    let e = enable(&sys, Values::new());
    let task = subscribe(&e.summary, &e.summary_docs, &e.settings);
    tokio::time::sleep(Duration::from_millis(500)).await;
    let reads = stat_reads(&m.roots);
    assert_eq!(
        e.summary_docs.lock().unwrap().last().unwrap()["menu"],
        json!(false)
    );
    // A right click, half a second into a 2 s interval: the panel shows its menu before the next sample.
    act(&e, "sysmon.menu", json!({"on": true})).await.unwrap();
    tokio::time::sleep(Duration::from_millis(50)).await;
    assert_eq!(
        e.summary_docs.lock().unwrap().last().unwrap()["menu"],
        json!(true)
    );
    assert_eq!(
        stat_reads(&m.roots),
        reads,
        "the flag is published from the last values, not sampled"
    );
    act(&e, "sysmon.menu", json!({"on": false})).await.unwrap();
    tokio::time::sleep(Duration::from_millis(50)).await;
    assert_eq!(
        e.summary_docs.lock().unwrap().last().unwrap()["menu"],
        json!(false)
    );
    assert!(
        act(&e, "sysmon.menu", json!({})).await.is_err(),
        "a click names on or off"
    );
    task.abort();
}

#[tokio::test(start_paused = true)]
async fn open_btop_starts_the_setting_terminal_and_refuses_what_it_cannot_run() {
    let m = machine();
    let launch = Arc::new(Launch {
        path: vec!["btop", "foot"],
        ..Launch::default()
    });
    let sys = Sysmon::with_launcher(m.roots.clone(), Arc::new(Sent::default()), launch.clone());
    let e = enable(&sys, Values::new());
    // The default terminal is foot, and the run is `foot -e btop`.
    act(&e, "sysmon.open_btop", json!({})).await.unwrap();
    assert_eq!(
        launch.started.lock().unwrap().clone(),
        vec![(
            "foot".to_string(),
            vec!["-e".to_string(), "btop".to_string()]
        )]
    );
    // A terminal the Settings list does not offer is refused, and nothing starts.
    let e = enable(&sys, values(&[("terminal", json!("rxvt"))]));
    assert!(matches!(
        act(&e, "sysmon.open_btop", json!({})).await,
        Err(ActionError::Invalid(ref k)) if k == "sysmon.error.terminal"
    ));
    // Offered, but not installed.
    let e = enable(&sys, values(&[("terminal", json!("kitty"))]));
    assert!(matches!(
        act(&e, "sysmon.open_btop", json!({})).await,
        Err(ActionError::Unavailable(ref k)) if k == "sysmon.error.no_terminal"
    ));
    assert_eq!(
        launch.started.lock().unwrap().len(),
        1,
        "refused runs start nothing"
    );
    // A terminal is there, btop is not.
    let bare = Arc::new(Launch {
        path: vec!["foot"],
        ..Launch::default()
    });
    let sys = Sysmon::with_launcher(m.roots.clone(), Arc::new(Sent::default()), bare.clone());
    let e = enable(&sys, Values::new());
    assert!(matches!(
        act(&e, "sysmon.open_btop", json!({})).await,
        Err(ActionError::Unavailable(ref k)) if k == "sysmon.error.no_btop"
    ));
    assert!(bare.started.lock().unwrap().is_empty());
}

#[test]
fn a_control_value_is_judged_by_floors_and_a_disabled_level_stays_off() {
    use crate::thermal::Kind;
    let (_, rx) = watch::channel(values(&[
        ("temp_activity", json!(60)),
        ("temp_critical", json!(85)),
    ]));
    let c = Cfg::of(&Settings::new(rx));
    assert_eq!(c.limits_for(Some(Kind::Die)).temp.critical, 85.0);
    let ctl = c.limits_for(Some(Kind::Control));
    assert_eq!(
        ctl.temp.critical, 95.0,
        "Tctl is never judged below its own 95 °C"
    );
    assert_eq!(ctl.temp.activity, 75.0);
    assert_eq!(c.limits_for(None), c.limits, "no reading, no floor");

    let (_, rx) = watch::channel(values(&[
        ("temp_activity", json!(0)),
        ("temp_critical", json!(0)),
    ]));
    let off = Cfg::of(&Settings::new(rx)).limits_for(Some(Kind::Control));
    assert_eq!(
        (off.temp.activity, off.temp.critical),
        (0.0, 0.0),
        "0 turns a level off"
    );
}

#[tokio::test(start_paused = true)]
async fn the_summary_names_the_battery_the_host_and_the_paths_searched() {
    let m = machine();
    let sys_dir = m._dir.path().join("sys");
    write(&sys_dir.join("class/power_supply/BAT0/type"), "Battery\n");
    write(
        &sys_dir.join("class/power_supply/BAT0/status"),
        "Discharging\n",
    );
    write(&sys_dir.join("class/power_supply/BAT0/capacity"), "64\n");
    write(
        &sys_dir.join("class/power_supply/BAT0/power_now"),
        "12000000\n",
    );
    write(
        &sys_dir.join("class/power_supply/BAT0/energy_now"),
        "24000000\n",
    );
    write(&sys_dir.join("class/hwmon/hwmon0/name"), "nvme\n");
    let sys = Sysmon::with(m.roots.clone(), Arc::new(Sent::default()));
    let e = enable(&sys, Values::new());
    let task = subscribe(&e.summary, &e.summary_docs, &e.settings);
    tokio::time::sleep(Duration::from_secs(3)).await;
    task.abort();
    let docs = e.summary_docs.lock().unwrap();
    let last = docs.last().unwrap();
    assert_eq!(last["battery"]["state"], json!("discharging"));
    assert_eq!(last["battery"]["percent"], json!(64.0));
    assert_eq!(last["battery"]["watts"], json!(12.0));
    assert_eq!(last["battery"]["minutes_left"], json!(120));
    assert!(last.get("temp").is_none(), "no sensor is omitted, never 0");
    assert_eq!(last["temp_search"]["found"], json!(["nvme"]));
    assert_eq!(last["temp_search"]["wanted"][0], json!("k10temp"));
    assert_eq!(
        last["host"],
        Value::Null,
        "a bare machine has no host label"
    );
    assert_eq!(last["menu"], json!(false));
}

#[test]
fn the_process_document_carries_the_hottest_process_by_cpu_of_the_whole_scan() {
    let row = |pid: i32, name: &str, cpu: Option<f64>| crate::procs::Row {
        pid,
        name: name.into(),
        start: 1,
        cpu,
        mem_bytes: 1 << 20,
        mem_pct: 0.1,
        uid: Some(1000),
    };
    // Not among the shown rows (the list is cut to eight): the hottest is still named.
    let mut rows: Vec<crate::procs::Row> = (1..=12).map(|i| row(i, "idle", Some(0.1))).collect();
    rows.push(row(99, "firefox", Some(31.5)));
    let hot = crate::procs::hottest(&rows, false);
    let doc = crate::doc::procs(&rows[..8], false, rows.len(), false, 1000, 4242, hot);
    assert_eq!(doc["hottest"]["name"], json!("firefox"));
    assert_eq!(doc["hottest"]["cpu"], json!(31.5));
    let unmeasured = [row(5, "x", None)];
    let none = crate::doc::procs(
        &unmeasured,
        false,
        1,
        false,
        1000,
        4242,
        crate::procs::hottest(&unmeasured, false),
    );
    assert_eq!(
        none["hottest"],
        Value::Null,
        "no CPU share yet, so no top process"
    );
}

#[tokio::test(start_paused = true)]
async fn the_menu_opens_while_paused_and_reads_nothing() {
    let m = machine();
    let sys = Sysmon::with(m.roots.clone(), Arc::new(Sent::default()));
    let e = enable(&sys, Values::new());
    let task = subscribe(&e.summary, &e.summary_docs, &e.settings);
    tokio::time::sleep(Duration::from_secs(1)).await;
    act(&e, "sysmon.pause", json!({"paused": true})).await.unwrap();
    tokio::time::sleep(Duration::from_millis(50)).await;
    let reads = stat_reads(&m.roots);
    // A right click while paused: the menu (with Resume in it) opens from the stale values, unsampled.
    act(&e, "sysmon.menu", json!({"on": true})).await.unwrap();
    tokio::time::sleep(Duration::from_millis(50)).await;
    let last = e.summary_docs.lock().unwrap().last().cloned().unwrap();
    assert_eq!(last["menu"], json!(true));
    assert_eq!(last["paused"], json!(true));
    assert_eq!(last["paused_by"], json!("panel"));
    assert_eq!(stat_reads(&m.roots), reads, "paused: the menu reads nothing");
    task.abort();
}
