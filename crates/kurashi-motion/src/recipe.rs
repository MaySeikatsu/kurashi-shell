//! Recipes (W59.7, K83, brief `docs/ux/motion-engine.md` §5 "Custom forms" tier 1): a form written without code, in a
//! motion pack, as tracks over the surface's one progress.
//!
//! ```toml
//! [recipes.pop-tilt]
//! label = "Pop and tilt"       # plain text or an i18n key; default: the id
//! base = "fade"                # optional: a content form the tracks compose with (BASES)
//! pivot = "centre"             # centre · edge · origin: what scale, rotate and skew turn about
//! [[recipes.pop-tilt.track]]
//! prop = "scale"               # PROPS
//! keys = [[0, 0.6], [0.7, 1.06], [1, 1]]   # [p, value], p rising within 0…1
//! curve = "ease-out"           # optional, per segment between two keys (a preset, a written curve, a pack's name)
//! unit = "fraction"            # translate tracks only: fraction (of the surface's size) or px
//! ```
//!
//! **The rest rule** (what makes p = 1 the motion-off frame): every track ends at its prop's rest value — a track whose
//! last key is before p = 1 is held to `[1, rest]` from there, and a key at p = 1 with another value is an error. A close
//! runs the same tracks from 1 back to 0.
//!
//! A recipe with any problem is skipped, whole, with every reason ([`Diag`]: an i18n key `config.diag.recipe.*` and its
//! arguments), so Settings can say what to fix; a profile or a setting naming it falls back to the next form in line.

use std::collections::BTreeMap;
use std::path::PathBuf;

use serde_json::{Map, Value, json};

use crate::curve::{self, Curve, Spec};
use crate::forms::{self, SURFACES};
use crate::pack::{Pack, Registry};

pub const MAX_TRACKS: usize = 12;
pub const MAX_KEYS: usize = 16;

/// What a translate track's values count in.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Unit {
    /// Of the surface's own size along that axis (1 = its whole height for a surface from a top bar).
    Fraction,
    Px,
}

/// An animatable property: its range and its rest value (where the surface is when it is open and still).
pub struct Prop {
    pub name: &'static str,
    pub min: f64,
    pub max: f64,
    pub rest: f64,
    /// Translate tracks: the range in px (`unit = "px"`).
    pub px: Option<(f64, f64)>,
}

const fn p(name: &'static str, min: f64, max: f64, rest: f64) -> Prop {
    Prop {
        name,
        min,
        max,
        rest,
        px: None,
    }
}

/// Every prop a track may animate (card W59.7). `translate_along` moves along the axis the surface comes in on, positive
/// toward its edge (where it comes from); `translate_across` parallel to that edge, positive right (top/bottom edges) or
/// down (left/right). Rotations and skews in degrees, blur in px, clips as fractions: `clip_inset` cuts every side by
/// that much of the size (0.5 = nothing left), `clip_iris` is a circle round the pivot whose radius reaches the farthest
/// corner at 1, `clip_wipe` uncovers the surface from its edge (1 = all of it).
#[rustfmt::skip]
pub const PROPS: &[Prop] = &[
    p("opacity", 0.0, 1.0, 1.0),
    p("scale", 0.0, 3.0, 1.0),
    p("scale_x", 0.0, 3.0, 1.0),
    p("scale_y", 0.0, 3.0, 1.0),
    Prop { px: Some((-4000.0, 4000.0)), ..p("translate_along", -2.0, 2.0, 0.0) },
    Prop { px: Some((-4000.0, 4000.0)), ..p("translate_across", -2.0, 2.0, 0.0) },
    p("rotate_x", -180.0, 180.0, 0.0),
    p("rotate_y", -180.0, 180.0, 0.0),
    p("rotate_z", -180.0, 180.0, 0.0),
    p("skew_x", -60.0, 60.0, 0.0),
    p("skew_y", -60.0, 60.0, 0.0),
    p("blur", 0.0, 64.0, 0.0),
    p("clip_inset", 0.0, 0.5, 0.0),
    p("clip_iris", 0.0, 1.0, 1.0),
    p("clip_wipe", 0.0, 1.0, 1.0),
];

pub fn prop(name: &str) -> Option<&'static Prop> {
    PROPS.iter().find(|p| p.name == name)
}

/// The forms a recipe may build on: today's content forms, which `Recipe.qml` runs under its tracks. Shape forms are the
/// morph's and sheet forms draw their own layer, so neither composes with tracks yet.
pub const BASES: [&str; 7] = [
    "slide", "rubber", "zoom", "fade", "flip", "bleed", "stepped",
];
pub const PIVOTS: [&str; 3] = ["centre", "edge", "origin"];

/// Reduce motion's line (brief §11, card W59.7): a recipe that turns more than this, or scales outside `VESTIBULAR_SCALE`,
/// is flagged `vestibular` and never runs under reduce motion.
pub const VESTIBULAR_DEG: f64 = 30.0;
pub const VESTIBULAR_SCALE: (f64, f64) = (0.8, 1.2);

#[derive(Clone, Debug, PartialEq)]
pub struct Track {
    pub prop: &'static str,
    /// `[p, value]`, p non-decreasing, ending at `[1, rest]`.
    pub keys: Vec<[f64; 2]>,
    /// Each segment's easing; `None` = linear (the host's progress is already on the role's curve).
    pub curve: Option<Curve>,
    pub unit: Unit,
}

/// Why a recipe is skipped: an i18n key (`config.diag.recipe.*`) and the arguments its sentence names.
#[derive(Clone, Debug, PartialEq)]
pub struct Diag {
    pub key: &'static str,
    pub args: Map<String, Value>,
}

#[derive(Clone, Debug, PartialEq)]
pub struct Recipe {
    pub id: String,
    /// i18n key or plain text.
    pub label: String,
    /// The pack that defines it, and that pack's file (none for a built-in pack).
    pub pack: String,
    pub path: Option<PathBuf>,
    pub base: Option<String>,
    pub pivot: &'static str,
    pub tracks: Vec<Track>,
    /// Empty: the recipe is a form. Otherwise every reason it is skipped.
    pub diags: Vec<Diag>,
}

pub const DIAG_ID: &str = "config.diag.recipe.id";
pub const DIAG_DUPLICATE: &str = "config.diag.recipe.duplicate";
pub const DIAG_SHAPE: &str = "config.diag.recipe.shape";
pub const DIAG_KEY: &str = "config.diag.recipe.key";
pub const DIAG_VALUE: &str = "config.diag.recipe.value";
pub const DIAG_BASE: &str = "config.diag.recipe.base";
pub const DIAG_PIVOT: &str = "config.diag.recipe.pivot";
pub const DIAG_EMPTY: &str = "config.diag.recipe.empty";
pub const DIAG_TRACKS: &str = "config.diag.recipe.tracks";
pub const DIAG_TRACK_KEY: &str = "config.diag.recipe.track_key";
pub const DIAG_PROP: &str = "config.diag.recipe.prop";
pub const DIAG_PARAM: &str = "config.diag.recipe.param";
pub const DIAG_PROP_TWICE: &str = "config.diag.recipe.prop_twice";
pub const DIAG_NO_KEYS: &str = "config.diag.recipe.no_keys";
pub const DIAG_KEYS: &str = "config.diag.recipe.keys";
pub const DIAG_KEY_SHAPE: &str = "config.diag.recipe.key_shape";
pub const DIAG_P_RANGE: &str = "config.diag.recipe.p_range";
pub const DIAG_ORDER: &str = "config.diag.recipe.order";
pub const DIAG_RANGE: &str = "config.diag.recipe.range";
pub const DIAG_REST: &str = "config.diag.recipe.rest";
pub const DIAG_CURVE: &str = "config.diag.recipe.curve";
pub const DIAG_CURVE_NAME: &str = "config.diag.recipe.curve_name";
pub const DIAG_UNIT: &str = "config.diag.recipe.unit";

fn diag(key: &'static str, args: Value) -> Diag {
    Diag {
        key,
        args: match args {
            Value::Object(m) => m,
            _ => Map::new(),
        },
    }
}

/// A number as a person wrote it (0.5, not 0.5000000001; 3, not 3.0).
fn num(v: f64) -> Value {
    let r = (v * 1e4).round() / 1e4;
    if r.fract() == 0.0 && r.abs() < 1e15 {
        json!(r as i64)
    } else {
        json!(r)
    }
}

impl Recipe {
    pub fn ok(&self) -> bool {
        self.diags.is_empty()
    }

    /// Large turns or zooms (brief §11): reduce motion skips it. A base that is vestibular (flip) makes it so too.
    pub fn vestibular(&self) -> bool {
        let base = self
            .base
            .as_deref()
            .and_then(forms::form)
            .is_some_and(|m| m.vestibular());
        base || self.tracks.iter().any(|t| {
            t.keys.iter().any(|&[_, v]| match t.prop {
                "rotate_x" | "rotate_y" | "rotate_z" => v.abs() > VESTIBULAR_DEG,
                "scale" | "scale_x" | "scale_y" => v < VESTIBULAR_SCALE.0 || v > VESTIBULAR_SCALE.1,
                _ => false,
            })
        })
    }

    /// Whether it draws through a layer while it moves (a blur or a clip; or a base that does, bleed).
    pub fn layered(&self) -> bool {
        self.base.as_deref() == Some("bleed")
            || self
                .tracks
                .iter()
                .any(|t| t.prop == "blur" || t.prop.starts_with("clip_"))
    }

    pub fn flags(&self) -> Vec<&'static str> {
        if self.vestibular() {
            vec!["vestibular"]
        } else {
            vec![]
        }
    }

    /// Its `motion.recipe.<id>` token (W59 contract, row 660's additions): the tracks to run and, for Settings, where it
    /// comes from and what is wrong with it. A skipped recipe keeps its diagnostics and no tracks.
    pub fn token(&self) -> Value {
        let ok = self.ok();
        let tracks: Vec<Value> = if ok {
            self.tracks
                .iter()
                .map(|t| {
                    json!({
                        "prop": t.prop,
                        "keys": t.keys.iter().map(|[p, v]| json!([num(*p), num(*v)])).collect::<Vec<_>>(),
                        "curve": t.curve.as_ref().map_or(Value::Null, curve_token),
                        "unit": match t.unit { Unit::Fraction => "fraction", Unit::Px => "px" },
                    })
                })
                .collect()
        } else {
            vec![]
        };
        json!({
            "ok": ok,
            "label": self.label,
            "pack": self.pack,
            "path": self.path.as_ref().map(|p| p.to_string_lossy().into_owned()),
            "base": self.base.clone().unwrap_or_default(),
            "pivot": self.pivot,
            "tracks": tracks,
            "flags": if ok { self.flags() } else { vec![] },
            "layer": ok && self.layered(),
            "diags": self.diags.iter().map(|d| json!({"key": d.key, "args": d.args})).collect::<Vec<_>>(),
        })
    }

    /// Its entry in the `motion.forms` meta (a valid recipe only): a content form any surface may take, clamped past 1.
    pub fn meta(&self) -> Value {
        json!({
            "family": "shape",
            "surfaces": SURFACES,
            "retarget": "morph",
            "overshoot": false,
            "flags": self.flags(),
            "tier": if self.layered() { "layer" } else { "transform" },
            "available": true,
            "recipe": true,
        })
    }
}

/// A track's curve as the frontend's curves.js prepares it (the role curves' token shape, without a duration of its own
/// but a spring's response).
fn curve_token(c: &Curve) -> Value {
    match c {
        Curve::Cubic(_) | Curve::Linear => {
            json!({"kind": "cubic", "ms": 0, "points": c.cubic_points()})
        }
        Curve::Spring {
            response_ms,
            bounce,
        } => {
            json!({"kind": "spring", "ms": response_ms, "response": response_ms, "bounce": bounce})
        }
        Curve::SpringQ { spring, damping } => {
            json!({"kind": "spring_q", "ms": 0, "spring": spring, "damping": damping})
        }
        Curve::Steps(n) => json!({"kind": "steps", "ms": 0, "n": n}),
        Curve::None => json!({"kind": "cubic", "ms": 0, "points": [0, 1, 0, 1, 1, 1]}),
    }
}

/// Reads one recipe of `pack` (`raw` as the pack file has it). Named curves resolve from that pack first, then any.
pub fn parse(id: &str, raw: &Value, pack: &Pack, reg: &Registry) -> Recipe {
    let mut r = Recipe {
        id: id.to_owned(),
        label: id.to_owned(),
        pack: pack.id.clone(),
        path: pack.path.clone(),
        base: None,
        pivot: "centre",
        tracks: vec![],
        diags: vec![],
    };
    if !curve::is_ident(id) || forms::form(id).is_some() {
        r.diags.push(diag(DIAG_ID, json!({"id": id})));
    }
    let Some(table) = raw.as_object() else {
        r.diags.push(diag(DIAG_SHAPE, json!({"id": id})));
        return r;
    };
    let mut raw_tracks: &[Value] = &[];
    for (k, v) in table {
        match (k.as_str(), v) {
            ("label", Value::String(s)) if !s.trim().is_empty() => r.label = s.clone(),
            ("base", Value::String(s)) => {
                if BASES.contains(&s.as_str()) {
                    r.base = Some(s.clone());
                } else {
                    r.diags.push(diag(DIAG_BASE, json!({"base": s})));
                }
            }
            ("pivot", Value::String(s)) => match PIVOTS.iter().find(|p| **p == s.as_str()) {
                Some(p) => r.pivot = *p,
                None => r.diags.push(diag(DIAG_PIVOT, json!({"pivot": s}))),
            },
            ("track", Value::Array(a)) => raw_tracks = a,
            ("label" | "base" | "pivot" | "track", _) => {
                r.diags.push(diag(DIAG_VALUE, json!({"key": k})));
            }
            _ => r.diags.push(diag(DIAG_KEY, json!({"key": k}))),
        }
    }
    if raw_tracks.is_empty() {
        r.diags.push(diag(DIAG_EMPTY, json!({"id": id})));
    }
    if raw_tracks.len() > MAX_TRACKS {
        r.diags.push(diag(
            DIAG_TRACKS,
            json!({"n": raw_tracks.len(), "max": MAX_TRACKS}),
        ));
    }
    let mut seen: BTreeMap<&'static str, usize> = BTreeMap::new();
    for (i, t) in raw_tracks.iter().enumerate() {
        // Tracks count from 1 in what a person reads.
        let n = i + 1;
        // A prop animated twice is ambiguous: the first track counts, broken or not.
        if let Some(pr) = t.get("prop").and_then(Value::as_str).and_then(prop) {
            if let Some(first) = seen.get(pr.name) {
                r.diags.push(diag(
                    DIAG_PROP_TWICE,
                    json!({"track": n, "prop": pr.name, "first": first}),
                ));
                continue;
            }
            seen.insert(pr.name, n);
        }
        if let Some(track) = parse_track(n, t, pack, reg, &mut r.diags) {
            r.tracks.push(track);
        }
    }
    r
}

fn parse_track(
    n: usize,
    raw: &Value,
    pack: &Pack,
    reg: &Registry,
    diags: &mut Vec<Diag>,
) -> Option<Track> {
    let Some(t) = raw.as_object() else {
        diags.push(diag(DIAG_TRACK_KEY, json!({"track": n, "key": "track"})));
        return None;
    };
    for k in t.keys() {
        if !["prop", "keys", "curve", "unit"].contains(&k.as_str()) {
            diags.push(diag(DIAG_TRACK_KEY, json!({"track": n, "key": k})));
        }
    }
    let name = t.get("prop").and_then(Value::as_str).unwrap_or_default();
    let Some(pr) = prop(name) else {
        // `fold.crease` and the like: a sheet form's own params, which recipes cannot drive until a sheet base can be
        // composed (card W59.7, not built).
        let key = if name.contains('.') {
            DIAG_PARAM
        } else {
            DIAG_PROP
        };
        diags.push(diag(key, json!({"track": n, "prop": name})));
        return None;
    };
    let mut ok = true;
    let mut fail = |d: Diag| {
        diags.push(d);
        ok = false;
    };

    let unit = match t.get("unit") {
        None => Unit::Fraction,
        Some(Value::String(u)) if pr.px.is_some() && u == "fraction" => Unit::Fraction,
        Some(Value::String(u)) if pr.px.is_some() && u == "px" => Unit::Px,
        Some(u) => {
            fail(diag(
                DIAG_UNIT,
                json!({"track": n, "prop": pr.name, "unit": u.as_str().unwrap_or("?")}),
            ));
            Unit::Fraction
        }
    };
    let (min, max) = match unit {
        Unit::Px => pr.px.unwrap_or((pr.min, pr.max)),
        Unit::Fraction => (pr.min, pr.max),
    };

    let curve = match t.get("curve") {
        None => None,
        Some(Value::String(s)) => match curve::parse(s) {
            Ok(Spec::Named(name)) => {
                let c = reg.curve(&name, &[Some(pack)]);
                if c.is_none() {
                    fail(diag(
                        DIAG_CURVE_NAME,
                        json!({"track": n, "prop": pr.name, "curve": name}),
                    ));
                }
                c
            }
            Ok(spec) => spec.curve(),
            Err(e) => {
                fail(diag(
                    DIAG_CURVE,
                    json!({"track": n, "prop": pr.name, "curve": s, "error": e.key()}),
                ));
                None
            }
        },
        Some(_) => {
            fail(diag(
                DIAG_CURVE,
                json!({"track": n, "prop": pr.name, "curve": "?", "error": "error.config.curve.syntax"}),
            ));
            None
        }
    };

    let raw_keys = t.get("keys").and_then(Value::as_array);
    let raw_keys = match raw_keys {
        Some(k) if !k.is_empty() => k,
        _ => {
            fail(diag(DIAG_NO_KEYS, json!({"track": n, "prop": pr.name})));
            return None;
        }
    };
    if raw_keys.len() > MAX_KEYS {
        fail(diag(
            DIAG_KEYS,
            json!({"track": n, "prop": pr.name, "n": raw_keys.len(), "max": MAX_KEYS}),
        ));
    }
    let mut keys: Vec<[f64; 2]> = Vec::with_capacity(raw_keys.len() + 1);
    for (j, k) in raw_keys.iter().enumerate() {
        let kn = j + 1;
        let pair = k
            .as_array()
            .filter(|a| a.len() == 2)
            .and_then(|a| Some([a[0].as_f64()?, a[1].as_f64()?]))
            .filter(|[p, v]| p.is_finite() && v.is_finite());
        let Some([p, v]) = pair else {
            fail(diag(
                DIAG_KEY_SHAPE,
                json!({"track": n, "prop": pr.name, "key": kn}),
            ));
            continue;
        };
        if !(0.0..=1.0).contains(&p) {
            fail(diag(
                DIAG_P_RANGE,
                json!({"track": n, "prop": pr.name, "key": kn, "p": num(p)}),
            ));
        } else if keys.last().is_some_and(|[lp, _]| p < *lp) {
            fail(diag(
                DIAG_ORDER,
                json!({"track": n, "prop": pr.name, "key": kn, "p": num(p)}),
            ));
        }
        if !(min..=max).contains(&v) {
            fail(diag(
                DIAG_RANGE,
                json!({"track": n, "prop": pr.name, "key": kn, "value": num(v), "min": num(min), "max": num(max)}),
            ));
        }
        keys.push([p, v]);
    }
    // The rest rule: the track ends where the surface rests.
    match keys.last() {
        Some(&[p, v]) if p >= 1.0 => {
            if (v - pr.rest).abs() > 1e-9 {
                fail(diag(
                    DIAG_REST,
                    json!({"track": n, "prop": pr.name, "value": num(v), "rest": num(pr.rest)}),
                ));
            }
        }
        Some(_) => keys.push([1.0, pr.rest]),
        None => {}
    }
    ok.then_some(Track {
        prop: pr.name,
        keys,
        curve,
        unit,
    })
}

/// Every recipe the packs define, in pack order: the first definition of an id counts; a later one is skipped with
/// [`DIAG_DUPLICATE`] (returned beside, as it has no token of its own: `motion.recipe.<id>` is the first's).
pub fn collect(reg: &Registry) -> (Vec<Recipe>, Vec<Recipe>) {
    let mut out: Vec<Recipe> = vec![];
    let mut shadowed = vec![];
    for pack in &reg.packs {
        for (id, raw) in &pack.recipes {
            let mut r = parse(id, raw, pack, reg);
            if let Some(first) = out.iter().find(|x| x.id == *id) {
                r.diags
                    .push(diag(DIAG_DUPLICATE, json!({"id": id, "pack": first.pack})));
                shadowed.push(r);
            } else {
                out.push(r);
            }
        }
    }
    (out, shadowed)
}

/// A diagnostic as a log line (the theme's notes).
pub fn note(r: &Recipe, d: &Diag) -> String {
    format!(
        "motion: recipe {} ({}): {} {}",
        r.id,
        r.pack,
        d.key,
        Value::Object(d.args.clone())
    )
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::pack;

    /// The three worked examples of the brief (§5 "Recipes"), byte for byte: the docs cannot drift from what parses.
    pub const BRIEF_EXAMPLES: &str = include_str!("../tests/recipes-brief.toml");

    fn reg_of(src: &str) -> Registry {
        let (p, diags) = pack::parse(src, "mine", false).expect("pack parses");
        assert!(diags.is_empty(), "{diags:?}");
        let mut r = Registry::bundled().clone();
        r.packs.push(p);
        r
    }

    fn one(src: &str) -> Recipe {
        let reg = reg_of(src);
        let (mut all, _) = collect(&reg);
        assert_eq!(all.len(), 1, "{all:?}");
        all.remove(0)
    }

    fn keys(r: &Recipe) -> Vec<&'static str> {
        r.diags.iter().map(|d| d.key).collect()
    }

    #[test]
    fn the_brief_examples_parse_and_flag_as_the_brief_says() {
        let reg = reg_of(BRIEF_EXAMPLES);
        let (all, shadowed) = collect(&reg);
        assert!(shadowed.is_empty());
        let ids: Vec<_> = all.iter().map(|r| r.id.as_str()).collect();
        assert_eq!(ids, ["drop-squash", "pop-tilt", "slide-blur"]);
        for r in &all {
            assert!(r.ok(), "{}: {:?}", r.id, r.diags);
            assert_eq!(r.pack, "mine");
        }
        let get = |id: &str| all.iter().find(|r| r.id == id).unwrap();
        // pop-tilt starts at 0.6 of its size: a zoom reduce motion skips.
        assert!(get("pop-tilt").vestibular());
        assert_eq!(get("pop-tilt").token()["flags"], json!(["vestibular"]));
        // drop-squash stays within 0.8–1.2 and turns nothing: it may run under reduce motion's rules.
        assert!(!get("drop-squash").vestibular());
        assert_eq!(get("drop-squash").pivot, "edge");
        let along = &get("drop-squash").tracks[0];
        assert_eq!(along.prop, "translate_along");
        assert_eq!(along.unit, Unit::Px);
        // slide-blur builds on slide and blurs: a layer while it moves.
        let sb = get("slide-blur");
        assert_eq!(sb.base.as_deref(), Some("slide"));
        assert!(sb.layered() && !sb.vestibular());
        assert_eq!(sb.meta()["tier"], "layer");
        assert_eq!(get("pop-tilt").meta()["tier"], "transform");
    }

    #[test]
    fn a_track_ends_at_rest() {
        let r = one(
            "[recipes.a]\n[[recipes.a.track]]\nprop = \"opacity\"\nkeys = [[0, 0], [0.4, 1]]\n\
             [[recipes.a.track]]\nprop = \"clip_iris\"\nkeys = [[0, 0]]\n",
        );
        assert!(r.ok(), "{:?}", r.diags);
        // Held to the rest value from the last key: implicit [1, rest].
        assert_eq!(r.tracks[0].keys, vec![[0.0, 0.0], [0.4, 1.0], [1.0, 1.0]]);
        assert_eq!(r.tracks[1].keys, vec![[0.0, 0.0], [1.0, 1.0]]);
        assert_eq!(r.token()["tracks"][1]["keys"], json!([[0, 0], [1, 1]]));
        // A key at p = 1 elsewhere than at rest is refused (p = 1 must be the motion-off frame).
        let bad = one(
            "[recipes.a]\n[[recipes.a.track]]\nprop = \"scale\"\nkeys = [[0, 0.9], [1, 1.1]]\n",
        );
        assert_eq!(keys(&bad), [DIAG_REST]);
        assert_eq!(bad.diags[0].args["rest"], json!(1));
        assert_eq!(bad.diags[0].args["value"], json!(1.1));
    }

    #[test]
    fn every_diagnostic_says_where() {
        let r = one(r#"
[recipes.bad]
lable = "typo"
base = "fold"
pivot = "corner"
[[recipes.bad.track]]
prop = "wobble"
keys = [[0, 1]]
[[recipes.bad.track]]
prop = "fold.crease"
keys = [[0, 1]]
[[recipes.bad.track]]
prop = "opacity"
keys = [[0.5, 0], [0.2, 0.5], [1.5, 1]]
[[recipes.bad.track]]
prop = "scale"
keys = [[0, 4], "x"]
easing = "ease"
[[recipes.bad.track]]
prop = "rotate_z"
keys = []
[[recipes.bad.track]]
prop = "blur"
keys = [[0, 8]]
curve = "cubic-bezier(1.4, 0, 0, 1)"
unit = "px"
[[recipes.bad.track]]
prop = "translate_along"
keys = [[0, 1]]
curve = "no-such-curve"
[[recipes.bad.track]]
prop = "opacity"
keys = [[0, 0]]
"#);
        assert!(!r.ok());
        let k = keys(&r);
        for want in [
            DIAG_KEY,
            DIAG_BASE,
            DIAG_PIVOT,
            DIAG_PROP,
            DIAG_PARAM,
            DIAG_ORDER,
            DIAG_P_RANGE,
            DIAG_RANGE,
            DIAG_KEY_SHAPE,
            DIAG_TRACK_KEY,
            DIAG_NO_KEYS,
            DIAG_CURVE,
            DIAG_UNIT,
            DIAG_CURVE_NAME,
            DIAG_PROP_TWICE,
        ] {
            assert!(k.contains(&want), "{want} missing from {k:?}");
        }
        let range = r.diags.iter().find(|d| d.key == DIAG_RANGE).unwrap();
        assert_eq!(
            Value::Object(range.args.clone()),
            json!({"track": 4, "prop": "scale", "key": 1, "value": 4, "min": 0, "max": 3})
        );
        let curve = r.diags.iter().find(|d| d.key == DIAG_CURVE).unwrap();
        assert_eq!(curve.args["error"], "error.config.curve.x_range");
        let twice = r.diags.iter().find(|d| d.key == DIAG_PROP_TWICE).unwrap();
        assert_eq!(twice.args["first"], json!(3));
        // A skipped recipe publishes its reasons and nothing to run.
        let t = r.token();
        assert_eq!(t["ok"], false);
        assert_eq!(t["tracks"], json!([]));
        assert_eq!(t["diags"].as_array().unwrap().len(), r.diags.len());
    }

    #[test]
    fn limits_and_names() {
        let mut src = String::from("[recipes.many]\n");
        for prop in PROPS.iter().map(|p| p.name).take(13) {
            src += &format!("[[recipes.many.track]]\nprop = \"{prop}\"\nkeys = [[1, 0]]\n");
        }
        // 13 tracks (and each ends off rest: those are reported too, but the count is what this checks).
        assert!(keys(&one(&src)).contains(&DIAG_TRACKS));
        let keys17: Vec<String> = (0..17)
            .map(|i| format!("[{}, 1]", i as f64 / 16.0))
            .collect();
        let r = one(&format!(
            "[recipes.k]\n[[recipes.k.track]]\nprop = \"opacity\"\nkeys = [{}]\n",
            keys17.join(", ")
        ));
        assert_eq!(keys(&r), [DIAG_KEYS]);
        // A built-in form's id, or no identifier, cannot name a recipe.
        assert_eq!(
            keys(&one(
                "[recipes.fold]\n[[recipes.fold.track]]\nprop = \"opacity\"\nkeys = [[0, 0]]\n"
            )),
            [DIAG_ID]
        );
        assert!(keys(&one("[recipes.Big]\n")).contains(&DIAG_ID));
        assert_eq!(keys(&one("[recipes.e]\nlabel = \"E\"\n")), [DIAG_EMPTY]);
        // Equal p is a jump, allowed.
        assert!(
            one("[recipes.j]\n[[recipes.j.track]]\nprop = \"opacity\"\nkeys = [[0, 0], [0.5, 0], [0.5, 1]]\n").ok()
        );
    }

    #[test]
    fn curves_name_presets_springs_and_pack_curves() {
        let r = one(r#"
[curves]
my-ease = "cubic-bezier(0.3, 0, 0.2, 1)"
[recipes.c]
[[recipes.c.track]]
prop = "opacity"
keys = [[0, 0]]
curve = "my-ease"
[[recipes.c.track]]
prop = "scale"
keys = [[0, 0.9]]
curve = "spring(400ms, 0.4)"
[[recipes.c.track]]
prop = "translate_across"
keys = [[0, 0.1]]
curve = "steps(4)"
[[recipes.c.track]]
prop = "rotate_z"
keys = [[0, 5]]
curve = "ease-out"
"#);
        assert!(r.ok(), "{:?}", r.diags);
        let t = r.token();
        assert_eq!(t["tracks"][0]["curve"]["kind"], "cubic");
        assert_eq!(
            t["tracks"][0]["curve"]["points"],
            json!([0.3, 0.0, 0.2, 1.0, 1.0, 1.0])
        );
        assert_eq!(
            t["tracks"][1]["curve"],
            json!({"kind": "spring", "ms": 400.0, "response": 400.0, "bounce": 0.4})
        );
        assert_eq!(
            t["tracks"][2]["curve"],
            json!({"kind": "steps", "ms": 0, "n": 4})
        );
        assert_eq!(t["tracks"][3]["curve"]["kind"], "cubic");
        assert!(!r.vestibular(), "5° and 0.9 stay under the line");
    }

    #[test]
    fn vestibular_line() {
        let turn = |deg: i32| {
            one(&format!(
                "[recipes.t]\n[[recipes.t.track]]\nprop = \"rotate_y\"\nkeys = [[0, {deg}]]\n"
            ))
            .vestibular()
        };
        assert!(!turn(30));
        assert!(turn(31));
        assert!(turn(-45));
        let base_flip = one(
            "[recipes.f]\nbase = \"flip\"\n[[recipes.f.track]]\nprop = \"opacity\"\nkeys = [[0, 0]]\n",
        );
        assert!(
            base_flip.vestibular(),
            "flip is vestibular, and so is a recipe on it"
        );
    }

    #[test]
    fn the_first_definition_counts() {
        let mut reg = reg_of(
            "[recipes.x]\nlabel = \"First\"\n[[recipes.x.track]]\nprop = \"opacity\"\nkeys = [[0, 0]]\n",
        );
        let (p, _) = pack::parse(
            "[recipes.x]\nlabel = \"Second\"\n[[recipes.x.track]]\nprop = \"opacity\"\nkeys = [[0, 0]]\n",
            "other",
            false,
        )
        .unwrap();
        reg.packs.push(p);
        let (all, shadowed) = collect(&reg);
        assert_eq!(all.len(), 1);
        assert_eq!(all[0].label, "First");
        assert_eq!(shadowed.len(), 1);
        assert_eq!(shadowed[0].pack, "other");
        assert_eq!(shadowed[0].diags[0].key, DIAG_DUPLICATE);
        assert_eq!(shadowed[0].diags[0].args["pack"], "mine");
    }
}
