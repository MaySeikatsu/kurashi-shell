use std::collections::{BTreeMap, BTreeSet, HashSet, VecDeque};
use std::path::{Path, PathBuf};

use serde_json::Value as Json;
use toml_edit::{DocumentMut, Item};

use crate::convert::json_to_value;
use crate::sparse::{
    Flat, Migration, VERSION_KEY, atomic_write, flatten, read_doc, remove_path, segments, set_path,
    set_version,
};
use crate::{
    Applied, ConfigError, Diagnostic, DiagnosticReason, Diff, DiffEntry, FORCED_NIX, Forced,
    LayerValue, Op, OpError, Paths, Provenanced, REASON_NIX_ENFORCED, Rev, SchemaView, Slot,
    Source,
};

/// Bounded global undo stack (ARCHITECTURE §3).
pub const UNDO_LIMIT: usize = 100;
const MANAGED_KEY: &str = "_managed";

#[derive(Debug, Clone, Default)]
pub struct Options {
    /// Read-only profile directories shipped with the package, searched after the user's.
    pub bundled_profile_dirs: Vec<PathBuf>,
    /// `schema_version` chain applied to the user file (persisted), profiles and managed.toml
    /// (in memory only).
    pub migrations: Vec<Migration>,
}

/// The sparse layers. `default` is not stored: it comes from the schema.
#[derive(Debug, Clone, Default, PartialEq)]
pub(crate) struct Layers {
    pub nix: BTreeMap<Slot, Json>,
    pub theme: Option<(String, BTreeMap<Slot, Json>)>,
    /// Entries may come from different profiles after section-wise loads (K7).
    pub profile: BTreeMap<Slot, (String, Json)>,
    pub user: BTreeMap<Slot, Json>,
    /// `forced:<name>` sub-layers; later entries win.
    pub forced: Vec<(String, BTreeMap<Slot, Forced>)>,
}

impl Layers {
    fn slots(&self) -> BTreeSet<Slot> {
        let mut s: BTreeSet<Slot> = self.nix.keys().cloned().collect();
        if let Some((_, t)) = &self.theme {
            s.extend(t.keys().cloned());
        }
        s.extend(self.profile.keys().cloned());
        s.extend(self.user.keys().cloned());
        for (_, f) in &self.forced {
            s.extend(f.keys().cloned());
        }
        s
    }
}

type Change<V> = (Slot, Option<V>, Option<V>);

/// Entry-level patch of one transaction; undo writes `before` back for exactly these slots, so
/// external edits to other keys in between survive an undo.
#[derive(Debug, Clone)]
struct TxRecord {
    id: String,
    user: Vec<Change<Json>>,
    profile: Vec<Change<(String, Json)>>,
}

fn diff_map<V: Clone + PartialEq>(a: &BTreeMap<Slot, V>, b: &BTreeMap<Slot, V>) -> Vec<Change<V>> {
    let keys: BTreeSet<&Slot> = a.keys().chain(b.keys()).collect();
    keys.into_iter()
        .filter_map(|k| {
            let (x, y) = (a.get(k), b.get(k));
            (x != y).then(|| (k.clone(), x.cloned(), y.cloned()))
        })
        .collect()
}

fn patch<V: Clone>(m: &mut BTreeMap<Slot, V>, changes: &[Change<V>], forward: bool) {
    for (slot, before, after) in changes {
        match if forward { after } else { before } {
            Some(v) => m.insert(slot.clone(), v.clone()),
            None => m.remove(slot),
        };
    }
}

pub(crate) fn section(key: &str) -> &str {
    key.split('.').next().unwrap_or(key)
}

/// The config engine. Single-threaded by design: the daemon owns it on its state task.
pub struct Config<S: SchemaView> {
    pub(crate) schema: S,
    known: HashSet<String>,
    keys: Vec<String>,
    paths: Paths,
    opts: Options,
    pub(crate) layers: Layers,
    /// `None` while `config.toml` is unreadable: writes are refused instead of clobbering it.
    user_doc: Option<DocumentMut>,
    rev: Rev,
    undo: VecDeque<TxRecord>,
    redo: Vec<TxRecord>,
    diagnostics: BTreeMap<PathBuf, Vec<Diagnostic>>,
}

impl<S: SchemaView> Config<S> {
    /// Loads `managed.toml`, `config.toml` (migrating it if older) and the profile layer.
    /// Problems become [`Config::diagnostics`], never a failed start.
    pub fn open(schema: S, paths: Paths, opts: Options) -> Self {
        let mut keys = schema.keys();
        keys.sort();
        let mut cfg = Self {
            known: keys.iter().cloned().collect(),
            keys,
            schema,
            paths,
            opts,
            layers: Layers::default(),
            user_doc: Some(DocumentMut::new()),
            rev: 0,
            undo: VecDeque::new(),
            redo: Vec::new(),
            diagnostics: BTreeMap::new(),
        };
        cfg.reload_managed_file();
        cfg.reload_user_file();
        cfg.load_profile_state();
        cfg.rev = 0;
        cfg
    }

    pub fn rev(&self) -> Rev {
        self.rev
    }

    pub fn paths(&self) -> &Paths {
        &self.paths
    }

    pub fn schema(&self) -> &S {
        &self.schema
    }

    /// Current diagnostics of every file (user, managed, profile state).
    pub fn diagnostics(&self) -> Vec<Diagnostic> {
        self.diagnostics.values().flatten().cloned().collect()
    }

    pub fn can_undo(&self) -> bool {
        !self.undo.is_empty()
    }

    pub fn can_redo(&self) -> bool {
        !self.redo.is_empty()
    }

    /// Output names mentioned by any layer for `key`.
    pub fn outputs_for(&self, key: &str) -> BTreeSet<String> {
        self.layers
            .slots()
            .into_iter()
            .filter(|(k, _)| k == key)
            .filter_map(|(_, o)| o)
            .collect()
    }

    // --- resolution -------------------------------------------------------------------------

    /// Effective value with provenance; `None` for keys no layer (not even the schema) knows.
    pub fn resolve(&self, key: &str, output: Option<&str>) -> Option<Provenanced> {
        self.resolve_in(&self.layers, key, output)
    }

    pub(crate) fn resolve_in(
        &self,
        l: &Layers,
        key: &str,
        output: Option<&str>,
    ) -> Option<Provenanced> {
        let g: Slot = (key.to_string(), None);
        let o: Option<Slot> = output.map(|o| (key.to_string(), Some(o.to_string())));
        let pick =
            |m: &BTreeMap<Slot, Json>| o.as_ref().and_then(|o| m.get(o)).or(m.get(&g)).cloned();
        let plain = |value, source| Provenanced {
            value,
            source,
            forced_by: None,
            reason: None,
        };

        for (name, m) in l.forced.iter().rev() {
            if let Some(f) = o.as_ref().and_then(|o| m.get(o)).or(m.get(&g)) {
                return Some(Provenanced {
                    value: f.value.clone(),
                    source: Source::Forced(name.clone()),
                    forced_by: f.forced_by.clone(),
                    reason: f.reason.clone(),
                });
            }
        }
        if let Some(v) = pick(&l.user) {
            return Some(plain(v, Source::User));
        }
        if let Some((name, v)) = o
            .as_ref()
            .and_then(|o| l.profile.get(o))
            .or(l.profile.get(&g))
        {
            return Some(plain(v.clone(), Source::Profile(name.clone())));
        }
        if let Some((name, m)) = &l.theme
            && let Some(v) = pick(m)
        {
            return Some(plain(v, Source::Theme(name.clone())));
        }
        if let Some(v) = pick(&l.nix) {
            return Some(plain(v, Source::Nix));
        }
        self.schema.default(key).map(|v| plain(v, Source::Default))
    }

    /// Every layer's contribution, lowest precedence first (`cfg.why`). For an output, each
    /// layer lists its global entry and then its output-specific one.
    pub fn explain(&self, key: &str, output: Option<&str>) -> Vec<LayerValue> {
        let l = &self.layers;
        let mut out = Vec::new();
        let mut slots = vec![(key.to_string(), None)];
        if let Some(o) = output {
            slots.push((key.to_string(), Some(o.to_string())));
        }
        let lv = |source: Source, slot: &Slot, value: &Json| LayerValue {
            source,
            output: slot.1.clone(),
            value: value.clone(),
            forced_by: None,
            reason: None,
        };
        if let Some(v) = self.schema.default(key) {
            out.push(lv(Source::Default, &slots[0], &v));
        }
        for s in &slots {
            if let Some(v) = l.nix.get(s) {
                out.push(lv(Source::Nix, s, v));
            }
        }
        if let Some((name, m)) = &l.theme {
            for s in &slots {
                if let Some(v) = m.get(s) {
                    out.push(lv(Source::Theme(name.clone()), s, v));
                }
            }
        }
        for s in &slots {
            if let Some((name, v)) = l.profile.get(s) {
                out.push(lv(Source::Profile(name.clone()), s, v));
            }
        }
        for s in &slots {
            if let Some(v) = l.user.get(s) {
                out.push(lv(Source::User, s, v));
            }
        }
        for (name, m) in &l.forced {
            for s in &slots {
                if let Some(f) = m.get(s) {
                    out.push(LayerValue {
                        forced_by: f.forced_by.clone(),
                        reason: f.reason.clone(),
                        ..lv(Source::Forced(name.clone()), s, &f.value)
                    });
                }
            }
        }
        out
    }

    /// Effective changes between two layer states. Output slots are listed only where they
    /// deviate from the global slot (a global change implies all following outputs).
    pub(crate) fn diff_effective(&self, a: &Layers, b: &Layers) -> Vec<DiffEntry> {
        let mut slots: BTreeSet<Slot> = a.slots();
        slots.extend(b.slots());
        slots.extend(self.keys.iter().map(|k| (k.clone(), None)));
        let mut out = Vec::new();
        for (key, output) in slots {
            let before = self.resolve_in(a, &key, output.as_deref());
            let after = self.resolve_in(b, &key, output.as_deref());
            if before == after {
                continue;
            }
            if output.is_some()
                && before == self.resolve_in(a, &key, None)
                && after == self.resolve_in(b, &key, None)
            {
                continue;
            }
            out.push(DiffEntry {
                key,
                output,
                before,
                after,
            });
        }
        out
    }

    // --- transactions -----------------------------------------------------------------------

    /// Validates the whole batch first; any error rejects it with nothing changed.
    pub fn apply(&mut self, ops: &[Op]) -> Result<Applied, Vec<OpError>> {
        let mut errors = Vec::new();
        let mut next = self.layers.clone();
        for (index, op) in ops.iter().enumerate() {
            match op {
                Op::Set { key, output, value } => match self.check_set(index, key, output, value) {
                    Ok(()) => {
                        next.user
                            .insert((key.clone(), output.clone()), value.clone());
                    }
                    Err(e) => errors.push(e),
                },
                Op::Reset { key, output } => {
                    let prefix = format!("{key}.");
                    if !self.known.contains(key)
                        && !self.keys.iter().any(|k| k.starts_with(&prefix))
                    {
                        errors.push(OpError::UnknownKey {
                            index,
                            key: key.clone(),
                        });
                        continue;
                    }
                    next.user
                        .retain(|(k, o), _| !(o == output && (k == key || k.starts_with(&prefix))));
                }
            }
        }
        if !errors.is_empty() {
            return Err(errors);
        }
        self.commit(next)
            .map_err(|message| vec![OpError::Persist { message }])
    }

    fn check_set(
        &self,
        index: usize,
        key: &str,
        output: &Option<String>,
        value: &Json,
    ) -> Result<(), OpError> {
        let key = key.to_string();
        if !self.known.contains(&key) {
            return Err(OpError::UnknownKey { index, key });
        }
        if let Some(o) = output
            && !self.schema.per_output(&key)
        {
            let output = o.clone();
            return Err(OpError::NotPerOutput { index, key, output });
        }
        let message = if json_to_value(value).is_none() {
            Some("config.error.unrepresentable".to_string())
        } else {
            self.schema.validate(&key, value).err()
        };
        match message {
            None => Ok(()),
            Some(message) => Err(OpError::Invalid {
                index,
                key,
                message,
            }),
        }
    }

    /// Records `next` as one undoable transaction.
    fn commit(&mut self, next: Layers) -> Result<Applied, String> {
        let record = TxRecord {
            id: format!("tx-{}", self.rev + 1),
            user: diff_map(&self.layers.user, &next.user),
            profile: diff_map(&self.layers.profile, &next.profile),
        };
        if record.user.is_empty() && record.profile.is_empty() {
            return Ok(Applied {
                rev: self.rev,
                tx_id: None,
                changed: Vec::new(),
            });
        }
        let changed = self.transition(next)?;
        let tx_id = Some(record.id.clone());
        self.undo.push_back(record);
        if self.undo.len() > UNDO_LIMIT {
            self.undo.pop_front();
        }
        self.redo.clear();
        Ok(Applied {
            rev: self.rev,
            tx_id,
            changed,
        })
    }

    /// Persists the user/profile-layer difference, then swaps state and bumps the revision.
    fn transition(&mut self, next: Layers) -> Result<Vec<Slot>, String> {
        let user = diff_map(&self.layers.user, &next.user);
        if !user.is_empty() {
            let Some(doc) = &self.user_doc else {
                return Err("config.error.user_file_unreadable".into());
            };
            let mut doc = doc.clone();
            for (slot, _, after) in &user {
                let segs = segments(slot);
                match after.as_ref().and_then(json_to_value) {
                    Some(v) => set_path(doc.as_table_mut(), false, &segs, v),
                    None => {
                        remove_path(doc.as_table_mut(), &segs);
                    }
                }
            }
            if doc.get(VERSION_KEY).is_none() {
                set_version(&mut doc, self.schema.version());
            }
            atomic_write(&self.paths.user_file(), &doc.to_string()).map_err(|e| e.to_string())?;
            self.user_doc = Some(doc);
        }
        if next.profile != self.layers.profile {
            self.write_profile_state(&next.profile)
                .map_err(|e| e.to_string())?;
        }
        let changed = self
            .diff_effective(&self.layers, &next)
            .into_iter()
            .map(|e| (e.key, e.output))
            .collect();
        self.layers = next;
        self.rev += 1;
        Ok(changed)
    }

    /// Reverts the latest transaction (as a new revision). `Ok(None)`: nothing to undo.
    pub fn undo(&mut self) -> Result<Option<Applied>, ConfigError> {
        self.step(false)
    }

    pub fn redo(&mut self) -> Result<Option<Applied>, ConfigError> {
        self.step(true)
    }

    fn step(&mut self, forward: bool) -> Result<Option<Applied>, ConfigError> {
        let popped = if forward {
            self.redo.pop()
        } else {
            self.undo.pop_back()
        };
        let Some(record) = popped else {
            return Ok(None);
        };
        let mut next = self.layers.clone();
        patch(&mut next.user, &record.user, forward);
        patch(&mut next.profile, &record.profile, forward);
        match self.transition(next) {
            Ok(changed) => {
                let tx_id = Some(record.id.clone());
                if forward {
                    self.undo.push_back(record);
                } else {
                    self.redo.push(record);
                }
                Ok(Some(Applied {
                    rev: self.rev,
                    tx_id,
                    changed,
                }))
            }
            Err(message) => {
                if forward {
                    self.redo.push(record);
                } else {
                    self.undo.push_back(record);
                }
                Err(ConfigError::Refused(message))
            }
        }
    }

    // --- non-transactional layers (daemon-driven, not undoable) ------------------------------

    fn swap_external(&mut self, next: Layers) -> Vec<DiffEntry> {
        let entries = self.diff_effective(&self.layers, &next);
        self.layers = next;
        if !entries.is_empty() {
            self.rev += 1;
        }
        entries
    }

    fn set_diagnostics(&mut self, file: PathBuf, d: Vec<Diagnostic>) {
        if d.is_empty() {
            self.diagnostics.remove(&file);
        } else {
            self.diagnostics.insert(file, d);
        }
    }

    fn flatten_doc(&self, doc: &DocumentMut, file: &Path, skip: &[&str]) -> Flat {
        flatten(doc.as_table(), &self.schema, &self.known, file, skip)
    }

    /// Re-reads `config.toml` after an external edit (the daemon's file watcher calls this).
    /// An unreadable file keeps the last good values in effect and blocks writes until fixed.
    pub fn reload_user_file(&mut self) -> Diff {
        let path = self.paths.user_file();
        let loaded = read_doc(&path, self.schema.version(), &self.opts.migrations, true);
        let mut diagnostics = loaded.diagnostics;
        let mut next = self.layers.clone();
        if let Some(doc) = &loaded.doc {
            let flat = self.flatten_doc(doc, &path, &[VERSION_KEY]);
            next.user = flat.entries;
            diagnostics.extend(flat.diagnostics);
        }
        self.user_doc = loaded.doc;
        let entries = self.swap_external(next);
        self.set_diagnostics(path, diagnostics.clone());
        Diff {
            rev: self.rev,
            entries,
            diagnostics,
        }
    }

    /// Re-reads `managed.toml` (K15): the `nix` layer, or `forced:nix` when
    /// `_managed.enforce = true`.
    pub fn reload_managed_file(&mut self) -> Diff {
        let path = self.paths.managed_file();
        let loaded = read_doc(&path, self.schema.version(), &self.opts.migrations, false);
        let mut diagnostics = loaded.diagnostics;
        let mut next = self.layers.clone();
        next.forced.retain(|(n, _)| n != FORCED_NIX);
        next.nix.clear();
        if let Some(doc) = &loaded.doc {
            let flat = self.flatten_doc(doc, &path, &[VERSION_KEY, MANAGED_KEY]);
            diagnostics.extend(flat.diagnostics);
            let enforce = doc
                .get(MANAGED_KEY)
                .and_then(|m| m.get("enforce"))
                .and_then(Item::as_bool)
                .unwrap_or(false);
            if enforce {
                let forced = flat
                    .entries
                    .into_iter()
                    .map(|(slot, value)| {
                        let f = Forced {
                            value,
                            forced_by: Some(FORCED_NIX.into()),
                            reason: Some(REASON_NIX_ENFORCED.into()),
                        };
                        (slot, f)
                    })
                    .collect();
                next.forced.insert(0, (FORCED_NIX.into(), forced));
            } else {
                next.nix = flat.entries;
            }
        }
        let entries = self.swap_external(next);
        self.set_diagnostics(path, diagnostics.clone());
        Diff {
            rev: self.rev,
            entries,
            diagnostics,
        }
    }

    fn validated(
        &self,
        origin: &str,
        entries: BTreeMap<Slot, Json>,
    ) -> (BTreeMap<Slot, Json>, Vec<Diagnostic>) {
        let mut diags = Vec::new();
        let mut ok = BTreeMap::new();
        for ((key, output), v) in entries {
            let reason = if !self.known.contains(&key) {
                Some(DiagnosticReason::UnknownKey)
            } else if output.is_some() && !self.schema.per_output(&key) {
                Some(DiagnosticReason::NotPerOutput)
            } else {
                self.schema
                    .validate(&key, &v)
                    .err()
                    .map(|message| DiagnosticReason::Invalid { message })
            };
            match reason {
                Some(reason) => diags.push(Diagnostic {
                    file: PathBuf::from(origin),
                    key: key.clone(),
                    reason,
                }),
                None => {
                    ok.insert((key, output), v);
                }
            }
        }
        (ok, diags)
    }

    /// Replaces the `theme:<recipe>` layer (decor pack recipe, K8). Invalid entries are dropped
    /// and reported.
    pub fn set_theme_layer(&mut self, theme: Option<(String, BTreeMap<Slot, Json>)>) -> Diff {
        let mut next = self.layers.clone();
        let mut diagnostics = Vec::new();
        next.theme = theme.map(|(name, entries)| {
            let (ok, d) = self.validated(&format!("theme:{name}"), entries);
            diagnostics = d;
            (name, ok)
        });
        let entries = self.swap_external(next);
        Diff {
            rev: self.rev,
            entries,
            diagnostics,
        }
    }

    /// Pins a slot in `forced:<name>` (e.g. `capability`). Invalid values are refused.
    pub fn set_forced(&mut self, name: &str, slot: Slot, forced: Forced) -> Result<Diff, OpError> {
        self.check_set(0, &slot.0, &slot.1, &forced.value)?;
        let mut next = self.layers.clone();
        match next.forced.iter_mut().find(|(n, _)| n == name) {
            Some((_, m)) => {
                m.insert(slot, forced);
            }
            None => next
                .forced
                .push((name.into(), BTreeMap::from([(slot, forced)]))),
        }
        let entries = self.swap_external(next);
        Ok(Diff {
            rev: self.rev,
            entries,
            diagnostics: Vec::new(),
        })
    }

    /// Unpins one slot of `forced:<name>`, or the whole sub-layer with `slot = None`.
    pub fn clear_forced(&mut self, name: &str, slot: Option<&Slot>) -> Diff {
        let mut next = self.layers.clone();
        match slot {
            None => next.forced.retain(|(n, _)| n != name),
            Some(s) => {
                for (n, m) in &mut next.forced {
                    if n == name {
                        m.remove(s);
                    }
                }
                next.forced.retain(|(_, m)| !m.is_empty());
            }
        }
        let entries = self.swap_external(next);
        Diff {
            rev: self.rev,
            entries,
            diagnostics: Vec::new(),
        }
    }

    /// Writes the user document back unchanged (byte-identical when nothing changed).
    pub fn save(&self) -> Result<(), ConfigError> {
        let path = self.paths.user_file();
        let Some(doc) = &self.user_doc else {
            return Err(ConfigError::Refused(
                "config.error.user_file_unreadable".into(),
            ));
        };
        if doc.as_table().is_empty() && !path.exists() {
            return Ok(());
        }
        atomic_write(&path, &doc.to_string()).map_err(|source| ConfigError::Io { path, source })
    }

    // --- profiles ---------------------------------------------------------------------------

    /// Profile state lives in `profile-layer.toml` as `[<profile>.<section>…]` tables so a
    /// restart restores which profile supplied which entry. Derived state: not migrated.
    fn load_profile_state(&mut self) {
        let path = self.paths.profile_state_file();
        let loaded = read_doc(&path, 1, &[], false);
        let mut diagnostics = loaded.diagnostics;
        let mut profile = BTreeMap::new();
        if let Some(doc) = &loaded.doc {
            for (name, item) in doc.iter() {
                let Some(t) = item.as_table_like() else {
                    continue;
                };
                let flat = flatten(t, &self.schema, &self.known, &path, &[]);
                diagnostics.extend(flat.diagnostics);
                for (slot, v) in flat.entries {
                    profile.insert(slot, (name.to_string(), v));
                }
            }
        }
        self.layers.profile = profile;
        self.set_diagnostics(path, diagnostics);
    }

    fn write_profile_state(&self, profile: &BTreeMap<Slot, (String, Json)>) -> std::io::Result<()> {
        let mut doc = DocumentMut::new();
        for (slot, (name, v)) in profile {
            let mut segs = vec![name.clone()];
            segs.extend(segments(slot));
            if let Some(v) = json_to_value(v) {
                set_path(doc.as_table_mut(), false, &segs, v);
            }
        }
        atomic_write(&self.paths.profile_state_file(), &doc.to_string())
    }

    fn check_name(name: &str) -> Result<(), ConfigError> {
        let bad = name.is_empty()
            || name.starts_with('.')
            || name.contains(['/', '\\', '\0'])
            || name.len() > 128;
        if bad {
            return Err(ConfigError::InvalidProfileName(name.into()));
        }
        Ok(())
    }

    /// User profiles shadow bundled ones of the same name.
    pub fn find_profile(&self, name: &str) -> Result<PathBuf, ConfigError> {
        Self::check_name(name)?;
        std::iter::once(self.paths.user_profiles_dir())
            .chain(self.opts.bundled_profile_dirs.iter().cloned())
            .map(|d| d.join(format!("{name}.toml")))
            .find(|p| p.is_file())
            .ok_or_else(|| ConfigError::ProfileNotFound(name.into()))
    }

    /// `(name, path, bundled)` of every available profile, user first, sorted by name.
    pub fn list_profiles(&self) -> Vec<(String, PathBuf, bool)> {
        let mut seen = BTreeMap::new();
        let dirs = std::iter::once((self.paths.user_profiles_dir(), false)).chain(
            self.opts
                .bundled_profile_dirs
                .iter()
                .map(|d| (d.clone(), true)),
        );
        for (dir, bundled) in dirs {
            let Ok(rd) = std::fs::read_dir(&dir) else {
                continue;
            };
            for e in rd.flatten() {
                let p = e.path();
                if p.extension().is_some_and(|x| x == "toml")
                    && let Some(stem) = p.file_stem().and_then(|s| s.to_str())
                {
                    seen.entry(stem.to_string()).or_insert((p, bundled));
                }
            }
        }
        seen.into_iter().map(|(n, (p, b))| (n, p, b)).collect()
    }

    fn read_profile(&self, name: &str) -> Result<Flat, ConfigError> {
        let path = self.find_profile(name)?;
        let loaded = read_doc(&path, self.schema.version(), &self.opts.migrations, false);
        let Some(doc) = &loaded.doc else {
            return Err(ConfigError::Unreadable(loaded.diagnostics));
        };
        let mut flat = self.flatten_doc(doc, &path, &[VERSION_KEY]);
        let mut d = loaded.diagnostics;
        d.append(&mut flat.diagnostics);
        flat.diagnostics = d;
        Ok(flat)
    }

    /// Loading replaces the profile layer for the chosen sections (all with `None`) and clears
    /// user overrides there, so the profile actually takes effect; forced/nix/theme stay.
    fn profile_candidate(
        &self,
        name: &str,
        entries: BTreeMap<Slot, Json>,
        sections: Option<&[&str]>,
    ) -> Layers {
        let mut next = self.layers.clone();
        let inside = |k: &str| sections.is_none_or(|s| s.contains(&section(k)));
        next.profile.retain(|(k, _), _| !inside(k));
        next.user.retain(|(k, _), _| !inside(k));
        for (slot, v) in entries {
            if inside(&slot.0) {
                next.profile.insert(slot, (name.to_string(), v));
            }
        }
        next
    }

    /// Effective before/after of loading `name` (sections = top-level tables; `None` = all).
    pub fn preview_profile(
        &self,
        name: &str,
        sections: Option<&[&str]>,
    ) -> Result<Diff, ConfigError> {
        let flat = self.read_profile(name)?;
        let next = self.profile_candidate(name, flat.entries, sections);
        Ok(Diff {
            rev: self.rev,
            entries: self.diff_effective(&self.layers, &next),
            diagnostics: flat.diagnostics,
        })
    }

    /// Loads a profile as **one** undoable transaction; returns the file's diagnostics too.
    pub fn load_profile(
        &mut self,
        name: &str,
        sections: Option<&[&str]>,
    ) -> Result<(Applied, Vec<Diagnostic>), ConfigError> {
        let flat = self.read_profile(name)?;
        let next = self.profile_candidate(name, flat.entries, sections);
        let applied = self.commit(next).map_err(ConfigError::Refused)?;
        Ok((applied, flat.diagnostics))
    }

    /// Snapshots current effective values that differ from the schema default (forced values
    /// excluded: they describe the machine, not a look) into `profiles/<name>.toml`.
    pub fn save_profile(
        &self,
        name: &str,
        sections: Option<&[&str]>,
    ) -> Result<PathBuf, ConfigError> {
        Self::check_name(name)?;
        let mut doc = DocumentMut::new();
        set_version(&mut doc, self.schema.version());
        let keep = |p: &Provenanced| !matches!(p.source, Source::Forced(_));
        for key in &self.keys {
            if sections.is_some_and(|s| !s.contains(&section(key))) {
                continue;
            }
            let global = self.resolve(key, None);
            if let Some(g) = &global
                && keep(g)
                && Some(&g.value) != self.schema.default(key).as_ref()
                && let Some(v) = json_to_value(&g.value)
            {
                set_path(
                    doc.as_table_mut(),
                    false,
                    &segments(&(key.clone(), None)),
                    v,
                );
            }
            for o in self.outputs_for(key) {
                let Some(e) = self.resolve(key, Some(&o)) else {
                    continue;
                };
                if keep(&e)
                    && Some(&e.value) != global.as_ref().map(|g| &g.value)
                    && let Some(v) = json_to_value(&e.value)
                {
                    set_path(
                        doc.as_table_mut(),
                        false,
                        &segments(&(key.clone(), Some(o))),
                        v,
                    );
                }
            }
        }
        let path = self.paths.user_profiles_dir().join(format!("{name}.toml"));
        atomic_write(&path, &doc.to_string()).map_err(|source| ConfigError::Io {
            path: path.clone(),
            source,
        })?;
        Ok(path)
    }
}
