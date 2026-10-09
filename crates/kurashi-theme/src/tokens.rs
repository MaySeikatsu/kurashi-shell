//! Axes -> scales, roles -> component tokens, everything -> the flat `TokenMap`.

use std::collections::BTreeMap;

use serde_json::{Value, json};

use crate::ThemeError;
use crate::color::{BLACK, Rgb, WHITE, contrast};
use crate::fonts::{FontProvider, resolve_chain};
use crate::input::{Axes, Density, Material, MotionProfile, Shape};
use crate::palette::{Palette, ROLES};

/// Flat dotted-key map; the `theme` document's `tokens` object.
pub type TokenMap = BTreeMap<String, Value>;

fn px(map: &mut TokenMap, key: &str, v: f64) {
    map.insert(key.to_string(), json!(v.round() as i64));
}

fn col(map: &mut TokenMap, key: &str, c: Rgb) {
    map.insert(key.to_string(), json!(c.hex()));
}

/// Spacing (4 px base) x density.
pub fn space_scale(d: Density) -> [(&'static str, f64); 6] {
    let k: f64 = match d {
        Density::Compact => 0.75,
        Density::Regular => 1.0,
        Density::Airy => 1.25,
    };
    [
        ("xs", 4.0),
        ("sm", 8.0),
        ("md", 12.0),
        ("lg", 16.0),
        ("xl", 24.0),
        ("2xl", 32.0),
    ]
    .map(|(n, v)| (n, (v * k).round()))
}

/// Radius steps x `radius_scale`; shape `none` collapses all of them to 0.
pub fn radius_scale(shape: Shape, scale: f64) -> [(&'static str, f64); 5] {
    let k = if shape == Shape::None {
        0.0
    } else {
        scale.max(0.0)
    };
    [
        ("none", 0.0),
        ("sm", 6.0 * k),
        ("md", 12.0 * k),
        ("lg", 18.0 * k),
        ("full", if k == 0.0 { 0.0 } else { 999.0 }),
    ]
}

/// (name, base ms) before speed/profile.
const DURATIONS: [(&str, f64); 5] = [
    ("instant", 0.0),
    ("quick", 120.0),
    ("standard", 220.0),
    ("emphasized", 320.0),
    ("long", 500.0),
];

pub fn duration_ms(base: f64, profile: MotionProfile, speed: f64) -> i64 {
    let speed = speed.clamp(0.25, 4.0);
    let profile_k = match profile {
        MotionProfile::None => return 0,
        MotionProfile::Calm => 1.0,
        MotionProfile::Lively => 0.8,
    };
    (base * profile_k / speed).round() as i64
}

/// Cubic-bezier control points per easing role.
pub fn easing(profile: MotionProfile) -> [(&'static str, [f64; 4]); 4] {
    match profile {
        MotionProfile::None => {
            ["enter", "exit", "emphasized", "continuous"].map(|n| (n, [0.0, 0.0, 1.0, 1.0]))
        }
        MotionProfile::Calm => [
            ("enter", [0.05, 0.7, 0.1, 1.0]),
            ("exit", [0.3, 0.0, 0.8, 0.15]),
            ("emphasized", [0.2, 0.0, 0.0, 1.0]),
            ("continuous", [0.4, 0.0, 0.2, 1.0]),
        ],
        // Slight overshoot on arrival; exits stay crisp.
        MotionProfile::Lively => [
            ("enter", [0.34, 1.4, 0.64, 1.0]),
            ("exit", [0.3, 0.0, 0.8, 0.15]),
            ("emphasized", [0.3, 1.2, 0.3, 1.0]),
            ("continuous", [0.4, 0.0, 0.2, 1.0]),
        ],
    }
}

const TYPE_SCALE: [(&str, f64); 5] = [
    ("caption", 11.0),
    ("label", 12.0),
    ("body", 13.0),
    ("title", 16.0),
    ("display", 24.0),
];

/// Mix toward `toward`, used for hover/pressed overlays.
fn overlay(base: Rgb, toward: Rgb, t: f64) -> Rgb {
    base.mix(toward, t)
}

/// `c` mixed toward `toward` in small steps, the first step that reaches `min` contrast on `bg`;
/// `toward` itself when none does.
fn at_least(c: Rgb, bg: Rgb, min: f64, toward: Rgb) -> Rgb {
    (0..=20)
        .map(|i| c.mix(toward, f64::from(i) / 20.0))
        .find(|m| contrast(*m, bg) >= min)
        .unwrap_or(toward)
}

pub fn build(
    p: &Palette,
    axes: &Axes,
    fonts: &dyn FontProvider,
    overrides: &BTreeMap<String, Value>,
) -> Result<(TokenMap, Vec<String>), ThemeError> {
    let mut t = TokenMap::new();
    let mut notes = vec![];

    // --- semantic roles ---
    for r in ROLES {
        col(&mut t, &format!("color.{r}"), p.get(r));
    }
    let (alpha, blur) = match axes.material {
        Material::Solid => (1.0, false),
        Material::Translucent => (axes.opacity.clamp(0.0, 1.0), false),
        Material::Glass => (axes.opacity.clamp(0.0, 1.0), axes.blur),
    };
    t.insert("color.surface_alpha".into(), json!(alpha));
    t.insert("blur".into(), json!(blur));

    // --- scales ---
    for (n, v) in space_scale(axes.density) {
        px(&mut t, &format!("space.{n}"), v);
    }
    for (n, v) in radius_scale(axes.shape, axes.radius_scale) {
        px(&mut t, &format!("radius.{n}"), v);
    }
    // Genuinely circular things (knobs, avatars) keep a circle even when shape is `none`.
    px(&mut t, "radius.circle", 999.0);
    let shape = match axes.shape {
        Shape::None => "none",
        Shape::Rounded => "rounded",
        Shape::Squircle => "squircle",
    };
    t.insert("shape.corner".into(), json!(shape));
    for (n, v) in TYPE_SCALE {
        px(
            &mut t,
            &format!("font.size.{n}"),
            v * axes.type_scale.clamp(0.5, 3.0),
        );
    }
    for (n, w) in [("regular", 400), ("medium", 500), ("bold", 700)] {
        t.insert(format!("font.weight.{n}"), json!(w));
    }
    let (fam, n1) = resolve_chain(&axes.font_chain, fonts);
    let (fam_jp, n2) = resolve_chain(&axes.font_chain_jp, fonts);
    notes.extend(n1);
    notes.extend(n2);
    t.insert("font.family".into(), json!(fam));
    t.insert("font.family_jp".into(), json!(fam_jp));

    for (n, base) in DURATIONS {
        t.insert(
            format!("motion.{n}_ms"),
            json!(duration_ms(base, axes.motion, axes.motion_speed)),
        );
    }
    for (n, b) in easing(axes.motion) {
        t.insert(format!("motion.easing.{n}"), json!(b));
    }
    t.insert(
        "motion.profile".into(),
        json!(match axes.motion {
            MotionProfile::Calm => "calm",
            MotionProfile::Lively => "lively",
            MotionProfile::None => "none",
        }),
    );

    // --- controls (touch targets stay >= 32 px even when compact) ---
    let ck = match axes.density {
        Density::Compact => 0.875,
        Density::Regular => 1.0,
        Density::Airy => 1.125,
    };
    px(&mut t, "bar.height", 36.0 * ck);
    px(&mut t, "control.height", (36.0 * ck).max(32.0));
    px(&mut t, "slider.height", (6.0 * ck).max(4.0));

    // --- component tokens (renderers bind only to these) ---
    let g = |r: &str| p.get(r);
    let (surface, fg, accent, on_accent) =
        (g("surface"), g("on_surface"), g("accent"), g("on_accent"));
    col(&mut t, "bar.bg", surface);
    col(&mut t, "bar.fg", fg);
    col(&mut t, "bar.fg_dim", g("on_surface_variant"));
    col(&mut t, "bar.border", g("outline_variant"));
    col(&mut t, "island.bg", g("surface_container_high"));
    col(&mut t, "island.fg", fg);
    col(&mut t, "island.fg_dim", g("on_surface_variant"));
    col(&mut t, "island.border", g("outline_variant"));
    col(&mut t, "popup.bg", g("surface_container"));
    col(&mut t, "popup.fg", fg);
    col(&mut t, "popup.chrome", g("outline_variant"));
    col(&mut t, "popup.shadow", g("shadow"));
    col(&mut t, "card.bg", g("surface_container_low"));
    col(&mut t, "card.border", g("outline_variant"));
    col(&mut t, "osd.bg", g("surface_container_highest"));
    col(&mut t, "osd.fg", fg);
    col(&mut t, "lock.bg", g("surface_container_lowest"));
    col(&mut t, "lock.fg", fg);
    col(&mut t, "tooltip.bg", fg); // inverse of the surface; same ratio as on_surface/surface
    col(&mut t, "tooltip.fg", surface);
    col(&mut t, "focus.ring", accent);
    col(&mut t, "slider.track", g("surface_container_highest"));
    col(&mut t, "slider.fill", accent);
    col(&mut t, "slider.thumb", accent);
    col(&mut t, "toggle.track.off", g("surface_container_highest"));
    col(&mut t, "toggle.track.on", accent);
    col(&mut t, "toggle.thumb", on_accent);
    let bb = g("surface_container_high");
    col(&mut t, "button.bg", bb);
    col(&mut t, "button.bg.hover", overlay(bb, fg, 0.08));
    col(&mut t, "button.bg.pressed", overlay(bb, fg, 0.12));
    col(&mut t, "button.fg", fg);
    // Primary hover/pressed move *away* from on_accent so contrast only improves.
    let away = if on_accent.luminance() > accent.luminance() {
        BLACK
    } else {
        WHITE
    };
    col(&mut t, "button.primary.bg", accent);
    col(
        &mut t,
        "button.primary.bg.hover",
        overlay(accent, away, 0.08),
    );
    col(
        &mut t,
        "button.primary.bg.pressed",
        overlay(accent, away, 0.14),
    );
    col(&mut t, "button.primary.fg", on_accent);
    // Mod state marks (K25): a filled dot is on, a hollow ring off. Both are graphics, so they
    // reach 3:1 on the surface; the palette's own colour is kept unless it falls short.
    col(
        &mut t,
        "color.status.on",
        at_least(g("success"), surface, 3.0, fg),
    );
    col(
        &mut t,
        "color.status.off",
        at_least(g("on_surface_variant"), surface, 3.0, fg),
    );
    // I27: activity levels and warnings (sysmon, low battery) are text as often as marks, so the
    // warn role meets AA for text (4.5:1) on the surface, whatever the palette's own yellow is.
    col(
        &mut t,
        "color.status.warn",
        at_least(g("warning"), surface, 4.5, fg),
    );

    // --- overrides (per-surface / per-output); unknown keys are errors, not silent ---
    for (k, v) in overrides {
        if !t.contains_key(k) {
            return Err(ThemeError::UnknownOverride(k.clone()));
        }
        notes.push(format!("override: {k} {} → {v}", t[k]));
        t.insert(k.clone(), v.clone());
    }
    Ok((t, notes))
}
