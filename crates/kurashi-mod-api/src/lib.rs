//! The API a first-party native mod codes against (K26, docs/MODS.md "Native mods"). A mod crate
//! depends on this crate and never on the daemon. `NativeMod::enable` declares what the mod
//! registers through a [`ModCtx`]; the daemon applies those registrations only after `enable`
//! returned `Ok`, so a refused enable registers nothing. Settings arrive through [`Settings`]
//! (`mods.<id>.<key>`, K22). Faces and choice sources (K28) work the same way: a handle the mod
//! keeps raises or clears through [`Hooks`], and the daemon ignores it once the enable is over.
//! Background jobs (I23) are not registrations: [`ModCtx::background`] declares one, and the daemon
//! takes it with [`ModCtx::take_jobs`] and runs it while the mod is on and its setting wants it.
//! Host processes (K38, MODS.md "Host processes") are declared with [`ModCtx::host`]: the daemon starts
//! and supervises the program, and the mod starts and stops it through a [`HostHandle`]. A mod writes its
//! own settings through a [`SettingsWriter`] (K38: the web dock's view toggle).

use std::collections::{BTreeMap, BTreeSet};
use std::future::Future;
use std::pin::Pin;
use std::sync::Arc;
use std::time::Duration;

use serde_json::Value;
use tokio::sync::watch;

/// A mod's settings in effect, keyed by the setting's own key (without `mods.<id>.`).
pub type Values = BTreeMap<String, Value>;

/// What a service or an action returns; the daemon polls it on its runtime.
pub type BoxFuture<T> = Pin<Box<dyn Future<Output = T> + Send + 'static>>;

/// Publishes the state of a mod's document. A publish after the service stopped is dropped.
pub type Publish = Arc<dyn Fn(Value) + Send + Sync>;

/// A service body. It runs while its document has a subscriber (rule 5) and publishes the state;
/// it ends when it has nothing more to do, and the daemon stops it on the last unsubscribe.
pub type ServiceFn = Arc<dyn Fn(Publish, Settings) -> BoxFuture<()> + Send + Sync>;

/// An action handler, invoked by id like every action (ARCHITECTURE §6).
pub type ActionFn =
    Arc<dyn Fn(Value) -> BoxFuture<Result<Option<Value>, ActionError>> + Send + Sync>;

/// A choice source's function: the options it offers now (K28 (3), I9). The daemon calls it on
/// enable and after [`ChoicesHandle::choices_changed`]; it must not call that itself.
pub type ChoicesFn = Arc<dyn Fn() -> Vec<Choice> + Send + Sync>;

/// A background job's body. The daemon starts it again each time its setting turns the job on, so
/// it is a `Fn` and not an `FnOnce`.
pub type JobFn = Arc<dyn Fn(JobCtx) -> BoxFuture<()> + Send + Sync>;

/// Where a job's [`JobCtx::set_active`] goes: the daemon's end of it, made for one run of the job (I48).
pub type ActiveFn = Arc<dyn Fn(bool) + Send + Sync>;

/// A program a native mod runs next to the daemon (K38, MODS.md "Host processes"). `binary` is a file name
/// looked up in the daemon's `PATH` and must be declared as `exec:<binary>`. `args` and the values of `env`
/// may name `{mod_dir}`, `{data_dir}`, `{cache_dir}` and `{state_dir}`; the daemon expands them.
#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct HostSpec {
    pub binary: String,
    pub args: Vec<String>,
    pub env: BTreeMap<String, String>,
}

/// What a host process is doing (MODS.md "Host processes"). The reasons of `Missing` and `Failed` are i18n keys.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum HostState {
    /// Not running: never started, stopped, or its mod is off.
    Off,
    /// Running, and no scoped connection has said hello with its token yet.
    Starting,
    /// Running and connected with its scope.
    Ready,
    /// It stopped twice within ten minutes; `detail` names the exit status and the log file.
    Failed { reason: String, detail: String },
    /// Its program is not on `PATH`.
    Missing,
}

impl HostState {
    /// The state's name in documents: `off`, `starting`, `ready`, `failed` or `missing`.
    pub fn name(&self) -> &'static str {
        match self {
            Self::Off => "off",
            Self::Starting => "starting",
            Self::Ready => "ready",
            Self::Failed { .. } => "failed",
            Self::Missing => "missing",
        }
    }

    /// The i18n key that says why the host is in this state, for the states that have one.
    pub fn reason(&self) -> Option<&str> {
        match self {
            Self::Failed { reason, .. } => Some(reason),
            Self::Missing => Some("mods.host.missing"),
            _ => None,
        }
    }

    /// The detail of a `Failed` state (its exit status and log file), if there is one.
    pub fn detail(&self) -> Option<&str> {
        match self {
            Self::Failed { detail, .. } => Some(detail),
            _ => None,
        }
    }

    /// Whether a process of the host runs now (starting or ready).
    pub fn is_running(&self) -> bool {
        matches!(self, Self::Starting | Self::Ready)
    }
}

/// Starts and stops one host process of a mod, and reads its state. Cheap to clone. Calls after the mod is
/// off do nothing; the state reads `Off` then.
#[derive(Clone)]
pub struct HostHandle {
    hooks: Arc<dyn Hooks>,
    name: String,
    state: Arc<watch::Sender<HostState>>,
}

impl HostHandle {
    pub fn name(&self) -> &str {
        &self.name
    }

    /// Starts the process unless it runs (idempotent). A `Missing` or `Failed` host is tried again.
    pub fn start(&self) {
        self.hooks.host_start(&self.name);
    }

    /// Stops the process: SIGTERM to its group, SIGKILL after 3 s; the state is `Off` at once.
    pub fn stop(&self) {
        self.hooks.host_stop(&self.name);
    }

    /// The host's state, from now on.
    pub fn state(&self) -> watch::Receiver<HostState> {
        self.state.subscribe()
    }
}

/// Why a setting write was refused.
#[derive(Debug, Clone, PartialEq, Eq, thiserror::Error)]
pub enum SettingsError {
    /// The key is not a setting of this mod in its manifest.
    #[error("{0} is not a setting of this mod")]
    Unknown(String),
    /// The config refused the write (forced, or an invalid value); the config's error code.
    #[error("{0}")]
    Rejected(String),
    /// No config store is running, or the mod is off.
    #[error("the settings are not available")]
    Unavailable,
}

impl SettingsError {
    /// The i18n key (or the config's own key) that says why the write was refused.
    pub fn i18n_key(&self) -> &str {
        match self {
            Self::Unknown(_) => "mods.error.not_declared",
            Self::Rejected(key) => key,
            Self::Unavailable => "mods.error.setting_unavailable",
        }
    }
}

/// Writes the mod's own settings (`mods.<id>.<key>`) in the user layer, one undoable transaction each
/// (K38, MODS.md "Host processes"). Cheap to clone.
#[derive(Clone)]
pub struct SettingsWriter {
    hooks: Arc<dyn Hooks>,
}

impl SettingsWriter {
    pub async fn set(&self, key: &str, value: Value) -> Result<(), SettingsError> {
        self.hooks.set_setting(key, value)
    }
}

/// A first-party mod linked into the daemon. `id` is the `mod.toml` id and directory name.
pub trait NativeMod: Send + Sync + 'static {
    fn id(&self) -> &'static str;
    /// Declares what the mod registers. Called on every enable; nothing it registers outlives the
    /// disable. An `Err`, or a registration the manifest does not declare, enables nothing.
    fn enable(&self, ctx: &mut ModCtx) -> Result<(), ModError>;
}

/// Why an enable was refused. The i18n key (`mods.error.*`) is what Settings shows.
#[derive(Debug, Clone, PartialEq, Eq, thiserror::Error)]
pub enum ModError {
    /// The manifest's `provides` does not list this registration (`service:<id>`, `action:<id>`,
    /// `island-face:<name>`, `choices:<source>`).
    #[error("{0} is not declared in provides")]
    NotDeclared(String),
    /// The id is already registered: twice in one enable, or held by the daemon or another mod.
    #[error("{0} is already registered")]
    Duplicate(String),
    /// A host process runs a program the manifest does not declare as `exec:<binary>` (K38).
    #[error("{0} is not declared in capabilities")]
    NotGranted(String),
    /// The mod failed for its own reason.
    #[error("{0}")]
    Failed(String),
    /// The manifest declares daemon code (a service, action, island face, choice source, job or host) and
    /// this build links no code for the mod. Set by the daemon, not by the mod (B15).
    #[error("the mod's daemon code is not linked into this build")]
    NotBuilt,
}

impl ModError {
    pub fn i18n_key(&self) -> &'static str {
        match self {
            Self::NotDeclared(_) | Self::NotGranted(_) => "mods.error.not_declared",
            Self::Duplicate(_) => "mods.error.duplicate",
            Self::Failed(_) => "mods.error.enable_failed",
            Self::NotBuilt => "mods.error.not_built",
        }
    }
}

/// Action failures, the kinds an action may answer with (PROTOCOL §7).
#[derive(Debug, Clone, PartialEq, Eq, thiserror::Error)]
pub enum ActionError {
    #[error("{0}")]
    Invalid(String),
    #[error("{0}")]
    Unavailable(String),
    #[error("{0}")]
    Internal(String),
}

/// One option of a choice source (K28 (3), I9). `value` is what a setting stores; `label` is an
/// i18n key or plain text. An option that cannot work now is shown but not selectable: `enabled`
/// is false and `reason` is an i18n key that says why (a backend that is not installed).
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Choice {
    pub value: String,
    pub label: String,
    pub enabled: bool,
    pub reason: Option<String>,
}

impl Choice {
    /// An option that can work now.
    pub fn new(value: &str, label: &str) -> Self {
        Self {
            value: value.into(),
            label: label.into(),
            enabled: true,
            reason: None,
        }
    }

    /// The same option, not selectable now; `reason` is an i18n key.
    pub fn unavailable(mut self, reason: &str) -> Self {
        self.enabled = false;
        self.reason = Some(reason.into());
        self
    }
}

/// How a mod's island face is shown (K24, K28 (2)).
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct FaceSpec {
    /// Shown for `ttl_s` seconds after each raise, then the arbiter falls back, as an OSD does.
    /// Otherwise the face is shown while its relevance is above zero.
    pub transient: bool,
    /// The transient's lifetime in seconds. Ignored for a relevance face.
    pub ttl_s: u32,
}

/// What a face handle asks of the daemon.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum FaceUpdate {
    /// Relevance `0..=100` (0 = nothing to show). `ttl` makes the signal a transient that runs out.
    Raise {
        relevance: u8,
        ttl: Option<Duration>,
    },
    /// Takes back the face's relevance and any running transient.
    Clear,
}

/// The daemon's end of the handles a mod keeps ([`FaceHandle`], [`ChoicesHandle`]). The daemon
/// implements it once per enable and ignores calls after that enable is over; a mod never does.
pub trait Hooks: Send + Sync {
    /// Face `face` (declared by the mod) is raised or cleared.
    fn face(&self, face: &str, update: FaceUpdate);
    /// Choice source `source` offers different options now: ask its function again.
    fn choices_changed(&self, source: &str);
    /// Host process `host` of the mod is to start (idempotent; K38). Nothing when the mod is off.
    fn host_start(&self, _host: &str) {}
    /// Host process `host` of the mod is to stop (K38). Nothing when the mod is off.
    fn host_stop(&self, _host: &str) {}
    /// The mod's own setting `key` (without `mods.<id>.`) takes `value` in the user layer (K38). The daemon
    /// refuses keys the manifest does not declare; a `Hooks` without a config behind it refuses everything.
    fn set_setting(&self, _key: &str, _value: Value) -> Result<(), SettingsError> {
        Err(SettingsError::Unavailable)
    }
    /// The mod's contribution to slot `slot` needs setup (`reason`, an i18n key) or not (`None`) (K28, row 72).
    fn slot_reason(&self, _slot: &str, _reason: Option<&str>) {}
}

/// The mod's contribution to one core view slot (K28, row 72). A contribution that needs setup before it has
/// content — weather without a saved place — stays in the view and shows its call to action: `set_reason` puts
/// the reason (an i18n key) into `runtime.slots`, `None` takes it back. Cheap to clone.
#[derive(Clone)]
pub struct SlotHandle {
    hooks: Arc<dyn Hooks>,
    slot: String,
}

impl SlotHandle {
    pub fn set_reason(&self, reason: Option<&str>) {
        self.hooks.slot_reason(&self.slot, reason);
    }
}

/// Raises and clears one island face of a mod (K24). Cheap to clone, so an action or a service can
/// own a copy. A raise while the mod is off does nothing.
#[derive(Clone)]
pub struct FaceHandle {
    hooks: Arc<dyn Hooks>,
    name: String,
    spec: FaceSpec,
}

impl FaceHandle {
    pub fn name(&self) -> &str {
        &self.name
    }

    /// Shows the face at `relevance` (0..=100). A transient face runs its TTL from this call.
    pub fn raise(&self, relevance: u8) {
        let ttl = self
            .spec
            .transient
            .then(|| Duration::from_secs(u64::from(self.spec.ttl_s)));
        self.hooks
            .face(&self.name, FaceUpdate::Raise { relevance, ttl });
    }

    /// Takes the face's signals back; the arbiter shows what else is due.
    pub fn clear(&self) {
        self.hooks.face(&self.name, FaceUpdate::Clear);
    }
}

/// Tells the daemon that a choice source's options changed (K28 (3)).
#[derive(Clone)]
pub struct ChoicesHandle {
    hooks: Arc<dyn Hooks>,
    source: String,
}

impl ChoicesHandle {
    /// The daemon asks the source's function again and republishes the settings that name it.
    pub fn choices_changed(&self) {
        self.hooks.choices_changed(&self.source);
    }
}

/// What `enable` registers, applied by the daemon once `enable` returned `Ok`.
pub enum Registration {
    /// Document `mod.<id>`, backed by a service that runs while it has a subscriber.
    Service {
        id: String,
        initial: Value,
        run: ServiceFn,
    },
    /// Action `<id>`; `label` is an i18n key.
    Action {
        id: String,
        label: String,
        handler: ActionFn,
    },
    /// Island face `name`: registered with the arbiter; its signals come through the handle.
    Face { name: String },
    /// Choice source `source`, offered to the settings that name it.
    Choices { source: String, options: ChoicesFn },
}

/// A host process a mod declared (K38): taken with [`ModCtx::take_hosts`], like a background job. The daemon runs
/// `spec` when the mod starts it, and writes the state to `state`, which the mod's handle reads.
pub struct HostDecl {
    pub name: String,
    pub spec: HostSpec,
    pub state: Arc<watch::Sender<HostState>>,
}

/// What a background job gets when the daemon starts it: its settings, live like a service's, and the
/// way to say whether it has work now ([`JobCtx::set_active`]).
pub struct JobCtx {
    settings: Settings,
    active: ActiveFn,
}

impl JobCtx {
    /// For the daemon: the job's settings feed, and the sink `set_active` reaches for this run.
    pub fn with_active(settings: Settings, active: ActiveFn) -> Self {
        Self { settings, active }
    }

    /// A job context with no daemon behind it, for a test that drives a job body: `set_active` does nothing.
    pub fn new(settings: Settings) -> Self {
        Self::with_active(settings, Arc::new(|_| {}))
    }

    pub fn settings(&self) -> &Settings {
        &self.settings
    }

    /// Says whether the job has work now (I48). A job with nothing to do (a paused watch) keeps running and
    /// its body stays alive, but its `reason` leaves the mod's `running_reasons` until it has work again, so
    /// Settings never says "running" about a job that does nothing. A job starts out with work.
    pub fn set_active(&self, active: bool) {
        (self.active)(active);
    }
}

/// A background job a mod declared (`job:<name>`, I23). The daemon takes it with
/// [`ModCtx::take_jobs`] and runs it while the mod is enabled and the bool setting `wanted_by` is
/// true; it is cancelled when either stops. While it runs and has work ([`JobCtx::set_active`]),
/// `reason` (an i18n key) is in the `mods` document's `running_reasons` (Settings: "Running now").
pub struct Job {
    pub name: String,
    pub reason: String,
    pub wanted_by: String,
    pub run: JobFn,
}

/// The settings of a mod that is enabled. Reads never block. `changed` resolves on the next
/// change of any setting and is `false` once the mod is disabled.
#[derive(Clone)]
pub struct Settings {
    rx: watch::Receiver<Values>,
}

impl Settings {
    /// For the daemon: the receiving end of the mod's settings feed.
    pub fn new(rx: watch::Receiver<Values>) -> Self {
        Self { rx }
    }

    pub fn get(&self, key: &str) -> Option<Value> {
        self.rx.borrow().get(key).cloned()
    }

    pub async fn changed(&mut self) -> bool {
        self.rx.changed().await.is_ok()
    }
}

/// K59: what the host does to a picture before a wallpaper mod shows it (the material texture baked in, when the user
/// chose the wallpaper as a texture scope). The mod shows the returned file and keeps its own path everywhere else.
pub trait PictureFilter: Send + Sync {
    /// The file to show for `picture` on an output of `size` device pixels at `scale`: the picture itself when nothing
    /// applies. Blocking (it may decode and encode): call it from a blocking thread.
    fn filter(&self, picture: &std::path::Path, size: (u32, u32), scale: f32)
    -> std::path::PathBuf;
    /// Changes whenever the filter would give other files (a texture, its light, the scope): show the pictures again.
    fn changes(&self) -> watch::Receiver<u64>;
}

/// The registrations of one enable. Each call checks the manifest's `provides` (the list the daemon
/// passes in, e.g. `action:hello.*`); a call that fails is remembered, and `finish` fails with it
/// even when the mod ignored the error.
pub struct ModCtx {
    provides: Vec<String>,
    capabilities: Vec<String>,
    settings: Settings,
    hooks: Arc<dyn Hooks>,
    regs: Vec<Registration>,
    jobs: Vec<Job>,
    hosts: Vec<HostDecl>,
    seen: BTreeSet<String>,
    refused: Vec<ModError>,
    picture_filter: Option<Arc<dyn PictureFilter>>,
}

impl ModCtx {
    /// For the daemon: `provides` as the manifest lists them, `settings` as in effect now, and the
    /// `hooks` the handles of this enable call.
    pub fn new(provides: &[String], settings: Settings, hooks: Arc<dyn Hooks>) -> Self {
        Self {
            provides: provides.to_vec(),
            capabilities: Vec::new(),
            settings,
            hooks,
            regs: Vec::new(),
            jobs: Vec::new(),
            hosts: Vec::new(),
            seen: BTreeSet::new(),
            refused: Vec::new(),
            picture_filter: None,
        }
    }

    /// The host's picture filter (K59), handed to every mod; only a wallpaper mod has a use for it.
    pub fn with_picture_filter(mut self, filter: Option<Arc<dyn PictureFilter>>) -> Self {
        self.picture_filter = filter;
        self
    }

    pub fn picture_filter(&self) -> Option<Arc<dyn PictureFilter>> {
        self.picture_filter.clone()
    }

    /// The manifest's capabilities, which a host process checks its `exec:<binary>` against (K38).
    pub fn with_capabilities(mut self, capabilities: &[String]) -> Self {
        self.capabilities = capabilities.to_vec();
        self
    }

    /// Host process `name` (declared as `host:<name>`, K38, MODS.md "Host processes"): the program `spec`
    /// names, which must be declared as `exec:<binary>`. The daemon registers it when the enable succeeds;
    /// nothing runs until the mod calls [`HostHandle::start`].
    pub fn host(&mut self, name: &str, spec: HostSpec) -> Result<HostHandle, ModError> {
        self.claim("host", name)?;
        let granted = format!("exec:{}", spec.binary);
        let is_file_name = !spec.binary.is_empty() && !spec.binary.contains('/');
        if !is_file_name || !self.capabilities.contains(&granted) {
            return Err(self.refuse(ModError::NotGranted(granted)));
        }
        let state = Arc::new(watch::channel(HostState::Off).0);
        self.hosts.push(HostDecl {
            name: name.into(),
            spec,
            state: state.clone(),
        });
        Ok(HostHandle {
            hooks: self.hooks.clone(),
            name: name.into(),
            state,
        })
    }

    /// The host processes of this enable, for the daemon to run. Taken before [`ModCtx::finish`]: a host left
    /// behind would never run, so `finish` refuses it (as it does a job).
    pub fn take_hosts(&mut self) -> Vec<HostDecl> {
        std::mem::take(&mut self.hosts)
    }

    /// Writes this mod's settings (K38). Each write is one undoable transaction of the user layer.
    pub fn settings_writer(&self) -> SettingsWriter {
        SettingsWriter {
            hooks: self.hooks.clone(),
        }
    }

    /// Background job `name` (I23, `job:<name>`): runs while the mod is enabled and its bool setting
    /// `wanted_by` is true, and is cancelled when either stops. It shows in the `mods` document as
    /// `reason` (an i18n key) while it runs, so a poll the user can see is never unreported.
    pub fn background<F, Fut>(
        &mut self,
        name: &str,
        reason: &str,
        wanted_by: &str,
        run: F,
    ) -> Result<(), ModError>
    where
        F: Fn(JobCtx) -> Fut + Send + Sync + 'static,
        Fut: Future<Output = ()> + Send + 'static,
    {
        self.claim("job", name)?;
        let run: JobFn = Arc::new(move |ctx| Box::pin(run(ctx)));
        self.jobs.push(Job {
            name: name.into(),
            reason: reason.into(),
            wanted_by: wanted_by.into(),
            run,
        });
        Ok(())
    }

    /// The background jobs of this enable, for the daemon to run. Taken before [`ModCtx::finish`]:
    /// a job that is left behind would never run, so `finish` refuses it.
    pub fn take_jobs(&mut self) -> Vec<Job> {
        std::mem::take(&mut self.jobs)
    }

    pub fn settings(&self) -> &Settings {
        &self.settings
    }

    /// Document `mod.<id>` with its initial state, and the service that keeps it current.
    pub fn service<F, Fut>(&mut self, id: &str, initial: Value, run: F) -> Result<(), ModError>
    where
        F: Fn(Publish, Settings) -> Fut + Send + Sync + 'static,
        Fut: Future<Output = ()> + Send + 'static,
    {
        self.claim("service", id)?;
        let run: ServiceFn = Arc::new(move |publish, settings| Box::pin(run(publish, settings)));
        self.regs.push(Registration::Service {
            id: id.into(),
            initial,
            run,
        });
        Ok(())
    }

    /// Action `id`; `label` is its i18n key.
    pub fn action<F, Fut>(&mut self, id: &str, label: &str, handler: F) -> Result<(), ModError>
    where
        F: Fn(Value) -> Fut + Send + Sync + 'static,
        Fut: Future<Output = Result<Option<Value>, ActionError>> + Send + 'static,
    {
        self.claim("action", id)?;
        let handler: ActionFn = Arc::new(move |args| Box::pin(handler(args)));
        self.regs.push(Registration::Action {
            id: id.into(),
            label: label.into(),
            handler,
        });
        Ok(())
    }

    /// Island face `name` (declared as `island-face:<name>`, K28 (2)). The daemon registers it with
    /// the core arbiter when the enable succeeds and takes it off on disable. The mod's components
    /// are `qml/Face.qml` (compact) and `qml/FaceExpanded.qml` (expanded).
    pub fn face(&mut self, name: &str, spec: FaceSpec) -> Result<FaceHandle, ModError> {
        self.claim("island-face", name)?;
        self.regs.push(Registration::Face { name: name.into() });
        Ok(FaceHandle {
            hooks: self.hooks.clone(),
            name: name.into(),
            spec,
        })
    }

    /// Choice source `source` (declared as `choices:<source>`, K28 (3)). A setting with
    /// `choices_from = "<source>"` offers what `options` returns while the mod is enabled. Its
    /// values are inert (`settings.choice.unavailable`) once the mod is off.
    pub fn choices<F>(&mut self, source: &str, options: F) -> Result<ChoicesHandle, ModError>
    where
        F: Fn() -> Vec<Choice> + Send + Sync + 'static,
    {
        self.claim("choices", source)?;
        self.regs.push(Registration::Choices {
            source: source.into(),
            options: Arc::new(options),
        });
        Ok(ChoicesHandle {
            hooks: self.hooks.clone(),
            source: source.into(),
        })
    }

    /// A handle on the mod's contribution to slot `name` (manifest `slot:<name>`; K28, row 72).
    pub fn slot(&mut self, name: &str) -> Result<SlotHandle, ModError> {
        self.claim("slot", name)?;
        Ok(SlotHandle {
            hooks: self.hooks.clone(),
            slot: name.into(),
        })
    }

    /// The registrations for the daemon to apply, or the first refused one. Jobs not taken with
    /// [`ModCtx::take_jobs`] refuse the enable: they would never run.
    pub fn finish(self) -> Result<Vec<Registration>, ModError> {
        if let Some(e) = self.refused.into_iter().next() {
            return Err(e);
        }
        if !self.jobs.is_empty() {
            return Err(ModError::Failed(
                "background jobs are taken with take_jobs before finish".into(),
            ));
        }
        if !self.hosts.is_empty() {
            return Err(ModError::Failed(
                "host processes are taken with take_hosts before finish".into(),
            ));
        }
        Ok(self.regs)
    }

    fn claim(&mut self, kind: &str, id: &str) -> Result<(), ModError> {
        let key = format!("{kind}:{id}");
        if !self.declares(kind, id) {
            return Err(self.refuse(ModError::NotDeclared(key)));
        }
        if !self.seen.insert(key.clone()) {
            return Err(self.refuse(ModError::Duplicate(key)));
        }
        Ok(())
    }

    fn refuse(&mut self, e: ModError) -> ModError {
        self.refused.push(e.clone());
        e
    }

    /// `kind:id` is declared exactly, or by a `kind:<prefix>.*` glob that covers `id`.
    fn declares(&self, kind: &str, id: &str) -> bool {
        self.provides.iter().any(|p| {
            let Some(pid) = p.strip_prefix(kind).and_then(|rest| rest.strip_prefix(':')) else {
                return false;
            };
            match pid.strip_suffix(".*") {
                Some(prefix) => id
                    .strip_prefix(prefix)
                    .is_some_and(|rest| rest.starts_with('.')),
                None => pid == id,
            }
        })
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;
    use std::sync::Mutex;

    /// Records what the handles tell the daemon.
    #[derive(Default)]
    struct Record {
        calls: Mutex<Vec<String>>,
    }

    impl Hooks for Record {
        fn face(&self, face: &str, update: FaceUpdate) {
            self.calls
                .lock()
                .unwrap()
                .push(format!("face {face} {update:?}"));
        }

        fn choices_changed(&self, source: &str) {
            self.calls.lock().unwrap().push(format!("choices {source}"));
        }

        fn slot_reason(&self, slot: &str, reason: Option<&str>) {
            self.calls
                .lock()
                .unwrap()
                .push(format!("slot {slot} {reason:?}"));
        }
    }

    fn ctx(provides: &[&str]) -> ModCtx {
        let provides: Vec<String> = provides.iter().map(|p| p.to_string()).collect();
        let (_, rx) = watch::channel(Values::new());
        ModCtx::new(&provides, Settings::new(rx), Arc::new(Record::default()))
    }

    #[test]
    fn actions_match_declared_ids_and_globs_only() {
        let mut c = ctx(&["action:hello.*", "action:quit"]);
        assert!(c.action("hello.ping", "l", noop_action).is_ok());
        assert!(c.action("quit", "l", noop_action).is_ok());
        assert_eq!(
            c.action("hello", "l", noop_action),
            Err(ModError::NotDeclared("action:hello".into()))
        );
        assert_eq!(
            c.action("hellox.ping", "l", noop_action),
            Err(ModError::NotDeclared("action:hellox.ping".into()))
        );
        assert_eq!(
            c.service("hello", Value::Null, |_, _| async {}),
            Err(ModError::NotDeclared("service:hello".into()))
        );
    }

    #[test]
    fn a_duplicate_or_ignored_refusal_fails_the_whole_enable() {
        let mut c = ctx(&["action:hello.*"]);
        c.action("hello.a", "l", noop_action).unwrap();
        assert_eq!(
            c.action("hello.a", "l", noop_action),
            Err(ModError::Duplicate("action:hello.a".into()))
        );
        // The mod ignores the error: finish still refuses.
        let _ = c.action("other.x", "l", noop_action);
        assert_eq!(
            c.finish().map(|_| ()),
            Err(ModError::Duplicate("action:hello.a".into()))
        );
        let mut c = ctx(&["action:hello.*"]);
        let _ = c.action("other.x", "l", noop_action);
        assert_eq!(
            c.finish().map(|_| ()),
            Err(ModError::NotDeclared("action:other.x".into()))
        );
    }

    #[test]
    fn faces_and_choice_sources_need_their_provide() {
        let spec = FaceSpec {
            transient: false,
            ttl_s: 0,
        };
        let mut c = ctx(&["island-face:weather", "choices:weather.units"]);
        assert!(c.face("weather", spec).is_ok());
        assert!(c.choices("weather.units", Vec::new).is_ok());
        assert_eq!(
            c.face("clock", spec).err(),
            Some(ModError::NotDeclared("island-face:clock".into()))
        );
        assert_eq!(
            c.choices("weather.other", Vec::new).err(),
            Some(ModError::NotDeclared("choices:weather.other".into()))
        );
        assert_eq!(
            c.face("weather", spec).err(),
            Some(ModError::Duplicate("island-face:weather".into()))
        );
        assert!(c.finish().is_err(), "a refused face fails the enable");
    }

    #[test]
    fn handles_raise_clear_and_ask_for_a_ttl_only_when_transient() {
        let rec = Arc::new(Record::default());
        let provides = ["island-face:a".to_string(), "island-face:b".to_string()];
        let (_, rx) = watch::channel(Values::new());
        let mut c = ModCtx::new(&provides, Settings::new(rx), rec.clone());
        let relevance = c
            .face(
                "a",
                FaceSpec {
                    transient: false,
                    ttl_s: 9,
                },
            )
            .unwrap();
        let osd = c
            .face(
                "b",
                FaceSpec {
                    transient: true,
                    ttl_s: 3,
                },
            )
            .unwrap();
        relevance.raise(40);
        relevance.clear();
        osd.raise(0);
        assert_eq!(
            rec.calls.lock().unwrap().as_slice(),
            [
                "face a Raise { relevance: 40, ttl: None }",
                "face a Clear",
                "face b Raise { relevance: 0, ttl: Some(3s) }",
            ]
        );
    }

    #[test]
    fn a_background_job_is_declared_taken_and_never_left_behind() {
        let mut c = ctx(&["job:tick"]);
        c.background("tick", "mods.running.tick", "on", |_| async {})
            .unwrap();
        assert!(
            matches!(c.finish(), Err(ModError::Failed(_))),
            "a job the daemon does not take refuses the enable"
        );

        let mut c = ctx(&["job:tick"]);
        assert_eq!(
            c.background("tock", "mods.running.tock", "on", |_| async {}),
            Err(ModError::NotDeclared("job:tock".into()))
        );
        assert!(matches!(c.finish(), Err(ModError::NotDeclared(_))));

        let mut c = ctx(&["job:tick"]);
        c.background("tick", "mods.running.tick", "on", |_| async {})
            .unwrap();
        assert_eq!(
            c.background("tick", "mods.running.tick", "on", |_| async {}),
            Err(ModError::Duplicate("job:tick".into()))
        );

        let mut c = ctx(&["job:tick"]);
        c.background("tick", "mods.running.tick", "on", |_| async {})
            .unwrap();
        let jobs = c.take_jobs();
        assert_eq!(jobs.len(), 1);
        assert_eq!(jobs[0].name, "tick");
        assert_eq!(jobs[0].wanted_by, "on");
        assert!(c.finish().unwrap().is_empty());
    }

    #[test]
    fn set_active_reaches_the_sink_of_its_run() {
        let seen = Arc::new(Mutex::new(Vec::new()));
        let sink = seen.clone();
        let (_, rx) = watch::channel(Values::new());
        let ctx = JobCtx::with_active(
            Settings::new(rx),
            Arc::new(move |active| sink.lock().unwrap().push(active)),
        );
        ctx.set_active(false);
        ctx.set_active(true);
        assert_eq!(*seen.lock().unwrap(), [false, true]);
        // A context with no daemon behind it takes the call and does nothing with it.
        let (_, rx) = watch::channel(Values::new());
        JobCtx::new(Settings::new(rx)).set_active(false);
    }

    #[test]
    fn choices_and_their_changes_reach_the_hooks() {
        let rec = Arc::new(Record::default());
        let provides = ["choices:demo.pick".to_string()];
        let (_, rx) = watch::channel(Values::new());
        let mut c = ModCtx::new(&provides, Settings::new(rx), rec.clone());
        let handle = c
            .choices("demo.pick", || {
                vec![
                    Choice::new("a", "A"),
                    Choice::new("b", "B").unavailable("demo.missing"),
                ]
            })
            .unwrap();
        handle.choices_changed();
        assert_eq!(rec.calls.lock().unwrap().as_slice(), ["choices demo.pick"]);
        let regs = c.finish().unwrap();
        let [Registration::Choices { options, .. }] = regs.as_slice() else {
            panic!("one choice source is registered");
        };
        let offered = options();
        assert!(offered[0].enabled);
        assert_eq!(offered[1].reason.as_deref(), Some("demo.missing"));
        assert!(!offered[1].enabled);
    }

    /// Row 72: a declared slot gives a handle whose reasons reach the hooks; an undeclared one is refused.
    #[test]
    fn a_slot_handle_reports_its_reason() {
        let rec = Arc::new(Record::default());
        let provides = ["slot:clock.expanded.aside".to_string()];
        let (_, rx) = watch::channel(Values::new());
        let mut c = ModCtx::new(&provides, Settings::new(rx), rec.clone());
        let slot = c.slot("clock.expanded.aside").unwrap();
        slot.set_reason(Some("demo.no_place"));
        slot.set_reason(None);
        assert_eq!(
            rec.calls.lock().unwrap().as_slice(),
            [
                "slot clock.expanded.aside Some(\"demo.no_place\")",
                "slot clock.expanded.aside None"
            ]
        );
        assert!(c.slot("quick.tiles").is_err(), "not declared");
    }

    /// Records what a host handle and a settings writer ask of the daemon.
    #[derive(Default)]
    struct HostRecord {
        calls: Mutex<Vec<String>>,
    }

    impl Hooks for HostRecord {
        fn face(&self, _: &str, _: FaceUpdate) {}

        fn choices_changed(&self, _: &str) {}

        fn host_start(&self, host: &str) {
            self.calls.lock().unwrap().push(format!("start {host}"));
        }

        fn host_stop(&self, host: &str) {
            self.calls.lock().unwrap().push(format!("stop {host}"));
        }

        fn set_setting(&self, key: &str, value: Value) -> Result<(), SettingsError> {
            self.calls
                .lock()
                .unwrap()
                .push(format!("set {key} {value}"));
            Ok(())
        }
    }

    fn host_spec(binary: &str) -> HostSpec {
        HostSpec {
            binary: binary.into(),
            args: vec!["-p".into(), "{mod_dir}/host.qml".into()],
            env: BTreeMap::new(),
        }
    }

    #[test]
    fn a_host_needs_its_provide_and_its_exec_capability() {
        let (_, rx) = watch::channel(Values::new());
        let provides = ["host:web".to_string()];
        let caps = ["exec:qs-webengine".to_string()];
        let mut c = ModCtx::new(
            &provides,
            Settings::new(rx),
            Arc::new(HostRecord::default()),
        )
        .with_capabilities(&caps);
        assert!(c.host("web", host_spec("qs-webengine")).is_ok());
        assert_eq!(
            c.host("web", host_spec("qs-webengine")).err(),
            Some(ModError::Duplicate("host:web".into()))
        );
        assert_eq!(
            c.host("other", host_spec("qs-webengine")).err(),
            Some(ModError::NotDeclared("host:other".into()))
        );
        assert!(c.finish().is_err(), "a refused host fails the enable");

        // Declared, but the program is not granted by a capability: refused, and so is a path.
        for (binary, refused) in [
            ("xdg-open", "exec:xdg-open"),
            ("/usr/bin/qs-webengine", "exec:/usr/bin/qs-webengine"),
        ] {
            let (_, rx) = watch::channel(Values::new());
            let mut c = ModCtx::new(
                &provides,
                Settings::new(rx),
                Arc::new(HostRecord::default()),
            )
            .with_capabilities(&caps);
            assert_eq!(
                c.host("web", host_spec(binary)).err(),
                Some(ModError::NotGranted(refused.into()))
            );
        }
    }

    #[test]
    fn host_handles_reach_the_hooks_and_the_state_follows_the_daemon() {
        let rec = Arc::new(HostRecord::default());
        let provides = ["host:web".to_string()];
        let caps = ["exec:qs-webengine".to_string()];
        let (_, rx) = watch::channel(Values::new());
        let mut c = ModCtx::new(&provides, Settings::new(rx), rec.clone()).with_capabilities(&caps);
        let handle = c.host("web", host_spec("qs-webengine")).unwrap();
        assert_eq!(handle.name(), "web");
        assert_eq!(*handle.state().borrow(), HostState::Off);
        handle.start();
        handle.stop();

        let decls = c.take_hosts();
        let [decl] = decls.as_slice() else {
            panic!("one host is declared");
        };
        assert_eq!(decl.spec.args[1], "{mod_dir}/host.qml");
        assert!(
            c.finish().is_ok(),
            "a taken host does not refuse the enable"
        );
        // The daemon's end: the state it writes is what the handle's receiver sees.
        decl.state.send_replace(HostState::Ready);
        assert_eq!(*handle.state().borrow(), HostState::Ready);
        assert!(HostState::Ready.is_running());
        assert_eq!(HostState::Missing.reason(), Some("mods.host.missing"));
        assert_eq!(HostState::Ready.name(), "ready");

        assert_eq!(
            rec.calls.lock().unwrap().as_slice(),
            ["start web", "stop web"]
        );
    }

    #[tokio::test]
    async fn the_settings_writer_hands_the_key_to_the_hooks() {
        let rec = Arc::new(HostRecord::default());
        let (_, rx) = watch::channel(Values::new());
        let c = ModCtx::new(&[], Settings::new(rx), rec.clone());
        c.settings_writer()
            .set("view", json!("mobile"))
            .await
            .unwrap();
        assert_eq!(
            rec.calls.lock().unwrap().as_slice(),
            ["set view \"mobile\""]
        );

        // A `Hooks` with no config behind it refuses the write.
        let (_, rx) = watch::channel(Values::new());
        let silent = ModCtx::new(&[], Settings::new(rx), Arc::new(Record::default()));
        assert_eq!(
            silent.settings_writer().set("view", json!("mobile")).await,
            Err(SettingsError::Unavailable)
        );
        assert_eq!(
            SettingsError::Unknown("x".into()).i18n_key(),
            "mods.error.not_declared"
        );
    }

    async fn noop_action(_: Value) -> Result<Option<Value>, ActionError> {
        Ok(None)
    }
}
