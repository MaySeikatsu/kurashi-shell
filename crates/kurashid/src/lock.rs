//! The lock screen's personality (W53.0b, K80, `docs/ux/styles.md` "Lock faces"): what `runtime.lock` says besides
//! the authentication state `kurashi-auth` writes. Laid over that document as overlays (K66's `set_overlay`), so the
//! state machine knows nothing of faces or keyboards:
//! - `face`: the lock face in effect, resolved here (rule 1) from `lock.face` (`follow` | `plain` | a face's name) and the
//!   style's `decor.lock` token. Only a face the package ships is ever named; anything else falls back to `plain` and
//!   `face_reason` says why (Shōjiki). The frontend loads `components/lock/<Name>Face.qml` (kebab → Pascal) and never
//!   compares the name (rule 4).
//! - `caps_lock`: the keyboard's Caps Lock LED (`/sys/class/leds/*::capslock`), read when the screen locks, after each
//!   attempt and when the lock face sees the Caps Lock key (`lock.caps` intent) — never on a timer (Ma). Absent when no
//!   keyboard has such an LED: unknown, never `false`.
//! - `fingerprint {available, state}`: `available` when fprintd has a reader with enrolled fingers for the user and the
//!   lock's PAM service asks pam_fprintd; `state` is `scanning` while PAM waits on its message, else `idle`. Probed once
//!   per lock (no D-Bus while unlocked).

use std::path::{Path, PathBuf};
use std::sync::{Arc, Mutex};

use serde_json::{Value, json};

use crate::config::ConfigStore;
use crate::hub::Hub;

pub const DOC: &str = "runtime.lock";
pub const KEY_FACE: &str = "lock.face";
pub const FOLLOW: &str = "follow";
pub const PLAIN: &str = "plain";
/// The theme token naming the style's lock face (the look's `[slots] lock`, W53.0a); `""` or absent = none.
pub const TOKEN: &str = "decor.lock";
/// `face_reason`: the face asked for (by name, or by the style) is not shipped.
pub const REASON_MISSING: &str = "lockui.face.missing";
/// Where the LEDs are (tests point elsewhere).
pub const LEDS_DIR: &str = "/sys/class/leds";

/// The directory the lock faces ship in.
pub fn faces_dir() -> PathBuf {
    crate::i18n::data_dir().join("frontend/components/lock")
}

/// `LoginWindowFace.qml` → `login-window`; `None` for anything that is not a face (FaceBase, other files).
fn face_name(file: &str) -> Option<String> {
    let stem = file.strip_suffix("Face.qml")?;
    if stem.is_empty() || stem == "Base" || !stem.starts_with(|c: char| c.is_ascii_uppercase()) {
        return None;
    }
    let mut out = String::new();
    for (i, c) in stem.chars().enumerate() {
        if !c.is_ascii_alphanumeric() {
            return None;
        }
        if c.is_ascii_uppercase() && i > 0 {
            out.push('-');
        }
        out.push(c.to_ascii_lowercase());
    }
    Some(out)
}

/// The faces shipped in `dir`, by name, sorted (`plain` among them).
pub fn shipped_faces(dir: &Path) -> Vec<String> {
    let mut names: Vec<String> = std::fs::read_dir(dir)
        .into_iter()
        .flatten()
        .flatten()
        .filter_map(|e| face_name(&e.file_name().to_string_lossy()))
        .collect();
    names.sort();
    names.dedup();
    names
}

/// The face in effect and, when it is not the one asked for, why.
pub fn resolve(
    setting: &str,
    style_face: &str,
    shipped: &[String],
) -> (String, Option<&'static str>) {
    let wanted = match setting {
        "" | FOLLOW => style_face,
        other => other,
    };
    if wanted.is_empty() || wanted == PLAIN {
        return (PLAIN.into(), None);
    }
    if shipped.iter().any(|f| f == wanted) {
        (wanted.into(), None)
    } else {
        (PLAIN.into(), Some(REASON_MISSING))
    }
}

/// Caps Lock from the keyboards' LEDs: on when any is lit; `None` when no keyboard has one.
pub fn caps_lock(leds: &Path) -> Option<bool> {
    let mut seen = false;
    for e in std::fs::read_dir(leds).ok()?.flatten() {
        if !e.file_name().to_string_lossy().ends_with("::capslock") {
            continue;
        }
        let Ok(b) = std::fs::read_to_string(e.path().join("brightness")) else {
            continue;
        };
        seen = true;
        if b.trim().parse::<u32>().unwrap_or(0) > 0 {
            return Some(true);
        }
    }
    seen.then_some(false)
}

/// The lock's PAM service asks pam_fprintd (a fingerprint can unlock it at all).
pub fn pam_asks_fingerprint(pam_dir: &Path, service: &str) -> bool {
    std::fs::read_to_string(pam_dir.join(service))
        .map(|t| {
            t.lines()
                .map(str::trim)
                .any(|l| !l.starts_with('#') && l.contains("pam_fprintd"))
        })
        .unwrap_or(false)
}

/// fprintd has a reader and `user` has enrolled fingers on it (system bus; `false` on any failure).
async fn fprintd_enrolled(user: &str) -> bool {
    let probe = async {
        let bus = zbus::Connection::system().await.ok()?;
        let reply = bus
            .call_method(
                Some("net.reactivated.Fprint"),
                "/net/reactivated/Fprint/Manager",
                Some("net.reactivated.Fprint.Manager"),
                "GetDefaultDevice",
                &(),
            )
            .await
            .ok()?;
        let dev: zbus::zvariant::OwnedObjectPath = reply.body().deserialize().ok()?;
        let reply = bus
            .call_method(
                Some("net.reactivated.Fprint"),
                dev.as_str(),
                Some("net.reactivated.Fprint.Device"),
                "ListEnrolledFingers",
                &(user,),
            )
            .await
            .ok()?;
        let fingers: Vec<String> = reply.body().deserialize().ok()?;
        Some(!fingers.is_empty())
    };
    tokio::time::timeout(std::time::Duration::from_secs(2), probe)
        .await
        .ok()
        .flatten()
        .unwrap_or(false)
}

/// `fingerprint.state` from the authentication state: PAM shows a message while pam_fprintd waits on the reader.
pub fn fingerprint_state(available: bool, lock: &Value) -> &'static str {
    let waiting = lock["locked"] == true
        && lock["pam_message"]["kind"] == "info"
        && lock.get("prompt").is_none();
    if available && waiting {
        "scanning"
    } else {
        "idle"
    }
}

struct State {
    locked: bool,
    fp_available: bool,
}

/// The lock extras: owns the overlays on `runtime.lock`.
pub struct LockExtras {
    hub: Arc<Hub>,
    store: Option<Arc<ConfigStore>>,
    faces: PathBuf,
    leds: PathBuf,
    pam_dir: PathBuf,
    service: String,
    state: Mutex<State>,
}

impl LockExtras {
    pub fn new(
        hub: Arc<Hub>,
        store: Option<Arc<ConfigStore>>,
        faces: PathBuf,
        leds: PathBuf,
        pam_dir: PathBuf,
        service: &str,
    ) -> Arc<Self> {
        Arc::new(Self {
            hub,
            store,
            faces,
            leds,
            pam_dir,
            service: service.into(),
            state: Mutex::new(State {
                locked: false,
                fp_available: false,
            }),
        })
    }

    fn setting(&self) -> String {
        self.store
            .as_deref()
            .map(|s| crate::theme::s(s, KEY_FACE))
            .unwrap_or_default()
    }

    fn style_face(&self) -> String {
        self.hub
            .snapshot(crate::theme::DOC)
            .ok()
            .and_then(|(_, d)| d["tokens"][TOKEN].as_str().map(String::from))
            .unwrap_or_default()
    }

    /// Re-resolves `face` (after a config or theme change).
    pub fn refresh_face(&self) {
        let (face, why) = resolve(
            &self.setting(),
            &self.style_face(),
            &shipped_faces(&self.faces),
        );
        let _ = self.hub.set_overlay(DOC, "face", Some(json!(face)));
        let _ = self
            .hub
            .set_overlay(DOC, "face_reason", why.map(|w| json!(w)));
    }

    /// Re-reads the Caps Lock LED (lock, attempts, the `lock.caps` intent).
    pub fn refresh_caps(&self) {
        let caps = caps_lock(&self.leds).map(|c| json!(c));
        let _ = self.hub.set_overlay(DOC, "caps_lock", caps);
    }

    fn set_fingerprint(&self, lock: &Value) {
        let available = self
            .state
            .lock()
            .unwrap_or_else(|e| e.into_inner())
            .fp_available;
        let fp = json!({"available": available, "state": fingerprint_state(available, lock)});
        let _ = self.hub.set_overlay(DOC, "fingerprint", Some(fp));
    }

    /// A change of `runtime.lock`: on locking, probe the LED and the reader; after an attempt, the LED again.
    async fn on_lock_doc(self: &Arc<Self>, lock: Value) {
        let locked = lock["locked"] == true;
        let was = {
            let mut st = self.state.lock().unwrap_or_else(|e| e.into_inner());
            std::mem::replace(&mut st.locked, locked)
        };
        if locked && !was {
            self.refresh_caps();
            let user = std::env::var("USER").unwrap_or_default();
            let available =
                pam_asks_fingerprint(&self.pam_dir, &self.service) && fprintd_enrolled(&user).await;
            self.state
                .lock()
                .unwrap_or_else(|e| e.into_inner())
                .fp_available = available;
        } else if locked && lock["busy"] == false {
            self.refresh_caps();
        }
        self.set_fingerprint(&lock);
    }
}

/// Registers the overlays and keeps them current: `lock.face` changes, theme changes, lock state changes. Intent
/// `lock.caps` (the lock face saw the Caps Lock key) re-reads the LED.
pub fn register(
    hub: &Arc<Hub>,
    store: Option<Arc<ConfigStore>>,
    intents: &mut crate::Intents,
) -> Arc<LockExtras> {
    let extras = LockExtras::new(
        hub.clone(),
        store.clone(),
        faces_dir(),
        LEDS_DIR.into(),
        crate::wiring::PAM_DIR.into(),
        crate::wiring::PAM_SERVICE,
    );
    extras.refresh_face();
    let fp = json!({"available": false, "state": "idle"});
    let _ = hub.set_overlay(DOC, "fingerprint", Some(fp));
    if let Some(store) = &store {
        let e = extras.clone();
        store.on_change(move |_| e.refresh_face());
    }
    let e = extras.clone();
    intents.register("lock.caps", move |_, _| {
        // The LED follows the key a moment after the press reaches the lock surface.
        let e = e.clone();
        tokio::spawn(async move {
            tokio::time::sleep(std::time::Duration::from_millis(60)).await;
            e.refresh_caps();
        });
    });
    if let Ok(rt) = tokio::runtime::Handle::try_current() {
        let mut events = hub.events();
        let e = extras.clone();
        let hub = hub.clone();
        rt.spawn(async move {
            if let Ok((_, d)) = hub.snapshot(DOC) {
                e.on_lock_doc(d).await;
            }
            loop {
                let doc = match events.recv().await {
                    Ok(msg) => match msg.as_ref() {
                        kurashi_ipc::ServerMsg::Snap { doc, .. }
                        | kurashi_ipc::ServerMsg::Patch { doc, .. } => doc.clone(),
                        _ => continue,
                    },
                    Err(tokio::sync::broadcast::error::RecvError::Lagged(_)) => {
                        e.refresh_face();
                        DOC.to_owned()
                    }
                    Err(tokio::sync::broadcast::error::RecvError::Closed) => break,
                };
                if doc == crate::theme::DOC {
                    e.refresh_face();
                } else if doc == DOC {
                    if let Ok((_, d)) = hub.snapshot(DOC) {
                        e.on_lock_doc(d).await;
                    }
                }
            }
        });
    }
    extras
}

/// Offers of `lock.face` (`choices_from = "lock.faces"`): follow the style, the plain face, then every shipped face.
pub fn face_offers() -> Vec<(String, String)> {
    let mut out = vec![
        (FOLLOW.to_owned(), "lockui.face.follow".to_owned()),
        (PLAIN.to_owned(), "lockui.face.plain".to_owned()),
    ];
    for f in shipped_faces(&faces_dir()) {
        if f != PLAIN {
            let label = format!("lockui.face.name.{f}");
            out.push((f, label));
        }
    }
    out
}

#[cfg(test)]
mod tests {
    use super::*;

    fn tmp(name: &str) -> PathBuf {
        let d = std::env::temp_dir().join(format!("kurashid-lock-{name}-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&d);
        std::fs::create_dir_all(&d).unwrap();
        d
    }

    #[test]
    fn face_names_come_from_the_files() {
        assert_eq!(face_name("PlainFace.qml").as_deref(), Some("plain"));
        assert_eq!(
            face_name("LoginWindowFace.qml").as_deref(),
            Some("login-window")
        );
        assert_eq!(face_name("FaceBase.qml"), None);
        assert_eq!(face_name("BaseFace.qml"), None);
        assert_eq!(face_name("Face.qml"), None);
        assert_eq!(face_name("qmldir"), None);
        assert_eq!(face_name("x-Face.qml"), None);
    }

    #[test]
    fn the_shipped_directory_lists_the_plain_face() {
        let faces = shipped_faces(&faces_dir());
        assert!(faces.contains(&PLAIN.to_owned()), "{faces:?}");
        assert!(!faces.iter().any(|f| f == "base"));
    }

    #[test]
    fn follow_takes_the_style_face_only_when_it_ships() {
        let shipped = vec!["logon".to_owned(), PLAIN.to_owned()];
        assert_eq!(resolve(FOLLOW, "", &shipped), (PLAIN.into(), None));
        assert_eq!(resolve(FOLLOW, "logon", &shipped), ("logon".into(), None));
        assert_eq!(
            resolve(FOLLOW, "curtain", &shipped),
            (PLAIN.into(), Some(REASON_MISSING))
        );
        // Plain holds whatever the style brings; a name holds whatever the style is.
        assert_eq!(resolve(PLAIN, "logon", &shipped), (PLAIN.into(), None));
        assert_eq!(resolve("logon", "", &shipped), ("logon".into(), None));
        assert_eq!(
            resolve("nope", "logon", &shipped),
            (PLAIN.into(), Some(REASON_MISSING))
        );
    }

    #[test]
    fn caps_lock_reads_the_leds_and_says_unknown_without_one() {
        let d = tmp("leds");
        assert_eq!(caps_lock(&d), None);
        std::fs::create_dir_all(d.join("input3::capslock")).unwrap();
        std::fs::write(d.join("input3::capslock/brightness"), "0\n").unwrap();
        std::fs::create_dir_all(d.join("input3::numlock")).unwrap();
        std::fs::write(d.join("input3::numlock/brightness"), "1\n").unwrap();
        assert_eq!(caps_lock(&d), Some(false));
        std::fs::create_dir_all(d.join("input9::capslock")).unwrap();
        std::fs::write(d.join("input9::capslock/brightness"), "1\n").unwrap();
        assert_eq!(caps_lock(&d), Some(true));
        assert_eq!(caps_lock(&d.join("missing")), None);
    }

    #[test]
    fn fingerprint_needs_pam_fprintd_and_scans_only_on_its_message() {
        let d = tmp("pam");
        std::fs::write(d.join("kurashi"), "auth sufficient pam_unix.so\n").unwrap();
        assert!(!pam_asks_fingerprint(&d, "kurashi"));
        std::fs::write(
            d.join("kurashi"),
            "# pam_fprintd off\nauth sufficient /nix/store/x/lib/security/pam_fprintd.so\n",
        )
        .unwrap();
        assert!(pam_asks_fingerprint(&d, "kurashi"));
        assert!(!pam_asks_fingerprint(&d, "other"));
        let waiting =
            json!({"locked": true, "busy": true, "pam_message": {"kind": "info", "text": "…"}});
        assert_eq!(fingerprint_state(true, &waiting), "scanning");
        assert_eq!(fingerprint_state(false, &waiting), "idle");
        assert_eq!(fingerprint_state(true, &json!({"locked": true})), "idle");
    }

    #[tokio::test]
    async fn the_overlays_ride_on_whatever_the_lock_writes() {
        let hub = Hub::new();
        hub.register(
            DOC,
            json!({"locked": false, "busy": false, "failures": 0}),
            None,
        );
        hub.register(crate::theme::DOC, json!({"tokens": {TOKEN: "logon"}}), None);
        let (faces, leds, pam) = (tmp("faces"), tmp("leds2"), tmp("pam2"));
        std::fs::write(faces.join("PlainFace.qml"), "").unwrap();
        std::fs::write(faces.join("LogonFace.qml"), "").unwrap();
        std::fs::create_dir_all(leds.join("input1::capslock")).unwrap();
        std::fs::write(leds.join("input1::capslock/brightness"), "1").unwrap();
        let e = LockExtras::new(hub.clone(), None, faces, leds.clone(), pam, "kurashi");
        e.refresh_face();
        let doc = |h: &Arc<Hub>| h.snapshot(DOC).unwrap().1;
        assert_eq!(doc(&hub)["face"], "logon");
        assert!(doc(&hub).get("face_reason").is_none());
        // The writer replaces the document: the overlays stay.
        hub.set(
            DOC,
            json!({"locked": true, "busy": false, "failures": 0}),
            None,
        )
        .unwrap();
        e.on_lock_doc(doc(&hub)).await;
        let d = doc(&hub);
        assert_eq!(d["face"], "logon");
        assert_eq!(d["caps_lock"], true);
        assert_eq!(
            d["fingerprint"],
            json!({"available": false, "state": "idle"})
        );
        // The style's face goes away: plain, and why.
        hub.set(
            crate::theme::DOC,
            json!({"tokens": {TOKEN: "curtain"}}),
            None,
        )
        .unwrap();
        e.refresh_face();
        assert_eq!(doc(&hub)["face"], PLAIN);
        assert_eq!(doc(&hub)["face_reason"], REASON_MISSING);
        // No LED at all: the field goes (unknown), never `false`.
        std::fs::remove_dir_all(leds.join("input1::capslock")).unwrap();
        e.refresh_caps();
        assert!(doc(&hub).get("caps_lock").is_none());
    }
}
