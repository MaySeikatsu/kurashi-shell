//! `runtime.layout` (K71, PROTOCOL §3.1) as kurashid publishes it — computed when first watched, followed on config,
//! theme and output changes — and the layout actions: `layout.toggle` (`runtime.ui.shown`), `layout.bar.move` (one
//! undoable change) and the `actions` query `kurashi act --list` prints.

use std::sync::Arc;
use std::sync::atomic::{AtomicUsize, Ordering};
use std::time::{Duration, Instant};

use kurashi_config::{Options, Paths};
use kurashi_ipc::ApplyOp;
use kurashid::config::ConfigStore;
use kurashid::{ActionError, ActionRegistry, Daemon, Hub, Intents};
use serde_json::{Value, json};

fn open() -> (
    Arc<ConfigStore>,
    Arc<Hub>,
    ActionRegistry,
    std::path::PathBuf,
) {
    static N: AtomicUsize = AtomicUsize::new(0);
    let n = N.fetch_add(1, Ordering::SeqCst);
    let root = std::env::temp_dir().join(format!("kurashid-layout-{}-{n}", std::process::id()));
    let _ = std::fs::remove_dir_all(&root);
    let hub = Hub::new();
    let store = ConfigStore::open(
        hub.clone(),
        kurashi_schema::v1::registry(),
        Paths::rooted(&root),
        Options::default(),
    );
    let mut actions = ActionRegistry::default();
    kurashid::wiring::ui(&hub, &mut actions);
    store.register_actions(&mut actions);
    (store, hub, actions, root)
}

fn layout(hub: &Hub) -> Value {
    hub.snapshot("runtime.layout").expect("runtime.layout").1
}

async fn eventually(hub: &Hub, what: &str, pred: impl Fn(&Value) -> bool) {
    let until = Instant::now() + Duration::from_secs(2);
    while !pred(&layout(hub)) {
        assert!(Instant::now() < until, "{what}: {}", layout(hub));
        tokio::time::sleep(Duration::from_millis(10)).await;
    }
}

fn set(key: &str, value: Value, output: Option<&str>) -> ApplyOp {
    ApplyOp::Set {
        set: key.into(),
        value,
        output: output.map(str::to_owned),
    }
}

#[tokio::test]
async fn the_layout_follows_the_config_the_theme_and_the_outputs() {
    let (store, hub, _actions, root) = open();
    let (_, first) = hub.subscribe("runtime.layout").unwrap();
    // The defaults: one dynamic top bar holding its edge, today's modules in its zones, no frame.
    let top = &first["outputs"]["*"]["edges"]["top"];
    assert_eq!(top["bar"], true);
    assert_eq!(top["holder"], "bar");
    assert_eq!(top["reserve"], 32);
    assert_eq!(
        top["zones"]["center"],
        json!([{"id": "island", "kind": "core"}])
    );
    assert_eq!(first["outputs"]["*"]["frame"]["on"], false);
    assert_eq!(first["draw"], "dynamic");
    assert_eq!(
        first["outputs"]["*"]["sidebars"]["right"]["reserve_reason"],
        "layout.reserve.hidden"
    );

    // A value: the frame on one output.
    store
        .apply(&[set("layout.frame.enabled", json!(true), Some("DP-1"))])
        .unwrap();
    eventually(&hub, "the frame on DP-1", |d| {
        d["outputs"]["DP-1"]["frame"]["on"] == true && d["outputs"]["*"]["frame"]["on"] == false
    })
    .await;

    // The tokens: the theme's gap and join radius.
    hub.register(
        "theme",
        json!({"tokens": {"space.sm": 8, "radius.lg": 16}}),
        None,
    );
    hub.set(
        "theme",
        json!({"tokens": {"space.sm": 6, "radius.lg": 12}}),
        None,
    )
    .unwrap();
    eventually(&hub, "the theme's tokens", |d| {
        d["gap"] == 6 && d["join_radius"] == 12
    })
    .await;

    // An output the compositor reports.
    hub.register("svc.workspaces", json!({"outputs": {}}), None);
    hub.set(
        "svc.workspaces",
        json!({"outputs": {"HDMI-A-1": [{"id": 1, "idx": 1, "focused": true, "occupied": false}]}}),
        None,
    )
    .unwrap();
    eventually(&hub, "the new output", |d| {
        d["outputs"].get("HDMI-A-1").is_some()
    })
    .await;

    // A mod's glance: listed by `mods` where the top bar's zones name it.
    hub.register(
        "mods",
        json!({"mods": [{"id": "sysmon", "state": "enabled", "provides": ["widget:sysmon", "peek:sysmon"]}]}),
        None,
    );
    hub.set(
        "mods",
        json!({"mods": [{"id": "sysmon", "state": "enabled", "provides": ["widget:sysmon"]}]}),
        None,
    )
    .unwrap();
    eventually(&hub, "the mod widget", |d| {
        d["outputs"]["*"]["edges"]["top"]["zones"]["end"][1]["id"] == "mod:sysmon:sysmon"
    })
    .await;
    hub.unsubscribe("runtime.layout");
    let _ = std::fs::remove_dir_all(&root);
}

#[tokio::test]
async fn layout_toggle_brings_a_target_out_and_puts_it_away() {
    let (store, hub, actions, root) = open();
    let shown = || hub.snapshot("runtime.ui").unwrap().1.get("shown").cloned();
    actions
        .invoke(
            "layout.toggle",
            json!({"target": "bar:top", "output": "DP-1"}),
        )
        .await
        .unwrap();
    assert_eq!(shown(), Some(json!(["bar:top@DP-1"])));
    actions
        .invoke(
            "layout.toggle",
            json!({"target": "bar:top", "output": "DP-1"}),
        )
        .await
        .unwrap();
    assert_eq!(shown(), None, "the same toggle puts it away");

    // Targets that are not on that output.
    for target in ["bar:bottom", "dock", "module:bottom:center"] {
        assert_eq!(
            actions
                .invoke("layout.toggle", json!({"target": target, "output": "DP-1"}))
                .await,
            Err(ActionError::Invalid("layout.error.target".into())),
            "{target}"
        );
    }
    for bad in [
        json!({}),
        json!({"target": "bar:middle"}),
        json!({"target": "nope"}),
    ] {
        assert_eq!(
            actions.invoke("layout.toggle", bad.clone()).await,
            Err(ActionError::Invalid("error.args.invalid".into())),
            "{bad}"
        );
    }
    // A module group of an edge without a bar, on the focused output (svc.workspaces says which).
    store
        .apply(&[set("edges.bottom.center", json!(["clock"]), None)])
        .unwrap();
    hub.register(
        "svc.workspaces",
        json!({"outputs": {"DP-1": [{"id": 1, "focused": false}], "DP-2": [{"id": 2, "focused": true}]}}),
        None,
    );
    actions
        .invoke("layout.toggle", json!({"target": "module:bottom:center"}))
        .await
        .unwrap();
    assert_eq!(shown(), Some(json!(["module:bottom:center@DP-2"])));
    // ui.close (and Esc, which sends it) takes every entry.
    actions.invoke("ui.close", json!({})).await.unwrap();
    assert_eq!(shown(), None);
    let _ = std::fs::remove_dir_all(&root);
}

#[tokio::test]
async fn layout_bar_move_moves_the_bar_with_its_zones_in_one_undoable_change() {
    let (store, _hub, actions, root) = open();
    let v = |k: &str, o: Option<&str>| store.get(k, o).unwrap().value;
    let top_end = v("edges.top.end", None);
    let done = actions
        .invoke("layout.bar.move", json!({"from": "top", "to": "bottom"}))
        .await
        .unwrap()
        .expect("rev and undo");
    assert!(done["rev"].is_u64() && done["undo"].is_string(), "{done}");
    assert_eq!(v("edges.top.bar", None), json!(false));
    assert_eq!(v("edges.bottom.bar", None), json!(true));
    assert_eq!(v("edges.bottom.end", None), top_end);
    assert_eq!(v("edges.bottom.center", None), json!(["island"]));
    assert_eq!(v("edges.top.end", None), json!([]));

    assert_eq!(
        actions
            .invoke("layout.bar.move", json!({"from": "bottom", "to": "bottom"}))
            .await,
        Err(ActionError::Invalid("layout.error.edge_taken".into()))
    );
    assert_eq!(
        actions
            .invoke("layout.bar.move", json!({"from": "left", "to": "right"}))
            .await,
        Err(ActionError::Invalid("layout.error.target".into()))
    );
    // One undo puts the bar and every zone back.
    store.undo(false).unwrap();
    assert_eq!(v("edges.top.bar", None), json!(true));
    assert_eq!(v("edges.bottom.bar", None), json!(false));
    assert_eq!(v("edges.top.end", None), top_end);
    assert_eq!(v("edges.bottom.end", None), json!([]));

    // Per output.
    actions
        .invoke(
            "layout.bar.move",
            json!({"from": "top", "to": "left", "output": "DP-1"}),
        )
        .await
        .unwrap();
    assert_eq!(v("edges.left.bar", Some("DP-1")), json!(true));
    assert_eq!(v("edges.left.bar", None), json!(false));
    let _ = std::fs::remove_dir_all(&root);
}

#[tokio::test]
async fn layout_bar_move_keeps_the_modules_the_destination_edge_showed_on_their_own() {
    let (store, _hub, actions, root) = open();
    let v = |k: &str| store.get(k, None).unwrap().value;
    store
        .apply(&[ApplyOp::Set {
            set: "edges.bottom.end".into(),
            value: json!(["clock", "weather"]),
            output: None,
        }])
        .unwrap();
    let top_end: Vec<Value> = v("edges.top.end").as_array().unwrap().clone();
    actions
        .invoke("layout.bar.move", json!({"from": "top", "to": "bottom"}))
        .await
        .unwrap();
    // The bar's modules first; the edge's own after them, without a second clock.
    let mut want = top_end.clone();
    want.push(json!("weather"));
    assert!(top_end.contains(&json!("clock")));
    assert_eq!(v("edges.bottom.end"), Value::Array(want));
    let _ = std::fs::remove_dir_all(&root);
}

#[tokio::test]
async fn the_actions_query_lists_the_layout_actions() {
    let (_store, hub, actions, root) = open();
    let daemon = Daemon::new(hub, actions, Intents::default());
    let q = daemon
        .queries
        .get("actions")
        .expect("the actions query")
        .clone();
    let items = q("layout.");
    let ids: Vec<&str> = items.iter().filter_map(|i| i["id"].as_str()).collect();
    assert_eq!(ids, ["layout.bar.move", "layout.toggle"]);
    assert_eq!(items[1]["args"], "{target, output?}");
    assert!(items[1]["help"].as_str().is_some_and(|h| !h.is_empty()));
    assert!(q("").len() > 10, "every action is listed");
    let _ = std::fs::remove_dir_all(&root);
}

/// Row 486: `layout.toggle {target: "sidebar:<side>"}` is `sidebar.toggle` — one truth, `runtime.ui.sidebar` (and
/// `sidebar_output` when an output is named), no `shown` entry; the same toggle closes it, as `sidebar.close` does.
#[tokio::test]
async fn layout_toggle_of_a_sidebar_drives_sidebar_toggle() {
    let (_store, hub, actions, root) = open();
    let ui = || hub.snapshot("runtime.ui").unwrap().1;
    actions
        .invoke(
            "layout.toggle",
            json!({"target": "sidebar:right", "output": "DP-1"}),
        )
        .await
        .unwrap();
    assert_eq!(ui()["sidebar"], json!("right"));
    assert_eq!(ui()["sidebar_output"], json!("DP-1"));
    assert_eq!(ui().get("shown"), None, "a sidebar is never a shown entry");
    // The same toggle closes it; without an output it opens on the frontend's focused one (no sidebar_output).
    actions
        .invoke(
            "layout.toggle",
            json!({"target": "sidebar:right", "output": "DP-1"}),
        )
        .await
        .unwrap();
    assert_eq!(ui().get("sidebar"), None);
    actions
        .invoke("layout.toggle", json!({"target": "sidebar:right"}))
        .await
        .unwrap();
    assert_eq!(ui()["sidebar"], json!("right"));
    assert_eq!(ui().get("sidebar_output"), None);
    // One at a time with the launcher, and sidebar.close closes what layout.toggle opened.
    actions.invoke("launcher.toggle", json!({})).await.unwrap();
    assert_eq!(ui().get("sidebar"), None, "the launcher closes it");
    actions
        .invoke("layout.toggle", json!({"target": "sidebar:right"}))
        .await
        .unwrap();
    assert_eq!(ui()["launcher"], json!(false), "and it closes the launcher");
    actions.invoke("sidebar.close", json!({})).await.unwrap();
    assert_eq!(ui().get("sidebar"), None);
    // An unknown side is refused like any bad target.
    assert_eq!(
        actions
            .invoke("layout.toggle", json!({"target": "sidebar:middle"}))
            .await,
        Err(ActionError::Invalid("error.args.invalid".into()))
    );
    let _ = std::fs::remove_dir_all(&root);
}
