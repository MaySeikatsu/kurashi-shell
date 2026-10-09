//! `kurashi doctor` against an in-process daemon on a temp socket (never the real one).

use std::sync::Arc;

use kurashi::doctor::{client_checks, run_doctor};
use kurashi::{EXIT_ERR, EXIT_OK, EXIT_UNAVAILABLE};
use kurashid::doctor::{DoctorFacts, register};
use kurashid::{ActionRegistry, Daemon, Hub, Intents, config::ConfigStore};

async fn start(name: &str, facts: DoctorFacts) -> std::path::PathBuf {
    let root = std::env::temp_dir().join(format!("kurashi-doctor-{}-{name}", std::process::id()));
    let _ = std::fs::remove_dir_all(&root);
    std::fs::create_dir_all(&root).unwrap();
    let sock = root.join("ipc.sock");
    let hub = Hub::new();
    let store = ConfigStore::open(
        hub.clone(),
        kurashi_schema::v1::registry(),
        kurashi_config::Paths::rooted(&root),
        kurashi_config::Options::default(),
    );
    let mut daemon = Daemon::new(hub, ActionRegistry::default(), Intents::default());
    daemon.config = Some(store);
    register(&mut daemon, facts);
    let listener = tokio::net::UnixListener::bind(&sock).unwrap();
    tokio::spawn(kurashid::server::serve(
        listener,
        Arc::new(daemon),
        std::future::pending(),
    ));
    sock
}

fn status(items: &[serde_json::Value], id: &str) -> String {
    items.iter().find(|i| i["id"] == id).unwrap()["status"]
        .as_str()
        .unwrap()
        .to_string()
}

#[tokio::test]
async fn healthy_facts_exit_zero_with_ok_warn_and_na_rows() {
    let sock = start(
        "warn",
        DoctorFacts {
            compositor_socket: Some(true),
            session_bus: Some(true),
            system_bus: Some(false), // warn
            data_dir_found: Some(true),
            ..Default::default() // notifications / fonts: n/a
        },
    )
    .await;
    let out = run_doctor(&sock, true).await;
    assert_eq!(out.code, EXIT_OK, "{}", out.text);
    let items: Vec<serde_json::Value> = serde_json::from_str(&out.text).unwrap();
    assert_eq!(status(&items, "compositor"), "ok");
    assert_eq!(status(&items, "bus_system"), "warn");
    assert_eq!(status(&items, "fonts"), "n/a");
    assert_eq!(status(&items, "protocol"), "ok");
    let warn = items.iter().find(|i| i["id"] == "bus_system").unwrap();
    assert_eq!(warn["fix_key"], "doctor.bus_system.fix");
    assert_eq!(warn["summary_key"], "doctor.bus_system.warn");
}

#[tokio::test]
async fn failing_fact_exits_one_and_renders_fix() {
    let sock = start(
        "fail",
        DoctorFacts {
            compositor_socket: Some(false),
            ..Default::default()
        },
    )
    .await;
    let out = run_doctor(&sock, false).await;
    assert_eq!(out.code, EXIT_ERR);
    assert!(out.text.contains('✘'), "{}", out.text);
    assert!(
        out.text.contains("Compositor socket not found"),
        "{}",
        out.text
    );
    assert!(out.text.contains("fix:"), "{}", out.text);
}

#[tokio::test]
async fn unreachable_daemon_runs_client_checks_and_exits_three() {
    let missing =
        std::env::temp_dir().join(format!("kurashi-doctor-none-{}.sock", std::process::id()));
    let out = run_doctor(&missing, false).await;
    assert_eq!(out.code, EXIT_UNAVAILABLE);
    assert!(out.text.contains("Socket file missing"), "{}", out.text);
    let json = run_doctor(&missing, true).await;
    let v: serde_json::Value = serde_json::from_str(&json.text).unwrap();
    assert_eq!(v["daemon"], "unreachable");
}

#[test]
fn client_checks_read_the_environment() {
    let env = |k: &str| (k == "NIRI_SOCKET").then(|| "/run/niri".to_string());
    let items = client_checks(std::path::Path::new("/nonexistent/ipc.sock"), &env);
    assert_eq!(status(&items, "client_socket"), "fail");
    assert_eq!(status(&items, "client_runtime_dir"), "warn");
    assert_eq!(status(&items, "client_niri"), "ok");
}
