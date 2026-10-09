//! Config store (M1.5): the schema registry behind `kurashi-config`, published as the `config`
//! and `schema.settings` documents, answering `cfg.*` / `apply` / `undo` / `redo`, the `profile.*`
//! actions (PROTOCOL §5, §6) and `settings.open` (I25, the Settings window).

use std::collections::{BTreeMap, BTreeSet, HashMap};
use std::ffi::{OsStr, OsString};
use std::os::unix::fs::PermissionsExt;
use std::os::unix::process::CommandExt;
use std::path::{Path, PathBuf};
use std::process::{Child, Command, Stdio};
use std::sync::{Arc, Mutex, OnceLock};
use std::time::{Duration, Instant};

use kurashi_config::{
    Config, ConfigError, DiagnosticReason, Op, Options, Paths, ProfileReview, SchemaView, Source,
};
use kurashi_core::Provenanced;
use kurashi_ipc::{ApplyOp, DiffEntry, LayerValue, OpError};
use kurashi_mods::{Manifest, ModState, Provide, Setting, SettingType, SettingValue};
use kurashi_schema::{Choice, Coupling, KeyMeta, Registry, Ty, validate_value};
use serde_json::{Map, Value, json};

use crate::actions::{ActionError, ActionRegistry};
use crate::hub::Hub;

pub const DOC: &str = "config";
pub const SETTINGS_DOC: &str = "schema.settings";
/// Reason of a `restart` key whose value differs from the one its service started with (K21).
pub const REASON_PENDING_RESTART: &str = "settings.pending.restart";
/// Reason of a mod setting whose mod is off: the value is kept and has no effect (K22, K21).
pub const REASON_MOD_DISABLED: &str = "mods.disabled";
/// Reason of a value outside the options its `choices_from` source offers (I9, K21).
pub const REASON_CHOICE_UNAVAILABLE: &str = "settings.choice.unavailable";
/// The island instance the `island.main.*` keys configure; its document lists the faces.
const ISLAND_DOC: &str = "runtime.island.main";
/// OSD faces: transient-only, never in the cycle, so they are no option of `island.*.faces`
/// (island.rs `apply_config`, K9).
const TRANSIENT_FACES: [&str; 2] = ["volume", "brightness"];
/// The choice sources the core offers (I9). A mod's `choices:<source>` may not take one of these
/// names: its offers would replace the core's.
pub const CORE_SOURCES: [&str; 2] = ["palettes", "island.faces"];

/// `kurashi-config` is schema-agnostic; this is the only place the two meet. Core keys come from
/// the static schema; the mods' lists `mods.loaded` / `mods.enabled` (K25) are hidden keys of
/// their own; mod settings (`mods.<id>.<key>`, K22) come from `mods`, rebuilt by
/// [`ConfigStore::sync_mods`] whenever the mods registry changes.
pub struct SchemaAdapter {
    core: &'static Registry,
    lists: Registry,
    mods: ModTable,
    /// Options of each `choices_from` source (I9), by source name. A source that is missing here
    /// is not known yet, so its values are not judged.
    offers: BTreeMap<String, Vec<Offer>>,
}

impl SchemaView for SchemaAdapter {
    fn version(&self) -> u32 {
        self.core.version()
    }
    fn default(&self, key: &str) -> Option<Value> {
        self.core
            .get(key)
            .or_else(|| self.lists.get(key))
            .map(|m| m.default.clone())
            .or_else(|| self.mods.find(key).map(|(_, m)| m.default.clone()))
    }
    fn validate(&self, key: &str, v: &Value) -> Result<(), String> {
        let checked = match self.mods.find(key) {
            Some((_, meta)) => validate_value(meta, v),
            None if self.lists.get(key).is_some() => self.lists.validate(key, v),
            None => self.core.validate(key, v),
        };
        checked.map_err(|e| e.i18n_key().into())
    }
    fn per_output(&self, key: &str) -> bool {
        self.core.get(key).is_some_and(|m| m.flags.per_output)
    }
    fn keys(&self) -> Vec<String> {
        self.core
            .keys()
            .chain(self.lists.keys())
            .map(String::from)
            .chain(self.mods.keys())
            .collect()
    }
}

/// `mods.loaded` and `mods.enabled` (K25): lists of mod ids, `enabled ⊆ loaded`. Both default to
/// empty: no bundled mod is on by default (CONTRACT row 61 — `easter-eggs` has no code in this build,
/// B15). Hidden from the generated pages: the Mods page and the mod pages drive them.
fn list_keys(version: u32) -> Registry {
    let key = |name: &str| {
        let mut m = KeyMeta::new(format!("mods.{name}"), Ty::StringList, json!([]));
        m.flags.hidden = true;
        m
    };
    Registry::from_keys(version, vec![key("loaded"), key("enabled")])
        .unwrap_or_else(|errs| panic!("mods list keys are inconsistent: {errs:?}"))
}

/// One option of a `choices_from` source (I9, PROTOCOL §5): what `schema.settings` lists.
#[derive(Clone, Debug, PartialEq)]
pub struct Offer {
    pub value: String,
    /// i18n key of the label.
    pub label: String,
    /// `false` with a `reason` for an option that cannot work now (a backend not installed).
    pub enabled: bool,
    pub reason: Option<String>,
}

impl Offer {
    fn on(value: &str, label: String) -> Self {
        Self {
            value: value.into(),
            label,
            enabled: true,
            reason: None,
        }
    }

    fn json(&self) -> Value {
        let mut v = json!({"value": self.value, "label": self.label});
        if !self.enabled {
            v["enabled"] = json!(false);
        }
        if let Some(r) = &self.reason {
            v["reason"] = json!(r);
        }
        v
    }
}

/// The options of every source the daemon can resolve now. `palettes` are the bundled palettes
/// (a mod's palette file cannot be loaded yet, so it is no option); `island.faces` are the faces
/// the island registered (`runtime.island.main`), without the OSD faces. `mod_faces` names the
/// faces a mod provides, with the mod's name as their label (I37); a core face has its catalogue key.
fn offers_now(hub: &Hub, mod_faces: &BTreeMap<String, String>) -> BTreeMap<String, Vec<Offer>> {
    let mut offers = BTreeMap::new();
    let mut palettes: Vec<Offer> = kurashi_theme::bundled_names()
        .into_iter()
        .map(|name| Offer::on(name, format!("config.choice.palette.{name}")))
        .collect();
    // K34: the wallpaper's own colours, offered while the wallpaper mod serves its document.
    if hub.snapshot(crate::theme::WALLPAPER_DOC).is_ok() {
        palettes.push(Offer::on(
            crate::theme::WALLPAPER_PALETTE,
            "config.choice.palette.wallpaper".into(),
        ));
    }
    offers.insert("palettes".to_string(), palettes);
    if let Ok((_, doc)) = hub.snapshot(ISLAND_DOC) {
        let faces = doc["faces"]
            .as_array()
            .into_iter()
            .flatten()
            .filter_map(Value::as_str)
            .filter(|f| !TRANSIENT_FACES.contains(f))
            .map(|f| {
                let label = mod_faces
                    .get(f)
                    .cloned()
                    .unwrap_or_else(|| format!("config.face.{f}"));
                Offer::on(f, label)
            })
            .collect();
        offers.insert("island.faces".to_string(), faces);
    }
    offers
}

/// The settings of every mod with a valid manifest (K22). A mod that is off keeps its entries, so
/// its stored values stay valid and are reported inert instead of being dropped.
#[derive(Default)]
struct ModTable {
    mods: Vec<ModSettings>,
}

struct ModSettings {
    id: String,
    /// The manifest's name: an i18n key or plain text. It titles the mod's settings page.
    name: String,
    /// Loaded (K25): the mod has a settings page, on or off.
    loaded: bool,
    /// On: its contributions are live, its settings take effect.
    enabled: bool,
    keys: Vec<KeyMeta>,
    /// The island faces it provides (`island-face:<name>`): labelled with its name (I37).
    faces: Vec<String>,
}

impl ModTable {
    fn from_registry(reg: &kurashi_mods::Registry) -> Self {
        let mods = reg
            .iter()
            .filter_map(|e| {
                let m = e.manifest.as_ref()?;
                let faces = m
                    .provides
                    .iter()
                    .filter_map(|p| match p {
                        Provide::IslandFace(f) => Some(f.clone()),
                        _ => None,
                    })
                    .collect();
                Some(ModSettings {
                    id: m.id.clone(),
                    name: m.name.clone(),
                    loaded: matches!(e.state, ModState::Disabled | ModState::Enabled),
                    enabled: e.state == ModState::Enabled,
                    keys: m.settings.iter().map(|s| setting_meta(m, s)).collect(),
                    faces,
                })
            })
            .collect();
        Self { mods }
    }

    /// Face id → the name of the mod that provides it (the label of its island offer).
    fn face_names(&self) -> BTreeMap<String, String> {
        self.mods
            .iter()
            .flat_map(|m| m.faces.iter().map(move |f| (f.clone(), m.name.clone())))
            .collect()
    }

    /// The mod that owns `key`, and the key's metadata.
    fn find(&self, key: &str) -> Option<(&ModSettings, &KeyMeta)> {
        self.mods
            .iter()
            .find_map(|m| m.keys.iter().find(|k| k.key == key).map(|k| (m, k)))
    }

    fn keys(&self) -> impl Iterator<Item = String> + '_ {
        self.mods
            .iter()
            .flat_map(|m| m.keys.iter().map(|k| k.key.clone()))
    }

    fn is_disabled(&self, key: &str) -> bool {
        self.find(key).is_some_and(|(m, _)| !m.enabled)
    }
}

/// Whether the offers of a `choices_from` source take `value`, a string or a list of strings.
/// `None` while the source is not known (nothing to judge).
fn offered(offers: &BTreeMap<String, Vec<Offer>>, source: &str, value: &Value) -> Option<bool> {
    let options = offers.get(source)?;
    let ok = |v: &Value| {
        v.as_str()
            .is_some_and(|s| options.iter().any(|o| o.enabled && o.value == s))
    };
    Some(match value {
        Value::Array(items) => items.iter().all(ok),
        v => ok(v),
    })
}

/// One manifest setting as the schema sees it. Same types, bounds and choices as the manifest, so
/// the schema's one validator (`validate_value`) rejects what the manifest rejects (K22).
fn setting_meta(m: &Manifest, s: &Setting) -> KeyMeta {
    let key = m.config_key(&s.key);
    let ty = match s.ty {
        SettingType::Bool => Ty::Bool,
        SettingType::Int => Ty::Int,
        SettingType::Float => Ty::Float,
        SettingType::String => Ty::String,
        SettingType::Enum => Ty::Choice,
        SettingType::Color => Ty::Color,
        // A `list` is a string list with fixed choices (I26): the schema's validator and `pick_list`.
        SettingType::List => Ty::StringList,
    };
    let default = match &s.default {
        SettingValue::Bool(b) => json!(b),
        SettingValue::Int(n) => json!(n),
        SettingValue::Float(f) => json!(f),
        SettingValue::Str(t) => json!(t),
        SettingValue::List(items) => json!(items),
    };
    let mut meta = KeyMeta::new(key.clone(), ty, default);
    // Labels are i18n keys like core keys; without one the derived key names the setting.
    meta.label = s.label.clone().unwrap_or_else(|| key.clone());
    meta.help = s.help.clone();
    meta.page = format!("mods.{}", m.id);
    meta.section = "general".into();
    meta.constraints.unit = s.unit.clone();
    if let Some((lo, hi)) = s.range {
        meta.constraints.min = Some(bound(s.ty, lo));
        meta.constraints.max = Some(bound(s.ty, hi));
    }
    meta.constraints.choices = s
        .choices
        .iter()
        .map(|c| Choice {
            value: c.clone(),
            label: format!("{key}.{c}"),
            text: String::new(),
        })
        .collect();
    // I9: the options come from the source at publish time, not from the manifest.
    meta.constraints.choices_from = s.choices_from.clone();
    meta
}

/// A range bound in the setting's own type: whole numbers for an int setting, so the page shows
/// `1`, not `1.0`.
fn bound(ty: SettingType, x: f64) -> Value {
    if ty == SettingType::Int && x.fract() == 0.0 {
        json!(x as i64)
    } else {
        json!(x)
    }
}

/// `schema.settings`: the core pages, then one page per loaded mod (K25), with or without
/// settings. The page id is `mods.<id>`, its title the mod's name (the frontend shows "Mods ›
/// name"), and `mod` names the mod so the sidebar can find its state. Rows whose `choices_from`
/// names a source carry that source's options (I9).
fn settings_document(
    core: &Registry,
    mods: &ModTable,
    offers: &BTreeMap<String, Vec<Offer>>,
) -> Value {
    let mut doc = kurashi_schema::settings_meta(core);
    let pages = doc["pages"]
        .as_array_mut()
        .expect("settings_meta lists its pages");
    for m in mods.mods.iter().filter(|m| m.loaded) {
        let mut page = json!({"id": format!("mods.{}", m.id), "label": m.name, "sections": []});
        if !m.keys.is_empty() {
            match Registry::from_keys(core.version(), m.keys.clone()) {
                Ok(reg) => {
                    page["sections"] =
                        kurashi_schema::settings_meta(&reg)["pages"][0]["sections"].take()
                }
                Err(errs) => tracing::warn!(mod_id = %m.id, ?errs, "mod settings left out"),
            }
        }
        page["mod"] = json!(m.id);
        pages.push(page);
    }
    for page in pages.iter_mut() {
        for section in page["sections"].as_array_mut().into_iter().flatten() {
            for row in section["rows"].as_array_mut().into_iter().flatten() {
                let Some(source) = row["choices_from"].as_str().map(String::from) else {
                    continue;
                };
                let options = offers
                    .get(&source)
                    .map_or_else(Vec::new, |o| o.iter().map(Offer::json).collect());
                row["choices"] = Value::Array(options);
            }
        }
    }
    doc
}

/// `mods.<id>.<key>` (K22): a mod's setting. `mods.loaded` and `mods.enabled` are the lists, which
/// are always known and so keep their diagnostics.
fn is_mod_key(key: &str) -> bool {
    key.strip_prefix("mods.")
        .is_some_and(|rest| rest.contains('.'))
}

type Listener = Box<dyn Fn(&ConfigStore) + Send + Sync>;

pub struct ConfigStore {
    cfg: Mutex<Config<SchemaAdapter>>,
    hub: Arc<Hub>,
    registry: &'static Registry,
    /// `forced:accessibility` entries currently applied (only rewritten when they change).
    a11y_forced: Mutex<Vec<(String, Value, String)>>,
    /// Effective value of each `restart` key when the daemon started: what its service runs with.
    started: OnceLock<HashMap<String, Value>>,
    listeners: Mutex<Vec<Listener>>,
    /// Options of the mods' choice sources (K28 (3)), by source name. A source a manifest declares
    /// is known here even while its mod is off (no options): its values are then inert, not unjudged.
    mod_sources: Mutex<BTreeMap<String, Vec<Offer>>>,
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

/// `profile.list`'s answer and the `config` document's `profiles` (K27): one list, one order.
fn profile_entries(cfg: &Config<SchemaAdapter>) -> Vec<Value> {
    cfg.list_profiles()
        .into_iter()
        .map(|(name, _, bundled)| json!({"name": name, "bundled": bundled}))
        .collect()
}

/// A profile request without a usable name is refused as an invalid name.
const PROFILE_INVALID_NAME: &str = "config.error.profile_invalid_name";
/// A profile file path that is missing or not absolute: the daemon does not resolve it against its
/// own working directory.
const PROFILE_PATH: &str = "config.error.profile_path";
/// Arguments of an action missing or of the wrong type (catalogue: session domain).
const ARGS_INVALID: &str = "error.args.invalid";
/// `settings.open` of a key no layer knows (catalogue: schema domain, with `{key}`).
const UNKNOWN_KEY: &str = "error.config.unknown_key";
/// `settings.open` without a Settings directory (`shell.qml` missing) or without `qs` on the PATH.
const SETTINGS_NOT_INSTALLED: &str = "error.settings.not_installed";
const SETTINGS_NO_RUNTIME: &str = "error.settings.no_runtime";

/// The profile review as the actions answer it: the effective changes and the entries a forced
/// layer holds back (`not_applied`, PROTOCOL §6).
fn review_json(r: &ProfileReview) -> Value {
    json!({"diff": diff_entries(&r.diff), "not_applied": r.not_applied})
}

/// A profile file path argument: absolute, or refused.
fn absolute_path(v: &Value) -> Result<PathBuf, ActionError> {
    let path = PathBuf::from(v.get("path").and_then(Value::as_str).unwrap_or_default());
    if path.is_absolute() {
        Ok(path)
    } else {
        Err(ActionError::Invalid(PROFILE_PATH.into()))
    }
}

/// `apply` of `profile.import`: absent means review only; anything but a boolean is refused.
fn apply_flag(v: &Value) -> Result<bool, ActionError> {
    match v.get("apply") {
        None => Ok(false),
        Some(Value::Bool(b)) => Ok(*b),
        Some(_) => Err(ActionError::Invalid(ARGS_INVALID.into())),
    }
}

/// A refused profile action as its i18n key (K27, B5). The engine's text is English detail and
/// never goes on the wire: the key says what is wrong, the catalog says what to do about it.
fn profile_refusal(e: ConfigError) -> ActionError {
    let key = match &e {
        ConfigError::ProfileNotFound(_) => "config.error.profile_not_found",
        ConfigError::InvalidProfileName(_) => PROFILE_INVALID_NAME,
        // A syntax error is for the user to fix; any other read failure is the file itself.
        ConfigError::Unreadable(diags)
            if diags
                .iter()
                .any(|d| matches!(d.reason, DiagnosticReason::Parse { .. })) =>
        {
            "config.error.profile_parse"
        }
        ConfigError::Unreadable(_) => "config.error.profile_unreadable",
        ConfigError::Io { .. } => "config.error.profile_write",
        // The engine refuses with a catalog key when config.toml itself cannot be used.
        ConfigError::Refused(key) if key == "config.error.user_file_unreadable" => {
            "config.error.user_file_unreadable"
        }
        ConfigError::Refused(_) => "config.error.profile_write",
    };
    ActionError::Invalid(key.into())
}

impl ConfigStore {
    pub fn open(
        hub: Arc<Hub>,
        registry: &'static Registry,
        paths: Paths,
        opts: Options,
    ) -> Arc<Self> {
        // No mods yet: their face labels follow with `sync_mods`.
        let offers = offers_now(&hub, &BTreeMap::new());
        let schema = SchemaAdapter {
            core: registry,
            lists: list_keys(registry.version()),
            mods: ModTable::default(),
            offers: offers.clone(),
        };
        let cfg = Config::open(schema, paths, opts);
        // Mod keys are unknown until the mods registry is discovered (`sync_mods`); their
        // diagnostics wait for that instead of warning on every start.
        for d in cfg.diagnostics().iter().filter(|d| !is_mod_key(&d.key)) {
            tracing::warn!(file = %d.file.display(), key = %d.key, reason = d.reason.i18n_key(), "config diagnostic");
        }
        hub.register(
            SETTINGS_DOC,
            settings_document(registry, &ModTable::default(), &offers),
            None,
        );
        let store = Arc::new(ConfigStore {
            cfg: Mutex::new(cfg),
            hub: hub.clone(),
            registry,
            a11y_forced: Mutex::new(Vec::new()),
            started: OnceLock::new(),
            listeners: Mutex::new(Vec::new()),
            mod_sources: Mutex::new(BTreeMap::new()),
        });
        store.apply_couplings();
        store.remember_started();
        hub.register(DOC, store.document(), None);
        store
    }

    /// Records the `restart` keys' effective values once, after the couplings forced what they
    /// force: a later difference is pending until the next start (K21). Restart keys are global;
    /// a per-output one would need per-output starts (the honesty test asserts there is none).
    fn remember_started(&self) {
        let cfg = self.cfg.lock().expect("config lock");
        let started = self
            .registry
            .iter()
            .filter(|m| m.flags.restart)
            .filter_map(|m| cfg.resolve(&m.key, None).map(|p| (m.key.clone(), p.value)))
            .collect();
        self.started
            .set(started)
            .expect("restart values are taken once, at open");
    }

    /// Run `f` after every effective change (theme recompute, island config, …).
    pub fn on_change(&self, f: impl Fn(&ConfigStore) + Send + Sync + 'static) {
        self.listeners.lock().expect("listeners").push(Box::new(f));
    }

    /// Schema couplings the daemon evaluates (ARCHITECTURE §3): `overridden_by` a11y modes
    /// become `forced:accessibility` entries with `forced_by` = the mode key, so the UI shows
    /// why a control is inert instead of silently ignoring it (Shōjiki).
    fn apply_couplings(&self) {
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

    /// `{"values":{key: Provenanced}, "outputs":{name:{key: Provenanced}}, "history":{can_undo,
    /// can_redo}, "profiles":[{name, bundled}]}` — rebuilt whole and diffed by the hub, so patches
    /// carry exactly what changed (K17). An output with values of its own lists every per-output
    /// key, so a key inert on that output alone says so without an override of its own: the view
    /// falls back to the global entry, and must not have to evaluate `requires` itself (K21).
    /// `history` and `profiles` are the daemon's own state, pushed so no client keeps a copy (K27).
    pub fn document(&self) -> Value {
        let cfg = self.cfg.lock().expect("config lock");
        let keys = cfg.schema().keys();
        let mut values = Map::new();
        for key in &keys {
            if let Some(p) = cfg.resolve(key, None) {
                values.insert(key.clone(), json!(self.decorate(&cfg, key, None, p)));
            }
        }
        let explicit: Vec<(&String, BTreeSet<String>)> =
            keys.iter().map(|k| (k, cfg.outputs_for(k))).collect();
        let named: BTreeSet<String> = explicit
            .iter()
            .flat_map(|(_, outs)| outs.iter().cloned())
            .collect();
        let mut outputs: Map<String, Value> = Map::new();
        for out in &named {
            let mut scope = Map::new();
            for (key, own) in &explicit {
                if !(own.contains(out) || cfg.schema().per_output(key)) {
                    continue;
                }
                let scoped = Some(out.as_str());
                if let Some(p) = cfg.resolve(key, scoped) {
                    scope.insert(key.to_string(), json!(self.decorate(&cfg, key, scoped, p)));
                }
            }
            outputs.insert(out.clone(), Value::Object(scope));
        }
        json!({
            "values": values,
            "outputs": outputs,
            "history": {"can_undo": cfg.can_undo(), "can_redo": cfg.can_redo()},
            "profiles": profile_entries(&cfg),
        })
    }

    /// K21: the provenance `cfg.get`, `cfg.explain` and the `config` document all report, so they
    /// agree. A reason a forced layer already gave stays: the value was replaced, which is the
    /// stronger statement, and the honesty test pins that reason. Otherwise a `requires` coupling
    /// that does not hold makes the key inert, `inert_by` naming the key it waits on (read in the
    /// same output scope). Failing that, a restart key running another value than at start is
    /// pending. The value and source never change.
    fn decorate(
        &self,
        cfg: &Config<SchemaAdapter>,
        key: &str,
        output: Option<&str>,
        mut p: Provenanced,
    ) -> Provenanced {
        if p.reason.is_some() {
            return p;
        }
        // K22: a mod that is off keeps its settings. They are configured, not in effect.
        if cfg.schema().mods.is_disabled(key) {
            p.reason = Some(REASON_MOD_DISABLED.into());
            return p;
        }
        let value_of = |k: &str| cfg.resolve(k, output).map(|q| q.value);
        // A mod's setting is not in the core registry: its metadata is the mod table's (K22).
        let meta = self
            .registry
            .get(key)
            .or_else(|| cfg.schema().mods.find(key).map(|(_, m)| m));
        let requires = meta.and_then(|m| {
            m.couplings.iter().find_map(|c| match c {
                Coupling::Requires { key: by, .. } if c.blocks(&value_of, &|_: &str| true) => {
                    Some((c.reason_key(), by.clone()))
                }
                _ => None,
            })
        });
        let choice_gone = meta
            .and_then(|m| m.constraints.choices_from.as_deref())
            .and_then(|source| offered(&cfg.schema().offers, source, &p.value))
            == Some(false);
        if let Some((reason, by)) = requires {
            p.reason = Some(reason.into());
            p.inert_by = Some(by);
        } else if choice_gone {
            // I9: never rejected, just not in effect while the source does not offer it.
            p.reason = Some(REASON_CHOICE_UNAVAILABLE.into());
        } else if self
            .started
            .get()
            .and_then(|s| s.get(key))
            .is_some_and(|start| *start != p.value)
        {
            p.reason = Some(REASON_PENDING_RESTART.into());
        }
        p
    }

    pub fn registry(&self) -> &'static Registry {
        self.registry
    }

    /// Pins (`Some`) or unpins (`None`) `key` in `forced:capability` and republishes.
    /// Used by `capabilities::apply`.
    pub fn force_capability(&self, key: &str, forced: Option<kurashi_config::Forced>) {
        {
            let mut cfg = self.cfg.lock().expect("config lock");
            let slot = (key.to_string(), None);
            match forced {
                Some(f) => {
                    if let Err(e) = cfg.set_forced("capability", slot, f) {
                        tracing::warn!(%key, error = %e, "cannot force capability coupling");
                        return;
                    }
                }
                None => {
                    cfg.clear_forced("capability", Some(&slot));
                }
            }
        }
        self.publish();
    }

    /// Mod settings (K22): the keys of every valid mod (`mods.<id>.<key>`) join the schema, the
    /// loaded mods get their pages, and stored values are read again and validated. Call after
    /// discovery (and after a rescan of the mods registry); changes of state go through
    /// [`ConfigStore::adopt_mods`] instead.
    pub fn sync_mods(&self, reg: &kurashi_mods::Registry) {
        {
            let mut cfg = self.cfg.lock().expect("config lock");
            cfg.schema_mut().mods = ModTable::from_registry(reg);
            cfg.refresh_keys();
            for d in cfg.diagnostics().iter().filter(|d| is_mod_key(&d.key)) {
                tracing::warn!(file = %d.file.display(), key = %d.key, reason = d.reason.i18n_key(), "config diagnostic");
            }
        }
        self.publish();
    }

    /// A mod was loaded, enabled, disabled or unloaded: its pages and the reasons of its values
    /// follow. Unlike [`ConfigStore::sync_mods`] this neither re-reads files nor runs the change
    /// listeners, so a listener (the mods reconcile) may call it.
    pub fn adopt_mods(&self, reg: &kurashi_mods::Registry) {
        self.cfg.lock().expect("config lock").schema_mut().mods = ModTable::from_registry(reg);
        self.publish_settings();
        self.publish_document();
    }

    /// The string list at `key` as it takes effect (`mods.loaded`, `mods.enabled`); empty when
    /// there is none.
    pub fn string_list(&self, key: &str) -> Vec<String> {
        self.get(key, None)
            .and_then(|p| p.value.as_array().cloned())
            .unwrap_or_default()
            .iter()
            .filter_map(|v| v.as_str().map(String::from))
            .collect()
    }

    /// Whether a forced layer (managed `_managed.enforce`, a capability pin) decides `key`: a
    /// change written to it has no effect, so the caller refuses it.
    pub fn is_forced(&self, key: &str) -> bool {
        self.get(key, None)
            .is_some_and(|p| matches!(p.source, Source::Forced(_)))
    }

    fn publish(&self) {
        self.apply_couplings();
        self.publish_settings();
        let _ = self.hub.set(DOC, self.document(), None);
        for l in self.listeners.lock().expect("listeners").iter() {
            l(self);
        }
    }

    /// Republishes `schema.settings` with the sources' current options, for a source that changed
    /// without a config change (the island registered a face, a mod's palette came and went). The
    /// `config` document follows, since a value may now be outside its options (I9).
    pub fn refresh_choices(&self) {
        self.publish_settings();
        self.publish_document();
    }

    /// Replaces the options of every mod choice source (K28 (3)). The native mods send the whole
    /// table after each registry change: a declared source offers what its enabled mod returns, and
    /// an empty list when the mod is off, so the values that name it are inert, not unjudged.
    pub fn set_mod_sources(&self, sources: BTreeMap<String, Vec<Offer>>) {
        *self.mod_sources.lock().expect("mod sources") = sources;
        self.refresh_choices();
    }

    /// One mod choice source's options changed (`ChoicesHandle::changed`, K28 (3)).
    pub fn set_mod_source(&self, source: &str, options: Vec<Offer>) {
        self.mod_sources
            .lock()
            .expect("mod sources")
            .insert(source.to_string(), options);
        self.refresh_choices();
    }

    /// `schema.settings` with the sources' current options: the island's faces change with what
    /// it registers, the mods' pages with their state. Republished whole; an unchanged document is
    /// no patch (hub).
    fn publish_settings(&self) {
        // The mods' face names are read under their own lock first: `offers_now` reads the hub.
        let mod_faces = self
            .cfg
            .lock()
            .expect("config lock")
            .schema()
            .mods
            .face_names();
        let mut offers = offers_now(&self.hub, &mod_faces);
        for (source, options) in self.mod_sources.lock().expect("mod sources").iter() {
            // A core source keeps its own options (the native mods refuse those names).
            offers
                .entry(source.clone())
                .or_insert_with(|| options.clone());
        }
        let page = {
            let mut cfg = self.cfg.lock().expect("config lock");
            cfg.schema_mut().offers = offers;
            let schema = cfg.schema();
            settings_document(self.registry, &schema.mods, &schema.offers)
        };
        let _ = self.hub.set(SETTINGS_DOC, page, None);
    }

    /// Republishes the `config` document alone, for a change of the profiles only: no value in
    /// effect moved, so the couplings and the listeners stay as they are.
    fn publish_document(&self) {
        let _ = self.hub.set(DOC, self.document(), None);
    }

    pub fn get(&self, key: &str, output: Option<&str>) -> Option<Provenanced> {
        let cfg = self.cfg.lock().expect("config lock");
        let p = cfg.resolve(key, output)?;
        Some(self.decorate(&cfg, key, output, p))
    }

    pub fn explain(&self, key: &str, output: Option<&str>) -> Vec<LayerValue> {
        let cfg = self.cfg.lock().expect("config lock");
        let layers = cfg.explain(key, output);
        // The active layer states the reason `cfg.get` reports, so the two cannot disagree (K21).
        let shown = cfg
            .resolve(key, output)
            .map(|p| self.decorate(&cfg, key, output, p));
        let n = layers.len();
        layers
            .into_iter()
            .enumerate()
            .map(|(i, l)| {
                let active = i + 1 == n;
                let reason = match (active, &shown) {
                    (true, Some(p)) => p.reason.clone().or_else(|| p.forced_by.clone()),
                    _ => l.reason.or(l.forced_by),
                };
                LayerValue {
                    source: l.source,
                    value: l.value,
                    active,
                    reason,
                }
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

    /// Current file diagnostics (`kurashi doctor`).
    pub fn diagnostics(&self) -> Vec<kurashi_config::Diagnostic> {
        self.cfg.lock().expect("config lock").diagnostics()
    }

    pub fn paths(&self) -> Paths {
        self.cfg.lock().expect("config lock").paths().clone()
    }

    /// `profile.*` and `settings.open` (the daemon's Settings launcher, [`SettingsApp::from_env`]).
    pub fn register_actions(self: &Arc<Self>, actions: &mut ActionRegistry) {
        self.register_actions_with(actions, SettingsApp::from_env());
    }

    /// `profile.list` / `profile.preview` / `profile.load` / `profile.save` / `profile.export` /
    /// `profile.import` (PROTOCOL §6) and `settings.open` through `app`. Refusals carry i18n keys
    /// (`config.error.profile_*`, K27); the list is also pushed in the `config` document.
    pub fn register_actions_with(self: &Arc<Self>, actions: &mut ActionRegistry, app: SettingsApp) {
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
        let no_name = || ActionError::Invalid(PROFILE_INVALID_NAME.into());

        let me = self.clone();
        actions.register("profile.list", "action.profile.list", move |_| {
            let me = me.clone();
            async move {
                let list = profile_entries(&me.cfg.lock().expect("config lock"));
                Ok(Some(json!({"profiles": list})))
            }
        });
        let me = self.clone();
        actions.register("profile.preview", "action.profile.preview", move |v| {
            let me = me.clone();
            async move {
                let (name, sections) = args(&v);
                let name = name.ok_or_else(&no_name)?;
                let secs: Option<Vec<&str>> = sections
                    .as_ref()
                    .map(|s| s.iter().map(String::as_str).collect());
                let review = me
                    .cfg
                    .lock()
                    .expect("config lock")
                    .preview_profile(&name, secs.as_deref())
                    .map_err(profile_refusal)?;
                Ok(Some(review_json(&review)))
            }
        });
        let me = self.clone();
        actions.register("profile.load", "action.profile.load", move |v| {
            let me = me.clone();
            async move {
                let (name, sections) = args(&v);
                let name = name.ok_or_else(&no_name)?;
                let secs: Option<Vec<&str>> = sections
                    .as_ref()
                    .map(|s| s.iter().map(String::as_str).collect());
                let loaded = me
                    .cfg
                    .lock()
                    .expect("config lock")
                    .load_profile(&name, secs.as_deref())
                    .map_err(profile_refusal)?;
                me.publish();
                Ok(Some(json!({
                    "rev": loaded.applied.rev,
                    "undo": loaded.applied.tx_id,
                    "not_applied": loaded.not_applied,
                })))
            }
        });
        let me = self.clone();
        actions.register("profile.save", "action.profile.save", move |v| {
            let me = me.clone();
            async move {
                let (name, sections) = args(&v);
                let name = name.ok_or_else(&no_name)?;
                let secs: Option<Vec<&str>> = sections
                    .as_ref()
                    .map(|s| s.iter().map(String::as_str).collect());
                let path = me
                    .cfg
                    .lock()
                    .expect("config lock")
                    .save_profile(&name, secs.as_deref())
                    .map_err(profile_refusal)?;
                // The file is listed now; the watcher's (debounced) publish would only repeat this.
                me.publish_document();
                Ok(Some(json!({"path": path})))
            }
        });
        let me = self.clone();
        actions.register("profile.export", "action.profile.export", move |v| {
            let me = me.clone();
            async move {
                let (name, _) = args(&v);
                let name = name.ok_or_else(&no_name)?;
                let path = absolute_path(&v)?;
                let exported = me
                    .cfg
                    .lock()
                    .expect("config lock")
                    .export_profile(&name, &path)
                    .map_err(profile_refusal)?;
                Ok(Some(
                    json!({"path": exported.path, "left_out": exported.left_out}),
                ))
            }
        });
        let me = self.clone();
        actions.register("profile.import", "action.profile.import", move |v| {
            let me = me.clone();
            async move {
                let path = absolute_path(&v)?;
                let apply = apply_flag(&v)?;
                let (_, sections) = args(&v);
                let secs: Option<Vec<&str>> = sections
                    .as_ref()
                    .map(|s| s.iter().map(String::as_str).collect());
                let name = path
                    .file_stem()
                    .and_then(|s| s.to_str())
                    .unwrap_or_default()
                    .to_string();
                if !apply {
                    let review = me
                        .cfg
                        .lock()
                        .expect("config lock")
                        .review_profile_file(&path, secs.as_deref())
                        .map_err(profile_refusal)?;
                    let mut out = review_json(&review);
                    out["name"] = json!(name);
                    out["diagnostics"] = json!(review.diff.diagnostics);
                    return Ok(Some(out));
                }
                let loaded = me
                    .cfg
                    .lock()
                    .expect("config lock")
                    .load_profile_file(&path, secs.as_deref())
                    .map_err(profile_refusal)?;
                me.publish();
                Ok(Some(json!({
                    "name": name,
                    "rev": loaded.applied.rev,
                    "undo": loaded.applied.tx_id,
                    "not_applied": loaded.not_applied,
                    "diagnostics": loaded.diagnostics,
                })))
            }
        });
        let app = Arc::new(app);
        let me = self.clone();
        actions.register("settings.open", "action.settings.open", move |v| {
            let me = me.clone();
            let app = app.clone();
            async move {
                let key = match v.get("key") {
                    None | Some(Value::Null) => None,
                    Some(Value::String(k)) if !k.is_empty() => Some(k.clone()),
                    Some(_) => return Err(ActionError::Invalid(ARGS_INVALID.into())),
                };
                // A page link needs Settings to read a page at start, which it cannot yet (PROTOCOL §6).
                if v.get("page").is_some() {
                    return Err(ActionError::Invalid(ARGS_INVALID.into()));
                }
                if let Some(k) = &key
                    && me.get(k, None).is_none()
                {
                    return Err(ActionError::Invalid(UNKNOWN_KEY.into()));
                }
                // Probing and starting block (a `qs` call that waits for its reply): off the runtime.
                let how = tokio::task::spawn_blocking(move || app.open(key.as_deref()))
                    .await
                    .map_err(|e| ActionError::Internal(e.to_string()))??;
                Ok(Some(json!({"opened": how})))
            }
        });
    }
}

/// The Settings window (`settings/`, a Quickshell config; I25, I36): the daemon opens it on a
/// setting, or jumps the window that already runs. The window starts as a program with its
/// arguments, never through a shell, and outside the daemon's process group.
#[derive(Debug, Clone)]
pub struct SettingsApp {
    /// What `qs -p` loads: `<data dir>/settings`, the package's copy.
    pub dir: PathBuf,
    /// Where `qs` is looked up: the PATH the daemon runs with (tests pass their own).
    pub path: OsString,
}

/// How long one `qs ipc` probe may take before it counts as "no window".
const PROBE_TIMEOUT: Duration = Duration::from_secs(2);

impl SettingsApp {
    pub fn from_env() -> Self {
        Self {
            dir: crate::i18n::data_dir().join("settings"),
            path: std::env::var_os("PATH").unwrap_or_default(),
        }
    }

    /// Opens Settings on `key`, or shows it without one. Answers `jumped` (a running window moved
    /// to `key`), `open` (a running window, no key) or `launched` (a new window, with
    /// `KURASHI_SETTINGS_KEY` set to `key`).
    pub fn open(&self, key: Option<&str>) -> Result<&'static str, ActionError> {
        if !self.dir.join("shell.qml").is_file() {
            return Err(ActionError::Unavailable(SETTINGS_NOT_INSTALLED.into()));
        }
        let qs = find_program("qs", &self.path)
            .ok_or_else(|| ActionError::Unavailable(SETTINGS_NO_RUNTIME.into()))?;
        match key {
            Some(key) if probe(&qs, &self.dir, &["jump", key]) => return Ok("jumped"),
            None if probe(&qs, &self.dir, &["current"]) => return Ok("open"),
            _ => {}
        }
        let mut cmd = Command::new(&qs);
        cmd.arg("-p")
            .arg(&self.dir)
            .stdin(Stdio::null())
            .stdout(Stdio::null())
            .stderr(Stdio::null())
            .process_group(0);
        match key {
            Some(key) => cmd.env("KURASHI_SETTINGS_KEY", key),
            None => cmd.env_remove("KURASHI_SETTINGS_KEY"),
        };
        let child = cmd.spawn().map_err(|e| {
            tracing::warn!(error = %e, "settings window did not start");
            ActionError::Unavailable(SETTINGS_NO_RUNTIME.into())
        })?;
        reap(child);
        Ok("launched")
    }
}

/// The first executable `name` on `path`.
fn find_program(name: &str, path: &OsStr) -> Option<PathBuf> {
    std::env::split_paths(path)
        .map(|dir| dir.join(name))
        .find(|p| {
            p.metadata()
                .is_ok_and(|m| m.is_file() && m.permissions().mode() & 0o111 != 0)
        })
}

/// Whether `qs -p <dir> ipc call settings <args>` answers, i.e. a Settings window runs. A probe
/// that does not finish within [`PROBE_TIMEOUT`] counts as no window.
fn probe(qs: &Path, dir: &Path, args: &[&str]) -> bool {
    let spawned = Command::new(qs)
        .arg("-p")
        .arg(dir)
        .args(["ipc", "call", "settings"])
        .args(args)
        .stdin(Stdio::null())
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .spawn();
    let Ok(mut child) = spawned else {
        return false;
    };
    let deadline = Instant::now() + PROBE_TIMEOUT;
    loop {
        match child.try_wait() {
            Ok(Some(status)) => return status.success(),
            Ok(None) if Instant::now() < deadline => std::thread::sleep(Duration::from_millis(10)),
            _ => {
                let _ = child.kill();
                let _ = child.wait();
                return false;
            }
        }
    }
}

/// Waits for a started window on a thread of its own, so it does not stay a zombie of the daemon.
fn reap(mut child: Child) {
    let spawned = std::thread::Builder::new()
        .name("settings-window".into())
        .spawn(move || {
            let _ = child.wait();
        });
    if let Err(e) = spawned {
        tracing::warn!(error = %e, "settings window not reaped");
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn a_mod_face_is_labelled_with_the_mod_name() {
        let hub = Hub::new();
        hub.register(
            "runtime.island.main",
            json!({"faces": ["clock", "weather", "bluetooth", "volume"]}),
            None,
        );
        let mods = BTreeMap::from([("weather".to_string(), "mods.weather.name".to_string())]);
        let offers = offers_now(&hub, &mods);
        let faces = &offers["island.faces"];
        let label = |v: &str| faces.iter().find(|o| o.value == v).map(|o| o.label.clone());
        assert_eq!(label("weather").as_deref(), Some("mods.weather.name"));
        assert_eq!(label("bluetooth").as_deref(), Some("config.face.bluetooth"));
        assert_eq!(label("volume"), None, "OSD faces are not offered");
    }
}

/// What a burst of file events touched: a config file (everything is reloaded), or only files in
/// the profiles directory (the `profiles` list is republished).
#[derive(Clone, Copy, PartialEq, Eq)]
enum Touched {
    Config,
    Profiles,
}

/// `profiles/<name>.toml`, or the profiles directory itself (created or removed: the list changes).
fn is_profile_event(path: &std::path::Path, profiles: &std::path::Path) -> bool {
    path == profiles
        || (path.parent() == Some(profiles) && path.extension().is_some_and(|x| x == "toml"))
}

/// Watch the config directory and reload on external edits of `config.toml` / `managed.toml`
/// (debounced; our own writes produce an empty diff). Files in `profiles/` (K27) are watched too,
/// so the `profiles` list follows them without a reconnect. The watch is recursive because
/// `profiles/` may not exist yet: a watch on it alone would have to wait for its creation. Keep the
/// returned watcher alive.
pub fn watch(store: Arc<ConfigStore>) -> notify::Result<notify::RecommendedWatcher> {
    use notify::{RecursiveMode, Watcher};
    let paths = store.paths();
    let names = [paths.user_file(), paths.managed_file()];
    let profiles = paths.user_profiles_dir();
    let dir = paths.config_dir.clone();
    std::fs::create_dir_all(&dir).ok();
    let (tx, mut rx) = tokio::sync::mpsc::unbounded_channel::<Touched>();
    let mut watcher = notify::recommended_watcher(move |res: notify::Result<notify::Event>| {
        let Ok(ev) = res else { return };
        if ev.paths.iter().any(|p| names.contains(p)) {
            let _ = tx.send(Touched::Config);
        } else if ev.paths.iter().any(|p| is_profile_event(p, &profiles)) {
            let _ = tx.send(Touched::Profiles);
        }
    })?;
    watcher.watch(&dir, RecursiveMode::Recursive)?;
    tokio::spawn(async move {
        while let Some(first) = rx.recv().await {
            // Editors write in bursts (temp file, rename, chmod): settle, then act once.
            tokio::time::sleep(std::time::Duration::from_millis(150)).await;
            let mut touched = first;
            while let Ok(next) = rx.try_recv() {
                if next == Touched::Config {
                    touched = Touched::Config;
                }
            }
            match touched {
                // Reloads and publishes the whole `config` document.
                Touched::Config => store.reload(),
                Touched::Profiles => store.publish_document(),
            }
        }
    });
    Ok(watcher)
}
