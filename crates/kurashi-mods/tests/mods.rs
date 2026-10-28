use kurashi_mods::{ModState, ModsError, Policy, Registry, manifest};
use semver::Version;
use serde_json::json;
use std::collections::BTreeSet;
use std::fs;
use std::path::{Path, PathBuf};

fn daemon() -> Version {
    Version::new(0, 1, 0)
}

fn manifest_dir(sub: &str) -> PathBuf {
    Path::new(env!("CARGO_MANIFEST_DIR")).join(sub)
}

/// The bundled mods and the fixtures' `media`, a mod with settings (bundled until media became core, I281).
fn sample_roots() -> [PathBuf; 2] {
    [
        manifest_dir("../../mods"),
        manifest_dir("tests/fixtures/sample"),
    ]
}

const GOOD: &str = r#"
id = "demo"
name = "Demo"
version = "1.0.0"
tier = "native"
kurashi = ">=0.1"
provides = ["widget:demo"]
"#;

fn codes(text: &str) -> Vec<&'static str> {
    manifest::parse("demo", text, &daemon())
        .expect_err("must be invalid")
        .iter()
        .map(|e| e.code)
        .collect()
}

fn write(root: &Path, id: &str, body: &str) {
    fs::create_dir_all(root.join(id)).unwrap();
    fs::write(root.join(id).join("mod.toml"), body).unwrap();
}

fn with_id(id: &str, provides: &str) -> String {
    GOOD.replace(r#"["widget:demo"]"#, provides)
        .replace("demo", id)
}

/// A mod's strings: the shared `mods` domain or its own `mod-<id>` domain (K28: one file per mod).
fn mod_strings(locale: &str, id: &str) -> toml::Table {
    let mut table = toml::Table::new();
    for file in ["mods.toml".to_string(), format!("mod-{id}.toml")] {
        let path = manifest_dir(&format!("../../i18n/{locale}/{file}"));
        if let Ok(text) = fs::read_to_string(path) {
            table.extend(text.parse::<toml::Table>().unwrap());
        }
    }
    table
}

#[test]
fn bundled_manifests_validate() {
    let r = Registry::discover(&[manifest_dir("../../mods")], &daemon());
    let ids: Vec<_> = r.iter().map(|e| e.id.as_str()).collect();
    // Every bundled mod validates; the first two are the oldest (more join as cards land).
    assert!(
        ids.contains(&"easter-eggs"),
        "easter-eggs missing from {ids:?}"
    );
    assert!(!ids.contains(&"media"), "media is core, not a mod (I281)");
    for e in r.iter() {
        assert_eq!(e.state, ModState::Available, "{}: {:?}", e.id, e.state);
        let m = e.manifest.as_ref().unwrap();
        assert!(m.description.is_some(), "{} lacks a description", e.id);
    }
}

#[test]
fn validation_error_table() {
    let setting = |extra: &str| format!("{GOOD}\n[[setting]]\nkey = \"k\"\n{extra}\n");
    let cases: Vec<(String, &str)> = vec![
        (
            GOOD.replace("id = \"demo\"", "id = \"Bad Id\""),
            "id_invalid",
        ),
        (
            GOOD.replace("id = \"demo\"", "id = \"other\""),
            "id_dir_mismatch",
        ),
        (
            GOOD.replace("version = \"1.0.0\"", "version = \"one\""),
            "version_invalid",
        ),
        (GOOD.replace("native", "wasm"), "tier_invalid"),
        (GOOD.replace(">=0.1", "nonsense"), "kurashi_invalid"),
        (GOOD.replace(">=0.1", ">=9.0"), "kurashi_incompatible"),
        (format!("{GOOD}cost = \"huge\"\n"), "cost_invalid"),
        (
            GOOD.replace("widget:demo", "gadget:x"),
            "provide_unknown_kind",
        ),
        (GOOD.replace("widget:demo", "widget"), "provide_malformed"),
        (
            GOOD.replace("widget:demo", "widget:A B"),
            "provide_malformed",
        ),
        (
            GOOD.replace("[\"widget:demo\"]", "[\"widget:demo\", \"widget:demo\"]"),
            "provide_duplicate",
        ),
        (
            format!("{GOOD}capabilities = [\"teleport\"]\n"),
            "capability_unknown",
        ),
        (
            setting("type = \"vec\"\ndefault = 1"),
            "setting_type_invalid",
        ),
        (
            setting("type = \"int\"\ndefault = \"x\""),
            "setting_default_type",
        ),
        (
            setting("type = \"int\"\ndefault = 99\nrange = [1, 10]"),
            "setting_default_out_of_range",
        ),
        (
            setting("type = \"int\"\ndefault = 5\nrange = [10, 1]"),
            "setting_range_invalid",
        ),
        (
            setting("type = \"bool\"\ndefault = true\nrange = [0, 1]"),
            "setting_range_not_numeric",
        ),
        (
            setting("type = \"enum\"\ndefault = \"a\""),
            "setting_choices_missing",
        ),
        (
            setting("type = \"enum\"\ndefault = \"c\"\nchoices = [\"a\", \"b\"]"),
            "setting_default_not_in_choices",
        ),
        (
            setting("type = \"color\"\ndefault = \"red\""),
            "setting_default_not_color",
        ),
        (
            setting("type = \"bool\"\ndefault = true\nchoices = [\"a\"]"),
            "setting_choices_not_enum",
        ),
        (
            format!(
                "{}\n[[setting]]\nkey = \"k\"\ntype = \"bool\"\ndefault = true\n",
                setting("type = \"bool\"\ndefault = true")
            ),
            "setting_key_duplicate",
        ),
        (
            setting("type = \"bool\"\ndefault = true\nbogus = 1"),
            "parse",
        ),
        ("not toml [".into(), "parse"),
    ];
    for (text, want) in cases {
        let got = codes(&text);
        assert!(got.contains(&want), "want {want}, got {got:?} for:\n{text}");
    }
}

#[test]
fn errors_have_i18n_key_and_path() {
    let e = &manifest::parse("demo", &GOOD.replace("native", "wasm"), &daemon()).unwrap_err()[0];
    assert_eq!(
        (e.i18n_key().as_str(), e.path.as_str()),
        ("mods.error.tier_invalid", "tier")
    );
}

#[test]
fn good_manifest_and_float_default() {
    let text = format!(
        "{GOOD}\n[[setting]]\nkey = \"f\"\ntype = \"float\"\ndefault = 1\nrange = [0, 2.5]\n"
    );
    let m = manifest::parse("demo", &text, &daemon()).unwrap();
    assert_eq!(m.config_key("f"), "mods.demo.f");
}

#[test]
fn invalid_fixture_does_not_stop_discovery() {
    let roots = [
        manifest_dir("../../mods"),
        manifest_dir("tests/fixtures/sample"),
        manifest_dir("tests/fixtures/invalid"),
    ];
    let mut r = Registry::discover(&roots, &daemon());
    let broken = r.get("broken-mod").unwrap();
    let ModState::Invalid { errors } = &broken.state else {
        panic!("{:?}", broken.state)
    };
    let codes: Vec<_> = errors.iter().map(|e| e.code).collect();
    for c in [
        "id_dir_mismatch",
        "tier_invalid",
        "capability_unknown",
        "provide_unknown_kind",
        "setting_default_out_of_range",
    ] {
        assert!(codes.contains(&c), "{c} in {codes:?}");
    }
    assert_eq!(r.get("media").unwrap().state, ModState::Available);
    assert!(matches!(r.enable("broken-mod"), Err(ModsError::Invalid(_))));
    let doc = r.doc();
    let b = doc["mods"]
        .as_array()
        .unwrap()
        .iter()
        .find(|m| m["id"] == "broken-mod")
        .unwrap();
    assert_eq!(b["state"], "invalid");
    assert!(
        b["errors"][0]["key"]
            .as_str()
            .unwrap()
            .starts_with("mods.error.")
    );
}

#[test]
fn missing_manifest_is_invalid() {
    let t = tempfile::tempdir().unwrap();
    fs::create_dir(t.path().join("empty")).unwrap();
    let r = Registry::discover(&[t.path().into()], &daemon());
    let ModState::Invalid { errors } = &r.get("empty").unwrap().state else {
        panic!()
    };
    assert_eq!(errors[0].code, "manifest_missing");
}

#[test]
fn user_shadows_bundled() {
    let (b, u) = (tempfile::tempdir().unwrap(), tempfile::tempdir().unwrap());
    write(b.path(), "demo", GOOD);
    write(u.path(), "demo", &GOOD.replace("1.0.0", "2.0.0"));
    let r = Registry::discover(&[b.path().into(), u.path().into()], &daemon());
    assert_eq!(
        r.get("demo")
            .unwrap()
            .manifest
            .as_ref()
            .unwrap()
            .version
            .to_string(),
        "2.0.0"
    );
    assert_eq!(r.shadows.len(), 1);
    assert_eq!(r.shadows[0].winner, u.path().join("demo"));
    assert_eq!(r.shadows[0].shadowed, b.path().join("demo"));
    assert_eq!(r.doc()["mods"][0]["shadows_bundled"], true);
}

#[test]
fn too_new_mod_is_invalid_in_discovery() {
    let t = tempfile::tempdir().unwrap();
    write(t.path(), "demo", &GOOD.replace(">=0.1", ">=9.0"));
    let r = Registry::discover(&[t.path().into()], &daemon());
    let ModState::Invalid { errors } = &r.get("demo").unwrap().state else {
        panic!()
    };
    assert_eq!(errors[0].code, "kurashi_incompatible");
}

#[test]
fn conflicts_name_both_mods() {
    let t = tempfile::tempdir().unwrap();
    write(
        t.path(),
        "aa",
        &with_id("aa", r#"["widget:x", "action:media.*"]"#),
    );
    write(t.path(), "bb", &with_id("bb", r#"["action:media.play"]"#));
    write(t.path(), "cc", &with_id("cc", r#"["widget:x"]"#));
    write(t.path(), "dd", &with_id("dd", r#"["action:other.play"]"#));
    let mut r = Registry::discover(&[t.path().into()], &daemon());
    r.enable("aa").unwrap();
    let Err(ModsError::Conflict { mod_id, other, .. }) = r.enable("bb") else {
        panic!()
    };
    assert_eq!((mod_id.as_str(), other.as_str()), ("bb", "aa"));
    assert!(matches!(r.enable("cc"), Err(ModsError::Conflict { .. })));
    assert_eq!(r.get("bb").unwrap().state, ModState::Available);
    r.enable("dd").unwrap();
    // disabling frees the slot
    r.disable("aa").unwrap();
    r.enable("cc").unwrap();
}

#[test]
fn enable_disable_symmetric_and_idempotent() {
    let mut r = Registry::discover(&sample_roots(), &daemon());
    let on = r.enable("media").unwrap();
    assert_eq!(r.get("media").unwrap().state, ModState::Enabled);
    assert_eq!(on.added.len(), 5 + 2);
    assert!(on.removed.is_empty());
    assert!(r.enable("media").unwrap().added.is_empty());
    // Disabling drops the provides; the mod is still loaded, so its settings stay registered.
    let off = r.disable("media").unwrap();
    assert_eq!(r.get("media").unwrap().state, ModState::Disabled);
    assert_eq!(off.removed, on.added[..5]);
    assert!(off.added.is_empty());
    assert!(r.disable("media").unwrap().removed.is_empty());
    // Unloading takes the settings too, and enabling an available mod registers all of it again.
    let unloaded = r.unload("media").unwrap();
    assert_eq!(unloaded.removed, on.added[5..]);
    assert_eq!(r.get("media").unwrap().state, ModState::Available);
    assert_eq!(r.enable("media").unwrap().added, on.added);
    assert!(matches!(r.enable("nope"), Err(ModsError::Unknown(_))));
}

#[test]
fn load_registers_settings_and_leaves_provides_off() {
    let mut r = Registry::discover(&sample_roots(), &daemon());
    let loaded = r.load("media").unwrap();
    assert_eq!(r.get("media").unwrap().state, ModState::Disabled);
    assert!(
        loaded
            .added
            .iter()
            .all(|c| matches!(c, kurashi_mods::Contribution::Setting { .. }))
    );
    assert_eq!(loaded.added.len(), 2);
    assert!(r.load("media").unwrap().added.is_empty(), "idempotent");
    // Loading a mod that is on changes nothing; unloading it switches it off first.
    r.enable("media").unwrap();
    assert!(r.load("media").unwrap().added.is_empty());
    let gone = r.unload("media").unwrap();
    assert_eq!(gone.removed.len(), 5 + 2);
    assert_eq!(r.get("media").unwrap().state, ModState::Available);
    assert!(r.unload("media").unwrap().removed.is_empty());
    assert!(matches!(r.load("nope"), Err(ModsError::Unknown(_))));
    assert!(matches!(r.unload("nope"), Err(ModsError::Unknown(_))));
}

#[test]
fn reconcile_makes_the_registry_equal_to_the_lists() {
    let mut r = Registry::discover(&sample_roots(), &daemon());
    let set = |ids: &[&str]| ids.iter().map(|s| s.to_string()).collect();
    // An enabled id is loaded even when the loaded list does not name it (K25, enabled ⊆ loaded).
    assert!(r.reconcile(&set(&[]), &set(&["media"])).is_empty());
    assert_eq!(r.get("media").unwrap().state, ModState::Enabled);
    // Dropping it from both lists unloads it; unknown ids are ignored.
    assert!(r.reconcile(&set(&["nope"]), &set(&["nope"])).is_empty());
    assert_eq!(r.get("media").unwrap().state, ModState::Available);
    // Loaded but off.
    r.reconcile(&set(&["media"]), &set(&[]));
    assert_eq!(r.get("media").unwrap().state, ModState::Disabled);
    // Idempotent: the same lists again change nothing.
    let before = r.doc();
    r.reconcile(&set(&["media"]), &set(&[]));
    assert_eq!(r.doc(), before);
}

#[test]
fn reconcile_switches_off_before_it_switches_on() {
    let t = tempfile::tempdir().unwrap();
    write(t.path(), "aa", &with_id("aa", r#"["widget:x"]"#));
    write(t.path(), "bb", &with_id("bb", r#"["widget:x"]"#));
    let set = |ids: &[&str]| -> BTreeSet<String> { ids.iter().map(|s| s.to_string()).collect() };
    let mut r = Registry::discover(&[t.path().into()], &daemon());
    r.reconcile(&set(&["aa"]), &set(&["aa"]));
    // The rival is listed in place of the mod it replaces: the swap must go through.
    let refused = r.reconcile(&set(&["bb"]), &set(&["bb"]));
    assert!(refused.is_empty(), "{refused:?}");
    assert_eq!(r.get("bb").unwrap().state, ModState::Enabled);
    assert_eq!(r.get("aa").unwrap().state, ModState::Available);
    // Both listed as enabled from scratch: the first by id gets the provide, the other is
    // reported and stays off.
    let mut r = Registry::discover(&[t.path().into()], &daemon());
    let refused = r.reconcile(&set(&["aa", "bb"]), &set(&["aa", "bb"]));
    assert_eq!(refused.len(), 1);
    assert_eq!(refused[0].0, "bb");
    assert_eq!(r.get("aa").unwrap().state, ModState::Enabled);
    assert_eq!(r.get("bb").unwrap().state, ModState::Disabled);
}

#[test]
fn running_is_reported_per_mod_and_defaults_off() {
    let mut r = Registry::discover(&sample_roots(), &daemon());
    r.enable("media").unwrap();
    assert!(
        r.doc()["mods"]
            .as_array()
            .unwrap()
            .iter()
            .all(|m| m["running"] == false)
    );
    r.set_running_reasons("media", vec!["mods.running.subscribed".into()]);
    r.set_running_reasons("nope", vec!["mods.running.subscribed".into()]);
    let doc = r.doc();
    let media = doc["mods"]
        .as_array()
        .unwrap()
        .iter()
        .find(|m| m["id"] == "media")
        .unwrap();
    assert_eq!(media["running"], true);
    assert_eq!(media["running_reasons"], json!(["mods.running.subscribed"]));
    assert_eq!(media["state"], "enabled");
    r.set_running_reasons("media", Vec::new());
    let doc = r.doc();
    let media = doc["mods"]
        .as_array()
        .unwrap()
        .iter()
        .find(|m| m["id"] == "media")
        .unwrap();
    assert_eq!(media["running"], false);
    assert_eq!(media["running_reasons"], json!([]));
}

#[test]
fn jobs_are_declared_per_mod_and_never_conflict() {
    // A job is the mod's own (I23): two mods may both declare `job:watch`, and both can be on.
    let t = tempfile::tempdir().unwrap();
    write(t.path(), "aa", &with_id("aa", r#"["job:watch"]"#));
    write(t.path(), "bb", &with_id("bb", r#"["job:watch"]"#));
    write(t.path(), "cc", &with_id("cc", r#"["job:Watch"]"#));
    let mut r = Registry::discover(&[t.path().into()], &daemon());
    assert_eq!(
        r.get("aa").unwrap().manifest.as_ref().unwrap().provides[0].to_string(),
        "job:watch"
    );
    r.enable("aa").unwrap();
    r.enable("bb").unwrap();
    assert_eq!(r.get("cc").unwrap().state.name(), "invalid");
}

#[test]
fn ids_of_the_mods_lists_are_reserved() {
    // `mods.loaded` / `mods.enabled` are config keys: a mod table of the same name cannot exist.
    for id in ["loaded", "enabled"] {
        let errs = manifest::parse(id, &with_id(id, r#"["widget:x"]"#), &daemon())
            .expect_err("reserved id");
        let codes: Vec<_> = errs.iter().map(|e| e.code).collect();
        assert_eq!(codes, ["id_reserved"], "{id}");
    }
}

#[test]
fn policy_enables_only_listed() {
    let mut r = Registry::discover(&sample_roots(), &daemon());
    let policy = Policy {
        default_enabled: ["easter-eggs".to_string()].into(),
    };
    let out = r.apply_defaults(&policy);
    assert_eq!(out.len(), 1);
    assert!(out[0].1.is_ok());
    assert_eq!(r.get("easter-eggs").unwrap().state, ModState::Enabled);
    assert_eq!(r.get("media").unwrap().state, ModState::Available);
}

#[test]
fn setting_contributions_use_mod_config_keys() {
    let mut r = Registry::discover(&sample_roots(), &daemon());
    let ch = r.enable("media").unwrap();
    let keys: Vec<_> = ch
        .added
        .iter()
        .filter_map(|c| match c {
            kurashi_mods::Contribution::Setting { config_key, .. } => Some(config_key.as_str()),
            _ => None,
        })
        .collect();
    assert_eq!(keys, ["mods.media.show_art", "mods.media.seek_step"]);
}

#[test]
fn description_is_optional_and_blank_counts_as_absent() {
    assert_eq!(
        manifest::parse("demo", GOOD, &daemon())
            .unwrap()
            .description,
        None
    );
    let text = format!("{GOOD}description = \"mods.demo.description\"\n");
    let m = manifest::parse("demo", &text, &daemon()).unwrap();
    assert_eq!(m.description.as_deref(), Some("mods.demo.description"));
    let blank = format!("{GOOD}description = \"  \"\n");
    assert_eq!(
        manifest::parse("demo", &blank, &daemon())
            .unwrap()
            .description,
        None
    );
}

fn entry<'a>(doc: &'a serde_json::Value, id: &str) -> &'a serde_json::Value {
    doc["mods"]
        .as_array()
        .unwrap()
        .iter()
        .find(|m| m["id"] == id)
        .unwrap()
}

/// A JSON null anywhere in a document breaks PROTOCOL: absence is the only "empty".
fn assert_no_nulls(v: &serde_json::Value, at: &str) {
    use serde_json::Value;
    match v {
        Value::Null => panic!("null at {at}"),
        Value::Array(xs) => {
            for (i, x) in xs.iter().enumerate() {
                assert_no_nulls(x, &format!("{at}[{i}]"));
            }
        }
        Value::Object(kv) => {
            for (k, x) in kv {
                assert_no_nulls(x, &format!("{at}.{k}"));
            }
        }
        _ => {}
    }
}

#[test]
fn mods_doc_emits_description_only_when_declared() {
    let t = tempfile::tempdir().unwrap();
    write(
        t.path(),
        "demo",
        &format!("{GOOD}description = \"mods.demo.description\"\n"),
    );
    write(t.path(), "plain", &with_id("plain", r#"["widget:plain"]"#));
    let doc = Registry::discover(&[t.path().into()], &daemon()).doc();
    assert_eq!(entry(&doc, "demo")["description"], "mods.demo.description");
    assert!(entry(&doc, "plain").get("description").is_none());
}

#[test]
fn documents_carry_no_nulls_and_invalid_entries_omit_absent_fields() {
    let t = tempfile::tempdir().unwrap();
    fs::create_dir(t.path().join("empty")).unwrap(); // no mod.toml at all
    let roots = [
        manifest_dir("../../mods"),
        manifest_dir("tests/fixtures/sample"),
        manifest_dir("tests/fixtures/invalid"),
        t.path().into(),
    ];
    let doc = Registry::discover(&roots, &daemon()).doc();
    assert_no_nulls(&doc, "doc");
    for id in ["broken-mod", "empty"] {
        let e = entry(&doc, id);
        assert_eq!(e["state"], "invalid");
        for key in ["version", "tier", "cost", "description"] {
            assert!(e.get(key).is_none(), "{id}.{key} must be absent, not null");
        }
    }
    assert_eq!(entry(&doc, "media")["version"], "0.1.0");
}

#[test]
fn bundled_descriptions_resolve_in_both_locales() {
    let r = Registry::discover(&[manifest_dir("../../mods")], &daemon());
    for e in r.iter() {
        let key = e.manifest.as_ref().unwrap().description.as_deref().unwrap();
        for locale in ["en", "ja"] {
            let table = mod_strings(locale, &e.id);
            let text = table.get(key).and_then(|v| v.as_str());
            assert!(
                text.is_some_and(|s| !s.trim().is_empty()),
                "{key} missing in i18n/{locale}/mods.toml and mod-{}.toml",
                e.id
            );
        }
    }
}

/// Every label, help and choice label a bundled setting shows (K22: `mods.<id>.<key>` when the
/// manifest names no label) resolves in both catalogs.
#[test]
fn bundled_setting_strings_resolve_in_both_locales() {
    let r = Registry::discover(&[manifest_dir("../../mods")], &daemon());
    for e in r.iter() {
        let m = e.manifest.as_ref().unwrap();
        for s in &m.settings {
            let mut keys = vec![s.label.clone().unwrap_or_else(|| m.config_key(&s.key))];
            keys.extend(s.help.clone());
            keys.extend(
                s.choices
                    .iter()
                    .map(|c| format!("{}.{c}", m.config_key(&s.key))),
            );
            for locale in ["en", "ja"] {
                let table = mod_strings(locale, &e.id);
                for key in &keys {
                    let text = table.get(key).and_then(|v| v.as_str());
                    assert!(
                        text.is_some_and(|t| !t.trim().is_empty()),
                        "{key} missing in i18n/{locale}/mods.toml and mod-{}.toml",
                        e.id
                    );
                }
            }
        }
    }
}
