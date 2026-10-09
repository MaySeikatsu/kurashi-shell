//! CLI command functions against an in-process kurashid on a temp socket and temp config root.
//! Never touches the real socket or ~/.config.

use std::sync::Arc;
use std::sync::atomic::{AtomicUsize, Ordering};

use kurashi::{ConfigCmd, Conn, EXIT_OK, EXIT_REJECTED, EXIT_UNAVAILABLE, Output, ProfileCmd, run};
use kurashid::{ActionRegistry, Daemon, Hub, Intents, config::ConfigStore};

async fn start() -> Conn {
    static N: AtomicUsize = AtomicUsize::new(0);
    let n = N.fetch_add(1, Ordering::SeqCst);
    let root = std::env::temp_dir().join(format!("kurashi-cli-{}-{n}", std::process::id()));
    let _ = std::fs::remove_dir_all(&root);
    std::fs::create_dir_all(&root).unwrap();
    let sock = root.join("ipc.sock");

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
    daemon.config = Some(store);
    let listener = tokio::net::UnixListener::bind(&sock).unwrap();
    tokio::spawn(kurashid::server::serve(
        listener,
        Arc::new(daemon),
        std::future::pending(),
    ));
    Conn::connect(&sock).await.unwrap()
}

async fn go(c: &mut Conn, cmd: ConfigCmd) -> Output {
    run(c, cmd, false).await.unwrap()
}

fn get(key: &str) -> ConfigCmd {
    ConfigCmd::Get {
        key: key.into(),
        output: None,
    }
}

fn reset(key: &str) -> ConfigCmd {
    ConfigCmd::Reset {
        key: key.into(),
        output: None,
    }
}

fn set(args: &[&str], dry_run: bool) -> ConfigCmd {
    ConfigCmd::Set {
        args: args.iter().map(|s| s.to_string()).collect(),
        output: None,
        dry_run,
    }
}

fn prof(f: fn(String, Option<Vec<String>>) -> ProfileCmd, name: &str) -> ConfigCmd {
    ConfigCmd::Profile(f(name.into(), None))
}

#[tokio::test]
async fn get_set_why_undo_redo() {
    let mut c = start().await;
    let o = go(&mut c, get("bar.height")).await;
    assert_eq!(o.code, EXIT_OK);
    assert!(o.text.starts_with("bar.height = "), "{}", o.text);
    assert!(o.text.ends_with("(default)"), "{}", o.text);

    let o = go(&mut c, set(&["bar.height", "44"], false)).await;
    assert_eq!(o.code, EXIT_OK, "{}", o.text);
    assert!(o.text.starts_with("applied rev "), "{}", o.text);
    assert_eq!(
        go(&mut c, get("bar.height")).await.text,
        "bar.height = 44   (user)"
    );

    let why = go(
        &mut c,
        ConfigCmd::Why {
            key: "bar.height".into(),
            output: None,
        },
    )
    .await;
    let lines: Vec<&str> = why.text.lines().collect();
    assert_eq!(lines[0], "bar.height");
    assert!(lines[1].contains("default"), "{}", why.text);
    let last = lines.last().unwrap();
    assert!(
        last.starts_with('*') && last.contains("user"),
        "{}",
        why.text
    );

    assert_eq!(go(&mut c, ConfigCmd::Undo).await.code, EXIT_OK);
    assert!(
        go(&mut c, get("bar.height"))
            .await
            .text
            .ends_with("(default)")
    );
    assert_eq!(go(&mut c, ConfigCmd::Redo).await.code, EXIT_OK);
    assert_eq!(
        go(&mut c, get("bar.height")).await.text,
        "bar.height = 44   (user)"
    );

    assert_eq!(go(&mut c, reset("bar.height")).await.code, EXIT_OK);
    assert!(
        go(&mut c, get("bar.height"))
            .await
            .text
            .ends_with("(default)")
    );
}

#[tokio::test]
async fn dry_run_does_not_commit_and_json_works() {
    let mut c = start().await;
    let o = go(&mut c, set(&["bar.height=44"], true)).await;
    assert_eq!(o.code, EXIT_OK);
    assert!(o.text.starts_with("bar.height: "), "{}", o.text);
    assert!(o.text.contains("->"), "{}", o.text);
    assert!(
        go(&mut c, get("bar.height"))
            .await
            .text
            .ends_with("(default)")
    );

    let o = run(&mut c, get("bar.height"), true).await.unwrap();
    let v: serde_json::Value = serde_json::from_str(&o.text).unwrap();
    assert_eq!(v["source"]["kind"], "default");
}

#[tokio::test]
async fn rejected_batch_is_atomic_with_exit_2() {
    let mut c = start().await;
    let o = go(&mut c, set(&["bar.height=44", "no.such.key=1"], false)).await;
    assert_eq!(o.code, EXIT_REJECTED);
    assert!(o.text.starts_with("rejected no.such.key"), "{}", o.text);
    // The valid op in the same batch must not have landed.
    assert!(
        go(&mut c, get("bar.height"))
            .await
            .text
            .ends_with("(default)")
    );
}

#[tokio::test]
async fn profile_save_list_preview_load() {
    let mut c = start().await;
    go(&mut c, set(&["bar.height", "44"], false)).await;
    let o = go(
        &mut c,
        prof(|name, sections| ProfileCmd::Save { name, sections }, "mine"),
    )
    .await;
    assert!(o.text.starts_with("saved "), "{}", o.text);
    go(&mut c, reset("bar.height")).await;

    let o = go(&mut c, ConfigCmd::Profile(ProfileCmd::List)).await;
    assert!(o.text.lines().any(|l| l == "mine"), "{}", o.text);

    let o = go(
        &mut c,
        prof(
            |name, sections| ProfileCmd::Preview { name, sections },
            "mine",
        ),
    )
    .await;
    assert!(o.text.contains("bar.height"), "{}", o.text);
    assert!(
        go(&mut c, get("bar.height"))
            .await
            .text
            .ends_with("(default)")
    );

    let o = go(
        &mut c,
        prof(|name, sections| ProfileCmd::Load { name, sections }, "mine"),
    )
    .await;
    assert!(o.text.starts_with("applied rev "), "{}", o.text);
    assert_eq!(
        go(&mut c, get("bar.height")).await.text,
        "bar.height = 44   (profile: mine)"
    );
}

#[tokio::test]
async fn missing_socket_is_unavailable() {
    let e = Conn::connect(std::path::Path::new("/nonexistent/kurashi-test.sock"))
        .await
        .err()
        .unwrap();
    assert_eq!(e.exit_code(), EXIT_UNAVAILABLE);
}
