//! kurashid — the daemon that owns all state (K2). The binary in `main.rs` only wires the
//! socket; everything testable lives here.

pub mod actions;
pub mod hub;
pub mod intents;
pub mod server;

use std::sync::Arc;

pub use actions::{ActionError, ActionRegistry};
pub use hub::{Hub, Provider};
pub use intents::Intents;

/// Shared daemon state handed to every connection.
pub struct Daemon {
    pub hub: Arc<Hub>,
    pub actions: ActionRegistry,
    pub intents: Arc<Intents>,
    pub caps: Vec<String>,
    /// Changes every start (PROTOCOL §2).
    pub instance: String,
}

impl Daemon {
    pub fn new(hub: Arc<Hub>, actions: ActionRegistry, intents: Intents) -> Self {
        Daemon {
            hub,
            actions,
            intents: Arc::new(intents),
            caps: Vec::new(),
            instance: new_instance_id(),
        }
    }
}

fn new_instance_id() -> String {
    let nanos = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map_or(0, |d| d.as_nanos());
    format!("{:x}{:x}", nanos as u64, std::process::id())
}
