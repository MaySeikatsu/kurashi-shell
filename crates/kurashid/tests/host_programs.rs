//! Host programs (K155, W93; PROTOCOL §2 "Host programs", MODS.md "Host programs"): a mod with no crate whose code is a
//! program the manifest declares. The test mod `tea` (tests/data/host-programs/mods) brings `bin/tea-host`, a Python
//! script that speaks the protocol as MODDING.md shows it. Through the daemon's own mods wiring and socket server.

use std::fs;
use std::path::{Path, PathBuf};
use std::sync::{Arc, OnceLock};
use std::time::Duration;

use kurashi_config::{Options, Paths};
use kurashi_mod_api::NativeMod;
use kurashid::config::ConfigStore;
use kurashid::native::hosts::{HostEnv, set_host_env};
use kurashid::{ActionError, ActionRegistry, Hub, wiring};
use serde_json::{Value, json};
use tokio::sync::{Mutex, oneshot};

/// One test at a time: the host environment and the scope table are per process.
static GATE: Mutex<()> = Mutex::const_new(());

/// The first `name` on `PATH` (the script's interpreter: the build sandbox has no /usr/bin/env).
fn on_path(name: &str) -> PathBuf {
    std::env::split_paths(&std::env::var_os("PATH").unwrap_or_default())
        .map(|d| d.join(name))
        .find(|p| p.is_file())
        .unwrap_or_else(|| panic!("{name} is not on PATH"))
}

/// The directory the tests work in, with a copy of the test mod whose program is executable.
fn base() -> &'static PathBuf {
    static BASE: OnceLock<PathBuf> = OnceLock::new();
    BASE.get_or_init(|| {
        use std::os::unix::fs::PermissionsExt;
        let base =
            std::env::temp_dir().join(format!("kurashid-host-programs-{}", std::process::id()));
        let _ = fs::remove_dir_all(&base);
        let src = Path::new(env!("CARGO_MANIFEST_DIR")).join("tests/data/host-programs/mods/tea");
        let dst = base.join("mods/tea");
        fs::create_dir_all(dst.join("bin")).unwrap();
        fs::copy(src.join("mod.toml"), dst.join("mod.toml")).unwrap();
        let script = fs::read_to_string(src.join("bin/tea-host")).unwrap();
        let script = script.replacen(
            "#!/usr/bin/env python3",
            &format!("#!{}", on_path("python3").display()),
            1,
        );
        fs::write(dst.join("bin/tea-host"), script).unwrap();
        fs::set_permissions(dst.join("bin/tea-host"), fs::Permissions::from_mode(0o755)).unwrap();
        let set = set_host_env(HostEnv {
            search: vec![],
            data: Some(base.join("data")),
            cache: Some(base.join("cache")),
            state: Some(base.join("state")),
            // The program connects to this test's daemon, never to a running shell's.
            socket: Some(base.join("kurashid.sock")),
        });
        assert!(set, "the host environment is set once per process");
        base
    })
}

struct Daemon {
    hub: Arc<Hub>,
    actions: ActionRegistry,
    _stop: oneshot::Sender<()>,
}

async fn start(tag: &str) -> Daemon {
    let dir = base().join(tag);
    let _ = fs::remove_dir_all(&dir);
    fs::create_dir_all(&dir).unwrap();
    let _ = fs::remove_file(report());
    let sock = base().join("kurashid.sock");
    let _ = fs::remove_file(&sock);
    let hub = Hub::new();
    let store: Arc<ConfigStore> = ConfigStore::open(
        hub.clone(),
        kurashi_schema::v1::registry(),
        Paths::rooted(&dir.join("config")),
        Options::default(),
    );
    let mut actions = ActionRegistry::default();
    wiring::ui(&hub, &mut actions);
    // No crate is linked: the mod's code is its program.
    wiring::mods_native(
        &hub,
        &mut actions,
        vec![base().join("mods")],
        Some(store.clone()),
        Vec::<Box<dyn NativeMod>>::new(),
        None,
    );
    let mut daemon =
        kurashid::Daemon::new(hub.clone(), actions.clone(), kurashid::Intents::default());
    daemon.config = Some(store);
    let listener = tokio::net::UnixListener::bind(&sock).unwrap();
    let (stop, stopped) = oneshot::channel::<()>();
    tokio::spawn(kurashid::server::serve(listener, Arc::new(daemon), async {
        let _ = stopped.await;
    }));
    Daemon {
        hub,
        actions,
        _stop: stop,
    }
}

fn report() -> PathBuf {
    base().join("state/tea/report.txt")
}

fn reported() -> Vec<String> {
    fs::read_to_string(report())
        .unwrap_or_default()
        .lines()
        .map(str::to_string)
        .collect()
}

impl Daemon {
    fn tea(&self) -> Value {
        self.hub.snapshot("mod.tea").unwrap().1
    }

    fn entry(&self) -> Value {
        let (_, doc) = self.hub.snapshot("mods").unwrap();
        doc["mods"]
            .as_array()
            .unwrap()
            .iter()
            .find(|m| m["id"] == "tea")
            .cloned()
            .expect("the tea mod is listed")
    }
}

async fn eventually(what: &str, mut check: impl FnMut() -> bool) {
    for _ in 0..400 {
        if check() {
            return;
        }
        tokio::time::sleep(Duration::from_millis(20)).await;
    }
    panic!(
        "not reached within 8 s: {what}; the program reported {:?}",
        reported()
    );
}

#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn a_program_serves_its_mods_document_and_action_and_nothing_it_did_not_declare() {
    let _gate = GATE.lock().await;
    let d = start("serves").await;
    // A mod with no crate is offered and enables: its manifest declares a program.
    assert_eq!(d.entry()["state"], "available");
    d.actions
        .invoke("mod.enable", json!({"id": "tea"}))
        .await
        .unwrap();
    assert_eq!(d.entry()["state"], "enabled");
    assert_eq!(d.entry()["errors"], json!([]));

    // Nobody watches: the program does not run (Ma), and the document says why it is empty.
    assert_eq!(
        d.tea(),
        json!({"available": false, "reason": "mods.host.starting"})
    );
    assert_eq!(
        d.actions.invoke("tea.start", json!({})).await,
        Err(ActionError::Unavailable("mods.host.not_running".into()))
    );
    assert!(reported().is_empty());

    // A subscriber starts it; it publishes the mod's document and takes its action.
    d.hub.subscribe("mod.tea").unwrap();
    eventually("the document is the program's", || {
        d.tea()["available"] == true
    })
    .await;
    assert_eq!(d.tea()["steeping"], false);
    eventually("the program's requests were answered", || {
        reported().len() >= 4
    })
    .await;
    let r = reported();
    assert_eq!(r[0], "hello welcome");
    // What the manifest does not say is refused, and none of that `serve` was taken.
    assert!(r.contains(&"x1 err forbidden".to_string()), "{r:?}");
    assert!(r.contains(&"x2 err forbidden".to_string()), "{r:?}");
    assert!(r.contains(&"s1 done ".to_string()), "{r:?}");
    assert!(d.hub.snapshot("mod.other").is_err());

    // The action reaches the program with its declared argument checked and its default filled in.
    assert_eq!(
        d.actions.invoke("tea.start", json!({})).await,
        Ok(Some(json!({"minutes": 3})))
    );
    eventually("the program published the change", || {
        d.tea()["steeping"] == true
    })
    .await;
    assert_eq!(d.tea()["minutes"], 3);
    assert!(matches!(
        d.actions
            .invoke("tea.start", json!({"minutes": "long"}))
            .await,
        Err(ActionError::Invalid(_))
    ));
    // The program's own refusal comes back as it said it.
    assert_eq!(
        d.actions.invoke("tea.start", json!({"minutes": 60})).await,
        Err(ActionError::Unavailable("mod-tea.error.no_kettle".into()))
    );

    // Off: the program is asked to stop, and its action is gone.
    d.actions
        .invoke("mod.disable", json!({"id": "tea"}))
        .await
        .unwrap();
    eventually("the program was stopped", || {
        reported().iter().any(|l| l == "term")
    })
    .await;
    assert_eq!(
        d.actions.invoke("tea.start", json!({})).await,
        Err(ActionError::Unknown("tea.start".into()))
    );
}
