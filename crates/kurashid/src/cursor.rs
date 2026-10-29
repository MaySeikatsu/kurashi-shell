//! Cursor personality (W53.0b, K80, I317), both off by default.
//! - **The style's pointer** (`cursor.theme`, `cursor.size`): a stylised Xcursor theme the style brings
//!   (`cursors/<set>/` in the package: an `index.theme` and `cursors/`; the set is the style's `decor.cursor` token, else
//!   one named like the style). It is set as the compositor's cursor theme the way K64's keys are: kurashid writes
//!   `niri/kurashi-cursor.kdl` (`cursor { xcursor-theme …; xcursor-size … }`), included from niri's config, and links the
//!   theme into `$XDG_DATA_HOME/icons/kurashi-<set>` so niri finds it by name. A file we did not write (a Home-Manager
//!   link, the user's own) is never overwritten; with the switch off ours becomes a stub that sets nothing (an include of
//!   it keeps working). niri only for now: on other compositors the state is `unsupported`.
//! - **The pointer decoration** (`cursor.decoration`): which one the frontend's effects sheet draws (`trail`, `sparkles`,
//!   `ring`; `style` = the style's `decor.cursor_decoration` token), fed by `svc.pointer`. Where the compositor cannot
//!   say where the pointer is, `decoration_reason` says so and none is drawn.
//!
//! `svc.cursor` reports both: `{theme, compositor, state, set?, name?, file?, include?, reason?, detail?, decoration,
//! decoration_reason?}`.

use std::path::{Path, PathBuf};
use std::sync::{Arc, Mutex};

use serde_json::{Value, json};

use kurashi_compositor::any::Kind;

use crate::config::ConfigStore;
use crate::hub::Hub;

pub const DOC: &str = "svc.cursor";
pub const NIRI_FILE: &str = "niri/kurashi-cursor.kdl";
pub const NIRI_CONFIG: &str = "niri/config.kdl";
pub const NIRI_INCLUDE: &str = "include \"kurashi-cursor.kdl\"";
const HEADER: &str =
    "// Written by kurashid from the cursor.* settings (Settings → Appearance → Cursor).";
/// The theme tokens of the style (the look's slots, W53.0a); `""` or absent = none.
pub const TOKEN_THEME: &str = "decor.cursor";
pub const TOKEN_DECORATION: &str = "decor.cursor_decoration";
pub const DECORATIONS: [&str; 3] = ["trail", "sparkles", "ring"];
pub const REASON_NO_SET: &str = "cursor.no_set";
pub const REASON_NO_DECORATION: &str = "cursor.no_decoration";
pub const REASON_WRITE_FAILED: &str = "cursor.error.write_failed";
pub const REASON_REFUSED: &str = "cursor.error.refused";

pub fn cursors_dir() -> PathBuf {
    crate::i18n::data_dir().join("cursors")
}

fn slug_ok(s: &str) -> bool {
    !s.is_empty()
        && s.bytes()
            .all(|b| b.is_ascii_lowercase() || b.is_ascii_digit() || b == b'-' || b == b'_')
}

/// The cursor set in effect: the style's token, else the style's name, when `root` ships it as an Xcursor theme.
pub fn set_name(token: &str, style: &str, root: &Path) -> Option<String> {
    [token, style]
        .into_iter()
        .find(|s| {
            slug_ok(s)
                && root.join(s).join("cursors").is_dir()
                && root.join(s).join("index.theme").is_file()
        })
        .map(String::from)
}

/// The theme name a set is installed under.
pub fn theme_name(set: &str) -> String {
    format!("kurashi-{set}")
}

/// The decoration drawn: `(kind, reason)`; kind `""` = none.
pub fn decoration(setting: &str, style_token: &str) -> (String, Option<&'static str>) {
    match setting {
        "trail" | "sparkles" | "ring" => (setting.to_owned(), None),
        "style" if DECORATIONS.contains(&style_token) => (style_token.to_owned(), None),
        "style" => (String::new(), Some(REASON_NO_DECORATION)),
        _ => (String::new(), None),
    }
}

pub fn render(name: &str, size: u32) -> String {
    format!("{HEADER}\ncursor {{\n    xcursor-theme \"{name}\"\n    xcursor-size {size}\n}}\n")
}

fn stub() -> String {
    format!(
        "{HEADER}\n// cursor.theme is off: your own cursor theme stays. Kept so an include of it still works.\n"
    )
}

/// The line of niri's config that includes our file (comments skipped), if any.
fn include_at(cfg: &str) -> Option<usize> {
    cfg.lines().position(|raw| {
        let line = raw.trim();
        !line.starts_with("//")
            && line.starts_with("include")
            && line.contains("kurashi-cursor.kdl\"")
    })
}

fn write_if_changed(path: &Path, text: &str) -> std::io::Result<bool> {
    if std::fs::read_to_string(path).is_ok_and(|old| old == text) {
        return Ok(false);
    }
    if let Some(dir) = path.parent() {
        std::fs::create_dir_all(dir)?;
    }
    let tmp = path.with_extension("kurashi-tmp");
    std::fs::write(&tmp, text)?;
    std::fs::rename(&tmp, path)?;
    Ok(true)
}

/// Links the set into the icon directory under its theme name (replacing a link of ours that points elsewhere).
fn link_theme(icons: &Path, root: &Path, set: &str) -> std::io::Result<()> {
    let link = icons.join(theme_name(set));
    let target = root.join(set);
    match std::fs::symlink_metadata(&link) {
        Ok(m) if m.file_type().is_symlink() => {
            if std::fs::read_link(&link).is_ok_and(|t| t == target) {
                return Ok(());
            }
            std::fs::remove_file(&link)?;
        }
        // A real directory of that name is the user's: left alone (niri finds it by the name anyway).
        Ok(_) => return Ok(()),
        Err(_) => {}
    }
    std::fs::create_dir_all(icons)?;
    std::os::unix::fs::symlink(&target, &link)
}

/// What one run reads.
pub struct Run<'a> {
    /// `$XDG_CONFIG_HOME`.
    pub home: &'a Path,
    /// `$XDG_DATA_HOME/icons`.
    pub icons: &'a Path,
    /// The package's `cursors/`.
    pub root: &'a Path,
    pub on: bool,
    pub size: u32,
    pub set: Option<String>,
    pub compositor: Option<Kind>,
    /// `niri`, when on PATH: checks a changed file first.
    pub checker: Option<&'a Path>,
}

/// Writes the file when it is ours and changed, and returns the theme part of `svc.cursor`.
pub fn apply(run: &Run) -> Value {
    let mut doc = json!({"theme": run.on, "compositor": run.compositor.map(Kind::name)});
    if let Some(s) = &run.set {
        doc["set"] = json!(s);
        doc["name"] = json!(theme_name(s));
    }
    if run.compositor != Some(Kind::Niri) {
        doc["state"] = json!(if run.on { "unsupported" } else { "off" });
        return doc;
    }
    let file = run.home.join(NIRI_FILE);
    let cfg = run.home.join(NIRI_CONFIG);
    doc["file"] = json!(file.to_string_lossy());
    doc["include"] = json!({
        "file": cfg.to_string_lossy(),
        "line": NIRI_INCLUDE,
        "present": include_at(&std::fs::read_to_string(&cfg).unwrap_or_default()).is_some(),
    });
    let meta = std::fs::symlink_metadata(&file).ok();
    if meta.as_ref().is_some_and(|m| m.file_type().is_symlink()) {
        doc["state"] = json!("managed");
        return doc;
    }
    let existing = std::fs::read_to_string(&file).ok();
    if existing
        .as_deref()
        .is_some_and(|t| !t.starts_with(HEADER) && !t.trim().is_empty())
    {
        doc["state"] = json!("foreign");
        return doc;
    }
    let text = match (&run.set, run.on) {
        (Some(set), true) => {
            if let Err(e) = link_theme(run.icons, run.root, set) {
                tracing::warn!(error = %e, "cursor: could not link the theme");
                doc["state"] = json!("error");
                doc["reason"] = json!(REASON_WRITE_FAILED);
                return doc;
            }
            render(&theme_name(set), run.size)
        }
        (None, true) => {
            doc["reason"] = json!(REASON_NO_SET);
            stub()
        }
        _ => stub(),
    };
    if !run.on && existing.is_none() {
        // Nothing to undo and no include to keep working: no file.
        doc["state"] = json!("off");
        return doc;
    }
    let unchanged = existing.as_deref() == Some(text.as_str());
    if !unchanged
        && let Some(program) = run.checker
        && let Some(Err(msg)) = crate::keys::check(Kind::Niri, program, &text)
    {
        doc["state"] = json!("error");
        doc["reason"] = json!(REASON_REFUSED);
        doc["detail"] = json!(
            msg.lines()
                .map(str::trim)
                .filter(|l| !l.is_empty())
                .collect::<Vec<_>>()
                .join(" ")
        );
        return doc;
    }
    match write_if_changed(&file, &text) {
        Ok(changed) => {
            let written = run.on && run.set.is_some();
            doc["state"] = json!(if written { "written" } else { "off" });
            doc["changed"] = json!(changed);
        }
        Err(e) => {
            tracing::warn!(error = %e, "cursor: could not write the file");
            doc["state"] = json!("error");
            doc["reason"] = json!(REASON_WRITE_FAILED);
        }
    }
    doc
}

fn xdg(var: &str, fallback: &str) -> PathBuf {
    std::env::var_os(var)
        .map(PathBuf::from)
        .filter(|p| p.is_absolute())
        .or_else(|| std::env::var_os("HOME").map(|h| PathBuf::from(h).join(fallback)))
        .unwrap_or_else(|| PathBuf::from("/tmp"))
}

struct Cursor {
    hub: Arc<Hub>,
    store: Arc<ConfigStore>,
    compositor: Option<Kind>,
    turn: Mutex<()>,
}

impl Cursor {
    fn run(&self) {
        let _turn = self.turn.lock().unwrap_or_else(|e| e.into_inner());
        let theme = self
            .hub
            .snapshot(crate::theme::DOC)
            .map(|(_, d)| d)
            .unwrap_or_default();
        let token = |k: &str| theme["tokens"][k].as_str().unwrap_or("").to_owned();
        let style = theme["appearance"]["style"]
            .as_str()
            .unwrap_or("")
            .to_owned();
        let on = self
            .store
            .get("cursor.theme", None)
            .is_some_and(|p| p.value == Value::Bool(true));
        let size = self
            .store
            .get("cursor.size", None)
            .and_then(|p| p.value.as_u64())
            .unwrap_or(24) as u32;
        let root = cursors_dir();
        let home = xdg("XDG_CONFIG_HOME", ".config");
        let icons = xdg("XDG_DATA_HOME", ".local/share").join("icons");
        let checker = crate::keys::on_path("niri");
        let mut doc = apply(&Run {
            home: &home,
            icons: &icons,
            root: &root,
            on,
            size,
            set: set_name(&token(TOKEN_THEME), &style, &root),
            compositor: self.compositor,
            checker: checker.as_deref(),
        });
        let (kind, why) = decoration(
            &crate::theme::s(&self.store, "cursor.decoration"),
            &token(TOKEN_DECORATION),
        );
        doc["decoration"] = json!(kind);
        if let Some(w) = why {
            doc["decoration_reason"] = json!(w);
        }
        let _ = self.hub.set(DOC, doc, None);
    }
}

/// `svc.cursor`, kept current after each config and theme change (a run writes only when the file's text changes).
pub fn register(hub: &Arc<Hub>, store: &Arc<ConfigStore>, compositor: Option<Kind>) {
    let c = Arc::new(Cursor {
        hub: hub.clone(),
        store: store.clone(),
        compositor,
        turn: Mutex::new(()),
    });
    hub.register(
        DOC,
        json!({"theme": false, "state": "off", "decoration": ""}),
        None,
    );
    let spawn = |c: Arc<Cursor>| match tokio::runtime::Handle::try_current() {
        // `niri validate` is a subprocess: off the caller's thread.
        Ok(rt) => {
            rt.spawn_blocking(move || c.run());
        }
        Err(_) => c.run(),
    };
    spawn(c.clone());
    {
        let c = c.clone();
        store.on_change(move |_| spawn(c.clone()));
    }
    let Ok(rt) = tokio::runtime::Handle::try_current() else {
        return;
    };
    let mut events = hub.events();
    rt.spawn(async move {
        loop {
            match events.recv().await {
                Ok(msg) => match msg.as_ref() {
                    kurashi_ipc::ServerMsg::Snap { doc, .. }
                    | kurashi_ipc::ServerMsg::Patch { doc, .. }
                        if doc == crate::theme::DOC => {}
                    _ => continue,
                },
                Err(tokio::sync::broadcast::error::RecvError::Lagged(_)) => {}
                Err(tokio::sync::broadcast::error::RecvError::Closed) => break,
            }
            let c = c.clone();
            let _ = tokio::task::spawn_blocking(move || c.run()).await;
        }
    });
}

#[cfg(test)]
mod tests {
    use super::*;

    fn tmp(name: &str) -> PathBuf {
        let d = std::env::temp_dir().join(format!("kurashid-cursor-{name}-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&d);
        std::fs::create_dir_all(&d).unwrap();
        d
    }

    fn set_dir(root: &Path, set: &str) {
        std::fs::create_dir_all(root.join(set).join("cursors")).unwrap();
        std::fs::write(root.join(set).join("index.theme"), "[Icon Theme]\nName=x\n").unwrap();
    }

    #[test]
    fn the_set_must_be_a_shipped_xcursor_theme() {
        let root = tmp("root");
        set_dir(&root, "win95");
        std::fs::create_dir_all(root.join("half")).unwrap();
        assert_eq!(set_name("", "win95", &root).as_deref(), Some("win95"));
        assert_eq!(set_name("half", "win95", &root).as_deref(), Some("win95"));
        assert_eq!(set_name("", "kanso", &root), None);
        assert_eq!(set_name("../win95", "", &root), None);
    }

    #[test]
    fn the_shipped_sets_are_themes() {
        for e in std::fs::read_dir(cursors_dir())
            .into_iter()
            .flatten()
            .flatten()
        {
            let name = e.file_name().to_string_lossy().into_owned();
            assert_eq!(
                set_name(&name, "", &cursors_dir()).as_deref(),
                Some(name.as_str())
            );
            assert!(
                e.path().join("cursors/default").exists(),
                "{name}: no default cursor"
            );
            assert!(
                e.path().join("cursors/left_ptr").exists(),
                "{name}: no left_ptr"
            );
        }
    }

    #[test]
    fn the_decoration_is_the_users_or_the_styles() {
        assert_eq!(decoration("off", "ring"), (String::new(), None));
        assert_eq!(decoration("trail", ""), ("trail".into(), None));
        assert_eq!(decoration("style", "sparkles"), ("sparkles".into(), None));
        assert_eq!(
            decoration("style", ""),
            (String::new(), Some(REASON_NO_DECORATION))
        );
        assert_eq!(
            decoration("style", "boom"),
            (String::new(), Some(REASON_NO_DECORATION))
        );
    }

    #[test]
    fn writes_the_include_only_while_on_and_never_over_a_file_it_did_not_write() {
        let (home, icons, root) = (tmp("home"), tmp("icons"), tmp("sets"));
        set_dir(&root, "win95");
        let run = |on: bool, set: Option<&str>, compositor: Option<Kind>| {
            apply(&Run {
                home: &home,
                icons: &icons,
                root: &root,
                on,
                size: 32,
                set: set.map(String::from),
                compositor,
                checker: None,
            })
        };
        // Off by default: no file at all.
        let d = run(false, Some("win95"), Some(Kind::Niri));
        assert_eq!(d["state"], "off");
        assert!(!home.join(NIRI_FILE).exists());
        assert_eq!(d["include"]["present"], false);
        // On: the file names the linked theme, and the link is there.
        std::fs::create_dir_all(home.join("niri")).unwrap();
        std::fs::write(
            home.join(NIRI_CONFIG),
            "input {}\ninclude \"kurashi-cursor.kdl\"\n",
        )
        .unwrap();
        let d = run(true, Some("win95"), Some(Kind::Niri));
        assert_eq!(d["state"], "written", "{d}");
        assert_eq!(d["include"]["present"], true);
        let text = std::fs::read_to_string(home.join(NIRI_FILE)).unwrap();
        assert!(
            text.contains("xcursor-theme \"kurashi-win95\"") && text.contains("xcursor-size 32"),
            "{text}"
        );
        assert_eq!(
            std::fs::read_link(icons.join("kurashi-win95")).unwrap(),
            root.join("win95")
        );
        // On, but the style brings none: a stub, and why.
        let d = run(true, None, Some(Kind::Niri));
        assert_eq!(d["reason"], REASON_NO_SET);
        assert!(
            !std::fs::read_to_string(home.join(NIRI_FILE))
                .unwrap()
                .contains("cursor {")
        );
        // Off again: the stub, the include still works.
        let d = run(false, Some("win95"), Some(Kind::Niri));
        assert_eq!(d["state"], "off");
        assert!(
            std::fs::read_to_string(home.join(NIRI_FILE))
                .unwrap()
                .starts_with(HEADER)
        );
        // The user's own file is never written.
        std::fs::write(home.join(NIRI_FILE), "cursor { xcursor-theme \"mine\"; }\n").unwrap();
        assert_eq!(
            run(true, Some("win95"), Some(Kind::Niri))["state"],
            "foreign"
        );
        assert!(
            std::fs::read_to_string(home.join(NIRI_FILE))
                .unwrap()
                .contains("mine")
        );
        // Elsewhere: not yet.
        assert_eq!(
            run(true, Some("win95"), Some(Kind::Sway))["state"],
            "unsupported"
        );
        assert_eq!(run(false, Some("win95"), None)["state"], "off");
    }
}
