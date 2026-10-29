//! Schema v7 (session 17, I297): the material `glass` became `translucent` with its blur switch on, and blur's default
//! went off; `v6_to_v7` keeps what a file showed.

use std::path::PathBuf;
use std::sync::atomic::{AtomicUsize, Ordering};

use kurashi_config::{Options, Paths};
use kurashid::Hub;
use kurashid::config::ConfigStore;

fn root() -> PathBuf {
    static N: AtomicUsize = AtomicUsize::new(0);
    let n = N.fetch_add(1, Ordering::SeqCst);
    let root = std::env::temp_dir().join(format!("kurashid-mig7-{}-{n}", std::process::id()));
    let _ = std::fs::remove_dir_all(&root);
    std::fs::create_dir_all(root.join("config")).unwrap();
    root
}

/// The file after the store opened (and migrated) it, and the store's effective values for `keys`.
fn migrated(src: &str, keys: &[&str]) -> (String, Vec<serde_json::Value>) {
    let root = root();
    let paths = Paths::rooted(&root);
    std::fs::write(paths.user_file(), src).unwrap();
    let store = ConfigStore::open(
        Hub::new(),
        kurashi_schema::v1::registry(),
        Paths::rooted(&root),
        Options::default(),
    );
    let values = keys
        .iter()
        .map(|k| store.get(k, None).unwrap().value)
        .collect();
    let out = std::fs::read_to_string(paths.user_file()).unwrap();
    let _ = std::fs::remove_dir_all(&root);
    (out, values)
}

fn version(doc: &toml::Table) -> Option<i64> {
    doc["schema_version"].as_integer()
}

#[test]
fn glass_becomes_translucent_with_its_blur_on() {
    let (out, v) = migrated(
        "schema_version = 6\n\n[theme.material]\n# frosted\nkind = \"glass\"\nopacity = 0.6\n",
        &["theme.material.kind", "theme.material.blur"],
    );
    let doc: toml::Table = out.parse().unwrap();
    assert_eq!(
        version(&doc),
        Some(i64::from(kurashi_schema::v1::VERSION)),
        "{out}"
    );
    let m = &doc["theme"]["material"];
    assert_eq!(m["kind"].as_str(), Some("translucent"), "{out}");
    // Blur was the default (on) under glass: written, since the default is off now.
    assert_eq!(m["blur"].as_bool(), Some(true), "{out}");
    assert_eq!(m["opacity"].as_float(), Some(0.6), "{out}");
    assert!(out.contains("# frosted"), "{out}");
    assert_eq!(
        v,
        [serde_json::json!("translucent"), serde_json::json!(true)]
    );
}

#[test]
fn glass_keeps_a_blur_switch_turned_off() {
    let (out, _) = migrated(
        "schema_version = 6\n\n[theme.material]\nkind = \"glass\"\nblur = false\n",
        &[],
    );
    let doc: toml::Table = out.parse().unwrap();
    let m = &doc["theme"]["material"];
    assert_eq!(m["kind"].as_str(), Some("translucent"), "{out}");
    assert_eq!(m["blur"].as_bool(), Some(false), "{out}");
}

#[test]
fn glass_on_an_output_migrates_too() {
    let (out, _) = migrated(
        "schema_version = 6\n\n[outputs.\"DP-1\".theme.material]\nkind = \"glass\"\n",
        &[],
    );
    let doc: toml::Table = out.parse().unwrap();
    let m = &doc["outputs"]["DP-1"]["theme"]["material"];
    assert_eq!(m["kind"].as_str(), Some("translucent"), "{out}");
    assert_eq!(m["blur"].as_bool(), Some(true), "{out}");
}

#[test]
fn translucent_with_an_inert_blur_switch_stays_unblurred() {
    let (out, v) = migrated(
        "schema_version = 6\n\n[theme.material]\nkind = \"translucent\"\nblur = true\n",
        &["theme.material.blur"],
    );
    let doc: toml::Table = out.parse().unwrap();
    assert_eq!(
        doc["theme"]["material"]["blur"].as_bool(),
        Some(false),
        "{out}"
    );
    assert_eq!(v, [serde_json::json!(false)]);
}

#[test]
fn a_v6_file_without_glass_round_trips() {
    let src = "schema_version = 6\n\n# The user's own.\n[theme]\nlook = \"kanso\"\n\n[theme.shape]\ncorners = \"squircle\"\nradius = 12\n\n[theme.material]\nkind = \"solid\"\nblur = true\n";
    let (out, v) = migrated(src, &["theme.shape.squircle", "theme.frame_outline"]);
    assert_eq!(
        out,
        src.replacen(
            "schema_version = 6",
            &format!("schema_version = {}", kurashi_schema::v1::VERSION),
            1
        )
    );
    // The new keys take their defaults: today's squircle curve, the chrome's own frame outline.
    assert_eq!(v, [serde_json::json!(0.77), serde_json::json!("auto")]);
}
