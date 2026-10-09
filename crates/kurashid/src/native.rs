//! Native mods (K26), daemon side. A mod linked into kurashid implements `NativeMod`. While its
//! manifest is `enabled` (K25), `enable` runs once and the registrations it made are remembered per
//! mod: disabling drops exactly those (documents get a final `{available:false}` snapshot first,
//! actions go, the settings feed ends), so nothing of a mod runs while it is off.

use std::collections::{BTreeMap, BTreeSet};
use std::path::Path;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Arc, Mutex, Weak};

use kurashi_mod_api::{
    ModCtx, ModError, NativeMod, Publish, Registration, ServiceFn, Settings, Values,
};
use kurashi_mods::{ModEntry, ModState, Provide, Registry, SettingValue, Tier};
use serde_json::{Map, Value, json};
use tokio::sync::watch;
use tokio::task::JoinHandle;

use crate::actions::{ActionError, ActionRegistry};
use crate::config::ConfigStore;
use crate::hub::{Hub, Provider};

/// The first-party native mods linked into this daemon (K26). None ship yet; the wallpaper mod
/// (W12) is the first. The test mod `hello` is linked by the tests only: its manifest is test data.
pub fn linked() -> Vec<Box<dyn NativeMod>> {
    Vec::new()
}

/// Which documents of which mods have a subscriber. The services keep it current; the `mods`
/// document reads it (`running`, K25).
#[derive(Default)]
pub struct Subscribed {
    docs: Mutex<BTreeSet<(String, String)>>,
}

impl Subscribed {
    fn set(&self, mod_id: &str, doc: &str, on: bool) {
        let key = (mod_id.to_string(), doc.to_string());
        let mut docs = self.docs.lock().expect("subscribed lock");
        if on {
            docs.insert(key);
        } else {
            docs.remove(&key);
        }
    }

    /// One of the mod's documents has a subscriber right now.
    pub fn running(&self, mod_id: &str) -> bool {
        self.docs
            .lock()
            .expect("subscribed lock")
            .iter()
            .any(|(m, _)| m == mod_id)
    }
}

/// A native mod's document as a hub provider: its service runs from the first subscriber to the last
/// (rule 5). It is a plain task, not a `ServiceProvider`: a native service has no bus to connect to.
struct Service {
    mod_id: String,
    doc: String,
    run: ServiceFn,
    settings: Arc<watch::Sender<Values>>,
    subscribed: Arc<Subscribed>,
    hub: Weak<Hub>,
    /// Set while the service runs. The publish handle drops its updates otherwise.
    live: Arc<AtomicBool>,
    task: Mutex<Option<JoinHandle<()>>>,
}

impl Service {
    /// Called after the subscription changed, under the hub's `docs` lock by `update`: the flag is
    /// read there, so the last of two racing updates always carries the current value.
    fn publish_running(&self, hub: &Hub) {
        let _ = hub.update("mods", None, |d| {
            set_running(d, &self.mod_id, self.subscribed.running(&self.mod_id));
        });
    }
}

impl Provider for Service {
    fn start(&self, hub: Arc<Hub>) {
        self.live.store(true, Ordering::SeqCst);
        let publish: Publish = {
            let (live, doc, hub) = (self.live.clone(), self.doc.clone(), hub.clone());
            Arc::new(move |state| {
                if live.load(Ordering::SeqCst) {
                    let _ = hub.set(&doc, state, None);
                }
            })
        };
        let settings = Settings::new(self.settings.subscribe());
        let task = tokio::spawn((self.run)(publish, settings));
        if let Some(old) = self.task.lock().expect("task lock").replace(task) {
            old.abort();
        }
        self.subscribed.set(&self.mod_id, &self.doc, true);
        self.publish_running(&hub);
    }

    fn stop(&self) {
        self.live.store(false, Ordering::SeqCst);
        if let Some(task) = self.task.lock().expect("task lock").take() {
            task.abort();
        }
        self.subscribed.set(&self.mod_id, &self.doc, false);
        if let Some(hub) = self.hub.upgrade() {
            self.publish_running(&hub);
        }
    }
}

fn set_running(doc: &mut Value, mod_id: &str, running: bool) {
    if let Some(entries) = doc["mods"].as_array_mut() {
        for entry in entries.iter_mut() {
            if entry["id"] == mod_id {
                entry["running"] = json!(running);
            }
        }
    }
}

/// What one enable of a mod registered, so the disable can take exactly that back.
struct Ledger {
    documents: Vec<String>,
    actions: Vec<String>,
    /// The settings feed; the services hold receivers of it.
    settings: Arc<watch::Sender<Values>>,
    /// (key, config key, default) of each setting the manifest declares.
    keys: Vec<(String, String, SettingValue)>,
}

/// The daemon's native mods: the linked ones, which of them are active, and the reasons of refused
/// enables. Driven by `sync` (after every registry change) and `feed` (after every config change).
pub struct Native {
    hub: Arc<Hub>,
    actions: ActionRegistry,
    linked: BTreeMap<String, Arc<dyn NativeMod>>,
    active: BTreeMap<String, Ledger>,
    /// Why the last enable was refused. The mod is off; `document` shows the reason.
    refused: BTreeMap<String, ModError>,
    subscribed: Arc<Subscribed>,
}

impl Native {
    pub fn new(hub: Arc<Hub>, actions: ActionRegistry, linked: Vec<Box<dyn NativeMod>>) -> Self {
        Self {
            hub,
            actions,
            linked: linked
                .into_iter()
                .map(|m| (m.id().to_string(), Arc::from(m)))
                .collect(),
            active: BTreeMap::new(),
            refused: BTreeMap::new(),
            subscribed: Arc::default(),
        }
    }

    /// Makes the native mods match the registry: an enabled mod is activated, one that is not
    /// enabled is deactivated. A refused enable leaves the mod disabled in the registry.
    pub fn sync(&mut self, reg: &mut Registry, store: Option<&ConfigStore>) {
        let ids: Vec<String> = self.linked.keys().cloned().collect();
        for id in ids {
            let on = reg.get(&id).is_some_and(|e| e.state == ModState::Enabled);
            let active = self.active.contains_key(&id);
            if active && !on {
                self.deactivate(&id);
            }
            if !on {
                self.refused.remove(&id);
            } else if !active {
                let module = self.linked[&id].clone();
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
        let mut ctx = ModCtx::new(&provides, Settings::new(settings.subscribe()));
        module.enable(&mut ctx)?;
        let registrations = ctx.finish()?;
        // Nothing may take an id the daemon or another mod holds: disabling would remove it again.
        for r in &registrations {
            let taken = match r {
                Registration::Service { id, .. } => self.hub.snapshot(&format!("mod.{id}")).is_ok(),
                Registration::Action { id, .. } => self.actions.contains(id),
            };
            if taken {
                let id = match r {
                    Registration::Service { id, .. } => format!("service:{id}"),
                    Registration::Action { id, .. } => format!("action:{id}"),
                };
                return Err(ModError::Duplicate(id));
            }
        }

        let mut ledger = Ledger {
            documents: Vec::new(),
            actions: Vec::new(),
            settings: settings.clone(),
            keys,
        };
        for registration in registrations {
            match registration {
                Registration::Service { id, initial, run } => {
                    let doc = format!("mod.{id}");
                    let service = Service {
                        mod_id: module.id().to_string(),
                        doc: doc.clone(),
                        run,
                        settings: settings.clone(),
                        subscribed: self.subscribed.clone(),
                        hub: Arc::downgrade(&self.hub),
                        live: Arc::default(),
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
        for doc in ledger.documents {
            self.hub.unregister(&doc, json!({"available": false}));
        }
        for action in ledger.actions {
            self.actions.unregister(&action);
        }
        // Dropping the ledger ends the settings feed: the services were stopped by `unregister`.
    }

    /// Pushes the settings in effect to the enabled mods, after every config change. A mod's
    /// service is woken only when one of its values changed.
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
        }
    }

    /// The `mods` document (K25, K26, PROTOCOL §5): the registry's entries, `running` from the
    /// subscriptions, `qml` for enabled native mods whose component files exist, and the reason of
    /// a refused enable in `errors`. Called under the hub's lock (`update`), so it reads the
    /// subscriptions as they are at the write.
    pub fn document(&self, reg: &mut Registry) -> Value {
        let ids: Vec<String> = reg.iter().map(|e| e.id.clone()).collect();
        for id in &ids {
            reg.set_running(id, self.subscribed.running(id));
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

/// `setting_value`: the value in effect for a `mods.<id>.<key>`, or the manifest default when the
/// config store does not know it (no store, or before the mod's keys were added to it).
fn setting_value(store: Option<&ConfigStore>, config_key: &str, default: &SettingValue) -> Value {
    store.and_then(|s| s.get(config_key, None)).map_or_else(
        || serde_json::to_value(default).unwrap_or(Value::Null),
        |p| p.value,
    )
}

/// `qml` of an enabled native mod (K26): the file URL of each component its manifest provides
/// (`widget:x` → `qml/Widget.qml`, `panel:x` → `qml/Panel.qml`, `island-face:x` → `qml/Face.qml`),
/// listed only where the file exists: a URL to nothing is not in effect (Shōjiki).
fn qml_of(e: &ModEntry) -> Option<Value> {
    let m = e
        .manifest
        .as_ref()
        .filter(|m| m.tier == Tier::Native && e.state == ModState::Enabled)?;
    let mut qml = Map::new();
    for p in &m.provides {
        let file = match p {
            Provide::Widget(_) => "Widget.qml",
            Provide::Panel(_) => "Panel.qml",
            Provide::IslandFace(_) => "Face.qml",
            _ => continue,
        };
        let path = e.dir.join("qml").join(file);
        if path.is_file() {
            qml.insert(p.to_string(), json!(file_url(&path)));
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
