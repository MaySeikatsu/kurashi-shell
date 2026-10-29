//! Palette pipeline -> flat token map (the `theme` document). The daemon resolves every
//! colour, size, radius, font and duration here; renderers never compute colours
//! (CLAUDE.md rule 4). Input is a plain [`ThemeInput`]; no schema/config dependency.
//!
//! Pipeline order: source, scheme, oled, contrast, season, colorblind, ink, wcag. Each stage is
//! a pure `Palette -> Palette` function in [`stages`] returning provenance notes.
//! Wallpaper extraction ([`Wallpaper::load`], [`stages::from_wallpaper`]) is blocking CPU:
//! callers run it on a blocking thread (`tokio::task::spawn_blocking`).

pub mod appearance;
pub mod color;
pub mod export;
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
    let s = stages::ink(s.palette, &input.ink);
    push("ink", s.notes);
    let s = stages::wcag(s.palette, input.wcag);
    push("wcag", s.notes);
    Ok((s.palette, notes))
}

/// Full resolution: palette pipeline, axis scales, component tokens, overrides.
pub fn resolve(input: &ThemeInput, fonts: &dyn FontProvider) -> Result<ThemeOutput, ThemeError> {
    let (palette, mut notes) = resolve_palette(input)?;
    let (tokens, tn) = tokens::build(
        &palette,
        &input.axes,
        &input.decor,
        input.contrast == ContrastLevel::High,
        fonts,
        &input.overrides,
    )?;
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

/// What a style or a look looks like (K45, I104, K53): the tokens a preview card draws, resolved from theme `entries`
/// alone (a pack's layer, [`appearance::layer`]) — the user's own values left out, so the card shows the pack itself.
/// The font is the first installed family of the pack's chain (Shōjiki). `None` when the tokens cannot be resolved.
pub fn preview(
    name: &str,
    entries: &[(String, serde_json::Value)],
    fonts: &dyn FontProvider,
) -> Option<serde_json::Value> {
    use serde_json::{Value, json};
    let mut input = ThemeInput::default();
    for (key, v) in entries {
        let s = v.as_str().unwrap_or_default();
        let f = v.as_f64().unwrap_or_default();
        match key.as_str() {
            "theme.colors.palette" => input.source = Source::Palette(s.into()),
            "theme.colors.scheme" => {
                input.scheme = if s == "light" {
                    Scheme::Light
                } else {
                    Scheme::Dark
                }
            }
            "theme.chrome" => input.axes.chrome = Chrome::parse(s),
            "theme.material.kind" => {
                input.axes.material = if s == "solid" {
                    Material::Solid
                } else {
                    Material::Translucent
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
            "theme.shape.radius" => input.axes.radius = f,
            "theme.colors.ink" if s != "palette" => input.ink = Ink::Named(s.into()),
            "theme.typography.family_jp" => {
                input.axes.font_chain_jp = v
                    .as_array()
                    .map(|a| {
                        a.iter()
                            .filter_map(|x| x.as_str().map(String::from))
                            .collect()
                    })
                    .unwrap_or_default()
            }
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
        "font.family_jp",
        "font.weight.bold",
    ];
    let tokens: serde_json::Map<String, Value> = keys
        .iter()
        .filter_map(|k| t.get(*k).map(|v| ((*k).to_owned(), v.clone())))
        .collect();
    Some(json!({ "name": name, "tokens": tokens }))
}

/// A style's preview card: its look, palette and recipe, with its frame and category.
pub fn style_preview(name: &str, fonts: &dyn FontProvider) -> Option<serde_json::Value> {
    use appearance::Kind;
    let style = appearance::find(Kind::Style, name)?;
    let look = appearance::find(Kind::Look, &style.look);
    let entries: Vec<_> = appearance::layer(Some(&style), look.as_ref())
        .into_iter()
        .map(|(k, v, _)| (k, v))
        .collect();
    let mut p = preview(name, &entries, fonts)?;
    p["category"] = style.category.into();
    p["look"] = style.look.into();
    p["palette"] = style.palette.into();
    p["frame"] = look.map(|l| l.frame).unwrap_or_default().into();
    Some(p)
}

/// A palette's preview card, drawn in the look in effect and `scheme` (K53: the palette is what differs).
pub fn palette_preview(
    name: &str,
    look: &str,
    scheme: &str,
    fonts: &dyn FontProvider,
) -> Option<serde_json::Value> {
    use appearance::Kind;
    let look = appearance::find(Kind::Look, look);
    let mut entries: Vec<_> = appearance::layer(None, look.as_ref())
        .into_iter()
        .map(|(k, v, _)| (k, v))
        .collect();
    entries.push(("theme.colors.palette".into(), name.into()));
    entries.push(("theme.colors.scheme".into(), scheme.into()));
    preview(name, &entries, fonts)
}

/// A look's preview card, drawn in `palette` and `scheme` (the ones in effect: a look has no colours of its own).
pub fn look_preview(
    name: &str,
    palette: &str,
    scheme: &str,
    fonts: &dyn FontProvider,
) -> Option<serde_json::Value> {
    use appearance::Kind;
    let look = appearance::find(Kind::Look, name)?;
    let mut entries: Vec<_> = appearance::layer(None, Some(&look))
        .into_iter()
        .map(|(k, v, _)| (k, v))
        .collect();
    entries.push(("theme.colors.palette".into(), palette.into()));
    entries.push(("theme.colors.scheme".into(), scheme.into()));
    let mut p = preview(name, &entries, fonts)?;
    p["category"] = look.category.into();
    p["frame"] = look.frame.into();
    Some(p)
}
