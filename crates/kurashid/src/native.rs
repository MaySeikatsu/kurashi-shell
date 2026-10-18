//! Native mods (K26), daemon side. A mod linked into kurashid implements `NativeMod`. While its
//! manifest is `enabled` (K25), `enable` runs once and the registrations it made are remembered per
//! mod: disabling drops exactly those (documents get a final `{available:false}` snapshot first,
//! actions go, faces leave the arbiter, the settings feed ends), so nothing of a mod runs while it is
//! off. K28 adds what a mod contributes to the core views: `runtime.slots`, island faces and choice
//! sources.

use std::collections::{BTreeMap, BTreeSet};
use std::path::Path;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Arc, Mutex, Weak};

use kurashi_island::{Face, FaceSignal, Source, Transient};
use kurashi_mod_api::{
    Choice, ChoicesFn, FaceUpdate, Hooks, JobCtx, JobFn, ModCtx, ModError, NativeMod, Publish,
    Registration, ServiceFn, Settings, Values,
};
use kurashi_mods::{
    Manifest, ModEntry, ModState, Provide, Registry, SettingType, SettingValue, Tier,
};
use serde_json::{Map, Value, json};
use tokio::runtime::Handle;
use tokio::sync::watch;
use tokio::task::JoinHandle;

use crate::actions::{ActionError, ActionRegistry};
use crate::config::{CORE_SOURCES, ConfigStore, Offer};
use crate::hub::{Hub, Provider};
use crate::island::IslandHost;

/// The first-party native mods linked into this daemon (K26). The test mod `hello` is linked by the
/// tests, and by the `test-mods` feature for the live mods test (W14): its manifest is test data.
pub fn linked() -> Vec<Box<dyn NativeMod>> {
    let mods = vec![
        Box::new(kurashi_mod_weather::WeatherMod::new()) as Box<dyn NativeMod>,
        Box::new(kurashi_mod_sysmon::Sysmon::new()),
        Box::new(kurashi_mod_wallpaper::Wallpaper::new()),
    ];
    #[cfg(feature = "test-mods")]
    let mods = mods
        .into_iter()
        .chain([Box::new(kurashi_mod_hello::Hello) as Box<dyn NativeMod>])
        .collect();
    mods
}

/// `runtime.slots` (K28): the contributions of enabled mods to the core views' slots.
pub const SLOTS_DOC: &str = "runtime.slots";

/// `running_reasons` of a mod whose document has a subscriber (K25 "Running now").
const RUNNING_SUBSCRIBED: &str = "mods.running.subscribed";

/// Why each mod runs now (K25, I23): a document with a subscriber, a background job that is started.
/// The services and jobs keep it current; the `mods` document reads it as `running_reasons`.
#[derive(Default)]
pub struct Running {
    docs: Mutex<BTreeSet<(String, String)>>,
    /// (mod, job) -> the job's reason, for the jobs that run now.
    jobs: Mutex<BTreeMap<(String, String), String>>,
}

impl Running {
    fn set_doc(&self, mod_id: &str, doc: &str, on: bool) {
        let key = (mod_id.to_string(), doc.to_string());
        let mut docs = self.docs.lock().expect("running lock");
        if on {
            docs.insert(key);
        } else {
            docs.remove(&key);
        }
    }

    fn set_job(&self, mod_id: &str, job: &str, reason: Option<&str>) {
        let key = (mod_id.to_string(), job.to_string());
        let mut jobs = self.jobs.lock().expect("running lock");
        match reason {
            Some(reason) => jobs.insert(key, reason.to_string()),
            None => jobs.remove(&key),
        };
    }

    /// The reasons the mod runs now: its subscribers first, then its jobs by name, each once.
    pub fn reasons(&self, mod_id: &str) -> Vec<String> {
        let mut out = Vec::new();
        let subscribed = self
            .docs
            .lock()
            .expect("running lock")
            .iter()
            .any(|(m, _)| m == mod_id);
        if subscribed {
            out.push(RUNNING_SUBSCRIBED.to_string());
        }
        for ((m, _), reason) in self.jobs.lock().expect("running lock").iter() {
            if m == mod_id && !out.contains(reason) {
                out.push(reason.clone());
            }
        }
        out
    }
}

/// A native mod's document as a hub provider: its service runs from the first subscriber to the last
/// (rule 5). It is a plain task, not a `ServiceProvider`: a native service has no bus to connect to.
struct Service {
    mod_id: String,
    doc: String,
    run: ServiceFn,
    settings: Arc<watch::Sender<Values>>,
    running: Arc<Running>,
    hub: Weak<Hub>,
    /// Set while the service runs. The publish handle drops its updates otherwise.
    live: Arc<AtomicBool>,
    /// The mod's primary document (its first service): `ready` in `runtime.slots` follows it.
    ready: Option<Arc<AtomicBool>>,
    task: Mutex<Option<JoinHandle<()>>>,
}

impl Service {
    /// Called after the subscription changed, under the hub's `docs` lock by `update`: the flag is
    /// read there, so the last of two racing updates always carries the current value.
    fn publish_running(&self, hub: &Hub) {
        let _ = hub.update("mods", None, |d| {
            set_running(d, &self.mod_id, self.running.reasons(&self.mod_id));
        });
    }
}

/// A background job of a mod (I23, `ModCtx::background`). It runs on the daemon's runtime while the
/// mod is on and its `wanted_by` setting is true: `feed` starts and stops it as the setting changes,
/// `deactivate` cancels it. A job that ends by itself stops running and says so in the document.
struct BackgroundJob {
    mod_id: String,
    name: String,
    reason: String,
    wanted_by: String,
    body: JobFn,
    settings: Arc<watch::Sender<Values>>,
    running: Arc<Running>,
    hub: Weak<Hub>,
    runtime: Handle,
    run: Mutex<JobRun>,
}

/// One job's run: its task, and how many runs there were, so a run that ends late never clears
/// the state of a later one.
#[derive(Default)]
struct JobRun {
    starts: u64,
    task: Option<JoinHandle<()>>,
}

/// Reports the end of one run of a job when it is dropped: the body returned, panicked, or was
/// cancelled with its task.
struct RunEnd {
    job: Arc<BackgroundJob>,
    start: u64,
}

impl Drop for RunEnd {
    fn drop(&mut self) {
        self.job.ended(self.start);
    }
}

impl BackgroundJob {
    /// Whether the setting in effect wants the job running.
    fn wants(&self, values: &Values) -> bool {
        values.get(&self.wanted_by).and_then(Value::as_bool) == Some(true)
    }

    /// Starts the job unless it runs. Its reason joins `running_reasons` until it stops.
    fn start(self: &Arc<Self>) {
        let mut run = self.run.lock().expect("job lock");
        if run.task.is_some() {
            return;
        }
        run.starts += 1;
        let start = run.starts;
        self.running
            .set_job(&self.mod_id, &self.name, Some(&self.reason));
        let ctx = JobCtx::new(Settings::new(self.settings.subscribe()));
        let body = (self.body)(ctx);
        let end = RunEnd {
            job: self.clone(),
            start,
        };
        run.task = Some(self.runtime.spawn(async move {
            let _end = end;
            body.await;
        }));
    }

    /// Cancels the job if it runs. The task leaves the lock first: dropping a cancelled run reports
    /// its end, and that takes the lock.
    fn stop(&self) {
        let task = self.run.lock().expect("job lock").task.take();
        if let Some(task) = task {
            task.abort();
            self.running.set_job(&self.mod_id, &self.name, None);
        }
    }

    /// The run `start` ended: its body returned, panicked, or was cancelled. A run that a stop or a
    /// later start has already superseded changes nothing.
    fn ended(&self, start: u64) {
        let mut run = self.run.lock().expect("job lock");
        if run.starts != start || run.task.take().is_none() {
            return;
        }
        drop(run);
        self.running.set_job(&self.mod_id, &self.name, None);
        if let Some(hub) = self.hub.upgrade() {
            let _ = hub.update("mods", None, |d| {
                set_running(d, &self.mod_id, self.running.reasons(&self.mod_id));
            });
        }
    }
}

fn set_running(doc: &mut Value, mod_id: &str, reasons: Vec<String>) {
    if let Some(entries) = doc["mods"].as_array_mut() {
        for entry in entries.iter_mut() {
            if entry["id"] == mod_id {
                entry["running"] = json!(!reasons.is_empty());
                entry["running_reasons"] = json!(reasons);
            }
        }
    }
}

impl Provider for Service {
    fn start(&self, hub: Arc<Hub>) {
        self.live.store(true, Ordering::SeqCst);
        let publish: Publish = {
            let (live, doc, hub) = (self.live.clone(), self.doc.clone(), hub.clone());
            let (mod_id, ready) = (self.mod_id.clone(), self.ready.clone());
            Arc::new(move |state| {
                if !live.load(Ordering::SeqCst) {
                    return;
                }
                let available = is_available(&state);
                let _ = hub.set(&doc, state, None);
                if let Some(flag) = &ready {
                    flag.store(available, Ordering::SeqCst);
                    let _ = hub.update(SLOTS_DOC, None, |d| set_ready(d, &mod_id, available));
                }
            })
        };
        let settings = Settings::new(self.settings.subscribe());
        let task = tokio::spawn((self.run)(publish, settings));
        if let Some(old) = self.task.lock().expect("task lock").replace(task) {
            old.abort();
        }
        self.running.set_doc(&self.mod_id, &self.doc, true);
        self.publish_running(&hub);
    }

    fn stop(&self) {
        self.live.store(false, Ordering::SeqCst);
        if let Some(task) = self.task.lock().expect("task lock").take() {
            task.abort();
        }
        self.running.set_doc(&self.mod_id, &self.doc, false);
        if let Some(hub) = self.hub.upgrade() {
            self.publish_running(&hub);
        }
    }
}

/// A document is available when its state says so: the `available` flag every document a mod
/// serves carries. A primary document without it is not ready (Shōjiki).
fn is_available(state: &Value) -> bool {
    state["available"] == true
}

/// Sets `ready` on the entries of `runtime.slots` that belong to `mod_id`.
fn set_ready(doc: &mut Value, mod_id: &str, ready: bool) {
    for list in doc.as_object_mut().into_iter().flat_map(|o| o.values_mut()) {
        for entry in list.as_array_mut().into_iter().flatten() {
            if entry["mod"] == mod_id {
                entry["ready"] = json!(ready);
            }
        }
    }
}

/// What a mod's face and choice handles reach (K28). One per enable: `live` goes false on disable,
/// so a handle the mod kept does nothing afterwards, and the mod's offers leave with the enable.
struct Link {
    island: Option<Arc<IslandHost>>,
    /// Weak: the store's listener is what reconciles the mods, so the store must not own the mods.
    config: Option<Weak<ConfigStore>>,
    state: Mutex<LinkState>,
}

#[derive(Default)]
struct LinkState {
    live: bool,
    /// Each choice source of this enable, with the function that offers its options.
    choices: BTreeMap<String, ChoicesFn>,
    /// The options each of those sources offers now.
    offers: BTreeMap<String, Vec<Offer>>,
}

impl Hooks for Link {
    fn face(&self, face: &str, update: FaceUpdate) {
        let state = self.state.lock().expect("link lock");
        if !state.live {
            return;
        }
        let Some(island) = &self.island else {
            return;
        };
        match update {
            FaceUpdate::Raise { relevance, ttl } => island.signal(FaceSignal {
                face: face.into(),
                relevance,
                condition: true,
                // A transient keeps the arbiter's TTL rules; it never displaces a manual choice.
                transient: ttl.map(|ttl| Transient {
                    kind: face.into(),
                    ttl_ms: u64::try_from(ttl.as_millis()).unwrap_or(u64::MAX),
                    may_interrupt: false,
                }),
            }),
            FaceUpdate::Clear => island.clear_face(face),
        }
    }

    fn choices_changed(&self, source: &str) {
        let offer_fn = {
            let state = self.state.lock().expect("link lock");
            match state.choices.get(source) {
                Some(f) if state.live => f.clone(),
                _ => return,
            }
        };
        // The mod's function runs without the lock; a disable that came in meanwhile is checked below.
        let offers = offers_of(offer_fn());
        let mut state = self.state.lock().expect("link lock");
        if !state.live {
            return;
        }
        state.offers.insert(source.into(), offers.clone());
        if let Some(store) = self.config.as_ref().and_then(Weak::upgrade) {
            store.set_mod_source(source, offers);
        }
    }
}

/// What a choice function offers, as the config store keeps it.
fn offers_of(options: Vec<Choice>) -> Vec<Offer> {
    options
        .into_iter()
        .map(|c| Offer {
            value: c.value,
            label: c.label,
            enabled: c.enabled,
            reason: c.reason,
        })
        .collect()
}

/// What one enable of a mod registered, so the disable can take exactly that back.
struct Ledger {
    documents: Vec<String>,
    actions: Vec<String>,
    faces: Vec<String>,
    /// The background jobs; `feed` starts and stops them, `deactivate` cancels them.
    jobs: Vec<Arc<BackgroundJob>>,
    /// The settings feed; the services hold receivers of it.
    settings: Arc<watch::Sender<Values>>,
    /// (key, config key, default) of each setting the manifest declares.
    keys: Vec<(String, String, SettingValue)>,
    link: Arc<Link>,
    /// `ready` of the primary document; true for a mod that serves none.
    ready: Arc<AtomicBool>,
}

/// The daemon's native mods: the linked ones, which of them are active, and the reasons of refused
/// enables. Driven by `sync` (after every registry change) and `feed` (after every config change).
pub struct Native {
    hub: Arc<Hub>,
    actions: ActionRegistry,
    /// The island the mods' faces join (K28).
    island: Option<Arc<IslandHost>>,
    config: Option<Weak<ConfigStore>>,
    linked: BTreeMap<String, Arc<dyn NativeMod>>,
    active: BTreeMap<String, Ledger>,
    /// Why the last enable was refused. The mod is off; `document` shows the reason.
    refused: BTreeMap<String, ModError>,
    running: Arc<Running>,
    /// Where background jobs run. Enable may run off the runtime (a config reload), so it is taken
    /// here; without one a job cannot run and its mod's enable is refused.
    runtime: Option<Handle>,
}

impl Native {
    pub fn new(
        hub: Arc<Hub>,
        actions: ActionRegistry,
        linked: Vec<Box<dyn NativeMod>>,
        island: Option<Arc<IslandHost>>,
        config: Option<Weak<ConfigStore>>,
    ) -> Self {
        Self {
            hub,
            actions,
            island,
            config,
            linked: linked
                .into_iter()
                .map(|m| (m.id().to_string(), Arc::from(m)))
                .collect(),
            active: BTreeMap::new(),
            refused: BTreeMap::new(),
            running: Arc::default(),
            runtime: Handle::try_current().ok(),
        }
    }

    /// Makes the native mods match the registry: an enabled mod is activated, one that is not
    /// enabled is deactivated. A refused enable leaves the mod disabled in the registry, and so does
    /// an enabled mod whose daemon code is not linked (B15): switched on, it would do nothing.
    pub fn sync(&mut self, reg: &mut Registry, store: Option<&ConfigStore>) {
        let ids: Vec<String> = reg.iter().map(|e| e.id.clone()).collect();
        for id in ids {
            let on = reg.get(&id).is_some_and(|e| e.state == ModState::Enabled);
            let active = self.active.contains_key(&id);
            if active && !on {
                self.deactivate(&id);
            }
            if !on {
                self.refused.remove(&id);
                continue;
            }
            if active {
                continue;
            }
            let Some(module) = self.linked.get(&id).cloned() else {
                let needs_code = reg
                    .get(&id)
                    .and_then(|e| e.manifest.as_ref())
                    .is_some_and(needs_daemon_code);
                if needs_code {
                    self.refused.insert(id.clone(), ModError::NotBuilt);
                    let _ = reg.disable(&id);
                }
                continue;
            };
            match self.activate(module.as_ref(), reg, store) {
                Ok(()) => {
                    self.refused.remove(&id);
                }
                Err(e) => {
                    self.refused.insert(id.clone(), e);
                    let _ = reg.disable(&id);
                }
            }
        }
    }

    /// Runs `enable` and applies what it registered. Registrations are applied only after it
    /// succeeded, so a refused enable leaves nothing behind.
    fn activate(
        &mut self,
        module: &dyn NativeMod,
        reg: &Registry,
        store: Option<&ConfigStore>,
    ) -> Result<(), ModError> {
        let manifest = reg
            .get(module.id())
            .and_then(|e| e.manifest.as_ref())
            .ok_or_else(|| ModError::Failed("no manifest".into()))?;
        let keys: Vec<(String, String, SettingValue)> = manifest
            .settings
            .iter()
            .map(|s| {
                (
                    s.key.clone(),
                    manifest.config_key(&s.key),
                    s.default.clone(),
                )
            })
            .collect();
        let values: Values = keys
            .iter()
            .map(|(key, config_key, default)| {
                (key.clone(), setting_value(store, config_key, default))
            })
            .collect();
        let settings = Arc::new(watch::channel(values).0);
        let provides: Vec<String> = manifest.provides.iter().map(ToString::to_string).collect();
        let link = Arc::new(Link {
            island: self.island.clone(),
            config: self.config.clone(),
            state: Mutex::default(),
        });
        let mut ctx = ModCtx::new(&provides, Settings::new(settings.subscribe()), link.clone());
        module.enable(&mut ctx)?;
        let declared_jobs = ctx.take_jobs();
        let registrations = ctx.finish()?;
        // A job waits for a bool setting of its own mod (I23); without a runtime it could never run.
        for job in &declared_jobs {
            let bool_setting = manifest
                .settings
                .iter()
                .any(|s| s.key == job.wanted_by && s.ty == SettingType::Bool);
            if !bool_setting {
                return Err(ModError::Failed(format!(
                    "job {} waits for {}, which is not a bool setting",
                    job.name, job.wanted_by
                )));
            }
        }
        if !declared_jobs.is_empty() && self.runtime.is_none() {
            return Err(ModError::Failed("the daemon runtime is not running".into()));
        }
        // Nothing may take an id the daemon or another mod holds: disabling would remove it again.
        // A core choice source keeps its own options (config.rs `CORE_SOURCES`).
        for r in &registrations {
            let (taken, id) = match r {
                Registration::Service { id, .. } => (
                    self.hub.snapshot(&format!("mod.{id}")).is_ok(),
                    format!("service:{id}"),
                ),
                Registration::Action { id, .. } => {
                    (self.actions.contains(id), format!("action:{id}"))
                }
                Registration::Face { name } => (
                    self.island.as_ref().is_some_and(|i| i.has_face(name)),
                    format!("island-face:{name}"),
                ),
                Registration::Choices { source, .. } => (
                    CORE_SOURCES.contains(&source.as_str()),
                    format!("choices:{source}"),
                ),
            };
            if taken {
                return Err(ModError::Duplicate(id));
            }
        }
        if self.island.is_none()
            && registrations
                .iter()
                .any(|r| matches!(r, Registration::Face { .. }))
        {
            return Err(ModError::Failed("island-face needs an island".into()));
        }

        // Live from here, before the first registration is applied: a face or choice the enable
        // offers is in effect from its registration on.
        link.state.lock().expect("link lock").live = true;
        let ready = Arc::new(AtomicBool::new(true));
        let jobs: Vec<Arc<BackgroundJob>> = declared_jobs
            .into_iter()
            .map(|job| {
                Arc::new(BackgroundJob {
                    mod_id: module.id().to_string(),
                    name: job.name,
                    reason: job.reason,
                    wanted_by: job.wanted_by,
                    body: job.run,
                    settings: settings.clone(),
                    running: self.running.clone(),
                    hub: Arc::downgrade(&self.hub),
                    runtime: self
                        .runtime
                        .clone()
                        .expect("checked above: jobs need a runtime"),
                    run: Mutex::default(),
                })
            })
            .collect();
        let mut ledger = Ledger {
            documents: Vec::new(),
            actions: Vec::new(),
            faces: Vec::new(),
            jobs,
            settings: settings.clone(),
            keys,
            link: link.clone(),
            ready: ready.clone(),
        };
        let mut primary = true;
        for registration in registrations {
            match registration {
                Registration::Service { id, initial, run } => {
                    let doc = format!("mod.{id}");
                    let flag = primary.then(|| ready.clone());
                    primary = false;
                    if let Some(flag) = &flag {
                        flag.store(is_available(&initial), Ordering::SeqCst);
                    }
                    let service = Service {
                        mod_id: module.id().to_string(),
                        doc: doc.clone(),
                        run,
                        settings: settings.clone(),
                        running: self.running.clone(),
                        hub: Arc::downgrade(&self.hub),
                        live: Arc::default(),
                        ready: flag,
                        task: Mutex::default(),
                    };
                    self.hub.register(&doc, initial, Some(Arc::new(service)));
                    ledger.documents.push(doc);
                }
                Registration::Action { id, label, handler } => {
                    self.actions.register(&id, &label, move |args| {
                        let handler = handler.clone();
                        async move { handler(args).await.map_err(action_error) }
                    });
                    ledger.actions.push(id);
                }
                Registration::Face { name } => {
                    if let Some(island) = &self.island {
                        island.register_face(Face {
                            id: name.clone(),
                            source: Source::Mod(module.id().to_string()),
                            default_priority: 0,
                        });
                    }
                    ledger.faces.push(name);
                }
                Registration::Choices { source, options } => {
                    let offers = offers_of(options());
                    let mut state = link.state.lock().expect("link lock");
                    state.choices.insert(source.clone(), options);
                    state.offers.insert(source, offers);
                }
            }
        }
        // A job whose setting wants it runs from the enable on (I23).
        for job in &ledger.jobs {
            let wanted = job.wants(&settings.borrow());
            if wanted {
                job.start();
            }
        }
        self.active.insert(module.id().to_string(), ledger);
        Ok(())
    }

    /// Drops everything the mod's enable registered. Documents answer `unknown_doc` afterwards.
    fn deactivate(&mut self, id: &str) {
        let Some(ledger) = self.active.remove(id) else {
            return;
        };
        // The mod's handles stop reaching the island and the config before anything is taken back.
        ledger.link.state.lock().expect("link lock").live = false;
        for job in &ledger.jobs {
            job.stop();
        }
        for doc in ledger.documents {
            self.hub.unregister(&doc, json!({"available": false}));
        }
        for action in ledger.actions {
            self.actions.unregister(&action);
        }
        if let Some(island) = &self.island {
            for face in &ledger.faces {
                island.unregister_face(face);
            }
        }
        // Dropping the ledger ends the settings feed: the services were stopped by `unregister`.
    }

    /// Pushes the settings in effect to the enabled mods, after every config change. A mod's
    /// service is woken only when one of its values changed. A background job starts or stops as
    /// its setting now wants it (I23).
    pub fn feed(&self, store: &ConfigStore) {
        for ledger in self.active.values() {
            let values: Values = ledger
                .keys
                .iter()
                .map(|(key, config_key, default)| {
                    (key.clone(), setting_value(Some(store), config_key, default))
                })
                .collect();
            ledger.settings.send_if_modified(|current| {
                if *current == values {
                    false
                } else {
                    *current = values;
                    true
                }
            });
            // After the send: a job started now reads the settings in effect.
            for job in &ledger.jobs {
                let wanted = job.wants(&ledger.settings.borrow());
                if wanted {
                    job.start();
                } else {
                    job.stop();
                }
            }
        }
    }

    /// The options of every choice source (K28 (3)), for the config store: each source a manifest
    /// declares, or a setting names with `choices_from`, is known. A source of an enabled mod offers
    /// what its function returned last; every other one offers nothing, so its values are inert.
    pub fn source_offers(&self, reg: &Registry) -> BTreeMap<String, Vec<Offer>> {
        let mut out: BTreeMap<String, Vec<Offer>> = BTreeMap::new();
        for e in reg.iter() {
            let Some(m) = &e.manifest else {
                continue;
            };
            let declared = m.provides.iter().filter_map(|p| match p {
                Provide::Choices(source) => Some(source.as_str()),
                _ => None,
            });
            let named = m.settings.iter().filter_map(|s| s.choices_from.as_deref());
            for source in declared.chain(named) {
                if !CORE_SOURCES.contains(&source) {
                    out.entry(source.to_string()).or_default();
                }
            }
        }
        for ledger in self.active.values() {
            let state = ledger.link.state.lock().expect("link lock");
            for (source, offers) in &state.offers {
                out.insert(source.clone(), offers.clone());
            }
        }
        out
    }

    /// `runtime.slots` (K28, PROTOCOL §5): each contribution of an enabled mod whose slot file
    /// exists, by slot and in mod id order. `ready` is the mod's primary document's `available`.
    /// Called under the slots document's lock, so it reads nothing from the hub.
    pub fn slots(&self, reg: &Registry) -> Value {
        let mut out: Map<String, Value> = Map::new();
        for e in reg.iter() {
            let (Some(m), Some(ledger)) = (&e.manifest, self.active.get(&e.id)) else {
                continue;
            };
            let ready = ledger.ready.load(Ordering::SeqCst);
            for p in &m.provides {
                let Provide::Slot(name) = p else {
                    continue;
                };
                let file = e.dir.join("qml").join("slots").join(format!("{name}.qml"));
                if !file.is_file() {
                    continue;
                }
                let entry = json!({"mod": e.id, "qml": file_url(&file), "ready": ready});
                let list = out.entry(name.clone()).or_insert_with(|| json!([]));
                if let Some(items) = list.as_array_mut() {
                    items.push(entry);
                }
            }
        }
        Value::Object(out)
    }

    /// The `mods` document (K25, K26, I23, PROTOCOL §5): the registry's entries, `running_reasons`
    /// from the subscriptions and the started jobs, `qml` for enabled native mods whose component files exist, and the reason of
    /// a refused enable in `errors`. Called under the hub's lock (`update`), so it reads the
    /// subscriptions as they are at the write.
    pub fn document(&self, reg: &mut Registry) -> Value {
        let ids: Vec<String> = reg.iter().map(|e| e.id.clone()).collect();
        for id in &ids {
            reg.set_running_reasons(id, self.running.reasons(id));
        }
        let mut doc = reg.doc();
        if let Some(entries) = doc["mods"].as_array_mut() {
            for entry in entries.iter_mut() {
                let Some(id) = entry["id"].as_str().map(str::to_owned) else {
                    continue;
                };
                if let Some(e) = self.refused.get(&id) {
                    entry["errors"] = json!([{
                        "key": e.i18n_key(),
                        "path": "enable",
                        "detail": e.to_string(),
                    }]);
                }
                if let Some(qml) = reg.get(&id).and_then(qml_of) {
                    entry["qml"] = qml;
                }
            }
        }
        doc
    }
}

/// Whether a manifest declares something only linked daemon code can serve: a service, an action, an
/// island face, a choice source or a background job (B15). Frontend-only provides (widgets, panels,
/// slots, palettes…) need no code and stay enable-able.
fn needs_daemon_code(m: &Manifest) -> bool {
    m.provides.iter().any(|p| {
        matches!(
            p,
            Provide::Service(_)
                | Provide::Action(_)
                | Provide::IslandFace(_)
                | Provide::Choices(_)
                | Provide::Job(_)
        )
    })
}

/// `setting_value`: the value in effect for a `mods.<id>.<key>`, or the manifest default when the
/// config store does not know it (no store, or before the mod's keys were added to it).
fn setting_value(store: Option<&ConfigStore>, config_key: &str, default: &SettingValue) -> Value {
    store.and_then(|s| s.get(config_key, None)).map_or_else(
        || serde_json::to_value(default).unwrap_or(Value::Null),
        |p| p.value,
    )
}

/// `qml` of an enabled native mod (K26, K28): the file URL of each component its manifest provides
/// (`widget:x` → `qml/Widget.qml`, `panel:x` → `qml/Panel.qml`, `peek:x` → `qml/Peek.qml` (K35),
/// `island-face:x` → `qml/Face.qml`,
/// `island-face:x:expanded` → `qml/FaceExpanded.qml`, `slot:x` → `qml/slots/x.qml`), listed only
/// where the file exists: a URL to nothing is not in effect (Shōjiki).
fn qml_of(e: &ModEntry) -> Option<Value> {
    let m = e
        .manifest
        .as_ref()
        .filter(|m| m.tier == Tier::Native && e.state == ModState::Enabled)?;
    let dir = e.dir.join("qml");
    let mut qml = Map::new();
    for p in &m.provides {
        let files = match p {
            Provide::Widget(_) => vec![(p.to_string(), dir.join("Widget.qml"))],
            Provide::Panel(_) => vec![(p.to_string(), dir.join("Panel.qml"))],
            Provide::Peek(_) => vec![(p.to_string(), dir.join("Peek.qml"))],
            Provide::IslandFace(_) => vec![
                (p.to_string(), dir.join("Face.qml")),
                (format!("{p}:expanded"), dir.join("FaceExpanded.qml")),
            ],
            Provide::Slot(name) => {
                vec![(p.to_string(), dir.join("slots").join(format!("{name}.qml")))]
            }
            _ => continue,
        };
        for (key, file) in files {
            if file.is_file() {
                qml.insert(key, json!(file_url(&file)));
            }
        }
    }
    (!qml.is_empty()).then_some(Value::Object(qml))
}

/// `file://` URL of an absolute path, percent-encoded outside the unreserved characters.
fn file_url(path: &Path) -> String {
    let mut url = String::from("file://");
    for b in path.to_string_lossy().bytes() {
        match b {
            b'A'..=b'Z' | b'a'..=b'z' | b'0'..=b'9' | b'-' | b'.' | b'_' | b'~' | b'/' => {
                url.push(char::from(b));
            }
            _ => url.push_str(&format!("%{b:02X}")),
        }
    }
    url
}

fn action_error(e: kurashi_mod_api::ActionError) -> ActionError {
    use kurashi_mod_api::ActionError as M;
    match e {
        M::Invalid(m) => ActionError::Invalid(m),
        M::Unavailable(m) => ActionError::Unavailable(m),
        M::Internal(m) => ActionError::Internal(m),
    }
}
