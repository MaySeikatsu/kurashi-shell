//! The shell's material in ghostty (I174, W37; K49, K59, K61): a generated `custom-shader` (GLSL, Shadertoy style — the
//! rendered terminal is `iChannel0`) that lays a procedural relief close to the active kind over the terminal's own
//! background. Ghostty loads no textures of its own into a custom shader, so the relief is computed per pixel (value and
//! Voronoi noise, one recipe per kind) instead of sampling the daemon's tile; the light, its colour, the amplitude (the
//! shell's legibility cap included), gloss, ink and depth are the theme's tokens, baked in as constants. The shading is
//! `kurashi_texture::shade_with` without the beam and the relief shadows (DESIGN-SYSTEM "Texture and light").
//!
//! Readability first: only pixels of the baked background colour get the relief, and none within a few pixels of any
//! other pixel (40 taps of `iChannel0`), so text, the cursor, selections and coloured cells pass through untouched and
//! keep their contrast. The shader reads no time: with `custom-shader-animation = false` it runs only when the terminal
//! draws a frame (Ma). See docs/ux/terminal-texture.md.

use serde_json::{Map, Value};

use crate::color::Rgb;

/// Where the export writes the shader, under `$XDG_CONFIG_HOME`.
pub const PATH: &str = "ghostty/shaders/kurashi.glsl";

/// The template placeholder that becomes the theme file's shader lines (or nothing while the material is off).
pub const PLACEHOLDER: &str = "ghostty.shader";

/// The kinds with a procedural recipe here: every `theme.texture.kind` but `none` (kurashid's tests hold it to
/// `kurashi_texture::Kind::ALL`).
pub const KINDS: [&str; 13] = [
    "paper",
    "paper_dots",
    "paper_lines",
    "paper_grid",
    "fabric",
    "wool",
    "stone",
    "halftone",
    "metal",
    "leather",
    "wood",
    "paint",
    "brush",
];

/// Written in place of the shader while the material is off, when a shader file is there: a config that still names
/// it (a terminal not reloaded yet, a line copied into the user's own config) keeps loading and shows the terminal as
/// it is.
pub const PASS_THROUGH: &str = "// kurashi (W37): the shell's material is off, so this shader passes the terminal through unchanged.\n\
void mainImage(out vec4 fragColor, in vec2 fragCoord) {\n    fragColor = texture(iChannel0, fragCoord / iResolution.xy);\n}\n";

/// The theme file's lines for the shader at `path` (absolute, so it never depends on how ghostty resolves a relative
/// one). No animation: the shader is static (Ma).
pub fn lines(path: &str) -> String {
    format!("custom-shader = {path}\ncustom-shader-animation = false")
}

/// The tile parameters the tokens do not carry: `theme.texture.kind`, `wrinkles`, `cracks`, `crack_style` as resolved
/// (high contrast forces the kind off; CONTRACT-CHANGE row 400 asks for a `texture.kind` token).
#[derive(Clone, Debug, Default, PartialEq)]
pub struct Material {
    pub kind: String,
    pub wrinkles: f64,
    pub cracks: f64,
    pub crack_style: String,
}

/// Why there is no shader.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Off {
    /// No material: kind `none`, forced off (high contrast, reduce transparency) or its tile still generating.
    Material,
    /// The material is not on the shell's surfaces (scope `wallpaper`), or the `everything` overlay already lies over
    /// the terminal (a shader would shade it twice).
    Scope,
    /// A kind without a recipe here.
    Kind,
}

/// The shader for the theme in effect, or why there is none.
pub fn generate(tokens: &Map<String, Value>, m: &Material) -> Result<String, Off> {
    let num = |k: &str, d: f64| tokens.get(k).and_then(Value::as_f64).unwrap_or(d);
    let on = tokens
        .get("texture.map")
        .and_then(Value::as_str)
        .is_some_and(|s| !s.is_empty())
        && num("texture.amp", 0.0) > 0.0;
    if !on || m.kind.is_empty() || m.kind == "none" {
        return Err(Off::Material);
    }
    if tokens.get("texture.shell").and_then(Value::as_bool) != Some(true)
        || tokens.get("texture.overlay").and_then(Value::as_bool) == Some(true)
    {
        return Err(Off::Scope);
    }
    let kind = recipe(&m.kind).ok_or(Off::Kind)?;
    let colour = |k: &str, d: Rgb| {
        tokens
            .get(k)
            .and_then(Value::as_str)
            .and_then(Rgb::parse)
            .unwrap_or(d)
    };
    let bg = colour("color.surface", Rgb(0, 0, 0));
    let dir: Vec<f64> = tokens
        .get("light.dir")
        .and_then(Value::as_array)
        .map(|a| a.iter().filter_map(Value::as_f64).collect())
        .filter(|v: &Vec<f64>| v.len() == 3)
        .unwrap_or_else(|| vec![-0.54, -0.54, 0.64]);
    // The tile's device px per logical px is the largest output's scale (K59): the terminal's pixels are device pixels.
    let dev = match (
        num("texture.tile_px", 0.0),
        num("texture.tile_logical", 0.0),
    ) {
        (px, l) if px > 0.0 && l > 0.0 => px / l,
        _ => 1.0,
    };
    let scale = num("texture.scale", 1.0).max(0.1);
    let ink_alpha = num("texture.ink_alpha", 0.0);
    let glass = m.crack_style == "glass";
    let wrinkles = m.wrinkles.clamp(0.0, 1.0);
    let cracks = m.cracks.clamp(0.0, 1.0);

    let mut s = String::with_capacity(12 * 1024);
    s.push_str(&format!(
        "// kurashi — the shell's material in ghostty (K59, W37). Generated by kurashid from the theme in effect; the\n\
         // next theme change rewrites it, so edit a copy. Static: use it with `custom-shader-animation = false`.\n\
         // The relief touches only pixels of the terminal's background colour, never within a few pixels of text, the\n\
         // cursor or a selection.\n\
         // kind {kind} · wrinkles {wrinkles:.2} · cracks {cracks:.2} {style}\n\n",
        kind = m.kind,
        style = if glass { "glass" } else { "stone" },
    ));
    let v3 = |c: [f64; 3]| format!("vec3({}, {}, {})", f(c[0]), f(c[1]), f(c[2]));
    let rgb = |c: Rgb| [c.0, c.1, c.2].map(|v| f64::from(v) / 255.0);
    let lin = |c: [f64; 3]| {
        c.map(|v| {
            if v <= 0.04045 {
                v / 12.92
            } else {
                ((v + 0.055) / 1.055).powf(2.4)
            }
        })
    };
    let consts = [
        ("BG", v3(rgb(bg)), "the terminal's background (sRGB)"),
        (
            "BG_LIN",
            v3(lin(rgb(bg))),
            "the same, linear (ghostty's linear blending)",
        ),
        (
            "LIGHT_DIR",
            v3([dir[0], dir[1], dir[2]].map(|v| (v * 100.0).round() / 100.0)),
            "toward the light: x right, y down, z toward the viewer",
        ),
        (
            "LIGHT_COL",
            v3(rgb(colour("light.color", Rgb(255, 255, 255)))),
            "the highlights' colour",
        ),
        (
            "INK",
            v3(rgb(colour("texture.ink", Rgb(0, 0, 0)))),
            "the kind's ink (rulings, dots, pigment)",
        ),
    ];
    for (name, value, why) in consts {
        s.push_str(&format!("const vec3 {name} = {value}; // {why}\n"));
    }
    let scalars = [
        ("INK_A", ink_alpha, "the ink's opacity (0: tint off)"),
        (
            "AMP",
            num("texture.amp", 0.0),
            "the largest shade either way: strength under the legibility cap",
        ),
        ("GLOSS", num("texture.gloss", 0.0), "specular amount"),
        (
            "SHIN",
            num("texture.shininess", 8.0).max(1.0),
            "specular exponent",
        ),
        ("DEPTH", num("texture.depth", 1.0), "steepens the normals"),
        (
            "LIT",
            num("texture.lit", 1.0),
            "the light half's weight (less on dark grounds)",
        ),
        (
            "DEV",
            dev,
            "device px per logical px (the largest output's scale)",
        ),
        (
            "PX",
            dev * scale,
            "device px per sheet px (× texture.scale)",
        ),
        (
            "RELIEF",
            kind.relief,
            "the kind's relief: px of height per unit",
        ),
        ("WRINKLES", wrinkles, "folds and creases"),
        ("CRACKS", cracks, "the crack network"),
        (
            "GLASS",
            if glass { 1.0 } else { 0.0 },
            "1: glass shards, 0: stone cracks",
        ),
    ];
    for (name, value, why) in scalars {
        s.push_str(&format!("const float {name} = {}; // {why}\n", f(value)));
    }
    s.push_str(HELPERS);
    s.push_str(&kind.glsl);
    s.push_str(&format!(
        "\nfloat height(vec2 p) {{\n    float h = RELIEF * kindHeight(p);\n{}{}    return h;\n}}\n",
        if wrinkles > 0.0 {
            "    h += 2.0 * WRINKLES * creases(p);\n"
        } else {
            ""
        },
        if cracks > 0.0 {
            "    h -= 2.5 * CRACKS * crackAt(p);\n"
        } else {
            ""
        },
    ));
    s.push_str(MAIN);
    Ok(s)
}

/// A float as GLSL source: always with a decimal point, four places.
fn f(v: f64) -> String {
    let t = format!("{:.4}", if v.is_finite() { v } else { 0.0 });
    if t == "-0.0000" { "0.0000".into() } else { t }
}

/// One kind: its height (`kindHeight`, about −0.5…0.5, mean near 0 so the cavity does not shift the tone) and ink
/// coverage (`kindInk`, 0…1), and how many px of height one unit is.
struct Recipe {
    relief: f64,
    glsl: String,
}

fn recipe(kind: &str) -> Option<Recipe> {
    let r = |relief, glsl: &str| {
        Some(Recipe {
            relief,
            glsl: glsl.to_owned(),
        })
    };
    match kind {
        "paper" => r(
            0.45,
            "float kindHeight(vec2 p) { return paperStock(p, 1.3); }\n\
             float kindInk(vec2 p) { return fibres(p); }\n",
        ),
        "paper_dots" => r(
            0.35,
            "float ruling(vec2 p) { return 1.0 - smoothstep(0.7, 1.4, length(mod(p, 24.0) - 12.0)); }\n",
        )
        .map(ruled),
        "paper_lines" => r(
            0.35,
            "float ruling(vec2 p) {\n    float line = 1.0 - smoothstep(0.3, 0.9, abs(mod(p.y, 24.0) - 12.0));\n    \
             float margin = 1.0 - smoothstep(0.3, 0.9, abs(p.x - 72.0));\n    return max(line, margin);\n}\n",
        )
        .map(ruled),
        "paper_grid" => r(
            0.35,
            "float ruling(vec2 p) {\n    vec2 d = abs(mod(p, 24.0) - 12.0);\n    \
             return 1.0 - smoothstep(0.3, 0.9, min(d.x, d.y));\n}\n",
        )
        .map(ruled),
        "fabric" => r(
            0.9,
            "float kindHeight(vec2 p) {\n    vec2 c = floor(p / 4.0);\n    vec2 g = fract(p / 4.0);\n    \
             float over = mod(c.x + c.y, 2.0);\n    float warp = sin(PI * g.x) * (0.55 + 0.45 * sin(PI * g.y));\n    \
             float weft = sin(PI * g.y) * (0.55 + 0.45 * sin(PI * g.x));\n    \
             float slub = 0.35 * (vnoise(p * vec2(0.04, 0.5)) + vnoise(p * vec2(0.5, 0.04) + 7.0)) - 0.35;\n    \
             return 0.8 * mix(weft, warp, over) + slub - 0.3;\n}\n\
             float kindInk(vec2 p) { return vnoise(p * vec2(0.04, 0.5)); }\n",
        ),
        "wool" => r(
            1.1,
            "float kindHeight(vec2 p) {\n    vec2 g = p / vec2(7.0, 6.0);\n    float col = fract(g.x) - 0.5;\n    \
             float row = fract(g.y + abs(col) * 0.9);\n    \
             float loop = sin(PI * row) * (1.0 - 4.0 * col * col);\n    \
             return 0.7 * loop + 0.3 * fbm(p / 1.2, 2) - 0.5;\n}\n\
             float kindInk(vec2 p) { return 0.0; }\n",
        ),
        "stone" => r(
            1.4,
            "float kindHeight(vec2 p) {\n    float grain = fbm(p / 14.0, 4) + 0.35 * fbm(p / 2.0 + 3.0, 2);\n    \
             float pits = smoothstep(0.75, 0.9, vnoise(p / 2.5 + 11.0));\n    \
             float fine = pow(ridge(fbm(p / 18.0 + 5.0, 3)), 24.0);\n    \
             return 0.8 * grain - 0.35 * pits - 0.3 * fine - 0.5;\n}\n\
             float kindInk(vec2 p) { return smoothstep(0.7, 0.85, vnoise(p / 1.6 + 29.0)); }\n",
        ),
        "halftone" => r(
            0.35,
            "float halftoneDot(vec2 p) {\n    vec2 c = fract(rot(0.785) * p / 6.0) - 0.5;\n    \
             float r = 0.16 + 0.2 * vnoise(p / 60.0);\n    return 1.0 - smoothstep(r - 0.06, r + 0.06, length(c));\n}\n\
             float kindHeight(vec2 p) { return 0.6 * paperStock(p, 0.6) + 0.25 * halftoneDot(p) - 0.05; }\n\
             float kindInk(vec2 p) { return halftoneDot(p); }\n",
        ),
        "metal" => r(
            0.6,
            "float kindHeight(vec2 p) {\n    \
             float brushed = 0.6 * vnoise(p * vec2(0.02, 1.1)) + 0.4 * vnoise(p * vec2(0.05, 2.7) + 3.0);\n    \
             float scratch = pow(ridge(vnoise(rot(0.6) * p * vec2(0.01, 0.6) + 9.0)), 60.0)\n        \
             + pow(ridge(vnoise(rot(-1.1) * p * vec2(0.012, 0.7) + 21.0)), 60.0);\n    \
             return 0.8 * brushed - 0.6 * scratch - 0.4;\n}\n\
             float kindInk(vec2 p) { return 0.0; }\n",
        ),
        "leather" => r(
            1.3,
            "float kindHeight(vec2 p) {\n    vec2 warp = 0.6 * vec2(vnoise(p / 20.0), vnoise(p / 20.0 + 5.0));\n    \
             vec2 v = voronoi(p / 7.0 + warp);\n    float cell = smoothstep(0.0, 0.45, v.y - v.x);\n    \
             float pores = smoothstep(0.85, 0.95, vnoise(p / 1.5 + 41.0));\n    \
             float crease = pow(ridge(vnoise(p * vec2(0.02, 0.08))), 30.0);\n    \
             return 0.75 * cell - 0.2 * pores - 0.3 * crease - 0.45;\n}\n\
             float kindInk(vec2 p) { return 0.0; }\n",
        ),
        "wood" => r(
            0.9,
            "float lateWood(vec2 p) {\n    float t = fract(p.y / 11.0 + 2.5 * fbm(p * vec2(0.004, 0.02), 3));\n    \
             return smoothstep(0.6, 0.93, t) * (1.0 - smoothstep(0.93, 1.0, t));\n}\n\
             float kindHeight(vec2 p) {\n    float pores = smoothstep(0.8, 0.95, vnoise(p * vec2(0.07, 0.9) + 13.0));\n    \
             return 0.6 * lateWood(p) + 0.25 * vnoise(p * vec2(0.02, 0.5)) - 0.35 * pores - 0.3;\n}\n\
             float kindInk(vec2 p) { return lateWood(p); }\n",
        ),
        "paint" => r(
            1.5,
            "float kindHeight(vec2 p) { return strokes(p, 3.0, 25.0, 0.9, 14.0); }\n\
             float kindInk(vec2 p) { return vnoise(p / 30.0); }\n",
        ),
        "brush" => r(
            1.3,
            "float kindHeight(vec2 p) { return strokes(p, 0.6, 90.0, 1.3, 22.0); }\n\
             float kindInk(vec2 p) { return vnoise(p / 40.0 + 3.0); }\n",
        ),
        _ => None,
    }
}

/// The notebook kinds: the quiet stock with its rulings printed (ink) or, with the tint off, pressed in.
fn ruled(r: Recipe) -> Recipe {
    // Each ruled recipe holds only `ruling`; the stock and the emboss are shared.
    Recipe {
        glsl: format!(
            "{}float kindHeight(vec2 p) {{ return paperStock(p, 0.55) - (INK_A > 0.0 ? 0.0 : 0.6 * ruling(p)); }}\n\
             float kindInk(vec2 p) {{ return ruling(p); }}\n",
            r.glsl
        ),
        ..r
    }
}

/// Noise and shapes every recipe draws from: an integer hash (stable on every GPU, unlike `fract(sin(…))`), value noise,
/// fBm, Voronoi, the paper stock, the brush strokes, creases and cracks.
const HELPERS: &str = r#"
const float PI = 3.14159265;

uint hashU(vec2 p) {
    uvec2 v = uvec2(ivec2(floor(p)) + ivec2(65536));
    uint h = (v.x * 0x8da6b343u) ^ (v.y * 0xd8163841u);
    h ^= h >> 15u; h *= 0x2c1b3c6du; h ^= h >> 12u; h *= 0x297a2d39u; h ^= h >> 15u;
    return h;
}
float hash(vec2 p) { return float(hashU(p)) * (1.0 / 4294967295.0); }
vec2 hash2(vec2 p) { uint h = hashU(p); return vec2(float(h & 0xffffu), float(h >> 16u)) * (1.0 / 65535.0); }

float vnoise(vec2 x) {
    vec2 i = floor(x);
    vec2 g = x - i;
    vec2 u = g * g * (3.0 - 2.0 * g);
    float a = hash(i), b = hash(i + vec2(1.0, 0.0)), c = hash(i + vec2(0.0, 1.0)), d = hash(i + vec2(1.0, 1.0));
    return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}
float fbm(vec2 x, int octaves) {
    float sum = 0.0, amp = 0.5, norm = 0.0;
    for (int i = 0; i < octaves; i++) {
        sum += amp * vnoise(x);
        norm += amp;
        x = x * 2.03 + vec2(17.1, 9.7);
        amp *= 0.5;
    }
    return sum / norm;
}
// 1 on the noise's middle line: thin crests (fibres, scratches, creases).
float ridge(float n) { return 1.0 - abs(2.0 * n - 1.0); }
mat2 rot(float a) { float c = cos(a), s = sin(a); return mat2(c, -s, s, c); }
// x: distance to the nearest site, y: to the second nearest (in cells).
vec2 voronoi(vec2 x) {
    vec2 i = floor(x), g = x - i;
    float d1 = 8.0, d2 = 8.0;
    for (int y = -1; y <= 1; y++) {
        for (int k = -1; k <= 1; k++) {
            vec2 c = vec2(float(k), float(y));
            float d = length(c + hash2(i + c) - g);
            if (d < d1) { d2 = d1; d1 = d; } else if (d < d2) { d2 = d; }
        }
    }
    return vec2(d1, d2);
}
// Long thin fibres, nearly straight, in two directions.
float fibres(vec2 p) {
    float a = pow(ridge(vnoise(rot(0.5) * p * vec2(0.08, 0.9))), 8.0);
    float b = pow(ridge(vnoise(rot(-0.7) * p * vec2(0.07, 0.8) + 31.0)), 8.0);
    return 0.5 * (a + b);
}
// Felt, a slow formation cloud that thickens the fibres, the fibres, and pores.
float paperStock(vec2 p, float fibre) {
    float felt = fbm(p / 3.0, 2) - 0.5;
    float cloud = vnoise(p / 48.0);
    float pores = smoothstep(0.82, 0.95, vnoise(p / 1.7 + 63.0));
    return 0.35 * felt + 0.2 * (cloud - 0.5) + fibre * (0.6 + 0.6 * cloud) * fibres(p) - 0.3 * pores - 0.03 * fibre;
}
// Brush strokes: bristle grooves along a wandering direction, bands of paint with a ridge where a stroke ends.
float strokes(vec2 p, float wander, float along, float across, float band) {
    vec2 q = rot(wander * (vnoise(p / 160.0) - 0.5)) * p;
    float bristle = ridge(vnoise(q * vec2(1.0 / along, across)));
    float b = vnoise(q * vec2(1.0 / (3.0 * along), 1.0 / band));
    float edge = 1.0 - abs(b - 0.5) * 8.0;
    return 0.6 * bristle * bristle + 0.5 * smoothstep(0.45, 0.55, b) + 0.25 * max(edge, 0.0) - 0.55;
}
float creases(vec2 p) {
    return pow(ridge(fbm(p / 90.0, 3)), 10.0) + 0.6 * pow(ridge(fbm(rot(1.2) * p / 60.0 + 7.0, 2)), 12.0);
}
// 1 on a crack: Voronoi edges, jagged (stone: the cells warped by noise) or straight (glass).
float crackAt(vec2 p) {
    vec2 q = p / 46.0 + (1.0 - GLASS) * 0.25 * vec2(fbm(p / 9.0, 2), fbm(p / 9.0 + 3.7, 2));
    vec2 v = voronoi(q);
    return 1.0 - smoothstep(0.0, 1.2, (v.y - v.x) * 46.0);
}
"#;

/// The ground test, the readability margin and the shading.
const MAIN: &str = r#"
// 1 where `c` is the terminal's background (either encoding), 0 anywhere else.
float ground(vec4 c) {
    vec3 rgb = c.rgb / max(c.a, 1e-4);
    float d = min(distance(rgb, BG), distance(rgb, BG_LIN));
    return 1.0 - smoothstep(1.5 / 255.0, 4.0 / 255.0, d);
}

const vec2 DIRS[8] = vec2[8](vec2(1.0, 0.0), vec2(0.7071, 0.7071), vec2(0.0, 1.0), vec2(-0.7071, 0.7071),
                             vec2(-1.0, 0.0), vec2(-0.7071, -0.7071), vec2(0.0, -1.0), vec2(0.7071, -0.7071));

void mainImage(out vec4 fragColor, in vec2 fragCoord) {
    vec4 src = texture(iChannel0, fragCoord / iResolution.xy);
    // Readability: the relief only on the background, none within 3 px of anything else (text, cursor, selection,
    // coloured cells) and fading in over the next 3.5 px, so text keeps its contrast against what is round it.
    float clear = ground(src);
    for (int i = 0; i < 8 && clear > 0.0; i++) {
        vec2 d = DIRS[i] * DEV;
        clear *= ground(texture(iChannel0, (fragCoord + d) / iResolution.xy));
        clear *= ground(texture(iChannel0, (fragCoord + 2.0 * d) / iResolution.xy));
        clear *= ground(texture(iChannel0, (fragCoord + 3.0 * d) / iResolution.xy));
        clear *= mix(1.0, ground(texture(iChannel0, (fragCoord + 4.5 * d) / iResolution.xy)), 0.75);
        clear *= mix(1.0, ground(texture(iChannel0, (fragCoord + 6.5 * d) / iResolution.xy)), 0.4);
    }
    if (clear <= 0.0) {
        fragColor = src;
        return;
    }
    // The sheet from the terminal's top-left corner, y down, in sheet px.
    vec2 p = vec2(fragCoord.x, iResolution.y - fragCoord.y) / PX;
    float h0 = height(p);
    vec2 g = vec2(height(p + vec2(0.5, 0.0)) - h0, height(p + vec2(0.0, 0.5)) - h0) / 0.5;
    vec3 n0 = normalize(vec3(-g, 1.0));
    // kurashi_texture::shade_with, without the beam and the relief shadows.
    vec3 n = normalize(vec3(DEPTH * n0.xy, n0.z));
    float cav = clamp(2.0 * h0 / max(RELIEF, 1e-3), -1.0, 1.0);
    vec3 L = normalize(LIGHT_DIR);
    float diff = dot(n, L) - L.z;
    vec3 H = normalize(L + vec3(0.0, 0.0, 1.0));
    float spec = GLOSS * (pow(max(dot(n, H), 0.0), SHIN) - pow(max(H.z, 0.0), SHIN));
    float v = AMP * (2.0 * diff + 0.5 * cav + spec);
    if (v > 0.0) v *= LIT;
    v = clamp(v, -AMP, AMP);
    vec4 shade = v < 0.0 ? vec4(0.0, 0.0, 0.0, -v) : vec4(LIGHT_COL * v, v);
    float ia = INK_A * clamp(kindInk(p), 0.0, 1.0);
    vec4 o = shade + vec4(INK * ia, ia) * (1.0 - shade.a);
    vec3 col = o.rgb + BG * (1.0 - o.a);
    // The pixel came in linear: hand it back linear.
    vec3 rgb = src.rgb / max(src.a, 1e-4);
    if (distance(rgb, BG_LIN) < distance(rgb, BG)) {
        col = mix(col / 12.92, pow((col + 0.055) / 1.055, vec3(2.4)), step(0.04045, col));
    }
    fragColor = vec4(mix(src.rgb, col * src.a, clear), src.a);
}
"#;

#[cfg(test)]
mod tests {
    use super::*;
    use std::path::PathBuf;
    use std::process::Command;

    /// A theme document's tokens with the material on for the shell: kami's dark paper.
    fn tokens() -> Map<String, Value> {
        serde_json::json!({
            "color.surface": "#1d2230",
            "texture.map": "/cache/paper_dots-w000-c000-ink-s100-v9.png",
            "texture.tile_px": 480, "texture.tile_logical": 480.0, "texture.scale": 1.0,
            "texture.amp": 0.09, "texture.gloss": 0.0, "texture.shininess": 8.0,
            "texture.ink": "#9ab4e8", "texture.ink_alpha": 0.45, "texture.depth": 1.0, "texture.lit": 0.6,
            "texture.shell": true, "texture.overlay": false,
            "light.dir": [-0.5416752, -0.5416752, 0.6427876], "light.color": "#ffffff",
        })
        .as_object()
        .cloned()
        .unwrap()
    }

    fn material(kind: &str) -> Material {
        Material {
            kind: kind.into(),
            ..Material::default()
        }
    }

    /// Ghostty's Shadertoy prefix (src/renderer/shaders/shadertoy_prefix.glsl): a uniform block with the Shadertoy
    /// inputs, `iChannel0` the rendered terminal, and a `main` that calls `mainImage`. Ghostty compiles the result with
    /// glslang to SPIR-V for OpenGL (then spirv-cross), which `glslangValidator -G` repeats.
    const PREFIX: &str = "#version 430 core\n\
        layout(binding = 1, std140) uniform Globals {\n    uniform vec3 iResolution;\n    uniform float iTime;\n    \
        uniform float iTimeDelta;\n    uniform float iFrameRate;\n    uniform int iFrame;\n    \
        uniform float iChannelTime[4];\n    uniform vec3 iChannelResolution[4];\n    uniform vec4 iMouse;\n    \
        uniform vec4 iDate;\n    uniform float iSampleRate;\n};\n\
        layout(binding = 0) uniform sampler2D iChannel0;\n\
        void mainImage(out vec4 fragColor, in vec2 fragCoord);\n\
        layout(location = 0) out vec4 _fragColor;\n\
        void main() { mainImage(_fragColor, gl_FragCoord.xy); }\n";

    /// `glslangValidator`, from PATH or `KURASHI_GLSLANG`; `None` (the compile tests skip) without it, unless
    /// `KURASHI_REQUIRE_GLSLANG=1` (tools/test-ghostty.sh) makes its absence a failure.
    fn glslang() -> Option<PathBuf> {
        let exe = std::env::var_os("KURASHI_GLSLANG")
            .map(PathBuf::from)
            .unwrap_or_else(|| PathBuf::from("glslangValidator"));
        if Command::new(&exe)
            .arg("--version")
            .output()
            .is_ok_and(|o| o.status.success())
        {
            return Some(exe);
        }
        assert!(
            std::env::var("KURASHI_REQUIRE_GLSLANG").as_deref() != Ok("1"),
            "glslangValidator is required (KURASHI_REQUIRE_GLSLANG=1) but not found"
        );
        eprintln!("skipped: glslangValidator is not on PATH here");
        None
    }

    fn compile(exe: &PathBuf, what: &str, body: &str) {
        static N: std::sync::atomic::AtomicU32 = std::sync::atomic::AtomicU32::new(0);
        let n = N.fetch_add(1, std::sync::atomic::Ordering::Relaxed);
        let dir = std::env::temp_dir().join(format!("kurashi-w37-glsl-{}-{n}", std::process::id()));
        std::fs::create_dir_all(&dir).unwrap();
        let file = dir.join("kurashi.frag");
        std::fs::write(&file, format!("{PREFIX}{body}")).unwrap();
        let out = Command::new(exe)
            .args(["-G", "-S", "frag", "-o"])
            .arg(dir.join("out.spv"))
            .arg(&file)
            .output()
            .expect("glslangValidator runs");
        let _ = std::fs::remove_dir_all(&dir);
        assert!(
            out.status.success(),
            "{what} does not compile:\n{}{}",
            String::from_utf8_lossy(&out.stdout),
            String::from_utf8_lossy(&out.stderr)
        );
    }

    #[test]
    fn every_kind_compiles_and_is_filled() {
        let exe = glslang();
        for kind in KINDS {
            for (wrinkles, cracks, style) in [(0.0, 0.0, "stone"), (0.6, 0.5, "glass")] {
                let m = Material {
                    kind: kind.into(),
                    wrinkles,
                    cracks,
                    crack_style: style.into(),
                };
                let glsl = generate(&tokens(), &m).unwrap_or_else(|e| panic!("{kind}: {e:?}"));
                assert!(!glsl.contains("{{"), "{kind}: an unfilled placeholder");
                assert!(!glsl.contains("NaN") && !glsl.contains("inf"), "{kind}");
                assert!(glsl.contains("void mainImage("), "{kind}");
                assert!(
                    !glsl.contains("iTime"),
                    "{kind}: the shader reads no time (it is static)"
                );
                if let Some(exe) = &exe {
                    compile(exe, &format!("{kind} w{wrinkles} c{cracks}"), &glsl);
                }
            }
        }
        if let Some(exe) = &exe {
            compile(exe, "the pass-through stub", PASS_THROUGH);
        }
    }

    /// One generated shader, byte for byte (`KURASHI_BLESS=1` writes it again after an intended change).
    #[test]
    fn golden_paper_dots() {
        let glsl = generate(
            &tokens(),
            &Material {
                kind: "paper_dots".into(),
                wrinkles: 0.2,
                cracks: 0.0,
                crack_style: "stone".into(),
            },
        )
        .unwrap();
        let path = PathBuf::from(env!("CARGO_MANIFEST_DIR"))
            .join("src/ghostty_shader/golden-paper_dots.glsl");
        if std::env::var("KURASHI_BLESS").as_deref() == Ok("1") {
            std::fs::write(&path, &glsl).unwrap();
        }
        let want = std::fs::read_to_string(&path).expect("the golden exists (KURASHI_BLESS=1)");
        assert_eq!(
            glsl, want,
            "the generated shader changed: bless it if intended"
        );
    }

    #[test]
    fn no_shader_without_the_material_on_the_shell() {
        let mut t = tokens();
        assert_eq!(generate(&t, &material("none")), Err(Off::Material));
        assert_eq!(generate(&t, &material("velvet")), Err(Off::Kind));
        t.insert("texture.shell".into(), Value::Bool(false));
        assert_eq!(
            generate(&t, &material("paper")),
            Err(Off::Scope),
            "scope wallpaper"
        );
        t.insert("texture.shell".into(), Value::Bool(true));
        t.insert("texture.overlay".into(), Value::Bool(true));
        assert_eq!(
            generate(&t, &material("paper")),
            Err(Off::Scope),
            "the overlay already covers the terminal"
        );
        let mut t = tokens();
        t.insert("texture.map".into(), Value::String(String::new()));
        assert_eq!(
            generate(&t, &material("paper")),
            Err(Off::Material),
            "the tile is still generating, or forced off"
        );
    }

    #[test]
    fn constants_follow_the_tokens() {
        let mut t = tokens();
        t.insert("texture.tile_px".into(), serde_json::json!(960));
        t.insert("texture.scale".into(), serde_json::json!(1.5));
        let glsl = generate(&t, &material("stone")).unwrap();
        assert!(glsl.contains("const float DEV = 2.0000;"), "{glsl}");
        assert!(glsl.contains("const float PX = 3.0000;"), "{glsl}");
        assert!(glsl.contains("const vec3 LIGHT_DIR = vec3(-0.5400, -0.5400, 0.6400);"));
        assert!(glsl.contains("const float AMP = 0.0900;"));
        // #1d2230 as sRGB and as linear.
        assert!(
            glsl.contains("const vec3 BG = vec3(0.1137, 0.1333, 0.1882);"),
            "{glsl}"
        );
        assert!(
            glsl.contains("const vec3 BG_LIN = vec3(0.0123, 0.0160, 0.0296);"),
            "{glsl}"
        );
        assert!(!glsl.contains("creases(p);\n") && !glsl.contains("crackAt(p);\n"));
    }
}
