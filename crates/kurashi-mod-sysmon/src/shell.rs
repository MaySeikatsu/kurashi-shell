//! The shell's own processes (B24, docs/ux/sysmon.md "The process that matters"). The list never offers to end them:
//! a signal to this session's daemon, its Quickshell frontend or its Settings window would end the shell from inside
//! itself, and another kurashid of the same user is another shell of the user's, so it is refused as well. Identity is
//! the program (its executable, or its command name when the executable cannot be read) and, for Quickshell, the
//! directory it runs (`-p <dir>`: `frontend` or `settings`), never the pid alone, so a reused pid running something else
//! is not the shell. Another user's process is never the shell here: it is refused as not yours. The login session
//! only words the reason ("this session" or another one of the user's).

use crate::names::program_name;
use crate::roots::Roots;
use std::path::Path;

/// Which part of the shell a process is.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Part {
    /// A kurashid of the user: this session's, or another session's.
    Daemon,
    /// The Quickshell frontend (`qs -p <share/kurashi/frontend>`).
    Frontend,
    /// The Settings window (`qs -p <settings dir>`).
    Settings,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct Own {
    pub part: Part,
    /// The process is in the daemon's login session (same POSIX session id).
    pub this_session: bool,
}

impl Own {
    /// The reason the list and the actions give for not ending it, as a catalogue key.
    pub fn reason(self) -> &'static str {
        if self.this_session {
            "sysmon.error.shell"
        } else {
            "sysmon.error.shell_other"
        }
    }
}

/// The daemon itself: its pid (refused without a read) and its login session.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct Me {
    pub pid: u32,
    pub session: u64,
}

impl Me {
    /// This process, as the kernel knows it. A session that cannot be read is 0: no process is then this session's,
    /// which only changes the wording of the reason.
    pub fn live() -> Self {
        let session =
            rustix::process::getsid(None).map_or(0, |p| u64::try_from(p.as_raw_pid()).unwrap_or(0));
        Self {
            pid: std::process::id(),
            session,
        }
    }
}

/// Whether a process (its pid, command name, executable basename when readable, session and owner) is part of the
/// shell this daemon serves. The owner is read by the caller (`uid`); None is "not the shell".
pub fn of(
    roots: &Roots,
    pid: i32,
    comm: &str,
    exe: Option<&str>,
    session: u64,
    uid: Option<u32>,
    me: Me,
) -> Option<Own> {
    if i64::from(pid) == i64::from(me.pid) {
        return Some(Own {
            part: Part::Daemon,
            this_session: true,
        });
    }
    if uid != Some(roots.uid) {
        return None;
    }
    let part = match program_name(comm, exe) {
        "kurashid" => Part::Daemon,
        "quickshell" | "qs" => match run_dir(roots, pid)?.as_str() {
            "frontend" => Part::Frontend,
            "settings" => Part::Settings,
            _ => return None,
        },
        _ => return None,
    };
    Some(Own {
        part,
        this_session: session == me.session,
    })
}

/// The directory a Quickshell process runs: the argument after `-p`, by its last component. A relative one (the
/// frontend's own `launch.sh` run from its directory) is taken from the process's working directory.
fn run_dir(roots: &Roots, pid: i32) -> Option<String> {
    let base = roots.proc.join(pid.to_string());
    let raw = roots.read_bytes(base.join("cmdline"))?;
    let args: Vec<&[u8]> = raw.split(|b| *b == 0).collect();
    let at = args.iter().position(|a| *a == b"-p")?;
    let dir = std::str::from_utf8(args.get(at + 1)?).ok()?;
    let path = Path::new(dir);
    if let Some(name) = path.file_name() {
        return name.to_str().map(str::to_string);
    }
    let cwd = roots.link(base.join("cwd"))?;
    cwd.join(path).file_name()?.to_str().map(str::to_string)
}

#[cfg(test)]
mod tests {
    use super::*;

    const ME: Me = Me {
        pid: 4000,
        session: 77,
    };

    /// A process with its executable (or none), and its command line (or none).
    fn process(roots: &Roots, pid: i32, exe: Option<&str>, cmdline: Option<&str>) {
        let dir = roots.proc.join(pid.to_string());
        std::fs::create_dir_all(&dir).unwrap();
        if let Some(exe) = exe {
            std::os::unix::fs::symlink(exe, dir.join("exe")).unwrap();
        }
        if let Some(line) = cmdline {
            std::fs::write(dir.join("cmdline"), line.replace(' ', "\0")).unwrap();
        }
    }

    fn roots() -> (tempfile::TempDir, Roots) {
        let dir = tempfile::tempdir().unwrap();
        let roots = Roots::new(dir.path().join("proc"), dir.path().join("sys"), 1000);
        (dir, roots)
    }

    fn of_pid(roots: &Roots, pid: i32, comm: &str, session: u64, uid: Option<u32>) -> Option<Own> {
        let exe = crate::names::exe_base(roots, pid);
        of(roots, pid, comm, exe.as_deref(), session, uid, ME)
    }

    #[test]
    fn this_daemon_is_the_shell_of_this_session_without_a_read() {
        let (_dir, roots) = roots();
        let own = of(&roots, 4000, "kurashid", None, 77, None, ME).unwrap();
        assert_eq!(
            own,
            Own {
                part: Part::Daemon,
                this_session: true
            }
        );
        assert_eq!(own.reason(), "sysmon.error.shell");
        assert!(
            roots.trace().is_empty() && roots.reads() == 0,
            "the daemon's own pid is never read"
        );
    }

    #[test]
    fn a_second_kurashid_of_the_same_user_is_another_shell_of_theirs() {
        let (_dir, roots) = roots();
        process(
            &roots,
            5001,
            Some("/nix/store/aaa-kurashid/bin/kurashid"),
            None,
        );
        let other = of_pid(&roots, 5001, "kurashid", 900, Some(1000)).unwrap();
        assert_eq!(other.part, Part::Daemon);
        assert!(!other.this_session, "another login session");
        assert_eq!(other.reason(), "sysmon.error.shell_other");
        // The same daemon in this session (the sandbox runs in the same session as its test) is this session's.
        let same = of_pid(&roots, 5001, "kurashid", 77, Some(1000)).unwrap();
        assert!(same.this_session);
        assert_eq!(same.reason(), "sysmon.error.shell");
    }

    #[test]
    fn a_kurashid_of_another_user_is_not_the_shell_but_not_yours() {
        let (_dir, roots) = roots();
        process(
            &roots,
            5002,
            Some("/nix/store/aaa-kurashid/bin/kurashid"),
            None,
        );
        assert_eq!(of_pid(&roots, 5002, "kurashid", 77, Some(0)), None);
        assert_eq!(
            of_pid(&roots, 5002, "kurashid", 77, None),
            None,
            "no owner read: not identified"
        );
    }

    #[test]
    fn the_frontend_and_the_settings_window_are_found_by_the_directory_they_run() {
        let (_dir, roots) = roots();
        let wrapped = "/nix/store/bbb-quickshell/bin/.quickshell-wrapped";
        process(
            &roots,
            6001,
            Some(wrapped),
            Some("qs -p /nix/store/ccc-kurashi/share/kurashi/frontend"),
        );
        process(
            &roots,
            6002,
            Some(wrapped),
            Some("qs -p /nix/store/ccc-kurashi/share/kurashi/settings"),
        );
        process(
            &roots,
            6003,
            Some(wrapped),
            Some("qs -p /home/maike/other-shell"),
        );
        process(&roots, 6004, Some(wrapped), Some("qs"));
        let frontend = of_pid(&roots, 6001, ".quickshell-wra", 77, Some(1000)).unwrap();
        assert_eq!(
            (frontend.part, frontend.this_session),
            (Part::Frontend, true)
        );
        let settings = of_pid(&roots, 6002, ".quickshell-wra", 77, Some(1000)).unwrap();
        assert_eq!(settings.part, Part::Settings);
        assert_eq!(
            of_pid(&roots, 6003, ".quickshell-wra", 77, Some(1000)),
            None,
            "another config is not the shell"
        );
        assert_eq!(
            of_pid(&roots, 6004, ".quickshell-wra", 77, Some(1000)),
            None,
            "no directory: not the shell"
        );
    }

    #[test]
    fn a_relative_run_directory_counts_from_the_working_directory() {
        let (_dir, roots) = roots();
        process(
            &roots,
            6010,
            Some("/nix/store/bbb-quickshell/bin/.quickshell-wrapped"),
            Some("qs -p ."),
        );
        std::os::unix::fs::symlink(
            "/nix/store/ccc-kurashi/share/kurashi/frontend",
            roots.proc.join("6010/cwd"),
        )
        .unwrap();
        let own = of_pid(&roots, 6010, ".quickshell-wra", 77, Some(1000)).unwrap();
        assert_eq!(own.part, Part::Frontend);
    }

    #[test]
    fn identity_falls_back_to_the_command_name_when_the_executable_is_unreadable() {
        let (_dir, roots) = roots();
        // Not dumpable: no exe link, but the command line is still readable for the owner.
        process(
            &roots,
            6020,
            None,
            Some("qs -p /nix/store/ccc-kurashi/share/kurashi/frontend"),
        );
        let own = of_pid(&roots, 6020, ".quickshell-wra", 77, Some(1000)).unwrap();
        assert_eq!(own.part, Part::Frontend);
        process(&roots, 6021, None, None);
        assert_eq!(
            of_pid(&roots, 6021, "kurashid", 77, Some(1000))
                .unwrap()
                .part,
            Part::Daemon
        );
    }

    #[test]
    fn an_ordinary_program_and_a_reused_pid_are_not_the_shell() {
        let (_dir, roots) = roots();
        process(
            &roots,
            6030,
            Some("/usr/lib/firefox/firefox"),
            Some("firefox -P default"),
        );
        assert_eq!(of_pid(&roots, 6030, "firefox", 77, Some(1000)), None);
        // The pid was a kurashid when the list was read; now it runs something else under the same name.
        process(&roots, 6031, Some("/usr/bin/kurashid-helper-tool"), None);
        assert_eq!(of_pid(&roots, 6031, "kurashid", 77, Some(1000)), None);
    }
}
