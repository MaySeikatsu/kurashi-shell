//! kurashid — the daemon that owns all state (K2). The binary in `main.rs` only wires the
//! socket; everything testable lives here.

pub mod actions;
pub mod bindings;
pub mod capabilities;
pub mod clock;
pub mod config;
pub mod doctor;
pub mod greeter_cache;
pub mod hub;
pub mod i18n;
pub mod icons;
pub mod intents;
pub mod island;
pub mod keys;
pub mod native;
pub mod os_scheme;
pub mod server;
pub mod services;
pub mod texture;
pub mod theme;
pub mod theme_export;
pub mod wiring;
pub mod workspaces;

use std::sync::Arc;

pub use actions::{ActionError, ActionRegistry};
pub use hub::{Hub, Provider};
pub use intents::Intents;

/// A `query` provider (PROTOCOL §6): query text → result items.
pub type QueryFn = Arc<dyn Fn(&str) -> Vec<serde_json::Value> + Send + Sync>;

/// Shared daemon state handed to every connection.
pub struct Daemon {
    pub hub: Arc<Hub>,
    pub actions: ActionRegistry,
    pub intents: Arc<Intents>,
    pub caps: Vec<String>,
    /// Changes every start (PROTOCOL §2).
    pub instance: String,
    /// `None` only in protocol tests that don't need config.
    pub config: Option<Arc<config::ConfigStore>>,
    /// `query` providers by `kind` (e.g. `launcher`).
    pub queries: std::collections::BTreeMap<String, QueryFn>,
}

impl Daemon {
    pub fn new(hub: Arc<Hub>, actions: ActionRegistry, intents: Intents) -> Self {
        Daemon {
            hub,
            actions,
            intents: Arc::new(intents),
            caps: Vec::new(),
            instance: new_instance_id(),
            config: None,
            queries: Default::default(),
        }
    }
}

fn new_instance_id() -> String {
    let nanos = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map_or(0, |d| d.as_nanos());
    format!("{:x}{:x}", nanos as u64, std::process::id())
}

/// `$XDG_<kind>_HOME/kurashi` with the spec's fallbacks (`state` → ~/.local/state, `cache` →
/// ~/.cache, `data` → ~/.local/share).
pub fn xdg_dir(kind: &str) -> std::path::PathBuf {
    let (var, fallback) = match kind {
        "state" => ("XDG_STATE_HOME", ".local/state"),
        "cache" => ("XDG_CACHE_HOME", ".cache"),
        _ => ("XDG_DATA_HOME", ".local/share"),
    };
    let base = std::env::var_os(var)
        .filter(|v| !v.is_empty())
        .map(std::path::PathBuf::from)
        .unwrap_or_else(|| {
            std::path::PathBuf::from(std::env::var_os("HOME").unwrap_or_default()).join(fallback)
        });
    base.join("kurashi")
}
