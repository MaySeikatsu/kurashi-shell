//! I205 (K66, row 103): `notifications.dnd` follows the config while the daemon runs, forced or not. A test has no
//! session bus, so no notification server is up here; `follow_dnd` is the point the daemon hands the value to.

use std::sync::atomic::Ordering;
use std::sync::{Arc, Mutex};

use kurashi_ipc::ApplyOp;
use kurashid::config::ConfigStore;
use kurashid::hub::Hub;
use kurashid::wiring::follow_dnd;
use serde_json::json;

fn root(tag: &str) -> std::path::PathBuf {
    let dir = std::env::temp_dir().join(format!("kurashid-dnd-{tag}-{}", std::process::id()));
    let _ = std::fs::remove_dir_all(&dir);
    std::fs::create_dir_all(dir.join("config")).unwrap();
    dir
}

#[test]
fn notify_dnd_follows_the_config_at_runtime_forced_or_not() {
    let dir = root("follow");
    let user = dir.join("config").join("config.toml");
    let managed = dir.join("config").join("managed.toml");
    std::fs::write(&user, "[notifications]\ndnd = false\n").unwrap();
    let store = ConfigStore::open(
        Hub::new(),
        kurashi_schema::v1::registry(),
        kurashi_config::Paths::rooted(&dir),
        kurashi_config::Options::default(),
    );
    let seen = Arc::new(Mutex::new(Vec::new()));
    let sink = seen.clone();
    let held = follow_dnd(&store, move |on| sink.lock().unwrap().push(on));
    let calls = || seen.lock().unwrap().clone();
    let is_held = || held.load(Ordering::Relaxed);
    assert!(calls().is_empty(), "the value at the start is not a change");

    // The user's file, edited while the daemon runs.
    std::fs::write(&user, "[notifications]\ndnd = true\n").unwrap();
    store.reload();
    assert_eq!(calls(), [true]);
    assert!(!is_held());

    // An unrelated edit leaves the switch alone: the value did not move, so nothing is put in effect.
    std::fs::write(
        &user,
        "[notifications]\ndnd = true\n[night_light]\nenabled = true\n",
    )
    .unwrap();
    store.reload();
    assert_eq!(calls(), [true]);

    // The settings page writes the key: one atomic apply, the same path.
    store
        .apply(&[ApplyOp::Set {
            set: "notifications.dnd".into(),
            value: json!(false),
            output: None,
        }])
        .unwrap();
    assert_eq!(calls(), [true, false]);

    // Forced by managed.toml: the forced value is in effect, and it holds the switch (K66).
    std::fs::write(
        &managed,
        "[notifications]\ndnd = true\n[_managed]\nenforce = true\n",
    )
    .unwrap();
    store.reload();
    assert_eq!(calls(), [true, false, true]);
    assert!(is_held());

    // The force goes: the user's layer (false) is in effect again, and the switch is free.
    std::fs::write(&managed, "[notifications]\ndnd = true\n").unwrap();
    store.reload();
    assert_eq!(calls(), [true, false, true, false]);
    assert!(!is_held());
    let _ = std::fs::remove_dir_all(&dir);
}
