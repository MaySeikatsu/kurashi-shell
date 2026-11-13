//! Mods' launcher providers (K150, manifest `launcher:<name>`): a table the native mods' enable fills
//! ([`crate::native`]) and the launcher's query reads ([`crate::wiring::launcher`]). A provider with a prefix owns the
//! queries that start with it; one without adds rows to the ordinary results. A prefix the launcher's own modes hold
//! (`kurashi_launcher::BUILTIN_PREFIXES`), an empty one, or one an earlier provider holds is refused: that provider
//! answers nothing and `runtime.launcher` names it with the reason (Shōjiki).

use std::collections::BTreeMap;
use std::sync::{Arc, Mutex};

use kurashi_mod_api::{LauncherRow, LauncherSpec};
use serde_json::{Value, json};

/// The document that shows the prefixes (K150).
pub const DOC: &str = "runtime.launcher";

/// The launcher row id of a mod's row: launching it invokes `action` with `args`.
pub const ROW_PREFIX: &str = "modact:";

#[derive(Clone)]
struct Provider {
    mod_id: String,
    spec: LauncherSpec,
}

/// The providers by `<mod>:<name>`, in registration order of their keys (a `BTreeMap`: the order is the key's, so
/// which of two providers holds a contested prefix does not depend on enable timing).
#[derive(Clone, Default)]
pub struct LauncherMods {
    inner: Arc<Mutex<BTreeMap<String, Provider>>>,
}

/// Why a provider's prefix is not in effect.
#[derive(Debug, Clone, PartialEq)]
pub enum Refusal {
    Empty,
    Builtin(String),
    Taken { by: String },
}

impl LauncherMods {
    pub fn insert(&self, mod_id: &str, name: &str, spec: LauncherSpec) {
        self.inner.lock().expect("launcher mods").insert(
            format!("{mod_id}:{name}"),
            Provider {
                mod_id: mod_id.into(),
                spec,
            },
        );
    }

    pub fn remove_mod(&self, mod_id: &str) {
        self.inner
            .lock()
            .expect("launcher mods")
            .retain(|_, p| p.mod_id != mod_id);
    }

    /// Every provider's prefix as it stands now: in effect (`Ok`) or refused (`Err`). `None` for one without.
    pub fn prefixes(&self) -> Vec<(String, Option<Result<String, Refusal>>)> {
        let providers: Vec<(String, Provider)> = self
            .inner
            .lock()
            .expect("launcher mods")
            .iter()
            .map(|(k, p)| (k.clone(), p.clone()))
            .collect();
        let mut held: BTreeMap<String, String> = BTreeMap::new();
        let mut out = Vec::new();
        for (key, p) in providers {
            let state = (p.spec.prefix)().map(|pre| {
                let pre = pre.trim().to_string();
                if pre.is_empty() {
                    Err(Refusal::Empty)
                } else if let Some(b) = kurashi_launcher::BUILTIN_PREFIXES
                    .iter()
                    .find(|b| pre.starts_with(**b) || b.starts_with(pre.as_str()))
                {
                    Err(Refusal::Builtin((*b).to_string()))
                } else if let Some(by) = held
                    .iter()
                    .find(|(h, _)| pre.starts_with(h.as_str()) || h.starts_with(pre.as_str()))
                    .map(|(_, by)| by.clone())
                {
                    Err(Refusal::Taken { by })
                } else {
                    held.insert(pre.clone(), key.clone());
                    Ok(pre)
                }
            });
            out.push((key, state));
        }
        out
    }

    /// The rows for query `q`: `Some` when a provider's prefix owns it (only its rows), else `None` and the rows of
    /// the providers without a prefix go into `extra`.
    /// `tr` translates a row's `sub` when it is an i18n key (a mod words its second line by key, rule 8).
    pub fn query(
        &self,
        q: &str,
        tr: &dyn Fn(&str) -> String,
        extra: &mut Vec<Value>,
    ) -> Option<Vec<Value>> {
        let providers: BTreeMap<String, Provider> =
            self.inner.lock().expect("launcher mods").clone();
        for (key, state) in self.prefixes() {
            let Some(p) = providers.get(&key) else {
                continue;
            };
            match state {
                Some(Ok(pre)) => {
                    if let Some(rest) = q.strip_prefix(pre.as_str()) {
                        return Some(rows_json(&p.mod_id, (p.spec.query)(rest.trim_start()), tr));
                    }
                }
                None => {
                    if !q.trim().is_empty() {
                        extra.extend(rows_json(&p.mod_id, (p.spec.query)(q), tr));
                    }
                }
                Some(Err(_)) => {}
            }
        }
        None
    }

    /// `runtime.launcher`'s `providers`: each provider, its prefix and whether it is in effect.
    pub fn document(&self) -> Value {
        let list: Vec<Value> = self
            .prefixes()
            .into_iter()
            .map(|(key, state)| match state {
                None => json!({"id": key}),
                Some(Ok(p)) => json!({"id": key, "prefix": p}),
                Some(Err(r)) => json!({"id": key, "refused": match r {
                    Refusal::Empty => json!({"reason": "launcher.error.prefix_empty"}),
                    Refusal::Builtin(b) => json!({"reason": "launcher.error.prefix_builtin", "prefix": b}),
                    Refusal::Taken { by } => json!({"reason": "launcher.error.prefix_taken", "by": by}),
                }}),
            })
            .collect();
        json!({ "builtin": kurashi_launcher::BUILTIN_PREFIXES, "providers": list })
    }
}

/// The rows as the launcher's query answers them; a row naming an action outside its mod is dropped.
fn rows_json(mod_id: &str, rows: Vec<LauncherRow>, tr: &dyn Fn(&str) -> String) -> Vec<Value> {
    let own = format!("{mod_id}.");
    rows.into_iter()
        .filter(|r| r.action.starts_with(&own))
        .enumerate()
        .map(|(i, r)| {
            let payload = json!({"action": r.action, "args": r.args});
            json!({
                "id": format!("{ROW_PREFIX}{}", payload),
                "key": r.key,
                "name": r.name,
                "generic": tr(&r.sub),
                "icon": if r.icon.is_empty() { Value::Null } else { json!(r.icon) },
                "kind": "mod",
                "mod": mod_id,
                // (the provider's order is its ranking)
                "score": 1.0 - (i as f64) * 0.001,
            })
        })
        .collect()
}

/// A mod row's action and arguments from its launcher id.
pub fn parse_row(id: &str) -> Option<(String, Value)> {
    let payload: Value = serde_json::from_str(id.strip_prefix(ROW_PREFIX)?).ok()?;
    Some((
        payload["action"].as_str()?.to_string(),
        payload["args"].clone(),
    ))
}

#[cfg(test)]
mod tests {
    use super::*;

    fn spec(prefix: Option<&'static str>, name: &'static str) -> LauncherSpec {
        LauncherSpec {
            prefix: Arc::new(move || prefix.map(String::from)),
            query: Arc::new(move |q| {
                vec![LauncherRow {
                    key: format!("{name}:{q}"),
                    name: format!("{name} {q}"),
                    sub: String::new(),
                    icon: String::new(),
                    action: format!("{name}.go"),
                    args: json!({"text": q}),
                }]
            }),
        }
    }

    #[test]
    fn a_prefix_owns_its_queries_and_a_row_runs_the_mods_own_action() {
        let l = LauncherMods::default();
        l.insert("webdock", "web", spec(Some("/"), "webdock"));
        let mut extra = Vec::new();
        let rows = l
            .query("/ github.com", &|k| k.to_string(), &mut extra)
            .expect("the prefix owns it");
        assert_eq!(rows[0]["name"], "webdock github.com");
        let (action, args) = parse_row(rows[0]["id"].as_str().unwrap()).unwrap();
        assert_eq!(
            (action.as_str(), args["text"].as_str()),
            ("webdock.go", Some("github.com"))
        );
        assert!(l.query("firefox", &|k| k.to_string(), &mut extra).is_none() && extra.is_empty());
    }

    #[test]
    fn builtin_empty_and_contested_prefixes_are_refused_and_said() {
        let l = LauncherMods::default();
        l.insert("a", "x", spec(Some(">"), "a"));
        l.insert("b", "x", spec(Some(" "), "b"));
        l.insert("c", "x", spec(Some("!"), "c"));
        l.insert("d", "x", spec(Some("!"), "d"));
        let doc = l.document();
        let p = doc["providers"].as_array().unwrap();
        assert_eq!(p[0]["refused"]["reason"], "launcher.error.prefix_builtin");
        assert_eq!(p[1]["refused"]["reason"], "launcher.error.prefix_empty");
        assert_eq!(p[2]["prefix"], "!");
        assert_eq!(p[3]["refused"]["by"], "c:x");
        let mut extra = Vec::new();
        assert!(
            l.query("> lock", &|k| k.to_string(), &mut extra).is_none(),
            "the built-in `>` stays the shell's"
        );
    }

    #[test]
    fn a_provider_without_a_prefix_adds_rows_and_a_foreign_action_is_dropped() {
        let l = LauncherMods::default();
        l.insert("terminal", "t", spec(None, "terminal"));
        l.insert("evil", "e", spec(None, "webdock"));
        let mut extra = Vec::new();
        assert!(l.query("htop", &|k| k.to_string(), &mut extra).is_none());
        assert_eq!(extra.len(), 1, "only the mod's own action: {extra:?}");
        l.remove_mod("terminal");
        extra.clear();
        l.query("htop", &|k| k.to_string(), &mut extra);
        assert!(extra.is_empty());
    }
}
