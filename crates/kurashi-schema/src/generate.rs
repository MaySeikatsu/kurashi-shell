//! Generators: everything that used to be a hand-maintained parallel list (rule 3).
//!
//! Visibility of `hidden` keys: excluded from [`settings_meta`], present (marked) in
//! [`example_toml`] and [`docs_markdown`] — they are valid config, just not offered in the UI.

use std::fmt::Write as _;

use serde_json::{Map, Value, json};

use crate::meta::{Coupling, KeyMeta, Ty};
use crate::records::RecordSpec;
use crate::registry::Registry;

/// Settings control a row renders with.
pub fn control_kind(m: &KeyMeta) -> &'static str {
    let c = &m.constraints;
    match m.ty {
        Ty::Bool => "toggle",
        Ty::Int | Ty::Float if c.min.is_some() && c.max.is_some() => "slider",
        Ty::Int | Ty::Float => "number",
        Ty::Choice => "select",
        // K64: every `keys.*` string is a shortcut, recorded by keys (`keys.write` is a bool). A stand-in until the derive
        // takes `#[kurashi(control = "shortcut")]` (CONTRACT-CHANGE 425): the check moved here from Settings' `pickerOf`.
        Ty::String if m.key.starts_with("keys.") => "shortcut",
        Ty::String if !c.choices.is_empty() || c.choices_from.is_some() => "select",
        Ty::String => "text",
        // Fixed choices (a mod's `list` setting, I26) or a choice source: an ordered pick list.
        Ty::StringList if c.choices_from.is_some() || !c.choices.is_empty() => "pick_list",
        Ty::StringList => "list",
        Ty::Color => "color",
        Ty::Font => "font",
        Ty::Action => "action_binding",
        // A list of tables with declared fields (K38): the generic records editor.
        Ty::Records => "records",
    }
}

type Section<'a> = (&'a str, Vec<&'a KeyMeta>);
type Page<'a> = (&'a str, Vec<Section<'a>>);

/// Group keys by `(page, section)` in first-appearance order.
fn pages(reg: &Registry, include_hidden: bool) -> Vec<Page<'_>> {
    let mut out: Vec<Page<'_>> = Vec::new();
    for m in reg.iter().filter(|m| include_hidden || !m.flags.hidden) {
        let pi = match out.iter().position(|(p, _)| *p == m.page) {
            Some(i) => i,
            None => {
                out.push((&m.page, Vec::new()));
                out.len() - 1
            }
        };
        let sections = &mut out[pi].1;
        match sections.iter_mut().find(|(s, _)| *s == m.section) {
            Some((_, rows)) => rows.push(m),
            None => sections.push((&m.section, vec![m])),
        }
    }
    out
}

/// Settings page metadata for the frontend. Wire shape (to be frozen by the lead):
///
/// ```text
/// { schema_version, pages: [ { id, label, sections: [ { id, label, rows: [
///     { key, control, type, default, label, help?, min?, max?, step?, unit?,
///       choices?: [{value, label}], choices_from?, per_output, restart, advanced, since,
///       couplings: [ {kind: requires|capability|overridden_by, reason, ...} ] } ] } ] } ] }
/// ```
/// `label`/`help`/`reason` are i18n keys. `couplings` lets the UI say *why* a control is inert.
pub fn settings_meta(reg: &Registry) -> Value {
    let pages: Vec<Value> = pages(reg, false)
        .into_iter()
        .map(|(page, sections)| {
            let sections: Vec<Value> = sections
                .into_iter()
                .map(|(section, rows)| {
                    json!({
                        "id": section,
                        "label": format!("settings.section.{section}"),
                        "rows": rows.into_iter().map(row).collect::<Vec<_>>(),
                    })
                })
                .collect();
            json!({ "id": page, "label": format!("settings.page.{page}"), "sections": sections })
        })
        .collect();
    json!({ "schema_version": reg.version(), "pages": pages })
}

fn row(m: &KeyMeta) -> Value {
    let mut r = Map::new();
    r.insert("key".into(), json!(m.key));
    r.insert("control".into(), json!(control_kind(m)));
    r.insert("type".into(), json!(m.ty));
    r.insert("default".into(), m.default.clone());
    r.insert("label".into(), json!(m.label));
    if let Some(help) = &m.help {
        r.insert("help".into(), json!(help));
    }
    let c = &m.constraints;
    for (name, v) in [("min", &c.min), ("max", &c.max), ("step", &c.step)] {
        if let Some(v) = v {
            r.insert(name.into(), v.clone());
        }
    }
    if let Some(unit) = &c.unit {
        r.insert("unit".into(), json!(unit));
    }
    if !c.choices.is_empty() {
        r.insert("choices".into(), json!(c.choices));
    }
    // Resolved into `choices` by the daemon (I9, PROTOCOL §5); an empty list until it does.
    if let Some(src) = &c.choices_from {
        r.insert("choices_from".into(), json!(src));
        r.entry("choices").or_insert_with(|| json!([]));
    }
    if let Some(spec) = &c.record {
        r.insert("record".into(), record_json(&m.key, spec));
    }
    r.insert("per_output".into(), json!(m.flags.per_output));
    r.insert("restart".into(), json!(m.flags.restart));
    r.insert("advanced".into(), json!(m.flags.advanced));
    r.insert("since".into(), json!(m.since));
    let couplings: Vec<Value> = m
        .couplings
        .iter()
        .map(|cp| {
            let mut v = serde_json::to_value(cp).unwrap_or_default();
            if let Some(o) = v.as_object_mut() {
                o.insert("reason".into(), json!(cp.reason_key()));
            }
            v
        })
        .collect();
    r.insert("couplings".into(), Value::Array(couplings));
    Value::Object(r)
}

/// The records editor's description of a `records` key (K38): its fields with their controls, the
/// `unique` field and the field a row is named by. Choice labels are i18n keys
/// `<key>.<field>.<choice>`, as a mod's enum choices are (K22); a field's label is its declared key
/// or, without one, its name.
fn record_json(key: &str, spec: &RecordSpec) -> Value {
    let fields: Vec<Value> = spec
        .fields
        .iter()
        .map(|f| {
            let mut j = Map::new();
            j.insert("key".into(), json!(f.key));
            j.insert("type".into(), json!(f.ty.name()));
            j.insert("required".into(), json!(f.required));
            if let Some(d) = &f.default {
                j.insert("default".into(), d.clone());
            }
            j.insert(
                "label".into(),
                json!(f.label.clone().unwrap_or_else(|| f.key.clone())),
            );
            if let Some(p) = &f.pattern {
                j.insert("pattern".into(), json!(p));
            }
            if !f.schemes.is_empty() {
                j.insert("schemes".into(), json!(f.schemes));
            }
            if !f.choices.is_empty() {
                let choices: Vec<Value> = f
                    .choices
                    .iter()
                    .map(|c| json!({"value": c, "label": format!("{key}.{}.{c}", f.key)}))
                    .collect();
                j.insert("choices".into(), Value::Array(choices));
            }
            if let Some((lo, hi)) = f.range {
                j.insert("range".into(), json!([lo, hi]));
            }
            Value::Object(j)
        })
        .collect();
    let mut r = Map::new();
    if let Some(unique) = &spec.unique {
        r.insert("unique".into(), json!(unique));
    }
    if let Some(label) = spec.label_field() {
        r.insert("item_label".into(), json!(label.key));
    }
    r.insert("fields".into(), Value::Array(fields));
    Value::Object(r)
}

/// TOML literal for a JSON value (strings, numbers, bools, arrays — the only shapes we use).
pub fn toml_value(v: &Value) -> String {
    match v {
        Value::Array(items) => {
            let inner: Vec<String> = items.iter().map(toml_value).collect();
            format!("[{}]", inner.join(", "))
        }
        Value::Object(map) => {
            let inner: Vec<String> = map
                .iter()
                .map(|(k, v)| format!("{k} = {}", toml_value(v)))
                .collect();
            format!("{{ {} }}", inner.join(", "))
        }
        // serde_json strings/numbers/bools are valid TOML literals (f64 keeps its `.0`).
        other => other.to_string(),
    }
}

fn wrap(text: &str, width: usize) -> Vec<String> {
    let mut lines = Vec::new();
    let mut line = String::new();
    for word in text.split_whitespace() {
        if !line.is_empty() && line.len() + 1 + word.len() > width {
            lines.push(std::mem::take(&mut line));
        }
        if !line.is_empty() {
            line.push(' ');
        }
        line.push_str(word);
    }
    if !line.is_empty() {
        lines.push(line);
    }
    lines
}

/// One-line notes shared by the TOML and Markdown generators.
fn notes(m: &KeyMeta, code: fn(&str) -> String) -> Vec<String> {
    let c = &m.constraints;
    let mut n = Vec::new();
    if let (Some(lo), Some(hi)) = (&c.min, &c.max) {
        let mut s = format!("range: {}", code(&format!("{lo}..={hi}")));
        if let Some(step) = &c.step {
            let _ = write!(s, ", step {}", code(&step.to_string()));
        }
        if let Some(unit) = &c.unit {
            let _ = write!(s, " ({unit})");
        }
        n.push(s);
    } else if let Some(unit) = &c.unit {
        n.push(format!("unit: {unit}"));
    }
    if !c.choices.is_empty() {
        let list: Vec<String> = c
            .choices
            .iter()
            .map(|ch| code(&format!("{:?}", ch.value)))
            .collect();
        n.push(format!("choices: {}", list.join(" | ")));
    }
    if let Some(src) = &c.choices_from {
        n.push(format!("choices: from `{src}` (resolved at runtime)"));
    }
    for cp in &m.couplings {
        n.push(match cp {
            Coupling::Requires { key, op, value } => {
                format!(
                    "only while {}",
                    code(&format!("{key} {} {value}", op.symbol()))
                )
            }
            Coupling::Capability { name } => {
                format!("needs compositor capability {}", code(name))
            }
            Coupling::OverriddenBy { key, forces } => match forces {
                Some(f) => format!(
                    "forced to {} while {} is on",
                    code(&f.to_string()),
                    code(key)
                ),
                None => format!("overridden while {} is on", code(key)),
            },
        });
    }
    let f = &m.flags;
    for (on, label) in [
        (f.per_output, "per-output"),
        (f.restart, "restart required"),
        (f.advanced, "advanced"),
        (f.hidden, "hidden"),
    ] {
        if on {
            n.push(label.into());
        }
    }
    if m.since > 1 {
        n.push(format!("since schema v{}", m.since));
    }
    n
}

/// `config.example.toml`: every key commented out at its default, with label, help and notes.
pub fn example_toml(reg: &Registry) -> String {
    let mut out = format!(
        "# Kurashi configuration — schema v{v}.\n\
         # Generated from the schema (kurashi_schema::example_toml); do not edit by hand.\n\
         #\n\
         # Every key is listed commented out at its default. Set only what you want to change:\n\
         # unset keys keep following defaults, themes and profiles.\n\
         # Per-output keys can be overridden per monitor, e.g. [outputs.\"DP-1\".bar] height = 40.\n\
         #\n\
         # schema_version = {v}\n",
        v = reg.version()
    );
    // Group by table, in first-appearance order; root keys (no dot) must precede any header.
    let mut tables: Vec<(&str, Vec<&KeyMeta>)> = Vec::new();
    for m in reg.iter() {
        let table = m.key.rsplit_once('.').map_or("", |(t, _)| t);
        match tables.iter_mut().find(|(t, _)| *t == table) {
            Some((_, keys)) => keys.push(m),
            None => tables.push((table, vec![m])),
        }
    }
    tables.sort_by_key(|(t, _)| !t.is_empty());
    for (table, keys) in tables {
        out.push('\n');
        if !table.is_empty() {
            let _ = writeln!(out, "# [{table}]");
        }
        for m in keys {
            let name = m.key.rsplit_once('.').map_or(m.key.as_str(), |(_, n)| n);
            let _ = writeln!(out, "#");
            let head = match &m.text.help {
                Some(help) => format!("{} — {help}", m.text.label),
                None => m.text.label.clone(),
            };
            for line in wrap(&head, 90) {
                let _ = writeln!(out, "# {line}");
            }
            let notes = notes(m, |s| s.to_owned());
            if !notes.is_empty() {
                for line in wrap(&notes.join(" · "), 90) {
                    let _ = writeln!(out, "#   {line}");
                }
            }
            let _ = writeln!(out, "# {name} = {}", toml_value(&m.default));
        }
    }
    out
}

/// `docs/CONFIG.md`-style reference, grouped by settings page and section.
pub fn docs_markdown(reg: &Registry) -> String {
    let mut out = format!(
        "# Configuration reference (schema v{})\n\n\
         <!-- Generated by kurashi_schema::docs_markdown — do not edit by hand. -->\n\n\
         Keys are flat and dotted; in `config.toml` the last segment is the key and the rest is \
         the table (`bar.height` → `[bar] height = …`). Per-output keys may also be set under \
         `[outputs.\"<name>\".<table>]`.\n",
        reg.version()
    );
    let code = |s: &str| format!("`{s}`");
    for (page, sections) in pages(reg, true) {
        let _ = write!(out, "\n## {}\n", humanize(page));
        for (section, keys) in sections {
            let _ = write!(out, "\n### {}\n", humanize(section));
            for m in keys {
                let _ = write!(out, "\n#### `{}` — {}\n\n", m.key, m.text.label);
                if let Some(help) = &m.text.help {
                    let _ = write!(out, "{help}\n\n");
                }
                let _ = writeln!(
                    out,
                    "- type: `{}` · default: `{}`",
                    m.ty,
                    toml_value(&m.default)
                );
                for n in notes(m, code) {
                    let _ = writeln!(out, "- {n}");
                }
            }
        }
    }
    out
}

/// The `en` i18n catalog for every key this schema references (labels, help, choices, pages,
/// sections, inert reasons, validation errors), flat quoted keys. The lead writes it to
/// `i18n/en/config.toml`; `ja` is translated from it.
pub fn i18n_en(reg: &Registry) -> String {
    let mut entries: Vec<(String, String)> = Vec::new();
    let mut push = |k: &str, v: &str| {
        if !entries.iter().any(|(e, _)| e == k) {
            entries.push((k.to_owned(), v.to_owned()));
        }
    };
    for (page, sections) in pages(reg, true) {
        push(&format!("settings.page.{page}"), &humanize(page));
        for (section, _) in sections {
            push(&format!("settings.section.{section}"), &humanize(section));
        }
    }
    for m in reg.iter() {
        push(&m.label, &m.text.label);
        if let (Some(k), Some(v)) = (&m.help, &m.text.help) {
            push(k, v);
        }
        for ch in &m.constraints.choices {
            push(&ch.label, &ch.text);
        }
    }
    push(
        "settings.inert.requires",
        "Only applies while {key} is {value}.",
    );
    push(
        "settings.inert.capability",
        "Your compositor does not support {name}.",
    );
    push("settings.inert.overridden_by", "Controlled by {key}.");
    for (k, v) in crate::error::ValidationError::CATALOG {
        push(k, v);
    }
    let mut out = format!(
        "# Generated by kurashi_schema::i18n_en (schema v{}) — do not edit by hand.\n",
        reg.version()
    );
    for (k, v) in entries {
        let _ = writeln!(out, "{} = {}", Value::from(k), Value::from(v));
    }
    out
}

/// `motion_profile` → `Motion profile`.
pub fn humanize(id: &str) -> String {
    let s = id.replace(['_', '-'], " ");
    let mut c = s.chars();
    match c.next() {
        Some(f) => f.to_uppercase().chain(c).collect(),
        None => String::new(),
    }
}
