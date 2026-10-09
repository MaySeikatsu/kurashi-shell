use kurashi_mods::{ModState, ModsError, Policy, Registry, manifest};
use semver::Version;
use std::fs;
use std::path::{Path, PathBuf};

fn daemon() -> Version {
    Version::new(0, 1, 0)
}

fn manifest_dir(sub: &str) -> PathBuf {
    Path::new(env!("CARGO_MANIFEST_DIR")).join(sub)
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

#[test]
fn bundled_manifests_validate() {
    let r = Registry::discover(&[manifest_dir("../../mods")], &daemon());
    let ids: Vec<_> = r.iter().map(|e| e.id.as_str()).collect();
    assert_eq!(ids, ["easter-eggs", "media"]);
    for e in r.iter() {
        assert_eq!(e.state, ModState::Available, "{}: {:?}", e.id, e.state);
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
    assert_eq!(m.config_key("f"), "mod.demo.f");
}

#[test]
fn invalid_fixture_does_not_stop_discovery() {
    let roots = [
        manifest_dir("../../mods"),
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
    let mut r = Registry::discover(&[manifest_dir("../../mods")], &daemon());
    let on = r.enable("media").unwrap();
    assert_eq!(r.get("media").unwrap().state, ModState::Enabled);
    assert_eq!(on.added.len(), 5 + 2);
    assert!(on.removed.is_empty());
    assert!(r.enable("media").unwrap().added.is_empty());
    let off = r.disable("media").unwrap();
    assert_eq!(r.get("media").unwrap().state, ModState::Disabled);
    assert_eq!(off.removed, on.added);
    assert!(off.added.is_empty());
    assert!(r.disable("media").unwrap().removed.is_empty());
    assert_eq!(r.enable("media").unwrap().added, on.added);
    assert!(matches!(r.enable("nope"), Err(ModsError::Unknown(_))));
}

#[test]
fn policy_enables_only_listed() {
    let mut r = Registry::discover(&[manifest_dir("../../mods")], &daemon());
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
    let mut r = Registry::discover(&[manifest_dir("../../mods")], &daemon());
    let ch = r.enable("media").unwrap();
    let keys: Vec<_> = ch
        .added
        .iter()
        .filter_map(|c| match c {
            kurashi_mods::Contribution::Setting { config_key, .. } => Some(config_key.as_str()),
            _ => None,
        })
        .collect();
    assert_eq!(keys, ["mod.media.show_art", "mod.media.seek_step"]);
}
