//! The tasks mod in the mock (K46, parity with `crates/kurashi-mod-tasks`): a small `mod.tasks` document and the
//! `tasks.*` actions answered in memory, so the desk cards and the panel can be driven without the daemon. No file is
//! read or written; the shape and the refusals (i18n keys) are the daemon's. The mock keeps every done item in `tasks`
//! (the daemon lists only today's, with `show_done`).

use serde_json::{Map, Value, json};

use crate::state::Fail;

const ERR_TEXT: &str = "mod-tasks.error.text";
const ERR_ID: &str = "mod-tasks.error.id";
const ERR_GONE: &str = "mod-tasks.error.gone";

/// What an action did: the merge patch for `mod.tasks` and the reply.
pub struct Outcome {
    pub ops: Option<Value>,
    pub reply: Option<Value>,
}

pub fn initial() -> Value {
    let tasks = json!([
        {"id": "m1", "text": "Pay the rent", "done": false, "due": "2026-10-21", "priority": 1, "section": "Today"},
        {"id": "m2", "text": "Call the dentist", "done": false, "priority": 2, "section": "Today"},
        {"id": "m3", "text": "Read chapter 3", "done": true, "section": "Today"},
        {"id": "m4", "text": "Buy milk", "done": false, "section": "Shopping"}
    ]);
    let mut doc = json!({
        "state": "ready",
        "file": "/home/mock/.local/share/kurashi/tasks.md",
        "notes": {
            "file": "/home/mock/.local/share/kurashi/notes.md",
            "state": "ready",
            "text": "# Groceries\nmilk, eggs, miso\n"
        }
    });
    set_tasks(&mut doc, tasks.as_array().cloned().unwrap_or_default());
    doc
}

/// The list and its counts as one patch (a merge patch replaces arrays whole).
fn set_tasks(doc: &mut Value, tasks: Vec<Value>) {
    let open = tasks.iter().filter(|t| t["done"] != json!(true)).count();
    let done = tasks.len() - open;
    doc["tasks"] = Value::Array(tasks);
    doc["open"] = json!(open);
    doc["done"] = json!(done);
}

fn list_patch(tasks: Vec<Value>) -> Value {
    let mut patch = json!({});
    set_tasks(&mut patch, tasks);
    patch
}

fn text_arg(args: &Value) -> Result<String, Fail> {
    let one: String = args["text"]
        .as_str()
        .unwrap_or("")
        .chars()
        .map(|c| if c == '\n' || c == '\r' { ' ' } else { c })
        .collect();
    let t = one.trim();
    if t.is_empty() || t.chars().count() > 500 {
        return Err(Fail::invalid(ERR_TEXT));
    }
    Ok(t.to_owned())
}

fn index_of(tasks: &[Value], args: &Value) -> Result<usize, Fail> {
    let id = args["id"]
        .as_str()
        .filter(|s| !s.is_empty())
        .ok_or_else(|| Fail::invalid(ERR_ID))?;
    tasks
        .iter()
        .position(|t| t["id"] == json!(id))
        .ok_or_else(|| Fail::unavailable(ERR_GONE))
}

fn next_id(tasks: &[Value]) -> String {
    let n = tasks
        .iter()
        .filter_map(|t| t["id"].as_str()?.strip_prefix('m')?.parse::<u64>().ok())
        .max()
        .unwrap_or(0);
    format!("m{}", n + 1)
}

pub fn act(doc: &Value, action: &str, args: &Value) -> Result<Outcome, Fail> {
    let mut tasks = doc["tasks"].as_array().cloned().unwrap_or_default();
    let reply = match action {
        "tasks.add" => {
            let text = text_arg(args)?;
            let id = next_id(&tasks);
            let mut t = Map::new();
            t.insert("id".into(), json!(id));
            t.insert("text".into(), json!(text));
            t.insert("done".into(), json!(false));
            if let Some(s) = tasks.last().and_then(|t| t.get("section")).cloned() {
                t.insert("section".into(), s);
            }
            tasks.push(Value::Object(t));
            Some(json!({"id": id}))
        }
        "tasks.toggle" => {
            let i = index_of(&tasks, args)?;
            let done = tasks[i]["done"] != json!(true);
            tasks[i]["done"] = json!(done);
            Some(json!({"id": tasks[i]["id"], "done": done}))
        }
        "tasks.edit" => {
            let i = index_of(&tasks, args)?;
            let text = text_arg(args)?;
            let id = next_id(&tasks);
            tasks[i]["text"] = json!(text);
            tasks[i]["id"] = json!(id);
            Some(json!({"id": id}))
        }
        "tasks.remove" => {
            let i = index_of(&tasks, args)?;
            tasks.remove(i);
            None
        }
        "tasks.clear_done" => {
            let before = tasks.len();
            tasks.retain(|t| t["done"] != json!(true));
            Some(json!({"removed": before - tasks.len()}))
        }
        "tasks.notes.set" => {
            let text = args["text"]
                .as_str()
                .ok_or_else(|| Fail::invalid(ERR_TEXT))?;
            return Ok(Outcome {
                ops: Some(json!({"notes": {"state": "ready", "text": text, "reason": null}})),
                reply: None,
            });
        }
        _ => {
            return Err(Fail {
                kind: "unknown_action",
                msg: format!("no action {action}"),
            });
        }
    };
    Ok(Outcome {
        ops: Some(list_patch(tasks)),
        reply,
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn actions_change_the_list_as_the_daemon_would() {
        let mut doc = initial();
        assert_eq!(doc["open"], 3);
        let apply = |doc: &mut Value, a: &str, args: Value| {
            let out = act(doc, a, &args).expect("acts");
            if let Some(ops) = out.ops {
                for (k, v) in ops.as_object().unwrap() {
                    doc[k] = v.clone();
                }
            }
            out.reply
        };
        let r = apply(&mut doc, "tasks.add", json!({"text": "Water plants"})).unwrap();
        assert_eq!(r["id"], "m5");
        assert_eq!(doc["tasks"][4]["section"], "Shopping");
        assert_eq!(doc["open"], 4);
        apply(&mut doc, "tasks.toggle", json!({"id": "m5"}));
        assert_eq!(doc["done"], 2);
        let r = apply(&mut doc, "tasks.clear_done", json!({})).unwrap();
        assert_eq!(r["removed"], 2);
        assert_eq!(doc["done"], 0);
        let f = act(&doc, "tasks.toggle", &json!({"id": "m3"}))
            .err()
            .unwrap();
        assert_eq!((f.kind, f.msg.as_str()), ("unavailable", ERR_GONE));
        let f = act(&doc, "tasks.add", &json!({"text": " "})).err().unwrap();
        assert_eq!((f.kind, f.msg.as_str()), ("invalid", ERR_TEXT));
    }
}
