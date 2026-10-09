//! Native mods (K26, MODS.md "Native mods"): an enabled mod registers what its manifest provides
//! through a `ModCtx`; disabling drops every registration (documents get a final `{available:false}`
//! snapshot first); `running` follows the subscribers; a registration the manifest does not declare
//! is refused and the mod stays off. Drives the daemon's wiring over a scratch config root, no socket.

use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicBool, AtomicUsize, Ordering};
use std::sync::{Arc, Mutex};
use std::time::Duration;

use kurashi_config::{Options, Paths};
use kurashi_ipc::{ApplyOp, ClientMsg, LineReader, ServerMsg, write_msg};
use kurashi_island::IslandConfig;
use kurashi_mod_api::{
    ActionError as ModActionError, Choice, ChoicesHandle, FaceHandle, FaceSpec, ModCtx, ModError,
    NativeMod,
};
use kurashi_mod_hello::Hello;
use kurashid::config::ConfigStore;
use kurashid::hub::UnknownDoc;
use kurashid::island::IslandHost;
use kurashid::{ActionError, ActionRegistry, Hub, wiring};
use serde_json::{Value, json};
use tokio::net::UnixStream;
use tokio::net::unix::{OwnedReadHalf, OwnedWriteHalf};
use tokio::sync::{broadcast, oneshot};

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
    // The island is built before the config is opened, as `main` does: the offers read its faces.
    let island = IslandHost::new(
        hub.clone(),
        "main",
        IslandConfig {
            faces: vec!["clock".into(), "media".into()],
            default: "clock".into(),
            ..Default::default()
        },
        &["clock", "media"],
    );
    let store = ConfigStore::open(
        hub.clone(),
        kurashi_schema::v1::registry(),
        Paths::rooted(root),
        Options::default(),
    );
    let mut actions = ActionRegistry::default();
    wiring::ui(&hub, &mut actions);
    wiring::mods_native(
        &hub,
        &mut actions,
        roots(extra),
        Some(store.clone()),
        linked,
        Some(island),
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

/// A client of the daemon's socket, as the frontend speaks it (PROTOCOL §2–§7).
struct Wire {
    rd: LineReader<OwnedReadHalf>,
    wr: OwnedWriteHalf,
}

impl Wire {
    async fn connect(path: &Path) -> Wire {
        let (rd, wr) = UnixStream::connect(path).await.unwrap().into_split();
        let mut w = Wire {
            rd: LineReader::new(rd),
            wr,
        };
        w.send(ClientMsg::Hello {
            v: 1,
            client: "test".into(),
            caps: vec![],
        })
        .await;
        assert!(matches!(w.recv().await, ServerMsg::Welcome { .. }));
        w
    }

    async fn send(&mut self, m: ClientMsg) {
        write_msg(&mut self.wr, &m).await.unwrap();
    }

    async fn recv(&mut self) -> ServerMsg {
        tokio::time::timeout(Duration::from_secs(2), self.rd.next_value())
            .await
            .expect("timed out waiting for the daemon")
            .unwrap()
            .expect("the daemon closed the connection")
    }

    /// The first message that matches; patches and other replies in between are skipped.
    async fn until(&mut self, what: impl Fn(&ServerMsg) -> bool) -> ServerMsg {
        loop {
            let m = self.recv().await;
            if what(&m) {
                return m;
            }
        }
    }

    async fn reply_to(&mut self, id: &str) -> ServerMsg {
        self.until(|m| match m {
            ServerMsg::Done { id: i, .. } | ServerMsg::Err { id: Some(i), .. } => i == id,
            ServerMsg::Snap { id: Some(i), .. } => i == id,
            _ => false,
        })
        .await
    }
}

#[tokio::test]
async fn over_the_socket_a_disabled_mod_answers_unknown_doc_and_unknown_action() {
    let d = start(&scratch("wire"), &[], hello());
    let path = scratch("sock").join("kurashid.sock");
    let mut daemon = kurashid::Daemon::new(
        d.hub.clone(),
        d.actions.clone(),
        kurashid::Intents::default(),
    );
    daemon.config = Some(d.store.clone());
    let (stop_tx, stop_rx) = oneshot::channel::<()>();
    let listener = tokio::net::UnixListener::bind(&path).unwrap();
    tokio::spawn(kurashid::server::serve(listener, Arc::new(daemon), async {
        let _ = stop_rx.await;
    }));
    let mut w = Wire::connect(&path).await;

    // Off: the document and the action are unknown.
    w.send(ClientMsg::Sub {
        id: "1".into(),
        doc: "mod.hello".into(),
    })
    .await;
    let ServerMsg::Err { kind, .. } = w.reply_to("1").await else {
        panic!("a disabled mod's document is not served");
    };
    assert_eq!(kind, "unknown_doc");
    w.send(ClientMsg::Act {
        id: "2".into(),
        action: "hello.ping".into(),
        args: json!({}),
    })
    .await;
    let ServerMsg::Err { kind, .. } = w.reply_to("2").await else {
        panic!("a disabled mod's action ran");
    };
    assert_eq!(kind, "unknown_action");

    // On: served, the action answers, and the mods document says the mod runs while subscribed.
    w.send(ClientMsg::Act {
        id: "3".into(),
        action: "mod.enable".into(),
        args: json!({"id": "hello"}),
    })
    .await;
    assert!(matches!(w.reply_to("3").await, ServerMsg::Done { .. }));
    w.send(ClientMsg::Sub {
        id: "4".into(),
        doc: "mod.hello".into(),
    })
    .await;
    let ServerMsg::Snap { data, .. } = w.reply_to("4").await else {
        panic!("an enabled mod serves its document");
    };
    assert_eq!(data, json!({"available": true, "greeting": "hi"}));
    w.send(ClientMsg::Act {
        id: "5".into(),
        action: "hello.ping".into(),
        args: json!({}),
    })
    .await;
    let ServerMsg::Done { data, .. } = w.reply_to("5").await else {
        panic!("hello.ping answers");
    };
    assert_eq!(data, Some(json!({"pong": true})));
    w.send(ClientMsg::Sub {
        id: "6".into(),
        doc: "mods".into(),
    })
    .await;
    let ServerMsg::Snap { data, .. } = w.reply_to("6").await else {
        panic!("the mods document is served");
    };
    let hello = data["mods"]
        .as_array()
        .unwrap()
        .iter()
        .find(|m| m["id"] == "hello")
        .unwrap();
    assert_eq!(hello["running"], true);

    // Disabled again while subscribed: the subscriber gets the final snapshot, then the same
    // errors as before, and nothing of the mod runs.
    w.send(ClientMsg::Act {
        id: "7".into(),
        action: "mod.disable".into(),
        args: json!({"id": "hello"}),
    })
    .await;
    // The reply and the final snapshot come in either order (replies go first when both are ready).
    let (mut done, mut fin) = (false, None);
    while !done || fin.is_none() {
        match w.recv().await {
            ServerMsg::Done { id, .. } if id == "7" => done = true,
            ServerMsg::Snap {
                id: None,
                doc,
                data,
                ..
            } if doc == "mod.hello" => fin = Some(data),
            _ => {}
        }
    }
    assert_eq!(fin, Some(json!({"available": false})));
    w.send(ClientMsg::Sub {
        id: "8".into(),
        doc: "mod.hello".into(),
    })
    .await;
    assert!(matches!(
        w.reply_to("8").await,
        ServerMsg::Err { kind, .. } if kind == "unknown_doc"
    ));
    w.send(ClientMsg::Act {
        id: "9".into(),
        action: "hello.ping".into(),
        args: json!({}),
    })
    .await;
    assert!(matches!(
        w.reply_to("9").await,
        ServerMsg::Err { kind, .. } if kind == "unknown_action"
    ));
    let _ = stop_tx.send(());
}

/// Keeps its face handle past the disable, to show a raise after it does nothing (K28).
struct Keeper(Arc<Mutex<Option<FaceHandle>>>);

impl NativeMod for Keeper {
    fn id(&self) -> &'static str {
        "keeper"
    }

    fn enable(&self, ctx: &mut ModCtx) -> Result<(), ModError> {
        let handle = ctx.face(
            "keeper",
            FaceSpec {
                transient: false,
                ttl_s: 0,
            },
        )?;
        *self.0.lock().unwrap() = Some(handle);
        Ok(())
    }
}

/// Offers the options it holds, and keeps the handle that says when they changed (K28 (3)).
struct Shifty(Arc<Mutex<Vec<String>>>, Arc<Mutex<Option<ChoicesHandle>>>);

impl NativeMod for Shifty {
    fn id(&self) -> &'static str {
        "shifty"
    }

    fn enable(&self, ctx: &mut ModCtx) -> Result<(), ModError> {
        let held = self.0.clone();
        let handle = ctx.choices("shifty.pick", move || {
            held.lock()
                .unwrap()
                .iter()
                .map(|v| Choice::new(v, v))
                .collect()
        })?;
        *self.1.lock().unwrap() = Some(handle);
        Ok(())
    }
}

/// A primary document that is not available until it is subscribed to (K28 `ready`).
struct Gate;

impl NativeMod for Gate {
    fn id(&self) -> &'static str {
        "gate"
    }

    fn enable(&self, ctx: &mut ModCtx) -> Result<(), ModError> {
        ctx.service(
            "gate",
            json!({"available": false}),
            |publish, _| async move {
                publish(json!({"available": true}));
            },
        )
    }
}

/// `file://` URL of a file of the test mod `hello`, as the daemon lists it.
fn hello_file(rel: &str) -> String {
    format!(
        "file://{}/tests/data/mods/hello/{rel}",
        env!("CARGO_MANIFEST_DIR")
    )
}

fn island_doc(d: &Daemon) -> Value {
    d.hub.snapshot("runtime.island.main").unwrap().1
}

fn island_faces(d: &Daemon) -> Vec<Value> {
    island_doc(d)["faces"].as_array().unwrap().clone()
}

/// The row of `key` in the `schema.settings` document.
fn setting_row(d: &Daemon, key: &str) -> Value {
    let (_, doc) = d.hub.snapshot("schema.settings").unwrap();
    doc["pages"]
        .as_array()
        .into_iter()
        .flatten()
        .flat_map(|page| page["sections"].as_array().into_iter().flatten())
        .flat_map(|section| section["rows"].as_array().into_iter().flatten())
        .find(|row| row["key"] == key)
        .cloned()
        .unwrap_or_else(|| panic!("no row for {key}"))
}

/// The values a settings row offers.
fn offered(row: &Value) -> Vec<String> {
    row["choices"]
        .as_array()
        .unwrap()
        .iter()
        .map(|c| c["value"].as_str().unwrap().to_string())
        .collect()
}

/// The reason a setting's value is not in effect, if any.
fn reason_of(d: &Daemon, key: &str) -> Option<String> {
    d.store.get(key, None).and_then(|p| p.reason)
}

#[tokio::test]
async fn enable_puts_the_slot_face_panel_and_choices_in_effect_and_disable_takes_them_back() {
    let d = start(&scratch("hooks"), &[], hello());
    assert_eq!(d.hub.snapshot("runtime.slots").unwrap().1, json!({}));
    assert!(!island_faces(&d).contains(&json!("hello")));

    d.act("mod.enable", "hello").await.unwrap();

    // The footer slot: its file, ready from the primary document (`mod.hello` is available).
    assert_eq!(
        d.hub.snapshot("runtime.slots").unwrap().1,
        json!({"clock.expanded.footer": [{
            "mod": "hello",
            "qml": hello_file("qml/slots/clock.expanded.footer.qml"),
            "ready": true,
        }]})
    );
    // The mods document names the component files that exist: the expanded face view and the slot too.
    assert_eq!(
        d.entry("hello")["qml"],
        json!({
            "island-face:hello": hello_file("qml/Face.qml"),
            "island-face:hello:expanded": hello_file("qml/FaceExpanded.qml"),
            "panel:hello": hello_file("qml/Panel.qml"),
            "slot:clock.expanded.footer": hello_file("qml/slots/clock.expanded.footer.qml"),
        })
    );

    // The face is registered: in the cycle, shown by relevance when raised, back to the default on clear.
    assert!(island_faces(&d).contains(&json!("hello")));
    d.actions
        .invoke("hello.raise", json!({"relevance": 60}))
        .await
        .unwrap();
    let shown = island_doc(&d);
    assert_eq!(shown["face"], "hello");
    assert_eq!(shown["reason"], "relevance");
    d.actions.invoke("hello.clear", json!({})).await.unwrap();
    let shown = island_doc(&d);
    assert_eq!(shown["face"], "clock");
    assert_eq!(shown["reason"], "default");

    // The choice source: the greeting setting, which names it, offers the mod's options.
    let row = setting_row(&d, "mods.hello.greeting");
    assert_eq!(row["choices_from"], "hello.greetings");
    assert_eq!(offered(&row), ["hi", "hello", "yo"]);
    assert_eq!(reason_of(&d, "mods.hello.greeting"), None);

    // The panel: `mod.panel.open` toggles `mod:hello:hello`; a panel the mod does not provide is refused.
    d.actions
        .invoke("mod.panel.open", json!({"id": "hello", "panel": "hello"}))
        .await
        .unwrap();
    assert_eq!(
        d.hub.snapshot("runtime.ui").unwrap().1["panel"],
        "mod:hello:hello"
    );
    d.actions
        .invoke("mod.panel.open", json!({"id": "hello", "panel": "hello"}))
        .await
        .unwrap();
    assert_eq!(d.hub.snapshot("runtime.ui").unwrap().1["panel"], "");
    assert_eq!(
        d.actions
            .invoke("mod.panel.open", json!({"id": "hello", "panel": "other"}))
            .await,
        Err(ActionError::Invalid("mods.error.panel_unavailable".into()))
    );
    assert_eq!(
        d.actions
            .invoke("mod.panel.open", json!({"id": "hello"}))
            .await,
        Err(ActionError::Invalid(wiring::ARGS_INVALID.into()))
    );

    // Disabled while its face is shown: slot, face and panel are gone, the island falls back, and the
    // greeting keeps its value, inert because its mod is off.
    d.actions
        .invoke("hello.raise", json!({"relevance": 60}))
        .await
        .unwrap();
    d.act("mod.disable", "hello").await.unwrap();
    assert_eq!(d.hub.snapshot("runtime.slots").unwrap().1, json!({}));
    assert!(!island_faces(&d).contains(&json!("hello")));
    assert_eq!(island_doc(&d)["face"], "clock");
    assert_eq!(
        d.actions
            .invoke("mod.panel.open", json!({"id": "hello", "panel": "hello"}))
            .await,
        Err(ActionError::Invalid("mods.error.panel_unavailable".into()))
    );
    assert_eq!(
        reason_of(&d, "mods.hello.greeting").as_deref(),
        Some("mods.disabled")
    );
}

/// A setting of one mod that names another mod's choice source: in effect while the source's mod is
/// on, inert (`settings.choice.unavailable`) while it is off, as a source that offers nothing.
#[tokio::test]
async fn a_setting_naming_a_choice_source_is_inert_while_the_source_mod_is_off() {
    let extra = scratch("consumer-mods");
    write(
        &extra.join("consumer/mod.toml"),
        "id = \"consumer\"\nname = \"Consumer\"\nversion = \"0.1.0\"\ntier = \"native\"\n\
         kurashi = \">=0.0.1\"\n\n[[setting]]\nkey = \"pick\"\ntype = \"string\"\n\
         default = \"hi\"\nchoices_from = \"hello.greetings\"\n",
    );
    let d = start(&scratch("consumer"), std::slice::from_ref(&extra), hello());
    d.act("mod.enable", "consumer").await.unwrap();
    // hello is off: its source is known with no options, so the value is judged and inert.
    assert_eq!(
        reason_of(&d, "mods.consumer.pick").as_deref(),
        Some("settings.choice.unavailable")
    );
    d.act("mod.enable", "hello").await.unwrap();
    assert_eq!(reason_of(&d, "mods.consumer.pick"), None);
    d.act("mod.disable", "hello").await.unwrap();
    assert_eq!(
        reason_of(&d, "mods.consumer.pick").as_deref(),
        Some("settings.choice.unavailable")
    );
}

/// A face handle kept past its disable raises nothing, also after the mod is enabled again (K28).
#[tokio::test]
async fn a_face_handle_kept_past_a_disable_raises_nothing() {
    let extra = scratch("keeper-mods");
    write(
        &extra.join("keeper/mod.toml"),
        "id = \"keeper\"\nname = \"Keeper\"\nversion = \"0.1.0\"\ntier = \"native\"\n\
         kurashi = \">=0.0.1\"\nprovides = [\"island-face:keeper\"]\n",
    );
    let kept = Arc::new(Mutex::new(None));
    let linked = vec![Box::new(Keeper(kept.clone())) as Box<dyn NativeMod>];
    let d = start(&scratch("keeper"), std::slice::from_ref(&extra), linked);
    d.act("mod.enable", "keeper").await.unwrap();
    let old = kept.lock().unwrap().clone().expect("the face handle");
    d.act("mod.disable", "keeper").await.unwrap();
    old.raise(90);
    assert_eq!(island_doc(&d)["face"], "clock");
    assert!(!island_faces(&d).contains(&json!("keeper")));

    d.act("mod.enable", "keeper").await.unwrap();
    assert!(island_faces(&d).contains(&json!("keeper")));
    old.raise(90);
    assert_eq!(
        island_doc(&d)["reason"],
        "default",
        "the old handle does not reach the new enable"
    );
}

/// `ChoicesHandle::changed` asks the source again: the settings that name it show the new options.
#[tokio::test]
async fn changed_choices_reach_the_settings_at_once() {
    let extra = scratch("shifty-mods");
    write(
        &extra.join("shifty/mod.toml"),
        "id = \"shifty\"\nname = \"Shifty\"\nversion = \"0.1.0\"\ntier = \"native\"\n\
         kurashi = \">=0.0.1\"\nprovides = [\"choices:shifty.pick\"]\n\n[[setting]]\n\
         key = \"pick\"\ntype = \"string\"\ndefault = \"a\"\nchoices_from = \"shifty.pick\"\n",
    );
    let options = Arc::new(Mutex::new(vec!["a".to_string()]));
    let handle = Arc::new(Mutex::new(None));
    let linked = vec![Box::new(Shifty(options.clone(), handle.clone())) as Box<dyn NativeMod>];
    let d = start(&scratch("shifty"), std::slice::from_ref(&extra), linked);
    d.act("mod.enable", "shifty").await.unwrap();
    assert_eq!(offered(&setting_row(&d, "mods.shifty.pick")), ["a"]);
    options.lock().unwrap().push("b".into());
    handle
        .lock()
        .unwrap()
        .as_ref()
        .expect("the choices handle")
        .choices_changed();
    assert_eq!(offered(&setting_row(&d, "mods.shifty.pick")), ["a", "b"]);
}

/// `runtime.slots` `ready` follows the primary document's `available`: not ready until the service
/// publishes it, which happens once something subscribes (rule 5).
#[tokio::test]
async fn a_slot_is_ready_when_its_primary_document_says_so() {
    let extra = scratch("gate-mods");
    let dir = extra.join("gate");
    write(
        &dir.join("mod.toml"),
        "id = \"gate\"\nname = \"Gate\"\nversion = \"0.1.0\"\ntier = \"native\"\n\
         kurashi = \">=0.0.1\"\nprovides = [\"service:gate\", \"slot:quick.tiles\"]\n",
    );
    write(&dir.join("qml/slots/quick.tiles.qml"), "import QtQuick\n");
    let linked = vec![Box::new(Gate) as Box<dyn NativeMod>];
    let d = start(&scratch("gate"), std::slice::from_ref(&extra), linked);
    d.act("mod.enable", "gate").await.unwrap();
    let ready =
        |d: &Daemon| d.hub.snapshot("runtime.slots").unwrap().1["quick.tiles"][0]["ready"].clone();
    assert_eq!(ready(&d), json!(false), "not available until it runs");
    d.hub.subscribe("mod.gate").unwrap();
    let hub = d.hub.clone();
    eventually(|| hub.snapshot("runtime.slots").unwrap().1["quick.tiles"][0]["ready"] == true)
        .await;
}

/// A mod with one island face, its handle kept for the test to raise (K28 (2)).
struct Faced {
    id: &'static str,
    face: &'static str,
    spec: FaceSpec,
    held: Arc<Mutex<Option<FaceHandle>>>,
}

impl NativeMod for Faced {
    fn id(&self) -> &'static str {
        self.id
    }

    fn enable(&self, ctx: &mut ModCtx) -> Result<(), ModError> {
        let handle = ctx.face(self.face, self.spec)?;
        *self.held.lock().unwrap() = Some(handle);
        Ok(())
    }
}

/// A transient face shows for its TTL after a raise, then the island falls back (K9, K28 (2)).
#[tokio::test]
async fn a_transient_face_runs_its_ttl_then_the_island_falls_back() {
    let extra = scratch("osd-mods");
    write(
        &extra.join("osd/mod.toml"),
        "id = \"osd\"\nname = \"Osd\"\nversion = \"0.1.0\"\ntier = \"native\"\n\
         kurashi = \">=0.0.1\"\nprovides = [\"island-face:osd\"]\n",
    );
    let held = Arc::new(Mutex::new(None));
    let linked = vec![Box::new(Faced {
        id: "osd",
        face: "osd",
        spec: FaceSpec {
            transient: true,
            ttl_s: 1,
        },
        held: held.clone(),
    }) as Box<dyn NativeMod>];
    let d = start(&scratch("osd"), std::slice::from_ref(&extra), linked);
    d.act("mod.enable", "osd").await.unwrap();
    let face = held.lock().unwrap().clone().expect("the face handle");
    face.raise(0);
    assert_eq!(island_doc(&d)["face"], "osd");
    assert_eq!(island_doc(&d)["reason"], "transient");
    let hub = d.hub.clone();
    eventually(|| hub.snapshot("runtime.island.main").unwrap().1["face"] == "clock").await;
}

/// A face may not take the name of a core face: the enable is refused and the core face stays.
#[tokio::test]
async fn a_face_named_like_a_core_face_is_refused() {
    let extra = scratch("dup-mods");
    write(
        &extra.join("dup/mod.toml"),
        "id = \"dup\"\nname = \"Dup\"\nversion = \"0.1.0\"\ntier = \"native\"\n\
         kurashi = \">=0.0.1\"\nprovides = [\"island-face:clock\"]\n",
    );
    let linked = vec![Box::new(Faced {
        id: "dup",
        face: "clock",
        spec: FaceSpec {
            transient: false,
            ttl_s: 0,
        },
        held: Arc::new(Mutex::new(None)),
    }) as Box<dyn NativeMod>];
    let d = start(&scratch("dup"), std::slice::from_ref(&extra), linked);
    d.act("mod.enable", "dup").await.unwrap();
    assert_eq!(d.state("dup"), "disabled");
    assert_eq!(d.entry("dup")["errors"][0]["key"], "mods.error.duplicate");
    assert_eq!(
        island_faces(&d).iter().filter(|f| *f == "clock").count(),
        1,
        "the core face is registered once"
    );
}

/// Counts ticks in its background job `tick`, and says whether a run of the job is in progress.
struct Ticker {
    ticks: Arc<AtomicUsize>,
    alive: Arc<AtomicBool>,
}

/// Clears its flag when dropped: a job the daemon cancels is dropped, so the flag tells it ended.
struct Alive(Arc<AtomicBool>);

impl Drop for Alive {
    fn drop(&mut self) {
        self.0.store(false, Ordering::SeqCst);
    }
}

impl NativeMod for Ticker {
    fn id(&self) -> &'static str {
        "ticker"
    }

    fn enable(&self, ctx: &mut ModCtx) -> Result<(), ModError> {
        let (ticks, alive) = (self.ticks.clone(), self.alive.clone());
        ctx.background("tick", "mods.running.tick", "on", move |_job| {
            let (ticks, alive) = (ticks.clone(), alive.clone());
            async move {
                alive.store(true, Ordering::SeqCst);
                let _alive = Alive(alive);
                loop {
                    ticks.fetch_add(1, Ordering::SeqCst);
                    tokio::time::sleep(Duration::from_secs(1)).await;
                }
            }
        })
    }
}

/// Declares a job whose body returns at once, so the job ends by itself.
struct Once;

impl NativeMod for Once {
    fn id(&self) -> &'static str {
        "once"
    }

    fn enable(&self, ctx: &mut ModCtx) -> Result<(), ModError> {
        ctx.background("once", "mods.running.once", "on", |_job| async {})
    }
}

/// Writes the manifest of a test mod with one bool setting `on` and one `job:<name>` per job.
fn job_mod(extra: &Path, id: &str, jobs: &[&str]) {
    let provides: Vec<String> = jobs.iter().map(|j| format!("\"job:{j}\"")).collect();
    write(
        &extra.join(id).join("mod.toml"),
        &format!(
            "id = \"{id}\"\nname = \"{id}\"\nversion = \"0.1.0\"\ntier = \"native\"\n\
             kurashi = \">=0.0.1\"\nprovides = [{}]\n\n[[setting]]\nkey = \"on\"\n\
             type = \"bool\"\ndefault = false\n",
            provides.join(", ")
        ),
    );
}

fn set_on(d: &Daemon, id: &str, on: bool) {
    d.store
        .apply(&[ApplyOp::Set {
            set: format!("mods.{id}.on"),
            value: json!(on),
            output: None,
        }])
        .expect("a bool setting of the mod");
}

/// The reasons a mod reports as running now (`running_reasons` of the `mods` document).
fn reasons(d: &Daemon, id: &str) -> Value {
    d.entry(id)["running_reasons"].clone()
}

/// A background job runs only while its mod is on and its setting wants it, is reported with its
/// reason while it runs, and is cancelled when the setting lets go or the mod is disabled (I23).
#[tokio::test(start_paused = true)]
async fn a_background_job_runs_while_on_and_wanted_and_is_reported() {
    let extra = scratch("ticker-mods");
    job_mod(&extra, "ticker", &["tick"]);
    let (ticks, alive) = (
        Arc::new(AtomicUsize::new(0)),
        Arc::new(AtomicBool::new(false)),
    );
    let linked = vec![Box::new(Ticker {
        ticks: ticks.clone(),
        alive: alive.clone(),
    }) as Box<dyn NativeMod>];
    let d = start(&scratch("ticker"), std::slice::from_ref(&extra), linked);
    d.act("mod.enable", "ticker").await.unwrap();

    // On, but the setting does not want the job: nothing runs and nothing is reported.
    tokio::time::sleep(Duration::from_secs(3)).await;
    assert_eq!(ticks.load(Ordering::SeqCst), 0);
    assert_eq!(reasons(&d, "ticker"), json!([]));
    assert!(!d.running("ticker"));

    // The setting wants it: the job runs, and the mod says why.
    set_on(&d, "ticker", true);
    tokio::time::sleep(Duration::from_millis(2500)).await;
    assert!(ticks.load(Ordering::SeqCst) >= 2, "the job ticks");
    assert!(alive.load(Ordering::SeqCst));
    assert_eq!(reasons(&d, "ticker"), json!(["mods.running.tick"]));
    assert!(d.running("ticker"));

    // The setting lets go: the job is cancelled and the count stops.
    set_on(&d, "ticker", false);
    tokio::time::sleep(Duration::from_millis(10)).await;
    let stopped_at = ticks.load(Ordering::SeqCst);
    assert!(
        !alive.load(Ordering::SeqCst),
        "the cancelled run is dropped"
    );
    assert_eq!(reasons(&d, "ticker"), json!([]));
    tokio::time::sleep(Duration::from_secs(5)).await;
    assert_eq!(ticks.load(Ordering::SeqCst), stopped_at);

    // Wanted again, then the mod is disabled: the job is cancelled with it.
    set_on(&d, "ticker", true);
    tokio::time::sleep(Duration::from_millis(1500)).await;
    assert!(alive.load(Ordering::SeqCst));
    d.act("mod.disable", "ticker").await.unwrap();
    tokio::time::sleep(Duration::from_millis(10)).await;
    assert!(!alive.load(Ordering::SeqCst));
    assert_eq!(reasons(&d, "ticker"), json!([]));
    assert!(!d.running("ticker"));
    let stopped_at = ticks.load(Ordering::SeqCst);
    tokio::time::sleep(Duration::from_secs(3)).await;
    assert_eq!(ticks.load(Ordering::SeqCst), stopped_at);
}

/// A job whose body returns by itself is no longer running, and the document says so (I23).
#[tokio::test(start_paused = true)]
async fn a_job_that_ends_by_itself_is_no_longer_reported() {
    let extra = scratch("once-mods");
    job_mod(&extra, "once", &["once"]);
    let linked = vec![Box::new(Once) as Box<dyn NativeMod>];
    let d = start(&scratch("once"), std::slice::from_ref(&extra), linked);
    d.act("mod.enable", "once").await.unwrap();
    set_on(&d, "once", true);
    tokio::time::sleep(Duration::from_millis(10)).await;
    assert_eq!(reasons(&d, "once"), json!([]));
    assert!(!d.running("once"));
    // Wanted again: it runs once more and ends again.
    set_on(&d, "once", false);
    set_on(&d, "once", true);
    tokio::time::sleep(Duration::from_millis(10)).await;
    assert_eq!(reasons(&d, "once"), json!([]));
}

/// A `list` setting is an ordered pick from its fixed choices (I26): its row is a pick list of them,
/// the order stored is the order in effect, and a member outside the choices is refused.
#[tokio::test]
async fn a_list_setting_is_a_pick_list_of_its_choices() {
    let extra = scratch("list-mods");
    write(
        &extra.join("picker/mod.toml"),
        "id = \"picker\"\nname = \"Picker\"\nversion = \"0.1.0\"\ntier = \"native\"\n\
         kurashi = \">=0.0.1\"\n\n[[setting]]\nkey = \"show\"\ntype = \"list\"\n\
         default = [\"mem\", \"cpu\"]\nchoices = [\"cpu\", \"mem\", \"temp\"]\n",
    );
    let d = start(&scratch("list"), std::slice::from_ref(&extra), Vec::new());
    d.act("mod.enable", "picker").await.unwrap();

    let row = setting_row(&d, "mods.picker.show");
    assert_eq!(row["control"], "pick_list");
    assert_eq!(row["default"], json!(["mem", "cpu"]));
    assert_eq!(offered(&row), ["cpu", "mem", "temp"]);

    let set = |value: Value| {
        d.store.apply(&[ApplyOp::Set {
            set: "mods.picker.show".into(),
            value,
            output: None,
        }])
    };
    set(json!(["temp", "cpu"])).expect("members of the choices, in the order picked");
    let p = d.store.get("mods.picker.show", None).unwrap();
    assert_eq!(p.value, json!(["temp", "cpu"]));
    assert_eq!(p.reason, None);
    assert!(set(json!(["gpu"])).is_err(), "a member outside the choices");
    assert_eq!(
        d.store.get("mods.picker.show", None).unwrap().value,
        json!(["temp", "cpu"]),
        "a refused value leaves the one in effect"
    );
}

/// B15: a mod whose manifest declares daemon code (a service, action, island face, choice source or
/// job) is refused when this build links none for it; a frontend-only mod is switched on as before.
/// The bundled `media` and `easter-eggs` (on by default) declare daemon code and no linked module.
#[tokio::test]
async fn an_unlinked_mod_with_daemon_provides_is_refused_and_a_frontend_only_one_is_on() {
    let extra = scratch("unbuilt-mods");
    write(
        &extra.join("ghost/mod.toml"),
        "id = \"ghost\"\nname = \"Ghost\"\nversion = \"0.1.0\"\ntier = \"native\"\n\
         kurashi = \">=0.0.1\"\nprovides = [\"action:ghost.*\"]\n",
    );
    write(
        &extra.join("glass/mod.toml"),
        "id = \"glass\"\nname = \"Glass\"\nversion = \"0.1.0\"\ntier = \"native\"\n\
         kurashi = \">=0.0.1\"\nprovides = [\"widget:glass\", \"panel:glass\", \"slot:quick.tiles\"]\n",
    );
    let d = start(
        &scratch("unbuilt"),
        std::slice::from_ref(&extra),
        Vec::new(),
    );

    // Switched on by the config default, the bundled easter-eggs has an action and no code: refused.
    assert_eq!(d.state("easter-eggs"), "disabled");
    assert_eq!(
        d.entry("easter-eggs")["errors"][0]["key"],
        "mods.error.not_built"
    );

    d.act("mod.enable", "ghost").await.unwrap();
    assert_eq!(d.state("ghost"), "disabled");
    assert_eq!(d.entry("ghost")["errors"][0]["key"], "mods.error.not_built");

    // The bundled media declares a service, a face and actions: the same refusal, and nothing served.
    d.act("mod.enable", "media").await.unwrap();
    assert_eq!(d.state("media"), "disabled");
    assert_eq!(d.entry("media")["errors"][0]["key"], "mods.error.not_built");
    assert!(d.hub.snapshot("mod.media").is_err());

    // Frontend-only provides need no code: on, with their components listed.
    d.act("mod.enable", "glass").await.unwrap();
    assert_eq!(d.state("glass"), "enabled");
    assert_eq!(d.entry("glass")["errors"], json!([]));
}
