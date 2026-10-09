//! The real executor (`SystemExec`) against fake backend binaries on a temporary PATH: shell scripts
//! that log their argv and keep a marker for "the daemon runs". The awww and awww-daemon on the
//! user's session are never run by a test.

use std::os::unix::fs::PermissionsExt;
use std::path::{Path, PathBuf};
use std::sync::Arc;

use kurashi_mod_api::{ModCtx, NativeMod, Settings, Values};
use kurashi_mod_wallpaper::{Dirs, Exec, SystemExec, Wallpaper};
use serde_json::{Value, json};
use tokio::sync::watch;

const CLIENT: &str = r#"#!/bin/sh
echo "awww $*" >> "$KURASHI_FAKE_LOG"
case "$1" in
  --version) echo "awww 0.12.1" ;;
  query)
    if [ -f "$KURASHI_FAKE_STATE/daemon" ]; then
      echo '{"": [{"name": "DP-1", "width": 2560, "height": 1440, "scale": 1, "displaying": {"color": "000000"}}]}'
    else
      echo "Failed to connect to the awww-daemon socket" >&2
      exit 1
    fi ;;
  kill) rm -f "$KURASHI_FAKE_STATE/daemon" ;;
esac
exit 0
"#;

const DAEMON: &str = r#"#!/bin/sh
echo "awww-daemon $*" >> "$KURASHI_FAKE_LOG"
touch "$KURASHI_FAKE_STATE/daemon"
"#;

fn scratch(tag: &str) -> PathBuf {
    let dir = std::env::temp_dir().join(format!("kurashi-wp-fake-{tag}-{}", std::process::id()));
    let _ = std::fs::remove_dir_all(&dir);
    std::fs::create_dir_all(&dir).unwrap();
    dir
}

fn script(path: &Path, body: &str) {
    std::fs::write(path, body).unwrap();
    std::fs::set_permissions(path, std::fs::Permissions::from_mode(0o755)).unwrap();
}

/// Enables the wallpaper with `exec` and returns its document and actions the way kurashid would.
struct Live {
    doc: watch::Receiver<Value>,
    actions: Vec<(String, kurashi_mod_api::ActionFn)>,
    _settings: watch::Sender<Values>,
}

fn enable(exec: Arc<dyn Exec>, dirs: Dirs, folder: &Path) -> Live {
    let mut values = Values::new();
    for (k, v) in [
        ("backend", json!("awww")),
        ("folders", json!(folder.display().to_string())),
        ("fit", json!("crop")),
        ("crop_anchor", json!("center")),
        ("transition", json!("none")),
        ("transition_duration", json!(1.0)),
        ("transition_angle", json!(45)),
        ("rotate", json!(0)),
        ("rotate_order", json!("alphabetical")),
        ("rotate_per_output", json!(false)),
        ("restore", json!(true)),
    ] {
        values.insert(k.into(), v);
    }
    let (settings_tx, settings_rx) = watch::channel(values);
    let provides: Vec<String> = [
        "service:wallpaper",
        "action:wallpaper.*",
        "panel:wallpaper",
        "choices:wallpaper.backends",
        "slot:quick.tiles",
    ]
    .iter()
    .map(|s| s.to_string())
    .collect();
    struct Quiet;
    impl kurashi_mod_api::Hooks for Quiet {
        fn face(&self, _: &str, _: kurashi_mod_api::FaceUpdate) {}
        fn choices_changed(&self, _: &str) {}
    }
    let mut ctx = ModCtx::new(
        &provides,
        Settings::new(settings_rx.clone()),
        Arc::new(Quiet),
    );
    Wallpaper::with(exec, dirs).enable(&mut ctx).unwrap();
    let (doc_tx, doc) = watch::channel(Value::Null);
    let doc_tx = Arc::new(doc_tx);
    let mut actions = Vec::new();
    for r in ctx.finish().unwrap() {
        match r {
            kurashi_mod_api::Registration::Service { run, .. } => {
                let tx = doc_tx.clone();
                let publish: kurashi_mod_api::Publish = Arc::new(move |v| {
                    let _ = tx.send(v);
                });
                tokio::spawn(run(publish, Settings::new(settings_rx.clone())));
            }
            kurashi_mod_api::Registration::Action { id, handler, .. } => {
                actions.push((id, handler))
            }
            _ => {}
        }
    }
    Live {
        doc,
        actions,
        _settings: settings_tx,
    }
}

impl Live {
    async fn act(
        &self,
        id: &str,
        args: Value,
    ) -> Result<Option<Value>, kurashi_mod_api::ActionError> {
        let h = self
            .actions
            .iter()
            .find(|(i, _)| i == id)
            .unwrap()
            .1
            .clone();
        h(args).await
    }
}

#[tokio::test]
async fn the_real_executor_starts_the_daemon_once_and_logs_the_flags_of_each_img() {
    let root = scratch("real");
    let bin = root.join("bin");
    let state = root.join("state");
    let folder = root.join("pics");
    for d in [&bin, &state, &folder] {
        std::fs::create_dir_all(d).unwrap();
    }
    let log = root.join("calls.log");
    script(&bin.join("awww"), CLIENT);
    script(&bin.join("awww-daemon"), DAEMON);
    // A picture the backend could show: `set` reads the header before it asks the backend.
    image::RgbImage::from_pixel(1, 1, image::Rgb([90, 120, 200]))
        .save(folder.join("a.png"))
        .unwrap();
    let exec = Arc::new(SystemExec::with(
        vec![bin.clone()],
        vec![
            ("KURASHI_FAKE_LOG".into(), log.display().to_string()),
            ("KURASHI_FAKE_STATE".into(), state.display().to_string()),
        ],
    ));

    let live = enable(exec, Dirs::rooted(&root), &folder);
    let mut doc = live.doc.clone();
    tokio::time::timeout(std::time::Duration::from_secs(10), async {
        while doc.borrow_and_update()["loaded"] != true {
            doc.changed().await.unwrap();
        }
    })
    .await
    .expect("the backend was looked at");
    assert_eq!(doc.borrow()["backend"]["version"], "0.12.1");
    assert_eq!(doc.borrow()["outputs"]["DP-1"]["width"], 2560);

    let path = folder.join("a.png");
    live.act("wallpaper.set", json!({"path": path, "output": "DP-1"}))
        .await
        .unwrap();
    let text = std::fs::read_to_string(&log).unwrap();
    let lines: Vec<&str> = text.lines().collect();
    assert_eq!(
        lines
            .iter()
            .filter(|l| l.starts_with("awww-daemon"))
            .count(),
        1,
        "the daemon started once: {text}"
    );
    // The first query fails (no daemon), the daemon starts, the query answers, then the version.
    assert_eq!(lines.first(), Some(&"awww query --json"));
    assert!(lines.contains(&"awww --version"));
    assert!(lines.contains(&"awww-daemon --no-cache"));
    let img = format!(
        "awww img {} --outputs DP-1 --resize crop --crop-gravity center \
         --transition-type none --transition-duration 1.00 --transition-angle 45",
        path.display()
    );
    assert!(lines.contains(&img.as_str()), "argv logged:\n{text}");
}

#[tokio::test]
async fn a_binary_that_is_not_on_the_path_is_a_reason_not_a_crash() {
    let root = scratch("nopath");
    let empty = root.join("empty-bin");
    std::fs::create_dir_all(&empty).unwrap();
    let folder = root.join("pics");
    std::fs::create_dir_all(&folder).unwrap();
    let exec = Arc::new(SystemExec::with(vec![empty], Vec::new()));
    let live = enable(exec, Dirs::rooted(&root), &folder);
    let mut doc = live.doc.clone();
    tokio::time::timeout(std::time::Duration::from_secs(10), async {
        while doc.borrow_and_update()["loaded"] != true {
            doc.changed().await.unwrap();
        }
    })
    .await
    .expect("looked at");
    assert_eq!(doc.borrow()["available"], false);
    assert_eq!(
        doc.borrow()["backend"]["reason"],
        "mod-wallpaper.backend.missing"
    );
    let refused = live.act("wallpaper.next", json!({})).await.unwrap_err();
    assert_eq!(refused.to_string(), "mod-wallpaper.backend.missing");
}
