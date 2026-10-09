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
