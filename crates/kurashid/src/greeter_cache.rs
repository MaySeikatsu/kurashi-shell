//! The greeter's copy of the user's look (W28, `docs/ux/greeter.md`). The greeter runs before any session, as its own
//! user, with no kurashid to ask; after every change of the theme, the wallpaper or the locale this writes what it needs
//! to draw the last user's look: `{v, user, locale, tokens, wallpaper?, lock_face?}` (`lock_face`: the lock face in
//! effect, `runtime.lock.face`, W53.0b).
//! - Always: `$XDG_STATE_HOME/kurashi/greeter-theme.json` (atomic, only when the content changed).
//! - When the system asks for it: the NixOS module (`services.kurashi.greeter`) makes `/var/lib/kurashi-greeter/
//!   <user>.json` (and `<user>.wallpaper`) owned by the user in a directory only the greeter may write. kurashid never
//!   creates them: an existing, writable file is the request. They are written in place (no rename: the directory is
//!   not the user's), the picture copied into the `.wallpaper` slot, since the greeter cannot read a home directory;
//!   likewise the texture's maps into `.texture`, `.texture-ink` and `.texture-height` (I166). A map without its slot
//!   is left out of the shared copy (no material, no ink, no shadows), never pointed at the user's cache.
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
    let tokens = theme["tokens"].as_object().cloned().unwrap_or_default();
    let mut doc = json!({
        "v": 1,
        "user": user,
        "locale": locale,
        "tokens": tokens,
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
    /// I166: a texture map was copied into its slot.
    pub texture: bool,
}

/// The texture's maps and their slots (I166): the token, the slot's suffix, and the tokens that go when the map cannot.
/// A token, its slot's suffix, and the tokens set when the map has no slot.
type TextureSlot = (&'static str, &'static str, &'static [(&'static str, f64)]);

const TEXTURE_SLOTS: [TextureSlot; 3] = [
    ("texture.map", "texture", &[("texture.amp", 0.0)]),
    (
        "texture.ink_map",
        "texture-ink",
        &[("texture.ink_alpha", 0.0)],
    ),
    (
        "texture.height_map",
        "texture-height",
        &[("texture.shadow", 0.0)],
    ),
];

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
    // I166: the texture's maps live in the user's cache; the greeter reads them from their slots (copied when their
    // bytes changed), or does without them.
    for (token, suffix, without) in TEXTURE_SLOTS {
        let Some(src) = doc["tokens"][token]
            .as_str()
            .filter(|p| !p.is_empty())
            .map(PathBuf::from)
        else {
            continue;
        };
        let slot = shared.join(format!("{user}.{suffix}"));
        let copied_in = slot.is_file()
            && std::fs::read(&src)
                .and_then(|bytes| in_place_if_changed(&slot, &bytes))
                .map(|changed| out.texture |= changed)
                .is_ok();
        doc["tokens"][token] = if copied_in {
            json!(slot.to_string_lossy())
        } else {
            for (k, v) in without {
                doc["tokens"][*k] = json!(v);
            }
            json!("")
        };
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
            let mut doc = cache_doc(&theme, &locale, picture.as_deref(), &user);
            // W53.0b (K80): the lock face in effect (`lock.face` resolved against the style), which the greeter hosts.
            if let Some(face) = hub
                .snapshot(crate::lock::DOC)
                .ok()
                .and_then(|(_, l)| l["face"].as_str().map(String::from))
            {
                doc["lock_face"] = json!(face);
            }
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
                            || doc == crate::lock::DOC
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
                picture: true,
                texture: false,
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

        // I166: the texture's maps go into their slots; a map without one is left out with what it drives.
        let maps = dir.join("maps");
        std::fs::create_dir_all(&maps).unwrap();
        std::fs::write(maps.join("t.png"), b"RELIEF").unwrap();
        std::fs::write(maps.join("t-ink.png"), b"INK").unwrap();
        std::fs::write(maps.join("t-height.png"), b"HEIGHT").unwrap();
        let textured = json!({"tokens": {
            "texture.map": maps.join("t.png"), "texture.amp": 0.09,
            "texture.ink_map": maps.join("t-ink.png"), "texture.ink_alpha": 0.4,
            "texture.height_map": maps.join("t-height.png"), "texture.shadow": 1.0,
        }});
        let tdoc = cache_doc(&textured, "ja", Some(&pic), "tester");
        std::fs::write(shared.join("tester.texture"), "").unwrap();
        std::fs::write(shared.join("tester.texture-ink"), "").unwrap();
        let w = write(&tdoc, &state, &shared, "tester", &mut copied).unwrap();
        assert!(w.texture && w.shared, "{w:?}");
        let copy: Value =
            serde_json::from_str(&std::fs::read_to_string(shared.join("tester.json")).unwrap())
                .unwrap();
        let slot = |s: &str| shared.join(s).to_string_lossy().into_owned();
        assert_eq!(copy["tokens"]["texture.map"], slot("tester.texture"));
        assert_eq!(copy["tokens"]["texture.amp"], 0.09);
        assert_eq!(
            copy["tokens"]["texture.ink_map"],
            slot("tester.texture-ink")
        );
        assert_eq!(copy["tokens"]["texture.height_map"], "", "no height slot");
        assert_eq!(copy["tokens"]["texture.shadow"], 0.0);
        assert_eq!(
            std::fs::read(shared.join("tester.texture")).unwrap(),
            b"RELIEF"
        );
        // The local copy keeps the user's own paths (the user can read them).
        let local: Value = serde_json::from_str(
            &std::fs::read_to_string(state.join("kurashi").join(FILE)).unwrap(),
        )
        .unwrap();
        assert_eq!(
            local["tokens"]["texture.height_map"],
            maps.join("t-height.png").to_string_lossy().as_ref()
        );
        let doc = tdoc;

        // Unchanged: nothing is written again.
        let w = write(&doc, &state, &shared, "tester", &mut copied).unwrap();
        assert_eq!(w, Written::default());
        let _ = std::fs::remove_dir_all(&dir);
    }
}
