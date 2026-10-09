//! Config schema v1 — the first real tree. Small on purpose; the lead extends it.
//!
//! Axes follow DESIGN-SYSTEM §3, a11y modes §5 (they force axes via `overridden_by`, which the
//! daemon resolves as `forced:accessibility`), the island ARCHITECTURE §5/§6.

use std::sync::OnceLock;

use crate::{FontFamilies, KurashiSchema, Registry, strings};

pub const VERSION: u32 = 1;

/// The v1 registry, built once. Building is checked by tests, so this never panics in practice.
pub fn registry() -> &'static Registry {
    static REG: OnceLock<Registry> = OnceLock::new();
    REG.get_or_init(|| {
        Registry::build::<Config>(VERSION)
            .unwrap_or_else(|errs| panic!("schema v{VERSION} is inconsistent: {errs:?}"))
    })
}

#[derive(Debug, Clone, PartialEq, KurashiSchema)]
pub struct Config {
    #[kurashi(nested)]
    pub bar: Bar,
    #[kurashi(nested)]
    pub theme: Theme,
    #[kurashi(nested)]
    pub a11y: A11y,
    #[kurashi(nested)]
    pub island: Island,
}

// --- bar ---------------------------------------------------------------------------------------

#[derive(Debug, Clone, Copy, PartialEq, Eq, KurashiSchema)]
pub enum Edge {
    Top,
    Bottom,
    Left,
    Right,
}

#[derive(Debug, Clone, PartialEq, KurashiSchema)]
#[kurashi(page = "bar", section = "layout")]
pub struct Bar {
    /// Show bar
    /// Whether this output gets a bar at all.
    #[kurashi(default = true, per_output)]
    pub enabled: bool,
    /// Edge
    /// Screen edge the bar is anchored to.
    #[kurashi(default = Edge::Top, per_output, requires = "bar.enabled == true")]
    pub edge: Edge,
    /// Height
    /// Thickness of the bar in logical pixels (its width when anchored left or right).
    #[kurashi(default = 32, range = 16..=96, step = 2, unit = "px", per_output,
              requires = "bar.enabled == true")]
    pub height: u32,
}

// --- theme axes ----------------------------------------------------------------------------------

#[derive(Debug, Clone, PartialEq, KurashiSchema)]
#[kurashi(page = "appearance")]
pub struct Theme {
    #[kurashi(nested, section = "shape")]
    pub shape: Shape,
    #[kurashi(nested, section = "material")]
    pub material: Material,
    #[kurashi(nested, section = "motion")]
    pub motion: Motion,
    /// Density
    /// Scales spacing and control sizes everywhere.
    #[kurashi(default = Density::Regular, section = "layout")]
    pub density: Density,
    #[kurashi(nested, section = "typography")]
    pub typography: Typography,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, KurashiSchema)]
pub enum Corners {
    /// Square
    None,
    Rounded,
    Squircle,
}

#[derive(Debug, Clone, PartialEq, KurashiSchema)]
pub struct Shape {
    /// Corners
    /// Corner style of bars, popups and the island.
    #[kurashi(default = Corners::Rounded)]
    pub corners: Corners,
    /// Corner radius scale
    /// Multiplies every corner radius token.
    #[kurashi(default = 1.0, range = 0.0..=2.0, step = 0.05, advanced,
              requires = "theme.shape.corners != none")]
    pub radius_scale: f64,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, KurashiSchema)]
#[kurashi(i18n = "material")]
pub enum MaterialKind {
    Solid,
    Translucent,
    /// Glass (blurred)
    Glass,
}

#[derive(Debug, Clone, PartialEq, KurashiSchema)]
pub struct Material {
    /// Material
    /// Surface material of shell chrome.
    #[kurashi(default = MaterialKind::Translucent,
              overridden_by = "a11y.reduce_transparency => solid",
              overridden_by = "a11y.high_contrast => solid")]
    pub kind: MaterialKind,
    /// Opacity
    /// Opacity of translucent and glass surfaces.
    #[kurashi(default = 0.85, range = 0.3..=1.0, step = 0.01,
              requires = "theme.material.kind != solid",
              overridden_by = "a11y.reduce_transparency => 1.0")]
    pub opacity: f64,
    /// Background blur
    /// Blur what is behind glass surfaces. Forced off when the compositor cannot blur.
    #[kurashi(
        default = true,
        capability = "blur",
        requires = "theme.material.kind == glass",
        overridden_by = "a11y.reduce_transparency => false"
    )]
    pub blur: bool,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, KurashiSchema)]
pub enum MotionProfile {
    Calm,
    Lively,
    /// Off
    None,
}

#[derive(Debug, Clone, PartialEq, KurashiSchema)]
pub struct Motion {
    /// Motion
    /// Character of animations: calm, lively, or none at all.
    #[kurashi(default = MotionProfile::Calm, overridden_by = "a11y.reduce_motion => none")]
    pub profile: MotionProfile,
    /// Animation speed
    /// Multiplies every motion duration's speed (2.0 = twice as fast).
    #[kurashi(default = 1.0, range = 0.25..=3.0, step = 0.05, advanced,
              requires = "theme.motion.profile != none")]
    pub speed: f64,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, KurashiSchema)]
pub enum Density {
    Compact,
    Regular,
    Airy,
}

#[derive(Debug, Clone, PartialEq, KurashiSchema)]
pub struct Typography {
    /// Font family
    /// Fallback chain; the first installed family wins (resolved via fontconfig).
    #[kurashi(default = FontFamilies::of(&["Inter", "Noto Sans CJK JP", "sans-serif"]))]
    pub family: FontFamilies,
    /// Text scale
    /// Multiplies every type size token.
    #[kurashi(default = 1.0, range = 0.75..=2.0, step = 0.05,
              overridden_by = "a11y.large_text => 1.25")]
    pub scale: f64,
}

// --- accessibility -------------------------------------------------------------------------------

#[derive(Debug, Clone, PartialEq, KurashiSchema)]
#[kurashi(page = "accessibility", section = "modes")]
pub struct A11y {
    /// Reduce motion
    /// Turns animations off (forces the motion profile to none).
    #[kurashi(default = false)]
    pub reduce_motion: bool,
    /// Reduce transparency
    /// Makes every surface solid and disables blur.
    #[kurashi(default = false)]
    pub reduce_transparency: bool,
    /// High contrast
    /// Solid surfaces and a high-contrast palette.
    #[kurashi(default = false)]
    pub high_contrast: bool,
    /// Large text
    /// Raises the text scale to 125 %.
    #[kurashi(default = false)]
    pub large_text: bool,
}

// --- island --------------------------------------------------------------------------------------

#[derive(Debug, Clone, PartialEq, KurashiSchema)]
#[kurashi(page = "island")]
pub struct Island {
    #[kurashi(nested, section = "main")]
    pub main: IslandInstance,
}

#[derive(Debug, Clone, PartialEq, KurashiSchema)]
#[kurashi(input_slots(
    left = "island.expand",
    right = "island.face_picker",
    scroll_up = "island.face.prev",
    scroll_down = "island.face.next"
))]
pub struct IslandInstance {
    /// Faces
    /// Faces this island may show, in cycling order.
    #[kurashi(default = strings(&["clock", "media", "notifications"]))]
    pub faces: Vec<String>,
    /// Default face
    /// Face shown when nothing more relevant is happening.
    #[kurashi(default = "clock".to_owned())]
    pub default: String,
    /// Transient duration
    /// How long a transient face (volume, notification) stays before falling back.
    #[kurashi(default = 5, range = 1..=60, unit = "s")]
    pub ttl: u32,
}
