//! Schema v6 (session 16): the styles that were only a palette (catppuccin, rose-pine, tokyo-night) became palette
//! choices; `v5_to_v6` keeps a file's appearance — style `none`, the style's look, palette and recipe as its own values.

use std::path::PathBuf;
use std::sync::atomic::{AtomicUsize, Ordering};

use kurashi_config::{Options, Paths};
use kurashid::Hub;
use kurashid::config::ConfigStore;

fn root() -> PathBuf {
    static N: AtomicUsize = AtomicUsize::new(0);
    let n = N.fetch_add(1, Ordering::SeqCst);
    let root = std::env::temp_dir().join(format!("kurashid-mig6-{}-{n}", std::process::id()));
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
fn a_palette_style_becomes_your_own_with_its_values() {
    let out = migrated(
        "schema_version = 5\n\n[theme]\nstyle = \"tokyo-night\"\n\n[theme.shape]\nradius = 9\n",
    );
    let doc: toml::Table = out.parse().unwrap();
    let th = &doc["theme"];
    assert_eq!(th["style"].as_str(), Some("none"), "{out}");
    assert_eq!(th["look"].as_str(), Some("kanso"), "{out}");
    assert_eq!(
        th["colors"]["palette"].as_str(),
        Some("tokyo-night"),
        "{out}"
    );
    assert_eq!(th["density"].as_str(), Some("compact"), "{out}");
    // A value the file set stays its own.
    assert_eq!(th["shape"]["radius"].as_integer(), Some(9), "{out}");
}

#[test]
fn another_style_is_left_alone() {
    let out = migrated("schema_version = 5\n\n[theme]\nstyle = \"washi\"\n");
    let doc: toml::Table = out.parse().unwrap();
    assert_eq!(doc["theme"]["style"].as_str(), Some("washi"), "{out}");
    assert!(doc["theme"].get("look").is_none(), "{out}");
}
