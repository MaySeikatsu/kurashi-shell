//! The web dock through the daemon (K38, MODS.md "Web dock"), with the bundled manifest (`mods/webdock/mod.toml`) and
//! the dock's own directories redirected into a scratch folder. What needs a site (a pin: a site starts the host, a
//! view does not, the idle clock, disable) waits for the `pins` records setting (W17-records), which this manifest
//! does not carry yet: that logic is covered by crates/kurashi-mod-webdock/tests/behaviour.rs with a recording
//! host, and the host's start, stop and restarts by tests/hosts.rs.

use std::path::Path;
use std::sync::Arc;

use kurashi_config::{Options, Paths};
use kurashi_mod_webdock::{Dirs, SystemOpener, Webdock};
use kurashid::config::ConfigStore;
use kurashid::{ActionError, ActionRegistry, Hub, wiring};
use serde_json::json;

#[tokio::test]
async fn the_dock_serves_its_document_once_enabled_and_refuses_what_it_must() {
    let dir = std::env::temp_dir().join(format!("kurashid-webdock-{}", std::process::id()));
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
