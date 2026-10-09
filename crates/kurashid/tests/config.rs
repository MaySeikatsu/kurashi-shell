//! `cfg.*` / `apply` / `undo` over a real socket against the v1 schema (M1.5).

use std::sync::Arc;
use std::sync::atomic::{AtomicUsize, Ordering};
use std::time::Duration;

use kurashi_core::Source;
use kurashi_ipc::{ApplyOp, ClientMsg, LineReader, ServerMsg, merge_patch, write_msg};
use kurashid::config::ConfigStore;
use kurashid::{ActionRegistry, Daemon, Hub, Intents};
use serde_json::{Value, json};
use tokio::net::UnixStream;
use tokio::net::unix::{OwnedReadHalf, OwnedWriteHalf};

struct Client {
    rd: LineReader<OwnedReadHalf>,
    wr: OwnedWriteHalf,
}

impl Client {
    async fn send(&mut self, m: ClientMsg) {
        write_msg(&mut self.wr, &m).await.unwrap();
    }
    async fn recv(&mut self) -> ServerMsg {
        tokio::time::timeout(Duration::from_secs(2), self.rd.next_value())
            .await
            .expect("timeout")
            .unwrap()
            .expect("closed")
    }
    /// Next reply that isn't a patch (patches for `config` interleave with replies).
    async fn reply(&mut self) -> ServerMsg {
        loop {
            match self.recv().await {
                ServerMsg::Patch { .. } => continue,
                m => return m,
            }
        }
    }
}

struct Fx {
    client: Client,
    store: Arc<ConfigStore>,
    root: std::path::PathBuf,
}

async fn start() -> Fx {
    static N: AtomicUsize = AtomicUsize::new(0);
    let n = N.fetch_add(1, Ordering::SeqCst);
    let root = std::env::temp_dir().join(format!("kurashid-cfg-{}-{n}", std::process::id()));
    let _ = std::fs::remove_dir_all(&root);
    let sock = root.join("ipc.sock");
    std::fs::create_dir_all(&root).unwrap();

    let hub = Hub::new();
    let mut actions = ActionRegistry::default();
    let store = ConfigStore::open(
        hub.clone(),
        kurashi_schema::v1::registry(),
        kurashi_config::Paths::rooted(&root),
        kurashi_config::Options::default(),
    );
    store.register_actions(&mut actions);
    let mut daemon = Daemon::new(hub, actions, Intents::default());
    daemon.config = Some(store.clone());
    let listener = tokio::net::UnixListener::bind(&sock).unwrap();
    tokio::spawn(kurashid::server::serve(
        listener,
        Arc::new(daemon),
        std::future::pending(),
    ));

    let (rd, wr) = UnixStream::connect(&sock).await.unwrap().into_split();
    let mut client = Client {
        rd: LineReader::new(rd),
        wr,
    };
    client
        .send(ClientMsg::Hello {
            v: 1,
            client: "t".into(),
            caps: vec![],
        })
        .await;
    client.recv().await;
    Fx {
        client,
        store,
        root,
    }
}

fn set(key: &str, value: Value) -> ApplyOp {
    ApplyOp::Set {
        set: key.into(),
        value,
        output: None,
    }
}

#[tokio::test]
async fn get_apply_explain_undo_roundtrip() {
    let mut f = start().await;
    let c = &mut f.client;
    c.send(ClientMsg::CfgGet {
        id: "1".into(),
        key: "bar.height".into(),
        output: None,
    })
    .await;
    let default = match c.reply().await {
        ServerMsg::CfgVal { v, .. } => {
            assert_eq!(v.source, Source::Default);
            v.value
        }
        other => panic!("{other:?}"),
    };

    c.send(ClientMsg::Apply {
        id: "2".into(),
        ops: vec![set("bar.height", json!(44))],
        dry_run: true,
    })
    .await;
    match c.reply().await {
        ServerMsg::Preview { diff, .. } => {
            assert_eq!(diff.len(), 1);
            assert_eq!(diff[0].after.as_ref().unwrap().value, json!(44));
        }
        other => panic!("{other:?}"),
    }
    assert_eq!(
        f.store.get("bar.height", None).unwrap().value,
        default,
        "dry run"
    );

    c.send(ClientMsg::Apply {
        id: "3".into(),
        ops: vec![set("bar.height", json!(44))],
        dry_run: false,
    })
    .await;
    assert!(matches!(c.reply().await, ServerMsg::Applied { undo, .. } if undo.starts_with("tx-")));
    let user_file = std::fs::read_to_string(f.root.join("config/kurashi/config.toml"))
        .or_else(|_| std::fs::read_to_string(kurashi_config::Paths::rooted(&f.root).user_file()))
        .unwrap();
    assert!(user_file.contains("44"), "persisted sparse: {user_file}");

    c.send(ClientMsg::CfgExplain {
        id: "4".into(),
        key: "bar.height".into(),
        output: None,
    })
    .await;
    match c.reply().await {
        ServerMsg::CfgWhy { layers, .. } => {
            let active: Vec<_> = layers.iter().filter(|l| l.active).collect();
            assert_eq!(active.len(), 1);
            assert_eq!(active[0].source, Source::User);
            assert_eq!(layers[0].source, Source::Default);
        }
        other => panic!("{other:?}"),
    }

    c.send(ClientMsg::Undo { id: "5".into() }).await;
    assert!(matches!(c.reply().await, ServerMsg::Applied { .. }));
    assert_eq!(f.store.get("bar.height", None).unwrap().value, default);
    c.send(ClientMsg::Undo { id: "6".into() }).await;
    assert!(
        matches!(c.reply().await, ServerMsg::Rejected { errors, .. } if errors[0].code == "config.error.nothing_to_undo")
    );
}

#[tokio::test]
async fn invalid_batches_are_rejected_atomically() {
    let mut f = start().await;
    let c = &mut f.client;
    c.send(ClientMsg::Apply {
        id: "1".into(),
        ops: vec![
            set("theme.motion.speed", json!(1.5)),
            set("bar.height", json!("tall")),
            set("no.such.key", json!(1)),
        ],
        dry_run: false,
    })
    .await;
    match c.reply().await {
        ServerMsg::Rejected { errors, .. } => {
            assert_eq!(errors.len(), 2);
            assert!(errors.iter().any(|e| e.code == "config.diag.unknown_key"));
        }
        other => panic!("{other:?}"),
    }
    assert_eq!(
        f.store.get("theme.motion.speed", None).unwrap().source,
        Source::Default,
        "nothing applied"
    );
}

#[tokio::test]
async fn config_document_patches_and_external_edits_reload() {
    let mut f = start().await;
    f.client
        .send(ClientMsg::Sub {
            id: "s".into(),
            doc: "config".into(),
        })
        .await;
    let mut doc = match f.client.recv().await {
        ServerMsg::Snap { data, .. } => data,
        other => panic!("{other:?}"),
    };
    assert_eq!(doc["values"]["bar.height"]["source"]["kind"], "default");

    // An external editor writes the user file; the watcher would call reload().
    let path = kurashi_config::Paths::rooted(&f.root).user_file();
    std::fs::create_dir_all(path.parent().unwrap()).unwrap();
    std::fs::write(&path, "# mine\n[bar]\nheight = 40\n").unwrap();
    f.store.reload();
    match f.client.recv().await {
        ServerMsg::Patch { ops, .. } => merge_patch(&mut doc, &ops),
        other => panic!("{other:?}"),
    }
    assert_eq!(doc["values"]["bar.height"]["value"], 40);
    assert_eq!(doc["values"]["bar.height"]["source"]["kind"], "user");
}

#[tokio::test]
async fn schema_settings_document_is_served() {
    let mut f = start().await;
    f.client
        .send(ClientMsg::Sub {
            id: "s".into(),
            doc: "schema.settings".into(),
        })
        .await;
    match f.client.recv().await {
        ServerMsg::Snap { data, .. } => {
            assert!(!data["pages"].as_array().unwrap().is_empty());
        }
        other => panic!("{other:?}"),
    }
}

#[tokio::test]
async fn a11y_mode_forces_coupled_keys_and_theme_follows() {
    let f = start().await;
    let hub = Hub::new();
    let fonts: Arc<dyn kurashi_theme::FontProvider + Send + Sync> =
        Arc::new(kurashi_theme::FakeFonts::new(&["Inter"]));
    kurashid::theme::register(&hub, &f.store, fonts);
    let before = hub.snapshot("theme").unwrap().1;
    assert!(before["tokens"]["motion.standard_ms"].as_f64().unwrap() > 0.0);

    f.store
        .apply(&[set("a11y.reduce_motion", json!(true))])
        .unwrap();
    let p = f.store.get("theme.motion.profile", None).unwrap();
    assert_eq!(p.value, json!("none"));
    assert_eq!(p.source, Source::Forced("accessibility".into()));
    assert_eq!(p.forced_by.as_deref(), Some("a11y.reduce_motion"));
    let after = hub.snapshot("theme").unwrap().1;
    assert_eq!(
        after["tokens"]["motion.standard_ms"],
        json!(0),
        "motion off"
    );

    f.store.undo(false).unwrap();
    assert_eq!(
        f.store.get("theme.motion.profile", None).unwrap().source,
        Source::Default,
        "forcing lifts when the mode is off"
    );
}
