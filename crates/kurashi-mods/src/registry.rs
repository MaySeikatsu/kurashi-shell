//! Discovery + live load/enable state. Pure data: the daemon turns `Change`s into registrations.
//!
//! States (MODS.md "States, persistence and Settings", K25): `available` (found, not loaded),
//! `disabled` (loaded: manifest and settings known, contributions off), `enabled` (on) and
//! `invalid`. The daemon keeps the registry equal to the config lists (`mods.loaded`,
//! `mods.enabled`) through [`Registry::reconcile`].

use crate::manifest::{self, Manifest, Provide, Setting, ValidationError};
use semver::Version;
use serde::Serialize;
use serde_json::{Value, json};
use std::collections::{BTreeMap, BTreeSet};
use std::path::{Path, PathBuf};

#[derive(Debug, Clone, PartialEq, Serialize)]
#[serde(tag = "type", rename_all = "kebab-case")]
pub enum Contribution {
    Provides {
        mod_id: String,
        provide: Provide,
    },
    /// A typed setting; `config_key` is `mods.<id>.<key>` (K22).
    Setting {
        mod_id: String,
        config_key: String,
        setting: Setting,
    },
}

/// What one registry call registered or removed. Settings are registered while a mod is loaded
/// (off or on), provides only while it is enabled.
#[derive(Debug, Clone, Default, PartialEq, Serialize)]
pub struct Change {
    pub added: Vec<Contribution>,
    pub removed: Vec<Contribution>,
}

#[derive(Debug, Clone, PartialEq)]
pub enum ModState {
    Available,
    Enabled,
    Disabled,
    Invalid { errors: Vec<ValidationError> },
}

impl ModState {
    pub fn name(&self) -> &'static str {
        match self {
            Self::Available => "available",
            Self::Enabled => "enabled",
            Self::Disabled => "disabled",
            Self::Invalid { .. } => "invalid",
        }
    }
}

#[derive(Debug, Clone, PartialEq)]
pub enum ModsError {
    Unknown(String),
    /// Invalid mods cannot be loaded or enabled; Settings shows their errors instead.
    Invalid(String),
    Conflict {
        mod_id: String,
        other: String,
        provide: String,
        other_provide: String,
    },
}

impl ModsError {
    pub fn i18n_key(&self) -> &'static str {
        match self {
            Self::Unknown(_) => "mods.error.unknown_mod",
            Self::Invalid(_) => "mods.error.not_enableable",
            Self::Conflict { .. } => "mods.error.provide_conflict",
        }
    }
}

/// A mod directory hidden by a same-id mod from a later (higher-precedence) root.
#[derive(Debug, Clone, PartialEq)]
pub struct Shadow {
    pub id: String,
    pub winner: PathBuf,
    pub shadowed: PathBuf,
}

#[derive(Debug, Clone)]
pub struct ModEntry {
    pub id: String,
    pub dir: PathBuf,
    pub manifest: Option<Manifest>,
    pub state: ModState,
    /// Why the mod runs now, as i18n keys (`mods` doc `running_reasons`, K25 "Running now"): a
    /// service has a subscriber, a background job is started (I23). The daemon sets it through
    /// [`Registry::set_running_reasons`]; `running` in the document is "any reason".
    pub running_reasons: Vec<String>,
}

/// Policy as data: bundled mods are off unless listed (MODS.md: only `easter-eggs`). Used when
/// there is no config store to hold the lists.
#[derive(Debug, Clone, Default)]
pub struct Policy {
    pub default_enabled: BTreeSet<String>,
}

#[derive(Debug, Clone)]
pub struct Registry {
    mods: BTreeMap<String, ModEntry>,
    pub shadows: Vec<Shadow>,
}

impl Registry {
    /// Scan `roots` (lowest precedence first; a later root shadows an earlier one with the same
    /// id). Broken manifests never abort the scan: they become `Invalid` entries.
    pub fn discover(roots: &[PathBuf], daemon: &Version) -> Self {
        let mut mods: BTreeMap<String, ModEntry> = BTreeMap::new();
        let mut shadows = Vec::new();
        for root in roots {
            let Ok(rd) = std::fs::read_dir(root) else {
                continue;
            };
            let mut dirs: Vec<PathBuf> = rd
                .flatten()
                .map(|e| e.path())
                .filter(|p| p.is_dir())
                .collect();
            dirs.sort();
            for dir in dirs {
                let Some(id) = dir.file_name().and_then(|n| n.to_str()).map(str::to_owned) else {
                    continue;
                };
                let entry = load(&id, &dir, daemon);
                if let Some(old) = mods.insert(id.clone(), entry) {
                    shadows.push(Shadow {
                        id,
                        winner: dir,
                        shadowed: old.dir,
                    });
                }
            }
        }
        Self { mods, shadows }
    }

    /// Load and enable the policy's mods (no config store). Returns per-mod outcomes so the
    /// daemon can log conflicts.
    pub fn apply_defaults(&mut self, policy: &Policy) -> Vec<(String, Result<Change, ModsError>)> {
        let ids: Vec<String> = self
            .mods
            .keys()
            .filter(|id| policy.default_enabled.contains(*id))
            .cloned()
            .collect();
        ids.into_iter()
            .map(|id| {
                let r = self.enable(&id);
                (id, r)
            })
            .collect()
    }

    pub fn get(&self, id: &str) -> Option<&ModEntry> {
        self.mods.get(id)
    }

    pub fn iter(&self) -> impl Iterator<Item = &ModEntry> {
        self.mods.values()
    }

    /// `available` → `disabled`: the mod is loaded and its settings are known; nothing else
    /// runs. Idempotent. Invalid mods cannot be loaded.
    pub fn load(&mut self, id: &str) -> Result<Change, ModsError> {
        let e = self
            .mods
            .get_mut(id)
            .ok_or_else(|| ModsError::Unknown(id.into()))?;
        let Some(m) = e.manifest.as_ref() else {
            return Err(ModsError::Invalid(id.into()));
        };
        if e.state != ModState::Available {
            return Ok(Change::default());
        }
        let added = settings_of(m);
        e.state = ModState::Disabled;
        Ok(Change {
            added,
            removed: vec![],
        })
    }

    /// Back to `available`: a mod that is on is switched off first, then its settings go.
    /// Unknown mods are an error; an invalid one has nothing loaded, so nothing happens.
    pub fn unload(&mut self, id: &str) -> Result<Change, ModsError> {
        let mut change = self.disable(id)?;
        let e = self.mods.get_mut(id).expect("checked by disable");
        if e.state == ModState::Disabled {
            if let Some(m) = e.manifest.as_ref() {
                change.removed.extend(settings_of(m));
            }
            e.state = ModState::Available;
        }
        Ok(change)
    }

    /// `available` or `disabled` → `enabled`; an available mod is loaded on the way. Idempotent.
    /// A provide already held by another enabled mod refuses the whole call, nothing changes.
    pub fn enable(&mut self, id: &str) -> Result<Change, ModsError> {
        let e = self
            .mods
            .get(id)
            .ok_or_else(|| ModsError::Unknown(id.into()))?;
        let m = match (&e.manifest, &e.state) {
            (Some(m), s) if !matches!(s, ModState::Invalid { .. }) => m.clone(),
            _ => return Err(ModsError::Invalid(id.into())),
        };
        if e.state == ModState::Enabled {
            return Ok(Change::default());
        }
        for other in self.mods.values().filter(|o| o.state == ModState::Enabled) {
            let Some(om) = &other.manifest else { continue };
            for p in &m.provides {
                if let Some(q) = om.provides.iter().find(|q| p.conflicts_with(q)) {
                    return Err(ModsError::Conflict {
                        mod_id: id.into(),
                        other: other.id.clone(),
                        provide: p.to_string(),
                        other_provide: q.to_string(),
                    });
                }
            }
        }
        let Some(e) = self.mods.get_mut(id) else {
            unreachable!("checked above")
        };
        // From `available` the settings are registered now, as the load would have done.
        let added = if e.state == ModState::Available {
            contributions(&m)
        } else {
            provides_of(&m)
        };
        e.state = ModState::Enabled;
        Ok(Change {
            added,
            removed: vec![],
        })
    }

    /// `enabled` → `disabled`: the provides go, the settings stay (the mod is still loaded).
    /// Config values are kept by the daemon; only registrations are reversed.
    pub fn disable(&mut self, id: &str) -> Result<Change, ModsError> {
        let e = self
            .mods
            .get_mut(id)
            .ok_or_else(|| ModsError::Unknown(id.into()))?;
        let Some(m) = e.manifest.as_ref().filter(|_| e.state == ModState::Enabled) else {
            return Ok(Change::default());
        };
        let removed = provides_of(m);
        e.state = ModState::Disabled;
        Ok(Change {
            added: vec![],
            removed,
        })
    }

    /// Makes the registry equal to the config lists: `loaded` and `enabled` are the effective
    /// `mods.loaded` / `mods.enabled`, and an enabled id is loaded too (K25, enabled ⊆ loaded).
    /// Unknown ids are ignored. Switching off comes first, so a mod can take the provides of
    /// the one it replaces. Returns the enables that a conflict refused; invalid mods are left
    /// alone (`mods` doc says why).
    pub fn reconcile(
        &mut self,
        loaded: &BTreeSet<String>,
        enabled: &BTreeSet<String>,
    ) -> Vec<(String, ModsError)> {
        let want_on = |id: &str| enabled.contains(id);
        let want_loaded = |id: &str| loaded.contains(id) || enabled.contains(id);
        let ids: Vec<String> = self.mods.keys().cloned().collect();
        for id in &ids {
            if !want_on(id) {
                let _ = self.disable(id);
            }
            if !want_loaded(id) {
                let _ = self.unload(id);
            }
        }
        let mut refused = Vec::new();
        for id in &ids {
            if want_loaded(id) {
                let _ = self.load(id);
            }
            if want_on(id)
                && let Err(e @ ModsError::Conflict { .. }) = self.enable(id)
            {
                refused.push((id.clone(), e));
            }
        }
        refused
    }

    /// The daemon reports why a mod runs now (K25 "Running now", I23): empty when nothing runs.
    /// Unknown ids are ignored.
    pub fn set_running_reasons(&mut self, id: &str, reasons: Vec<String>) {
        if let Some(e) = self.mods.get_mut(id) {
            e.running_reasons = reasons;
        }
    }

    /// Catalog for the `mods` document, see [`mods_doc`].
    pub fn doc(&self) -> Value {
        mods_doc(self)
    }
}

fn provides_of(m: &Manifest) -> Vec<Contribution> {
    m.provides
        .iter()
        .map(|p| Contribution::Provides {
            mod_id: m.id.clone(),
            provide: p.clone(),
        })
        .collect()
}

fn settings_of(m: &Manifest) -> Vec<Contribution> {
    m.settings
        .iter()
        .map(|s| Contribution::Setting {
            mod_id: m.id.clone(),
            config_key: m.config_key(&s.key),
            setting: s.clone(),
        })
        .collect()
}

fn contributions(m: &Manifest) -> Vec<Contribution> {
    provides_of(m).into_iter().chain(settings_of(m)).collect()
}

fn load(id: &str, dir: &Path, daemon: &Version) -> ModEntry {
    let invalid = |errors| ModEntry {
        id: id.into(),
        dir: dir.into(),
        manifest: None,
        state: ModState::Invalid { errors },
        running_reasons: Vec::new(),
    };
    let text = match std::fs::read_to_string(dir.join("mod.toml")) {
        Ok(t) => t,
        Err(e) => {
            let code = if e.kind() == std::io::ErrorKind::NotFound {
                "manifest_missing"
            } else {
                "manifest_unreadable"
            };
            return invalid(vec![ValidationError::new(code, "mod.toml", e.to_string())]);
        }
    };
    match manifest::parse(id, &text, daemon) {
        Ok(m) => ModEntry {
            id: id.into(),
            dir: dir.into(),
            manifest: Some(m),
            state: ModState::Available,
            running_reasons: Vec::new(),
        },
        Err(errors) => invalid(errors),
    }
}

/// `{mods: [{id, name, description?, version, tier, state, running, running_reasons, capabilities,
/// cost, provides, errors: [{key, path, detail}], shadows_bundled}]}`; `state` is
/// available|enabled|disabled|invalid (`disabled` = loaded, off); `running` is true while
/// `running_reasons` (i18n keys) is not empty. Documents carry no nulls (PROTOCOL): an invalid entry
/// has no version/tier/cost and name = id, and `description` (i18n key or text) is present only when
/// the manifest declares one.
pub fn mods_doc(r: &Registry) -> Value {
    let mods: Vec<Value> = r
        .iter()
        .map(|e| {
            let errors: Vec<Value> = match &e.state {
                ModState::Invalid { errors } => errors
                    .iter()
                    .map(|x| json!({"key": x.i18n_key(), "path": x.path, "detail": x.detail}))
                    .collect(),
                _ => vec![],
            };
            let shadowed = r.shadows.iter().any(|s| s.id == e.id);
            let running = !e.running_reasons.is_empty();
            let mut entry = match &e.manifest {
                Some(m) => json!({
                    "id": e.id, "name": m.name, "version": m.version.to_string(), "tier": m.tier,
                    "state": e.state.name(), "running": running, "running_reasons": e.running_reasons,
                    "capabilities": m.capabilities, "cost": m.cost,
                    "provides": m.provides.iter().map(|p| p.to_string()).collect::<Vec<_>>(),
                    "errors": errors, "shadows_bundled": shadowed,
                }),
                None => json!({
                    "id": e.id, "name": e.id, "state": "invalid", "running": running,
                    "running_reasons": e.running_reasons, "capabilities": [], "provides": [],
                    "errors": errors, "shadows_bundled": shadowed,
                }),
            };
            if let Some(d) = e.manifest.as_ref().and_then(|m| m.description.as_ref()) {
                entry["description"] = json!(d);
            }
            entry
        })
        .collect();
    json!({ "mods": mods })
}
