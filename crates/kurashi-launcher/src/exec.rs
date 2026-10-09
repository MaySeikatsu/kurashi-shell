//! Exec key expansion and detached spawning.
//!
//! `build_command` is pure (tests assert the argv); `spawn` is the only function that starts a
//! process and is never called from tests.

use std::os::unix::process::CommandExt;
use std::process::{Command, Stdio};

use crate::LaunchError;

/// What to run. `exec` comes from the entry or one of its actions.
#[derive(Debug, Clone)]
pub struct Target<'a> {
    pub exec: &'a str,
    pub name: &'a str,
    pub icon: Option<&'a str>,
    /// Path of the `.desktop` file (`%k`).
    pub desktop_path: &'a str,
    pub terminal: bool,
}

#[derive(Debug, Clone)]
pub struct LaunchOptions {
    /// Terminal prefix for `Terminal=true` entries, e.g. `["foot", "-e"]`.
    pub terminal_cmd: Vec<String>,
    /// Wrap in `systemd-run --user --scope` so the app leaves the daemon's cgroup.
    pub systemd_scope: bool,
}

impl Default for LaunchOptions {
    fn default() -> Self {
        Self {
            terminal_cmd: vec!["xterm".into(), "-e".into()],
            systemd_scope: false,
        }
    }
}

/// Split an Exec value into arguments per the spec's quoting rules: double quotes group,
/// and inside quotes `\"`, `` \` ``, `\$`, `\\` are escapes. (The value-level `\\` unescape
/// has already happened in the parser.)
fn split_exec(s: &str) -> Result<Vec<String>, LaunchError> {
    let mut args = Vec::new();
    let mut cur = String::new();
    let mut in_arg = false;
    let mut quoted = false;
    let mut it = s.chars().peekable();
    while let Some(c) = it.next() {
        if quoted {
            match c {
                '"' => quoted = false,
                '\\' => match it.peek() {
                    Some(&n) if matches!(n, '"' | '`' | '$' | '\\') => {
                        cur.push(n);
                        it.next();
                    }
                    _ => cur.push('\\'),
                },
                _ => cur.push(c),
            }
        } else {
            match c {
                '"' => {
                    quoted = true;
                    in_arg = true;
                }
                c if c.is_whitespace() => {
                    if in_arg {
                        args.push(std::mem::take(&mut cur));
                        in_arg = false;
                    }
                }
                _ => {
                    cur.push(c);
                    in_arg = true;
                }
            }
        }
    }
    if quoted {
        return Err(LaunchError::BadExec("unterminated quote".into()));
    }
    if in_arg {
        args.push(cur);
    }
    Ok(args)
}

/// Expand field codes. `files` are the paths/URLs the caller wants opened (may be empty).
pub fn expand(t: &Target<'_>, files: &[String]) -> Result<Vec<String>, LaunchError> {
    let mut out = Vec::new();
    for arg in split_exec(t.exec)? {
        // A bare %F / %U is a list code: it becomes zero or more arguments.
        if arg == "%F" || arg == "%U" {
            out.extend(files.iter().cloned());
            continue;
        }
        // %i expands to two arguments, so it must stand alone.
        if arg == "%i" {
            if let Some(icon) = t.icon {
                out.push("--icon".into());
                out.push(icon.into());
            }
            continue;
        }
        let mut s = String::with_capacity(arg.len());
        let mut it = arg.chars();
        while let Some(c) = it.next() {
            if c != '%' {
                s.push(c);
                continue;
            }
            match it.next() {
                Some('%') => s.push('%'),
                Some('f' | 'u') => {
                    if let Some(f) = files.first() {
                        s.push_str(f);
                    }
                }
                Some('F' | 'U') => s.push_str(&files.join(" ")),
                Some('c') => s.push_str(t.name),
                Some('k') => s.push_str(t.desktop_path),
                Some('i') => {} // embedded %i is not valid; drop
                // Deprecated codes are removed (spec Appendix B).
                Some('d' | 'D' | 'n' | 'N' | 'v' | 'm') => {}
                Some(o) => return Err(LaunchError::BadExec(format!("unknown field code %{o}"))),
                None => return Err(LaunchError::BadExec("trailing %".into())),
            }
        }
        // An argument that was only a single-file code with no file given vanishes, so
        // `app %f` launches as plain `app`.
        if s.is_empty() && arg.starts_with('%') && arg.len() == 2 {
            continue;
        }
        out.push(s);
    }
    if out.is_empty() {
        return Err(LaunchError::BadExec("empty command".into()));
    }
    Ok(out)
}

/// Full argv including terminal and systemd-run wrapping.
pub fn build_command(
    t: &Target<'_>,
    files: &[String],
    opts: &LaunchOptions,
) -> Result<Vec<String>, LaunchError> {
    let mut argv = expand(t, files)?;
    if t.terminal {
        if opts.terminal_cmd.is_empty() {
            return Err(LaunchError::NoTerminal);
        }
        let mut full = opts.terminal_cmd.clone();
        full.extend(argv);
        argv = full;
    }
    if opts.systemd_scope {
        let mut full: Vec<String> = [
            "systemd-run",
            "--user",
            "--scope",
            "--quiet",
            "--collect",
            "--",
        ]
        .map(String::from)
        .into();
        full.extend(argv);
        argv = full;
    }
    Ok(argv)
}

/// Start `argv` detached: own process group, no stdio, no inherited `KURASHI_*` variables.
/// Returns the pid. A reaper thread waits on the child so it never lingers as a zombie.
pub fn spawn(argv: &[String]) -> Result<u32, LaunchError> {
    let (prog, args) = argv
        .split_first()
        .ok_or(LaunchError::BadExec("empty".into()))?;
    let mut cmd = Command::new(prog);
    cmd.args(args)
        .stdin(Stdio::null())
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .process_group(0);
    for (k, _) in std::env::vars_os() {
        if k.to_string_lossy().starts_with("KURASHI_") {
            cmd.env_remove(k);
        }
    }
    let mut child = cmd
        .spawn()
        .map_err(|e| LaunchError::Spawn(prog.clone(), e))?;
    let pid = child.id();
    std::thread::spawn(move || {
        let _ = child.wait();
    });
    Ok(pid)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn t<'a>(exec: &'a str) -> Target<'a> {
        Target {
            exec,
            name: "My App",
            icon: Some("myicon"),
            desktop_path: "/usr/share/applications/my.desktop",
            terminal: false,
        }
    }

    fn files(f: &[&str]) -> Vec<String> {
        f.iter().map(|s| s.to_string()).collect()
    }

    fn argv(exec: &str, f: &[&str]) -> Vec<String> {
        expand(&t(exec), &files(f)).unwrap()
    }

    #[test]
    fn expansion_table() {
        let cases: &[(&str, &[&str], &[&str])] = &[
            ("app", &[], &["app"]),
            ("app %f", &[], &["app"]),
            ("app %u", &["a b"], &["app", "a b"]),
            ("app %f", &["x", "y"], &["app", "x"]),
            ("app %F", &["x", "y"], &["app", "x", "y"]),
            ("app %U", &[], &["app"]),
            ("app --file=%f", &["x"], &["app", "--file=x"]),
            ("app --file=%f", &[], &["app", "--file="]),
            ("app %i", &[], &["app", "--icon", "myicon"]),
            ("app %c", &[], &["app", "My App"]),
            (
                "app %k",
                &[],
                &["app", "/usr/share/applications/my.desktop"],
            ),
            ("app 100%%", &[], &["app", "100%"]),
            ("app %d %D %n %N %v %m", &[], &["app"]),
            (
                r#"app "two words" 'sq'"#,
                &[],
                &["app", "two words", "'sq'"],
            ),
            (
                r#"sh -c "echo \"hi\" \$HOME""#,
                &[],
                &["sh", "-c", r#"echo "hi" $HOME"#],
            ),
            (r#"app "%f""#, &["x y"], &["app", "x y"]),
            ("  app   a    b ", &[], &["app", "a", "b"]),
        ];
        for (exec, f, want) in cases {
            assert_eq!(argv(exec, f), *want, "exec={exec:?} files={f:?}");
        }
    }

    #[test]
    fn expansion_errors() {
        assert!(expand(&t("app %z"), &[]).is_err());
        assert!(expand(&t("app %"), &[]).is_err());
        assert!(expand(&t(r#"app "unterminated"#), &[]).is_err());
        assert!(expand(&t("   "), &[]).is_err());
    }

    #[test]
    fn icon_omitted_when_none() {
        let mut tt = t("app %i");
        tt.icon = None;
        assert_eq!(expand(&tt, &[]).unwrap(), ["app"]);
    }

    #[test]
    fn terminal_and_scope_wrapping() {
        let mut tt = t("htop");
        tt.terminal = true;
        let opts = LaunchOptions {
            terminal_cmd: vec!["foot".into(), "-e".into()],
            systemd_scope: false,
        };
        assert_eq!(
            build_command(&tt, &[], &opts).unwrap(),
            ["foot", "-e", "htop"]
        );

        let opts = LaunchOptions {
            systemd_scope: true,
            ..opts
        };
        assert_eq!(
            build_command(&tt, &[], &opts).unwrap(),
            [
                "systemd-run",
                "--user",
                "--scope",
                "--quiet",
                "--collect",
                "--",
                "foot",
                "-e",
                "htop"
            ]
        );

        let none = LaunchOptions {
            terminal_cmd: vec![],
            systemd_scope: false,
        };
        assert!(matches!(
            build_command(&tt, &[], &none),
            Err(LaunchError::NoTerminal)
        ));
    }
}
