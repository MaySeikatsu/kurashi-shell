//! Island arbitration (K9): pinned > transient (TTL) > live relevance > default.
//!
//! Pure logic, no IO, no timers. Time is an input (`now`, ms on any monotone clock the daemon
//! picks) so tests are exact and the daemon arms one timer at `next_deadline()` (Ma: no ticking).
//! A user's manual cycling sits between pinned and the rest: relevance cannot override it for
//! `manual_hold_ms`; only a transient that is allowed to interrupt can.
//!
//! Beside the primary face the decision names the next live activity of another face (`secondary`)
//! and counts the rest (`overflow`). A face may also say one peek line and when its content goes
//! stale (`Annotation`); both are published only while the face is live or shown, so a stale claim
//! about a face nobody sees is never in the document (Shōjiki). Core transient sources live in
//! `signals`.

pub mod signals;

use serde_json::{Value, json};
use std::cmp::Reverse;
use std::collections::{BTreeMap, BTreeSet};

pub type Ms = u64;

#[derive(Clone, Debug, PartialEq, Eq)]
pub enum Source {
    Core,
    Mod(String),
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Face {
    pub id: String,
    pub source: Source,
    /// Breaks relevance ties before configured order does.
    pub default_priority: u8,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Transient {
    /// Trigger kind, e.g. "volume"; keys `ttl_overrides` and `interruptible_by`.
    pub kind: String,
    pub ttl_ms: Ms,
    /// Whether this transient may displace a manual choice (still gated by config).
    pub may_interrupt: bool,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct FaceSignal {
    pub face: String,
    /// 0..=100; larger values are clamped.
    pub relevance: u8,
    /// False = the face has nothing to show right now (relevance ignored).
    pub condition: bool,
    pub transient: Option<Transient>,
}

/// What a face says beside its name, composed by the daemon: one peek line, and the time after
/// which its content is only "as of" its last update. The default (nothing to say) removes it.
#[derive(Clone, Debug, Default, PartialEq, Eq)]
pub struct Annotation {
    pub detail: Option<String>,
    /// Wall-clock ms, the same clock as `Decision::until`.
    pub stale_at: Option<Ms>,
}

#[derive(Clone, Debug)]
pub struct IslandConfig {
    /// Face order: also the tie-break and the cycling order. Unlisted faces follow, by id.
    pub faces: Vec<String>,
    pub default: String,
    /// Trigger kinds whose transients may interrupt a manual hold.
    pub interruptible_by: BTreeSet<String>,
    /// Per-kind TTL replacing the signal's own.
    pub ttl_overrides: BTreeMap<String, Ms>,
    pub manual_hold_ms: Ms,
    /// Faces only a transient may show (the volume OSD): never reachable by cycling.
    pub transient_only: BTreeSet<String>,
}

impl Default for IslandConfig {
    fn default() -> Self {
        Self {
            faces: Vec::new(),
            default: String::new(),
            interruptible_by: BTreeSet::new(),
            ttl_overrides: BTreeMap::new(),
            manual_hold_ms: 10_000,
            transient_only: BTreeSet::new(),
        }
    }
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub enum Reason {
    Pinned,
    Transient { until: Ms },
    Manual { until: Ms },
    Relevance { score: u8 },
    Default,
}

impl Reason {
    pub fn as_str(&self) -> &'static str {
        match self {
            Reason::Pinned => "pinned",
            Reason::Transient { .. } => "transient",
            Reason::Manual { .. } => "manual",
            Reason::Relevance { .. } => "relevance",
            Reason::Default => "default",
        }
    }
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Decision {
    /// Empty only when no face is registered.
    pub face: String,
    pub reason: Reason,
    /// When this decision stops being valid on its own (transient/manual expiry).
    pub until: Option<Ms>,
    /// Registered faces in cycling order.
    pub faces: Vec<String>,
    /// The next live activity of a face other than `face`, shown minimal beside the pill.
    pub secondary: Option<String>,
    /// Live activities beyond `face` and `secondary`.
    pub overflow: usize,
    /// Peek lines of the live faces and of `face`, where they have one.
    pub detail: BTreeMap<String, String>,
    /// Staleness times of the same faces (wall-clock ms).
    pub stale_at: BTreeMap<String, Ms>,
}

struct Rel {
    relevance: u8,
    condition: bool,
}

pub struct Arbiter {
    cfg: IslandConfig,
    faces: BTreeMap<String, Face>,
    rel: BTreeMap<String, Rel>,
    transients: BTreeMap<String, (Ms, Transient)>, // face -> (until, trigger)
    annots: BTreeMap<String, Annotation>,
    pinned: Option<String>,
    manual: Option<(String, Ms)>,
}

impl Arbiter {
    pub fn new(cfg: IslandConfig) -> Self {
        Self {
            cfg,
            faces: BTreeMap::new(),
            rel: BTreeMap::new(),
            transients: BTreeMap::new(),
            annots: BTreeMap::new(),
            pinned: None,
            manual: None,
        }
    }

    pub fn set_config(&mut self, cfg: IslandConfig) {
        self.cfg = cfg;
    }

    pub fn config(&self) -> &IslandConfig {
        &self.cfg
    }

    pub fn register_face(&mut self, face: Face) {
        self.faces.insert(face.id.clone(), face);
    }

    /// Mods come and go: everything tied to the face is dropped, so a shown face falls back.
    pub fn unregister_face(&mut self, id: &str) {
        self.faces.remove(id);
        self.clear(id);
        if self.pinned.as_deref() == Some(id) {
            self.pinned = None;
        }
        if self.manual.as_ref().is_some_and(|(f, _)| f == id) {
            self.manual = None;
        }
    }

    /// Update a face's relevance; a transient (if any) starts its TTL at `now`. A signal without
    /// a transient leaves a running one alone. Signals for unregistered faces are ignored.
    pub fn signal(&mut self, now: Ms, s: FaceSignal) {
        if !self.faces.contains_key(&s.face) {
            return;
        }
        self.rel.insert(
            s.face.clone(),
            Rel {
                relevance: s.relevance.min(100),
                condition: s.condition,
            },
        );
        if let Some(t) = s.transient {
            let ttl = self
                .cfg
                .ttl_overrides
                .get(&t.kind)
                .copied()
                .unwrap_or(t.ttl_ms);
            self.transients.insert(s.face, (now.saturating_add(ttl), t));
        }
    }

    /// Sets what a face says beside its name (peek line, staleness). Unregistered faces are
    /// ignored; the default annotation removes the face's one.
    pub fn annotate(&mut self, face: &str, a: Annotation) {
        if !self.faces.contains_key(face) {
            return;
        }
        if a == Annotation::default() {
            self.annots.remove(face);
        } else {
            self.annots.insert(face.to_string(), a);
        }
    }

    /// Takes the face's relevance, transient and annotation back.
    pub fn clear(&mut self, face: &str) {
        self.rel.remove(face);
        self.transients.remove(face);
        self.annots.remove(face);
    }

    pub fn pin(&mut self, face: &str) -> bool {
        let ok = self.faces.contains_key(face);
        if ok {
            self.pinned = Some(face.to_string());
            self.manual = None;
        }
        ok
    }

    pub fn unpin(&mut self) {
        self.pinned = None;
    }

    pub fn pinned(&self) -> bool {
        self.pinned.is_some()
    }

    /// Cycle forward/back from the face currently shown. No-op while pinned (pin means stay).
    pub fn next(&mut self, now: Ms) -> Decision {
        self.cycle(now, 1)
    }

    pub fn prev(&mut self, now: Ms) -> Decision {
        self.cycle(now, -1)
    }

    fn cycle(&mut self, now: Ms, dir: isize) -> Decision {
        let cur = self.decide(now);
        let ring: Vec<&String> = cur
            .faces
            .iter()
            .filter(|f| !self.cfg.transient_only.contains(*f))
            .collect();
        let n = ring.len() as isize;
        if self.pinned.is_none() && n > 1 {
            // Showing a transient-only face: step from just before/after the ring's start.
            let i = ring
                .iter()
                .position(|f| **f == cur.face)
                .map_or(if dir > 0 { -1 } else { 0 }, |i| i as isize);
            let f = ring[(i + dir).rem_euclid(n) as usize].clone();
            self.manual = Some((f, now.saturating_add(self.cfg.manual_hold_ms)));
        }
        self.decide(now)
    }

    /// Earliest stored expiry (transient or manual hold); the daemon arms one timer for it.
    pub fn next_deadline(&self) -> Option<Ms> {
        self.transients
            .values()
            .map(|(u, _)| *u)
            .chain(self.manual.as_ref().map(|(_, u)| *u))
            .min()
    }

    fn rank(&self, id: &str) -> (usize, String) {
        let i = self
            .cfg
            .faces
            .iter()
            .position(|f| f == id)
            .unwrap_or(usize::MAX);
        (i, id.to_string())
    }

    fn ordered(&self) -> Vec<String> {
        let mut v: Vec<String> = self.faces.keys().cloned().collect();
        v.sort_by_key(|f| self.rank(f));
        v
    }

    /// Deterministic for a given set of inputs and `now`. Prunes expired timers first.
    pub fn decide(&mut self, now: Ms) -> Decision {
        self.transients.retain(|_, (u, _)| *u > now);
        if self.manual.as_ref().is_some_and(|(_, u)| *u <= now) {
            self.manual = None;
        }
        let faces = self.ordered();
        let (face, reason, until) = self.primary(&faces);
        let live = self.activities(now);
        let secondary = live.iter().find(|f| **f != face).cloned();
        let shown = live
            .iter()
            .filter(|f| **f == face || Some(*f) == secondary.as_ref())
            .count();
        let mut detail = BTreeMap::new();
        let mut stale_at = BTreeMap::new();
        for f in live.iter().chain(std::iter::once(&face)) {
            if let Some(a) = self.annots.get(f) {
                if let Some(line) = &a.detail {
                    detail.insert(f.clone(), line.clone());
                }
                if let Some(at) = a.stale_at {
                    stale_at.insert(f.clone(), at);
                }
            }
        }
        Decision {
            face,
            reason,
            until,
            faces,
            secondary,
            overflow: live.len() - shown,
            detail,
            stale_at,
        }
    }

    /// The face on screen by precedence: pinned, then a manual hold (a transient that may
    /// interrupt it still wins), transients, live relevance, default. Expired timers are pruned.
    fn primary(&self, faces: &[String]) -> (String, Reason, Option<Ms>) {
        if let Some(p) = &self.pinned {
            return (p.clone(), Reason::Pinned, None);
        }

        // Newest-ending transient wins; ties by configured order.
        let best_transient = |only_interrupting: bool| {
            self.transients
                .iter()
                .filter(|(_, (_, t))| {
                    !only_interrupting
                        || (t.may_interrupt && self.cfg.interruptible_by.contains(&t.kind))
                })
                .max_by(|(a, (ua, _)), (b, (ub, _))| {
                    ua.cmp(ub).then_with(|| self.rank(b).cmp(&self.rank(a)))
                })
                .map(|(f, (u, _))| (f.clone(), *u))
        };

        if let Some((mf, mu)) = &self.manual {
            if let Some((f, u)) = best_transient(true) {
                return (f, Reason::Transient { until: u }, Some(u));
            }
            return (mf.clone(), Reason::Manual { until: *mu }, Some(*mu));
        }
        if let Some((f, u)) = best_transient(false) {
            return (f, Reason::Transient { until: u }, Some(u));
        }

        let live = self
            .rel
            .iter()
            .filter(|(_, r)| r.condition && r.relevance > 0)
            .max_by(|(a, ra), (b, rb)| {
                let pa = self.faces[*a].default_priority;
                let pb = self.faces[*b].default_priority;
                (ra.relevance, pa)
                    .cmp(&(rb.relevance, pb))
                    .then_with(|| self.rank(b).cmp(&self.rank(a)))
            });
        if let Some((f, r)) = live {
            return (f.clone(), Reason::Relevance { score: r.relevance }, None);
        }

        let d = if self.faces.contains_key(&self.cfg.default) {
            self.cfg.default.clone()
        } else {
            faces.first().cloned().unwrap_or_default()
        };
        (d, Reason::Default, None)
    }

    /// Faces with a live activity (a running transient, or relevance that is up), best first, in
    /// the order `primary` picks them: transients (newest-ending first), then relevance (score,
    /// default priority), then configured order.
    fn activities(&self, now: Ms) -> Vec<String> {
        type Key = (u8, Ms, u8, u8, Reverse<(usize, String)>);
        let mut v: Vec<(String, Key)> = Vec::new();
        for f in self.faces.keys() {
            let key: Key = if let Some((u, _)) = self.transients.get(f).filter(|(u, _)| *u > now) {
                (2, *u, 0, 0, Reverse(self.rank(f)))
            } else if let Some(r) = self.rel.get(f).filter(|r| r.condition && r.relevance > 0) {
                (
                    1,
                    0,
                    r.relevance,
                    self.faces[f].default_priority,
                    Reverse(self.rank(f)),
                )
            } else {
                continue;
            };
            v.push((f.clone(), key));
        }
        v.sort_by(|a, b| b.1.cmp(&a.1));
        v.into_iter().map(|(f, _)| f).collect()
    }
}

/// The `runtime.island.<id>` document. `until` and `secondary` are additive (absent unless set),
/// `detail` and `stale_at` are maps that are absent when empty, and `overflow` is always there.
pub fn doc(d: &Decision, pinned: bool) -> Value {
    let mut v = json!({
        "face": d.face,
        "faces": d.faces,
        "reason": d.reason.as_str(),
        "pinned": pinned,
        "overflow": d.overflow,
    });
    if let Some(u) = d.until {
        v["until"] = json!(u);
    }
    if let Some(s) = &d.secondary {
        v["secondary"] = json!(s);
    }
    if !d.detail.is_empty() {
        v["detail"] = json!(d.detail);
    }
    if !d.stale_at.is_empty() {
        v["stale_at"] = json!(d.stale_at);
    }
    v
}

#[cfg(test)]
mod tests {
    use super::*;
    use proptest::prelude::*;

    fn face(id: &str, prio: u8) -> Face {
        Face {
            id: id.into(),
            source: Source::Core,
            default_priority: prio,
        }
    }
    fn sig(f: &str, rel: u8) -> FaceSignal {
        FaceSignal {
            face: f.into(),
            relevance: rel,
            condition: true,
            transient: None,
        }
    }
    #[test]
    fn transient_only_faces_are_not_cyclable() {
        let mut c = IslandConfig {
            faces: vec!["clock".into(), "media".into()],
            default: "clock".into(),
            ..Default::default()
        };
        c.transient_only.insert("volume".into());
        c.interruptible_by.insert("volume".into());
        let mut a = Arbiter::new(c);
        for (f, p) in [("clock", 3), ("media", 2), ("volume", 1)] {
            a.register_face(face(f, p));
        }
        let mut seen = vec![a.decide(0).face];
        for _ in 0..4 {
            seen.push(a.next(0).face);
        }
        assert!(!seen.iter().any(|f| f == "volume"), "{seen:?}");
        // Cycling while the OSD is up picks a ring face, shown once the OSD expires.
        a.signal(0, osd("volume", 1000, true));
        assert_eq!(a.decide(0).face, "volume");
        a.next(0);
        assert_ne!(a.decide(2000).face, "volume");
    }

    fn osd(f: &str, ttl: Ms, interrupt: bool) -> FaceSignal {
        FaceSignal {
            face: f.into(),
            relevance: 0,
            condition: false,
            transient: Some(Transient {
                kind: "volume".into(),
                ttl_ms: ttl,
                may_interrupt: interrupt,
            }),
        }
    }
    fn arb() -> Arbiter {
        let mut a = Arbiter::new(IslandConfig {
            faces: vec!["clock".into(), "media".into(), "osd".into()],
            default: "clock".into(),
            interruptible_by: ["volume".to_string()].into(),
            ..Default::default()
        });
        for (f, p) in [("clock", 0), ("media", 1), ("osd", 2)] {
            a.register_face(face(f, p));
        }
        a
    }

    #[test]
    fn precedence_table() {
        // (pin, transient, relevance) -> (face, reason)
        let cases = [
            (false, false, false, "clock", "default"),
            (false, false, true, "media", "relevance"),
            (false, true, true, "osd", "transient"),
            (true, true, true, "clock", "pinned"),
        ];
        for (pin, tr, rel, face, reason) in cases {
            let mut a = arb();
            if rel {
                a.signal(0, sig("media", 60));
            }
            if tr {
                a.signal(0, osd("osd", 2000, false));
            }
            if pin {
                a.pin("clock");
            }
            let d = a.decide(10);
            assert_eq!(
                (d.face.as_str(), d.reason.as_str()),
                (face, reason),
                "{pin}{tr}{rel}"
            );
        }
    }

    #[test]
    fn ties_by_priority_then_order() {
        let mut a = arb();
        a.signal(0, sig("osd", 50));
        a.signal(0, sig("media", 50));
        assert_eq!(a.decide(0).face, "osd"); // higher default_priority
        a.register_face(face("media", 0));
        a.register_face(face("osd", 0));
        assert_eq!(a.decide(0).face, "media"); // configured order
    }

    #[test]
    fn condition_false_ignored() {
        let mut a = arb();
        a.signal(
            0,
            FaceSignal {
                condition: false,
                ..sig("media", 90)
            },
        );
        assert_eq!(a.decide(0).reason, Reason::Default);
    }

    #[test]
    fn transient_ttl_expiry_via_deadline() {
        let mut a = arb();
        a.signal(100, sig("media", 60));
        a.signal(100, osd("osd", 2000, false));
        assert_eq!(a.next_deadline(), Some(2100));
        let d = a.decide(2099);
        assert_eq!((d.face.as_str(), d.until), ("osd", Some(2100)));
        let d = a.decide(a.next_deadline().unwrap());
        assert_eq!(d.face, "media");
        assert_eq!(a.next_deadline(), None);
    }

    #[test]
    fn ttl_override() {
        let mut a = arb();
        let mut c = a.cfg.clone();
        c.ttl_overrides.insert("volume".into(), 500);
        a.set_config(c);
        a.signal(0, osd("osd", 2000, false));
        assert_eq!(a.next_deadline(), Some(500));
    }

    #[test]
    fn manual_cycle_holds_against_relevance() {
        let mut a = arb();
        a.signal(0, sig("media", 60));
        assert_eq!(a.decide(0).face, "media");
        let d = a.next(0); // media -> osd
        assert_eq!(
            (d.face.as_str(), d.reason.clone()),
            ("osd", Reason::Manual { until: 10_000 })
        );
        a.signal(5, sig("media", 100));
        assert_eq!(a.decide(9_999).face, "osd");
        assert_eq!(a.next_deadline(), Some(10_000));
        let d = a.decide(10_000);
        assert_eq!((d.face.as_str(), d.reason.as_str()), ("media", "relevance"));
        let d = a.prev(10_000); // media -> clock
        assert_eq!(d.face, "clock");
    }

    #[test]
    fn interrupting_transient_beats_manual_only_if_allowed() {
        let mut a = arb();
        a.next(0);
        a.signal(1, osd("osd", 1000, false));
        assert_eq!(a.decide(2).reason.as_str(), "manual");
        a.signal(3, osd("osd", 1000, true));
        assert_eq!(a.decide(4).reason.as_str(), "transient");
        // may_interrupt but the kind is not allowed by config
        let mut c = a.cfg.clone();
        c.interruptible_by.clear();
        a.set_config(c);
        assert_eq!(a.decide(4).reason.as_str(), "manual");
    }

    #[test]
    fn pinned_ignores_cycling_and_unpin_restores() {
        let mut a = arb();
        a.pin("media");
        assert_eq!(a.next(0).face, "media");
        a.signal(0, osd("osd", 1000, true));
        assert_eq!(a.decide(1).reason, Reason::Pinned);
        a.unpin();
        assert_eq!(a.decide(1).face, "osd");
    }

    #[test]
    fn unregistered_shown_face_falls_back() {
        let mut a = arb();
        a.register_face(Face {
            id: "mod.weather".into(),
            source: Source::Mod("weather".into()),
            default_priority: 0,
        });
        a.signal(0, sig("mod.weather", 80));
        assert_eq!(a.decide(0).face, "mod.weather");
        a.unregister_face("mod.weather");
        let d = a.decide(0);
        assert_eq!((d.face.as_str(), d.reason.as_str()), ("clock", "default"));
        assert_eq!(d.faces, ["clock", "media", "osd"]);
        // a pinned mod face also falls back
        a.register_face(face("m", 0));
        a.pin("m");
        a.unregister_face("m");
        assert!(!a.pinned());
    }

    #[test]
    fn doc_shape() {
        let mut a = arb();
        a.signal(0, osd("osd", 2000, false));
        let d = a.decide(0);
        assert_eq!(
            doc(&d, false),
            json!({"face":"osd","faces":["clock","media","osd"],"reason":"transient","pinned":false,"overflow":0,"until":2000})
        );
        let d = arb().decide(0);
        assert!(doc(&d, false).get("until").is_none());
        assert_eq!(doc(&d, false)["overflow"], 0);
        assert!(doc(&d, false).get("secondary").is_none());
        assert!(doc(&d, false).get("detail").is_none());
        assert!(doc(&d, false).get("stale_at").is_none());
    }

    #[test]
    fn secondary_is_the_next_live_activity_of_another_face() {
        let mut a = arb(); // clock, media, osd
        a.signal(0, sig("media", 60));
        assert_eq!(a.decide(0).secondary, None, "one activity has no secondary");
        a.signal(0, osd("osd", 2000, true));
        let d = a.decide(0);
        assert_eq!(
            (d.face.as_str(), d.secondary.as_deref(), d.overflow),
            ("osd", Some("media"), 0)
        );
        // Pinned: the pinned face stays primary; the live ones are offered beside it, transients first.
        a.pin("clock");
        let d = a.decide(0);
        assert_eq!(
            (d.face.as_str(), d.secondary.as_deref(), d.overflow),
            ("clock", Some("osd"), 1)
        );
        assert_eq!(doc(&d, true)["secondary"], "osd");
    }

    #[test]
    fn overflow_counts_live_activities_beyond_primary_and_secondary() {
        let mut a = arb();
        a.register_face(face("notif", 3));
        a.signal(0, sig("media", 60));
        a.signal(0, sig("notif", 40));
        a.signal(0, osd("osd", 2000, false));
        let d = a.decide(0);
        assert_eq!(
            (d.face.as_str(), d.secondary.as_deref(), d.overflow),
            ("osd", Some("media"), 1),
            "notif is the one left over"
        );
        // A face whose condition is down is not an activity, however high its relevance.
        a.signal(
            1,
            FaceSignal {
                condition: false,
                ..sig("notif", 90)
            },
        );
        assert_eq!(a.decide(1).overflow, 0);
        // Nothing live, only the default: no secondary, no overflow.
        a.clear("osd");
        a.clear("media");
        let d = a.decide(1);
        assert_eq!((d.secondary, d.overflow), (None, 0));
    }

    #[test]
    fn annotations_are_exposed_only_for_live_or_shown_faces() {
        let mut a = arb();
        let media = Annotation {
            detail: Some("Mitski".into()),
            stale_at: None,
        };
        a.annotate("media", media.clone());
        assert!(a.decide(0).detail.is_empty(), "media is not live");
        a.signal(0, sig("media", 60));
        assert_eq!(a.decide(0).detail["media"], "Mitski");
        // The pinned face is shown, so its own annotation is exposed even when it is not live.
        a.annotate(
            "clock",
            Annotation {
                detail: Some("10:00 standup".into()),
                stale_at: Some(9_000),
            },
        );
        a.pin("clock");
        let d = a.decide(0);
        assert_eq!(d.detail["clock"], "10:00 standup");
        assert_eq!(d.stale_at["clock"], 9_000);
        assert_eq!(d.detail["media"], "Mitski", "live (secondary) as well");
        let v = doc(&d, true);
        assert_eq!(v["detail"]["clock"], "10:00 standup");
        assert_eq!(v["stale_at"], json!({"clock": 9000}));
    }

    #[test]
    fn annotations_go_with_the_face_and_default_removes_them() {
        let mut a = arb();
        a.signal(0, sig("media", 60));
        a.annotate(
            "media",
            Annotation {
                detail: Some("x".into()),
                stale_at: Some(5),
            },
        );
        assert_eq!(a.decide(0).stale_at["media"], 5);
        a.annotate("media", Annotation::default());
        let d = a.decide(0);
        assert!(d.detail.is_empty() && d.stale_at.is_empty());
        a.annotate(
            "media",
            Annotation {
                detail: Some("y".into()),
                stale_at: None,
            },
        );
        a.clear("media");
        assert!(a.decide(0).detail.is_empty(), "clear drops the annotation");
        // An unregistered face cannot be annotated, and unregistering drops its annotation.
        a.annotate(
            "ghost",
            Annotation {
                detail: Some("z".into()),
                stale_at: None,
            },
        );
        a.signal(0, sig("media", 60));
        a.annotate(
            "media",
            Annotation {
                detail: Some("w".into()),
                stale_at: None,
            },
        );
        a.unregister_face("media");
        assert!(a.decide(0).detail.is_empty());
    }

    /// `fixtures/ipc/server/snap_island.json` is the document of this scenario: a volume OSD on top
    /// of live media and a notification, with a peek line on each (the frontend's golden).
    #[test]
    fn snap_island_fixture_is_the_document() {
        let mut a = Arbiter::new(IslandConfig {
            faces: vec!["clock".into(), "media".into(), "notifications".into()],
            default: "clock".into(),
            interruptible_by: ["volume".to_string()].into(),
            transient_only: ["volume".to_string()].into(),
            ..Default::default()
        });
        for (f, p) in [
            ("clock", 3),
            ("media", 2),
            ("notifications", 1),
            ("volume", 0),
        ] {
            a.register_face(face(f, p));
        }
        a.signal(0, sig("media", 60));
        a.annotate(
            "media",
            Annotation {
                detail: Some("Mitski · Working for the Man".into()),
                stale_at: None,
            },
        );
        a.signal(
            0,
            FaceSignal {
                face: "notifications".into(),
                relevance: 40,
                condition: true,
                transient: None,
            },
        );
        a.annotate(
            "notifications",
            Annotation {
                detail: Some("Mail · Build finished".into()),
                stale_at: None,
            },
        );
        a.signal(1_000, osd("volume", 1_500, true));
        a.annotate(
            "volume",
            Annotation {
                detail: Some("Headphones".into()),
                stale_at: None,
            },
        );
        let fixture: Value = serde_json::from_str(include_str!(
            "../../../fixtures/ipc/server/snap_island.json"
        ))
        .unwrap();
        assert_eq!(doc(&a.decide(1_200), false), fixture["data"]);
    }

    #[test]
    fn stale_at_survives_the_document_and_expires_with_the_face() {
        let mut a = arb();
        a.signal(0, sig("media", 60));
        a.annotate(
            "media",
            Annotation {
                detail: None,
                stale_at: Some(7_000),
            },
        );
        let d = a.decide(100);
        assert_eq!(doc(&d, false)["stale_at"], json!({"media": 7000}));
        // Stale data is not a reason to hide the face: freshness is data the view renders.
        assert_eq!(d.face, "media");
        a.signal(
            200,
            FaceSignal {
                condition: false,
                ..sig("media", 60)
            },
        );
        assert!(a.decide(300).stale_at.is_empty());
    }

    proptest! {
        #[test]
        fn arrival_order_independent(
            sigs in proptest::collection::vec(
                (0usize..3, 0u8..=100, any::<bool>(), proptest::option::of((100u64..5000, any::<bool>()))),
                0..3,
            ),
            now in 0u64..6000,
            seed in any::<u64>(),
        ) {
            // one signal per face (a later signal for the same face legitimately replaces)
            let names = ["clock", "media", "osd"];
            let mut by_face: BTreeMap<usize, FaceSignal> = BTreeMap::new();
            for (i, rel, cond, tr) in sigs {
                by_face.insert(i, FaceSignal {
                    face: names[i].into(),
                    relevance: rel,
                    condition: cond,
                    transient: tr.map(|(ttl, int)| Transient {
                        kind: "volume".into(), ttl_ms: ttl, may_interrupt: int,
                    }),
                });
            }
            let list: Vec<_> = by_face.into_values().collect();
            let mut shuffled = list.clone();
            let n = shuffled.len().max(1);
            shuffled.rotate_left((seed as usize) % n);
            if seed % 2 == 0 {
                shuffled.reverse();
            }
            let run = |order: &[FaceSignal], reg_rev: bool| {
                let mut a = Arbiter::new(IslandConfig {
                    faces: vec!["clock".into(), "media".into()], // osd unlisted
                    default: "clock".into(),
                    ..Default::default()
                });
                let mut fs = vec![face("clock", 0), face("media", 1), face("osd", 2)];
                if reg_rev {
                    fs.reverse();
                }
                for f in fs {
                    a.register_face(f);
                }
                for s in order {
                    a.signal(0, s.clone());
                }
                (a.decide(now), a.next_deadline())
            };
            prop_assert_eq!(run(&list, false), run(&shuffled, true));
        }
    }
}
