//! Mod settings as config keys (K22): `mods.<id>.<key>` goes through the same layers and
//! validation as core keys, keeps its value while its mod is off (inert, `mods.disabled`), and has
//! a settings page while the mod is loaded (K25). Drives `ConfigStore` directly, no socket.

use std::path::PathBuf;
use std::sync::Arc;
use std::sync::atomic::{AtomicUsize, Ordering};

use kurashi_config::{Options, Paths, Source};
use kurashi_ipc::{ApplyOp, OpError};
use kurashi_mods::Registry;
use kurashid::config::ConfigStore;
use kurashid::{ActionRegistry, Hub};
use semver::Version;
use serde_json::{Value, json};

const SEEK: &str = "mods.media.seek_step";

/// The bundled mods (`mods/`): `media` (off by default) and `easter-eggs` (on by default).
fn bundled() -> Registry {
    let version = Version::parse(env!("CARGO_PKG_VERSION")).unwrap();
    let dir = PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../../mods");
    Registry::discover(&[dir], &version)
}

/// A store over a fresh config dir. `user_toml` is written to `config.toml` before the store
/// opens, as a file from an earlier session would be.
fn open(user_toml: Option<&str>) -> (Arc<ConfigStore>, Arc<Hub>, Registry) {
    static N: AtomicUsize = AtomicUsize::new(0);
    let n = N.fetch_add(1, Ordering::SeqCst);
    let root = std::env::temp_dir().join(format!("kurashid-modset-{}-{n}", std::process::id()));
    let _ = std::fs::remove_dir_all(&root);
    let paths = Paths::rooted(&root);
    if let Some(text) = user_toml {
        std::fs::create_dir_all(&paths.config_dir).unwrap();
        std::fs::write(paths.user_file(), text).unwrap();
    }
    let hub = Hub::new();
    let store = ConfigStore::open(
        hub.clone(),
        kurashi_schema::v1::registry(),
        paths,
        Options::default(),
    );
    (store, hub, bundled())
}

/// Turns a mod on or off in the registry and publishes it, as the daemon's mod actions do.
fn turn(store: &ConfigStore, reg: &mut Registry, id: &str, on: bool) {
    if on {
        reg.enable(id).unwrap();
    } else {
        reg.disable(id).unwrap();
    }
    store.sync_mods(reg);
}

fn set(store: &ConfigStore, key: &str, value: Value) -> Result<(), Vec<OpError>> {
    store
        .apply(&[ApplyOp::Set {
            set: key.into(),
            value,
            output: None,
        }])
        .map(|_| ())
}

/// The rejection code of a value the daemon must refuse.
fn rejected(store: &ConfigStore, key: &str, value: Value) -> String {
    let errs = set(store, key, value).expect_err("the value is rejected");
    errs[0].code.clone()
}

/// The `schema.settings` page with this id, if the daemon serves one.
fn page(hub: &Hub, id: &str) -> Option<Value> {
    let (_, doc) = hub.snapshot("schema.settings").unwrap();
    doc["pages"]
        .as_array()
        .unwrap()
        .iter()
        .find(|p| p["id"] == id)
        .cloned()
}

/// The row of `key` on a settings page.
fn row(page: &Value, key: &str) -> Value {
    page["sections"]
        .as_array()
        .unwrap()
        .iter()
        .flat_map(|s| s["rows"].as_array().unwrap().iter())
        .find(|r| r["key"] == key)
        .expect("the row is on the page")
        .clone()
}

#[test]
fn stored_value_loads_once_its_mod_is_discovered() {
    let (store, hub, mut reg) = open(Some("[mods.media]\nseek_step = 7\n"));
    // Before discovery the key is unknown to the schema: nothing resolves.
    assert!(store.get(SEEK, None).is_none());
    store.sync_mods(&reg);
    // Media is off: the file's value is in effect in the config, but reported as having no effect.
    let p = store.get(SEEK, None).unwrap();
    assert_eq!(p.value, json!(7));
    assert_eq!(p.source, Source::User);
    assert_eq!(p.reason.as_deref(), Some("mods.disabled"));
    assert!(page(&hub, "mods.media").is_none());
    turn(&store, &mut reg, "media", true);
    let p = store.get(SEEK, None).unwrap();
    assert_eq!(
        (p.value, p.source, p.reason),
        (json!(7), Source::User, None)
    );
    assert!(page(&hub, "mods.media").is_some());
}

#[test]
fn set_get_and_explain_carry_provenance() {
    let (store, hub, mut reg) = open(None);
    turn(&store, &mut reg, "media", true);
    assert!(set(&store, SEEK, json!(10)).is_ok());
    let p = store.get(SEEK, None).unwrap();
    assert_eq!(
        (p.value, p.source, p.reason),
        (json!(10), Source::User, None)
    );
    let layers = store.explain(SEEK, None);
    assert!(
        layers
            .iter()
            .any(|l| l.source == Source::Default && l.value == json!(5))
    );
    let active: Vec<_> = layers.iter().filter(|l| l.active).collect();
    assert_eq!(active.len(), 1);
    assert_eq!(
        (active[0].source.clone(), active[0].value.clone()),
        (Source::User, json!(10))
    );
    // Undo takes the user value away: the default is in effect again.
    assert!(store.undo(false).is_ok());
    let p = store.get(SEEK, None).unwrap();
    assert_eq!((p.value, p.source), (json!(5), Source::Default));
    // The row carries the manifest's type, range and unit.
    let r = row(&page(&hub, "mods.media").unwrap(), SEEK);
    assert_eq!(r["control"], "slider");
    assert_eq!((r["min"].clone(), r["max"].clone()), (json!(1), json!(60)));
    assert_eq!(r["unit"], "s");
    assert_eq!(r["label"], "mods.media.seek_step");
    assert_eq!(r["help"], "mods.media.seek_step.help");
}

#[test]
fn values_outside_the_manifest_are_rejected() {
    let (store, _hub, mut reg) = open(None);
    turn(&store, &mut reg, "media", true);
    assert_eq!(
        rejected(&store, SEEK, json!(0)),
        "error.config.out_of_range"
    );
    assert_eq!(
        rejected(&store, SEEK, json!(61)),
        "error.config.out_of_range"
    );
    assert_eq!(
        rejected(&store, SEEK, json!("fast")),
        "error.config.wrong_type"
    );
    assert_eq!(
        rejected(&store, "mods.media.show_art", json!(1)),
        "error.config.wrong_type"
    );
    assert_eq!(
        rejected(&store, "mods.easter-eggs.frequency", json!("often")),
        "error.config.unknown_choice"
    );
    // The range is inclusive: both ends are valid.
    assert!(set(&store, SEEK, json!(1)).is_ok());
    assert!(set(&store, SEEK, json!(60)).is_ok());
    // A key the manifest does not declare is still an unknown key.
    assert_eq!(
        rejected(&store, "mods.media.nope", json!(1)),
        "config.diag.unknown_key"
    );
    assert_eq!(
        rejected(&store, "mods.nope.seek_step", json!(1)),
        "config.diag.unknown_key"
    );
    // A rejected batch changes nothing.
    assert_eq!(store.get(SEEK, None).unwrap().value, json!(60));
}

#[test]
fn disabled_mod_keeps_its_value_and_reports_why_it_is_inert() {
    let (store, hub, mut reg) = open(None);
    turn(&store, &mut reg, "media", true);
    assert!(set(&store, SEEK, json!(20)).is_ok());
    turn(&store, &mut reg, "media", false);
    let p = store.get(SEEK, None).unwrap();
    assert_eq!((p.value, p.source), (json!(20), Source::User));
    assert_eq!(p.reason.as_deref(), Some("mods.disabled"));
    assert_eq!(p.inert_by, None);
    // The config document says the same as cfg.get. The mod is still loaded, so its page stays.
    let (_, doc) = hub.snapshot("config").unwrap();
    assert_eq!(doc["values"][SEEK]["reason"], "mods.disabled");
    assert!(page(&hub, "mods.media").is_some());
    // Turning it back on makes the value effective again, with no reason.
    turn(&store, &mut reg, "media", true);
    let p = store.get(SEEK, None).unwrap();
    assert_eq!((p.value, p.reason), (json!(20), None));
}

#[test]
fn settings_pages_exist_for_loaded_mods() {
    let (store, hub, mut reg) = open(None);
    // Discovery alone loads nothing (the mods lists decide that, K25).
    store.sync_mods(&reg);
    assert!(page(&hub, "mods.easter-eggs").is_none());
    assert!(page(&hub, "mods.media").is_none());
    turn(&store, &mut reg, "easter-eggs", true);
    turn(&store, &mut reg, "media", true);
    let media = page(&hub, "mods.media").expect("media page");
    assert_eq!(media["label"], "Media");
    assert_eq!(row(&media, "mods.media.show_art")["control"], "toggle");
    let eggs = page(&hub, "mods.easter-eggs").expect("easter-eggs page");
    assert_eq!(eggs["label"], "Easter eggs");
    let freq = row(&eggs, "mods.easter-eggs.frequency");
    assert_eq!(freq["control"], "select");
    assert_eq!(
        freq["choices"],
        json!([
            {"value": "rare", "label": "mods.easter-eggs.frequency.rare"},
            {"value": "sometimes", "label": "mods.easter-eggs.frequency.sometimes"},
        ])
    );
    // Off but loaded keeps its page (the switch is there); unloaded loses it.
    turn(&store, &mut reg, "media", false);
    assert!(page(&hub, "mods.media").is_some());
    reg.unload("media").unwrap();
    store.sync_mods(&reg);
    assert!(page(&hub, "mods.media").is_none());
    assert!(page(&hub, "mods.easter-eggs").is_some());
}

/// Profiles snapshot mod values under the `mods` section (the first key segment, as for every key)
/// and load them with their source, the same as core keys.
#[tokio::test]
async fn profiles_carry_mod_values_with_their_source() {
    let (store, _hub, mut reg) = open(None);
    turn(&store, &mut reg, "media", true);
    assert!(set(&store, SEEK, json!(12)).is_ok());
    let mut actions = ActionRegistry::default();
    store.register_actions(&mut actions);
    let saved = json!({"name": "mine", "sections": ["mods"]});
    actions.invoke("profile.save", saved).await.unwrap();
    let reset = ApplyOp::Reset {
        reset: "mods".into(),
        output: None,
    };
    assert!(store.apply(&[reset]).is_ok());
    assert_eq!(store.get(SEEK, None).unwrap().value, json!(5));
    let loaded = json!({"name": "mine", "sections": ["mods"]});
    actions.invoke("profile.load", loaded).await.unwrap();
    let p = store.get(SEEK, None).unwrap();
    assert_eq!(
        (p.value, p.source),
        (json!(12), Source::Profile("mine".into()))
    );
}
