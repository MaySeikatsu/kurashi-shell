//! What the host tests share (rule 10): a daemon over its own config root, with the mods wiring and its socket served.

use std::path::{Path, PathBuf};
use std::sync::Arc;

use kurashi_config::{Options, Paths};
use kurashi_mod_api::NativeMod;
use kurashid::config::ConfigStore;
use kurashid::{ActionRegistry, Hub, wiring};
use tokio::sync::oneshot;

/// The daemon's parts a test drives; dropping `_stop` ends the server.
pub struct Served {
    pub hub: Arc<Hub>,
    pub actions: ActionRegistry,
    pub _stop: oneshot::Sender<()>,
}

/// A daemon whose config lives under `dir/config`, with the mods of `roots` and the `linked` crates, listening on `sock`.
pub fn serve(
    dir: &Path,
    sock: &Path,
    roots: Vec<PathBuf>,
    linked: Vec<Box<dyn NativeMod>>,
) -> Served {
    let hub = Hub::new();
    let store: Arc<ConfigStore> = ConfigStore::open(
        hub.clone(),
        kurashi_schema::v1::registry(),
        Paths::rooted(&dir.join("config")),
        Options::default(),
    );
    let mut actions = ActionRegistry::default();
    wiring::ui(&hub, &mut actions);
    wiring::mods_native(&hub, &mut actions, roots, Some(store.clone()), linked, None);
    let mut daemon =
        kurashid::Daemon::new(hub.clone(), actions.clone(), kurashid::Intents::default());
    daemon.config = Some(store);
    let listener = tokio::net::UnixListener::bind(sock).unwrap();
    let (stop, stopped) = oneshot::channel::<()>();
    tokio::spawn(kurashid::server::serve(listener, Arc::new(daemon), async {
        let _ = stopped.await;
    }));
    Served {
        hub,
        actions,
        _stop: stop,
    }
}
