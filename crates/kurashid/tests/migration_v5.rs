//! Schema v5 (K74, session 16): `v4_to_v5` keeps a screen-corner size the user chose — a file that sets
//! `theme.shape.screen_corners` gets `screen_corners_follow = false` — and leaves every other file following the radius.

use std::path::PathBuf;
use std::sync::atomic::{AtomicUsize, Ordering};

use kurashi_config::{Options, Paths};
use kurashid::Hub;
use kurashid::config::ConfigStore;

fn root() -> PathBuf {
    static N: AtomicUsize = AtomicUsize::new(0);
    let n = N.fetch_add(1, Ordering::SeqCst);
    let root = std::env::temp_dir().join(format!("kurashid-mig5-{}-{n}", std::process::id()));
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
fn a_chosen_screen_corner_size_stops_following() {
    let out = migrated("schema_version = 4\n\n[theme.shape]\nscreen_corners = 24\n");
    let doc: toml::Table = out.parse().unwrap();
    assert_eq!(
        doc["schema_version"].as_integer(),
        Some(i64::from(kurashi_schema::v1::VERSION)),
        "{out}"
    );
    let shape = &doc["theme"]["shape"];
    assert_eq!(shape["screen_corners"].as_integer(), Some(24), "{out}");
    assert_eq!(
        shape["screen_corners_follow"].as_bool(),
        Some(false),
        "{out}"
    );
}

#[test]
fn square_screen_corners_chosen_stay_square() {
    let out = migrated("schema_version = 4\n\n[theme.shape]\nscreen_corners = 0\n");
    let doc: toml::Table = out.parse().unwrap();
    assert_eq!(
        doc["theme"]["shape"]["screen_corners_follow"].as_bool(),
        Some(false),
        "{out}"
    );
}

#[test]
fn a_file_without_a_size_follows_and_a_said_follow_stays() {
    let out = migrated("schema_version = 4\n\n[theme.shape]\nradius = 12\n");
    assert!(!out.contains("screen_corners_follow"), "{out}");
    let out = migrated("[theme.shape]\nscreen_corners = 10\nscreen_corners_follow = true\n");
    let doc: toml::Table = out.parse().unwrap();
    assert_eq!(
        doc["theme"]["shape"]["screen_corners_follow"].as_bool(),
        Some(true),
        "{out}"
    );
}
