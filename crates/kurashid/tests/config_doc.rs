//! The `config` document's `history` and `profiles` (K27, CONTRACT rows 21–22) and profile refusals
//! as i18n keys (B5). Drives `ConfigStore` directly, the watcher as the daemon starts it.

use std::path::{Path, PathBuf};
use std::sync::Arc;
use std::sync::atomic::{AtomicUsize, Ordering};
use std::time::{Duration, Instant};

use kurashi_config::{Options, Paths};
use kurashi_ipc::ApplyOp;
use kurashid::config::{self, ConfigStore};
use kurashid::{ActionError, ActionRegistry, Hub, i18n};
use serde_json::{Value, json};

const DOC: &str = "config";

/// A store over a fresh config dir, its actions registered as the daemon registers them.
fn open() -> (Arc<ConfigStore>, Arc<Hub>, ActionRegistry, PathBuf) {
    static N: AtomicUsize = AtomicUsize::new(0);
    let n = N.fetch_add(1, Ordering::SeqCst);
    let root = std::env::temp_dir().join(format!("kurashid-cfgdoc-{}-{n}", std::process::id()));
    let _ = std::fs::remove_dir_all(&root);
    let hub = Hub::new();
    let store = ConfigStore::open(
        hub.clone(),
        kurashi_schema::v1::registry(),
        Paths::rooted(&root),
        Options::default(),
    );
    let mut actions = ActionRegistry::default();
    store.register_actions(&mut actions);
    (store, hub, actions, root)
}

fn profiles_dir(root: &Path) -> PathBuf {
    root.join("config").join("profiles")
}

fn doc(hub: &Hub) -> Value {
    hub.snapshot(DOC).expect("config document").1
}

/// Whether the `config` document lists a profile called `name`.
fn lists(d: &Value, name: &str) -> bool {
    d["profiles"]
        .as_array()
        .is_some_and(|a| a.iter().any(|p| p["name"] == name))
}

/// Waits for `pred` on the `config` document, at most two seconds (the daemon's bound for files).
async fn within_two_seconds(hub: &Hub, pred: impl Fn(&Value) -> bool) -> bool {
    let until = Instant::now() + Duration::from_secs(2);
    loop {
        if pred(&doc(hub)) {
            return true;
        }
        if Instant::now() >= until {
            return false;
        }
        tokio::time::sleep(Duration::from_millis(50)).await;
    }
}

#[tokio::test]
async fn history_follows_apply_undo_redo_and_profile_actions() {
    let (store, hub, actions, root) = open();
    // The buttons' state, without the revision (checked on its own below).
    let buttons = |hub: &Hub| {
        let mut h = doc(hub)["history"].clone();
        h.as_object_mut().unwrap().remove("rev");
        h
    };
    assert_eq!(
        buttons(&hub),
        json!({"can_undo": false, "can_redo": false}),
        "nothing done yet"
    );
    let before = doc(&hub)["history"]["rev"]
        .as_u64()
        .expect("history.rev (K57)");

    store
        .apply(&[ApplyOp::Set {
            set: "bar.height".into(),
            value: json!(44),
            output: None,
        }])
        .expect("apply");
    assert_eq!(buttons(&hub), json!({"can_undo": true, "can_redo": false}));
    // K57: the config's own revision, as the apply answered it.
    assert!(doc(&hub)["history"]["rev"].as_u64().unwrap() > before);

    store.undo(false).expect("undo");
    assert_eq!(buttons(&hub), json!({"can_undo": false, "can_redo": true}));

    store.undo(true).expect("redo");
    assert_eq!(buttons(&hub), json!({"can_undo": true, "can_redo": false}));

    // A profile load is one undoable change; saving a profile publishes the list at once.
    std::fs::create_dir_all(profiles_dir(&root)).unwrap();
    std::fs::write(
        profiles_dir(&root).join("late.toml"),
        "[bar]\nheight = 48\n",
    )
    .unwrap();
    actions
        .invoke("profile.load", json!({"name": "late"}))
        .await
        .expect("profile.load");
    let d = doc(&hub);
    assert_eq!(d["history"]["can_undo"], true);
    assert_eq!(d["history"]["can_redo"], false);
    assert!(lists(&d, "late"), "{d}");

    actions
        .invoke("profile.save", json!({"name": "mine"}))
        .await
        .expect("profile.save");
    assert!(lists(&doc(&hub), "mine"), "saved profile listed at once");

    // `profiles` is what profile.list answers, in the same order.
    let listed = actions
        .invoke("profile.list", json!({}))
        .await
        .expect("profile.list")
        .expect("data");
    assert_eq!(listed["profiles"], doc(&hub)["profiles"]);
}

#[tokio::test]
async fn profile_files_appear_and_vanish_within_two_seconds() {
    let (store, hub, _actions, root) = open();
    // The profiles directory does not exist yet: the watch must still see files that arrive in it.
    let _watch = config::watch(store.clone()).expect("watcher");
    assert!(!lists(&doc(&hub), "late"));

    std::fs::create_dir_all(profiles_dir(&root)).unwrap();
    std::fs::write(
        profiles_dir(&root).join("late.toml"),
        "[bar]\nheight = 48\n",
    )
    .unwrap();
    assert!(
        within_two_seconds(&hub, |d| lists(d, "late")).await,
        "a profile file appears in `profiles` within 2 s"
    );
    let entry = doc(&hub)["profiles"]
        .as_array()
        .and_then(|a| a.iter().find(|p| p["name"] == "late").cloned());
    assert_eq!(entry, Some(json!({"name": "late", "bundled": false})));

    std::fs::remove_file(profiles_dir(&root).join("late.toml")).unwrap();
    assert!(
        within_two_seconds(&hub, |d| !lists(d, "late")).await,
        "a removed profile file leaves `profiles` within 2 s"
    );
}

#[tokio::test]
async fn profile_refusals_are_catalog_keys_in_both_locales() {
    let (_store, _hub, actions, root) = open();
    std::fs::create_dir_all(profiles_dir(&root)).unwrap();
    std::fs::write(profiles_dir(&root).join("broken.toml"), "[bar\nheight = ").unwrap();

    let cases = [
        (
            "profile.load",
            json!({"name": "missing"}),
            "config.error.profile_not_found",
        ),
        (
            "profile.preview",
            json!({"name": "missing"}),
            "config.error.profile_not_found",
        ),
        (
            "profile.load",
            json!({}),
            "config.error.profile_invalid_name",
        ),
        (
            "profile.save",
            json!({"name": "../escape"}),
            "config.error.profile_invalid_name",
        ),
        (
            "profile.preview",
            json!({"name": "broken"}),
            "config.error.profile_parse",
        ),
    ];
    for (action, args, key) in cases {
        let err = actions.invoke(action, args).await.expect_err(action);
        assert_eq!(err, ActionError::Invalid(key.into()), "{action}");
    }

    // Settings shows the catalog text of the key, so every key needs text in en and ja (rule 8).
    // The checkout's catalog: `data_dir()` names the install prefix, which a Nix build's check
    // phase has not populated yet.
    let catalog = std::path::Path::new(env!("CARGO_MANIFEST_DIR")).join("../../i18n");
    for locale in ["en", "ja"] {
        let strings = i18n::load_locale(&catalog, locale);
        for key in [
            "config.error.profile_not_found",
            "config.error.profile_invalid_name",
            "config.error.profile_unreadable",
            "config.error.profile_parse",
            "config.error.profile_write",
        ] {
            assert!(
                strings.get(key).is_some_and(|t| !t.is_empty()),
                "{locale} lacks {key}"
            );
        }
    }
}

/// W33 bench: reading `config.toml` (as the daemon's own reload does) must not trigger a reload — inotify reports
/// opens, and every reload used to wake the next one (~5 a second).
#[tokio::test]
async fn reading_the_config_file_does_not_reload_it() {
    let (store, hub, _actions, _root) = open();
    let user = store.paths().user_file();
    std::fs::create_dir_all(user.parent().unwrap()).unwrap();
    std::fs::write(&user, "schema_version = 2\n[bar]\nheight = 40\n").unwrap();
    let _watch = config::watch(store.clone()).expect("watcher");
    // Let the write's own reload (if any) settle.
    tokio::time::sleep(std::time::Duration::from_millis(600)).await;
    let (before, _) = hub.snapshot(DOC).expect("config doc");
    for _ in 0..5 {
        let _ = std::fs::read_to_string(&user).unwrap();
        tokio::time::sleep(std::time::Duration::from_millis(100)).await;
    }
    tokio::time::sleep(std::time::Duration::from_millis(600)).await;
    let (after, _) = hub.snapshot(DOC).expect("config doc");
    assert_eq!(
        before, after,
        "reading config.toml republished the config document"
    );
}

/// I39: a binding slot offers the registered actions; one that names no action is kept but reported unavailable.
#[tokio::test]
async fn a_binding_to_an_unknown_action_is_inert_with_its_reason() {
    let (store, _hub, mut actions, root) = open();
    actions.register("island.expand", "action.island.expand", |_| async {
        Ok(None)
    });
    kurashid::config::set_action_registry(actions.clone());
    let user = store.paths().user_file();
    std::fs::create_dir_all(user.parent().unwrap()).unwrap();
    std::fs::write(
        &user,
        "schema_version = 2\n[island.main.input]\nleft = \"island.expand\"\nright = \"no.such.action\"\n",
    )
    .unwrap();
    store.reload();
    store.refresh_choices();
    let known = store.get("island.main.input.left", None).expect("left");
    let unknown = store.get("island.main.input.right", None).expect("right");
    assert_eq!(known.reason, None, "{known:?}");
    assert_eq!(
        unknown.reason.as_deref(),
        Some(kurashid::config::REASON_CHOICE_UNAVAILABLE),
        "{unknown:?}"
    );
    let _ = std::fs::remove_dir_all(root);
}
