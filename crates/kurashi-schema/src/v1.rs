//! Config schema v1 — the first real tree. Small on purpose; the lead extends it.
//!
//! Axes follow DESIGN-SYSTEM §3, a11y modes §5 (they force axes via `overridden_by`, which the
//! daemon resolves as `forced:accessibility`), the island ARCHITECTURE §5/§6.

use std::sync::OnceLock;

use crate::{FontFamilies, KurashiSchema, Registry, strings};

pub const VERSION: u32 = 2;

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
    #[kurashi(nested)]
    pub idle: Idle,
    #[kurashi(nested)]
    pub night_light: NightLight,
    #[kurashi(nested)]
    pub recorder: Recorder,
    #[kurashi(nested)]
    pub dock: Dock,
    #[kurashi(nested)]
    pub sidebar: Sidebar,
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
    /// Style
    /// A fixed preset that recreates one aesthetic: a look, a palette, the scheme, density and motion. Applying a
    /// style resets your appearance changes; what you change afterwards shows as a difference from it. It changes how
    /// things look, never where they are (K53).
    #[kurashi(default = "washi".to_owned(), choices_from = "styles", section = "colors")]
    pub style: String,
    /// Look
    /// The form and feel of the interface without its colours: chrome, corners, material, motion, type and its
    /// art — sekai's toy keycaps, washi's paper and ink, win95's bevels. The style picks one; pick another to
    /// override it (K53).
    #[kurashi(default = "kanso".to_owned(), choices_from = "looks", section = "colors")]
    pub look: String,
    #[kurashi(nested, section = "colors")]
    pub colors: Colors,
    #[kurashi(nested, section = "shape")]
    pub shape: Shape,
    #[kurashi(nested, section = "material")]
    pub material: Material,
    /// Chrome
    /// How blocks are drawn: flat fills; keycaps with an ink outline, a light ring and a hard shadow
    /// they sink into when pressed; soft blocks with a faint rim and a soft shadow; or ink lines
    /// (K42, K45).
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
    /// Apps that follow
    /// Write the shell's colours for these apps whenever the theme changes: GTK, Qt, terminals, niri (K49). Each one
    /// needs one line in its own config to read the file; Settings shows it.
    #[kurashi(default = strings(&[]), choices_from = "theme.export", section = "colors")]
    pub export: Vec<String>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, KurashiSchema)]
pub enum Chrome {
    Flat,
    /// Keycap
    Keycap,
    /// Soft
    Soft,
    /// Lines
    Line,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, KurashiSchema)]
pub enum Scheme {
    /// Follow the system
    Auto,
    /// Follow the wallpaper
    Wallpaper,
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
    /// Colours only: the roles every surface is painted with, in light and dark. A style picks one; pick another to
    /// override it (K53).
    #[kurashi(default = "wa-iro".to_owned(), choices_from = "palettes")]
    pub palette: String,
    /// Light or dark
    /// Every palette has both. Follow the system's preference, the wallpaper's brightness, or pick one. Applying a
    /// style makes it follow the style; "Back to …" returns to your own choice (K55).
    #[kurashi(default = Scheme::Auto)]
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
    #[kurashi(default = false, requires = "theme.colors.scheme != light")]
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
    /// Screen corners
    /// Rounds the corners of every screen by this many pixels (0 = square, as the panel is).
    #[kurashi(default = 0, range = 0..=48, step = 2, unit = "px")]
    pub screen_corners: u32,
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
    /// Order
    /// The cards from top to bottom: `clock`, `calendar`, `media`, `weather`, and mods' cards as `mod:<id>:<name>`.
    /// A card that is not listed comes after the listed ones. The desk's edit mode writes it (K48).
    #[kurashi(default = strings(&["clock", "calendar", "media", "weather"]), advanced,
              requires = "desktop.enabled == true")]
    pub order: Vec<String>,
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
    /// Web search
    /// The address a query is searched at, `{}` standing for the query; empty = no web search row.
    #[kurashi(default = "https://duckduckgo.com/?q={}".to_owned())]
    pub web_search: String,
}

// --- idle (K47) ------------------------------------------------------------------------------

#[derive(Debug, Clone, PartialEq, KurashiSchema)]
#[kurashi(page = "power", section = "idle")]
pub struct Idle {
    /// Idle actions
    /// Dim, lock, turn the screens off and suspend after a time without input. Apps that play video
    /// or calls that are on keep the screen awake (they inhibit idle).
    #[kurashi(default = true)]
    pub enabled: bool,
    /// Dim after
    /// Lowers the brightness a little before locking. 0 = never.
    #[kurashi(default = 240, range = 0..=7200, step = 30, unit = "s", requires = "idle.enabled == true")]
    pub dim_after: u32,
    /// Lock after
    /// 0 = never.
    #[kurashi(default = 300, range = 0..=7200, step = 30, unit = "s", requires = "idle.enabled == true")]
    pub lock_after: u32,
    /// Screens off after
    /// 0 = never.
    #[kurashi(default = 600, range = 0..=7200, step = 30, unit = "s", requires = "idle.enabled == true")]
    pub screen_off_after: u32,
    /// Suspend after
    /// 0 = never.
    #[kurashi(default = 0, range = 0..=14400, step = 60, unit = "s", requires = "idle.enabled == true")]
    pub suspend_after: u32,
    /// Stay awake while media plays
    /// Music or video that plays keeps the screen on.
    #[kurashi(default = true, requires = "idle.enabled == true")]
    pub inhibit_while_media: bool,
}

// --- night light (K47) -----------------------------------------------------------------------

#[derive(Debug, Clone, Copy, PartialEq, Eq, KurashiSchema)]
pub enum NightSchedule {
    /// Always on
    Always,
    /// Between two times
    Manual,
    /// Sunset to sunrise
    Sun,
}

#[derive(Debug, Clone, PartialEq, KurashiSchema)]
#[kurashi(page = "power", section = "night_light")]
pub struct NightLight {
    /// Night light
    /// Warmer colours in the evening (wlsunset). Off by default.
    #[kurashi(default = false)]
    pub enabled: bool,
    /// Warmth
    /// Colour temperature at night; lower is warmer.
    #[kurashi(default = 4000, range = 1500..=6500, step = 100, unit = "K", requires = "night_light.enabled == true")]
    pub temperature: u32,
    /// Schedule
    /// When the night colours are on. Sunset to sunrise needs the weather mod's place.
    #[kurashi(default = NightSchedule::Manual, requires = "night_light.enabled == true")]
    pub schedule: NightSchedule,
    /// From
    /// Start of the night colours, as HH:MM.
    #[kurashi(default = "20:00".to_owned(), requires = "night_light.schedule == manual")]
    pub start: String,
    /// Until
    /// End of the night colours, as HH:MM.
    #[kurashi(default = "07:00".to_owned(), requires = "night_light.schedule == manual")]
    pub end: String,
}

// --- screen recorder (K47) -------------------------------------------------------------------

#[derive(Debug, Clone, Copy, PartialEq, Eq, KurashiSchema)]
pub enum RecorderBackend {
    /// Automatic
    Auto,
    /// gpu-screen-recorder
    GpuScreenRecorder,
    /// wf-recorder
    WfRecorder,
}

#[derive(Debug, Clone, PartialEq, KurashiSchema)]
#[kurashi(page = "power", section = "recorder")]
pub struct Recorder {
    /// Folder
    /// Where recordings are saved; empty = your Videos folder.
    #[kurashi(default = String::new())]
    pub directory: String,
    /// Record sound
    /// The desktop's sound goes into the recording.
    #[kurashi(default = true)]
    pub audio: bool,
    /// Recorder
    /// The program that records; automatic takes the first one installed.
    #[kurashi(default = RecorderBackend::Auto, advanced)]
    pub backend: RecorderBackend,
}

// --- app dock (K51) --------------------------------------------------------------------------

#[derive(Debug, Clone, Copy, PartialEq, Eq, KurashiSchema)]
pub enum DockEdge {
    Bottom,
    Left,
    Right,
}

#[derive(Debug, Clone, PartialEq, KurashiSchema)]
#[kurashi(page = "dock", section = "dock")]
pub struct Dock {
    /// App dock
    /// Your pinned apps and the running ones, at a screen edge.
    #[kurashi(default = false, per_output)]
    pub enabled: bool,
    /// Edge
    #[kurashi(default = DockEdge::Bottom, per_output, requires = "dock.enabled == true")]
    pub edge: DockEdge,
    /// Hide automatically
    /// The dock slides away and comes back when the pointer touches the edge.
    #[kurashi(default = true, requires = "dock.enabled == true")]
    pub autohide: bool,
    /// Pinned apps
    /// Desktop entry ids (e.g. firefox, org.gnome.Nautilus), in order. Right-click an app in the dock to pin it.
    #[kurashi(default = strings(&[]), requires = "dock.enabled == true")]
    pub pinned: Vec<String>,
    /// Icon size
    #[kurashi(default = 44, range = 24..=96, step = 2, unit = "px", requires = "dock.enabled == true")]
    pub icon_size: u32,
    /// Running apps
    /// Apps with windows that are not pinned show after the pinned ones.
    #[kurashi(default = true, requires = "dock.enabled == true")]
    pub show_running: bool,
}

// --- sidebars (W29, docs/ux/sidebar.md) ------------------------------------------------------

#[derive(Debug, Clone, Copy, PartialEq, Eq, KurashiSchema)]
pub enum SidebarStyle {
    /// Panel
    Panel,
    /// Floating
    Floating,
}

#[derive(Debug, Clone, PartialEq, KurashiSchema)]
#[kurashi(page = "sidebar", section = "sidebar")]
pub struct Sidebar {
    /// Style
    /// Panel: from the bar (or the screen edge) to the far edge, flush to its side, the inner corners rounded. Floating:
    /// the same column a gap away from every edge, every corner rounded, with the look's shadow.
    #[kurashi(default = SidebarStyle::Panel)]
    pub style: SidebarStyle,
    /// Width
    #[kurashi(default = 420, range = 320..=640, step = 10, unit = "px")]
    pub width: u32,
    /// Right sidebar
    /// Its sections, top to bottom: you and the session, the quick tiles, the levels, notifications, the month, what
    /// plays, and the mods' panels.
    #[kurashi(default = strings(&["header", "toggles", "sliders", "notifications", "calendar"]),
              choices_from = "sidebar.sections")]
    pub right: Vec<String>,
    /// Left sidebar
    /// Its tabs: the mods' panels (AI chat, tasks, …). A tab whose mod is not on is skipped. Empty: no left sidebar.
    #[kurashi(default = strings(&["mod:ai:ai"]), choices_from = "sidebar.tabs")]
    pub left: Vec<String>,
    /// Open from the bar
    /// The bar's quick settings button opens the right sidebar instead of the quick settings card.
    #[kurashi(default = false)]
    pub from_bar: bool,
    /// Buttons in the bar
    /// A button at each end of the bar opens that side's sidebar: the left one at the start, the right one at the end
    /// (left out while the quick settings button opens the right sidebar). The launcher's "> sidebar" and the keys
    /// open them too.
    #[kurashi(default = true)]
    pub bar_buttons: bool,
}
