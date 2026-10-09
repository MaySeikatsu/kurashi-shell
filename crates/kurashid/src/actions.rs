//! Action registry: every user-triggerable operation has a stable id (`island.next`,
//! `audio.mute.toggle`, …). Input bindings, the CLI and mods all invoke actions by id
//! (ARCHITECTURE §6), so behaviour never lives in a renderer.

use std::collections::BTreeMap;
use std::future::Future;
use std::pin::Pin;
use std::sync::Arc;

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

#[derive(Default)]
pub struct ActionRegistry {
    map: BTreeMap<String, (ActionMeta, Handler)>,
}

impl ActionRegistry {
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
        self.map.insert(id.into(), (meta, h));
    }

    pub async fn invoke(&self, id: &str, args: Value) -> ActionResult {
        let handler = match self.map.get(id) {
            Some((_, h)) => h.clone(),
            None => return Err(ActionError::Unknown(id.into())),
        };
        handler(args).await
    }

    pub fn list(&self) -> impl Iterator<Item = &ActionMeta> {
        self.map.values().map(|(m, _)| m)
    }
}
