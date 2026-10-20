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
    #[kurashi(nested)]
    pub notifications: Notifications,
    #[kurashi(nested)]
    pub launcher: Launcher,
    #[kurashi(nested)]
    pub clock: Clock,
    #[kurashi(nested)]
    pub desktop: Desktop,
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
    /// Look
    /// A decor pack: recommends colours, chrome, motion, corners and fonts in one choice. Your own
    /// settings still win over what it recommends (K42).
    #[kurashi(default = Decor::None, section = "colors")]
    pub decor: Decor,
    #[kurashi(nested, section = "colors")]
    pub colors: Colors,
    #[kurashi(nested, section = "shape")]
    pub shape: Shape,
    #[kurashi(nested, section = "material")]
    pub material: Material,
    /// Chrome
    /// How blocks are drawn: flat fills, or keycaps with an ink outline, a light ring and a hard
    /// shadow they sink into when pressed (K42).
    #[kurashi(default = Chrome::Flat, section = "shape",
              overridden_by = "a11y.high_contrast => flat")]
    pub chrome: Chrome,
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
pub enum Decor {
    /// Your own
    None,
    /// Sekai (pop keycaps)
    Sekai,
    /// Glass (frosted)
    Glass,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, KurashiSchema)]
pub enum Chrome {
    Flat,
    /// Keycap
    Keycap,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, KurashiSchema)]
pub enum Scheme {
    Dark,
    Light,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, KurashiSchema)]
pub enum Contrast {
    Standard,
    Medium,
    High,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, KurashiSchema)]
pub enum Colorblind {
    /// Off
    None,
    Protanopia,
    Deuteranopia,
    Tritanopia,
}

#[derive(Debug, Clone, PartialEq, KurashiSchema)]
pub struct Colors {
    /// Palette
    /// Colour palette (bundled: wa-iro, kanso, high-contrast; mods may add more).
    #[kurashi(default = "wa-iro".to_owned(), choices_from = "palettes")]
    pub palette: String,
    /// Scheme
    /// Dark or light surfaces.
    #[kurashi(default = Scheme::Dark)]
    pub scheme: Scheme,
    /// Contrast
    /// Raises the contrast between surfaces and text.
    #[kurashi(default = Contrast::Standard, overridden_by = "a11y.high_contrast => high")]
    pub contrast: Contrast,
    /// Colour-blind adjustment
    /// Shifts accent colours so they stay distinguishable.
    #[kurashi(default = Colorblind::None)]
    pub colorblind: Colorblind,
    /// Seasonal tint (旬)
    /// A slight seasonal drift of hues following the 24 solar terms.
    #[kurashi(default = false, advanced)]
    pub season: bool,
    /// Pure black (OLED)
    /// Pure-black grounds on dark schemes.
    #[kurashi(default = false, requires = "theme.colors.scheme == dark")]
    pub oled: bool,
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
    right = "island.pin",
    scroll_up = "island.prev",
    scroll_down = "island.next"
))]
pub struct IslandInstance {
    /// Faces
    /// Faces this island may show, in cycling order.
    #[kurashi(
        default = strings(&["clock", "media", "notifications"]),
        choices_from = "island.faces"
    )]
    pub faces: Vec<String>,
    /// Default face
    /// Face shown when nothing more relevant is happening.
    #[kurashi(default = "clock".to_owned(), choices_from = "island.faces")]
    pub default: String,
    /// Transient duration
    /// How long a transient face (volume, brightness, notification) stays before falling back.
    #[kurashi(default = 5, range = 1..=60, unit = "s")]
    pub ttl: u32,
}

// --- notifications ---------------------------------------------------------------------------

#[derive(Debug, Clone, PartialEq, KurashiSchema)]
#[kurashi(page = "notifications", section = "server")]
pub struct Notifications {
    /// Notification server
    /// Receive desktop notifications. Never takes over from another running notification daemon.
    #[kurashi(default = true, restart)]
    pub server: bool,
    /// Do not disturb
    /// Store notifications silently; critical ones still show.
    #[kurashi(default = false)]
    pub dnd: bool,
    /// History size
    /// How many notifications are kept.
    #[kurashi(default = 200, range = 10..=2000, step = 10, advanced, restart)]
    pub history_max: u32,
}

// --- clock ------------------------------------------------------------------------------------

#[derive(Debug, Clone, Copy, PartialEq, Eq, KurashiSchema)]
pub enum WeekStart {
    Auto,
    Monday,
    Sunday,
    Saturday,
}

#[derive(Debug, Clone, PartialEq, KurashiSchema)]
#[kurashi(page = "island", section = "clock")]
pub struct Clock {
    /// First day of the week
    /// The calendar's first column; automatic follows the language (Sunday for Japanese, Monday otherwise).
    #[kurashi(default = WeekStart::Auto)]
    pub week_start: WeekStart,
    /// Week numbers
    /// Show ISO week numbers beside the calendar's rows.
    #[kurashi(default = false)]
    pub week_numbers: bool,
}

// --- desktop widgets (K43) --------------------------------------------------------------------

#[derive(Debug, Clone, Copy, PartialEq, Eq, KurashiSchema)]
pub enum Side {
    Left,
    Right,
}

#[derive(Debug, Clone, PartialEq, KurashiSchema)]
#[kurashi(page = "desktop", section = "widgets")]
pub struct Desktop {
    /// Desktop widgets
    /// Cards on the desktop under your windows: the clock, the month, what is playing, the weather.
    #[kurashi(default = false, per_output)]
    pub enabled: bool,
    /// Side
    /// The screen side the cards stand on.
    #[kurashi(default = Side::Right, per_output, requires = "desktop.enabled == true")]
    pub side: Side,
    /// Clock
    /// The time in big keys, with the date.
    #[kurashi(default = true, requires = "desktop.enabled == true")]
    pub clock: bool,
    /// Calendar
    /// This month, today marked.
    #[kurashi(default = true, requires = "desktop.enabled == true")]
    pub calendar: bool,
    /// Now playing
    /// The song that plays, with its controls; hidden while nothing plays.
    #[kurashi(default = true, requires = "desktop.enabled == true")]
    pub media: bool,
    /// Weather
    /// Today's weather, while the weather mod is on and has a place.
    #[kurashi(default = true, requires = "desktop.enabled == true")]
    pub weather: bool,
}

// --- launcher --------------------------------------------------------------------------------

#[derive(Debug, Clone, PartialEq, KurashiSchema)]
#[kurashi(page = "launcher", section = "apps")]
pub struct Launcher {
    /// Terminal command
    /// Prefix for apps that need a terminal, e.g. foot -e.
    #[kurashi(default = strings(&["foot", "-e"]), restart)]
    pub terminal: Vec<String>,
    /// Separate app scopes
    /// Start apps in their own systemd scope so they outlive the shell.
    #[kurashi(default = true, advanced, restart)]
    pub systemd_scope: bool,
}
