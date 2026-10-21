//! The greeter's copy of the user's look (W28, `docs/ux/greeter.md`). The greeter runs before any session, as its own
//! user, with no kurashid to ask; after every change of the theme, the wallpaper or the locale this writes what it needs
//! to draw the last user's look: `{v, user, locale, tokens, wallpaper?}`.
//! - Always: `$XDG_STATE_HOME/kurashi/greeter-theme.json` (atomic, only when the content changed).
//! - When the system asks for it: the NixOS module (`services.kurashi.greeter`) makes `/var/lib/kurashi-greeter/
//!   <user>.json` (and `<user>.wallpaper`) owned by the user in a directory only the greeter may write. kurashid never
//!   creates them: an existing, writable file is the request. They are written in place (no rename: the directory is
//!   not the user's), the picture copied into the `.wallpaper` slot, since the greeter cannot read a home directory.
//!   `KURASHI_GREETER_DIR` names another directory (tests).

use std::path::{Path, PathBuf};
use std::sync::{Arc, Mutex};

use serde_json::{Value, json};

use crate::hub::Hub;

pub const FILE: &str = "greeter-theme.json";
pub const SHARED_DIR: &str = "/var/lib/kurashi-greeter";

fn state_home() -> PathBuf {
    std::env::var_os("XDG_STATE_HOME")
        .map(PathBuf::from)
        .filter(|p| p.is_absolute())
        .or_else(|| std::env::var_os("HOME").map(|h| PathBuf::from(h).join(".local/state")))
        .unwrap_or_else(|| PathBuf::from("/tmp"))
}

fn shared_dir() -> PathBuf {
    std::env::var_os("KURASHI_GREETER_DIR")
        .map(PathBuf::from)
        .unwrap_or_else(|| PathBuf::from(SHARED_DIR))
}

fn user() -> Option<String> {
    ["USER", "LOGNAME"]
        .iter()
        .filter_map(|k| std::env::var(k).ok())
        .find(|u| !u.is_empty() && !u.contains('/'))
}

/// The picture on screen: the one last applied with its theme, else the first output's.
pub fn wallpaper_of(doc: &Value) -> Option<PathBuf> {
    if let Some(p) = doc["theme"]["image"].as_str().filter(|s| !s.is_empty()) {
        return Some(p.into());
    }
    doc["outputs"]
        .as_object()?
        .values()
        .find_map(|o| o["path"].as_str().filter(|s| !s.is_empty()))
        .map(Into::into)
}

/// The cache's content (absent fields are left out, as in documents: B25).
pub fn cache_doc(theme: &Value, locale: &str, wallpaper: Option<&Path>, user: &str) -> Value {
    let mut doc = json!({
        "v": 1,
        "user": user,
        "locale": locale,
        "tokens": theme["tokens"].as_object().cloned().unwrap_or_default(),
    });
    if let Some(w) = wallpaper {
        doc["wallpaper"] = json!(w.to_string_lossy());
    }
    doc
}

fn atomic_if_changed(path: &Path, text: &str) -> std::io::Result<bool> {
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

/// Truncate-and-write into a file that exists (keeps its owner and mode).
fn in_place_if_changed(path: &Path, bytes: &[u8]) -> std::io::Result<bool> {
    if std::fs::read(path).is_ok_and(|old| old == bytes) {
        return Ok(false);
    }
    use std::io::Write;
    let mut f = std::fs::OpenOptions::new()
        .write(true)
        .truncate(true)
        .open(path)?;
    f.write_all(bytes)?;
    Ok(true)
}

/// What one write did, for tests and the log.
#[derive(Debug, Default, PartialEq, Eq)]
pub struct Written {
    pub local: bool,
    pub shared: bool,
    pub picture: bool,
}

/// Writes the local cache under `state` and, when its files exist, the shared copy under `shared`. `copied` remembers
/// the picture last copied into the slot (path, length, mtime), so an unchanged picture is not read again.
pub fn write(
    doc: &Value,
    state: &Path,
    shared: &Path,
    user: &str,
    copied: &mut Option<(PathBuf, u64, Option<std::time::SystemTime>)>,
) -> std::io::Result<Written> {
    let mut out = Written {
        local: atomic_if_changed(&state.join("kurashi").join(FILE), &format!("{doc:#}\n"))?,
        ..Written::default()
    };
    let slot_json = shared.join(format!("{user}.json"));
    if !slot_json.is_file() {
        return Ok(out);
    }
    let mut doc = doc.clone();
    let slot_pic = shared.join(format!("{user}.wallpaper"));
    if let Some(src) = doc["wallpaper"].as_str().map(PathBuf::from)
        && slot_pic.is_file()
        && let Ok(meta) = std::fs::metadata(&src)
    {
        let key = (src.clone(), meta.len(), meta.modified().ok());
        if copied.as_ref() != Some(&key) {
            out.picture = in_place_if_changed(&slot_pic, &std::fs::read(&src)?)?;
            *copied = Some(key);
        }
        doc["wallpaper"] = json!(slot_pic.to_string_lossy());
    }
    out.shared = in_place_if_changed(&slot_json, format!("{doc:#}\n").as_bytes())?;
    Ok(out)
}

/// Keeps the cache current after each change of `theme`, `mod.wallpaper` or `i18n`. Event-driven: nothing runs while
/// none of them changes (Ma).
pub fn register(hub: &Arc<Hub>) {
    let Some(user) = user() else {
        return;
    };
    let copied = Arc::new(Mutex::new(None));
    let run = {
        let hub = hub.clone();
        move || {
            let Ok((_, theme)) = hub.snapshot(crate::theme::DOC) else {
                return;
            };
            if theme["tokens"].as_object().is_none_or(|t| t.is_empty()) {
                return;
            }
            let locale = hub
                .snapshot("i18n")
                .ok()
                .and_then(|(_, d)| d["locale"].as_str().map(String::from))
                .unwrap_or_else(crate::i18n::locale_from_env);
            let picture = hub
                .snapshot(crate::theme::WALLPAPER_DOC)
                .ok()
                .and_then(|(_, d)| wallpaper_of(&d));
            let doc = cache_doc(&theme, &locale, picture.as_deref(), &user);
            let mut copied = copied.lock().unwrap_or_else(|e| e.into_inner());
            match write(&doc, &state_home(), &shared_dir(), &user, &mut copied) {
                Ok(w) if w != Written::default() => tracing::debug!(?w, "greeter cache written"),
                Ok(_) => {}
                Err(e) => tracing::warn!(error = %e, "greeter cache not written"),
            }
        }
    };
    let Ok(rt) = tokio::runtime::Handle::try_current() else {
        return;
    };
    let mut events = hub.events();
    rt.spawn(async move {
        let _ = tokio::task::spawn_blocking(run.clone()).await;
        loop {
            match events.recv().await {
                Ok(msg) => match msg.as_ref() {
                    kurashi_ipc::ServerMsg::Snap { doc, .. }
                    | kurashi_ipc::ServerMsg::Patch { doc, .. }
                        if doc == crate::theme::DOC
                            || doc == crate::theme::WALLPAPER_DOC
                            || doc == "i18n" => {}
                    _ => continue,
                },
                Err(tokio::sync::broadcast::error::RecvError::Lagged(_)) => {}
                Err(tokio::sync::broadcast::error::RecvError::Closed) => break,
            }
            let _ = tokio::task::spawn_blocking(run.clone()).await;
        }
    });
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn wallpaper_prefers_the_themed_picture_then_an_output() {
        let both = json!({"theme": {"image": "/w/t.png"}, "outputs": {"A": {"path": "/w/a.png"}}});
        assert_eq!(wallpaper_of(&both), Some("/w/t.png".into()));
        let out = json!({"theme": {}, "outputs": {"A": {"path": "/w/a.png", "fit": "crop"}}});
        assert_eq!(wallpaper_of(&out), Some("/w/a.png".into()));
        assert_eq!(wallpaper_of(&json!({"theme": {}, "outputs": {}})), None);
    }

    #[test]
    fn writes_locally_and_into_the_shared_slots_only_when_they_exist() {
        let dir = std::env::temp_dir().join(format!("kurashi-greeter-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&dir);
        let (state, shared) = (dir.join("state"), dir.join("shared"));
        std::fs::create_dir_all(&shared).unwrap();
        let pic = dir.join("pic.png");
        std::fs::write(&pic, b"PNG-1").unwrap();
        let theme = json!({"tokens": {"color.accent": "#c9404b", "chrome.ring": 2}});
        let doc = cache_doc(&theme, "ja", Some(&pic), "tester");
        assert_eq!(doc["tokens"]["chrome.ring"], 2);
        let mut copied = None;

        // No slot: the local file only; nothing is created in the shared directory.
        let w = write(&doc, &state, &shared, "tester", &mut copied).unwrap();
        assert_eq!(
            w,
            Written {
                local: true,
                ..Written::default()
            }
        );
        let local: Value = serde_json::from_str(
            &std::fs::read_to_string(state.join("kurashi").join(FILE)).unwrap(),
        )
        .unwrap();
        assert_eq!(local["locale"], "ja");
        assert_eq!(local["wallpaper"], pic.to_string_lossy().as_ref());
        assert!(std::fs::read_dir(&shared).unwrap().next().is_none());

        // The module made the slots: both are filled in place, the copy points at the picture slot.
        std::fs::write(shared.join("tester.json"), "").unwrap();
        std::fs::write(shared.join("tester.wallpaper"), "").unwrap();
        let w = write(&doc, &state, &shared, "tester", &mut copied).unwrap();
        assert_eq!(
            w,
            Written {
                local: false,
                shared: true,
                picture: true
            }
        );
        assert_eq!(
            std::fs::read(shared.join("tester.wallpaper")).unwrap(),
            b"PNG-1"
        );
        let copy: Value =
            serde_json::from_str(&std::fs::read_to_string(shared.join("tester.json")).unwrap())
                .unwrap();
        assert_eq!(
            copy["wallpaper"],
            shared.join("tester.wallpaper").to_string_lossy().as_ref()
        );
        assert_eq!(copy["tokens"]["color.accent"], "#c9404b");

        // Unchanged: nothing is written again.
        let w = write(&doc, &state, &shared, "tester", &mut copied).unwrap();
        assert_eq!(w, Written::default());
        let _ = std::fs::remove_dir_all(&dir);
    }
}
