//! Small fake schema for tests (here and, via the `testing` feature, in other crates).

use std::collections::BTreeMap;

use serde_json::{Value as Json, json};

use crate::SchemaView;

#[derive(Debug, Clone)]
pub enum Kind {
    Int { min: i64, max: i64 },
    Float,
    Bool,
    Str,
    Enum(&'static [&'static str]),
    StrList,
}

#[derive(Debug, Clone)]
pub struct FakeKey {
    pub default: Json,
    pub kind: Kind,
    pub per_output: bool,
}

#[derive(Debug, Clone)]
pub struct FakeSchema {
    pub version: u32,
    pub keys: BTreeMap<String, FakeKey>,
}

pub const EDGES: &[&str] = &["top", "bottom", "left", "right"];

impl Default for FakeSchema {
    fn default() -> Self {
        Self::new()
    }
}

impl FakeSchema {
    pub fn new() -> Self {
        let k = |default, kind, per_output| FakeKey {
            default,
            kind,
            per_output,
        };
        let keys = BTreeMap::from([
            (
                "bar.height".into(),
                k(json!(32), Kind::Int { min: 16, max: 200 }, true),
            ),
            (
                "bar.main.edge".into(),
                k(json!("top"), Kind::Enum(EDGES), true),
            ),
            (
                "bar.main.autohide".into(),
                k(json!(false), Kind::Bool, false),
            ),
            ("theme.palette".into(), k(json!("wa-iro"), Kind::Str, false)),
            (
                "theme.motion.speed".into(),
                k(json!(1.0), Kind::Float, false),
            ),
            ("island.enabled".into(), k(json!(true), Kind::Bool, true)),
            (
                "island.faces".into(),
                k(json!(["media", "clock"]), Kind::StrList, false),
            ),
        ]);
        Self { version: 1, keys }
    }

    pub fn with_version(version: u32) -> Self {
        Self {
            version,
            ..Self::new()
        }
    }
}

impl SchemaView for FakeSchema {
    fn version(&self) -> u32 {
        self.version
    }

    fn default(&self, key: &str) -> Option<Json> {
        self.keys.get(key).map(|k| k.default.clone())
    }

    fn validate(&self, key: &str, v: &Json) -> Result<(), String> {
        let k = self.keys.get(key).ok_or("config.error.unknown_key")?;
        let ok = match &k.kind {
            Kind::Int { min, max } => {
                let i = v.as_i64().ok_or("config.error.type")?;
                if i < *min || i > *max {
                    return Err("config.error.range".into());
                }
                true
            }
            Kind::Float => v.is_number(),
            Kind::Bool => v.is_boolean(),
            Kind::Str => v.is_string(),
            Kind::Enum(allowed) => {
                let s = v.as_str().ok_or("config.error.type")?;
                if !allowed.contains(&s) {
                    return Err("config.error.enum".into());
                }
                true
            }
            Kind::StrList => v.as_array().is_some_and(|a| a.iter().all(Json::is_string)),
        };
        if ok {
            Ok(())
        } else {
            Err("config.error.type".into())
        }
    }

    fn per_output(&self, key: &str) -> bool {
        self.keys.get(key).is_some_and(|k| k.per_output)
    }

    fn keys(&self) -> Vec<String> {
        self.keys.keys().cloned().collect()
    }
}
