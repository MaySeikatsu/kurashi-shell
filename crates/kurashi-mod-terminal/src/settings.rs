//! The mod's settings as the model reads them (`mods.terminal.*`, mods/terminal/mod.toml). Every key has the manifest's
//! default here too, so a feed that lacks a key (a test, an older config) reads as the manifest says.

use std::collections::BTreeMap;

use kurashi_mod_api::Settings;
use serde_json::Value;

/// The keys whose provenance the document carries (`forced`), so a control the configuration forces is drawn inert.
pub const KEYS: &[&str] = &[
    "shell",
    "start_dir",
    "favourites",
    "font",
    "font_size",
    "opacity",
    "scrollback",
    "place",
    "edge",
    "length",
    "width",
    "height",
    "anchor",
    "offset_x",
    "offset_y",
    "sizes",
    "pinned",
    "hide_on_blur",
    "bar_mode",
    "input_target",
    "run_in",
    "dir_opens",
    "run_prefix",
];

/// The launcher's own query prefixes (`:` emoji, `;` clipboard, `?` keys, `>` the shell's commands; kurashid's launcher
/// query). A local stand-in until the launcher publishes them from its one place (CONTRACT-CHANGE, W83 row): then this
/// list is read from there and never kept by hand.
pub const LAUNCHER_PREFIXES: &[&str] = &[":", ";", "?", ">"];

/// A favourite directory (records `favourites`).
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Favourite {
    pub path: String,
    pub label: String,
}

#[derive(Debug, Clone, PartialEq)]
pub struct Cfg {
    pub shell: String,
    pub start_dir: String,
    pub favourites: Vec<Favourite>,
    pub font: String,
    pub font_size: i64,
    pub opacity: i64,
    pub scrollback: i64,
    pub place: String,
    pub edge: String,
    pub length: i64,
    pub width: i64,
    pub height: i64,
    pub anchor: String,
    pub offset_x: i64,
    pub offset_y: i64,
    /// The height the user dragged, per output (records `sizes`: `{output, height}`), in % of the output.
    pub sizes: BTreeMap<String, i64>,
    pub pinned: bool,
    pub hide_on_blur: bool,
    pub bar_mode: String,
    pub input_target: String,
    pub run_in: String,
    pub dir_opens: String,
    pub run_prefix: String,
}

impl Default for Cfg {
    fn default() -> Self {
        Self {
            shell: String::new(),
            start_dir: "~".into(),
            favourites: Vec::new(),
            font: String::new(),
            font_size: 13,
            opacity: 60,
            scrollback: 10_000,
            place: "bar".into(),
            edge: "top".into(),
            length: 100,
            width: 60,
            height: 45,
            anchor: "top-left".into(),
            offset_x: 0,
            offset_y: 0,
            sizes: BTreeMap::new(),
            pinned: false,
            hide_on_blur: false,
            bar_mode: "icon".into(),
            input_target: "show".into(),
            run_in: "current".into(),
            dir_opens: "new".into(),
            run_prefix: "$".into(),
        }
    }
}

fn s(settings: &Settings, key: &str, dflt: &str) -> String {
    settings
        .get(key)
        .and_then(|v| v.as_str().map(str::to_string))
        .unwrap_or_else(|| dflt.to_string())
}

fn i(settings: &Settings, key: &str, dflt: i64) -> i64 {
    settings.get(key).and_then(|v| v.as_i64()).unwrap_or(dflt)
}

fn b(settings: &Settings, key: &str, dflt: bool) -> bool {
    settings.get(key).and_then(|v| v.as_bool()).unwrap_or(dflt)
}

impl Cfg {
    pub fn read(settings: &Settings) -> Self {
        let d = Cfg::default();
        Self {
            shell: s(settings, "shell", &d.shell),
            start_dir: s(settings, "start_dir", &d.start_dir),
            favourites: favourites_of(settings.get("favourites").as_ref()),
            font: s(settings, "font", &d.font),
            font_size: i(settings, "font_size", d.font_size),
            opacity: i(settings, "opacity", d.opacity),
            scrollback: i(settings, "scrollback", d.scrollback),
            place: s(settings, "place", &d.place),
            edge: s(settings, "edge", &d.edge),
            length: i(settings, "length", d.length),
            width: i(settings, "width", d.width),
            height: i(settings, "height", d.height),
            anchor: s(settings, "anchor", &d.anchor),
            offset_x: i(settings, "offset_x", d.offset_x),
            offset_y: i(settings, "offset_y", d.offset_y),
            sizes: sizes_of(settings.get("sizes").as_ref()),
            pinned: b(settings, "pinned", d.pinned),
            hide_on_blur: b(settings, "hide_on_blur", d.hide_on_blur),
            bar_mode: s(settings, "bar_mode", &d.bar_mode),
            input_target: s(settings, "input_target", &d.input_target),
            run_in: s(settings, "run_in", &d.run_in),
            dir_opens: s(settings, "dir_opens", &d.dir_opens),
            run_prefix: s(settings, "run_prefix", &d.run_prefix),
        }
    }

    /// Why `run_prefix` is not in effect, or `None`: empty or blank, or one the launcher uses itself. The prefix in
    /// effect is then the default (Shōjiki: the document says both, the value set and why it is not the one used).
    pub fn prefix_problem(&self) -> Option<&'static str> {
        let p = self.run_prefix.trim();
        if p.is_empty() || p.chars().any(char::is_whitespace) {
            return Some("terminal.error.prefix_blank");
        }
        if LAUNCHER_PREFIXES
            .iter()
            .any(|t| p.starts_with(t) || t.starts_with(p))
        {
            return Some("terminal.error.prefix_taken");
        }
        None
    }

    pub fn prefix_in_effect(&self) -> String {
        if self.prefix_problem().is_some() {
            Cfg::default().run_prefix
        } else {
            self.run_prefix.trim().to_string()
        }
    }
}

fn favourites_of(v: Option<&Value>) -> Vec<Favourite> {
    let Some(rows) = v.and_then(Value::as_array) else {
        return Vec::new();
    };
    rows.iter()
        .filter_map(|r| {
            let path = r["path"].as_str().filter(|p| !p.trim().is_empty())?;
            Some(Favourite {
                path: path.to_string(),
                label: r["label"].as_str().unwrap_or("").to_string(),
            })
        })
        .collect()
}

fn sizes_of(v: Option<&Value>) -> BTreeMap<String, i64> {
    let Some(rows) = v.and_then(Value::as_array) else {
        return BTreeMap::new();
    };
    rows.iter()
        .filter_map(|r| Some((r["output"].as_str()?.to_string(), r["height"].as_i64()?)))
        .collect()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn prefix_refused_when_blank_or_taken() {
        let mut c = Cfg::default();
        assert_eq!(c.prefix_problem(), None);
        c.run_prefix = " ".into();
        assert_eq!(c.prefix_problem(), Some("terminal.error.prefix_blank"));
        c.run_prefix = ">".into();
        assert_eq!(c.prefix_problem(), Some("terminal.error.prefix_taken"));
        // (a prefix that begins with one of the launcher's would never reach the terminal)
        c.run_prefix = ">>".into();
        assert_eq!(c.prefix_problem(), Some("terminal.error.prefix_taken"));
        assert_eq!(c.prefix_in_effect(), "$");
        c.run_prefix = "!".into();
        assert_eq!(c.prefix_in_effect(), "!");
    }
}
