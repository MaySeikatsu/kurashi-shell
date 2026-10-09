//! Hand-rolled TOML ↔ JSON conversion (avoids serde round-trips that would drop decor).

use serde_json::Value as Json;
use toml_edit::{Array, InlineTable, Item, Value};

/// `None` for values JSON cannot carry (NaN/inf floats, empty items).
pub fn item_to_json(item: &Item) -> Option<Json> {
    match item {
        Item::None => None,
        Item::Value(v) => value_to_json(v),
        Item::Table(t) => {
            let mut m = serde_json::Map::new();
            for (k, i) in t.iter() {
                m.insert(k.to_string(), item_to_json(i)?);
            }
            Some(Json::Object(m))
        }
        Item::ArrayOfTables(a) => {
            let mut out = Vec::new();
            for t in a.iter() {
                out.push(item_to_json(&Item::Table(t.clone()))?);
            }
            Some(Json::Array(out))
        }
    }
}

pub fn value_to_json(v: &Value) -> Option<Json> {
    Some(match v {
        Value::String(s) => Json::String(s.value().clone()),
        Value::Integer(i) => Json::from(*i.value()),
        Value::Float(f) => Json::Number(serde_json::Number::from_f64(*f.value())?),
        Value::Boolean(b) => Json::Bool(*b.value()),
        // Datetimes are not a schema type; keep them readable rather than dropping them.
        Value::Datetime(d) => Json::String(d.value().to_string()),
        Value::Array(a) => Json::Array(a.iter().map(value_to_json).collect::<Option<_>>()?),
        Value::InlineTable(t) => {
            let mut m = serde_json::Map::new();
            for (k, v) in t.iter() {
                m.insert(k.to_string(), value_to_json(v)?);
            }
            Json::Object(m)
        }
    })
}

/// `None` for `null` (TOML has no null) anywhere inside the value.
pub fn json_to_value(j: &Json) -> Option<Value> {
    Some(match j {
        Json::Null => return None,
        Json::Bool(b) => Value::from(*b),
        Json::Number(n) => match n.as_i64() {
            Some(i) => Value::from(i),
            None => Value::from(n.as_f64()?),
        },
        Json::String(s) => Value::from(s.as_str()),
        Json::Array(a) => {
            let mut arr = Array::new();
            for v in a {
                arr.push(json_to_value(v)?);
            }
            Value::Array(arr)
        }
        Json::Object(m) => {
            let mut t = InlineTable::new();
            for (k, v) in m {
                t.insert(k, json_to_value(v)?);
            }
            Value::InlineTable(t)
        }
    })
}
