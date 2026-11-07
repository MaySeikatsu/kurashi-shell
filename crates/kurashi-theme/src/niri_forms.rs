//! The shell's forms on niri's windows (K91, `docs/ux/niri-motion.md`): each form as a `custom-shader` for niri's
//! `window-open` and `window-close`, run backwards from the frontend's mesh and fragment passes, because niri gives a
//! fragment stage only. One progress, as in the shell: p is 0 gone … 1 in place, so a close is the open's frames backwards.
//! A form has one file in `niri_forms/`; its parameters and the theme's colours arrive as constants, so a style's shader
//! is its own. GLSL ES 1.00 after niri's prelude: no `#extension`, no derivatives. Not a contract niri keeps ("custom
//! shaders do not have a backwards compatibility guarantee"): if one no longer compiles, niri warns and keeps its default.

use kurashi_motion::curve::Curve;
use serde_json::{Map, Value};

const COMMON: &str = include_str!("niri_forms/common.glsl");

/// The form's GLSL: `ks_form(uv, size, p, opening)`. `None`: a form with no file here, a user's recipe (`niri_recipe`).
fn source(form: &str) -> Option<&'static str> {
    Some(match form {
        "fade" => include_str!("niri_forms/fade.glsl"),
        "zoom" => include_str!("niri_forms/zoom.glsl"),
        // (rubber is slide on an overshooting curve, as in the shell)
        "slide" | "rubber" => include_str!("niri_forms/slide.glsl"),
        "flip" => include_str!("niri_forms/flip.glsl"),
        "stepped" => include_str!("niri_forms/stepped.glsl"),
        "expand" => include_str!("niri_forms/expand.glsl"),
        "grow" => include_str!("niri_forms/grow.glsl"),
        "liquid" => include_str!("niri_forms/liquid.glsl"),
        "iris" => include_str!("niri_forms/iris.glsl"),
        "stamp" => include_str!("niri_forms/stamp.glsl"),
        "outline" => include_str!("niri_forms/outline.glsl"),
        "bleed" => include_str!("niri_forms/bleed.glsl"),
        "pixelate" => include_str!("niri_forms/pixelate.glsl"),
        "glitch" => include_str!("niri_forms/glitch.glsl"),
        "dissolve" => include_str!("niri_forms/dissolve.glsl"),
        "crt" => include_str!("niri_forms/crt.glsl"),
        "fold" => include_str!("niri_forms/fold.glsl"),
        "roll" => include_str!("niri_forms/roll.glsl"),
        "book" => include_str!("niri_forms/book.glsl"),
        "genie" => include_str!("niri_forms/genie.glsl"),
        "noren" => include_str!("niri_forms/noren.glsl"),
        "fan" => include_str!("niri_forms/fan.glsl"),
        "crumple" => include_str!("niri_forms/crumple.glsl"),
        "drop" => include_str!("niri_forms/drop.glsl"),
        _ => return None,
    })
}

type Tokens = Map<String, Value>;

fn rgb(t: &Tokens, key: &str, fallback: [f64; 3]) -> [f64; 3] {
    let Some(h) = t.get(key).and_then(Value::as_str) else {
        return fallback;
    };
    let h = h.trim_start_matches('#');
    let ch = |i: usize| {
        h.get(i..i + 2)
            .and_then(|s| u8::from_str_radix(s, 16).ok())
            .map(|v| f64::from(v) / 255.0)
    };
    match (ch(0), ch(2), ch(4)) {
        (Some(r), Some(g), Some(b)) => [r, g, b],
        _ => fallback,
    }
}
fn mix(a: [f64; 3], b: [f64; 3], k: f64) -> [f64; 3] {
    [0, 1, 2].map(|i| a[i] + (b[i] - a[i]) * k)
}
fn lum(c: [f64; 3]) -> f64 {
    0.2126 * c[0] + 0.7152 * c[1] + 0.0722 * c[2]
}
/// A GLSL float: ES 1.00 refuses `1` where it wants `1.0`.
pub(crate) fn fl(x: f64) -> String {
    format!("{x:.5}")
}
fn vec3(c: [f64; 3]) -> String {
    format!("vec3({}, {}, {})", fl(c[0]), fl(c[1]), fl(c[2]))
}

/// The constants a form reads: the theme's colours as the frontend's forms take them (`SheetForm.qml`, `Crt.qml`,
/// `Dissolve.qml`), the light (K82) and the form's own parameters (`motion.form_params.<form>`).
fn constants(t: &Tokens, form: &str) -> String {
    let empty = Map::new();
    let params = t
        .get(&format!("motion.form_params.{form}"))
        .and_then(Value::as_object)
        .unwrap_or(&empty);
    let p = |k: &str, d: f64, lo: f64, hi: f64| {
        params
            .get(k)
            .and_then(Value::as_f64)
            .map_or(d, |v| v.clamp(lo, hi))
    };
    let word = |k: &str| params.get(k).and_then(Value::as_str).unwrap_or("");
    let fill = rgb(t, "color.surface", [0.1, 0.1, 0.12]);
    let ink = rgb(t, "color.on_surface", [0.9, 0.9, 0.85]);
    let accent = rgb(t, "color.accent", [0.8, 0.25, 0.3]);
    let back = fill.map(|c| c / 1.087);
    let ember = match word("edge") {
        "ember" => rgb(t, "color.tertiary", accent),
        "warning" => rgb(t, "color.warning", accent),
        "text" => ink,
        _ => accent,
    };
    let char_ink = if lum(ink) < lum(fill) {
        ink
    } else {
        fill.map(|c| c / 2.4)
    };
    let hot = if lum(ink) >= lum(fill) { ink } else { fill };
    let light = t
        .get("light.dir")
        .and_then(Value::as_array)
        .map(|a| a.iter().filter_map(Value::as_f64).collect::<Vec<_>>())
        .filter(|a| a.len() == 3)
        .map_or([0.0, 0.0, 1.0], |a| [a[0], a[1], a[2]]);
    let mut out = String::new();
    let mut c3 = |name: &str, v: [f64; 3]| {
        out.push_str(&format!("const vec3 ks_{name} = {};\n", vec3(v)));
    };
    c3("light", light);
    c3("fill", fill);
    c3("accent", accent);
    c3("back", back);
    c3("cover_tone", mix(back, accent, 0.16));
    c3("ember", ember);
    c3("char", char_ink);
    c3("beam", mix(hot, [1.0, 1.0, 1.0], 0.35));
    c3("outline", rgb(t, "color.outline", ink));
    let radius = t.get("radius.lg").and_then(Value::as_f64).unwrap_or(12.0);
    let axes = if params.get("axes").and_then(Value::as_f64) == Some(2.0) {
        2.0
    } else {
        1.0
    };
    let on = |b: bool| if b { 1.0 } else { 0.0 };
    for (name, v) in [
        ("shade", p("crease", 0.35, 0.0, 1.0) / 0.35),
        ("radius", radius),
        ("panels", p("panels", 0.0, 0.0, 5.0)),
        ("axes", axes),
        ("rad", p("radius", 18.0, 10.0, 28.0)),
        ("scroll", on(word("variant") == "scroll")),
        ("pad", on(word("spine") == "hinge")),
        ("bend", p("bend", 0.5, 0.0, 1.0)),
        ("strips", p("strips", 0.0, 0.0, 7.0)),
        ("ribs", p("ribs", 0.0, 0.0, 12.0)),
        ("glow", p("glow", 0.6, 0.0, 1.0)),
        ("scanlines", p("scanlines", 0.5, 0.0, 1.0)),
        ("depth", p("crumple", 0.8, 0.0, 1.0)),
        ("ring", p("ring", 3.0, 2.0, 4.0)),
        ("refraction", p("refraction", 0.6, 0.0, 1.0)),
        ("neck", p("neck", 0.5, 0.0, 1.0)),
        ("frames", p("frames", 7.0, 3.0, 12.0)),
    ] {
        out.push_str(&format!("const float ks_{name} = {};\n", fl(v)));
    }
    out
}

/// What niri's `curve` cannot say, in the shader on a linear clock: `steps(n)` exactly, several segments as a polyline.
fn easing(curve: Option<&Value>) -> Option<String> {
    let c = curve?;
    match c.get("kind").and_then(Value::as_str)? {
        "steps" => {
            let n = c.get("n").and_then(Value::as_f64)?.max(1.0);
            let n = fl(n);
            Some(format!(
                "float ks_curve(float t) {{ return t >= 1.0 ? 1.0 : floor(t * {n}) / {n}; }}\n"
            ))
        }
        "cubic" => {
            let pts: Vec<f64> = c
                .get("points")?
                .as_array()?
                .iter()
                .filter_map(Value::as_f64)
                .collect();
            if pts.len() <= 6 {
                return None;
            }
            let curve = Curve::Cubic(pts);
            const N: usize = 32;
            let at = |i: usize| i as f64 / N as f64;
            let mut s = String::from("float ks_curve(float t) {\n");
            for i in 0..N {
                let (a, b) = (at(i), at(i + 1));
                let (ya, yb) = (curve.sample(a)?, curve.sample(b)?);
                s.push_str(&format!(
                    "    if (t < {}) return mix({}, {}, (t - {}) / {});\n",
                    fl(b),
                    fl(ya),
                    fl(yb),
                    fl(a),
                    fl(b - a)
                ));
            }
            s.push_str("    return 1.0;\n}\n");
            Some(s)
        }
        _ => None,
    }
}

/// Whether the shader keeps the clock itself: niri then runs `curve "linear"` over the duration.
pub fn needs_linear(curve: Option<&Value>) -> bool {
    easing(curve).is_some()
}

/// The `custom-shader` text of `form` for one direction, under `curve` (the role's token). A form's file, or a user's recipe
/// generated from its tracks (K95). `None`: neither (a recipe that is skipped), so the window keeps niri's own animation on
/// the shell's curve.
pub fn shader(t: &Tokens, form: &str, opening: bool, curve: Option<&Value>) -> Option<String> {
    let recipe = source(form).is_none();
    let base = if recipe {
        crate::niri_recipe::base(t, form)?
    } else {
        form
    };
    let body = if recipe {
        crate::niri_recipe::source(t, form, source(base))?
    } else {
        source(form)?.to_owned()
    };
    let overshoots = kurashi_motion::forms::form(form).is_some_and(|m| m.overshoot);
    let ease = easing(curve);
    let progress = match (&ease, overshoots) {
        (Some(_), _) => "ks_curve(niri_clamped_progress)",
        (None, true) => "niri_progress",
        (None, false) => "niri_clamped_progress",
    };
    let (name, p, flag) = if opening {
        ("open", progress.to_owned(), "1.0")
    } else {
        ("close", format!("1.0 - {progress}"), "0.0")
    };
    let mut out = constants(t, base);
    if let Some(e) = ease {
        out.push_str(&e);
    }
    // (only what compiles: the comments live in the files)
    for line in COMMON.lines().chain(body.lines()) {
        if !line.trim_start().starts_with("//") {
            out.push_str(line);
            out.push('\n');
        }
    }
    out.push_str(&format!(
        "vec4 {name}_color(vec3 coords_geo, vec3 size_geo) {{\n    return ks_form(coords_geo.xy, size_geo.xy, {p}, {flag});\n}}\n"
    ));
    Some(out)
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    fn tokens() -> Tokens {
        json!({
            "color.surface": "#ece6da", "color.on_surface": "#2b2622", "color.accent": "#b34d2e",
            "color.outline": "#5a5048", "light.dir": [-0.5, -0.5, 0.7], "radius.lg": 14,
            "motion.form_params.fold": {"axes": 2, "crease": 0.7},
            "motion.form_params.roll": {"variant": "scroll"},
            "motion.form_params.dissolve": {"edge": "text"},
        })
        .as_object()
        .unwrap()
        .clone()
    }

    /// Every form the shell offers has a shader, but `none`, which is niri's `off`. (A new form must be added here.)
    #[test]
    fn every_form_has_a_shader() {
        for m in kurashi_motion::forms::FORMS {
            assert_eq!(source(m.id).is_some(), m.id != "none", "{}", m.id);
        }
        assert!(source("a-users-recipe").is_none());
    }

    /// The shader goes between `r"` and `"` in a KDL raw string: one double quote would break the whole config.
    #[test]
    fn nothing_breaks_the_raw_string() {
        let t = tokens();
        for m in kurashi_motion::forms::FORMS {
            for opening in [true, false] {
                if let Some(s) = shader(&t, m.id, opening, None) {
                    assert!(!s.contains('"'), "{} has a double quote", m.id);
                    assert!(!s.contains("niri_tex_prev"), "{}", m.id);
                }
            }
        }
    }

    #[test]
    fn the_form_runs_forwards_and_backwards_on_one_progress() {
        let t = tokens();
        let o = shader(&t, "fold", true, None).unwrap();
        let c = shader(&t, "fold", false, None).unwrap();
        assert!(o.contains("vec4 open_color") && o.contains("niri_clamped_progress, 1.0)"));
        assert!(c.contains("vec4 close_color") && c.contains("1.0 - niri_clamped_progress, 0.0)"));
        // an overshooting form reads the unclamped progress
        assert!(
            shader(&t, "slide", true, None)
                .unwrap()
                .contains(", niri_progress, 1.0)")
        );
    }

    #[test]
    fn the_params_and_colours_arrive_as_constants() {
        let t = tokens();
        let fold = shader(&t, "fold", true, None).unwrap();
        assert!(fold.contains("const float ks_axes = 2.00000;"), "{fold}");
        assert!(fold.contains("const float ks_shade = 2.00000;"), "{fold}");
        assert!(
            shader(&t, "roll", true, None)
                .unwrap()
                .contains("const float ks_scroll = 1.00000;")
        );
        // the edge's role: text, the ink
        let d = shader(&t, "dissolve", true, None).unwrap();
        assert!(
            d.contains("const vec3 ks_ember = vec3(0.16863, 0.14902, 0.13333);"),
            "{d}"
        );
        assert!(
            d.contains("const vec3 ks_accent = vec3(0.70196, 0.30196, 0.18039);"),
            "{d}"
        );
    }

    #[test]
    fn what_niri_has_no_curve_for_is_kept_in_the_shader() {
        let t = tokens();
        let steps = json!({"kind": "steps", "ms": 240, "n": 6});
        let s = shader(&t, "stepped", true, Some(&steps)).unwrap();
        assert!(needs_linear(Some(&steps)));
        assert!(s.contains("floor(t * 6.00000) / 6.00000"), "{s}");
        assert!(s.contains("ks_curve(niri_clamped_progress), 1.0)"), "{s}");
        let segs = json!({"kind": "cubic", "ms": 300, "points":
            [0.2, 0.4, 0.3, 0.5, 0.5, 0.6, 0.6, 0.7, 0.8, 0.9, 1.0, 1.0]});
        assert!(needs_linear(Some(&segs)));
        assert!(
            shader(&t, "fade", false, Some(&segs))
                .unwrap()
                .contains("1.0 - ks_curve(")
        );
        let one = json!({"kind": "cubic", "ms": 300, "points": [0.2, 0.4, 0.3, 0.5, 1.0, 1.0]});
        assert!(!needs_linear(Some(&one)));
        assert!(!needs_linear(Some(&json!({"kind": "spring", "ms": 300}))));
    }

    /// A token as the daemon publishes it (`Recipe::token`): every prop, every kind of curve, on a base when given.
    fn with_recipe(base: &str) -> Tokens {
        let mut t = tokens();
        let cubic = json!({"kind": "cubic", "ms": 0, "points": [0.2, 0, 0, 1, 1, 1]});
        let spring = json!({"kind": "spring", "ms": 300, "response": 300, "bounce": 0.3});
        let spring_q = json!({"kind": "spring_q", "ms": 0, "spring": 0.1, "damping": 0.3});
        let steps = json!({"kind": "steps", "ms": 0, "n": 4});
        let curves = [Value::Null, cubic, spring, spring_q, steps];
        let tracks: Vec<Value> = kurashi_motion::recipe::PROPS
            .iter()
            .enumerate()
            .map(|(i, p)| {
                let mid = (p.max + p.min) * 0.5 + p.rest * 0.1;
                json!({"prop": p.name, "keys": [[0, p.min], [0.5, mid], [1, p.rest]],
                       "curve": curves[i % curves.len()],
                       "unit": if p.px.is_some() && i % 2 == 0 { "px" } else { "fraction" }})
            })
            .collect();
        t.insert(
            "motion.recipe.mine".into(),
            json!({"ok": true, "base": base, "pivot": "edge", "tracks": tracks}),
        );
        t.insert(
            "motion.recipe.broken".into(),
            json!({"ok": false, "base": "", "pivot": "centre", "tracks": [], "diags": [{"key": "x"}]}),
        );
        t
    }

    /// I418: a recipe's tracks become functions of p, what no track moves stays at rest, and a skipped one has no shader.
    #[test]
    fn a_recipe_is_written_from_its_tracks() {
        let t = with_recipe("");
        let s = shader(&t, "mine", true, None).unwrap();
        assert!(s.contains("float ks_r_scale(float p) {\n"), "{s}");
        assert!(s.contains("float ks_e_scale(float x) {\n"), "{s}");
        assert!(s.contains("const float ks_pivot = 0.00000;"), "{s}");
        assert!(s.contains("vec4 open_color") && s.contains("niri_clamped_progress, 1.0)"));
        assert!(!s.contains('"'), "a double quote breaks the raw string");
        let c = shader(&t, "mine", false, None).unwrap();
        assert!(c.contains("1.0 - niri_clamped_progress, 0.0)"), "{c}");
        assert!(shader(&t, "broken", true, None).is_none());
        assert!(shader(&t, "nobody", true, None).is_none());

        let mut one = tokens();
        one.insert(
            "motion.recipe.fades".into(),
            json!({"ok": true, "base": "", "pivot": "centre", "tracks": [
                {"prop": "opacity", "keys": [[0, 0], [0.5, 1], [1, 1]], "curve": null, "unit": "fraction"}]}),
        );
        let s = shader(&one, "fades", true, None).unwrap();
        assert!(
            s.contains("float ks_r_scale(float p) { return 1.00000; }"),
            "{s}"
        );
        assert!(
            s.contains("float ks_r_blur(float p) { return 0.00000; }"),
            "{s}"
        );
        assert!(
            s.contains("if (p < 0.50000) return mix(0.00000, 1.00000, (p - 0.00000) / 0.50000);"),
            "{s}"
        );
        assert!(s.contains("const float ks_pivot = 0.50000;"), "{s}");
    }

    /// A base runs under the tracks with its own parameters, by its name in the shader.
    #[test]
    fn a_recipe_runs_over_its_base() {
        let s = shader(&with_recipe("slide"), "mine", true, None).unwrap();
        assert!(
            s.contains(
                "vec4 ks_base(vec2 uv, vec2 size, float p, float opening) {\n    float travel"
            ),
            "{s}"
        );
        assert_eq!(s.matches("vec4 ks_form(").count(), 1, "{s}");
    }

    /// Every shader through a GLSL ES 1.00 compiler, between what niri puts round it (its prelude and epilogue, kept in
    /// step by `frontend/test-niri-motion.sh`, which compiles them in niri itself). Skips where `glslangValidator` is not on
    /// the PATH: the dev shell has it.
    #[test]
    fn every_shader_compiles_as_es100() {
        const PRELUDE: &str = "#version 100\nprecision highp float;\nvarying vec2 niri_v_coords;\nuniform vec2 niri_size;\nuniform mat3 niri_input_to_geo;\nuniform vec2 niri_geo_size;\nuniform sampler2D niri_tex;\nuniform mat3 niri_geo_to_tex;\nuniform float niri_progress;\nuniform float niri_clamped_progress;\nuniform float niri_random_seed;\nuniform float niri_alpha;\nuniform float niri_scale;\n";
        if std::process::Command::new("glslangValidator")
            .arg("--version")
            .output()
            .is_err()
        {
            eprintln!("glslangValidator not on the PATH: skipped");
            return;
        }
        let dir = std::env::temp_dir().join(format!("kurashi-niri-forms-{}", std::process::id()));
        std::fs::create_dir_all(&dir).unwrap();
        let t = tokens();
        let steps = json!({"kind": "steps", "ms": 240, "n": 6});
        let compile = |t: &Tokens,
                       form: &str,
                       label: &str,
                       opening: bool,
                       curve: Option<&Value>| {
            let Some(s) = shader(t, form, opening, curve) else {
                return;
            };
            let name = if opening { "open" } else { "close" };
            let text = format!(
                "{PRELUDE}{s}\nvoid main() {{\n    vec3 g = niri_input_to_geo * vec3(niri_v_coords, 1.0);\n    gl_FragColor = {name}_color(g, vec3(niri_geo_size, 1.0)) * niri_alpha;\n}}\n"
            );
            let file = dir.join(format!("{label}-{name}.frag"));
            std::fs::write(&file, text).unwrap();
            let out = std::process::Command::new("glslangValidator")
                .arg(&file)
                .output()
                .unwrap();
            assert!(
                out.status.success(),
                "{label} {name}: {}",
                String::from_utf8_lossy(&out.stdout)
            );
        };
        for m in kurashi_motion::forms::FORMS {
            for (opening, curve) in [(true, None), (false, None), (true, Some(&steps))] {
                compile(&t, m.id, m.id, opening, curve);
            }
        }
        // I418: a recipe with every prop and every kind of curve, on no base and on each.
        for base in std::iter::once("").chain(kurashi_motion::recipe::BASES) {
            let t = with_recipe(base);
            let label = format!("recipe-{base}");
            compile(&t, "mine", &label, true, None);
            compile(&t, "mine", &label, false, Some(&steps));
        }
        std::fs::remove_dir_all(&dir).ok();
    }
}
