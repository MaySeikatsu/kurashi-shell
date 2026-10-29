//! Plain input structs. The lead maps resolved config onto these; this crate knows
//! nothing about the schema/config crates.

use std::collections::BTreeMap;
use std::path::{Path, PathBuf};

use serde_json::Value;

use crate::ThemeError;
use crate::palette::RawRoles;
use crate::season::Date;

#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub enum Scheme {
    Dark,
    Light,
}

#[derive(Clone, Copy, PartialEq, Eq, Debug, Default)]
pub enum ContrastLevel {
    #[default]
    Standard,
    Medium,
    High,
}

#[derive(Clone, Copy, PartialEq, Eq, Debug, Default)]
pub enum Colorblind {
    #[default]
    None,
    Protanopia,
    Deuteranopia,
    Tritanopia,
}

/// Downscaled RGBA image (row-major, 4 bytes per pixel). Decode + downscale off the
/// async runtime (`spawn_blocking`): [`Wallpaper::load`] is blocking I/O and CPU.
#[derive(Clone, Debug)]
pub struct Wallpaper {
    pub width: u32,
    pub height: u32,
    pub rgba: Vec<u8>,
}

impl Wallpaper {
    /// Decode `path` and downscale so the longest side is at most `max_side` (64 is plenty
    /// for colour extraction).
    pub fn load(path: &Path, max_side: u32) -> Result<Wallpaper, ThemeError> {
        let img =
            image::open(path).map_err(|e| ThemeError::Image(format!("{}: {e}", path.display())))?;
        let small = img.thumbnail(max_side, max_side).to_rgba8();
        Ok(Wallpaper {
            width: small.width(),
            height: small.height(),
            rgba: small.into_raw(),
        })
    }
}

#[derive(Clone, Debug)]
pub enum Source {
    /// `palette:<name>`: a bundled palette.
    Palette(String),
    /// `palette:<name>` from user TOML text (same format as `palettes/*.toml`).
    PaletteToml(String),
    /// `manual`: user-pinned roles (applies to whichever scheme is selected).
    Manual(RawRoles),
    /// `wallpaper`: material-colors extraction from pixels the caller decoded.
    Wallpaper(Wallpaper),
    /// `wallpaper` from the picture at this path. Decoded and extracted once per path, mtime and
    /// size (`stages::wallpaper_file`), so a resolve on every config change costs no decode.
    WallpaperFile(PathBuf),
}

#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub enum Shape {
    None,
    Rounded,
    Squircle,
}

#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub enum Material {
    Solid,
    /// See-through at `opacity`, blurred behind when `blur` is on (the daemon forces `blur` off if unsupported).
    /// Schema v7 (I297): this is what `glass` was; translucent without blur is the same with the switch off.
    Translucent,
}

/// `theme.frame_outline` (I303): `Auto` takes the chrome's own default (`tokens::build`'s chrome data).
#[derive(Clone, Copy, PartialEq, Eq, Debug, Default)]
pub enum FrameOutline {
    #[default]
    Auto,
    On,
    Off,
}

#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub enum MotionProfile {
    /// Timed curves after Caelestia's (M3 expressive): surfaces grow out of their edge and overshoot a little (K74).
    Expressive,
    Calm,
    Lively,
    None,
}

/// How a block of chrome is drawn (K42, K45): flat fills; keycaps — outline, light ring, fill and a
/// hard shadow straight down that the block sinks into when pressed; soft — a hairline rim and a
/// soft drop shadow, pressed blocks shrink a little; line — ink outlines, no shadow, crisp.
#[derive(Clone, Copy, PartialEq, Eq, Debug, Default)]
pub enum Chrome {
    #[default]
    Flat,
    Keycap,
    Soft,
    Line,
}

#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub enum Density {
    Compact,
    Regular,
    Airy,
}

#[derive(Clone, Debug)]
pub struct Axes {
    pub shape: Shape,
    /// The one corner radius (K74), px.
    pub radius: f64,
    /// `theme.shape.squircle` (I300): 0 nearly round … 1 nearly square; the `shape.squircle_k` token.
    pub squircle: f64,
    pub material: Material,
    pub opacity: f64,
    pub blur: bool,
    pub motion: MotionProfile,
    pub motion_speed: f64,
    pub density: Density,
    pub chrome: Chrome,
    pub frame_outline: FrameOutline,
    /// `theme.outline_ink` (session 17): passed through as the token `outline.ink` ("outline" | "text" | "accent"): the
    /// colour of every outline; looks set it in their recipe.
    pub outline_ink: String,
    /// `theme.material.elevation` (W57, K78): "auto" | "off" | "static" | "follow"; auto takes the chrome's default.
    pub elevation: String,
    pub elevation_strength: f64,
    pub elevation_pointer: bool,
    /// Type scale multiplier (accessibility `large_text` raises it).
    pub type_scale: f64,
    pub font_chain: Vec<String>,
    pub font_chain_jp: Vec<String>,
}

impl Default for Axes {
    fn default() -> Self {
        Axes {
            shape: Shape::Rounded,
            radius: 18.0,
            squircle: 0.77,
            material: Material::Translucent,
            opacity: 0.82,
            blur: true,
            motion: MotionProfile::Expressive,
            motion_speed: 1.0,
            density: Density::Regular,
            chrome: Chrome::Flat,
            frame_outline: FrameOutline::Auto,
            outline_ink: "outline".into(),
            elevation: "auto".into(),
            elevation_strength: 1.0,
            elevation_pointer: false,
            type_scale: 1.0,
            font_chain: ["Inter", "Noto Sans", "sans-serif"]
                .map(String::from)
                .to_vec(),
            font_chain_jp: [
                "Noto Sans CJK JP",
                "Noto Sans JP",
                "IPAexGothic",
                "sans-serif",
            ]
            .map(String::from)
            .to_vec(),
        }
    }
}

/// The text colour (K60): the palette's own, a named ink (`stages::ink_color`) or one colour for both schemes.
#[derive(Clone, Debug, Default, PartialEq)]
pub enum Ink {
    #[default]
    Palette,
    Named(String),
    Custom(crate::color::Rgb),
}

#[derive(Clone, Debug)]
pub struct ThemeInput {
    pub source: Source,
    pub scheme: Scheme,
    pub contrast: ContrastLevel,
    /// 旬 stage: `Some(date)` turns it on; off by default.
    pub season: Option<Date>,
    pub colorblind: Colorblind,
    /// AA enforcement (DESIGN-SYSTEM §2.6). On by default; turning it off is allowed but
    /// then nothing guarantees legibility.
    pub wcag: bool,
    /// Pure-black grounds on dark schemes (OLED).
    pub oled: bool,
    /// The text colour (K60).
    pub ink: Ink,
    pub axes: Axes,
    /// Per-surface / per-output overrides: component token key -> value
    /// (e.g. `"popup.bg" -> "#101010"`). Unknown keys are an error, never silent.
    pub overrides: BTreeMap<String, Value>,
}

impl Default for ThemeInput {
    fn default() -> Self {
        ThemeInput {
            source: Source::Palette("wa-iro".into()),
            scheme: Scheme::Dark,
            contrast: ContrastLevel::Standard,
            season: None,
            colorblind: Colorblind::None,
            wcag: true,
            oled: false,
            ink: Ink::Palette,
            axes: Axes::default(),
            overrides: BTreeMap::new(),
        }
    }
}
