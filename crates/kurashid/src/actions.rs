//! Action registry: every user-triggerable operation has a stable id (`island.next`,
//! `audio.mute.toggle`, …). Input bindings, the CLI and mods all invoke actions by id
//! (ARCHITECTURE §6), so behaviour never lives in a renderer.
//!
//! Clones share one table: the daemon's registry and the handles native mods keep (K26) see the same
//! actions, and a mod's actions are registered and removed while the daemon runs.

use std::collections::BTreeMap;
use std::future::Future;
use std::pin::Pin;
use std::sync::{Arc, RwLock};

use serde::Serialize;
use serde_json::Value;

pub type ActionResult = Result<Option<Value>, ActionError>;
type Handler =
    Arc<dyn Fn(Value) -> Pin<Box<dyn Future<Output = ActionResult> + Send>> + Send + Sync>;

#[derive(Debug, thiserror::Error, PartialEq)]
pub enum ActionError {
    #[error("unknown action {0}")]
    Unknown(String),
    #[error("{0}")]
    Invalid(String),
    #[error("{0}")]
    Unavailable(String),
    #[error("{0}")]
    Internal(String),
}

impl ActionError {
    /// PROTOCOL §7 error kind.
    pub fn kind(&self) -> &'static str {
        match self {
            ActionError::Unknown(_) => "unknown_action",
            ActionError::Invalid(_) => "invalid",
            ActionError::Unavailable(_) => "unavailable",
            ActionError::Internal(_) => "internal",
        }
    }
}

/// What Settings needs to offer an action in a binding picker.
#[derive(Debug, Clone, Serialize, PartialEq)]
pub struct ActionMeta {
    pub id: String,
    /// i18n key (rule 8).
    pub label: String,
}

type Table = BTreeMap<String, (ActionMeta, Handler)>;

#[derive(Clone, Default)]
pub struct ActionRegistry {
    map: Arc<RwLock<Table>>,
}

impl ActionRegistry {
    /// Registers `id`, replacing an action of the same id. `&mut` as before for the startup code;
    /// the table itself is shared, so a native mod's handle registers at runtime too (K26).
    pub fn register<F, Fut>(&mut self, id: &str, label: &str, handler: F)
    where
        F: Fn(Value) -> Fut + Send + Sync + 'static,
        Fut: Future<Output = ActionResult> + Send + 'static,
    {
        let meta = ActionMeta {
            id: id.into(),
            label: label.into(),
        };
        let h: Handler = Arc::new(move |args| Box::pin(handler(args)));
        self.map
            .write()
            .expect("actions lock")
            .insert(id.into(), (meta, h));
    }

    pub fn contains(&self, id: &str) -> bool {
        self.map.read().expect("actions lock").contains_key(id)
    }

    /// Removes `id`; invoking it afterwards is `unknown_action`. False when there was none.
    pub fn unregister(&self, id: &str) -> bool {
        self.map.write().expect("actions lock").remove(id).is_some()
    }

    pub async fn invoke(&self, id: &str, args: Value) -> ActionResult {
        // The lock is released before the handler runs.
        let handler = match self.map.read().expect("actions lock").get(id) {
            Some((_, h)) => h.clone(),
            None => return Err(ActionError::Unknown(id.into())),
        };
        handler(args).await
    }

    pub fn list(&self) -> Vec<ActionMeta> {
        self.map
            .read()
            .expect("actions lock")
            .values()
            .map(|(m, _)| m.clone())
            .collect()
    }
}
