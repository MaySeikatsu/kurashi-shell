//! What the migration tests share (rule 10): a config file written as an older schema, opened by the store (which
//! migrates it), and read back.

use std::path::PathBuf;
use std::sync::atomic::{AtomicUsize, Ordering};

use kurashi_config::{Options, Paths};
use kurashid::Hub;
use kurashid::config::ConfigStore;

fn root() -> PathBuf {
    static N: AtomicUsize = AtomicUsize::new(0);
    let n = N.fetch_add(1, Ordering::SeqCst);
    let root = std::env::temp_dir().join(format!("kurashid-mig-{}-{n}", std::process::id()));
    let _ = std::fs::remove_dir_all(&root);
    std::fs::create_dir_all(root.join("config")).unwrap();
    root
}

/// The file after the store opened (and migrated) it, and the store's effective values for `keys`.
pub fn migrated(src: &str, keys: &[&str]) -> (String, Vec<serde_json::Value>) {
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
