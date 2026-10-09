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
    Translucent,
    /// Translucent plus a blur request (the daemon forces `blur` off if unsupported).
    Glass,
}

#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub enum MotionProfile {
    Calm,
    Lively,
    None,
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
    pub radius_scale: f64,
    pub material: Material,
    pub opacity: f64,
    pub blur: bool,
    pub motion: MotionProfile,
    pub motion_speed: f64,
    pub density: Density,
    /// Type scale multiplier (accessibility `large_text` raises it).
    pub type_scale: f64,
    pub font_chain: Vec<String>,
    pub font_chain_jp: Vec<String>,
}

impl Default for Axes {
    fn default() -> Self {
        Axes {
            shape: Shape::Rounded,
            radius_scale: 1.0,
            material: Material::Glass,
            opacity: 0.82,
            blur: true,
            motion: MotionProfile::Calm,
            motion_speed: 1.0,
            density: Density::Regular,
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
            axes: Axes::default(),
            overrides: BTreeMap::new(),
        }
    }
}
