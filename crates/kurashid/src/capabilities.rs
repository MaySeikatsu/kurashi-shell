//! Compositor capabilities (M2 blur capability): probe the Wayland globals once, pin every
//! schema key that `capability = "…"`-couples to a missing capability as `forced:capability`
//! (off + reason), and publish `compositor.caps`. Shōjiki: a blur toggle the compositor cannot
//! honour must say so instead of silently doing nothing.

use std::collections::BTreeSet;

use kurashi_config::Forced;
use kurashi_core::Source;
use kurashi_schema::Coupling;
use serde_json::{Value, json};

use crate::config::ConfigStore;
use crate::hub::Hub;

pub const DOC: &str = "compositor.caps";

/// Capability names the document always lists, present or not.
const KNOWN: [&str; 4] = ["blur", "session_lock", "screencopy", "layer_shell"];

/// Probe `$WAYLAND_DISPLAY` and apply. A failed probe is treated as "nothing offered" (the
/// honest answer when we cannot ask), logged once.
pub fn probe_and_apply(store: &ConfigStore, hub: &Hub) -> BTreeSet<String> {
    let caps = match kurashi_compositor::globals::probe_env() {
        Ok(ifs) => kurashi_compositor::globals::capabilities(&ifs),
        Err(e) => {
            tracing::warn!(error = %e, "wayland capability probe failed; assuming none");
            BTreeSet::new()
        }
    };
    apply(store, hub, &caps);
    caps
}

/// Force/clear couplings for `caps` and publish `compositor.caps`. Call at startup and on
/// compositor `Event::Resync`.
pub fn apply(store: &ConfigStore, hub: &Hub, caps: &BTreeSet<String>) {
    let registry = store.registry();
    for key in registry.keys() {
        let Some(meta) = registry.get(key) else {
            continue;
        };
        let missing = meta.couplings.iter().find_map(|c| match c {
            Coupling::Capability { name } if !caps.contains(name) => Some(name.clone()),
            _ => None,
        });
        let already = store
            .get(key, None)
            .is_some_and(|p| p.source == Source::Forced("capability".into()));
        match (missing, already) {
            // Only bools have an unambiguous "off"; anything else is left alone (and logged).
            (Some(name), false) => {
                if meta.default.is_boolean() {
                    store.force_capability(
                        key,
                        Some(Forced {
                            value: Value::Bool(false),
                            forced_by: Some(name),
                            reason: Some("settings.inert.capability".into()),
                        }),
                    );
                } else {
                    tracing::warn!(%key, "capability coupling on a non-bool key is not enforced");
                }
            }
            (None, true) => store.force_capability(key, None),
            _ => {}
        }
    }
    publish_doc(hub, caps);
}

fn publish_doc(hub: &Hub, caps: &BTreeSet<String>) {
    let mut d = serde_json::Map::new();
    for n in KNOWN {
        d.insert(n.into(), json!(caps.contains(n)));
    }
    let probed_at = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map_or(0, |t| t.as_millis() as u64);
    d.insert("probed_at".into(), json!(probed_at));
    let doc = Value::Object(d);
    if hub.snapshot(DOC).is_err() {
        hub.register(DOC, doc, None);
    } else {
        let _ = hub.set(DOC, doc, None);
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn store(tag: &str) -> (std::sync::Arc<Hub>, std::sync::Arc<ConfigStore>) {
        let root = std::env::temp_dir().join(format!("kurashid-caps-{}-{tag}", std::process::id()));
        let _ = std::fs::remove_dir_all(&root);
        std::fs::create_dir_all(&root).unwrap();
        let hub = Hub::new();
        let s = ConfigStore::open(
            hub.clone(),
            kurashi_schema::v1::registry(),
            kurashi_config::Paths::rooted(&root),
            kurashi_config::Options::default(),
        );
        (hub, s)
    }

    #[test]
    fn missing_blur_is_forced_off_with_reason_then_cleared() {
        let (hub, s) = store("couple");
        apply(&s, &hub, &BTreeSet::new());
        let p = s.get("theme.material.blur", None).unwrap();
        assert_eq!(p.value, json!(false));
        assert_eq!(p.source, Source::Forced("capability".into()));
        assert_eq!(p.forced_by.as_deref(), Some("blur"));
        assert_eq!(p.reason.as_deref(), Some("settings.inert.capability"));
        assert_eq!(hub.snapshot(DOC).unwrap().1["blur"], json!(false));

        apply(&s, &hub, &BTreeSet::from(["blur".to_string()]));
        let p = s.get("theme.material.blur", None).unwrap();
        assert_ne!(p.source, Source::Forced("capability".into()));
        // Back to the schema default (off since v7, I297).
        assert_eq!(p.value, json!(false));
        assert_eq!(hub.snapshot(DOC).unwrap().1["blur"], json!(true));
    }
}
