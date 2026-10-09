//! kurashid binary: socket lifecycle and wiring. Stores, services and actions are registered
//! here as they land (docs/ROADMAP.md); the protocol machinery lives in the library.

use std::sync::Arc;

use anyhow::Context;
use kurashid::{ActionRegistry, Daemon, Hub, Intents};
use serde_json::json;
use tokio::net::UnixListener;

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    tracing_subscriber::fmt()
        .with_env_filter(
            tracing_subscriber::EnvFilter::try_from_default_env().unwrap_or_else(|_| "info".into()),
        )
        .with_writer(std::io::stderr)
        .init();

    let path = kurashi_core::default_socket_path();
    if let Some(dir) = path.parent() {
        std::fs::create_dir_all(dir).with_context(|| format!("create {}", dir.display()))?;
    }
    let _ = std::fs::remove_file(&path);
    let listener = UnixListener::bind(&path).with_context(|| format!("bind {}", path.display()))?;
    {
        use std::os::unix::fs::PermissionsExt;
        std::fs::set_permissions(&path, std::fs::Permissions::from_mode(0o600))?;
    }

    let hub = Hub::new();
    hub.register(
        "daemon",
        json!({"version": env!("CARGO_PKG_VERSION")}),
        None,
    );
    let locale = kurashid::i18n::locale_from_env();
    hub.register(
        "i18n",
        kurashid::i18n::document(&kurashid::i18n::data_dir().join("i18n"), &locale),
        None,
    );
    let mut actions = ActionRegistry::default();
    // niri first (ARCHITECTURE §7); other adapters slot in here. Without a compositor socket the
    // document stays empty rather than pretending (Shōjiki).
    match std::env::var_os("NIRI_SOCKET") {
        Some(sock) => {
            let sock = std::path::PathBuf::from(sock);
            let provider = kurashid::workspaces::WorkspacesProvider::new(move || {
                kurashi_compositor::niri::NiriCompositor::spawn(sock.clone())
            });
            provider.register_actions(&mut actions);
            hub.register(
                kurashid::workspaces::DOC,
                json!({"outputs": {}}),
                Some(provider),
            );
        }
        None => {
            tracing::warn!("NIRI_SOCKET not set: svc.workspaces stays empty");
            hub.register(kurashid::workspaces::DOC, json!({"outputs": {}}), None);
        }
    }
    let daemon = Arc::new(Daemon::new(hub, actions, Intents::default()));
    tracing::info!(socket = %path.display(), instance = %daemon.instance, "kurashid listening");

    let mut term = tokio::signal::unix::signal(tokio::signal::unix::SignalKind::terminate())?;
    let shutdown = async move {
        tokio::select! {
            _ = tokio::signal::ctrl_c() => {}
            _ = term.recv() => {}
        }
    };
    kurashid::server::serve(listener, daemon, shutdown).await;
    let _ = std::fs::remove_file(&path);
    tracing::info!("kurashid stopped");
    Ok(())
}
