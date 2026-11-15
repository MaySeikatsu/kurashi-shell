//! The manifest's integration contract (K154, MODS.md "Integration contract"): what a mod `uses` beyond its own
//! documents and actions, the `points` it opens, its declared actions with typed arguments, its menu rows and the
//! variants it skips. Parsed and validated with the manifest; `kurashi mod check` and the daemon read the result.

use std::collections::BTreeMap;

use serde::{Deserialize, Serialize};
use serde_json::{Value, json};

use crate::manifest::{Provide, ValidationError};
use crate::points;

/// What every mod may read and call without naming it (MODS.md "Integration contract").
pub const BASE_DOCS: &[&str] = &[
    "theme",
    "i18n",
    "mods",
    "config",
    "runtime.slots",
    "runtime.ui",
    "runtime.layout",
];
pub const BASE_ACTIONS: &[&str] = &["mod.panel.open", "settings.open", "ui.close", "ui.keep"];

#[derive(Debug, Clone, Copy, PartialEq, Eq, PartialOrd, Ord, Serialize)]
#[serde(rename_all = "lowercase")]
pub enum UseKind {
    Doc,
    Action,
    /// An intent: a config key or a service's level the mod writes (`intent:theme.colors.scheme`).
    Intent,
}

/// One `uses` entry: `doc:svc.media`, `action:terminal.run?`, `intent:theme.colors.scheme`.
#[derive(Debug, Clone, PartialEq, Eq, PartialOrd, Ord, Serialize)]
pub struct Use {
    pub kind: UseKind,
    pub id: String,
    /// `?`: the mod works without it.
    pub optional: bool,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize)]
#[serde(rename_all = "lowercase")]
pub enum ArgType {
    Bool,
    Int,
    Float,
    String,
    Enum,
    /// An output's connector name; absent = the focused output.
    Output,
}

#[derive(Debug, Clone, PartialEq, Serialize)]
pub struct ArgDecl {
    pub name: String,
    #[serde(rename = "type")]
    pub ty: ArgType,
    /// Filled in when the caller leaves the argument out.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub default: Option<Value>,
    /// May be left out without a default: the handler has its own meaning for absence (`timer.start` without a
    /// length starts the last one). An argument with neither is required.
    #[serde(skip_serializing_if = "std::ops::Not::not")]
    pub optional: bool,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub range: Option<(f64, f64)>,
    #[serde(skip_serializing_if = "Vec::is_empty")]
    pub choices: Vec<String>,
    /// A `>` command hands the rest of its line to this argument.
    #[serde(skip_serializing_if = "std::ops::Not::not")]
    pub rest: bool,
}

#[derive(Debug, Clone, PartialEq, Serialize)]
pub struct ActionDecl {
    pub id: String,
    /// i18n key.
    pub label: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub icon: Option<String>,
    /// The word(s) a `>` command answers to besides its label; absent = not a command.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub command: Option<String>,
    /// `None`: the arguments are not described (and not checked); `Some(vec![])`: it takes none.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub args: Option<Vec<ArgDecl>>,
}

impl ActionDecl {
    /// The display form the `actions` query has always carried: `{minutes?, output?}`; "" for none or not described.
    pub fn args_display(&self) -> String {
        match &self.args {
            Some(args) if !args.is_empty() => {
                let names: Vec<String> = args
                    .iter()
                    .map(|a| {
                        if !a.required() {
                            format!("{}?", a.name)
                        } else {
                            a.name.clone()
                        }
                    })
                    .collect();
                format!("{{{}}}", names.join(", "))
            }
            _ => String::new(),
        }
    }

    /// Checks `args` against the declaration and fills the defaults in. Unknown members pass through (a handler may
    /// take more than it declares, e.g. a host's report). `Err` names the argument: the daemon answers
    /// `error.args.invalid` with it.
    pub fn check(&self, args: &Value) -> Result<Value, String> {
        let Some(decl) = &self.args else {
            return Ok(args.clone());
        };
        let mut out = match args {
            Value::Object(o) => o.clone(),
            Value::Null => serde_json::Map::new(),
            _ => return Err("args".into()),
        };
        for a in decl {
            let Some(v) = out.get(&a.name) else {
                match &a.default {
                    Some(d) => {
                        out.insert(a.name.clone(), d.clone());
                    }
                    None if a.required() => return Err(a.name.clone()),
                    None => {}
                }
                continue;
            };
            let ok = match a.ty {
                ArgType::Bool => v.is_boolean(),
                ArgType::Int => v.as_i64().is_some() && in_range(v.as_f64(), a.range),
                ArgType::Float => v.is_number() && in_range(v.as_f64(), a.range),
                ArgType::String | ArgType::Output => v.is_string(),
                ArgType::Enum => v.as_str().is_some_and(|s| a.choices.iter().any(|c| c == s)),
            };
            if !ok {
                return Err(a.name.clone());
            }
        }
        Ok(Value::Object(out))
    }

    /// The arguments a `>` command runs with for the words after it: its `rest` argument typed as declared, or none.
    /// `None` when the words do not fit (the command is then not offered for them).
    pub fn command_args(&self, words: &str) -> Option<Value> {
        let w = words.trim();
        let Some(arg) = self.args.as_ref().and_then(|a| a.iter().find(|a| a.rest)) else {
            return w.is_empty().then(|| json!({}));
        };
        if w.is_empty() {
            return (!arg.required()).then(|| json!({}));
        }
        let v = self.rest_value(arg, w)?;
        Some(json!({ arg.name.clone(): v }))
    }

    fn rest_value(&self, arg: &ArgDecl, w: &str) -> Option<Value> {
        match arg.ty {
            ArgType::Int => w.parse::<i64>().ok().map(Value::from),
            ArgType::Float => w.parse::<f64>().ok().map(Value::from),
            ArgType::Enum => arg.choices.iter().any(|c| c == w).then(|| json!(w)),
            _ => Some(json!(w)),
        }
        .filter(|v| in_range(v.as_f64(), arg.range) || !v.is_number())
    }
}

impl ArgDecl {
    /// Whether a caller must give it: no default, not `optional`, and not an output (absent = the focused one).
    pub fn required(&self) -> bool {
        self.default.is_none() && !self.optional && self.ty != ArgType::Output
    }
}

fn in_range(v: Option<f64>, range: Option<(f64, f64)>) -> bool {
    match (v, range) {
        (Some(x), Some((lo, hi))) => (lo..=hi).contains(&x),
        _ => true,
    }
}

/// One `[[menu]]` row: an action in a menu of the shell (`at` names a menu point) or the mod's own (`module`).
#[derive(Debug, Clone, PartialEq, Serialize)]
pub struct MenuRow {
    pub at: String,
    pub action: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub args: Option<Value>,
    /// i18n key; the action's label otherwise.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub label: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub icon: Option<String>,
}

#[derive(Debug, Clone, Default, PartialEq, Serialize)]
pub struct Contract {
    #[serde(skip_serializing_if = "Vec::is_empty")]
    pub uses: Vec<Use>,
    /// Local names: another mod fills `open_in` of mod `sessions` with `slot:sessions:open_in`.
    #[serde(skip_serializing_if = "Vec::is_empty")]
    pub points: Vec<String>,
    #[serde(skip_serializing_if = "Vec::is_empty")]
    pub actions: Vec<ActionDecl>,
    #[serde(skip_serializing_if = "Vec::is_empty")]
    pub menus: Vec<MenuRow>,
    /// Variant key (a point's id) → why the mod has none.
    #[serde(skip_serializing_if = "BTreeMap::is_empty")]
    pub skips: BTreeMap<String, String>,
}

impl Contract {
    pub fn action(&self, id: &str) -> Option<&ActionDecl> {
        self.actions.iter().find(|a| a.id == id)
    }

    /// Whether mod `id` may read document `doc`: its own, the base set, or a declared use.
    pub fn may_read(&self, id: &str, doc: &str) -> bool {
        own_doc(id, doc)
            || BASE_DOCS.contains(&doc)
            || self
                .uses
                .iter()
                .any(|u| u.kind == UseKind::Doc && (u.id == doc || covers(&u.id, doc)))
    }

    /// Whether mod `id` may call `action`: its own, the base set, or a declared use.
    pub fn may_call(&self, id: &str, action: &str) -> bool {
        own_action(id, action)
            || BASE_ACTIONS.contains(&action)
            || self
                .uses
                .iter()
                .any(|u| u.kind == UseKind::Action && (u.id == action || covers(&u.id, action)))
    }
}

impl Contract {
    /// Whether mod `id` may send the intent `key`: one of its own settings, or a declared use.
    pub fn may_send(&self, id: &str, key: &str) -> bool {
        own_intent(id, key)
            || self
                .uses
                .iter()
                .any(|u| u.kind == UseKind::Intent && (u.id == key || covers(&u.id, key)))
    }
}

/// `mods.<id>.*`: the mod's own settings.
pub fn own_intent(id: &str, key: &str) -> bool {
    key.strip_prefix("mods.")
        .and_then(|r| r.strip_prefix(id))
        .is_some_and(|r| r.starts_with('.'))
}

/// `mod.<id>` and `mod.<id>.*`.
pub fn own_doc(id: &str, doc: &str) -> bool {
    doc.strip_prefix("mod.")
        .is_some_and(|rest| rest == id || rest.strip_prefix(id).is_some_and(|r| r.starts_with('.')))
}

/// `<id>.*`.
pub fn own_action(id: &str, action: &str) -> bool {
    action
        .strip_prefix(id)
        .is_some_and(|r| r.starts_with('.') && r.len() > 1)
}

/// A use ending in `.*` covers everything under it (`action:media.*`).
fn covers(pattern: &str, id: &str) -> bool {
    pattern
        .strip_suffix(".*")
        .is_some_and(|p| id.strip_prefix(p).is_some_and(|r| r.starts_with('.')))
}

#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
pub(crate) struct RawAction {
    id: String,
    label: Option<String>,
    icon: Option<String>,
    command: Option<String>,
    #[serde(default, rename = "arg")]
    args: Option<Vec<RawArg>>,
    /// An action that takes no arguments says so; without it and without `[[action.arg]]` they are not described.
    #[serde(default)]
    no_args: bool,
}

#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
pub(crate) struct RawArg {
    name: String,
    #[serde(rename = "type")]
    ty: String,
    default: Option<toml::Value>,
    range: Option<[toml::Value; 2]>,
    #[serde(default)]
    choices: Vec<String>,
    #[serde(default)]
    optional: bool,
    #[serde(default)]
    rest: bool,
}

#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
pub(crate) struct RawMenu {
    at: String,
    action: String,
    args: Option<toml::Value>,
    label: Option<String>,
    icon: Option<String>,
}

fn ident(s: &str) -> bool {
    !s.is_empty()
        && s.chars()
            .all(|c| c.is_ascii_lowercase() || c.is_ascii_digit() || c == '_')
}

fn dotted(s: &str) -> bool {
    !s.is_empty()
        && !s.starts_with('.')
        && !s.ends_with('.')
        && s.chars()
            .all(|c| c.is_ascii_lowercase() || c.is_ascii_digit() || "_-.".contains(c))
}

pub(crate) fn icon_ok(s: &str) -> bool {
    ident(s)
}

fn num(v: &toml::Value) -> Option<f64> {
    match v {
        toml::Value::Integer(i) => Some(*i as f64),
        toml::Value::Float(f) => Some(*f),
        _ => None,
    }
}

fn to_json(v: &toml::Value) -> Value {
    serde_json::to_value(v).unwrap_or(Value::Null)
}

/// Validates the contract sections of a manifest. Errors go to `errs` with the same codes-and-paths form as the
/// rest of the manifest (`ValidationError`).
pub(crate) fn parse(
    id: &str,
    provides: &[Provide],
    uses: &[String],
    points_raw: &[String],
    actions: &[RawAction],
    menus: &[RawMenu],
    skips: &BTreeMap<String, String>,
    errs: &mut Vec<ValidationError>,
) -> Contract {
    let mut err = |c: &'static str, p: String, d: &str| errs.push(ValidationError::new(c, p, d));
    let mut c = Contract::default();

    for (i, u) in uses.iter().enumerate() {
        let at = format!("uses[{i}]");
        let (body, optional) = match u.strip_suffix('?') {
            Some(b) => (b, true),
            None => (u.as_str(), false),
        };
        let parsed = body.split_once(':').and_then(|(k, name)| {
            let kind = match k {
                "doc" => UseKind::Doc,
                "action" => UseKind::Action,
                "intent" => UseKind::Intent,
                _ => return None,
            };
            let plain = name.strip_suffix(".*").unwrap_or(name);
            dotted(plain).then(|| (kind, name.to_owned()))
        });
        match parsed {
            None => err("use_malformed", at, u),
            Some((kind, name)) => {
                let own = match kind {
                    UseKind::Doc => own_doc(id, &name),
                    UseKind::Action => own_action(id, &name),
                    UseKind::Intent => own_intent(id, &name),
                };
                if own {
                    err("use_own", at, u);
                } else if c.uses.iter().any(|x| x.kind == kind && x.id == name) {
                    err("use_duplicate", at, u);
                } else {
                    c.uses.push(Use {
                        kind,
                        id: name,
                        optional,
                    });
                }
            }
        }
    }

    for (i, p) in points_raw.iter().enumerate() {
        if !ident(p) {
            // A point is a local name (`open_in`); another mod names it `<mod>:<name>`.
            err("point_invalid", format!("points[{i}]"), p);
        } else if c.points.contains(p) {
            err("point_duplicate", format!("points[{i}]"), p);
        } else {
            c.points.push(p.clone());
        }
    }

    for (i, a) in actions.iter().enumerate() {
        let at = |f: &str| format!("action[{i}].{f}");
        if !own_action(id, &a.id) || !dotted(&a.id) {
            err("action_id_foreign", at("id"), &a.id);
            continue;
        }
        if c.actions.iter().any(|x| x.id == a.id) {
            err("action_duplicate", at("id"), &a.id);
            continue;
        }
        let provided = provides.iter().any(|p| match p {
            Provide::Action(g) => {
                g == &a.id
                    || g.strip_suffix(".*")
                        .is_some_and(|b| a.id.starts_with(&format!("{b}.")))
            }
            _ => false,
        });
        if !provided {
            err("action_not_provided", at("id"), &a.id);
        }
        let Some(label) = a.label.clone().filter(|l| !l.trim().is_empty()) else {
            err("action_label_missing", at("label"), &a.id);
            continue;
        };
        if let Some(icon) = &a.icon
            && !icon_ok(icon)
        {
            err("icon_invalid", at("icon"), icon);
        }
        if let Some(cmd) = &a.command
            && (cmd.trim().is_empty()
                || !cmd
                    .chars()
                    .all(|ch| ch.is_ascii_lowercase() || ch.is_ascii_digit() || ch == ' '))
        {
            err("action_command_invalid", at("command"), cmd);
        }
        let mut args: Option<Vec<ArgDecl>> = match (&a.args, a.no_args) {
            (Some(_), true) => {
                err("action_args_conflict", at("no_args"), &a.id);
                None
            }
            (None, true) => Some(Vec::new()),
            (None, false) => None,
            (Some(_), false) => Some(Vec::new()),
        };
        for (j, r) in a.args.iter().flatten().enumerate() {
            let aat = |f: &str| format!("action[{i}].arg[{j}].{f}");
            let ty = match r.ty.as_str() {
                "bool" => ArgType::Bool,
                "int" => ArgType::Int,
                "float" => ArgType::Float,
                "string" => ArgType::String,
                "enum" => ArgType::Enum,
                "output" => ArgType::Output,
                t => {
                    err("action_arg_type", aat("type"), t);
                    continue;
                }
            };
            if !ident(&r.name) {
                err("action_arg_name", aat("name"), &r.name);
                continue;
            }
            let list = args.get_or_insert_with(Vec::new);
            if list.iter().any(|x| x.name == r.name) {
                err("action_arg_duplicate", aat("name"), &r.name);
                continue;
            }
            let numeric = matches!(ty, ArgType::Int | ArgType::Float);
            let range = match &r.range {
                None => None,
                Some([lo, hi]) => match (num(lo), num(hi)) {
                    (Some(lo), Some(hi)) if numeric && lo <= hi => Some((lo, hi)),
                    _ => {
                        err("action_arg_range", aat("range"), &r.name);
                        None
                    }
                },
            };
            if (ty == ArgType::Enum) == r.choices.is_empty() {
                err("action_arg_choices", aat("choices"), &r.name);
            }
            let default = r.default.as_ref().map(to_json);
            if let Some(d) = &default {
                let fits = match ty {
                    ArgType::Bool => d.is_boolean(),
                    ArgType::Int => d.as_i64().is_some() && in_range(d.as_f64(), range),
                    ArgType::Float => d.is_number() && in_range(d.as_f64(), range),
                    ArgType::String | ArgType::Output => d.is_string(),
                    ArgType::Enum => d.as_str().is_some_and(|s| r.choices.iter().any(|c| c == s)),
                };
                if !fits {
                    err("action_arg_default", aat("default"), &r.name);
                }
            }
            if r.optional && r.default.is_some() {
                err("action_arg_optional", aat("optional"), &r.name);
            }
            if r.rest
                && (matches!(ty, ArgType::Bool | ArgType::Output) || list.iter().any(|x| x.rest))
            {
                err("action_arg_rest", aat("rest"), &r.name);
            }
            list.push(ArgDecl {
                name: r.name.clone(),
                ty,
                default,
                optional: r.optional,
                range,
                choices: r.choices.clone(),
                rest: r.rest,
            });
        }
        if a.command.is_some() {
            // A `>` command runs from one line: nothing it needs may be left unsaid.
            match &args {
                None => err("action_command_untyped", at("command"), &a.id),
                Some(list) => {
                    if list.iter().any(|x| x.required() && !x.rest) {
                        err("action_command_needs_args", at("command"), &a.id);
                    }
                }
            }
        }
        c.actions.push(ActionDecl {
            id: a.id.clone(),
            label,
            icon: a.icon.clone(),
            command: a.command.clone(),
            args,
        });
    }

    for (i, m) in menus.iter().enumerate() {
        let at = |f: &str| format!("menu[{i}].{f}");
        if !points::is_menu(&m.at) {
            err("menu_at_unknown", at("at"), &m.at);
        }
        let declared = c.actions.iter().any(|a| a.id == m.action)
            || (!own_action(id, &m.action) && c.may_call(id, &m.action));
        if !declared {
            err("menu_action_undeclared", at("action"), &m.action);
        }
        if let Some(icon) = &m.icon
            && !icon_ok(icon)
        {
            err("icon_invalid", at("icon"), icon);
        }
        let args = m.args.as_ref().map(to_json);
        if args.as_ref().is_some_and(|a| !a.is_object()) {
            err("menu_args_invalid", at("args"), &m.action);
        } else if let (Some(decl), Some(a)) = (c.action(&m.action), &args)
            && let Err(arg) = decl.check(a)
        {
            err("menu_args_invalid", at("args"), &arg);
        }
        c.menus.push(MenuRow {
            at: m.at.clone(),
            action: m.action.clone(),
            args,
            label: m.label.clone(),
            icon: m.icon.clone(),
        });
    }

    for (key, why) in skips {
        let at = format!("skips.{key}");
        match points::get(key) {
            Some(p) if p.expected => {
                if why.trim().is_empty() {
                    err("skip_reason_empty", at, key);
                } else if provided_variant(key, provides, &c) {
                    err("skip_provided", at, key);
                } else {
                    c.skips.insert(key.clone(), why.clone());
                }
            }
            _ => err("skip_unknown", at, key),
        }
    }
    c
}

/// Whether the mod ships the variant `key` (a point's id with `expected`).
pub fn provided_variant(key: &str, provides: &[Provide], c: &Contract) -> bool {
    match key {
        "glance" => provides.iter().any(|p| matches!(p, Provide::Widget(_))),
        "peek" => provides.iter().any(|p| matches!(p, Provide::Peek(_))),
        "panel" => provides.iter().any(|p| matches!(p, Provide::Panel(_))),
        "desk" => provides.iter().any(|p| matches!(p, Provide::Desk(_))),
        "island-face" => provides.iter().any(|p| matches!(p, Provide::IslandFace(_))),
        "quick-tile" => provides
            .iter()
            .any(|p| matches!(p, Provide::Slot(s) if s == "quick.tiles")),
        "command" => c.actions.iter().any(|a| a.command.is_some()),
        "menu" => c.menus.iter().any(|m| m.at == "module"),
        _ => false,
    }
}
