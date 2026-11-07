//! App theme export (VISION "app theme export", M2 "exporter", K49, W34): the final palette and the theme's tokens
//! rendered through templates into files other programs read — GTK, Qt, KDE, terminals, niri — and the desktop's
//! settings (gsettings), the one target that writes settings instead of a file. The template language is matugen's
//! colour subset (`{{colors.<role>.<mode>.<format>}}`), so the templates DMS and shellseikatsu ship for matugen, and a
//! user's own matugen templates, work unchanged. Matugen's Material role names map onto ours (`primary` = `accent`,
//! …); a name we cannot map is left in place and reported, never guessed silently (Shōjiki).
//!
//! Beyond colours (W34) a template names values of the theme in effect: see [`values`] and templates/README.md.
//!
//! Formats: `hex` (`#rrggbb`), `hex_stripped` (`rrggbb`), `rgb` (`rgb(r, g, b)`), `rgba` (`rgba(r, g, b, 1.0)`),
//! `red`/`green`/`blue` (0–255). Modes `default`, `dark` and `light` all give the current scheme: kurashi resolves one
//! scheme at a time.

use std::collections::{BTreeMap, BTreeSet};

use serde_json::Value;

use crate::color::{BLACK, Rgb, WHITE};
use crate::palette::Palette;

/// The ghostty target's second file: the shell's material as a custom shader (W37). Declared here so the export owns
/// it (lib.rs stays as it is).
#[path = "ghostty_shader.rs"]
pub mod ghostty_shader;

/// A matugen role name as one of ours, or a colour derived from ours.
pub fn role(p: &Palette, name: &str) -> Option<Rgb> {
    let g = |r: &str| p.roles.get(r).copied();
    let tone = |base: Rgb, amount: f64| {
        // Material "container" roles: the base pulled towards the surface.
        base.mix(
            g("surface").unwrap_or(if p.dark { BLACK } else { WHITE }),
            amount,
        )
    };
    Some(match name {
        "primary" | "source_color" | "surface_tint" => g("accent")?,
        "on_primary" => g("on_accent")?,
        "primary_container" | "primary_fixed" | "primary_fixed_dim" | "inverse_primary" => {
            g("accent_container")?
        }
        "on_primary_container" | "on_primary_fixed" | "on_primary_fixed_variant" => {
            g("on_accent_container")?
        }
        "secondary_container" | "secondary_fixed" | "secondary_fixed_dim" => {
            tone(g("secondary")?, 0.65)
        }
        "on_secondary_container" | "on_secondary_fixed" | "on_secondary_fixed_variant" => {
            g("on_surface")?
        }
        "tertiary_container" | "tertiary_fixed" | "tertiary_fixed_dim" => {
            tone(g("tertiary")?, 0.65)
        }
        "on_tertiary_container" | "on_tertiary_fixed" | "on_tertiary_fixed_variant" => {
            g("on_surface")?
        }
        "error_container" => tone(g("error")?, 0.65),
        "on_error_container" => g("on_surface")?,
        "background" | "surface_dim" => g("surface")?,
        "on_background" => g("on_surface")?,
        "surface_bright" => g("surface_container_highest")?,
        "surface_variant" => g("surface_container_highest")?,
        "inverse_surface" => g("on_surface")?,
        "inverse_on_surface" => g("surface")?,
        // A palette without status roles still gives the templates that name them a colour (KDE's positive/neutral).
        "success" => g("success").or_else(|| g("secondary"))?,
        "warning" => g("warning")
            .or_else(|| g("tertiary"))
            .or_else(|| g("accent"))?,
        other => g(other)?,
    })
}

fn format(c: Rgb, fmt: &str) -> Option<String> {
    let Rgb(r, g, b) = c;
    Some(match fmt {
        "hex" => c.hex(),
        "hex_stripped" => c.hex().trim_start_matches('#').to_owned(),
        "rgb" => format!("rgb({r}, {g}, {b})"),
        "rgba" => format!("rgba({r}, {g}, {b}, 1.0)"),
        "red" => r.to_string(),
        "green" => g.to_string(),
        "blue" => b.to_string(),
        _ => return None,
    })
}

/// `{{colors.<role>.<mode>.<format>}}` filled from the palette.
fn colour(p: &Palette, path: &str) -> Option<String> {
    let mut parts = path.split('.');
    let (name, mode, fmt) = (parts.next()?, parts.next()?, parts.next()?);
    if parts.next().is_some() || !matches!(mode, "default" | "dark" | "light") {
        return None;
    }
    format(role(p, name)?, fmt)
}

/// Every value a template names besides the palette's colours, by its dotted name (W34). Built once per export run
/// by [`values`]; a name missing from the map is reported as unknown, like a misspelt colour.
pub type Values = BTreeMap<String, String>;

/// Where the values come from: the theme document's tokens and scheme in effect, the config values the apps follow,
/// and the config home the lines point into.
pub struct Inputs<'a> {
    pub tokens: &'a serde_json::Map<String, Value>,
    /// `dark` or `light`: the scheme in effect (the theme document's `appearance.scheme_effective`).
    pub scheme: &'a str,
    /// `theme.icon_theme`; "" = leave each app's own choice (I183).
    pub icon_theme: &'a str,
    /// `theme.motion.speed`.
    pub motion_speed: f64,
    /// `$XDG_CONFIG_HOME`, absolute.
    pub config_dir: &'a str,
    /// `theme.window_frame`: the compositors draw a frame round every window.
    pub window_frame: bool,
    /// `theme.window_frame_color`: `accent`, `shell_outline` or a palette role (I423).
    pub window_frame_color: &'a str,
    /// `theme.inactive_opacity` while `theme.inactive_transparent` is on; `None` leaves each compositor's own.
    pub inactive_opacity: Option<f64>,
    /// `theme.window_animations`: the compositors take the shell's motion. Off: each keeps its own.
    pub animations: bool,
    /// `theme.window_titlebars`: the compositors that draw titlebars (sway; Hyprland with hyprbars) take the shell's.
    pub titlebars: bool,
    /// The palette, for the titlebar lines (they are written whole, so their colours are filled here).
    pub palette: &'a Palette,
}

/// The shell's values as templates name them. Typography, shape, motion and material are the tokens in effect (a
/// value the theme does not carry is absent and reported, never invented); the icon theme and the config home come
/// from the config and the paths. Shipped templates: templates/README.md.
pub fn values(i: &Inputs) -> Values {
    let num = |k: &str| i.tokens.get(k).and_then(Value::as_f64);
    let mut v = Values::new();
    if let Some(f) = i.tokens.get("font.family").and_then(Value::as_str) {
        v.insert("fonts.family".into(), f.into());
    }
    if let Some(px) = num("font.size.body") {
        v.insert("fonts.size".into(), pt(px));
    }
    // The shell has no monospace choice of its own (a CONTRACT-CHANGE row asks for one): the generic family, which
    // fontconfig maps to the installed one. The shipped templates do not set it, so a user's font stays.
    v.insert("fonts.mono".into(), "monospace".into());
    v.insert("icons.theme".into(), i.icon_theme.into());
    v.insert("scheme".into(), i.scheme.into());
    v.insert(
        "gsettings.color_scheme".into(),
        if i.scheme == "light" {
            "default"
        } else {
            "prefer-dark"
        }
        .into(),
    );
    if let Some(r) = num("radius.lg") {
        v.insert("shape.radius".into(), whole(r));
    }
    // The shell's outline width; flat chrome draws none, and a 0 px focus ring would hide the focused window, so 2.
    if let Some(o) = num("chrome.outline") {
        let w = whole(if o > 0.0 { o } else { 2.0 });
        v.extend(frame_lines(i.window_frame, &w));
        v.insert("shape.border".into(), w);
    }
    let frame = frame_colour(i);
    for fmt in ["hex", "hex_stripped"] {
        if let Some(c) = format(frame, fmt) {
            v.insert(format!("frame.active.{fmt}"), c);
        }
    }
    v.extend(opacity_lines(i.inactive_opacity));
    if let Some(ms) = num("motion.standard_ms") {
        v.insert("motion.ms".into(), whole(ms));
    }
    if let Some(c) = i
        .tokens
        .get("motion.easing.continuous")
        .and_then(Value::as_array)
    {
        let c: Vec<f64> = c.iter().filter_map(Value::as_f64).collect();
        if let [a, b, cc, d] = c[..] {
            v.insert(
                "motion.curve".into(),
                format!(
                    "cubic-bezier({}, {}, {}, {})",
                    num_text(a),
                    num_text(b),
                    num_text(cc),
                    num_text(d)
                ),
            );
        }
    }
    if let Some(a) = num("color.surface_alpha") {
        v.insert("material.opacity".into(), format!("{a:.2}"));
    }
    if let Some(profile) = niri_family(i.tokens) {
        // K83 (W59.9): `theme.motion.windows = follow` gives the windows the profile's own curves and springs; off (the
        // default) keeps the family's springs as before; no motion is `off` either way.
        // K91: `forms` also gives them the forms the surfaces move in, as niri's custom shaders.
        let windows = i.tokens.get("motion.windows").and_then(Value::as_str);
        let niri_block = match (profile, windows) {
            ("none", _) => niri_animations(profile, i.motion_speed),
            (_, Some("follow")) => niri_follow(i.tokens, profile, i.motion_speed, false),
            (_, Some("forms")) => niri_follow(i.tokens, profile, i.motion_speed, true),
            _ => niri_animations(profile, i.motion_speed),
        };
        // K49 amendment 2: Hyprland and MangoWM on the continuous curve and the standard duration; every block empty
        // with `theme.window_animations` off (each compositor keeps its own).
        let curve = v.get("motion.curve").and_then(|c| {
            c.strip_prefix("cubic-bezier(")?
                .strip_suffix(')')
                .map(|c| c.replace(' ', ""))
        });
        let ms = num("motion.standard_ms");
        let anim = |s: Option<String>| (!i.animations).then(String::new).or(s);
        let hypr = match (profile, &curve, ms) {
            ("none", ..) => Some("animations {\n    enabled = false\n}".to_owned()),
            (_, Some(c), Some(ms)) => Some(hyprland_animations(c, ms)),
            _ => None,
        };
        let mango = match (profile, &curve, ms) {
            ("none", ..) => Some("animations=0".to_owned()),
            (_, Some(c), Some(ms)) => Some(mango_animations(c, ms)),
            _ => None,
        };
        for (k, s) in [
            ("motion.niri", Some(niri_block)),
            ("motion.hyprland", hypr),
            ("motion.mango", mango),
        ] {
            if let Some(s) = anim(s) {
                v.insert(k.into(), s);
            }
        }
    }
    if let (Some(f), Some(size), Some(w)) = (
        v.get("fonts.family").cloned(),
        v.get("fonts.size").cloned(),
        v.get("shape.border").cloned(),
    ) {
        let (sway, hypr) = if i.titlebars {
            (
                format!(
                    "default_border normal {w}\ndefault_floating_border normal {w}\nfont pango:{f} {size}\n\
                     title_align center"
                ),
                hyprbars(i.palette, &f, &size),
            )
        } else {
            (String::new(), String::new())
        };
        v.insert("titlebar.sway".into(), sway);
        v.insert("titlebar.hyprland".into(), hypr);
    }
    v.insert("paths.config".into(), i.config_dir.into());
    v
}

/// Hyprland's `animations {}` on the shell's continuous curve and standard duration (its speed is in 100 ms steps).
fn hyprland_animations(curve: &str, ms: f64) -> String {
    let sp = format!("{:.1}", (ms / 100.0).max(0.1));
    let c = curve.replace(',', ", ");
    format!(
        "animations {{\n    enabled = true\n    bezier = kurashi, {c}\n    animation = windows, 1, {sp}, kurashi, popin 90%\n    \
         animation = fade, 1, {sp}, kurashi\n    animation = workspaces, 1, {sp}, kurashi, slide\n    \
         animation = layers, 1, {sp}, kurashi, fade\n}}"
    )
}

/// MangoWM's animation keys on the shell's continuous curve and standard duration.
fn mango_animations(curve: &str, ms: f64) -> String {
    let ms = whole(ms);
    let mut out = String::from(
        "animations=1\nanimation_type_open=zoom\nanimation_type_close=zoom\nanimation_fade_in=1\nanimation_fade_out=1",
    );
    // (one string: the icon-name scan reads quoted words as Material Symbols names)
    for k in "open close move tag".split(' ') {
        out.push_str(&format!(
            "\nanimation_duration_{k}={ms}\nanimation_curve_{k}={curve}"
        ));
    }
    out
}

/// Hyprland's titlebars in the shell's colours and font: the hyprbars plugin's block (Hyprland draws none itself).
fn hyprbars(p: &Palette, family: &str, size: &str) -> String {
    let c = |r: &str| {
        role(p, r).map_or_else(String::new, |c| c.hex().trim_start_matches('#').to_owned())
    };
    let pt = size.parse::<f64>().map_or(10, |s| s.round() as i64);
    format!(
        "plugin {{\n    hyprbars {{\n        bar_height = {h}\n        bar_color = rgb({bg})\n        col.text = rgb({fg})\n        \
         bar_text_font = {family}\n        bar_text_size = {pt}\n        bar_part_of_window = true\n        \
         bar_precedence_over_border = true\n        \
         hyprbars-button = rgb({close}), 14, ×, hyprctl dispatch killactive\n        \
         hyprbars-button = rgb({max}), 14, □, hyprctl dispatch fullscreen 1\n    }}\n}}",
        h = pt * 2 + 8,
        bg = c("surface_container"),
        fg = c("on_surface"),
        close = c("error"),
        max = c("tertiary"),
    )
}

/// The colour round the focused window (`theme.window_frame_color`, I423). `shell_outline` is the shell's frame outline as
/// `Theme.frameOutlineColor` has it, opaque: the text's ink, the accent, or the chrome's outline (flat chrome: the role).
fn frame_colour(i: &Inputs) -> Rgb {
    let p = i.palette;
    let accent = role(p, "primary").unwrap_or(Rgb(128, 128, 128));
    let by_role = |name: &str| role(p, name).unwrap_or(accent);
    match i.window_frame_color {
        "shell_outline" => match i.tokens.get("outline.ink").and_then(Value::as_str) {
            Some("text") => by_role("on_surface"),
            Some("accent") => accent,
            _ => {
                let drawn = i.tokens.get("chrome.outline").and_then(Value::as_f64) > Some(0.0);
                i.tokens
                    .get("chrome.outline_color")
                    .and_then(Value::as_str)
                    .filter(|_| drawn)
                    .and_then(Rgb::parse)
                    .unwrap_or_else(|| by_role("outline"))
            }
        },
        "secondary" => by_role("secondary"),
        "tertiary" => by_role("tertiary"),
        "outline" => by_role("outline"),
        "on_surface" => by_role("on_surface"),
        _ => accent,
    }
}

/// The compositors' frame lines (`theme.window_frame`): on → each draws its frame at `width`, niri its border in place
/// of the focus ring; off → empty, so each keeps its own setting and only takes the colours.
fn frame_lines(on: bool, width: &str) -> Values {
    let pick = |s: String| if on { s } else { String::new() };
    Values::from([
        ("frame.niri.ring".into(), pick("off".into())),
        ("frame.niri.border".into(), pick("on".into())),
        (
            "frame.hyprland".into(),
            pick(format!("border_size = {width}")),
        ),
        ("frame.mango".into(), pick(format!("border_px={width}"))),
        (
            "frame.sway".into(),
            pick(format!(
                "default_border pixel {width}\ndefault_floating_border pixel {width}"
            )),
        ),
    ])
}

/// The compositors' lines for see-through unfocused windows (`theme.inactive_opacity`); none → empty. sway has no
/// such setting.
fn opacity_lines(opacity: Option<f64>) -> Values {
    let o = opacity.map(|o| format!("{:.2}", o.clamp(0.0, 1.0)));
    let pick = |f: &dyn Fn(&str) -> String| o.as_deref().map(f).unwrap_or_default();
    Values::from([
        (
            "opacity.niri".into(),
            pick(&|o| format!("window-rule {{\n    match is-focused=false\n    opacity {o}\n}}")),
        ),
        (
            "opacity.hyprland".into(),
            pick(&|o| format!("inactive_opacity = {o}")),
        ),
        (
            "opacity.mango".into(),
            pick(&|o| format!("unfocused_opacity={o}")),
        ),
    ])
}

/// A pixel size as points for the apps' font strings (96 dpi), to the half point: 13 px → 10 pt.
pub fn pt(px: f64) -> String {
    num_text((px * 0.75 * 2.0).round() / 2.0)
}

/// Whole numbers without a fraction, the rest as they are.
fn whole(x: f64) -> String {
    format!("{}", x.round() as i64)
}

fn num_text(x: f64) -> String {
    if x.fract() == 0.0 {
        format!("{}", x as i64)
    } else {
        format!("{x}")
    }
}

/// The animations the shell owns in niri (W34). The others keep niri's own.
const NIRI_ANIMATIONS: [&str; 6] = [
    "workspace-switch",
    "horizontal-view-movement",
    "window-open",
    "window-close",
    "window-movement",
    "window-resize",
];

/// The family of [`niri_animations`] for the motion in effect. K83 made `motion.profile` a motion pack's id (`washi`,
/// `kawaii`), so the family is read from what the pack resolved to — no springs (`none`, reduce motion) is off, a
/// bouncier spring than calm's is lively, springs are calm, curves expressive; tokens without `motion.kind` (an old
/// document) keep naming it by `motion.profile`. (W59.9 maps the curves and springs themselves.)
fn niri_family(t: &serde_json::Map<String, Value>) -> Option<&str> {
    let Some(kind) = t.get("motion.kind").and_then(Value::as_str) else {
        return t.get("motion.profile").and_then(Value::as_str);
    };
    let damping = t.get("motion.spring.damping").and_then(Value::as_f64);
    Some(
        match (kind, t.get("motion.spring.on").and_then(Value::as_bool)) {
            ("none", _) | (_, Some(false)) => "none",
            ("spring", _) if damping.is_some_and(|d| d < 0.45) => "lively",
            ("spring", _) => "calm",
            _ => "expressive",
        },
    )
}

/// niri's `animations` block from the resolved curves (K83, `theme.motion.windows = follow`): windows open on the open
/// curve and close on the close curve, the view and workspaces move on the open curve, moving and resizing windows on
/// the fast one. A single cubic is niri's `curve "cubic-bezier"` over its duration; a spring maps 1:1 (mass 1:
/// `stiffness = (2π / response)²`, `damping-ratio = 1 − bounce`, or `1 / (1 + bounce)` when overdamped); K42's springs
/// (`spring_q`), multi-segment cubics and steps have no niri form and take the family's spring. With `forms` (K91) a window
/// opens and closes in its form (`motion.form.window.*`): the form's pace stretches the curve as in the shell, what niri has
/// no curve for runs in the shader on a linear clock, `none` is niri's `off`, and a recipe is generated from its tracks.
fn niri_follow(
    t: &serde_json::Map<String, Value>,
    family: &str,
    speed: f64,
    forms: bool,
) -> String {
    let fallback = |name: &str| {
        let b = niri_animations(family, speed);
        b.lines()
            .skip_while(|l| l.trim() != format!("{name} {{"))
            .nth(1)
            .map(|l| l.trim().to_owned())
            .unwrap_or_default()
    };
    let body = |name: &str, role: &str, pace: f64| -> String {
        let c = t.get(&format!("motion.curve.{role}"));
        let kind = c
            .and_then(|c| c.get("kind"))
            .and_then(Value::as_str)
            .unwrap_or("");
        let ms = c
            .and_then(|c| c.get("ms"))
            .and_then(Value::as_f64)
            .unwrap_or(0.0)
            * pace;
        if pace_linear(forms, name, c) && ms > 0.0 {
            return format!(
                "duration-ms {}\n        curve \"linear\"",
                ms.round() as i64
            );
        }
        match kind {
            "cubic" => {
                let pts: Vec<f64> = c
                    .and_then(|c| c.get("points"))
                    .and_then(Value::as_array)
                    .map(|a| a.iter().filter_map(Value::as_f64).collect())
                    .unwrap_or_default();
                if pts.len() == 6 && ms > 0.0 {
                    let n = |x: f64| format!("{}", (x * 1e4).round() / 1e4);
                    format!(
                        "duration-ms {}\n        curve \"cubic-bezier\" {} {} {} {}",
                        ms.round() as i64,
                        n(pts[0]),
                        n(pts[1]),
                        n(pts[2]),
                        n(pts[3])
                    )
                } else {
                    fallback(name)
                }
            }
            "spring" => {
                let r = c
                    .and_then(|c| c.get("response"))
                    .and_then(Value::as_f64)
                    .unwrap_or(ms)
                    * if c.and_then(|c| c.get("response")).is_some() {
                        pace
                    } else {
                        1.0
                    }
                    / 1000.0;
                let b = c
                    .and_then(|c| c.get("bounce"))
                    .and_then(Value::as_f64)
                    .unwrap_or(0.0);
                if r <= 0.0 {
                    return fallback(name);
                }
                let k = (std::f64::consts::TAU / r).powi(2).round().max(1.0) as i64;
                let ratio = if b >= 0.0 { 1.0 - b } else { 1.0 / (1.0 + b) };
                format!("spring damping-ratio={ratio:.2} stiffness={k} epsilon=0.0001")
            }
            _ => fallback(name),
        }
    };
    let mut out = String::from("animations {\n");
    for name in NIRI_ANIMATIONS {
        let role = match name {
            "window-open" | "workspace-switch" | "horizontal-view-movement" => "open",
            "window-close" => "close",
            _ => "fast",
        };
        // K91: the window's own form on open and close.
        let form = (forms && matches!(name, "window-open" | "window-close"))
            .then(|| {
                let dir = if name == "window-open" {
                    "open"
                } else {
                    "close"
                };
                t.get(&format!("motion.form.window.{dir}"))
                    .and_then(Value::as_str)
            })
            .flatten();
        if form == Some("none") {
            out.push_str(&format!("    {name} {{\n        off\n    }}\n"));
            continue;
        }
        let pace = form
            .and_then(kurashi_motion::forms::form)
            .map_or(1.0, |m| m.pace());
        let curve = t.get(&format!("motion.curve.{role}"));
        let shader =
            form.and_then(|f| crate::niri_forms::shader(t, f, name == "window-open", curve));
        out.push_str(&format!(
            "    {name} {{\n        {}\n",
            body(name, role, pace)
        ));
        if let Some(s) = shader {
            out.push_str(&format!("        custom-shader r\"\n{s}\"\n"));
        }
        out.push_str("    }\n");
    }
    out.push('}');
    out
}

/// K91: a window's open or close whose curve niri cannot say: the shader keeps that curve on a linear clock.
fn pace_linear(forms: bool, name: &str, curve: Option<&Value>) -> bool {
    forms
        && matches!(name, "window-open" | "window-close")
        && crate::niri_forms::needs_linear(curve)
}

/// niri's `animations` block for a motion profile (W34): calm settles without a bounce, lively overshoots a little,
/// none turns every animation off with niri's `off` (not a stiff spring that only looks instant). The stiffness
/// scales with the speed setting squared: a spring's time scale grows with the square root of its stiffness.
pub fn niri_animations(profile: &str, speed: f64) -> String {
    if profile == "none" {
        return "animations {\n    off\n}".into();
    }
    // (expressive: the shell's surfaces overshoot ~6 % on their curves; the windows a little less, on a spring)
    let (damping, stiffness) = match profile {
        "lively" => (0.75, 1000.0),
        "expressive" => (0.85, 900.0),
        _ => (1.0, 800.0),
    };
    let k = (stiffness * speed.clamp(0.25, 4.0).powi(2)).round() as i64;
    let mut out = String::from("animations {\n");
    for name in NIRI_ANIMATIONS {
        // niri reads the damping ratio as a float: `1` is an integer and refused.
        out.push_str(&format!(
            "    {name} {{\n        spring damping-ratio={damping:.2} stiffness={k} epsilon=0.0001\n    }}\n"
        ));
    }
    out.push('}');
    out
}

/// `template` with every `{{…}}` filled in: `colors.<role>.<mode>.<format>` from the palette, any other name from
/// `values`. The placeholders that could not be filled stay as they were and are returned (reported, Shōjiki).
pub fn render(template: &str, p: &Palette, values: &Values) -> (String, BTreeSet<String>) {
    let mut out = String::with_capacity(template.len());
    let mut unknown = BTreeSet::new();
    let mut rest = template;
    while let Some(start) = rest.find("{{") {
        out.push_str(&rest[..start]);
        let Some(len) = rest[start..].find("}}") else {
            out.push_str(&rest[start..]);
            rest = "";
            break;
        };
        let whole = &rest[start..start + len + 2];
        let inner = whole[2..whole.len() - 2].trim();
        let filled = match inner.strip_prefix("colors.") {
            Some(path) => colour(p, path),
            None => values.get(inner).cloned(),
        };
        match filled {
            Some(v) => out.push_str(&v),
            None => {
                unknown.insert(inner.to_owned());
                out.push_str(whole);
            }
        }
        rest = &rest[start + len + 2..];
    }
    out.push_str(rest);
    (out, unknown)
}

/// One `key=value` a rendered template asks an app's config (or the desktop's settings) to hold, under its `[section]`
/// (`""` before any). `value` is the text after the `=`, quotes included: gsettings reads GVariant text.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Entry {
    pub section: String,
    pub key: String,
    pub value: String,
}

impl Entry {
    /// The line as the file holds it.
    pub fn line(&self) -> String {
        format!("{}={}", self.key, self.value)
    }
}

/// The entries of a rendered template. Comments (`#`, `;`) and blank lines are skipped; so is a line whose value is
/// empty once its quotes are removed: a value the shell does not have (no icon theme chosen) is left to the app, not
/// written over (Shōjiki, K49 amendment). So is a value a placeholder did not fill (`{{…}}` left in it): the braces would
/// go into the app's or the desktop's setting, and the placeholder is reported as unknown instead.
pub fn entries(text: &str) -> Vec<Entry> {
    let mut out = Vec::new();
    let mut section = String::new();
    for raw in text.lines() {
        let line = raw.trim();
        if line.is_empty() || line.starts_with('#') || line.starts_with(';') {
            continue;
        }
        if let Some(s) = line.strip_prefix('[').and_then(|s| s.strip_suffix(']')) {
            section = s.trim().to_owned();
            continue;
        }
        let Some((key, value)) = line.split_once('=') else {
            continue;
        };
        let (key, value) = (key.trim(), value.trim());
        if value.trim_matches(['\'', '"']).trim().is_empty() || value.contains("{{") {
            continue;
        }
        out.push(Entry {
            section: section.clone(),
            key: key.to_owned(),
            value: value.to_owned(),
        });
    }
    out
}

/// Where a target's output goes.
pub enum Output {
    /// A file: `template` under `templates/`, written to `path` under `$XDG_CONFIG_HOME` (`@data/…`: under
    /// `$XDG_DATA_HOME`).
    File {
        template: &'static str,
        path: &'static str,
    },
    /// The desktop's settings (K49 amendment, W34): `template` holds `[schema]` sections of `key='value'` lines,
    /// applied with gsettings. The only target that writes settings instead of a file; opt-in like every target.
    Settings { template: &'static str },
}

/// A bundled export target: its name (`theme.export` lists these), its output, and what the program's own config must
/// hold to use it.
pub struct Target {
    pub name: &'static str,
    pub output: Output,
    /// The line the program's config must hold to read the file: (the config file under `$XDG_CONFIG_HOME`, the line).
    pub include: Option<(&'static str, &'static str)>,
    /// Lines the program's config must hold, rather than an include: (the config file, the template under
    /// `templates/lines/`).
    pub lines: Option<(&'static str, &'static str)>,
    /// A file an earlier version wrote (the include line that named it): kurashid keeps it as a stub, so the old
    /// include still loads, and reports the old line as stale.
    pub legacy: Option<(&'static str, &'static str)>,
    /// A generated shader written beside the file, under `$XDG_CONFIG_HOME` (ghostty, W37: [`ghostty_shader`]). The
    /// template names it with `{{ghostty.shader}}`: the shader lines while the material is on, nothing otherwise.
    pub shader: Option<&'static str>,
}

/// Written in place of a superseded file (see [`Target::legacy`]). Comments only: an empty include is valid for niri.
pub const LEGACY_STUB: &str = "// Superseded (K49, W34): the shell's niri settings are in kurashi.kdl now. Replace the\n// include line that names this file with `include \"kurashi.kdl\"`.\n";

/// The targets, in the order Settings lists them.
pub const TARGETS: &[Target] = &[
    Target {
        name: "gtk3",
        output: Output::File {
            template: "gtk-colors.css",
            path: "gtk-3.0/kurashi-colors.css",
        },
        include: Some(("gtk-3.0/gtk.css", "@import 'kurashi-colors.css';")),
        lines: None,
        legacy: None,
        shader: None,
    },
    Target {
        name: "gtk4",
        // libadwaita 1.6+ reads CSS variables: GTK 4 gets them besides the named colours (GTK 3 would warn on them).
        output: Output::File {
            template: "gtk4-colors.css",
            path: "gtk-4.0/kurashi-colors.css",
        },
        include: Some(("gtk-4.0/gtk.css", "@import 'kurashi-colors.css';")),
        lines: None,
        legacy: None,
        shader: None,
    },
    Target {
        name: "qt",
        output: Output::File {
            template: "qtct-colors.conf",
            path: "qt6ct/colors/kurashi.conf",
        },
        include: None,
        lines: Some(("qt6ct/qt6ct.conf", "lines/qt6ct.conf")),
        legacy: None,
        shader: None,
    },
    Target {
        name: "qt5",
        output: Output::File {
            template: "qtct-colors.conf",
            path: "qt5ct/colors/kurashi.conf",
        },
        include: None,
        lines: Some(("qt5ct/qt5ct.conf", "lines/qt5ct.conf")),
        legacy: None,
        shader: None,
    },
    // KDE apps take their colours from a KDE colour scheme over the Qt palette: one for them to pick, in
    // `$XDG_DATA_HOME` (the `@data/` prefix), where their Window Color Scheme menu lists it. kdeglobals names it.
    Target {
        name: "kde",
        output: Output::File {
            template: "kde-colors.colors",
            path: "@data/color-schemes/Kurashi.colors",
        },
        include: None,
        lines: Some(("kdeglobals", "lines/kdeglobals.conf")),
        legacy: None,
        shader: None,
    },
    Target {
        name: "foot",
        output: Output::File {
            template: "foot.ini",
            path: "foot/kurashi-colors.ini",
        },
        include: Some(("foot/foot.ini", "include=~/.config/foot/kurashi-colors.ini")),
        lines: None,
        legacy: None,
        shader: None,
    },
    Target {
        name: "kitty",
        output: Output::File {
            template: "kitty.conf",
            path: "kitty/kurashi-colors.conf",
        },
        include: Some(("kitty/kitty.conf", "include kurashi-colors.conf")),
        lines: None,
        legacy: None,
        shader: None,
    },
    Target {
        name: "alacritty",
        output: Output::File {
            template: "alacritty.toml",
            path: "alacritty/kurashi-colors.toml",
        },
        include: Some((
            "alacritty/alacritty.toml",
            "general.import = [\"~/.config/alacritty/kurashi-colors.toml\"]",
        )),
        lines: None,
        legacy: None,
        shader: None,
    },
    Target {
        name: "ghostty",
        output: Output::File {
            template: "ghostty.conf",
            path: "ghostty/themes/kurashi",
        },
        include: Some(("ghostty/config", "theme = kurashi")),
        lines: None,
        legacy: None,
        shader: Some(ghostty_shader::PATH),
    },
    // zellij reads the theme by name from its themes folder.
    Target {
        name: "zellij",
        output: Output::File {
            template: "zellij.kdl",
            path: "zellij/themes/kurashi.kdl",
        },
        include: Some(("zellij/config.kdl", "theme \"kurashi\"")),
        lines: None,
        legacy: None,
        shader: None,
    },
    // fzf's colours (noren's picker, and every other fzf): an options file fzf reads through FZF_DEFAULT_OPTS_FILE
    // (fzf 0.47+), set in the shell's config (fish shown; bash/zsh: `export FZF_DEFAULT_OPTS_FILE=…`).
    Target {
        name: "fzf",
        output: Output::File {
            template: "fzf.opts",
            path: "kurashi/apps/fzf",
        },
        include: Some((
            "fish/config.fish",
            "set -gx FZF_DEFAULT_OPTS_FILE {{paths.config}}/kurashi/apps/fzf",
        )),
        lines: None,
        legacy: None,
        shader: None,
    },
    Target {
        name: "nvim",
        output: Output::File {
            template: "nvim.lua",
            path: "nvim/colors/kurashi.lua",
        },
        include: Some(("nvim/init.lua", "vim.cmd.colorscheme(\"kurashi\")")),
        lines: None,
        legacy: None,
        shader: None,
    },
    Target {
        name: "helix",
        output: Output::File {
            template: "helix.toml",
            path: "helix/themes/kurashi.toml",
        },
        include: Some(("helix/config.toml", "theme = \"kurashi\"")),
        lines: None,
        legacy: None,
        shader: None,
    },
    Target {
        name: "zed",
        output: Output::File {
            template: "zed.json",
            path: "zed/themes/kurashi.json",
        },
        include: Some(("zed/settings.json", "\"theme\": \"Kurashi\",")),
        lines: None,
        legacy: None,
        shader: None,
    },
    // Firefox and Zen read the file from the profile's userChrome.css (`~/` = $HOME, the profile is the user's).
    Target {
        name: "firefox",
        output: Output::File {
            template: "mozilla.css",
            path: "kurashi/apps/firefox.css",
        },
        include: Some((
            "mozilla/firefox/<profile>/chrome/userChrome.css",
            "@import url(\"file://{{paths.config}}/kurashi/apps/firefox.css\");",
        )),
        lines: None,
        legacy: None,
        shader: None,
    },
    Target {
        name: "zen",
        output: Output::File {
            template: "mozilla.css",
            path: "kurashi/apps/zen.css",
        },
        include: Some((
            "~/.zen/<profile>/chrome/userChrome.css",
            "@import url(\"file://{{paths.config}}/kurashi/apps/zen.css\");",
        )),
        lines: None,
        legacy: None,
        shader: None,
    },
    // Vesktop lists the file under Settings → Vencord → Themes; it is enabled there, not in a config line.
    Target {
        name: "vesktop",
        output: Output::File {
            template: "vesktop.css",
            path: "vesktop/themes/kurashi.css",
        },
        include: None,
        lines: None,
        legacy: None,
        shader: None,
    },
    // Spotify takes the colours on `spicetify apply` (the user runs it; the shell runs nothing).
    Target {
        name: "spicetify",
        output: Output::File {
            template: "spicetify.ini",
            path: "spicetify/Themes/Kurashi/color.ini",
        },
        include: None,
        lines: Some(("spicetify/config-xpui.ini", "lines/spicetify.ini")),
        legacy: None,
        shader: None,
    },
    // Obsidian reads CSS snippets per vault: the file is linked into a vault's `.obsidian/snippets/` (README).
    Target {
        name: "obsidian",
        output: Output::File {
            template: "obsidian.css",
            path: "kurashi/apps/obsidian.css",
        },
        include: None,
        lines: None,
        legacy: None,
        shader: None,
    },
    Target {
        name: "niri",
        output: Output::File {
            template: "niri-colors.kdl",
            path: "niri/kurashi.kdl",
        },
        include: Some(("niri/config.kdl", "include \"kurashi.kdl\"")),
        lines: None,
        legacy: Some(("niri/kurashi-colors.kdl", "include \"kurashi-colors.kdl\"")),
        shader: None,
    },
    Target {
        name: "hyprland",
        output: Output::File {
            template: "hyprland.conf",
            path: "hypr/kurashi.conf",
        },
        include: Some(("hypr/hyprland.conf", "source = ~/.config/hypr/kurashi.conf")),
        lines: None,
        legacy: None,
        shader: None,
    },
    Target {
        name: "mango",
        output: Output::File {
            template: "mango.conf",
            path: "mango/kurashi.conf",
        },
        include: Some(("mango/config.conf", "source=~/.config/mango/kurashi.conf")),
        lines: None,
        legacy: None,
        shader: None,
    },
    Target {
        name: "sway",
        output: Output::File {
            template: "sway.conf",
            path: "sway/kurashi.conf",
        },
        include: Some(("sway/config", "include ~/.config/sway/kurashi.conf")),
        lines: None,
        legacy: None,
        shader: None,
    },
    Target {
        name: "gsettings",
        output: Output::Settings {
            template: "gsettings.ini",
        },
        include: None,
        lines: None,
        legacy: None,
        shader: None,
    },
];

pub fn target(name: &str) -> Option<&'static Target> {
    TARGETS.iter().find(|t| t.name == name)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn palette() -> Palette {
        let mut roles = BTreeMap::new();
        for (r, c) in [
            ("surface", Rgb(0x1b, 0x1a, 0x1e)),
            ("on_surface", Rgb(0xe9, 0xe4, 0xd8)),
            ("accent", Rgb(0xc9, 0x40, 0x4b)),
            ("on_accent", Rgb(0xff, 0xf6, 0xf1)),
            ("secondary", Rgb(0x5b, 0x7f, 0xa6)),
            ("error", Rgb(0xe4, 0x69, 0x62)),
        ] {
            roles.insert(r.to_owned(), c);
        }
        Palette {
            name: "t".into(),
            dark: true,
            roles,
        }
    }

    /// The theme document's tokens as the tests' palette and shape want them (W34).
    fn tokens() -> serde_json::Map<String, Value> {
        serde_json::json!({
            "font.family": "Inter",
            "font.size.body": 13,
            "radius.lg": 18,
            "chrome.outline": 2,
            "motion.standard_ms": 220,
            "motion.easing.continuous": [0.4, 0.0, 0.2, 1.0],
            "color.surface_alpha": 0.85,
            "motion.profile": "calm",
        })
        .as_object()
        .cloned()
        .unwrap()
    }

    fn inputs(tokens: &serde_json::Map<String, Value>) -> Values {
        values(&Inputs {
            tokens,
            scheme: "dark",
            icon_theme: "Papirus-Dark",
            motion_speed: 1.0,
            config_dir: "/home/u/.config",
            window_frame: false,
            window_frame_color: "accent",
            inactive_opacity: None,
            animations: true,
            titlebars: false,
            palette: &palette(),
        })
    }

    /// I423: the colour round the focused window. Accent stays the default; the shell's outline follows its ink.
    #[test]
    fn the_window_frame_takes_the_colour_asked_for() {
        let mut p = palette();
        p.roles.insert("tertiary".into(), Rgb(0x8f, 0x6a, 0xc1));
        p.roles.insert("outline".into(), Rgb(0x70, 0x70, 0x70));
        let frame = |color: &str, tokens: serde_json::Map<String, Value>| {
            values(&Inputs {
                tokens: &tokens,
                scheme: "dark",
                icon_theme: "",
                motion_speed: 1.0,
                config_dir: "/",
                window_frame: true,
                window_frame_color: color,
                inactive_opacity: None,
                animations: true,
                titlebars: false,
                palette: &p,
            })["frame.active.hex"]
                .clone()
        };
        let hex = |r: &str| role(&p, r).unwrap().hex();
        let with = |ink: &str, outline: f64| {
            let mut t = tokens();
            t.insert("outline.ink".into(), ink.into());
            t.insert("chrome.outline".into(), outline.into());
            t.insert("chrome.outline_color".into(), "#123456".into());
            t
        };
        assert_eq!(frame("accent", with("text", 1.0)), hex("primary"));
        assert_eq!(frame("shell_outline", with("text", 1.0)), hex("on_surface"));
        assert_eq!(frame("shell_outline", with("accent", 1.0)), hex("primary"));
        assert_eq!(frame("shell_outline", with("outline", 1.0)), "#123456");
        // Flat chrome draws no outline of its own: the shell falls to the role, and so does the frame.
        assert_eq!(frame("shell_outline", with("outline", 0.0)), hex("outline"));
        for r in ["secondary", "tertiary", "outline", "on_surface"] {
            assert_eq!(frame(r, tokens()), hex(r));
        }
    }

    /// Every compositor that draws frames takes it.
    #[test]
    fn every_compositor_template_names_the_frame_colour() {
        for (name, text) in [
            ("niri", include_str!("../../../templates/niri-colors.kdl")),
            ("hyprland", include_str!("../../../templates/hyprland.conf")),
            ("mango", include_str!("../../../templates/mango.conf")),
            ("sway", include_str!("../../../templates/sway.conf")),
        ] {
            assert!(text.contains("{{frame.active.hex"), "{name}");
        }
    }

    #[test]
    fn matugen_placeholders_fill_from_our_roles() {
        let (s, unknown) = render(
            "bg={{colors.background.default.hex}} fg={{ colors.on_surface.dark.hex_stripped }} \
             a={{colors.primary.default.red}},{{colors.primary.default.green}} {{image}} {{colors.nope.default.hex}}",
            &palette(),
            &Values::new(),
        );
        assert_eq!(
            s,
            "bg=#1b1a1e fg=e9e4d8 a=201,64 {{image}} {{colors.nope.default.hex}}"
        );
        assert_eq!(
            unknown.into_iter().collect::<Vec<_>>(),
            vec!["colors.nope.default.hex", "image"]
        );
    }

    #[test]
    fn values_fill_every_non_colour_placeholder() {
        let t = tokens();
        let v = inputs(&t);
        let (s, unknown) = render(
            "{{fonts.family}}|{{fonts.size}}|{{fonts.mono}}|{{icons.theme}}|{{scheme}}|{{shape.radius}}|\
             {{shape.border}}|{{motion.ms}}|{{motion.curve}}|{{material.opacity}}|{{paths.config}}|\
             {{gsettings.color_scheme}}",
            &palette(),
            &v,
        );
        assert_eq!(
            s,
            "Inter|10|monospace|Papirus-Dark|dark|18|2|220|cubic-bezier(0.4, 0, 0.2, 1)|0.85|/home/u/.config|prefer-dark"
        );
        assert!(unknown.is_empty(), "{unknown:?}");
    }

    #[test]
    fn a_missing_token_or_unknown_name_is_reported_not_invented() {
        let empty = serde_json::Map::new();
        let (s, unknown) = render(
            "{{fonts.family}} {{shape.radius}} {{fonts.nope}}",
            &palette(),
            &inputs(&empty),
        );
        assert_eq!(s, "{{fonts.family}} {{shape.radius}} {{fonts.nope}}");
        assert_eq!(
            unknown.into_iter().collect::<Vec<_>>(),
            vec!["fonts.family", "fonts.nope", "shape.radius"]
        );
    }

    #[test]
    fn scheme_light_and_the_settings_values_follow_it() {
        let t = tokens();
        let v = values(&Inputs {
            tokens: &t,
            scheme: "light",
            icon_theme: "",
            motion_speed: 1.0,
            config_dir: "/c",
            window_frame: false,
            window_frame_color: "accent",
            inactive_opacity: None,
            animations: true,
            titlebars: false,
            palette: &palette(),
        });
        assert_eq!(v["gsettings.color_scheme"], "default");
        assert_eq!(v["scheme"], "light");
        assert_eq!(
            v["icons.theme"], "",
            "`leave as is` is an empty value, not a missing one"
        );
    }

    #[test]
    fn shape_border_floor_for_flat_chrome_and_pixels_as_points() {
        let mut t = tokens();
        t.insert("chrome.outline".into(), serde_json::json!(0));
        assert_eq!(
            inputs(&t)["shape.border"],
            "2",
            "flat chrome draws no outline; the focus ring keeps 2 px"
        );
        t.insert("chrome.outline".into(), serde_json::json!(1));
        assert_eq!(inputs(&t)["shape.border"], "1");
        assert_eq!(pt(13.0), "10", "13 px = 9.75 pt, to the half point");
        assert_eq!(pt(11.0), "8.5", "11 px = 8.25 pt, to the half point");
        assert_eq!(pt(16.0), "12");
        assert_eq!(pt(9.0), "7");
    }

    /// `theme.motion.windows = follow`: windows take the profile's own cubic and spring; what niri cannot express
    /// (K42's springs, several segments, steps) takes the family's spring; off keeps the family's block.
    #[test]
    fn niri_follows_the_profiles_curves_when_asked() {
        let toks = |windows: &str| {
            serde_json::json!({
                "motion.kind": "timed", "motion.spring.on": true, "motion.spring.damping": 0.45,
                "motion.windows": windows,
                "motion.curve.open": {"kind": "cubic", "ms": 500, "points": [0.38, 1.21, 0.22, 1.0, 1.0, 1.0]},
                "motion.curve.close": {"kind": "spring", "ms": 550, "response": 550, "bounce": 0.45},
                "motion.curve.fast": {"kind": "spring_q", "ms": 0, "spring": 4.0, "damping": 0.45},
            })
        };
        let t = toks("follow");
        let fam = niri_family(t.as_object().unwrap()).unwrap();
        let b = niri_follow(t.as_object().unwrap(), fam, 1.0, false);
        assert!(b.contains("window-open {\n        duration-ms 500\n        curve \"cubic-bezier\" 0.38 1.21 0.22 1\n"), "{b}");
        // spring(550 ms, 0.45): stiffness (2π / 0.55)² ≈ 131, ratio 0.55.
        assert!(
            b.contains(
                "window-close {\n        spring damping-ratio=0.55 stiffness=131 epsilon=0.0001"
            ),
            "{b}"
        );
        // spring_q (fast → window-movement) has no niri form: the family's spring.
        assert!(
            b.contains("window-movement {\n        spring damping-ratio=0.85 stiffness=900"),
            "{b}"
        );
    }

    /// `theme.motion.windows = forms` (K91): open and close carry the window's form as a custom shader, on the form's
    /// pace; the view, moves and resizes keep their curves; `none` is `off`; a recipe that is skipped has the curve alone.
    #[test]
    fn niri_carries_the_forms_when_asked() {
        let toks = |open: &str, close: &str| {
            serde_json::json!({
                "motion.kind": "timed", "motion.spring.on": true, "motion.spring.damping": 0.45,
                "motion.windows": "forms",
                "motion.form.window.open": open, "motion.form.window.close": close,
                "motion.curve.open": {"kind": "cubic", "ms": 500, "points": [0.38, 1.21, 0.22, 1.0, 1.0, 1.0]},
                "motion.curve.close": {"kind": "spring", "ms": 400, "response": 400, "bounce": 0.0},
                "motion.curve.fast": {"kind": "steps", "ms": 200, "n": 4},
            })
        };
        let t = toks("fold", "drop");
        let t = t.as_object().unwrap();
        let b = niri_follow(t, "expressive", 1.0, true);
        // fold's pace 1.4 over 500 ms, drop's 1.9 over a 400 ms response (0.76 s: (2π / 0.76)² ≈ 68).
        assert!(
            b.contains("window-open {\n        duration-ms 700\n"),
            "{b}"
        );
        assert!(
            b.contains("window-close {\n        spring damping-ratio=1.00 stiffness=68 "),
            "{b}"
        );
        assert_eq!(b.matches("custom-shader r\"").count(), 2, "{b}");
        assert!(
            b.contains("vec4 open_color") && b.contains("vec4 close_color"),
            "{b}"
        );
        assert!(!b.contains("window-resize {\n        custom-shader"), "{b}");
        // niri's curves stay for what has no form: steps have no niri form there (the family's spring)
        assert!(b.contains("window-movement {\n        spring"), "{b}");
        let t = toks("none", "my-recipe");
        let b = niri_follow(t.as_object().unwrap(), "expressive", 1.0, true);
        assert!(b.contains("window-open {\n        off\n"), "{b}");
        assert!(b.contains("window-close {\n        spring"), "{b}");
        assert!(!b.contains("custom-shader"), "{b}");
        // `follow` stays curves alone
        let t = toks("fold", "drop");
        assert!(
            !niri_follow(t.as_object().unwrap(), "expressive", 1.0, false)
                .contains("custom-shader")
        );
    }

    #[test]
    fn niri_family_from_the_resolved_motion() {
        let fam =
            |pairs: serde_json::Value| niri_family(pairs.as_object().unwrap()).map(String::from);
        let on = |kind: &str, damping: f64| {
            serde_json::json!({"motion.profile": "kawaii", "motion.kind": kind, "motion.spring.on": true,
                               "motion.spring.damping": damping})
        };
        assert_eq!(fam(on("timed", 0.45)).as_deref(), Some("expressive"));
        assert_eq!(fam(on("stepped", 0.45)).as_deref(), Some("expressive"));
        assert_eq!(fam(on("spring", 0.45)).as_deref(), Some("calm"));
        assert_eq!(fam(on("spring", 0.26)).as_deref(), Some("lively"));
        assert_eq!(fam(on("none", 1.0)).as_deref(), Some("none"));
        // Reduce motion: timed fades, no springs — windows do not animate either.
        assert_eq!(
            fam(serde_json::json!({"motion.kind": "timed", "motion.spring.on": false})).as_deref(),
            Some("none")
        );
        assert_eq!(
            fam(serde_json::json!({"motion.profile": "calm"})).as_deref(),
            Some("calm")
        );
    }

    #[test]
    fn niri_animations_by_profile_and_speed() {
        assert_eq!(niri_animations("none", 1.0), "animations {\n    off\n}");
        let calm = niri_animations("calm", 1.0);
        assert!(calm.starts_with("animations {\n"), "{calm}");
        assert!(
            calm.contains("spring damping-ratio=1.00 stiffness=800 epsilon=0.0001"),
            "{calm}"
        );
        assert!(niri_animations("lively", 1.0).contains("damping-ratio=0.75 stiffness=1000"));
        // Twice as fast: a spring's stiffness four times as big.
        assert!(niri_animations("calm", 2.0).contains("stiffness=3200"));
        for name in NIRI_ANIMATIONS {
            assert!(calm.contains(&format!("    {name} {{")), "{name} missing");
        }
    }

    #[test]
    fn entries_keep_sections_and_drop_values_the_shell_does_not_have() {
        let text = "# comment\n[Appearance]\nicon_theme=\ncustom_palette=true\n\n[Fonts]\ngeneral=\"Inter,10\"\n\
                    [org.gnome.desktop.interface]\nicon-theme=''\ncolor-scheme='prefer-dark'\nfont-name='{{fonts.family}} 10'\n";
        let e = entries(text);
        let lines: Vec<String> = e
            .iter()
            .map(|x| format!("{}|{}", x.section, x.line()))
            .collect();
        assert_eq!(
            lines,
            vec![
                "Appearance|custom_palette=true",
                "Fonts|general=\"Inter,10\"",
                "org.gnome.desktop.interface|color-scheme='prefer-dark'",
            ]
        );
    }

    #[test]
    fn every_target_template_exists() {
        let root = std::path::Path::new(env!("CARGO_MANIFEST_DIR")).join("../../templates");
        for t in TARGETS {
            let template = match t.output {
                Output::File { template, .. } | Output::Settings { template } => template,
            };
            assert!(
                root.join(template).is_file(),
                "{} lacks templates/{template}",
                t.name
            );
            if let Some((_, lines)) = t.lines {
                assert!(
                    root.join(lines).is_file(),
                    "{} lacks templates/{lines}",
                    t.name
                );
            }
        }
    }
}
