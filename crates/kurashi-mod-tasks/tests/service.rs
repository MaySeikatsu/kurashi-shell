//! The mod enabled the way the daemon does it (a `ModCtx` with a settings feed), on real files in a temporary folder:
//! the actions write, the service publishes, an edit made behind its back arrives through the watch, and the watch
//! ends with the service (Ma).

use std::sync::{Arc, Mutex};
use std::time::Duration;

use kurashi_mod_api::{
    ActionFn, FaceUpdate, Hooks, ModCtx, NativeMod, Registration, ServiceFn, Settings, Values,
};
use kurashi_mod_tasks::{Paths, TasksMod};
use serde_json::{Value, json};
use tokio::sync::watch;

struct NoHooks;
impl Hooks for NoHooks {
    fn face(&self, _face: &str, _update: FaceUpdate) {}
    fn choices_changed(&self, _source: &str) {}
}

struct Enabled {
    regs: Vec<Registration>,
    tx: watch::Sender<Values>,
}

impl Enabled {
    fn service(&self) -> (Value, ServiceFn) {
        self.regs
            .iter()
            .find_map(|r| match r {
                Registration::Service { initial, run, .. } => Some((initial.clone(), run.clone())),
                _ => None,
            })
            .expect("a service")
    }
    fn action(&self, id: &str) -> ActionFn {
        self.regs
            .iter()
            .find_map(|r| match r {
                Registration::Action { id: i, handler, .. } if i == id => Some(handler.clone()),
                _ => None,
            })
            .unwrap_or_else(|| panic!("action {id}"))
    }
}

fn enable(m: &TasksMod, values: Values) -> Enabled {
    let provides: Vec<String> = [
        "service:tasks",
        "action:tasks.*",
        "desk:tasks",
        "desk:notes",
    ]
    .iter()
    .map(|s| (*s).to_owned())
    .collect();
    let (tx, rx) = watch::channel(values);
    let mut ctx = ModCtx::new(&provides, Settings::new(rx), Arc::new(NoHooks));
    m.enable(&mut ctx).expect("enables");
    Enabled {
        regs: ctx.finish().expect("no refused registration"),
        tx,
    }
}

type Seen = Arc<Mutex<Vec<Value>>>;

fn last(seen: &Seen) -> Value {
    seen.lock().unwrap().last().cloned().unwrap_or(Value::Null)
}

async fn wait_for(seen: &Seen, what: &str, ok: impl Fn(&Value) -> bool) -> Value {
    for _ in 0..100 {
        let v = last(seen);
        if ok(&v) {
            return v;
        }
        tokio::time::sleep(Duration::from_millis(50)).await;
    }
    panic!("{what}: last document {}", last(seen));
}

fn texts(d: &Value) -> Vec<String> {
    d["tasks"]
        .as_array()
        .map(|a| {
            a.iter()
                .map(|t| t["text"].as_str().unwrap_or("").to_owned())
                .collect()
        })
        .unwrap_or_default()
}

#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn add_toggle_external_edit_and_notes() {
    let dir = tempfile::tempdir().expect("tempdir");
    let paths = Paths {
        data_dir: dir.path().join("data/kurashi"),
        home: dir.path().to_path_buf(),
    };
    let m = TasksMod::with(paths, Arc::new(|| "2026-10-20".to_owned()));
    let values: Values = [
        ("file".to_owned(), json!("~/vault/Tasks.md")),
        ("notes_file".to_owned(), json!("")),
        ("show_done".to_owned(), json!(true)),
    ]
    .into_iter()
    .collect();
    let e = enable(&m, values);
    let (initial, run) = e.service();
    assert_eq!(initial["state"], "missing");
    assert_eq!(initial["notes"]["state"], "missing");
    let file = dir.path().join("vault/Tasks.md");
    assert_eq!(initial["file"], file.to_string_lossy().as_ref());

    let seen: Seen = Arc::default();
    let s2 = seen.clone();
    let service = tokio::spawn(run(
        Arc::new(move |v| s2.lock().unwrap().push(v)),
        Settings::new(e.tx.subscribe()),
    ));
    wait_for(&seen, "first publish", |d| d["state"] == "missing").await;

    // Two adds: the file and its folder are made.
    let add = e.action("tasks.add");
    let first = add(json!({"text": "Buy milk"}))
        .await
        .expect("add")
        .expect("reply");
    add(json!({"text": "  Call\nmum  "})).await.expect("add");
    let d = wait_for(&seen, "two tasks", |d| d["open"] == 2).await;
    assert_eq!(d["state"], "ready");
    assert_eq!(texts(&d), ["Buy milk", "Call mum"]);
    assert_eq!(
        std::fs::read_to_string(&file).unwrap(),
        "- [ ] Buy milk\n- [ ] Call mum\n"
    );

    // Toggle: done today, kept in the list, struck through by the views.
    let toggle = e.action("tasks.toggle");
    let r = toggle(json!({"id": first["id"]}))
        .await
        .expect("toggle")
        .expect("reply");
    assert_eq!(r["done"], true);
    let d = wait_for(&seen, "one done", |d| d["done"] == 1).await;
    assert_eq!(d["tasks"][0]["done"], true);
    assert!(
        std::fs::read_to_string(&file)
            .unwrap()
            .contains("- [x] Buy milk ✅ 2026-10-20\n")
    );

    // An edit behind the daemon's back: the watch publishes it; the untouched item keeps its id.
    let call_id = d["tasks"][1]["id"].clone();
    std::fs::write(
        &file,
        "# Inbox\n- [ ] Call mum\n- [ ] Water plants 📅 2026-10-21\n",
    )
    .unwrap();
    let d = wait_for(&seen, "external edit", |d| {
        texts(d).contains(&"Water plants".to_owned())
    })
    .await;
    assert_eq!(d["tasks"][0]["id"], call_id);
    assert_eq!(d["tasks"][1]["due"], "2026-10-21");
    assert_eq!(d["tasks"][1]["section"], "Inbox");

    // An action for an item that is gone answers so, and the file stays.
    let err = toggle(json!({"id": first["id"]})).await.unwrap_err();
    assert_eq!(
        err,
        kurashi_mod_api::ActionError::Unavailable("mod-tasks.error.gone".into())
    );
    let bad = add(json!({"text": "   "})).await.unwrap_err();
    assert_eq!(
        bad,
        kurashi_mod_api::ActionError::Invalid("mod-tasks.error.text".into())
    );

    // Edit, remove, clear done.
    let edit = e.action("tasks.edit");
    let r = edit(json!({"id": call_id, "text": "Call mum back"}))
        .await
        .expect("edit")
        .expect("reply");
    assert_ne!(r["id"], call_id);
    e.action("tasks.remove")(json!({"id": r["id"]}))
        .await
        .expect("remove");
    let d = wait_for(&seen, "removed", |d| d["open"] == 1).await;
    assert_eq!(texts(&d), ["Water plants"]);
    let water = d["tasks"][0]["id"].clone();
    toggle(json!({"id": water})).await.expect("toggle");
    let r = e.action("tasks.clear_done")(json!({}))
        .await
        .expect("clear")
        .expect("reply");
    assert_eq!(r["removed"], 1);
    let d = wait_for(&seen, "cleared", |d| d["open"] == 0 && d["done"] == 0).await;
    assert_eq!(d["state"], "ready");
    assert_eq!(std::fs::read_to_string(&file).unwrap(), "# Inbox\n");

    // The note: written whole, published as LF.
    let notes = e.action("tasks.notes.set");
    notes(json!({"text": "# Groceries\nmilk\n"}))
        .await
        .expect("notes");
    let d = wait_for(&seen, "note", |d| d["notes"]["state"] == "ready").await;
    assert_eq!(d["notes"]["text"], "# Groceries\nmilk\n");
    let note_file = dir.path().join("data/kurashi/notes.md");
    assert_eq!(
        std::fs::read_to_string(&note_file).unwrap(),
        "# Groceries\nmilk\n"
    );

    // The settings feed ends (the mod is disabled): the service ends with its watch.
    drop(e.tx);
    tokio::time::timeout(Duration::from_secs(2), service)
        .await
        .expect("the service ends with its settings feed")
        .expect("no panic");
}

#[cfg(unix)]
#[tokio::test]
async fn read_only_refuses_writes() {
    use std::os::unix::fs::PermissionsExt;
    let dir = tempfile::tempdir().expect("tempdir");
    let file = dir.path().join("t.md");
    std::fs::write(&file, "- [ ] a\n").unwrap();
    std::fs::set_permissions(&file, std::fs::Permissions::from_mode(0o444)).unwrap();
    let paths = Paths {
        data_dir: dir.path().to_path_buf(),
        home: dir.path().to_path_buf(),
    };
    let m = TasksMod::with(paths, Arc::new(|| "2026-10-20".to_owned()));
    let values: Values = [("file".to_owned(), json!(file.to_string_lossy()))]
        .into_iter()
        .collect();
    let e = enable(&m, values);
    let (initial, _) = e.service();
    assert_eq!(initial["state"], "ready");
    assert_eq!(initial["reason"], "mod-tasks.read_only");
    let err = e.action("tasks.add")(json!({"text": "b"}))
        .await
        .unwrap_err();
    assert_eq!(
        err,
        kurashi_mod_api::ActionError::Unavailable("mod-tasks.error.read_only".into())
    );
    assert_eq!(std::fs::read_to_string(&file).unwrap(), "- [ ] a\n");
}
