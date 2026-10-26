//! Schema v3 (K71): `v2_to_v3` on a v2 file with every renamed key and `[outputs.*]` tables gives the golden v3 file,
//! the values in effect are the same in effect (what the bar, the dock, the sidebars and the desk show), and a file
//! already in the new shape — Home-Manager's `managed.toml` has no `schema_version`, so it runs every migration — keeps
//! what it says. Regenerate the golden with `UPDATE_GOLDEN=1`.

use std::path::PathBuf;
use std::sync::Arc;
use std::sync::atomic::{AtomicUsize, Ordering};

use kurashi_config::{Options, Paths};
use kurashid::Hub;
use kurashid::config::ConfigStore;
use serde_json::{Value, json};

const V2: &str = r#"schema_version = 2

# The user's bar sits on the left.
[bar]
edge = "left"
height = 36

[dock]
enabled = true
autohide = false
icon_size = 40

[sidebar]
style = "floating"
width = 500
right = ["header", "calendar"]
left = ["mod:tasks:tasks"]
bar_buttons = false
from_bar = true

[desktop]
enabled = true
side = "right"
order = ["calendar", "clock"]

[outputs."DP-1".bar]
edge = "bottom"

[outputs."HDMI-A-1".bar]
enabled = false

[outputs."HDMI-A-1".desktop]
side = "left"
"#;

fn root() -> PathBuf {
    static N: AtomicUsize = AtomicUsize::new(0);
    let n = N.fetch_add(1, Ordering::SeqCst);
    let root = std::env::temp_dir().join(format!("kurashid-mig3-{}-{n}", std::process::id()));
    let _ = std::fs::remove_dir_all(&root);
    std::fs::create_dir_all(root.join("config")).unwrap();
    root
}

fn open(root: &std::path::Path) -> Arc<ConfigStore> {
    ConfigStore::open(
        Hub::new(),
        kurashi_schema::v1::registry(),
        Paths::rooted(root),
        Options::default(),
    )
}

const EDGES: [&str; 4] = ["top", "bottom", "left", "right"];
const TOP: [&str; 12] = [
    "sidebar_left",
    "workspaces",
    "windows",
    "island",
    "volume",
    "mods",
    "recorder",
    "keyboard",
    "clock",
    "quick",
    "tray",
    "sidebar_right",
];

/// What the screen shows, as the frontend's readers derive it: the bar's edge and its modules, every module an edge
/// without a bar would show, the dock, the sidebars and the desk's order on its side.
#[derive(Debug, PartialEq)]
struct Effect {
    bar: Option<String>,
    bar_modules: Vec<String>,
    edge_modules: Vec<String>,
    height: u64,
    dock_always: bool,
    sidebar_floating: bool,
    widths: (u64, u64),
    right: Vec<String>,
    left: Vec<String>,
    desk: Vec<String>,
}

fn strings(v: &Value) -> Vec<String> {
    v.as_array()
        .into_iter()
        .flatten()
        .filter_map(Value::as_str)
        .map(str::to_owned)
        .collect()
}

/// v2's meaning, read from the v2 file itself (an output's value wins over the global one).
fn effect_v2(output: Option<&str>) -> Effect {
    let doc: toml::Value = toml::from_str(V2).unwrap();
    let doc = serde_json::to_value(doc).unwrap();
    let pick = |path: &[&str]| -> Value {
        let walk = |mut v: &Value| {
            for p in path {
                v = &v[*p];
            }
            v.clone()
        };
        let own = output.map(|o| walk(&doc["outputs"][o])).unwrap_or(Value::Null);
        if own.is_null() { walk(&doc) } else { own }
    };
    let enabled = pick(&["bar", "enabled"]).as_bool().unwrap_or(true);
    let edge = pick(&["bar", "edge"]).as_str().unwrap_or("top").to_owned();
    let buttons = pick(&["sidebar", "bar_buttons"]).as_bool().unwrap_or(true);
    let side = pick(&["desktop", "side"]).as_str().unwrap_or("right").to_owned();
    let _ = side;
    Effect {
        bar: enabled.then(|| edge.clone()),
        bar_modules: if enabled {
            TOP.iter()
                .filter(|m| buttons || !m.starts_with("sidebar_"))
                .map(|m| (*m).to_owned())
                .collect()
        } else {
            Vec::new()
        },
        edge_modules: Vec::new(),
        height: pick(&["bar", "height"]).as_u64().unwrap_or(32),
        dock_always: pick(&["dock", "autohide"]).as_bool() == Some(false),
        sidebar_floating: pick(&["sidebar", "style"]).as_str() == Some("floating"),
        widths: {
            let w = pick(&["sidebar", "width"]).as_u64().unwrap_or(420);
            (w, w)
        },
        right: strings(&pick(&["sidebar", "right"])),
        left: strings(&pick(&["sidebar", "left"])),
        desk: strings(&pick(&["desktop", "order"])),
    }
}

/// v3's meaning, from the store's values in effect (BarConfig.qml: the first edge with a bar is the bar).
fn effect_v3(store: &ConfigStore, output: Option<&str>) -> Effect {
    let v = |k: &str| store.get(k, output).map(|p| p.value).unwrap_or(Value::Null);
    let zones = |e: &str| -> Vec<String> {
        ["start", "center", "end"]
            .iter()
            .flat_map(|z| strings(&v(&format!("edges.{e}.{z}"))))
            .collect()
    };
    let bar = EDGES
        .iter()
        .find(|e| v(&format!("edges.{e}.bar")) == json!(true))
        .map(|e| (*e).to_owned());
    let side = v("desktop.side").as_str().unwrap_or("right").to_owned();
    Effect {
        bar_modules: bar.as_deref().map(zones).unwrap_or_default(),
        edge_modules: EDGES
            .iter()
            .filter(|e| Some(**e) != bar.as_deref())
            .flat_map(|e| zones(e))
            .collect(),
        bar,
        height: v("bar.height").as_u64().unwrap(),
        dock_always: v("dock.visibility") == json!("always"),
        sidebar_floating: v("sidebar.right.draw") == json!("floating")
            && v("sidebar.left.draw") == json!("floating"),
        widths: (
            v("sidebar.right.width").as_u64().unwrap(),
            v("sidebar.left.width").as_u64().unwrap(),
        ),
        right: strings(&v("sidebar.right.sections")),
        left: strings(&v("sidebar.left.sections")),
        desk: strings(&v(&format!("desktop.{side}"))),
    }
}

#[test]
fn a_v2_file_migrates_to_the_golden_v3_file_with_the_same_effect() {
    let root = root();
    let paths = Paths::rooted(&root);
    std::fs::write(paths.user_file(), V2).unwrap();
    let store = open(&root);
    assert!(
        store.diagnostics().is_empty(),
        "the migrated file reads clean: {:?}",
        store.diagnostics()
    );

    let migrated = std::fs::read_to_string(paths.user_file()).unwrap();
    let golden = std::path::Path::new(env!("CARGO_MANIFEST_DIR")).join("tests/golden/migrated_v3.toml");
    if std::env::var_os("UPDATE_GOLDEN").is_some() {
        std::fs::write(&golden, &migrated).unwrap();
    }
    assert_eq!(
        migrated,
        std::fs::read_to_string(&golden).expect("golden (UPDATE_GOLDEN=1 writes it)"),
        "migrated config.toml differs from the golden"
    );
    // The v2 bytes are kept beside it.
    let backup = paths.user_file().with_file_name("config.toml.bak-v2");
    assert_eq!(std::fs::read_to_string(backup).unwrap(), V2);

    for output in [None, Some("DP-1"), Some("HDMI-A-1")] {
        assert_eq!(effect_v3(&store, output), effect_v2(output), "{output:?}");
    }
    // The desk on HDMI-A-1 stands on the left: the order went to both lists.
    assert_eq!(
        effect_v3(&store, Some("HDMI-A-1")).desk,
        ["calendar", "clock"]
    );
    // Opening again changes nothing (the file is v3 now).
    drop(store);
    let again = open(&root);
    assert!(again.diagnostics().is_empty());
    assert_eq!(std::fs::read_to_string(paths.user_file()).unwrap(), migrated);
    let _ = std::fs::remove_dir_all(&root);
}

/// A file without `schema_version` that already says v3 (Home-Manager's `managed.toml`) keeps its values: `v2_to_v3`
/// leaves keys in the new shape alone, `sidebar.right` a table included.
#[test]
fn an_unversioned_file_in_the_new_shape_keeps_its_values() {
    let root = root();
    let paths = Paths::rooted(&root);
    std::fs::write(
        paths.managed_file(),
        r#"[edges.top]
bar = false
[edges.bottom]
bar = true
start = ["workspaces"]
end = ["clock", "tray"]
[dock]
enabled = true
visibility = "hover"
[sidebar.right]
sections = ["header"]
width = 480
draw = "connected"
[desktop]
left = ["clock"]
"#,
    )
    .unwrap();
    let store = open(&root);
    assert!(
        store.diagnostics().is_empty(),
        "{:?}",
        store.diagnostics()
    );
    let v = |k: &str| store.get(k, None).unwrap().value;
    assert_eq!(v("edges.top.bar"), json!(false));
    assert_eq!(v("edges.bottom.bar"), json!(true));
    assert_eq!(v("edges.bottom.start"), json!(["workspaces"]));
    assert_eq!(v("edges.bottom.end"), json!(["clock", "tray"]));
    // Not written by the file: the defaults.
    assert_eq!(v("edges.bottom.center"), json!([]));
    assert_eq!(v("edges.top.end").as_array().unwrap().len(), 8);
    assert_eq!(v("dock.visibility"), json!("hover"));
    assert_eq!(v("sidebar.right.sections"), json!(["header"]));
    assert_eq!(v("sidebar.right.width"), json!(480));
    assert_eq!(v("sidebar.right.draw"), json!("connected"));
    assert_eq!(v("sidebar.left.width"), json!(420));
    assert_eq!(v("desktop.left"), json!(["clock"]));
    // The managed file is the Nix layer: never rewritten.
    assert!(!std::fs::read_to_string(paths.managed_file()).unwrap().contains("schema_version"));
    let _ = std::fs::remove_dir_all(&root);
}

/// Mixed: an old key beside a new one of the same meaning — the new one is kept.
#[test]
fn an_old_key_never_overwrites_the_new_one() {
    let root = root();
    let paths = Paths::rooted(&root);
    std::fs::write(
        paths.user_file(),
        "[dock]\nautohide = false\nvisibility = \"hover\"\n[sidebar]\nwidth = 360\n[sidebar.right]\nwidth = 600\n",
    )
    .unwrap();
    let store = open(&root);
    assert!(store.diagnostics().is_empty(), "{:?}", store.diagnostics());
    let v = |k: &str| store.get(k, None).unwrap().value;
    assert_eq!(v("dock.visibility"), json!("hover"));
    assert_eq!(v("sidebar.right.width"), json!(600));
    assert_eq!(v("sidebar.left.width"), json!(360));
    let _ = std::fs::remove_dir_all(&root);
}

/// A bundled profile still written in v2 (`profiles/terminal-dense.toml`: `bar.edge = "bottom"`) loads as v3 in memory.
#[tokio::test]
async fn a_v2_profile_loads_as_v3() {
    let root = root();
    let profiles = root.join("bundled");
    std::fs::create_dir_all(&profiles).unwrap();
    std::fs::write(
        profiles.join("dense.toml"),
        "schema_version = 2\n[bar]\nedge = \"bottom\"\nheight = 28\n[dock]\nautohide = false\n",
    )
    .unwrap();
    let hub = Hub::new();
    let store = ConfigStore::open(
        hub,
        kurashi_schema::v1::registry(),
        Paths::rooted(&root),
        Options {
            bundled_profile_dirs: vec![profiles.clone()],
            migrations: kurashid::config::migrations(),
        },
    );
    let mut actions = kurashid::ActionRegistry::default();
    store.register_actions(&mut actions);
    actions
        .invoke("profile.load", json!({"name": "dense"}))
        .await
        .expect("the v2 profile loads");
    let v = |k: &str| store.get(k, None).unwrap().value;
    assert_eq!(v("edges.top.bar"), json!(false));
    assert_eq!(v("edges.bottom.bar"), json!(true));
    assert_eq!(v("edges.bottom.center"), json!(["island"]));
    assert_eq!(v("edges.top.center"), json!([]));
    assert_eq!(v("bar.height"), json!(28));
    assert_eq!(v("dock.visibility"), json!("always"));
    let _ = std::fs::remove_dir_all(&root);
}
