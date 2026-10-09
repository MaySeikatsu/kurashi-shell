//! Golden files for the generators over `v1`. Regenerate with `UPDATE_GOLDEN=1 cargo test`.

use std::path::PathBuf;

use kurashi_schema::{docs_markdown, example_toml, i18n_en, settings_meta, v1};

fn check(name: &str, actual: &str) {
    let path = PathBuf::from(env!("CARGO_MANIFEST_DIR"))
        .join("tests/golden")
        .join(name);
    if std::env::var_os("UPDATE_GOLDEN").is_some() {
        std::fs::write(&path, actual).unwrap();
        return;
    }
    let expected = std::fs::read_to_string(&path)
        .unwrap_or_else(|e| panic!("{}: {e} (run with UPDATE_GOLDEN=1)", path.display()));
    assert!(
        expected == actual,
        "{name} differs from golden; rerun with UPDATE_GOLDEN=1 and review the diff"
    );
}

#[test]
fn v1_builds() {
    let reg = v1::registry();
    assert_eq!(reg.version(), kurashi_schema::SCHEMA_VERSION);
    assert!(reg.get("theme.material.blur").is_some());
    let d = reg.defaults();
    assert_eq!(d["bar.height"], 32);
    assert_eq!(d["theme.motion.profile"], "calm");
    // Every default validates (also enforced by Registry::build).
    for (k, v) in &d {
        reg.validate(k, v).unwrap();
    }
}

#[test]
fn settings_meta_golden() {
    let mut s = serde_json::to_string_pretty(&settings_meta(v1::registry())).unwrap();
    s.push('\n');
    check("settings_meta.json", &s);
}

#[test]
fn example_toml_golden() {
    check("config.example.toml", &example_toml(v1::registry()));
}

#[test]
fn docs_markdown_golden() {
    check("CONFIG.md", &docs_markdown(v1::registry()));
}

#[test]
fn i18n_en_golden() {
    check("i18n_en.toml", &i18n_en(v1::registry()));
}

/// The commented example must become valid config when uncommented: strip the `# ` from
/// every header and `key = value` line, parse it as real TOML, and validate each key.
#[test]
fn example_toml_roundtrips_defaults() {
    let reg = v1::registry();
    let uncommented: String = example_toml(reg)
        .lines()
        .filter_map(|l| l.strip_prefix("# "))
        .filter(|b| b.starts_with('[') || b.split_once(" = ").is_some_and(|(k, _)| is_bare_key(k)))
        .map(|b| format!("{b}\n"))
        .collect();
    let doc: serde_json::Value = toml::from_str(&uncommented).expect("valid TOML");
    let mut flat = Vec::new();
    flatten("", &doc, &mut flat);
    let mut seen = 0;
    for (key, v) in flat {
        if key == "schema_version" {
            continue;
        }
        reg.validate(&key, &v).unwrap();
        assert_eq!(reg.get(&key).unwrap().default, v, "{key}");
        seen += 1;
    }
    assert_eq!(seen, reg.len());
}

fn flatten(prefix: &str, v: &serde_json::Value, out: &mut Vec<(String, serde_json::Value)>) {
    match v.as_object() {
        Some(map) => {
            for (k, v) in map {
                let key = if prefix.is_empty() {
                    k.clone()
                } else {
                    format!("{prefix}.{k}")
                };
                flatten(&key, v, out);
            }
        }
        None => out.push((prefix.to_owned(), v.clone())),
    }
}

fn is_bare_key(k: &str) -> bool {
    !k.is_empty()
        && k.bytes()
            .all(|b| b.is_ascii_lowercase() || b.is_ascii_digit() || b == b'_')
}
