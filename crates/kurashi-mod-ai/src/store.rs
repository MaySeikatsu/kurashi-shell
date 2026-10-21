//! Conversations on disk: one JSON file each, `<data>/conversations/<id>.json` (`$XDG_DATA_HOME/kurashi/ai`, the
//! `{data_dir}` of MODS.md "Host processes"), written whole through a temporary file. The newest `history` are kept;
//! `history = 0` keeps none (and saves none). Files are read when the panel first opens and when one is opened.

use std::fs;
use std::io::Write;
use std::path::{Path, PathBuf};

use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum Role {
    User,
    Assistant,
}

impl Role {
    pub fn id(self) -> &'static str {
        match self {
            Self::User => "user",
            Self::Assistant => "assistant",
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct Message {
    pub role: Role,
    /// The text as written (an answer's think blocks between `<think>` marks).
    pub text: String,
    /// Unix seconds.
    #[serde(default)]
    pub at: i64,
    /// An answer's provider and model.
    #[serde(default, skip_serializing_if = "String::is_empty")]
    pub provider: String,
    #[serde(default, skip_serializing_if = "String::is_empty")]
    pub model: String,
    /// Why the answer failed (an i18n key), with the provider's words.
    #[serde(default, skip_serializing_if = "String::is_empty")]
    pub error: String,
    #[serde(default, skip_serializing_if = "String::is_empty")]
    pub detail: String,
    /// Stopped by the user before the end.
    #[serde(default, skip_serializing_if = "std::ops::Not::not")]
    pub stopped: bool,
}

impl Message {
    pub fn user(text: String, at: i64) -> Self {
        Self {
            role: Role::User,
            text,
            at,
            provider: String::new(),
            model: String::new(),
            error: String::new(),
            detail: String::new(),
            stopped: false,
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct Conversation {
    #[serde(default = "one")]
    pub v: u32,
    pub id: String,
    pub title: String,
    pub created: i64,
    pub updated: i64,
    pub messages: Vec<Message>,
}

fn one() -> u32 {
    1
}

/// What the conversation list shows.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Summary {
    pub id: String,
    pub title: String,
    pub updated: i64,
}

impl Conversation {
    pub fn new(id: String, at: i64) -> Self {
        Self {
            v: 1,
            id,
            title: String::new(),
            created: at,
            updated: at,
            messages: Vec::new(),
        }
    }

    pub fn summary(&self) -> Summary {
        Summary {
            id: self.id.clone(),
            title: self.title.clone(),
            updated: self.updated,
        }
    }
}

/// A conversation's title: the first line of its first question, at most 60 characters.
pub fn title_of(text: &str) -> String {
    let line = text
        .lines()
        .map(str::trim)
        .find(|l| !l.is_empty())
        .unwrap_or("");
    let mut t: String = line.chars().take(60).collect();
    if line.chars().count() > 60 {
        t = t.trim_end().to_string();
        t.push('…');
    }
    t
}

/// An id as this store makes them (digits, a dash): anything else is refused before it names a file.
pub fn valid_id(id: &str) -> bool {
    !id.is_empty() && id.len() <= 40 && id.bytes().all(|b| b.is_ascii_alphanumeric() || b == b'-')
}

pub struct Store {
    dir: PathBuf,
}

impl Store {
    /// `data` is the mod's data folder; conversations go in `conversations/` under it.
    pub fn new(data: PathBuf) -> Self {
        Self {
            dir: data.join("conversations"),
        }
    }

    pub fn dir(&self) -> &Path {
        &self.dir
    }

    fn path(&self, id: &str) -> PathBuf {
        self.dir.join(format!("{id}.json"))
    }

    /// A new id from the clock (ms), unique in the folder.
    pub fn new_id(&self, now_ms: i64) -> String {
        let base = now_ms.max(0).to_string();
        if !self.path(&base).exists() {
            return base;
        }
        (2..)
            .map(|n| format!("{base}-{n}"))
            .find(|id| !self.path(id).exists())
            .unwrap_or(base)
    }

    pub fn load(&self, id: &str) -> Option<Conversation> {
        if !valid_id(id) {
            return None;
        }
        let text = fs::read_to_string(self.path(id)).ok()?;
        let c: Conversation = serde_json::from_str(&text).ok()?;
        (c.id == id).then_some(c)
    }

    /// Every readable conversation, newest first. A broken file is skipped (and kept: it may be fixed by hand).
    pub fn list(&self) -> Vec<Summary> {
        let Ok(rd) = fs::read_dir(&self.dir) else {
            return Vec::new();
        };
        let mut out: Vec<Summary> = rd
            .filter_map(|e| e.ok())
            .filter_map(|e| {
                let name = e.file_name().into_string().ok()?;
                let id = name.strip_suffix(".json")?;
                self.load(id).map(|c| c.summary())
            })
            .collect();
        out.sort_by(|a, b| b.updated.cmp(&a.updated).then(b.id.cmp(&a.id)));
        out
    }

    /// Writes `c`, then drops the oldest beyond `keep` (0: writes nothing and keeps nothing).
    pub fn save(&self, c: &Conversation, keep: usize) -> std::io::Result<()> {
        if keep == 0 {
            return Ok(());
        }
        fs::create_dir_all(&self.dir)?;
        let tmp = self.dir.join(format!(".{}.json.tmp", c.id));
        {
            let mut f = fs::File::create(&tmp)?;
            f.write_all(
                serde_json::to_string_pretty(c)
                    .map_err(std::io::Error::other)?
                    .as_bytes(),
            )?;
            f.sync_all()?;
        }
        fs::rename(&tmp, self.path(&c.id))?;
        self.prune(keep);
        Ok(())
    }

    pub fn prune(&self, keep: usize) {
        for old in self.list().into_iter().skip(keep) {
            let _ = fs::remove_file(self.path(&old.id));
        }
    }

    pub fn delete(&self, id: &str) -> bool {
        valid_id(id) && fs::remove_file(self.path(id)).is_ok()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn titles_and_ids() {
        assert_eq!(
            title_of("\n  How do I list files?\nmore"),
            "How do I list files?"
        );
        let long = "a".repeat(70);
        assert_eq!(title_of(&long).chars().count(), 61);
        assert!(title_of(&long).ends_with('…'));
        assert!(valid_id("1729500000000-2"));
        assert!(!valid_id("../etc/passwd"));
        assert!(!valid_id(""));
    }

    #[test]
    fn save_list_load_prune_delete() {
        let dir = tempfile::tempdir().unwrap();
        let s = Store::new(dir.path().to_path_buf());
        assert!(s.list().is_empty());
        for (i, t) in [(1, "first"), (2, "second"), (3, "third")] {
            let id = s.new_id(1000 + i);
            let mut c = Conversation::new(id, i);
            c.title = t.into();
            c.messages.push(Message::user(t.into(), i));
            s.save(&c, 2).unwrap();
        }
        let l = s.list();
        assert_eq!(
            l.iter().map(|x| x.title.as_str()).collect::<Vec<_>>(),
            vec!["third", "second"]
        );
        let c = s.load(&l[0].id).unwrap();
        assert_eq!(c.messages[0].text, "third");
        assert_eq!(s.new_id(1003), "1003-2");
        // A broken file is skipped.
        fs::write(s.dir().join("999.json"), "{").unwrap();
        assert_eq!(s.list().len(), 2);
        assert!(s.delete(&l[0].id));
        assert_eq!(s.list().len(), 1);
        assert!(!s.delete("../x"));
        // history = 0 writes nothing.
        let mut c = Conversation::new("5".into(), 5);
        c.title = "x".into();
        s.save(&c, 0).unwrap();
        assert!(s.load("5").is_none());
    }

    #[test]
    fn the_file_format() {
        let mut c = Conversation::new("7".into(), 7);
        c.messages.push(Message::user("Hi".into(), 7));
        c.messages.push(Message {
            role: Role::Assistant,
            text: "Hello".into(),
            at: 8,
            provider: "ollama".into(),
            model: "llama3.2".into(),
            error: String::new(),
            detail: String::new(),
            stopped: true,
        });
        let v: serde_json::Value = serde_json::to_value(&c).unwrap();
        assert_eq!(
            v["messages"][0],
            serde_json::json!({"role": "user", "text": "Hi", "at": 7})
        );
        assert_eq!(v["messages"][1]["stopped"], true);
        assert!(v["messages"][1].get("error").is_none());
    }
}
