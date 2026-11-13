//! noren, read through its CLI only (never its config): `noren list <source>` prints one row per line, tab-separated
//! `source  name  path  state  display` (noren `src/sources/mod.rs` `rows_to_tsv`). `state` is `live | exited | dir |
//! config`; whether a session is attached (▣) or pinned (📌) is only in the display column, which itself may hold tabs and
//! ANSI escapes — so a line is split into five fields at most. `sep` rows are the picker's hairline.

use std::path::{Path, PathBuf};
use std::time::Duration;

use serde::Serialize;

/// What an entry is: a zellij session, a zoxide folder or a `[[session]]` entry of noren's config.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize)]
#[serde(rename_all = "lowercase")]
pub enum Kind {
    Session,
    Folder,
    Config,
}

/// The state the shell shows (docs/ux/sessions.md "The flow").
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize)]
#[serde(rename_all = "lowercase")]
pub enum State {
    /// Running and shown in a terminal right now (▣).
    Attached,
    /// Running in the background (▢).
    Running,
    /// Exited, resurrectable (⊗).
    Exited,
    /// A folder (zoxide) or a configured entry: nothing runs yet.
    Idle,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
pub struct Entry {
    /// Stable identity: `s:<name>` for sessions, `c:<name>` for config entries, `d:<path>` for folders.
    pub key: String,
    pub kind: Kind,
    pub name: String,
    /// Absent for a session noren knows no folder of.
    #[serde(skip_serializing_if = "String::is_empty")]
    pub path: String,
    pub state: State,
    #[serde(skip_serializing_if = "std::ops::Not::not")]
    pub pinned: bool,
    /// The folder does not exist (said, and refused on open).
    #[serde(skip_serializing_if = "std::ops::Not::not")]
    pub missing: bool,
}

impl Entry {
    /// What `noren connect` is given: a session or config entry by name, a folder by its path.
    pub fn target(&self) -> &str {
        match self.kind {
            Kind::Folder => &self.path,
            _ => &self.name,
        }
    }

    /// The project's identity for remembered choices and desks: noren's path, else the session's name.
    pub fn project(&self) -> String {
        if self.path.is_empty() {
            format!("session:{}", self.name)
        } else {
            self.path.clone()
        }
    }
}

/// Drop ANSI escapes (`\x1b[…m`) from a display column.
fn plain(s: &str) -> String {
    let mut out = String::with_capacity(s.len());
    let mut it = s.chars().peekable();
    while let Some(c) = it.next() {
        if c == '\x1b' {
            if it.peek() == Some(&'[') {
                it.next();
                for d in it.by_ref() {
                    if d.is_ascii_alphabetic() {
                        break;
                    }
                }
            }
            continue;
        }
        out.push(c);
    }
    out
}

/// noren's rows → entries, in noren's order (its sort: the most relevant next to the prompt, i.e. *last*; reversed here
/// so the most relevant comes first). Unknown sources and `sep` rows are skipped; the first row of an identity wins.
pub fn parse(tsv: &str, exists: &dyn Fn(&str) -> bool) -> Vec<Entry> {
    let mut out: Vec<Entry> = Vec::new();
    for line in tsv.lines().rev() {
        let f: Vec<&str> = line.splitn(5, '\t').collect();
        if f.len() < 4 {
            continue;
        }
        let (source, name, path, state) = (f[0], f[1].trim(), f[2].trim(), f[3].trim());
        let display = plain(f.get(4).copied().unwrap_or(""));
        let kind = match source {
            "zellij" => Kind::Session,
            "zoxide" => Kind::Folder,
            "config" => Kind::Config,
            _ => continue,
        };
        if name.is_empty() && path.is_empty() {
            continue;
        }
        let state = match state {
            "live" if display.contains('▣') => State::Attached,
            "live" => State::Running,
            "exited" => State::Exited,
            _ => State::Idle,
        };
        let key = match kind {
            Kind::Session => format!("s:{name}"),
            Kind::Config => format!("c:{name}"),
            Kind::Folder => format!("d:{path}"),
        };
        if out.iter().any(|e| e.key == key) {
            continue;
        }
        let name = if name.is_empty() {
            path.rsplit('/').find(|p| !p.is_empty()).unwrap_or(path)
        } else {
            name
        };
        out.push(Entry {
            key,
            kind,
            name: name.to_string(),
            path: path.to_string(),
            state,
            pinned: display.contains('📌'),
            missing: !path.is_empty() && !exists(path),
        });
    }
    out
}

/// The noren program: `command` (a setting) as an absolute path, else looked up in `PATH`. `None`: not installed.
pub fn resolve(command: &str, path_env: Option<&str>) -> Option<PathBuf> {
    let command = command.trim();
    if command.is_empty() {
        return None;
    }
    if command.contains('/') {
        let p = PathBuf::from(command);
        return is_exec(&p).then_some(p);
    }
    which(command, path_env)
}

/// `name` on `PATH` (the daemon's), or `None`.
pub fn which(name: &str, path_env: Option<&str>) -> Option<PathBuf> {
    path_env?
        .split(':')
        .filter(|d| !d.is_empty())
        .map(|d| Path::new(d).join(name))
        .find(|p| is_exec(p))
}

fn is_exec(p: &Path) -> bool {
    use std::os::unix::fs::PermissionsExt;
    std::fs::metadata(p)
        .map(|m| m.is_file() && m.permissions().mode() & 0o111 != 0)
        .unwrap_or(false)
}

/// How noren is run: a trait so the model's tests never start a program.
pub trait Runner: Send + Sync {
    /// `program args…` with a timeout; stdout on success, the first line of stderr (or the status) on failure.
    fn run(&self, program: &Path, args: &[&str]) -> Result<String, String>;
}

/// The real runner: a program (no shell), stdin closed, killed when it overstays `timeout`.
pub struct Exec {
    pub timeout: Duration,
}

impl Runner for Exec {
    fn run(&self, program: &Path, args: &[&str]) -> Result<String, String> {
        use std::io::Read;
        use std::process::{Command, Stdio};
        let mut child = Command::new(program)
            .args(args)
            .stdin(Stdio::null())
            .stdout(Stdio::piped())
            .stderr(Stdio::piped())
            .spawn()
            .map_err(|e| e.to_string())?;
        let (mut out, mut err) = (child.stdout.take(), child.stderr.take());
        // (read both pipes off-thread: a full pipe would stall the child past its timeout)
        let reader = std::thread::spawn(move || {
            let (mut o, mut e) = (String::new(), String::new());
            if let Some(s) = out.as_mut() {
                let _ = s.read_to_string(&mut o);
            }
            if let Some(s) = err.as_mut() {
                let _ = s.read_to_string(&mut e);
            }
            (o, e)
        });
        let start = std::time::Instant::now();
        let status = loop {
            match child.try_wait() {
                Ok(Some(s)) => break s,
                Ok(None) if start.elapsed() > self.timeout => {
                    let _ = child.kill();
                    let _ = child.wait();
                    return Err(format!("timed out after {} s", self.timeout.as_secs()));
                }
                Ok(None) => std::thread::sleep(Duration::from_millis(20)),
                Err(e) => return Err(e.to_string()),
            }
        };
        let (o, e) = reader.join().unwrap_or_default();
        if status.success() {
            Ok(o)
        } else {
            let first = e.lines().find(|l| !l.trim().is_empty()).unwrap_or("");
            Err(if first.is_empty() {
                status.to_string()
            } else {
                first.trim().to_string()
            })
        }
    }
}

/// A word for a POSIX shell: `'…'`, with `'` written `'\''` (the line typed into the in-shell terminal).
pub fn quote(s: &str) -> String {
    format!("'{}'", s.replace('\'', "'\\''"))
}

#[cfg(test)]
mod tests {
    use super::*;

    const LIST: &str = "zoxide\tdocs\t/home/u/docs\tdir\t📁 docs \t\x1b[2m~/docs\x1b[0m\n\
sep\t\t\tsep\t╌╌╌\n\
zellij\told\t/home/u/old\texited\t⊗ old\n\
zellij\tbg\t/home/u/bg\tlive\t▢ bg\n\
config\tnixos\t/home/u/nixos\tconfig\t⚙ nixos\n\
zellij\tkurashi\t/home/u/kurashi-shell\tlive\t📌 ▣ kurashi (code, logs)\t\x1b[2m~/kurashi-shell\x1b[0m\n";

    #[test]
    fn rows_become_entries_most_relevant_first() {
        let e = parse(LIST, &|p| p != "/home/u/old");
        let keys: Vec<&str> = e.iter().map(|e| e.key.as_str()).collect();
        assert_eq!(
            keys,
            ["s:kurashi", "c:nixos", "s:bg", "s:old", "d:/home/u/docs"]
        );
        assert_eq!(e[0].state, State::Attached);
        assert!(e[0].pinned);
        assert_eq!(e[2].state, State::Running);
        assert_eq!(e[3].state, State::Exited);
        assert!(e[3].missing);
        assert_eq!(e[4].kind, Kind::Folder);
        assert_eq!(e[4].target(), "/home/u/docs");
        assert_eq!(e[0].target(), "kurashi");
        assert_eq!(e[0].project(), "/home/u/kurashi-shell");
    }

    #[test]
    fn short_and_odd_lines_are_skipped() {
        let e = parse("garbage\nzellij\tx\nmystery\ta\t/a\tdir\t?\n", &|_| true);
        assert!(e.is_empty());
    }

    #[test]
    fn a_session_without_a_folder_is_keyed_by_name() {
        let e = parse("zellij\tscratch\t\tlive\t▢ scratch\n", &|_| false);
        assert_eq!(e[0].project(), "session:scratch");
        assert!(!e[0].missing);
    }

    #[test]
    fn quoting_keeps_a_name_one_word() {
        assert_eq!(quote("a b"), "'a b'");
        assert_eq!(quote("it's; rm -rf ~"), "'it'\\''s; rm -rf ~'");
    }

    #[test]
    fn the_command_resolves_by_path_or_on_path() {
        let dir = tempfile::tempdir().unwrap();
        let bin = dir.path().join("noren");
        std::fs::write(&bin, "#!/bin/sh\n").unwrap();
        use std::os::unix::fs::PermissionsExt;
        std::fs::set_permissions(&bin, std::fs::Permissions::from_mode(0o755)).unwrap();
        let path = dir.path().to_str().unwrap().to_string();
        assert_eq!(resolve("noren", Some(&path)), Some(bin.clone()));
        assert_eq!(resolve(bin.to_str().unwrap(), None), Some(bin));
        assert_eq!(resolve("noren", Some("/nonexistent")), None);
        assert_eq!(resolve("/nonexistent/noren", Some(&path)), None);
        assert_eq!(resolve("", Some(&path)), None);
    }

    #[test]
    fn exec_reports_the_first_error_line() {
        let r = Exec {
            timeout: Duration::from_secs(5),
        };
        let sh = Path::new("/bin/sh");
        assert_eq!(r.run(sh, &["-c", "echo hi"]).unwrap(), "hi\n");
        assert_eq!(
            r.run(sh, &["-c", "echo '' >&2; echo boom >&2; exit 3"])
                .unwrap_err(),
            "boom"
        );
    }
}
