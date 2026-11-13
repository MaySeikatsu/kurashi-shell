//! The terminals the "Open in…" step offers (docs/ux/sessions.md "The flow" 2): each known one found on the daemon's
//! PATH, with how it is told to run a command. A known terminal that is not installed is not listed.

use std::path::PathBuf;

use serde::Serialize;

use crate::noren::which;

/// (id = the binary's name, what comes between the binary and the command).
const KNOWN: &[(&str, &[&str])] = &[
    ("foot", &[]),
    ("kitty", &[]),
    ("ghostty", &["-e"]),
    ("alacritty", &["-e"]),
    ("wezterm", &["start", "--"]),
    ("konsole", &["-e"]),
    ("gnome-terminal", &["--"]),
    ("kgx", &["--"]),
    ("xfce4-terminal", &["-x"]),
    ("xterm", &["-e"]),
];

#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
pub struct Terminal {
    pub id: String,
    #[serde(skip)]
    pub program: PathBuf,
    #[serde(skip)]
    pub before: Vec<String>,
}

impl Terminal {
    /// The argv that runs `command` in a new window of this terminal.
    pub fn argv(&self, command: &[String]) -> Vec<String> {
        let mut v = vec![self.program.to_string_lossy().into_owned()];
        v.extend(self.before.iter().cloned());
        v.extend(command.iter().cloned());
        v
    }
}

/// The known terminals on `PATH`, in the table's order.
pub fn installed(path_env: Option<&str>) -> Vec<Terminal> {
    KNOWN
        .iter()
        .filter_map(|(id, before)| {
            Some(Terminal {
                id: (*id).to_string(),
                program: which(id, path_env)?,
                before: before.iter().map(|s| (*s).to_string()).collect(),
            })
        })
        .collect()
}

/// Whether `id` is a terminal the table knows.
pub fn known(id: &str) -> bool {
    KNOWN.iter().any(|(k, _)| *k == id)
}

/// The "Terminal window" command (`window_command`, the launcher's `foot -e` form), else `$TERMINAL` (one word, with
/// the table's way to run a command when known), else the first installed terminal. `None`: no terminal at all.
pub fn window(
    setting: &[String],
    terminal_env: Option<&str>,
    installed: &[Terminal],
    path_env: Option<&str>,
) -> Option<Vec<String>> {
    if let Some(first) = setting.first().filter(|s| !s.trim().is_empty()) {
        // (the program must exist: a window that cannot open is not offered)
        let found = if first.contains('/') {
            std::path::Path::new(first).exists()
        } else {
            which(first, path_env).is_some()
        };
        return found.then(|| setting.to_vec());
    }
    if let Some(t) = terminal_env.map(str::trim).filter(|t| !t.is_empty()) {
        if let Some(known) = installed.iter().find(|i| i.id == t) {
            return Some(known.argv(&[]));
        }
        if which(t, path_env).is_some() || std::path::Path::new(t).is_absolute() {
            return Some(vec![t.to_string(), "-e".into()]);
        }
    }
    installed.first().map(|t| t.argv(&[]))
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::os::unix::fs::PermissionsExt;

    fn bin(dir: &std::path::Path, name: &str) {
        let p = dir.join(name);
        std::fs::write(&p, "#!/bin/sh\n").unwrap();
        std::fs::set_permissions(&p, std::fs::Permissions::from_mode(0o755)).unwrap();
    }

    #[test]
    fn only_installed_terminals_are_listed_and_each_runs_its_way() {
        let d = tempfile::tempdir().unwrap();
        bin(d.path(), "kitty");
        bin(d.path(), "wezterm");
        let path = d.path().to_str().unwrap().to_string();
        let t = installed(Some(&path));
        let ids: Vec<&str> = t.iter().map(|t| t.id.as_str()).collect();
        assert_eq!(ids, ["kitty", "wezterm"]);
        let cmd = vec!["noren".to_string(), "connect".into(), "x".into()];
        assert_eq!(
            &t[1].argv(&cmd)[1..],
            ["start", "--", "noren", "connect", "x"]
        );
        assert_eq!(&t[0].argv(&cmd)[1..], ["noren", "connect", "x"]);
    }

    #[test]
    fn the_window_command_falls_back_to_terminal_then_the_first_installed() {
        let d = tempfile::tempdir().unwrap();
        bin(d.path(), "kitty");
        bin(d.path(), "foot");
        let path = d.path().to_str().unwrap().to_string();
        let t = installed(Some(&path));
        let set = vec!["foot".to_string(), "-e".into()];
        assert_eq!(window(&set, None, &t, Some(&path)), Some(set.clone()));
        let missing = vec!["nope".to_string(), "-e".into()];
        assert_eq!(window(&missing, None, &t, Some(&path)), None);
        let w = window(&[], Some("kitty"), &t, Some(&path)).unwrap();
        assert!(w[0].ends_with("/kitty") && w.len() == 1);
        let w = window(&[], None, &t, Some(&path)).unwrap();
        assert!(w[0].ends_with("/foot"));
        assert_eq!(window(&[], None, &[], Some("/nonexistent")), None);
    }
}
