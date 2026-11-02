//! Motion packs (K83, brief §3): a motion profile as a file, `motion/<id>.toml` built in and
//! `$XDG_CONFIG_HOME/kurashi/motion/<id>.toml` from the user (a user pack replaces a built-in one of the same id).
//!
//! ```toml
//! name = "origami"
//! label = "config.choice.motion.profile.origami"   # default: config.choice.motion.profile.<name>
//! base = "expressive"        # expressive · calm · lively · none · reduced (default expressive)
//! [timing]                   # curves per role (curve.rs) and their durations (0 / left out = K74's role default)
//! open = "paper"   open_ms = 520
//! [form]                     # the default form, then per surface class
//! open = "fold"    close = "fold"
//! [form.peek] open = "grow"  close = "grow"
//! [params.fold] panels = 0  axes = 2  crease = 0.35
//! [accents] content = "late"  stagger_ms = 0  squash = 0  jelly = 0  overshoot_cap = 1  shadow = "fade"
//! [curves] my-snap = "segments(…)"
//! [recipes.my-pop]           # W59.7
//! ```
//!
//! `base` (W59.1, CONTRACT-CHANGE): what today's K42/K74 machinery does under the pack — the spring family the morphs
//! retarget with and the island's faces spring on, the small-control durations and easings, and whether surfaces move on
//! curves (`expressive`, `reduced`), on springs (`calm`, `lively`) or not at all (`none`).
//!
//! **Blocks.** `[timing]`, `[form]` (with `[params]`) and `[accents]` are each the pack's own when the table is there —
//! even empty, which means the defaults — and the style's pack's when it is not. So `calm`, `lively`, `none` and
//! `expressive`, which carry only a base, are what they were before K83: a way of moving the style's forms and curves
//! (calm on washi still bleeds), while a full pack replaces all of it.

use std::collections::BTreeMap;
use std::path::{Path, PathBuf};
use std::sync::OnceLock;

use serde_json::{Map, Value};

use crate::curve::{self, Curve, Spec};
use crate::forms::{self, SURFACES};

/// The timing roles (brief §4), in the order the arrays here keep them.
pub const ROLES: [&str; 4] = ["open", "close", "fast", "effects"];
/// A role's duration limit (ms), as the schema's `theme.motion.timing.*_ms`.
pub const MAX_MS: i64 = 3000;

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Base {
    /// Surfaces move on curves; what is not on a curve springs as calm does (K74).
    Expressive,
    /// K42's springs, settling without a bounce.
    Calm,
    /// K42's bouncy springs; small-control durations at 0.8×, squash and stretch.
    Lively,
    /// No motion.
    None,
    /// Reduce motion (K83 D1): short fades, no springs, no overshoot.
    Reduced,
}

impl Base {
    pub fn parse(s: &str) -> Option<Base> {
        Some(match s {
            "expressive" => Base::Expressive,
            "calm" => Base::Calm,
            "lively" => Base::Lively,
            "none" => Base::None,
            "reduced" => Base::Reduced,
            _ => return None,
        })
    }
}

/// One role of `[timing]`: its curve (`None` = the default's) and duration (0 = K74's role default).
#[derive(Clone, Debug, Default, PartialEq)]
pub struct Role {
    pub curve: Option<Spec>,
    pub ms: u32,
}

/// `[form]` and `[params]`: the default forms, per-surface forms and the forms' parameters.
#[derive(Clone, Debug, Default, PartialEq)]
pub struct Forms {
    pub open: Option<String>,
    pub close: Option<String>,
    /// surface → (open, close).
    pub surfaces: BTreeMap<String, (Option<String>, Option<String>)>,
    pub params: BTreeMap<String, Map<String, Value>>,
}

#[derive(Clone, Debug, Default, PartialEq)]
pub struct Accents {
    pub content: Option<String>,
    pub stagger_ms: Option<i64>,
    pub squash: Option<f64>,
    pub jelly: Option<f64>,
    pub overshoot_cap: Option<f64>,
    pub shadow: Option<String>,
}

#[derive(Clone, Debug, PartialEq)]
pub struct Pack {
    pub id: String,
    /// i18n keys (or plain text in a user's pack).
    pub label: String,
    pub description: String,
    pub bundled: bool,
    pub base: Option<Base>,
    pub timing: Option<[Role; 4]>,
    pub forms: Option<Forms>,
    pub accents: Option<Accents>,
    /// `[curves]`: named curves (a user's "Save as preset…").
    pub curves: BTreeMap<String, Curve>,
    /// `[recipes]` as written; `recipe.rs` validates them (W59.7).
    pub recipes: BTreeMap<String, Value>,
    /// The file it was read from (none for a built-in pack): Settings' "open the pack file".
    pub path: Option<PathBuf>,
}

/// A problem in a pack: which pack, the i18n key of what is wrong, and the detail (a key, a value, a parse error).
#[derive(Clone, Debug, PartialEq)]
pub struct Diag {
    pub pack: String,
    pub key: &'static str,
    pub detail: String,
}

impl std::fmt::Display for Diag {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(
            f,
            "motion pack {}: {} ({})",
            self.pack, self.key, self.detail
        )
    }
}

/// A pack file that cannot be read (TOML, a bad name): skipped.
pub const DIAG_BROKEN: &str = "config.diag.motion.broken";
/// A key or value a pack may not hold: left out, the rest of the pack applies.
pub const DIAG_KEY: &str = "config.diag.motion.key";
/// A form id that does not exist.
pub const DIAG_FORM: &str = "config.diag.form.unknown";

impl Pack {
    /// A pack with nothing of its own: the base only.
    fn empty(id: &str, bundled: bool) -> Pack {
        Pack {
            id: id.to_owned(),
            label: format!("config.choice.motion.profile.{id}"),
            description: format!("config.choice.motion.profile.{id}.desc"),
            bundled,
            base: None,
            timing: None,
            forms: None,
            accents: None,
            curves: BTreeMap::new(),
            recipes: BTreeMap::new(),
            path: None,
        }
    }

    /// Whether its default forms can be drawn now (a pack built on forms whose card has not merged is offered disabled).
    /// Its own recipes count as drawn (W59.7): a broken one falls back when resolved, with its diagnostic.
    pub fn available(&self) -> bool {
        self.forms.as_ref().is_none_or(|f| {
            [&f.open, &f.close].into_iter().flatten().all(|id| {
                self.recipes.contains_key(id) || forms::form(id).is_some_and(|m| m.available)
            })
        })
    }
}

/// Parses one pack; `fallback_id` (the file's stem) when it names none. `Err` = the file is skipped; the `Vec` lists
/// what was left out of a pack that loads.
pub fn parse(src: &str, fallback_id: &str, bundled: bool) -> Result<(Pack, Vec<Diag>), Diag> {
    let broken = |detail: String| Diag {
        pack: fallback_id.to_owned(),
        key: DIAG_BROKEN,
        detail,
    };
    let v: toml::Table = toml::from_str(src).map_err(|e| broken(e.to_string()))?;
    let id = v
        .get("name")
        .and_then(toml::Value::as_str)
        .unwrap_or(fallback_id)
        .to_owned();
    if !curve::is_ident(&id) {
        return Err(broken(format!("name {id:?}")));
    }
    let mut p = Pack::empty(&id, bundled);
    let mut diags = vec![];
    let mut bad = |detail: String| {
        diags.push(Diag {
            pack: id.clone(),
            key: DIAG_KEY,
            detail,
        })
    };
    for (k, val) in &v {
        match (k.as_str(), val) {
            ("name", _) => {}
            ("label", toml::Value::String(s)) => p.label = s.clone(),
            ("description", toml::Value::String(s)) => p.description = s.clone(),
            ("base", toml::Value::String(s)) if Base::parse(s).is_some() => p.base = Base::parse(s),
            ("timing", toml::Value::Table(t)) => p.timing = Some(timing(t, &mut bad)),
            ("form", toml::Value::Table(_)) | ("params", toml::Value::Table(_)) => {}
            ("accents", toml::Value::Table(t)) => p.accents = Some(accents(t, &mut bad)),
            ("curves", toml::Value::Table(t)) => {
                for (name, c) in t {
                    let parsed = c.as_str().map(curve::parse);
                    match parsed {
                        Some(Ok(spec))
                            if curve::preset(name).is_none() && curve::is_ident(name) =>
                        {
                            match spec.curve() {
                                Some(c) => {
                                    p.curves.insert(name.clone(), c);
                                }
                                None => bad(format!("curves.{name}: names another curve")),
                            }
                        }
                        Some(Err(e)) => bad(format!("curves.{name}: {}", e.key())),
                        _ => bad(format!("curves.{name}")),
                    }
                }
            }
            ("recipes", toml::Value::Table(t)) => {
                for (name, r) in t {
                    if let Ok(j) = serde_json::to_value(r) {
                        p.recipes.insert(name.clone(), j);
                    }
                }
            }
            _ => bad(k.clone()),
        }
    }
    let form = v.get("form").and_then(toml::Value::as_table);
    let params = v.get("params").and_then(toml::Value::as_table);
    if form.is_some() || params.is_some() {
        let mut f = Forms::default();
        for (k, val) in form.into_iter().flatten() {
            match (k.as_str(), val) {
                ("open" | "close", toml::Value::String(id)) => {
                    let ok = form_id(id, &p.recipes, &mut diags, &p.id);
                    if k == "open" {
                        f.open = ok;
                    } else {
                        f.close = ok;
                    }
                }
                (surface, toml::Value::Table(t)) if SURFACES.contains(&surface) => {
                    let mut pair = (None, None);
                    for (dir, id) in t {
                        match (dir.as_str(), id.as_str()) {
                            ("open", Some(id)) => {
                                pair.0 = form_id(id, &p.recipes, &mut diags, &p.id)
                            }
                            ("close", Some(id)) => {
                                pair.1 = form_id(id, &p.recipes, &mut diags, &p.id)
                            }
                            _ => diags.push(Diag {
                                pack: p.id.clone(),
                                key: DIAG_KEY,
                                detail: format!("form.{surface}.{dir}"),
                            }),
                        }
                    }
                    f.surfaces.insert(surface.to_owned(), pair);
                }
                _ => diags.push(Diag {
                    pack: p.id.clone(),
                    key: DIAG_KEY,
                    detail: format!("form.{k}"),
                }),
            }
        }
        for (form, val) in params.into_iter().flatten() {
            match (forms::form(form), val.as_table()) {
                (Some(_), Some(t)) => {
                    if let Ok(Value::Object(m)) = serde_json::to_value(t) {
                        f.params.insert(form.clone(), m);
                    }
                }
                _ => diags.push(Diag {
                    pack: p.id.clone(),
                    key: DIAG_FORM,
                    detail: format!("params.{form}"),
                }),
            }
        }
        p.forms = Some(f);
    }
    Ok((p, diags))
}

/// A form a pack may name: a built-in one, or a recipe of its own (W59.7; validated when resolved).
fn form_id(
    id: &str,
    recipes: &BTreeMap<String, Value>,
    diags: &mut Vec<Diag>,
    pack: &str,
) -> Option<String> {
    if forms::form(id).is_some() || recipes.contains_key(id) {
        Some(id.to_owned())
    } else {
        diags.push(Diag {
            pack: pack.to_owned(),
            key: DIAG_FORM,
            detail: id.to_owned(),
        });
        None
    }
}

fn timing(t: &toml::Table, bad: &mut impl FnMut(String)) -> [Role; 4] {
    let mut roles: [Role; 4] = Default::default();
    for (k, val) in t {
        let (role, is_ms) = match k.strip_suffix("_ms") {
            Some(r) => (r, true),
            None => (k.as_str(), false),
        };
        let Some(i) = ROLES.iter().position(|r| *r == role) else {
            bad(format!("timing.{k}"));
            continue;
        };
        if is_ms {
            match val.as_integer() {
                Some(ms) if (0..=MAX_MS).contains(&ms) => roles[i].ms = ms as u32,
                _ => bad(format!("timing.{k}")),
            }
            continue;
        }
        // A bad curve is left out: the role takes the default's (a diagnostic says why).
        match val.as_str().map(curve::parse) {
            Some(Ok(spec)) => roles[i].curve = Some(spec),
            Some(Err(e)) => bad(format!("timing.{k}: {}", e.key())),
            None => bad(format!("timing.{k}")),
        }
    }
    roles
}

fn accents(t: &toml::Table, bad: &mut impl FnMut(String)) -> Accents {
    let mut a = Accents::default();
    let num = |v: &toml::Value| v.as_float().or_else(|| v.as_integer().map(|i| i as f64));
    for (k, val) in t {
        let ok = match k.as_str() {
            "content" => val
                .as_str()
                .filter(|s| ["late", "with", "cascade"].contains(s))
                .map(|s| a.content = Some(s.to_owned()))
                .is_some(),
            "shadow" => val
                .as_str()
                .filter(|s| ["carry", "fade"].contains(s))
                .map(|s| a.shadow = Some(s.to_owned()))
                .is_some(),
            "stagger_ms" => val
                .as_integer()
                .filter(|v| (0..=60).contains(v))
                .map(|v| a.stagger_ms = Some(v))
                .is_some(),
            "squash" => num(val)
                .filter(|v| (0.0..=0.15).contains(v))
                .map(|v| a.squash = Some(v))
                .is_some(),
            "jelly" => num(val)
                .filter(|v| (0.0..=1.0).contains(v))
                .map(|v| a.jelly = Some(v))
                .is_some(),
            "overshoot_cap" => num(val)
                .filter(|v| (0.0..=1.0).contains(v))
                .map(|v| a.overshoot_cap = Some(v))
                .is_some(),
            _ => false,
        };
        if !ok {
            bad(format!("accents.{k}"));
        }
    }
    a
}

/// The built-in packs (K83 §12): today's four profiles and reduce motion, the motion of the looks that had one (W53's
/// `[decor] motion.*`, moved here bit-exact), and the new profiles W59.9 finishes (offered once their forms exist).
const BUNDLED: &[(&str, &str)] = &[
    (
        "expressive",
        include_str!("../../../motion/expressive.toml"),
    ),
    ("calm", include_str!("../../../motion/calm.toml")),
    ("lively", include_str!("../../../motion/lively.toml")),
    ("none", include_str!("../../../motion/none.toml")),
    ("reduced", include_str!("../../../motion/reduced.toml")),
    // Today's look motion (W53), now packs of the looks' names.
    ("washi", include_str!("../../../motion/washi.toml")),
    ("material", include_str!("../../../motion/material.toml")),
    ("terminal", include_str!("../../../motion/terminal.toml")),
    ("aqua", include_str!("../../../motion/aqua.toml")),
    ("vibrancy", include_str!("../../../motion/vibrancy.toml")),
    ("win95", include_str!("../../../motion/win95.toml")),
    ("luna", include_str!("../../../motion/luna.toml")),
    ("aero", include_str!("../../../motion/aero.toml")),
    ("fluent", include_str!("../../../motion/fluent.toml")),
    ("ps2", include_str!("../../../motion/ps2.toml")),
    ("snes", include_str!("../../../motion/snes.toml")),
    ("kawaii", include_str!("../../../motion/kawaii.toml")),
    ("yorha", include_str!("../../../motion/yorha.toml")),
    (
        "hallownest",
        include_str!("../../../motion/hallownest.toml"),
    ),
    ("souls", include_str!("../../../motion/souls.toml")),
    // K83 §12's new profiles (drafts; W59.9 tunes them and the styles that recommend them).
    ("origami", include_str!("../../../motion/origami.toml")),
    ("sumi", include_str!("../../../motion/sumi.toml")),
    ("pop", include_str!("../../../motion/pop.toml")),
    ("liquid", include_str!("../../../motion/liquid.toml")),
    ("phosphor", include_str!("../../../motion/phosphor.toml")),
    ("glitch", include_str!("../../../motion/glitch.toml")),
    ("ember", include_str!("../../../motion/ember.toml")),
    ("outline", include_str!("../../../motion/outline.toml")),
    ("pudding", include_str!("../../../motion/pudding.toml")),
    ("genie", include_str!("../../../motion/genie.toml")),
];

/// The packs in effect: built in, then the user's.
#[derive(Clone, Debug, Default)]
pub struct Registry {
    pub packs: Vec<Pack>,
    pub diags: Vec<Diag>,
}

impl Registry {
    /// The built-in packs, parsed once.
    pub fn bundled() -> &'static Registry {
        static CELL: OnceLock<Registry> = OnceLock::new();
        CELL.get_or_init(|| {
            let mut r = Registry::default();
            for (id, src) in BUNDLED {
                r.add(parse(src, id, true));
            }
            r
        })
    }

    /// The built-in packs and the ones in `dirs` (a pack of the same id replaces the built-in one; a broken file is
    /// skipped with a diagnostic).
    pub fn load(dirs: &[PathBuf]) -> Registry {
        let mut r = Registry::bundled().clone();
        for dir in dirs {
            let Ok(rd) = std::fs::read_dir(dir) else {
                continue;
            };
            let mut files: Vec<PathBuf> = rd
                .flatten()
                .map(|e| e.path())
                .filter(|p| p.extension().is_some_and(|x| x == "toml"))
                .collect();
            files.sort();
            for f in files {
                r.add(read(&f));
            }
        }
        r
    }

    fn add(&mut self, parsed: Result<(Pack, Vec<Diag>), Diag>) {
        match parsed {
            Ok((p, diags)) => {
                self.diags.extend(diags);
                match self.packs.iter_mut().find(|x| x.id == p.id) {
                    Some(slot) => *slot = p,
                    None => self.packs.push(p),
                }
            }
            Err(d) => self.diags.push(d),
        }
    }

    pub fn find(&self, id: &str) -> Option<&Pack> {
        self.packs.iter().find(|p| p.id == id)
    }

    /// A named curve: from these packs first (the profile's, the style's), then any pack's (a user's saved presets).
    pub fn curve(&self, name: &str, first: &[Option<&Pack>]) -> Option<Curve> {
        first
            .iter()
            .flatten()
            .copied()
            .chain(self.packs.iter())
            .find_map(|p| p.curves.get(name).cloned())
    }
}

fn read(path: &Path) -> Result<(Pack, Vec<Diag>), Diag> {
    let stem = path
        .file_stem()
        .and_then(|s| s.to_str())
        .unwrap_or_default();
    let src = std::fs::read_to_string(path).map_err(|e| Diag {
        pack: stem.to_owned(),
        key: DIAG_BROKEN,
        detail: e.to_string(),
    })?;
    parse(&src, stem, false).map(|(mut p, d)| {
        p.path = Some(path.to_path_buf());
        (p, d)
    })
}

/// `$XDG_CONFIG_HOME/kurashi/motion` (or `~/.config/kurashi/motion`): the user's packs.
pub fn user_dir() -> Option<PathBuf> {
    std::env::var_os("XDG_CONFIG_HOME")
        .map(PathBuf::from)
        .filter(|p| p.is_absolute())
        .or_else(|| std::env::var_os("HOME").map(|h| PathBuf::from(h).join(".config")))
        .map(|c| c.join("kurashi").join("motion"))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn every_bundled_pack_parses_cleanly() {
        let r = Registry::bundled();
        assert_eq!(r.packs.len(), BUNDLED.len());
        assert!(r.diags.is_empty(), "{:?}", r.diags);
        for (id, _) in BUNDLED {
            let p = r.find(id).unwrap();
            assert_eq!(p.id, *id, "a bundled pack's name is its file's");
            assert!(p.bundled);
        }
        // The contract's built-ins are there.
        for id in [
            "expressive",
            "calm",
            "lively",
            "none",
            "reduced",
            "fluent",
            "aqua",
            "material",
            "snes",
            "ps2",
            "kawaii",
        ] {
            assert!(r.find(id).is_some(), "{id}");
        }
    }

    #[test]
    fn todays_profiles_are_a_base_only() {
        for id in ["expressive", "calm", "lively", "none"] {
            let p = Registry::bundled().find(id).unwrap();
            assert!(
                p.timing.is_none() && p.forms.is_none() && p.accents.is_none(),
                "{id}"
            );
        }
        let r = Registry::bundled().find("reduced").unwrap();
        assert_eq!(r.base, Some(Base::Reduced));
        assert_eq!(r.forms.as_ref().unwrap().open.as_deref(), Some("fade"));
    }

    #[test]
    fn a_pack_reads_every_block() {
        let (p, diags) = parse(
            r#"
name = "mine"
base = "lively"
[timing]
open = "cubic-bezier(0.2, 0, 0, 1)"
open_ms = 300
effects = "my-snap"
[form]
open = "slide"
[form.toast]
close = "fade"
[params.fold]
panels = 3
[accents]
jelly = 0.4
content = "cascade"
[curves]
my-snap = "segments(0.1 0 0.2 0.5 0.5 0.6, 0.6 0.7 0.9 1 1 1)"
"#,
            "file",
            false,
        )
        .unwrap();
        assert!(diags.is_empty(), "{diags:?}");
        assert_eq!(p.id, "mine");
        assert_eq!(p.label, "config.choice.motion.profile.mine");
        assert_eq!(p.base, Some(Base::Lively));
        let t = p.timing.unwrap();
        assert_eq!(t[0].ms, 300);
        assert_eq!(t[3].curve, Some(Spec::Named("my-snap".into())));
        let f = p.forms.unwrap();
        assert_eq!(f.open.as_deref(), Some("slide"));
        assert_eq!(f.surfaces["toast"], (None, Some("fade".into())));
        assert_eq!(f.params["fold"]["panels"], 3);
        assert_eq!(p.accents.unwrap().jelly, Some(0.4));
        assert!(matches!(p.curves["my-snap"], Curve::Cubic(_)));
    }

    #[test]
    fn bad_parts_are_left_out_with_a_diagnostic_and_broken_files_skipped() {
        let (p, diags) = parse(
            "[timing]\nopen = \"cubic-bezier(1.4, 0, 0, 1)\"\nclose_ms = 99999\nwobble = 1\n[form]\nopen = \"warp\"\n[accents]\nsquash = 0.9\n",
            "bad",
            false,
        )
        .unwrap();
        let t = p.timing.unwrap();
        assert_eq!(t[0].curve, None, "a bad curve falls back to the default's");
        assert_eq!(t[1].ms, 0);
        assert_eq!(p.forms.unwrap().open, None);
        assert_eq!(p.accents.unwrap().squash, None);
        let details: Vec<_> = diags.iter().map(|d| d.detail.as_str()).collect();
        assert!(
            details.contains(&"timing.open: error.config.curve.x_range"),
            "{details:?}"
        );
        assert!(details.contains(&"timing.close_ms"));
        assert!(details.contains(&"timing.wobble"));
        assert!(details.contains(&"warp"));
        assert!(details.contains(&"accents.squash"));
        assert_eq!(
            parse("name = 3\n[[", "x", false).unwrap_err().key,
            DIAG_BROKEN
        );
        assert_eq!(
            parse("name = \"Not An Id\"", "x", false).unwrap_err().key,
            DIAG_BROKEN
        );
    }

    #[test]
    fn a_user_pack_replaces_a_built_in_one_and_adds_its_own() {
        let dir = std::env::temp_dir().join(format!("kurashi-motion-{}", std::process::id()));
        std::fs::create_dir_all(&dir).unwrap();
        std::fs::write(
            dir.join("calm.toml"),
            "base = \"calm\"\n[form]\nopen = \"zoom\"\n",
        )
        .unwrap();
        std::fs::write(dir.join("mine.toml"), "[timing]\nopen = \"snap\"\n").unwrap();
        std::fs::write(dir.join("broken.toml"), "[timing\n").unwrap();
        let r = Registry::load(std::slice::from_ref(&dir));
        std::fs::remove_dir_all(&dir).unwrap();
        let calm = r.find("calm").unwrap();
        assert!(!calm.bundled);
        assert_eq!(calm.forms.as_ref().unwrap().open.as_deref(), Some("zoom"));
        assert!(r.find("mine").is_some());
        assert!(r.find("broken").is_none());
        assert!(
            r.diags
                .iter()
                .any(|d| d.pack == "broken" && d.key == DIAG_BROKEN)
        );
        assert_eq!(
            r.packs.len(),
            Registry::bundled().packs.len() + 1,
            "calm replaced in place"
        );
    }

    #[test]
    fn availability_follows_the_default_forms() {
        let r = Registry::bundled();
        for id in [
            "expressive",
            "calm",
            "washi",
            "fluent",
            "snes",
            "reduced",
            "pudding",
            "origami",
            "phosphor",
            "sumi",
            "genie",
            // W59.8b: their forms have landed (glitch = glitch/dissolve, ember = fade/dissolve).
            "glitch",
            "ember",
            // W59.3: their forms have landed (pop = stamp, outline = outline).
            "pop",
            "outline",
            // W59.9a: liquid has landed.
            "liquid",
        ] {
            assert!(r.find(id).unwrap().available(), "{id}");
        }
    }
}
