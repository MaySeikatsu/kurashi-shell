//! Input bindings (ARCHITECTURE §6): every component's universal slots (`<component>.input.<slot>`)
//! resolved from config into the `bindings` document, and `input.dispatch` as the frontend's one
//! entry point for clicks and scrolls. Unbound slots (empty action) are absent, never null.

use std::sync::{Arc, OnceLock, Weak};

use serde_json::{Map, Value, json};

use crate::Daemon;
use crate::actions::{ActionError, ActionRegistry};
use crate::config::ConfigStore;
use crate::hub::Hub;

pub const DOC: &str = "bindings";

/// Resolved bindings: `{ "<component>": { "<slot>": {action, source, forced_by?} } }`.
pub fn resolve(cfg: &ConfigStore) -> Value {
    let mut out: Map<String, Value> = Map::new();
    for key in kurashi_schema::v1::registry().keys() {
        let Some((component, slot)) = key.split_once(".input.") else {
            continue;
        };
        let Some(p) = cfg.get(key, None) else {
            continue;
        };
        let Some(action) = p.value.as_str().filter(|a| !a.is_empty()) else {
            continue;
        };
        let mut e = json!({"action": action, "source": p.source});
        if let Some(f) = &p.forced_by {
            e["forced_by"] = json!(f);
        }
        out.entry(component)
            .or_insert_with(|| json!({}))
            .as_object_mut()
            .expect("object")
            .insert(slot.into(), e);
    }
    Value::Object(out)
}

pub struct Bindings {
    cfg: Arc<ConfigStore>,
    daemon: OnceLock<Weak<Daemon>>,
}

impl Bindings {
    /// Registers the `bindings` document and keeps it current on every config change.
    pub fn new(hub: &Arc<Hub>, cfg: Arc<ConfigStore>) -> Arc<Self> {
        hub.register(DOC, resolve(&cfg), None);
        let h = hub.clone();
        cfg.on_change(move |c| {
            let _ = h.set(DOC, resolve(c), None);
        });
        Arc::new(Bindings {
            cfg,
            daemon: OnceLock::new(),
        })
    }

    /// The action registry lives inside `Daemon`; call once after `Arc::new(daemon)` so
    /// `input.dispatch` can invoke the bound action (weak: no cycle).
    pub fn attach(&self, daemon: &Arc<Daemon>) {
        let _ = self.daemon.set(Arc::downgrade(daemon));
    }

    /// `input.dispatch {component, slot, args?}`: look up the binding, invoke its action.
    pub fn register_actions(self: &Arc<Self>, actions: &mut ActionRegistry) {
        let me = self.clone();
        actions.register(
            "input.dispatch",
            "action.input.dispatch",
            move |v: Value| {
                let me = me.clone();
                async move {
                    let field = |k: &str| {
                        v.get(k).and_then(Value::as_str).ok_or_else(|| {
                            ActionError::Invalid(format!("input.dispatch needs {k}"))
                        })
                    };
                    let (component, slot) = (field("component")?, field("slot")?);
                    let key = format!("{component}.input.{slot}");
                    let action = me
                        .cfg
                        .get(&key, None)
                        .and_then(|p| p.value.as_str().map(String::from))
                        .filter(|a| !a.is_empty());
                    // An unbound slot is a no-op, not an error: the UI may send every click.
                    let Some(action) = action else {
                        return Ok(None);
                    };
                    let daemon =
                        me.daemon.get().and_then(Weak::upgrade).ok_or_else(|| {
                            ActionError::Unavailable("bindings not attached".into())
                        })?;
                    let args = v.get("args").cloned().unwrap_or(Value::Null);
                    daemon.actions.invoke(&action, args).await
                }
            },
        );
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::Intents;
    use std::sync::atomic::{AtomicUsize, Ordering};

    static N: AtomicUsize = AtomicUsize::new(0);

    fn setup(user_toml: &str) -> (Arc<Hub>, Arc<ConfigStore>, std::path::PathBuf) {
        let root = std::env::temp_dir().join(format!(
            "kurashid-bind-{}-{}",
            std::process::id(),
            N.fetch_add(1, Ordering::SeqCst)
        ));
        let _ = std::fs::remove_dir_all(&root);
        let paths = kurashi_config::Paths::rooted(&root);
        if !user_toml.is_empty() {
            let f = paths.user_file();
            std::fs::create_dir_all(f.parent().unwrap()).unwrap();
            std::fs::write(f, user_toml).unwrap();
        }
        let hub = Hub::new();
        let cfg = ConfigStore::open(
            hub.clone(),
            kurashi_schema::v1::registry(),
            paths,
            kurashi_config::Options::default(),
        );
        (hub, cfg, root)
    }

    #[tokio::test]
    async fn doc_shows_provenance_and_follows_changes() {
        let (hub, cfg, root) = setup("[island.main.input]\nleft = \"test.hit\"\n");
        let _b = Bindings::new(&hub, cfg.clone());
        let doc = hub.snapshot(DOC).unwrap().1;
        assert_eq!(doc["island.main"]["left"]["action"], "test.hit");
        assert_eq!(doc["island.main"]["left"]["source"]["kind"], "user");
        assert_eq!(doc["island.main"]["scroll_up"]["source"]["kind"], "default");
        assert!(
            doc["island.main"].get("middle").is_none(),
            "unbound = absent"
        );
        cfg.apply(&[kurashi_ipc::ApplyOp::Set {
            set: "island.main.input.right".into(),
            value: json!("test.other"),
            output: None,
        }])
        .unwrap();
        let doc = hub.snapshot(DOC).unwrap().1;
        assert_eq!(doc["island.main"]["right"]["action"], "test.other");
        let _ = std::fs::remove_dir_all(root);
    }

    #[tokio::test]
    async fn dispatch_invokes_bound_action() {
        let (hub, cfg, root) = setup("[island.main.input]\nleft = \"test.hit\"\n");
        let b = Bindings::new(&hub, cfg);
        let hits = Arc::new(AtomicUsize::new(0));
        let mut actions = ActionRegistry::default();
        b.register_actions(&mut actions);
        let h = hits.clone();
        actions.register("test.hit", "x", move |_| {
            let h = h.clone();
            async move {
                h.fetch_add(1, Ordering::SeqCst);
                Ok(None)
            }
        });
        let daemon = Arc::new(Daemon::new(hub, actions, Intents::default()));
        b.attach(&daemon);
        let d = |slot: &str| json!({"component": "island.main", "slot": slot});
        daemon
            .actions
            .invoke("input.dispatch", d("left"))
            .await
            .unwrap();
        assert_eq!(hits.load(Ordering::SeqCst), 1);
        // Unbound slot: no-op.
        daemon
            .actions
            .invoke("input.dispatch", d("middle"))
            .await
            .unwrap();
        assert_eq!(hits.load(Ordering::SeqCst), 1);
        assert!(matches!(
            daemon.actions.invoke("input.dispatch", json!({})).await,
            Err(ActionError::Invalid(_))
        ));
        let _ = std::fs::remove_dir_all(root);
    }
}
