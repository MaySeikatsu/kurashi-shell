//! The terminal's state (docs/ux/terminal.md; MODS.md "Terminal"): the tabs (sessions), the places open and the one that
//! shows the terminal, the commands waiting for the host, the history of the bar's field, and the host's state. Pure: the
//! actions change it, `doc()` renders `mod.terminal`, and `wants_host()` says whether the host should run.

use std::collections::{BTreeMap, VecDeque};
use std::path::{Path, PathBuf};

use kurashi_mod_api::HostState;
use serde_json::{Map, Value, json};

use crate::settings::Cfg;

/// The history the bar's field and the launcher's prefix keep (Up/Down), most recent last.
pub const HISTORY: usize = 50;

#[derive(Debug, Clone, Copy, PartialEq, Eq, PartialOrd, Ord)]
pub enum Place {
    Dropdown,
    Card,
    Sidebar,
}

impl Place {
    pub fn parse(s: &str) -> Option<Self> {
        match s {
            "dropdown" => Some(Self::Dropdown),
            "card" => Some(Self::Card),
            "sidebar" => Some(Self::Sidebar),
            _ => None,
        }
    }

    pub fn name(self) -> &'static str {
        match self {
            Self::Dropdown => "dropdown",
            Self::Card => "card",
            Self::Sidebar => "sidebar",
        }
    }
}

/// Where a place's well rests on its output (logical px from the output's top-left corner, zones ignored).
#[derive(Debug, Clone, PartialEq)]
pub struct Rest {
    pub output: String,
    pub x: i64,
    pub y: i64,
    pub width: i64,
    pub height: i64,
}

#[derive(Debug, Clone, PartialEq)]
pub struct Tab {
    pub id: String,
    /// The shell's title (OSC 0/2) or the user's name for the tab.
    pub title: String,
    pub renamed: bool,
    /// Where the session started (absolute).
    pub dir: String,
    /// The host's last report: the working directory and the foreground program ("" while the shell waits).
    pub cwd: String,
    pub program: String,
}

/// A line waiting for the host to type into a tab (the bar's field, the launcher's prefix, a favourite's `cd`).
#[derive(Debug, Clone, PartialEq)]
pub struct Run {
    pub id: u64,
    pub tab: String,
    pub text: String,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Error {
    Argument,
    UnknownTab,
    NoDir(String),
    Crashed,
}

impl Error {
    pub fn key(&self) -> &'static str {
        match self {
            Self::Argument => "terminal.error.argument",
            Self::UnknownTab => "terminal.error.unknown_tab",
            Self::NoDir(_) => "terminal.error.no_dir",
            Self::Crashed => "terminal.error.crashed",
        }
    }
}

#[derive(Debug)]
pub struct Model {
    cfg: Cfg,
    forced: BTreeMap<String, String>,
    home: PathBuf,
    tabs: Vec<Tab>,
    active: Option<String>,
    next_tab: u64,
    /// The drop-down is out, and on which output.
    dropdown: bool,
    dropdown_output: Option<String>,
    /// The places open, the one opened last at the end: it shows the terminal (last opened wins).
    open: Vec<Place>,
    rests: BTreeMap<Place, Rest>,
    runs: Vec<Run>,
    next_run: u64,
    history: VecDeque<String>,
    /// Asks the host to give the keyboard to the shown place (a counter: each ask once).
    focus: u64,
    host: HostState,
    /// The host stopped without being asked: its sessions are gone, and the places say so until a restart.
    crashed: bool,
    /// The model asked the host to stop: its leaving is not a crash.
    stopping: bool,
    /// What the last open-in-a-directory refused (Shōjiki: said in the place, cleared by the next good one).
    notice: Option<(String, String)>,
    /// The pointer is on the host's window (a hover-opened card holds while it is).
    pointer: bool,
}

impl Model {
    pub fn new(cfg: Cfg, home: PathBuf) -> Self {
        Self {
            cfg,
            forced: BTreeMap::new(),
            home,
            tabs: Vec::new(),
            active: None,
            next_tab: 1,
            dropdown: false,
            dropdown_output: None,
            open: Vec::new(),
            rests: BTreeMap::new(),
            runs: Vec::new(),
            next_run: 1,
            history: VecDeque::new(),
            focus: 0,
            host: HostState::Off,
            crashed: false,
            stopping: false,
            notice: None,
            pointer: false,
        }
    }

    pub fn cfg(&self) -> &Cfg {
        &self.cfg
    }

    pub fn set_cfg(&mut self, cfg: Cfg, forced: BTreeMap<String, String>) {
        self.cfg = cfg;
        self.forced = forced;
    }

    // ---- directories ----

    /// `~` and `~/…` against the home; anything else as written. Relative paths are taken from the home too.
    pub fn expand(&self, path: &str) -> PathBuf {
        let p = path.trim();
        if p == "~" || p.is_empty() {
            return self.home.clone();
        }
        if let Some(rest) = p.strip_prefix("~/") {
            return self.home.join(rest);
        }
        let pb = PathBuf::from(p);
        if pb.is_absolute() {
            pb
        } else {
            self.home.join(pb)
        }
    }

    /// The directory a new tab starts in: `start_dir`, or the home when that is not a directory (and the document
    /// says so: `problems.start_dir`).
    fn start_dir(&self) -> String {
        let d = self.expand(&self.cfg.start_dir);
        if d.is_dir() {
            d.to_string_lossy().into_owned()
        } else {
            self.home.to_string_lossy().into_owned()
        }
    }

    fn dir_arg(&self, path: &str) -> Result<String, Error> {
        let d = self.expand(path);
        if d.is_dir() {
            Ok(d.to_string_lossy().into_owned())
        } else {
            Err(Error::NoDir(d.to_string_lossy().into_owned()))
        }
    }

    // ---- tabs ----

    /// A new tab in `dir` (absolute; the start directory when `None`), made the active one. Returns its id.
    pub fn new_tab(&mut self, dir: Option<String>) -> String {
        let id = format!("t{}", self.next_tab);
        self.next_tab += 1;
        let dir = dir.unwrap_or_else(|| self.start_dir());
        self.tabs.push(Tab {
            id: id.clone(),
            title: String::new(),
            renamed: false,
            dir,
            cwd: String::new(),
            program: String::new(),
        });
        self.active = Some(id.clone());
        id
    }

    pub fn new_tab_in(&mut self, path: Option<&str>) -> Result<String, Error> {
        let dir = match path {
            Some(p) => Some(self.dir_arg(p)?),
            None => None,
        };
        self.crashed = false;
        Ok(self.new_tab(dir))
    }

    fn index(&self, tab: &str) -> Result<usize, Error> {
        self.tabs
            .iter()
            .position(|t| t.id == tab)
            .ok_or(Error::UnknownTab)
    }

    /// Closes a tab (the host ends its session when it leaves the document). The active one passes to its neighbour.
    pub fn close_tab(&mut self, tab: &str) -> Result<(), Error> {
        let i = self.index(tab)?;
        self.tabs.remove(i);
        self.runs.retain(|r| r.tab != tab);
        if self.active.as_deref() == Some(tab) {
            self.active = self
                .tabs
                .get(i.min(self.tabs.len().saturating_sub(1)))
                .map(|t| t.id.clone());
        }
        Ok(())
    }

    pub fn select(&mut self, tab: &str) -> Result<(), Error> {
        self.index(tab)?;
        self.active = Some(tab.to_string());
        Ok(())
    }

    /// Steps the active tab by `by` (wrapping), as Ctrl+PageUp/PageDown.
    pub fn step(&mut self, by: i64) {
        let n = self.tabs.len() as i64;
        if n == 0 {
            return;
        }
        let at = self
            .active
            .as_deref()
            .and_then(|a| self.tabs.iter().position(|t| t.id == a))
            .unwrap_or(0) as i64;
        let to = (at + by).rem_euclid(n) as usize;
        self.active = Some(self.tabs[to].id.clone());
    }

    /// The user's name for a tab; an empty one gives the tab back to the shell's title.
    pub fn rename(&mut self, tab: &str, title: &str) -> Result<(), Error> {
        let i = self.index(tab)?;
        let t = &mut self.tabs[i];
        let title = title.trim();
        t.renamed = !title.is_empty();
        t.title = title.to_string();
        Ok(())
    }

    /// Moves a tab to index `to` (clamped).
    pub fn move_tab(&mut self, tab: &str, to: i64) -> Result<(), Error> {
        let i = self.index(tab)?;
        let t = self.tabs.remove(i);
        let to = to.clamp(0, self.tabs.len() as i64) as usize;
        self.tabs.insert(to, t);
        Ok(())
    }

    // ---- the host's reports ----

    pub fn host_title(&mut self, tab: &str, title: Option<&str>, cwd: Option<&str>, program: Option<&str>) {
        if let Some(t) = self.tabs.iter_mut().find(|t| t.id == tab) {
            if let (Some(title), false) = (title, t.renamed) {
                t.title = title.to_string();
            }
            if let Some(c) = cwd {
                t.cwd = c.to_string();
            }
            if let Some(p) = program {
                t.program = p.to_string();
            }
        }
    }

    /// The shell of `tab` exited: the tab closes (Yakuake, Guake). Unknown tabs are ignored (it was closed first).
    pub fn host_exited(&mut self, tab: &str) {
        let _ = self.close_tab(tab);
    }

    pub fn host_ran(&mut self, run: u64) {
        self.runs.retain(|r| r.id != run);
    }

    /// The host's state moved. Leaving `ready` (or `starting`) for anything without the model having asked is a crash:
    /// the sessions died with the process, so the tabs go and the places say so until `restart`.
    /// Returns true when the host should be stopped now (the daemon's own restart of it would make new shells silently).
    pub fn set_host(&mut self, state: HostState) -> bool {
        let was_running = matches!(self.host, HostState::Ready);
        let mut stop = false;
        let lost = match &state {
            HostState::Off => !self.stopping,
            HostState::Failed { .. } => true,
            // The daemon restarted it after an exit we did not ask for.
            HostState::Starting => true,
            HostState::Ready | HostState::Missing => false,
        };
        if was_running && lost && !self.stopping {
            self.crashed = true;
            self.tabs.clear();
            self.active = None;
            self.runs.clear();
            stop = !matches!(state, HostState::Off);
            self.stopping = stop;
        }
        if matches!(state, HostState::Off | HostState::Missing) {
            self.stopping = false;
        }
        self.host = state;
        stop
    }

    pub fn host_state(&self) -> &HostState {
        &self.host
    }

    /// Whether the host should run: a session exists, or a place is open to show one — never while it crashed (a press
    /// on the place restarts it).
    pub fn wants_host(&self) -> bool {
        !self.crashed && (!self.tabs.is_empty() || !self.open.is_empty())
    }

    /// The model asks the host to stop (nothing to show, nothing running).
    pub fn note_stopping(&mut self) {
        self.stopping = true;
    }

    /// A press on "restart": the next start makes a new session.
    pub fn restart(&mut self) {
        self.crashed = false;
        self.stopping = false;
        if self.tabs.is_empty() {
            self.new_tab(None);
        }
    }

    // ---- places ----

    fn raise(&mut self, p: Place) {
        self.open.retain(|q| *q != p);
        self.open.push(p);
    }

    fn ensure_tab(&mut self) {
        if self.tabs.is_empty() && !self.crashed {
            self.new_tab(None);
        }
    }

    pub fn shown_in(&self) -> Option<Place> {
        self.open.last().copied()
    }

    pub fn dropdown_open(&self) -> bool {
        self.dropdown
    }

    /// Out on `output` (the drop-down moves there when it is out elsewhere), with the keyboard.
    pub fn show(&mut self, output: Option<&str>) {
        self.dropdown = true;
        if let Some(o) = output {
            if self.dropdown_output.as_deref() != Some(o) {
                self.rests.remove(&Place::Dropdown);
            }
            self.dropdown_output = Some(o.to_string());
        }
        self.raise(Place::Dropdown);
        self.ensure_tab();
        self.focus += 1;
    }

    pub fn hide(&mut self) {
        self.dropdown = false;
        self.open.retain(|q| *q != Place::Dropdown);
        self.rests.remove(&Place::Dropdown);
    }

    /// Out → hidden; hidden (or out on another output) → out here.
    pub fn toggle(&mut self, output: Option<&str>) {
        let here = output.is_none() || self.dropdown_output.as_deref() == output;
        if self.dropdown && here {
            self.hide();
        } else {
            self.show(output);
        }
    }

    /// The drop-down's window lost the keyboard: it hides when `hide_on_blur` is on and it is not pinned.
    pub fn blur(&mut self) {
        if self.dropdown && self.cfg.hide_on_blur && !self.cfg.pinned {
            self.hide();
        }
    }

    /// A place's report (`terminal.place`): `rest` where its well rests now, or `None` while it moves; `closed` when it
    /// went away. `fresh` (its first rest after opening) makes it the one that shows the terminal.
    pub fn place(&mut self, p: Place, rest: Option<Rest>, closed: bool, fresh: bool) {
        if closed {
            self.open.retain(|q| *q != p);
            self.rests.remove(&p);
            if p == Place::Dropdown {
                self.dropdown = false;
            }
            return;
        }
        match rest {
            Some(r) => {
                self.rests.insert(p, r);
            }
            None => {
                self.rests.remove(&p);
            }
        }
        if fresh || !self.open.contains(&p) {
            self.raise(p);
            self.ensure_tab();
        }
    }

    /// "Show it here" in a place that shows where the terminal is instead: it becomes the place that shows it.
    pub fn bring(&mut self, p: Place) {
        if self.open.contains(&p) {
            self.raise(p);
            self.focus += 1;
        }
    }

    pub fn set_pointer(&mut self, on: bool) {
        self.pointer = on;
    }

    // ---- running lines ----

    /// Types `text` + Enter into the active tab, or a new one (`new`, or none open). Returns the tab.
    pub fn run(&mut self, text: &str, new_tab: bool) -> Result<String, Error> {
        let text = text.trim_end_matches(['\n', '\r']);
        if text.trim().is_empty() {
            return Err(Error::Argument);
        }
        self.crashed = false;
        let tab = match (&self.active, new_tab) {
            (Some(a), false) => a.clone(),
            _ => self.new_tab(None),
        };
        let id = self.next_run;
        self.next_run += 1;
        self.runs.push(Run {
            id,
            tab: tab.clone(),
            text: text.to_string(),
        });
        if self.history.back().map(String::as_str) != Some(text) {
            self.history.push_back(text.to_string());
            while self.history.len() > HISTORY {
                self.history.pop_front();
            }
        }
        Ok(tab)
    }

    /// Opens `path`: a new tab there, or `cd` in the active one. A path that is not a directory is refused and said.
    pub fn open_dir(&mut self, path: &str, new_tab: bool) -> Result<String, Error> {
        let dir = match self.dir_arg(path) {
            Ok(d) => d,
            Err(e) => {
                if let Error::NoDir(d) = &e {
                    self.notice = Some(("terminal.error.no_dir".into(), d.clone()));
                }
                return Err(e);
            }
        };
        self.notice = None;
        self.crashed = false;
        if new_tab || self.active.is_none() {
            return Ok(self.new_tab(Some(dir)));
        }
        let tab = self.active.clone().unwrap_or_default();
        let id = self.next_run;
        self.next_run += 1;
        self.runs.push(Run {
            id,
            tab: tab.clone(),
            text: format!("cd {}", quote(&dir)),
        });
        Ok(tab)
    }

    // ---- the document ----

    pub fn doc(&self) -> Value {
        let c = &self.cfg;
        let mut d = Map::new();
        d.insert("available".into(), json!(true));
        let mut host = Map::new();
        host.insert("state".into(), json!(self.host.name()));
        if let Some(r) = self.host.reason() {
            host.insert("reason".into(), json!(r));
        }
        if let Some(r) = self.host.detail() {
            host.insert("detail".into(), json!(r));
        }
        if self.crashed {
            host.insert("crashed".into(), json!(true));
        }
        d.insert("host".into(), Value::Object(host));
        d.insert(
            "tabs".into(),
            Value::Array(
                self.tabs
                    .iter()
                    .map(|t| {
                        let mut o = Map::new();
                        o.insert("id".into(), json!(t.id));
                        o.insert("title".into(), json!(t.title));
                        if t.renamed {
                            o.insert("renamed".into(), json!(true));
                        }
                        o.insert("dir".into(), json!(t.dir));
                        if !t.cwd.is_empty() {
                            o.insert("cwd".into(), json!(t.cwd));
                        }
                        if !t.program.is_empty() {
                            o.insert("program".into(), json!(t.program));
                        }
                        Value::Object(o)
                    })
                    .collect(),
            ),
        );
        if let Some(a) = &self.active {
            d.insert("active".into(), json!(a));
        }
        let mut dd = Map::new();
        dd.insert("open".into(), json!(self.dropdown));
        if let Some(o) = &self.dropdown_output {
            dd.insert("output".into(), json!(o));
        }
        d.insert("dropdown".into(), Value::Object(dd));
        if let Some(p) = self.shown_in() {
            d.insert("shown_in".into(), json!(p.name()));
        }
        d.insert(
            "open".into(),
            Value::Array(self.open.iter().map(|p| json!(p.name())).collect()),
        );
        let mut rests = Map::new();
        for (p, r) in &self.rests {
            rests.insert(
                p.name().into(),
                json!({"output": r.output, "x": r.x, "y": r.y, "width": r.width, "height": r.height}),
            );
        }
        d.insert("rests".into(), Value::Object(rests));
        d.insert(
            "runs".into(),
            Value::Array(
                self.runs
                    .iter()
                    .map(|r| json!({"id": r.id, "tab": r.tab, "text": r.text}))
                    .collect(),
            ),
        );
        d.insert(
            "history".into(),
            Value::Array(self.history.iter().map(|h| json!(h)).collect()),
        );
        d.insert("focus".into(), json!(self.focus));
        if self.pointer {
            d.insert("pointer".into(), json!(true));
        }
        if let Some((key, path)) = &self.notice {
            d.insert("notice".into(), json!({"key": key, "path": path}));
        }
        // The settings in effect (the places and the host draw from these; Settings shows the configured values).
        d.insert(
            "settings".into(),
            json!({
                "shell": c.shell,
                "start_dir": self.start_dir(),
                "font": c.font,
                "font_size": c.font_size.clamp(6, 48),
                "opacity": c.opacity.clamp(0, 100),
                "scrollback": c.scrollback.clamp(100, 1_000_000),
                "place": one_of(&c.place, &["bar", "edge", "center", "position"], "bar"),
                "edge": one_of(&c.edge, &["top", "bottom", "left", "right"], "top"),
                "length": c.length.clamp(20, 100),
                "width": c.width.clamp(20, 100),
                "height": c.height.clamp(20, 95),
                "anchor": c.anchor,
                "offset_x": c.offset_x,
                "offset_y": c.offset_y,
                "sizes": c.sizes.iter().map(|(o, h)| (o.clone(), json!((*h).clamp(20, 95)))).collect::<Map<_, _>>(),
                "pinned": c.pinned,
                "hide_on_blur": c.hide_on_blur,
                "bar_mode": one_of(&c.bar_mode, &["icon", "status", "input"], "icon"),
                "input_target": one_of(&c.input_target, &["show", "quiet"], "show"),
                "run_in": one_of(&c.run_in, &["current", "new"], "current"),
                "dir_opens": one_of(&c.dir_opens, &["new", "current"], "new"),
                "run_prefix": c.prefix_in_effect(),
                "favourites": c.favourites.iter().map(|f| {
                    let p = self.expand(&f.path);
                    let mut o = Map::new();
                    o.insert("path".into(), json!(f.path));
                    o.insert("label".into(), json!(if f.label.is_empty() { tail(&p) } else { f.label.clone() }));
                    o.insert("dir".into(), json!(p.to_string_lossy()));
                    if !p.is_dir() {
                        o.insert("missing".into(), json!(true));
                    }
                    Value::Object(o)
                }).collect::<Vec<_>>(),
            }),
        );
        let mut problems = Map::new();
        if let Some(p) = c.prefix_problem() {
            problems.insert("run_prefix".into(), json!(p));
        }
        if !self.expand(&c.start_dir).is_dir() {
            problems.insert("start_dir".into(), json!("terminal.error.no_dir"));
        }
        if !problems.is_empty() {
            d.insert("problems".into(), Value::Object(problems));
        }
        if !self.forced.is_empty() {
            d.insert(
                "forced".into(),
                Value::Object(
                    self.forced
                        .iter()
                        .map(|(k, v)| (k.clone(), json!(v)))
                        .collect(),
                ),
            );
        }
        Value::Object(d)
    }
}

fn one_of(v: &str, of: &[&str], dflt: &str) -> String {
    if of.contains(&v) { v } else { dflt }.to_string()
}

/// The last segment of a path, for a favourite without a label.
fn tail(p: &Path) -> String {
    p.file_name()
        .map(|n| n.to_string_lossy().into_owned())
        .unwrap_or_else(|| p.to_string_lossy().into_owned())
}

/// A path as one single-quoted word, for sh, bash, zsh and fish alike (`'` → `'\''`).
pub fn quote(s: &str) -> String {
    format!("'{}'", s.replace('\'', r"'\''"))
}

#[cfg(test)]
mod tests {
    use super::*;

    fn model() -> (tempfile::TempDir, Model) {
        let home = tempfile::tempdir().unwrap();
        std::fs::create_dir(home.path().join("proj")).unwrap();
        let m = Model::new(Cfg::default(), home.path().to_path_buf());
        (home, m)
    }

    #[test]
    fn toggle_opens_with_a_tab_and_hides() {
        let (_h, mut m) = model();
        assert!(!m.wants_host());
        m.toggle(Some("A"));
        assert!(m.dropdown_open());
        assert_eq!(m.shown_in(), Some(Place::Dropdown));
        assert_eq!(m.doc()["tabs"].as_array().unwrap().len(), 1);
        assert!(m.wants_host());
        m.toggle(Some("A"));
        assert!(!m.dropdown_open());
        // The session keeps running while hidden.
        assert!(m.wants_host());
        // Out on A, a toggle on B moves it there.
        m.toggle(Some("A"));
        m.toggle(Some("B"));
        assert!(m.dropdown_open());
        assert_eq!(m.doc()["dropdown"]["output"], "B");
    }

    #[test]
    fn last_opened_place_shows_the_terminal() {
        let (_h, mut m) = model();
        m.show(Some("A"));
        let r = Rest {
            output: "A".into(),
            x: 1,
            y: 2,
            width: 300,
            height: 200,
        };
        m.place(Place::Card, Some(r.clone()), false, true);
        assert_eq!(m.shown_in(), Some(Place::Card));
        // A rest after a move does not take it back; the card closing gives it back to the drop-down.
        m.place(Place::Dropdown, Some(r.clone()), false, false);
        assert_eq!(m.shown_in(), Some(Place::Card));
        m.place(Place::Card, None, true, false);
        assert_eq!(m.shown_in(), Some(Place::Dropdown));
        assert_eq!(m.doc()["rests"]["dropdown"]["width"], 300);
        m.bring(Place::Dropdown);
        assert_eq!(m.doc()["focus"], 2);
    }

    #[test]
    fn tabs_close_rename_move_step() {
        let (_h, mut m) = model();
        let a = m.new_tab(None);
        let b = m.new_tab(None);
        let c = m.new_tab(None);
        assert_eq!(m.doc()["active"], json!(c));
        m.step(1);
        assert_eq!(m.doc()["active"], json!(a));
        m.rename(&a, "build").unwrap();
        m.host_title(&a, Some("fish"), Some("/tmp"), Some("cargo"));
        assert_eq!(m.doc()["tabs"][0]["title"], "build");
        assert_eq!(m.doc()["tabs"][0]["program"], "cargo");
        m.rename(&a, "").unwrap();
        m.host_title(&a, Some("fish"), None, None);
        assert_eq!(m.doc()["tabs"][0]["title"], "fish");
        m.move_tab(&a, 9).unwrap();
        assert_eq!(m.doc()["tabs"][2]["id"], json!(a));
        m.select(&b).unwrap();
        m.close_tab(&b).unwrap();
        assert_eq!(m.doc()["active"], json!(c));
        assert_eq!(m.close_tab("nope"), Err(Error::UnknownTab));
        m.host_exited(&c);
        m.host_exited(&a);
        assert!(m.doc().get("active").is_none());
    }

    #[test]
    fn runs_and_history() {
        let (_h, mut m) = model();
        assert_eq!(m.run("  ", false), Err(Error::Argument));
        let t = m.run("echo kurashi\n", false).unwrap();
        assert_eq!(m.doc()["runs"][0]["text"], "echo kurashi");
        assert_eq!(m.doc()["runs"][0]["tab"], json!(t));
        let t2 = m.run("echo kurashi", true).unwrap();
        assert_ne!(t, t2);
        // (the same line twice is kept once)
        assert_eq!(m.doc()["history"].as_array().unwrap().len(), 1);
        m.host_ran(1);
        assert_eq!(m.doc()["runs"].as_array().unwrap().len(), 1);
    }

    #[test]
    fn directories_expand_and_missing_ones_are_said() {
        let (h, mut m) = model();
        let t = m.open_dir("~/proj", true).unwrap();
        let proj = h.path().join("proj").to_string_lossy().into_owned();
        assert_eq!(m.doc()["tabs"][0]["dir"], json!(proj));
        assert_eq!(m.doc()["active"], json!(t));
        m.open_dir("~/proj", false).unwrap();
        assert_eq!(m.doc()["runs"][0]["text"], json!(format!("cd '{proj}'")));
        let e = m.open_dir("~/nope", true).unwrap_err();
        assert_eq!(e.key(), "terminal.error.no_dir");
        assert_eq!(m.doc()["notice"]["key"], "terminal.error.no_dir");
        assert_eq!(quote("it's"), r"'it'\''s'");
    }

    #[test]
    fn a_crash_clears_the_sessions_until_restart() {
        let (_h, mut m) = model();
        m.show(Some("A"));
        assert!(!m.set_host(HostState::Starting));
        assert!(!m.set_host(HostState::Ready));
        // The process died and the daemon restarted it: the model stops it and says so.
        assert!(m.set_host(HostState::Starting));
        assert!(!m.wants_host());
        assert_eq!(m.doc()["host"]["crashed"], true);
        assert!(m.doc()["tabs"].as_array().unwrap().is_empty());
        assert!(!m.set_host(HostState::Off));
        m.restart();
        assert!(m.wants_host());
        assert_eq!(m.doc()["tabs"].as_array().unwrap().len(), 1);
        // A stop the model asked for is not a crash.
        m.set_host(HostState::Ready);
        m.note_stopping();
        assert!(!m.set_host(HostState::Off));
        assert!(m.doc()["host"].get("crashed").is_none());
    }

    #[test]
    fn blur_hides_unless_pinned() {
        let (_h, mut m) = model();
        m.show(None);
        m.blur();
        assert!(m.dropdown_open());
        let cfg = Cfg {
            hide_on_blur: true,
            ..Cfg::default()
        };
        m.set_cfg(cfg.clone(), BTreeMap::new());
        m.blur();
        assert!(!m.dropdown_open());
        m.show(None);
        m.set_cfg(
            Cfg {
                pinned: true,
                ..cfg
            },
            BTreeMap::new(),
        );
        m.blur();
        assert!(m.dropdown_open());
    }
}
