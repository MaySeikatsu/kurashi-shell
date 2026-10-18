//! What a process is called in the list (I61, docs/ux/sysmon.md). The kernel keeps 15 bytes of a command name, and a
//! Nix wrapper hides the real program behind a dotted name: `.quickshell-wrapped` shows as `.quickshell-wra`, and a
//! browser's content process as `Isolated Web Co`. The list names a process by its executable's basename with the
//! wrapper's marks removed, or by the `Name` of the desktop entry that starts that program. The full command line goes
//! to the accessible description. Names are read for the rows the list shows (and the culprit), never for all of them.

use crate::roots::Roots;
use std::collections::HashMap;
use std::path::Path;
use std::sync::OnceLock;

/// The kernel's limit on a command name, counting no terminator: longer names are cut to it.
const KERNEL_COMM_MAX: usize = 15;
/// The longest command line kept: a screen reader reads all of it, so a longer one is cut.
const COMMAND_MAX: usize = 240;
/// Interpreters and launchers: a desktop entry that starts one names the script, not an application.
const GENERIC_PROGRAMS: [&str; 8] = [
    "sh", "bash", "zsh", "fish", "env", "python", "python3", "java",
];

/// An executable's name without a Nix wrapper's marks: a leading dot and a trailing `-wrapped`.
pub fn clean_exe(base: &str) -> &str {
    let name = base.strip_prefix('.').unwrap_or(base);
    name.strip_suffix("-wrapped").unwrap_or(name)
}

/// A command name, cleaned the same way. A name at the kernel's limit may have lost the end of `-wrapped`, so a
/// trailing part of it goes too (`.zen-twilight-w` is `zen-twilight`).
pub fn clean_comm(comm: &str) -> &str {
    let name = comm.strip_prefix('.').unwrap_or(comm);
    if comm.len() >= KERNEL_COMM_MAX {
        if let Some(at) = name.rfind('-') {
            let tail = &name[at + 1..];
            if !tail.is_empty() && "wrapped".starts_with(tail) {
                return &name[..at];
            }
        }
    }
    name.strip_suffix("-wrapped").unwrap_or(name)
}

/// The program's name for a process: its executable's basename when the link is readable, else its command name.
/// Cleaned, so the same program has the same name whatever the kernel kept.
pub fn program_name<'a>(comm: &'a str, exe: Option<&'a str>) -> &'a str {
    match exe {
        Some(exe) => clean_exe(exe),
        None => clean_comm(comm),
    }
}

/// The executable's basename, from the link `/proc/<pid>/exe`. A binary replaced since the process started (a rebuild)
/// reads `… (deleted)`: the name stays the program's. None when the link cannot be read.
pub fn exe_base(roots: &Roots, pid: i32) -> Option<String> {
    let link = roots.link(roots.proc.join(pid.to_string()).join("exe"))?;
    let name = link.file_name()?.to_str()?;
    let name = name.strip_suffix(" (deleted)").unwrap_or(name);
    (!name.is_empty()).then(|| name.to_string())
}

/// The name a row shows: the `Name` of the desktop entry that starts the program, else the program's own name.
pub fn display(roots: &Roots, apps: &Apps, pid: i32, comm: &str, exe: Option<&str>) -> String {
    let program = program_name(comm, exe);
    apps.name_of(roots, program).unwrap_or_else(|| {
        if program.is_empty() {
            pid.to_string()
        } else {
            program.to_string()
        }
    })
}

/// The full command line, its arguments joined by spaces and cut at [`COMMAND_MAX`] characters. None for a kernel
/// thread, which has no arguments.
pub fn command_line(roots: &Roots, pid: i32) -> Option<String> {
    let raw = roots.read_bytes(roots.proc.join(pid.to_string()).join("cmdline"))?;
    let args: Vec<String> = raw
        .split(|b| *b == 0)
        .filter(|a| !a.is_empty())
        .map(|a| String::from_utf8_lossy(a).into_owned())
        .collect();
    if args.is_empty() {
        return None;
    }
    let line = args.join(" ");
    if line.chars().count() <= COMMAND_MAX {
        return Some(line);
    }
    let cut: String = line.chars().take(COMMAND_MAX).collect();
    Some(format!("{cut}…"))
}

/// The applications of the desktop entries, by the program each one starts. Read once, on the first name that needs
/// one, so a list nobody looks at reads no desktop entry.
#[derive(Default)]
pub struct Apps(OnceLock<HashMap<String, String>>);

impl Apps {
    /// The `Name` of the first desktop entry (in directory precedence order) whose program is `program`.
    pub fn name_of(&self, roots: &Roots, program: &str) -> Option<String> {
        self.0.get_or_init(|| index(roots)).get(program).cloned()
    }
}

fn index(roots: &Roots) -> HashMap<String, String> {
    let mut out = HashMap::new();
    for dir in &roots.apps {
        for file in roots.list(dir) {
            if file.extension().and_then(|e| e.to_str()) != Some("desktop") {
                continue;
            }
            let Some(text) = roots.read(&file) else {
                continue;
            };
            if let Some((program, name)) = parse_entry(&text) {
                out.entry(program).or_insert(name);
            }
        }
    }
    out
}

/// The program and the name of a desktop entry, from its `[Desktop Entry]` section. None without an `Exec` or a
/// `Name`, or when the program is a generic launcher.
fn parse_entry(text: &str) -> Option<(String, String)> {
    let mut section = "";
    let mut name = None;
    let mut exec = None;
    for line in text.lines() {
        let line = line.trim();
        if let Some(s) = line.strip_prefix('[').and_then(|l| l.strip_suffix(']')) {
            section = s;
            continue;
        }
        if section != "Desktop Entry" {
            continue;
        }
        if let Some(v) = line.strip_prefix("Name=") {
            name.get_or_insert_with(|| v.trim().to_string());
        } else if let Some(v) = line.strip_prefix("Exec=") {
            exec.get_or_insert_with(|| v.trim().to_string());
        }
    }
    let program = exec_program(&exec?)?;
    if GENERIC_PROGRAMS.contains(&program.as_str()) {
        return None;
    }
    Some((program, name?))
}

/// The program an `Exec` line starts: its first word that is neither `env` nor an assignment, by its cleaned basename.
fn exec_program(exec: &str) -> Option<String> {
    let word = exec
        .split_whitespace()
        .find(|w| *w != "env" && !w.contains('='))?;
    let base = Path::new(word.trim_matches('"')).file_name()?.to_str()?;
    Some(clean_exe(base).to_string())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn a_nix_wrapper_shows_its_program() {
        for (raw, want) in [
            (".quickshell-wrapped", "quickshell"),
            (".kurashid-wrapped", "kurashid"),
            (".zen-twilight-wrapped", "zen-twilight"),
            ("firefox", "firefox"),
            ("Web Content", "Web Content"),
        ] {
            assert_eq!(clean_exe(raw), want, "exe {raw}");
        }
    }

    #[test]
    fn a_command_name_cut_by_the_kernel_is_cleaned_too() {
        for (raw, want) in [
            (".quickshell-wra", "quickshell"),
            (".zen-twilight-w", "zen-twilight"),
            ("Isolated Web Co", "Isolated Web Co"),
            ("pipewire-pulse", "pipewire-pulse"),
            ("xdg-desktop-por", "xdg-desktop-por"),
            ("kurashid", "kurashid"),
        ] {
            assert_eq!(clean_comm(raw), want, "comm {raw}");
        }
    }

    #[test]
    fn the_executable_names_a_process_and_the_command_name_is_the_fallback() {
        assert_eq!(
            program_name(".quickshell-wra", Some(".quickshell-wrapped")),
            "quickshell"
        );
        assert_eq!(
            program_name("Isolated Web Co", Some(".firefox-wrapped")),
            "firefox"
        );
        assert_eq!(program_name(".quickshell-wra", None), "quickshell");
    }

    #[test]
    fn a_replaced_binary_keeps_its_program_name() {
        let dir = tempfile::tempdir().unwrap();
        let roots = Roots::new(dir.path().join("proc"), dir.path().join("sys"), 1000);
        let pid = dir.path().join("proc/77");
        std::fs::create_dir_all(&pid).unwrap();
        std::os::unix::fs::symlink(
            "/nix/store/abc-kurashid/bin/kurashid (deleted)",
            pid.join("exe"),
        )
        .unwrap();
        assert_eq!(exe_base(&roots, 77).as_deref(), Some("kurashid"));
        assert_eq!(
            exe_base(&roots, 78),
            None,
            "no such process: no name from the link"
        );
    }

    #[test]
    fn a_desktop_entry_names_the_program_it_starts_and_a_generic_launcher_names_nothing() {
        let dir = tempfile::tempdir().unwrap();
        let apps = dir.path().join("share/applications");
        std::fs::create_dir_all(&apps).unwrap();
        std::fs::write(
            apps.join("firefox.desktop"),
            "[Desktop Entry]\nName=Firefox\nName[ja]=Firefox ja\nExec=env MOZ_X=1 /usr/lib/firefox/firefox %u\n",
        )
        .unwrap();
        std::fs::write(
            apps.join("script.desktop"),
            "[Desktop Entry]\nName=A script\nExec=sh -c 'x'\n",
        )
        .unwrap();
        let roots = Roots::fixture(dir.path(), 1000);
        let index = Apps::default();
        assert_eq!(index.name_of(&roots, "firefox").as_deref(), Some("Firefox"));
        assert_eq!(
            index.name_of(&roots, "sh"),
            None,
            "a launcher names no application"
        );
        assert_eq!(
            display(
                &roots,
                &index,
                5,
                "Isolated Web Co",
                Some(".firefox-wrapped")
            ),
            "Firefox"
        );
        assert_eq!(
            display(&roots, &index, 6, "kurashid", None),
            "kurashid",
            "no entry: the program's name"
        );
    }

    #[test]
    fn the_command_line_is_its_arguments_and_a_kernel_thread_has_none() {
        let dir = tempfile::tempdir().unwrap();
        let roots = Roots::new(dir.path().join("proc"), dir.path().join("sys"), 1000);
        let pid = dir.path().join("proc/9");
        std::fs::create_dir_all(&pid).unwrap();
        std::fs::write(pid.join("cmdline"), b"qs\0-p\0/x/frontend\0").unwrap();
        assert_eq!(
            command_line(&roots, 9).as_deref(),
            Some("qs -p /x/frontend")
        );
        std::fs::write(pid.join("cmdline"), b"").unwrap();
        assert_eq!(command_line(&roots, 9), None);
        std::fs::write(pid.join("cmdline"), "x".repeat(300)).unwrap();
        let cut = command_line(&roots, 9).unwrap();
        assert_eq!(
            cut.chars().count(),
            COMMAND_MAX + 1,
            "cut, with an ellipsis"
        );
    }
}
