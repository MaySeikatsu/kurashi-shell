//! The user's own palettes (I453, card W68; `docs/ux/palettes.md` "Custom palettes"): files in the bundled format in
//! `$XDG_CONFIG_HOME/kurashi/palettes/<slug>.toml`, loaded beside the bundled ones (a bundled name wins), offered under
//! `palettes` with group `custom`, watched with the config directory (`config::watch`), and edited from Settings through
//! the `palette.*` actions — Settings reads no files (rule 1).
//!
//! The editor's live preview is a **draft** the daemon holds in memory: the theme document wears it (with a note saying
//! so), nothing is written, the apps keep the saved colours (`theme::for_apps`). It ends with `palette.draft.clear`, a
//! save, or the last watcher of `theme.previews` going away (Settings closed or crashed: `theme::SwatchWatch`).

use std::path::{Path, PathBuf};
use std::sync::{Arc, Mutex};

use kurashi_ipc::ApplyOp;
use kurashi_theme::palette::{self, PaletteSet, Problem, ROLES};
use kurashi_theme::{ContrastLevel, FontProvider, Scheme, Source, ThemeInput};
use serde_json::{Map, Value, json};

use crate::actions::{ActionError, ActionRegistry};
use crate::config::ConfigStore;
use crate::hub::Hub;

/// The directory under the config dir.
pub const DIR: &str = "palettes";
const KEY: &str = "theme.colors.palette";
/// Refusals (i18n keys, `i18n/*/palettes.toml`).
const E_ARGS: &str = "palettes.error.args";
const E_UNKNOWN: &str = "palettes.error.unknown";
const E_READ_ONLY: &str = "palettes.error.read_only";
const E_WRITE: &str = "palettes.error.write";
const E_NO_EDITOR: &str = "palettes.error.no_editor";
const E_NO_PICTURE: &str = "palettes.error.no_picture";

pub fn dir(store: &ConfigStore) -> PathBuf {
    store.paths().config_dir.join(DIR)
}

/// One file of the directory as Settings lists it.
#[derive(Clone, Debug)]
pub struct Entry {
    pub name: String,
    pub label: Option<String>,
    pub path: PathBuf,
    /// Why it does not load (listed greyed, with Delete).
    pub problem: Option<Problem>,
    pub dark: bool,
    pub light: bool,
    /// A link (Home-Manager's into the store): read-only here.
    pub managed: bool,
}

/// The directory's files, as read last (a global as the theme crate's table is: the offers and the theme read it).
static ENTRIES: Mutex<Vec<Entry>> = Mutex::new(Vec::new());
/// The editor's draft as palette TOML.
static DRAFT: Mutex<Option<String>> = Mutex::new(None);

/// Reads the directory again: the list, and the palettes the theme crate resolves by name.
pub fn reload(dir: &Path) {
    let files = palette::load_dir(dir);
    let entries = files
        .iter()
        .map(|f| Entry {
            name: f.name.clone(),
            label: f.palette.as_ref().ok().and_then(|s| s.meta.label.clone()),
            path: f.path.clone(),
            problem: f.palette.as_ref().err().cloned(),
            dark: f.palette.as_ref().is_ok_and(|s| s.dark.is_some()),
            light: f.palette.as_ref().is_ok_and(|s| s.light.is_some()),
            managed: std::fs::symlink_metadata(&f.path).is_ok_and(|m| m.file_type().is_symlink()),
        })
        .collect();
    palette::set_user(files.into_iter().filter_map(|f| f.palette.ok()));
    *ENTRIES.lock().unwrap_or_else(|e| e.into_inner()) = entries;
}

pub fn entries() -> Vec<Entry> {
    ENTRIES.lock().unwrap_or_else(|e| e.into_inner()).clone()
}

pub fn draft() -> Option<String> {
    DRAFT.lock().unwrap_or_else(|e| e.into_inner()).clone()
}

fn set_draft(text: Option<String>) {
    *DRAFT.lock().unwrap_or_else(|e| e.into_inner()) = text;
}

/// Ends the draft; true when there was one (the theme has to be republished).
pub fn drop_draft() -> bool {
    DRAFT
        .lock()
        .unwrap_or_else(|e| e.into_inner())
        .take()
        .is_some()
}

/// Whether files can be written in `dir` (or, before it exists, in the directory it would be made in).
fn writable(dir: &Path) -> bool {
    if std::fs::symlink_metadata(dir).is_ok_and(|m| m.file_type().is_symlink()) {
        return false;
    }
    let probe_in = if dir.is_dir() {
        dir.to_path_buf()
    } else {
        match dir.parent() {
            Some(p) => p.to_path_buf(),
            None => return false,
        }
    };
    let probe = probe_in.join(format!(".kurashi-write-probe-{}", std::process::id()));
    let ok = std::fs::File::create(&probe).is_ok();
    let _ = std::fs::remove_file(&probe);
    ok
}

// ---------- the palette as JSON (the file's own shape) ----------

/// A palette in the file's shape as JSON: `{name, label?, category?, dark?: {<role>: "#hex", terminal?: {…}}, light?}`.
fn to_json(set: &PaletteSet) -> Value {
    toml::from_str::<toml::Value>(&set.to_toml())
        .ok()
        .and_then(|t| serde_json::to_value(t).ok())
        .unwrap_or(Value::Null)
}

fn without_nulls(v: &Value) -> Value {
    match v {
        Value::Object(m) => Value::Object(
            m.iter()
                .filter(|(_, v)| !v.is_null())
                .map(|(k, v)| (k.clone(), without_nulls(v)))
                .collect(),
        ),
        Value::Array(a) => Value::Array(a.iter().map(without_nulls).collect()),
        v => v.clone(),
    }
}

/// The palette the args describe (the file's shape: `label`, `dark`, `light`), validated as a file is: known roles,
/// colours, 16 terminal colours, the required roles of each scheme, at least one scheme.
fn from_args(args: &Value, name: &str) -> Result<PaletteSet, ActionError> {
    let bad = || ActionError::Invalid(E_ARGS.into());
    let mut doc = Map::new();
    doc.insert("name".into(), json!(name));
    doc.insert("category".into(), json!("custom"));
    if let Some(l) = args.get("label").and_then(Value::as_str) {
        let l = l.trim();
        if !l.is_empty() {
            doc.insert("label".into(), json!(l));
        }
    }
    for side in ["dark", "light"] {
        match args.get(side) {
            None | Some(Value::Null) => {}
            Some(v @ Value::Object(_)) => {
                doc.insert(side.into(), without_nulls(v));
            }
            Some(_) => return Err(bad()),
        }
    }
    let text = toml::to_string(&toml::Value::try_from(Value::Object(doc)).map_err(|_| bad())?)
        .map_err(|_| bad())?;
    let set = PaletteSet::from_toml(&text)
        .map_err(|e| ActionError::Invalid(format!("palettes.error.parse: {e}")))?;
    if set.missing_role().is_some() {
        return Err(ActionError::Invalid("palettes.error.missing_role".into()));
    }
    Ok(set)
}

// ---------- names ----------

/// The file name a palette with this label is saved as: its slug, or `palette` for a label with no letters a slug keeps
/// (a Japanese one), with `-2`, `-3`… while the name is taken — by a bundled palette, a reserved word, or another of the
/// user's files (not `replaces`, the one being edited). The note says why the name is not the label's own.
fn choose_name(label: &str, replaces: Option<&str>) -> (String, Option<&'static str>) {
    let base = match palette::slug(label) {
        s if s.is_empty() => "palette".to_owned(),
        s => s,
    };
    let taken = |n: &str| {
        Some(n) != replaces
            && (palette::check_name(n).is_err() || entries().iter().any(|e| e.name == n))
    };
    if !taken(&base) {
        return (base, None);
    }
    let note = match palette::check_name(&base) {
        Err(palette::NameError::Bundled) => "palettes.note.renamed_bundled",
        Err(palette::NameError::Reserved) => "palettes.note.renamed_reserved",
        _ => "palettes.note.renamed_taken",
    };
    let stem: String = base.chars().take(44).collect();
    let n = (2..)
        .map(|i| format!("{stem}-{i}"))
        .find(|n| !taken(n))
        .expect("a free name");
    (n, Some(note))
}

/// The name a save writes: the args' own `name` (checked, never another file's), else one from the label.
fn name_of(args: &Value) -> Result<(String, Option<&'static str>), ActionError> {
    let replaces = args.get("replaces").and_then(Value::as_str);
    if let Some(n) = args.get("name").and_then(Value::as_str) {
        palette::check_name(n).map_err(|e| ActionError::Invalid(e.key().into()))?;
        if Some(n) != replaces && entries().iter().any(|e| e.name == n) {
            return Err(ActionError::Invalid("palettes.error.name_taken".into()));
        }
        return Ok((n.to_owned(), None));
    }
    let label = args
        .get("label")
        .and_then(Value::as_str)
        .unwrap_or_default();
    Ok(choose_name(label, replaces))
}

// ---------- what the pipeline does to a draft ----------

/// The stages that move every colour, in effect now: what a "shown as" names when no wcag note names the role.
fn global_stages(input: &ThemeInput) -> Vec<&'static str> {
    let mut v = vec![];
    if input.oled {
        v.push("oled");
    }
    if input.contrast != ContrastLevel::Standard {
        v.push("contrast");
    }
    if input.season.is_some() {
        v.push("season");
    }
    if input.colorblind != kurashi_theme::Colorblind::None {
        v.push("colorblind");
    }
    if input.strong_chrome {
        v.push("chrome");
    }
    v
}

/// The draft resolved in `scheme` as the shell would show it: every role's final colour, and for each role the user
/// picked that a stage moved, `{picked, shown, stages, against?}` (wcag's note names the ground it was raised against).
fn resolved(set: &PaletteSet, base: &ThemeInput, scheme: Scheme) -> Value {
    let input = ThemeInput {
        source: Source::PaletteToml(set.to_toml()),
        scheme,
        ..base.clone()
    };
    let Ok((p, notes)) = kurashi_theme::resolve_palette(&input) else {
        return Value::Null;
    };
    let (own, from) = match scheme {
        Scheme::Dark => (
            set.dark.as_ref().or(set.light.as_ref()),
            set.dark.as_ref().map_or("light", |_| "dark"),
        ),
        Scheme::Light => (
            set.light.as_ref().or(set.dark.as_ref()),
            set.light.as_ref().map_or("dark", |_| "light"),
        ),
    };
    let stages = global_stages(&input);
    let mut moved = Map::new();
    for (role, picked) in own.into_iter().flatten() {
        let shown = p.get(role);
        if shown == *picked {
            continue;
        }
        let mut why: Vec<&str> = stages.clone();
        if role == "on_surface" && !matches!(input.ink, kurashi_theme::Ink::Palette) {
            why.push("ink");
        }
        // `wcag: <role> #a → #b (2.1 → 3.0:1 on <ground>, need 3)`.
        let prefix = format!("wcag: {role} ");
        let against = notes
            .iter()
            .filter(|n| n.stage == "wcag" && n.text.starts_with(&prefix))
            .find_map(|n| {
                let rest = n.text.split(":1 on ").nth(1)?;
                Some(rest.split(',').next()?.trim().to_owned())
            });
        if against.is_some() {
            why.push("wcag");
        }
        let mut m = json!({"picked": picked.hex(), "shown": shown.hex(), "stages": why});
        if let Some(a) = against {
            m["against"] = json!(a);
        }
        moved.insert(role.clone(), m);
    }
    let roles: Map<String, Value> = ROLES
        .iter()
        .map(|r| ((*r).to_owned(), json!(p.get(r).hex())))
        .collect();
    json!({"from": from, "roles": roles, "moved": moved})
}

/// The draft's colours on screen in both schemes (Settings draws the side being edited).
fn resolutions(set: &PaletteSet, store: &ConfigStore, hub: &Hub) -> Value {
    let pic = crate::theme::wallpaper_picture(hub);
    let base = crate::theme::input_with(store, pic.as_deref());
    json!({
        "dark": resolved(set, &base, Scheme::Dark),
        "light": resolved(set, &base, Scheme::Light),
    })
}

/// The palette `name` names: a bundled one, the user's, or `wallpaper` (the picture's colours as extracted now).
fn source_of(name: &str, store: &ConfigStore, hub: &Hub) -> Result<PaletteSet, ActionError> {
    if name == crate::theme::WALLPAPER_PALETTE {
        let pic = crate::theme::wallpaper_picture(hub)
            .ok_or_else(|| ActionError::Unavailable(E_NO_PICTURE.into()))?;
        let src = Source::WallpaperFile(pic, crate::theme::extraction_mode(store));
        return kurashi_theme::stages::source(&src)
            .map(|(s, _)| s)
            .map_err(|e| ActionError::Internal(e.to_string()));
    }
    kurashi_theme::bundled(name).map_err(|_| ActionError::Invalid(E_UNKNOWN.into()))
}

/// The quick swatches of the picker: the saved palette in effect's colours and the wallpaper's (when it has a picture).
fn swatches(store: &ConfigStore, hub: &Hub) -> Value {
    let pic = crate::theme::wallpaper_picture(hub);
    let input = crate::theme::input_with(store, pic.as_deref());
    let mut seen = std::collections::BTreeSet::new();
    let mut uniq = |v: Vec<String>| -> Vec<String> {
        v.into_iter().filter(|h| seen.insert(h.clone())).collect()
    };
    const SHOWN: &[&str] = &[
        "surface",
        "surface_container",
        "on_surface",
        "outline",
        "accent",
        "secondary",
        "tertiary",
        "success",
        "warning",
        "error",
    ];
    let palette = kurashi_theme::resolve_palette(&input)
        .map(|(p, _)| SHOWN.iter().map(|r| p.get(r).hex()).collect())
        .unwrap_or_default();
    let palette = uniq(palette);
    let wallpaper = pic
        .and_then(|p| {
            let src = Source::WallpaperFile(p, crate::theme::extraction_mode(store));
            kurashi_theme::stages::source(&src).ok()
        })
        .and_then(|(set, _)| {
            let roles = match input.scheme {
                Scheme::Dark => set.dark.or(set.light),
                Scheme::Light => set.light.or(set.dark),
            }?;
            Some(
                SHOWN
                    .iter()
                    .filter_map(|r| roles.get(*r).map(|c| c.hex()))
                    .collect(),
            )
        })
        .unwrap_or_default();
    let wallpaper = uniq(wallpaper);
    json!({"palette": palette, "wallpaper": wallpaper})
}

fn entry_json(e: &Entry) -> Value {
    let mut v = json!({
        "name": e.name,
        "label": e.label,
        "path": e.path,
        "dark": e.dark,
        "light": e.light,
        "managed": e.managed,
    });
    if let Some(p) = &e.problem {
        v["problem"] = json!({"key": p.key, "detail": p.detail});
    }
    v
}

fn refusal(errs: Vec<kurashi_ipc::OpError>) -> ActionError {
    let code = errs
        .first()
        .map_or("config.error.unrepresentable", |e| e.code.as_str());
    ActionError::Invalid(code.into())
}

// ---------- the actions ----------

/// `palette.list` / `palette.get` / `palette.duplicate` / `palette.draft` / `palette.draft.clear` / `palette.save` /
/// `palette.delete` (I453). Refusals carry i18n keys (`palettes.error.*`).
pub fn register_actions(
    actions: &mut ActionRegistry,
    hub: &Arc<Hub>,
    store: &Arc<ConfigStore>,
    fonts: Arc<dyn FontProvider + Send + Sync>,
) {
    let ctx = Ctx {
        hub: hub.clone(),
        store: store.clone(),
        fonts,
    };
    macro_rules! act {
        ($id:literal, $args:literal, $f:ident) => {{
            let ctx = ctx.clone();
            actions.register_with_args($id, concat!("action.", $id), $args, move |v: Value| {
                let ctx = ctx.clone();
                async move { ctx.$f(&v) }
            });
        }};
    }
    act!("palette.list", "{}", list);
    act!("palette.get", "{name}", get);
    act!("palette.duplicate", "{from}", duplicate);
    act!("palette.draft", "{label?, dark?, light?, replaces?}", draft);
    act!("palette.draft.clear", "{}", clear);
    act!(
        "palette.save",
        "{label?, name?, dark?, light?, replaces?, select?}",
        save
    );
    act!("palette.delete", "{name}", delete);
}

#[derive(Clone)]
pub struct Ctx {
    hub: Arc<Hub>,
    store: Arc<ConfigStore>,
    fonts: Arc<dyn FontProvider + Send + Sync>,
}

type Reply = Result<Option<Value>, ActionError>;

fn str_arg<'a>(v: &'a Value, key: &str) -> Result<&'a str, ActionError> {
    v.get(key)
        .and_then(Value::as_str)
        .filter(|s| !s.is_empty())
        .ok_or_else(|| ActionError::Invalid(E_ARGS.into()))
}

impl Ctx {
    pub fn new(
        hub: Arc<Hub>,
        store: Arc<ConfigStore>,
        fonts: Arc<dyn FontProvider + Send + Sync>,
    ) -> Self {
        Self { hub, store, fonts }
    }

    fn republish(&self) {
        crate::theme::republish(&self.hub, &self.store, self.fonts.as_ref());
    }

    /// Files changed: read them again; the offers, the config document and the theme follow.
    fn changed(&self) {
        reload(&dir(&self.store));
        self.store.packs_changed();
    }

    /// `{dir, writable, palettes: [{name, label, path, dark, light, managed, problem?}], swatches: {palette, wallpaper}}`.
    pub fn list(&self, _: &Value) -> Reply {
        let d = dir(&self.store);
        Ok(Some(json!({
            "dir": d,
            "writable": writable(&d),
            "palettes": entries().iter().map(entry_json).collect::<Vec<_>>(),
            "swatches": swatches(&self.store, &self.hub),
        })))
    }

    /// `{palette (the file's shape), custom, managed, path?, label_key?, resolved: {dark, light}}`.
    pub fn get(&self, v: &Value) -> Reply {
        let name = str_arg(v, "name")?;
        let set = source_of(name, &self.store, &self.hub)?;
        let entry = entries()
            .into_iter()
            .find(|e| e.name == name && e.problem.is_none());
        let custom = entry.is_some() && !palette::is_bundled(name);
        Ok(Some(json!({
            "palette": to_json(&set),
            "custom": custom,
            "managed": entry.as_ref().is_some_and(|e| e.managed),
            "path": entry.map(|e| e.path),
            "label_key": (!custom).then(|| format!("config.choice.palette.{name}")),
            "resolved": resolutions(&set, &self.store, &self.hub),
        })))
    }

    /// [`Self::get`] as the start of a new palette: the copy keeps the colours and the terminal tables, not the name.
    pub fn duplicate(&self, v: &Value) -> Reply {
        let from = str_arg(v, "from")?;
        let mut set = source_of(from, &self.store, &self.hub)?;
        let label_key = (!palette::is_user(from) || palette::is_bundled(from))
            .then(|| format!("config.choice.palette.{from}"));
        let label = set.meta.label.take();
        set.meta = palette::Meta {
            category: Some("custom".into()),
            ..Default::default()
        };
        let mut p = to_json(&set);
        p["name"] = Value::Null;
        Ok(Some(json!({
            "palette": p,
            "from": from,
            "from_label": label,
            "label_key": label_key,
            "resolved": resolutions(&set, &self.store, &self.hub),
        })))
    }

    /// The editor's draft, worn by the shell until it is cleared or saved, or the editor goes (no watcher of
    /// `theme.previews` left). Replies with the name a save would write and the draft as it shows in both schemes.
    pub fn draft(&self, v: &Value) -> Reply {
        if self.hub.subscribers(crate::theme::PREVIEWS_DOC) == 0 {
            return Err(ActionError::Unavailable(E_NO_EDITOR.into()));
        }
        let (name, note) = name_of(v)?;
        let set = from_args(v, &name)?;
        let text = set.to_toml();
        if draft().as_deref() != Some(text.as_str()) {
            set_draft(Some(text));
            self.republish();
        }
        Ok(Some(json!({
            "name": name,
            "note": note,
            "resolved": resolutions(&set, &self.store, &self.hub),
        })))
    }

    pub fn clear(&self, _: &Value) -> Reply {
        if drop_draft() {
            self.republish();
        }
        Ok(None)
    }

    /// Writes the palette (the file's shape), removes the one it replaces when the name changed, ends the draft and
    /// picks it (`select`, default true: one change, so Undo goes back to the palette before). `{name, path, rev?, undo?}`.
    pub fn save(&self, v: &Value) -> Reply {
        let d = dir(&self.store);
        if !writable(&d) {
            return Err(ActionError::Unavailable(E_READ_ONLY.into()));
        }
        let (name, note) = name_of(v)?;
        let set = from_args(v, &name)?;
        let path = d.join(format!("{name}.toml"));
        if std::fs::symlink_metadata(&path).is_ok_and(|m| m.file_type().is_symlink()) {
            return Err(ActionError::Unavailable(E_READ_ONLY.into()));
        }
        let write = || -> std::io::Result<()> {
            std::fs::create_dir_all(&d)?;
            let tmp = d.join(format!(".{name}.toml.tmp"));
            std::fs::write(&tmp, set.to_toml())?;
            std::fs::rename(&tmp, &path)
        };
        write().map_err(|e| {
            tracing::warn!(error = %e, path = %path.display(), "palette not written");
            ActionError::Internal(E_WRITE.into())
        })?;
        let replaced = v
            .get("replaces")
            .and_then(Value::as_str)
            .filter(|r| *r != name);
        if let Some(old) = replaced
            && let Some(e) = entries().into_iter().find(|e| e.name == old && !e.managed)
        {
            let _ = std::fs::remove_file(&e.path);
        }
        drop_draft();
        self.changed();
        let mut out = json!({"name": name, "path": path, "note": note});
        let select = v.get("select").and_then(Value::as_bool).unwrap_or(true);
        let current = crate::theme::s(&self.store, KEY);
        if select && (current != name) {
            let done = self
                .store
                .apply(&[ApplyOp::Set {
                    set: KEY.into(),
                    value: json!(name),
                    output: None,
                }])
                .map_err(refusal)?;
            out["rev"] = json!(done.rev);
            out["undo"] = json!(done.undo);
        }
        Ok(Some(out))
    }

    /// Removes a user palette's file (a broken one too). The palette in effect goes back to the default first (the user's
    /// value reset: one change). `{reset, rev?, undo?}`.
    pub fn delete(&self, v: &Value) -> Reply {
        let name = str_arg(v, "name")?;
        let entry = entries()
            .into_iter()
            .find(|e| e.name == name)
            .ok_or_else(|| ActionError::Invalid(E_UNKNOWN.into()))?;
        if entry.managed || !writable(&dir(&self.store)) {
            return Err(ActionError::Unavailable(E_READ_ONLY.into()));
        }
        let mut out = json!({"reset": false});
        if crate::theme::s(&self.store, KEY) == name {
            let done = self
                .store
                .apply(&[ApplyOp::Reset {
                    reset: KEY.into(),
                    output: None,
                }])
                .map_err(refusal)?;
            out = json!({"reset": true, "rev": done.rev, "undo": done.undo});
        }
        std::fs::remove_file(&entry.path).map_err(|e| {
            tracing::warn!(error = %e, path = %entry.path.display(), "palette not removed");
            ActionError::Internal(E_WRITE.into())
        })?;
        self.changed();
        Ok(Some(out))
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    /// One test at a time: the list and the draft are process-wide, as the daemon has one of each.
    static SERIAL: Mutex<()> = Mutex::new(());

    fn setup() -> (tempfile::TempDir, Arc<Hub>, Arc<ConfigStore>, Ctx) {
        let root = tempfile::tempdir().unwrap();
        std::fs::create_dir_all(root.path().join("config")).unwrap();
        let hub = Hub::new();
        let store = ConfigStore::open(
            hub.clone(),
            kurashi_schema::v1::registry(),
            kurashi_config::Paths::rooted(root.path()),
            kurashi_config::Options::default(),
        );
        let fonts: Arc<dyn FontProvider + Send + Sync> =
            Arc::new(kurashi_theme::FakeFonts::new(&[]));
        crate::theme::register(&hub, &store, fonts.clone());
        reload(&dir(&store));
        set_draft(None);
        let ctx = Ctx::new(hub.clone(), store.clone(), fonts);
        (root, hub, store, ctx)
    }

    fn token(hub: &Hub, key: &str) -> String {
        hub.snapshot(crate::theme::DOC).unwrap().1["tokens"][key]
            .as_str()
            .unwrap_or_default()
            .to_owned()
    }

    fn notes(hub: &Hub) -> String {
        hub.snapshot(crate::theme::DOC).unwrap().1["notes"].to_string()
    }

    fn offered(hub: &Hub) -> Vec<Value> {
        let settings = hub.snapshot(crate::config::SETTINGS_DOC).unwrap().1;
        let mut found = vec![];
        fn rows(v: &Value, out: &mut Vec<Value>) {
            match v {
                Value::Object(m) => {
                    if m.get("key").and_then(Value::as_str) == Some(KEY) {
                        out.extend(
                            m.get("choices")
                                .and_then(Value::as_array)
                                .cloned()
                                .unwrap_or_default(),
                        );
                    }
                    m.values().for_each(|x| rows(x, out));
                }
                Value::Array(a) => a.iter().for_each(|x| rows(x, out)),
                _ => {}
            }
        }
        rows(&settings, &mut found);
        found
    }

    fn mine(accent: &str) -> Value {
        let g = to_json(&kurashi_theme::bundled("gruvbox").unwrap());
        let mut dark = g["dark"].clone();
        dark["accent"] = json!(accent);
        json!({"label": "My Gruvbox", "dark": dark})
    }

    /// A custom file loads, is offered under `palettes` with group `custom`; a broken one is listed with its reason;
    /// a bundled name cannot be shadowed.
    #[test]
    fn files_load_and_are_offered() {
        let _one = SERIAL.lock().unwrap_or_else(|e| e.into_inner());
        let (_root, hub, store, _) = setup();
        let d = dir(&store);
        std::fs::create_dir_all(&d).unwrap();
        let mut set = kurashi_theme::bundled("nord").unwrap();
        set.name = "x".into();
        set.meta.label = Some("Cold".into());
        std::fs::write(d.join("cold.toml"), set.to_toml()).unwrap();
        std::fs::write(d.join("broken.toml"), "name = \"broken\"\n[dark\n").unwrap();
        std::fs::write(d.join("gruvbox.toml"), set.to_toml()).unwrap();
        reload(&d);
        store.packs_changed();
        let offers = offered(&hub);
        let of = |n: &str| {
            offers
                .iter()
                .find(|o| o["value"] == n)
                .cloned()
                .unwrap_or(Value::Null)
        };
        assert_eq!(of("cold")["group"], "custom");
        assert_eq!(of("cold")["label"], "Cold");
        assert_eq!(of("broken")["enabled"], false);
        assert_eq!(of("broken")["reason"], "palettes.error.parse");
        assert_eq!(
            of("gruvbox")["group"],
            "common",
            "the bundled one is offered, not the file"
        );
        assert_eq!(
            offers.iter().filter(|o| o["value"] == "gruvbox").count(),
            2,
            "the file is listed as a problem beside it"
        );
        assert_eq!(
            offers
                .iter()
                .find(|o| o["value"] == "gruvbox" && o["group"] == "custom")
                .unwrap()["reason"],
            "palettes.error.name_bundled"
        );
        let e = entries();
        let broken = e.iter().find(|e| e.name == "broken").unwrap();
        assert!(!broken.problem.as_ref().unwrap().detail.is_empty());
        // The palette resolves by name: picked, the theme wears it.
        store
            .apply(&[
                ApplyOp::Set {
                    set: KEY.into(),
                    value: json!("cold"),
                    output: None,
                },
                ApplyOp::Set {
                    set: "theme.colors.scheme".into(),
                    value: json!("dark"),
                    output: None,
                },
            ])
            .unwrap();
        assert_eq!(
            token(&hub, "color.accent"),
            set.dark.as_ref().unwrap()["accent"].hex()
        );
        let shown = crate::theme::previews(&store, &kurashi_theme::FakeFonts::new(&[]), None);
        assert!(
            shown["palettes"]
                .as_array()
                .unwrap()
                .iter()
                .any(|p| p["name"] == "cold")
        );
        palette::set_user([]);
        reload(Path::new("/nonexistent"));
    }

    /// Save writes a file that reads back through `from_toml`, picks it (undoable), and ends the draft; a draft never
    /// persists and ends with the editor; deleting the palette in effect falls back to the default.
    #[test]
    fn save_draft_delete() {
        let _one = SERIAL.lock().unwrap_or_else(|e| e.into_inner());
        let (_root, hub, store, ctx) = setup();
        let default_accent = token(&hub, "color.accent");
        // No editor (nothing watches the previews): no draft.
        assert_eq!(
            ctx.draft(&mine("#3366ff")).unwrap_err(),
            ActionError::Unavailable(E_NO_EDITOR.into())
        );
        hub.subscribe(crate::theme::PREVIEWS_DOC).unwrap();
        let r = ctx.draft(&mine("#3366ff")).unwrap().unwrap();
        assert_eq!(r["name"], "my-gruvbox");
        assert_eq!(r["resolved"]["dark"]["roles"]["accent"], "#3366ff");
        assert_eq!(r["resolved"]["light"]["from"], "dark");
        assert_eq!(token(&hub, "color.accent"), "#3366ff");
        assert!(notes(&hub).contains("theme.note.palette_draft"));
        // Nothing on disk, and the config still names the default.
        assert!(!dir(&store).join("my-gruvbox.toml").exists());
        assert_eq!(crate::theme::s(&store, KEY), "wa-iro");
        // A low-contrast accent: shown as something else, and why.
        let low = ctx.draft(&mine("#2a2a2a")).unwrap().unwrap();
        let m = &low["resolved"]["dark"]["moved"]["accent"];
        assert_eq!(m["picked"], "#2a2a2a");
        assert_ne!(m["shown"], "#2a2a2a");
        assert!(
            m["stages"].as_array().unwrap().contains(&json!("wcag")),
            "{m}"
        );
        assert_eq!(m["against"], "surface");
        // The editor goes (Settings closed or crashed): the draft ends, the saved colours are back.
        hub.unsubscribe(crate::theme::PREVIEWS_DOC);
        assert!(draft().is_none());
        crate::theme::republish(&hub, &store, &kurashi_theme::FakeFonts::new(&[]));
        assert_eq!(token(&hub, "color.accent"), default_accent);
        assert!(!notes(&hub).contains("palette_draft"));

        // Save: a file in the bundled format, picked, the draft gone.
        hub.subscribe(crate::theme::PREVIEWS_DOC).unwrap();
        ctx.draft(&mine("#3366ff")).unwrap();
        let saved = ctx.save(&mine("#3366ff")).unwrap().unwrap();
        assert_eq!(saved["name"], "my-gruvbox");
        assert!(saved["undo"].is_string());
        let path = dir(&store).join("my-gruvbox.toml");
        let back = PaletteSet::from_toml(&std::fs::read_to_string(&path).unwrap()).unwrap();
        assert_eq!(back.dark.unwrap()["accent"].hex(), "#3366ff");
        assert_eq!(back.meta.label.as_deref(), Some("My Gruvbox"));
        assert_eq!(back.meta.category.as_deref(), Some("custom"));
        assert!(draft().is_none());
        assert_eq!(crate::theme::s(&store, KEY), "my-gruvbox");
        assert_eq!(token(&hub, "color.accent"), "#3366ff");
        // The same label again (a new palette): another file name, and the reply says why.
        let (n, note) = name_of(&json!({"label": "My Gruvbox"})).unwrap();
        assert_eq!(
            (n.as_str(), note),
            ("my-gruvbox-2", Some("palettes.note.renamed_taken"))
        );
        // Editing it keeps its name; a bundled label is never its name.
        assert_eq!(
            name_of(&json!({"label": "My Gruvbox", "replaces": "my-gruvbox"}))
                .unwrap()
                .0,
            "my-gruvbox"
        );
        assert_eq!(
            name_of(&json!({"label": "Gruvbox"})).unwrap(),
            ("gruvbox-2".into(), Some("palettes.note.renamed_bundled"))
        );
        assert_eq!(name_of(&json!({"label": "夜"})).unwrap().0, "palette");
        assert!(name_of(&json!({"name": "../x"})).is_err());
        // get / duplicate: the file's shape, ready for the editor.
        let got = ctx.get(&json!({"name": "my-gruvbox"})).unwrap().unwrap();
        assert_eq!(got["custom"], true);
        assert_eq!(got["palette"]["dark"]["accent"], "#3366ff");
        let dup = ctx.duplicate(&json!({"from": "gruvbox"})).unwrap().unwrap();
        assert_eq!(dup["label_key"], "config.choice.palette.gruvbox");
        assert!(dup["palette"]["dark"]["terminal"]["colors"].is_array());
        assert!(ctx.duplicate(&json!({"from": "nope"})).is_err());

        // Delete the palette in effect: the row is reset, the default is back.
        let gone = ctx.delete(&json!({"name": "my-gruvbox"})).unwrap().unwrap();
        assert_eq!(gone["reset"], true);
        assert!(!path.exists());
        assert_eq!(crate::theme::s(&store, KEY), "wa-iro");
        assert_eq!(token(&hub, "color.accent"), default_accent);
        assert!(ctx.delete(&json!({"name": "my-gruvbox"})).is_err());

        // A palette deleted by hand while in effect: the default shows, and the document says so.
        ctx.save(&mine("#3366ff")).unwrap();
        std::fs::remove_file(&path).unwrap();
        reload(&dir(&store));
        store.packs_changed();
        assert_eq!(crate::theme::s(&store, KEY), "my-gruvbox");
        assert_eq!(token(&hub, "color.accent"), default_accent);
        assert!(notes(&hub).contains("theme.note.palette_gone"));
        hub.unsubscribe(crate::theme::PREVIEWS_DOC);
        palette::set_user([]);
        reload(Path::new("/nonexistent"));
    }
}
