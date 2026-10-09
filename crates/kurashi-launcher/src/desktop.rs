//! Desktop Entry parsing (freedesktop Desktop Entry Specification 1.5).
//!
//! Pure: takes text, returns a `DesktopEntry`. Visibility rules (OnlyShowIn, TryExec, ...) are
//! applied by the index, not here, so the parser stays testable without an environment.

use std::collections::HashMap;

#[derive(Debug, Clone, PartialEq)]
pub struct DesktopAction {
    pub id: String,
    pub name: String,
    pub exec: String,
    pub icon: Option<String>,
}

#[derive(Debug, Clone, PartialEq)]
pub struct DesktopEntry {
    pub name: String,
    pub generic_name: Option<String>,
    pub keywords: Vec<String>,
    pub categories: Vec<String>,
    pub exec: Option<String>,
    pub try_exec: Option<String>,
    pub icon: Option<String>,
    pub kind: String,
    pub no_display: bool,
    pub hidden: bool,
    pub terminal: bool,
    pub only_show_in: Vec<String>,
    pub not_show_in: Vec<String>,
    pub actions: Vec<DesktopAction>,
}

type Section = HashMap<String, String>;

/// Parse one `.desktop` file. `locale` is e.g. `ja_JP.UTF-8`; `None` means unlocalised.
/// Returns `None` when there is no `[Desktop Entry]` group or no `Name`.
pub fn parse(text: &str, locale: Option<&str>) -> Option<DesktopEntry> {
    let mut sections: Vec<(String, Section)> = Vec::new();
    for line in text.lines() {
        let line = line.trim();
        if line.is_empty() || line.starts_with('#') {
            continue;
        }
        if let Some(h) = line.strip_prefix('[').and_then(|l| l.strip_suffix(']')) {
            sections.push((h.to_string(), Section::new()));
        } else if let (Some((_, sec)), Some((k, v))) = (sections.last_mut(), line.split_once('=')) {
            // First occurrence wins; duplicates are invalid per spec.
            sec.entry(k.trim().to_string())
                .or_insert_with(|| v.trim_start().to_string());
        }
    }
    let main = &sections.iter().find(|(h, _)| h == "Desktop Entry")?.1;
    let cands = locale_candidates(locale);
    let name = localized(main, "Name", &cands)?;

    let list = |k: &str| main.get(k).map(|v| split_list(v)).unwrap_or_default();
    let flag = |k: &str| main.get(k).is_some_and(|v| v.trim() == "true");

    let keywords = localized_raw(main, "Keywords", &cands)
        .map(|v| split_list(v))
        .unwrap_or_default();

    let actions = list("Actions")
        .into_iter()
        .filter_map(|id| {
            let header = format!("Desktop Action {id}");
            let sec = &sections.iter().find(|(h, _)| *h == header)?.1;
            Some(DesktopAction {
                name: localized(sec, "Name", &cands)?,
                exec: unescape(sec.get("Exec")?),
                icon: sec.get("Icon").map(|s| unescape(s)),
                id,
            })
        })
        .collect();

    Some(DesktopEntry {
        name,
        generic_name: localized(main, "GenericName", &cands),
        keywords,
        categories: list("Categories"),
        exec: main.get("Exec").map(|s| unescape(s)),
        try_exec: main.get("TryExec").map(|s| unescape(s)),
        icon: main.get("Icon").map(|s| unescape(s)),
        kind: main.get("Type").cloned().unwrap_or_default(),
        no_display: flag("NoDisplay"),
        hidden: flag("Hidden"),
        terminal: flag("Terminal"),
        only_show_in: list("OnlyShowIn"),
        not_show_in: list("NotShowIn"),
        actions,
    })
}

/// Lookup order from the spec: `lang_COUNTRY@MOD`, `lang_COUNTRY`, `lang@MOD`, `lang`.
fn locale_candidates(locale: Option<&str>) -> Vec<String> {
    let Some(l) = locale else { return vec![] };
    let l = l.split('.').next().unwrap_or(l); // drop encoding
    let (base, modifier) = match l.split_once('@') {
        Some((b, m)) => (b, Some(m)),
        None => (l, None),
    };
    let (lang, country) = match base.split_once('_') {
        Some((a, c)) => (a, Some(c)),
        None => (base, None),
    };
    if lang.is_empty() || lang == "C" || lang == "POSIX" {
        return vec![];
    }
    let mut out = Vec::new();
    if let (Some(c), Some(m)) = (country, modifier) {
        out.push(format!("{lang}_{c}@{m}"));
    }
    if let Some(c) = country {
        out.push(format!("{lang}_{c}"));
    }
    if let Some(m) = modifier {
        out.push(format!("{lang}@{m}"));
    }
    out.push(lang.to_string());
    out
}

fn localized_raw<'a>(sec: &'a Section, key: &str, cands: &[String]) -> Option<&'a String> {
    cands
        .iter()
        .find_map(|c| sec.get(&format!("{key}[{c}]")))
        .or_else(|| sec.get(key))
}

fn localized(sec: &Section, key: &str, cands: &[String]) -> Option<String> {
    localized_raw(sec, key, cands).map(|s| unescape(s))
}

/// `\s \n \t \r \\ \;` escapes for string values.
pub fn unescape(s: &str) -> String {
    let mut out = String::with_capacity(s.len());
    let mut it = s.chars();
    while let Some(c) = it.next() {
        if c != '\\' {
            out.push(c);
            continue;
        }
        match it.next() {
            Some('s') => out.push(' '),
            Some('n') => out.push('\n'),
            Some('t') => out.push('\t'),
            Some('r') => out.push('\r'),
            Some('\\') => out.push('\\'),
            Some(';') => out.push(';'),
            Some(o) => {
                out.push('\\');
                out.push(o);
            }
            None => out.push('\\'),
        }
    }
    out
}

/// Split a `;`-separated list honouring `\;`.
fn split_list(raw: &str) -> Vec<String> {
    let mut items = Vec::new();
    let mut cur = String::new();
    let mut esc = false;
    for c in raw.chars() {
        if esc {
            cur.push('\\');
            cur.push(c);
            esc = false;
        } else if c == '\\' {
            esc = true;
        } else if c == ';' {
            items.push(std::mem::take(&mut cur));
        } else {
            cur.push(c);
        }
    }
    if esc {
        cur.push('\\');
    }
    if !cur.is_empty() {
        items.push(cur);
    }
    items
        .into_iter()
        .map(|i| unescape(&i))
        .filter(|i| !i.is_empty())
        .collect()
}

#[cfg(test)]
mod tests {
    use super::*;

    const FF: &str = "\
# comment
[Desktop Entry]
Type=Application
Name=Firefox
Name[ja]=ファイアフォックス
Name[de_DE]=Feuerfuchs
Name[de]=Fuchs
GenericName=Web Browser
GenericName[ja]=ウェブブラウザ
Keywords=internet;www;browser;
Keywords[ja]=ネット;ブラウザ;
Categories=Network;WebBrowser;
Exec=firefox %u
Icon=firefox
Terminal=false
Actions=new-window;private-window;

[Desktop Action new-window]
Name=New Window
Name[ja]=新しいウィンドウ
Exec=firefox --new-window %u

[Desktop Action private-window]
Name=New Private Window
Exec=firefox --private-window
Icon=private
";

    #[test]
    fn parses_basic_fields_and_actions() {
        let e = parse(FF, None).unwrap();
        assert_eq!(e.name, "Firefox");
        assert_eq!(e.generic_name.as_deref(), Some("Web Browser"));
        assert_eq!(e.keywords, ["internet", "www", "browser"]);
        assert_eq!(e.categories, ["Network", "WebBrowser"]);
        assert_eq!(e.exec.as_deref(), Some("firefox %u"));
        assert!(!e.terminal && !e.no_display && !e.hidden);
        assert_eq!(e.actions.len(), 2);
        assert_eq!(e.actions[0].id, "new-window");
        assert_eq!(e.actions[1].icon.as_deref(), Some("private"));
    }

    #[test]
    fn localised_keys_with_fallback() {
        let ja = parse(FF, Some("ja_JP.UTF-8")).unwrap();
        assert_eq!(ja.name, "ファイアフォックス");
        assert_eq!(ja.generic_name.as_deref(), Some("ウェブブラウザ"));
        assert_eq!(ja.keywords, ["ネット", "ブラウザ"]);
        assert_eq!(ja.actions[0].name, "新しいウィンドウ");
        assert_eq!(ja.actions[1].name, "New Private Window"); // no ja key: falls back

        assert_eq!(parse(FF, Some("de_DE.UTF-8")).unwrap().name, "Feuerfuchs");
        assert_eq!(parse(FF, Some("de_AT")).unwrap().name, "Fuchs");
        assert_eq!(parse(FF, Some("C")).unwrap().name, "Firefox");
        assert_eq!(parse(FF, Some("fr_FR")).unwrap().name, "Firefox");
    }

    #[test]
    fn visibility_keys() {
        let t = "[Desktop Entry]\nType=Application\nName=X\nExec=x\nNoDisplay=true\nHidden=true\nTerminal=true\nOnlyShowIn=GNOME;KDE;\nNotShowIn=niri;\nTryExec=/bin/x\n";
        let e = parse(t, None).unwrap();
        assert!(e.no_display && e.hidden && e.terminal);
        assert_eq!(e.only_show_in, ["GNOME", "KDE"]);
        assert_eq!(e.not_show_in, ["niri"]);
        assert_eq!(e.try_exec.as_deref(), Some("/bin/x"));
    }

    #[test]
    fn rejects_missing_group_or_name() {
        assert!(parse("[Other]\nName=x\n", None).is_none());
        assert!(parse("[Desktop Entry]\nExec=x\n", None).is_none());
    }

    #[test]
    fn escapes_and_escaped_semicolons() {
        let t = "[Desktop Entry]\nName=A\\sB\nKeywords=a\\;b;c;\n";
        let e = parse(t, None).unwrap();
        assert_eq!(e.name, "A B");
        assert_eq!(e.keywords, ["a;b", "c"]);
    }

    #[test]
    fn first_duplicate_key_wins_and_other_groups_ignored() {
        let t = "[Desktop Entry]\nName=One\nName=Two\n[Desktop Action x]\nName=Z\n";
        assert_eq!(parse(t, None).unwrap().name, "One");
    }
}
