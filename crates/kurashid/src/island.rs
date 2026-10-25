//! Island hosting (K9): one arbiter per island instance, its decision published as
//! `runtime.island.<id>`, and exactly one timer armed for the next TTL expiry (Ma). The core
//! sources feed it here: media, notifications, the default output and the volume, the charger and
//! the battery, Bluetooth connections. Each is an edge of the service document (kurashi-island
//! `signals`), and the peek lines are composed from the daemon's copy (K17, `island-daemon.toml`).

use std::collections::{BTreeMap, BTreeSet};
use std::path::Path;
use std::sync::{Arc, Mutex, MutexGuard};

use kurashi_island::signals::{
    AudioEdge, AudioSample, PowerEdge, PowerSample, audio_edges, connected_edges, power_edges,
};
use kurashi_island::{
    Annotation, Arbiter, Face, FaceSignal, IslandConfig, Ms, Source, Transient, doc,
};
use serde_json::{Value, json};

use crate::actions::ActionRegistry;
use crate::config::ConfigStore;
use crate::hub::Hub;

/// Wall-clock ms, so `until` in the document means something to frontends.
fn now_ms() -> Ms {
    std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map_or(0, |d| d.as_millis() as Ms)
}

/// The island's state is a plain value, so a panic in another holder must not wedge it: the guard
/// is taken back from a poisoned lock (as kurashi-auth does).
fn lock<T>(m: &Mutex<T>) -> MutexGuard<'_, T> {
    m.lock().unwrap_or_else(|e| e.into_inner())
}

/// Code defaults of the core transients' TTLs; `island.main.ttl` replaces them once config is read.
const VOLUME_TTL: Ms = 1_500;
const POWER_TTL: Ms = 4_000;
const BATTERY_TTL: Ms = 6_000;
const BLUETOOTH_TTL: Ms = 4_000;
/// Relevance of the media and notification faces while they have something (K9 scale).
const MEDIA_RELEVANCE: u8 = 60;
const NOTIFICATION_RELEVANCE: u8 = 40;
/// A notification's summary in a peek line: its first line, at most this many characters.
const PEEK_MAX: usize = 60;

/// The daemon's copy for the peek lines (K17): flat keys of `i18n/<locale>/*.toml`, the locale's
/// text over English. A key with no text shows as the key, a visible gap rather than silence.
#[derive(Clone, Debug, Default)]
pub struct Texts(BTreeMap<String, String>);

impl Texts {
    pub fn load(root: &Path, locale: &str) -> Self {
        let mut strings = crate::i18n::load_locale(root, crate::i18n::FALLBACK);
        if locale != crate::i18n::FALLBACK {
            strings.extend(crate::i18n::load_locale(root, locale));
        }
        Texts(strings)
    }

    /// `key` with each `{name}` replaced by its value.
    pub fn t(&self, key: &str, args: &[(&str, &str)]) -> String {
        let Some(text) = self.0.get(key) else {
            return key.to_string();
        };
        args.iter().fold(text.clone(), |text, (name, value)| {
            text.replace(&format!("{{{name}}}"), value)
        })
    }

    /// "1 h 20 min" or "45 min", at least one minute: a battery's time is not shown in seconds.
    fn duration(&self, secs: u64) -> String {
        let mins = ((secs + 30) / 60).max(1);
        if mins >= 60 {
            let (h, m) = ((mins / 60).to_string(), (mins % 60).to_string());
            self.t("island.peek.hm", &[("h", h.as_str()), ("m", m.as_str())])
        } else {
            let m = mins.to_string();
            self.t("island.peek.m", &[("m", m.as_str())])
        }
    }

    fn percent(&self, n: u64) -> String {
        let n = n.to_string();
        self.t("island.peek.percent", &[("n", n.as_str())])
    }
}

/// The parts that have text, joined with the copy's separator; `None` when none has.
fn join(texts: &Texts, parts: impl IntoIterator<Item = Option<String>>) -> Option<String> {
    parts
        .into_iter()
        .flatten()
        .filter(|p| !p.is_empty())
        .reduce(|a, b| texts.t("island.peek.join", &[("a", a.as_str()), ("b", b.as_str())]))
}

/// The first non-empty line of `s`, cut to `max` characters with an ellipsis.
fn one_line(s: &str, max: usize) -> String {
    let line = s
        .lines()
        .map(str::trim)
        .find(|l| !l.is_empty())
        .unwrap_or("");
    if line.chars().count() <= max {
        line.to_string()
    } else {
        let cut: String = line.chars().take(max).collect();
        format!("{cut}…")
    }
}

/// One core transient: the face it shows, its trigger, and the peek line it carries.
struct Ping {
    face: &'static str,
    kind: &'static str,
    ttl_ms: Ms,
    may_interrupt: bool,
    detail: Option<String>,
}

/// Applies pings in order; a later ping on the same face replaces the earlier one's transient.
fn apply(arb: &mut Arbiter, now: Ms, pings: Vec<Ping>) {
    for p in pings {
        arb.signal(
            now,
            FaceSignal {
                face: p.face.into(),
                relevance: 0,
                condition: true,
                transient: Some(Transient {
                    kind: p.kind.into(),
                    ttl_ms: p.ttl_ms,
                    may_interrupt: p.may_interrupt,
                }),
            },
        );
        arb.annotate(
            p.face,
            Annotation {
                detail: p.detail,
                stale_at: None,
            },
        );
    }
}

/// The system sources the island holds subscribed itself (K30): without the hold the shell could not
/// announce a plugged charger or a connected headset while no panel reads them.
const CORE_DOCS: [&str; 2] = ["svc.power", "svc.bluetooth"];
/// The faces of the system events (`island.main.system_events`, K65): the OSDs and the notices.
const SYSTEM_FACES: [&str; 4] = ["volume", "brightness", "power", "bluetooth"];

/// The island's own hold on [`CORE_DOCS`]: held while the daemon asked for it (`follow_core`, once
/// the documents exist) and `island.main.system_events` is on (K65, I18).
struct CoreHold {
    wanted: bool,
    events: bool,
    held: Vec<&'static str>,
}

/// What a core source looked like at its last report; the edges are between two of these.
#[derive(Default)]
struct Watch {
    power: Option<PowerSample>,
    connected: Option<BTreeSet<String>>,
    audio: Option<AudioSample>,
    /// The default output the session began on: the volume OSD names any other one (brief 6).
    usual_sink: Option<String>,
}

pub struct IslandHost {
    doc: String,
    hub: Arc<Hub>,
    arb: Mutex<Arbiter>,
    timer: Mutex<Option<tokio::task::JoinHandle<()>>>,
    /// The daemon's runtime, captured while built on it. `signal` may come from any thread (the
    /// audio worker is a plain one), and only the runtime can run the expiry timer.
    rt: Option<tokio::runtime::Handle>,
    /// Edge state of the core sources. Taken before `arb` when both are needed, never the reverse.
    watch: Mutex<Watch>,
    texts: Mutex<Texts>,
    /// Taken alone: subscribing may start a service, whose first document reaches `observe_*`.
    core: Mutex<CoreHold>,
}

impl IslandHost {
    /// Registers `runtime.island.<id>` with the core faces and publishes the first decision.
    pub fn new(hub: Arc<Hub>, id: &str, cfg: IslandConfig, core_faces: &[&str]) -> Arc<Self> {
        let mut arb = Arbiter::new(cfg);
        for (i, f) in core_faces.iter().enumerate() {
            arb.register_face(Face {
                id: (*f).into(),
                source: Source::Core,
                default_priority: (core_faces.len() - i) as u8,
            });
        }
        let d = arb.decide(now_ms());
        let doc_name = format!("runtime.island.{id}");
        hub.register(&doc_name, doc(&d, arb.pinned()), None);
        Arc::new(IslandHost {
            doc: doc_name,
            hub,
            arb: Mutex::new(arb),
            timer: Mutex::new(None),
            rt: tokio::runtime::Handle::try_current().ok(),
            watch: Mutex::new(Watch::default()),
            texts: Mutex::new(Texts::default()),
            core: Mutex::new(CoreHold {
                wanted: false,
                events: true,
                held: Vec::new(),
            }),
        })
    }

    /// The peek lines and OSD details are composed in this copy; set it before the sources start.
    pub fn set_texts(&self, texts: Texts) {
        *lock(&self.texts) = texts;
    }

    /// Feed a face signal (media playing, volume changed, a mod's relevance, …).
    pub fn signal(self: &Arc<Self>, s: FaceSignal) {
        self.with(|arb, now| arb.signal(now, s));
    }

    /// Several arbiter inputs at once, one decision and one publish: `f` runs under the arbiter's lock.
    pub fn update(self: &Arc<Self>, f: impl FnOnce(&mut Arbiter, Ms)) {
        self.with(f);
    }

    pub fn register_face(self: &Arc<Self>, face: Face) {
        self.with(|arb, _| arb.register_face(face));
    }

    pub fn unregister_face(self: &Arc<Self>, id: &str) {
        self.with(|arb, _| arb.unregister_face(id));
    }

    /// Takes a face's relevance and transient back (a mod's `FaceUpdate::Clear`); the face stays
    /// registered, so the arbiter shows what else is due.
    pub fn clear_face(self: &Arc<Self>, id: &str) {
        self.with(|arb, _| arb.clear(id));
    }

    /// Whether a face is registered, shown or not (K68): a mod's face the list leaves out still holds its name, so a
    /// second mod cannot take it. Read under the arbiter's lock; no caller holds it (a registration checks first,
    /// outside `with`).
    pub fn has_face(&self, id: &str) -> bool {
        lock(&self.arb).registered(id)
    }

    /// Map `island.main.{faces,default,ttl}` onto the arbiter and re-publish. Re-register on
    /// every change with `ConfigStore::on_change`. The OSD and notice faces (`volume`, `brightness`,
    /// `power`, `bluetooth`) are always transient-only, whatever `faces` says, and `ttl` sets how
    /// long they stay (K9). A list somebody chose restricts the island to it (K68); the schema
    /// default restricts nothing, so a user who never chose one keeps every face, a mod's included.
    pub fn apply_config(self: &Arc<Self>, cfg: &ConfigStore) {
        let listed = cfg.get("island.main.faces", None);
        let restrict = listed
            .as_ref()
            .is_some_and(|p| p.source != kurashi_core::Source::Default);
        let faces = listed.and_then(|p| serde_json::from_value::<Vec<String>>(p.value).ok());
        let default = cfg
            .get("island.main.default", None)
            .and_then(|p| p.value.as_str().map(String::from));
        let ttl = cfg
            .get("island.main.ttl", None)
            .and_then(|p| p.value.as_u64());
        let events = cfg
            .get("island.main.system_events", None)
            .and_then(|p| p.value.as_bool())
            .unwrap_or(true);
        self.with(|arb, _| {
            let mut c = arb.config().clone();
            if let Some(f) = faces {
                c.faces = f;
                c.restrict = restrict;
            }
            if let Some(d) = default {
                c.default = d;
            }
            if let Some(s) = ttl {
                for kind in [
                    "volume",
                    "brightness",
                    "notification",
                    "power",
                    "battery",
                    "bluetooth",
                ] {
                    c.ttl_overrides.insert(kind.into(), s * 1000);
                }
            }
            for face in SYSTEM_FACES {
                c.transient_only.insert(face.into());
            }
            arb.set_config(c);
        });
        self.set_system_events(events);
    }

    /// Whether the system events reach the island (`island.main.system_events`, K65): the volume
    /// and brightness OSDs, the charger, the battery and Bluetooth connections.
    pub fn system_events(&self) -> bool {
        lock(&self.core).events
    }

    /// Turns the system events on or off. Off drops the island's own subscriptions to the power and
    /// Bluetooth documents (their services stop unless a panel reads them: Ma, I18) and takes back
    /// any of their transients on show; on subscribes again, and the next reports start afresh, as
    /// at startup (nothing that changed meanwhile is news).
    pub fn set_system_events(self: &Arc<Self>, on: bool) {
        {
            let mut core = lock(&self.core);
            if core.events == on {
                return;
            }
            core.events = on;
        }
        self.reconcile_core();
        if !on {
            let mut w = lock(&self.watch);
            w.power = None;
            w.connected = None;
            w.audio = None;
            drop(w);
            self.with(|arb, _| {
                for face in SYSTEM_FACES {
                    arb.clear(face);
                }
            });
        }
    }

    /// Subscribes or unsubscribes [`CORE_DOCS`] so the island holds them exactly while it wants them
    /// and the system events are on. The hub calls are made outside the lock: a subscribe may start
    /// a service whose first document comes straight back through `observe_*`.
    fn reconcile_core(&self) {
        let (take, release) = {
            let mut core = lock(&self.core);
            if core.wanted && core.events && core.held.is_empty() {
                core.held = CORE_DOCS.to_vec();
                (CORE_DOCS.to_vec(), Vec::new())
            } else if !(core.wanted && core.events) && !core.held.is_empty() {
                (Vec::new(), std::mem::take(&mut core.held))
            } else {
                return;
            }
        };
        for doc in release {
            self.hub.unsubscribe(doc);
        }
        let mut failed = Vec::new();
        for doc in take {
            if let Err(e) = self.hub.subscribe(doc) {
                tracing::warn!(doc, error = %e, "island cannot follow a core source");
                failed.push(doc);
            }
        }
        // A document that is not registered holds nothing, so it is never unsubscribed either.
        if !failed.is_empty() {
            lock(&self.core).held.retain(|d| !failed.contains(d));
        }
    }

    /// Apply an input, re-decide, publish, close a card the list dropped, re-arm the single deadline timer.
    fn with(self: &Arc<Self>, f: impl FnOnce(&mut Arbiter, Ms)) {
        let now = now_ms();
        let (value, deadline, faces) = {
            let mut arb = lock(&self.arb);
            f(&mut arb, now);
            let d = arb.decide(now);
            (doc(&d, arb.pinned()), arb.next_deadline(), d.faces)
        };
        let _ = self.hub.set(&self.doc, value, None);
        self.close_dropped_card(&faces);
        self.arm(deadline, now);
    }

    /// K68 (row 451): a card open on a face the island no longer offers closes, as a collapse does, so it never shows a
    /// face the list may not show. `runtime.ui` is wiring.rs's document; its collapse (`close_panel`) is private there, so
    /// this writes the same fields (row 470 asks for one helper for both). Called outside the arbiter's lock; an unchanged
    /// `runtime.ui` sends nothing.
    fn close_dropped_card(&self, faces: &[String]) {
        let _ = self.hub.update("runtime.ui", None, |ui| {
            let face = ui["face"].as_str().unwrap_or("");
            if ui["panel"].as_str() == Some("island")
                && !face.is_empty()
                && !faces.iter().any(|f| f == face)
            {
                ui["panel"] = json!("");
                ui["popup"] = json!(false);
                ui["tray"] = json!("");
                ui["face"] = json!("");
                if let Some(o) = ui.as_object_mut() {
                    o.remove("peek");
                }
            }
        });
    }

    /// Re-arms the one expiry timer on the runtime captured at construction, so it works from any
    /// thread: the audio worker signals from a plain one.
    fn arm(self: &Arc<Self>, deadline: Option<Ms>, now: Ms) {
        let mut timer = lock(&self.timer);
        if let Some(t) = timer.take() {
            t.abort();
        }
        let Some(at) = deadline else {
            return;
        };
        let Some(rt) = &self.rt else {
            tracing::warn!("island built outside a tokio runtime: TTL expiry not armed");
            return;
        };
        let me = self.clone();
        let wait = std::time::Duration::from_millis(at.saturating_sub(now));
        *timer = Some(rt.spawn(async move {
            tokio::time::sleep(wait).await;
            me.with(|_, _| {});
        }));
    }

    /// The core sources run only while someone subscribes (Ma), and the frontend's readers of the
    /// power and Bluetooth documents (quick settings, the island panel) subscribe only while open.
    /// The Island keeps its own subscription, so a charger or a headset is seen whenever it changes
    /// (Ma trade-off, CONTRACT-CHANGE 35) — unless `island.main.system_events` is off (K65). Both
    /// services are event-driven (no polling), and follow their bus names' owners themselves. Call
    /// once the documents are registered, after the config was applied (so a user who turned the
    /// events off never starts the services at all).
    pub fn follow_core(&self) {
        lock(&self.core).wanted = true;
        self.reconcile_core();
    }

    /// `svc.media`: relevance while something plays; the artist (else the player) as the peek line.
    pub fn observe_media(self: &Arc<Self>, doc: &Value) {
        let playing = doc["playing"].as_bool() == Some(true);
        let line = [doc["artist"].as_str(), doc["player"].as_str()]
            .into_iter()
            .flatten()
            .find(|s| !s.is_empty())
            .map(String::from);
        self.update(|arb, now| {
            arb.signal(
                now,
                FaceSignal {
                    face: "media".into(),
                    relevance: if playing { MEDIA_RELEVANCE } else { 0 },
                    condition: playing,
                    transient: None,
                },
            );
            arb.annotate(
                "media",
                Annotation {
                    detail: if playing { line } else { None },
                    stale_at: None,
                },
            );
        });
    }

    /// `svc.notifications`: relevance while anything is unread; the newest unread as the peek line.
    pub fn observe_notifications(self: &Arc<Self>, doc: &Value) {
        let unread = doc["unread"].as_u64().unwrap_or(0);
        let newest = doc["items"].as_array().and_then(|items| {
            items
                .iter()
                .filter(|i| i["read"].as_bool() != Some(true))
                .max_by_key(|i| i["time"].as_u64().unwrap_or(0))
        });
        let line = newest.and_then(|i| {
            let texts = lock(&self.texts);
            let app = i["app_name"].as_str().map(String::from);
            let summary = Some(one_line(i["summary"].as_str().unwrap_or(""), PEEK_MAX));
            join(&texts, [app, summary])
        });
        self.update(|arb, now| {
            arb.signal(
                now,
                FaceSignal {
                    face: "notifications".into(),
                    relevance: if unread > 0 {
                        NOTIFICATION_RELEVANCE
                    } else {
                        0
                    },
                    condition: unread > 0,
                    transient: None,
                },
            );
            arb.annotate(
                "notifications",
                Annotation {
                    detail: line,
                    stale_at: None,
                },
            );
        });
    }

    /// `svc.power`: the charger and the battery level are edges; each shows the `power` face (the
    /// charger) or its `battery` kind (low, critical) with the charge or the time left.
    pub fn observe_power(self: &Arc<Self>, doc: &Value) {
        if doc["available"].as_bool() != Some(true) || !self.system_events() {
            return;
        }
        let sample = PowerSample {
            on_battery: doc["on_battery"].as_bool().unwrap_or(false),
            percent: doc["percent"]
                .as_f64()
                .map(|p| p.round().clamp(0.0, 100.0) as u8),
        };
        let mut w = lock(&self.watch);
        let edges = power_edges(w.power, sample);
        w.power = Some(sample);
        if edges.is_empty() {
            return;
        }
        let texts = lock(&self.texts);
        let pings: Vec<Ping> = edges
            .into_iter()
            .map(|e| {
                let pct = sample.percent.map(|p| texts.percent(u64::from(p)));
                let left = |key: &str, field: &str| {
                    doc[field].as_u64().filter(|s| *s > 0).map(|s| {
                        let t = texts.duration(s);
                        texts.t(key, &[("t", t.as_str())])
                    })
                };
                let (kind, ttl_ms, state, extra) = match e {
                    PowerEdge::Plugged => (
                        "power",
                        POWER_TTL,
                        texts.t("island.peek.power.charging", &[]),
                        left("island.peek.to_full", "time_to_full_s"),
                    ),
                    PowerEdge::Unplugged => (
                        "power",
                        POWER_TTL,
                        texts.t("island.peek.power.battery", &[]),
                        left("island.peek.to_empty", "time_to_empty_s"),
                    ),
                    PowerEdge::Low => (
                        "battery",
                        BATTERY_TTL,
                        texts.t("island.peek.power.low", &[]),
                        None,
                    ),
                    PowerEdge::Critical => (
                        "battery",
                        BATTERY_TTL,
                        texts.t("island.peek.power.critical", &[]),
                        None,
                    ),
                };
                Ping {
                    face: "power",
                    kind,
                    ttl_ms,
                    may_interrupt: true,
                    detail: join(&texts, [Some(state), pct, extra]),
                }
            })
            .collect();
        drop(texts);
        self.update(move |arb, now| apply(arb, now, pings));
        drop(w);
    }

    /// `svc.bluetooth`: a device that becomes connected shows the `bluetooth` face with its name and
    /// battery. Devices connected when the watch starts are not news.
    pub fn observe_bluetooth(self: &Arc<Self>, doc: &Value) {
        if doc["available"].as_bool() != Some(true) || !self.system_events() {
            return;
        }
        let devices: &[Value] = doc["devices"].as_array().map(Vec::as_slice).unwrap_or(&[]);
        let connected: BTreeSet<String> = devices
            .iter()
            .filter(|d| d["connected"].as_bool() == Some(true))
            .filter_map(|d| d["address"].as_str().map(String::from))
            .collect();
        let mut w = lock(&self.watch);
        let edges = connected_edges(w.connected.as_ref(), &connected);
        w.connected = Some(connected);
        if edges.is_empty() {
            return;
        }
        let texts = lock(&self.texts);
        let pings: Vec<Ping> = edges
            .iter()
            .filter_map(|addr| {
                devices
                    .iter()
                    .find(|d| d["address"].as_str() == Some(addr.as_str()))
            })
            .map(|d| {
                let name = d["name"]
                    .as_str()
                    .filter(|n| !n.is_empty())
                    .or(d["address"].as_str())
                    .map(String::from);
                let battery = d["battery"].as_u64().map(|b| texts.percent(b));
                Ping {
                    face: "bluetooth",
                    kind: "bluetooth",
                    ttl_ms: BLUETOOTH_TTL,
                    may_interrupt: false,
                    detail: join(&texts, [name, battery]),
                }
            })
            .collect();
        drop(texts);
        self.update(move |arb, now| apply(arb, now, pings));
        drop(w);
    }

    /// `svc.audio`: a moved default output names the device; a level or mute change shows the
    /// `volume` OSD, naming the device when it is not the one the session began on.
    pub fn observe_audio(self: &Arc<Self>, doc: &Value) {
        if doc["available"].as_bool() != Some(true) || !self.system_events() {
            return;
        }
        let sink = &doc["sink"];
        let sample = AudioSample {
            sink: sink["name"].as_str().map(String::from),
            volume: doc["volume"].as_f64().unwrap_or(0.0),
            muted: doc["muted"].as_bool().unwrap_or(false),
        };
        let mut w = lock(&self.watch);
        if w.usual_sink.is_none() {
            w.usual_sink = sample.sink.clone();
        }
        let edges = audio_edges(w.audio.as_ref(), &sample);
        let other = sample.sink.is_some() && sample.sink != w.usual_sink;
        let moved = edges.contains(&AudioEdge::DeviceChanged);
        w.audio = Some(sample);
        if edges.is_empty() {
            return;
        }
        let name = sink["description"]
            .as_str()
            .filter(|d| !d.is_empty())
            .or(sink["name"].as_str())
            .map(String::from);
        let ping = Ping {
            face: "volume",
            kind: "volume",
            ttl_ms: VOLUME_TTL,
            may_interrupt: true,
            detail: if moved || other { name } else { None },
        };
        self.update(move |arb, now| apply(arb, now, vec![ping]));
        drop(w);
    }

    /// `island.next` / `island.prev` / `island.pin` (toggle) — what scroll and right-click do.
    pub fn register_actions(self: &Arc<Self>, actions: &mut ActionRegistry) {
        let me = self.clone();
        actions.register("island.next", "action.island.next", move |_: Value| {
            let me = me.clone();
            async move {
                me.with(|arb, now| {
                    arb.next(now);
                });
                Ok(None)
            }
        });
        let me = self.clone();
        actions.register("island.prev", "action.island.prev", move |_: Value| {
            let me = me.clone();
            async move {
                me.with(|arb, now| {
                    arb.prev(now);
                });
                Ok(None)
            }
        });
        let me = self.clone();
        actions.register("island.pin", "action.island.pin", move |_: Value| {
            let me = me.clone();
            async move {
                me.with(|arb, now| {
                    if arb.pinned() {
                        arb.unpin();
                    } else {
                        let face = arb.decide(now).face;
                        arb.pin(&face);
                    }
                });
                Ok(None)
            }
        });
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use kurashi_island::Transient;
    use serde_json::json;

    fn host() -> (Arc<Hub>, Arc<IslandHost>, ActionRegistry) {
        let hub = Hub::new();
        let cfg = IslandConfig {
            faces: vec!["clock".into(), "media".into(), "volume".into()],
            default: "clock".into(),
            ..Default::default()
        };
        let h = IslandHost::new(hub.clone(), "main", cfg, &["clock", "media", "volume"]);
        let mut actions = ActionRegistry::default();
        h.register_actions(&mut actions);
        (hub, h, actions)
    }

    fn face(hub: &Hub) -> Value {
        hub.snapshot("runtime.island.main").unwrap().1
    }

    fn rev(hub: &Hub) -> u64 {
        hub.snapshot("runtime.island.main").unwrap().0
    }

    fn store(hub: &Arc<Hub>, user_toml: &str) -> (Arc<ConfigStore>, std::path::PathBuf) {
        use std::sync::atomic::{AtomicUsize, Ordering};
        static N: AtomicUsize = AtomicUsize::new(0);
        let root = std::env::temp_dir().join(format!(
            "kurashid-island-{}-{}",
            std::process::id(),
            N.fetch_add(1, Ordering::SeqCst)
        ));
        let _ = std::fs::remove_dir_all(&root);
        let paths = kurashi_config::Paths::rooted(&root);
        if !user_toml.is_empty() {
            let f = paths.user_file();
            std::fs::create_dir_all(f.parent().unwrap()).unwrap();
            std::fs::write(f, user_toml).unwrap();
        }
        let s = ConfigStore::open(
            hub.clone(),
            kurashi_schema::v1::registry(),
            paths,
            kurashi_config::Options::default(),
        );
        (s, root)
    }

    #[tokio::test]
    async fn config_reconfigures_island() {
        let hub = Hub::new();
        let (cfg, root) = store(&hub, "");
        let h = IslandHost::new(
            hub.clone(),
            "main",
            IslandConfig::default(),
            &["clock", "media", "notifications", "volume"],
        );
        let mut actions = ActionRegistry::default();
        h.register_actions(&mut actions);
        {
            let h = h.clone();
            cfg.on_change(move |c| h.apply_config(c));
        }
        h.apply_config(&cfg);
        // `volume` is registered but not in the cycling ring.
        assert_eq!(face(&hub)["face"], "clock");
        for _ in 0..5 {
            actions.invoke("island.next", Value::Null).await.unwrap();
            assert_ne!(face(&hub)["face"], "volume");
        }
        cfg.apply(&[kurashi_ipc::ApplyOp::Set {
            set: "island.main.default".into(),
            value: json!("media"),
            output: None,
        }])
        .unwrap();
        // Manual hold from the cycling above still wins; unpinned default is checked in the doc.
        assert_eq!(h.arb.lock().unwrap().config().default, "media");
        cfg.apply(&[kurashi_ipc::ApplyOp::Set {
            set: "island.main.ttl".into(),
            value: json!(2),
            output: None,
        }])
        .unwrap();
        assert_eq!(h.arb.lock().unwrap().config().ttl_overrides["volume"], 2000);
        let _ = std::fs::remove_dir_all(root);
    }

    #[tokio::test]
    async fn actions_cycle_and_pin() {
        let (hub, _h, actions) = host();
        assert_eq!(face(&hub)["face"], "clock");
        actions.invoke("island.next", Value::Null).await.unwrap();
        assert_eq!(face(&hub)["face"], "media");
        actions.invoke("island.pin", Value::Null).await.unwrap();
        assert_eq!(face(&hub)["pinned"], json!(true));
        actions.invoke("island.pin", Value::Null).await.unwrap();
        assert_eq!(face(&hub)["pinned"], json!(false));
    }

    #[tokio::test]
    async fn transient_expires_via_single_timer() {
        let (hub, h, _) = host();
        h.signal(FaceSignal {
            face: "volume".into(),
            relevance: 0,
            condition: true,
            transient: Some(Transient {
                kind: "volume".into(),
                ttl_ms: 50,
                may_interrupt: true,
            }),
        });
        assert_eq!(face(&hub)["face"], "volume");
        // The wall clock drives `now`; let it pass the deadline.
        tokio::time::sleep(std::time::Duration::from_millis(120)).await;
        assert_eq!(face(&hub)["face"], "clock");
    }

    #[tokio::test]
    async fn osd_faces_are_transient_only_and_share_the_ttl() {
        let hub = Hub::new();
        let (cfg, root) = store(&hub, "");
        let h = IslandHost::new(
            hub.clone(),
            "main",
            IslandConfig::default(),
            &["clock", "media", "notifications", "volume", "brightness"],
        );
        h.apply_config(&cfg);
        let c = h.arb.lock().unwrap().config().clone();
        for kind in ["volume", "brightness"] {
            assert!(c.transient_only.contains(kind), "{kind} is not cyclable");
            // The default `island.main.ttl` is 5 s.
            assert_eq!(
                c.ttl_overrides[kind], 5000,
                "{kind} follows island.main.ttl"
            );
        }
        let _ = std::fs::remove_dir_all(root);
    }

    /// Signals arrive from threads without a runtime (the audio worker). The transient still
    /// appears, and the timer armed on the daemon's runtime still expires it.
    #[tokio::test]
    async fn signal_from_a_plain_thread_arms_the_expiry_timer() {
        let (hub, h, _) = host();
        let from_thread = h.clone();
        std::thread::spawn(move || {
            from_thread.signal(FaceSignal {
                face: "volume".into(),
                relevance: 0,
                condition: true,
                transient: Some(Transient {
                    kind: "volume".into(),
                    ttl_ms: 50,
                    may_interrupt: true,
                }),
            });
        })
        .join()
        .expect("a signal from a plain thread must not panic");
        assert_eq!(face(&hub)["face"], "volume");
        tokio::time::sleep(std::time::Duration::from_millis(150)).await;
        assert_eq!(face(&hub)["face"], "clock");
    }

    /// A panic while the state is locked must not wedge the island for good.
    #[tokio::test]
    async fn a_poisoned_island_keeps_working() {
        let (hub, h, _) = host();
        let poisoner = h.clone();
        let _ = std::thread::spawn(move || {
            let _held = poisoner.arb.lock().unwrap();
            panic!("poisoning the island on purpose (test)");
        })
        .join();
        h.signal(FaceSignal {
            face: "volume".into(),
            relevance: 0,
            condition: true,
            transient: Some(Transient {
                kind: "volume".into(),
                ttl_ms: 5_000,
                may_interrupt: true,
            }),
        });
        assert_eq!(face(&hub)["face"], "volume");
    }

    /// The core-source host: the real island faces, the English copy, and every TTL set to `ttl_ms`.
    fn core(ttl_ms: Ms) -> (Arc<Hub>, Arc<IslandHost>) {
        let hub = Hub::new();
        let mut cfg = IslandConfig {
            faces: vec!["clock".into(), "media".into(), "notifications".into()],
            default: "clock".into(),
            interruptible_by: ["volume", "brightness", "power", "battery"]
                .map(String::from)
                .into(),
            ..Default::default()
        };
        for kind in ["volume", "power", "battery", "bluetooth"] {
            cfg.ttl_overrides.insert(kind.into(), ttl_ms);
        }
        let core_faces = [
            "clock",
            "media",
            "notifications",
            "volume",
            "brightness",
            "power",
            "bluetooth",
        ];
        let h = IslandHost::new(hub.clone(), "main", cfg, &core_faces);
        let root = Path::new(env!("CARGO_MANIFEST_DIR")).join("../../i18n");
        h.set_texts(Texts::load(&root, "en"));
        (hub, h)
    }

    fn power(on_battery: bool, percent: f64, extra: Value) -> Value {
        let mut d = json!({"available": true, "present": true, "on_battery": on_battery, "percent": percent});
        for (k, v) in extra.as_object().into_iter().flatten() {
            d[k] = v.clone();
        }
        d
    }

    #[test]
    fn charger_and_battery_show_once_each_with_their_peek_line() {
        let (hub, h) = core(60_000);
        h.observe_power(&power(false, 80.0, json!({"time_to_full_s": 1200})));
        assert_eq!(face(&hub)["face"], "clock", "a baseline shows nothing");
        h.observe_power(&power(true, 60.0, json!({"time_to_empty_s": 4500})));
        let d = face(&hub);
        assert_eq!(
            (d["face"].as_str(), d["reason"].as_str()),
            (Some("power"), Some("transient"))
        );
        assert_eq!(d["detail"]["power"], "On battery · 60 % · 1 h 15 min left");
        h.observe_power(&power(true, 9.4, json!({})));
        assert_eq!(face(&hub)["detail"]["power"], "Battery low · 9 %");
        h.observe_power(&power(true, 4.0, json!({})));
        assert_eq!(face(&hub)["detail"]["power"], "Battery critical · 4 %");
        // Still critical, and still on battery: nothing is published again.
        let before = rev(&hub);
        h.observe_power(&power(true, 3.0, json!({})));
        assert_eq!(rev(&hub), before, "a state that holds repeats nothing");
        h.observe_power(&power(false, 4.0, json!({"time_to_full_s": 1200})));
        assert_eq!(
            face(&hub)["detail"]["power"],
            "Charging · 4 % · 20 min to full"
        );
    }

    #[tokio::test]
    async fn a_held_state_is_announced_once_after_its_ttl() {
        let (hub, h) = core(40);
        h.observe_power(&power(false, 80.0, json!({})));
        h.observe_power(&power(true, 60.0, json!({})));
        assert_eq!(face(&hub)["face"], "power");
        tokio::time::sleep(std::time::Duration::from_millis(90)).await;
        assert_eq!(face(&hub)["face"], "clock", "the TTL ends the transient");
        // The same reading again is no new edge: the face stays away.
        h.observe_power(&power(true, 59.0, json!({})));
        assert_eq!(face(&hub)["face"], "clock");
    }

    #[test]
    fn a_missing_power_reading_is_no_edge() {
        let (hub, h) = core(60_000);
        h.observe_power(&power(false, 80.0, json!({})));
        h.observe_power(&json!({"available": false}));
        h.observe_power(&power(true, 60.0, json!({})));
        assert_eq!(
            face(&hub)["face"],
            "power",
            "the last known charger still counts"
        );
    }

    #[test]
    fn a_bluetooth_connection_names_the_device_and_its_battery() {
        let (hub, h) = core(60_000);
        let headset = |addr: &str, name: &str, connected: bool, battery: Option<u64>| {
            let mut d =
                json!({"address": addr, "name": name, "paired": true, "connected": connected});
            if let Some(b) = battery {
                d["battery"] = json!(b);
            }
            d
        };
        h.observe_bluetooth(&json!({"available": true, "powered": true, "devices": [headset("AA", "Headset", true, None)]}));
        assert_eq!(
            face(&hub)["face"],
            "clock",
            "already connected at the baseline"
        );
        h.observe_bluetooth(&json!({"available": true, "powered": true, "devices": [
            headset("AA", "Headset", true, None),
            headset("BB", "Buds", true, Some(55)),
        ]}));
        let d = face(&hub);
        assert_eq!(
            (d["face"].as_str(), d["detail"]["bluetooth"].as_str()),
            (Some("bluetooth"), Some("Buds · 55 %"))
        );
        let before = rev(&hub);
        h.observe_bluetooth(&json!({"available": true, "powered": true, "devices": [
            headset("AA", "Headset", true, None),
            headset("BB", "Buds", true, Some(50)),
        ]}));
        assert_eq!(rev(&hub), before, "the same connection repeats nothing");
    }

    fn audio(sink: &str, desc: &str, volume: f64, muted: bool) -> Value {
        json!({"available": true, "volume": volume, "muted": muted, "sinks": [],
               "sink": {"id": 1, "name": sink, "description": desc, "default": true}})
    }

    #[test]
    fn a_moved_output_names_the_device_and_the_usual_one_is_not_named() {
        let (hub, h) = core(60_000);
        h.observe_audio(&audio("speakers", "Speakers", 0.4, false));
        assert_eq!(face(&hub)["face"], "clock", "the baseline shows nothing");
        h.observe_audio(&audio("speakers", "Speakers", 0.5, false));
        assert_eq!(face(&hub)["face"], "volume");
        assert!(
            face(&hub)["detail"].get("volume").is_none(),
            "the usual output is not named"
        );
        h.observe_audio(&audio("headphones", "Headphones", 0.5, false));
        assert_eq!(
            face(&hub)["detail"]["volume"],
            "Headphones",
            "a moved output is named"
        );
        h.observe_audio(&audio("headphones", "Headphones", 0.6, false));
        assert_eq!(
            face(&hub)["detail"]["volume"],
            "Headphones",
            "another output is named while it is not the usual one"
        );
        h.observe_audio(&audio("speakers", "Speakers", 0.6, false));
        assert_eq!(
            face(&hub)["detail"]["volume"],
            "Speakers",
            "moving back is named too"
        );
        h.observe_audio(&audio("speakers", "Speakers", 0.7, false));
        assert!(
            face(&hub)["detail"].get("volume").is_none(),
            "back on the usual output, no name"
        );
    }

    #[test]
    fn media_and_notifications_are_relevance_with_a_peek_line() {
        let (hub, h) = core(60_000);
        h.observe_media(
            &json!({"available": true, "playing": true, "artist": "Mitski", "player": "mpv"}),
        );
        assert_eq!(face(&hub)["face"], "media");
        assert_eq!(face(&hub)["detail"]["media"], "Mitski");
        h.observe_notifications(&json!({"unread": 2, "items": [
            {"app_name": "Mail", "summary": "Build finished\nlog follows", "time": 200, "read": false},
            {"app_name": "Chat", "summary": "older", "time": 100, "read": false},
            {"app_name": "Read", "summary": "read already", "time": 900, "read": true},
        ]}));
        let d = face(&hub);
        assert_eq!(
            (d["secondary"].as_str(), d["overflow"].as_u64()),
            (Some("notifications"), Some(0))
        );
        assert_eq!(d["detail"]["notifications"], "Mail · Build finished");
        h.observe_media(&json!({"available": true, "playing": false, "artist": "Mitski"}));
        assert!(
            face(&hub)["detail"].get("media").is_none(),
            "nothing playing, no peek line"
        );
        assert!(face(&hub)["secondary"].is_null());
    }

    #[test]
    fn long_summaries_are_cut_to_one_line() {
        assert_eq!(one_line("  first\nsecond ", 60), "first");
        assert_eq!(one_line("abcdef", 3), "abc…");
        assert_eq!(one_line("", 3), "");
    }

    #[test]
    fn durations_round_to_minutes_and_show_hours() {
        let texts = Texts::load(
            Path::new(env!("CARGO_MANIFEST_DIR"))
                .join("../../i18n")
                .as_path(),
            "en",
        );
        assert_eq!(texts.duration(20), "1 min");
        assert_eq!(texts.duration(45 * 60), "45 min");
        assert_eq!(texts.duration(4_500), "1 h 15 min");
        assert_eq!(texts.duration(3_600), "1 h 0 min");
    }

    #[test]
    fn a_missing_key_shows_the_key() {
        let texts = Texts::default();
        assert_eq!(texts.t("island.peek.missing", &[]), "island.peek.missing");
    }

    #[test]
    fn follow_core_keeps_power_and_bluetooth_subscribed() {
        let hub = Hub::new();
        hub.register("svc.power", json!({"available": false}), None);
        hub.register("svc.bluetooth", json!({"available": false}), None);
        let h = IslandHost::new(hub.clone(), "main", IslandConfig::default(), &["clock"]);
        assert_eq!(hub.subscribers("svc.power"), 0);
        h.follow_core();
        assert_eq!(hub.subscribers("svc.power"), 1);
        assert_eq!(hub.subscribers("svc.bluetooth"), 1);
    }

    /// A provider that counts how often its service started and stopped.
    #[derive(Default)]
    struct Counted {
        starts: std::sync::atomic::AtomicUsize,
        stops: std::sync::atomic::AtomicUsize,
    }

    impl crate::hub::Provider for Counted {
        fn start(&self, _: Arc<Hub>) {
            self.starts
                .fetch_add(1, std::sync::atomic::Ordering::SeqCst);
        }
        fn stop(&self) {
            self.stops.fetch_add(1, std::sync::atomic::Ordering::SeqCst);
        }
    }

    impl Counted {
        fn counts(&self) -> (usize, usize) {
            use std::sync::atomic::Ordering::SeqCst;
            (self.starts.load(SeqCst), self.stops.load(SeqCst))
        }
    }

    /// The core host with counted power and Bluetooth services.
    fn counted_core() -> (Arc<Hub>, Arc<IslandHost>, Arc<Counted>, Arc<Counted>) {
        let (hub, h) = core(60_000);
        let power = Arc::new(Counted::default());
        let bt = Arc::new(Counted::default());
        hub.register(
            "svc.power",
            json!({"available": false}),
            Some(power.clone()),
        );
        hub.register(
            "svc.bluetooth",
            json!({"available": false}),
            Some(bt.clone()),
        );
        (hub, h, power, bt)
    }

    /// I18 (K65): `island.main.system_events = false` drops the island's own power and Bluetooth
    /// subscriptions, so their services stop when nothing else reads them; on subscribes again.
    #[test]
    fn system_events_off_stops_the_services_the_island_held() {
        let (hub, h, power, bt) = counted_core();
        h.follow_core();
        assert_eq!(power.counts(), (1, 0));
        assert_eq!(bt.counts(), (1, 0));

        h.set_system_events(false);
        assert_eq!(hub.subscribers("svc.power"), 0);
        assert_eq!(hub.subscribers("svc.bluetooth"), 0);
        assert_eq!(power.counts(), (1, 1), "nothing else reads power: it stops");
        assert_eq!(bt.counts(), (1, 1));
        h.set_system_events(false);
        assert_eq!(power.counts(), (1, 1), "a repeated off changes nothing");

        h.set_system_events(true);
        assert_eq!(hub.subscribers("svc.power"), 1);
        assert_eq!(power.counts(), (2, 1));
        assert_eq!(bt.counts(), (2, 1));
    }

    /// Another reader (quick settings open) keeps its service running when the island lets go.
    #[test]
    fn system_events_off_leaves_other_readers_running() {
        let (hub, h, power, _) = counted_core();
        h.follow_core();
        hub.subscribe("svc.power").unwrap();
        h.set_system_events(false);
        assert_eq!(hub.subscribers("svc.power"), 1);
        assert_eq!(power.counts(), (1, 0));
        hub.unsubscribe("svc.power");
        assert_eq!(power.counts(), (1, 1));
    }

    /// The config is applied before the island follows its sources: with the events off at
    /// startup, the services never start.
    #[test]
    fn system_events_off_from_the_start_never_starts_the_services() {
        let (hub, h, power, bt) = counted_core();
        let (cfg, root) = store(&hub, "[island.main]\nsystem_events = false\n");
        h.apply_config(&cfg);
        h.follow_core();
        assert!(!h.system_events());
        assert_eq!(power.counts(), (0, 0));
        assert_eq!(bt.counts(), (0, 0));
        let _ = std::fs::remove_dir_all(root);
    }

    /// Off, no system transient shows (the charger, a headset, the volume OSD), and one on show is
    /// taken back. Back on, the first report is a baseline again: what changed meanwhile is not news.
    #[test]
    fn system_events_off_shows_no_transients_and_on_starts_afresh() {
        let (hub, h) = core(60_000);
        h.observe_power(&power(false, 80.0, json!({})));
        h.observe_power(&power(true, 79.0, json!({})));
        assert_eq!(face(&hub)["face"], "power");

        h.set_system_events(false);
        assert_eq!(
            face(&hub)["face"],
            "clock",
            "the shown notice is taken back"
        );
        h.observe_power(&power(false, 79.0, json!({})));
        h.observe_power(&power(true, 9.0, json!({})));
        h.observe_bluetooth(&json!({"available": true, "devices": []}));
        h.observe_bluetooth(&json!({"available": true, "devices": [
            {"address": "AA", "name": "Headset", "connected": true}
        ]}));
        h.observe_audio(
            &json!({"available": true, "volume": 0.4, "muted": false, "sink": {"name": "a"}}),
        );
        h.observe_audio(
            &json!({"available": true, "volume": 0.6, "muted": false, "sink": {"name": "a"}}),
        );
        assert_eq!(face(&hub)["face"], "clock", "no system event while off");

        h.set_system_events(true);
        h.observe_power(&power(false, 50.0, json!({})));
        h.observe_audio(
            &json!({"available": true, "volume": 0.6, "muted": false, "sink": {"name": "a"}}),
        );
        assert_eq!(
            face(&hub)["face"],
            "clock",
            "the first reports are baselines"
        );
        h.observe_power(&power(true, 50.0, json!({})));
        assert_eq!(
            face(&hub)["face"],
            "power",
            "an edge after that shows again"
        );
    }

    /// A mod's weather face, as `native.rs` registers one.
    fn weather() -> Face {
        Face {
            id: "weather".into(),
            source: Source::Mod("weather".into()),
            default_priority: 0,
        }
    }

    /// The island of the daemon (main.rs): its core faces registered, the schema's defaults until a config is applied.
    fn daemon_host(hub: &Arc<Hub>) -> Arc<IslandHost> {
        IslandHost::new(
            hub.clone(),
            "main",
            IslandConfig::default(),
            &[
                "clock",
                "media",
                "notifications",
                "volume",
                "brightness",
                "power",
                "bluetooth",
            ],
        )
    }

    /// The faces the island offers (`runtime.island.main.faces`), in cycling order.
    fn offered(hub: &Hub) -> Vec<String> {
        face(hub)["faces"]
            .as_array()
            .into_iter()
            .flatten()
            .filter_map(|f| f.as_str().map(String::from))
            .collect()
    }

    /// K68: a user who never chose a list keeps every face they see: a mod's face the default list does not name still
    /// shows, after the listed ones. Nothing is written to the user's config.
    #[tokio::test]
    async fn the_default_list_keeps_every_face() {
        let hub = Hub::new();
        let (cfg, root) = store(&hub, "");
        let h = daemon_host(&hub);
        h.register_face(weather());
        h.apply_config(&cfg);
        let shown = offered(&hub);
        assert_eq!(&shown[..3], ["clock", "media", "notifications"]);
        assert!(shown.iter().any(|f| f == "weather"), "{shown:?}");
        assert!(h.has_face("weather"));
        assert!(!kurashi_config::Paths::rooted(&root).user_file().exists());
        let _ = std::fs::remove_dir_all(root);
    }

    /// K68: a list the user chose restricts. A face it does not name is not offered (so `island.expand {face}` finds no
    /// face to open), cannot win by relevance, is not cycled, and keeps its name. The system faces stay exempt.
    #[tokio::test]
    async fn a_chosen_list_hides_the_faces_it_does_not_name() {
        let hub = Hub::new();
        let (cfg, root) = store(
            &hub,
            "[island.main]\nfaces = [\"clock\", \"media\", \"notifications\"]\n",
        );
        let h = daemon_host(&hub);
        h.register_face(weather());
        h.apply_config(&cfg);
        let shown = offered(&hub);
        assert_eq!(&shown[..3], ["clock", "media", "notifications"]);
        assert!(!shown.iter().any(|f| f == "weather"), "{shown:?}");
        assert!(shown.iter().any(|f| f == "volume"), "exempt: {shown:?}");
        assert!(h.has_face("weather"), "the name is still taken");
        h.signal(FaceSignal {
            face: "weather".into(),
            relevance: 90,
            condition: true,
            transient: None,
        });
        assert_eq!(face(&hub)["face"], "clock");
        let mut actions = ActionRegistry::default();
        h.register_actions(&mut actions);
        for _ in 0..5 {
            actions.invoke("island.next", Value::Null).await.unwrap();
            assert_ne!(face(&hub)["face"], "weather");
        }
        let _ = std::fs::remove_dir_all(root);
    }

    /// K68: the list takes effect at once, both ways. Listing a face shows it again; unlisting the face a pin holds drops
    /// the pin, and a face the list gives back is not pinned again.
    #[tokio::test]
    async fn a_change_of_the_list_takes_effect_at_once() {
        let hub = Hub::new();
        let (cfg, root) = store(
            &hub,
            "[island.main]\nfaces = [\"clock\", \"media\", \"notifications\"]\n",
        );
        let h = daemon_host(&hub);
        h.register_face(weather());
        {
            let h = h.clone();
            cfg.on_change(move |c| h.apply_config(c));
        }
        h.apply_config(&cfg);
        let mut actions = ActionRegistry::default();
        h.register_actions(&mut actions);
        cfg.apply(&[kurashi_ipc::ApplyOp::Set {
            set: "island.main.faces".into(),
            value: json!(["clock", "media", "notifications", "weather"]),
            output: None,
        }])
        .unwrap();
        assert!(offered(&hub).iter().any(|f| f == "weather"));
        h.signal(FaceSignal {
            face: "weather".into(),
            relevance: 90,
            condition: true,
            transient: None,
        });
        assert_eq!(face(&hub)["face"], "weather");
        actions.invoke("island.pin", Value::Null).await.unwrap();
        assert_eq!(face(&hub)["pinned"], json!(true));
        cfg.apply(&[kurashi_ipc::ApplyOp::Set {
            set: "island.main.faces".into(),
            value: json!(["clock", "media", "notifications"]),
            output: None,
        }])
        .unwrap();
        assert_eq!(face(&hub)["face"], "clock");
        assert_eq!(face(&hub)["pinned"], json!(false));
        assert_eq!(face(&hub)["reason"], "default");
        let _ = std::fs::remove_dir_all(root);
    }

    /// K68: a default face the list does not name falls back to the first face it names.
    #[test]
    fn the_default_face_falls_back_to_the_first_listed_one() {
        let hub = Hub::new();
        let (cfg, root) = store(&hub, "[island.main]\nfaces = [\"media\"]\n");
        let h = daemon_host(&hub);
        h.apply_config(&cfg);
        assert_eq!(face(&hub)["face"], "media");
        assert_eq!(face(&hub)["reason"], "default");
        let _ = std::fs::remove_dir_all(root);
    }

    /// K68: picking the default three faces is still a choice. The config store keeps a value equal to the default as the
    /// user's, so the list restricts and a mod's face it leaves out is hidden (a Settings "remove" must not do nothing).
    #[tokio::test]
    async fn choosing_the_default_faces_still_restricts() {
        let hub = Hub::new();
        let (cfg, root) = store(&hub, "");
        let h = daemon_host(&hub);
        h.register_face(weather());
        {
            let h = h.clone();
            cfg.on_change(move |c| h.apply_config(c));
        }
        h.apply_config(&cfg);
        assert!(offered(&hub).iter().any(|f| f == "weather"));
        cfg.apply(&[kurashi_ipc::ApplyOp::Set {
            set: "island.main.faces".into(),
            value: json!(["clock", "media", "notifications"]),
            output: None,
        }])
        .unwrap();
        let listed = cfg.get("island.main.faces", None).unwrap();
        assert_eq!(listed.source, kurashi_core::Source::User, "{listed:?}");
        assert!(
            !offered(&hub).iter().any(|f| f == "weather"),
            "{:?}",
            offered(&hub)
        );
        let _ = std::fs::remove_dir_all(root);
    }

    /// K68 and K65: the system events are exempt from the list. A volume change shows its OSD whatever the list names.
    #[test]
    fn the_list_does_not_hide_the_system_events() {
        let hub = Hub::new();
        let (cfg, root) = store(&hub, "[island.main]\nfaces = [\"clock\"]\n");
        let h = daemon_host(&hub);
        h.apply_config(&cfg);
        let audio = |volume: f64| json!({"available": true, "volume": volume, "muted": false, "sink": {"name": "a"}});
        h.observe_audio(&audio(0.4));
        h.observe_audio(&audio(0.6));
        assert_eq!(face(&hub)["face"], "volume");
        let _ = std::fs::remove_dir_all(root);
    }

    /// K68 (row 452): a list that names only a mod that is off shows the clock, and the document says so: the clock leads
    /// `faces`, and the faces the list leaves out come back as `unlisted`, which Settings offers.
    #[test]
    fn a_list_of_mods_that_are_off_shows_the_clock() {
        let hub = Hub::new();
        let (cfg, root) = store(&hub, "[island.main]\nfaces = [\"weather\"]\n");
        let h = daemon_host(&hub);
        h.apply_config(&cfg);
        assert_eq!(face(&hub)["face"], "clock");
        assert_eq!(face(&hub)["reason"], "default");
        assert_eq!(offered(&hub)[0], "clock");
        assert_eq!(face(&hub)["unlisted"], json!(["media", "notifications"]));
        let _ = std::fs::remove_dir_all(root);
    }

    /// K68 (row 451): a card open on a face the list drops closes, and one open on a face the list keeps stays open. A
    /// mod's face that goes away (its mod is off) closes its card the same way.
    #[tokio::test]
    async fn a_card_open_on_a_dropped_face_closes() {
        let hub = Hub::new();
        let card = |face: &str| json!({"popup": true, "panel": "island", "launcher": false, "tray": "", "face": face});
        hub.register("runtime.ui", card("media"), None);
        let (cfg, root) = store(
            &hub,
            "[island.main]\nfaces = [\"clock\", \"media\", \"notifications\"]\n",
        );
        let h = daemon_host(&hub);
        h.register_face(weather());
        {
            let h = h.clone();
            cfg.on_change(move |c| h.apply_config(c));
        }
        h.apply_config(&cfg);
        let ui = || hub.snapshot("runtime.ui").unwrap().1;
        let set_faces = |v: Value| {
            cfg.apply(&[kurashi_ipc::ApplyOp::Set {
                set: "island.main.faces".into(),
                value: v,
                output: None,
            }])
            .unwrap();
        };
        set_faces(json!(["clock", "media"]));
        assert_eq!(
            ui()["panel"],
            "island",
            "the list keeps media: the card stays"
        );
        set_faces(json!(["clock", "notifications"]));
        assert_eq!(ui()["panel"], "", "the list drops media: the card closes");
        assert_eq!(ui()["face"], "");
        assert_eq!(ui()["popup"], json!(false));
        set_faces(json!(["clock", "weather"]));
        hub.set("runtime.ui", card("weather"), None).unwrap();
        h.unregister_face("weather");
        assert_eq!(
            ui()["panel"],
            "",
            "a mod that is off takes its card with it"
        );
        assert_eq!(ui()["face"], "");
        let _ = std::fs::remove_dir_all(root);
    }
}
