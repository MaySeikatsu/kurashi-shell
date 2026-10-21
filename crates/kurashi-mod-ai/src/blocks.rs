//! An answer as the panel draws it: Markdown text, code and think blocks. After ii's `StringUtils.splitMarkdownBlocks`
//! (```` ```lang ```` fences and `<think>…</think>`, an unfinished one still open while the answer streams), here line
//! based so a fence must start a line (CommonMark: up to three spaces, ``` or ~~~, closed by the same mark at least as
//! long), and done in the daemon so the view only draws.

use serde_json::{Value, json};

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Kind {
    Text,
    Code,
    Think,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Block {
    pub kind: Kind,
    pub text: String,
    /// A code block's language (the fence's info word), empty for none.
    pub lang: String,
    /// Not closed yet: the answer is still being written (or broke off).
    pub open: bool,
}

impl Block {
    pub fn json(&self) -> Value {
        let mut v = json!({
            "kind": match self.kind { Kind::Text => "text", Kind::Code => "code", Kind::Think => "think" },
            "text": self.text,
        });
        if !self.lang.is_empty() {
            v["lang"] = json!(self.lang);
        }
        if self.open {
            v["open"] = json!(true);
        }
        v
    }
}

pub const THINK_OPEN: &str = "<think>";
pub const THINK_CLOSE: &str = "</think>";

/// The blocks of `text`, in order; text blocks that are only white space are left out.
pub fn split(text: &str) -> Vec<Block> {
    let mut out = Vec::new();
    let mut rest = text;
    while !rest.is_empty() {
        match rest.find(THINK_OPEN) {
            None => {
                fences(rest, &mut out);
                break;
            }
            Some(at) => {
                fences(&rest[..at], &mut out);
                let inner = &rest[at + THINK_OPEN.len()..];
                match inner.find(THINK_CLOSE) {
                    Some(end) => {
                        push_think(&inner[..end], false, &mut out);
                        rest = &inner[end + THINK_CLOSE.len()..];
                    }
                    None => {
                        push_think(inner, true, &mut out);
                        break;
                    }
                }
            }
        }
    }
    out
}

/// `text` without its think blocks: what is copied and what is sent back to the model as the answer.
pub fn without_think(text: &str) -> String {
    let mut s = String::new();
    for b in split(text) {
        match b.kind {
            Kind::Think => {}
            Kind::Text => {
                if !s.is_empty() {
                    s.push_str("\n\n");
                }
                s.push_str(&b.text);
            }
            Kind::Code => {
                if !s.is_empty() {
                    s.push_str("\n\n");
                }
                s.push_str(&format!("```{}\n{}\n```", b.lang, b.text));
            }
        }
    }
    s
}

fn push_think(text: &str, open: bool, out: &mut Vec<Block>) {
    let t = text.trim();
    if t.is_empty() && !open {
        return;
    }
    out.push(Block {
        kind: Kind::Think,
        text: t.to_string(),
        lang: String::new(),
        open,
    });
}

fn push_text(buf: &mut Vec<&str>, out: &mut Vec<Block>) {
    let joined = buf.join("\n");
    buf.clear();
    let t = joined.trim_matches(|c: char| c == '\n' || c == '\r');
    if t.trim().is_empty() {
        return;
    }
    out.push(Block {
        kind: Kind::Text,
        text: t.trim_end().to_string(),
        lang: String::new(),
        open: false,
    });
}

/// A fence line: its mark (` or ~), its length and its info string.
fn fence(line: &str) -> Option<(char, usize, &str)> {
    let indent = line.len() - line.trim_start_matches(' ').len();
    if indent > 3 {
        return None;
    }
    let l = &line[indent..];
    let mark = l.chars().next().filter(|c| *c == '`' || *c == '~')?;
    let n = l.chars().take_while(|c| *c == mark).count();
    if n < 3 {
        return None;
    }
    let info = l[n..].trim();
    // An info string of a backtick fence cannot hold a backtick (CommonMark).
    if mark == '`' && info.contains('`') {
        return None;
    }
    Some((mark, n, info))
}

fn fences(text: &str, out: &mut Vec<Block>) {
    let mut buf: Vec<&str> = Vec::new();
    let mut code: Option<(char, usize, String, Vec<&str>)> = None;
    for line in text.split('\n') {
        let line = line.strip_suffix('\r').unwrap_or(line);
        match code.as_mut() {
            None => {
                if let Some((mark, n, info)) = fence(line) {
                    push_text(&mut buf, out);
                    let lang = info.split_whitespace().next().unwrap_or("").to_string();
                    code = Some((mark, n, lang, Vec::new()));
                } else {
                    buf.push(line);
                }
            }
            Some((mark, n, lang, lines)) => {
                let closes = fence(line)
                    .is_some_and(|(m, k, info)| m == *mark && k >= *n && info.is_empty());
                if closes {
                    out.push(Block {
                        kind: Kind::Code,
                        text: lines.join("\n"),
                        lang: std::mem::take(lang),
                        open: false,
                    });
                    code = None;
                } else {
                    lines.push(line);
                }
            }
        }
    }
    match code {
        Some((_, _, lang, lines)) => out.push(Block {
            kind: Kind::Code,
            text: lines.join("\n"),
            lang,
            open: true,
        }),
        None => push_text(&mut buf, out),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn kinds(bs: &[Block]) -> Vec<(&str, &str, bool)> {
        bs.iter()
            .map(|b| {
                (
                    match b.kind {
                        Kind::Text => "text",
                        Kind::Code => "code",
                        Kind::Think => "think",
                    },
                    b.text.as_str(),
                    b.open,
                )
            })
            .collect()
    }

    #[test]
    fn text_code_and_think() {
        let t = "<think>\nThe user wants a loop.\n</think>\n\nHere is one:\n\n```rust\nfor i in 0..3 {\n    println!(\"{i}\");\n}\n```\n\nThat prints **three** lines.";
        let b = split(t);
        assert_eq!(
            kinds(&b),
            vec![
                ("think", "The user wants a loop.", false),
                ("text", "Here is one:", false),
                ("code", "for i in 0..3 {\n    println!(\"{i}\");\n}", false),
                ("text", "That prints **three** lines.", false),
            ]
        );
        assert_eq!(b[2].lang, "rust");
        assert_eq!(b[2].json()["lang"], "rust");
        assert!(b[1].json().get("open").is_none());
    }

    #[test]
    fn open_blocks_while_streaming() {
        assert_eq!(
            kinds(&split("Try:\n```sh\nls -l")),
            vec![("text", "Try:", false), ("code", "ls -l", true)]
        );
        assert_eq!(kinds(&split("<think>hmm")), vec![("think", "hmm", true)]);
        // The opening fence alone: an empty open code block.
        assert_eq!(kinds(&split("```")), vec![("code", "", true)]);
        assert_eq!(split("```py\n")[0].lang, "py");
    }

    #[test]
    fn fences_follow_commonmark() {
        // A longer fence holds a shorter one; tildes do not close backticks.
        let t = "````md\n```js\nx\n```\n~~~\n````\nafter";
        assert_eq!(
            kinds(&split(t)),
            vec![
                ("code", "```js\nx\n```\n~~~", false),
                ("text", "after", false)
            ]
        );
        // Inline backticks and indented code are text.
        assert_eq!(
            kinds(&split("use `ls` here\n\n    ```\n    not a fence")),
            vec![("text", "use `ls` here\n\n    ```\n    not a fence", false)]
        );
        // CRLF answers.
        assert_eq!(
            kinds(&split("a\r\n```\r\nb\r\n```\r\n")),
            vec![("text", "a", false), ("code", "b", false)]
        );
        assert!(split("  \n\n ").is_empty());
    }

    #[test]
    fn without_think_keeps_the_answer() {
        assert_eq!(
            without_think("<think>x</think>\n\nOK\n\n```sh\nls\n```"),
            "OK\n\n```sh\nls\n```"
        );
        assert_eq!(without_think("plain"), "plain");
    }
}
