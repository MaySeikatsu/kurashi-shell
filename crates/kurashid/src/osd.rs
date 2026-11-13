//! The OSD (session 33, I527; docs/ux/osd.md): the transient answer to a system change — volume, mic mute, brightness,
//! keyboard layout — as one document the frontend's OSD surface draws, `runtime.osd`. The daemon decides what is worth
//! showing (an edge of the document it watches, an event the settings want shown) and where (`osd.place`); with
//! `osd.place = island` the island's own faces show volume and brightness as before (K65) and nothing is published here.
//!
//! `runtime.osd`: `{}` until the first event, then `{seq, kind, value?, muted?, label?, icon, place, timeout_ms}`; `seq`
//! rises with every event, so the same level shown twice (a key held at 100 %) still reads as a new one.

use std::sync::Mutex;

use serde_json::{Value, json};

use crate::config::ConfigStore;
use crate::hub::Hub;

pub const DOC: &str = "runtime.osd";

/// What the settings say (`osd.*`), read on every config change.
#[derive(Debug, Clone, PartialEq)]
struct Prefs {
    place: String,
    timeout_ms: u64,
    volume: bool,
    mic: bool,
    brightness: bool,
    layout: bool,
}

impl Default for Prefs {
    fn default() -> Self {
        Self {
            place: "bottom".into(),
            timeout_ms: 1500,
            volume: true,
            mic: true,
            brightness: true,
            layout: true,
        }
    }
}

/// The last value of each watched source: an OSD is an edge, never the first report.
#[derive(Default)]
struct Seen {
    audio: Option<(f64, bool, bool)>,
    layout: Option<usize>,
}

#[derive(Default)]
pub struct Osd {
    prefs: Mutex<Prefs>,
    seen: Mutex<Seen>,
    seq: Mutex<u64>,
}

impl Osd {
    /// `osd.*` from the config in effect.
    pub fn apply_config(&self, cfg: &ConfigStore) {
        let d = Prefs::default();
        let s = |k: &str, def: &str| {
            cfg.get(k, None)
                .and_then(|p| p.value.as_str().map(String::from))
                .unwrap_or_else(|| def.to_string())
        };
        let b = |k: &str, def: bool| {
            cfg.get(k, None)
                .and_then(|p| p.value.as_bool())
                .unwrap_or(def)
        };
        let p = Prefs {
            place: s("osd.place", &d.place),
            timeout_ms: cfg
                .get("osd.timeout_ms", None)
                .and_then(|p| p.value.as_u64())
                .unwrap_or(d.timeout_ms),
            volume: b("osd.volume", d.volume),
            mic: b("osd.mic", d.mic),
            brightness: b("osd.brightness", d.brightness),
            layout: b("osd.layout", d.layout),
        };
        *self.prefs.lock().expect("osd prefs") = p;
    }

    /// Sets where the OSD shows without a config (tests; a daemon with no config store keeps the default).
    pub fn set_place(&self, place: &str) {
        self.prefs.lock().expect("osd prefs").place = place.to_string();
    }

    /// The island shows volume and brightness itself (`osd.place = island`, K65's faces).
    pub fn in_island(&self) -> bool {
        self.prefs.lock().expect("osd prefs").place == "island"
    }

    /// `svc.audio`: a level, mute or mic-mute change. The first report only sets what was seen.
    pub fn observe_audio(&self, hub: &Hub, doc: &Value) {
        if doc["available"].as_bool() != Some(true) {
            return;
        }
        let now = (
            doc["volume"].as_f64().unwrap_or(0.0),
            doc["muted"].as_bool().unwrap_or(false),
            doc["source"]["muted"].as_bool().unwrap_or(false),
        );
        let was = self.seen.lock().expect("osd seen").audio.replace(now);
        let Some((vol, muted, mic)) = was else {
            return;
        };
        let p = self.prefs.lock().expect("osd prefs").clone();
        if p.place == "island" {
            return;
        }
        let sink = doc["sink"]["description"]
            .as_str()
            .filter(|s| !s.is_empty())
            .or(doc["sink"]["name"].as_str())
            .unwrap_or_default()
            .to_string();
        if p.mic && mic != now.2 {
            let label = doc["source"]["description"].as_str().unwrap_or_default();
            self.publish(
                hub,
                &p,
                json!({"kind": "mic", "muted": now.2, "label": label,
                "icon": if now.2 { "mic_off" } else { "mic" }}),
            );
        } else if p.volume && ((vol - now.0).abs() > 1e-4 || muted != now.1) {
            let icon = if now.1 || now.0 <= 0.0 {
                "volume_off"
            } else if now.0 < 0.5 {
                "volume_down"
            } else {
                "volume_up"
            };
            self.publish(
                hub,
                &p,
                json!({"kind": "volume", "value": now.0, "muted": now.1,
                "label": sink, "icon": icon}),
            );
        }
    }

    /// A brightness change by key or action (the level written, 0..=1).
    pub fn brightness(&self, hub: &Hub, level: f64) {
        let p = self.prefs.lock().expect("osd prefs").clone();
        if p.place == "island" || !p.brightness {
            return;
        }
        let icon = if level < 0.34 {
            "brightness_low"
        } else if level < 0.67 {
            "brightness_medium"
        } else {
            "brightness_high"
        };
        self.publish(
            hub,
            &p,
            json!({"kind": "brightness", "value": level, "icon": icon}),
        );
    }

    /// `svc.keyboard`: the current layout changed (not the first report).
    pub fn observe_keyboard(&self, hub: &Hub, doc: &Value) {
        let Some(cur) = doc["current"].as_u64().map(|c| c as usize) else {
            return;
        };
        let layouts = doc["layouts"].as_array().cloned().unwrap_or_default();
        if layouts.len() < 2 {
            self.seen.lock().expect("osd seen").layout = Some(cur);
            return;
        }
        let was = self.seen.lock().expect("osd seen").layout.replace(cur);
        if was.is_none() || was == Some(cur) {
            return;
        }
        let p = self.prefs.lock().expect("osd prefs").clone();
        if !p.layout {
            return;
        }
        let l = &layouts[cur.min(layouts.len() - 1)];
        // (the layout is no island face: it shows here whatever `place` says, the island place drawing it centred)
        self.publish(
            hub,
            &p,
            json!({"kind": "layout", "label": l["name"], "short": l["short"],
            "icon": "keyboard"}),
        );
    }

    fn publish(&self, hub: &Hub, p: &Prefs, mut event: Value) {
        let seq = {
            let mut s = self.seq.lock().expect("osd seq");
            *s += 1;
            *s
        };
        event["seq"] = json!(seq);
        event["place"] = json!(if p.place == "island" {
            "bottom"
        } else {
            p.place.as_str()
        });
        event["timeout_ms"] = json!(p.timeout_ms);
        let _ = hub.update(DOC, None, |d| *d = event);
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn audio(vol: f64, muted: bool, mic: bool) -> Value {
        json!({"available": true, "volume": vol, "muted": muted,
               "sink": {"name": "a", "description": "Speakers"},
               "source": {"muted": mic, "description": "Headset"}})
    }

    fn doc(hub: &Hub) -> Value {
        hub.snapshot(DOC).unwrap().1
    }

    #[test]
    fn a_volume_edge_shows_and_the_first_report_does_not() {
        let hub = Hub::new();
        hub.register(DOC, json!({}), None);
        let osd = Osd::default();
        osd.observe_audio(&hub, &audio(0.4, false, false));
        assert_eq!(doc(&hub), json!({}), "the first report is no change");
        osd.observe_audio(&hub, &audio(0.5, false, false));
        let d = doc(&hub);
        assert_eq!(
            (d["kind"].as_str(), d["value"].as_f64()),
            (Some("volume"), Some(0.5))
        );
        assert_eq!(d["label"], "Speakers");
        assert_eq!(d["seq"], 1);
        osd.observe_audio(&hub, &audio(0.5, true, false));
        assert_eq!(
            (doc(&hub)["muted"].as_bool(), doc(&hub)["seq"].as_u64()),
            (Some(true), Some(2))
        );
        osd.observe_audio(&hub, &audio(0.5, true, true));
        assert_eq!(doc(&hub)["kind"], "mic");
        osd.observe_audio(&hub, &audio(0.5, true, true));
        assert_eq!(doc(&hub)["seq"], 3, "no change, no OSD");
    }

    #[test]
    fn a_layout_change_shows_its_name_and_a_single_layout_shows_nothing() {
        let hub = Hub::new();
        hub.register(DOC, json!({}), None);
        let osd = Osd::default();
        let kb = |c: u64| {
            json!({"layouts": [{"name": "English (US)", "short": "EN"},
                                             {"name": "Japanese", "short": "JA"}], "current": c})
        };
        osd.observe_keyboard(&hub, &kb(0));
        osd.observe_keyboard(&hub, &kb(1));
        assert_eq!(
            (doc(&hub)["kind"].as_str(), doc(&hub)["short"].as_str()),
            (Some("layout"), Some("JA"))
        );
        let hub2 = Hub::new();
        hub2.register(DOC, json!({}), None);
        let osd2 = Osd::default();
        osd2.observe_keyboard(
            &hub2,
            &json!({"layouts": [{"name": "EN", "short": "EN"}], "current": 0}),
        );
        osd2.observe_keyboard(
            &hub2,
            &json!({"layouts": [{"name": "EN", "short": "EN"}], "current": 0}),
        );
        assert_eq!(doc(&hub2), json!({}));
    }

    #[test]
    fn the_island_place_publishes_nothing_for_its_own_faces() {
        let hub = Hub::new();
        hub.register(DOC, json!({}), None);
        let osd = Osd::default();
        osd.prefs.lock().unwrap().place = "island".into();
        osd.brightness(&hub, 0.5);
        osd.observe_audio(&hub, &audio(0.4, false, false));
        osd.observe_audio(&hub, &audio(0.6, false, false));
        assert_eq!(doc(&hub), json!({}));
        assert!(osd.in_island());
    }
}
