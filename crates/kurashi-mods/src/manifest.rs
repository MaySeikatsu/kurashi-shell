//! `mod.toml` parsing and validation. Errors carry a stable code (`mods.error.<code>`, i18n key)
//! and the offending field path so Settings can say exactly why a mod is inert (Shōjiki).

use kurashi_schema::{FieldType, RecordField, RecordProblem, RecordSpec, check_record_field};
use semver::{Version, VersionReq};
use serde::{Deserialize, Serialize};
use serde_json::{Map, Value as Json};
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

/// Capabilities are declared and shown in Settings; unknown ones are an error, not ignored. A
/// program a mod runs is declared as `exec:<binary>` (its name, not a path; see [`capability_known`]).
/// `fs:read` reads system files for the figures, `proc:signal` signals a process of the user (I28).
pub const KNOWN_CAPABILITIES: &[&str] = &[
    "dbus:session",
    "dbus:system",
    "network",
    "audio",
    "notifications",
    "fs:scoped",
    "fs:read",
    "proc:signal",
    "exec",
    "secrets",
];

/// Whether `c` is a capability this daemon knows: one of [`KNOWN_CAPABILITIES`], or `exec:<binary>`
/// for a program named by its file name (`exec:awww`). The bare `exec` predates the named form.
pub fn capability_known(c: &str) -> bool {
    if KNOWN_CAPABILITIES.contains(&c) {
        return true;
    }
    c.strip_prefix("exec:").is_some_and(|binary| {
        !binary.is_empty()
            && binary
                .chars()
                .all(|ch| ch.is_ascii_lowercase() || ch.is_ascii_digit() || "-_.".contains(ch))
    })
}

/// The contribution slots of the core views (K28, `docs/ux/COMPOSITION.md` §3). A mod's
/// `slot:<name>` must name one of these; the core never names a mod, so the list is the contract.
pub const SLOTS: &[&str] = &[
    "clock.expanded.aside",
    "clock.expanded.day",
    // One mark per date in the clock view's month grid (row 71, I46): instantiated per visible day cell.
    "clock.expanded.daymark",
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
    /// A hover/focus peek the Stage shows under the mod's widget (K35): `qml/Peek.qml`.
    Peek(String),
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
    /// A background job (I23, `ModCtx::background`): a poll or watch the daemon runs while it is wanted.
    Job(String),
    /// A process of the mod's own that the daemon starts and stops (K38, `ModCtx::host`): it connects back
    /// with a scoped hello and sees only the mod's documents and actions.
    Host(String),
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
            "peek" => Self::Peek(id),
            "service" => Self::Service(id),
            "action" => Self::Action(id),
            "palette" => Self::Palette(id),
            "decor" => Self::Decor(id),
            "launcher" => Self::Launcher(id),
            "slot" => Self::Slot(id),
            "choices" => Self::Choices(id),
            "job" => Self::Job(id),
            "host" => Self::Host(id),
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
            // Several mods fill one slot; that is what slots are for (K28). Job names belong to their mod.
            (Self::Slot(_), Self::Slot(_))
            | (Self::Job(_), Self::Job(_))
            | (Self::Host(_), Self::Host(_)) => false,
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
            Self::Peek(i) => write!(f, "peek:{i}"),
            Self::Service(i) => write!(f, "service:{i}"),
            Self::Action(i) => write!(f, "action:{i}"),
            Self::Palette(i) => write!(f, "palette:{i}"),
            Self::Decor(i) => write!(f, "decor:{i}"),
            Self::Launcher(i) => write!(f, "launcher:{i}"),
            Self::Slot(i) => write!(f, "slot:{i}"),
            Self::Choices(i) => write!(f, "choices:{i}"),
            Self::Job(i) => write!(f, "job:{i}"),
            Self::Host(i) => write!(f, "host:{i}"),
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
    /// A `list` setting: members of its `choices`, in the order the user picked them (I26).
    List(Vec<String>),
    /// A `records` setting: rows of the declared fields, every field present (K38, MODS.md "Records").
    Records(Vec<Map<String, Json>>),
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
    /// An ordered subset of fixed `choices` (I26, CONTRACT 41): the Settings page shows a pick list.
    List,
    /// A list of tables whose fields the manifest declares (K38, CONTRACT 89): the records editor.
    Records,
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
    /// The fields of each `records` setting (K38), by the setting's key. They sit beside the settings, not in
    /// them: `Setting` is inline in `registry::Contribution`, and clippy's large_enum_variant limits its size.
    #[serde(skip_serializing_if = "Vec::is_empty")]
    pub records: Vec<(String, RecordSpec)>,
}

impl Manifest {
    /// Config key for one of this mod's settings: `mods.<id>.<key>` (K22).
    pub fn config_key(&self, key: &str) -> String {
        format!("mods.{}.{key}", self.id)
    }

    /// The fields of the `records` setting `key` of this mod (K38), if it is one.
    pub fn record_spec(&self, key: &str) -> Option<&RecordSpec> {
        self.records
            .iter()
            .find(|(k, _)| k == key)
            .map(|(_, spec)| spec)
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
    /// `[[setting.field]]` of a `records` setting (K38).
    #[serde(default, rename = "field")]
    fields: Vec<RawField>,
    unique: Option<String>,
    item_label: Option<String>,
}

/// One `[[setting.field]]` (MODS.md "Records").
#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
struct RawField {
    key: String,
    #[serde(rename = "type")]
    ty: String,
    #[serde(default)]
    required: bool,
    default: Option<toml::Value>,
    label: Option<String>,
    pattern: Option<String>,
    #[serde(default)]
    schemes: Vec<String>,
    #[serde(default)]
    choices: Vec<String>,
    range: Option<Vec<toml::Value>>,
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

fn fail(
    errs: &mut Vec<ValidationError>,
    code: &'static str,
    path: String,
    detail: impl Into<String>,
) {
    errs.push(ValidationError::new(code, path, detail));
}

/// The scheme of a url field: a lowercase letter, then lowercase letters, digits, `+`, `.` or `-`.
fn scheme_ok(s: &str) -> bool {
    s.bytes().next().is_some_and(|c| c.is_ascii_lowercase())
        && s.bytes()
            .all(|b| b.is_ascii_lowercase() || b.is_ascii_digit() || b"+.-".contains(&b))
}

/// `[[setting.field]]`, `unique` and `item_label` are options of a `records` setting only.
fn records_options_on_other_type(i: usize, s: &RawSetting, errs: &mut Vec<ValidationError>) {
    let at = |f: &str| format!("setting[{i}].{f}");
    if !s.fields.is_empty() {
        fail(errs, "setting_fields_not_records", at("field"), &s.ty);
    }
    for (name, given) in [
        ("unique", s.unique.is_some()),
        ("item_label", s.item_label.is_some()),
    ] {
        if given {
            fail(errs, "setting_option_not_records", at(name), &s.ty);
        }
    }
}

/// One `[[setting.field]]` (K38, MODS.md "Records"): its declaration is checked the way a setting's
/// is, and its default as a value of the field. `None` when the field cannot be used.
fn record_field(
    i: usize,
    j: usize,
    f: &RawField,
    seen: &mut Vec<String>,
    errs: &mut Vec<ValidationError>,
) -> Option<RecordField> {
    let at = |x: &str| format!("setting[{i}].field[{j}].{x}");
    let before = errs.len();
    if !key_ok(&f.key) {
        fail(errs, "setting_field_key_invalid", at("key"), &f.key);
    } else if seen.contains(&f.key) {
        fail(errs, "setting_field_key_duplicate", at("key"), &f.key);
    }
    seen.push(f.key.clone());
    let ty = match f.ty.as_str() {
        "string" => FieldType::String,
        "url" => FieldType::Url,
        "enum" => FieldType::Enum,
        "bool" => FieldType::Bool,
        "int" => FieldType::Int,
        t => {
            fail(errs, "setting_field_type_invalid", at("type"), t);
            return None;
        }
    };
    // Each option belongs to one type; naming it on another is a mistake, not a no-op.
    for (name, given, takes) in [
        ("pattern", f.pattern.is_some(), ty == FieldType::String),
        ("schemes", !f.schemes.is_empty(), ty == FieldType::Url),
        ("choices", !f.choices.is_empty(), ty == FieldType::Enum),
        ("range", f.range.is_some(), ty == FieldType::Int),
    ] {
        if given && !takes {
            fail(
                errs,
                "setting_field_option_not_for_type",
                at(name),
                f.ty.as_str(),
            );
        }
    }
    let pattern = match f.pattern.as_deref() {
        None => None,
        Some("slug") => Some("slug".to_string()),
        Some(p) => {
            fail(errs, "setting_field_pattern_invalid", at("pattern"), p);
            None
        }
    };
    let schemes = if ty == FieldType::Url {
        if f.schemes.is_empty() {
            fail(errs, "setting_field_schemes_missing", at("schemes"), "");
        }
        for s in f.schemes.iter().filter(|s| !scheme_ok(s.as_str())) {
            fail(
                errs,
                "setting_field_scheme_invalid",
                at("schemes"),
                s.as_str(),
            );
        }
        f.schemes.clone()
    } else {
        Vec::new()
    };
    let choices = if ty == FieldType::Enum {
        if f.choices.is_empty() {
            fail(errs, "setting_field_choices_missing", at("choices"), "");
        }
        let mut seen_choice: Vec<&String> = Vec::new();
        for c in &f.choices {
            if seen_choice.contains(&c) {
                fail(
                    errs,
                    "setting_field_choices_duplicate",
                    at("choices"),
                    c.as_str(),
                );
            }
            seen_choice.push(c);
        }
        f.choices.clone()
    } else {
        Vec::new()
    };
    let range = match f.range.as_deref() {
        None => None,
        Some(_) if ty != FieldType::Int => None,
        Some([toml::Value::Integer(lo), toml::Value::Integer(hi)]) if lo <= hi => Some((*lo, *hi)),
        Some(_) => {
            fail(
                errs,
                "setting_field_range_invalid",
                at("range"),
                "expected [min, max] whole numbers with min <= max",
            );
            None
        }
    };
    let mut field = RecordField {
        key: f.key.clone(),
        ty,
        required: f.required,
        default: None,
        label: f.label.clone(),
        pattern,
        schemes,
        choices,
        range,
    };
    // Required unless the field is required: what a row without the field takes.
    match &f.default {
        None if !f.required => fail(errs, "setting_field_default_missing", at("default"), ""),
        None => {}
        Some(d) => match serde_json::to_value(d) {
            Ok(v) => match check_record_field(&field, &v) {
                None => field.default = Some(v),
                Some(RecordProblem::WrongType { .. }) => {
                    fail(
                        errs,
                        "setting_field_default_type",
                        at("default"),
                        d.to_string(),
                    );
                }
                Some(p) => fail(
                    errs,
                    "setting_field_default_invalid",
                    at("default"),
                    p.to_string(),
                ),
            },
            Err(_) => fail(
                errs,
                "setting_field_default_type",
                at("default"),
                d.to_string(),
            ),
        },
    }
    (errs.len() == before).then_some(field)
}

/// A `records` setting (K38): its fields, `unique` and `item_label`, and its default's rows checked
/// against the fields and normalised (every field present). `None` when a problem was reported.
fn records_setting(
    i: usize,
    s: &RawSetting,
    errs: &mut Vec<ValidationError>,
) -> Option<(RecordSpec, Vec<Map<String, Json>>)> {
    let at = |x: &str| format!("setting[{i}].{x}");
    let before = errs.len();
    let mut seen = Vec::new();
    let mut fields = Vec::new();
    for (j, f) in s.fields.iter().enumerate() {
        fields.extend(record_field(i, j, f, &mut seen, errs));
    }
    if s.fields.is_empty() {
        fail(errs, "setting_fields_missing", at("field"), "");
    }
    let unique = match &s.unique {
        None => None,
        Some(u) if s.fields.iter().any(|f| &f.key == u) => Some(u.clone()),
        Some(u) => {
            fail(
                errs,
                "setting_unique_unknown_field",
                at("unique"),
                u.as_str(),
            );
            None
        }
    };
    let item_label = match &s.item_label {
        None => None,
        Some(l) if s.fields.iter().any(|f| &f.key == l) => Some(l.clone()),
        Some(l) => {
            fail(
                errs,
                "setting_item_label_unknown_field",
                at("item_label"),
                l.as_str(),
            );
            None
        }
    };
    if errs.len() != before {
        // The declaration is wrong; checking the default against it would only repeat the trouble.
        return None;
    }
    let spec = RecordSpec {
        fields,
        unique,
        item_label,
    };
    let items = match &s.default {
        toml::Value::Array(items) => items,
        other => {
            fail(
                errs,
                "setting_default_type",
                at("default"),
                format!("{other} is not a list of records"),
            );
            return None;
        }
    };
    let json = Json::Array(
        items
            .iter()
            .map(|v| serde_json::to_value(v).unwrap_or(Json::Null))
            .collect(),
    );
    match spec.check(&at("default"), &json) {
        Ok(rows) => {
            let rows = rows
                .as_array()
                .map(|a| a.iter().filter_map(|r| r.as_object().cloned()).collect())
                .unwrap_or_default();
            Some((spec, rows))
        }
        Err(found) => {
            for e in found {
                match e {
                    kurashi_schema::ValidationError::Record { key, problem } => {
                        let code = match problem {
                            RecordProblem::NotARecord | RecordProblem::WrongType { .. } => {
                                "setting_default_type"
                            }
                            RecordProblem::UnknownField => "setting_default_field_unknown",
                            RecordProblem::MissingField => "setting_default_field_missing",
                            RecordProblem::Duplicate => "setting_default_duplicate",
                            _ => "setting_default_field_invalid",
                        };
                        fail(errs, code, key, problem.to_string());
                    }
                    other => fail(
                        errs,
                        "setting_default_type",
                        at("default"),
                        other.to_string(),
                    ),
                }
            }
            None
        }
    }
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
        if !capability_known(c) {
            err("capability_unknown", &format!("capabilities[{i}]"), c);
        }
    }

    let mut settings = Vec::new();
    let mut record_specs: Vec<(String, RecordSpec)> = Vec::new();
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
            "list" => SettingType::List,
            "records" => SettingType::Records,
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
        let fixed = matches!(ty, SettingType::Enum | SettingType::List);
        if fixed && s.choices.is_empty() {
            err("setting_choices_missing", &at("choices"), "");
        } else if !fixed && !s.choices.is_empty() {
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
        // Records (K38): the fields, `unique`, `item_label` and the default's rows; the other types
        // take none of those options.
        let mut rec_errs = Vec::new();
        let records = if ty == SettingType::Records {
            records_setting(i, s, &mut rec_errs)
        } else {
            records_options_on_other_type(i, s, &mut rec_errs);
            None
        };
        for e in &rec_errs {
            err(e.code, &e.path, &e.detail);
        }
        let default = match (ty, &s.default) {
            (SettingType::Records, _) => records
                .as_ref()
                .map(|(_, rows)| SettingValue::Records(rows.clone())),
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
            // Members of the choices, each once, in the order the default lists them.
            (SettingType::List, toml::Value::Array(items)) => {
                let mut members = Vec::new();
                let mut valid = true;
                for item in items {
                    match item {
                        toml::Value::String(t) if !s.choices.contains(t) => {
                            err("setting_default_not_in_choices", &at("default"), t);
                            valid = false;
                        }
                        toml::Value::String(t) if members.contains(t) => {
                            err("setting_default_duplicate", &at("default"), t);
                            valid = false;
                        }
                        toml::Value::String(t) => members.push(t.clone()),
                        other => {
                            err(
                                "setting_default_type",
                                &at("default"),
                                &format!("{other} is not a string"),
                            );
                            valid = false;
                        }
                    }
                }
                valid.then_some(SettingValue::List(members))
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
            if let Some((spec, _)) = records {
                record_specs.push((s.key.clone(), spec));
            }
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
            records: record_specs,
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

    #[test]
    fn capabilities_name_what_a_mod_reads_signals_or_runs() {
        for c in [
            "fs:read",
            "proc:signal",
            "network",
            "exec",
            "exec:awww",
            "exec:xdg-open",
        ] {
            assert!(capability_known(c), "{c} is known");
        }
        for c in [
            "exec:",
            "exec:/usr/bin/awww",
            "exec:Awww",
            "exec:a b",
            "fs:write",
            "teleport",
        ] {
            assert!(!capability_known(c), "{c} is not");
        }
        let t = "id = \"demo\"\nname = \"Demo\"\nversion = \"0.1.0\"\ntier = \"native\"\n\
                 kurashi = \">=0.0.1\"\ncapabilities = [\"fs:read\", \"exec:/bin/sh\"]\n";
        assert_eq!(codes(t), ["capability_unknown"]);
    }

    #[test]
    fn a_list_setting_takes_fixed_choices_and_a_default_of_members() {
        let ok = text(
            "",
            "[[setting]]\nkey = \"show\"\ntype = \"list\"\ndefault = [\"mem\", \"cpu\"]\n\
             choices = [\"cpu\", \"mem\", \"temp\"]\n",
        );
        let m = parse("demo", &ok, &Version::new(0, 1, 0)).unwrap();
        assert_eq!(m.settings[0].ty, SettingType::List);
        assert_eq!(
            m.settings[0].default,
            SettingValue::List(vec!["mem".into(), "cpu".into()])
        );
        assert_eq!(m.settings[0].choices, ["cpu", "mem", "temp"]);
        assert!(m.settings[0].choices_from.is_none());

        let list = |default: &str, extra: &str| {
            text(
                "",
                &format!(
                    "[[setting]]\nkey = \"show\"\ntype = \"list\"\ndefault = {default}\n{extra}\n"
                ),
            )
        };
        assert_eq!(
            codes(&list("[]", "")),
            ["setting_choices_missing"],
            "fixed choices are required"
        );
        assert_eq!(
            codes(&list("[\"gpu\"]", "choices = [\"cpu\"]")),
            ["setting_default_not_in_choices"]
        );
        assert_eq!(
            codes(&list("[\"cpu\", \"cpu\"]", "choices = [\"cpu\"]")),
            ["setting_default_duplicate"]
        );
        assert_eq!(
            codes(&list("[1]", "choices = [\"cpu\"]")),
            ["setting_default_type"]
        );
        assert_eq!(
            codes(&list("[]", "choices = [\"cpu\"]\nrange = [0, 1]")),
            ["setting_range_not_numeric"]
        );
        assert_eq!(
            codes(&list("[]", "choices_from = \"demo.pick\"")),
            ["setting_choices_missing", "setting_choices_from_type"]
        );
    }

    /// A `records` setting: `default` (TOML), its own keys (`unique = …`), and its `[[setting.field]]`s.
    fn records_text(default: &str, keys: &str, fields: &str) -> String {
        text(
            "",
            &format!(
                "[[setting]]\nkey = \"pins\"\ntype = \"records\"\ndefault = {default}\n{keys}\n{fields}"
            ),
        )
    }

    /// `[[setting.field]]` tables, each required so that one mistake is one problem.
    fn field(key: &str, ty: &str, extra: &str) -> String {
        format!(
            "  [[setting.field]]\n  key = \"{key}\"\n  type = \"{ty}\"\n  required = true\n{extra}\n"
        )
    }

    fn problems(t: &str) -> Vec<(&'static str, String)> {
        match parse("demo", t, &Version::new(0, 1, 0)) {
            Ok(_) => vec![],
            Err(errs) => errs.into_iter().map(|e| (e.code, e.path)).collect(),
        }
    }

    #[test]
    fn records_take_declared_fields_and_refuse_each_mistake_by_code() {
        let id = field("id", "string", "  pattern = \"slug\"");
        let target = field("target", "url", "  schemes = [\"https\", \"mod\"]");
        let both = format!("{id}{target}");

        // The shape of the web dock's pins: fields, `unique`, `item_label`, a default of rows.
        let ok = records_text(
            "[{id = \"a\", target = \"https://x\"}]",
            "unique = \"id\"\nitem_label = \"target\"",
            &format!(
                "{both}  [[setting.field]]\n  key = \"view\"\n  type = \"enum\"\n  \
                 choices = [\"default\", \"mobile\"]\n  default = \"default\"\n"
            ),
        );
        let m = parse("demo", &ok, &Version::new(0, 1, 0)).unwrap();
        let spec = m.record_spec("pins").unwrap();
        assert_eq!(spec.fields.len(), 3);
        assert_eq!(spec.unique.as_deref(), Some("id"));
        assert_eq!(spec.label_field().unwrap().key, "target");
        // The default's row is normalised: the absent optional field takes its default.
        let SettingValue::Records(rows) = &m.settings[0].default else {
            panic!("a records default")
        };
        assert_eq!(rows[0]["view"], "default");
        assert!(problems(&records_text("[]", "", &both)).is_empty());

        // Each refusal names one code, and the path that says where.
        let refused: Vec<(String, &str)> = vec![
            (records_text("[]", "", ""), "setting_fields_missing"),
            (
                records_text("[]", "unique = \"nope\"", &both),
                "setting_unique_unknown_field",
            ),
            (
                records_text("[]", "item_label = \"nope\"", &both),
                "setting_item_label_unknown_field",
            ),
            (records_text("\"x\"", "", &both), "setting_default_type"),
            (records_text("[1]", "", &both), "setting_default_type"),
            (
                records_text(
                    "[{id = \"a\", target = \"https://x\", extra = 1}]",
                    "",
                    &both,
                ),
                "setting_default_field_unknown",
            ),
            (
                records_text("[{id = \"a\"}]", "", &both),
                "setting_default_field_missing",
            ),
            (
                records_text("[{id = \"Bad Id\", target = \"https://x\"}]", "", &both),
                "setting_default_field_invalid",
            ),
            (
                records_text(
                    "[{id = \"a\", target = \"https://x\"}, {id = \"a\", target = \"https://y\"}]",
                    "unique = \"id\"",
                    &both,
                ),
                "setting_default_duplicate",
            ),
            (
                records_text("[]", "", &field("Bad Key", "string", "")),
                "setting_field_key_invalid",
            ),
            (
                records_text("[]", "", &format!("{id}{}", field("id", "string", ""))),
                "setting_field_key_duplicate",
            ),
            (
                records_text("[]", "", &field("when", "date", "")),
                "setting_field_type_invalid",
            ),
            (
                records_text("[]", "", &field("n", "int", "  pattern = \"slug\"")),
                "setting_field_option_not_for_type",
            ),
            (
                records_text("[]", "", &field("s", "string", "  schemes = [\"https\"]")),
                "setting_field_option_not_for_type",
            ),
            (
                records_text("[]", "", &field("b", "bool", "  choices = [\"a\"]")),
                "setting_field_option_not_for_type",
            ),
            (
                records_text("[]", "", &field("s", "string", "  range = [1, 2]")),
                "setting_field_option_not_for_type",
            ),
            (
                records_text("[]", "", &field("s", "string", "  pattern = \"email\"")),
                "setting_field_pattern_invalid",
            ),
            (
                records_text("[]", "", &field("u", "url", "")),
                "setting_field_schemes_missing",
            ),
            (
                records_text("[]", "", &field("u", "url", "  schemes = [\"HTTPS\"]")),
                "setting_field_scheme_invalid",
            ),
            (
                records_text("[]", "", &field("e", "enum", "")),
                "setting_field_choices_missing",
            ),
            (
                records_text("[]", "", &field("e", "enum", "  choices = [\"a\", \"a\"]")),
                "setting_field_choices_duplicate",
            ),
            (
                records_text("[]", "", &field("n", "int", "  range = [5, 1]")),
                "setting_field_range_invalid",
            ),
            (
                records_text(
                    "[]",
                    "",
                    "  [[setting.field]]\n  key = \"n\"\n  type = \"int\"\n",
                ),
                "setting_field_default_missing",
            ),
            (
                records_text("[]", "", &field("on", "bool", "  default = \"yes\"")),
                "setting_field_default_type",
            ),
            (
                records_text(
                    "[]",
                    "",
                    &field("e", "enum", "  choices = [\"a\"]\n  default = \"nope\""),
                ),
                "setting_field_default_invalid",
            ),
        ];
        for (t, code) in &refused {
            assert_eq!(
                problems(t).iter().map(|p| p.0).collect::<Vec<_>>(),
                [*code],
                "for:\n{t}"
            );
        }
        // Paths name the field and the option: `setting[0].field[1].schemes`.
        let at = records_text("[]", "", &format!("{id}{}", field("u", "url", "")));
        assert_eq!(
            problems(&at),
            [(
                "setting_field_schemes_missing",
                "setting[0].field[1].schemes".to_string()
            )]
        );
        let row = records_text("[{id = \"a\"}]", "", &both);
        assert_eq!(
            problems(&row),
            [(
                "setting_default_field_missing",
                "setting[0].default[0].target".to_string()
            )]
        );
        // Options that only a records setting takes, on the other types.
        let on_bool = text(
            "",
            "[[setting]]\nkey = \"on\"\ntype = \"bool\"\ndefault = true\nunique = \"id\"\n\
             [[setting.field]]\n  key = \"id\"\n  type = \"string\"\n  required = true\n",
        );
        assert_eq!(
            problems(&on_bool).iter().map(|p| p.0).collect::<Vec<_>>(),
            ["setting_fields_not_records", "setting_option_not_records"]
        );
    }
}
