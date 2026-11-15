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
    /// The arguments it takes, as the `actions` query lists them (`{target, output?}`); empty for none or not described.
    pub args: String,
    /// K154: what the action's declaration adds — its icon, the word(s) of its `>` command, the mod it belongs to.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub icon: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub command: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none", rename = "mod")]
    pub module: Option<String>,
    /// The declaration (`[[action]]`): its typed arguments are checked before the handler runs.
    #[serde(skip)]
    pub decl: Option<Arc<kurashi_mods::ActionDecl>>,
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
        self.register_with_args(id, label, "", handler);
    }

    /// [`register`](Self::register), naming the arguments for `kurashi act --list` (PROTOCOL §6, the `actions` query).
    pub fn register_with_args<F, Fut>(&mut self, id: &str, label: &str, args: &str, handler: F)
    where
        F: Fn(Value) -> Fut + Send + Sync + 'static,
        Fut: Future<Output = ActionResult> + Send + 'static,
    {
        let meta = ActionMeta {
            id: id.into(),
            label: label.into(),
            args: args.into(),
            icon: None,
            command: None,
            module: None,
            decl: None,
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
        let (handler, decl) = match self.map.read().expect("actions lock").get(id) {
            Some((m, h)) => (h.clone(), m.decl.clone()),
            None => return Err(ActionError::Unknown(id.into())),
        };
        // K154: declared arguments are checked here, once, and their defaults filled in.
        // The answer is the catalogue's key (views translate `msg`); the daemon's log names the argument.
        let args = match decl {
            Some(d) => d.check(&args).map_err(|arg| {
                tracing::warn!(
                    "action {id}: argument `{arg}` is missing or not what its declaration says"
                );
                ActionError::Invalid(crate::wiring::ARGS_INVALID.into())
            })?,
            None => args,
        };
        handler(args).await
    }

    /// Lays a mod's `[[action]]` declaration over the registered action `id` (K154): its typed arguments (the
    /// display form follows them), icon and `>` command. False when there is no such action.
    pub fn declare(&self, id: &str, decl: &kurashi_mods::ActionDecl, module: &str) -> bool {
        match self.map.write().expect("actions lock").get_mut(id) {
            Some((meta, _)) => {
                if decl.args.is_some() {
                    meta.args = decl.args_display();
                }
                meta.icon = decl.icon.clone();
                meta.command = decl.command.clone();
                meta.module = Some(module.into());
                meta.decl = Some(Arc::new(decl.clone()));
                true
            }
            None => false,
        }
    }

    /// The declared `>` commands (K154), by id.
    pub fn commands(&self) -> Vec<ActionMeta> {
        let mut list = self.list();
        list.retain(|m| m.command.is_some());
        list.sort_by(|a, b| a.id.cmp(&b.id));
        list
    }

    pub fn list(&self) -> Vec<ActionMeta> {
        self.map
            .read()
            .expect("actions lock")
            .values()
            .map(|(m, _)| m.clone())
            .collect()
    }

    /// Names the arguments of an action registered without them (one described where it is wired up, not where its
    /// handler is). False when there is no such action.
    pub fn describe(&self, id: &str, args: &str) -> bool {
        match self.map.write().expect("actions lock").get_mut(id) {
            Some((meta, _)) => {
                meta.args = args.into();
                true
            }
            None => false,
        }
    }

    /// The `actions` query (PROTOCOL §6): every action whose id contains `q`, by id, as `{id, args, help}` — `help` the
    /// label's text in the daemon's language (`strings`, the `i18n` document's), else the label's key.
    pub fn query(&self, q: &str, strings: &Value) -> Vec<Value> {
        let mut list = self.list();
        list.retain(|m| m.id.contains(q));
        list.sort_by(|a, b| a.id.cmp(&b.id));
        list.into_iter()
            .map(|m| {
                let help = strings[&m.label]
                    .as_str()
                    .map_or_else(|| m.label.clone(), str::to_owned);
                let mut row = serde_json::json!({"id": m.id, "args": m.args, "help": help});
                // K154 (additive, K17): what a declaration adds.
                if let Some(d) = &m.decl
                    && let Some(args) = &d.args
                {
                    row["schema"] = serde_json::json!(args);
                }
                for (k, v) in [
                    ("icon", &m.icon),
                    ("command", &m.command),
                    ("mod", &m.module),
                ] {
                    if let Some(v) = v {
                        row[k] = serde_json::json!(v);
                    }
                }
                row
            })
            .collect()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    async fn the_actions_query_lists_ids_arguments_and_help() {
        let mut reg = ActionRegistry::default();
        reg.register_with_args(
            "layout.toggle",
            "action.layout.toggle",
            "{target, output?}",
            |_| async { Ok(None) },
        );
        reg.register("island.next", "action.island.next", |_| async { Ok(None) });
        assert!(reg.describe("island.next", "{island?}"));
        assert!(!reg.describe("nope", ""));
        let strings =
            serde_json::json!({"action.layout.toggle": "Show or hide a part of the layout"});
        let items = reg.query("", &strings);
        assert_eq!(
            items,
            [
                serde_json::json!({"id": "island.next", "args": "{island?}", "help": "action.island.next"}),
                serde_json::json!({"id": "layout.toggle", "args": "{target, output?}",
                                   "help": "Show or hide a part of the layout"}),
            ]
        );
        assert_eq!(reg.query("layout", &strings).len(), 1);
    }

    /// K154: a declaration types the arguments (checked before the handler, defaults filled in), names the icon and
    /// the `>` command, and the `actions` query says so.
    #[tokio::test]
    async fn a_declared_action_checks_its_arguments_and_lists_its_schema() {
        let mut reg = ActionRegistry::default();
        reg.register("timer.start", "mod-timer.action.start", |args| async move {
            Ok(Some(args))
        });
        let m = kurashi_mods::parse(
            "timer",
            r#"id = "timer"
name = "Timer"
version = "0.1.0"
tier = "native"
kurashi = ">=0.0.1"
provides = ["action:timer.*"]
[[action]]
id = "timer.start"
label = "mod-timer.action.start"
icon = "timer"
command = "timer"
  [[action.arg]]
  name = "minutes"
  type = "int"
  range = [1, 600]
  optional = true
  rest = true
  [[action.arg]]
  name = "sound"
  type = "bool"
  default = true
"#,
            &semver::Version::new(0, 3, 0),
        )
        .unwrap();
        let decl = m.contract.action("timer.start").unwrap();
        assert!(reg.declare("timer.start", decl, "timer"));
        assert!(!reg.declare("timer.nope", decl, "timer"));
        let done = reg
            .invoke("timer.start", serde_json::json!({"minutes": 5}))
            .await
            .unwrap();
        assert_eq!(done, Some(serde_json::json!({"minutes": 5, "sound": true})));
        let err = reg
            .invoke("timer.start", serde_json::json!({"minutes": 0}))
            .await
            .unwrap_err();
        assert_eq!(err, ActionError::Invalid("error.args.invalid".into()));
        assert_eq!(
            decl.command_args("25"),
            Some(serde_json::json!({"minutes": 25}))
        );
        assert_eq!(decl.command_args(""), Some(serde_json::json!({})));
        assert_eq!(decl.command_args("soon"), None);
        let row = &reg.query("timer", &serde_json::json!({}))[0];
        assert_eq!(row["args"], "{minutes?, sound?}");
        assert_eq!(row["icon"], "timer");
        assert_eq!(row["command"], "timer");
        assert_eq!(row["mod"], "timer");
        assert_eq!(row["schema"][0]["type"], "int");
        assert_eq!(reg.commands().len(), 1);
    }
}
