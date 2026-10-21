//! The keybind cheat sheet (`?`, W26): the compositor's binds read from niri's config and its includes, grouped and
//! labelled, plus kurashi's own pointer bindings (the daemon adds those). Read-only: the rows carry no id to launch.
//!
//! Modelled on DankMaterialShell's niri provider (`core/internal/keybinds/providers/niri_parser.go`, `niri.go`): the
//! files are walked from `config.kdl` through every `include` (relative to the including file, each file once), `binds`
//! and `recent-windows { binds }` are read, a later bind for the same key replaces an earlier one in its first place,
//! `hotkey-overlay-title` labels a bind and `hotkey-overlay-title=null` hides it (niri's own overlay rule), and the group
//! comes from the action (DMS `categorizeByAction`, plus kurashi's `spawn "kurashi" "act" …` as the shell's own group).
//! The parser is a small KDL reader of our own (v1 and v2 spellings): no new dependency for one config shape.

use std::collections::HashSet;
use std::path::{Path, PathBuf};
use std::sync::Mutex;
use std::time::SystemTime;

use serde_json::{Value, json};

/// One KDL node: name, positional values, properties, children.
#[derive(Debug, Default, Clone, PartialEq)]
pub struct Node {
    pub name: String,
    pub args: Vec<String>,
    pub props: Vec<(String, String)>,
    pub children: Vec<Node>,
}

impl Node {
    fn prop(&self, key: &str) -> Option<&str> {
        self.props
            .iter()
            .rev()
            .find(|(k, _)| k == key)
            .map(|(_, v)| v.as_str())
    }
}

#[derive(Debug, Clone, PartialEq)]
enum Tok {
    Word(String),
    Str(String),
    Open,
    Close,
    End,
    Eq,
    SlashDash,
}

fn lex(src: &str) -> Vec<Tok> {
    let s: Vec<char> = src.chars().collect();
    let n = s.len();
    let mut out = Vec::new();
    let mut i = 0;
    while i < n {
        let c = s[i];
        let next = s.get(i + 1).copied();
        match c {
            '\n' | ';' => {
                out.push(Tok::End);
                i += 1;
            }
            c if c.is_whitespace() || c == '\u{feff}' => i += 1,
            '/' if next == Some('/') => {
                while i < n && s[i] != '\n' {
                    i += 1;
                }
            }
            '/' if next == Some('*') => {
                let mut depth = 1;
                i += 2;
                while i < n && depth > 0 {
                    if s[i] == '/' && s.get(i + 1) == Some(&'*') {
                        depth += 1;
                        i += 2;
                    } else if s[i] == '*' && s.get(i + 1) == Some(&'/') {
                        depth -= 1;
                        i += 2;
                    } else {
                        i += 1;
                    }
                }
            }
            '/' if next == Some('-') => {
                out.push(Tok::SlashDash);
                i += 2;
            }
            // A line continuation: the node goes on on the next line.
            '\\' => {
                i += 1;
                while i < n && s[i] != '\n' {
                    if s[i] == '/' && s.get(i + 1) == Some(&'/') {
                        while i < n && s[i] != '\n' {
                            i += 1;
                        }
                        break;
                    }
                    i += 1;
                }
                i += 1;
            }
            '{' => {
                out.push(Tok::Open);
                i += 1;
            }
            '}' => {
                out.push(Tok::Close);
                i += 1;
            }
            '=' => {
                out.push(Tok::Eq);
                i += 1;
            }
            // A type annotation, `(u8)10`: dropped.
            '(' => {
                while i < n && s[i] != ')' {
                    i += 1;
                }
                i += 1;
            }
            '"' => {
                let (text, end) = quoted(&s, i + 1);
                out.push(Tok::Str(text));
                i = end;
            }
            // Raw strings: `r#"…"#` (KDL v1) and `#"…"#` (v2).
            'r' | '#' if raw_start(&s, if c == 'r' { i + 1 } else { i }).is_some() => {
                let from = if c == 'r' { i + 1 } else { i };
                let hashes = raw_start(&s, from).unwrap_or(0);
                let body = from + hashes + 1;
                let mut j = body;
                let close: Vec<char> = std::iter::once('"')
                    .chain(std::iter::repeat_n('#', hashes))
                    .collect();
                while j < n && s[j..].iter().take(close.len()).ne(close.iter()) {
                    j += 1;
                }
                out.push(Tok::Str(s[body..j.min(n)].iter().collect()));
                i = (j + close.len()).min(n);
            }
            _ => {
                let start = i;
                while i < n {
                    let c = s[i];
                    let nx = s.get(i + 1).copied();
                    if c.is_whitespace()
                        || matches!(c, '{' | '}' | ';' | '=' | '"' | '(' | ')' | '\\')
                        || (c == '/' && matches!(nx, Some('/' | '*' | '-')))
                    {
                        break;
                    }
                    i += 1;
                }
                let w: String = s[start..i].iter().collect();
                // KDL v2 keywords: `#true`, `#false`, `#null`.
                let w = w.strip_prefix('#').map(str::to_owned).unwrap_or(w);
                out.push(Tok::Word(w));
            }
        }
    }
    out
}

/// The number of `#` before the opening quote of a raw string starting at `i`, if one starts there.
fn raw_start(s: &[char], i: usize) -> Option<usize> {
    let mut j = i;
    while s.get(j) == Some(&'#') {
        j += 1;
    }
    (s.get(j) == Some(&'"') && (j > i || s.get(i.wrapping_sub(1)) == Some(&'r'))).then_some(j - i)
}

/// A quoted string's text from `i` (after the opening quote) and the index after its closing quote.
fn quoted(s: &[char], mut i: usize) -> (String, usize) {
    let mut out = String::new();
    while i < s.len() {
        match s[i] {
            '"' => return (out, i + 1),
            '\\' => {
                i += 1;
                match s.get(i) {
                    Some('n') => out.push('\n'),
                    Some('t') => out.push('\t'),
                    Some('r') => out.push('\r'),
                    Some('u') if s.get(i + 1) == Some(&'{') => {
                        let hex: String = s[i + 2..].iter().take_while(|c| **c != '}').collect();
                        if let Some(ch) =
                            u32::from_str_radix(&hex, 16).ok().and_then(char::from_u32)
                        {
                            out.push(ch);
                        }
                        i += hex.chars().count() + 2;
                    }
                    // A whitespace escape (v2) swallows the whitespace.
                    Some(c) if c.is_whitespace() => {
                        while s.get(i).is_some_and(|c| c.is_whitespace()) {
                            i += 1;
                        }
                        continue;
                    }
                    Some(c) => out.push(*c),
                    None => {}
                }
                i += 1;
            }
            c => {
                out.push(c);
                i += 1;
            }
        }
    }
    (out, i)
}

/// Parses KDL text into its top-level nodes. Never fails: what it cannot read it skips (a cheat sheet shows what it
/// understood rather than nothing).
pub fn parse(src: &str) -> Vec<Node> {
    let toks = lex(src);
    let mut at = 0;
    nodes(&toks, &mut at, false)
}

fn nodes(t: &[Tok], at: &mut usize, nested: bool) -> Vec<Node> {
    let mut out = Vec::new();
    while let Some(tok) = t.get(*at) {
        match tok {
            Tok::End | Tok::Eq => *at += 1,
            Tok::Close => {
                *at += 1;
                if nested {
                    return out;
                }
            }
            Tok::SlashDash => {
                *at += 1;
                let _ = node(t, at);
            }
            Tok::Open => {
                *at += 1;
                let _ = nodes(t, at, true);
            }
            Tok::Word(_) | Tok::Str(_) => out.push(node(t, at)),
        }
    }
    out
}

fn value(tok: Option<&Tok>) -> Option<String> {
    match tok {
        Some(Tok::Word(w)) | Some(Tok::Str(w)) => Some(w.clone()),
        _ => None,
    }
}

fn node(t: &[Tok], at: &mut usize) -> Node {
    let mut n = Node {
        name: value(t.get(*at)).unwrap_or_default(),
        ..Node::default()
    };
    *at += 1;
    while let Some(tok) = t.get(*at) {
        match tok {
            Tok::End => {
                *at += 1;
                break;
            }
            Tok::Close => break,
            Tok::Eq => *at += 1,
            Tok::SlashDash => {
                *at += 1;
                match t.get(*at) {
                    Some(Tok::Open) => {
                        *at += 1;
                        let _ = nodes(t, at, true);
                    }
                    Some(Tok::Word(_) | Tok::Str(_)) => {
                        *at += 1;
                        if t.get(*at) == Some(&Tok::Eq) {
                            *at += 2;
                        }
                    }
                    _ => {}
                }
            }
            Tok::Open => {
                *at += 1;
                n.children.extend(nodes(t, at, true));
                // A children block ends the node.
                break;
            }
            Tok::Word(w) | Tok::Str(w) => {
                *at += 1;
                if t.get(*at) == Some(&Tok::Eq) {
                    *at += 1;
                    let v = value(t.get(*at)).unwrap_or_default();
                    *at += 1;
                    n.props.push((w.clone(), v));
                } else {
                    n.args.push(w.clone());
                }
            }
        }
    }
    n
}

/// One compositor bind as written.
#[derive(Debug, Clone, PartialEq)]
pub struct Bind {
    /// The key as written, e.g. `Mod+Shift+E`.
    pub combo: String,
    pub action: String,
    pub args: Vec<String>,
    /// `hotkey-overlay-title`, when the user named it.
    pub title: Option<String>,
    /// `hotkey-overlay-title=null`: niri leaves it out of its overlay, and so do we.
    pub hidden: bool,
    /// From `recent-windows { binds { … } }` (the Alt-Tab switcher).
    pub switcher: bool,
}

/// What the niri config holds: its binds in order, the mod key, the files read (for the change check).
#[derive(Debug, Clone, Default, PartialEq)]
pub struct NiriBinds {
    pub config: PathBuf,
    /// Whether `config` exists. Without it niri runs on its built-in defaults, which are not listed.
    pub found: bool,
    pub binds: Vec<Bind>,
    /// `input { mod-key "…" }`; niri's default is Super.
    pub mod_key: Option<String>,
    pub files: Vec<PathBuf>,
    /// Includes that point at no file.
    pub missing: Vec<PathBuf>,
}

/// niri's config file: `$NIRI_CONFIG`, else `$XDG_CONFIG_HOME/niri/config.kdl`, else `~/.config/niri/config.kdl`.
pub fn niri_config_path() -> PathBuf {
    if let Some(p) = std::env::var_os("NIRI_CONFIG").filter(|v| !v.is_empty()) {
        return PathBuf::from(p);
    }
    let base = std::env::var_os("XDG_CONFIG_HOME")
        .filter(|v| !v.is_empty())
        .map(PathBuf::from)
        .unwrap_or_else(|| {
            PathBuf::from(std::env::var_os("HOME").unwrap_or_default()).join(".config")
        });
    base.join("niri").join("config.kdl")
}

fn expand(path: &str, base: &Path) -> PathBuf {
    if let Some(rest) = path.strip_prefix("~/") {
        return PathBuf::from(std::env::var_os("HOME").unwrap_or_default()).join(rest);
    }
    let p = PathBuf::from(path);
    if p.is_absolute() { p } else { base.join(p) }
}

/// Reads `config` and every file it includes.
pub fn read_niri(config: &Path) -> NiriBinds {
    let mut out = NiriBinds {
        config: config.to_path_buf(),
        found: config.is_file(),
        ..NiriBinds::default()
    };
    let mut seen = HashSet::new();
    let mut order: Vec<String> = Vec::new();
    let mut by_key: std::collections::HashMap<String, Bind> = std::collections::HashMap::new();
    if out.found {
        walk(config, &mut out, &mut seen, &mut |b: Bind| {
            let k = b.combo.to_lowercase();
            if !by_key.contains_key(&k) {
                order.push(k.clone());
            }
            by_key.insert(k, b);
        });
    }
    out.binds = order
        .into_iter()
        .filter_map(|k| by_key.remove(&k))
        .collect();
    out
}

fn walk(path: &Path, out: &mut NiriBinds, seen: &mut HashSet<PathBuf>, add: &mut dyn FnMut(Bind)) {
    let key = std::fs::canonicalize(path).unwrap_or_else(|_| path.to_path_buf());
    if !seen.insert(key) {
        return;
    }
    let Ok(text) = std::fs::read_to_string(path) else {
        out.missing.push(path.to_path_buf());
        return;
    };
    out.files.push(path.to_path_buf());
    let base = path.parent().unwrap_or(Path::new("."));
    for n in parse(&text) {
        match n.name.as_str() {
            "include" => {
                if let Some(p) = n.args.first() {
                    let inc = expand(p, base);
                    if inc.is_file() {
                        walk(&inc, out, seen, add);
                    } else if n.prop("optional") != Some("true") {
                        out.missing.push(inc);
                    }
                }
            }
            "input" => {
                if let Some(m) = n.children.iter().find(|c| c.name == "mod-key")
                    && let Some(v) = m.args.first()
                {
                    out.mod_key = Some(v.clone());
                }
            }
            "binds" => n
                .children
                .iter()
                .filter_map(|c| bind(c, false))
                .for_each(&mut *add),
            "recent-windows" => n
                .children
                .iter()
                .filter(|c| c.name == "binds")
                .flat_map(|b| b.children.iter())
                .filter_map(|c| bind(c, true))
                .for_each(&mut *add),
            _ => {}
        }
    }
}

fn bind(n: &Node, switcher: bool) -> Option<Bind> {
    let action = n.children.first()?;
    if n.name.is_empty() {
        return None;
    }
    let title = n.prop("hotkey-overlay-title");
    Some(Bind {
        combo: n.name.clone(),
        action: action.name.clone(),
        args: action.args.clone(),
        title: title
            .filter(|t| *t != "null" && !t.is_empty())
            .map(str::to_owned),
        hidden: title == Some("null"),
        switcher,
    })
}

/// The kurashi action a bind runs: `spawn "kurashi" "act" "<id>"` (or a store path ending in `/kurashi`), or the
/// same as one `spawn-sh` string.
pub fn kurashi_action(b: &Bind) -> Option<String> {
    let words: Vec<String> = match b.action.as_str() {
        "spawn" => b.args.clone(),
        "spawn-sh" => b
            .args
            .first()?
            .split_whitespace()
            .map(|w| w.trim_matches(['"', '\'']).to_owned())
            .collect(),
        _ => return None,
    };
    let bin = words.first()?;
    if Path::new(bin).file_name()? == "kurashi" && words.get(1).map(String::as_str) == Some("act") {
        words.get(2).cloned()
    } else {
        None
    }
}

fn media_key(key: &str) -> bool {
    let k = key.to_ascii_lowercase();
    k.starts_with("xf86audio")
        || k.starts_with("xf86monbrightness")
        || k.starts_with("xf86kbdbrightness")
}

/// The cheat sheet's group of a bind (DMS `categorizeByAction`, regrouped for the shell): one of `shell`, `apps`,
/// `windows`, `workspaces`, `monitors`, `media`, `screenshot`, `system`, `other`.
pub fn group(b: &Bind) -> &'static str {
    let a = b.action.as_str();
    let key = b.combo.rsplit('+').next().unwrap_or("");
    if kurashi_action(b).is_some() {
        return "shell";
    }
    let spawned = match a {
        "spawn" => b.args.first().map(|p| {
            Path::new(p)
                .file_name()
                .map(|f| f.to_string_lossy().into_owned())
                .unwrap_or_default()
        }),
        "spawn-sh" => b
            .args
            .first()
            .and_then(|s| s.split_whitespace().next())
            .map(str::to_owned),
        _ => None,
    };
    let media_tool = spawned.as_deref().is_some_and(|t| {
        matches!(
            t,
            "wpctl"
                | "pactl"
                | "pamixer"
                | "playerctl"
                | "brightnessctl"
                | "swayosd-client"
                | "light"
        )
    });
    if media_key(key) || media_tool {
        return "media";
    }
    if b.switcher || a == "next-window" || a == "previous-window" || a == "toggle-overview" {
        return "windows";
    }
    if a.contains("screenshot") {
        return "screenshot";
    }
    if matches!(
        a,
        "quit"
            | "power-off-monitors"
            | "power-on-monitors"
            | "suspend"
            | "do-screen-transition"
            | "toggle-keyboard-shortcuts-inhibit"
            | "toggle-touchpad"
            | "show-hotkey-overlay"
            | "switch-layout"
            | "load-config-file"
            | "toggle-debug-tint"
    ) || a.contains("dpms")
    {
        return "system";
    }
    if spawned.is_some() {
        return "apps";
    }
    if a.contains("workspace") {
        return "workspaces";
    }
    if a.starts_with("focus-monitor") || a.contains("-to-monitor") {
        return "monitors";
    }
    if [
        "window",
        "focus",
        "move",
        "swap",
        "resize",
        "column",
        "fullscreen",
        "maximize",
        "consume",
        "expel",
        "center",
        "width",
        "height",
    ]
    .iter()
    .any(|w| a.contains(w))
    {
        return "windows";
    }
    "other"
}

/// The order groups are shown in (the pointer bindings the daemon adds come after the keys).
pub const GROUPS: &[&str] = &[
    "shell",
    "apps",
    "windows",
    "workspaces",
    "monitors",
    "media",
    "screenshot",
    "system",
    "other",
    "pointer",
];

/// One part of a key combo as shown on a keycap: `Mod` becomes the mod key, xkb names their symbols.
pub fn key_cap(part: &str, mod_key: &str) -> String {
    let named = match part {
        "Mod" => mod_key,
        "Super" | "Win" | "Mod4" | "Meta" => "Super",
        "Ctrl" | "Control" | "Primary" => "Ctrl",
        "Alt" | "Mod1" => "Alt",
        "ISO_Level3_Shift" | "Mod5" => "AltGr",
        "Comma" | "comma" => ",",
        "Period" | "period" => ".",
        "Slash" | "slash" => "/",
        "Backslash" | "backslash" => "\\",
        "Minus" | "minus" => "-",
        "Equal" | "equal" => "=",
        "Plus" | "plus" => "+",
        "BracketLeft" | "bracketleft" => "[",
        "BracketRight" | "bracketright" => "]",
        "Semicolon" | "semicolon" => ";",
        "Apostrophe" | "apostrophe" => "'",
        "Grave" | "grave" => "`",
        "Left" => "←",
        "Right" => "→",
        "Up" => "↑",
        "Down" => "↓",
        "Page_Up" | "Prior" => "PgUp",
        "Page_Down" | "Next" => "PgDn",
        "Return" | "KP_Enter" => "Enter",
        "Escape" => "Esc",
        "Print" => "PrtSc",
        "Delete" => "Del",
        "BackSpace" => "⌫",
        "space" | "Space" => "Space",
        "WheelScrollDown" => "Wheel ↓",
        "WheelScrollUp" => "Wheel ↑",
        "WheelScrollLeft" => "Wheel ←",
        "WheelScrollRight" => "Wheel →",
        "TouchpadScrollDown" => "Touchpad ↓",
        "TouchpadScrollUp" => "Touchpad ↑",
        "TouchpadScrollLeft" => "Touchpad ←",
        "TouchpadScrollRight" => "Touchpad →",
        "XF86AudioRaiseVolume" => "Vol +",
        "XF86AudioLowerVolume" => "Vol −",
        "XF86AudioMute" => "Mute",
        "XF86AudioMicMute" => "Mic mute",
        "XF86AudioPlay" => "Play",
        "XF86AudioPause" => "Pause",
        "XF86AudioStop" => "Stop",
        "XF86AudioNext" => "Next",
        "XF86AudioPrev" => "Prev",
        "XF86MonBrightnessUp" => "Bright +",
        "XF86MonBrightnessDown" => "Bright −",
        _ => "",
    };
    if !named.is_empty() {
        return named.to_owned();
    }
    let mut cs = part.chars();
    match (cs.next(), cs.next()) {
        (Some(c), None) => c.to_uppercase().collect(),
        _ => part.trim_start_matches("XF86").to_owned(),
    }
}

/// `focus-column-left` → `Focus column left`.
fn humanize(action: &str) -> String {
    let words = action.replace('-', " ");
    let mut cs = words.chars();
    cs.next()
        .map(|c| c.to_uppercase().chain(cs).collect())
        .unwrap_or_default()
}

/// The text a spawn bind runs, for its label: `foot`, `sh -c "…"` as its command.
fn command_text(b: &Bind) -> String {
    let a = &b.args;
    if b.action == "spawn-sh" {
        return a.join(" ");
    }
    if a.len() >= 3 && matches!(a[0].as_str(), "sh" | "bash") && a[1] == "-c" {
        return a[2..].join(" ");
    }
    a.iter()
        .enumerate()
        .map(|(i, w)| {
            if i == 0 {
                Path::new(w)
                    .file_name()
                    .map_or_else(|| w.clone(), |f| f.to_string_lossy().into_owned())
            } else {
                w.clone()
            }
        })
        .collect::<Vec<_>>()
        .join(" ")
}

/// The raw action as written: `focus-workspace 3`, `spawn foot`.
fn raw(b: &Bind) -> String {
    if b.args.is_empty() {
        b.action.clone()
    } else {
        format!("{} {}", b.action, b.args.join(" "))
    }
}

/// The label of a bind: the user's `hotkey-overlay-title`; a kurashi action's label; a niri action's
/// (`launcher.keys.niri.<action>`, `{}` = its arguments); the command a spawn runs; else the action in words.
/// `tr` answers a translation or None.
pub fn label(b: &Bind, tr: &dyn Fn(&str) -> Option<String>) -> String {
    if let Some(t) = &b.title {
        return t.clone();
    }
    if let Some(id) = kurashi_action(b) {
        return tr(&format!("action.{id}")).unwrap_or(id);
    }
    if b.action == "spawn" || b.action == "spawn-sh" {
        return command_text(b);
    }
    let args = b.args.join(" ");
    match tr(&format!("launcher.keys.niri.{}", b.action)) {
        Some(t) if t.contains("{}") => t.replace("{}", &args),
        Some(t) if args.is_empty() => t,
        Some(t) => format!("{t} {args}"),
        None if args.is_empty() => humanize(&b.action),
        None => format!("{} {args}", humanize(&b.action)),
    }
}

/// Rows for the cheat sheet: a `keygroup` header row per group (name translated), then `key` rows
/// `{name, generic (the raw action), keys: [caps], group}` whose label, keys or action hold every word of `q`. `extra`
/// are rows the caller adds (kurashi's pointer bindings), each with a `group` from [`GROUPS`].
pub fn key_rows(
    nb: &NiriBinds,
    extra: Vec<Value>,
    q: &str,
    tr: &dyn Fn(&str) -> Option<String>,
) -> Vec<Value> {
    let words: Vec<String> = q.split_whitespace().map(str::to_lowercase).collect();
    let mod_key = nb.mod_key.as_deref().unwrap_or("Super");
    let mut rows: Vec<Value> = nb
        .binds
        .iter()
        .filter(|b| !b.hidden)
        .map(|b| {
            let caps: Vec<String> = b
                .combo
                .split('+')
                .filter(|p| !p.is_empty())
                .map(|p| key_cap(p, mod_key))
                .collect();
            json!({"id": "", "kind": "key", "name": label(b, tr), "generic": raw(b), "keys": caps,
                   "group": group(b), "icon": null, "score": 0.0})
        })
        .chain(extra)
        .filter(|r| {
            let hay = format!(
                "{} {} {}",
                r["name"].as_str().unwrap_or(""),
                r["generic"].as_str().unwrap_or(""),
                r["keys"]
                    .as_array()
                    .map(|k| k
                        .iter()
                        .filter_map(Value::as_str)
                        .collect::<Vec<_>>()
                        .join(" "))
                    .unwrap_or_default()
            )
            .to_lowercase();
            words.iter().all(|w| hay.contains(w.as_str()))
        })
        .collect();
    let rank = |r: &Value| {
        GROUPS
            .iter()
            .position(|g| r["group"] == *g)
            .unwrap_or(GROUPS.len())
    };
    rows.sort_by_key(rank); // stable: config order within a group
    let mut out = Vec::with_capacity(rows.len() + GROUPS.len() + 1);
    if !nb.found {
        out.push(
            json!({"id": "", "kind": "note", "name": "launcher.keys.no_config",
                        "arg": nb.config.display().to_string(), "icon": null, "score": 0.0}),
        );
    } else if nb.binds.is_empty() && words.is_empty() {
        out.push(
            json!({"id": "", "kind": "note", "name": "launcher.keys.no_binds",
                        "arg": nb.config.display().to_string(), "icon": null, "score": 0.0}),
        );
    }
    for p in nb.missing.iter().filter(|_| words.is_empty()) {
        out.push(
            json!({"id": "", "kind": "note", "name": "launcher.keys.missing_include",
                        "arg": p.display().to_string(), "icon": null, "score": 0.0}),
        );
    }
    let mut last = String::new();
    for r in rows {
        let g = r["group"].as_str().unwrap_or("other").to_owned();
        if g != last {
            let key = format!("launcher.keys.group.{g}");
            out.push(
                json!({"id": "", "kind": "keygroup", "name": tr(&key).unwrap_or(g.clone()),
                            "group": g, "icon": null, "score": 0.0}),
            );
            last = g;
        }
        out.push(r);
    }
    out
}

/// kurashi's own pointer bindings for the cheat sheet, from the daemon's `bindings` document
/// (`{"<component>": {"<slot>": {action, …}}}`): one `pointer` row per bound slot, its caps the component and the slot
/// (`launcher.keys.component.<first part>`, `launcher.keys.slot.<slot>`), its label the action's.
pub fn pointer_rows(bindings: &Value, tr: &dyn Fn(&str) -> Option<String>) -> Vec<Value> {
    let Some(components) = bindings.as_object() else {
        return Vec::new();
    };
    components
        .iter()
        .flat_map(|(component, slots)| {
            let head = component.split('.').next().unwrap_or(component);
            let comp = tr(&format!("launcher.keys.component.{head}")).unwrap_or_else(|| component.clone());
            slots
                .as_object()
                .into_iter()
                .flatten()
                .filter_map(move |(slot, b)| {
                    let action = b["action"].as_str().filter(|a| !a.is_empty())?;
                    let cap = tr(&format!("launcher.keys.slot.{slot}")).unwrap_or_else(|| slot.clone());
                    Some(json!({"id": "", "kind": "key", "group": "pointer", "icon": null, "score": 0.0,
                                "name": tr(&format!("action.{action}")).unwrap_or_else(|| action.to_owned()),
                                "generic": format!("{component} · {action}"), "keys": [comp.clone(), cap]}))
                })
                .collect::<Vec<_>>()
        })
        .collect()
}

/// The niri binds, re-read only when a file it read changed (the cheat sheet asks on every keystroke).
#[derive(Default)]
pub struct KeysCache {
    last: Mutex<Option<(Stamps, NiriBinds)>>,
}

/// Each file read and its modification time (None: missing).
type Stamps = Vec<(PathBuf, Option<SystemTime>)>;

fn stamp(paths: &[PathBuf]) -> Stamps {
    paths
        .iter()
        .map(|p| {
            (
                p.clone(),
                std::fs::metadata(p).and_then(|m| m.modified()).ok(),
            )
        })
        .collect()
}

impl KeysCache {
    pub fn binds(&self, config: &Path) -> NiriBinds {
        let mut last = self.last.lock().expect("keys cache");
        if let Some((stamps, nb)) = last.as_ref()
            && nb.config == config
            && nb.found == config.is_file()
            && stamp(&stamps.iter().map(|(p, _)| p.clone()).collect::<Vec<_>>()) == *stamps
        {
            return nb.clone();
        }
        let nb = read_niri(config);
        let mut watched = nb.files.clone();
        watched.extend(nb.missing.iter().cloned());
        *last = Some((stamp(&watched), nb.clone()));
        nb
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn kdl_reads_nodes_props_children_and_skips_comments() {
        let n = parse(
            r##"
// a comment
/* block /* nested */ */
binds {
    Mod+T hotkey-overlay-title="Open a Terminal: foot" { spawn "foot"; }
    /-Mod+X { close-window; }
    Mod+Q repeat=false { close-window; }
    Mod+1 { focus-workspace 1; }
    Mod+Shift+S { spawn-sh r#"grim -g "$(slurp)" - | wl-copy"#; }
    Mod+Alt+L allow-when-locked=#true { spawn "a" \
        "b"; }
}
"##,
        );
        assert_eq!(n.len(), 1);
        let b = &n[0].children;
        assert_eq!(b.len(), 5, "{b:#?}");
        assert_eq!(
            b[0].prop("hotkey-overlay-title"),
            Some("Open a Terminal: foot")
        );
        assert_eq!(b[0].children[0].args, vec!["foot"]);
        assert_eq!(b[1].name, "Mod+Q");
        assert_eq!(b[2].children[0].args, vec!["1"]);
        assert_eq!(
            b[3].children[0].args,
            vec![r#"grim -g "$(slurp)" - | wl-copy"#]
        );
        assert_eq!(b[4].prop("allow-when-locked"), Some("true"));
        assert_eq!(b[4].children[0].args, vec!["a", "b"]);
    }

    fn write(dir: &Path, name: &str, text: &str) -> PathBuf {
        let p = dir.join(name);
        std::fs::create_dir_all(p.parent().unwrap()).unwrap();
        std::fs::write(&p, text).unwrap();
        p
    }

    #[test]
    fn niri_binds_follow_includes_and_later_binds_win() {
        let d = tempfile::tempdir().unwrap();
        let cfg = write(
            d.path(),
            "config.kdl",
            r#"
input { mod-key "Alt"; }
binds {
    Mod+Space { spawn "fuzzel"; }
    Mod+Left { focus-column-left; }
    Mod+Shift+Slash { show-hotkey-overlay; }
    Mod+O hotkey-overlay-title=null { toggle-overview; }
}
include "kurashi-binds.kdl"
include "sub/more.kdl"
include "missing.kdl"
include "kurashi-binds.kdl"
"#,
        );
        write(
            d.path(),
            "kurashi-binds.kdl",
            r#"binds {
    Mod+Space repeat=false { spawn "kurashi" "act" "launcher.toggle"; }
    XF86AudioRaiseVolume allow-when-locked=true { spawn "kurashi" "act" "audio.volume.up"; }
}"#,
        );
        write(
            d.path(),
            "sub/more.kdl",
            r#"binds { Mod+3 { move-column-to-workspace 3; } Print { screenshot; } }
recent-windows { binds { Alt+Tab { next-window; } } }
include "../config.kdl""#,
        );
        let nb = read_niri(&cfg);
        assert!(nb.found);
        assert_eq!(nb.mod_key.as_deref(), Some("Alt"));
        assert_eq!(
            nb.files.len(),
            3,
            "each file once, the cycle back to config.kdl is cut"
        );
        assert_eq!(nb.missing, vec![d.path().join("missing.kdl")]);
        let combos: Vec<&str> = nb.binds.iter().map(|b| b.combo.as_str()).collect();
        assert_eq!(
            combos,
            [
                "Mod+Space",
                "Mod+Left",
                "Mod+Shift+Slash",
                "Mod+O",
                "XF86AudioRaiseVolume",
                "Mod+3",
                "Print",
                "Alt+Tab"
            ]
        );
        // The include's bind replaced the config's one in its first place.
        assert_eq!(
            kurashi_action(&nb.binds[0]).as_deref(),
            Some("launcher.toggle")
        );
        let groups: Vec<&str> = nb.binds.iter().map(group).collect();
        assert_eq!(
            groups,
            [
                "shell",
                "windows",
                "system",
                "windows",
                "shell",
                "workspaces",
                "screenshot",
                "windows"
            ]
        );

        let tr = |k: &str| match k {
            "action.launcher.toggle" => Some("Launcher".to_owned()),
            "launcher.keys.niri.move-column-to-workspace" => {
                Some("Move column to workspace {}".to_owned())
            }
            "launcher.keys.group.shell" => Some("Shell".to_owned()),
            _ => None,
        };
        let rows = key_rows(&nb, vec![], "", &tr);
        assert_eq!(rows[0]["kind"], "note");
        assert_eq!(rows[0]["name"], "launcher.keys.missing_include");
        assert_eq!(rows[1]["kind"], "keygroup");
        assert_eq!(rows[1]["name"], "Shell");
        assert_eq!(rows[2]["name"], "Launcher");
        assert_eq!(rows[2]["keys"], json!(["Alt", "Space"]));
        assert!(
            rows.iter().all(|r| r["generic"] != "toggle-overview"),
            "hotkey-overlay-title=null hides a bind"
        );
        let found = key_rows(&nb, vec![], "workspace 3", &tr);
        let hits: Vec<&Value> = found.iter().filter(|r| r["kind"] == "key").collect();
        assert_eq!(hits.len(), 1);
        assert_eq!(hits[0]["name"], "Move column to workspace 3");
        let vol = rows
            .iter()
            .find(|r| {
                r["generic"]
                    .as_str()
                    .unwrap_or("")
                    .contains("audio.volume.up")
            })
            .unwrap();
        assert_eq!(vol["keys"], json!(["Vol +"]));
        assert_eq!(
            vol["name"], "audio.volume.up",
            "an untranslated action shows its id"
        );

        let none = read_niri(&d.path().join("nope.kdl"));
        assert!(!none.found);
        let r = key_rows(
            &none,
            vec![
                json!({"kind":"key","name":"Expand","generic":"island.main","keys":["Click"],"group":"pointer"}),
            ],
            "",
            &tr,
        );
        assert_eq!(r[0]["name"], "launcher.keys.no_config");
        assert_eq!(r[1]["kind"], "keygroup");
        assert_eq!(r[2]["name"], "Expand");
    }

    #[test]
    fn cache_rereads_only_after_a_change() {
        let d = tempfile::tempdir().unwrap();
        let cfg = write(d.path(), "config.kdl", "binds { Mod+A { close-window; } }");
        let c = KeysCache::default();
        assert_eq!(c.binds(&cfg).binds.len(), 1);
        std::thread::sleep(std::time::Duration::from_millis(20));
        std::fs::write(
            &cfg,
            "binds { Mod+A { close-window; } Mod+B { fullscreen-window; } }",
        )
        .unwrap();
        assert_eq!(c.binds(&cfg).binds.len(), 2);
    }

    #[test]
    fn pointer_bindings_become_rows() {
        let doc = json!({"island.main": {"left": {"action": "island.expand", "source": {"kind": "default"}},
                                         "scroll_up": {"action": "island.prev"}}});
        let tr = |k: &str| match k {
            "launcher.keys.component.island" => Some("Island".to_owned()),
            "launcher.keys.slot.left" => Some("Click".to_owned()),
            "action.island.expand" => Some("Expand".to_owned()),
            _ => None,
        };
        let rows = pointer_rows(&doc, &tr);
        assert_eq!(rows.len(), 2);
        let left = rows.iter().find(|r| r["name"] == "Expand").unwrap();
        assert_eq!(left["keys"], json!(["Island", "Click"]));
        assert_eq!(left["group"], "pointer");
        assert!(
            rows.iter()
                .any(|r| r["keys"] == json!(["Island", "scroll_up"]))
        );
        assert!(pointer_rows(&json!(null), &tr).is_empty());
    }

    #[test]
    fn key_caps() {
        assert_eq!(key_cap("Mod", "Super"), "Super");
        assert_eq!(key_cap("q", "Super"), "Q");
        assert_eq!(key_cap("Comma", "Super"), ",");
        assert_eq!(key_cap("XF86AudioMute", "Super"), "Mute");
        assert_eq!(key_cap("XF86Launch1", "Super"), "Launch1");
        assert_eq!(humanize("focus-column-left"), "Focus column left");
    }
}
