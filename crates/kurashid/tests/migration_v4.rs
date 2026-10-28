//! Schema v4 (K74): `v3_to_v4` turns `theme.shape.radius_scale` into `theme.shape.radius` (px) at the root and in
//! `[outputs.*]` tables, drops `layout.frame.radius`, and leaves a file that already says `radius` as it is.

use std::path::PathBuf;
use std::sync::atomic::{AtomicUsize, Ordering};

use kurashi_config::{Options, Paths};
use kurashid::Hub;
use kurashid::config::ConfigStore;

fn root() -> PathBuf {
    static N: AtomicUsize = AtomicUsize::new(0);
    let n = N.fetch_add(1, Ordering::SeqCst);
    let root = std::env::temp_dir().join(format!("kurashid-mig4-{}-{n}", std::process::id()));
    let _ = std::fs::remove_dir_all(&root);
    std::fs::create_dir_all(root.join("config")).unwrap();
    root
}

fn migrated(src: &str) -> String {
    let root = root();
    let paths = Paths::rooted(&root);
    std::fs::write(paths.user_file(), src).unwrap();
    let _store = ConfigStore::open(
        Hub::new(),
        kurashi_schema::v1::registry(),
        Paths::rooted(&root),
        Options::default(),
    );
    let out = std::fs::read_to_string(paths.user_file()).unwrap();
    let _ = std::fs::remove_dir_all(&root);
    out
}

#[test]
fn radius_scale_becomes_px_and_frame_radius_goes() {
    let out = migrated(
        "schema_version = 3\n\n[theme.shape]\nradius_scale = 1.25\n\n[layout.frame]\nenabled = true\nradius = 24\n\n\
         [outputs.\"DP-1\".theme.shape]\nradius_scale = 0.5\n",
    );
    assert!(
        out.contains(&format!("schema_version = {}", kurashi_schema::v1::VERSION)),
        "{out}"
    );
    assert!(!out.contains("radius_scale"), "{out}");
    let doc: toml::Table = out.parse().unwrap();
    assert_eq!(
        doc["theme"]["shape"]["radius"].as_integer(),
        Some(23),
        "{out}"
    );
    assert_eq!(
        doc["outputs"]["DP-1"]["theme"]["shape"]["radius"].as_integer(),
        Some(9),
        "{out}"
    );
    assert!(doc["layout"]["frame"].get("radius").is_none(), "{out}");
    assert_eq!(
        doc["layout"]["frame"]["enabled"].as_bool(),
        Some(true),
        "{out}"
    );
}

#[test]
fn a_file_in_the_new_shape_keeps_its_radius() {
    let out = migrated("[theme.shape]\nradius = 12\n");
    let doc: toml::Table = out.parse().unwrap();
    assert_eq!(
        doc["theme"]["shape"]["radius"].as_integer(),
        Some(12),
        "{out}"
    );
}
