//! The checklist file as lines (K46, docs/ux/tasks.md "Fit"): which lines are task items, what they say, and the
//! edits the actions make. Pure: text in, text out. Every line keeps its own ending (CRLF stays CRLF) and every line that
//! is not touched comes back byte for byte. An item is `- [ ] …` or `- [x] …` (also `*` and `+`, indented or not)
//! outside a fenced code block and the front matter; any other status (`[/]`, `[-]`) is not an item and is kept.
//! Obsidian Tasks' markers end the text: `📅 YYYY-MM-DD` is the due date, `⏫ 🔼 🔽` (and `🔺 ⏬`) the priority,
//! `✅ YYYY-MM-DD` the done date; the shown text stops at the first marker, and an edit keeps everything from there.

/// One line of the file: its text and its own ending ("\n", "\r\n" or "" for a last line without one).
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Line {
    pub body: String,
    pub ending: String,
}

/// A task item as the document shows it, and where it lives.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Item {
    /// Index into [`File::lines`].
    pub line: usize,
    /// A hash of `text` and the item's occurrence among items of the same text: ticking, re-dating or editing another
    /// line keeps it; editing this item's text gives a new one.
    pub id: String,
    pub text: String,
    pub done: bool,
    pub due: Option<String>,
    pub priority: Option<u8>,
    /// The done date (`✅ YYYY-MM-DD`), when the item carries one.
    pub done_on: Option<String>,
    /// The nearest `#` heading above.
    pub section: Option<String>,
}

/// The parsed file: its lines, the items among them, and the line ending new lines get.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct File {
    pub lines: Vec<Line>,
    pub items: Vec<Item>,
    pub eol: &'static str,
}

/// The Obsidian Tasks markers that end an item's text (a variation selector may follow each).
const MARKERS: &[&str] = &[
    "📅", "⏳", "🛫", "✅", "➕", "❌", "🔁", "⏫", "🔼", "🔽", "🔺", "⏬", "🆔", "⛔", "🏁",
];
const VS16: char = '\u{FE0F}';
const BOM: char = '\u{FEFF}';

/// Longest text an item may have (characters).
pub const MAX_TEXT: usize = 500;

/// The parts of an item line: `<indent><bullet> [<status>] <rest>`.
struct Parts<'a> {
    /// Byte offset of the status character.
    status_at: usize,
    status: char,
    /// Byte offset where the rest (text and markers) begins.
    rest_at: usize,
    rest: &'a str,
}

fn item_parts(body: &str) -> Option<Parts<'_>> {
    let trimmed = body.trim_start_matches([' ', '\t']);
    let indent = body.len() - trimmed.len();
    let mut chars = trimmed.char_indices();
    let (_, bullet) = chars.next()?;
    if !matches!(bullet, '-' | '*' | '+') {
        return None;
    }
    let after = &trimmed[1..];
    let after = after.strip_prefix(' ')?;
    let after = after.trim_start_matches(' ');
    let open_at = indent + (trimmed.len() - after.len());
    let mut it = after.chars();
    if it.next()? != '[' {
        return None;
    }
    let status = it.next()?;
    if !matches!(status, ' ' | 'x' | 'X') {
        return None;
    }
    if it.next()? != ']' {
        return None;
    }
    let close_end = open_at + 1 + status.len_utf8() + 1;
    let tail = &body[close_end..];
    // `- [ ]` alone, or followed by a space; `- [ ]x` is not an item.
    let rest_at = if tail.is_empty() {
        close_end
    } else {
        let stripped = tail.strip_prefix(' ')?;
        close_end + (tail.len() - stripped.len())
    };
    Some(Parts {
        status_at: open_at + 1,
        status,
        rest_at,
        rest: &body[rest_at..],
    })
}

/// Byte offset of the first marker in `rest`, or its length.
fn marker_at(rest: &str) -> usize {
    MARKERS
        .iter()
        .filter_map(|m| rest.find(m))
        .min()
        .unwrap_or(rest.len())
}

/// The date after `marker` in `tail` ("2026-10-21"), when it is one.
fn date_after(tail: &str, marker: &str) -> Option<String> {
    let at = tail.find(marker)? + marker.len();
    let s = tail[at..].trim_start_matches(VS16).trim_start();
    let d = s.get(..10)?;
    chrono::NaiveDate::parse_from_str(d, "%Y-%m-%d").ok()?;
    Some(d.to_owned())
}

fn priority_of(tail: &str) -> Option<u8> {
    if tail.contains('⏫') || tail.contains('🔺') {
        Some(1)
    } else if tail.contains('🔼') {
        Some(2)
    } else if tail.contains('🔽') || tail.contains('⏬') {
        Some(3)
    } else {
        None
    }
}

/// The heading text of an ATX heading line (`# Title`, `## Title ##`), or None.
fn heading(body: &str) -> Option<String> {
    let s = body.trim_start_matches(BOM);
    let indent = s.len() - s.trim_start_matches(' ').len();
    if indent > 3 {
        return None;
    }
    let s = &s[indent..];
    let level = s.chars().take_while(|c| *c == '#').count();
    if level == 0 || level > 6 {
        return None;
    }
    let rest = &s[level..];
    if !rest.is_empty() && !rest.starts_with([' ', '\t']) {
        return None;
    }
    let text = rest.trim().trim_end_matches('#').trim_end();
    Some(text.to_owned())
}

fn fence(body: &str) -> Option<&'static str> {
    let s = body.trim_start_matches(' ');
    if s.starts_with("```") {
        Some("```")
    } else if s.starts_with("~~~") {
        Some("~~~")
    } else {
        None
    }
}

/// FNV-1a, 64 bit: a stable hash with no dependency (ids must survive a daemon restart).
fn fnv(s: &str) -> u64 {
    let mut h: u64 = 0xcbf2_9ce4_8422_2325;
    for b in s.as_bytes() {
        h ^= u64::from(*b);
        h = h.wrapping_mul(0x0100_0000_01b3);
    }
    h
}

/// Splits `src` into lines that keep their endings.
fn split(src: &str) -> Vec<Line> {
    src.split_inclusive('\n')
        .map(|l| {
            if let Some(b) = l.strip_suffix("\r\n") {
                Line {
                    body: b.to_owned(),
                    ending: "\r\n".into(),
                }
            } else if let Some(b) = l.strip_suffix('\n') {
                Line {
                    body: b.to_owned(),
                    ending: "\n".into(),
                }
            } else {
                Line {
                    body: l.to_owned(),
                    ending: String::new(),
                }
            }
        })
        .collect()
}

impl File {
    pub fn parse(src: &str) -> Self {
        let lines = split(src);
        let eol = match lines.iter().find(|l| !l.ending.is_empty()) {
            Some(l) if l.ending == "\r\n" => "\r\n",
            _ => "\n",
        };
        let mut f = Self {
            lines,
            items: Vec::new(),
            eol,
        };
        f.index();
        f
    }

    /// Finds the items again after the lines changed.
    fn index(&mut self) {
        let mut items = Vec::new();
        let mut section: Option<String> = None;
        let mut in_fence: Option<&'static str> = None;
        let mut seen: std::collections::HashMap<String, usize> = std::collections::HashMap::new();
        // Front matter: a first line `---` opens it, the next `---` or `...` closes it.
        let mut front = self
            .lines
            .first()
            .is_some_and(|l| l.body.trim_start_matches(BOM).trim_end() == "---");
        for (i, l) in self.lines.iter().enumerate() {
            let body = l.body.as_str();
            if front {
                if i > 0 && matches!(body.trim_end(), "---" | "...") {
                    front = false;
                }
                continue;
            }
            if let Some(open) = in_fence {
                if fence(body) == Some(open) {
                    in_fence = None;
                }
                continue;
            }
            if let Some(f) = fence(body) {
                in_fence = Some(f);
                continue;
            }
            if let Some(h) = heading(body) {
                section = (!h.is_empty()).then_some(h);
                continue;
            }
            let Some(parts) = item_parts(body.trim_start_matches(BOM)) else {
                continue;
            };
            let cut = marker_at(parts.rest);
            let text = parts.rest[..cut].trim().to_owned();
            let tail = &parts.rest[cut..];
            let n = seen.entry(text.clone()).or_insert(0);
            let id = format!("{:016x}-{n}", fnv(&text));
            *n += 1;
            items.push(Item {
                line: i,
                id,
                done: parts.status != ' ',
                due: date_after(tail, "📅"),
                priority: priority_of(tail),
                done_on: date_after(tail, "✅"),
                section: section.clone(),
                text,
            });
        }
        self.items = items;
    }

    pub fn render(&self) -> String {
        let mut out = String::new();
        for l in &self.lines {
            out.push_str(&l.body);
            out.push_str(&l.ending);
        }
        out
    }

    pub fn find(&self, id: &str) -> Option<&Item> {
        self.items.iter().find(|i| i.id == id)
    }

    pub fn open_count(&self) -> usize {
        self.items.iter().filter(|i| !i.done).count()
    }

    /// The line's offset of BOM bytes (the first line may start with one; it is kept in front of the item).
    fn bom_len(&self, line: usize) -> usize {
        if line == 0 && self.lines[0].body.starts_with(BOM) {
            BOM.len_utf8()
        } else {
            0
        }
    }

    /// Ticks or unticks item `id`. Ticking appends the done date (` ✅ YYYY-MM-DD`, as Obsidian Tasks does); unticking
    /// takes it off. Returns the item's done state after, or None for an unknown id.
    pub fn toggle(&mut self, id: &str, today: &str) -> Option<bool> {
        let item = self.find(id)?.clone();
        let off = self.bom_len(item.line);
        let body = self.lines[item.line].body.clone();
        let parts = item_parts(&body[off..])?;
        let status_at = off + parts.status_at;
        let done = !item.done;
        let mut new = String::with_capacity(body.len() + 16);
        new.push_str(&body[..status_at]);
        new.push(if done { 'x' } else { ' ' });
        new.push_str(&body[status_at + parts.status.len_utf8()..]);
        if done {
            if item.done_on.is_none() {
                let trimmed = new.trim_end().len();
                new.truncate(trimmed);
                new.push_str(" ✅ ");
                new.push_str(today);
            }
        } else {
            new = strip_done_date(&new);
        }
        self.lines[item.line].body = new;
        self.index();
        Some(done)
    }

    /// Replaces item `id`'s text and keeps its status, indent, bullet and markers. Returns the new id.
    pub fn edit(&mut self, id: &str, text: &str) -> Option<String> {
        let item = self.find(id)?.clone();
        let off = self.bom_len(item.line);
        let body = self.lines[item.line].body.clone();
        let parts = item_parts(&body[off..])?;
        let tail = parts.rest[marker_at(parts.rest)..].trim_end();
        let mut new = body[..off + parts.rest_at].to_owned();
        if off + parts.rest_at == body.len() {
            new.push(' ');
        }
        new.push_str(text);
        if !tail.is_empty() {
            new.push(' ');
            new.push_str(tail);
        }
        self.lines[item.line].body = new;
        self.index();
        self.items
            .iter()
            .find(|i| i.line == item.line)
            .map(|i| i.id.clone())
    }

    /// Removes item `id`'s line. A last line without an ending keeps the file without a final newline.
    pub fn remove(&mut self, id: &str) -> bool {
        let Some(line) = self.find(id).map(|i| i.line) else {
            return false;
        };
        self.remove_lines(&[line]);
        true
    }

    /// Removes every done item. Returns how many.
    pub fn clear_done(&mut self) -> usize {
        let lines: Vec<usize> = self
            .items
            .iter()
            .filter(|i| i.done)
            .map(|i| i.line)
            .collect();
        self.remove_lines(&lines);
        lines.len()
    }

    fn remove_lines(&mut self, lines: &[usize]) {
        for &line in lines.iter().rev() {
            let gone = self.lines.remove(line);
            if gone.ending.is_empty() && line > 0 && line == self.lines.len() {
                self.lines[line - 1].ending.clear();
            }
        }
        self.index();
    }

    /// Adds `- [ ] text` under the last section: after the last item below the last heading, else at the end of the file.
    /// The bullet follows that item's. Returns the new item's id.
    pub fn add(&mut self, text: &str) -> String {
        let last_heading = self
            .lines
            .iter()
            .enumerate()
            .rev()
            .find(|(_, l)| heading(&l.body).is_some())
            .map(|(i, _)| i);
        let anchor = self
            .items
            .iter()
            .rev()
            .find(|i| last_heading.is_none_or(|h| i.line > h))
            .map(|i| i.line);
        let bullet = anchor
            .and_then(|l| {
                self.lines[l]
                    .body
                    .trim_start_matches(BOM)
                    .trim_start_matches([' ', '\t'])
                    .chars()
                    .next()
            })
            .unwrap_or('-');
        // An item that is indented under another is a subtask: the new one goes at the top level.
        let at = match anchor {
            Some(l) => l + 1,
            None => self.lines.len(),
        };
        if at > 0 && self.lines[at - 1].ending.is_empty() {
            self.lines[at - 1].ending = self.eol.to_owned();
        }
        // At the end of a file whose last line is text, a blank line keeps the new item out of that paragraph.
        let mut new_lines = Vec::new();
        if anchor.is_none()
            && at > 0
            && !self.lines[at - 1].body.trim().is_empty()
            && heading(&self.lines[at - 1].body).is_none()
        {
            new_lines.push(Line {
                body: String::new(),
                ending: self.eol.to_owned(),
            });
        }
        new_lines.push(Line {
            body: format!("{bullet} [ ] {text}"),
            ending: self.eol.to_owned(),
        });
        let item_line = at + new_lines.len() - 1;
        for (k, l) in new_lines.into_iter().enumerate() {
            self.lines.insert(at + k, l);
        }
        self.index();
        self.items
            .iter()
            .find(|i| i.line == item_line)
            .map(|i| i.id.clone())
            .unwrap_or_default()
    }
}

/// `body` without its ` ✅ YYYY-MM-DD` (the space before it too).
fn strip_done_date(body: &str) -> String {
    let Some(at) = body.find('✅') else {
        return body.to_owned();
    };
    let after = &body[at + '✅'.len_utf8()..];
    let after_vs = after.trim_start_matches(VS16);
    let after_ws = after_vs.trim_start();
    let end = if after_ws
        .get(..10)
        .is_some_and(|d| chrono::NaiveDate::parse_from_str(d, "%Y-%m-%d").is_ok())
    {
        body.len() - after_ws.len() + 10
    } else {
        body.len() - after_vs.len()
    };
    let start = body[..at].trim_end().len();
    let mut out = body[..start].to_owned();
    let rest = &body[end..];
    if !rest.is_empty() && !out.is_empty() && !rest.starts_with(' ') {
        out.push(' ');
    }
    out.push_str(rest);
    out
}

/// An item's text as the user typed it, made one line: line breaks become spaces, the ends are trimmed. None when it is
/// empty or longer than [`MAX_TEXT`].
pub fn clean_text(s: &str) -> Option<String> {
    let one: String = s
        .chars()
        .map(|c| {
            if matches!(c, '\r' | '\n' | '\u{2028}' | '\u{2029}') {
                ' '
            } else {
                c
            }
        })
        .collect();
    let t = one.trim();
    (!t.is_empty() && t.chars().count() <= MAX_TEXT).then(|| t.to_owned())
}

#[cfg(test)]
mod tests {
    use super::*;

    const OBSIDIAN: &str = include_str!("../fixtures/obsidian.md");
    const CRLF: &str = include_str!("../fixtures/crlf.md");
    const UNICODE: &str = include_str!("../fixtures/unicode.md");
    const PLAIN: &str = include_str!("../fixtures/plain.md");
    const TODAY: &str = "2026-10-20";

    fn texts(f: &File) -> Vec<&str> {
        f.items.iter().map(|i| i.text.as_str()).collect()
    }

    #[test]
    fn round_trip_is_byte_for_byte() {
        for src in [
            OBSIDIAN,
            CRLF,
            UNICODE,
            PLAIN,
            "",
            "\n",
            "- [ ] a",
            "x\r\n\r\n",
        ] {
            assert_eq!(File::parse(src).render(), src);
        }
    }

    #[test]
    fn obsidian_markers_sections_and_non_items() {
        let f = File::parse(OBSIDIAN);
        assert_eq!(
            texts(&f),
            [
                "Pay the rent",
                "Call the dentist #health",
                "Read chapter 3",
                "Water the plants",
                "Sub task",
                "Buy milk",
                "Buy milk",
            ]
        );
        let rent = &f.items[0];
        assert_eq!(rent.due.as_deref(), Some("2026-10-21"));
        assert_eq!(rent.priority, Some(1));
        assert_eq!(rent.section.as_deref(), Some("Today"));
        assert!(!rent.done);
        let dentist = &f.items[1];
        assert_eq!(dentist.priority, Some(2));
        assert_eq!(dentist.due, None);
        let read = &f.items[2];
        assert!(read.done);
        assert_eq!(read.done_on.as_deref(), Some("2026-10-19"));
        assert_eq!(read.priority, Some(3));
        assert_eq!(f.items[3].section.as_deref(), Some("Later"));
        // The same text twice: two ids, by occurrence.
        assert_ne!(f.items[5].id, f.items[6].id);
        assert!(f.items[5].id.ends_with("-0") && f.items[6].id.ends_with("-1"));
        // Items in a code fence, in front matter, `[-]` and `[/]` statuses are not items.
        assert!(!texts(&f).contains(&"not a task in a fence"));
        assert!(!texts(&f).contains(&"cancelled"));
        assert_eq!(f.open_count(), 6);
    }

    #[test]
    fn ids_survive_unrelated_edits_and_toggles() {
        let mut f = File::parse(OBSIDIAN);
        let ids: Vec<String> = f.items.iter().map(|i| i.id.clone()).collect();
        assert_eq!(f.toggle(&ids[0], TODAY), Some(true));
        let after: Vec<String> = f.items.iter().map(|i| i.id.clone()).collect();
        assert_eq!(ids, after);
        // A line added above every item does not move an id either.
        let shifted = File::parse(&format!("# Inbox\n- [ ] new one\n{OBSIDIAN}"));
        assert_eq!(
            shifted.find(&ids[3]).map(|i| i.text.as_str()),
            Some("Water the plants")
        );
    }

    #[test]
    fn toggle_appends_and_removes_the_done_date() {
        let mut f = File::parse("- [ ] Pay the rent ⏫ 📅 2026-10-21\n");
        let id = f.items[0].id.clone();
        assert_eq!(f.toggle(&id, TODAY), Some(true));
        assert_eq!(
            f.render(),
            "- [x] Pay the rent ⏫ 📅 2026-10-21 ✅ 2026-10-20\n"
        );
        assert_eq!(f.items[0].done_on.as_deref(), Some(TODAY));
        assert_eq!(f.toggle(&id, TODAY), Some(false));
        assert_eq!(f.render(), "- [ ] Pay the rent ⏫ 📅 2026-10-21\n");
        // A done date in the middle of the markers is taken out cleanly.
        let mut g = File::parse("* [X] a ✅ 2026-10-01 🔁 every day\n");
        let gid = g.items[0].id.clone();
        g.toggle(&gid, TODAY);
        assert_eq!(g.render(), "* [ ] a 🔁 every day\n");
        assert_eq!(g.toggle("nope", TODAY), None);
    }

    #[test]
    fn edit_keeps_markers_indent_and_bullet() {
        let mut f = File::parse("  + [ ] old text 🔼 📅 2026-11-01  \n");
        let id = f.items[0].id.clone();
        let new = f.edit(&id, "new text").expect("edited");
        assert_ne!(new, id);
        assert_eq!(f.render(), "  + [ ] new text 🔼 📅 2026-11-01\n");
        assert_eq!(f.items[0].text, "new text");
        let mut g = File::parse("- [ ]\n");
        let gid = g.items[0].id.clone();
        g.edit(&gid, "filled");
        assert_eq!(g.render(), "- [ ] filled\n");
    }

    #[test]
    fn crlf_stays_crlf() {
        let mut f = File::parse(CRLF);
        assert_eq!(f.eol, "\r\n");
        let id = f.items[0].id.clone();
        f.toggle(&id, TODAY);
        f.add("third");
        let out = f.render();
        assert!(
            !out.replace("\r\n", "").contains('\n'),
            "a bare LF crept in: {out:?}"
        );
        assert!(out.contains("- [ ] third\r\n"));
        assert!(out.starts_with("# List\r\n- [x] first ✅ 2026-10-20\r\n"));
    }

    #[test]
    fn unicode_text_and_bom() {
        let mut f = File::parse(UNICODE);
        assert_eq!(f.items[0].text, "牛乳を買う 🥛");
        assert_eq!(f.items[0].section.as_deref(), Some("買い物"));
        assert_eq!(f.items[1].text, "Ünïcödé — ok");
        let id = f.items[0].id.clone();
        f.toggle(&id, TODAY);
        assert!(f.render().starts_with('\u{FEFF}'));
        assert!(f.render().contains("- [x] 牛乳を買う 🥛 ✅ 2026-10-20"));
    }

    #[test]
    fn add_goes_under_the_last_section() {
        let mut f = File::parse(OBSIDIAN);
        let id = f.add("Fresh");
        let item = f.find(&id).expect("added");
        assert_eq!(item.section.as_deref(), Some("Shopping"));
        // Right after that section's last item, before the trailing text.
        let rendered = f.render();
        assert!(
            rendered.contains("- [ ] Buy milk\n- [ ] Fresh\n"),
            "{rendered}"
        );
        // A blank file, and a file with no newline at its end.
        let mut blank = File::parse("");
        blank.add("one");
        assert_eq!(blank.render(), "- [ ] one\n");
        let mut tail = File::parse("- [ ] a");
        tail.add("b");
        assert_eq!(tail.render(), "- [ ] a\n- [ ] b\n");
        // A note with no items: the new one gets its own paragraph.
        let mut prose = File::parse("Some words");
        prose.add("x");
        assert_eq!(prose.render(), "Some words\n\n- [ ] x\n");
        // A last heading with nothing under it yet: right under it.
        let mut empty_section = File::parse("- [ ] a\n# Next\n");
        empty_section.add("b");
        assert_eq!(empty_section.render(), "- [ ] a\n# Next\n- [ ] b\n");
    }

    #[test]
    fn remove_and_clear_done() {
        let mut f = File::parse(PLAIN);
        let n = f.items.len();
        let id = f.items[0].id.clone();
        assert!(f.remove(&id));
        assert_eq!(f.items.len(), n - 1);
        assert!(!f.remove("nope"));
        assert_eq!(f.clear_done(), 1);
        assert!(f.items.iter().all(|i| !i.done));
        assert!(f.render().contains("Plain text stays."));
        // The last line without an ending: the file still has no final newline.
        let mut g = File::parse("- [ ] a\n- [x] b");
        g.clear_done();
        assert_eq!(g.render(), "- [ ] a");
    }

    #[test]
    fn clean_text_is_one_line() {
        assert_eq!(clean_text("  a\nb \r\n").as_deref(), Some("a b"));
        assert_eq!(clean_text("   "), None);
        assert_eq!(clean_text(&"x".repeat(MAX_TEXT + 1)), None);
    }
}
