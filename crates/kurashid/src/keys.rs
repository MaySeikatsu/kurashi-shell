//! Keyboard shortcuts as config (K64, I72): `keys.*` names one combo per shell action. With `keys.write` on, kurashid
//! writes the compositor's binds file from them (niri: `$XDG_CONFIG_HOME/niri/kurashi-binds.kdl`) — only when the
//! content changes — and `svc.keys` reports the file, the include line the compositor's config needs and whether it is
//! there, and each shortcut's state: a combo the compositor would not take, or one that two actions share, is left out
//! of the file and says why (Shōjiki). K49's pattern: our own file, never the user's config. A file we did not write (a
//! Home-Manager store symlink, a copy of `docs/niri-binds.kdl`) is never overwritten: the document says whose it is.
//! niri reloads included files by itself; a niri on PATH checks the file before it is written.

use std::collections::BTreeMap;
use std::io::Read;
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};
use std::sync::{Arc, Mutex};
use std::time::{Duration, Instant};

use serde_json::{Value, json};

use kurashi_compositor::any::Kind;

use crate::config::ConfigStore;
use crate::hub::{Hub, Provider};

pub const DOC: &str = "svc.keys";
/// The binds file, under `$XDG_CONFIG_HOME`.
pub const NIRI_FILE: &str = "niri/kurashi-binds.kdl";
/// niri's own config, which includes it.
pub const NIRI_CONFIG: &str = "niri/config.kdl";
pub const NIRI_INCLUDE: &str = "include \"kurashi-binds.kdl\"";
/// The first line of every file we write: a file at that path without it is not ours.
const HEADER: &str = "// Written by kurashid from the keys.* settings (Settings → Keys).";

/// One shortcut: the config field, the action it runs, and how niri treats the key (as `docs/niri-binds.kdl`).
pub struct Bind {
    pub field: &'static str,
    pub action: &'static str,
    /// The action's JSON arguments.
    pub args: Option<&'static str>,
    /// Repeats while held (volume, brightness); every other bind would flip on each repeat.
    pub repeat: bool,
    /// Works while the session is locked, as niri's own media keys do.
    pub locked: bool,
    /// Stays reachable while an app inhibits shortcuts (a VM, a remote desktop): the session menu and the lock.
    pub always: bool,
}

const fn bind(field: &'static str, action: &'static str) -> Bind {
    Bind {
        field,
        action,
        args: None,
        repeat: false,
        locked: false,
        always: false,
    }
}

/// The `keys.*` fields in the schema's order; the first of two actions on one combo is the one written.
pub const BINDS: [Bind; 14] = [
    bind("launcher", "launcher.toggle"),
    bind("notifications", "notifications.center"),
    Bind {
        args: Some(r#"{"side":"right"}"#),
        ..bind("sidebar_right", "sidebar.toggle")
    },
    Bind {
        args: Some(r#"{"side":"left"}"#),
        ..bind("sidebar_left", "sidebar.toggle")
    },
    bind("quick", "quick.toggle"),
    Bind {
        always: true,
        ..bind("session_menu", "session.menu")
    },
    Bind {
        always: true,
        ..bind("lock", "session.lock")
    },
    bind("settings", "settings.open"),
    bind("webdock", "webdock.toggle"),
    Bind {
        repeat: true,
        locked: true,
        ..bind("volume_up", "audio.volume.up")
    },
    Bind {
        repeat: true,
        locked: true,
        ..bind("volume_down", "audio.volume.down")
    },
    Bind {
        locked: true,
        ..bind("mute", "audio.mute.toggle")
    },
    Bind {
        repeat: true,
        locked: true,
        ..bind("brightness_up", "brightness.up")
    },
    Bind {
        repeat: true,
        locked: true,
        ..bind("brightness_down", "brightness.down")
    },
];

// --- combos --------------------------------------------------------------------------------------

/// Modifiers niri knows, as spelled in the file, in the order we write them. `Mod` is Super on a TTY and Alt in a
/// nested niri; a conflict check treats it as Super (the real session).
const MODIFIERS: [(&str, &[&str]); 7] = [
    ("Mod", &["mod"]),
    ("Super", &["super", "win"]),
    ("Ctrl", &["ctrl", "control"]),
    ("Alt", &["alt"]),
    ("Shift", &["shift"]),
    ("ISO_Level3_Shift", &["iso_level3_shift", "mod5"]),
    ("ISO_Level5_Shift", &["iso_level5_shift"]),
];

/// Key names niri takes (xkb keysyms, matched without case), as we write them. XF86 and keypad keys go by their
/// prefix; a niri on PATH has the last word on those.
const NAMED: &[&str] = &[
    "Home",
    "End",
    "Page_Up",
    "Page_Down",
    "Prior",
    "Next",
    "Insert",
    "Print",
    "Pause",
    "Scroll_Lock",
    "Menu",
    "Caps_Lock",
    // niri's pointer triggers.
    "WheelScrollDown",
    "WheelScrollUp",
    "WheelScrollLeft",
    "WheelScrollRight",
    "TouchpadScrollDown",
    "TouchpadScrollUp",
    "TouchpadScrollLeft",
    "TouchpadScrollRight",
    "MouseLeft",
    "MouseRight",
    "MouseMiddle",
    "MouseBack",
    "MouseForward",
];

/// Named keys that type or edit text: bound without a modifier, they could not be typed any more. The symbols after
/// `Grave` are the unshifted symbol of a key on some layouts (AZERTY's number row).
const TYPING: &[&str] = &[
    "Space",
    "Return",
    "Tab",
    "BackSpace",
    "Delete",
    "Escape",
    "Left",
    "Right",
    "Up",
    "Down",
    "Comma",
    "Period",
    "Slash",
    "Semicolon",
    "Apostrophe",
    "BracketLeft",
    "BracketRight",
    "Backslash",
    "Minus",
    "Equal",
    "Grave",
    "Plus",
    "Exclam",
    "At",
    "NumberSign",
    "Dollar",
    "Percent",
    "AsciiCircum",
    "Ampersand",
    "Asterisk",
    "ParenLeft",
    "ParenRight",
    "Underscore",
    "BraceLeft",
    "BraceRight",
    "Colon",
    "QuoteDbl",
    "Less",
    "Greater",
    "Question",
    "Bar",
    "AsciiTilde",
    "Section",
    "Eacute",
    "Egrave",
    "Agrave",
    "Ccedilla",
    "Ugrave",
];

fn types_text(key: &str) -> bool {
    key.len() == 1 || TYPING.contains(&key)
}

/// A parsed combo: modifiers (indices into [`MODIFIERS`], sorted) and the key, both as written.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Combo {
    mods: Vec<usize>,
    key: String,
}

impl Combo {
    /// Parses `Mod+Shift+E`, `XF86AudioMute`, `ctrl+alt+k`. An error is a `keys.invalid.*` key.
    pub fn parse(text: &str) -> Result<Combo, &'static str> {
        let text = text.trim();
        if text.chars().any(char::is_whitespace) {
            return Err("keys.invalid.syntax");
        }
        let parts: Vec<&str> = text.split('+').collect();
        if parts.iter().any(|p| p.is_empty()) {
            return Err("keys.invalid.syntax");
        }
        let (key, mods) = parts.split_last().ok_or("keys.invalid.syntax")?;
        let mut idx = Vec::new();
        for m in mods {
            let i = modifier(m).ok_or("keys.invalid.modifier")?;
            if !idx.contains(&i) {
                idx.push(i);
            }
        }
        if modifier(key).is_some() {
            return Err("keys.invalid.only_modifiers");
        }
        let key = key_name(key).ok_or("keys.invalid.key")?;
        idx.sort_unstable();
        if idx.is_empty() && types_text(&key) {
            return Err("keys.invalid.needs_modifier");
        }
        Ok(Combo { mods: idx, key })
    }

    /// As written into the file: `Mod+Shift+E`.
    pub fn text(&self) -> String {
        let mut s: Vec<&str> = self.mods.iter().map(|&i| MODIFIERS[i].0).collect();
        s.push(&self.key);
        s.join("+")
    }

    /// The form two combos compare by: lower case, Super as Mod. Settings' recorder writes this form (lowered) too.
    pub fn canon(&self) -> String {
        let mut mods: Vec<usize> = self
            .mods
            .iter()
            .map(|&i| if i == 1 { 0 } else { i })
            .collect();
        mods.sort_unstable();
        mods.dedup();
        let mut s: Vec<&str> = mods.iter().map(|&i| MODIFIERS[i].0).collect();
        s.push(&self.key);
        s.join("+").to_lowercase()
    }

    pub fn key(&self) -> &str {
        &self.key
    }
}

fn modifier(name: &str) -> Option<usize> {
    let l = name.to_lowercase();
    MODIFIERS
        .iter()
        .position(|(_, aliases)| aliases.contains(&l.as_str()))
}

/// The key as written, or `None` for a name niri does not know.
fn key_name(name: &str) -> Option<String> {
    let l = name.to_lowercase();
    if name.len() == 1 && name.chars().all(|c| c.is_ascii_alphanumeric()) {
        return Some(name.to_uppercase());
    }
    if let Some(n) = l.strip_prefix('f').and_then(|n| n.parse::<u8>().ok())
        && (1..=35).contains(&n)
        && !l[1..].starts_with('0')
    {
        return Some(format!("F{n}"));
    }
    if let Some(k) = NAMED.iter().chain(TYPING).find(|k| k.to_lowercase() == l) {
        return Some((*k).to_owned());
    }
    let word = |rest: &str| {
        !rest.is_empty() && rest.chars().all(|c| c.is_ascii_alphanumeric() || c == '_')
    };
    if let Some(rest) = name.get(4..).filter(|_| l.starts_with("xf86"))
        && word(rest)
    {
        return Some(format!("XF86{rest}"));
    }
    if let Some(rest) = name.get(3..).filter(|_| l.starts_with("kp_"))
        && word(rest)
    {
        return Some(format!("KP_{rest}"));
    }
    None
}

// --- evaluation ----------------------------------------------------------------------------------

/// One shortcut as `svc.keys` reports it.
#[derive(Debug, Clone, PartialEq)]
pub struct Entry {
    pub field: &'static str,
    pub combo: String,
    pub parsed: Option<Combo>,
    /// `ok`, `none` (no combo), `invalid`, `conflict` (an earlier action has it: not written).
    pub state: &'static str,
    pub reason: Option<String>,
    /// The other `keys.*` on the same combo.
    pub with: Vec<String>,
    /// The user's niri config binds the same combo: `replaces` (ours comes later and wins) or `overridden` (theirs
    /// comes later: ours is not in effect).
    pub config: Option<&'static str>,
}

/// Judges every combo: `values` are `(field, combo)` in [`BINDS`] order.
pub fn evaluate(values: &[(&'static str, String)]) -> Vec<Entry> {
    let mut out: Vec<Entry> = values
        .iter()
        .map(|(field, combo)| {
            let (parsed, state, reason) = if combo.trim().is_empty() {
                (None, "none", None)
            } else {
                match Combo::parse(combo) {
                    Ok(c) => (Some(c), "ok", None),
                    Err(e) => (None, "invalid", Some(e.to_owned())),
                }
            };
            Entry {
                field,
                combo: combo.clone(),
                parsed,
                state,
                reason,
                with: Vec::new(),
                config: None,
            }
        })
        .collect();
    // Rows by combo, in table order: the first of a group is written, the rest are not; each names the others.
    let mut groups: BTreeMap<String, Vec<usize>> = BTreeMap::new();
    for (i, e) in out.iter().enumerate() {
        if let Some(c) = &e.parsed {
            groups.entry(c.canon()).or_default().push(i);
        }
    }
    for rows in groups.values().filter(|g| g.len() > 1) {
        let names: Vec<String> = rows
            .iter()
            .map(|&i| format!("keys.{}", out[i].field))
            .collect();
        for (n, &i) in rows.iter().enumerate() {
            out[i].with = names
                .iter()
                .enumerate()
                .filter(|(m, _)| *m != n)
                .map(|(_, s)| s.clone())
                .collect();
            if n > 0 {
                out[i].state = "conflict";
                out[i].reason = Some("keys.conflict.taken".into());
            }
        }
    }
    out
}

/// The binds the user's own niri config holds (canon → line), and the line of our include. A light reading: lines of
/// a top-level `binds {}` block, comments skipped. niri lets a later bind of the same key replace an earlier one.
fn scan_config(text: &str) -> (BTreeMap<String, usize>, Option<usize>) {
    let mut binds = BTreeMap::new();
    let mut include = None;
    let mut depth = 0usize;
    let mut in_binds = false;
    let mut in_comment = false;
    for (n, raw) in text.lines().enumerate() {
        let mut line = raw.trim();
        if in_comment {
            match line.find("*/") {
                Some(i) => {
                    in_comment = false;
                    line = line[i + 2..].trim();
                }
                None => continue,
            }
        }
        if let Some(i) = line.find("//") {
            line = line[..i].trim();
        }
        if line.starts_with("/*") {
            in_comment = !line.contains("*/");
            continue;
        }
        if line.is_empty() || line.starts_with("/-") {
            continue;
        }
        if depth == 0 && is_our_include(line) {
            include = Some(n);
        }
        if depth == 0 && line.starts_with("binds") && line.contains('{') {
            in_binds = true;
        } else if in_binds
            && depth == 1
            && let Some(first) = line.split(|c: char| c.is_whitespace() || c == '{').next()
            && let Ok(c) = Combo::parse(first)
        {
            binds.insert(c.canon(), n);
        }
        let opens = line.matches('{').count();
        let closes = line.matches('}').count();
        depth = (depth + opens).saturating_sub(closes);
        if depth == 0 {
            in_binds = false;
        }
    }
    (binds, include)
}

fn is_our_include(line: &str) -> bool {
    line.starts_with("include") && line.contains("kurashi-binds.kdl\"")
}

// --- niri ----------------------------------------------------------------------------------------

fn kdl_string(s: &str) -> String {
    format!("\"{}\"", s.replace('\\', "\\\\").replace('"', "\\\""))
}

/// The binds file for niri (as `docs/niri-binds.kdl`): the entries in state `ok`, each spawning `kurashi act`.
pub fn render_niri(entries: &[Entry], kurashi: &Path) -> String {
    let mut s = String::new();
    s.push_str(HEADER);
    s.push_str("\n// Change them there, not here: this file is written again when they change.\n");
    s.push_str("// niri reads it once ~/.config/niri/config.kdl includes it, after your own binds {} block:\n");
    s.push_str(&format!("//     {NIRI_INCLUDE}\n\nbinds {{\n"));
    let program = kdl_string(&kurashi.to_string_lossy());
    for (e, b) in entries.iter().zip(BINDS.iter()) {
        let Some(c) = e.parsed.as_ref().filter(|_| e.state == "ok") else {
            continue;
        };
        let mut lhs = vec![c.text()];
        if b.always {
            lhs.push("allow-inhibiting=false".into());
        }
        if b.locked {
            lhs.push("allow-when-locked=true".into());
        }
        if !b.repeat {
            lhs.push("repeat=false".into());
        }
        let mut argv = vec![program.clone(), kdl_string("act"), kdl_string(b.action)];
        if let Some(a) = b.args {
            argv.push(kdl_string(a));
        }
        s.push_str(&format!(
            "    {} {{ spawn {}; }}\n",
            lhs.join(" "),
            argv.join(" ")
        ));
    }
    s.push_str("}\n");
    s
}

/// The stub a file of ours becomes while `keys.write` is off: an include that names it keeps working (niri refuses a
/// config whose include is missing), and binds nothing.
fn stub_niri() -> String {
    format!(
        "{HEADER}\n// keys.write is off: your compositor's own config keeps the keys. Kept so an include of it still works.\nbinds {{\n}}\n"
    )
}

/// `niri validate` of a file's text: `None` without a niri on PATH (or one that does not answer in time), else its
/// verdict with the message.
pub fn niri_validate(program: &Path, text: &str) -> Option<Result<(), String>> {
    // One name per check: two runs at once (tests in parallel) must not read each other's file.
    static SEQ: std::sync::atomic::AtomicU64 = std::sync::atomic::AtomicU64::new(0);
    let n = SEQ.fetch_add(1, std::sync::atomic::Ordering::Relaxed);
    let tmp = std::env::temp_dir().join(format!("kurashid-keys-{}-{n}.kdl", std::process::id()));
    std::fs::write(&tmp, text).ok()?;
    let result = run_validate(program, &tmp);
    let _ = std::fs::remove_file(&tmp);
    result
}

fn run_validate(program: &Path, file: &Path) -> Option<Result<(), String>> {
    let mut child = Command::new(program)
        .arg("validate")
        .arg("-c")
        .arg(file)
        .env("NO_COLOR", "1")
        .stdin(Stdio::null())
        .stdout(Stdio::null())
        .stderr(Stdio::piped())
        .spawn()
        .ok()?;
    let deadline = Instant::now() + Duration::from_secs(3);
    let status = loop {
        match child.try_wait() {
            Ok(Some(s)) => break s,
            Ok(None) if Instant::now() < deadline => std::thread::sleep(Duration::from_millis(5)),
            _ => {
                let _ = child.kill();
                let _ = child.wait();
                tracing::warn!("niri validate did not answer in time");
                return None;
            }
        }
    };
    let mut err = String::new();
    if let Some(mut e) = child.stderr.take() {
        let _ = e.read_to_string(&mut err);
    }
    Some(if status.success() { Ok(()) } else { Err(err) })
}

/// The key niri named in "invalid key: X", if that is what it refused.
fn refused_key(message: &str) -> Option<String> {
    let i = message.find("invalid key: ")?;
    let rest = &message[i + "invalid key: ".len()..];
    let key: String = rest.chars().take_while(|c| !c.is_whitespace()).collect();
    (!key.is_empty()).then_some(key)
}

/// A program on PATH, as `Command` would find it.
pub fn on_path(name: &str) -> Option<PathBuf> {
    std::env::var_os("PATH").and_then(|paths| {
        std::env::split_paths(&paths)
            .map(|d| d.join(name))
            .find(|p| p.is_file())
    })
}

/// The `kurashi` binary next to this daemon (the package installs both), else the name for PATH.
pub fn kurashi_binary() -> PathBuf {
    std::env::current_exe()
        .ok()
        .and_then(|p| p.parent().map(|d| d.join("kurashi")))
        .filter(|p| p.is_file())
        .unwrap_or_else(|| PathBuf::from("kurashi"))
}

fn write_if_changed(path: &Path, text: &str) -> std::io::Result<bool> {
    if std::fs::read_to_string(path).is_ok_and(|old| old == text) {
        return Ok(false);
    }
    if let Some(dir) = path.parent() {
        std::fs::create_dir_all(dir)?;
    }
    let tmp = path.with_extension("kurashi-tmp");
    std::fs::write(&tmp, text)?;
    std::fs::rename(&tmp, path)?;
    Ok(true)
}

// --- one run -------------------------------------------------------------------------------------

/// What one run reads and writes.
pub struct Run<'a> {
    /// `$XDG_CONFIG_HOME`.
    pub home: &'a Path,
    /// `keys.write`.
    pub write: bool,
    /// `(field, combo)` in [`BINDS`] order.
    pub values: Vec<(&'static str, String)>,
    /// The session's compositor.
    pub compositor: Option<Kind>,
    /// What the binds spawn.
    pub kurashi: &'a Path,
    /// `niri` for `niri validate`, when there is one.
    pub niri: Option<&'a Path>,
}

/// Judges the combos, writes the file when it is ours to write and changed, and returns the `svc.keys` document.
pub fn apply(run: &Run) -> Value {
    let mut entries = evaluate(&run.values);
    let mut doc = json!({
        "write": run.write,
        "compositor": run.compositor.map(Kind::name),
    });
    if run.compositor != Some(Kind::Niri) {
        doc["state"] = json!(if run.write { "unsupported" } else { "off" });
        doc["binds"] = binds_json(&entries);
        return doc;
    }
    let file = run.home.join(NIRI_FILE);
    let cfg = run.home.join(NIRI_CONFIG);
    let cfg_text = std::fs::read_to_string(&cfg).unwrap_or_default();
    let (theirs, include_at) = scan_config(&cfg_text);
    doc["file"] = json!(file.to_string_lossy());
    doc["include"] = json!({
        "file": cfg.to_string_lossy(),
        "line": NIRI_INCLUDE,
        "present": include_at.is_some(),
    });
    let meta = std::fs::symlink_metadata(&file).ok();
    let link = meta.as_ref().is_some_and(|m| m.file_type().is_symlink());
    let existing = if link {
        None
    } else {
        std::fs::read_to_string(&file).ok()
    };
    let ours = existing
        .as_deref()
        .is_none_or(|t| t.starts_with(HEADER) || t.trim().is_empty());
    if link {
        // Home-Manager's file (programs.kurashi.niri.binds) is a link into the store: its keys are in effect, not ours.
        doc["state"] = json!("managed");
        if let Ok(t) = std::fs::read_link(&file) {
            doc["target"] = json!(t.to_string_lossy());
        }
    } else if !ours {
        doc["state"] = json!("foreign");
    } else if !run.write {
        doc["state"] = json!("off");
        if existing.is_some()
            && let Err(e) = write_if_changed(&file, &stub_niri())
        {
            tracing::warn!(error = %e, "keys: could not empty the binds file");
        }
    } else {
        write_niri(run, &file, &mut entries, &mut doc);
    }
    // Only a file niri reads can collide with the user's own binds.
    if include_at.is_some() && doc["state"] == "written" {
        for e in entries.iter_mut().filter(|e| e.state == "ok") {
            let canon = e.parsed.as_ref().map(Combo::canon).unwrap_or_default();
            if let (Some(&at), Some(inc)) = (theirs.get(&canon), include_at) {
                e.config = Some(if at > inc { "overridden" } else { "replaces" });
            }
        }
    }
    doc["binds"] = binds_json(&entries);
    doc
}

/// Renders, lets niri check it (a key it does not know is left out and named), and writes it when it changed.
fn write_niri(run: &Run, file: &Path, entries: &mut [Entry], doc: &mut Value) {
    let mut text = render_niri(entries, run.kurashi);
    let unchanged = std::fs::read_to_string(file).is_ok_and(|old| old == text);
    if !unchanged && let Some(niri) = run.niri {
        let mut checked = false;
        for _ in 0..=BINDS.len() {
            match niri_validate(niri, &text) {
                None => break,
                Some(Ok(())) => {
                    checked = true;
                    break;
                }
                Some(Err(msg)) => {
                    let bad = refused_key(&msg).map(|k| k.to_lowercase());
                    let hit = entries.iter_mut().filter(|e| e.state == "ok").find(|e| {
                        bad.as_deref().is_some_and(|b| {
                            e.parsed
                                .as_ref()
                                .is_some_and(|c| c.key().to_lowercase() == b)
                        })
                    });
                    match hit {
                        Some(e) => {
                            e.state = "invalid";
                            e.reason = Some("keys.invalid.niri".into());
                            text = render_niri(entries, run.kurashi);
                        }
                        None => {
                            let detail = msg
                                .lines()
                                .map(str::trim)
                                .filter(|l| !l.is_empty())
                                .collect::<Vec<_>>();
                            doc["state"] = json!("error");
                            doc["error"] = json!("keys.error.niri_refused");
                            doc["detail"] = json!(detail.join(" "));
                            return;
                        }
                    }
                }
            }
        }
        doc["checked"] = json!(checked);
    }
    match write_if_changed(file, &text) {
        Ok(changed) => {
            doc["state"] = json!("written");
            doc["changed"] = json!(changed);
        }
        Err(e) => {
            tracing::warn!(error = %e, "keys: could not write the binds file");
            doc["state"] = json!("error");
            doc["error"] = json!("keys.error.write_failed");
        }
    }
}

fn binds_json(entries: &[Entry]) -> Value {
    let list: Vec<Value> = entries
        .iter()
        .zip(BINDS.iter())
        .map(|(e, b)| {
            let mut v = json!({
                "key": format!("keys.{}", e.field),
                "action": b.action,
                "combo": e.combo,
                "state": e.state,
            });
            if let Some(a) = b.args {
                v["args"] = serde_json::from_str(a).unwrap_or(Value::Null);
            }
            if let Some(c) = &e.parsed {
                v["canon"] = json!(c.canon());
            }
            if let Some(r) = &e.reason {
                v["reason"] = json!(r);
            }
            if !e.with.is_empty() {
                v["with"] = json!(e.with);
            }
            if let Some(c) = e.config {
                v["config"] = json!(c);
            }
            v
        })
        .collect();
    Value::Array(list)
}

// --- wiring --------------------------------------------------------------------------------------

fn config_home() -> PathBuf {
    std::env::var_os("XDG_CONFIG_HOME")
        .map(PathBuf::from)
        .filter(|p| p.is_absolute())
        .or_else(|| std::env::var_os("HOME").map(|h| PathBuf::from(h).join(".config")))
        .unwrap_or_else(|| PathBuf::from("/tmp"))
}

struct Keys {
    hub: Arc<Hub>,
    store: Arc<ConfigStore>,
    compositor: Option<Kind>,
    kurashi: PathBuf,
    /// One run at a time: the last one reads the latest values.
    turn: Mutex<()>,
    /// niri's config directory watched while Settings shows the document: an include line added by hand shows at once.
    watcher: Mutex<Option<notify::RecommendedWatcher>>,
}

impl Keys {
    fn run(&self) {
        let _turn = self.turn.lock().unwrap_or_else(|e| e.into_inner());
        let text = |field: &str| {
            self.store
                .get(&format!("keys.{field}"), None)
                .and_then(|p| p.value.as_str().map(str::to_owned))
                .unwrap_or_default()
        };
        let write = self
            .store
            .get("keys.write", None)
            .is_some_and(|p| p.value == Value::Bool(true));
        let niri = on_path("niri");
        let home = config_home();
        let doc = apply(&Run {
            home: &home,
            write,
            values: BINDS.iter().map(|b| (b.field, text(b.field))).collect(),
            compositor: self.compositor,
            kurashi: &self.kurashi,
            niri: niri.as_deref(),
        });
        let _ = self.hub.set(DOC, doc, None);
    }
}

/// The provider: a run when the first viewer subscribes (a file edited by hand since shows as it is now), and niri's
/// config directory watched while one does (Ma: nothing runs while nobody looks; config changes run regardless).
struct KeysProvider(Arc<Keys>);

impl Provider for KeysProvider {
    fn start(&self, _hub: Arc<Hub>) {
        self.0.run();
        if self.0.compositor != Some(Kind::Niri) {
            return;
        }
        use notify::Watcher;
        let keys = self.0.clone();
        let dir = config_home().join("niri");
        let watcher = notify::recommended_watcher(move |ev: notify::Result<notify::Event>| {
            let ours = ev.is_ok_and(|e| {
                e.paths.iter().any(|p| {
                    p.file_name()
                        .is_some_and(|n| n == "config.kdl" || n == "kurashi-binds.kdl")
                })
            });
            if ours {
                keys.run();
            }
        });
        match watcher {
            Ok(mut w) => {
                if w.watch(&dir, notify::RecursiveMode::NonRecursive).is_ok() {
                    *self.0.watcher.lock().unwrap_or_else(|e| e.into_inner()) = Some(w);
                }
            }
            Err(e) => tracing::debug!(error = %e, "keys: no watcher for niri's config"),
        }
    }

    fn stop(&self) {
        *self.0.watcher.lock().unwrap_or_else(|e| e.into_inner()) = None;
    }
}

/// `svc.keys`, kept current after each config change.
pub fn register(hub: &Arc<Hub>, store: &Arc<ConfigStore>, compositor: Option<Kind>) {
    let keys = Arc::new(Keys {
        hub: hub.clone(),
        store: store.clone(),
        compositor,
        kurashi: kurashi_binary(),
        turn: Mutex::new(()),
        watcher: Mutex::new(None),
    });
    hub.register(
        DOC,
        json!({"binds": []}),
        Some(Arc::new(KeysProvider(keys.clone()))),
    );
    keys.run();
    store.on_change(move |_| {
        let k = keys.clone();
        // A changed file is checked by niri (a subprocess): off the caller's thread.
        match tokio::runtime::Handle::try_current() {
            Ok(rt) => {
                rt.spawn_blocking(move || k.run());
            }
            Err(_) => k.run(),
        }
    });
}

#[cfg(test)]
mod tests {
    use super::*;

    fn defaults() -> Vec<(&'static str, String)> {
        let d = [
            "Mod+Space",
            "Mod+N",
            "Mod+Shift+N",
            "Mod+A",
            "",
            "Mod+Shift+E",
            "Super+Alt+L",
            "",
            "",
            "XF86AudioRaiseVolume",
            "XF86AudioLowerVolume",
            "XF86AudioMute",
            "XF86MonBrightnessUp",
            "XF86MonBrightnessDown",
        ];
        BINDS
            .iter()
            .zip(d)
            .map(|(b, c)| (b.field, c.to_owned()))
            .collect()
    }

    fn with(values: &[(&str, &str)]) -> Vec<(&'static str, String)> {
        let mut v = defaults();
        for (f, c) in values {
            let slot = v.iter_mut().find(|(k, _)| k == f).expect("a keys field");
            slot.1 = (*c).to_owned();
        }
        v
    }

    fn run<'a>(
        home: &'a Path,
        write: bool,
        values: Vec<(&'static str, String)>,
        niri: Option<&'a Path>,
    ) -> Value {
        apply(&Run {
            home,
            write,
            values,
            compositor: Some(Kind::Niri),
            kurashi: Path::new("/run/current-system/sw/bin/kurashi"),
            niri,
        })
    }

    fn bind_of<'a>(doc: &'a Value, key: &str) -> &'a Value {
        doc["binds"]
            .as_array()
            .unwrap()
            .iter()
            .find(|b| b["key"] == key)
            .unwrap_or_else(|| panic!("no {key} in {doc}"))
    }

    /// niri on PATH, or the test says it skips that part (it never fails on a machine without niri).
    fn niri() -> Option<PathBuf> {
        let n = on_path("niri");
        if n.is_none() {
            eprintln!(
                "SKIPPED: `niri` is not on PATH here — the rendered file was not checked by niri validate"
            );
        }
        n
    }

    #[test]
    fn keys_combos_parse_and_compare() {
        let c = Combo::parse("ctrl+alt+k").unwrap();
        assert_eq!(c.text(), "Ctrl+Alt+K");
        assert_eq!(c.canon(), "ctrl+alt+k");
        assert_eq!(Combo::parse("Shift+Mod+e").unwrap().text(), "Mod+Shift+E");
        assert_eq!(Combo::parse("Super+Alt+L").unwrap().text(), "Super+Alt+L");
        assert_eq!(
            Combo::parse("Super+Alt+L").unwrap().canon(),
            Combo::parse("Mod+Alt+L").unwrap().canon()
        );
        assert_eq!(
            Combo::parse("xf86audiomute").unwrap().text(),
            "XF86audiomute"
        );
        assert_eq!(Combo::parse("Mod+comma").unwrap().text(), "Mod+Comma");
        assert_eq!(Combo::parse("Mod+f12").unwrap().text(), "Mod+F12");
        assert_eq!(Combo::parse("Print").unwrap().text(), "Print");
        assert_eq!(
            Combo::parse("Mod+WheelScrollDown").unwrap().text(),
            "Mod+WheelScrollDown"
        );
        assert_eq!(Combo::parse("Mod+Foo"), Err("keys.invalid.key"));
        assert_eq!(Combo::parse("Mod+F0"), Err("keys.invalid.key"));
        assert_eq!(Combo::parse("Hyper+A"), Err("keys.invalid.modifier"));
        assert_eq!(Combo::parse("Mod+"), Err("keys.invalid.syntax"));
        assert_eq!(Combo::parse("Mod + A"), Err("keys.invalid.syntax"));
        assert_eq!(
            Combo::parse("Mod+Shift"),
            Err("keys.invalid.only_modifiers")
        );
        assert_eq!(Combo::parse("A"), Err("keys.invalid.needs_modifier"));
        assert_eq!(Combo::parse("Space"), Err("keys.invalid.needs_modifier"));
        assert_eq!(Combo::parse("Comma"), Err("keys.invalid.needs_modifier"));
    }

    #[test]
    fn keys_duplicates_write_the_first_and_name_both() {
        let e = evaluate(&with(&[("quick", "mod+n"), ("settings", "Mod+N")]));
        let by = |f: &str| e.iter().find(|x| x.field == f).unwrap();
        assert_eq!(by("notifications").state, "ok");
        assert_eq!(
            by("notifications").with,
            vec!["keys.quick", "keys.settings"]
        );
        assert_eq!(by("quick").state, "conflict");
        assert_eq!(
            by("quick").with,
            vec!["keys.notifications", "keys.settings"]
        );
        assert_eq!(by("settings").state, "conflict");
        assert_eq!(
            by("settings").with,
            vec!["keys.notifications", "keys.quick"]
        );
        // Super and Mod are one key in a real session.
        let e = evaluate(&with(&[("quick", "Mod+Alt+L")]));
        assert_eq!(
            e.iter().find(|x| x.field == "lock").unwrap().state,
            "conflict"
        );
    }

    #[test]
    fn keys_render_matches_the_snippet() {
        let dir = tempfile::tempdir().unwrap();
        let doc = run(dir.path(), true, defaults(), None);
        assert_eq!(doc["state"], "written", "{doc}");
        assert_eq!(doc["changed"], true);
        assert_eq!(doc["include"]["present"], false);
        assert_eq!(doc["include"]["line"], NIRI_INCLUDE);
        let text = std::fs::read_to_string(dir.path().join(NIRI_FILE)).unwrap();
        let k = "\"/run/current-system/sw/bin/kurashi\" \"act\"";
        for line in [
            format!("Mod+Space repeat=false {{ spawn {k} \"launcher.toggle\"; }}"),
            format!(
                "Mod+Shift+N repeat=false {{ spawn {k} \"sidebar.toggle\" \"{{\\\"side\\\":\\\"right\\\"}}\"; }}"
            ),
            format!(
                "Mod+Shift+E allow-inhibiting=false repeat=false {{ spawn {k} \"session.menu\"; }}"
            ),
            format!(
                "XF86AudioRaiseVolume allow-when-locked=true {{ spawn {k} \"audio.volume.up\"; }}"
            ),
            format!(
                "XF86AudioMute allow-when-locked=true repeat=false {{ spawn {k} \"audio.mute.toggle\"; }}"
            ),
        ] {
            assert!(text.contains(&line), "missing `{line}` in\n{text}");
        }
        // Empty fields bind nothing.
        assert!(!text.contains("quick.toggle"), "{text}");
        assert_eq!(bind_of(&doc, "keys.quick")["state"], "none");
    }

    #[test]
    fn keys_bad_and_duplicate_combos_stay_out_of_the_file() {
        let dir = tempfile::tempdir().unwrap();
        let doc = run(
            dir.path(),
            true,
            with(&[("quick", "Mod+N"), ("settings", "Mod+Foo")]),
            None,
        );
        let text = std::fs::read_to_string(dir.path().join(NIRI_FILE)).unwrap();
        assert_eq!(text.matches("Mod+N ").count(), 1, "{text}");
        assert!(
            text.contains("notifications.center") && !text.contains("quick.toggle"),
            "{text}"
        );
        assert!(!text.contains("Foo"), "{text}");
        assert_eq!(bind_of(&doc, "keys.quick")["state"], "conflict");
        assert_eq!(bind_of(&doc, "keys.quick")["reason"], "keys.conflict.taken");
        assert_eq!(bind_of(&doc, "keys.settings")["state"], "invalid");
        assert_eq!(bind_of(&doc, "keys.settings")["reason"], "keys.invalid.key");
        assert_eq!(
            bind_of(&doc, "keys.notifications")["with"],
            json!(["keys.quick"])
        );
    }

    #[test]
    fn keys_write_only_on_change_and_stub_when_off() {
        let dir = tempfile::tempdir().unwrap();
        let file = dir.path().join(NIRI_FILE);
        assert_eq!(run(dir.path(), true, defaults(), None)["changed"], true);
        let again = run(dir.path(), true, defaults(), None);
        assert_eq!(again["state"], "written");
        assert_eq!(again["changed"], false);
        let changed = run(dir.path(), true, with(&[("quick", "Mod+Q")]), None);
        assert_eq!(changed["changed"], true);
        assert!(
            std::fs::read_to_string(&file)
                .unwrap()
                .contains("quick.toggle")
        );
        // Off: the file stays (an include of it must keep working) but binds nothing.
        let off = run(dir.path(), false, defaults(), None);
        assert_eq!(off["state"], "off");
        let text = std::fs::read_to_string(&file).unwrap();
        assert!(
            text.starts_with(HEADER) && !text.contains("spawn"),
            "{text}"
        );
        // Off with no file: none is made.
        let fresh = tempfile::tempdir().unwrap();
        assert_eq!(run(fresh.path(), false, defaults(), None)["state"], "off");
        assert!(!fresh.path().join(NIRI_FILE).exists());
    }

    #[test]
    fn keys_leave_a_managed_symlink_and_a_foreign_file_alone() {
        let dir = tempfile::tempdir().unwrap();
        let store = dir.path().join("store-binds.kdl");
        std::fs::write(&store, "binds {\n}\n").unwrap();
        std::fs::create_dir_all(dir.path().join("niri")).unwrap();
        std::os::unix::fs::symlink(&store, dir.path().join(NIRI_FILE)).unwrap();
        let doc = run(dir.path(), true, defaults(), None);
        assert_eq!(doc["state"], "managed", "{doc}");
        assert_eq!(doc["target"], json!(store.to_string_lossy()));
        assert_eq!(std::fs::read_to_string(&store).unwrap(), "binds {\n}\n");
        assert!(
            std::fs::symlink_metadata(dir.path().join(NIRI_FILE))
                .unwrap()
                .file_type()
                .is_symlink()
        );
        // Off changes nothing either.
        assert_eq!(run(dir.path(), false, defaults(), None)["state"], "managed");
        assert_eq!(std::fs::read_to_string(&store).unwrap(), "binds {\n}\n");

        let other = tempfile::tempdir().unwrap();
        std::fs::create_dir_all(other.path().join("niri")).unwrap();
        let copy = "// my copy of the snippet\nbinds {\n    Mod+Space { spawn \"fuzzel\"; }\n}\n";
        std::fs::write(other.path().join(NIRI_FILE), copy).unwrap();
        assert_eq!(
            run(other.path(), true, defaults(), None)["state"],
            "foreign"
        );
        assert_eq!(
            std::fs::read_to_string(other.path().join(NIRI_FILE)).unwrap(),
            copy
        );
    }

    #[test]
    fn keys_report_the_include_and_binds_of_the_users_config() {
        let dir = tempfile::tempdir().unwrap();
        std::fs::create_dir_all(dir.path().join("niri")).unwrap();
        // Mod+Space bound before the include (ours replaces it), Mod+N after it (theirs wins); a commented include
        // does not count, nor a bind in a commented block.
        std::fs::write(
            dir.path().join(NIRI_CONFIG),
            "// include \"kurashi-binds.kdl\"\nbinds {\n    Mod+Space { spawn \"fuzzel\"; }\n    /-Mod+A { spawn \"x\"; }\n}\n\
             include \"kurashi-binds.kdl\"\nbinds {\n    mod+n { spawn \"mako\"; }\n}\n",
        )
        .unwrap();
        let doc = run(dir.path(), true, defaults(), None);
        assert_eq!(doc["include"]["present"], true, "{doc}");
        assert_eq!(bind_of(&doc, "keys.launcher")["config"], "replaces");
        assert_eq!(bind_of(&doc, "keys.notifications")["config"], "overridden");
        assert!(bind_of(&doc, "keys.sidebar_left").get("config").is_none());
        // Without the include niri reads none of ours: nothing collides.
        std::fs::write(
            dir.path().join(NIRI_CONFIG),
            "binds {\n    Mod+N { spawn \"mako\"; }\n}\n",
        )
        .unwrap();
        let doc = run(dir.path(), true, defaults(), None);
        assert_eq!(doc["include"]["present"], false);
        assert!(bind_of(&doc, "keys.notifications").get("config").is_none());
    }

    #[test]
    fn keys_other_compositors_write_nothing() {
        let dir = tempfile::tempdir().unwrap();
        let doc = apply(&Run {
            home: dir.path(),
            write: true,
            values: defaults(),
            compositor: Some(Kind::Sway),
            kurashi: Path::new("kurashi"),
            niri: None,
        });
        assert_eq!(doc["state"], "unsupported");
        assert_eq!(doc["compositor"], "sway");
        assert!(doc.get("file").is_none());
        assert_eq!(bind_of(&doc, "keys.launcher")["canon"], "mod+space");
        assert!(!dir.path().join(NIRI_FILE).exists());
    }

    #[test]
    fn keys_rendered_file_passes_niri_validate() {
        let Some(niri) = niri() else { return };
        let dir = tempfile::tempdir().unwrap();
        let all = with(&[
            ("quick", "Mod+Q"),
            ("settings", "Ctrl+Alt+Comma"),
            ("webdock", "Mod+B"),
        ]);
        let doc = run(dir.path(), true, all, Some(&niri));
        assert_eq!(doc["state"], "written", "{doc}");
        assert_eq!(doc["checked"], true, "{doc}");
        // As the user's config would: a niri config that includes the rendered file.
        let cfg = dir.path().join(NIRI_CONFIG);
        std::fs::write(&cfg, format!("{NIRI_INCLUDE}\n")).unwrap();
        let out = Command::new(&niri)
            .arg("validate")
            .arg("-c")
            .arg(&cfg)
            .output()
            .unwrap();
        assert!(
            out.status.success(),
            "niri validate: {}",
            String::from_utf8_lossy(&out.stderr)
        );
        // The stub too: an include of it keeps working while keys.write is off.
        run(dir.path(), false, defaults(), Some(&niri));
        let out = Command::new(&niri)
            .arg("validate")
            .arg("-c")
            .arg(&cfg)
            .output()
            .unwrap();
        assert!(
            out.status.success(),
            "niri validate (stub): {}",
            String::from_utf8_lossy(&out.stderr)
        );
    }

    #[test]
    fn keys_niri_refusing_a_key_leaves_it_out_and_says_so() {
        let Some(niri) = niri() else { return };
        let dir = tempfile::tempdir().unwrap();
        let doc = run(
            dir.path(),
            true,
            with(&[("quick", "Mod+XF86Bogus")]),
            Some(&niri),
        );
        assert_eq!(doc["state"], "written", "{doc}");
        assert_eq!(bind_of(&doc, "keys.quick")["state"], "invalid");
        assert_eq!(bind_of(&doc, "keys.quick")["reason"], "keys.invalid.niri");
        let text = std::fs::read_to_string(dir.path().join(NIRI_FILE)).unwrap();
        assert!(
            !text.contains("Bogus") && text.contains("launcher.toggle"),
            "{text}"
        );
    }
}
