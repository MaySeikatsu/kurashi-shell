use serde_json::{Map, Value, json};

use crate::CompositorState;

/// The `svc.workspaces` document (PROTOCOL §8):
/// `{"outputs":{"<name>":[{id,idx,focused,occupied},…]}}`, each list ordered by `idx`.
///
/// Every known output appears, even with no workspaces, so the bar can still draw it.
pub fn workspaces_doc(state: &CompositorState) -> Value {
    let mut map = Map::new();
    for o in &state.outputs {
        map.insert(o.name.clone(), Value::Array(Vec::new()));
    }
    let mut ws: Vec<_> = state
        .workspaces
        .iter()
        .filter(|w| w.output.is_some())
        .collect();
    ws.sort_by_key(|w| w.idx);
    for w in ws {
        let name = w.output.as_deref().unwrap_or_default();
        let entry = map
            .entry(name.to_string())
            .or_insert_with(|| Value::Array(Vec::new()));
        if let Value::Array(list) = entry {
            list.push(json!({
                "id": w.id, "idx": w.idx, "focused": w.focused, "occupied": w.occupied
            }));
        }
    }
    json!({ "outputs": map })
}
