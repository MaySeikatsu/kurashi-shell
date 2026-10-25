//! Starting btop in a terminal: "Open in btop", the escape hatch of the bar's menu (docs/ux/sysmon.md). The
//! terminal is a Settings choice from a fixed list, and the manifest declares an `exec:` capability for each
//! program that may run, so a name outside the list is refused and never run. A program that is not on PATH
//! is a reason the menu shows ("btop is not installed"), not a click that does nothing.

use std::io;
use std::path::Path;
use std::process::{Command, Stdio};

/// The terminals Settings offers, and the arguments that run btop in each.
pub const TERMINALS: [(&str, &[&str]); 4] = [
    ("foot", &["-e", "btop"]),
    ("alacritty", &["-e", "btop"]),
    ("kitty", &["btop"]),
    ("xterm", &["-e", "btop"]),
];

/// Looks programs up and starts them. The daemon uses [`Spawn`]; tests record instead, so they never start
/// a terminal.
pub trait Launcher: Send + Sync {
    /// Whether `program` is an executable file on PATH.
    fn on_path(&self, program: &str) -> bool;
    /// Starts `program` with `args`, detached from the daemon's standard streams.
    fn spawn(&self, program: &str, args: &[&str]) -> io::Result<()>;
}

/// The live launcher: PATH lookup and `Command::spawn`.
pub struct Spawn;

impl Launcher for Spawn {
    fn on_path(&self, program: &str) -> bool {
        std::env::var_os("PATH").is_some_and(|paths| {
            std::env::split_paths(&paths).any(|dir| is_executable(&dir.join(program)))
        })
    }

    fn spawn(&self, program: &str, args: &[&str]) -> io::Result<()> {
        use std::os::unix::process::CommandExt;
        // I59: started the way the launcher starts apps — in a systemd user scope of its own when systemd-run is
        // there, in its own process group, without the daemon's KURASHI_* variables — so it outlives a daemon
        // restart and is not counted as part of the shell.
        let mut cmd = if self.on_path("systemd-run") {
            let mut c = Command::new("systemd-run");
            c.args(["--user", "--scope", "--quiet", "--collect", "--", program])
                .args(args);
            c
        } else {
            let mut c = Command::new(program);
            c.args(args);
            c
        };
        for (k, _) in std::env::vars_os() {
            if k.to_string_lossy().starts_with("KURASHI_") {
                cmd.env_remove(&k);
            }
        }
        cmd.process_group(0);
        let mut child = cmd
            .stdin(Stdio::null())
            .stdout(Stdio::null())
            .stderr(Stdio::null())
            .spawn()?;
        // Waited for on a thread: a terminal closed later leaves no zombie behind the daemon.
        std::thread::spawn(move || {
            let _ = child.wait();
        });
        Ok(())
    }
}

fn is_executable(path: &Path) -> bool {
    use std::os::unix::fs::PermissionsExt;
    std::fs::metadata(path).is_ok_and(|m| m.is_file() && m.permissions().mode() & 0o111 != 0)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn every_terminal_offered_runs_btop() {
        for (name, args) in TERMINALS {
            assert!(!name.is_empty());
            assert!(args.contains(&"btop"), "{name} must start btop");
        }
    }

    #[test]
    fn an_executable_on_path_is_found_and_a_plain_file_is_not() {
        let dir = tempfile::tempdir().unwrap();
        let bin = dir.path().join("tool");
        std::fs::write(&bin, "#!/bin/sh\n").unwrap();
        assert!(
            !is_executable(&bin),
            "a file without the execute bit is not a program"
        );
        use std::os::unix::fs::PermissionsExt;
        std::fs::set_permissions(&bin, std::fs::Permissions::from_mode(0o755)).unwrap();
        assert!(is_executable(&bin));
        assert!(!is_executable(&dir.path().join("missing")));
    }
}
