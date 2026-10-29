//! Axes -> scales, roles -> component tokens, everything -> the flat `TokenMap`.

use std::collections::BTreeMap;

use serde_json::{Value, json};

use crate::ThemeError;
use crate::color::{BLACK, Rgb, WHITE, contrast, ensure_contrast};
use crate::fonts::{FontProvider, resolve_chain};
use crate::input::{Axes, Chrome, Density, FrameOutline, Material, MotionProfile, Shape};
use crate::palette::{Palette, ROLES};

/// The squircle's control-point ratio at `theme.shape.squircle` 0 (a circle's quarter, `K_CIRCLE` in corner.js) and 1.
pub const SQUIRCLE_K_ROUND: f64 = 0.5523;
pub const SQUIRCLE_K_SQUARE: f64 = 0.98;

/// `shape.squircle_k` (I300): the setting's 0..1 mapped onto the control-point ratio; the default 0.77 gives ≈ 0.88,
/// the constant the frontend drew before.
pub fn squircle_k(v: f64) -> f64 {
    SQUIRCLE_K_ROUND + v.clamp(0.0, 1.0) * (SQUIRCLE_K_SQUARE - SQUIRCLE_K_ROUND)
}

/// The icon font components draw glyphs with (ligatures by name), when installed.
pub const ICON_FAMILY: &str = "Material Symbols Rounded";
/// Line chrome's icons (K45): the square-cornered cut of the same set, when installed.
pub const ICON_FAMILY_SHARP: &str = "Material Symbols Sharp";
/// The shell's subset of the two cuts (nix/icon-font.nix, W39-block; installed by the package, W41 row 445): the same
/// glyphs for the names in nix/icon-names.txt, a fraction of the file. Preferred when installed.
pub const ICON_SUBSET: &str = "Kurashi Symbols Rounded";
/// The sharp cut of the subset (line chrome).
pub const ICON_SUBSET_SHARP: &str = "Kurashi Symbols Sharp";

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

/// Radius steps from the one radius `r` (K74): `lg` is `r` (panels, cards), `md` two thirds of it (controls), `sm` a
/// third (small parts) — the steps of the old scale at 18 px, so the default stays pixel-identical. Shape `none`
/// collapses all of them to 0.
/// A squircle corner spans this many radii along its sides (I281): with the same ends as a circle's quarter it sits closer
/// to the corner, so its steps are this much longer to read as round as the radius the user set.
pub const SQUIRCLE_SCALE: f64 = 1.3;

pub fn radius_steps(shape: Shape, r: f64) -> [(&'static str, f64); 5] {
    let r = match shape {
        Shape::None => 0.0,
        Shape::Rounded => r.max(0.0),
        Shape::Squircle => r.max(0.0) * SQUIRCLE_SCALE,
    };
    [
        ("none", 0.0),
        ("sm", (r / 3.0).round()),
        ("md", (r * 2.0 / 3.0).round()),
        ("lg", r.round()),
        ("full", if r == 0.0 { 0.0 } else { 999.0 }),
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
        MotionProfile::Calm | MotionProfile::Expressive => 1.0,
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
        // Caelestia's (M3 expressive) default spatial curve on arrival, its accelerating exit.
        MotionProfile::Expressive => [
            ("enter", [0.38, 1.21, 0.22, 1.0]),
            ("exit", [0.3, 0.0, 0.8, 0.15]),
            ("emphasized", [0.05, 0.7, 0.1, 1.0]),
            ("continuous", [0.2, 0.0, 0.0, 1.0]),
        ],
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
        Material::Translucent => (axes.opacity.clamp(0.0, 1.0), axes.blur),
    };
    t.insert("color.surface_alpha".into(), json!(alpha));
    t.insert("blur".into(), json!(blur));

    // --- scales ---
    for (n, v) in space_scale(axes.density) {
        px(&mut t, &format!("space.{n}"), v);
    }
    for (n, v) in radius_steps(axes.shape, axes.radius) {
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
    // Always emitted; the frontend reads it only under `squircle`. Rounded to 4 places so the document stays stable.
    t.insert(
        "shape.squircle_k".into(),
        json!((squircle_k(axes.squircle) * 1e4).round() / 1e4),
    );
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
    // Icons (K42, W41): the shell's subset when installed, else Material Symbols, else "" and components draw their
    // text glyph instead (Shōjiki: no tofu boxes for a font that is not there). Line chrome takes the sharp cut first,
    // so a subset of the other cut never beats the full family of this one.
    let (chain, full): (&[&str], &[&str]) = if axes.chrome == Chrome::Line {
        (
            &[
                ICON_SUBSET_SHARP,
                ICON_FAMILY_SHARP,
                ICON_SUBSET,
                ICON_FAMILY,
            ],
            &[ICON_FAMILY_SHARP, ICON_FAMILY],
        )
    } else {
        (&[ICON_SUBSET, ICON_FAMILY], &[ICON_FAMILY])
    };
    let icons = chain
        .iter()
        .copied()
        .find(|f| fonts.is_installed(f))
        .unwrap_or("");
    // `font.icons_fallback` (row 446): the full family of the same cut, where a name the subset lacks is drawn
    // (Icon.qml). "" when the theme's family is the full one already, or no full family is installed.
    let fallback = if icons == ICON_SUBSET || icons == ICON_SUBSET_SHARP {
        full.iter()
            .copied()
            .find(|f| fonts.is_installed(f))
            .unwrap_or("")
    } else {
        ""
    };
    t.insert("font.icons".into(), json!(icons));
    t.insert("font.icons_fallback".into(), json!(fallback));
    // Icon cut per chrome (K45): keycaps take filled, heavier symbols; line chrome hairline ones.
    let (icon_fill, icon_weight) = match axes.chrome {
        Chrome::Keycap => (1, 600),
        Chrome::Soft => (0, 400),
        Chrome::Line => (0, 300),
        Chrome::Flat => (0, 400),
    };
    t.insert("icon.fill".into(), json!(icon_fill));
    t.insert("icon.weight".into(), json!(icon_weight));

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
            MotionProfile::Expressive => "expressive",
            MotionProfile::Calm => "calm",
            MotionProfile::Lively => "lively",
            MotionProfile::None => "none",
        }),
    );
    // K74: how surfaces move. `timed` (expressive): Caelestia's curves (M3 expressive, read 2026-10-28 from
    // caelestia-dots/shell `plugin/src/Caelestia/Config/tokens.hpp`) — a surface grows out of its edge on the default
    // spatial curve (500 ms, overshoots ~6 %) and folds back on the emphasized one (400 ms), its content fading on the
    // effects curve; `spring` (calm, lively): the spring family below; `none`: cuts. Curves are QML `bezierCurve` lists
    // (segments of c1, c2, end; the last point 1, 1).
    t.insert(
        "motion.kind".into(),
        json!(match axes.motion {
            MotionProfile::Expressive => "timed",
            MotionProfile::None => "none",
            _ => "spring",
        }),
    );
    for (n, ms) in [
        ("open", 500.0),
        ("close", 400.0),
        ("fast", 350.0),
        ("effects", 200.0),
    ] {
        t.insert(
            format!("motion.timed.{n}_ms"),
            json!(duration_ms(ms, axes.motion, axes.motion_speed)),
        );
    }
    t.insert(
        "motion.timed.open_curve".into(),
        json!([0.38, 1.21, 0.22, 1.0, 1.0, 1.0]),
    );
    t.insert(
        "motion.timed.close_curve".into(),
        json!([
            0.05,
            0.0,
            2.0 / 15.0,
            0.06,
            1.0 / 6.0,
            0.4,
            5.0 / 24.0,
            0.82,
            0.25,
            1.0,
            1.0,
            1.0
        ]),
    );
    t.insert(
        "motion.timed.fast_curve".into(),
        json!([0.42, 1.67, 0.21, 0.9, 1.0, 1.0]),
    );
    t.insert(
        "motion.timed.effects_curve".into(),
        json!([0.34, 0.8, 0.34, 1.0, 1.0, 1.0]),
    );

    // Springs (K42): overshoot of arrivals (QML Easing.OutBack amplitude) and a spring for
    // retargetable morphs (QML SpringAnimation `spring`/`damping`). Calm settles without a bounce,
    // keycap chrome bounces more, `none` has no spring at all (`motion.spring.on` false).
    let overshoot = match (axes.motion, axes.chrome) {
        (MotionProfile::None, _) => 0.0,
        (MotionProfile::Calm | MotionProfile::Expressive, _) => 0.6,
        (MotionProfile::Lively, Chrome::Flat) => 1.4,
        (MotionProfile::Lively, Chrome::Keycap) => 2.2,
        (MotionProfile::Lively, Chrome::Soft) => 1.0,
        (MotionProfile::Lively, Chrome::Line) => 0.4,
    };
    t.insert("motion.spring.overshoot".into(), json!(overshoot));
    let (spring, damping) = match axes.motion {
        MotionProfile::None => (0.0, 1.0),
        // (Expressive: what is not moved on its curves yet springs as calm does.)
        MotionProfile::Calm | MotionProfile::Expressive => (4.0, 0.45),
        MotionProfile::Lively => (3.2, 0.26),
    };
    let sk = axes.motion_speed.clamp(0.25, 4.0);
    t.insert(
        "motion.spring.on".into(),
        json!(axes.motion != MotionProfile::None),
    );
    t.insert(
        "motion.spring.spring".into(),
        json!((spring * sk * 100.0).round() / 100.0),
    );
    t.insert("motion.spring.damping".into(), json!(damping));
    // W34 (rows 360, 363): squash and stretch mid-morph and the neck's wobble on landing — lively only (docs/ux/motion.md).
    t.insert(
        "motion.spring.squash".into(),
        json!(if axes.motion == MotionProfile::Lively {
            0.06
        } else {
            0.0
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

    // Chrome (K42, K45): what a block is made of. Every chrome is a set of widths and colours, so a
    // renderer draws all four from the same tokens (rule 4).
    //   flat   — a fill, nothing round it.
    //   keycap — an outline in `chrome.line`, a ring between outline and fill, a hard shadow in
    //            the line colour straight down that the block sinks into while pressed.
    //   soft   — a hairline rim (`chrome.outline_color`, faint), a soft drop shadow below; pressed
    //            blocks shrink to `chrome.press_scale`.
    //   line   — an ink outline in the palette's outline role, no shadow, no ring.
    // `chrome.groups`: bar groups stand as blocks of their own instead of sitting on one strip.
    struct Ch {
        style: &'static str,
        outline: f64,
        ring: f64,
        shadow: f64,
        soft: f64,
        soft_dy: f64,
        press_scale: f64,
        groups: bool,
        /// `frame.outline` under `theme.frame_outline = auto` (I303): on where blocks are drawn in ink (keycap, line).
        frame_outline: bool,
    }
    let ch = match axes.chrome {
        Chrome::Flat => Ch {
            style: "flat",
            outline: 0.0,
            ring: 0.0,
            shadow: 0.0,
            soft: 0.0,
            soft_dy: 0.0,
            press_scale: 0.97,
            groups: false,
            frame_outline: false,
        },
        Chrome::Keycap => Ch {
            style: "keycap",
            outline: 2.0,
            ring: 3.0,
            shadow: 4.0,
            soft: 0.0,
            soft_dy: 0.0,
            press_scale: 1.0,
            groups: true,
            frame_outline: true,
        },
        Chrome::Soft => Ch {
            style: "soft",
            outline: 1.0,
            ring: 0.0,
            shadow: 0.0,
            soft: 18.0,
            soft_dy: 6.0,
            press_scale: 0.96,
            groups: true,
            frame_outline: false,
        },
        Chrome::Line => Ch {
            style: "line",
            outline: 1.0,
            ring: 0.0,
            shadow: 0.0,
            soft: 0.0,
            soft_dy: 0.0,
            press_scale: 1.0,
            groups: true,
            frame_outline: true,
        },
    };
    let keycap = axes.chrome == Chrome::Keycap;
    t.insert("chrome.style".into(), json!(ch.style));
    px(&mut t, "chrome.outline", ch.outline);
    px(&mut t, "chrome.ring", ch.ring);
    px(&mut t, "chrome.shadow", ch.shadow);
    px(&mut t, "chrome.soft", ch.soft);
    px(&mut t, "chrome.soft_dy", ch.soft_dy);
    t.insert("chrome.press_scale".into(), json!(ch.press_scale));
    t.insert("chrome.groups".into(), json!(ch.groups));
    let frame_outline = match axes.frame_outline {
        FrameOutline::Auto => ch.frame_outline,
        FrameOutline::On => true,
        FrameOutline::Off => false,
    };
    t.insert("frame.outline".into(), json!(frame_outline));
    t.insert("outline.ink".into(), json!(axes.outline_ink));
    // W57 (K78): the surfaces' elevation shadows. Automatic: where blocks lift (keycap, soft) the surfaces do too; flat
    // and line looks read as deliberately shadowless.
    let elevation = match axes.elevation.as_str() {
        m @ ("off" | "static" | "follow") => m,
        _ if ch.shadow > 0.0 || ch.soft > 0.0 => "static",
        _ => "off",
    };
    t.insert("elevation.mode".into(), json!(elevation));
    t.insert("elevation.strength".into(), json!(axes.elevation_strength));
    t.insert(
        "elevation.pointer".into(),
        json!(axes.elevation_pointer && elevation == "follow"),
    );
    col(&mut t, "chrome.line", g("line"));
    col(&mut t, "chrome.ring_color", g("ring"));
    // The outline's colour and opacity: ink for keycaps, the outline role for line chrome, a faint
    // light rim for soft chrome (glass edges catch the light), nothing for flat.
    let (oc, oa) = match axes.chrome {
        Chrome::Keycap => (g("line"), 1.0),
        Chrome::Line => (g("outline"), 1.0),
        Chrome::Soft => (
            if p.dark { WHITE } else { g("on_surface") },
            if p.dark { 0.16 } else { 0.10 },
        ),
        Chrome::Flat => (g("outline_variant"), 0.0),
    };
    col(&mut t, "chrome.outline_color", oc);
    t.insert("chrome.outline_alpha".into(), json!(oa));
    col(&mut t, "chrome.soft_color", g("shadow"));
    t.insert(
        "chrome.soft_alpha".into(),
        json!(if p.dark { 0.45 } else { 0.18 }),
    );
    // Keycap type is heavier: the rounded families it is paired with read thin at 500.
    if keycap {
        for (n, w) in [("regular", 500), ("medium", 700), ("bold", 800)] {
            t.insert(format!("font.weight.{n}"), json!(w));
        }
    }
    // Selected states are tonal, not the accent itself, so a panel full of selections does not
    // read as an alarm (I51); data marks get their own roles apart from the accent (I63).
    // Deeper on dark grounds, so the text on it stays the light on_surface.
    let sel = g("accent").mix(g("surface_container_high"), if p.dark { 0.8 } else { 0.72 });
    col(&mut t, "color.selected", sel);
    // `at_least` picks the ink's extreme by the container's lightness and can fall short of AA when that extreme is the
    // weaker one (yorha light: 2.99 before this); `ensure_contrast` then nudges it to the other extreme. A passing ink is
    // returned as it was, so the palettes that met AA keep their values.
    let on_sel = ensure_contrast(
        at_least(
            g("on_surface"),
            sel,
            4.5,
            if sel.luminance() > 0.4 { BLACK } else { WHITE },
        ),
        sel,
        4.5,
    );
    col(&mut t, "color.on_selected", on_sel);
    // K66 (row 104, DESIGN-SYSTEM §7): a quick tile's on state as components. The container is the selected role, the badge
    // the accent, and the label's ink meets AA on the container (as color.on_selected does). The frontend's fallbacks are
    // these same roles, so a palette that sends none looks as it did before.
    col(&mut t, "quick.tile.on.bg", sel);
    // The badge is a graphic on the container (WCAG 1.4.11, I204): the accent, nudged to 3:1 where it falls short (dark
    // wa-iro read 2.39:1); a passing accent is returned as it was, so the looks keep their badge.
    col(
        &mut t,
        "quick.tile.on.badge",
        ensure_contrast(g("accent"), sel, 3.0),
    );
    col(&mut t, "quick.tile.on.fg", on_sel);
    col(&mut t, "color.data.1", g("secondary"));
    col(&mut t, "color.data.2", g("tertiary"));
    col(&mut t, "color.data.3", g("warning"));
    col(&mut t, "color.data.4", g("accent"));
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

    // K67: the shadow vector at the look's own strength, straight down; the daemon resolves it again with the user's
    // strength, direction and light (`shadow_tokens`), so a theme without those (previews, the mock) still has all three.
    shadow_tokens(&mut t, &Shadow::default());

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

/// K67: how a theme's drop shadows fall — the user's strength (0 none, 1 the look's own, 2 twice as long and dark), the
/// direction they fall in (degrees round the screen, 180 straight down, 135 down to the right), and, when they follow the
/// light, the light's direction (`light.dir`: toward the light, x right, y down, z toward the viewer).
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct Shadow {
    pub strength: f64,
    pub angle: f64,
    pub light: Option<[f64; 3]>,
}

impl Default for Shadow {
    fn default() -> Self {
        Shadow {
            strength: 1.0,
            angle: 180.0,
            light: None,
        }
    }
}

/// The light's height (degrees) at which a shadow that follows it is the look's own length (the light's default).
const SHADOW_REST_ELEVATION: f64 = 40.0;
/// How much shorter (a high light) and longer (a low one) a followed shadow gets than at [`SHADOW_REST_ELEVATION`].
const SHADOW_FOLLOW_RANGE: (f64, f64) = (0.5, 2.0);
/// A soft shadow's opacity never passes this, whatever the strength (a shadow, never a solid blot).
const SOFT_ALPHA_MAX: f64 = 0.9;

/// The unit vector (x right, y down) of a shadow falling at `angle` degrees round the screen (0 up, 90 right, 180 down).
pub fn shadow_unit(angle: f64) -> [f64; 2] {
    let a = angle.to_radians();
    [a.sin(), -a.cos()]
}

/// A shadow that follows the light: its unit direction (away from the light) and how much longer than the look's own it
/// is (`tan 40° / tan elevation`, within 0.5…2). `None` for a light straight overhead (no direction to fall in).
pub fn shadow_from_light(dir: [f64; 3]) -> Option<([f64; 2], f64)> {
    let len = dir[0].hypot(dir[1]);
    if len < 1e-3 {
        return None;
    }
    let elevation = dir[2].atan2(len).max(1f64.to_radians());
    let k = (SHADOW_REST_ELEVATION.to_radians().tan() / elevation.tan())
        .clamp(SHADOW_FOLLOW_RANGE.0, SHADOW_FOLLOW_RANGE.1);
    Some(([-dir[0] / len, -dir[1] / len], k))
}

/// The shadow's vector in px for a shadow of the look's own `length` (`chrome.shadow` or `chrome.soft_dy`).
pub fn shadow_vector(length: f64, s: &Shadow) -> [f64; 2] {
    let strength = s.strength.clamp(0.0, 2.0);
    let (u, k) = s
        .light
        .and_then(shadow_from_light)
        .unwrap_or_else(|| (shadow_unit(s.angle), 1.0));
    // Two decimals (renderers round where a hard edge needs whole px); never a -0.
    let r = |v: f64| {
        let v = (v * 100.0).round() / 100.0;
        if v == 0.0 { 0.0 } else { v }
    };
    [
        r(u[0] * length * k * strength),
        r(u[1] * length * k * strength),
    ]
}

/// K67: `shadow.dx`, `shadow.dy` — the vector every block and surface casts its shadow along: the keycap's hard shadow
/// and its press sink, or the soft shadow's offset — and `shadow.alpha_scale` (the soft shadow's opacity × this, kept
/// under [`SOFT_ALPHA_MAX`]). Read from the chrome tokens already in `t`; a chrome without a shadow gets 0, 0.
pub fn shadow_tokens(t: &mut TokenMap, s: &Shadow) {
    let num = |k: &str| t.get(k).and_then(Value::as_f64).unwrap_or(0.0);
    let (hard, soft_dy, soft_alpha) = (
        num("chrome.shadow"),
        num("chrome.soft_dy"),
        num("chrome.soft_alpha"),
    );
    let length = if hard > 0.0 { hard } else { soft_dy };
    let [dx, dy] = shadow_vector(length, s);
    let strength = s.strength.clamp(0.0, 2.0);
    let alpha = if soft_alpha > 0.0 {
        strength.min(SOFT_ALPHA_MAX / soft_alpha)
    } else {
        strength
    };
    t.insert("shadow.dx".into(), json!(dx));
    t.insert("shadow.dy".into(), json!(dy));
    t.insert(
        "shadow.alpha_scale".into(),
        json!((alpha * 100.0).round() / 100.0),
    );
}

#[cfg(test)]
mod shadow_tests {
    use super::*;

    fn close(a: [f64; 2], b: [f64; 2]) -> bool {
        (a[0] - b[0]).abs() < 0.011 && (a[1] - b[1]).abs() < 0.011
    }

    #[test]
    fn the_default_is_todays_shadow_straight_down() {
        assert_eq!(shadow_vector(4.0, &Shadow::default()), [0.0, 4.0]);
        assert_eq!(shadow_vector(6.0, &Shadow::default()), [0.0, 6.0]);
        assert_eq!(shadow_vector(0.0, &Shadow::default()), [0.0, 0.0]);
        let mut t = TokenMap::new();
        t.insert("chrome.shadow".into(), json!(4));
        t.insert("chrome.soft_dy".into(), json!(0));
        shadow_tokens(&mut t, &Shadow::default());
        assert_eq!(t["shadow.dx"], json!(0.0));
        assert_eq!(t["shadow.dy"], json!(4.0));
        assert_eq!(t["shadow.alpha_scale"], json!(1.0));
    }

    #[test]
    fn angle_and_strength_turn_and_scale_the_vector() {
        let at = |angle, strength| {
            shadow_vector(
                4.0,
                &Shadow {
                    strength,
                    angle,
                    light: None,
                },
            )
        };
        let d = 4.0 * std::f64::consts::FRAC_1_SQRT_2;
        assert!(close(at(135.0, 1.0), [d, d]), "{:?}", at(135.0, 1.0));
        assert!(close(at(225.0, 1.0), [-d, d]));
        assert!(close(at(90.0, 1.0), [4.0, 0.0]));
        assert!(close(at(0.0, 1.0), [0.0, -4.0]));
        assert_eq!(at(180.0, 2.0), [0.0, 8.0]);
        assert_eq!(at(180.0, 0.5), [0.0, 2.0]);
        assert_eq!(at(135.0, 0.0), [0.0, 0.0]);
        // Out of range strengths are clamped, as the schema's range is.
        assert_eq!(at(180.0, 5.0), [0.0, 8.0]);
    }

    #[test]
    fn a_followed_shadow_falls_away_from_the_light_and_lengthens_as_it_sinks() {
        let light = |angle: f64, elevation: f64| {
            let (a, e) = (angle.to_radians(), elevation.to_radians());
            [a.sin() * e.cos(), -a.cos() * e.cos(), e.sin()]
        };
        let follow = |angle, elevation| Shadow {
            strength: 1.0,
            angle: 180.0,
            light: Some(light(angle, elevation)),
        };
        let d = 4.0 * std::f64::consts::FRAC_1_SQRT_2;
        // The light from the top left (315) casts down to the right (135); from the top right (45) down to the left.
        assert!(close(shadow_vector(4.0, &follow(315.0, 40.0)), [d, d]));
        assert!(close(shadow_vector(4.0, &follow(45.0, 40.0)), [-d, d]));
        // From the top at the rest height: exactly the static default.
        assert!(close(shadow_vector(4.0, &follow(0.0, 40.0)), [0.0, 4.0]));
        // Low light: longer, capped at twice; high light: shorter, at least half.
        let low = shadow_vector(4.0, &follow(0.0, 10.0));
        let lower = shadow_vector(4.0, &follow(0.0, 5.0));
        let high = shadow_vector(4.0, &follow(0.0, 80.0));
        assert!(
            close(low, [0.0, 8.0]) && close(lower, [0.0, 8.0]),
            "{low:?}"
        );
        assert!(close(high, [0.0, 2.0]), "{high:?}");
        let mid = shadow_vector(4.0, &follow(0.0, 25.0))[1];
        assert!(mid > 4.0 && mid < 8.0, "{mid}");
        // Straight overhead there is no direction: the static angle decides.
        let over = Shadow {
            light: Some([0.0, 0.0, 1.0]),
            angle: 135.0,
            ..Shadow::default()
        };
        assert!(close(shadow_vector(4.0, &over), [d, d]));
    }

    #[test]
    fn soft_alpha_scales_with_strength_and_stays_a_shadow() {
        let mut t = TokenMap::new();
        t.insert("chrome.shadow".into(), json!(0));
        t.insert("chrome.soft_dy".into(), json!(6));
        t.insert("chrome.soft_alpha".into(), json!(0.45));
        let mut s = Shadow {
            strength: 2.0,
            ..Shadow::default()
        };
        shadow_tokens(&mut t, &s);
        assert_eq!(t["shadow.dy"], json!(12.0));
        assert_eq!(t["shadow.alpha_scale"], json!(2.0));
        t.insert("chrome.soft_alpha".into(), json!(0.6));
        shadow_tokens(&mut t, &s);
        assert_eq!(t["shadow.alpha_scale"], json!(1.5));
        s.strength = 0.0;
        shadow_tokens(&mut t, &s);
        assert_eq!(t["shadow.dy"], json!(0.0));
        assert_eq!(t["shadow.alpha_scale"], json!(0.0));
    }
}

#[cfg(test)]
mod badge_tests {
    use crate::color::{Rgb, contrast};
    use crate::{ContrastLevel, FakeFonts, Scheme, Source, ThemeInput, bundled_names, resolve};

    /// I204: a quick tile's accent badge is a graphic on its on-state container, so it reaches 3:1 there in every palette,
    /// scheme and contrast level.
    #[test]
    fn quick_tile_badge_reaches_3_to_1_on_its_container() {
        let fonts = FakeFonts::new(&["Inter", "Noto Sans CJK JP"]);
        for name in bundled_names() {
            for scheme in [Scheme::Dark, Scheme::Light] {
                for contrast_level in [
                    ContrastLevel::Standard,
                    ContrastLevel::Medium,
                    ContrastLevel::High,
                ] {
                    let input = ThemeInput {
                        source: Source::Palette(name.into()),
                        scheme,
                        contrast: contrast_level,
                        ..Default::default()
                    };
                    let t = resolve(&input, &fonts).unwrap().tokens;
                    let c = |k: &str| Rgb::parse(t[k].as_str().unwrap()).unwrap();
                    let r = contrast(c("quick.tile.on.badge"), c("quick.tile.on.bg"));
                    assert!(
                        r >= 3.0,
                        "{name} {scheme:?} {contrast_level:?}: badge {r:.2}"
                    );
                    // Its icon (the on-accent ink, filled) stays a readable graphic on the nudged badge.
                    let i = contrast(c("color.on_accent"), c("quick.tile.on.badge"));
                    assert!(
                        i >= 3.0,
                        "{name} {scheme:?} {contrast_level:?}: badge icon {i:.2}"
                    );
                }
            }
        }
    }
}

#[cfg(test)]
mod icon_font_tests {
    use super::*;
    use crate::{FakeFonts, ThemeInput, resolve};

    fn icon_tokens(chrome: Chrome, installed: &[&str]) -> TokenMap {
        let mut i = ThemeInput::default();
        i.axes.chrome = chrome;
        resolve(&i, &FakeFonts::new(installed)).unwrap().tokens
    }

    /// W41 (rows 445, 446): the subset is preferred and its cut comes first under line chrome; the full family of the same
    /// cut is the fallback for a name the subset lacks, and the full family itself names no fallback.
    #[test]
    fn icon_font_prefers_the_subset_and_names_a_full_fallback() {
        let all = [
            ICON_SUBSET,
            ICON_FAMILY,
            ICON_SUBSET_SHARP,
            ICON_FAMILY_SHARP,
        ];
        let t = icon_tokens(Chrome::Soft, &all[..]);
        assert_eq!(t["font.icons"], ICON_SUBSET);
        assert_eq!(t["font.icons_fallback"], ICON_FAMILY);
        let t = icon_tokens(Chrome::Line, &all[..]);
        assert_eq!(t["font.icons"], ICON_SUBSET_SHARP);
        assert_eq!(t["font.icons_fallback"], ICON_FAMILY_SHARP);
        // A subset of the other cut never beats the full family of this one.
        let t = icon_tokens(
            Chrome::Line,
            &[ICON_SUBSET, ICON_FAMILY_SHARP, ICON_FAMILY][..],
        );
        assert_eq!(t["font.icons"], ICON_FAMILY_SHARP);
        assert_eq!(t["font.icons_fallback"], "");
        // The full families alone: as before the subset, nothing to fall back to.
        let t = icon_tokens(Chrome::Flat, &[ICON_FAMILY][..]);
        assert_eq!(t["font.icons"], ICON_FAMILY);
        assert_eq!(t["font.icons_fallback"], "");
        // The subset alone: a name it lacks has no family to fall back to (Icon.qml draws the glyph).
        let t = icon_tokens(Chrome::Flat, &[ICON_SUBSET][..]);
        assert_eq!(t["font.icons"], ICON_SUBSET);
        assert_eq!(t["font.icons_fallback"], "");
        // No icon font: components draw their glyphs.
        let t = icon_tokens(Chrome::Line, &[][..]);
        assert_eq!(t["font.icons"], "");
        assert_eq!(t["font.icons_fallback"], "");
    }
}
