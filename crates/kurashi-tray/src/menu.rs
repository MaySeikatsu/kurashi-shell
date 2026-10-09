//! An item's dbusmenu (`com.canonical.dbusmenu`) as a plain tree, read on demand.

use std::collections::HashMap;

use serde_json::{Map, Value, json};
use zbus::Connection;
use zbus::zvariant::OwnedValue;

use crate::call_timed;
use crate::item::prop;

pub const IFACE: &str = "com.canonical.dbusmenu";
/// Menus nest a few levels; this bounds the work for a buggy or hostile tree.
const MAX_DEPTH: usize = 16;

/// `(ia{sv}av)`: id, properties, children. Each child is a variant holding the same structure.
type Layout = (i32, HashMap<String, OwnedValue>, Vec<OwnedValue>);

/// The root node. Also the answer for an item that has no menu.
pub fn root(children: Vec<Value>) -> Value {
    json!({"id": 0, "enabled": true, "children": children})
}

/// Read the whole tree. The menu's own errors are returned as they are.
pub async fn fetch(conn: &Connection, dest: &str, path: &str) -> zbus::Result<Value> {
    // Qt and Electron build their menus lazily and want to hear about it first. The answer is
    // only a hint, so a failure here is not an error.
    let _ = call_timed(conn, dest, path, IFACE, "AboutToShow", &(0i32,)).await;
    let reply = call_timed(
        conn,
        dest,
        path,
        IFACE,
        "GetLayout",
        &(0i32, -1i32, Vec::<String>::new()),
    )
    .await?;
    let (_revision, (_, _, kids)): (u32, Layout) = reply.body().deserialize()?;
    Ok(root(children(kids, 1)))
}

fn children(kids: Vec<OwnedValue>, depth: usize) -> Vec<Value> {
    if depth > MAX_DEPTH {
        return vec![];
    }
    kids.into_iter()
        .filter_map(|k| node(Layout::try_from(k).ok()?, depth))
        .collect()
}

/// One entry. Hidden entries are dropped; absent properties are absent, never null.
fn node(layout: Layout, depth: usize) -> Option<Value> {
    let (id, props, kids) = layout;
    if !flag(&props, "visible", true) {
        return None;
    }
    let mut o = Map::new();
    o.insert("id".into(), id.into());
    if prop::<String>(&props, "type").as_deref() == Some("separator") {
        o.insert("separator".into(), true.into());
    } else if let Some(label) = prop::<String>(&props, "label")
        .map(|l| strip_mnemonic(&l))
        .filter(|l| !l.is_empty())
    {
        o.insert("label".into(), label.into());
    }
    o.insert("enabled".into(), flag(&props, "enabled", true).into());
    if let Some(icon) = prop::<String>(&props, "icon-name").filter(|s| !s.is_empty()) {
        o.insert("icon_name".into(), icon.into());
    }
    if let Some(kind) =
        prop::<String>(&props, "toggle-type").filter(|k| k == "checkmark" || k == "radio")
    {
        let checked = prop::<i32>(&props, "toggle-state") == Some(1);
        o.insert("toggle".into(), kind.into());
        o.insert("checked".into(), checked.into());
    }
    let kids = children(kids, depth + 1);
    if !kids.is_empty() {
        o.insert("children".into(), Value::Array(kids));
    }
    Some(Value::Object(o))
}

fn flag(props: &HashMap<String, OwnedValue>, key: &str, default: bool) -> bool {
    prop::<bool>(props, key).unwrap_or(default)
}

/// dbusmenu marks the accelerator with a single `_`; `__` is a literal underscore.
fn strip_mnemonic(label: &str) -> String {
    let mut out = String::with_capacity(label.len());
    let mut chars = label.chars().peekable();
    while let Some(c) = chars.next() {
        if c != '_' {
            out.push(c);
        } else if chars.peek() == Some(&'_') {
            out.push('_');
            chars.next();
        }
    }
    out
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn mnemonics_are_stripped_but_double_underscore_survives() {
        assert_eq!(strip_mnemonic("_Open"), "Open");
        assert_eq!(strip_mnemonic("Save __as"), "Save _as");
        assert_eq!(strip_mnemonic("plain"), "plain");
        assert_eq!(strip_mnemonic("__"), "_");
    }

    #[test]
    fn empty_root_has_stable_shape() {
        assert_eq!(
            root(vec![]),
            json!({"id": 0, "enabled": true, "children": []})
        );
    }
}
