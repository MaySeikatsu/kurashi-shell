//! The mod's state, without I/O: noren's list, the "Open in…" step, the handoffs to other mods' actions, frecency, the
//! current project and the saved desks. Every operation returns the [`Effect`]s the mod then carries out (a program to
//! start, a list to read, a desk to restore), so the decisions are tested without a process.

use std::collections::BTreeMap;
use std::path::PathBuf;

use serde::{Deserialize, Serialize};
use serde_json::{Value, json};

use crate::desk::Desk;
use crate::noren::{Entry, Kind, State, quote};
use crate::settings::{Cfg, Project};
use crate::terminals::Terminal;

/// The in-shell terminal, the default terminal window; every other target is a terminal's id.
pub const KURASHI: &str = "kurashi";
pub const WINDOW: &str = "window";
pub const ASK: &str = "ask";

/// noren on the daemon's PATH, as last seen.
#[derive(Debug, Clone, PartialEq)]
pub enum Noren {
    Loading,
    Ready,
    Missing,
    Failed(String),
}

/// An error an action answers with: an i18n key (the shell translates it).
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Error {
    Argument,
    Unknown,
    Missing,
    NoNoren,
    Target,
    NoDesk,
    NoTerminal,
}

impl Error {
    pub fn key(&self) -> &'static str {
        match self {
            Self::Argument => "sessions.error.argument",
            Self::Unknown => "sessions.error.unknown",
            Self::Missing => "sessions.error.missing",
            Self::NoNoren => "sessions.error.no_noren",
            Self::Target => "sessions.error.target",
            Self::NoDesk => "sessions.error.no_desk",
            Self::NoTerminal => "sessions.error.no_terminal",
        }
    }

    pub fn invalid(&self) -> bool {
        matches!(self, Self::Argument | Self::Unknown | Self::Target)
    }
}

/// What the mod does after an operation.
#[derive(Debug, Clone, PartialEq)]
pub enum Effect {
    /// Start a program (a terminal window), detached, in `cwd` when it exists.
    Spawn {
        argv: Vec<String>,
        cwd: Option<String>,
    },
    /// Read noren's list again (in the background).
    Refresh,
    /// Put the project's desk back.
    Restore { project: String },
    /// Write the `projects` records.
    Remember(Value),
    /// The persisted state changed (frecency, current, desks).
    Persist,
}

/// The step on screen: which entry is being opened, on which output.
#[derive(Debug, Clone, PartialEq)]
pub struct Choosing {
    pub entry: Entry,
    pub output: Option<String>,
}

/// An action of another mod the shell sends for this one (a stand-in: a native mod cannot invoke another's action,
/// CONTRACT-CHANGE 810). The mod's own surface sends it and answers `sessions.handed {seq}`.
#[derive(Debug, Clone, PartialEq, Serialize)]
pub struct Handoff {
    pub seq: u64,
    pub action: String,
    pub args: Value,
    /// The entry it opens: a handoff the shell cannot send (its mod is off) brings the step back for it.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub key: Option<String>,
}

/// Opens through the shell, per project: how many and the last (unix seconds).
#[derive(Debug, Clone, Default, PartialEq, Serialize, Deserialize)]
pub struct Use {
    pub count: u32,
    pub last: u64,
}

/// What lives across restarts (`$XDG_STATE_HOME/kurashi/sessions/state.json`).
#[derive(Debug, Clone, Default, PartialEq, Serialize, Deserialize)]
pub struct Persisted {
    #[serde(default)]
    pub uses: BTreeMap<String, Use>,
    /// The project last opened through the shell: (project, name).
    #[serde(default)]
    pub current: Option<(String, String)>,
    #[serde(default)]
    pub desks: BTreeMap<String, Desk>,
}

/// Handoffs not yet sent are kept up to this many (no shell running: they would pile up).
const HANDOFFS: usize = 8;

pub struct Model {
    cfg: Cfg,
    forced: BTreeMap<String, String>,
    pub noren: Noren,
    pub program: Option<PathBuf>,
    entries: Vec<Entry>,
    pub terminals: Vec<Terminal>,
    pub window: Option<Vec<String>>,
    choosing: Option<Choosing>,
    handoffs: Vec<Handoff>,
    seq: u64,
    pub persisted: Persisted,
    /// Saving the desk needs the compositor's window places: `None` when it can, else the reason key.
    pub desk_reason: Option<&'static str>,
    /// A desk just saved whose other mods' parts the shell is asked for: (seq, project).
    collect: Option<(u64, String)>,
    /// The last thing that went wrong, said in the section and the step: (key, detail).
    pub notice: Option<(String, Option<String>)>,
    pub restoring: bool,
    home: String,
}

impl Model {
    pub fn new(cfg: Cfg, home: String) -> Self {
        Self {
            cfg,
            forced: BTreeMap::new(),
            noren: Noren::Loading,
            program: None,
            entries: Vec::new(),
            terminals: Vec::new(),
            window: None,
            choosing: None,
            handoffs: Vec::new(),
            // (from the clock: a shell that outlives a daemon restart has sent sequence numbers up to its own count)
            seq: std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .map(|d| d.as_millis() as u64)
                .unwrap_or(0),
            persisted: Persisted::default(),
            desk_reason: None,
            collect: None,
            notice: None,
            restoring: false,
            home,
        }
    }

    pub fn cfg(&self) -> &Cfg {
        &self.cfg
    }

    pub fn set_cfg(&mut self, cfg: Cfg, forced: BTreeMap<String, String>) {
        self.cfg = cfg;
        self.forced = forced;
    }

    pub fn entries(&self) -> &[Entry] {
        &self.entries
    }

    /// noren's answer to `list`.
    pub fn set_list(&mut self, result: Result<Vec<Entry>, String>) {
        match result {
            Ok(e) => {
                self.entries = e;
                self.noren = Noren::Ready;
                // (a fresh list ends the old news: the failure it replaces, a desk saved or restored a while ago)
                if matches!(&self.notice, Some((k, _)) if k == "sessions.notice.failed" || k == "sessions.notice.saved" || k == "sessions.notice.restored")
                {
                    self.notice = None;
                }
            }
            Err(e) => {
                // (the last good list stays: the brief's "noren fails" row)
                self.noren = Noren::Failed(e.clone());
                self.notice = Some(("sessions.notice.failed".into(), Some(e)));
            }
        }
    }

    pub fn set_missing(&mut self) {
        self.noren = Noren::Missing;
        self.entries.clear();
    }

    fn tilde(&self, p: &str) -> String {
        match p.strip_prefix(&self.home) {
            Some(rest) if !self.home.is_empty() && (rest.is_empty() || rest.starts_with('/')) => {
                format!("~{rest}")
            }
            _ => p.to_string(),
        }
    }

    fn find(&self, args: &Value) -> Result<Entry, Error> {
        let by = |f: &dyn Fn(&Entry) -> bool| self.entries.iter().find(|e| f(e)).cloned();
        if let Some(k) = args["key"].as_str() {
            return by(&|e| e.key == k).ok_or(Error::Unknown);
        }
        if let Some(n) = args["name"].as_str() {
            return by(&|e| e.name == n && e.kind != Kind::Folder)
                .or_else(|| by(&|e| e.name == n))
                .ok_or(Error::Unknown);
        }
        if let Some(p) = args["path"].as_str() {
            let p = match p.trim_end_matches('/') {
                "" => "/",
                t => t,
            };
            if let Some(e) = by(&|e| e.path == p) {
                return Ok(e);
            }
            // A typed folder noren does not list yet: noren connects it (and names the session).
            let missing = !std::path::Path::new(p).is_dir();
            return Ok(Entry {
                key: format!("d:{p}"),
                kind: Kind::Folder,
                name: p.rsplit('/').find(|s| !s.is_empty()).unwrap_or(p).into(),
                path: p.into(),
                state: State::Idle,
                pinned: false,
                missing,
            });
        }
        Err(Error::Argument)
    }

    /// Where `entry` opens without asking: the call's `via`, the project's remembered choice, else `open_in`.
    fn via_for(&self, entry: &Entry, via: Option<&str>) -> String {
        if let Some(v) = via.filter(|v| !v.is_empty()) {
            return v.to_string();
        }
        match self.cfg.project(&entry.project()) {
            Some(p) if !p.open_in.is_empty() => p.open_in.clone(),
            _ => self.cfg.open_in.clone(),
        }
    }

    /// `sessions.open {key | name | path, via?, output?}`: open, or show the step (answer `{ask: true}`).
    pub fn open(&mut self, args: &Value, now: u64) -> Result<(Option<Value>, Vec<Effect>), Error> {
        let entry = self.find(args)?;
        if entry.missing {
            return Err(Error::Missing);
        }
        let output = args["output"].as_str().map(String::from);
        let via = self.via_for(&entry, args["via"].as_str());
        if via == ASK || via.is_empty() {
            self.choosing = Some(Choosing { entry, output });
            self.notice = None;
            return Ok((Some(json!({"ask": true})), vec![]));
        }
        let desk = self.cfg.project(&entry.project()).is_some_and(|p| p.desk);
        let fx = self.connect(&entry, &via, output.as_deref(), desk, now)?;
        Ok((None, fx))
    }

    /// `sessions.choose {via, remember?, desk?}`: the step's answer.
    pub fn choose(&mut self, args: &Value, now: u64) -> Result<Vec<Effect>, Error> {
        let via = args["via"].as_str().ok_or(Error::Argument)?.to_string();
        let c = self.choosing.clone().ok_or(Error::Unknown)?;
        let project = c.entry.project();
        let had = self.cfg.project(&project).cloned();
        let desk = args["desk"]
            .as_bool()
            .unwrap_or_else(|| had.as_ref().is_some_and(|p| p.desk));
        let mut fx = self.connect(&c.entry, &via, c.output.as_deref(), desk, now)?;
        self.choosing = None;
        let remember = args["remember"].as_bool() == Some(true);
        let open_in = if remember {
            via.clone()
        } else {
            had.as_ref().map(|p| p.open_in.clone()).unwrap_or_default()
        };
        let row = (!open_in.is_empty() || desk).then(|| Project {
            path: project.clone(),
            open_in,
            desk,
        });
        if row != had {
            fx.push(Effect::Remember(self.cfg.projects_with(&project, row)));
        }
        Ok(fx)
    }

    pub fn cancel(&mut self) {
        self.choosing = None;
    }

    /// "Ask again" for a project: its remembered target goes (its desk flag stays).
    pub fn forget(&self, project: &str) -> Option<Effect> {
        let had = self.cfg.project(project)?;
        let row = had.desk.then(|| Project {
            open_in: String::new(),
            ..had.clone()
        });
        Some(Effect::Remember(self.cfg.projects_with(project, row)))
    }

    /// Whether target `via` can open now (`None`) or why not.
    pub fn target_reason(&self, via: &str) -> Option<&'static str> {
        match via {
            KURASHI => None,
            WINDOW if self.window.is_none() => Some("sessions.target.no_window"),
            WINDOW => None,
            t if self.terminals.iter().any(|x| x.id == t) => None,
            _ => Some("sessions.target.not_installed"),
        }
    }

    fn connect(
        &mut self,
        entry: &Entry,
        via: &str,
        output: Option<&str>,
        desk: bool,
        now: u64,
    ) -> Result<Vec<Effect>, Error> {
        let noren = self.program.clone().ok_or(Error::NoNoren)?;
        let noren = noren.to_string_lossy().into_owned();
        let cmd = vec![
            noren.clone(),
            "connect".to_string(),
            entry.target().to_string(),
        ];
        let cwd = (!entry.path.is_empty()).then(|| entry.path.clone());
        let mut fx = Vec::new();
        match via {
            KURASHI => {
                let mut args = json!({
                    "text": format!("{} connect {}", quote(&noren), quote(entry.target())),
                    "in": "new",
                    "show": true,
                });
                if let Some(o) = output {
                    args["output"] = json!(o);
                }
                self.handoff("terminal.run", args);
                if let Some(h) = self.handoffs.last_mut() {
                    h.key = Some(entry.key.clone());
                }
            }
            WINDOW => {
                let mut argv = self.window.clone().ok_or(Error::NoTerminal)?;
                argv.extend(cmd);
                fx.push(Effect::Spawn { argv, cwd });
            }
            t => {
                let term = self
                    .terminals
                    .iter()
                    .find(|x| x.id == t)
                    .ok_or(Error::Target)?;
                fx.push(Effect::Spawn {
                    argv: term.argv(&cmd),
                    cwd,
                });
            }
        }
        let project = entry.project();
        let u = self.persisted.uses.entry(project.clone()).or_default();
        u.count = u.count.saturating_add(1);
        u.last = now;
        self.persisted.current = Some((project.clone(), entry.name.clone()));
        self.notice = None;
        fx.push(Effect::Persist);
        if desk && self.persisted.desks.contains_key(&project) {
            fx.push(Effect::Restore { project });
        }
        fx.push(Effect::Refresh);
        Ok(fx)
    }

    pub fn handoff(&mut self, action: &str, args: Value) {
        self.seq += 1;
        self.handoffs.push(Handoff {
            seq: self.seq,
            action: action.into(),
            args,
            key: None,
        });
        let over = self.handoffs.len().saturating_sub(HANDOFFS);
        self.handoffs.drain(..over);
    }

    /// `sessions.handed {seq}`: the shell sent every handoff up to `seq`.
    pub fn handed(&mut self, seq: u64) {
        self.handoffs.retain(|h| h.seq > seq);
    }

    /// `sessions.undelivered {seq}`: the shell could not send handoff `seq` (its mod is off). One that opened an entry
    /// shows the step again for it (where In Kurashi is grey with its reason) instead of nothing happening.
    pub fn undelivered(&mut self, seq: u64) {
        let Some(h) = self.handoffs.iter().find(|h| h.seq == seq).cloned() else {
            return;
        };
        self.handoffs.retain(|x| x.seq != seq);
        if let Some(entry) = h
            .key
            .and_then(|k| self.entries.iter().find(|e| e.key == k).cloned())
        {
            let output = h.args["output"].as_str().map(String::from);
            self.choosing = Some(Choosing { entry, output });
        }
        self.notice = Some(("sessions.notice.mod_off".into(), Some(h.action)));
    }

    /// The project of the current session, for "Save desk" without an argument.
    pub fn current(&self) -> Option<&(String, String)> {
        self.persisted.current.as_ref()
    }

    /// The name a project's rows say.
    pub fn name_of(&self, project: &str) -> String {
        self.entries
            .iter()
            .find(|e| e.project() == project)
            .map(|e| e.name.clone())
            .or_else(|| {
                self.persisted
                    .current
                    .as_ref()
                    .filter(|(p, _)| p == project)
                    .map(|(_, n)| n.clone())
            })
            .unwrap_or_else(|| project.rsplit('/').next().unwrap_or(project).to_string())
    }

    /// A desk was captured for `project`: keep it and ask the shell for the other mods' parts.
    pub fn saved(&mut self, project: String, desk: Desk) {
        self.persisted.desks.insert(project.clone(), desk);
        self.seq += 1;
        self.collect = Some((self.seq, project));
        self.notice = Some(("sessions.notice.saved".into(), None));
    }

    /// `sessions.desk.extras {project, terminal?, webdock?}`: the shell's answer to `collect`.
    pub fn extras(&mut self, args: &Value) -> Result<(), Error> {
        let project = args["project"].as_str().ok_or(Error::Argument)?;
        let d = self.persisted.desks.get_mut(project).ok_or(Error::NoDesk)?;
        d.terminal = args["terminal"]
            .as_array()
            .map(|a| {
                a.iter()
                    .filter_map(Value::as_str)
                    .map(String::from)
                    .collect()
            })
            .unwrap_or_default();
        d.webdock = args["webdock"].as_str().map(String::from);
        if self.collect.as_ref().is_some_and(|(_, p)| p == project) {
            self.collect = None;
        }
        Ok(())
    }

    pub fn forget_desk(&mut self, project: &str) -> bool {
        self.persisted.desks.remove(project).is_some()
    }

    /// The other mods' parts of a desk being restored: their own actions, sent by the shell.
    pub fn restore_extras(&mut self, project: &str) {
        let Some(d) = self.persisted.desks.get(project).cloned() else {
            return;
        };
        for dir in d.terminal {
            self.handoff(
                "terminal.open_dir",
                json!({"path": dir, "in": "new", "show": false}),
            );
        }
        if let Some(pin) = d.webdock {
            self.handoff("webdock.open", json!({"pin": pin}));
        }
    }

    /// The frecency of a project: its opens, halved every week since the last.
    fn frecency(&self, project: &str, now: u64) -> f64 {
        self.persisted.uses.get(project).map_or(0.0, |u| {
            let weeks = now.saturating_sub(u.last) as f64 / (7.0 * 86400.0);
            f64::from(u.count) * 0.5f64.powf(weeks)
        })
    }

    /// The launcher's rows for `text` (docs/ux/sessions.md "The flow" 1): `prefixed` when the query is the provider's
    /// alone (every match, up to 30), else at most five that match a name, after the apps.
    pub fn launcher(&self, text: &str, prefixed: bool, now: u64) -> Vec<Row> {
        let q = text.trim().to_lowercase();
        let mut rows = Vec::new();
        if self.noren == Noren::Missing {
            if prefixed || (q.len() >= 3 && ("noren".starts_with(&q) || "sessions".starts_with(&q)))
            {
                rows.push(Row::Missing);
            }
            return rows;
        }
        if !prefixed && q.chars().count() < 2 {
            return rows;
        }
        let mut scored: Vec<(f64, &Entry)> = self
            .entries
            .iter()
            .filter_map(|e| {
                let m = if q.is_empty() {
                    Some(0.0)
                } else {
                    matched(&q, &e.name.to_lowercase()).or_else(|| {
                        prefixed
                            .then(|| matched(&q, &e.path.to_lowercase()).map(|s| s * 0.5))
                            .flatten()
                    })
                }?;
                Some((m + self.frecency(&e.project(), now), e))
            })
            .collect();
        // (stable: noren's own order breaks the ties)
        scored.sort_by(|a, b| b.0.total_cmp(&a.0));
        let cap = if prefixed { 30 } else { 5 };
        rows.extend(scored.into_iter().take(cap).map(|(_, e)| Row::Entry {
            entry: e.clone(),
            sub: if e.missing {
                "sessions.launcher.missing_dir".into()
            } else {
                self.tilde(&e.path)
            },
        }));
        if let Some((project, name)) = self.current().cloned()
            && self.desk_reason.is_none()
            && (prefixed && q.is_empty() || (q.len() >= 3 && "save desk".contains(&q)))
        {
            rows.push(Row::SaveDesk { project, name });
        }
        if prefixed && rows.is_empty() && q.is_empty() {
            rows.push(Row::Empty);
        }
        rows
    }

    pub fn doc(&self) -> Value {
        let (state, reason, detail) = match &self.noren {
            Noren::Loading => ("loading", None, None),
            Noren::Ready => ("ready", None, None),
            Noren::Missing => ("missing", Some("sessions.state.missing"), None),
            Noren::Failed(e) => ("failed", Some("sessions.state.failed"), Some(e.clone())),
        };
        let mut noren = json!({"state": state});
        if let Some(r) = reason {
            noren["reason"] = json!(r);
        }
        if let Some(d) = detail {
            noren["detail"] = json!(d);
        }
        let entries: Vec<Value> = self
            .entries
            .iter()
            .map(|e| {
                let mut v = serde_json::to_value(e).unwrap_or_default();
                if !e.path.is_empty() {
                    v["dir"] = json!(self.tilde(&e.path));
                }
                let p = e.project();
                if self.persisted.desks.contains_key(&p) {
                    v["desk"] = json!(true);
                }
                if let Some(r) = self.cfg.project(&p) {
                    if !r.open_in.is_empty() {
                        v["open_in"] = json!(r.open_in);
                    }
                    if r.desk {
                        v["restore"] = json!(true);
                    }
                }
                v
            })
            .collect();
        let mut targets = vec![json!({"id": KURASHI, "label": "sessions.target.kurashi"})];
        let mut w = json!({"id": WINDOW, "label": "sessions.target.window"});
        let program = self
            .window
            .as_ref()
            .and_then(|argv| argv.first())
            .map(|p| p.rsplit('/').next().unwrap_or(p).to_string());
        match &program {
            Some(p) => w["program"] = json!(p),
            None => w["reason"] = json!("sessions.target.no_window"),
        }
        targets.push(w);
        // (the window's own terminal is that row already: not offered twice)
        targets.extend(
            self.terminals
                .iter()
                .filter(|t| program.as_deref() != Some(t.id.as_str()))
                .map(|t| json!({"id": t.id, "label": t.id})),
        );
        let mut d = json!({
            "available": self.noren == Noren::Ready,
            "noren": noren,
            "entries": entries,
            "targets": targets,
            "desk": match self.desk_reason {
                None => json!({"available": true}),
                Some(r) => json!({"available": false, "reason": r}),
            },
            "desks": self.persisted.desks.iter().map(|(p, d)| (p.clone(), json!({
                "saved": d.saved,
                "windows": d.windows.len(),
                "terminal": d.terminal.len(),
            }))).collect::<serde_json::Map<String, Value>>(),
            "settings": self.cfg.doc(),
            "forced": self.forced,
        });
        if let Some((p, n)) = &self.persisted.current {
            d["current"] = json!({"project": p, "name": n});
        }
        if let Some(c) = &self.choosing {
            let mut v = json!({
                "key": c.entry.key,
                "name": c.entry.name,
                "state": c.entry.state,
                "project": c.entry.project(),
                "desk": self.persisted.desks.contains_key(&c.entry.project()),
            });
            if !c.entry.path.is_empty() {
                v["dir"] = json!(self.tilde(&c.entry.path));
            }
            if let Some(o) = &c.output {
                v["output"] = json!(o);
            }
            if let Some(p) = self.cfg.project(&c.entry.project()) {
                v["restore"] = json!(p.desk);
            }
            d["choosing"] = v;
        }
        if !self.handoffs.is_empty() {
            d["handoff"] = json!(self.handoffs);
        }
        if let Some((seq, p)) = &self.collect {
            d["collect"] = json!({"seq": seq, "project": p});
        }
        if let Some((k, det)) = &self.notice {
            let mut n = json!({"key": k});
            if let Some(x) = det {
                n["detail"] = json!(x);
            }
            d["notice"] = n;
        }
        if self.restoring {
            d["restoring"] = json!(true);
        }
        d
    }
}

/// A launcher row before it becomes a [`kurashi_mod_api::LauncherRow`].
#[derive(Debug, Clone, PartialEq)]
pub enum Row {
    Entry { entry: Entry, sub: String },
    SaveDesk { project: String, name: String },
    Missing,
    Empty,
}

/// How well `q` matches `s` (both lower case): a prefix best, then a word's start, a substring, the letters in order.
pub fn matched(q: &str, s: &str) -> Option<f64> {
    if s.starts_with(q) {
        return Some(4.0);
    }
    if s.split(['-', '_', ' ', '/', '.']).any(|w| w.starts_with(q)) {
        return Some(3.0);
    }
    if s.contains(q) {
        return Some(2.0);
    }
    let mut it = s.chars();
    q.chars().all(|c| it.any(|d| d == c)).then_some(1.0)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::noren::parse;
    use std::path::PathBuf;

    const LIST: &str = "zoxide\tdocs\t/home/u/docs\tdir\t📁 docs\n\
zellij\told\t/home/u/gone\texited\t⊗ old\n\
zellij\tkurashi\t/home/u/kurashi-shell\tlive\t▣ kurashi\n";

    fn model() -> Model {
        let mut m = Model::new(Cfg::default(), "/home/u".into());
        m.program = Some(PathBuf::from("/bin/noren"));
        m.set_list(Ok(parse(LIST, &|p| p != "/home/u/gone")));
        m.terminals = vec![Terminal {
            id: "kitty".into(),
            program: "/bin/kitty".into(),
            before: vec![],
        }];
        m.window = Some(vec!["/bin/foot".into(), "-e".into()]);
        m
    }

    #[test]
    fn ask_shows_the_step_and_kurashi_hands_terminal_run_over() {
        let mut m = model();
        let (reply, fx) = m
            .open(&json!({"name": "kurashi", "output": "O"}), 10)
            .unwrap();
        assert_eq!(reply, Some(json!({"ask": true})));
        assert!(fx.is_empty());
        let d = m.doc();
        assert_eq!(d["choosing"]["name"], "kurashi");
        assert_eq!(d["choosing"]["dir"], "~/kurashi-shell");
        let fx = m.choose(&json!({"via": "kurashi"}), 11).unwrap();
        assert!(fx.contains(&Effect::Refresh) && fx.contains(&Effect::Persist));
        assert!(!fx.iter().any(|f| matches!(f, Effect::Remember(_))));
        let d = m.doc();
        assert!(d.get("choosing").is_none());
        let h = &d["handoff"][0];
        assert_eq!(h["action"], "terminal.run");
        assert_eq!(h["args"]["text"], "'/bin/noren' connect 'kurashi'");
        assert_eq!(h["args"]["in"], "new");
        assert_eq!(h["args"]["output"], "O");
        assert_eq!(d["current"]["name"], "kurashi");
        m.handed(h["seq"].as_u64().unwrap());
        assert!(m.doc().get("handoff").is_none());
    }

    #[test]
    fn a_terminal_runs_noren_connect_as_argv_in_the_folder() {
        let mut m = model();
        let (_, fx) = m
            .open(&json!({"key": "d:/home/u/docs", "via": "kitty"}), 1)
            .unwrap();
        assert_eq!(
            fx[0],
            Effect::Spawn {
                argv: vec![
                    "/bin/kitty".into(),
                    "/bin/noren".into(),
                    "connect".into(),
                    "/home/u/docs".into()
                ],
                cwd: Some("/home/u/docs".into()),
            }
        );
        let (_, fx) = m
            .open(&json!({"name": "docs", "via": "window"}), 1)
            .unwrap();
        assert!(
            matches!(&fx[0], Effect::Spawn { argv, .. } if argv[..2] == ["/bin/foot".to_string(), "-e".into()])
        );
        assert_eq!(
            m.open(&json!({"name": "docs", "via": "ghostty"}), 1)
                .unwrap_err(),
            Error::Target
        );
    }

    #[test]
    fn remember_writes_the_project_and_the_next_open_does_not_ask() {
        let mut m = model();
        m.open(&json!({"name": "kurashi"}), 1).unwrap();
        let fx = m
            .choose(&json!({"via": "kitty", "remember": true}), 1)
            .unwrap();
        let rows = fx
            .iter()
            .find_map(|f| match f {
                Effect::Remember(v) => Some(v.clone()),
                _ => None,
            })
            .unwrap();
        assert_eq!(
            rows,
            json!([{"path": "/home/u/kurashi-shell", "open_in": "kitty", "desk": false}])
        );
        let cfg = Cfg::from_get(&|k| (k == "projects").then(|| rows.clone()));
        m.set_cfg(cfg, BTreeMap::new());
        let (reply, fx) = m.open(&json!({"name": "kurashi"}), 2).unwrap();
        assert_eq!(reply, None);
        assert!(matches!(&fx[0], Effect::Spawn { argv, .. } if argv[0] == "/bin/kitty"));
        assert_eq!(
            m.forget("/home/u/kurashi-shell"),
            Some(Effect::Remember(json!([])))
        );
    }

    #[test]
    fn a_missing_folder_and_a_missing_noren_are_refused() {
        let mut m = model();
        assert_eq!(
            m.open(&json!({"name": "old"}), 1).unwrap_err(),
            Error::Missing
        );
        m.program = None;
        assert_eq!(
            m.open(&json!({"name": "kurashi", "via": "kurashi"}), 1)
                .unwrap_err(),
            Error::NoNoren
        );
        assert_eq!(m.open(&json!({}), 1).unwrap_err(), Error::Argument);
        assert_eq!(
            m.open(&json!({"key": "s:nope"}), 1).unwrap_err(),
            Error::Unknown
        );
    }

    #[test]
    fn the_launcher_matches_names_and_ranks_by_use() {
        let mut m = model();
        assert!(
            m.launcher("k", false, 0).is_empty(),
            "one letter joins nothing"
        );
        let rows = m.launcher("ku", false, 0);
        assert!(
            matches!(&rows[0], Row::Entry { entry, sub } if entry.name == "kurashi" && sub == "~/kurashi-shell")
        );
        assert_eq!(m.launcher("", true, 0).len(), 3);
        // the missing folder says so
        assert!(m.launcher("old", false, 0).iter().any(
            |r| matches!(r, Row::Entry { sub, .. } if sub == "sessions.launcher.missing_dir")
        ));
        // used projects first
        m.persisted.uses.insert(
            "/home/u/docs".into(),
            Use {
                count: 5,
                last: 100,
            },
        );
        let rows = m.launcher("", true, 100);
        assert!(matches!(&rows[0], Row::Entry { entry, .. } if entry.name == "docs"));
        // the current project offers "Save desk"
        m.persisted.current = Some(("/home/u/docs".into(), "docs".into()));
        assert!(
            m.launcher("", true, 100)
                .iter()
                .any(|r| matches!(r, Row::SaveDesk { .. }))
        );
        m.set_missing();
        assert_eq!(m.launcher("nor", false, 0), [Row::Missing]);
        assert_eq!(m.doc()["noren"]["reason"], "sessions.state.missing");
        assert_eq!(m.doc()["available"], false);
    }

    #[test]
    fn a_failed_list_keeps_the_last_good_one_and_says_why() {
        let mut m = model();
        m.set_list(Err("zellij: not found".into()));
        assert_eq!(m.entries().len(), 3);
        let d = m.doc();
        assert_eq!(d["noren"]["state"], "failed");
        assert_eq!(d["notice"]["detail"], "zellij: not found");
    }

    #[test]
    fn the_desk_comes_back_with_a_project_that_wants_it() {
        let mut m = model();
        let desk = Desk {
            saved: 1,
            workspace: None,
            output: None,
            windows: vec![],
            terminal: vec![],
            webdock: None,
        };
        m.saved("/home/u/kurashi-shell".into(), desk);
        assert_eq!(m.doc()["collect"]["project"], "/home/u/kurashi-shell");
        m.extras(&json!({"project": "/home/u/kurashi-shell", "terminal": ["/home/u/x"], "webdock": "mail"}))
            .unwrap();
        assert!(m.doc().get("collect").is_none());
        m.open(&json!({"name": "kurashi"}), 1).unwrap();
        let fx = m
            .choose(
                &json!({"via": "kurashi", "desk": true, "remember": true}),
                1,
            )
            .unwrap();
        assert!(fx.contains(&Effect::Restore {
            project: "/home/u/kurashi-shell".into()
        }));
        m.restore_extras("/home/u/kurashi-shell");
        let h = m.doc()["handoff"].clone();
        let actions: Vec<&str> = h
            .as_array()
            .unwrap()
            .iter()
            .map(|x| x["action"].as_str().unwrap())
            .collect();
        assert_eq!(
            actions,
            ["terminal.run", "terminal.open_dir", "webdock.open"]
        );
    }

    #[test]
    fn an_undelivered_in_kurashi_brings_the_step_back() {
        let mut m = model();
        m.open(&json!({"name": "kurashi", "via": "kurashi"}), 1)
            .unwrap();
        let seq = m.doc()["handoff"][0]["seq"].as_u64().unwrap();
        assert_eq!(m.doc()["handoff"][0]["key"], "s:kurashi");
        m.undelivered(seq);
        let d = m.doc();
        assert!(d.get("handoff").is_none());
        assert_eq!(d["choosing"]["name"], "kurashi");
        assert_eq!(d["notice"]["key"], "sessions.notice.mod_off");
    }

    #[test]
    fn handoffs_are_capped() {
        let mut m = model();
        for i in 0..20 {
            m.handoff("x.y", json!({"i": i}));
        }
        let h = m.doc()["handoff"].as_array().unwrap().clone();
        assert_eq!(h.len(), HANDOFFS);
        assert_eq!(h[0]["args"]["i"], 12);
    }

    #[test]
    fn matching() {
        assert_eq!(matched("ku", "kurashi"), Some(4.0));
        assert_eq!(matched("sh", "kurashi-shell"), Some(3.0));
        assert_eq!(matched("ash", "kurashi"), Some(2.0));
        assert_eq!(matched("krs", "kurashi"), Some(1.0));
        assert_eq!(matched("zz", "kurashi"), None);
    }
}
