//! The daemon side of the wallpaper mod (K26, K28): kurashid's mod wiring discovers the bundled
//! `mods/wallpaper/mod.toml`, `mod.enable wallpaper` registers `mod.wallpaper` and its actions, the
//! `mods` document names the picker, `runtime.slots` names the quick tile (not ready while the backend
//! is missing), and `mod.disable` takes everything back. No config store: the lists live in memory.

use std::path::{Path, PathBuf};
use std::sync::Arc;
use std::time::Duration;

use kurashi_mod_api::NativeMod;
use kurashi_mod_wallpaper::{Dirs, SystemExec, Wallpaper};
use kurashid::hub::UnknownDoc;
use kurashid::{ActionError, ActionRegistry, Hub, wiring};
use serde_json::{Value, json};

fn scratch(tag: &str) -> PathBuf {
    let dir = std::env::temp_dir().join(format!("kurashi-wp-wiring-{tag}-{}", std::process::id()));
    let _ = std::fs::remove_dir_all(&dir);
    std::fs::create_dir_all(&dir).unwrap();
    dir
}

/// A daemon's mod side with the bundled mods and the wallpaper linked over an empty PATH (so the
/// backend is missing, as on a machine without awww).
fn start(root: &Path) -> (Arc<Hub>, ActionRegistry) {
    let hub = Hub::new();
    let mut actions = ActionRegistry::default();
    let bundled = Path::new(env!("CARGO_MANIFEST_DIR")).join("../../mods");
    let exec = Arc::new(SystemExec::with(Vec::new(), Vec::new()));
    let linked: Vec<Box<dyn NativeMod>> = vec![Box::new(Wallpaper::with(exec, Dirs::rooted(root)))];
    wiring::mods_native(&hub, &mut actions, vec![bundled], None, linked, None);
    (hub, actions)
}

async fn eventually(mut check: impl FnMut() -> bool) {
    for _ in 0..500 {
        if check() {
            return;
        }
        tokio::time::sleep(Duration::from_millis(10)).await;
    }
    panic!("not reached within 5 s");
}

fn entry(hub: &Hub, id: &str) -> Value {
    let (_, doc) = hub.snapshot("mods").unwrap();
    doc["mods"]
        .as_array()
        .unwrap()
        .iter()
        .find(|m| m["id"] == id)
        .cloned()
        .expect("listed in the mods document")
}

#[tokio::test]
async fn the_bundled_manifest_is_listed_with_its_panel_file() {
    let root = scratch("listed");
    let (hub, _actions) = start(&root);
    let m = entry(&hub, "wallpaper");
    assert_eq!(m["state"], "available", "loaded, not on yet");
    assert_eq!(m["cost"], "low");
    assert_eq!(
        m["capabilities"],
        json!(["exec", "fs:scoped"]),
        "the declared capabilities are the validator's known ones"
    );
}

#[tokio::test]
async fn enable_registers_the_document_the_actions_and_the_slot_and_disable_takes_them_back() {
    let root = scratch("enable");
    let (hub, actions) = start(&root);
    actions
        .invoke("mod.enable", json!({"id": "wallpaper"}))
        .await
        .unwrap();

    let m = entry(&hub, "wallpaper");
    assert_eq!(m["state"], "enabled");
    assert_eq!(
        m["qml"]["panel:wallpaper"]
            .as_str()
            .map(|u| u.ends_with("mods/wallpaper/qml/Panel.qml")),
        Some(true),
        "the picker's file is named in the mods document"
    );
    assert_eq!(
        m["qml"]["slot:quick.tiles"]
            .as_str()
            .map(|u| u.ends_with("qml/slots/quick.tiles.qml")),
        Some(true),
        "the tile's file is named too"
    );

    // The document is served while subscribed; the backend is missing, which the document says.
    let (_, _) = hub
        .subscribe("mod.wallpaper")
        .expect("served while enabled");
    let h = hub.clone();
    eventually(|| h.snapshot("mod.wallpaper").unwrap().1["loaded"] == true).await;
    let (_, doc) = hub.snapshot("mod.wallpaper").unwrap();
    assert_eq!(
        doc["available"], false,
        "not installed: the quick tile is not ready"
    );
    assert_eq!(doc["backend"]["reason"], "mod-wallpaper.backend.missing");

    // The quick tile's slot lists the contribution, not ready (its primary document is unavailable).
    let (_, slots) = hub.snapshot("runtime.slots").unwrap();
    assert_eq!(slots["quick.tiles"][0]["mod"], "wallpaper");
    assert_eq!(slots["quick.tiles"][0]["ready"], false);

    // The actions answer with the reason, not as unknown actions.
    assert_eq!(
        actions.invoke("wallpaper.next", json!({})).await,
        Err(ActionError::Unavailable(
            "mod-wallpaper.backend.missing".into()
        ))
    );

    actions
        .invoke("mod.disable", json!({"id": "wallpaper"}))
        .await
        .unwrap();
    assert!(matches!(hub.subscribe("mod.wallpaper"), Err(UnknownDoc(_))));
    assert_eq!(
        actions.invoke("wallpaper.next", json!({})).await,
        Err(ActionError::Unknown("wallpaper.next".into()))
    );
    let (_, slots) = hub.snapshot("runtime.slots").unwrap();
    assert!(
        slots.get("quick.tiles").is_none(),
        "a disabled mod contributes nothing"
    );
}
