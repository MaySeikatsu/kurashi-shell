//! Runtime registry: flat dotted keys in declaration order, validation and defaults.

use std::collections::{BTreeMap, HashMap};

use serde_json::Value;

use crate::error::{SchemaError, ValidationError};
use crate::leaf::{Ctx, KurashiNode};
use crate::meta::{Coupling, KeyMeta, Ty};

#[derive(Debug, Clone)]
pub struct Registry {
    version: u32,
    keys: Vec<KeyMeta>,
    index: HashMap<String, usize>,
}

impl Registry {
    /// Collect the tree rooted at `T` and check it for consistency.
    pub fn build<T: KurashiNode>(version: u32) -> Result<Self, Vec<SchemaError>> {
        let mut keys = Vec::new();
        T::collect("", &Ctx::default(), &mut keys);
        Self::from_keys(version, keys)
    }

    /// Build from hand-made metadata (tests, mods later). Reports every problem, not the first.
    pub fn from_keys(version: u32, keys: Vec<KeyMeta>) -> Result<Self, Vec<SchemaError>> {
        let mut errors = Vec::new();
        let mut index = HashMap::with_capacity(keys.len());
        for (i, m) in keys.iter().enumerate() {
            if index.insert(m.key.clone(), i).is_some() {
                errors.push(SchemaError::DuplicateKey(m.key.clone()));
            }
        }
        let reg = Self {
            version,
            keys,
            index,
        };
        for m in &reg.keys {
            let table = format!("{}.", m.key);
            if reg.keys.iter().any(|o| o.key.starts_with(&table)) {
                errors.push(SchemaError::KeyIsTable(m.key.clone()));
            }
            if m.since > version {
                errors.push(SchemaError::SinceTooNew {
                    key: m.key.clone(),
                    since: m.since,
                    version,
                });
            }
            if let Err(error) = validate_value(m, &m.default) {
                errors.push(SchemaError::InvalidDefault {
                    key: m.key.clone(),
                    error,
                });
            }
            reg.check_couplings(m, &mut errors);
        }
        if errors.is_empty() {
            Ok(reg)
        } else {
            Err(errors)
        }
    }

    fn check_couplings(&self, m: &KeyMeta, errors: &mut Vec<SchemaError>) {
        for c in &m.couplings {
            let (target, check): (&str, Option<(&KeyMeta, &Value)>) = match c {
                Coupling::Capability { .. } => continue,
                Coupling::Requires { key, value, .. } => match self.get(key) {
                    Some(t) => (key, Some((t, value))),
                    None => (key, None),
                },
                Coupling::OverriddenBy { key, forces, .. } => match self.get(key) {
                    Some(t) if t.ty != Ty::Bool => {
                        errors.push(SchemaError::OverrideNotBool {
                            key: m.key.clone(),
                            target: key.clone(),
                        });
                        continue;
                    }
                    // The forced value must be valid for *this* key.
                    Some(_) => (key, forces.as_ref().map(|f| (m, f))),
                    None => (key, None),
                },
            };
            if self.get(target).is_none() {
                errors.push(SchemaError::DanglingCoupling {
                    key: m.key.clone(),
                    target: target.to_owned(),
                });
            } else if let Some((meta, value)) = check
                && let Err(error) = validate_value(meta, value)
            {
                errors.push(SchemaError::CouplingValue {
                    key: m.key.clone(),
                    target: target.to_owned(),
                    error,
                });
            }
        }
    }

    pub fn version(&self) -> u32 {
        self.version
    }

    pub fn get(&self, key: &str) -> Option<&KeyMeta> {
        self.index.get(key).map(|&i| &self.keys[i])
    }

    /// Keys in declaration order.
    pub fn iter(&self) -> impl Iterator<Item = &KeyMeta> {
        self.keys.iter()
    }

    pub fn keys(&self) -> impl Iterator<Item = &str> {
        self.keys.iter().map(|m| m.key.as_str())
    }

    pub fn len(&self) -> usize {
        self.keys.len()
    }

    pub fn is_empty(&self) -> bool {
        self.keys.is_empty()
    }

    pub fn defaults(&self) -> BTreeMap<String, Value> {
        self.keys
            .iter()
            .map(|m| (m.key.clone(), m.default.clone()))
            .collect()
    }

    pub fn validate(&self, key: &str, value: &Value) -> Result<(), ValidationError> {
        match self.get(key) {
            Some(m) => validate_value(m, value),
            None => Err(ValidationError::UnknownKey { key: key.into() }),
        }
    }
}

/// Check `v` against one key's type and constraints.
pub fn validate_value(m: &KeyMeta, v: &Value) -> Result<(), ValidationError> {
    let key = || m.key.clone();
    let wrong = || ValidationError::WrongType {
        key: key(),
        expected: m.ty,
        got: v.clone(),
    };
    let c = &m.constraints;
    match m.ty {
        Ty::Bool => v.as_bool().map(drop).ok_or_else(wrong),
        Ty::Int | Ty::Float => {
            let ok = match m.ty {
                Ty::Int => v.is_i64() || v.is_u64(),
                _ => v.is_number(),
            };
            if !ok {
                return Err(wrong());
            }
            let n = v.as_f64().ok_or_else(wrong)?;
            for (lo, hi) in [(c.min.as_ref(), c.max.as_ref())]
                .into_iter()
                .chain(c.type_bounds.as_ref().map(|(a, b)| (Some(a), Some(b))))
            {
                let below = lo.and_then(Value::as_f64).is_some_and(|lo| n < lo);
                let above = hi.and_then(Value::as_f64).is_some_and(|hi| n > hi);
                if below || above {
                    return Err(ValidationError::OutOfRange {
                        key: key(),
                        min: lo.cloned().unwrap_or(Value::Null),
                        max: hi.cloned().unwrap_or(Value::Null),
                        got: v.clone(),
                    });
                }
            }
            if let Some(step) = c.step.as_ref().and_then(Value::as_f64)
                && step > 0.0
            {
                let base = c.min.as_ref().and_then(Value::as_f64).unwrap_or(0.0);
                let q = (n - base) / step;
                if (q - q.round()).abs() > 1e-6 {
                    return Err(ValidationError::OffStep {
                        key: key(),
                        step: c.step.clone().unwrap_or_default(),
                        base: c.min.clone().unwrap_or(Value::from(0)),
                        got: v.clone(),
                    });
                }
            }
            Ok(())
        }
        Ty::String | Ty::Choice => {
            let s = v.as_str().ok_or_else(wrong)?;
            if (m.ty == Ty::Choice || !c.choices.is_empty())
                && !c.choices.iter().any(|ch| ch.value == s)
            {
                return Err(ValidationError::UnknownChoice {
                    key: key(),
                    got: s.into(),
                    choices: c.choices.iter().map(|ch| ch.value.clone()).collect(),
                });
            }
            Ok(())
        }
        Ty::StringList | Ty::Font => {
            let items = v.as_array().ok_or_else(wrong)?;
            if !items.iter().all(Value::is_string) {
                return Err(wrong());
            }
            if m.ty == Ty::Font && items.is_empty() {
                return Err(ValidationError::EmptyList { key: key() });
            }
            // Fixed choices (a mod's `list` setting, I26): every member is one of them.
            if !c.choices.is_empty() {
                let member_of = |s: &str| c.choices.iter().any(|ch| ch.value == s);
                if let Some(bad) = items
                    .iter()
                    .filter_map(Value::as_str)
                    .find(|s| !member_of(s))
                {
                    return Err(ValidationError::UnknownChoice {
                        key: key(),
                        got: bad.into(),
                        choices: c.choices.iter().map(|ch| ch.value.clone()).collect(),
                    });
                }
            }
            Ok(())
        }
        Ty::Color => {
            let s = v.as_str().ok_or_else(wrong)?;
            let hex = s.strip_prefix('#').unwrap_or("");
            if (hex.len() == 6 || hex.len() == 8) && hex.bytes().all(|b| b.is_ascii_hexdigit()) {
                Ok(())
            } else {
                Err(ValidationError::InvalidColor {
                    key: key(),
                    got: s.into(),
                })
            }
        }
        Ty::Action => {
            let s = v.as_str().ok_or_else(wrong)?;
            if s.is_empty() || is_action_id(s) {
                Ok(())
            } else {
                Err(ValidationError::InvalidAction {
                    key: key(),
                    got: s.into(),
                })
            }
        }
        // The one validator for records (K38): the same check the manifest's default goes through.
        Ty::Records => c
            .record
            .clone()
            .unwrap_or_default()
            .check(&m.key, v)
            .map(drop)
            .map_err(|mut errs| errs.swap_remove(0)),
    }
}

/// `segment(.segment)*`, segments `[a-z0-9_-]+` starting with a letter.
fn is_action_id(s: &str) -> bool {
    s.split('.').all(|seg| {
        seg.starts_with(|c: char| c.is_ascii_lowercase())
            && seg
                .bytes()
                .all(|b| b.is_ascii_lowercase() || b.is_ascii_digit() || b == b'_' || b == b'-')
    })
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::meta::{CmpOp, Coupling};
    use serde_json::json;

    fn int(key: &str) -> KeyMeta {
        let mut m = KeyMeta::new(key, Ty::Int, json!(32));
        m.constraints.min = Some(json!(16));
        m.constraints.max = Some(json!(96));
        m.constraints.step = Some(json!(2));
        m
    }

    #[test]
    fn numbers() {
        let m = int("bar.height");
        assert!(validate_value(&m, &json!(40)).is_ok());
        assert!(matches!(
            validate_value(&m, &json!(100)),
            Err(ValidationError::OutOfRange { .. })
        ));
        assert!(matches!(
            validate_value(&m, &json!(17)),
            Err(ValidationError::OffStep { .. })
        ));
        assert!(matches!(
            validate_value(&m, &json!(40.5)),
            Err(ValidationError::WrongType { .. })
        ));
        let mut u = KeyMeta::new("x", Ty::Int, json!(0));
        u.constraints.type_bounds = Some((json!(0), json!(255)));
        let e = validate_value(&u, &json!(-1)).unwrap_err();
        assert_eq!(e.i18n_key(), "error.config.out_of_range");
    }

    #[test]
    fn colors_and_actions() {
        let c = KeyMeta::new("c", Ty::Color, json!("#d7c4a1"));
        assert!(validate_value(&c, &json!("#d7c4a1ff")).is_ok());
        assert!(validate_value(&c, &json!("d7c4a1")).is_err());
        let a = KeyMeta::new("a", Ty::Action, json!(""));
        assert!(validate_value(&a, &json!("island.face.next")).is_ok());
        assert!(validate_value(&a, &json!("")).is_ok());
        assert!(validate_value(&a, &json!("Island Expand")).is_err());
    }

    #[test]
    fn build_reports_inconsistencies() {
        let mut bad_default = int("a.b");
        bad_default.default = json!(1000);
        let mut dangling = KeyMeta::new("a.c", Ty::Bool, json!(true));
        dangling.couplings.push(Coupling::Requires {
            key: "nope".into(),
            op: CmpOp::Eq,
            value: json!(true),
        });
        let table = KeyMeta::new("a", Ty::Bool, json!(true));
        let errs = Registry::from_keys(1, vec![bad_default.clone(), dangling, table, bad_default])
            .unwrap_err();
        assert!(errs.contains(&SchemaError::DuplicateKey("a.b".into())));
        assert!(errs.contains(&SchemaError::KeyIsTable("a".into())));
        assert!(
            errs.iter()
                .any(|e| matches!(e, SchemaError::InvalidDefault { .. }))
        );
        assert!(
            errs.iter()
                .any(|e| matches!(e, SchemaError::DanglingCoupling { .. }))
        );
    }

    #[test]
    fn unknown_key() {
        let r = Registry::from_keys(1, vec![int("bar.height")]).unwrap();
        assert_eq!(
            r.validate("bar.width", &json!(1)),
            Err(ValidationError::UnknownKey {
                key: "bar.width".into()
            })
        );
    }
}
