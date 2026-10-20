//! The web dock through the daemon (K38, K40, MODS.md "Web dock"), with the bundled manifest (`mods/webdock/mod.toml`)
//! and the dock's own directories redirected into a scratch folder. The pins are the `pins` records and `pinned`
//! settings the manifest carries: the settings writes of `webdock.add`, `pin` and `remove` go through the real config
//! store here, and the dock reads them back from its feed. The supervisor's timers and the recording host are covered
//! by crates/kurashi-mod-webdock/tests/behaviour.rs, and the host's start, stop and restarts by tests/hosts.rs.

use std::path::Path;
use std::sync::Arc;
use std::time::Duration;

use kurashi_config::{Options, Paths};
use kurashi_mod_webdock::{Dirs, SystemOpener, Webdock};
use kurashid::config::ConfigStore;
use kurashid::{ActionError, ActionRegistry, Hub, wiring};
use serde_json::{Value, json};

/// Polls the document until `ready` holds (the service publishes from its own task), for up to two seconds.
async fn wait_for(hub: &Hub, ready: impl Fn(&Value) -> bool) -> Value {
    for _ in 0..200 {
        let (_, doc) = hub.snapshot("mod.webdock").expect("served while enabled");
        if ready(&doc) {
            return doc;
        }
        tokio::time::sleep(Duration::from_millis(10)).await;
    }
    panic!("the document did not reach the expected state in two seconds");
}

#[tokio::test]
async fn the_pin_writes_reach_the_document_and_a_rest_on_the_edge_reveals_it() {
    let dir = std::env::temp_dir().join(format!("w20-dmn-writes-{}", std::process::id()));
    let _ = std::fs::remove_dir_all(&dir);
    std::fs::create_dir_all(&dir).unwrap();

    let hub = Hub::new();
    let store: Arc<ConfigStore> = ConfigStore::open(
        hub.clone(),
        kurashi_schema::v1::registry(),
        Paths::rooted(&dir.join("config")),
        Options::default(),
    );
    let mut actions = ActionRegistry::default();
    wiring::ui(&hub, &mut actions);
    let dock = Webdock::with(Dirs::rooted(&dir), Arc::new(SystemOpener));
    wiring::mods_native(
        &hub,
        &mut actions,
        vec![Path::new(env!("CARGO_MANIFEST_DIR")).join("../../mods")],
        Some(store.clone()),
        vec![Box::new(dock)],
        None,
    );
    actions
        .invoke("mod.enable", json!({"id": "webdock"}))
        .await
        .expect("the bundled dock enables");
    // The document's service runs while something subscribes to it (rule 5): the test is the subscriber.
    hub.subscribe("mod.webdock").expect("served while enabled");

    // `add` writes a record through the config store and answers with its id; the dock serves the pin.
    assert_eq!(
        actions
            .invoke(
                "webdock.add",
                json!({"url": "https://www.example.org/start", "title": "Docs"})
            )
            .await,
        Ok(Some(json!({"pin": "example-org"})))
    );
    let doc = wait_for(&hub, |d| {
        d["pins"]
            .as_array()
            .is_some_and(|p| p.iter().any(|p| p["id"] == "example-org"))
    })
    .await;
    let pin = doc["pins"]
        .as_array()
        .unwrap()
        .iter()
        .find(|p| p["id"] == "example-org")
        .unwrap();
    assert_eq!(pin["kind"], "web");
    assert_eq!(pin["title"], "Docs");
    assert_eq!(pin["target"], "https://www.example.org/start");
    assert_eq!(
        actions
            .invoke("webdock.add", json!({"url": "https://example.org/other"}))
            .await,
        Ok(Some(json!({"pin": "example-org-2"}))),
        "the same host takes the next free id"
    );
    actions
        .invoke("webdock.move", json!({"pin": "example-org-2", "to": 0}))
        .await
        .unwrap();
    wait_for(&hub, |d| d["pins"][0]["id"] == "example-org-2").await;
    actions
        .invoke("webdock.remove", json!({"pin": "example-org-2"}))
        .await
        .unwrap();
    wait_for(&hub, |d| d["pins"].as_array().is_some_and(|p| p.len() == 1)).await;
    assert_eq!(
        actions
            .invoke("webdock.remove", json!({"pin": "example-org-2"}))
            .await,
        Err(ActionError::Invalid("webdock.error.unknown_pin".into()))
    );

    // `pin` with no argument writes `pinned`, which the dock serves once the feed brings it back.
    assert_eq!(
        wait_for(&hub, |d| d["pinned"] == false).await["pinned"],
        false
    );
    actions.invoke("webdock.pin", json!({})).await.unwrap();
    wait_for(&hub, |d| d["pinned"] == true).await;

    // A rest on the edge reveals the strip after 250 ms on the real clock (K40); a leave that comes first does not.
    actions
        .invoke(
            "webdock.hover",
            json!({"part": "edge", "inside": true, "output": "DP-1"}),
        )
        .await
        .unwrap();
    wait_for(&hub, |d| d["mode"] == "compact" && d["output"] == "DP-1").await;
    actions.invoke("webdock.collapse", json!({})).await.unwrap();
    actions
        .invoke(
            "webdock.hover",
            json!({"part": "edge", "inside": false, "output": "DP-1"}),
        )
        .await
        .unwrap();

    actions
        .invoke("mod.disable", json!({"id": "webdock"}))
        .await
        .unwrap();
    let _ = std::fs::remove_dir_all(&dir);
}

#[tokio::test]
async fn the_dock_serves_its_document_once_enabled_and_refuses_what_it_must() {
    let dir = std::env::temp_dir().join(format!("w20-dmn-serve-{}", std::process::id()));
    let _ = std::fs::remove_dir_all(&dir);
    std::fs::create_dir_all(&dir).unwrap();

    let hub = Hub::new();
    let store: Arc<ConfigStore> = ConfigStore::open(
        hub.clone(),
        kurashi_schema::v1::registry(),
        Paths::rooted(&dir.join("config")),
        Options::default(),
    );
    let mut actions = ActionRegistry::default();
    wiring::ui(&hub, &mut actions);
    // The bundled manifest, and the dock linked with its directories under the scratch folder. The browser is the
    // system's, which no test here reaches: `file:` is refused before it is asked.
    let dock = Webdock::with(Dirs::rooted(&dir), Arc::new(SystemOpener));
    wiring::mods_native(
        &hub,
        &mut actions,
        vec![Path::new(env!("CARGO_MANIFEST_DIR")).join("../../mods")],
        Some(store.clone()),
        vec![Box::new(dock)],
        None,
    );

    // Off by default: nothing is served.
    assert!(
        hub.subscribe("mod.webdock").is_err(),
        "a disabled dock serves no document"
    );

    actions
        .invoke("mod.enable", json!({"id": "webdock"}))
        .await
        .expect("the bundled dock enables");
    let (_, doc) = hub.subscribe("mod.webdock").expect("served while enabled");
    assert_eq!(doc["available"], true);
    assert_eq!(doc["mode"], "hidden");
    assert_eq!(doc["size"], "phone");
    assert_eq!(
        doc["host"],
        json!({"state": "off"}),
        "no host runs until a site opens"
    );
    assert_eq!(doc["keep"], json!([]));
    assert_eq!(
        doc["geometry"]["width"], 412,
        "the manifest's default width"
    );
    assert_eq!(doc["geometry"]["large"], 90);
    assert_eq!(doc["pins"], json!([]));

    assert_eq!(
        actions.invoke("webdock.open", json!({"pin": "nope"})).await,
        Err(ActionError::Invalid("webdock.error.unknown_pin".into()))
    );
    assert_eq!(
        actions
            .invoke(
                "webdock.open_external",
                json!({"url": "file:///etc/passwd"})
            )
            .await,
        Err(ActionError::Invalid("webdock.error.url".into()))
    );
    assert_eq!(
        actions
            .invoke("webdock.size", json!({"size": "huge"}))
            .await,
        Err(ActionError::Invalid("webdock.error.size".into()))
    );
    actions.invoke("webdock.size", json!({})).await.unwrap();
    // The service publishes from its own task: the document follows once that task has run.
    let mut size = String::new();
    for _ in 0..200 {
        let (_, doc) = hub.snapshot("mod.webdock").unwrap();
        size = doc["size"].as_str().unwrap_or_default().to_string();
        if size == "large" {
            break;
        }
        tokio::time::sleep(std::time::Duration::from_millis(10)).await;
    }
    assert_eq!(size, "large", "no argument toggles the size");

    actions
        .invoke("mod.disable", json!({"id": "webdock"}))
        .await
        .unwrap();
    assert!(
        hub.subscribe("mod.webdock").is_err(),
        "a disabled dock serves no document again"
    );
}
