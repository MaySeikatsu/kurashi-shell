//! The launcher's `:` prefix mode (session 9, after Capsule's launcher): emoji, in rows of the app rows' shape with
//! `kind` `emoji` and an id the launch action understands (`emoji:<char>`). The clipboard (`;`) is [`crate::clip`],
//! the keybind cheat sheet (`?`) [`crate::keys`].

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

/// Emoji whose name or keys contain every word of `q` (all of them for an empty `q`), at most `limit`. `recent` is an
/// emoji's frecency score (0 = never copied): recent ones come first (W26, as GNOME Characters' and Noctalia's
/// "recent"), then a name that starts with the first word, then the data's order. Recent rows carry `recent: true`.
pub fn emoji_rows(q: &str, limit: usize, recent: &dyn Fn(&str) -> f64) -> Vec<Value> {
    let words: Vec<String> = q.split_whitespace().map(str::to_lowercase).collect();
    let mut hits: Vec<(f64, usize, usize, &Emoji)> = emoji()
        .iter()
        .enumerate()
        .filter(|(_, e)| words.iter().all(|w| e.k.contains(w.as_str())))
        .map(|(i, e)| {
            // A name that starts with the first word ranks first.
            let rank = usize::from(!words.first().is_some_and(|w| e.k.starts_with(w.as_str())));
            (recent(&e.c), rank, i, e)
        })
        .collect();
    hits.sort_by(|a, b| b.0.total_cmp(&a.0).then(a.1.cmp(&b.1)).then(a.2.cmp(&b.2)));
    hits.into_iter()
        .take(limit)
        .map(|(score, _, _, e)| {
            let mut r = json!({"id": format!("emoji:{}", e.c), "name": e.n, "generic": e.g, "glyph": e.c,
                               "icon": null, "kind": "emoji", "score": 1.0});
            if score > 0.0 {
                r["recent"] = json!(true);
            }
            r
        })
        .collect()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn emoji_search() {
        let none = |_: &str| 0.0;
        let r = emoji_rows("grinning", 5, &none);
        assert!(!r.is_empty());
        assert_eq!(r[0]["kind"], "emoji");
        assert!(r[0]["id"].as_str().unwrap().starts_with("emoji:"));
        assert!(emoji_rows("zzzz-no-such", 5, &none).is_empty());
        assert_eq!(emoji_rows("", 7, &none).len(), 7);
    }

    #[test]
    fn recent_emoji_come_first() {
        let all = emoji_rows("", 400, &|_| 0.0);
        let (a, b) = (
            all[300]["glyph"].as_str().unwrap().to_owned(),
            all[200]["glyph"].as_str().unwrap().to_owned(),
        );
        let mut f = crate::Frecency::memory();
        f.record(&a, 1000);
        f.record(&a, 1000);
        f.record(&b, 1000);
        let recent = |c: &str| f.score(c, 1000);
        let r = emoji_rows("", 10, &recent);
        assert_eq!(r[0]["glyph"], a.as_str());
        assert_eq!(r[1]["glyph"], b.as_str());
        assert_eq!(r[0]["recent"], true);
        assert!(r[2].get("recent").is_none());
        // A query keeps a recent one first among its matches.
        let third = emoji_rows("face", 3, &|_| 0.0)[2]["glyph"]
            .as_str()
            .unwrap()
            .to_owned();
        let r = emoji_rows("face", 3, &|c| if c == third { 1.0 } else { 0.0 });
        assert_eq!(r[0]["glyph"], third.as_str());
    }
}
