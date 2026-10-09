//! The shipped manifest and its strings (rule 8): the real validator accepts `mods/sysmon/mod.toml`, and every
//! copy key the crate and the QML views use exists in both catalogues with the same placeholders.

use kurashi_mods::{Provide, SettingType};
use std::collections::BTreeSet;
use std::path::{Path, PathBuf};

fn repo() -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../..")
}

fn manifest_text() -> String {
    std::fs::read_to_string(repo().join("mods/sysmon/mod.toml")).unwrap()
}

fn catalogue(locale: &str) -> toml::Table {
    let path = repo().join(format!("i18n/{locale}/mod-sysmon.toml"));
    toml::from_str(&std::fs::read_to_string(path).unwrap()).unwrap()
}

/// Every `"…"` literal in `text` that starts with one of the copy prefixes.
fn copy_keys(text: &str) -> BTreeSet<String> {
    const PREFIXES: [&str; 7] = [
        "action.sysmon.",
        "mods.sysmon.",
        "sysmon.error.",
        "sysmon.bar.",
        "sysmon.panel.",
        "sysmon.face.",
        "sysmon.state.",
    ];
    text.split('"')
        .skip(1)
        .step_by(2)
        .filter(|lit| PREFIXES.iter().any(|p| lit.starts_with(p)))
        .map(str::to_string)
        .collect()
}

fn scan(dir: &Path, ext: &str, out: &mut String) {
    for entry in std::fs::read_dir(dir).unwrap().flatten() {
        let path = entry.path();
        if path.is_dir() {
            scan(&path, ext, out);
        } else if path.extension().is_some_and(|e| e == ext) {
            out.push_str(&std::fs::read_to_string(&path).unwrap());
            out.push('\n');
        }
    }
}

fn placeholders(s: &str) -> BTreeSet<String> {
    s.split('{')
        .skip(1)
        .filter_map(|rest| rest.split_once('}').map(|(name, _)| name.to_string()))
        .collect()
}

#[test]
fn the_shipped_manifest_passes_the_validator_and_declares_what_the_crate_registers() {
    let daemon = semver::Version::parse("0.0.1").unwrap();
    let m = kurashi_mods::parse("sysmon", &manifest_text(), &daemon).expect("valid manifest");
    assert_eq!(m.id, "sysmon");
    for want in [
        Provide::Service("sysmon".into()),
        Provide::Service("sysmon.procs".into()),
        Provide::Widget("sysmon".into()),
        Provide::Panel("sysmon".into()),
        Provide::IslandFace("sysmon".into()),
        Provide::Action("sysmon.*".into()),
    ] {
        assert!(m.provides.contains(&want), "{want:?}");
    }
    let keys: Vec<&str> = m.settings.iter().map(|s| s.key.as_str()).collect();
    assert_eq!(keys.len(), 14, "{keys:?}");
    let interval = m.settings.iter().find(|s| s.key == "interval").unwrap();
    assert_eq!(interval.ty, SettingType::Int);
    assert_eq!(interval.range, Some((1.0, 60.0)));
    assert!(m.capabilities.is_empty());
}

#[test]
fn every_copy_key_exists_in_both_catalogues_with_the_same_placeholders() {
    let en = catalogue("en");
    let ja = catalogue("ja");

    let mut used = BTreeSet::new();
    let m =
        kurashi_mods::parse("sysmon", &manifest_text(), &semver::Version::new(0, 0, 1)).unwrap();
    used.extend(m.description.clone());
    for s in &m.settings {
        used.extend(s.label.clone());
        used.extend(s.help.clone());
    }
    let mut code = String::new();
    scan(
        &repo().join("crates/kurashi-mod-sysmon/src"),
        "rs",
        &mut code,
    );
    used.extend(copy_keys(&code));
    let mut qml = String::new();
    scan(&repo().join("mods/sysmon/qml"), "qml", &mut qml);
    used.extend(copy_keys(&qml));
    // A floor, so an empty scan cannot pass: the manifest and the crate alone have more than this.
    assert!(used.len() >= 25, "the scan found the copy: {}", used.len());

    for key in &used {
        let (Some(e), Some(j)) = (en.get(key), ja.get(key)) else {
            panic!("{key} is missing from en or ja");
        };
        let (e, j) = (e.as_str().unwrap(), j.as_str().unwrap());
        assert_eq!(
            placeholders(e),
            placeholders(j),
            "{key}: placeholders differ"
        );
    }
}
