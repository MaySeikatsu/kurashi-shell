//! Native mods (K26, MODS.md "Native mods"): an enabled mod registers what its manifest provides
//! through a `ModCtx`; disabling drops every registration (documents get a final `{available:false}`
//! snapshot first); `running` follows the subscribers; a registration the manifest does not declare
//! is refused and the mod stays off. Drives the daemon's wiring over a scratch config root, no socket.

use std::path::{Path, PathBuf};
use std::sync::Arc;
use std::sync::atomic::{AtomicUsize, Ordering};
use std::time::Duration;

use kurashi_config::{Options, Paths};
use kurashi_ipc::{ApplyOp, ServerMsg};
use kurashi_mod_api::{ActionError as ModActionError, ModCtx, ModError, NativeMod};
use kurashi_mod_hello::Hello;
use kurashid::config::ConfigStore;
use kurashid::hub::UnknownDoc;
use kurashid::{ActionError, ActionRegistry, Hub, wiring};
use serde_json::{Value, json};
use tokio::sync::broadcast;

/// Registers an action its manifest declares, then one it does not.
struct Rogue;

impl NativeMod for Rogue {
    fn id(&self) -> &'static str {
        "rogue"
    }

    fn enable(&self, ctx: &mut ModCtx) -> Result<(), ModError> {
        ctx.action("rogue.ok", "action.rogue.ok", |_| async {
            Ok::<Option<Value>, ModActionError>(None)
        })?;
        ctx.action("rogue.secret", "action.rogue.secret", |_| async {
            Ok::<Option<Value>, ModActionError>(None)
        })?;
        Ok(())
    }
}

/// Registers an action the daemon already holds (`mod.enable`): it must be refused, and the daemon's
/// action must keep working.
struct Clash;

impl NativeMod for Clash {
    fn id(&self) -> &'static str {
        "clash"
    }

    fn enable(&self, ctx: &mut ModCtx) -> Result<(), ModError> {
        ctx.action("mod.enable", "action.mod.enable", |_| async {
            Ok::<Option<Value>, ModActionError>(None)
        })
    }
}

/// The bundled mods, then the test data (`hello`, not shipped), then any extra root.
fn roots(extra: &[PathBuf]) -> Vec<PathBuf> {
    let manifest = PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let mut roots = vec![
        manifest.join("../../mods"),
        manifest.join("tests/data/mods"),
    ];
    roots.extend(extra.iter().cloned());
    roots
}

/// An empty directory for one test: its config root, or a directory of extra mods.
fn scratch(tag: &str) -> PathBuf {
    static N: AtomicUsize = AtomicUsize::new(0);
    let n = N.fetch_add(1, Ordering::SeqCst);
    let root =
        std::env::temp_dir().join(format!("kurashid-native-{tag}-{}-{n}", std::process::id()));
    let _ = std::fs::remove_dir_all(&root);
    std::fs::create_dir_all(&root).unwrap();
    root
}

fn write(path: &Path, text: &str) {
    std::fs::create_dir_all(path.parent().unwrap()).unwrap();
    std::fs::write(path, text).unwrap();
}

/// A daemon's mod side over `root`, as `main` wires it, with the given native mods linked.
struct Daemon {
    hub: Arc<Hub>,
    store: Arc<ConfigStore>,
    actions: ActionRegistry,
}

fn start(root: &Path, extra: &[PathBuf], linked: Vec<Box<dyn NativeMod>>) -> Daemon {
    let hub = Hub::new();
    let store = ConfigStore::open(
        hub.clone(),
        kurashi_schema::v1::registry(),
        Paths::rooted(root),
        Options::default(),
    );
    let mut actions = ActionRegistry::default();
    wiring::mods_native(
        &hub,
        &mut actions,
        roots(extra),
        Some(store.clone()),
        linked,
    );
    Daemon {
        hub,
        store,
        actions,
    }
}

fn hello() -> Vec<Box<dyn NativeMod>> {
    vec![Box::new(Hello) as Box<dyn NativeMod>]
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

    fn state(&self, id: &str) -> String {
        self.entry(id)["state"].as_str().unwrap().to_string()
    }

    fn running(&self, id: &str) -> bool {
        self.entry(id)["running"] == true
    }
}

/// Polls until `check` holds: services publish from their own task, so a change lands a moment later.
async fn eventually(mut check: impl FnMut() -> bool) {
    for _ in 0..500 {
        if check() {
            return;
        }
        tokio::time::sleep(Duration::from_millis(10)).await;
    }
    panic!("not reached within 5 s");
}

/// The `snap` without an id that a document's removal sent, if any has been sent since.
fn final_snap(events: &mut broadcast::Receiver<Arc<ServerMsg>>, doc: &str) -> Option<Value> {
    let mut found = None;
    while let Ok(m) = events.try_recv() {
        if let ServerMsg::Snap {
            id: None,
            doc: d,
            data,
            ..
        } = &*m
            && d == doc
        {
            found = Some(data.clone());
        }
    }
    found
}

#[tokio::test]
async fn a_mod_that_is_off_registers_nothing() {
    let d = start(&scratch("off"), &[], hello());
    assert_eq!(d.state("hello"), "available");
    assert!(matches!(d.hub.subscribe("mod.hello"), Err(UnknownDoc(_))));
    assert_eq!(
        d.act("hello.ping", "").await,
        Err(ActionError::Unknown("hello.ping".into()))
    );
}

#[tokio::test]
async fn enable_serves_the_document_and_the_action_and_running_follows_the_subscriber() {
    let d = start(&scratch("on"), &[], hello());
    d.act("mod.enable", "hello").await.unwrap();
    assert_eq!(d.state("hello"), "enabled");

    let (_, data) = d.hub.subscribe("mod.hello").expect("served while enabled");
    assert_eq!(data, json!({"available": true, "greeting": "hi"}));
    assert!(d.running("hello"), "a subscriber runs the mod's service");

    assert_eq!(
        d.actions.invoke("hello.ping", json!({})).await,
        Ok(Some(json!({"pong": true})))
    );

    // The setting is read through the same store; a change reaches the document.
    d.store
        .apply(&[ApplyOp::Set {
            set: "mods.hello.greeting".into(),
            value: json!("yo"),
            output: None,
        }])
        .expect("a string setting of the mod");
    let hub = d.hub.clone();
    eventually(|| hub.snapshot("mod.hello").unwrap().1["greeting"] == "yo").await;

    d.hub.unsubscribe("mod.hello");
    assert!(!d.running("hello"), "the last subscriber leaving stops it");
}

#[tokio::test]
async fn disable_sends_a_final_snapshot_then_unknown_doc_and_unknown_action() {
    let d = start(&scratch("disable"), &[], hello());
    d.act("mod.enable", "hello").await.unwrap();
    d.hub.subscribe("mod.hello").unwrap();
    assert!(d.running("hello"));
    let mut events = d.hub.events();

    d.act("mod.disable", "hello").await.unwrap();
    assert_eq!(d.state("hello"), "disabled");
    assert!(
        !d.running("hello"),
        "the subscriber's service is gone with the document"
    );
    assert_eq!(
        final_snap(&mut events, "mod.hello"),
        Some(json!({"available": false}))
    );
    assert!(matches!(d.hub.subscribe("mod.hello"), Err(UnknownDoc(_))));
    assert_eq!(
        d.act("hello.ping", "").await,
        Err(ActionError::Unknown("hello.ping".into()))
    );
}

#[tokio::test]
async fn a_re_enabled_document_goes_on_with_a_later_revision() {
    let d = start(&scratch("rev"), &[], hello());
    d.act("mod.enable", "hello").await.unwrap();
    let (first, _) = d.hub.subscribe("mod.hello").unwrap();
    d.hub.unsubscribe("mod.hello");
    d.act("mod.disable", "hello").await.unwrap();
    d.act("mod.enable", "hello").await.unwrap();
    let (again, data) = d.hub.subscribe("mod.hello").unwrap();
    assert!(again > first, "rev {again} after {first}");
    assert_eq!(data, json!({"available": true, "greeting": "hi"}));
}

#[tokio::test]
async fn an_undeclared_registration_is_refused_and_the_mod_stays_off() {
    let extra = scratch("rogue-mods");
    write(
        &extra.join("rogue/mod.toml"),
        "id = \"rogue\"\nname = \"Rogue\"\nversion = \"0.1.0\"\ntier = \"native\"\n\
         kurashi = \">=0.0.1\"\nprovides = [\"action:rogue.ok\"]\n",
    );
    let d = start(
        &scratch("rogue"),
        std::slice::from_ref(&extra),
        vec![Box::new(Rogue) as Box<dyn NativeMod>],
    );
    assert_eq!(d.state("rogue"), "available");
    d.act("mod.enable", "rogue").await.unwrap();

    // Off, with the reason in the document; the declared action of the same enable is not made either.
    assert_eq!(d.state("rogue"), "disabled");
    let errors = d.entry("rogue")["errors"].clone();
    assert_eq!(errors[0]["key"], "mods.error.not_declared");
    assert_eq!(
        errors[0]["detail"],
        "action:rogue.secret is not declared in provides"
    );
    assert_eq!(
        d.act("rogue.ok", "").await,
        Err(ActionError::Unknown("rogue.ok".into()))
    );
}

#[tokio::test]
async fn a_registration_that_takes_a_held_id_is_refused_and_the_held_one_keeps_working() {
    let extra = scratch("clash-mods");
    write(
        &extra.join("clash/mod.toml"),
        "id = \"clash\"\nname = \"Clash\"\nversion = \"0.1.0\"\ntier = \"native\"\n\
         kurashi = \">=0.0.1\"\nprovides = [\"action:mod.enable\"]\n",
    );
    let linked = vec![
        Box::new(Clash) as Box<dyn NativeMod>,
        Box::new(Hello) as Box<dyn NativeMod>,
    ];
    let d = start(&scratch("clash"), std::slice::from_ref(&extra), linked);
    d.act("mod.enable", "clash").await.unwrap();
    assert_eq!(d.state("clash"), "disabled");
    assert_eq!(d.entry("clash")["errors"][0]["key"], "mods.error.duplicate");
    // The daemon's own `mod.enable` still answers, and turns on the mod it names, which serves.
    d.act("mod.enable", "hello").await.unwrap();
    assert_eq!(d.state("hello"), "enabled");
    assert!(d.hub.subscribe("mod.hello").is_ok());
}

#[tokio::test]
async fn an_enabled_native_mod_names_the_component_files_that_exist() {
    // A native mod's QML needs no linked code: the document lists the files its provides name.
    let extra = scratch("qml-mods");
    let dir = extra.join("panelmod");
    write(
        &dir.join("mod.toml"),
        "id = \"panelmod\"\nname = \"Panel mod\"\nversion = \"0.1.0\"\ntier = \"native\"\n\
         kurashi = \">=0.0.1\"\nprovides = [\"panel:main\", \"widget:gone\"]\n",
    );
    write(&dir.join("qml/Panel.qml"), "import QtQuick\n");
    let d = start(&scratch("qml"), std::slice::from_ref(&extra), Vec::new());
    d.act("mod.enable", "panelmod").await.unwrap();
    // Only the file that exists is listed: a URL to nothing is not in effect.
    assert_eq!(
        d.entry("panelmod")["qml"],
        json!({"panel:main": format!("file://{}/qml/Panel.qml", dir.display())})
    );
    d.act("mod.disable", "panelmod").await.unwrap();
    assert!(d.entry("panelmod").get("qml").is_none());
}
