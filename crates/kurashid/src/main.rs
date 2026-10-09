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
    // Island faces come from config once M1.5 wires it; core faces for now (K9).
    let island = kurashid::island::IslandHost::new(
        hub.clone(),
        "main",
        kurashi_island::IslandConfig {
            faces: vec!["clock".into(), "media".into(), "notifications".into()],
            default: "clock".into(),
            // The volume OSD may interrupt a manual face choice; it is transient-only.
            interruptible_by: ["volume".to_string()].into(),
            ..Default::default()
        },
        &["clock", "media", "notifications", "volume"],
    );
    island.register_actions(&mut actions);
    register_services(&hub, &island, &mut actions);
    let mut fc_ok: Option<bool> = None;
    let config = match kurashi_config::Paths::from_xdg() {
        Some(paths) => {
            let store = kurashid::config::ConfigStore::open(
                hub.clone(),
                kurashi_schema::v1::registry(),
                paths,
                kurashi_config::Options {
                    bundled_profile_dirs: vec![kurashid::i18n::data_dir().join("profiles")],
                    migrations: Vec::new(),
                },
            );
            store.register_actions(&mut actions);
            // fc-list once at startup (subprocess); fonts installed later need a restart for now.
            let fonts: Arc<dyn kurashi_theme::FontProvider + Send + Sync> =
                match kurashi_theme::FcList::query() {
                    Ok(f) => {
                        fc_ok = Some(true);
                        Arc::new(f)
                    }
                    Err(e) => {
                        fc_ok = Some(false);
                        tracing::warn!(error = %e, "fc-list unavailable; font chains unresolved");
                        Arc::new(kurashi_theme::FakeFonts::new(&[]))
                    }
                };
            kurashid::theme::register(&hub, &store, fonts);
            Some(store)
        }
        None => {
            tracing::error!("no XDG config dir: running without config (defaults only)");
            None
        }
    };
    // Kept alive for the daemon's lifetime.
    let _watcher = config.clone().and_then(|c| {
        kurashid::config::watch(c)
            .map_err(|e| tracing::warn!(error = %e, "config watcher unavailable"))
            .ok()
    });
    kurashid::clock::register(&hub);
    kurashid::wiring::ui(&hub, &mut actions);
    kurashid::wiring::notifications(
        &hub,
        &mut actions,
        config.as_deref(),
        kurashid::xdg_dir("cache").join("notify-img"),
        Some(island.clone()),
    );
    kurashid::wiring::mods(
        &hub,
        &mut actions,
        vec![
            kurashid::i18n::data_dir().join("mods"),
            kurashid::xdg_dir("data").join("mods"),
        ],
    );
    let mut intents = Intents::default();
    kurashid::wiring::audio(&hub, &mut actions, &mut intents, Some(island.clone()));
    kurashid::wiring::lock(&hub, &mut actions, &mut intents);
    let mut daemon = Daemon::new(hub, actions, intents);
    kurashid::wiring::launcher(&mut daemon, config.as_deref(), kurashid::xdg_dir("state"));
    // Only facts we know synchronously; bus/notification probes stay n/a until they report
    // asynchronously (Shōjiki: n/a, never a guessed ok).
    kurashid::doctor::register(
        &mut daemon,
        kurashid::doctor::DoctorFacts {
            compositor_socket: Some(
                std::env::var_os("NIRI_SOCKET").is_some_and(|p| std::path::Path::new(&p).exists()),
            ),
            fc_list_worked: fc_ok,
            data_dir_found: Some(kurashid::i18n::data_dir().join("i18n").is_dir()),
            ..Default::default()
        },
    );
    daemon.config = config;
    daemon.caps = vec!["undo".into(), "profiles".into(), "island".into()];
    let daemon = Arc::new(daemon);
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

/// D-Bus services as refcounted documents (ARCHITECTURE §1, rule 5). Media also feeds the Island.
fn register_services(
    hub: &Arc<Hub>,
    island: &Arc<kurashid::island::IslandHost>,
    actions: &mut ActionRegistry,
) {
    use kurashi_services::{brightness, media, network, power, session};
    use kurashid::services::{Bus, ServiceProvider};

    let isl = island.clone();
    let media = Arc::new(
        ServiceProvider::new("svc.media", Bus::Session, media::start).observe(move |doc| {
            let playing = doc["playing"].as_bool().unwrap_or(false);
            isl.signal(kurashi_island::FaceSignal {
                face: "media".into(),
                relevance: if playing { 60 } else { 0 },
                condition: playing,
                transient: None,
            });
        }),
    );
    hub.register("svc.media", json!({"playing": false}), Some(media.clone()));
    for (id, which) in [
        ("media.play_pause", 0),
        ("media.next", 1),
        ("media.prev", 2),
    ] {
        let media = media.clone();
        actions.register(id, &format!("action.{id}"), move |_| {
            let cmds = media.commands();
            async move {
                let cmds = cmds.ok_or_else(|| {
                    kurashid::ActionError::Unavailable("media service not running".into())
                })?;
                match which {
                    0 => cmds.play_pause().await,
                    1 => cmds.next().await,
                    _ => cmds.prev().await,
                }
                .map_err(|e| kurashid::ActionError::Unavailable(e.to_string()))?;
                Ok(None)
            }
        });
    }

    // power has no commands (and its marker type isn't Clone).
    let power = Arc::new(ServiceProvider::new(
        "svc.power",
        Bus::System,
        |c, s| async move { power::start(c, s).await.map(|(h, _)| (h, ())) },
    ));
    hub.register("svc.power", json!({"present": false}), Some(power));
    let session = Arc::new(ServiceProvider::new(
        "svc.session",
        Bus::System,
        session::start,
    ));
    hub.register("svc.session", json!({}), Some(session));
    let network = Arc::new(ServiceProvider::new(
        "svc.network",
        Bus::System,
        network::start,
    ));
    hub.register("svc.network", json!({"state": "unknown"}), Some(network));
    let brightness = Arc::new(ServiceProvider::new(
        "svc.brightness",
        Bus::System,
        brightness::start,
    ));
    hub.register("svc.brightness", json!({}), Some(brightness));
}
