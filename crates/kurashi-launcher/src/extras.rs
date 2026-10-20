//! The launcher's prefix modes (session 9, after Capsule's launcher): `:` searches emoji, `;` the clipboard history
//! (cliphist). Each returns rows in the shape of the app rows, with `kind` `emoji` or `clip` and an id the launch
//! action understands (`emoji:<char>`, `clip:<cliphist line id>`).

use std::sync::OnceLock;

use serde::Deserialize;
use serde_json::{Value, json};

#[derive(Deserialize)]
struct Emoji {
    c: String,
    n: String,
    k: String,
    g: String,
}

fn emoji() -> &'static [Emoji] {
    static LIST: OnceLock<Vec<Emoji>> = OnceLock::new();
    LIST.get_or_init(|| {
        serde_json::from_str(include_str!("../data/emoji.json")).unwrap_or_default()
    })
}

/// Emoji whose name or keys contain every word of `q` (all of them for an empty `q`), at most `limit`.
pub fn emoji_rows(q: &str, limit: usize) -> Vec<Value> {
    let words: Vec<String> = q.split_whitespace().map(str::to_lowercase).collect();
    let mut hits: Vec<(usize, &Emoji)> = emoji()
        .iter()
        .filter(|e| words.iter().all(|w| e.k.contains(w.as_str())))
        .map(|e| {
            // A name that starts with the first word ranks first.
            let rank = usize::from(!words.first().is_some_and(|w| e.k.starts_with(w.as_str())));
            (rank, e)
        })
        .collect();
    hits.sort_by_key(|(r, _)| *r);
    hits.into_iter()
        .take(limit)
        .map(|(_, e)| {
            json!({"id": format!("emoji:{}", e.c), "name": e.n, "generic": e.g, "glyph": e.c,
                   "icon": null, "kind": "emoji", "score": 1.0})
        })
        .collect()
}

/// The clipboard history (`cliphist list`, newest first) filtered by `q`, at most `limit`; one explanatory row when
/// cliphist is not installed or holds nothing (Shōjiki: never an empty list that looks like "no matches").
pub fn clip_rows(q: &str, limit: usize) -> Vec<Value> {
    let out = match std::process::Command::new("cliphist").arg("list").output() {
        Ok(o) if o.status.success() => o.stdout,
        _ => return vec![note("launcher.clip.unavailable")],
    };
    let q = q.to_lowercase();
    let rows: Vec<Value> = String::from_utf8_lossy(&out)
        .lines()
        .filter_map(|l| l.split_once('\t'))
        .filter(|(_, text)| q.is_empty() || text.to_lowercase().contains(&q))
        .take(limit)
        .map(|(id, text)| {
            let shown: String = text.chars().take(120).collect();
            json!({"id": format!("clip:{id}"), "name": shown, "icon": null, "kind": "clip", "score": 1.0})
        })
        .collect();
    if rows.is_empty() && q.is_empty() {
        return vec![note("launcher.clip.empty")];
    }
    rows
}

/// A row that only says something (no id to launch): `name` is an i18n key the view translates.
fn note(key: &str) -> Value {
    json!({"id": "", "name": key, "icon": null, "kind": "note", "score": 0.0})
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn emoji_search() {
        let r = emoji_rows("grinning", 5);
        assert!(!r.is_empty());
        assert_eq!(r[0]["kind"], "emoji");
        assert!(r[0]["id"].as_str().unwrap().starts_with("emoji:"));
        assert!(emoji_rows("zzzz-no-such", 5).is_empty());
        assert_eq!(emoji_rows("", 7).len(), 7);
    }
}
