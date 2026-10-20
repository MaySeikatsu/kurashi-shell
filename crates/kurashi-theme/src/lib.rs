//! Palette pipeline -> flat token map (the `theme` document). The daemon resolves every
//! colour, size, radius, font and duration here; renderers never compute colours
//! (CLAUDE.md rule 4). Input is a plain [`ThemeInput`]; no schema/config dependency.
//!
//! Pipeline order: source, scheme, oled, contrast, season, colorblind, wcag. Each stage is
//! a pure `Palette -> Palette` function in [`stages`] returning provenance notes.
//! Wallpaper extraction ([`Wallpaper::load`], [`stages::from_wallpaper`]) is blocking CPU:
//! callers run it on a blocking thread (`tokio::task::spawn_blocking`).

pub mod color;
pub mod fonts;
pub mod input;
pub mod palette;
pub mod season;
pub mod stages;
pub mod tokens;

pub use fonts::{FakeFonts, FcList, FontProvider};
pub use input::*;
pub use palette::{Palette, PaletteSet, bundled, bundled_names};
pub use tokens::TokenMap;

#[derive(Debug, thiserror::Error)]
pub enum ThemeError {
    #[error("palette parse error: {0}")]
    Parse(String),
    #[error("unknown palette `{0}`")]
    UnknownPalette(String),
    #[error("palette is missing required role `{0}`")]
    MissingRole(String),
    #[error("unknown role `{0}`")]
    UnknownRole(String),
    #[error("bad colour: {0}")]
    BadColor(String),
    #[error("image: {0}")]
    Image(String),
    #[error("override targets unknown token `{0}`")]
    UnknownOverride(String),
}

/// One stage's provenance line(s), e.g. `wcag: on_accent #f0e0e0 → #fff6f1 (3.9 → 4.6:1 …)`.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Note {
    pub stage: &'static str,
    pub text: String,
}

pub struct ThemeOutput {
    pub tokens: TokenMap,
    /// The final palette after all stages (exporters read this later).
    pub palette: Palette,
    pub notes: Vec<Note>,
}

/// Run the palette pipeline only (no scales/components).
pub fn resolve_palette(input: &ThemeInput) -> Result<(Palette, Vec<Note>), ThemeError> {
    let mut notes = vec![];
    let mut push = |stage: &'static str, v: Vec<String>| {
        notes.extend(v.into_iter().map(|text| Note { stage, text }));
    };
    let (set, n) = stages::source(&input.source)?;
    push("source", n);
    let s = stages::scheme(set, input.scheme)?;
    push("scheme", s.notes);
    let s = stages::oled(s.palette, input.oled);
    push("oled", s.notes);
    let s = stages::contrast_level(s.palette, input.contrast);
    push("contrast", s.notes);
    let s = stages::season(s.palette, input.season);
    push("season", s.notes);
    let s = stages::colorblind(s.palette, input.colorblind);
    push("colorblind", s.notes);
    let s = stages::wcag(s.palette, input.wcag);
    push("wcag", s.notes);
    Ok((s.palette, notes))
}

/// Full resolution: palette pipeline, axis scales, component tokens, overrides.
pub fn resolve(input: &ThemeInput, fonts: &dyn FontProvider) -> Result<ThemeOutput, ThemeError> {
    let (palette, mut notes) = resolve_palette(input)?;
    let (tokens, tn) = tokens::build(&palette, &input.axes, fonts, &input.overrides)?;
    notes.extend(tn.into_iter().map(|text| Note {
        stage: if text.starts_with("override") {
            "override"
        } else {
            "font"
        },
        text,
    }));
    Ok(ThemeOutput {
        tokens,
        palette,
        notes,
    })
}

/// Decor packs' recipes (K42, K45, DESIGN-SYSTEM §4): the axis values a pack recommends, applied
/// by the daemon at the `theme:<pack>` layer, under everything the user sets. `None` for no pack.
/// A recipe names `theme.*` keys only: a decor changes how things look, never where they are —
/// layout (bar edge and height, desk cards, island placement) belongs to the user and to profiles.
pub fn decor_recipe(name: &str) -> Option<Vec<(&'static str, serde_json::Value)>> {
    use serde_json::json;
    match name {
        // After SekaiPop: pop keycaps on a pastel ground, bouncy springs, rounded type.
        "sekai" => Some(vec![
            ("theme.colors.palette", json!("sekai")),
            ("theme.colors.scheme", json!("light")),
            ("theme.chrome", json!("keycap")),
            ("theme.motion.profile", json!("lively")),
            ("theme.material.kind", json!("solid")),
            ("theme.shape.corners", json!("rounded")),
            ("theme.shape.radius_scale", json!(1.25)),
            (
                "theme.typography.family",
                json!([
                    "Nunito",
                    "M PLUS Rounded 1c",
                    "Noto Sans CJK JP",
                    "sans-serif"
                ]),
            ),
        ]),
        // After Vitreus/pleamar: frosted glass, soft squircles with a light rim and a soft shadow,
        // springs that settle.
        "glass" => Some(vec![
            ("theme.colors.palette", json!("kanso")),
            ("theme.colors.scheme", json!("dark")),
            ("theme.chrome", json!("soft")),
            ("theme.motion.profile", json!("lively")),
            ("theme.material.kind", json!("glass")),
            ("theme.material.opacity", json!(0.62)),
            ("theme.shape.corners", json!("squircle")),
            ("theme.shape.radius_scale", json!(1.4)),
            (
                "theme.typography.family",
                json!(["Inter", "Noto Sans CJK JP", "sans-serif"]),
            ),
        ]),
        // A terminal's honesty: ink outlines on mono, square corners, sharp icons, quick and calm.
        "terminal" => Some(vec![
            ("theme.colors.palette", json!("kanso")),
            ("theme.colors.scheme", json!("dark")),
            ("theme.chrome", json!("line")),
            ("theme.motion.profile", json!("calm")),
            ("theme.motion.speed", json!(1.6)),
            ("theme.material.kind", json!("solid")),
            ("theme.shape.corners", json!("none")),
            (
                "theme.typography.family",
                json!(["JetBrains Mono", "Noto Sans Mono CJK JP", "monospace"]),
            ),
        ]),
        // Paper and ink: wa-iro on a light ground, fine ink lines, small corners, a serif hand.
        "washi" => Some(vec![
            ("theme.colors.palette", json!("wa-iro")),
            ("theme.colors.scheme", json!("light")),
            ("theme.chrome", json!("line")),
            ("theme.motion.profile", json!("calm")),
            ("theme.material.kind", json!("solid")),
            ("theme.shape.corners", json!("rounded")),
            ("theme.shape.radius_scale", json!(0.5)),
            (
                "theme.typography.family",
                json!(["Noto Serif", "Noto Serif CJK JP", "serif"]),
            ),
        ]),
        _ => None,
    }
}

/// Names of the decor packs that have a recipe, in the order Settings shows them.
pub const DECORS: [&str; 4] = ["sekai", "glass", "terminal", "washi"];

/// What a decor would look like (K45, I104): the tokens a preview card draws, resolved from the
/// pack's recipe alone — the user's own values left out, so the card shows the pack itself. The
/// font is the first installed family of the pack's chain (Shōjiki). `None` for no recipe.
pub fn decor_preview(name: &str, fonts: &dyn FontProvider) -> Option<serde_json::Value> {
    use serde_json::{Value, json};
    let recipe = decor_recipe(name)?;
    let mut input = ThemeInput::default();
    for (key, v) in &recipe {
        let s = v.as_str().unwrap_or_default();
        let f = v.as_f64().unwrap_or_default();
        match *key {
            "theme.colors.palette" => input.source = Source::Palette(s.into()),
            "theme.colors.scheme" => {
                input.scheme = if s == "light" {
                    Scheme::Light
                } else {
                    Scheme::Dark
                }
            }
            "theme.chrome" => {
                input.axes.chrome = match s {
                    "keycap" => Chrome::Keycap,
                    "soft" => Chrome::Soft,
                    "line" => Chrome::Line,
                    _ => Chrome::Flat,
                }
            }
            "theme.material.kind" => {
                input.axes.material = match s {
                    "solid" => Material::Solid,
                    "glass" => Material::Glass,
                    _ => Material::Translucent,
                }
            }
            "theme.material.opacity" => input.axes.opacity = f,
            "theme.shape.corners" => {
                input.axes.shape = match s {
                    "none" => Shape::None,
                    "squircle" => Shape::Squircle,
                    _ => Shape::Rounded,
                }
            }
            "theme.shape.radius_scale" => input.axes.radius_scale = f,
            "theme.typography.family" => {
                input.axes.font_chain = v
                    .as_array()
                    .map(|a| {
                        a.iter()
                            .filter_map(|x| x.as_str().map(String::from))
                            .collect()
                    })
                    .unwrap_or_default()
            }
            _ => {}
        }
    }
    let t = resolve(&input, fonts).ok()?.tokens;
    let keys = [
        "color.surface",
        "color.surface_container",
        "color.surface_container_high",
        "color.on_surface",
        "color.on_surface_variant",
        "color.accent",
        "color.on_accent",
        "color.selected",
        "color.secondary",
        "color.tertiary",
        "color.surface_alpha",
        "chrome.style",
        "chrome.outline",
        "chrome.ring",
        "chrome.shadow",
        "chrome.soft",
        "chrome.soft_dy",
        "chrome.line",
        "chrome.ring_color",
        "chrome.outline_color",
        "chrome.outline_alpha",
        "chrome.soft_color",
        "chrome.soft_alpha",
        "radius.sm",
        "radius.lg",
        "font.family",
        "font.weight.bold",
    ];
    let tokens: serde_json::Map<String, Value> = keys
        .iter()
        .filter_map(|k| t.get(*k).map(|v| ((*k).to_owned(), v.clone())))
        .collect();
    Some(json!({ "name": name, "tokens": tokens }))
}
