//! Firefox-family profiles (I422, K100): where each machine's are, from the browser's own `profiles.ini`, never a hardcoded name.
//! `svc.theme_export` lists them for Settings; `theme.export.link` is the one thing here that writes into a profile, and only
//! on the user's click: the import at the top of its `chrome/userChrome.css`, the prefs it needs in a marked block of its `user.js`.
//! Taken back by the same action: only those lines go.

use std::path::{Path, PathBuf};

/// One profile as `profiles.ini` names it.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Profile {
    pub name: String,
    pub dir: PathBuf,
    /// The one the browser opens: an `[Install…]` section's `Default`, else the profile's `Default=1`.
    pub default: bool,
}

/// `profiles.ini` under `root` read. Unknown keys are the browser's own business.
pub fn profiles(root: &Path) -> Vec<Profile> {
    let Ok(text) = std::fs::read_to_string(root.join("profiles.ini")) else {
        return Vec::new();
    };
    parse(&text, root)
}

fn parse(text: &str, root: &Path) -> Vec<Profile> {
    #[derive(Default)]
    struct Sec {
        name: String,
        path: String,
        relative: bool,
        default: bool,
    }
    let mut out: Vec<Sec> = Vec::new();
    let mut install: Option<String> = None;
    let mut kind = "";
    for raw in text.lines() {
        let line = raw.trim();
        if let Some(s) = line.strip_prefix('[').and_then(|l| l.strip_suffix(']')) {
            kind = if s.starts_with("Profile") && s != "Profile Groups" {
                out.push(Sec {
                    relative: true,
                    ..Sec::default()
                });
                "profile"
            } else if s.starts_with("Install") {
                "install"
            } else {
                ""
            };
            continue;
        }
        let Some((k, v)) = line.split_once('=') else {
            continue;
        };
        match (kind, k.trim()) {
            ("install", "Default") if install.is_none() => install = Some(v.trim().to_owned()),
            ("profile", key) => {
                let Some(p) = out.last_mut() else { continue };
                match key {
                    "Name" => p.name = v.trim().to_owned(),
                    "Path" => p.path = v.trim().to_owned(),
                    "IsRelative" => p.relative = v.trim() != "0",
                    "Default" => p.default = v.trim() == "1",
                    _ => {}
                }
            }
            _ => {}
        }
    }
    let mut profiles: Vec<Profile> = out
        .into_iter()
        .filter(|s| !s.path.is_empty())
        .map(|s| Profile {
            default: match &install {
                Some(path) => *path == s.path,
                None => s.default,
            },
            dir: if s.relative {
                root.join(&s.path)
            } else {
                PathBuf::from(&s.path)
            },
            name: if s.name.is_empty() { s.path } else { s.name },
        })
        .collect();
    profiles.sort_by_key(|p| (!p.default, p.name.clone()));
    profiles
}

/// Where a browser's `profiles.ini` lives on this machine.
pub fn root_of(target: &str, home: &Path, config_home: &Path) -> Option<PathBuf> {
    match target {
        "zen" => Some(home.join(".zen")),
        // (Firefox moved under XDG on new installs; an old install stays where it was.)
        "firefox" => {
            let old = home.join(".mozilla/firefox");
            let new = config_home.join("mozilla/firefox");
            Some(
                if old.join("profiles.ini").is_file() || !new.join("profiles.ini").is_file() {
                    old
                } else {
                    new
                },
            )
        }
        _ => None,
    }
}

const BEGIN: &str = "// kurashi: begin (written by the shell; `Unlink` in Settings takes it back)";
const END: &str = "// kurashi: end";

/// `userChrome.css` with the import at the very top (`@import` must come first) or without it.
fn with_import(css: &str, line: &str, on: bool) -> String {
    let rest: String = css
        .lines()
        .filter(|l| l.trim() != line.trim())
        .collect::<Vec<_>>()
        .join("\n");
    let rest = rest.trim_start_matches('\n');
    if on {
        if rest.is_empty() {
            format!("{line}\n")
        } else {
            format!("{line}\n{rest}\n")
        }
    } else if rest.is_empty() {
        String::new()
    } else {
        format!("{rest}\n")
    }
}

/// `user.js` with the marked block holding `prefs` (`name`, its JS value), or without it. The rest of the file is left as it is.
pub fn with_prefs(js: &str, prefs: &[(&str, &str)], on: bool) -> String {
    let mut out = Vec::new();
    let mut inside = false;
    for l in js.lines() {
        if l.trim() == BEGIN {
            inside = true;
        } else if l.trim() == END {
            inside = false;
        } else if !inside {
            out.push(l.to_owned());
        }
    }
    while out.last().is_some_and(|l: &String| l.trim().is_empty()) {
        out.pop();
    }
    if on {
        if !out.is_empty() {
            out.push(String::new());
        }
        out.push(BEGIN.to_owned());
        for (k, v) in prefs {
            out.push(format!("user_pref(\"{k}\", {v});"));
        }
        out.push(END.to_owned());
    }
    if out.is_empty() {
        String::new()
    } else {
        out.join("\n") + "\n"
    }
}

/// Whether the import stands in the profile.
pub fn linked(dir: &Path, line: &str) -> bool {
    std::fs::read_to_string(dir.join("chrome/userChrome.css"))
        .is_ok_and(|c| c.lines().any(|l| l.trim() == line.trim()))
}

/// The user's click: the import and the prefs in, or out. Only the shell's own lines are touched.
pub fn set_link(dir: &Path, line: &str, prefs: &[(&str, &str)], on: bool) -> std::io::Result<()> {
    let chrome = dir.join("chrome");
    let css_path = chrome.join("userChrome.css");
    let css = std::fs::read_to_string(&css_path).unwrap_or_default();
    let next = with_import(&css, line, on);
    if next != css {
        std::fs::create_dir_all(&chrome)?;
        std::fs::write(&css_path, next)?;
    }
    sync_prefs(dir, prefs, on)
}

/// The block in `user.js` as `prefs` says (a linked profile, after a toggle).
pub fn sync_prefs(dir: &Path, prefs: &[(&str, &str)], on: bool) -> std::io::Result<()> {
    let path = dir.join("user.js");
    let js = std::fs::read_to_string(&path).unwrap_or_default();
    let next = with_prefs(&js, prefs, on);
    if next != js {
        std::fs::write(&path, next)?;
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    const INI: &str = "[General]\nStartWithLastProfile=1\n\n[Profile0]\nName=default\nIsRelative=1\nPath=95hxj346.default\nDefault=1\n\n[Profile2]\nName=migrated\nIsRelative=1\nPath=kyw28fqm.migrated\n\n[Profile1]\nName=maike\nIsRelative=0\nPath=/abs/maike\n\n[Profile Groups]\nx=y\n";

    #[test]
    fn profiles_come_from_the_ini_with_the_default_first() {
        let p = parse(INI, Path::new("/home/u/.zen"));
        assert_eq!(p.len(), 3);
        assert_eq!(p[0].name, "default");
        assert!(p[0].default);
        assert_eq!(p[0].dir, Path::new("/home/u/.zen/95hxj346.default"));
        assert_eq!(p[1].name, "maike");
        assert_eq!(p[1].dir, Path::new("/abs/maike"));
    }

    #[test]
    fn an_install_section_names_the_default() {
        let t = format!("[InstallABC]\nDefault=kyw28fqm.migrated\nLocked=1\n\n{INI}");
        let p = parse(&t, Path::new("/z"));
        assert_eq!(p[0].name, "migrated");
        assert!(p[0].default);
        assert!(!p.iter().any(|q| q.name == "default" && q.default));
    }

    #[test]
    fn the_import_goes_first_and_comes_back_out_alone() {
        let line = "@import url(\"file:///x.css\");";
        let mine = "/* mine */\n#foo { color: red }\n";
        let on = with_import(mine, line, true);
        assert!(on.starts_with(line));
        assert!(on.contains("#foo"));
        assert_eq!(with_import(&on, line, true), on);
        assert_eq!(with_import(&on, line, false), mine);
        assert_eq!(with_import(line, line, false), "");
    }

    #[test]
    fn the_prefs_block_leaves_the_rest_of_user_js() {
        let mine = "user_pref(\"a\", 1);\n";
        let on = with_prefs(mine, &[("b", "true")], true);
        assert!(on.contains("user_pref(\"a\", 1);"));
        assert!(on.contains("user_pref(\"b\", true);"));
        // A toggle replaces the block, it does not pile up.
        let again = with_prefs(&on, &[("c", "false")], true);
        assert!(!again.contains("\"b\"") && again.contains("\"c\""));
        assert_eq!(with_prefs(&on, &[], false), mine);
    }
}
