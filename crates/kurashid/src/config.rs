//! Config store (M1.5): the schema registry behind `kurashi-config`, published as the `config`
//! and `schema.settings` documents, answering `cfg.*` / `apply` / `undo` / `redo` and the
//! `profile.*` actions (PROTOCOL §5).

use std::sync::{Arc, Mutex};

use kurashi_config::{Config, Op, Options, Paths, SchemaView};
use kurashi_core::Provenanced;
use kurashi_ipc::{ApplyOp, DiffEntry, LayerValue, OpError};
use kurashi_schema::Registry;
use serde_json::{Map, Value, json};

use crate::actions::{ActionError, ActionRegistry};
use crate::hub::Hub;

pub const DOC: &str = "config";
pub const SETTINGS_DOC: &str = "schema.settings";

/// `kurashi-config` is schema-agnostic; this is the only place the two meet.
pub struct SchemaAdapter(pub &'static Registry);

impl SchemaView for SchemaAdapter {
    fn version(&self) -> u32 {
        self.0.version()
    }
    fn default(&self, key: &str) -> Option<Value> {
        self.0.get(key).map(|m| m.default.clone())
    }
    fn validate(&self, key: &str, v: &Value) -> Result<(), String> {
        self.0.validate(key, v).map_err(|e| e.i18n_key().into())
    }
    fn per_output(&self, key: &str) -> bool {
        self.0.get(key).is_some_and(|m| m.flags.per_output)
    }
    fn keys(&self) -> Vec<String> {
        self.0.keys().map(String::from).collect()
    }
}

type Listener = Box<dyn Fn(&ConfigStore) + Send + Sync>;

pub struct ConfigStore {
    cfg: Mutex<Config<SchemaAdapter>>,
    hub: Arc<Hub>,
    registry: &'static Registry,
    /// `forced:accessibility` entries currently applied (only rewritten when they change).
    a11y_forced: Mutex<Vec<(String, Value, String)>>,
    listeners: Mutex<Vec<Listener>>,
}

/// What a committed transaction answers on the wire.
pub struct Committed {
    pub rev: u64,
    pub undo: String,
}

fn op_error(e: kurashi_config::OpError) -> OpError {
    use kurashi_config::OpError as E;
    let msg = e.to_string();
    match e {
        E::UnknownKey { key, .. } => OpError {
            key: Some(key),
            output: None,
            code: "config.diag.unknown_key".into(),
            msg,
        },
        E::NotPerOutput { key, output, .. } => OpError {
            key: Some(key),
            output: Some(output),
            code: "config.diag.not_per_output".into(),
            msg,
        },
        // `message` is already the schema's i18n key (SchemaAdapter::validate).
        E::Invalid { key, message, .. } => OpError {
            key: Some(key),
            output: None,
            code: message,
            msg,
        },
        E::Persist { message } => OpError {
            key: None,
            output: None,
            code: "config.error.user_file_unreadable".into(),
            msg: message,
        },
    }
}

fn refused(code: &str, msg: impl Into<String>) -> Vec<OpError> {
    vec![OpError {
        key: None,
        output: None,
        code: code.into(),
        msg: msg.into(),
    }]
}

fn to_ops(ops: &[ApplyOp]) -> Vec<Op> {
    ops.iter()
        .map(|o| match o {
            ApplyOp::Set { set, value, output } => Op::Set {
                key: set.clone(),
                output: output.clone(),
                value: value.clone(),
            },
            ApplyOp::Reset { reset, output } => Op::Reset {
                key: reset.clone(),
                output: output.clone(),
            },
        })
        .collect()
}

fn diff_entries(d: &kurashi_config::Diff) -> Vec<DiffEntry> {
    d.entries
        .iter()
        .map(|e| DiffEntry {
            key: e.key.clone(),
            output: e.output.clone(),
            before: e.before.clone(),
            after: e.after.clone(),
        })
        .collect()
}

impl ConfigStore {
    pub fn open(
        hub: Arc<Hub>,
        registry: &'static Registry,
        paths: Paths,
        opts: Options,
    ) -> Arc<Self> {
        let cfg = Config::open(SchemaAdapter(registry), paths, opts);
        for d in cfg.diagnostics() {
            tracing::warn!(file = %d.file.display(), key = %d.key, reason = d.reason.i18n_key(), "config diagnostic");
        }
        hub.register(SETTINGS_DOC, kurashi_schema::settings_meta(registry), None);
        let store = Arc::new(ConfigStore {
            cfg: Mutex::new(cfg),
            hub: hub.clone(),
            registry,
            a11y_forced: Mutex::new(Vec::new()),
            listeners: Mutex::new(Vec::new()),
        });
        store.apply_couplings();
        hub.register(DOC, store.document(), None);
        store
    }

    /// Run `f` after every effective change (theme recompute, island config, …).
    pub fn on_change(&self, f: impl Fn(&ConfigStore) + Send + Sync + 'static) {
        self.listeners.lock().expect("listeners").push(Box::new(f));
    }

    /// Schema couplings the daemon evaluates (ARCHITECTURE §3): `overridden_by` a11y modes
    /// become `forced:accessibility` entries with `forced_by` = the mode key, so the UI shows
    /// why a control is inert instead of silently ignoring it (Shōjiki).
    fn apply_couplings(&self) {
        use kurashi_schema::Coupling;
        let mut cfg = self.cfg.lock().expect("config lock");
        let mut want: Vec<(String, Value, String)> = Vec::new();
        for key in self.registry.keys() {
            let Some(meta) = self.registry.get(key) else {
                continue;
            };
            for c in &meta.couplings {
                if let Coupling::OverriddenBy {
                    key: mode,
                    forces: Some(v),
                } = c
                    && cfg
                        .resolve(mode, None)
                        .is_some_and(|p| p.value == Value::Bool(true))
                {
                    want.push((key.to_string(), v.clone(), mode.clone()));
                    break; // first active mode wins (declaration order)
                }
            }
        }
        let mut have = self.a11y_forced.lock().expect("a11y lock");
        if *have == want {
            return;
        }
        cfg.clear_forced("accessibility", None);
        for (key, value, mode) in &want {
            let forced = kurashi_config::Forced {
                value: value.clone(),
                forced_by: Some(mode.clone()),
                reason: Some("settings.inert.overridden_by".into()),
            };
            if let Err(e) = cfg.set_forced("accessibility", (key.clone(), None), forced) {
                tracing::warn!(%key, error = %e, "cannot force a11y coupling");
            }
        }
        *have = want;
    }

    /// `{"values":{key: Provenanced}, "outputs":{name:{key: Provenanced}}}` — rebuilt whole and
    /// diffed by the hub, so patches carry exactly what changed (K17).
    pub fn document(&self) -> Value {
        let cfg = self.cfg.lock().expect("config lock");
        let mut values = Map::new();
        let mut outputs: Map<String, Value> = Map::new();
        for key in cfg.schema().keys() {
            if let Some(p) = cfg.resolve(&key, None) {
                values.insert(key.clone(), json!(p));
            }
            for out in cfg.outputs_for(&key) {
                if let Some(p) = cfg.resolve(&key, Some(&out)) {
                    outputs
                        .entry(out)
                        .or_insert_with(|| json!({}))
                        .as_object_mut()
                        .expect("object")
                        .insert(key.clone(), json!(p));
                }
            }
        }
        json!({"values": values, "outputs": outputs})
    }

    fn publish(&self) {
        self.apply_couplings();
        let _ = self.hub.set(DOC, self.document(), None);
        for l in self.listeners.lock().expect("listeners").iter() {
            l(self);
        }
    }

    pub fn get(&self, key: &str, output: Option<&str>) -> Option<Provenanced> {
        self.cfg.lock().expect("config lock").resolve(key, output)
    }

    pub fn explain(&self, key: &str, output: Option<&str>) -> Vec<LayerValue> {
        let layers = self.cfg.lock().expect("config lock").explain(key, output);
        let n = layers.len();
        layers
            .into_iter()
            .enumerate()
            .map(|(i, l)| LayerValue {
                source: l.source,
                value: l.value,
                active: i + 1 == n,
                reason: l.reason.or(l.forced_by),
            })
            .collect()
    }

    pub fn apply(&self, ops: &[ApplyOp]) -> Result<Committed, Vec<OpError>> {
        let applied = {
            let mut cfg = self.cfg.lock().expect("config lock");
            cfg.apply(&to_ops(ops))
                .map_err(|errs| errs.into_iter().map(op_error).collect::<Vec<_>>())?
        };
        self.publish();
        Ok(Committed {
            rev: applied.rev,
            undo: applied.tx_id.unwrap_or_default(),
        })
    }

    /// Effective changes a batch would cause, without committing (PROTOCOL §5 `dry_run`).
    pub fn preview(&self, ops: &[ApplyOp]) -> Result<Vec<DiffEntry>, Vec<OpError>> {
        let diff = self
            .cfg
            .lock()
            .expect("config lock")
            .preview(&to_ops(ops))
            .map_err(|errs| errs.into_iter().map(op_error).collect::<Vec<_>>())?;
        Ok(diff_entries(&diff))
    }

    pub fn undo(&self, redo: bool) -> Result<Committed, Vec<OpError>> {
        let step = {
            let mut cfg = self.cfg.lock().expect("config lock");
            if redo { cfg.redo() } else { cfg.undo() }
        };
        match step {
            Ok(Some(a)) => {
                self.publish();
                Ok(Committed {
                    rev: a.rev,
                    undo: a.tx_id.unwrap_or_default(),
                })
            }
            Ok(None) => Err(refused(
                if redo {
                    "config.error.nothing_to_redo"
                } else {
                    "config.error.nothing_to_undo"
                },
                "nothing to do",
            )),
            Err(e) => Err(refused("config.error.user_file_unreadable", e.to_string())),
        }
    }

    /// External edit of `config.toml` / `managed.toml` (file watcher).
    pub fn reload(&self) {
        let diags = {
            let mut cfg = self.cfg.lock().expect("config lock");
            let mut d = cfg.reload_user_file().diagnostics;
            d.extend(cfg.reload_managed_file().diagnostics);
            d
        };
        for d in diags {
            tracing::warn!(file = %d.file.display(), key = %d.key, reason = d.reason.i18n_key(), "config diagnostic");
        }
        self.publish();
    }

    pub fn paths(&self) -> Paths {
        self.cfg.lock().expect("config lock").paths().clone()
    }

    /// `profile.list` / `profile.preview` / `profile.load` / `profile.save`.
    pub fn register_actions(self: &Arc<Self>, actions: &mut ActionRegistry) {
        fn args(v: &Value) -> (Option<String>, Option<Vec<String>>) {
            let name = v.get("name").and_then(Value::as_str).map(String::from);
            let sections = v.get("sections").and_then(Value::as_array).map(|a| {
                a.iter()
                    .filter_map(Value::as_str)
                    .map(String::from)
                    .collect()
            });
            (name, sections)
        }
        let invalid = |m: &str| ActionError::Invalid(m.into());

        let me = self.clone();
        actions.register("profile.list", "action.profile.list", move |_| {
            let me = me.clone();
            async move {
                let list: Vec<Value> = me
                    .cfg
                    .lock()
                    .expect("config lock")
                    .list_profiles()
                    .into_iter()
                    .map(|(name, _, bundled)| json!({"name": name, "bundled": bundled}))
                    .collect();
                Ok(Some(json!({"profiles": list})))
            }
        });
        let me = self.clone();
        actions.register("profile.preview", "action.profile.preview", move |v| {
            let me = me.clone();
            async move {
                let (name, sections) = args(&v);
                let name = name.ok_or_else(|| invalid("profile.preview needs name"))?;
                let secs: Option<Vec<&str>> = sections
                    .as_ref()
                    .map(|s| s.iter().map(String::as_str).collect());
                let diff = me
                    .cfg
                    .lock()
                    .expect("config lock")
                    .preview_profile(&name, secs.as_deref())
                    .map_err(|e| ActionError::Invalid(e.to_string()))?;
                Ok(Some(json!({"diff": diff_entries(&diff)})))
            }
        });
        let me = self.clone();
        actions.register("profile.load", "action.profile.load", move |v| {
            let me = me.clone();
            async move {
                let (name, sections) = args(&v);
                let name = name.ok_or_else(|| invalid("profile.load needs name"))?;
                let secs: Option<Vec<&str>> = sections
                    .as_ref()
                    .map(|s| s.iter().map(String::as_str).collect());
                let (applied, _) = me
                    .cfg
                    .lock()
                    .expect("config lock")
                    .load_profile(&name, secs.as_deref())
                    .map_err(|e| ActionError::Invalid(e.to_string()))?;
                me.publish();
                Ok(Some(json!({"rev": applied.rev, "undo": applied.tx_id})))
            }
        });
        let me = self.clone();
        actions.register("profile.save", "action.profile.save", move |v| {
            let me = me.clone();
            async move {
                let (name, sections) = args(&v);
                let name = name.ok_or_else(|| invalid("profile.save needs name"))?;
                let secs: Option<Vec<&str>> = sections
                    .as_ref()
                    .map(|s| s.iter().map(String::as_str).collect());
                let path = me
                    .cfg
                    .lock()
                    .expect("config lock")
                    .save_profile(&name, secs.as_deref())
                    .map_err(|e| ActionError::Invalid(e.to_string()))?;
                Ok(Some(json!({"path": path})))
            }
        });
    }
}

/// Watch the config directory and reload on external edits of `config.toml` / `managed.toml`
/// (debounced; our own writes produce an empty diff). Keep the returned watcher alive.
pub fn watch(store: Arc<ConfigStore>) -> notify::Result<notify::RecommendedWatcher> {
    use notify::{RecursiveMode, Watcher};
    let paths = store.paths();
    let names = [paths.user_file(), paths.managed_file()];
    let dir = names[0]
        .parent()
        .map(std::path::Path::to_path_buf)
        .unwrap_or_default();
    std::fs::create_dir_all(&dir).ok();
    let (tx, mut rx) = tokio::sync::mpsc::unbounded_channel::<()>();
    let mut watcher = notify::recommended_watcher(move |res: notify::Result<notify::Event>| {
        if let Ok(ev) = res
            && ev.paths.iter().any(|p| names.contains(p))
        {
            let _ = tx.send(());
        }
    })?;
    watcher.watch(&dir, RecursiveMode::NonRecursive)?;
    tokio::spawn(async move {
        while rx.recv().await.is_some() {
            // Editors write in bursts (temp file, rename, chmod): settle, then reload once.
            tokio::time::sleep(std::time::Duration::from_millis(150)).await;
            while rx.try_recv().is_ok() {}
            store.reload();
        }
    });
    Ok(watcher)
}
