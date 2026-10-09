//! Island arbitration (K9): pinned > transient (TTL) > live relevance > default.
//!
//! Pure logic, no IO, no timers. Time is an input (`now`, ms on any monotone clock the daemon
//! picks) so tests are exact and the daemon arms one timer at `next_deadline()` (Ma: no ticking).
//! A user's manual cycling sits between pinned and the rest: relevance cannot override it for
//! `manual_hold_ms`; only a transient that is allowed to interrupt can.

use serde_json::{Value, json};
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

    pub fn clear(&mut self, face: &str) {
        self.rel.remove(face);
        self.transients.remove(face);
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
        let mk = |face: String, reason: Reason, until: Option<Ms>| Decision {
            face,
            reason,
            until,
            faces: faces.clone(),
        };

        if let Some(p) = &self.pinned {
            return mk(p.clone(), Reason::Pinned, None);
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
                return mk(f, Reason::Transient { until: u }, Some(u));
            }
            return mk(mf.clone(), Reason::Manual { until: *mu }, Some(*mu));
        }
        if let Some((f, u)) = best_transient(false) {
            return mk(f, Reason::Transient { until: u }, Some(u));
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
            return mk(f.clone(), Reason::Relevance { score: r.relevance }, None);
        }

        let d = if self.faces.contains_key(&self.cfg.default) {
            self.cfg.default.clone()
        } else {
            faces.first().cloned().unwrap_or_default()
        };
        mk(d, Reason::Default, None)
    }
}

/// The `runtime.island.<id>` document. `until` is additive (absent unless a timer is running).
pub fn doc(d: &Decision, pinned: bool) -> Value {
    let mut v = json!({
        "face": d.face,
        "faces": d.faces,
        "reason": d.reason.as_str(),
        "pinned": pinned,
    });
    if let Some(u) = d.until {
        v["until"] = json!(u);
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
            json!({"face":"osd","faces":["clock","media","osd"],"reason":"transient","pinned":false,"until":2000})
        );
        let d = arb().decide(0);
        assert!(doc(&d, false).get("until").is_none());
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
