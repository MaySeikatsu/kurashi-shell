//! Sound cues (W53.0b, K80, `docs/ux/styles.md` "Sounds"): every style may bring an original cue set, off by default
//! (`theme.sounds`). The daemon plays them (rule 1: no process in the frontend), one short `pw-play` (else `paplay`) per
//! cue; nothing is loaded, watched or running while the switch is off (Ma): the watcher that turns state changes into
//! cues exists only while it is on.
//! - Set: the style's `decor.sounds` token (the look's `[slots] sounds`, W53.0a), else a set named like the style, from
//!   `sounds/<set>/` in the package; no set = no sounds, and `svc.sound` says why.
//! - Cues: `unlock` (the session unlocks), `error` (a rejected attempt), `notify` (a new notification, not under
//!   do-not-disturb and not while locked), `open` / `close` (the launcher). Action `sound.cue {name}` plays one (a mod,
//!   a frontend); refused while sounds are off or the set lacks it.
//! - Files: `<cue>.{oga,ogg,wav,flac}`, original and synthesised (CC0), ≤ 50 KiB each.

use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicUsize, Ordering};
use std::sync::{Arc, Mutex};

use serde_json::{Value, json};

use crate::actions::{ActionError, ActionRegistry};
use crate::config::ConfigStore;
use crate::hub::Hub;

pub const DOC: &str = "svc.sound";
pub const KEY: &str = "theme.sounds";
pub const TOKEN: &str = "decor.sounds";
pub const CUES: [&str; 5] = ["unlock", "error", "notify", "open", "close"];
const EXTENSIONS: [&str; 4] = ["oga", "ogg", "wav", "flac"];
/// The players tried, in order.
const PLAYERS: [&str; 2] = ["pw-play", "paplay"];
/// Cues at once at most: a burst (ten notifications) plays a few, never a pile of processes.
const MAX_PLAYING: usize = 2;
pub const REASON_NO_SET: &str = "sound.no_set";
pub const REASON_NO_PLAYER: &str = "sound.no_player";
pub const REASON_OFF: &str = "sound.off";
pub const REASON_NO_CUE: &str = "sound.no_cue";

pub fn sounds_dir() -> PathBuf {
    crate::i18n::data_dir().join("sounds")
}

fn slug_ok(s: &str) -> bool {
    !s.is_empty()
        && s.bytes()
            .all(|b| b.is_ascii_lowercase() || b.is_ascii_digit() || b == b'-' || b == b'_')
}

/// The set in effect: the style's token, else the style's name, when `root` has it.
pub fn set_name(token: &str, style: &str, root: &Path) -> Option<String> {
    [token, style]
        .into_iter()
        .find(|s| slug_ok(s) && root.join(s).is_dir())
        .map(String::from)
}

pub fn cue_file(root: &Path, set: &str, cue: &str) -> Option<PathBuf> {
    if !CUES.contains(&cue) {
        return None;
    }
    EXTENSIONS
        .iter()
        .map(|e| root.join(set).join(format!("{cue}.{e}")))
        .find(|p| p.is_file())
}

/// The cues a state change asks for, from the documents before and after.
pub fn cues_for(doc: &str, before: &Value, after: &Value, locked: bool) -> Vec<&'static str> {
    let mut out = Vec::new();
    match doc {
        "runtime.lock" => {
            if before["locked"] == true && after["locked"] == false {
                out.push("unlock");
            }
            let failures = |d: &Value| d["failures"].as_u64().unwrap_or(0);
            if after["locked"] == true && failures(after) > failures(before) {
                out.push("error");
            }
        }
        "runtime.ui" => match (before["launcher"] == true, after["launcher"] == true) {
            (false, true) => out.push("open"),
            (true, false) => out.push("close"),
            _ => {}
        },
        "svc.notifications" => {
            let newest = |d: &Value| {
                d["items"]
                    .as_array()
                    .into_iter()
                    .flatten()
                    .filter_map(|i| i["id"].as_u64())
                    .max()
                    .unwrap_or(0)
            };
            let arrived = after["items"]
                .as_array()
                .into_iter()
                .flatten()
                .any(|i| i["id"].as_u64().unwrap_or(0) > newest(before) && i["read"] != true);
            if arrived && !before.is_null() && after["dnd"] != true && !locked {
                out.push("notify");
            }
        }
        _ => {}
    }
    out
}

fn player() -> Option<PathBuf> {
    PLAYERS.iter().find_map(|p| crate::keys::on_path(p))
}

struct Sound {
    hub: Arc<Hub>,
    store: Option<Arc<ConfigStore>>,
    root: PathBuf,
    playing: Arc<AtomicUsize>,
    /// The watcher, while the switch is on.
    watcher: Mutex<Option<tokio::task::JoinHandle<()>>>,
}

impl Sound {
    fn enabled(&self) -> bool {
        self.store.as_deref().is_some_and(|s| {
            s.get(KEY, None)
                .and_then(|p| p.value.as_bool())
                .unwrap_or(false)
        })
    }

    fn set(&self) -> Option<String> {
        let theme = self
            .hub
            .snapshot(crate::theme::DOC)
            .map(|(_, d)| d)
            .unwrap_or_default();
        set_name(
            theme["tokens"][TOKEN].as_str().unwrap_or(""),
            theme["appearance"]["style"].as_str().unwrap_or(""),
            &self.root,
        )
    }

    fn doc(&self) -> Value {
        let enabled = self.enabled();
        let set = self.set();
        let cues: Vec<&str> = set
            .as_deref()
            .map(|s| {
                CUES.iter()
                    .copied()
                    .filter(|c| cue_file(&self.root, s, c).is_some())
                    .collect()
            })
            .unwrap_or_default();
        let mut d = json!({"enabled": enabled, "set": set, "cues": cues});
        if enabled {
            match player() {
                Some(p) => {
                    d["player"] = json!(p.file_name().map(|n| n.to_string_lossy().into_owned()))
                }
                None => d["reason"] = json!(REASON_NO_PLAYER),
            }
            if set.is_none() {
                d["reason"] = json!(REASON_NO_SET);
            }
        }
        if d["set"].is_null()
            && let Some(o) = d.as_object_mut()
        {
            o.remove("set");
        }
        d
    }

    /// Plays `cue` from the set in effect: `Err(reason)` when it cannot.
    fn play(&self, cue: &str) -> Result<(), &'static str> {
        if !self.enabled() {
            return Err(REASON_OFF);
        }
        let set = self.set().ok_or(REASON_NO_SET)?;
        let file = cue_file(&self.root, &set, cue).ok_or(REASON_NO_CUE)?;
        let player = player().ok_or(REASON_NO_PLAYER)?;
        if self.playing.load(Ordering::SeqCst) >= MAX_PLAYING {
            return Ok(());
        }
        let child = tokio::process::Command::new(player)
            .arg(&file)
            .stdin(std::process::Stdio::null())
            .stdout(std::process::Stdio::null())
            .stderr(std::process::Stdio::null())
            .kill_on_drop(true)
            .spawn();
        let Ok(mut child) = child else {
            return Err(REASON_NO_PLAYER);
        };
        self.playing.fetch_add(1, Ordering::SeqCst);
        let playing = self.playing.clone();
        tokio::spawn(async move {
            // A cue is short; a player that hangs is stopped.
            let _ = tokio::time::timeout(std::time::Duration::from_secs(5), child.wait()).await;
            let _ = child.kill().await;
            playing.fetch_sub(1, Ordering::SeqCst);
        });
        Ok(())
    }

    fn publish(&self) {
        let _ = self.hub.set(DOC, self.doc(), None);
    }

    /// Starts the watcher while the switch is on and stops it when it goes off.
    fn follow(self: &Arc<Self>) {
        let on = self.enabled();
        let mut w = self.watcher.lock().unwrap_or_else(|e| e.into_inner());
        match (on, w.is_some()) {
            (true, false) => {
                let Ok(rt) = tokio::runtime::Handle::try_current() else {
                    return;
                };
                let me = self.clone();
                *w = Some(rt.spawn(async move { me.watch().await }));
            }
            (false, true) => {
                if let Some(t) = w.take() {
                    t.abort();
                }
            }
            _ => {}
        }
    }

    async fn watch(self: Arc<Self>) {
        let mut events = self.hub.events();
        let snap = |d: &str| self.hub.snapshot(d).map(|(_, v)| v).unwrap_or(Value::Null);
        let watched = ["runtime.lock", "runtime.ui", "svc.notifications"];
        let mut last: Vec<Value> = watched.iter().map(|d| snap(d)).collect();
        loop {
            match events.recv().await {
                Ok(msg) => {
                    let doc = match msg.as_ref() {
                        kurashi_ipc::ServerMsg::Snap { doc, .. }
                        | kurashi_ipc::ServerMsg::Patch { doc, .. } => doc.as_str(),
                        _ => continue,
                    };
                    if doc == crate::theme::DOC {
                        self.publish();
                        continue;
                    }
                    let Some(i) = watched.iter().position(|w| *w == doc) else {
                        continue;
                    };
                    let now = snap(doc);
                    let locked = last[0]["locked"] == true;
                    for cue in cues_for(doc, &last[i], &now, locked) {
                        let _ = self.play(cue);
                    }
                    last[i] = now;
                }
                Err(tokio::sync::broadcast::error::RecvError::Lagged(_)) => {
                    last = watched.iter().map(|d| snap(d)).collect();
                }
                Err(tokio::sync::broadcast::error::RecvError::Closed) => break,
            }
        }
    }
}

/// `svc.sound` and action `sound.cue {name}`; the watcher follows `theme.sounds`.
pub fn register(hub: &Arc<Hub>, store: Option<Arc<ConfigStore>>, actions: &mut ActionRegistry) {
    let s = Arc::new(Sound {
        hub: hub.clone(),
        store: store.clone(),
        root: sounds_dir(),
        playing: Arc::new(AtomicUsize::new(0)),
        watcher: Mutex::new(None),
    });
    hub.register(DOC, s.doc(), None);
    s.follow();
    if let Some(store) = &store {
        let s = s.clone();
        store.on_change(move |_| {
            s.publish();
            s.follow();
        });
    }
    let ss = s.clone();
    actions.register("sound.cue", "action.sound.cue", move |a| {
        let s = ss.clone();
        async move {
            let name = a["name"]
                .as_str()
                .filter(|n| CUES.contains(n))
                .ok_or_else(|| ActionError::Invalid(crate::wiring::ARGS_INVALID.into()))?
                .to_owned();
            s.play(&name)
                .map(|()| None)
                .map_err(|why| ActionError::Unavailable(why.into()))
        }
    });
    actions.describe("sound.cue", "{name}");
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn the_set_is_the_tokens_else_the_styles_when_it_ships() {
        let root = std::env::temp_dir().join(format!("kurashid-sounds-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&root);
        std::fs::create_dir_all(root.join("snes")).unwrap();
        std::fs::create_dir_all(root.join("chime")).unwrap();
        assert_eq!(set_name("chime", "snes", &root).as_deref(), Some("chime"));
        assert_eq!(set_name("", "snes", &root).as_deref(), Some("snes"));
        assert_eq!(set_name("missing", "snes", &root).as_deref(), Some("snes"));
        assert_eq!(set_name("", "kanso", &root), None);
        assert_eq!(set_name("../snes", "", &root), None);
        std::fs::write(root.join("snes/unlock.wav"), b"RIFF").unwrap();
        assert!(cue_file(&root, "snes", "unlock").is_some());
        assert!(cue_file(&root, "snes", "error").is_none());
        assert!(cue_file(&root, "snes", "../x").is_none());
    }

    #[test]
    fn the_shipped_sets_have_every_cue_and_stay_small() {
        for set in std::fs::read_dir(sounds_dir()).unwrap().flatten() {
            let name = set.file_name().to_string_lossy().into_owned();
            if !set.path().is_dir() {
                continue;
            }
            for cue in CUES {
                let f =
                    cue_file(&sounds_dir(), &name, cue).unwrap_or_else(|| panic!("{name}: {cue}"));
                let len = std::fs::metadata(&f).unwrap().len();
                assert!(len <= 50 * 1024, "{}: {len} bytes", f.display());
            }
        }
    }

    #[test]
    fn state_changes_become_cues() {
        let lock = |l: bool, f: u64| json!({"locked": l, "failures": f});
        assert_eq!(
            cues_for("runtime.lock", &lock(true, 0), &lock(false, 0), true),
            ["unlock"]
        );
        assert_eq!(
            cues_for("runtime.lock", &lock(true, 0), &lock(true, 1), true),
            ["error"]
        );
        assert!(cues_for("runtime.lock", &lock(false, 0), &lock(true, 0), false).is_empty());
        let ui = |l: bool| json!({"launcher": l});
        assert_eq!(
            cues_for("runtime.ui", &ui(false), &ui(true), false),
            ["open"]
        );
        assert_eq!(
            cues_for("runtime.ui", &ui(true), &ui(false), false),
            ["close"]
        );
        let n = |ids: &[u64], dnd: bool| json!({"dnd": dnd, "items": ids.iter().map(|i| json!({"id": i, "read": false})).collect::<Vec<_>>()});
        assert_eq!(
            cues_for(
                "svc.notifications",
                &n(&[1], false),
                &n(&[1, 2], false),
                false
            ),
            ["notify"]
        );
        // Dismissing one, do-not-disturb and a locked screen stay silent; so does the first document.
        assert!(
            cues_for(
                "svc.notifications",
                &n(&[1, 2], false),
                &n(&[1], false),
                false
            )
            .is_empty()
        );
        assert!(
            cues_for(
                "svc.notifications",
                &n(&[1], true),
                &n(&[1, 2], true),
                false
            )
            .is_empty()
        );
        assert!(
            cues_for(
                "svc.notifications",
                &n(&[1], false),
                &n(&[1, 2], false),
                true
            )
            .is_empty()
        );
        assert!(cues_for("svc.notifications", &Value::Null, &n(&[1, 2], false), false).is_empty());
    }

    #[tokio::test]
    async fn off_by_default_nothing_watches_and_a_cue_is_refused() {
        let hub = Hub::new();
        hub.register(crate::theme::DOC, json!({"tokens": {}}), None);
        let mut actions = ActionRegistry::default();
        register(&hub, None, &mut actions);
        let d = hub.snapshot(DOC).unwrap().1;
        assert_eq!(d["enabled"], false);
        assert!(d.get("reason").is_none());
        let err = actions
            .invoke("sound.cue", json!({"name": "unlock"}))
            .await
            .unwrap_err();
        assert_eq!(err, ActionError::Unavailable(REASON_OFF.into()));
        let err = actions
            .invoke("sound.cue", json!({"name": "boom"}))
            .await
            .unwrap_err();
        assert_eq!(
            err,
            ActionError::Invalid(crate::wiring::ARGS_INVALID.into())
        );
    }
}
