//! The mod enabled against a fake noren (never the user's: the runner is injected) and a fake compositor.

use std::sync::{Arc, Mutex};

use kurashi_mod_api::{
    ActionFn, FaceUpdate, Hooks, LauncherSpec, ModCtx, Registration, Settings, SettingsError,
    Values,
};
use serde_json::{Value, json};
use tokio::sync::watch;

use crate::SessionsMod;
use crate::desk::{Desktop, Live, Space, Step};
use crate::noren::Runner;

#[derive(Default)]
struct Rec {
    writes: Mutex<Vec<(String, Value)>>,
    /// The other mods' actions the mod called (W91), and whether the terminal is there to take them.
    called: Mutex<Vec<(String, Value)>>,
    terminal_off: std::sync::atomic::AtomicBool,
}

impl Hooks for Rec {
    fn face(&self, _face: &str, _update: FaceUpdate) {}
    fn choices_changed(&self, _source: &str) {}
    fn set_setting(&self, key: &str, value: Value) -> Result<(), SettingsError> {
        self.writes.lock().unwrap().push((key.into(), value));
        Ok(())
    }
    fn call(
        &self,
        action: &str,
        args: Value,
    ) -> kurashi_mod_api::BoxFuture<Result<Option<Value>, kurashi_mod_api::ActionError>> {
        let off = action.starts_with("terminal.")
            && self.terminal_off.load(std::sync::atomic::Ordering::SeqCst);
        if !off {
            self.called.lock().unwrap().push((action.into(), args));
        }
        Box::pin(async move {
            if off {
                Err(kurashi_mod_api::ActionError::Unavailable(
                    kurashi_mod_api::USE_UNAVAILABLE.into(),
                ))
            } else {
                Ok(None)
            }
        })
    }
}

struct Stub {
    calls: Mutex<Vec<Vec<String>>>,
}

impl Runner for Stub {
    fn run(&self, _program: &std::path::Path, args: &[&str]) -> Result<String, String> {
        self.calls
            .lock()
            .unwrap()
            .push(args.iter().map(|s| (*s).to_string()).collect());
        Ok("zellij\tkurashi\t/\tlive\t▢ kurashi\nzoxide\ttmp\t/tmp\tdir\t📁 tmp\n".into())
    }
}

struct OneWindow;
impl Desktop for OneWindow {
    fn list(&self) -> Result<(Vec<Space>, Vec<Live>), String> {
        Ok((
            vec![Space {
                id: 1,
                name: None,
                output: Some("O".into()),
                focused: true,
            }],
            vec![Live {
                id: 7,
                app_id: "kitty".into(),
                title: "t".into(),
                workspace: Some(1),
                pid: None,
                column: Some((1, 1)),
                size: (640, 480),
                floating: false,
                at: None,
            }],
        ))
    }
    fn act(&self, _step: &Step) -> Result<(), String> {
        Ok(())
    }
}

struct Enabled {
    actions: Vec<(String, ActionFn)>,
    launcher: LauncherSpec,
    doc: watch::Receiver<Value>,
    rec: Arc<Rec>,
    stub: Arc<Stub>,
    _feed: watch::Sender<Values>,
}

impl Enabled {
    async fn act(
        &self,
        id: &str,
        args: Value,
    ) -> Result<Option<Value>, kurashi_mod_api::ActionError> {
        let h = &self.actions.iter().find(|(a, _)| a == id).unwrap().1;
        h(args).await
    }
    async fn until(&mut self, f: impl Fn(&Value) -> bool) -> Value {
        for _ in 0..100 {
            let d = self.doc.borrow().clone();
            if f(&d) {
                return d;
            }
            let _ = tokio::time::timeout(std::time::Duration::from_millis(50), self.doc.changed())
                .await;
        }
        panic!("never: {}", self.doc.borrow().clone());
    }
}

async fn enable(command: &str, dir: &std::path::Path) -> Enabled {
    let manifest = std::fs::read_to_string(concat!(
        env!("CARGO_MANIFEST_DIR"),
        "/../../mods/sessions/mod.toml"
    ))
    .unwrap();
    let provides: Vec<String> = manifest
        .lines()
        .skip_while(|l| !l.starts_with("provides"))
        .skip(1)
        .take_while(|l| !l.starts_with(']'))
        .filter_map(|l| {
            l.trim()
                .strip_prefix('"')?
                .split('"')
                .next()
                .map(String::from)
        })
        .collect();
    let mut values = Values::new();
    values.insert("command".into(), json!(command));
    let (tx, rx) = watch::channel(values);
    let rec = Arc::new(Rec::default());
    let stub = Arc::new(Stub {
        calls: Mutex::new(vec![]),
    });
    let m = SessionsMod::with(
        dir.to_path_buf(),
        dir.join("state"),
        stub.clone(),
        Some(Arc::new(OneWindow)),
    );
    let uses: Vec<String> = [
        "action:terminal.run?",
        "action:terminal.open_dir?",
        "action:webdock.open?",
        "action:settings.open",
    ]
    .iter()
    .map(|u| (*u).to_string())
    .collect();
    let mut ctx = ModCtx::new(&provides, Settings::new(rx), rec.clone()).with_uses(&uses);
    use kurashi_mod_api::NativeMod;
    m.enable(&mut ctx).unwrap();
    let mut actions = vec![];
    let mut launcher = None;
    let mut service = None;
    for r in ctx.finish().unwrap() {
        match r {
            Registration::Action { id, handler, .. } => actions.push((id, handler)),
            Registration::Launcher { spec, .. } => launcher = Some(spec),
            Registration::Service { run, .. } => service = Some(run),
            _ => {}
        }
    }
    let (dtx, drx) = watch::channel(Value::Null);
    let publish: kurashi_mod_api::Publish = Arc::new(move |v| {
        let _ = dtx.send(v);
    });
    let (_t2, r2) = watch::channel(Values::new());
    tokio::spawn((service.unwrap())(publish, Settings::new(r2)));
    Enabled {
        actions,
        launcher: launcher.unwrap(),
        doc: drx,
        rec,
        stub,
        _feed: tx,
    }
}

fn exe(dir: &std::path::Path) -> String {
    use std::os::unix::fs::PermissionsExt;
    let p = dir.join("noren");
    std::fs::write(&p, "#!/bin/sh\n").unwrap();
    std::fs::set_permissions(&p, std::fs::Permissions::from_mode(0o755)).unwrap();
    p.to_string_lossy().into_owned()
}

#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn without_noren_the_mod_enables_and_says_why() {
    let dir = tempfile::tempdir().unwrap();
    let mut e = enable("/nonexistent/noren", dir.path()).await;
    let d = e.until(|d| d["noren"]["state"] == "missing").await;
    assert_eq!(d["available"], false);
    assert_eq!(d["noren"]["reason"], "sessions.state.missing");
    assert!(e.stub.calls.lock().unwrap().is_empty(), "nothing ran");
    let rows = (e.launcher.query)("noren");
    assert_eq!(rows[0].action, "sessions.help");
    assert_eq!(
        e.act("sessions.open", json!({"path": "/tmp", "via": "kurashi"}))
            .await
            .unwrap_err(),
        kurashi_mod_api::ActionError::Unavailable("sessions.error.no_noren".into())
    );
}

#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn list_step_handoff_remember_and_desk() {
    let dir = tempfile::tempdir().unwrap();
    let noren = exe(dir.path());
    let mut e = enable(&noren, dir.path()).await;
    e.until(|d| d["available"] == true).await;
    assert_eq!(e.stub.calls.lock().unwrap()[0], ["list", "all"]);
    let rows = (e.launcher.query)("ku");
    assert_eq!(rows[0].name, "kurashi");
    assert_eq!(rows[0].action, "sessions.open");
    assert_eq!(
        e.act("sessions.open", rows[0].args.clone()).await.unwrap(),
        Some(json!({"ask": true}))
    );
    e.until(|d| d["choosing"]["name"] == "kurashi").await;
    e.act(
        "sessions.choose",
        json!({"via": "kurashi", "remember": true}),
    )
    .await
    .unwrap();
    // W91: the mod calls the terminal itself — no surface is mapped here, and nothing rides in the document.
    let d = e.until(|d| d.get("choosing").is_none()).await;
    assert!(d.get("handoff").is_none());
    {
        let called = e.rec.called.lock().unwrap();
        assert_eq!(called[0].0, "terminal.run");
        assert_eq!(called[0].1["text"], format!("'{noren}' connect 'kurashi'"));
    }
    assert_eq!(
        e.rec.writes.lock().unwrap()[0],
        (
            "projects".into(),
            json!([{"path": "/", "open_in": "kurashi", "desk": false}])
        )
    );
    // the current project's desk
    let r = e
        .act("sessions.desk.save", json!({}))
        .await
        .unwrap()
        .unwrap();
    assert_eq!(r, json!({"project": "/", "windows": 1}));
    let d = e.until(|d| d["desks"]["/"]["windows"] == 1).await;
    assert_eq!(d["collect"]["project"], "/");
    let saved = std::fs::read_to_string(dir.path().join("state/state.json")).unwrap();
    assert!(saved.contains("kitty"));
    e.act("sessions.desk.restore", json!({})).await.unwrap();
    e.until(|d| d["notice"]["key"] == "sessions.notice.restored")
        .await;
}

/// W91: In Kurashi with the terminal mod off never does nothing — the call is not delivered, and the step comes back
/// with the reason.
#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn a_call_the_terminal_cannot_take_brings_the_step_back() {
    let dir = tempfile::tempdir().unwrap();
    let noren = exe(dir.path());
    let mut e = enable(&noren, dir.path()).await;
    e.until(|d| d["available"] == true).await;
    e.rec
        .terminal_off
        .store(true, std::sync::atomic::Ordering::SeqCst);
    let rows = (e.launcher.query)("ku");
    e.act("sessions.open", rows[0].args.clone()).await.unwrap();
    e.until(|d| d["choosing"]["name"] == "kurashi").await;
    e.act("sessions.choose", json!({"via": "kurashi"}))
        .await
        .unwrap();
    let d = e
        .until(|d| d["notice"]["key"] == "sessions.notice.mod_off")
        .await;
    assert_eq!(d["choosing"]["name"], "kurashi");
    assert!(e.rec.called.lock().unwrap().is_empty());
}
