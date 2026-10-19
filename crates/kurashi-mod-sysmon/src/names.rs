//! What a process is called in the list (I61, I65, docs/ux/sysmon.md). The kernel keeps 15 bytes of a command name, and a
//! Nix wrapper hides the real program behind a dotted name: `.quickshell-wrapped` shows as `.quickshell-wra`, and a
//! browser's content process as `Isolated Web Co`. The list names a process by its executable's basename with the
//! wrapper's marks removed. An executable named by a version or a hash (`…/claude/versions/2.1.302`) names nothing, so
//! the program is the next meaningful directory above it, else what argv[0] names. Then the `Name` of the desktop entry
//! that starts that program is used, in the session's language (`Name[ja]` under ja). The full command line goes to the
//! accessible description. Names are read for the rows the list shows (and the culprit), never for all of them.
//! The desktop entries are indexed once and read again when an applications directory changes; the process scan checks
//! the directories, and so runs only while the list is subscribed (Ma).

use crate::roots::Roots;
use std::collections::HashMap;
use std::path::{Path, PathBuf};
use std::sync::Mutex;
use std::time::SystemTime;

/// The kernel's limit on a command name, counting no terminator: longer names are cut to it.
const KERNEL_COMM_MAX: usize = 15;
/// The longest command line kept: a screen reader reads all of it, so a longer one is cut.
const COMMAND_MAX: usize = 240;
/// Interpreters and launchers: a desktop entry that starts one names the script, not an application.
const GENERIC_PROGRAMS: [&str; 8] = [
    "sh", "bash", "zsh", "fish", "env", "python", "python3", "java",
];
/// Directories that say where a file is kept, not what program it is: skipped when a versioned file is named.
const GENERIC_DIRS: [&str; 19] = [
    "bin",
    "versions",
    "libexec",
    "lib",
    "lib64",
    "share",
    "local",
    "cache",
    "current",
    "releases",
    "usr",
    "opt",
    "nix",
    "store",
    "x86_64-linux",
    "target",
    "release",
    "debug",
    "dist",
];
/// How many directories above a versioned executable are looked at for the program's name.
const PATH_DEPTH: usize = 3;

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

/// A name that says nothing of the program: a version (`2.1.302`, `v1.0-rc1`) or a hash (`3f9a2c7e`).
pub fn opaque(name: &str) -> bool {
    let version = name.strip_prefix('v').unwrap_or(name);
    let number = version.split(['-', '+']).next().unwrap_or("");
    let is_version = number.starts_with(|c: char| c.is_ascii_digit())
        && number.chars().all(|c| c.is_ascii_digit() || c == '.');
    let is_hash = name.len() >= 8
        && name.bytes().all(|b| b.is_ascii_hexdigit())
        && name.bytes().any(|b| b.is_ascii_digit())
        && name.bytes().any(|b| b.is_ascii_alphabetic());
    is_version || is_hash
}

/// The executable's path, from the link `/proc/<pid>/exe`, without the ` (deleted)` a replaced binary carries. None
/// when the link cannot be read.
pub fn exe_path(roots: &Roots, pid: i32) -> Option<PathBuf> {
    let link = roots.link(roots.proc.join(pid.to_string()).join("exe"))?;
    let text = link.to_str()?;
    Some(PathBuf::from(
        text.strip_suffix(" (deleted)").unwrap_or(text),
    ))
}

/// The executable's basename, from the link `/proc/<pid>/exe`. A binary replaced since the process started (a rebuild)
/// reads `… (deleted)`: the name stays the program's. None when the link cannot be read.
pub fn exe_base(roots: &Roots, pid: i32) -> Option<String> {
    let path = exe_path(roots, pid)?;
    let name = path.file_name()?.to_str()?;
    (!name.is_empty()).then(|| name.to_string())
}

/// The program a process runs, as the list names it before any desktop entry (see the module docs): the executable's
/// name, unless that is a version or a hash; then the next meaningful directory above the executable, then argv[0]'s
/// program, then the name the kernel kept.
pub fn program_label(roots: &Roots, pid: i32, comm: &str, exe: Option<&str>) -> String {
    let name = program_name(comm, exe);
    if !opaque(name) {
        return name.to_string();
    }
    if let Some(dir) = exe_path(roots, pid).and_then(|path| meaningful_dir(&path)) {
        return dir;
    }
    argv0_program(roots, pid).unwrap_or_else(|| name.to_string())
}

/// The first directory above an executable that names a program: skipping directories that only say where files are
/// kept, versions and hashes, and Nix store entries are read by the name they were built under.
fn meaningful_dir(exe: &Path) -> Option<String> {
    exe.ancestors()
        .skip(1)
        .take(PATH_DEPTH)
        .filter_map(|dir| dir.file_name()?.to_str())
        .find_map(|dir| {
            let name = store_name(dir);
            let clean = clean_exe(&name);
            (!clean.is_empty() && !opaque(clean) && !GENERIC_DIRS.contains(&clean))
                .then(|| clean.to_string())
        })
}

/// A directory name as the program it was built for: a Nix store entry (`<32 hash characters>-<name>-<version>`)
/// loses its hash and its version.
fn store_name(dir: &str) -> String {
    let rest = match dir.split_once('-') {
        Some((hash, rest))
            if hash.len() == 32
                && hash
                    .bytes()
                    .all(|b| b.is_ascii_lowercase() || b.is_ascii_digit()) =>
        {
            rest
        }
        _ => dir,
    };
    match rest.rfind('-') {
        Some(at) if at > 0 && rest[at + 1..].starts_with(|c: char| c.is_ascii_digit()) => {
            rest[..at].to_string()
        }
        _ => rest.to_string(),
    }
}

/// The program argv[0] names (its basename, cleaned), when that names a program and not a version or a hash.
fn argv0_program(roots: &Roots, pid: i32) -> Option<String> {
    let raw = roots.read_bytes(roots.proc.join(pid.to_string()).join("cmdline"))?;
    let first = raw.split(|b| *b == 0).next()?;
    let text = String::from_utf8_lossy(first);
    let base = Path::new(text.as_ref()).file_name()?.to_str()?;
    let clean = clean_exe(base);
    (!clean.is_empty() && !opaque(clean)).then(|| clean.to_string())
}

/// The name a row shows: the `Name` of the desktop entry that starts the program, else the program's own name.
pub fn display(roots: &Roots, apps: &Apps, pid: i32, comm: &str, exe: Option<&str>) -> String {
    let program = program_label(roots, pid, comm, exe);
    apps.name_of(roots, &program).unwrap_or_else(|| {
        if program.is_empty() {
            pid.to_string()
        } else {
            program
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

/// The applications of the desktop entries, by the program each one starts, named in the session's language. The index
/// is read on the first name that needs one, and read again when an applications directory changed since (see
/// [`Apps::refresh`]), so a list nobody looks at reads no desktop entry.
pub struct Apps {
    lang: String,
    index: Mutex<Option<Index>>,
}

/// The applications read, and the modification times of the directories they were read from.
struct Index {
    stamp: Vec<Option<SystemTime>>,
    names: HashMap<String, String>,
}

impl Apps {
    /// The index for `lang` (a language tag such as `ja`, as [`crate::roots::language_from_env`] gives it).
    pub fn new(lang: &str) -> Self {
        Self {
            lang: lang.to_string(),
            index: Mutex::new(None),
        }
    }

    /// Reads the index again when an applications directory changed (its entries were added, removed or renamed) or
    /// when none was read yet. The process scan calls this, so the directories are checked only while it is subscribed.
    pub fn refresh(&self, roots: &Roots) {
        let stamp = stamp(roots);
        let mut index = self.index.lock().expect("apps lock");
        if index.as_ref().is_none_or(|i| i.stamp != stamp) {
            *index = Some(Index {
                stamp,
                names: index_of(roots, &self.lang),
            });
        }
    }

    /// The `Name` of the first desktop entry (in directory precedence order) whose program is `program`.
    pub fn name_of(&self, roots: &Roots, program: &str) -> Option<String> {
        let mut index = self.index.lock().expect("apps lock");
        let index = index.get_or_insert_with(|| Index {
            stamp: stamp(roots),
            names: index_of(roots, &self.lang),
        });
        index.names.get(program).cloned()
    }
}

fn stamp(roots: &Roots) -> Vec<Option<SystemTime>> {
    roots.apps.iter().map(|dir| roots.modified(dir)).collect()
}

fn index_of(roots: &Roots, lang: &str) -> HashMap<String, String> {
    let mut out = HashMap::new();
    for dir in &roots.apps {
        for file in roots.list(dir) {
            if file.extension().and_then(|e| e.to_str()) != Some("desktop") {
                continue;
            }
            let Some(text) = roots.read(&file) else {
                continue;
            };
            if let Some((program, name)) = parse_entry(&text, lang) {
                out.entry(program).or_insert(name);
            }
        }
    }
    out
}

/// The program and the name of a desktop entry, from its `[Desktop Entry]` section: the `Name` in the session's
/// language (`Name[ja]`, or `Name[ja_JP]`) when it has one, else its `Name`. None without an `Exec` or a `Name`, or when
/// the program is a generic launcher.
fn parse_entry(text: &str, lang: &str) -> Option<(String, String)> {
    let mut section = "";
    let mut name = None;
    let mut localized = None;
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
        } else if let Some((tag, v)) = line.strip_prefix("Name[").and_then(|r| r.split_once("]=")) {
            let v = v.trim();
            if localized.is_none() && !v.is_empty() && language_tag(tag) == lang {
                localized = Some(v.to_string());
            }
        }
    }
    let program = exec_program(&exec?)?;
    if GENERIC_PROGRAMS.contains(&program.as_str()) {
        return None;
    }
    Some((program, localized.or(name)?))
}

/// The language of a locale key: `ja` for `ja`, `ja_JP` and `ja@latin`.
fn language_tag(tag: &str) -> String {
    tag.split(['_', '.', '@'])
        .next()
        .unwrap_or("")
        .to_ascii_lowercase()
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
    fn versions_and_hashes_say_nothing_of_a_program() {
        for name in ["2.1.302", "v1.0-rc1", "20240101", "3f9a2c7e1b0d"] {
            assert!(opaque(name), "{name} is a version or a hash");
        }
        for name in ["claude", "kurashid", "deadbeef", "7zip", "v", "Web Content"] {
            assert!(!opaque(name), "{name} names a program");
        }
    }

    #[test]
    fn a_nix_store_entry_is_read_by_the_name_it_was_built_under() {
        let hash = "a".repeat(32);
        for (dir, want) in [
            (format!("{hash}-claude-code-2.1.302"), "claude-code"),
            ("firefox-130".to_string(), "firefox"),
            ("zen-twilight".to_string(), "zen-twilight"),
            ("claude".to_string(), "claude"),
        ] {
            assert_eq!(store_name(&dir), want, "dir {dir}");
        }
    }

    /// A process with an executable link and a command line, in a fixture `/proc`.
    fn process(roots: &Roots, pid: i32, exe: Option<&str>, cmdline: Option<&[u8]>) {
        let dir = roots.proc.join(pid.to_string());
        std::fs::create_dir_all(&dir).unwrap();
        if let Some(exe) = exe {
            std::os::unix::fs::symlink(exe, dir.join("exe")).unwrap();
        }
        if let Some(cmdline) = cmdline {
            std::fs::write(dir.join("cmdline"), cmdline).unwrap();
        }
    }

    #[test]
    fn a_versioned_executable_takes_the_program_it_is_installed_for() {
        let dir = tempfile::tempdir().unwrap();
        let roots = Roots::new(dir.path().join("proc"), dir.path().join("sys"), 1000);
        // Claude Code's layout: `…/claude/versions/2.1.302`, started as `claude`.
        process(
            &roots,
            10,
            Some("/home/u/.local/share/claude/versions/2.1.302"),
            Some(b"claude\0--resume\0"),
        );
        assert_eq!(
            program_label(&roots, 10, "2.1.302", Some("2.1.302")),
            "claude"
        );
        // A store entry of a versioned program: the program is named by its store name.
        let hash = "b".repeat(32);
        let store = format!("/nix/store/{hash}-claude-code-2.1.302/bin/2.1.302");
        process(&roots, 11, Some(&store), None);
        assert_eq!(
            program_label(&roots, 11, "2.1.302", Some("2.1.302")),
            "claude-code"
        );
        // A hash-named file in a program's own directory: the directory names it.
        process(&roots, 12, Some("/home/u/.cache/foo/3f9a2c7e"), None);
        assert_eq!(
            program_label(&roots, 12, "3f9a2c7e", Some("3f9a2c7e")),
            "foo"
        );
        // No directory names it (the file sits at the root): argv[0] does.
        process(&roots, 13, Some("/2.1.302"), Some(b"/usr/bin/tool-run\0"));
        assert_eq!(
            program_label(&roots, 13, "2.1.302", Some("2.1.302")),
            "tool-run"
        );
        // Nothing readable but the kernel's name: that name is all there is.
        process(&roots, 14, None, None);
        assert_eq!(program_label(&roots, 14, "2.1.302", None), "2.1.302");
        // An ordinary program keeps its executable's name.
        process(
            &roots,
            15,
            Some("/usr/bin/.firefox-wrapped"),
            Some(b"firefox\0"),
        );
        assert_eq!(
            program_label(&roots, 15, "Isolated Web Co", Some(".firefox-wrapped")),
            "firefox"
        );
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
            "[Desktop Entry]\nName=Firefox\nName[ja]=Firefox ウェブブラウザー\nExec=env MOZ_X=1 /usr/lib/firefox/firefox %u\n",
        )
        .unwrap();
        std::fs::write(
            apps.join("script.desktop"),
            "[Desktop Entry]\nName=A script\nExec=sh -c 'x'\n",
        )
        .unwrap();
        let roots = Roots::fixture(dir.path(), 1000);
        let index = Apps::new("en");
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
    fn the_session_language_names_the_program_in_its_own_words() {
        let dir = tempfile::tempdir().unwrap();
        let apps = dir.path().join("share/applications");
        std::fs::create_dir_all(&apps).unwrap();
        // The localized name may come before or after the plain one, and a region tag names the same language.
        std::fs::write(
            apps.join("firefox.desktop"),
            "[Desktop Entry]\nName[ja]=Firefox ウェブブラウザー\nName=Firefox\nExec=/usr/lib/firefox/firefox\n",
        )
        .unwrap();
        std::fs::write(
            apps.join("gimp.desktop"),
            "[Desktop Entry]\nName=GIMP\nName[ja_JP]=GIMP（画像編集）\nExec=gimp-2.10 %U\n",
        )
        .unwrap();
        std::fs::write(
            apps.join("mpv.desktop"),
            "[Desktop Entry]\nName=mpv Media Player\nName[de]=mpv Medienplayer\nExec=mpv --player\n",
        )
        .unwrap();
        let roots = Roots::fixture(dir.path(), 1000);
        let ja = Apps::new("ja");
        assert_eq!(
            ja.name_of(&roots, "firefox").as_deref(),
            Some("Firefox ウェブブラウザー")
        );
        assert_eq!(
            ja.name_of(&roots, "gimp-2.10").as_deref(),
            Some("GIMP（画像編集）")
        );
        assert_eq!(
            ja.name_of(&roots, "mpv").as_deref(),
            Some("mpv Media Player"),
            "no Japanese name: the plain one"
        );
        let en = Apps::new("en");
        assert_eq!(en.name_of(&roots, "firefox").as_deref(), Some("Firefox"));
    }

    #[test]
    fn the_index_is_read_again_only_when_an_applications_directory_changed() {
        let dir = tempfile::tempdir().unwrap();
        let apps = dir.path().join("share/applications");
        std::fs::create_dir_all(&apps).unwrap();
        let stamp = |secs: u64| {
            let at = SystemTime::UNIX_EPOCH + std::time::Duration::from_secs(secs);
            std::fs::File::open(&apps)
                .unwrap()
                .set_modified(at)
                .unwrap();
        };
        std::fs::write(
            apps.join("firefox.desktop"),
            "[Desktop Entry]\nName=Firefox\nExec=firefox\n",
        )
        .unwrap();
        stamp(1_000);
        let roots = Roots::fixture(dir.path(), 1000);
        let index = Apps::new("en");
        index.refresh(&roots);
        assert_eq!(index.name_of(&roots, "firefox").as_deref(), Some("Firefox"));
        // A new entry in a directory that changed: nothing shows it until the index is refreshed.
        std::fs::write(
            apps.join("gimp.desktop"),
            "[Desktop Entry]\nName=GIMP\nExec=gimp\n",
        )
        .unwrap();
        stamp(2_000);
        assert_eq!(
            index.name_of(&roots, "gimp"),
            None,
            "the index is not read on every name"
        );
        index.refresh(&roots);
        assert_eq!(index.name_of(&roots, "gimp").as_deref(), Some("GIMP"));
        // A refresh with nothing changed keeps what was read.
        index.refresh(&roots);
        assert_eq!(index.name_of(&roots, "firefox").as_deref(), Some("Firefox"));
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
