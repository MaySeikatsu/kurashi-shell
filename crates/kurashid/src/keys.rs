//! Keyboard shortcuts as config (K64, I72): `keys.*` names one combo per shell action. With `keys.write` on, kurashid
//! writes the binds file of the session's compositor from them — only when the content changes — and `svc.keys` reports
//! the file, the include line that compositor's config needs and whether it is there, and each shortcut's state: a combo
//! the compositor would not take, or one that two actions share, is left out of the file and says why (Shōjiki). K49's
//! pattern: our own file, never the user's config. A file we did not write (a Home-Manager store symlink, a copy of
//! `docs/niri-binds.kdl`) is never overwritten: the document says whose it is.
//!
//! Three compositors (W38-keys). niri writes a `binds {}` block, each bind named by `hotkey-overlay-title` in niri's own
//! cheat sheet. Sway writes `bindsym` lines and reads them on `swaymsg reload` only. Hyprland writes `bind` lines and
//! reloads by itself. A checker on PATH (`niri validate`, `sway -C`, `hyprland --verify-config`) checks the file before it
//! is written. Only niri's own binds are compared with the user's binds (`config`): for Sway and Hyprland the document says
//! nothing about a collision, because `$mod` variables are not expanded there (docs/ux/keys.md, Limits).

use std::collections::BTreeMap;
use std::ffi::OsString;
use std::io::Read;
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::{Arc, Mutex};
use std::time::{Duration, Instant};

use serde_json::{Value, json};

use kurashi_compositor::any::Kind;

use crate::config::ConfigStore;
use crate::hub::{Hub, Provider};

pub const DOC: &str = "svc.keys";
/// The binds file of each compositor and the config that includes it, under `$XDG_CONFIG_HOME`.
pub const NIRI_FILE: &str = "niri/kurashi-binds.kdl";
/// niri's own config, which includes it.
pub const NIRI_CONFIG: &str = "niri/config.kdl";
pub const NIRI_INCLUDE: &str = "include \"kurashi-binds.kdl\"";
pub const SWAY_FILE: &str = "sway/kurashi-binds.conf";
pub const SWAY_CONFIG: &str = "sway/config";
/// Sway includes a file relative to the config that names it.
pub const SWAY_INCLUDE: &str = "include kurashi-binds.conf";
pub const HYPR_FILE: &str = "hypr/kurashi-binds.conf";
pub const HYPR_CONFIG: &str = "hypr/hyprland.conf";
/// The first line of every niri file we write: a file at that path without it is not ours.
const HEADER: &str = "// Written by kurashid from the keys.* settings (Settings → Keys).";
/// The same line in the `#` comments of Sway and Hyprland.
const HEADER_HASH: &str = "# Written by kurashid from the keys.* settings (Settings → Keys).";
/// One bind's niri title: the locale's `keys.overlay.title` with the action's label (`config.keys.<field>.label`).
const OVERLAY_TITLE: &str = "keys.overlay.title";

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

    /// The modifiers as `kind` spells them in a bind, in the order written (`Mod` and `Super` are one there); `None`
    /// when one of them has no name in that compositor.
    fn spelled_mods(&self, kind: Kind) -> Option<Vec<&'static str>> {
        let mut out: Vec<&'static str> = Vec::new();
        for &i in &self.mods {
            let name = spelled_mod(kind, i)?;
            if out.last() != Some(&name) {
                out.push(name);
            }
        }
        Some(out)
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
    /// niri only: the user's niri config binds the same combo: `replaces` (ours comes later and wins) or `overridden`
    /// (theirs comes later: ours is not in effect).
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
fn scan_niri(text: &str) -> (BTreeMap<String, usize>, Option<usize>) {
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
        if depth == 0 && is_our_include(Kind::Niri, line) {
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

/// The include line of a Sway or Hyprland config (`#` comments skipped). Their binds are not compared (see the module
/// doc), so only the include is read.
fn scan_hash(kind: Kind, text: &str) -> (BTreeMap<String, usize>, Option<usize>) {
    let include = text
        .lines()
        .enumerate()
        .filter(|(_, raw)| {
            let line = raw.trim();
            !line.starts_with('#') && is_our_include(kind, line)
        })
        .map(|(n, _)| n)
        .next();
    (BTreeMap::new(), include)
}

fn scan_config(kind: Kind, text: &str) -> (BTreeMap<String, usize>, Option<usize>) {
    match kind {
        Kind::Niri => scan_niri(text),
        Kind::Sway | Kind::Hyprland => scan_hash(kind, text),
    }
}

/// Whether a (comment-free) line of the compositor's config is our include.
fn is_our_include(kind: Kind, line: &str) -> bool {
    match kind {
        Kind::Niri => line.starts_with("include") && line.contains("kurashi-binds.kdl\""),
        Kind::Sway => line.starts_with("include") && line.contains("kurashi-binds.conf"),
        Kind::Hyprland => line.starts_with("source") && line.contains("kurashi-binds.conf"),
    }
}

// --- compositors ---------------------------------------------------------------------------------

/// The file a compositor reads our binds from, and the config that includes it (both under `$XDG_CONFIG_HOME`).
fn files(kind: Kind) -> (&'static str, &'static str) {
    match kind {
        Kind::Niri => (NIRI_FILE, NIRI_CONFIG),
        Kind::Sway => (SWAY_FILE, SWAY_CONFIG),
        Kind::Hyprland => (HYPR_FILE, HYPR_CONFIG),
    }
}

/// The first line of a file of ours for `kind` (the comment syntax is the compositor's).
fn header(kind: Kind) -> &'static str {
    match kind {
        Kind::Niri => HEADER,
        Kind::Sway | Kind::Hyprland => HEADER_HASH,
    }
}

/// The programs that check a file of `kind`, in the order looked for on PATH.
fn checkers(kind: Kind) -> &'static [&'static str] {
    match kind {
        Kind::Niri => &["niri"],
        Kind::Sway => &["sway"],
        Kind::Hyprland => &["hyprland", "Hyprland"],
    }
}

/// The line that makes the compositor read our file. Sway includes it relative to its config; Hyprland gets the absolute
/// path, which needs no assumption about where its config looks for `source`.
fn include_line(kind: Kind, file: &Path) -> String {
    match kind {
        Kind::Niri => NIRI_INCLUDE.to_owned(),
        Kind::Sway => SWAY_INCLUDE.to_owned(),
        Kind::Hyprland => format!("source = {}", file.to_string_lossy()),
    }
}

/// A modifier as the compositor spells it in a bind. Sway knows Mod4 (Super), Mod1 (Alt) and Mod5 (ISO Level 3); it
/// has no ISO Level 5 name. Hyprland has the same set under its own names. `Mod` is Super on a TTY.
fn spelled_mod(kind: Kind, index: usize) -> Option<&'static str> {
    let name = MODIFIERS[index].0;
    match kind {
        Kind::Niri => Some(name),
        Kind::Sway => Some(match name {
            "Mod" | "Super" => "Mod4",
            "Ctrl" => "Control",
            "Alt" => "Mod1",
            "Shift" => "Shift",
            "ISO_Level3_Shift" => "Mod5",
            _ => return None,
        }),
        Kind::Hyprland => Some(match name {
            "Mod" | "Super" => "SUPER",
            "Ctrl" => "CTRL",
            "Alt" => "ALT",
            "Shift" => "SHIFT",
            "ISO_Level3_Shift" => "MOD5",
            _ => return None,
        }),
    }
}

/// The reason a checker's refusal of a key is shown with.
fn refused_reason(kind: Kind) -> &'static str {
    match kind {
        Kind::Niri => "keys.invalid.niri",
        Kind::Sway => "keys.invalid.sway",
        Kind::Hyprland => "keys.invalid.hyprland",
    }
}

/// The stub a file of ours becomes while `keys.write` is off: an include that names it keeps working (niri refuses a
/// config whose include is missing), and binds nothing.
fn stub(kind: Kind) -> String {
    let c = if kind == Kind::Niri { "//" } else { "#" };
    let mut s = format!(
        "{}\n{c} keys.write is off: your compositor's own config keeps the keys. Kept so an include of it still works.\n",
        header(kind)
    );
    if kind == Kind::Niri {
        s.push_str("binds {\n}\n");
    }
    s
}

/// A word for `sh`: the command Sway's and Hyprland's `exec` run through it. Plain words stay as they are.
fn sh_word(s: &str) -> String {
    if !s.is_empty()
        && s.chars()
            .all(|c| c.is_ascii_alphanumeric() || "/._-+:@%=".contains(c))
    {
        s.to_owned()
    } else {
        sh_quote(s)
    }
}

/// A single-quoted word for `sh`. Sway passes single quotes through to the shell untouched, so JSON in them arrives
/// whole (the probe that fixed this: `'{"side":"right"}'` as one argument; the escaped-quote forms did not).
fn sh_quote(s: &str) -> String {
    format!("'{}'", s.replace('\'', "'\\''"))
}

/// The command a bind runs: `<kurashi> act <action> '<args>'`.
fn act_command(b: &Bind, program: &str) -> String {
    let args = b
        .args
        .map(|a| format!(" {}", sh_quote(a)))
        .unwrap_or_default();
    format!("{program} act {}{args}", b.action)
}

/// The binds file for niri (as `docs/niri-binds.kdl`): the entries in state `ok`, each spawning `kurashi act`, named by
/// their overlay title (`titles` in [`BINDS`] order).
fn render_niri(entries: &[Entry], kurashi: &Path, titles: &[String]) -> String {
    let mut s = String::new();
    s.push_str(HEADER);
    s.push_str("\n// Change them there, not here: this file is written again when they change.\n");
    s.push_str("// niri reads it once ~/.config/niri/config.kdl includes it, after your own binds {} block:\n");
    s.push_str(&format!("//     {NIRI_INCLUDE}\n\nbinds {{\n"));
    let program = kdl_string(&kurashi.to_string_lossy());
    for (i, (e, b)) in entries.iter().zip(BINDS.iter()).enumerate() {
        let Some(c) = e.parsed.as_ref().filter(|_| e.state == "ok") else {
            continue;
        };
        let mut lhs = vec![c.text()];
        if let Some(title) = titles.get(i) {
            lhs.push(format!("hotkey-overlay-title={}", kdl_string(title)));
        }
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

fn kdl_string(s: &str) -> String {
    format!("\"{}\"", s.replace('\\', "\\\\").replace('"', "\\\""))
}

/// The header of a `#`-commented file: where the compositor reads it from.
fn hash_header(include: &str) -> String {
    format!(
        "{HEADER_HASH}\n# Change them there, not here: this file is written again when they change.\n# The compositor reads it where its config includes it:\n#     {include}\n"
    )
}

/// The binds file for Sway: `bindsym` lines. `--locked` for a bind that works while locked, `--inhibited` for one that
/// works while an app inhibits shortcuts, `--no-repeat` for every bind that does not repeat while held.
fn render_sway(entries: &[Entry], kurashi: &Path, include: &str) -> String {
    let mut s = hash_header(include);
    s.push('\n');
    let program = sh_word(&kurashi.to_string_lossy());
    for (e, b) in entries.iter().zip(BINDS.iter()) {
        let Some(c) = e.parsed.as_ref().filter(|_| e.state == "ok") else {
            continue;
        };
        let Some(mods) = c.spelled_mods(Kind::Sway) else {
            continue;
        };
        let mut flags = String::new();
        if b.locked {
            flags.push_str("--locked ");
        }
        if b.always {
            flags.push_str("--inhibited ");
        }
        if !b.repeat {
            flags.push_str("--no-repeat ");
        }
        let combo: Vec<&str> = mods.iter().copied().chain([c.key()]).collect();
        s.push_str(&format!(
            "bindsym {flags}{} exec {}\n",
            combo.join("+"),
            act_command(b, &program)
        ));
    }
    s
}

/// The binds file for Hyprland: `bind` lines (`binde` repeats while held, `bindl` works while locked), the modifiers
/// space-separated before the key. Hyprland has no inhibit bypass, so `allow-inhibiting=false` is not in its file.
fn render_hypr(entries: &[Entry], kurashi: &Path, include: &str) -> String {
    let mut s = hash_header(include);
    s.push('\n');
    let program = sh_word(&kurashi.to_string_lossy());
    for (e, b) in entries.iter().zip(BINDS.iter()) {
        let Some(c) = e.parsed.as_ref().filter(|_| e.state == "ok") else {
            continue;
        };
        let Some(mods) = c.spelled_mods(Kind::Hyprland) else {
            continue;
        };
        let flags = format!(
            "{}{}",
            if b.repeat { "e" } else { "" },
            if b.locked { "l" } else { "" }
        );
        s.push_str(&format!(
            "bind{flags} = {}, {}, exec, {}\n",
            mods.join(" "),
            c.key(),
            act_command(b, &program)
        ));
    }
    s
}

/// The file for `kind`: the entries in state `ok`, each bound to `kurashi act <action>`.
fn render(
    kind: Kind,
    entries: &[Entry],
    kurashi: &Path,
    include: &str,
    titles: &[String],
) -> String {
    match kind {
        Kind::Niri => render_niri(entries, kurashi, titles),
        Kind::Sway => render_sway(entries, kurashi, include),
        Kind::Hyprland => render_hypr(entries, kurashi, include),
    }
}

/// Modifiers a compositor has no name for leave the file, with the reason (the file is written without them).
fn mark_unspellable(kind: Kind, entries: &mut [Entry]) {
    for e in entries.iter_mut().filter(|e| e.state == "ok") {
        let unspellable = e
            .parsed
            .as_ref()
            .is_some_and(|c| c.spelled_mods(kind).is_none());
        if unspellable {
            e.state = "invalid";
            e.reason = Some("keys.invalid.modifier_here".into());
        }
    }
}

/// The checker's verdict on a file's text: `None` when it does not answer in time (or the checker is not there), else
/// `Ok`, or the messages it gave.
pub fn check(kind: Kind, program: &Path, text: &str) -> Option<Result<(), String>> {
    // One name per check: two runs at once (tests in parallel) must not read each other's file.
    static SEQ: AtomicU64 = AtomicU64::new(0);
    let n = SEQ.fetch_add(1, Ordering::Relaxed);
    let ext = if kind == Kind::Niri { "kdl" } else { "conf" };
    let tmp = std::env::temp_dir().join(format!("kurashid-keys-{}-{n}.{ext}", std::process::id()));
    std::fs::write(&tmp, text).ok()?;
    let result = run_check(kind, program, &tmp);
    let _ = std::fs::remove_file(&tmp);
    result
}

fn run_check(kind: Kind, program: &Path, file: &Path) -> Option<Result<(), String>> {
    let flags: &[&str] = match kind {
        Kind::Niri => &["validate", "-c"],
        Kind::Sway => &["-C", "-c"],
        Kind::Hyprland => &["--verify-config", "-c"],
    };
    let mut child = Command::new(program)
        .args(flags)
        .arg(file)
        .env("NO_COLOR", "1")
        .stdin(Stdio::null())
        .stdout(Stdio::null())
        .stderr(Stdio::piped())
        .spawn()
        .ok()?;
    let deadline = Instant::now() + Duration::from_secs(5);
    let status = loop {
        match child.try_wait() {
            Ok(Some(s)) => break s,
            Ok(None) if Instant::now() < deadline => std::thread::sleep(Duration::from_millis(5)),
            _ => {
                let _ = child.kill();
                let _ = child.wait();
                tracing::warn!("keys: the compositor's checker did not answer in time");
                return None;
            }
        }
    };
    let mut err = String::new();
    if let Some(mut e) = child.stderr.take() {
        let _ = e.read_to_string(&mut err);
    }
    // `sway -C` exits 0 when only an included file has an error, so its own message decides too.
    let failed = !status.success() || err.contains("Error(s) loading config");
    Some(if failed { Err(err) } else { Ok(()) })
}

/// The key a checker refused, named in its message: niri's `invalid key: X`, Sway's `Unknown key or button 'X'`.
/// Hyprland names no key in its errors (it does not check key names), so its refusals leave the file unwritten.
fn refused_key(kind: Kind, message: &str) -> Option<String> {
    let (marker, end) = match kind {
        Kind::Niri => ("invalid key: ", None),
        Kind::Sway => ("Unknown key or button '", Some('\'')),
        Kind::Hyprland => return None,
    };
    let i = message.find(marker)?;
    let rest = &message[i + marker.len()..];
    let key: String = match end {
        Some(stop) => rest.chars().take_while(|c| *c != stop).collect(),
        None => rest.chars().take_while(|c| !c.is_whitespace()).collect(),
    };
    (!key.is_empty()).then_some(key)
}

/// What a checker's refusal says, for the document: the lines without colour and debug noise.
fn detail_of(kind: Kind, message: &str) -> String {
    let lines: Vec<String> = message
        .lines()
        .map(|l| strip_ansi(l).trim().to_owned())
        .filter(|l| !l.is_empty())
        .collect();
    if kind == Kind::Niri {
        return lines.join(" ");
    }
    let errors: Vec<&str> = lines
        .iter()
        .map(String::as_str)
        .filter(|l| l.to_lowercase().contains("error") && !l.contains("Nvidia"))
        .collect();
    if errors.is_empty() {
        lines.join(" ")
    } else {
        errors.join(" ")
    }
}

/// Removes the terminal colour codes a checker prints (`ESC [ … m`).
fn strip_ansi(s: &str) -> String {
    let mut out = String::with_capacity(s.len());
    let mut chars = s.chars();
    while let Some(c) = chars.next() {
        if c == '\u{1b}' {
            for d in chars.by_ref() {
                if d.is_ascii_alphabetic() {
                    break;
                }
            }
        } else {
            out.push(c);
        }
    }
    out
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
    /// The compositor's checker, when one is on PATH.
    pub checker: Option<&'a Path>,
    /// The niri overlay titles, in [`BINDS`] order (the locale's, see [`overlay_titles`]).
    pub titles: &'a [String],
}

/// Judges the combos, writes the file when it is ours to write and changed, and returns the `svc.keys` document.
pub fn apply(run: &Run) -> Value {
    let mut entries = evaluate(&run.values);
    let mut doc = json!({
        "write": run.write,
        "compositor": run.compositor.map(Kind::name),
    });
    let Some(kind) = run.compositor else {
        doc["state"] = json!(if run.write { "unsupported" } else { "off" });
        doc["binds"] = binds_json(&entries);
        return doc;
    };
    let (file_rel, config_rel) = files(kind);
    let file = run.home.join(file_rel);
    let cfg = run.home.join(config_rel);
    let cfg_text = std::fs::read_to_string(&cfg).unwrap_or_default();
    let (theirs, include_at) = scan_config(kind, &cfg_text);
    let include = include_line(kind, &file);
    doc["file"] = json!(file.to_string_lossy());
    doc["include"] = json!({
        "file": cfg.to_string_lossy(),
        "line": include,
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
        .is_none_or(|t| t.starts_with(header(kind)) || t.trim().is_empty());
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
            && let Err(e) = write_if_changed(&file, &stub(kind))
        {
            tracing::warn!(error = %e, "keys: could not empty the binds file");
        }
    } else {
        write_file(run, kind, &file, &include, &mut entries, &mut doc);
    }
    // Only a file the compositor reads can collide with the user's own binds (niri's config: see the module doc).
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

/// Renders, lets the checker judge it (a key it refuses is left out and named, when the message names one), and writes
/// it when it changed.
fn write_file(
    run: &Run,
    kind: Kind,
    file: &Path,
    include: &str,
    entries: &mut [Entry],
    doc: &mut Value,
) {
    mark_unspellable(kind, entries);
    let mut text = render(kind, entries, run.kurashi, include, run.titles);
    let unchanged = std::fs::read_to_string(file).is_ok_and(|old| old == text);
    if !unchanged && let Some(program) = run.checker {
        let mut checked = false;
        for _ in 0..=BINDS.len() {
            match check(kind, program, &text) {
                None => break,
                Some(Ok(())) => {
                    checked = true;
                    break;
                }
                Some(Err(msg)) => {
                    let bad = refused_key(kind, &msg).map(|k| k.to_lowercase());
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
                            e.reason = Some(refused_reason(kind).into());
                            text = render(kind, entries, run.kurashi, include, run.titles);
                        }
                        None => {
                            doc["state"] = json!("error");
                            doc["error"] = json!("keys.error.refused");
                            doc["detail"] = json!(detail_of(kind, &msg));
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

/// The document's `binds`: one row per shortcut, in [`BINDS`] order (`pub` for the mock's copy of the document).
pub fn binds_json(entries: &[Entry]) -> Value {
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

/// The overlay title of each bind, in [`BINDS`] order: the template `keys.overlay.title` with the action's label
/// (`config.keys.<field>.label`, the Settings row's own name). A key missing from `strings` shows the field name.
pub fn overlay_titles(strings: &BTreeMap<String, String>) -> Vec<String> {
    let template = strings
        .get(OVERLAY_TITLE)
        .map_or("{action}", String::as_str);
    BINDS
        .iter()
        .map(|b| {
            let label = strings
                .get(&format!("config.keys.{}.label", b.field))
                .map_or(b.field, String::as_str);
            template.replace("{action}", label)
        })
        .collect()
}

/// The strings of `locale` over English, as the daemon's i18n document holds them.
fn strings_of(locale: &str) -> BTreeMap<String, String> {
    let root = crate::i18n::data_dir().join("i18n");
    let mut out = crate::i18n::load_locale(&root, crate::i18n::FALLBACK);
    if locale != crate::i18n::FALLBACK {
        out.extend(crate::i18n::load_locale(&root, locale));
    }
    out
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
    /// The overlay titles in the session's language, read once (the locale is the session's).
    titles: Vec<String>,
    /// One run at a time: the last one reads the latest values.
    turn: Mutex<()>,
    /// The compositor's config directory watched while Settings shows the document: an include line added by hand shows
    /// at once.
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
        let checker = self
            .compositor
            .and_then(|kind| checkers(kind).iter().find_map(|n| on_path(n)));
        let home = config_home();
        let doc = apply(&Run {
            home: &home,
            write,
            values: BINDS.iter().map(|b| (b.field, text(b.field))).collect(),
            compositor: self.compositor,
            kurashi: &self.kurashi,
            checker: checker.as_deref(),
            titles: &self.titles,
        });
        let _ = self.hub.set(DOC, doc, None);
    }
}

/// The provider: a run when the first viewer subscribes (a file edited by hand since shows as it is now), and the
/// compositor's config directory watched while one does (Ma: nothing runs while nobody looks; config changes run
/// regardless).
struct KeysProvider(Arc<Keys>);

impl Provider for KeysProvider {
    fn start(&self, _hub: Arc<Hub>) {
        self.0.run();
        let Some(kind) = self.0.compositor else {
            return;
        };
        use notify::Watcher;
        let keys = self.0.clone();
        let (file_rel, config_rel) = files(kind);
        let dir = config_home().join(Path::new(config_rel).parent().unwrap_or(Path::new("")));
        let names: Vec<OsString> = [file_rel, config_rel]
            .iter()
            .filter_map(|p| Path::new(p).file_name().map(OsString::from))
            .collect();
        let watcher = notify::recommended_watcher(move |ev: notify::Result<notify::Event>| {
            let ours = ev.is_ok_and(|e| {
                e.paths
                    .iter()
                    .any(|p| p.file_name().is_some_and(|n| names.iter().any(|x| x == n)))
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
            Err(e) => tracing::debug!(error = %e, "keys: no watcher for the compositor's config"),
        }
    }

    fn stop(&self) {
        *self.0.watcher.lock().unwrap_or_else(|e| e.into_inner()) = None;
    }
}

/// `svc.keys`, kept current after each config change.
pub fn register(hub: &Arc<Hub>, store: &Arc<ConfigStore>, compositor: Option<Kind>) {
    let locale = crate::i18n::locale_from_env();
    let keys = Arc::new(Keys {
        hub: hub.clone(),
        store: store.clone(),
        compositor,
        kurashi: kurashi_binary(),
        titles: overlay_titles(&strings_of(&locale)),
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
        // A changed file is checked by the compositor's checker (a subprocess): off the caller's thread.
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

    /// The English overlay titles (the shipped strings) and the Japanese ones, which carry non-ASCII into the KDL.
    fn titles(locale: &str) -> Vec<String> {
        overlay_titles(&strings_of(locale))
    }

    fn run_as<'a>(
        kind: Kind,
        home: &'a Path,
        write: bool,
        values: Vec<(&'static str, String)>,
        checker: Option<&'a Path>,
        titles: &'a [String],
    ) -> Value {
        apply(&Run {
            home,
            write,
            values,
            compositor: Some(kind),
            kurashi: Path::new("/run/current-system/sw/bin/kurashi"),
            checker,
            titles,
        })
    }

    fn run<'a>(
        home: &'a Path,
        write: bool,
        values: Vec<(&'static str, String)>,
        checker: Option<&'a Path>,
        titles: &'a [String],
    ) -> Value {
        run_as(Kind::Niri, home, write, values, checker, titles)
    }

    fn bind_of<'a>(doc: &'a Value, key: &str) -> &'a Value {
        doc["binds"]
            .as_array()
            .unwrap()
            .iter()
            .find(|b| b["key"] == key)
            .unwrap_or_else(|| panic!("no {key} in {doc}"))
    }

    /// The checker of `kind` on PATH, or the test says it skips that part (it never fails on a machine without it).
    fn checker(kind: Kind) -> Option<PathBuf> {
        let c = checkers(kind).iter().find_map(|n| on_path(n));
        if c.is_none() {
            eprintln!(
                "SKIPPED: no {} on PATH — the rendered file was not checked",
                kind.name()
            );
        }
        c
    }

    /// `sway -C` opens a backend on `$WAYLAND_DISPLAY` under `$XDG_RUNTIME_DIR`, so its answer depended on the session the
    /// tests ran in: a sandbox's runtime dir refused every file (`keys.error.refused`). Checking a file needs no display,
    /// so the sway tests run the checker through this wrapper, which clears the variable for the checker alone. `run_check`
    /// is not the tests' to change (row 471), and this process's environment stays as it is (the workspace forbids unsafe).
    fn sway_without_display(sway: &Path, dir: &Path) -> PathBuf {
        use std::os::unix::fs::PermissionsExt;
        let wrapper = dir.join("sway-check");
        let script = format!(
            "#!/bin/sh\nunset WAYLAND_DISPLAY\nexec '{}' \"$@\"\n",
            sway.display()
        );
        std::fs::write(&wrapper, script).unwrap();
        std::fs::set_permissions(&wrapper, std::fs::Permissions::from_mode(0o755)).unwrap();
        wrapper
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
    fn keys_titles_come_from_the_locale_and_name_each_action() {
        let en = titles("en");
        assert_eq!(en[0], "kurashi: Launcher");
        assert_eq!(en[2], "kurashi: Right sidebar");
        assert_eq!(en.len(), BINDS.len());
        let ja = titles("ja");
        assert!(ja[0].starts_with("暮らし: "), "{}", ja[0]);
        // Every bind has a label of its own in both locales (a missing one would show the field name).
        for b in BINDS.iter() {
            for locale in ["en", "ja"] {
                let strings = strings_of(locale);
                assert!(
                    strings.contains_key(&format!("config.keys.{}.label", b.field)),
                    "no {locale} label for keys.{}",
                    b.field
                );
            }
        }
    }

    #[test]
    fn keys_render_matches_the_snippet() {
        let dir = tempfile::tempdir().unwrap();
        let t = titles("en");
        let doc = run(dir.path(), true, defaults(), None, &t);
        assert_eq!(doc["state"], "written", "{doc}");
        assert_eq!(doc["changed"], true);
        assert_eq!(doc["include"]["present"], false);
        assert_eq!(doc["include"]["line"], NIRI_INCLUDE);
        let text = std::fs::read_to_string(dir.path().join(NIRI_FILE)).unwrap();
        let k = "\"/run/current-system/sw/bin/kurashi\" \"act\"";
        for line in [
            format!(
                "Mod+Space hotkey-overlay-title=\"kurashi: Launcher\" repeat=false {{ spawn {k} \"launcher.toggle\"; }}"
            ),
            format!(
                "Mod+Shift+N hotkey-overlay-title=\"kurashi: Right sidebar\" repeat=false {{ spawn {k} \"sidebar.toggle\" \"{{\\\"side\\\":\\\"right\\\"}}\"; }}"
            ),
            format!(
                "Mod+Shift+E hotkey-overlay-title=\"kurashi: Session menu\" allow-inhibiting=false repeat=false {{ spawn {k} \"session.menu\"; }}"
            ),
            format!(
                "XF86AudioRaiseVolume hotkey-overlay-title=\"kurashi: Volume up\" allow-when-locked=true {{ spawn {k} \"audio.volume.up\"; }}"
            ),
            format!(
                "XF86AudioMute hotkey-overlay-title=\"kurashi: Mute\" allow-when-locked=true repeat=false {{ spawn {k} \"audio.mute.toggle\"; }}"
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
        let t = titles("en");
        let doc = run(
            dir.path(),
            true,
            with(&[("quick", "Mod+N"), ("settings", "Mod+Foo")]),
            None,
            &t,
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
        let t = titles("en");
        let file = dir.path().join(NIRI_FILE);
        assert_eq!(run(dir.path(), true, defaults(), None, &t)["changed"], true);
        let again = run(dir.path(), true, defaults(), None, &t);
        assert_eq!(again["state"], "written");
        assert_eq!(again["changed"], false);
        let changed = run(dir.path(), true, with(&[("quick", "Mod+Q")]), None, &t);
        assert_eq!(changed["changed"], true);
        assert!(
            std::fs::read_to_string(&file)
                .unwrap()
                .contains("quick.toggle")
        );
        // Off: the file stays (an include of it must keep working) but binds nothing.
        let off = run(dir.path(), false, defaults(), None, &t);
        assert_eq!(off["state"], "off");
        let text = std::fs::read_to_string(&file).unwrap();
        assert!(
            text.starts_with(HEADER) && !text.contains("spawn"),
            "{text}"
        );
        // Off with no file: none is made.
        let fresh = tempfile::tempdir().unwrap();
        assert_eq!(
            run(fresh.path(), false, defaults(), None, &t)["state"],
            "off"
        );
        assert!(!fresh.path().join(NIRI_FILE).exists());
    }

    #[test]
    fn keys_leave_a_managed_symlink_and_a_foreign_file_alone() {
        let t = titles("en");
        let dir = tempfile::tempdir().unwrap();
        let store = dir.path().join("store-binds.kdl");
        std::fs::write(&store, "binds {\n}\n").unwrap();
        std::fs::create_dir_all(dir.path().join("niri")).unwrap();
        std::os::unix::fs::symlink(&store, dir.path().join(NIRI_FILE)).unwrap();
        let doc = run(dir.path(), true, defaults(), None, &t);
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
        assert_eq!(
            run(dir.path(), false, defaults(), None, &t)["state"],
            "managed"
        );
        assert_eq!(std::fs::read_to_string(&store).unwrap(), "binds {\n}\n");

        let other = tempfile::tempdir().unwrap();
        std::fs::create_dir_all(other.path().join("niri")).unwrap();
        let copy = "// my copy of the snippet\nbinds {\n    Mod+Space { spawn \"fuzzel\"; }\n}\n";
        std::fs::write(other.path().join(NIRI_FILE), copy).unwrap();
        assert_eq!(
            run(other.path(), true, defaults(), None, &t)["state"],
            "foreign"
        );
        assert_eq!(
            std::fs::read_to_string(other.path().join(NIRI_FILE)).unwrap(),
            copy
        );
    }

    #[test]
    fn keys_report_the_include_and_binds_of_the_users_config() {
        let t = titles("en");
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
        let doc = run(dir.path(), true, defaults(), None, &t);
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
        let doc = run(dir.path(), true, defaults(), None, &t);
        assert_eq!(doc["include"]["present"], false);
        assert!(bind_of(&doc, "keys.notifications").get("config").is_none());
    }

    #[test]
    fn keys_no_compositor_writes_nothing() {
        let dir = tempfile::tempdir().unwrap();
        let t = titles("en");
        let doc = apply(&Run {
            home: dir.path(),
            write: true,
            values: defaults(),
            compositor: None,
            kurashi: Path::new("kurashi"),
            checker: None,
            titles: &t,
        });
        assert_eq!(doc["state"], "unsupported");
        assert!(doc.get("file").is_none());
        assert_eq!(bind_of(&doc, "keys.launcher")["canon"], "mod+space");
        assert!(!dir.path().join(NIRI_FILE).exists());
        assert!(!dir.path().join(SWAY_FILE).exists());
    }

    #[test]
    fn keys_sway_renders_bindsym_lines_with_the_json_quoted_for_sh() {
        let k = "/run/current-system/sw/bin/kurashi";
        let text = render(
            Kind::Sway,
            &evaluate(&defaults()),
            Path::new(k),
            SWAY_INCLUDE,
            &[],
        );
        assert!(text.starts_with(HEADER_HASH), "{text}");
        assert!(text.contains(&format!("#     {SWAY_INCLUDE}\n")), "{text}");
        for line in [
            format!("bindsym --no-repeat Mod4+Space exec {k} act launcher.toggle"),
            format!(
                "bindsym --no-repeat Mod4+Shift+N exec {k} act sidebar.toggle '{{\"side\":\"right\"}}'"
            ),
            format!("bindsym --inhibited --no-repeat Mod4+Shift+E exec {k} act session.menu"),
            format!("bindsym --inhibited --no-repeat Mod4+Mod1+L exec {k} act session.lock"),
            format!("bindsym --locked XF86AudioRaiseVolume exec {k} act audio.volume.up"),
            format!("bindsym --locked --no-repeat XF86AudioMute exec {k} act audio.mute.toggle"),
        ] {
            assert!(
                text.lines().any(|l| l == line),
                "missing `{line}` in\n{text}"
            );
        }
        // Empty fields bind nothing.
        assert!(!text.contains("quick.toggle"), "{text}");
    }

    #[test]
    fn keys_hyprland_renders_bind_lines() {
        let k = "/run/current-system/sw/bin/kurashi";
        let text = render(
            Kind::Hyprland,
            &evaluate(&defaults()),
            Path::new(k),
            "source = /x/hypr/kurashi-binds.conf",
            &[],
        );
        for line in [
            format!("bind = SUPER, Space, exec, {k} act launcher.toggle"),
            format!("bind = SUPER SHIFT, N, exec, {k} act sidebar.toggle '{{\"side\":\"right\"}}'"),
            format!("bind = SUPER SHIFT, E, exec, {k} act session.menu"),
            format!("bind = SUPER ALT, L, exec, {k} act session.lock"),
            format!("bindel = , XF86AudioRaiseVolume, exec, {k} act audio.volume.up"),
            format!("bindl = , XF86AudioMute, exec, {k} act audio.mute.toggle"),
        ] {
            assert!(
                text.lines().any(|l| l == line),
                "missing `{line}` in\n{text}"
            );
        }
    }

    #[test]
    fn keys_sway_and_hyprland_write_their_files_and_name_the_include() {
        let t = titles("en");
        for kind in [Kind::Sway, Kind::Hyprland] {
            let dir = tempfile::tempdir().unwrap();
            let doc = run_as(kind, dir.path(), true, defaults(), None, &t);
            assert_eq!(doc["state"], "written", "{doc}");
            assert_eq!(doc["compositor"], kind.name());
            assert_eq!(doc["include"]["present"], false);
            let (file, config) = files(kind);
            assert_eq!(
                doc["file"],
                json!(dir.path().join(file).to_string_lossy()),
                "{doc}"
            );
            assert!(doc["include"]["file"].as_str().unwrap().ends_with(config));
            // Off keeps a stub that binds nothing; the include of it keeps working.
            let off = run_as(kind, dir.path(), false, defaults(), None, &t);
            assert_eq!(off["state"], "off");
            let text = std::fs::read_to_string(dir.path().join(file)).unwrap();
            assert!(
                text.starts_with(HEADER_HASH) && !text.contains("exec"),
                "{text}"
            );
        }
    }

    #[test]
    fn keys_sway_and_hyprland_see_their_include_lines() {
        let dir = tempfile::tempdir().unwrap();
        std::fs::create_dir_all(dir.path().join("sway")).unwrap();
        std::fs::create_dir_all(dir.path().join("hypr")).unwrap();
        let t = titles("en");
        std::fs::write(
            dir.path().join(SWAY_CONFIG),
            "# include kurashi-binds.conf\n",
        )
        .unwrap();
        let doc = run_as(Kind::Sway, dir.path(), true, defaults(), None, &t);
        assert_eq!(
            doc["include"]["present"], false,
            "a commented include counts: {doc}"
        );
        std::fs::write(dir.path().join(SWAY_CONFIG), "include kurashi-binds.conf\n").unwrap();
        let doc = run_as(Kind::Sway, dir.path(), true, defaults(), None, &t);
        assert_eq!(doc["include"]["present"], true, "{doc}");
        // Hyprland: the absolute path it is sourced by.
        let source = format!(
            "source = {}\n",
            dir.path().join(HYPR_FILE).to_string_lossy()
        );
        std::fs::write(dir.path().join(HYPR_CONFIG), &source).unwrap();
        let doc = run_as(Kind::Hyprland, dir.path(), true, defaults(), None, &t);
        assert_eq!(doc["include"]["line"], json!(source.trim_end()), "{doc}");
        assert_eq!(doc["include"]["present"], true, "{doc}");
    }

    #[test]
    fn keys_sway_foreign_file_and_modifiers_it_cannot_name() {
        let dir = tempfile::tempdir().unwrap();
        std::fs::create_dir_all(dir.path().join("sway")).unwrap();
        let copy = "bindsym Mod4+Space exec fuzzel\n";
        std::fs::write(dir.path().join(SWAY_FILE), copy).unwrap();
        let t = titles("en");
        assert_eq!(
            run_as(Kind::Sway, dir.path(), true, defaults(), None, &t)["state"],
            "foreign"
        );
        assert_eq!(
            std::fs::read_to_string(dir.path().join(SWAY_FILE)).unwrap(),
            copy
        );
        // ISO Level 5 has no name in Sway or Hyprland: the bind is left out with the reason.
        let other = tempfile::tempdir().unwrap();
        let doc = run_as(
            Kind::Sway,
            other.path(),
            true,
            with(&[("quick", "ISO_Level5_Shift+A")]),
            None,
            &t,
        );
        assert_eq!(doc["state"], "written", "{doc}");
        assert_eq!(bind_of(&doc, "keys.quick")["state"], "invalid");
        assert_eq!(
            bind_of(&doc, "keys.quick")["reason"],
            "keys.invalid.modifier_here"
        );
        let text = std::fs::read_to_string(other.path().join(SWAY_FILE)).unwrap();
        assert!(!text.contains("quick.toggle"), "{text}");
    }

    #[test]
    fn keys_rendered_file_passes_niri_validate() {
        let Some(niri) = checker(Kind::Niri) else {
            return;
        };
        let dir = tempfile::tempdir().unwrap();
        // Japanese titles: the KDL strings carry non-ASCII, and niri must take them.
        let t = titles("ja");
        let all = with(&[
            ("quick", "Mod+Q"),
            ("settings", "Ctrl+Alt+Comma"),
            ("webdock", "Mod+B"),
        ]);
        let doc = run(dir.path(), true, all, Some(&niri), &t);
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
        run(dir.path(), false, defaults(), Some(&niri), &t);
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
    fn keys_sway_config_validates_the_written_file() {
        let Some(sway) = checker(Kind::Sway) else {
            return;
        };
        let bin = tempfile::tempdir().unwrap();
        let sway = sway_without_display(&sway, bin.path());
        let dir = tempfile::tempdir().unwrap();
        let t = titles("en");
        let all = with(&[("quick", "Mod+Q"), ("settings", "Ctrl+Alt+Comma")]);
        let doc = run_as(Kind::Sway, dir.path(), true, all, Some(&sway), &t);
        assert_eq!(doc["state"], "written", "{doc}");
        assert_eq!(doc["checked"], true, "{doc}");
        // Sway's own parser, as a config of its own, accepts the file.
        let file = dir.path().join(SWAY_FILE);
        let verdict = check(Kind::Sway, &sway, &std::fs::read_to_string(&file).unwrap());
        assert!(matches!(verdict, Some(Ok(()))), "{verdict:?}");
    }

    #[test]
    fn keys_sway_refused_key_is_left_out_and_says_so() {
        let Some(sway) = checker(Kind::Sway) else {
            return;
        };
        let bin = tempfile::tempdir().unwrap();
        let sway = sway_without_display(&sway, bin.path());
        let dir = tempfile::tempdir().unwrap();
        let t = titles("en");
        let doc = run_as(
            Kind::Sway,
            dir.path(),
            true,
            with(&[("quick", "Mod+WheelScrollDown")]),
            Some(&sway),
            &t,
        );
        assert_eq!(doc["state"], "written", "{doc}");
        assert_eq!(bind_of(&doc, "keys.quick")["state"], "invalid");
        assert_eq!(bind_of(&doc, "keys.quick")["reason"], "keys.invalid.sway");
        let text = std::fs::read_to_string(dir.path().join(SWAY_FILE)).unwrap();
        assert!(
            !text.contains("WheelScroll") && text.contains("launcher.toggle"),
            "{text}"
        );
    }

    #[test]
    fn keys_hyprland_config_verifies_the_written_file() {
        let Some(hypr) = checker(Kind::Hyprland) else {
            return;
        };
        let dir = tempfile::tempdir().unwrap();
        let t = titles("en");
        let doc = run_as(
            Kind::Hyprland,
            dir.path(),
            true,
            defaults(),
            Some(&hypr),
            &t,
        );
        assert_eq!(doc["state"], "written", "{doc}");
        assert_eq!(doc["checked"], true, "{doc}");
        let file = dir.path().join(HYPR_FILE);
        let verdict = check(
            Kind::Hyprland,
            &hypr,
            &std::fs::read_to_string(&file).unwrap(),
        );
        assert!(matches!(verdict, Some(Ok(()))), "{verdict:?}");
    }

    #[test]
    fn keys_niri_refusing_a_key_leaves_it_out_and_says_so() {
        let Some(niri) = checker(Kind::Niri) else {
            return;
        };
        let dir = tempfile::tempdir().unwrap();
        let t = titles("en");
        let doc = run(
            dir.path(),
            true,
            with(&[("quick", "Mod+XF86Bogus")]),
            Some(&niri),
            &t,
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

    #[test]
    fn keys_the_refusals_name_their_key_and_the_strings_exist() {
        assert_eq!(
            refused_key(
                Kind::Sway,
                "x Unknown key or button 'WheelScrollDown' (file)"
            ),
            Some("WheelScrollDown".into())
        );
        assert_eq!(refused_key(Kind::Hyprland, "Invalid mod: FOO"), None);
        assert_eq!(
            refused_key(Kind::Niri, "error: invalid key: Bogus\n"),
            Some("Bogus".into())
        );
        assert_eq!(kdl_string("a\"b\\c"), "\"a\\\"b\\\\c\"");
        assert_eq!(sh_quote("it's"), "'it'\\''s'");
        assert_eq!(strip_ansi("\u{1b}[1;31mERR\u{1b}[0m x"), "ERR x");
        // Every reason and message the code names is shipped in both locales.
        let reasons = [
            "keys.invalid.syntax",
            "keys.invalid.modifier",
            "keys.invalid.key",
            "keys.invalid.only_modifiers",
            "keys.invalid.needs_modifier",
            "keys.invalid.niri",
            "keys.invalid.sway",
            "keys.invalid.hyprland",
            "keys.invalid.modifier_here",
            "keys.conflict.taken",
            "keys.error.write_failed",
            "keys.error.refused",
            OVERLAY_TITLE,
        ];
        for locale in ["en", "ja"] {
            let strings = strings_of(locale);
            for key in reasons {
                assert!(strings.contains_key(key), "no {locale} string for {key}");
            }
        }
    }
}
