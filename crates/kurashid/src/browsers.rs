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
    let lines: Vec<&str> = css.lines().filter(|l| l.trim() != line.trim()).collect();
    if !on {
        let rest = lines.join("\n");
        let rest = rest.trim_start_matches('\n');
        return if rest.is_empty() {
            String::new()
        } else {
            format!("{rest}\n")
        };
    }
    // After the other imports at the top, so ours wins a tie with them; before everything else, where an @import must stand.
    let mut at = 0;
    for (i, l) in lines.iter().enumerate() {
        let t = l.trim();
        if t.starts_with("@import") {
            at = i + 1;
        } else if !(t.is_empty() || t.starts_with("/*")) {
            break;
        }
    }
    let mut out: Vec<&str> = lines[..at].to_vec();
    out.push(line);
    out.extend_from_slice(&lines[at..]);
    format!("{}\n", out.join("\n").trim_end_matches('\n'))
}

const OFF_OPEN: &str = "/* kurashi: off: ";
const OFF_CLOSE: &str = " */";

/// What an `@import` names, for Settings to say.
fn imported(line: &str) -> String {
    line.trim()
        .trim_start_matches("@import")
        .trim()
        .trim_start_matches("url(")
        .trim_end_matches(';')
        .trim_end_matches(')')
        .trim_matches(['"', '\''])
        .trim_start_matches("file://")
        .to_owned()
}

/// The other stylesheets a profile's `userChrome.css` imports (they can paint over the theme: another shell's, a theme of the
/// user's), and those turned off here (K100).
pub fn other_imports(dir: &Path, line: &str) -> (Vec<String>, Vec<String>) {
    let css = std::fs::read_to_string(dir.join("chrome/userChrome.css")).unwrap_or_default();
    let (mut on, mut off) = (vec![], vec![]);
    for l in css.lines().map(str::trim) {
        if l == line.trim() {
            continue;
        }
        if l.starts_with("@import") {
            on.push(imported(l));
        } else if let Some(rest) = l
            .strip_prefix(OFF_OPEN)
            .and_then(|r| r.strip_suffix(OFF_CLOSE))
        {
            off.push(imported(rest));
        }
    }
    (on, off)
}

/// The user's click: the other imports commented out with a mark, or back as they were. Only `@import` lines; `line` stays.
fn with_others(css: &str, line: &str, on: bool) -> String {
    let out: Vec<String> = css
        .lines()
        .map(|l| {
            let t = l.trim();
            if on {
                t.strip_prefix(OFF_OPEN)
                    .and_then(|r| r.strip_suffix(OFF_CLOSE))
                    .map_or_else(|| l.to_owned(), str::to_owned)
            } else if t.starts_with("@import") && t != line.trim() {
                format!("{OFF_OPEN}{t}{OFF_CLOSE}")
            } else {
                l.to_owned()
            }
        })
        .collect();
    if out.is_empty() {
        String::new()
    } else {
        out.join("\n") + "\n"
    }
}

pub fn set_others(dir: &Path, line: &str, on: bool) -> std::io::Result<()> {
    let path = dir.join("chrome/userChrome.css");
    let css = std::fs::read_to_string(&path).unwrap_or_default();
    let next = with_others(&css, line, on);
    if next != css {
        std::fs::write(&path, next)?;
    }
    Ok(())
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
    // (Unlink brings back what this turned off: the profile goes back to what the user had.)
    let css_in = if on {
        css.clone()
    } else {
        with_others(&css, line, true)
    };
    let next = with_import(&css_in, line, on);
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

    const OURS: &str = "@import url(\"file:///c/kurashi/apps/zen.css\");";
    const THEIRS: &str = "@import \"/c/noctalia/zen-userChrome.css\";";

    #[test]
    fn the_import_stands_after_the_others_and_before_the_rules() {
        let css = format!("/* mine */\n{THEIRS}\n#a {{ color: red }}\n");
        assert_eq!(
            with_import(&css, OURS, true),
            format!("/* mine */\n{THEIRS}\n{OURS}\n#a {{ color: red }}\n")
        );
        assert_eq!(
            with_import("#a {}\n", OURS, true),
            format!("{OURS}\n#a {{}}\n")
        );
        assert_eq!(with_import("", OURS, true), format!("{OURS}\n"));
        assert_eq!(
            with_import(&with_import(&css, OURS, true), OURS, false),
            css
        );
    }

    #[test]
    fn others_go_out_with_a_mark_and_come_back() {
        let css = format!("{OURS}\n{THEIRS}\n#a {{}}\n");
        let off = with_others(&css, OURS, false);
        assert!(off.contains(OURS), "{off}");
        assert!(off.contains("/* kurashi: off: @import"), "{off}");
        assert!(!off.lines().any(|l| l.trim() == THEIRS), "{off}");
        assert_eq!(with_others(&off, OURS, true), css);
        assert_eq!(imported(THEIRS), "/c/noctalia/zen-userChrome.css");
        assert_eq!(imported(OURS), "/c/kurashi/apps/zen.css");
    }

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
