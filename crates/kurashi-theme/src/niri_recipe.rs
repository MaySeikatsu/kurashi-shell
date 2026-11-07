//! A user's recipe as a shader for niri's windows (I418, K95): a recipe is declarative, so its tracks become GLSL with no
//! port by hand. `niri_forms/recipe.glsl` is the frame's math (`recipe.js`, run backwards per pixel); this writes what it
//! reads: one function per prop over p, each track's curve as a function of its segment's x, and the pivot and units.

use kurashi_motion::Spring;
use kurashi_motion::curve::Curve;
use kurashi_motion::recipe::PROPS;
use serde_json::{Map, Value};

use crate::niri_forms::fl;

/// A track's curve in how many straight pieces.
const PIECES: usize = 24;

const RECIPE: &str = include_str!("niri_forms/recipe.glsl");

/// y at x of a spring's step response over its settling (`springAtFraction`).
fn spring_at(s: &Spring, x: f64) -> f64 {
    s.position(x * s.settle_ms(), 0.0)
}

/// K42's spring (`springQStep`), the steps it takes to settle at most 600, sampled at x of them.
fn spring_q(k: f64, c: f64) -> Vec<f64> {
    let (mut x, mut v) = (0.0_f64, 0.0_f64);
    let mut out = vec![0.0];
    for _ in 0..600 {
        v = v + k * (1.0 - x) - c * v;
        x += v * 0.016;
        out.push(x);
        if (1.0 - x).abs() < 1e-3 && v.abs() < 1e-2 {
            break;
        }
    }
    out
}

/// The track's curve as a GLSL function `name`, as `curves.js`'s `at` has it. `None`: linear, no function needed.
fn ease(name: &str, curve: Option<&Value>) -> Option<String> {
    let c = curve?;
    let num = |k: &str| c.get(k).and_then(Value::as_f64);
    let y: Box<dyn Fn(f64) -> f64> = match c.get("kind").and_then(Value::as_str)? {
        // A staircase taken at the start of each step: the jump, then the hold.
        "steps" => {
            let n = fl(num("n")?.max(1.0));
            return Some(format!(
                "float {name}(float x) {{ return min(1.0, ceil(x * {n} - 0.0001) / {n}); }}\n"
            ));
        }
        "cubic" => {
            let pts: Vec<f64> = c
                .get("points")?
                .as_array()?
                .iter()
                .filter_map(Value::as_f64)
                .collect();
            let curve = Curve::Cubic(pts);
            Box::new(move |x| curve.sample(x).unwrap_or(1.0))
        }
        "spring" => {
            let r = num("response").or_else(|| num("ms"))?;
            let s = Spring::from_response(r, num("bounce").unwrap_or(0.0));
            Box::new(move |x| spring_at(&s, x))
        }
        "spring_q" => {
            let steps = spring_q(num("spring")?, num("damping")?);
            Box::new(move |x| {
                let i = (x * (steps.len() - 1) as f64).round() as usize;
                steps[i.min(steps.len() - 1)]
            })
        }
        _ => return None,
    };
    let at = |i: usize| i as f64 / PIECES as f64;
    let mut s = format!("float {name}(float x) {{\n");
    for i in 0..PIECES {
        let (a, b) = (at(i), at(i + 1));
        s.push_str(&format!(
            "    if (x < {}) return mix({}, {}, (x - {}) / {});\n",
            fl(b),
            fl(y(a)),
            fl(y(b)),
            fl(a),
            fl(b - a)
        ));
    }
    s.push_str("    return 1.0;\n}\n");
    Some(s)
}

/// One prop over p: its keys' segments (held before the first and after the last), or its rest where no track moves it.
fn track(name: &str, keys: &[(f64, f64)], curve: Option<&Value>, rest: f64) -> String {
    let Some(&(_, last)) = keys.last() else {
        return format!("float ks_r_{name}(float p) {{ return {}; }}\n", fl(rest));
    };
    let ease_name = format!("ks_e_{name}");
    let e = ease(&ease_name, curve);
    let mut s = e.clone().unwrap_or_default();
    s.push_str(&format!("float ks_r_{name}(float p) {{\n"));
    s.push_str(&format!(
        "    if (p <= {}) return {};\n",
        fl(keys[0].0),
        fl(keys[0].1)
    ));
    for w in keys.windows(2) {
        let ((pa, va), (pb, vb)) = (w[0], w[1]);
        if pb - pa <= 1e-9 {
            continue;
        }
        let x = format!("(p - {}) / {}", fl(pa), fl(pb - pa));
        let x = if e.is_some() {
            format!("{ease_name}({x})")
        } else {
            x
        };
        s.push_str(&format!(
            "    if (p < {}) return mix({}, {}, {x});\n",
            fl(pb),
            fl(va),
            fl(vb)
        ));
    }
    s.push_str(&format!("    return {};\n}}\n", fl(last)));
    s
}

/// The recipe's base (a form's id, or none) as `motion.recipe.<id>` has it. `None`: not a valid recipe.
pub(crate) fn base<'a>(t: &'a Map<String, Value>, id: &str) -> Option<&'a str> {
    let r = t.get(&format!("motion.recipe.{id}"))?;
    if r.get("ok").and_then(Value::as_bool) != Some(true) {
        return None;
    }
    Some(r.get("base").and_then(Value::as_str).unwrap_or(""))
}

/// The recipe's GLSL, with `ks_form` as a form's file has it: `base_source` (a base form's file) as `ks_base` first, then
/// the tracks. `None`: not a valid recipe, so the window keeps niri's own animation on the curve.
pub(crate) fn source(
    t: &Map<String, Value>,
    id: &str,
    base_source: Option<&str>,
) -> Option<String> {
    let r = t.get(&format!("motion.recipe.{id}"))?;
    if r.get("ok").and_then(Value::as_bool) != Some(true) {
        return None;
    }
    let tracks = r.get("tracks")?.as_array()?;
    let mut out = String::new();
    match base_source {
        Some(b) => out.push_str(&b.replace("ks_form(", "ks_base(")),
        None => out.push_str(
            "vec4 ks_base(vec2 uv, vec2 size, float p, float opening) { return ks_tex(uv); }\n",
        ),
    }
    let px = |prop: &str| {
        tracks.iter().any(|tr| {
            tr.get("prop").and_then(Value::as_str) == Some(prop)
                && tr.get("unit").and_then(Value::as_str) == Some("px")
        })
    };
    let pivot = if r.get("pivot").and_then(Value::as_str) == Some("centre") {
        0.5
    } else {
        0.0
    };
    for (name, v) in [
        ("px_along", f64::from(u8::from(px("translate_along")))),
        ("px_across", f64::from(u8::from(px("translate_across")))),
        ("pivot", pivot),
    ] {
        out.push_str(&format!("const float ks_{name} = {};\n", fl(v)));
    }
    for prop in PROPS {
        let tr = tracks
            .iter()
            .find(|tr| tr.get("prop").and_then(Value::as_str) == Some(prop.name));
        let keys: Vec<(f64, f64)> = tr
            .and_then(|tr| tr.get("keys"))
            .and_then(Value::as_array)
            .map(|a| {
                a.iter()
                    .filter_map(|k| Some((k.get(0)?.as_f64()?, k.get(1)?.as_f64()?)))
                    .collect()
            })
            .unwrap_or_default();
        let curve = tr.and_then(|tr| tr.get("curve")).filter(|c| !c.is_null());
        out.push_str(&track(prop.name, &keys, curve, prop.rest));
    }
    out.push_str(RECIPE);
    Some(out)
}
