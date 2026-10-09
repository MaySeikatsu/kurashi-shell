//! Probe a real (headless sway) compositor. Skips unless pointed at a kurashi sandbox, so it
//! can never touch the user's live session.

use kurashid::{Hub, capabilities, config::ConfigStore};

fn sandbox() -> bool {
    std::env::var("XDG_RUNTIME_DIR").is_ok_and(|r| r.starts_with("/tmp/kurashi-sb-"))
        && std::env::var_os("WAYLAND_DISPLAY").is_some()
}

#[test]
fn sandbox_sway_has_no_blur_so_it_is_forced_off() {
    if !sandbox() {
        eprintln!("SKIP: no sandbox (eval `tools/bench/sandbox.sh start` first)");
        return;
    }
    let root = std::env::temp_dir().join(format!("kurashid-caps-sb-{}", std::process::id()));
    std::fs::create_dir_all(&root).unwrap();
    let hub = Hub::new();
    let store = ConfigStore::open(
        hub.clone(),
        kurashi_schema::v1::registry(),
        kurashi_config::Paths::rooted(&root),
        kurashi_config::Options::default(),
    );
    let caps = capabilities::probe_and_apply(&store, &hub);
    assert!(
        caps.contains("layer_shell"),
        "sway offers layer-shell: {caps:?}"
    );
    assert!(
        !caps.contains("blur"),
        "sway has no ext-background-effect: {caps:?}"
    );
    let p = store.get("theme.material.blur", None).unwrap();
    assert_eq!(p.value, serde_json::json!(false));
    assert_eq!(p.reason.as_deref(), Some("settings.inert.capability"));
}
