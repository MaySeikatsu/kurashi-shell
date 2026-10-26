//! The timer mod as the daemon drives it (K73): the enable registers what the manifest lists, the actions run, the deadline
//! job ends timers with no view open, its notice buttons come back as signals, and a restart announces what passed.
//! Time is paused: the job's sleeps and the clock the mod reads advance together.

use std::sync::atomic::{AtomicU32, AtomicU64, Ordering};
use std::sync::{Arc, Mutex};
use std::time::Duration;

use kurashi_mod_api::{
    ActionError, FaceUpdate, Hooks, Job, JobCtx, ModCtx, NativeMod, Registration, Settings, Values,
};
use kurashi_mod_timer::actions::ERR_BACKGROUND;
use kurashi_mod_timer::notify::{BoxFut, Notice, Notifier, Signal};
use kurashi_mod_timer::shared::Clock;
use kurashi_mod_timer::texts::Texts;
use kurashi_mod_timer::{TimerMod, store};
use serde_json::{Value, json};
use tokio::sync::{mpsc, watch};

/// Wall-clock milliseconds: a base, plus the paused tokio time, plus a skew the test adds while "the daemon is down".
#[derive(Clone)]
struct Wall {
    base: u64,
    start: tokio::time::Instant,
    skew: Arc<AtomicU64>,
}

impl Wall {
    fn new(base: u64) -> Self {
        Self {
            base,
            start: tokio::time::Instant::now(),
            skew: Arc::new(AtomicU64::new(0)),
        }
    }

    fn now(&self) -> u64 {
        self.base + self.skew.load(Ordering::SeqCst) + self.start.elapsed().as_millis() as u64
    }

    fn clock(&self) -> Clock {
        let me = self.clone();
        Arc::new(move || me.now())
    }

    fn down_for(&self, ms: u64) {
        self.skew.fetch_add(ms, Ordering::SeqCst);
    }
}

/// The notification server, as the job sees it: every notice shown is kept, and the test sends the buttons back.
#[derive(Default)]
struct Server {
    shown: Mutex<Vec<Notice>>,
    next: AtomicU32,
    signal_tx: Mutex<Option<mpsc::UnboundedSender<Signal>>>,
}

impl Server {
    fn shown(&self) -> Vec<Notice> {
        self.shown.lock().unwrap().clone()
    }

    fn press(&self, id: u32, key: &str) {
        let tx = self.signal_tx.lock().unwrap();
        tx.as_ref()
            .expect("the job listens")
            .send(Signal::Invoked {
                id,
                key: key.into(),
            })
            .unwrap();
    }
}

impl Notifier for Server {
    fn show(&self, notice: Notice) -> BoxFut<Option<u32>> {
        self.shown.lock().unwrap().push(notice);
        let id = self.next.fetch_add(1, Ordering::SeqCst) + 1;
        Box::pin(async move { Some(id) })
    }

    fn signals(&self) -> mpsc::UnboundedReceiver<Signal> {
        let (tx, rx) = mpsc::unbounded_channel();
        *self.signal_tx.lock().unwrap() = Some(tx);
        rx
    }
}

#[derive(Default)]
struct Faces {
    updates: Mutex<Vec<FaceUpdate>>,
}

impl Hooks for Faces {
    fn face(&self, _face: &str, update: FaceUpdate) {
        self.updates.lock().unwrap().push(update);
    }

    fn choices_changed(&self, _source: &str) {}
}

/// One enable of the mod, as the daemon does it: the registrations, the job, and the settings feed (kept alive: its
/// sender ending is the mod's disable).
struct Enabled {
    regs: Vec<Registration>,
    job: Option<Job>,
    settings: Settings,
    _feed: watch::Sender<Values>,
    faces: Arc<Faces>,
}

impl Enabled {
    fn action(&self, id: &str, args: Value) -> Result<Option<Value>, ActionError> {
        let handler = self
            .regs
            .iter()
            .find_map(|r| match r {
                Registration::Action { id: i, handler, .. } if i == id => Some(handler.clone()),
                _ => None,
            })
            .unwrap_or_else(|| panic!("action {id} is registered"));
        futures_block_on(handler(args))
    }

    /// The document as a view sees it now: the registered service runs (as it does while a view subscribes) and its
    /// last publish is read. The first publish comes at once; the test lets the service run before it reads.
    async fn document(&self) -> Value {
        let run = self
            .regs
            .iter()
            .find_map(|r| match r {
                Registration::Service { id, run, .. } if id == "timer" => Some(run.clone()),
                _ => None,
            })
            .expect("the document is registered");
        let last = Arc::new(Mutex::new(Value::Null));
        let slot = last.clone();
        let publish: kurashi_mod_api::Publish = Arc::new(move |v| *slot.lock().unwrap() = v);
        let task = tokio::spawn(run(publish, self.settings.clone()));
        tokio::time::sleep(Duration::from_millis(1)).await;
        task.abort();
        let doc = last.lock().unwrap().clone();
        assert_ne!(doc, Value::Null, "the service published its document");
        doc
    }

    /// Starts the deadline job the way the daemon does: its own settings feed and a sink for "has work".
    fn start_job(&self, active: Arc<Mutex<Option<bool>>>) -> tokio::task::JoinHandle<()> {
        let job = self.job.as_ref().expect("the job is declared");
        let sink = Arc::new(move |on: bool| *active.lock().unwrap() = Some(on));
        let ctx = JobCtx::with_active(self.settings.clone(), sink);
        tokio::spawn((job.run)(ctx))
    }
}

fn futures_block_on<T>(fut: impl std::future::Future<Output = T>) -> T {
    // The actions do no I/O: a noop waker and one poll resolve them.
    use std::pin::pin;
    use std::task::{Context, Poll, Waker};
    let mut fut = pin!(fut);
    let mut cx = Context::from_waker(Waker::noop());
    match fut.as_mut().poll(&mut cx) {
        Poll::Ready(v) => v,
        Poll::Pending => panic!("an action that does no I/O is ready at once"),
    }
}

fn settings(background: bool) -> Values {
    let mut v = Values::new();
    v.insert("background".into(), json!(background));
    v.insert("presets".into(), json!("5,10,25"));
    v.insert("focus_minutes".into(), json!(25));
    v.insert("short_break_minutes".into(), json!(5));
    v.insert("long_break_minutes".into(), json!(15));
    v.insert("rounds".into(), json!(4));
    v.insert("auto_advance".into(), json!(true));
    v.insert("sound".into(), json!(true));
    v
}

fn enable(module: &TimerMod, values: Values) -> Enabled {
    let (feed, rx) = watch::channel(values);
    let settings = Settings::new(rx);
    let faces = Arc::new(Faces::default());
    let provides: Vec<String> = [
        "service:timer",
        "action:timer.*",
        "job:deadline",
        "island-face:timer",
    ]
    .map(String::from)
    .to_vec();
    let mut ctx = ModCtx::new(&provides, settings.clone(), faces.clone());
    module.enable(&mut ctx).expect("the mod enables");
    let jobs = ctx.take_jobs();
    let regs = ctx.finish().expect("nothing is left behind");
    Enabled {
        regs,
        job: jobs.into_iter().next(),
        settings,
        _feed: feed,
        faces,
    }
}

fn module(path: &std::path::Path, wall: &Wall, server: &Arc<Server>) -> TimerMod {
    TimerMod::with(
        path.to_path_buf(),
        wall.clock(),
        server.clone(),
        Texts::load(&kurashi_mod_timer::texts::i18n_root(), "en"),
    )
}

const T0: u64 = 1_800_000_000_000;
const MIN: u64 = 60_000;

#[tokio::test(start_paused = true)]
async fn a_countdown_ends_with_no_view_open_and_its_plus_one_button_runs_it_again() {
    let dir = tempfile::tempdir().unwrap();
    let path = dir.path().join("timer.json");
    let wall = Wall::new(T0);
    let server = Arc::new(Server::default());
    let e = enable(&module(&path, &wall, &server), settings(true));
    let active = Arc::new(Mutex::new(None));
    let _job = e.start_job(active.clone());

    let started = e
        .action("timer.start", json!({"seconds": 60, "label": "tea"}))
        .unwrap()
        .unwrap();
    assert_eq!(started["id"], 1);
    tokio::time::sleep(Duration::from_secs(59)).await;
    assert!(
        server.shown().is_empty(),
        "not yet: nothing announced before the end"
    );
    assert_eq!(
        *active.lock().unwrap(),
        Some(true),
        "the job has work while a timer runs"
    );
    assert!(
        e.faces
            .updates
            .lock()
            .unwrap()
            .contains(&FaceUpdate::Raise {
                relevance: 40,
                ttl: None
            }),
        "the live face is up while it runs"
    );

    tokio::time::sleep(Duration::from_secs(2)).await;
    let shown = server.shown();
    assert_eq!(shown.len(), 1, "one notice for the end, with no view open");
    assert_eq!(shown[0].summary, "tea");
    assert_eq!(shown[0].body, "Time is up");
    assert_eq!(
        shown[0].actions,
        vec![
            ("add".to_owned(), "+1 min".to_owned()),
            ("stop".to_owned(), "Stop".to_owned())
        ]
    );
    assert!(shown[0].sound, "the sound setting reaches the notice");
    assert!(
        e.faces
            .updates
            .lock()
            .unwrap()
            .contains(&FaceUpdate::Raise {
                relevance: 90,
                ttl: None
            }),
        "the end face is raised over the live one"
    );
    assert_eq!(
        *active.lock().unwrap(),
        Some(false),
        "nothing runs: the job has no work"
    );

    // The user presses "+1 min" on the notice: the same timer runs one more minute, and its end is announced again.
    server.press(1, "add");
    tokio::time::sleep(Duration::from_secs(61)).await;
    assert_eq!(
        server.shown().len(),
        2,
        "the second run ends and is announced"
    );
    assert_eq!(server.shown()[1].body, "Time is up");

    // The state on disk is what the daemon knows: the timer is ended, and nothing is pending.
    let saved = store::load(&path);
    assert_eq!(saved.timers.len(), 1);
    assert!(!saved.timers[0].pending_end);
}

#[tokio::test(start_paused = true)]
async fn a_pomodoro_moves_on_by_itself_and_says_so_when_the_break_starts() {
    let dir = tempfile::tempdir().unwrap();
    let path = dir.path().join("timer.json");
    let wall = Wall::new(T0);
    let server = Arc::new(Server::default());
    let e = enable(&module(&path, &wall, &server), settings(true));
    let _job = e.start_job(Arc::new(Mutex::new(None)));

    e.action("timer.pomodoro.start", json!({})).unwrap();
    tokio::time::sleep(Duration::from_secs(25 * 60 + 1)).await;
    let shown = server.shown();
    assert_eq!(shown.len(), 1, "the focus ended: one notice");
    assert_eq!(shown[0].summary, "Pomodoro");
    assert_eq!(shown[0].body, "Short break · 5 min");
    let keys: Vec<&str> = shown[0].actions.iter().map(|(k, _)| k.as_str()).collect();
    assert_eq!(
        keys,
        vec!["add", "stop", "skip"],
        "+1 min, Stop, Next phase"
    );

    let doc = e.document().await;
    assert_eq!(
        doc["timers"][0]["state"], "running",
        "the break runs on its own"
    );
    assert_eq!(doc["timers"][0]["phase"], "short_break");

    // Next phase skips the rest of the break: a focus round 2 starts now.
    let id = doc["timers"][0]["id"].as_u64().unwrap();
    server.press(1, "skip");
    tokio::time::sleep(Duration::from_millis(10)).await;
    let doc = e.document().await;
    assert_eq!(doc["timers"][0]["id"], id);
    assert_eq!(doc["timers"][0]["phase"], "focus");
    assert_eq!(doc["timers"][0]["round"], 2);
}

#[tokio::test(start_paused = true)]
async fn an_end_during_a_daemon_restart_is_announced_once_on_start_with_its_time() {
    let dir = tempfile::tempdir().unwrap();
    let path = dir.path().join("timer.json");
    let wall = Wall::new(T0);
    let server = Arc::new(Server::default());
    {
        let e = enable(&module(&path, &wall, &server), settings(true));
        e.action("timer.start", json!({"minutes": 3, "label": "tea"}))
            .unwrap();
    }
    // The daemon is down for ten minutes; the timer ran out meanwhile.
    wall.down_for(10 * MIN);
    let e = enable(&module(&path, &wall, &server), settings(true));
    let _job = e.start_job(Arc::new(Mutex::new(None)));
    tokio::time::sleep(Duration::from_millis(10)).await;
    let shown = server.shown();
    assert_eq!(
        shown.len(),
        1,
        "the end that passed while down is announced on start"
    );
    assert!(
        shown[0].body.starts_with("Ended at "),
        "a late end says when it ended: {}",
        shown[0].body
    );
    assert_eq!(shown[0].summary, "tea");

    // The next start finds nothing pending: no second notice for the same end.
    let e = enable(&module(&path, &wall, &server), settings(true));
    let _job = e.start_job(Arc::new(Mutex::new(None)));
    tokio::time::sleep(Duration::from_millis(10)).await;
    assert_eq!(server.shown().len(), 1);
}

#[tokio::test(start_paused = true)]
async fn an_idle_mod_has_no_deadline_and_a_stopped_timer_is_not_announced() {
    let dir = tempfile::tempdir().unwrap();
    let path = dir.path().join("timer.json");
    let wall = Wall::new(T0);
    let server = Arc::new(Server::default());
    let e = enable(&module(&path, &wall, &server), settings(true));
    let active = Arc::new(Mutex::new(None));
    let _job = e.start_job(active.clone());
    tokio::time::sleep(Duration::from_secs(3600)).await;
    assert!(
        server.shown().is_empty(),
        "idle: nothing ends, nothing is shown"
    );
    assert_eq!(
        *active.lock().unwrap(),
        Some(false),
        "idle: the job lists no running work"
    );

    e.action("timer.start", json!({"seconds": 90})).unwrap();
    e.action("timer.stop", json!({"id": 1})).unwrap();
    tokio::time::sleep(Duration::from_secs(120)).await;
    assert!(server.shown().is_empty(), "a stopped timer never ends");
}

#[tokio::test(start_paused = true)]
async fn background_off_refuses_a_new_timer_and_a_running_one_is_still_listed() {
    let dir = tempfile::tempdir().unwrap();
    let path = dir.path().join("timer.json");
    let wall = Wall::new(T0);
    let server = Arc::new(Server::default());
    let off = enable(&module(&path, &wall, &server), settings(false));
    let refused = off
        .action("timer.start", json!({"minutes": 1}))
        .unwrap_err();
    assert_eq!(refused, ActionError::Unavailable(ERR_BACKGROUND.into()));
    assert_eq!(off.document().await["background"], false);

    let on = enable(&module(&path, &wall, &server), settings(true));
    on.action("timer.start", json!({"seconds": 30})).unwrap();
    let on_again = enable(&module(&path, &wall, &server), settings(false));
    let doc = on_again.document().await;
    assert_eq!(
        doc["timers"].as_array().unwrap().len(),
        1,
        "the state is kept"
    );
}

#[tokio::test(start_paused = true)]
async fn pause_and_resume_survive_a_restart_with_the_time_that_was_left() {
    let dir = tempfile::tempdir().unwrap();
    let path = dir.path().join("timer.json");
    let wall = Wall::new(T0);
    let server = Arc::new(Server::default());
    {
        let e = enable(&module(&path, &wall, &server), settings(true));
        e.action("timer.start", json!({"minutes": 10})).unwrap();
        tokio::time::sleep(Duration::from_secs(4 * 60)).await;
        e.action("timer.pause", json!({"id": 1})).unwrap();
    }
    wall.down_for(60 * MIN);
    let e = enable(&module(&path, &wall, &server), settings(true));
    let doc = e.document().await;
    assert_eq!(
        doc["timers"][0]["state"], "paused",
        "a paused timer does not run down while down"
    );
    assert_eq!(doc["timers"][0]["remaining_ms"], 6 * MIN);
    assert!(server.shown().is_empty());
}
