//! Mod lists as config (K25, MODS "States, persistence and Settings"): `mod.load/unload/enable/
//! disable` are config writes on `mods.loaded` / `mods.enabled`, the registry follows the lists,
//! the `mods` document and the settings pages follow the registry, and all of it survives a
//! restart (B11). Drives the daemon's wiring over a scratch config root, no socket.

use std::path::{Path, PathBuf};
use std::sync::Arc;
use std::sync::atomic::{AtomicUsize, Ordering};

use kurashi_config::{Options, Paths};
use kurashi_ipc::ApplyOp;
use kurashid::config::ConfigStore;
use kurashid::{ActionError, ActionRegistry, Hub, wiring};
use serde_json::{Value, json};

/// The bundled mods (nothing is on by default, K33). `easter-eggs` declares daemon code this test build does not link,
/// so it is not offered at all (B15, I281): the lifecycle tests switch on `plain` from [`vehicle`] instead.
fn bundled() -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../../mods")
}

/// An empty directory for one test: its config root, or a directory of extra mods.
fn scratch(tag: &str) -> PathBuf {
    static N: AtomicUsize = AtomicUsize::new(0);
    let n = N.fetch_add(1, Ordering::SeqCst);
    let root = std::env::temp_dir().join(format!("kurashid-mods-{tag}-{}-{n}", std::process::id()));
    let _ = std::fs::remove_dir_all(&root);
    std::fs::create_dir_all(&root).unwrap();
    root
}

/// A directory of extra mods holding `plain`, a mod with a frontend-only provide: enabling it needs
/// no daemon code, so it can be switched on in the lifecycle tests.
fn vehicle(tag: &str) -> PathBuf {
    let dir = scratch(tag);
    write(
        &dir.join("plain/mod.toml"),
        "id = \"plain\"\nname = \"Plain\"\nversion = \"0.1.0\"\ntier = \"native\"\n\
         kurashi = \">=0.0.1\"\nprovides = [\"widget:plain\"]\n",
    );
    dir
}

/// A daemon's mod side over `root`: the store, the hub and the actions, as `main` wires them.
struct Daemon {
    hub: Arc<Hub>,
    store: Arc<ConfigStore>,
    actions: ActionRegistry,
}

fn start(root: &Path, extra_roots: &[PathBuf]) -> Daemon {
    let hub = Hub::new();
    let store = ConfigStore::open(
        hub.clone(),
        kurashi_schema::v1::registry(),
        Paths::rooted(root),
        Options::default(),
    );
    let mut actions = ActionRegistry::default();
    let mut roots = vec![bundled()];
    roots.extend(extra_roots.iter().cloned());
    wiring::mods(&hub, &mut actions, roots, Some(store.clone()));
    Daemon {
        hub,
        store,
        actions,
    }
}

impl Daemon {
    async fn act(&self, action: &str, id: &str) -> Result<Option<Value>, ActionError> {
        self.actions.invoke(action, json!({ "id": id })).await
    }

    fn entry(&self, id: &str) -> Value {
        let (_, doc) = self.hub.snapshot("mods").unwrap();
        doc["mods"]
            .as_array()
            .unwrap()
            .iter()
            .find(|m| m["id"] == id)
            .cloned()
            .expect("listed in the mods document")
    }

    fn listed(&self, id: &str) -> bool {
        let (_, doc) = self.hub.snapshot("mods").unwrap();
        doc["mods"]
            .as_array()
            .unwrap()
            .iter()
            .any(|m| m["id"] == id)
    }

    fn state(&self, id: &str) -> String {
        self.entry(id)["state"].as_str().unwrap().to_string()
    }

    fn page(&self, id: &str) -> Option<Value> {
        let (_, doc) = self.hub.snapshot("schema.settings").unwrap();
        doc["pages"]
            .as_array()
            .unwrap()
            .iter()
            .find(|p| p["id"] == id)
            .cloned()
    }
}

fn write(path: &Path, text: &str) {
    std::fs::create_dir_all(path.parent().unwrap()).unwrap();
    std::fs::write(path, text).unwrap();
}

#[tokio::test]
async fn enable_is_a_config_write_that_undo_reverts_and_a_restart_keeps() {
    let root = scratch("persist");
    let extra = vehicle("persist-mods");
    let d = start(&root, std::slice::from_ref(&extra));
    // Nothing is on by default (K33); easter-eggs has no code in this build and is not offered (I281).
    assert!(!d.listed("easter-eggs"));
    assert!(d.store.string_list("mods.enabled").is_empty());
    assert_eq!(d.state("plain"), "available");
    assert!(d.page("mods.plain").is_none());

    // Loaded first (its own transaction), then on.
    d.act("mod.load", "plain").await.unwrap();
    d.act("mod.enable", "plain").await.unwrap();
    assert_eq!(d.store.string_list("mods.enabled"), ["plain"]);
    assert_eq!(d.state("plain"), "enabled");
    let page = d.page("mods.plain").expect("the loaded mod has its page");
    assert_eq!(page["mod"], "plain");
    assert_eq!(page["label"], "Plain");

    // Undo takes the enable back; the mod stays loaded, so it is off again.
    d.store.undo(false).unwrap();
    assert_eq!(d.state("plain"), "disabled");
    d.store.undo(true).unwrap();
    assert_eq!(d.state("plain"), "enabled");

    // A restart over the same directories starts with the mod on (B11).
    drop(d);
    let d = start(&root, std::slice::from_ref(&extra));
    assert_eq!(d.state("plain"), "enabled");
    assert!(d.page("mods.plain").is_some());
}

#[tokio::test]
async fn enabling_an_available_mod_loads_it_and_one_undo_takes_both_back() {
    let extra = vehicle("one-tx-mods");
    let d = start(&scratch("one-tx"), std::slice::from_ref(&extra));
    d.act("mod.enable", "plain").await.unwrap();
    assert_eq!(d.state("plain"), "enabled");
    assert_eq!(d.store.string_list("mods.loaded"), ["plain"]);
    d.store.undo(false).unwrap();
    assert_eq!(d.state("plain"), "available");
    assert!(d.page("mods.plain").is_none());
}

#[tokio::test]
async fn disable_keeps_the_mod_loaded_and_unload_takes_it_back_to_available() {
    let root = scratch("unload");
    let extra = vehicle("unload-mods");
    let d = start(&root, std::slice::from_ref(&extra));
    d.act("mod.enable", "plain").await.unwrap();
    d.act("mod.disable", "plain").await.unwrap();
    assert_eq!(d.state("plain"), "disabled");
    assert!(d.page("mods.plain").is_some(), "loaded, off keeps its page");
    assert_eq!(d.store.string_list("mods.loaded"), ["plain"]);
    d.act("mod.unload", "plain").await.unwrap();
    assert_eq!(d.state("plain"), "available");
    assert!(d.page("mods.plain").is_none());
    // Unloading the mod that is on takes it off as well.
    d.act("mod.enable", "plain").await.unwrap();
    d.act("mod.unload", "plain").await.unwrap();
    assert_eq!(d.state("plain"), "available");
    assert_eq!(d.store.string_list("mods.enabled"), Vec::<String>::new());
}

#[tokio::test]
async fn load_adds_a_page_with_no_rows_for_a_mod_without_settings() {
    let extra = scratch("plain-mods");
    write(
        &extra.join("plain/mod.toml"),
        "id = \"plain\"\nname = \"Plain\"\nversion = \"0.1.0\"\ntier = \"native\"\n\
         kurashi = \">=0.0.1\"\nprovides = [\"widget:plain\"]\n",
    );
    let d = start(&scratch("load"), &[extra]);
    assert_eq!(d.state("plain"), "available");
    d.act("mod.load", "plain").await.unwrap();
    assert_eq!(d.state("plain"), "disabled");
    let page = d
        .page("mods.plain")
        .expect("loaded: a page, settings or not");
    assert_eq!(page["label"], "Plain");
    assert_eq!(page["mod"], "plain");
    let rows: usize = page["sections"]
        .as_array()
        .unwrap()
        .iter()
        .map(|s| s["rows"].as_array().unwrap().len())
        .sum();
    assert_eq!(rows, 0);
    assert_eq!(
        d.act("mod.load", "nope").await,
        Err(ActionError::Invalid("mods.error.unknown_mod".into()))
    );
    d.act("mod.unload", "plain").await.unwrap();
    assert!(d.page("mods.plain").is_none());
}

#[tokio::test]
async fn forced_lists_refuse_the_mod_actions_and_write_nothing() {
    let root = scratch("forced");
    let paths = Paths::rooted(&root);
    write(
        &paths.managed_file(),
        "[_managed]\nenforce = true\n\n[mods]\nenabled = []\n",
    );
    let extra = vehicle("forced-mods");
    let d = start(&root, std::slice::from_ref(&extra));
    assert!(d.store.is_forced("mods.enabled"));
    let forced = Err(ActionError::Invalid("config.error.forced".into()));
    assert_eq!(d.act("mod.enable", "plain").await, forced);
    // The refused enable wrote no list: the loaded one is not touched either (empty by default).
    assert!(d.store.string_list("mods.loaded").is_empty());
    assert_eq!(d.state("plain"), "available");
}

#[tokio::test]
async fn a_file_edit_reconciles_the_registry() {
    let root = scratch("edit");
    let extra = vehicle("edit-mods");
    let d = start(&root, std::slice::from_ref(&extra));
    write(
        &Paths::rooted(&root).user_file(),
        "[mods]\nenabled = [\"plain\"]\n",
    );
    d.store.reload();
    // Enabled implies loaded (K25): plain is on; nothing else was loaded by default.
    assert_eq!(d.state("plain"), "enabled");
    assert!(!d.listed("easter-eggs"));
    assert!(d.page("mods.easter-eggs").is_none());
}

#[tokio::test]
async fn choices_come_from_the_daemon_and_a_value_outside_them_is_inert() {
    let d = start(&scratch("choices"), &[]);
    let row = |key: &str| -> Value {
        let (_, doc) = d.hub.snapshot("schema.settings").unwrap();
        doc["pages"]
            .as_array()
            .unwrap()
            .iter()
            .flat_map(|p| p["sections"].as_array().unwrap().clone())
            .flat_map(|s| s["rows"].as_array().unwrap().clone())
            .find(|r| r["key"] == key)
            .expect("the row is on a page")
    };
    let values = |r: &Value| -> Vec<String> {
        r["choices"]
            .as_array()
            .unwrap()
            .iter()
            .map(|c| c["value"].as_str().unwrap().to_string())
            .collect()
    };
    let palette = row("theme.colors.palette");
    assert_eq!(palette["choices_from"], "palettes");
    // Every bundled palette, in bundle order (W25 added the identity packs' palettes).
    assert_eq!(values(&palette), kurashi_theme::bundled_names());
    assert_eq!(
        values(&palette)[..5],
        ["wa-iro", "kanso", "high-contrast", "sekai", "sekai-night"]
    );

    // The island registers its faces after the store opened; the next change picks them up. The
    // OSD faces are not an option of the island's face list.
    d.hub.register(
        "runtime.island.main",
        json!({"faces": ["clock", "media", "notifications", "volume", "brightness"]}),
        None,
    );
    d.store
        .apply(&[ApplyOp::Set {
            set: "island.main.ttl".into(),
            value: json!(7),
            output: None,
        }])
        .unwrap();
    assert_eq!(
        values(&row("island.main.faces")),
        ["clock", "media", "notifications"]
    );

    // Never rejected: kept, and reported as not in effect (I9, K21).
    d.store
        .apply(&[ApplyOp::Set {
            set: "theme.colors.palette".into(),
            value: json!("from-a-mod"),
            output: None,
        }])
        .expect("accepted");
    let p = d.store.get("theme.colors.palette", None).unwrap();
    assert_eq!(p.value, json!("from-a-mod"));
    assert_eq!(p.reason.as_deref(), Some("settings.choice.unavailable"));
}
