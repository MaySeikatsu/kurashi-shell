//! Host processes (K38, MODS.md "Host processes") and the scoped connections of PROTOCOL §2, through the daemon's own
//! mods wiring. A test mod (`probe`, tests/data/hosts/mods) declares one host whose program is the fake host
//! (tests/data/hosts/fake-host.py); the fake host speaks the scoped hello the way the web host does. The tests run
//! one at a time: `shutdown_all` and the scope table are per process.

use std::collections::BTreeMap;
use std::fs;
use std::path::{Path, PathBuf};
use std::sync::{Arc, OnceLock};
use std::time::Duration;

use kurashi_config::{Options, Paths};
use kurashi_ipc::{ClientMsg, LineReader, Scope, ServerMsg, write_msg};
use kurashi_mod_api::{HostSpec, ModCtx, ModError, NativeMod};
use kurashid::config::ConfigStore;
use kurashid::native::hosts::{HostEnv, set_host_env, shutdown_all};
use kurashid::{ActionRegistry, Hub, wiring};
use serde_json::{Value, json};
use tokio::net::UnixStream;
use tokio::sync::{Mutex, oneshot};

/// One test at a time: the host environment and the scope table are per process.
static GATE: Mutex<()> = Mutex::const_new(());

/// The directory every test works in (`base/<tag>`), with the fake host installed on the host search path.
fn base() -> &'static PathBuf {
    static BASE: OnceLock<PathBuf> = OnceLock::new();
    BASE.get_or_init(|| {
        use std::os::unix::fs::PermissionsExt;
        let base = std::env::temp_dir().join(format!("kurashid-hosts-{}", std::process::id()));
        let _ = fs::remove_dir_all(&base);
        let bin = base.join("bin");
        fs::create_dir_all(&bin).unwrap();
        let script = Path::new(env!("CARGO_MANIFEST_DIR")).join("tests/data/hosts/fake-host.py");
        let target = bin.join("fake-host");
        fs::copy(&script, &target).unwrap();
        fs::set_permissions(&target, fs::Permissions::from_mode(0o755)).unwrap();
        let set = set_host_env(HostEnv {
            search: vec![bin],
            data: Some(base.join("data")),
            cache: Some(base.join("cache")),
            state: Some(base.join("state")),
        });
        assert!(set, "the host environment is set once per process");
        base
    })
}

/// The test mod: one host, `fake`, that runs `binary` with `args`; actions start it, stop it and read its state.
struct Probe {
    binary: &'static str,
    args: Vec<String>,
}

impl NativeMod for Probe {
    fn id(&self) -> &'static str {
        "probe"
    }

    fn enable(&self, ctx: &mut ModCtx) -> Result<(), ModError> {
        let host = ctx.host(
            "fake",
            HostSpec {
                binary: self.binary.into(),
                args: self.args.clone(),
                env: BTreeMap::new(),
            },
        )?;
        ctx.service(
            "probe",
            json!({"available": true}),
            |publish, _| async move {
                publish(json!({"available": true}));
                std::future::pending::<()>().await
            },
        )?;
        let h = host.clone();
        ctx.action("probe.start", "action.probe.start", move |_| {
            let h = h.clone();
            async move {
                h.start();
                Ok(None)
            }
        })?;
        let h = host.clone();
        ctx.action("probe.stop", "action.probe.stop", move |_| {
            let h = h.clone();
            async move {
                h.stop();
                Ok(None)
            }
        })?;
        ctx.action("probe.state", "action.probe.state", move |_| {
            let h = host.clone();
            async move { Ok(Some(json!({"state": h.state().borrow().name()}))) }
        })?;
        Ok(())
    }
}

/// A daemon over its own config root, with the probe linked and its socket served (the fake host connects to it).
struct Daemon {
    dir: PathBuf,
    hub: Arc<Hub>,
    actions: ActionRegistry,
    sock: PathBuf,
    _stop: oneshot::Sender<()>,
}

async fn start(tag: &str, binary: &'static str, mode: &str) -> Daemon {
    let dir = base().join(tag);
    let _ = fs::remove_dir_all(&dir);
    fs::create_dir_all(&dir).unwrap();
    let sock = dir.join("kurashid.sock");
    let f = |name: &str| dir.join(name).to_string_lossy().into_owned();
    let probe = Probe {
        binary,
        args: vec![
            "--mode".into(),
            mode.into(),
            "--socket".into(),
            sock.to_string_lossy().into_owned(),
            "--start".into(),
            f("start.txt"),
            "--term".into(),
            f("term.txt"),
            "--token".into(),
            f("token.txt"),
            "--report".into(),
            f("report.txt"),
        ],
    };

    let hub = Hub::new();
    let store: Arc<ConfigStore> = ConfigStore::open(
        hub.clone(),
        kurashi_schema::v1::registry(),
        Paths::rooted(&dir.join("config")),
        Options::default(),
    );
    let mut actions = ActionRegistry::default();
    wiring::ui(&hub, &mut actions);
    wiring::mods_native(
        &hub,
        &mut actions,
        vec![Path::new(env!("CARGO_MANIFEST_DIR")).join("tests/data/hosts/mods")],
        Some(store.clone()),
        vec![Box::new(probe) as Box<dyn NativeMod>],
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
    let d = Daemon {
        dir,
        hub,
        actions,
        sock,
        _stop: stop,
    };
    d.actions
        .invoke("mod.enable", json!({"id": "probe"}))
        .await
        .expect("the probe enables");
    d
}

impl Daemon {
    fn file(&self, name: &str) -> PathBuf {
        self.dir.join(name)
    }

    fn lines(&self, name: &str) -> Vec<String> {
        fs::read_to_string(self.file(name))
            .unwrap_or_default()
            .lines()
            .map(str::to_string)
            .collect()
    }

    async fn state(&self) -> String {
        self.actions
            .invoke("probe.state", json!({}))
            .await
            .unwrap()
            .unwrap()["state"]
            .as_str()
            .unwrap()
            .to_string()
    }

    async fn act(&self, id: &str) {
        self.actions.invoke(id, json!({})).await.unwrap();
    }

    /// The reasons the `mods` document gives for the probe running now.
    fn running_reasons(&self) -> Vec<String> {
        let (_, doc) = self.hub.snapshot("mods").unwrap();
        doc["mods"]
            .as_array()
            .unwrap()
            .iter()
            .find(|m| m["id"] == "probe")
            .map(|m| {
                m["running_reasons"]
                    .as_array()
                    .unwrap()
                    .iter()
                    .map(|v| v.as_str().unwrap().to_string())
                    .collect()
            })
            .unwrap_or_default()
    }
}

/// Waits until the host reports `want` (its state changes from the daemon's own tasks).
async fn wait_for(d: &Daemon, want: &str) {
    for _ in 0..300 {
        if d.state().await == want {
            return;
        }
        tokio::time::sleep(Duration::from_millis(20)).await;
    }
    let logs: String = fs::read_dir(base().join("state"))
        .into_iter()
        .flatten()
        .flatten()
        .filter_map(|e| {
            fs::read_to_string(e.path())
                .ok()
                .map(|t| format!("{}:\n{t}", e.path().display()))
        })
        .collect();
    panic!(
        "the host did not reach {want}: it is {}\n{logs}",
        d.state().await
    );
}

/// Waits until `check` holds (a file the program writes, a report line).
async fn eventually(mut check: impl FnMut() -> bool) {
    for _ in 0..300 {
        if check() {
            return;
        }
        tokio::time::sleep(Duration::from_millis(20)).await;
    }
    panic!("not reached within 6 s");
}

/// Sends a `hello` with `token` for `mod_id` and returns the daemon's first answer.
async fn hello_with(sock: &Path, mod_id: &str, token: &str) -> ServerMsg {
    let (rd, mut wr) = UnixStream::connect(sock).await.unwrap().into_split();
    let mut reader = LineReader::new(rd);
    let hello = ClientMsg::Hello {
        v: 1,
        client: "test".into(),
        caps: vec![],
        scope: Some(Scope {
            mod_id: mod_id.into(),
            token: token.into(),
        }),
    };
    write_msg(&mut wr, &hello).await.unwrap();
    reader.next_value::<ServerMsg>().await.unwrap().unwrap()
}

#[tokio::test]
async fn a_host_starts_connects_stops_and_is_listed_as_running() {
    let _gate = GATE.lock().await;
    let d = start("start-stop", "fake-host", "hold").await;
    assert_eq!(d.state().await, "off");
    assert!(d.running_reasons().is_empty());

    d.act("probe.start").await;
    wait_for(&d, "ready").await;
    assert_eq!(d.lines("start.txt").len(), 1, "one program started");
    assert_eq!(
        d.running_reasons(),
        ["mods.running.host"],
        "K33: a host that runs is listed"
    );

    d.act("probe.stop").await;
    assert_eq!(d.state().await, "off", "stop is off at once");
    eventually(|| d.file("term.txt").exists()).await;
    eventually(|| d.running_reasons().is_empty()).await;
    shutdown_all().await;
}

#[tokio::test]
async fn a_scoped_connection_reaches_its_own_mod_and_nothing_else() {
    let _gate = GATE.lock().await;
    let d = start("scope", "fake-host", "probe").await;
    d.act("probe.start").await;
    wait_for(&d, "ready").await;
    eventually(|| d.lines("report.txt").iter().any(|l| l.contains("\"pong\""))).await;

    // The fake host asked, in order: its own document (ok), another (forbidden), its own action (done), another
    // mod's action (forbidden), an intent (forbidden), `theme` (ok) and `ping` (pong).
    let replies: Vec<Value> = d
        .lines("report.txt")
        .iter()
        .map(|l| serde_json::from_str(l).unwrap())
        .collect();
    let reply = |id: &str| {
        replies
            .iter()
            .find(|r| r["id"] == id)
            .unwrap_or_else(|| panic!("a reply to {id}"))
            .clone()
    };
    assert_eq!(reply("p1")["t"], "snap");
    assert_eq!(reply("p2")["t"], "err");
    assert_eq!(reply("p2")["kind"], "forbidden");
    assert_eq!(reply("p3")["t"], "done");
    assert_eq!(reply("p4")["kind"], "forbidden");
    // `theme` passes the scope; this harness registers no theme document, so the daemon answers unknown_doc
    // (a production daemon serves a snapshot). What must not happen is a refusal by scope.
    assert_ne!(reply("p5")["kind"], "forbidden");
    assert!(
        replies
            .iter()
            .any(|r| r["t"] == "err" && r["kind"] == "forbidden" && r.get("id").is_none()),
        "the intent is forbidden"
    );
    // The connection stayed open: the host is ready, not restarted.
    assert_eq!(d.state().await, "ready");
    assert_eq!(d.lines("start.txt").len(), 1);
    shutdown_all().await;
}

#[tokio::test]
async fn a_token_the_daemon_did_not_issue_or_one_held_is_refused_with_goodbye_scope() {
    let _gate = GATE.lock().await;
    let d = start("tokens", "fake-host", "hold").await;
    d.act("probe.start").await;
    wait_for(&d, "ready").await;
    let token = d
        .lines("token.txt")
        .last()
        .cloned()
        .expect("the host's token");

    let unknown = hello_with(&d.sock, "probe", "00112233445566778899aabbccddeeff").await;
    assert!(
        matches!(&unknown, ServerMsg::Goodbye { reason, .. } if reason == "scope"),
        "an unknown token: {unknown:?}"
    );
    let other_mod = hello_with(&d.sock, "weather", &token).await;
    assert!(
        matches!(&other_mod, ServerMsg::Goodbye { reason, .. } if reason == "scope"),
        "a token for another mod: {other_mod:?}"
    );
    // The host's own token, while its connection holds it.
    let held = hello_with(&d.sock, "probe", &token).await;
    assert!(
        matches!(&held, ServerMsg::Goodbye { reason, .. } if reason == "scope"),
        "a held token: {held:?}"
    );
    assert_eq!(
        d.state().await,
        "ready",
        "the refusals did not touch the host"
    );
    shutdown_all().await;
}

#[tokio::test]
async fn a_program_that_is_not_installed_is_missing() {
    let _gate = GATE.lock().await;
    let d = start("missing", "absent-host", "hold").await;
    d.act("probe.start").await;
    assert_eq!(d.state().await, "missing");
    assert!(d.lines("start.txt").is_empty(), "nothing ran");
    assert!(d.running_reasons().is_empty());
    shutdown_all().await;
}

#[tokio::test]
async fn a_host_that_exits_twice_is_restarted_once_and_then_failed() {
    let _gate = GATE.lock().await;
    let d = start("crash", "fake-host", "exit").await;
    d.act("probe.start").await;
    wait_for(&d, "failed").await;
    assert_eq!(
        d.lines("start.txt").len(),
        2,
        "one restart, then the failure"
    );
    assert!(d.running_reasons().is_empty());
    shutdown_all().await;
}

#[tokio::test]
async fn disabling_the_mod_stops_its_host() {
    let _gate = GATE.lock().await;
    let d = start("disable", "fake-host", "hold").await;
    d.act("probe.start").await;
    wait_for(&d, "ready").await;
    d.actions
        .invoke("mod.disable", json!({"id": "probe"}))
        .await
        .unwrap();
    eventually(|| d.file("term.txt").exists()).await;
    assert_eq!(
        d.lines("start.txt").len(),
        1,
        "a disabled mod starts nothing"
    );
    shutdown_all().await;
}

#[tokio::test]
async fn daemon_shutdown_stops_every_host() {
    let _gate = GATE.lock().await;
    let d = start("shutdown", "fake-host", "hold").await;
    d.act("probe.start").await;
    wait_for(&d, "ready").await;
    shutdown_all().await;
    eventually(|| d.file("term.txt").exists()).await;
    assert_eq!(d.state().await, "off");
}
