//! The wallpaper's supervisor: one task per enable, the only owner of the backend, the state file and
//! the rotation timer. It runs while the mod is enabled (not while the picker is open): wallpapers
//! stay set, and rotation keeps going, without subscribers. Actions and the document reach it
//! through commands and a watch channel; nothing else touches the backend.
//!
//! Ma: with rotation off and nothing asking, the task sleeps on its channels and runs no command.
//! The rotation timer is one `sleep_until` on the earliest due time, and it exists only while
//! rotation is on. A disabled mod ends the task (its settings feed closes).

use std::collections::BTreeMap;
use std::path::{Path, PathBuf};
use std::sync::{Arc, Mutex};
use std::time::{Duration, SystemTime, UNIX_EPOCH};

use kurashi_mod_api::{ActionError, ChoicesHandle, Settings};
use serde_json::{Map, Value, json};
use tokio::sync::{mpsc, oneshot, watch};
use tokio::time::Instant;

use crate::Dirs;
use crate::backend::{BackendId, ImgOpts, Output};
use crate::config::Config;
use crate::exec::{Exec, ExecError, ExecOutput};
use crate::library::{self, FolderStatus, Scan};
use crate::rotate::{self, Rng};
use crate::state::{self, Favourite, OutputState, Persisted};

const QUERY_TIMEOUT: Duration = Duration::from_secs(3);
const VERSION_TIMEOUT: Duration = Duration::from_secs(3);
const IMG_TIMEOUT: Duration = Duration::from_secs(5);
const KILL_TIMEOUT: Duration = Duration::from_secs(3);
/// A daemon gets this long to answer its first query after it was started.
const START_POLLS: u32 = 50;
const START_POLL: Duration = Duration::from_millis(100);
/// At most one daemon start per this gap, so a daemon that dies at once is not restarted in a loop.
const START_GAP: Duration = Duration::from_secs(10);

/// Where a refused or failed request answers: its action reply.
pub type Reply = oneshot::Sender<Result<Option<Value>, ActionError>>;

/// What the actions ask of the supervisor.
pub enum Cmd {
    /// Show `path` on `outputs` (empty = every output).
    Set {
        path: PathBuf,
        outputs: Vec<String>,
        reply: Reply,
    },
    /// The image before or after the current one, or a random one.
    Step {
        forward: bool,
        random: bool,
        output: Option<String>,
        reply: Reply,
    },
    /// Toggles a favourite look; `scheme` and `palette` are stored as given.
    Favourite {
        path: PathBuf,
        scheme: Option<String>,
        palette: Option<String>,
        reply: Reply,
    },
    /// `on = None` toggles the pause.
    Pause { on: Option<bool>, reply: Reply },
    /// Stops the backend daemon and starts it again, then restores the images.
    Restart { reply: Reply },
    /// The picker opened: check the backend and the library now. Fire and forget.
    Refresh,
}

/// What the supervisor and the actions share: the document the service serves, the command
/// channel, the settings feed and the directories.
pub struct Shared {
    pub doc: watch::Sender<Value>,
    pub cmd: mpsc::UnboundedSender<Cmd>,
    pub settings: Settings,
    pub exec: Arc<dyn Exec>,
    pub dirs: Dirs,
    /// The last library scan the picker asked for, reused for a few seconds (paging).
    pub scans: Mutex<Option<CachedScan>>,
}

pub struct CachedScan {
    pub at: std::time::Instant,
    pub key: String,
    pub scan: Arc<Scan>,
}

/// The backend's state as the document shows it.
#[derive(Clone, Debug, PartialEq, Eq)]
enum Status {
    /// Not installed (or an unknown backend id): the reason is an i18n key.
    Missing(&'static str),
    Starting,
    /// Installed, but its daemon does not answer.
    Down,
    /// Answers; the version when `--version` said one.
    Ok(Option<String>),
}

impl Status {
    fn reason(&self) -> Option<&'static str> {
        match self {
            Self::Missing(r) => Some(r),
            Self::Starting => Some("mod-wallpaper.backend.starting"),
            Self::Down => Some("mod-wallpaper.backend.down"),
            Self::Ok(_) => None,
        }
    }

    fn up(&self) -> bool {
        matches!(self, Self::Ok(_))
    }
}

pub struct Supervisor {
    shared: Arc<Shared>,
    cmds: mpsc::UnboundedReceiver<Cmd>,
    settings: Settings,
    choices: ChoicesHandle,
    cfg: Config,
    state: Persisted,
    status: Status,
    outputs: Vec<Output>,
    loaded: bool,
    lib_count: usize,
    lib_folders: Vec<FolderStatus>,
    /// The last failure a request or a rotation hit: its i18n key and detail, cleared by success.
    error: Option<(String, Option<String>)>,
    /// Next rotation per key: `*` for all outputs together, else one output's name.
    due: BTreeMap<String, Instant>,
    rng: Rng,
    last_start: Option<Instant>,
}

impl Supervisor {
    pub fn new(
        shared: Arc<Shared>,
        cmds: mpsc::UnboundedReceiver<Cmd>,
        choices: ChoicesHandle,
    ) -> Self {
        let settings = shared.settings.clone();
        let cfg = Config::read(&settings);
        Self {
            shared,
            cmds,
            settings,
            choices,
            cfg,
            state: Persisted::default(),
            status: Status::Starting,
            outputs: Vec::new(),
            loaded: false,
            lib_count: 0,
            lib_folders: Vec::new(),
            error: None,
            due: BTreeMap::new(),
            rng: Rng::from_clock(),
            last_start: None,
        }
    }

    pub async fn run(mut self) {
        self.start().await;
        self.publish();
        loop {
            let due = self.due.values().min().copied();
            tokio::select! {
                cmd = self.cmds.recv() => match cmd {
                    Some(cmd) => self.command(cmd).await,
                    None => break,
                },
                changed = self.settings.changed() => {
                    // False: the mod was disabled, and its settings feed closed with it.
                    if !changed {
                        break;
                    }
                    self.reconfigure().await;
                }
                () = wait_until(due) => self.tick().await,
            }
            self.publish();
        }
    }

    // ---- start, restore, backend -------------------------------------------------------------

    async fn start(&mut self) {
        let dirs = self.shared.dirs.clone();
        let loaded = state::load(&dirs.state_file());
        self.state = loaded.state;
        if loaded.set_aside {
            self.error = Some(("mod-wallpaper.state.set_aside".into(), None));
        }
        self.refresh_library().await;
        self.ensure_backend(true).await;
        if self.status.up() && self.cfg.restore {
            self.restore().await;
        }
        self.loaded = true;
        self.schedule_all();
        self.choices.choices_changed();
    }

    /// Checks the backend: installed, answering, and if not answering, started (at most once per
    /// [`START_GAP`]). Sets the status; refreshes the outputs when it answers.
    async fn ensure_backend(&mut self, may_start: bool) {
        let Some(id) = BackendId::parse(&self.cfg.backend) else {
            self.status = Status::Missing("mod-wallpaper.backend.unknown");
            self.outputs.clear();
            return;
        };
        if self.shared.exec.find(id.cli()).is_none() {
            self.status = Status::Missing("mod-wallpaper.backend.missing");
            self.outputs.clear();
            return;
        }
        if self.query(id).await.is_ok() {
            let version = self.version(id).await;
            self.status = Status::Ok(version);
            return;
        }
        let gap_open = self.last_start.is_none_or(|at| at.elapsed() >= START_GAP);
        if !may_start || !gap_open {
            self.status = Status::Down;
            return;
        }
        self.last_start = Some(Instant::now());
        self.status = Status::Starting;
        self.publish();
        if let Err(e) = self.shared.exec.spawn(id.daemon(), id.daemon_args()) {
            self.status = Status::Down;
            self.error = Some(("mod-wallpaper.backend.down".into(), Some(describe(&e))));
            return;
        }
        for _ in 0..START_POLLS {
            tokio::time::sleep(START_POLL).await;
            if self.query(id).await.is_ok() {
                let version = self.version(id).await;
                self.status = Status::Ok(version);
                return;
            }
        }
        self.status = Status::Down;
    }

    async fn query(&mut self, id: BackendId) -> Result<(), String> {
        let out = self
            .run_cli(id.cli(), id.query_args(), QUERY_TIMEOUT)
            .await?;
        self.outputs = id.parse_query(&out.stdout)?;
        Ok(())
    }

    async fn version(&self, id: BackendId) -> Option<String> {
        self.run_cli(id.cli(), vec!["--version".into()], VERSION_TIMEOUT)
            .await
            .ok()
            .and_then(|out| crate::backend::parse_version(&out.stdout))
    }

    /// Runs the backend's client. A failed call is its stderr (or the exec error) as text.
    async fn run_cli(
        &self,
        program: &str,
        args: Vec<String>,
        timeout: Duration,
    ) -> Result<ExecOutput, String> {
        match self.shared.exec.run(program, args, timeout).await {
            Ok(out) if out.ok => Ok(out),
            Ok(out) => Err(out.stderr.trim().to_string()),
            Err(e) => Err(describe(&e)),
        }
    }

    /// Applies `path` to `outputs` (empty = all) with `transition`. A failed call marks the backend
    /// down: the next request checks it again instead of assuming it works.
    async fn apply(
        &mut self,
        path: &str,
        outputs: &[String],
        transition: &str,
    ) -> Result<(), String> {
        let Some(id) = BackendId::parse(&self.cfg.backend) else {
            return Err("mod-wallpaper.backend.unknown".into());
        };
        let args = {
            let opts = ImgOpts {
                outputs,
                fit: &self.cfg.fit,
                crop_anchor: &self.cfg.crop_anchor,
                transition,
                duration: self.cfg.duration,
                angle: self.cfg.angle,
            };
            id.img_args(path, &opts)
        };
        match self.run_cli(id.cli(), args, IMG_TIMEOUT).await {
            Ok(_) => Ok(()),
            Err(e) => {
                self.status = Status::Down;
                Err(e)
            }
        }
    }

    /// Shows each output's stored image again (after a start, a backend change, a fit change). Only
    /// images that still exist are shown; the rest keep whatever the backend has.
    async fn restore(&mut self) {
        let plan: Vec<(String, String)> = self
            .outputs
            .iter()
            .filter_map(|o| self.path_of(&o.name).map(|p| (o.name.clone(), p)))
            .filter(|(_, p)| Path::new(p).is_file())
            .collect();
        for (name, path) in plan {
            if let Err(e) = self.apply(&path, &[name], "none").await {
                self.error = Some(("mod-wallpaper.error.apply".into(), Some(e)));
            }
        }
    }

    /// The image an output should show: its own, else the one set for all outputs.
    fn path_of(&self, output: &str) -> Option<String> {
        self.state
            .outputs
            .get(output)
            .map(|o| o.path.clone())
            .or_else(|| self.state.all.clone())
    }

    async fn refresh_library(&mut self) -> Arc<Scan> {
        let roots = self.cfg.roots();
        let scan = Arc::new(
            tokio::task::spawn_blocking(move || library::scan(&roots))
                .await
                .unwrap_or_default(),
        );
        self.lib_count = scan.entries.len();
        self.lib_folders = scan.folders.clone();
        scan
    }

    // ---- commands ----------------------------------------------------------------------------

    async fn command(&mut self, cmd: Cmd) {
        match cmd {
            Cmd::Set {
                path,
                outputs,
                reply,
            } => {
                let r = self.set_request(path, outputs).await;
                let _ = reply.send(r);
            }
            Cmd::Step {
                forward,
                random,
                output,
                reply,
            } => {
                let r = self.step(forward, random, output).await;
                let _ = reply.send(r);
            }
            Cmd::Favourite {
                path,
                scheme,
                palette,
                reply,
            } => {
                let r = self.favourite(&path, scheme, palette);
                let _ = reply.send(r);
            }
            Cmd::Pause { on, reply } => {
                self.state.paused = on.unwrap_or(!self.state.paused);
                self.save();
                self.schedule_all();
                let _ = reply.send(Ok(Some(json!({"paused": self.state.paused}))));
            }
            Cmd::Restart { reply } => {
                let r = self.restart().await;
                let _ = reply.send(r);
            }
            Cmd::Refresh => {
                self.refresh_library().await;
                self.ensure_backend(true).await;
                self.schedule_all();
                self.choices.choices_changed();
            }
        }
    }

    async fn set_request(
        &mut self,
        path: PathBuf,
        outputs: Vec<String>,
    ) -> Result<Option<Value>, ActionError> {
        if !library::is_image(&path) || !path.is_file() {
            return Err(ActionError::Invalid("mod-wallpaper.error.not_image".into()));
        }
        let path = path.display().to_string();
        self.ready().await?;
        let targets = self.targets(&outputs)?;
        self.set_on(
            &path,
            &targets,
            outputs.is_empty(),
            &self.cfg.transition.clone(),
        )
        .await
        .map(Some)
    }

    /// The outputs a request names, all of them when it names none; unknown names are refused.
    fn targets(&self, names: &[String]) -> Result<Vec<String>, ActionError> {
        if names.is_empty() {
            let all: Vec<String> = self.outputs.iter().map(|o| o.name.clone()).collect();
            if all.is_empty() {
                return Err(ActionError::Unavailable(
                    "mod-wallpaper.outputs.unknown".into(),
                ));
            }
            return Ok(all);
        }
        for n in names {
            if !self.outputs.iter().any(|o| &o.name == n) {
                return Err(ActionError::Invalid(
                    "mod-wallpaper.error.output_unknown".into(),
                ));
            }
        }
        Ok(names.to_vec())
    }

    /// Shows `path` on `targets`, then stores it (all-outputs replaces every output's own image).
    async fn set_on(
        &mut self,
        path: &str,
        targets: &[String],
        all: bool,
        transition: &str,
    ) -> Result<Value, ActionError> {
        // The backend is given the names when the request named some, and no names for all.
        let names: &[String] = if all { &[] } else { targets };
        if let Err(detail) = self.apply(path, names, transition).await {
            self.error = Some(("mod-wallpaper.error.apply".into(), Some(detail.clone())));
            return Err(ActionError::Unavailable("mod-wallpaper.error.apply".into()));
        }
        if all {
            self.state.all = Some(path.to_string());
            self.state.outputs.clear();
        } else {
            for name in targets {
                self.state.outputs.insert(
                    name.clone(),
                    OutputState {
                        path: path.to_string(),
                    },
                );
            }
        }
        self.error = None;
        self.save();
        self.schedule_all();
        Ok(json!({"path": path, "outputs": targets}))
    }

    /// The backend must answer before a request is applied: a missing or stopped daemon is started
    /// here (rate-limited), and a request that still cannot be served says why.
    async fn ready(&mut self) -> Result<(), ActionError> {
        if !self.status.up() {
            self.ensure_backend(true).await;
            if self.status.up() {
                if self.cfg.restore {
                    self.restore().await;
                }
                self.choices.choices_changed();
            }
        }
        match self.status.reason() {
            None => Ok(()),
            Some(reason) => Err(ActionError::Unavailable(reason.into())),
        }
    }

    async fn step(
        &mut self,
        forward: bool,
        random: bool,
        output: Option<String>,
    ) -> Result<Option<Value>, ActionError> {
        self.ready().await?;
        let scan = self.refresh_library().await;
        let list: Vec<PathBuf> = scan.entries.iter().map(|e| e.path.clone()).collect();
        if list.is_empty() {
            return Err(ActionError::Unavailable(
                "mod-wallpaper.library.empty".into(),
            ));
        }
        let current = match &output {
            Some(name) => self.path_of(name),
            None => self.state.all.clone(),
        };
        let current = current.map(PathBuf::from);
        let next = if random {
            rotate::random_pick(&list, current.as_deref(), &mut self.rng)
        } else {
            rotate::step(&list, current.as_deref(), forward)
        };
        let Some(next) = next else {
            return Err(ActionError::Unavailable(
                "mod-wallpaper.library.empty".into(),
            ));
        };
        let path = next.display().to_string();
        let names: Vec<String> = output.iter().cloned().collect();
        let targets = self.targets(&names)?;
        self.set_on(
            &path,
            &targets,
            names.is_empty(),
            &self.cfg.transition.clone(),
        )
        .await
        .map(Some)
    }

    fn favourite(
        &mut self,
        path: &Path,
        scheme: Option<String>,
        palette: Option<String>,
    ) -> Result<Option<Value>, ActionError> {
        let key = path.display().to_string();
        if let Some(i) = self.state.favourites.iter().position(|f| f.path == key) {
            self.state.favourites.remove(i);
            self.save();
            return Ok(Some(json!({"favourite": false})));
        }
        if !library::is_image(path) || !path.is_file() {
            return Err(ActionError::Invalid("mod-wallpaper.error.not_image".into()));
        }
        if scheme
            .as_deref()
            .is_some_and(|s| s != "dark" && s != "light")
            || palette.as_deref().is_some_and(|p| !is_slug(p))
        {
            return Err(ActionError::Invalid("mod-wallpaper.error.look".into()));
        }
        self.state.favourites.push(Favourite {
            path: key,
            scheme,
            palette,
        });
        self.save();
        Ok(Some(json!({"favourite": true})))
    }

    async fn restart(&mut self) -> Result<Option<Value>, ActionError> {
        if let Some(id) = BackendId::parse(&self.cfg.backend) {
            if self.status.up() {
                let _ = self
                    .run_cli(id.cli(), vec!["kill".into()], KILL_TIMEOUT)
                    .await;
            }
        }
        self.last_start = None;
        self.ensure_backend(true).await;
        if self.status.up() && self.cfg.restore {
            self.restore().await;
        }
        self.schedule_all();
        self.choices.choices_changed();
        match self.status.reason() {
            None => Ok(Some(json!({"available": true}))),
            Some(reason) => Err(ActionError::Unavailable(reason.into())),
        }
    }

    // ---- settings ----------------------------------------------------------------------------

    async fn reconfigure(&mut self) {
        let old = std::mem::replace(&mut self.cfg, Config::read(&self.settings));
        let new = self.cfg.clone();
        if old.backend != new.backend {
            // The old daemon is stopped (best effort) so two backends do not draw one background.
            if let Some(old_id) = BackendId::parse(&old.backend) {
                if self.status.up() {
                    let _ = self
                        .run_cli(old_id.cli(), vec!["kill".into()], KILL_TIMEOUT)
                        .await;
                }
            }
            self.last_start = None;
            self.ensure_backend(true).await;
            if self.status.up() && new.restore {
                self.restore().await;
            }
            self.schedule_all();
            self.choices.choices_changed();
            return;
        }
        if old.folders != new.folders {
            self.refresh_library().await;
        }
        if (old.fit.as_str(), old.crop_anchor.as_str())
            != (new.fit.as_str(), new.crop_anchor.as_str())
            && self.status.up()
        {
            self.reapply_all().await;
        }
        let rotation_changed = old.rotate_min != new.rotate_min
            || old.shuffle != new.shuffle
            || old.per_output != new.per_output;
        if rotation_changed {
            self.schedule_all();
        }
    }

    /// Every output's stored image, shown again with the current fit and no transition.
    async fn reapply_all(&mut self) {
        let plan: Vec<(String, String)> = self
            .outputs
            .iter()
            .filter_map(|o| self.path_of(&o.name).map(|p| (o.name.clone(), p)))
            .filter(|(_, p)| Path::new(p).is_file())
            .collect();
        for (name, path) in plan {
            if let Err(e) = self.apply(&path, &[name], "none").await {
                self.error = Some(("mod-wallpaper.error.apply".into(), Some(e)));
            }
        }
    }

    // ---- rotation ----------------------------------------------------------------------------

    fn rotation_on(&self) -> bool {
        self.cfg.rotate_min > 0 && !self.state.paused && self.status.up()
    }

    /// Arms the timers for the current settings: one due time for all outputs, or one per output.
    /// Nothing is armed when rotation is off, so an idle mod wakes for nothing.
    fn schedule_all(&mut self) {
        self.due.clear();
        if !self.rotation_on() {
            return;
        }
        let at = Instant::now() + self.interval();
        if self.cfg.per_output {
            for o in &self.outputs {
                self.due.insert(o.name.clone(), at);
            }
        } else {
            self.due.insert("*".into(), at);
        }
    }

    fn interval(&self) -> Duration {
        Duration::from_secs(60 * u64::from(self.cfg.rotate_min))
    }

    async fn tick(&mut self) {
        let now = Instant::now();
        let due: Vec<String> = self
            .due
            .iter()
            .filter(|(_, at)| **at <= now)
            .map(|(k, _)| k.clone())
            .collect();
        if due.is_empty() {
            return;
        }
        if !self.rotation_on() {
            self.due.clear();
            return;
        }
        let scan = self.refresh_library().await;
        let list: Vec<PathBuf> = scan.entries.iter().map(|e| e.path.clone()).collect();
        for key in due {
            if !list.is_empty() {
                let (current, names) = if key == "*" {
                    (self.state.all.clone(), Vec::new())
                } else {
                    (self.path_of(&key), vec![key.clone()])
                };
                let current = current.map(PathBuf::from);
                let next = if self.cfg.shuffle {
                    rotate::random_pick(&list, current.as_deref(), &mut self.rng)
                } else {
                    rotate::step(&list, current.as_deref(), true)
                };
                if let Some(next) = next {
                    let targets = names.clone();
                    let path = next.display().to_string();
                    let transition = self.cfg.transition.clone();
                    if let Err(e) = self
                        .set_on(&path, &targets, names.is_empty(), &transition)
                        .await
                    {
                        self.error =
                            Some(("mod-wallpaper.error.rotate".into(), Some(e.to_string())));
                    }
                }
            }
            // Re-armed even when the library is empty: the next tick looks again.
            self.due.insert(key, Instant::now() + self.interval());
        }
    }

    // ---- the document ------------------------------------------------------------------------

    fn save(&mut self) {
        if let Err(e) = state::save(&self.shared.dirs.state_file(), &self.state) {
            self.error = Some(("mod-wallpaper.state.write".into(), Some(e.to_string())));
        }
    }

    fn publish(&self) {
        let doc = self.document();
        self.shared.doc.send_if_modified(|current| {
            if *current == doc {
                false
            } else {
                *current = doc;
                true
            }
        });
    }

    /// `mod.wallpaper` (docs/ux/wallpaper.md, "Contract notes"). Every value is what is in effect:
    /// an output's `path` is the image the mod stored after the backend accepted it.
    pub fn document(&self) -> Value {
        // Top-level `available`: the backend is installed, so the mod can work (the quick tile is
        // shown). Whether its daemon answers now is `backend.available`, with the reason.
        let available = !matches!(self.status, Status::Missing(_));
        let mut backend = json!({"id": self.cfg.backend, "available": self.status.up()});
        if let Status::Ok(Some(version)) = &self.status {
            backend["version"] = json!(version);
        }
        if let Some(reason) = self.status.reason() {
            backend["reason"] = json!(reason);
        }
        let mut outputs = Map::new();
        for o in &self.outputs {
            outputs.insert(
                o.name.clone(),
                json!({
                    "path": self.path_of(&o.name),
                    "fit": self.cfg.fit,
                    "width": o.width,
                    "height": o.height,
                    "scale": o.scale,
                }),
            );
        }
        let mut doc = json!({
            "loaded": self.loaded,
            "available": available,
            "backend": backend,
            "outputs": outputs,
            "library": {"count": self.lib_count, "folders": self.lib_folders},
            "rotation": {
                "on": self.rotation_on(),
                "interval_min": self.cfg.rotate_min,
                "paused": self.state.paused,
                "order": self.cfg.order_name(),
                "per_output": self.cfg.per_output,
                "next_at": self.next_at_ms(),
            },
            "favourites": self.state.favourites,
        });
        if let Some((key, detail)) = &self.error {
            doc["error"] = json!({"key": key, "detail": detail});
        }
        doc
    }

    /// The earliest rotation as milliseconds since the epoch, for the document.
    fn next_at_ms(&self) -> Option<u64> {
        let at = *self.due.values().min()?;
        let wall = SystemTime::now() + at.saturating_duration_since(Instant::now());
        wall.duration_since(UNIX_EPOCH)
            .ok()
            .map(|d| u64::try_from(d.as_millis()).unwrap_or(u64::MAX))
    }
}

async fn wait_until(due: Option<Instant>) {
    match due {
        Some(at) => tokio::time::sleep_until(at).await,
        None => std::future::pending().await,
    }
}

fn describe(e: &ExecError) -> String {
    match e {
        ExecError::NotFound(p) => format!("not found: {p}"),
        ExecError::Timeout => "timeout".into(),
        ExecError::Failed(m) => m.clone(),
    }
}

/// A look's palette name: lowercase letters, digits, `-` and `_`, 1 to 40 of them.
fn is_slug(s: &str) -> bool {
    (1..=40).contains(&s.len())
        && s.bytes()
            .all(|b| b.is_ascii_lowercase() || b.is_ascii_digit() || b == b'-' || b == b'_')
}
