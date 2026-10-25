//! K66 (row 103): the service documents the quick card shows carry `forced_by` while a forced config key holds their
//! switch, through every publish of the service itself, and lose it when the force goes; `notify.dnd` is refused
//! while `notifications.dnd` is forced.

use kurashid::actions::{ActionError, ActionRegistry};
use kurashid::config::ConfigStore;
use kurashid::hub::Hub;
use kurashid::wiring::{DND_FORCED, SERVICE_SWITCH_KEYS, forced_services, notify_actions_held};
use serde_json::json;

fn root(tag: &str) -> std::path::PathBuf {
    let dir = std::env::temp_dir().join(format!("kurashid-forced-{tag}-{}", std::process::id()));
    let _ = std::fs::remove_dir_all(&dir);
    std::fs::create_dir_all(dir.join("config")).unwrap();
    dir
}

#[test]
fn a_forced_switch_key_marks_its_service_document() {
    let dir = root("svc");
    let managed = dir.join("config").join("managed.toml");
    std::fs::write(
        &managed,
        "[notifications]\ndnd = true\n[_managed]\nenforce = true\n",
    )
    .unwrap();
    let hub = Hub::new();
    for (doc, _) in SERVICE_SWITCH_KEYS {
        hub.register(doc, json!({"available": false}), None);
    }
    let store = ConfigStore::open(
        hub.clone(),
        kurashi_schema::v1::registry(),
        kurashi_config::Paths::rooted(&dir),
        kurashi_config::Options::default(),
    );
    forced_services(&hub, &store);
    let doc = |name: &str| hub.snapshot(name).unwrap().1;
    assert_eq!(doc("svc.notifications")["forced_by"], "nix");
    for (name, keys) in SERVICE_SWITCH_KEYS {
        if keys.is_empty() {
            assert!(
                doc(name).get("forced_by").is_none(),
                "{name}: no key, never forced"
            );
        }
    }

    // The notification server publishes its whole document: the field stays.
    hub.set(
        "svc.notifications",
        json!({"dnd": true, "unread": 0, "toasts": [], "items": []}),
        None,
    )
    .unwrap();
    assert_eq!(doc("svc.notifications")["forced_by"], "nix");
    assert_eq!(doc("svc.notifications")["dnd"], true);

    // Managed but no longer enforced: the user's layer may change it, so nothing holds the switch.
    std::fs::write(&managed, "[notifications]\ndnd = true\n").unwrap();
    store.reload();
    assert!(
        doc("svc.notifications").get("forced_by").is_none(),
        "{}",
        doc("svc.notifications")
    );
    let _ = std::fs::remove_dir_all(&dir);
}

#[tokio::test]
async fn notify_dnd_is_refused_while_its_key_is_forced() {
    let mut actions = ActionRegistry::default();
    notify_actions_held(&mut actions, || None, || true);
    assert_eq!(
        actions.invoke("notify.dnd", json!({"on": false})).await,
        Err(ActionError::Invalid(DND_FORCED.into()))
    );
    let mut actions = ActionRegistry::default();
    notify_actions_held(&mut actions, || None, || false);
    assert!(
        matches!(
            actions.invoke("notify.dnd", json!({"on": false})).await,
            Err(ActionError::Unavailable(_))
        ),
        "not held: on to the server (not running here)"
    );
}
