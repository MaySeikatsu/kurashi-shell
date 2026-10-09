//! `mod.toml` parsing and validation. Errors carry a stable code (`mods.error.<code>`, i18n key)
//! and the offending field path so Settings can say exactly why a mod is inert (Shōjiki).

use semver::{Version, VersionReq};
use serde::{Deserialize, Serialize};
use std::fmt;

#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
pub struct ValidationError {
    /// Stable machine code; the i18n key is `mods.error.<code>`.
    pub code: &'static str,
    /// Field path, e.g. `setting[1].default`.
    pub path: String,
    /// Offending value or extra context (not user-facing prose).
    pub detail: String,
}

impl ValidationError {
    pub(crate) fn new(
        code: &'static str,
        path: impl Into<String>,
        detail: impl Into<String>,
    ) -> Self {
        Self {
            code,
            path: path.into(),
            detail: detail.into(),
        }
    }
    pub fn i18n_key(&self) -> String {
        format!("mods.error.{}", self.code)
    }
}

impl fmt::Display for ValidationError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "{} at {}: {}", self.i18n_key(), self.path, self.detail)
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize)]
#[serde(rename_all = "lowercase")]
pub enum Tier {
    Native,
    Portable,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize)]
#[serde(rename_all = "lowercase")]
pub enum Cost {
    Low,
    Medium,
    High,
}

/// Capabilities are declared and shown in Settings; unknown ones are an error, not ignored.
pub const KNOWN_CAPABILITIES: &[&str] = &[
    "dbus:session",
    "dbus:system",
    "network",
    "audio",
    "notifications",
    "fs:scoped",
    "exec",
    "secrets",
];

/// The contribution slots of the core views (K28, `docs/ux/COMPOSITION.md` §3). A mod's
/// `slot:<name>` must name one of these; the core never names a mod, so the list is the contract.
pub const SLOTS: &[&str] = &[
    "clock.expanded.aside",
    "clock.expanded.day",
    "clock.expanded.footer",
    "media.expanded.below",
    "media.expanded.backdrop",
    "notifications.expanded.header",
    "quick.tiles",
    "lock.aside",
];

#[derive(Debug, Clone, PartialEq, Eq, PartialOrd, Ord, Hash, Serialize)]
#[serde(tag = "kind", content = "id", rename_all = "kebab-case")]
pub enum Provide {
    Widget(String),
    IslandFace(String),
    Panel(String),
    Service(String),
    /// Exact action id or a glob ending in `.*`.
    Action(String),
    Palette(String),
    Decor(String),
    Launcher(String),
    /// Fills a core view's slot (K28); the name is one of [`SLOTS`].
    Slot(String),
    /// A choice source a setting names with `choices_from` (K28 (3), I9).
    Choices(String),
    I18n,
}

impl Provide {
    fn parse(s: &str) -> Result<Self, &'static str> {
        if s == "i18n" {
            return Ok(Self::I18n);
        }
        let (kind, id) = s.split_once(':').ok_or("provide_malformed")?;
        let ok_char = |c: char| c.is_ascii_lowercase() || c.is_ascii_digit() || "-_.".contains(c);
        let valid = if kind == "action" {
            let body = id.strip_suffix(".*").unwrap_or(id);
            !body.is_empty() && body.chars().all(ok_char)
        } else {
            !id.is_empty() && id.chars().all(ok_char)
        };
        if !valid {
            return Err("provide_malformed");
        }
        if kind == "slot" && !SLOTS.contains(&id) {
            return Err("provide_unknown_slot");
        }
        let id = id.to_string();
        Ok(match kind {
            "widget" => Self::Widget(id),
            "island-face" => Self::IslandFace(id),
            "panel" => Self::Panel(id),
            "service" => Self::Service(id),
            "action" => Self::Action(id),
            "palette" => Self::Palette(id),
            "decor" => Self::Decor(id),
            "launcher" => Self::Launcher(id),
            "slot" => Self::Slot(id),
            "choices" => Self::Choices(id),
            _ => return Err("provide_unknown_kind"),
        })
    }

    /// True when two provides claim the same slot (action globs overlap by prefix).
    pub fn conflicts_with(&self, other: &Self) -> bool {
        match (self, other) {
            (Self::Action(a), Self::Action(b)) => {
                let (pa, pb) = (a.strip_suffix(".*"), b.strip_suffix(".*"));
                let under = |glob: &str, x: &str| x == glob || x.starts_with(&format!("{glob}."));
                match (pa, pb) {
                    (Some(ga), Some(gb)) => under(ga, gb) || under(gb, ga),
                    (Some(g), None) => under(g, b),
                    (None, Some(g)) => under(g, a),
                    (None, None) => a == b,
                }
            }
            // Several mods fill one slot; that is what slots are for (K28).
            (Self::Slot(_), Self::Slot(_)) => false,
            _ => self == other,
        }
    }
}

impl fmt::Display for Provide {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::Widget(i) => write!(f, "widget:{i}"),
            Self::IslandFace(i) => write!(f, "island-face:{i}"),
            Self::Panel(i) => write!(f, "panel:{i}"),
            Self::Service(i) => write!(f, "service:{i}"),
            Self::Action(i) => write!(f, "action:{i}"),
            Self::Palette(i) => write!(f, "palette:{i}"),
            Self::Decor(i) => write!(f, "decor:{i}"),
            Self::Launcher(i) => write!(f, "launcher:{i}"),
            Self::Slot(i) => write!(f, "slot:{i}"),
            Self::Choices(i) => write!(f, "choices:{i}"),
            Self::I18n => write!(f, "i18n"),
        }
    }
}

#[derive(Debug, Clone, PartialEq, Serialize)]
#[serde(untagged)]
pub enum SettingValue {
    Bool(bool),
    Int(i64),
    Float(f64),
    Str(String),
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize)]
#[serde(rename_all = "lowercase")]
pub enum SettingType {
    Bool,
    Int,
    Float,
    String,
    Enum,
    Color,
}

#[derive(Debug, Clone, PartialEq, Serialize)]
pub struct Setting {
    pub key: String,
    #[serde(rename = "type")]
    pub ty: SettingType,
    pub default: SettingValue,
    pub range: Option<(f64, f64)>,
    pub choices: Vec<String>,
    /// A choice source (I9, MODS.md wallpaper): the options are what the source offers now, and a
    /// value it does not offer is inert (`settings.choice.unavailable`), never rejected.
    pub choices_from: Option<String>,
    pub unit: Option<String>,
    pub label: Option<String>,
    pub help: Option<String>,
}

#[derive(Debug, Clone, PartialEq, Serialize)]
pub struct Manifest {
    pub id: String,
    pub name: String,
    /// i18n key or plain text, shown under the name on the Mods page. Absent when not declared.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub description: Option<String>,
    pub version: Version,
    pub tier: Tier,
    pub kurashi: VersionReq,
    pub provides: Vec<Provide>,
    pub capabilities: Vec<String>,
    pub cost: Cost,
    pub settings: Vec<Setting>,
}

impl Manifest {
    /// Config key for one of this mod's settings: `mods.<id>.<key>` (K22).
    pub fn config_key(&self, key: &str) -> String {
        format!("mods.{}.{key}", self.id)
    }
}

#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
struct Raw {
    id: String,
    name: String,
    description: Option<String>,
    version: String,
    tier: String,
    kurashi: String,
    #[serde(default)]
    provides: Vec<String>,
    #[serde(default)]
    capabilities: Vec<String>,
    #[serde(default = "default_cost")]
    cost: String,
    #[serde(default, rename = "setting")]
    settings: Vec<RawSetting>,
}

fn default_cost() -> String {
    "low".into()
}

#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
struct RawSetting {
    key: String,
    #[serde(rename = "type")]
    ty: String,
    default: toml::Value,
    range: Option<Vec<toml::Value>>,
    #[serde(default)]
    choices: Vec<String>,
    choices_from: Option<String>,
    unit: Option<String>,
    label: Option<String>,
    help: Option<String>,
}

/// Ids a mod may not take: `mods.loaded` and `mods.enabled` are config keys (K25), and a mod
/// with one of these ids would need a `[mods.<id>]` table next to them.
pub const RESERVED_IDS: &[&str] = &["loaded", "enabled"];

fn ident_ok(s: &str) -> bool {
    s.chars().next().is_some_and(|c| c.is_ascii_lowercase())
        && s.chars()
            .all(|c| c.is_ascii_lowercase() || c.is_ascii_digit() || c == '-')
}

fn key_ok(s: &str) -> bool {
    s.chars().next().is_some_and(|c| c.is_ascii_lowercase())
        && s.chars()
            .all(|c| c.is_ascii_lowercase() || c.is_ascii_digit() || c == '_')
}

fn num(v: &toml::Value) -> Option<f64> {
    match v {
        toml::Value::Integer(i) => Some(*i as f64),
        toml::Value::Float(f) => Some(*f),
        _ => None,
    }
}

/// A choice source name: the charset of provide ids (`hello.greetings`).
fn is_source_id(s: &str) -> bool {
    !s.is_empty()
        && s.chars()
            .all(|c| c.is_ascii_lowercase() || c.is_ascii_digit() || "-_.".contains(c))
}

fn is_color(s: &str) -> bool {
    s.strip_prefix('#')
        .is_some_and(|h| matches!(h.len(), 6 | 8) && h.chars().all(|c| c.is_ascii_hexdigit()))
}

/// Parse and validate `text`. `dir_name` is the mod's directory (id must match it);
/// `daemon` is checked against the manifest's `kurashi` requirement.
/// All problems are collected, not just the first.
pub fn parse(
    dir_name: &str,
    text: &str,
    daemon: &Version,
) -> Result<Manifest, Vec<ValidationError>> {
    let raw: Raw = toml::from_str(text).map_err(|e| {
        vec![ValidationError::new(
            "parse",
            "mod.toml",
            e.message().to_string(),
        )]
    })?;
    let mut errs: Vec<ValidationError> = Vec::new();
    let mut err = |c: &'static str, p: &str, d: &str| errs.push(ValidationError::new(c, p, d));

    if !ident_ok(&raw.id) {
        err("id_invalid", "id", &raw.id);
    } else if raw.id != dir_name {
        err(
            "id_dir_mismatch",
            "id",
            &format!("{} != {dir_name}", raw.id),
        );
    } else if RESERVED_IDS.contains(&raw.id.as_str()) {
        // `mods.<id>` is a config table; these ids are the mods lists' own keys (K25).
        err("id_reserved", "id", &raw.id);
    }
    if raw.name.trim().is_empty() {
        err("name_empty", "name", "");
    }
    let version = match Version::parse(&raw.version) {
        Ok(v) => Some(v),
        Err(e) => {
            err("version_invalid", "version", &e.to_string());
            None
        }
    };
    let tier = match raw.tier.as_str() {
        "native" => Some(Tier::Native),
        "portable" => Some(Tier::Portable),
        t => {
            err("tier_invalid", "tier", t);
            None
        }
    };
    let kurashi = match VersionReq::parse(&raw.kurashi) {
        Ok(r) => {
            if !r.matches(daemon) {
                err(
                    "kurashi_incompatible",
                    "kurashi",
                    &format!("{r} does not match daemon {daemon}"),
                );
            }
            Some(r)
        }
        Err(e) => {
            err("kurashi_invalid", "kurashi", &e.to_string());
            None
        }
    };
    let cost = match raw.cost.as_str() {
        "low" => Some(Cost::Low),
        "medium" => Some(Cost::Medium),
        "high" => Some(Cost::High),
        c => {
            err("cost_invalid", "cost", c);
            None
        }
    };

    let mut provides = Vec::new();
    for (i, p) in raw.provides.iter().enumerate() {
        match Provide::parse(p) {
            Ok(v) if provides.contains(&v) => {
                err("provide_duplicate", &format!("provides[{i}]"), p)
            }
            Ok(v) => provides.push(v),
            Err(c) => err(c, &format!("provides[{i}]"), p),
        }
    }
    for (i, c) in raw.capabilities.iter().enumerate() {
        if !KNOWN_CAPABILITIES.contains(&c.as_str()) {
            err("capability_unknown", &format!("capabilities[{i}]"), c);
        }
    }

    let mut settings = Vec::new();
    let mut seen = Vec::<&str>::new();
    for (i, s) in raw.settings.iter().enumerate() {
        let at = |f: &str| format!("setting[{i}].{f}");
        if !key_ok(&s.key) {
            err("setting_key_invalid", &at("key"), &s.key);
        } else if seen.contains(&s.key.as_str()) {
            err("setting_key_duplicate", &at("key"), &s.key);
        }
        seen.push(&s.key);
        let ty = match s.ty.as_str() {
            "bool" => SettingType::Bool,
            "int" => SettingType::Int,
            "float" => SettingType::Float,
            "string" => SettingType::String,
            "enum" => SettingType::Enum,
            "color" => SettingType::Color,
            t => {
                err("setting_type_invalid", &at("type"), t);
                continue;
            }
        };
        let numeric = matches!(ty, SettingType::Int | SettingType::Float);
        let range = match &s.range {
            None => None,
            Some(_) if !numeric => {
                err("setting_range_not_numeric", &at("range"), &s.ty);
                None
            }
            Some(r) => match r.as_slice() {
                [a, b] if num(a).is_some() && num(b).is_some() && num(a) <= num(b) => {
                    num(a).zip(num(b))
                }
                _ => {
                    err(
                        "setting_range_invalid",
                        &at("range"),
                        "expected [min, max] with min <= max",
                    );
                    None
                }
            },
        };
        if ty == SettingType::Enum && s.choices.is_empty() {
            err("setting_choices_missing", &at("choices"), "");
        } else if ty != SettingType::Enum && !s.choices.is_empty() {
            err("setting_choices_not_enum", &at("choices"), &s.ty);
        }
        let choices_from = s.choices_from.as_ref().and_then(|src| {
            if ty != SettingType::String {
                err("setting_choices_from_type", &at("choices_from"), &s.ty);
                None
            } else if !s.choices.is_empty() {
                err("setting_choices_and_from", &at("choices_from"), src);
                None
            } else if !is_source_id(src) {
                err("setting_choices_from_invalid", &at("choices_from"), src);
                None
            } else {
                Some(src.clone())
            }
        });
        let default = match (ty, &s.default) {
            (SettingType::Bool, toml::Value::Boolean(b)) => Some(SettingValue::Bool(*b)),
            (SettingType::Int, toml::Value::Integer(n)) => Some(SettingValue::Int(*n)),
            (SettingType::Float, v @ (toml::Value::Float(_) | toml::Value::Integer(_))) => {
                num(v).map(SettingValue::Float)
            }
            (SettingType::String, toml::Value::String(t)) => Some(SettingValue::Str(t.clone())),
            (SettingType::Enum, toml::Value::String(t)) => {
                if !s.choices.contains(t) {
                    err("setting_default_not_in_choices", &at("default"), t);
                }
                Some(SettingValue::Str(t.clone()))
            }
            (SettingType::Color, toml::Value::String(t)) => {
                if !is_color(t) {
                    err("setting_default_not_color", &at("default"), t);
                }
                Some(SettingValue::Str(t.clone()))
            }
            (_, v) => {
                err(
                    "setting_default_type",
                    &at("default"),
                    &format!("{v} is not {}", s.ty),
                );
                None
            }
        };
        if let (Some(d), Some((lo, hi))) = (&default, range) {
            let x = match d {
                SettingValue::Int(n) => *n as f64,
                SettingValue::Float(f) => *f,
                _ => lo,
            };
            if x < lo || x > hi {
                err(
                    "setting_default_out_of_range",
                    &at("default"),
                    &format!("{x} not in [{lo}, {hi}]"),
                );
            }
        }
        if let Some(default) = default {
            settings.push(Setting {
                key: s.key.clone(),
                ty,
                default,
                range,
                choices: s.choices.clone(),
                choices_from,
                unit: s.unit.clone(),
                label: s.label.clone(),
                help: s.help.clone(),
            });
        }
    }

    match (errs.is_empty(), version, tier, kurashi, cost) {
        (true, Some(version), Some(tier), Some(kurashi), Some(cost)) => Ok(Manifest {
            id: raw.id,
            name: raw.name,
            // A blank description is the same as none: the catalog only ever shows real text.
            description: raw.description.filter(|d| !d.trim().is_empty()),
            version,
            tier,
            kurashi,
            provides,
            capabilities: raw.capabilities,
            cost,
            settings,
        }),
        _ => Err(errs),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn text(provides: &str, setting: &str) -> String {
        format!(
            "id = \"demo\"\nname = \"Demo\"\nversion = \"0.1.0\"\ntier = \"native\"\n\
             kurashi = \">=0.0.1\"\nprovides = [{provides}]\n{setting}"
        )
    }

    fn codes(t: &str) -> Vec<&'static str> {
        match parse("demo", t, &Version::new(0, 1, 0)) {
            Ok(_) => vec![],
            Err(errs) => errs.iter().map(|e| e.code).collect(),
        }
    }

    #[test]
    fn slot_names_are_the_core_slots_only() {
        assert_eq!(
            Provide::parse("slot:clock.expanded.footer"),
            Ok(Provide::Slot("clock.expanded.footer".into()))
        );
        assert_eq!(
            Provide::parse("slot:clock.expanded.nope"),
            Err("provide_unknown_slot")
        );
        assert_eq!(Provide::parse("slot:"), Err("provide_malformed"));
        assert!(codes(&text(r#""slot:lock.aside""#, "")).is_empty());
        assert_eq!(
            codes(&text(r#""slot:island.face""#, "")),
            ["provide_unknown_slot"]
        );
    }

    #[test]
    fn several_mods_may_fill_one_slot_but_not_one_face_or_source() {
        let a = Provide::parse("slot:quick.tiles").unwrap();
        let b = Provide::parse("slot:quick.tiles").unwrap();
        assert!(!a.conflicts_with(&b));
        let f = Provide::parse("island-face:weather").unwrap();
        assert!(f.conflicts_with(&Provide::parse("island-face:weather").unwrap()));
        let c = Provide::parse("choices:weather.units").unwrap();
        assert!(c.conflicts_with(&Provide::parse("choices:weather.units").unwrap()));
    }

    #[test]
    fn choice_sources_are_provide_ids() {
        assert_eq!(
            Provide::parse("choices:hello.greetings"),
            Ok(Provide::Choices("hello.greetings".into()))
        );
        assert_eq!(Provide::parse("choices:Hello"), Err("provide_malformed"));
        assert_eq!(Provide::parse("choices:"), Err("provide_malformed"));
        assert_eq!(Provide::Choices("a.b".into()).to_string(), "choices:a.b");
        assert_eq!(
            Provide::Slot("lock.aside".into()).to_string(),
            "slot:lock.aside"
        );
    }

    #[test]
    fn a_string_setting_may_name_a_choice_source() {
        let t = text(
            r#""choices:demo.pick""#,
            "[[setting]]\nkey = \"pick\"\ntype = \"string\"\ndefault = \"a\"\n\
             choices_from = \"demo.pick\"\n",
        );
        let m = parse("demo", &t, &Version::new(0, 1, 0)).unwrap();
        assert_eq!(m.settings[0].choices_from.as_deref(), Some("demo.pick"));
        assert!(m.settings[0].choices.is_empty());
        // Only a string takes a source, and the name is checked like a provide id.
        let bool_t = text(
            "",
            "[[setting]]\nkey = \"on\"\ntype = \"bool\"\ndefault = true\nchoices_from = \"x.y\"\n",
        );
        assert_eq!(codes(&bool_t), ["setting_choices_from_type"]);
        let bad = text(
            "",
            "[[setting]]\nkey = \"pick\"\ntype = \"string\"\ndefault = \"a\"\n\
             choices_from = \"Demo Pick\"\n",
        );
        assert_eq!(codes(&bad), ["setting_choices_from_invalid"]);
    }
}
