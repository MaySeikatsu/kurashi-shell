//! The `mod.tasks` document (K46): `{state, file, reason?, tasks, open, done, notes: {file, state, text, reason?}}`.
//! `tasks` lists every open item and, with `show_done`, the items done today (their `✅` date is today): older done
//! items stay in the file and in the `done` count, which is what `tasks.clear_done` removes.

use std::path::Path;

use serde_json::{Map, Value, json};

use crate::markdown::File;
use crate::store::Read;

pub const STATE_READY: &str = "ready";
pub const STATE_MISSING: &str = "missing";
pub const STATE_ERROR: &str = "error";
pub const REASON_MISSING: &str = "mod-tasks.missing";
pub const REASON_READ_ONLY: &str = "mod-tasks.read_only";
pub const REASON_NOTES_MISSING: &str = "mod-tasks.notes.missing";

fn path_text(p: &Path) -> String {
    p.to_string_lossy().into_owned()
}

/// The task part of the document, from a read of the checklist.
pub fn tasks(path: &Path, read: &Read, show_done: bool, today: &str) -> Map<String, Value> {
    let mut m = Map::new();
    m.insert("file".into(), json!(path_text(path)));
    let (state, reason, file) = match read {
        Read::Missing => (STATE_MISSING, Some(REASON_MISSING), None),
        Read::Failed(key) => (STATE_ERROR, Some(*key), None),
        Read::Text(text, read_only) => (
            STATE_READY,
            read_only.then_some(REASON_READ_ONLY),
            Some(File::parse(text)),
        ),
    };
    m.insert("state".into(), json!(state));
    if let Some(r) = reason {
        m.insert("reason".into(), json!(r));
    }
    let (list, open, done) = file.as_ref().map_or((Vec::new(), 0, 0), |f| {
        let list: Vec<Value> = f
            .items
            .iter()
            .filter(|i| !i.done || (show_done && i.done_on.as_deref() == Some(today)))
            .map(|i| {
                let mut t = Map::new();
                t.insert("id".into(), json!(i.id));
                t.insert("text".into(), json!(i.text));
                t.insert("done".into(), json!(i.done));
                if let Some(d) = &i.due {
                    t.insert("due".into(), json!(d));
                }
                if let Some(p) = i.priority {
                    t.insert("priority".into(), json!(p));
                }
                if let Some(s) = &i.section {
                    t.insert("section".into(), json!(s));
                }
                Value::Object(t)
            })
            .collect();
        let open = f.open_count();
        (list, open, f.items.len() - open)
    });
    m.insert("tasks".into(), Value::Array(list));
    m.insert("open".into(), json!(open));
    m.insert("done".into(), json!(done));
    m
}

/// The note part: its text with LF line endings (the write puts the file's CRLF back).
pub fn notes(path: &Path, read: &Read) -> Value {
    let mut m = Map::new();
    m.insert("file".into(), json!(path_text(path)));
    match read {
        Read::Missing => {
            m.insert("state".into(), json!(STATE_MISSING));
            m.insert("text".into(), json!(""));
            m.insert("reason".into(), json!(REASON_NOTES_MISSING));
        }
        Read::Failed(key) => {
            m.insert("state".into(), json!(STATE_ERROR));
            m.insert("text".into(), json!(""));
            m.insert("reason".into(), json!(key));
        }
        Read::Text(text, read_only) => {
            m.insert("state".into(), json!(STATE_READY));
            m.insert("text".into(), json!(text.replace("\r\n", "\n")));
            if *read_only {
                m.insert("reason".into(), json!(REASON_READ_ONLY));
            }
        }
    }
    Value::Object(m)
}

pub fn build(
    tasks_path: &Path,
    tasks_read: &Read,
    notes_path: &Path,
    notes_read: &Read,
    show_done: bool,
    today: &str,
) -> Value {
    let mut m = tasks(tasks_path, tasks_read, show_done, today);
    m.insert("notes".into(), notes(notes_path, notes_read));
    Value::Object(m)
}

#[cfg(test)]
mod tests {
    use super::*;

    const SRC: &str = "# A\n- [ ] open 📅 2026-10-21 ⏫\n- [x] today ✅ 2026-10-20\n- [x] old ✅ 2026-10-01\n- [x] undated\n";

    #[test]
    fn ready_lists_open_and_todays_done() {
        let read = Read::Text(SRC.into(), false);
        let d = build(
            Path::new("/t.md"),
            &read,
            Path::new("/n.md"),
            &Read::Missing,
            true,
            "2026-10-20",
        );
        assert_eq!(d["state"], "ready");
        assert!(d.get("reason").is_none());
        let texts: Vec<&str> = d["tasks"]
            .as_array()
            .unwrap()
            .iter()
            .map(|t| t["text"].as_str().unwrap())
            .collect();
        assert_eq!(texts, ["open", "today"]);
        assert_eq!(d["tasks"][0]["due"], "2026-10-21");
        assert_eq!(d["tasks"][0]["priority"], 1);
        assert_eq!(d["tasks"][0]["section"], "A");
        assert_eq!(d["open"], 1);
        assert_eq!(d["done"], 3);
        assert_eq!(d["notes"]["state"], "missing");
        assert_eq!(d["notes"]["text"], "");
        // Without show_done only the open one.
        let hidden = tasks(Path::new("/t.md"), &read, false, "2026-10-20");
        assert_eq!(hidden["tasks"].as_array().unwrap().len(), 1);
    }

    #[test]
    fn missing_error_and_read_only() {
        let m = tasks(Path::new("/t.md"), &Read::Missing, true, "x");
        assert_eq!(m["state"], "missing");
        assert_eq!(m["reason"], REASON_MISSING);
        assert_eq!(m["tasks"], json!([]));
        let e = tasks(
            Path::new("/t.md"),
            &Read::Failed("mod-tasks.error.read"),
            true,
            "x",
        );
        assert_eq!(e["state"], "error");
        assert_eq!(e["reason"], "mod-tasks.error.read");
        let r = tasks(
            Path::new("/t.md"),
            &Read::Text("- [ ] a\n".into(), true),
            true,
            "x",
        );
        assert_eq!(r["state"], "ready");
        assert_eq!(r["reason"], REASON_READ_ONLY);
        let n = notes(Path::new("/n.md"), &Read::Text("a\r\nb\r\n".into(), false));
        assert_eq!(n["text"], "a\nb\n");
    }
}
