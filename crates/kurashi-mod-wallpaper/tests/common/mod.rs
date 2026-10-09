//! The test harness: a fake backend that records every call, and the wallpaper enabled through the
//! same `ModCtx` the daemon uses, so the registrations are the ones kurashid would apply.

#![allow(dead_code)]

use std::collections::BTreeSet;
use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Arc, Mutex};
use std::time::Duration;

use kurashi_mod_api::{
    ActionError, ActionFn, Choice, ChoicesFn, FaceUpdate, Hooks, ModCtx, ModError, NativeMod,
    Publish, Registration, ServiceFn, Settings, Values,
};
use kurashi_mod_wallpaper::{Dirs, Exec, ExecError, ExecFuture, ExecOutput, Wallpaper};
use serde_json::{Value, json};
use tokio::sync::watch;

/// The `provides` of the bundled manifest (`mods/wallpaper/mod.toml`).
pub const PROVIDES: &[&str] = &[
    "service:wallpaper",
    "action:wallpaper.*",
    "panel:wallpaper",
    "choices:wallpaper.backends",
    "slot:quick.tiles",
];

pub const QUERY_JSON: &str = r#"{"": [
    {"name": "DP-2", "width": 1920, "height": 1080, "scale": 1, "displaying": {"color": "000000"}},
    {"name": "DP-1", "width": 2560, "height": 1440, "scale": 1, "displaying": {"image": "/w/x.png"}}
]}"#;

/// A backend that answers like awww and remembers every call.
pub struct Fake {
    pub present: Mutex<BTreeSet<String>>,
    pub daemon_up: AtomicBool,
    /// Whether `spawn` of a daemon brings it up (false: a daemon that never answers).
    pub spawn_starts: AtomicBool,
    pub img_fails: AtomicBool,
    pub calls: Mutex<Vec<String>>,
}

impl Fake {
    pub fn new(present: &[&str]) -> Arc<Self> {
        Arc::new(Self {
            present: Mutex::new(present.iter().map(|s| s.to_string()).collect()),
            daemon_up: AtomicBool::new(false),
            spawn_starts: AtomicBool::new(true),
            img_fails: AtomicBool::new(false),
            calls: Mutex::new(Vec::new()),
        })
    }

    /// Calls whose line starts with `prefix` (e.g. `awww img`).
    pub fn count(&self, prefix: &str) -> usize {
        self.calls
            .lock()
            .unwrap()
            .iter()
            .filter(|c| c.starts_with(prefix))
            .count()
    }

    pub fn lines(&self, prefix: &str) -> Vec<String> {
        self.calls
            .lock()
            .unwrap()
            .iter()
            .filter(|c| c.starts_with(prefix))
            .cloned()
            .collect()
    }
}

fn ok(stdout: &str) -> Result<ExecOutput, ExecError> {
    Ok(ExecOutput {
        ok: true,
        stdout: stdout.into(),
        stderr: String::new(),
    })
}

fn fail(stderr: &str) -> Result<ExecOutput, ExecError> {
    Ok(ExecOutput {
        ok: false,
        stdout: String::new(),
        stderr: stderr.into(),
    })
}

impl Exec for Fake {
    fn find(&self, program: &str) -> Option<PathBuf> {
        self.present
            .lock()
            .unwrap()
            .contains(program)
            .then(|| PathBuf::from("/fake/bin").join(program))
    }

    fn run(&self, program: &str, args: Vec<String>, _timeout: Duration) -> ExecFuture {
        self.calls
            .lock()
            .unwrap()
            .push(format!("{program} {}", args.join(" ")));
        let result = match args.first().map(String::as_str) {
            Some("--version") => ok("awww 0.12.1\n"),
            Some("query") => {
                if self.daemon_up.load(Ordering::SeqCst) {
                    ok(QUERY_JSON)
                } else {
                    fail("Failed to connect to the awww-daemon socket")
                }
            }
            Some("img") => {
                if self.img_fails.load(Ordering::SeqCst) {
                    fail("image decode failed")
                } else {
                    ok("")
                }
            }
            Some("kill") => {
                self.daemon_up.store(false, Ordering::SeqCst);
                ok("")
            }
            _ => Err(ExecError::NotFound(program.into())),
        };
        Box::pin(async move { result })
    }

    fn spawn(&self, program: &str, args: Vec<String>) -> Result<(), ExecError> {
        self.calls
            .lock()
            .unwrap()
            .push(format!("spawn {program} {}", args.join(" ")));
        if program.ends_with("-daemon") && self.spawn_starts.load(Ordering::SeqCst) {
            self.daemon_up.store(true, Ordering::SeqCst);
        }
        Ok(())
    }
}

struct NoHooks;

impl Hooks for NoHooks {
    fn face(&self, _face: &str, _update: FaceUpdate) {}
    fn choices_changed(&self, _source: &str) {}
}

/// The settings a fresh install has (the manifest defaults), with `folders` pointed at `folder`.
pub fn values(folder: &Path) -> Values {
    let mut v = Values::new();
    for (k, val) in [
        ("backend", json!("awww")),
        ("folders", json!(folder.display().to_string())),
        ("fit", json!("crop")),
        ("crop_anchor", json!("center")),
        ("transition", json!("fade")),
        ("transition_duration", json!(1.0)),
        ("transition_angle", json!(45)),
        ("rotate", json!(0)),
        ("rotate_order", json!("alphabetical")),
        ("rotate_per_output", json!(false)),
        ("restore", json!(true)),
    ] {
        v.insert(k.into(), val);
    }
    v
}

/// A wallpaper enabled through `ModCtx`: what the daemon would register.
pub struct Mod {
    pub fake: Arc<Fake>,
    pub dirs: Dirs,
    /// What the service publishes (the document, as a subscriber sees it).
    pub doc: watch::Receiver<Value>,
    doc_tx: watch::Sender<Value>,
    /// The settings feed; dropping it is a disable (the supervisor's `changed()` returns false).
    pub settings: Option<watch::Sender<Values>>,
    service: ServiceFn,
    settings_rx: watch::Receiver<Values>,
    actions: Vec<(String, ActionFn)>,
    choices: Option<ChoicesFn>,
    pub subscriber: Option<tokio::task::JoinHandle<()>>,
}

impl Mod {
    pub fn enable(fake: Arc<Fake>, dirs: Dirs, values: Values) -> Result<Self, ModError> {
        let wp = Wallpaper::with(fake.clone(), dirs.clone());
        let (settings_tx, settings_rx) = watch::channel(values);
        let provides: Vec<String> = PROVIDES.iter().map(|s| s.to_string()).collect();
        let mut ctx = ModCtx::new(
            &provides,
            Settings::new(settings_rx.clone()),
            Arc::new(NoHooks),
        );
        wp.enable(&mut ctx)?;
        let regs = ctx.finish()?;
        let (doc_tx, doc) = watch::channel(Value::Null);
        let mut service = None;
        let mut actions = Vec::new();
        let mut choices = None;
        for r in regs {
            match r {
                Registration::Service { run, .. } => service = Some(run),
                Registration::Action { id, handler, .. } => actions.push((id, handler)),
                Registration::Choices { options, .. } => choices = Some(options),
                Registration::Face { .. } => {}
            }
        }
        Ok(Self {
            fake,
            dirs,
            doc,
            doc_tx,
            settings: Some(settings_tx),
            service: service.expect("the document is registered"),
            settings_rx,
            actions,
            choices,
            subscriber: None,
        })
    }

    /// A subscriber arrives: the service runs and publishes into `doc`.
    pub fn subscribe(&mut self) {
        let tx = self.doc_tx.clone();
        let publish: Publish = Arc::new(move |v| {
            let _ = tx.send(v);
        });
        let settings = Settings::new(self.settings_rx.clone());
        self.subscriber = Some(tokio::spawn((self.service)(publish, settings)));
    }

    pub async fn act(&self, id: &str, args: Value) -> Result<Option<Value>, ActionError> {
        let handler = self
            .actions
            .iter()
            .find(|(i, _)| i == id)
            .unwrap_or_else(|| panic!("action {id} is registered"))
            .1
            .clone();
        handler(args).await
    }

    pub fn has_action(&self, id: &str) -> bool {
        self.actions.iter().any(|(i, _)| i == id)
    }

    pub fn choices(&self) -> Vec<Choice> {
        (self
            .choices
            .as_ref()
            .expect("the backend choices are registered"))()
    }

    /// Changes one setting, as a config change does.
    pub fn set(&self, key: &str, value: Value) {
        if let Some(tx) = &self.settings {
            tx.send_modify(|v| {
                v.insert(key.into(), value);
            });
        }
    }

    /// A disable: the settings feed closes.
    pub fn disable(&mut self) {
        self.settings = None;
    }

    pub fn doc(&self) -> Value {
        self.doc.borrow().clone()
    }
}

/// Waits (up to 10 s of real time) until `check` holds. Yields and sleeps for real rather than on
/// the tokio clock, so a paused clock does not advance while the blocking pool does its work.
pub async fn eventually(mut check: impl FnMut() -> bool) {
    let start = std::time::Instant::now();
    while !check() {
        assert!(
            start.elapsed() < Duration::from_secs(10),
            "the condition was not reached in 10 s"
        );
        tokio::task::yield_now().await;
        std::thread::sleep(Duration::from_millis(1));
    }
}

/// A scratch directory for one test, empty.
pub fn scratch(tag: &str) -> PathBuf {
    let dir = std::env::temp_dir().join(format!(
        "kurashi-wp-{tag}-{}-{}",
        std::process::id(),
        std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .map_or(0, |d| d.as_nanos())
    ));
    let _ = std::fs::remove_dir_all(&dir);
    std::fs::create_dir_all(&dir).unwrap();
    dir
}

/// A library folder with `names` as one-pixel pictures: `set` reads each header before the backend is asked
/// (a picture the backend cannot read is refused), so the fake library holds real, tiny images.
pub fn library(root: &Path, names: &[&str]) -> PathBuf {
    let folder = root.join("library");
    std::fs::create_dir_all(&folder).unwrap();
    for n in names {
        let path = folder.join(n);
        // Names that are not pictures (a note, say) stay what they are: plain bytes.
        let is_picture = path.extension().and_then(|e| e.to_str()).is_some_and(|e| {
            matches!(
                e.to_ascii_lowercase().as_str(),
                "png" | "jpg" | "jpeg" | "webp" | "gif" | "bmp"
            )
        });
        if is_picture {
            image::RgbImage::from_pixel(1, 1, image::Rgb([90, 120, 200]))
                .save(&path)
                .unwrap();
        } else {
            std::fs::write(&path, b"not a picture").unwrap();
        }
    }
    folder
}

pub fn choices_by_value(choices: &[Choice]) -> Vec<(String, bool, Option<String>)> {
    choices
        .iter()
        .map(|c| (c.value.clone(), c.enabled, c.reason.clone()))
        .collect()
}
