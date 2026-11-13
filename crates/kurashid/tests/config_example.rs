//! `config.toml.example` at the repository root (session 33, the user: "a config example with all possible config
//! options exposed, as noren does"): every core key from the schema (`kurashi_schema::example_toml`) and every setting of
//! every bundled mod (their `mod.toml`), each commented out at its default with its label and help (English strings).
//! Generated, never hand-kept (rule 3): this test fails when the file differs; `UPDATE_GOLDEN=1` rewrites it.

use std::collections::BTreeMap;
use std::path::{Path, PathBuf};

use kurashi_mods::manifest::{Setting, SettingType, SettingValue};

fn root() -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../..")
}

/// Every English string, from every i18n domain file.
fn strings() -> BTreeMap<String, String> {
    let mut out = BTreeMap::new();
    let mut files: Vec<PathBuf> = std::fs::read_dir(root().join("i18n/en"))
        .unwrap()
        .flatten()
        .map(|e| e.path())
        .filter(|p| p.extension().is_some_and(|e| e == "toml"))
        .collect();
    files.sort();
    for f in files {
        let t: toml::Table = toml::from_str(&std::fs::read_to_string(&f).unwrap()).unwrap();
        for (k, v) in t {
            if let Some(s) = v.as_str() {
                out.insert(k, s.to_string());
            }
        }
    }
    out
}

/// `text` as comment lines of at most `width` columns, each starting with `# ` (and `indent` after it on a continuation).
fn wrap(text: &str, width: usize, indent: &str) -> Vec<String> {
    let mut lines = Vec::new();
    let mut line = String::from("#");
    let mut first = true;
    for word in text.split_whitespace() {
        let lead = if first { " " } else { "" };
        if line.len() + 1 + word.len() > width && line.len() > 2 {
            lines.push(line);
            line = format!("# {indent}");
            first = false;
        } else if !line.ends_with(' ') {
            line.push_str(lead);
        }
        if !line.ends_with(' ') && line.len() > 1 {
            line.push(' ');
        }
        line.push_str(word);
        first = false;
    }
    if line.len() > 1 {
        lines.push(line);
    }
    lines
}

fn toml_value(v: &SettingValue) -> String {
    let value = match v {
        SettingValue::Bool(b) => toml::Value::Boolean(*b),
        SettingValue::Int(i) => toml::Value::Integer(*i),
        SettingValue::Float(f) => toml::Value::Float(*f),
        SettingValue::Str(s) => toml::Value::String(s.clone()),
        SettingValue::List(l) => {
            toml::Value::Array(l.iter().cloned().map(toml::Value::String).collect())
        }
        SettingValue::Records(rows) => toml::Value::Array(
            rows.iter()
                .map(|r| toml::Value::try_from(r).expect("a record is a TOML table"))
                .collect(),
        ),
    };
    value.to_string()
}

fn type_note(s: &Setting) -> String {
    let mut parts = Vec::new();
    match s.ty {
        SettingType::Enum | SettingType::List if !s.choices.is_empty() => parts.push(format!(
            "choices: {}",
            s.choices
                .iter()
                .map(|c| format!("\"{c}\""))
                .collect::<Vec<_>>()
                .join(" | ")
        )),
        _ => {}
    }
    if let Some(src) = &s.choices_from {
        parts.push(format!("choices: from `{src}` (resolved at runtime)"));
    }
    if let Some((lo, hi)) = s.range {
        parts.push(format!("range: {lo}..={hi}"));
    }
    if let Some(u) = &s.unit {
        parts.push(format!("unit: {u}"));
    }
    if matches!(s.ty, SettingType::Records) {
        parts.push("records: a list of tables".into());
    }
    if matches!(s.ty, SettingType::Color) {
        parts.push("a colour, \"#rrggbb\"".into());
    }
    parts.join(" · ")
}

fn mods_part(strings: &BTreeMap<String, String>) -> String {
    let version = semver::Version::parse(env!("CARGO_PKG_VERSION")).unwrap();
    let mut dirs: Vec<PathBuf> = std::fs::read_dir(root().join("mods"))
        .unwrap()
        .flatten()
        .map(|e| e.path())
        .filter(|p| p.join("mod.toml").is_file())
        .collect();
    dirs.sort();
    let tr = |k: &str| strings.get(k).cloned().unwrap_or_else(|| k.to_string());
    let mut out = String::new();
    out.push_str(
        "\n# ==== Mods ======================================================================================\n\
         #\n\
         # Bundled mods are off until listed in `mods.enabled` (and `mods.loaded`), e.g.\n\
         #   [mods]\n\
         #   loaded = [\"webdock\", \"terminal\"]\n\
         #   enabled = [\"webdock\", \"terminal\"]\n\
         # Each mod's settings live under [mods.<id>] and apply while it is enabled.\n",
    );
    for dir in dirs {
        let name = dir.file_name().unwrap().to_string_lossy().into_owned();
        let text = std::fs::read_to_string(dir.join("mod.toml")).unwrap();
        let m = kurashi_mods::manifest::parse(&name, &text, &version)
            .unwrap_or_else(|e| panic!("mods/{name}/mod.toml: {e:?}"));
        if m.settings.is_empty() {
            continue;
        }
        out.push_str(&format!("\n# [mods.{}]\n#\n", m.id));
        let title = tr(&m.name);
        let desc = m.description.as_deref().map(tr).unwrap_or_default();
        for l in wrap(&format!("{title} — {desc}").trim_end_matches(" — ").to_string(), 100, "") {
            out.push_str(&l);
            out.push('\n');
        }
        out.push_str("#\n");
        for s in &m.settings {
            let label = s.label.as_deref().map(tr).unwrap_or_else(|| s.key.clone());
            let help = s.help.as_deref().map(tr).unwrap_or_default();
            let head = if help.is_empty() {
                label
            } else {
                format!("{label} — {help}")
            };
            for l in wrap(&head, 100, "") {
                out.push_str(&l);
                out.push('\n');
            }
            let note = type_note(s);
            if !note.is_empty() {
                out.push_str(&format!("#   {note}\n"));
            }
            out.push_str(&format!("# {} = {}\n#\n", s.key, toml_value(&s.default)));
        }
    }
    out
}

fn example() -> String {
    let strings = strings();
    let core = kurashi_schema::example_toml(kurashi_schema::v1::registry());
    let mut out = String::from(
        "# Kurashi (暮らし) configuration example — every option, at its default.\n\
         #\n\
         # Copy what you want to change into ~/.config/kurashi/config.toml (or set it in Settings; Home-Manager users:\n\
         # programs.kurashi.settings). Kurashi works with no config file at all; every key here is optional and listed\n\
         # commented out at its default. Unset keys keep following the defaults, the style and the profile.\n\
         #\n\
         # Generated from the schema and the bundled mods' manifests (crates/kurashid/tests/config_example.rs);\n\
         # do not edit by hand: `UPDATE_GOLDEN=1 cargo test -p kurashid --test config_example` rewrites it.\n\
         #\n\
         # ==== Core ======================================================================================\n\
         #\n",
    );
    // The schema's own header (its first lines up to the first blank one) is replaced by the one above.
    let body = core.split_once("\n\n").map(|(_, b)| b).unwrap_or(&core);
    let lead: Vec<&str> = core
        .lines()
        .take_while(|l| !l.is_empty())
        .filter(|l| l.starts_with("# Per-output") || l.starts_with("# schema_version"))
        .collect();
    for l in lead {
        out.push_str(l);
        out.push('\n');
    }
    out.push('\n');
    out.push_str(body.trim_end());
    out.push('\n');
    out.push_str(&mods_part(&strings));
    out
}

#[test]
fn config_toml_example_is_current() {
    let path: PathBuf = root().join("config.toml.example");
    let actual = example();
    // Every line is a comment or blank: the example is valid config, and copying a commented line in works.
    for l in actual.lines() {
        assert!(l.is_empty() || l.starts_with('#'), "not a comment: {l}");
    }
    // And every key line, uncommented, is TOML.
    for l in actual.lines().filter(|l| l.starts_with("# ") && l.contains(" = ")) {
        let line = &l[2..];
        let key = line.split(" = ").next().unwrap_or_default();
        let is_key = !key.is_empty()
            && key
                .chars()
                .all(|c| c.is_ascii_lowercase() || c.is_ascii_digit() || c == '_' || c == '.');
        if is_key {
            toml::from_str::<toml::Table>(line)
                .unwrap_or_else(|e| panic!("not TOML when uncommented: {line} ({e})"));
        }
    }
    if std::env::var_os("UPDATE_GOLDEN").is_some() {
        std::fs::write(&path, &actual).unwrap();
        return;
    }
    let expected = std::fs::read_to_string(&path).unwrap_or_default();
    assert!(
        expected == actual,
        "{} differs; rerun with UPDATE_GOLDEN=1 and review the diff",
        Path::new("config.toml.example").display()
    );
}
