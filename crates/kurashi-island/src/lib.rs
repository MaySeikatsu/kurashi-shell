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
    /// Face order: also the tie-break and the cycling order. Unlisted faces follow, by id, unless `restrict` holds
    /// them back.
    pub faces: Vec<String>,
    /// The list decides which faces show (K68): with it on and non-empty, a registered face it does not name is never
    /// offered, not as the default, by relevance or by cycling, and cannot be pinned. Off (the default list), `faces`
    /// only orders them, so every face shows.
    pub restrict: bool,
    pub default: String,
    /// Trigger kinds whose transients may interrupt a manual hold.
    pub interruptible_by: BTreeSet<String>,
    /// Per-kind TTL replacing the signal's own.
    pub ttl_overrides: BTreeMap<String, Ms>,
    pub manual_hold_ms: Ms,
    /// Faces only a transient may show (the volume OSD): never reachable by cycling, and exempt from the list (the
    /// system events govern them, K65).
    pub transient_only: BTreeSet<String>,
}

impl Default for IslandConfig {
    fn default() -> Self {
        Self {
            faces: Vec::new(),
            restrict: false,
            default: String::new(),
            interruptible_by: BTreeSet::new(),
            ttl_overrides: BTreeMap::new(),
            manual_hold_ms: 10_000,
            transient_only: BTreeSet::new(),
        }
    }
}

impl IslandConfig {
    /// Whether the list decides what shows: it restricts and it is not empty (an empty list shows every face).
    fn restricts(&self) -> bool {
        self.restrict && !self.faces.is_empty()
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
    /// The faces the island may show, in cycling order.
    pub faces: Vec<String>,
    /// Registered faces the list leaves out (K68), in cycling order: Settings offers them, the island never shows them.
    /// Empty unless the list restricts.
    pub unlisted: Vec<String>,
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
        let ok = self.offered(face);
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

    /// Earliest stored expiry of a face the list offers (transient or manual hold); the daemon arms one timer for it.
    /// A hidden face's timer would wake the daemon for nothing (Ma).
    pub fn next_deadline(&self) -> Option<Ms> {
        self.transients
            .iter()
            .filter(|(f, _)| self.offered(f))
            .map(|(_, (u, _))| *u)
            .chain(
                self.manual
                    .as_ref()
                    .filter(|(f, _)| self.offered(f))
                    .map(|(_, u)| *u),
            )
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

    /// Whether `id` is registered, shown or not: the island's own answer to "is this face known" (K68).
    pub fn registered(&self, id: &str) -> bool {
        self.faces.contains_key(id)
    }

    /// Whether the face may show now: registered, and named by the list when the list restricts. Faces only a
    /// transient may show are exempt (K65).
    fn offered(&self, id: &str) -> bool {
        self.faces.contains_key(id)
            && (!self.cfg.restricts()
                || self.cfg.transient_only.contains(id)
                || self.cfg.faces.iter().any(|f| f == id))
    }

    /// The registered faces `keep` accepts, in configured order (unlisted ones by id).
    fn sorted(&self, keep: impl Fn(&str) -> bool) -> Vec<String> {
        let mut v: Vec<String> = self
            .faces
            .keys()
            .filter(|f| keep(f.as_str()))
            .cloned()
            .collect();
        v.sort_by_key(|f| self.rank(f));
        v
    }

    /// The faces the island offers, in cycling order.
    fn ordered(&self) -> Vec<String> {
        self.sorted(|f| self.offered(f))
    }

    /// Registered faces the list leaves out, in cycling order (K68).
    fn unlisted(&self) -> Vec<String> {
        self.sorted(|f| !self.offered(f))
    }

    /// Deterministic for a given set of inputs and `now`. Prunes expired timers first, and drops a pin or a manual
    /// hold that the list no longer offers: the island never stays on a face it may not show.
    pub fn decide(&mut self, now: Ms) -> Decision {
        self.transients.retain(|_, (u, _)| *u > now);
        if self.manual.as_ref().is_some_and(|(_, u)| *u <= now) {
            self.manual = None;
        }
        if self.pinned.as_deref().is_some_and(|p| !self.offered(p)) {
            self.pinned = None;
        }
        if self.manual.as_ref().is_some_and(|(f, _)| !self.offered(f)) {
            self.manual = None;
        }
        let faces = self.ordered();
        let unlisted = self.unlisted();
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
            unlisted,
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
                .filter(|(f, (_, t))| {
                    self.offered(f)
                        && (!only_interrupting
                            || (t.may_interrupt && self.cfg.interruptible_by.contains(&t.kind)))
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
            .filter(|(f, r)| r.condition && r.relevance > 0 && self.offered(f))
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

        let d = if faces.contains(&self.cfg.default) {
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
        for f in self.faces.keys().filter(|f| self.offered(f)) {
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
    // K68 (row 450): the registered faces the list leaves out, so Settings can offer them back; absent when empty.
    if !d.unlisted.is_empty() {
        v["unlisted"] = json!(d.unlisted);
    }
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

    /// Clock, media and a mod's weather face registered; the list names `faces` and restricts.
    fn listed(faces: &[&str]) -> Arbiter {
        let mut a = Arbiter::new(IslandConfig {
            faces: faces.iter().map(|f| f.to_string()).collect(),
            restrict: true,
            default: "clock".into(),
            ..Default::default()
        });
        for (f, p) in [("clock", 0), ("media", 1), ("weather", 2)] {
            a.register_face(face(f, p));
        }
        a
    }

    /// K68: a face the list does not name never shows: not by relevance, not as the default, not by a transient
    /// (even one that may interrupt), not by cycling, and it cannot be pinned.
    #[test]
    fn an_unlisted_face_never_shows() {
        let mut a = listed(&["clock", "media"]);
        a.signal(0, sig("weather", 90));
        let d = a.decide(0);
        assert_eq!((d.face.as_str(), d.reason.as_str()), ("clock", "default"));
        assert_eq!(d.faces, ["clock", "media"]);
        assert_eq!(d.unlisted, ["weather"]);
        assert_eq!(d.overflow, 0);
        // Row 450: the document names the left-out face so Settings can offer it back.
        assert_eq!(doc(&d, false)["unlisted"], json!(["weather"]));
        let mut c = a.cfg.clone();
        c.interruptible_by.insert("volume".into());
        a.set_config(c);
        a.clear("weather");
        a.signal(0, osd("weather", 1000, true));
        assert_eq!(
            a.decide(0).face,
            "clock",
            "an interrupting transient of an unlisted face is no face"
        );
        let seen: Vec<String> = (0..4).map(|_| a.next(0).face).collect();
        assert!(!seen.iter().any(|f| f == "weather"), "{seen:?}");
        assert!(!a.pin("weather"));
        assert!(!a.pinned());
    }

    /// K68: the list keeps the transient-only faces (the system events, K65) whatever it names: they show on a
    /// transient, are listed after the list, and are never cycled.
    #[test]
    fn transient_only_faces_are_exempt_from_the_list() {
        let mut c = IslandConfig {
            faces: vec!["clock".into(), "media".into()],
            restrict: true,
            default: "clock".into(),
            ..Default::default()
        };
        c.transient_only.insert("volume".into());
        c.interruptible_by.insert("volume".into());
        let mut a = Arbiter::new(c);
        for (f, p) in [("clock", 0), ("media", 1), ("volume", 2)] {
            a.register_face(face(f, p));
        }
        a.signal(0, osd("volume", 1000, true));
        let d = a.decide(0);
        assert_eq!(
            (d.face.as_str(), d.reason.as_str()),
            ("volume", "transient")
        );
        assert_eq!(d.faces, ["clock", "media", "volume"]);
        assert!(d.unlisted.is_empty());
        let seen: Vec<String> = (0..3).map(|_| a.next(2000).face).collect();
        assert!(!seen.iter().any(|f| f == "volume"), "{seen:?}");
    }

    /// K68: an empty list offers every face, whatever `restrict` says (a safe fallback).
    #[test]
    fn an_empty_list_offers_every_face() {
        let mut a = listed(&[]);
        a.signal(0, sig("weather", 90));
        let d = a.decide(0);
        assert_eq!(d.face, "weather");
        assert_eq!(d.faces, ["clock", "media", "weather"]);
        assert!(d.unlisted.is_empty());
    }

    /// The default list does not restrict: `faces` only orders, so every registered face shows, the listed ones first.
    #[test]
    fn a_list_that_does_not_restrict_only_orders() {
        let mut a = Arbiter::new(IslandConfig {
            faces: vec!["media".into()],
            default: "media".into(),
            ..Default::default()
        });
        for (f, p) in [("clock", 0), ("media", 1), ("weather", 2)] {
            a.register_face(face(f, p));
        }
        let d = a.decide(0);
        assert_eq!(d.faces, ["media", "clock", "weather"]);
        assert!(d.unlisted.is_empty());
        a.signal(0, sig("weather", 90));
        assert_eq!(
            a.decide(0).face,
            "weather",
            "an unlisted face still wins by relevance"
        );
    }

    /// The default face that the list does not offer falls back to the first face it offers. A live face the list
    /// leaves out is neither the secondary nor counted in the overflow.
    #[test]
    fn the_default_falls_back_and_hidden_activities_do_not_count() {
        let mut a = listed(&["media"]);
        let d = a.decide(0);
        assert_eq!((d.face.as_str(), d.reason.as_str()), ("media", "default"));
        a.signal(0, sig("media", 60));
        a.signal(0, sig("weather", 80));
        let d = a.decide(0);
        assert_eq!(
            (d.face.as_str(), d.secondary, d.overflow),
            ("media", None, 0)
        );
    }

    /// A pin or a manual hold that the list stops offering is dropped: the island never stays on a face it may not show,
    /// and a face the list gives back is not pinned again.
    #[test]
    fn a_pin_or_hold_drops_out_with_the_list() {
        let mut a = listed(&["clock", "media"]);
        a.pin("media");
        assert_eq!(a.decide(0).reason, Reason::Pinned);
        let mut c = a.cfg.clone();
        c.faces = vec!["clock".into()];
        a.set_config(c);
        let d = a.decide(0);
        assert_eq!((d.face.as_str(), d.reason.as_str()), ("clock", "default"));
        assert!(!a.pinned());

        let mut a = listed(&["clock", "media"]);
        assert_eq!(a.next(0).face, "media", "a manual hold on media");
        let mut c = a.cfg.clone();
        c.faces = vec!["clock".into()];
        a.set_config(c);
        let d = a.decide(1);
        assert_eq!((d.face.as_str(), d.reason.as_str()), ("clock", "default"));
        assert_eq!(a.next_deadline(), None, "the dropped hold has no expiry");
    }

    /// A hidden face arms no timer: its transient expires unseen, and the daemon need not wake for it (Ma).
    #[test]
    fn a_hidden_face_arms_no_timer() {
        let mut a = listed(&["clock"]);
        a.signal(0, osd("weather", 1000, false));
        assert_eq!(a.next_deadline(), None);
        assert_eq!(a.decide(0).face, "clock");
    }

    /// `registered` knows every face the island has, shown or not, so a mod cannot take a name it holds; the
    /// unlisted ones come in cycling order.
    #[test]
    fn registered_knows_the_unlisted_faces() {
        let mut a = listed(&["clock"]);
        assert!(a.registered("weather"));
        assert!(!a.registered("ghost"));
        assert_eq!(a.decide(0).unlisted, ["media", "weather"]);
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
