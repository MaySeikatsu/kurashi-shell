//! `svc.idle` (K47): the idle policy — which stage the session is in, what to do when the seat goes idle or comes
//! back, and which of our own inhibitors hold the stages back. Pure: the daemon feeds it the compositor's idle events
//! (`ext-idle-notify-v1`, `kurashi_compositor::idle`), the settings, the media state and logind's idle inhibitors, and
//! runs the [`Step`]s it answers (brightness, `session.lock`, the compositor's power-off-monitors, logind suspend).
//!
//! Not refcounted, by design: idle is a policy that must act while nobody watches its document (like the
//! notification server), so it runs while `idle.enabled` and stops when that is off.
//!
//! Stages, in order (DMS `IdleService.qml`, ii `Idle.qml`): dim → lock → screens off → suspend, each `0` = never.
//! Our inhibitors: caffeine (DMS/ii "keep awake"), media playing (`idle.inhibit_while_media`, DMS), logind `idle`
//! block inhibitors (`systemd-inhibit --what=idle`). The apps' Wayland idle inhibitors are the compositor's: it does
//! not send idle notifications while one is up.

use std::path::Path;

use futures_util::StreamExt;
use serde::Serialize;
use serde_json::{Value, json};
use zbus::Connection;

use crate::util::{self, Props};

/// The idle settings in effect (`[idle]`, seconds).
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Settings {
    pub enabled: bool,
    pub dim_after: u32,
    pub lock_after: u32,
    pub screen_off_after: u32,
    pub suspend_after: u32,
    pub inhibit_while_media: bool,
}

impl Default for Settings {
    /// The schema's defaults.
    fn default() -> Self {
        Settings {
            enabled: true,
            dim_after: 240,
            lock_after: 300,
            screen_off_after: 600,
            suspend_after: 0,
            inhibit_while_media: true,
        }
    }
}

/// What each idle notification stands for; [`Policy::timers`] lists their timeouts in this order.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Kind {
    Dim,
    Lock,
    ScreenOff,
    Suspend,
}

pub const KINDS: [Kind; 4] = [Kind::Dim, Kind::Lock, Kind::ScreenOff, Kind::Suspend];

impl Kind {
    fn timeout(self, s: &Settings) -> u32 {
        match self {
            Kind::Dim => s.dim_after,
            Kind::Lock => s.lock_after,
            Kind::ScreenOff => s.screen_off_after,
            Kind::Suspend => s.suspend_after,
        }
    }
    /// The name `next.stage` gives it.
    fn name(self) -> &'static str {
        match self {
            Kind::Dim => "dimmed",
            Kind::Lock => "locked",
            Kind::ScreenOff => "screen_off",
            Kind::Suspend => "suspend",
        }
    }
}

/// The stage the session is in (`svc.idle.stage`), in the order they come.
#[derive(Debug, Clone, Copy, PartialEq, Eq, PartialOrd, Ord)]
pub enum Stage {
    Active,
    Dimmed,
    Locked,
    ScreenOff,
}

impl Stage {
    pub fn name(self) -> &'static str {
        match self {
            Stage::Active => "active",
            Stage::Dimmed => "dimmed",
            Stage::Locked => "locked",
            Stage::ScreenOff => "screen_off",
        }
    }
}

/// What the daemon does on a change.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Step {
    /// Lower the backlight (to [`DIM_FACTOR`] of its level), remembering the level.
    Dim,
    /// Restore the level remembered by `Dim`.
    Undim,
    Lock,
    ScreenOff,
    Suspend,
}

/// Dimming keeps this fraction of the level in effect (GNOME dims to ~30 %).
pub const DIM_FACTOR: f64 = 0.3;

/// One inhibitor in `svc.idle.inhibitors`. `why` is an i18n key for our own (media), else the app's own text.
#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
pub struct Inhibitor {
    pub who: String,
    pub why: String,
}

/// `why` of the media inhibitor.
pub const WHY_MEDIA: &str = "power.idle.why.media";

#[derive(Debug, Clone, PartialEq)]
pub struct Policy {
    settings: Settings,
    caffeine: bool,
    /// The player that is playing, while `inhibit_while_media` counts it.
    media: Option<String>,
    logind: Vec<Inhibitor>,
    stage: Stage,
    dimmed: bool,
    next: Option<(&'static str, u32)>,
    reason: Option<&'static str>,
}

impl Policy {
    pub fn new(settings: Settings) -> Self {
        Policy {
            settings,
            caffeine: false,
            media: None,
            logind: Vec::new(),
            stage: Stage::Active,
            dimmed: false,
            next: None,
            reason: None,
        }
    }

    pub fn settings(&self) -> &Settings {
        &self.settings
    }
    pub fn caffeine(&self) -> bool {
        self.caffeine
    }
    pub fn stage(&self) -> Stage {
        self.stage
    }

    /// Any of our inhibitors holds the stages back.
    pub fn inhibited(&self) -> bool {
        self.caffeine || self.media_counts() || !self.logind.is_empty()
    }

    fn media_counts(&self) -> bool {
        self.settings.inhibit_while_media && self.media.is_some()
    }

    /// The timeouts to arm, one per [`KINDS`] entry (0 = none); empty while nothing may fire.
    pub fn timers(&self) -> Vec<u32> {
        if !self.settings.enabled || self.inhibited() || self.reason.is_some() {
            return Vec::new();
        }
        KINDS.iter().map(|k| k.timeout(&self.settings)).collect()
    }

    pub fn set_settings(&mut self, s: Settings) -> Vec<Step> {
        self.settings = s;
        self.settle()
    }
    pub fn set_caffeine(&mut self, on: bool) -> Vec<Step> {
        self.caffeine = on;
        self.settle()
    }
    /// The player playing now (`None`: nothing plays).
    pub fn set_media(&mut self, playing: Option<String>) -> Vec<Step> {
        self.media = playing;
        self.settle()
    }
    pub fn set_logind(&mut self, list: Vec<Inhibitor>) -> Vec<Step> {
        self.logind = list;
        self.settle()
    }
    /// The compositor cannot send idle notifications: the stage stays active and the document says why.
    pub fn set_unavailable(&mut self, reason: Option<&'static str>) -> Vec<Step> {
        self.reason = reason;
        self.settle()
    }

    /// While nothing may fire, the session is active: a stage reached before is undone (re-arming destroys the
    /// notifications, so no `resumed` would come for it).
    fn settle(&mut self) -> Vec<Step> {
        if self.timers().is_empty() {
            self.back()
        } else {
            Vec::new()
        }
    }

    fn back(&mut self) -> Vec<Step> {
        let steps = if self.dimmed {
            vec![Step::Undim]
        } else {
            Vec::new()
        };
        self.stage = Stage::Active;
        self.dimmed = false;
        self.next = None;
        steps
    }

    /// The notification at `index` went idle.
    pub fn on_idle(&mut self, index: usize) -> Vec<Step> {
        let Some(&kind) = KINDS.get(index) else {
            return Vec::new();
        };
        if self.timers().is_empty() {
            return Vec::new();
        }
        let (stage, step) = match kind {
            Kind::Dim => (Stage::Dimmed, Step::Dim),
            Kind::Lock => (Stage::Locked, Step::Lock),
            Kind::ScreenOff => (Stage::ScreenOff, Step::ScreenOff),
            Kind::Suspend => (self.stage, Step::Suspend),
        };
        self.stage = self.stage.max(stage);
        if step == Step::Dim {
            if self.dimmed {
                return Vec::new();
            }
            self.dimmed = true;
        }
        // The next stage that is still to come, counted from this one.
        let t = kind.timeout(&self.settings);
        self.next = KINDS
            .iter()
            .map(|k| (k.name(), k.timeout(&self.settings)))
            .filter(|(_, tk)| *tk > t)
            .min_by_key(|(_, tk)| *tk)
            .map(|(name, tk)| (name, tk - t));
        vec![step]
    }

    /// Input came back.
    pub fn on_resume(&mut self) -> Vec<Step> {
        self.back()
    }

    /// The `svc.idle` document (PROTOCOL `svc.idle`).
    pub fn doc(&self) -> Value {
        let mut inhibitors: Vec<Inhibitor> = Vec::new();
        if self.media_counts()
            && let Some(who) = &self.media
        {
            inhibitors.push(Inhibitor {
                who: who.clone(),
                why: WHY_MEDIA.into(),
            });
        }
        inhibitors.extend(self.logind.iter().cloned());
        let mut d = json!({
            "enabled": self.settings.enabled,
            "stage": self.stage.name(),
            "caffeine": self.caffeine,
            "inhibited": self.inhibited(),
            "inhibitors": inhibitors,
        });
        if let Some((stage, in_s)) = self.next {
            d["next"] = json!({"stage": stage, "in_s": in_s});
        }
        if let Some(r) = self.reason {
            d["reason"] = json!(r);
        }
        d
    }
}

/// Reasons of `svc.idle.reason`.
pub const REASON_NO_PROTOCOL: &str = "power.idle.reason.no_protocol";
pub const REASON_NO_DISPLAY: &str = "power.idle.reason.no_display";
pub const REASON_LOST: &str = "power.idle.reason.lost";

/// The backlight level now, as a fraction (the first device by name, as `svc.brightness` picks it). `None`: no device.
pub fn backlight_level(dir: &Path) -> Option<f64> {
    let mut names: Vec<_> = std::fs::read_dir(dir)
        .ok()?
        .filter_map(|e| e.ok())
        .collect();
    names.sort_by_key(|e| e.file_name());
    names.into_iter().find_map(|e| {
        let num = |f: &str| {
            std::fs::read_to_string(e.path().join(f))
                .ok()?
                .trim()
                .parse::<u32>()
                .ok()
        };
        let max = num("max_brightness").filter(|m| *m > 0)?;
        Some(f64::from(num("brightness")?) / f64::from(max))
    })
}

// ---- logind idle inhibitors ------------------------------------------------------------------

const LOGIN1: &str = "org.freedesktop.login1";
const LOGIN1_PATH: &str = "/org/freedesktop/login1";
const MANAGER_IF: &str = "org.freedesktop.login1.Manager";

/// logind's `block` inhibitors whose `What` includes `idle`.
pub async fn logind_idle_inhibitors(conn: &Connection) -> zbus::Result<Vec<Inhibitor>> {
    let reply = util::call(conn, LOGIN1, LOGIN1_PATH, MANAGER_IF, "ListInhibitors", &()).await?;
    let list: Vec<(String, String, String, String, u32, u32)> = reply.body().deserialize()?;
    Ok(idle_blockers(list))
}

/// The `idle` block inhibitors of a `ListInhibitors` answer `(what, who, why, mode, uid, pid)`.
pub fn idle_blockers(list: Vec<(String, String, String, String, u32, u32)>) -> Vec<Inhibitor> {
    list.into_iter()
        .filter(|(what, _, _, mode, _, _)| mode == "block" && what.split(':').any(|w| w == "idle"))
        .map(|(_, who, why, _, _, _)| Inhibitor { who, why })
        .collect()
}

/// Follows logind's idle inhibitors: the list now, then a new list each time `BlockInhibited` changes (logind emits
/// it). Ends when the bus goes away. No polling.
pub async fn follow_logind(
    conn: Connection,
    tx: tokio::sync::mpsc::UnboundedSender<Vec<Inhibitor>>,
) -> anyhow::Result<()> {
    let rule = zbus::MatchRule::builder()
        .msg_type(zbus::message::Type::Signal)
        .interface("org.freedesktop.DBus.Properties")?
        .member("PropertiesChanged")?
        .path(LOGIN1_PATH)?
        .build();
    let mut events = util::watch(&conn, vec![rule]).await?;
    let mut last = logind_idle_inhibitors(&conn).await?;
    let _ = tx.send(last.clone());
    while let Some(Ok(msg)) = events.next().await {
        let Ok((iface, changed, _)) = msg.body().deserialize::<(String, Props, Vec<String>)>()
        else {
            continue;
        };
        if iface != MANAGER_IF || !changed.contains_key("BlockInhibited") {
            continue;
        }
        let now = logind_idle_inhibitors(&conn).await?;
        if now != last {
            last = now.clone();
            if tx.send(now).is_err() {
                break;
            }
        }
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    fn short() -> Settings {
        Settings {
            dim_after: 10,
            lock_after: 20,
            screen_off_after: 30,
            suspend_after: 0,
            ..Settings::default()
        }
    }

    #[test]
    fn stages_follow_idle_and_resume_undoes_the_dim() {
        let mut p = Policy::new(short());
        assert_eq!(p.timers(), vec![10, 20, 30, 0]);
        assert_eq!(p.on_idle(0), vec![Step::Dim]);
        assert_eq!(p.doc()["stage"], "dimmed");
        assert_eq!(p.doc()["next"], json!({"stage": "locked", "in_s": 10}));
        assert_eq!(p.on_idle(1), vec![Step::Lock]);
        assert_eq!(p.on_idle(2), vec![Step::ScreenOff]);
        assert_eq!(p.doc()["stage"], "screen_off");
        assert!(
            p.doc().get("next").is_none(),
            "suspend is never: no timer runs"
        );
        assert_eq!(p.on_resume(), vec![Step::Undim]);
        assert_eq!(p.doc()["stage"], "active");
        assert_eq!(p.on_resume(), vec![], "a second resume does nothing");
    }

    #[test]
    fn inhibitors_disarm_and_bring_the_session_back() {
        let mut p = Policy::new(short());
        p.on_idle(0);
        assert_eq!(p.set_caffeine(true), vec![Step::Undim]);
        assert!(p.timers().is_empty());
        assert_eq!(p.doc()["caffeine"], true);
        assert_eq!(p.doc()["inhibited"], true);
        assert_eq!(
            p.on_idle(1),
            vec![],
            "a late event of a destroyed notification does nothing"
        );
        p.set_caffeine(false);
        assert_eq!(p.timers().len(), 4);

        p.set_media(Some("mpv".into()));
        assert!(p.timers().is_empty());
        assert_eq!(
            p.doc()["inhibitors"],
            json!([{"who": "mpv", "why": WHY_MEDIA}])
        );
        p.set_settings(Settings {
            inhibit_while_media: false,
            ..short()
        });
        assert_eq!(
            p.timers().len(),
            4,
            "media does not count with the setting off"
        );
        assert_eq!(p.doc()["inhibitors"], json!([]));

        p.set_logind(vec![Inhibitor {
            who: "backup".into(),
            why: "Copying".into(),
        }]);
        assert!(p.doc()["inhibited"].as_bool().unwrap());
    }

    #[test]
    fn disabled_or_unsupported_arms_nothing() {
        let p = Policy::new(Settings {
            enabled: false,
            ..short()
        });
        assert!(p.timers().is_empty());
        assert_eq!(p.doc()["enabled"], false);
        let mut p = Policy::new(short());
        p.set_unavailable(Some(REASON_NO_PROTOCOL));
        assert!(p.timers().is_empty());
        assert_eq!(p.doc()["reason"], REASON_NO_PROTOCOL);
        assert_eq!(p.doc()["stage"], "active");
    }

    #[test]
    fn only_idle_block_inhibitors_count() {
        let row = |what: &str, mode: &str| {
            (
                what.to_owned(),
                "who".to_owned(),
                "why".to_owned(),
                mode.to_owned(),
                0,
                0,
            )
        };
        let got = idle_blockers(vec![
            row("sleep", "delay"),
            row("idle:sleep", "block"),
            row("idle", "delay"),
            row("handle-lid-switch", "block"),
        ]);
        assert_eq!(got.len(), 1);
    }

    #[test]
    fn backlight_level_reads_the_first_device() {
        let dir = tempfile::tempdir().unwrap();
        let dev = dir.path().join("intel_backlight");
        std::fs::create_dir(&dev).unwrap();
        std::fs::write(dev.join("max_brightness"), "200\n").unwrap();
        std::fs::write(dev.join("brightness"), "50\n").unwrap();
        assert_eq!(backlight_level(dir.path()), Some(0.25));
        assert_eq!(backlight_level(&dir.path().join("none")), None);
    }
}
