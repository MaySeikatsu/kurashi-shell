//! `kurashi mod check` (K154, MODS.md "Feeling native"): one mod's folder held to the ruleset — the manifest, what its
//! QML reads and calls against `uses`, the variants a placeable module answers for, and the lints that keep a mod
//! native (tokens, copy, the kit, Ma). The CLI, the daemon's `mod.check` and the bundled mods' test all call this.

use std::path::{Path, PathBuf};

use semver::Version;
use serde::Serialize;

use crate::contract::{BASE_ACTIONS, BASE_DOCS, provided_variant};
use crate::manifest::{Manifest, Provide, parse};
use crate::points;

#[derive(Debug, Clone, Copy, PartialEq, Eq, PartialOrd, Ord, Serialize)]
#[serde(rename_all = "lowercase")]
pub enum Level {
    /// The rule is not met: the check fails.
    Error,
    /// Reported; does not fail the check yet (the roll-out's "reports" step).
    Warn,
}

/// Every rule the check holds a mod to, in the order a list shows them (`mods.check.<rule>` names each). A rule with no
/// finding is met. The Mod Editor's list and the report's `rules` are this (rule 3); a test holds the source to it.
pub const RULES: &[&str] = &[
    "manifest",
    "use_undeclared",
    "use_unseen",
    "use_base",
    "variant",
    "icon",
    "description",
    "actions_declared",
    "setting_label",
    "no_process",
    "kit_only",
    "colour_literal",
    "font_literal",
    "copy_literal",
    "host_exec",
];

#[derive(Debug, Clone, PartialEq, Serialize)]
pub struct Finding {
    /// The rule's id; `mods.check.<rule>` is its i18n key.
    pub rule: &'static str,
    pub level: Level,
    /// `mod.toml`, `mod.toml: provides[2]`, `qml/Panel.qml:41`.
    pub at: String,
    pub detail: String,
}

#[derive(Debug, Clone, PartialEq, Serialize)]
pub struct Report {
    pub id: String,
    pub findings: Vec<Finding>,
}

impl Report {
    pub fn passed(&self) -> bool {
        !self.findings.iter().any(|f| f.level == Level::Error)
    }

    pub fn count(&self, level: Level) -> usize {
        self.findings.iter().filter(|f| f.level == level).count()
    }

    /// One line per finding, errors first: what `kurashi mod check` prints.
    pub fn text(&self) -> String {
        let mut f = self.findings.clone();
        f.sort_by(|a, b| (a.level, &a.at).cmp(&(b.level, &b.at)));
        let mut out = format!(
            "{}: {} ({} not met, {} noted)\n",
            self.id,
            if self.passed() { "passes" } else { "FAILS" },
            self.count(Level::Error),
            self.count(Level::Warn)
        );
        for x in f {
            let mark = if x.level == Level::Error { "✗" } else { "·" };
            out.push_str(&format!("  {mark} {:<18} {}  {}\n", x.rule, x.at, x.detail));
        }
        out
    }
}

/// What a mod's files read and call (the static part of `uses`): QML and JS under the mod's folder.
#[derive(Debug, Default, Clone, PartialEq)]
pub struct Reach {
    /// (document, file:line)
    pub docs: Vec<(String, String)>,
    /// (action, file:line)
    pub actions: Vec<(String, String)>,
    /// (intent, file:line)
    pub intents: Vec<(String, String)>,
}

fn name_char(c: char) -> bool {
    c.is_ascii_lowercase() || c.is_ascii_digit() || "_-.".contains(c)
}

/// The string literals that directly follow `needle` on `line` (`doc: "svc.media"` → `svc.media`).
fn literals_after<'a>(line: &'a str, needle: &str) -> Vec<&'a str> {
    let mut out = Vec::new();
    let mut rest = line;
    while let Some(i) = rest.find(needle) {
        let after = rest[i + needle.len()..].trim_start();
        if let Some(body) = after.strip_prefix('"')
            && let Some(end) = body.find('"')
        {
            out.push(&body[..end]);
        }
        rest = &rest[i + needle.len()..];
    }
    out
}

fn is_doc_name(s: &str) -> bool {
    !s.is_empty() && s.chars().all(name_char) && (s.contains('.') || BASE_DOCS.contains(&s))
}

fn is_action_name(s: &str) -> bool {
    s.contains('.') && !s.starts_with('.') && !s.ends_with('.') && s.chars().all(name_char)
}

fn files(dir: &Path, out: &mut Vec<PathBuf>) {
    let Ok(rd) = std::fs::read_dir(dir) else {
        return;
    };
    let mut entries: Vec<PathBuf> = rd.flatten().map(|e| e.path()).collect();
    entries.sort();
    for p in entries {
        let name = p.file_name().and_then(|n| n.to_str()).unwrap_or("");
        // A link is the shell's own file (a host's `core` → frontend/core); tests and shots are not the mod.
        if p.is_symlink() || matches!(name, "test" | "tests" | "shots" | "target") {
            continue;
        }
        if p.is_dir() {
            files(&p, out);
        } else if name.ends_with(".qml") || name.ends_with(".js") {
            out.push(p);
        }
    }
}

struct Source {
    rel: String,
    lines: Vec<String>,
}

fn sources(dir: &Path) -> Vec<Source> {
    let mut paths = Vec::new();
    files(dir, &mut paths);
    paths
        .into_iter()
        .filter_map(|p| {
            let text = std::fs::read_to_string(&p).ok()?;
            Some(Source {
                rel: p.strip_prefix(dir).unwrap_or(&p).display().to_string(),
                lines: text.lines().map(str::to_owned).collect(),
            })
        })
        .collect()
}

fn code(line: &str) -> &str {
    // A `//` inside a string (a URL) is rare in what these rules look at; a comment line is common.
    let t = line.trim_start();
    if t.starts_with("//") || t.starts_with('*') || t.starts_with("/*") {
        ""
    } else {
        line
    }
}

/// What a bundled mod's crate follows and calls (W91, K154 step 5): the literals of `follow("…")` and `calls("…")` in
/// `crates/kurashi-mod-<id>/src`, two folders up from the mod's own (`mods/<id>`). A mod outside the tree has no crate
/// here, and nothing is read.
fn crate_reach(dir: &Path, id: &str) -> Reach {
    let mut r = Reach::default();
    let Some(src) = dir
        .parent()
        .and_then(Path::parent)
        .map(|root| {
            root.join("crates")
                .join(format!("kurashi-mod-{id}"))
                .join("src")
        })
        .filter(|p| p.is_dir())
    else {
        return r;
    };
    let mut stack = vec![src.clone()];
    while let Some(d) = stack.pop() {
        let Ok(rd) = std::fs::read_dir(&d) else {
            continue;
        };
        for p in rd.flatten().map(|e| e.path()) {
            if p.is_dir() {
                stack.push(p);
                continue;
            }
            if p.extension().is_none_or(|x| x != "rs") {
                continue;
            }
            let Ok(text) = std::fs::read_to_string(&p) else {
                continue;
            };
            let rel = p.strip_prefix(&src).unwrap_or(&p).display().to_string();
            for (n, line) in text.lines().enumerate() {
                let line = code(line);
                let at = format!("{rel}:{}", n + 1);
                for doc in literals_after(line, ".follow(") {
                    r.docs.push((doc.to_string(), at.clone()));
                }
                for action in literals_after(line, ".calls(") {
                    r.actions.push((action.to_string(), at.clone()));
                }
            }
        }
    }
    r
}

fn reach_of(src: &[Source]) -> Reach {
    let mut r = Reach::default();
    for s in src {
        for (n, line) in s.lines.iter().enumerate() {
            let line = code(line);
            let at = format!("{}:{}", s.rel, n + 1);
            for needle in ["doc:", "docs["] {
                for lit in literals_after(line, needle) {
                    if is_doc_name(lit) {
                        r.docs.push((lit.to_owned(), at.clone()));
                    }
                }
            }
            for needle in ["act(", "action:", "run("] {
                for lit in literals_after(line, needle) {
                    if is_action_name(lit) {
                        r.actions.push((lit.to_owned(), at.clone()));
                    }
                }
            }
            for lit in literals_after(line, "intent(") {
                if is_action_name(lit) {
                    r.intents.push((lit.to_owned(), at.clone()));
                }
            }
        }
    }
    r
}

fn hex_colour(lit: &str) -> bool {
    lit.strip_prefix('#')
        .is_some_and(|h| matches!(h.len(), 6 | 8) && h.chars().all(|c| c.is_ascii_hexdigit()))
}

fn lints(src: &[Source], out: &mut Vec<Finding>) {
    let mut add = |rule: &'static str, level: Level, at: String, detail: &str| {
        out.push(Finding {
            rule,
            level,
            at,
            detail: detail.to_owned(),
        })
    };
    for s in src {
        if !s.rel.ends_with(".qml") {
            continue;
        }
        // A host process's QML is its own program (K38): it draws its own controls and may run what it is.
        let host = s.rel.starts_with("host/");
        for (n, raw) in s.lines.iter().enumerate() {
            let line = code(raw);
            let t = line.trim();
            let at = format!("{}:{}", s.rel, n + 1);
            if !host && t.starts_with("import qs.components") {
                add(
                    "kit_only",
                    Level::Warn,
                    at.clone(),
                    "imports the shell's own components: `qs.kit` is the supported set",
                );
            }
            if !host && (t.starts_with("Process {") || t.contains("execDetached(")) {
                add(
                    "no_process",
                    Level::Error,
                    at.clone(),
                    "a mod's views start no process (rule 1): an action or a host does",
                );
            }
            let mut rest = line;
            while let Some(i) = rest.find('"') {
                let body = &rest[i + 1..];
                let Some(end) = body.find('"') else { break };
                if hex_colour(&body[..end]) {
                    add("colour_literal", Level::Warn, at.clone(), &body[..end]);
                }
                rest = &body[end + 1..];
            }
            if let Some(i) = line.find("font.pixelSize:") {
                let v = line[i + "font.pixelSize:".len()..].trim_start();
                let n: String = v.chars().take_while(char::is_ascii_digit).collect();
                if !n.is_empty() {
                    add("font_literal", Level::Warn, at.clone(), &n);
                }
            }
            for needle in ["text:", "placeholderText:", "title:"] {
                for lit in literals_after(line, needle) {
                    let i = line.find(needle).unwrap_or(0);
                    // `font.text:` and the like are other properties; a word before the needle is not.
                    let own = line[..i]
                        .chars()
                        .next_back()
                        .is_none_or(|c| !(c.is_alphanumeric() || c == '.'));
                    let wordy = lit.chars().filter(|c| c.is_alphabetic()).count() >= 3
                        && lit.chars().next().is_some_and(char::is_alphabetic);
                    if own && wordy {
                        add("copy_literal", Level::Warn, at.clone(), lit);
                    }
                }
            }
        }
    }
}

/// Checks the mod in `dir` (its folder's name is its id). `daemon` is the version the manifest's `kurashi` range is
/// read against.
pub fn check_dir(dir: &Path, daemon: &Version) -> Report {
    let id = dir
        .file_name()
        .and_then(|n| n.to_str())
        .unwrap_or("")
        .to_owned();
    let mut findings = Vec::new();
    let text = match std::fs::read_to_string(dir.join("mod.toml")) {
        Ok(t) => t,
        Err(e) => {
            findings.push(Finding {
                rule: "manifest",
                level: Level::Error,
                at: "mod.toml".into(),
                detail: e.to_string(),
            });
            return Report { id, findings };
        }
    };
    let m = match parse(&id, &text, daemon) {
        Ok(m) => m,
        Err(errs) => {
            for e in errs {
                findings.push(Finding {
                    rule: "manifest",
                    level: Level::Error,
                    at: format!("mod.toml: {}", e.path),
                    detail: format!("{} {}", e.code, e.detail),
                });
            }
            return Report { id, findings };
        }
    };
    // K155 (W93): a host program is a file the mod brings (`bin/<exec>`, executable), or a program on PATH that its
    // capabilities name.
    for (i, h) in m.hosts.iter().enumerate() {
        use std::os::unix::fs::PermissionsExt;
        let own = dir.join("bin").join(&h.exec);
        let granted = m
            .capabilities
            .iter()
            .any(|c| c == &format!("exec:{}", h.exec));
        let at = format!("mod.toml: host[{i}].exec");
        match std::fs::metadata(&own) {
            Ok(meta) if meta.is_file() && meta.permissions().mode() & 0o111 == 0 => {
                findings.push(Finding {
                    rule: "host_exec",
                    level: Level::Error,
                    at,
                    detail: format!("`bin/{}` is not executable", h.exec),
                })
            }
            Ok(meta) if meta.is_file() => {}
            _ if granted => {}
            _ => findings.push(Finding {
                rule: "host_exec",
                level: Level::Error,
                at,
                detail: format!(
                    "`{0}` is neither a file in `bin/` nor named in capabilities (`exec:{0}`)",
                    h.exec
                ),
            }),
        }
    }
    let src = sources(dir);
    check_manifest(&m, &mut findings);
    check_reach(&m, &reach_of(&src), &crate_reach(dir, &m.id), &mut findings);
    lints(&src, &mut findings);
    Report { id, findings }
}

fn check_manifest(m: &Manifest, out: &mut Vec<Finding>) {
    let mut add = |rule: &'static str, level: Level, at: &str, detail: String| {
        out.push(Finding {
            rule,
            level,
            at: format!("mod.toml{}{at}", if at.is_empty() { "" } else { ": " }),
            detail,
        })
    };
    if m.icon.is_none() {
        add("icon", Level::Error, "icon", "no icon: its Settings page, its Mods row and its rows in the launcher and menus show one".into());
    }
    if m.description.is_none() {
        add(
            "description",
            Level::Error,
            "description",
            "no description (an i18n key): shown under the name on the Mods page".into(),
        );
    }
    for s in &m.settings {
        if s.label.is_none() {
            add(
                "setting_label",
                Level::Error,
                &format!("setting {}", s.key),
                "no label (an i18n key)".into(),
            );
        }
    }
    let has_action_glob = m.provides.iter().any(|p| matches!(p, Provide::Action(_)));
    if has_action_glob && m.contract.actions.is_empty() {
        add("actions_declared", Level::Error, "action", "provides actions and declares none: `[[action]]` is what `kurashi act`, the launcher and key binds read".into());
    }
    // K72: a placeable module answers for every variant the shell's places ask for.
    if m.provides.iter().any(|p| matches!(p, Provide::Widget(_))) {
        for p in points::expected() {
            if !provided_variant(p.id, &m.provides, &m.contract)
                && !m.contract.skips.contains_key(p.id)
            {
                add(
                    "variant",
                    Level::Error,
                    &format!("skips.{}", p.id),
                    format!("neither ships `{}` nor says why not in [skips]", p.fill),
                );
            }
        }
    }
}

fn check_reach(m: &Manifest, r: &Reach, in_crate: &Reach, out: &mut Vec<Finding>) {
    let mut seen: Vec<String> = Vec::new();
    for (doc, at) in &r.docs {
        if !m.contract.may_read(&m.id, doc) && !seen.contains(doc) {
            seen.push(doc.clone());
            out.push(Finding {
                rule: "use_undeclared",
                level: Level::Error,
                at: at.clone(),
                detail: format!("reads `{doc}`: add `doc:{doc}` to uses"),
            });
        }
    }
    for (action, at) in &r.actions {
        if !m.contract.may_call(&m.id, action) && !seen.contains(action) {
            seen.push(action.clone());
            out.push(Finding {
                rule: "use_undeclared",
                level: Level::Error,
                at: at.clone(),
                detail: format!("calls `{action}`: add `action:{action}` to uses"),
            });
        }
    }
    for (key, at) in &r.intents {
        if !m.contract.may_send(&m.id, key) && !seen.contains(key) {
            seen.push(key.clone());
            out.push(Finding {
                rule: "use_undeclared",
                level: Level::Error,
                at: at.clone(),
                detail: format!("writes `{key}`: add `intent:{key}` to uses"),
            });
        }
    }
    // The other way round: a use neither a view nor the mod's crate names is noted (W91: the crate's `follow("…")`
    // and `calls("…")` count).
    for u in &m.contract.uses {
        let named = match u.kind {
            crate::contract::UseKind::Doc => {
                r.docs.iter().chain(&in_crate.docs).any(|(d, _)| d == &u.id)
            }
            crate::contract::UseKind::Action => r
                .actions
                .iter()
                .chain(&in_crate.actions)
                .any(|(a, _)| a == &u.id),
            crate::contract::UseKind::Intent => r.intents.iter().any(|(a, _)| a == &u.id),
        };
        let base = BASE_DOCS.contains(&u.id.as_str()) || BASE_ACTIONS.contains(&u.id.as_str());
        if base {
            out.push(Finding {
                rule: "use_base",
                level: Level::Warn,
                at: "mod.toml: uses".into(),
                detail: format!("`{}` is in the base set: no entry needed", u.id),
            });
        } else if !named && !u.id.ends_with(".*") {
            out.push(Finding {
                rule: "use_unseen",
                level: Level::Warn,
                at: "mod.toml: uses".into(),
                detail: format!(
                    "`{}` is declared and neither a view nor the crate names it",
                    u.id
                ),
            });
        }
    }
}

/// What the views of the mod in `dir` read and call: for writing a first `uses` list.
pub fn reach(dir: &Path) -> Reach {
    reach_of(&sources(dir))
}

#[cfg(test)]
mod tests {
    use super::*;

    /// W94: the rule list is the rules the code reports, and each has its name in both catalogues.
    #[test]
    fn the_rule_list_is_what_the_check_reports_and_every_rule_has_a_name() {
        let src = include_str!("check.rs");
        let mut found = std::collections::BTreeSet::new();
        for marker in ["rule: \"", "add(\""] {
            for part in src.split(marker).skip(1) {
                let id: String = part
                    .chars()
                    .take_while(|c| c.is_ascii_lowercase() || *c == '_')
                    .collect();
                if part[id.len()..].starts_with('"') && !id.is_empty() {
                    found.insert(id);
                }
            }
        }
        // `add(` on a line of its own, the rule on the next.
        for part in src.split("add(\n").skip(1) {
            let line = part.trim_start();
            if let Some(rest) = line.strip_prefix('"') {
                found.insert(rest.chars().take_while(|c| *c != '"').collect());
            }
        }
        let listed: std::collections::BTreeSet<String> =
            RULES.iter().map(|r| (*r).to_string()).collect();
        assert_eq!(
            found, listed,
            "RULES and the rules the check reports differ"
        );
        for lang in ["en", "ja"] {
            let dir =
                std::path::Path::new(env!("CARGO_MANIFEST_DIR")).join(format!("../../i18n/{lang}"));
            let catalogue = ["mod-editor.toml", "mods.toml"]
                .iter()
                .map(|f| std::fs::read_to_string(dir.join(f)).unwrap())
                .collect::<String>();
            for r in RULES {
                assert!(
                    catalogue.contains(&format!("\"mods.check.{r}\"")),
                    "{lang}: mods.check.{r} has no name"
                );
            }
        }
    }

    fn write(dir: &Path, rel: &str, text: &str) {
        let p = dir.join(rel);
        std::fs::create_dir_all(p.parent().unwrap()).unwrap();
        std::fs::write(p, text).unwrap();
    }

    const BASE: &str = r#"id = "demo"
name = "Demo"
description = "mods.demo.description"
version = "0.1.0"
tier = "native"
kurashi = ">=0.0.1"
"#;

    fn rules(r: &Report, level: Level) -> Vec<&'static str> {
        r.findings
            .iter()
            .filter(|f| f.level == level)
            .map(|f| f.rule)
            .collect()
    }

    #[test]
    fn literals_are_read_after_their_needles() {
        assert_eq!(
            literals_after(r#"Watch { doc: "svc.media"; active: true }"#, "doc:"),
            ["svc.media"]
        );
        assert_eq!(
            literals_after(
                r#"Store.act("island.expand", { face: "x" }); Store.act("ui.close")"#,
                "act("
            ),
            ["island.expand", "ui.close"]
        );
        assert!(literals_after(r#"Store.act(name)"#, "act(").is_empty());
    }

    #[test]
    fn a_mod_is_held_to_its_uses_its_variants_and_the_native_rules() {
        let v = Version::new(0, 3, 0);
        let tmp = tempfile::tempdir().unwrap();
        let dir = tmp.path().join("demo");
        write(
            &dir,
            "mod.toml",
            &format!("{BASE}provides = [\"widget:demo\", \"action:demo.*\"]\n"),
        );
        write(
            &dir,
            "qml/Widget.qml",
            r##"import qs.components
Item {
    Watch { doc: "svc.media" }
    Watch { doc: "mod.demo" }
    // Watch { doc: "svc.hidden" }
    Text { text: "Hello there"; color: "#ff0000"; font.pixelSize: 12 }
    function go() { Store.act("island.expand"); Store.act("demo.go"); Store.act("ui.close") }
}
"##,
        );
        let r = check_dir(&dir, &v);
        assert!(!r.passed());
        let errors = rules(&r, Level::Error);
        assert!(errors.contains(&"icon"), "{errors:?}");
        assert!(errors.contains(&"actions_declared"));
        // svc.media and island.expand; the mod's own, the base set and the comment are not findings.
        assert_eq!(errors.iter().filter(|e| **e == "use_undeclared").count(), 2);
        // Eight expected points, the glance is provided.
        assert_eq!(errors.iter().filter(|e| **e == "variant").count(), 7);
        let warns = rules(&r, Level::Warn);
        for w in ["kit_only", "colour_literal", "font_literal", "copy_literal"] {
            assert!(warns.contains(&w), "{w}: {warns:?}");
        }

        // The same mod, declared: it passes.
        write(
            &dir,
            "mod.toml",
            &format!(
                r#"{BASE}icon = "bolt"
provides = ["widget:demo", "action:demo.*"]
uses = ["doc:svc.media", "action:island.expand?"]

[[action]]
id = "demo.go"
label = "mod-demo.action.go"
command = "demo"
no_args = true

[[menu]]
at = "module"
action = "demo.go"

[skips]
peek = "nothing more to say than the glance"
panel = "no state to show"
desk = "no state to show"
island-face = "no live activity"
quick-tile = "nothing to switch"
"#
            ),
        );
        let r = check_dir(&dir, &v);
        assert!(r.passed(), "{}", r.text());
    }

    #[test]
    fn a_broken_manifest_is_the_only_finding() {
        let tmp = tempfile::tempdir().unwrap();
        let dir = tmp.path().join("demo");
        write(&dir, "mod.toml", "id = \"other\"\n");
        let r = check_dir(&dir, &Version::new(0, 3, 0));
        assert!(!r.passed());
        assert!(r.findings.iter().all(|f| f.rule == "manifest"));
    }
}
