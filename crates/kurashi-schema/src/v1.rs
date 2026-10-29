//! Config schema v1 — the first real tree. Small on purpose; the lead extends it.
//!
//! Axes follow DESIGN-SYSTEM §3, a11y modes §5 (they force axes via `overridden_by`, which the
//! daemon resolves as `forced:accessibility`), the island ARCHITECTURE §5/§6.

use std::sync::OnceLock;

use crate::{Color, FontFamilies, KurashiSchema, Registry, strings};

pub const VERSION: u32 = 7;

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
    pub layout: Layout,
    #[kurashi(nested)]
    pub bar: Bar,
    #[kurashi(nested)]
    pub edges: Edges,
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
    #[kurashi(nested)]
    pub settings: SettingsApp,
    #[kurashi(nested)]
    pub keys: Keys,
}

// --- keyboard shortcuts (K64, I72) ---------------------------------------------------------------

#[derive(Debug, Clone, PartialEq, KurashiSchema)]
#[kurashi(page = "keys", section = "shortcuts")]
pub struct Keys {
    /// Shortcuts for the compositor
    /// Write these shortcuts into a file the compositor reads (niri: `kurashi-binds.kdl`, included from its config;
    /// Sway: `kurashi-binds.conf`, read on `swaymsg reload`; Hyprland: `kurashi-binds.conf`, sourced from `hyprland.conf`).
    /// Off: your compositor's own config keeps the keys, as now.
    #[kurashi(default = false)]
    pub write: bool,
    /// Launcher
    #[kurashi(default = "Mod+Space".to_owned(), requires = "keys.write == true")]
    pub launcher: String,
    /// Notification centre
    #[kurashi(default = "Mod+N".to_owned(), requires = "keys.write == true")]
    pub notifications: String,
    /// Right sidebar
    #[kurashi(default = "Mod+Shift+N".to_owned(), requires = "keys.write == true")]
    pub sidebar_right: String,
    /// Left sidebar
    #[kurashi(default = "Mod+A".to_owned(), requires = "keys.write == true")]
    pub sidebar_left: String,
    /// Quick settings
    #[kurashi(default = String::new(), requires = "keys.write == true")]
    pub quick: String,
    /// Session menu
    #[kurashi(default = "Mod+Shift+E".to_owned(), requires = "keys.write == true")]
    pub session_menu: String,
    /// Lock the screen
    #[kurashi(default = "Super+Alt+L".to_owned(), requires = "keys.write == true")]
    pub lock: String,
    /// Settings
    #[kurashi(default = String::new(), requires = "keys.write == true")]
    pub settings: String,
    /// Web dock
    #[kurashi(default = String::new(), requires = "keys.write == true")]
    pub webdock: String,
    /// Top bar
    #[kurashi(default = String::new(), requires = "keys.write == true")]
    pub bar_top: String,
    /// Bottom bar
    #[kurashi(default = String::new(), requires = "keys.write == true")]
    pub bar_bottom: String,
    /// Left bar
    #[kurashi(default = String::new(), requires = "keys.write == true")]
    pub bar_left: String,
    /// Right bar
    #[kurashi(default = String::new(), requires = "keys.write == true")]
    pub bar_right: String,
    /// Dock
    #[kurashi(default = String::new(), requires = "keys.write == true")]
    pub dock: String,
    /// Volume up
    #[kurashi(default = "XF86AudioRaiseVolume".to_owned(), requires = "keys.write == true")]
    pub volume_up: String,
    /// Volume down
    #[kurashi(default = "XF86AudioLowerVolume".to_owned(), requires = "keys.write == true")]
    pub volume_down: String,
    /// Mute
    #[kurashi(default = "XF86AudioMute".to_owned(), requires = "keys.write == true")]
    pub mute: String,
    /// Brightness up
    #[kurashi(default = "XF86MonBrightnessUp".to_owned(), requires = "keys.write == true")]
    pub brightness_up: String,
    /// Brightness down
    #[kurashi(default = "XF86MonBrightnessDown".to_owned(), requires = "keys.write == true")]
    pub brightness_down: String,
}

// --- the Settings app (K63) ------------------------------------------------------------------------

#[derive(Debug, Clone, Copy, PartialEq, Eq, KurashiSchema)]
#[kurashi(i18n = "settings_window")]
pub enum SettingsWindow {
    /// A window
    Window,
    /// A sheet over the desktop
    Sheet,
}

#[derive(Debug, Clone, PartialEq, KurashiSchema)]
#[kurashi(page = "appearance", section = "settings_app")]
pub struct SettingsApp {
    /// Settings opens as
    /// A normal window the compositor places and tiles, or a sheet the shell draws in the middle of the screen over a
    /// dimmed desktop — made of the shell's material and lit by its light, like every shell surface.
    #[kurashi(default = SettingsWindow::Window)]
    pub window: SettingsWindow,
}

// --- layout (K71, K72) ------------------------------------------------------------------------

#[derive(Debug, Clone, Copy, PartialEq, Eq, KurashiSchema)]
#[kurashi(i18n = "draw")]
pub enum DrawMode {
    /// Floating
    Floating,
    /// Dynamic
    Dynamic,
    /// Connected
    Connected,
}

/// A component's own draw mode; `auto` follows `layout.draw` (K71).
#[derive(Debug, Clone, Copy, PartialEq, Eq, KurashiSchema)]
#[kurashi(i18n = "draw_own")]
pub enum DrawChoice {
    /// Automatic
    Auto,
    /// Floating
    Floating,
    /// Dynamic
    Dynamic,
    /// Connected
    Connected,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, KurashiSchema)]
#[kurashi(i18n = "visibility")]
pub enum Visibility {
    /// Always shown
    Always,
    /// Show on hover
    Hover,
    /// Show on an empty desktop
    EmptyDesktop,
    /// Hidden (opens by key)
    Hidden,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, KurashiSchema)]
#[kurashi(i18n = "keep_space")]
pub enum KeepSpace {
    /// Automatic
    Auto,
    /// Always
    On,
    /// Never
    Off,
}

#[derive(Debug, Clone, PartialEq, KurashiSchema)]
#[kurashi(page = "layout", section = "layout")]
pub struct Layout {
    /// Draw mode
    /// How the bars, the dock, the sidebars and the island meet the screen's edges and each other. Floating: a gap away
    /// from everything, every corner rounded, with the look's shadow. Dynamic: flush on the edge (or the frame, or a
    /// bar), joined to it by rounded fillets. Connected: flush and joined with straight corners. A component set to its
    /// own mode keeps it.
    #[kurashi(default = DrawMode::Dynamic, since = 3)]
    pub draw: DrawMode,
    /// Reveal delay
    /// How long the pointer rests on an edge before what shows on hover comes out; an edge another screen touches waits
    /// twice as long.
    #[kurashi(default = 250, range = 0..=1000, step = 50, unit = "ms", since = 3)]
    pub reveal_delay: u32,
    #[kurashi(nested, section = "frame")]
    pub frame: Frame,
}

#[derive(Debug, Clone, PartialEq, KurashiSchema)]
pub struct Frame {
    /// Screen frame
    /// A band round the screen that the bars, the dock and the sidebars stand on, its inner corners rounded.
    #[kurashi(default = false, per_output, since = 3)]
    pub enabled: bool,
    /// Frame thickness
    #[kurashi(default = 8, range = 2..=32, step = 1, unit = "px", requires = "layout.frame.enabled == true",
              since = 3)]
    pub thickness: u32,
    /// Windows keep clear of the frame
    /// Windows tile inside the frame. Off: the frame is drawn over the windows' edges.
    #[kurashi(default = true, requires = "layout.frame.enabled == true", since = 3)]
    pub reserve: bool,
}

#[derive(Debug, Clone, PartialEq, KurashiSchema)]
#[kurashi(page = "layout", section = "layout")]
pub struct Bar {
    /// Bar height
    /// Thickness of every bar in logical pixels (its width on a left or right edge), and of an edge's modules.
    #[kurashi(default = 32, range = 16..=96, step = 2, unit = "px", per_output)]
    pub height: u32,
}

/// The top bar's zones: the left sidebar's button, the workspaces and the window list; the island; then the volume,
/// the mods' widgets, the recorder, the keyboard layout, the clock, quick settings, the tray and the right sidebar's
/// button — Bar.qml's rows before K71, so the default bar stays as it was.
pub const TOP_START: [&str; 3] = ["sidebar_left", "workspaces", "windows"];
pub const TOP_CENTER: [&str; 1] = ["island"];
pub const TOP_END: [&str; 8] = [
    "volume",
    "mods",
    "recorder",
    "keyboard",
    "clock",
    "quick",
    "tray",
    "sidebar_right",
];
const NO_MODULES: [&str; 0] = [];

/// One struct per edge, every key per output (K71): the derive's `default` is per leaf and the edges differ in theirs.
macro_rules! edge {
    ($name:ident, $section:literal, $bar:expr, $start:expr, $center:expr, $end:expr, $hidden:literal) => {
        #[derive(Debug, Clone, PartialEq, KurashiSchema)]
        #[kurashi(section = $section)]
        pub struct $name {
            /// Bar
            /// A bar stands on this edge and shows its modules. Without one, each part that lists modules shows them on
            /// their own at the edge.
            #[kurashi(default = $bar, per_output, since = 3)]
            pub bar: bool,
            /// Visibility
            /// Always shown; shown when the pointer rests on the edge; shown while the desktop is empty, else on
            /// hover; or hidden until a key, the command line or `layout.toggle` brings it out.
            #[kurashi(default = Visibility::Always, per_output, since = 3)]
            pub visibility: Visibility,
            /// Keep space
            /// Whether windows keep clear of it. Automatic keeps space only while it is always shown; Always keeps
            /// it while it hides on hover too.
            #[kurashi(default = KeepSpace::Auto, per_output, requires = $hidden, since = 3)]
            pub reserve: KeepSpace,
            /// Draw mode
            /// Automatic follows the layout's draw mode.
            #[kurashi(default = DrawChoice::Auto, per_output, since = 3)]
            pub draw: DrawChoice,
            /// Start
            /// The modules at the start of the edge (the left, or the top of a side edge), in order. "Other mods'
            /// widgets" stands for every mod widget no list names.
            #[kurashi(default = strings(&$start), choices_from = "modules", per_output, since = 3)]
            pub start: Vec<String>,
            /// Centre
            /// The modules in the middle of the edge, in order.
            #[kurashi(default = strings(&$center), choices_from = "modules", per_output, since = 3)]
            pub center: Vec<String>,
            /// End
            /// The modules at the end of the edge (the right, or the bottom of a side edge), in order.
            #[kurashi(default = strings(&$end), choices_from = "modules", per_output, since = 3)]
            pub end: Vec<String>,
        }
    };
}

edge!(
    TopEdge,
    "top_edge",
    true,
    TOP_START,
    TOP_CENTER,
    TOP_END,
    "edges.top.visibility != hidden"
);
edge!(
    BottomEdge,
    "bottom_edge",
    false,
    NO_MODULES,
    NO_MODULES,
    NO_MODULES,
    "edges.bottom.visibility != hidden"
);
edge!(
    LeftEdge,
    "left_edge",
    false,
    NO_MODULES,
    NO_MODULES,
    NO_MODULES,
    "edges.left.visibility != hidden"
);
edge!(
    RightEdge,
    "right_edge",
    false,
    NO_MODULES,
    NO_MODULES,
    NO_MODULES,
    "edges.right.visibility != hidden"
);

#[derive(Debug, Clone, PartialEq, KurashiSchema)]
#[kurashi(page = "layout")]
pub struct Edges {
    #[kurashi(nested)]
    pub top: TopEdge,
    #[kurashi(nested)]
    pub bottom: BottomEdge,
    #[kurashi(nested)]
    pub left: LeftEdge,
    #[kurashi(nested)]
    pub right: RightEdge,
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
    /// they sink into when pressed; soft blocks with a faint rim and a soft shadow; ink lines; or
    /// bevels, light and dark edges that press in (K42, K45, K80).
    // K80 amends K42: under high contrast a bevel stays (its lines carry pressed and sunken), drawn in the contrast ink;
    // every other chrome is forced flat (`except`: the daemon reads the value beneath the accessibility layer).
    #[kurashi(default = Chrome::Flat, section = "shape",
              overridden_by = "a11y.high_contrast => flat except bevel")]
    pub chrome: Chrome,
    /// Frame outline
    /// A line along the frame's inner edge and the sides of what is joined to it — bars, dock, sidebars — drawn in the
    /// chrome's style. Automatic is on for Keycap and Lines, off for Flat and Soft.
    // I303: the per-chrome default lives in kurashi-theme's chrome data (rule 4); the token is `frame.outline`.
    #[kurashi(default = FrameOutline::Auto, section = "shape", since = 7)]
    pub frame_outline: FrameOutline,
    /// Outline ink
    /// The colour of every outline the shell draws — blocks, the frame, the shapes joined to it: the chrome's own, the
    /// text's ink (as a hand-drawn look outlines its blocks), or the accent. Looks set it with the rest of their outline.
    #[kurashi(default = OutlineInk::Outline, section = "shape", since = 7)]
    pub outline_ink: OutlineInk,
    #[kurashi(nested, section = "motion")]
    pub motion: Motion,
    /// Density
    /// Scales spacing and control sizes everywhere.
    #[kurashi(default = Density::Regular, section = "layout")]
    pub density: Density,
    #[kurashi(nested, section = "typography")]
    pub typography: Typography,
    #[kurashi(nested, section = "texture")]
    pub texture: Texture,
    #[kurashi(nested, section = "light")]
    pub light: Light,
    #[kurashi(nested, section = "pen")]
    pub pen: Pen,
    /// Apps that follow
    /// Write the shell's colours for these apps whenever the theme changes: GTK, Qt, terminals, niri (K49). Each one
    /// needs one line in its own config to read the file; Settings shows it.
    #[kurashi(default = strings(&[]), choices_from = "theme.export", section = "colors")]
    pub export: Vec<String>,
    /// Icons for apps
    /// The icon theme the apps that follow use (GTK, Qt, KDE), written with their colours. "Leave as is" keeps each
    /// app's own choice (I183).
    #[kurashi(default = String::new(), choices_from = "icon_themes", section = "colors")]
    pub icon_theme: String,
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
    /// Bevel
    Bevel,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, KurashiSchema)]
#[kurashi(i18n = "outline_ink")]
pub enum OutlineInk {
    /// Outline
    Outline,
    /// Text
    Text,
    /// Accent
    Accent,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, KurashiSchema)]
#[kurashi(i18n = "frame_outline")]
pub enum FrameOutline {
    /// Automatic
    Auto,
    On,
    Off,
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
    /// The colours lean a little toward the season's own — winter blue, sakura, fresh green, maple — following the 24
    /// solar terms.
    #[kurashi(default = false, advanced)]
    pub season: bool,
    /// Pure black (OLED)
    /// Pure-black grounds on dark schemes.
    #[kurashi(default = false, requires = "theme.colors.scheme != light")]
    pub oled: bool,
    /// Text colour
    /// The colour of text and icons: the palette's own, or an ink — each with a shade for light and for dark — or a
    /// colour of your own. It is kept legible on every surface; the theme notes say when it had to be adjusted (K60).
    #[kurashi(default = Ink::Palette)]
    pub ink: Ink,
    /// Your text colour
    /// Used in light and dark alike, adjusted only as far as legibility needs.
    #[kurashi(default = Color::new("#2b4a8b"), requires = "theme.colors.ink == custom")]
    pub ink_custom: Color,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, KurashiSchema)]
pub enum Ink {
    /// The palette's
    Palette,
    /// Blue
    Blue,
    /// Black
    Black,
    /// Sepia
    Sepia,
    /// Red
    Red,
    /// Green
    Green,
    /// Violet
    Violet,
    /// Your own
    Custom,
}

// --- texture and light (K59) ---------------------------------------------------------------------

#[derive(Debug, Clone, Copy, PartialEq, Eq, KurashiSchema)]
#[kurashi(i18n = "texture")]
pub enum TextureKind {
    /// None
    None,
    /// Paper
    Paper,
    /// Dotted paper
    PaperDots,
    /// Lined paper
    PaperLines,
    /// Squared paper
    PaperGrid,
    /// Fabric
    Fabric,
    /// Wool
    Wool,
    /// Stone
    Stone,
    /// Print (halftone)
    Halftone,
    /// Scratched metal
    Metal,
    /// Leather
    Leather,
    /// Wood
    Wood,
    /// Oil paint (brush strokes)
    Paint,
    /// Brush strokes (bristles)
    Brush,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, KurashiSchema)]
#[kurashi(i18n = "crack_style")]
pub enum CrackStyle {
    /// Stone
    Stone,
    /// Glass
    Glass,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, KurashiSchema)]
#[kurashi(i18n = "texture_shadows")]
pub enum TextureShadows {
    /// Auto
    Auto,
    /// Off
    Off,
    /// On
    On,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, KurashiSchema)]
#[kurashi(i18n = "texture_sheet")]
pub enum TextureSheet {
    /// Carried
    Carried,
    /// Fixed
    Fixed,
    /// Separate
    Separate,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, KurashiSchema)]
#[kurashi(i18n = "texture_scope")]
pub enum TextureScope {
    /// The shell
    Shell,
    /// The wallpaper
    Wallpaper,
    /// The shell and the wallpaper
    ShellWallpaper,
    /// Everything (apps too)
    Everything,
}

#[derive(Debug, Clone, PartialEq, KurashiSchema)]
pub struct Texture {
    /// Material
    /// A relief the shell is made of — paper, fabric, stone, metal, leather, wood, brushed oil paint. It adds light and
    /// shade from the light below, never colours of its own (K59).
    #[kurashi(default = TextureKind::None, overridden_by = "a11y.high_contrast => none",
              overridden_by = "a11y.reduce_transparency => none")]
    pub kind: TextureKind,
    /// Where
    /// The shell's surfaces, the wallpaper (baked into the picture), both, or an overlay over everything, apps
    /// included — that one costs a full-screen layer, shows in screenshots and keeps fullscreen apps from the fastest
    /// path to the screen.
    #[kurashi(default = TextureScope::Shell, requires = "theme.texture.kind != none")]
    pub scope: TextureScope,
    /// Strength
    /// How strongly the relief reads; past 1 it is strong. Under text it is capped so text stays legible.
    #[kurashi(default = 0.5, range = 0.0..=2.0, step = 0.05, requires = "theme.texture.kind != none")]
    pub strength: f64,
    /// Depth
    /// How steep the relief is: deeper grain, threads and rulings, with longer shadows when the light is low.
    #[kurashi(default = 1.0, range = 0.5..=3.0, step = 0.05, requires = "theme.texture.kind != none")]
    pub depth: f64,
    /// Relief shadows
    /// Grain, threads and rulings cast short shadows away from the light, longer when the light is low. Auto: on for
    /// materials with real height (oil paint, brush strokes) and for styles that ask for it.
    #[kurashi(default = TextureShadows::Auto, requires = "theme.texture.kind != none")]
    pub shadows: TextureShadows,
    /// Scale
    /// The size of the material's grain, weave or rulings.
    #[kurashi(default = 1.0, range = 0.5..=3.0, step = 0.05, requires = "theme.texture.kind != none")]
    pub scale: f64,
    /// Wrinkles
    /// Crumples the material: folds and creases, as in crumpled paper or creased leather.
    #[kurashi(default = 0.0, range = 0.0..=1.0, step = 0.05, requires = "theme.texture.kind != none")]
    pub wrinkles: f64,
    /// Cracks
    /// Breaks the material: a network of fine cracks, as in old stone or broken glass.
    #[kurashi(default = 0.0, range = 0.0..=1.0, step = 0.05, requires = "theme.texture.kind != none")]
    pub cracks: f64,
    /// Crack pattern
    /// Stone: jagged, branching cracks. Glass: straight-edged shards.
    #[kurashi(default = CrackStyle::Stone, requires = "theme.texture.kind != none")]
    pub crack_style: CrackStyle,
    /// Ink and colour
    /// Print the rulings, dots and grain in faint colours of the palette. Off: relief only — rulings are pressed into
    /// the sheet, nothing is coloured.
    #[kurashi(default = true, requires = "theme.texture.kind != none")]
    pub tint: bool,
    /// Texture over text
    /// Let the relief run through text and icons too, as ink sinks into paper or is pressed into leather. Off keeps
    /// them crisp on the material.
    #[kurashi(default = false, requires = "theme.texture.kind != none")]
    pub text: bool,
    /// Texture over controls
    /// Let the relief run over buttons, sliders, switches and icons too, so the material reads through the whole
    /// interface. Pictures — album covers, wallpapers, avatars — stay untouched.
    #[kurashi(default = false, requires = "theme.texture.kind != none")]
    pub controls: bool,
    /// Sheet
    /// How the material sits on surfaces that move. Carried: a panel takes its texture along as it slides or grows and
    /// lands on the one continuous sheet. Fixed: the sheet stays put and surfaces slide over it. Separate: every surface
    /// is a sheet of its own.
    #[kurashi(default = TextureSheet::Carried, requires = "theme.texture.kind != none")]
    pub sheet: TextureSheet,
    #[kurashi(nested)]
    pub wallpaper: WallpaperTexture,
}

#[derive(Debug, Clone, PartialEq, KurashiSchema)]
pub struct WallpaperTexture {
    /// Own material for the wallpaper
    /// Give the wallpaper a material of its own instead of the shell's (it is baked into the picture).
    #[kurashi(
        default = false,
        requires = "theme.texture.scope != shell",
        requires = "theme.texture.scope != everything"
    )]
    pub own: bool,
    /// Wallpaper material
    /// The relief baked into the wallpaper.
    #[kurashi(default = TextureKind::Paper, requires = "theme.texture.wallpaper.own == true",
              requires = "theme.texture.scope != shell", requires = "theme.texture.scope != everything")]
    pub kind: TextureKind,
    /// Wallpaper strength
    /// How strongly the wallpaper's relief reads.
    #[kurashi(default = 0.5, range = 0.0..=2.0, step = 0.05, requires = "theme.texture.wallpaper.own == true",
              requires = "theme.texture.scope != shell", requires = "theme.texture.scope != everything")]
    pub strength: f64,
    /// Wallpaper scale
    /// The size of the wallpaper material's grain.
    #[kurashi(default = 1.0, range = 0.5..=3.0, step = 0.05, requires = "theme.texture.wallpaper.own == true",
              requires = "theme.texture.scope != shell", requires = "theme.texture.scope != everything")]
    pub scale: f64,
    /// Wallpaper wrinkles
    /// Crumples the wallpaper's material.
    #[kurashi(default = 0.0, range = 0.0..=1.0, step = 0.05, requires = "theme.texture.wallpaper.own == true",
              requires = "theme.texture.scope != shell", requires = "theme.texture.scope != everything")]
    pub wrinkles: f64,
    /// Wallpaper cracks
    /// Cracks in the wallpaper's material (the pattern is the shell's).
    #[kurashi(default = 0.0, range = 0.0..=1.0, step = 0.05, requires = "theme.texture.wallpaper.own == true",
              requires = "theme.texture.scope != shell", requires = "theme.texture.scope != everything")]
    pub cracks: f64,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, KurashiSchema)]
#[kurashi(i18n = "light")]
pub enum LightMode {
    /// Fixed
    Static,
    /// From the pointer
    Pointer,
    /// The sun
    Daytime,
    /// The wallpaper's light
    Wallpaper,
    /// Spotlight
    Spotlight,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, KurashiSchema)]
#[kurashi(i18n = "light_color")]
pub enum LightColor {
    /// Natural
    Natural,
    /// White
    White,
    /// Warm
    Warm,
    /// Cool
    Cool,
    /// Your own
    Custom,
}

#[derive(Debug, Clone, PartialEq, KurashiSchema)]
pub struct Light {
    /// Light
    /// Where the material's light comes from: a fixed direction, a lamp at the pointer (over the shell's surfaces;
    /// elsewhere it rests at the fixed direction), the sun of the day — sunrise from the left, sunset from the right,
    /// warm when it is low — the wallpaper's own light: a lamp at its brightest place, in its colour (K59) — or a
    /// spotlight: a lamp pinned at the screen's edge in the light's direction, its beam aimed at the pointer (K61).
    #[kurashi(default = LightMode::Static, requires = "theme.texture.kind != none")]
    pub mode: LightMode,
    /// Direction
    /// Where the fixed light comes from, in degrees round the screen: 0 from the top, 90 from the right, 315 from the
    /// top left.
    #[kurashi(default = 315, range = 0..=359, step = 1, unit = "°", requires = "theme.light.mode != daytime")]
    pub angle: u32,
    /// Height
    /// How high the light stands over the screen: low light makes long shadows and a deeper relief.
    #[kurashi(default = 40, range = 10..=80, step = 1, unit = "°", requires = "theme.light.mode != daytime")]
    pub elevation: u32,
    /// Beam width
    /// How wide the spotlight's beam is: narrow lights a small pool round the pointer, wide most of the screen.
    #[kurashi(default = 35, range = 10..=80, step = 1, unit = "°", requires = "theme.light.mode == spotlight")]
    pub beam: u32,
    /// Light colour
    /// The colour of the light's highlights. Natural: white, the sun's own, or the wallpaper's.
    #[kurashi(default = LightColor::Natural, requires = "theme.texture.kind != none")]
    pub color: LightColor,
    /// Your light colour
    /// The highlights' colour.
    #[kurashi(default = Color::new("#ffd9a0"), requires = "theme.light.color == custom")]
    pub color_custom: Color,
}

// --- pen (K62) -----------------------------------------------------------------------------------

#[derive(Debug, Clone, Copy, PartialEq, Eq, KurashiSchema)]
#[kurashi(i18n = "pen_line")]
pub enum PenLine {
    /// Solid
    Solid,
    /// Dotted
    Dotted,
    /// Dashed
    Dashed,
    /// Broken
    Broken,
    /// Rough
    Rough,
    /// Sketch
    /// Two light passes that drift a little, as a hand draws (kami's blocks).
    Sketch,
}

#[derive(Debug, Clone, PartialEq, KurashiSchema)]
pub struct Pen {
    /// Outline
    /// How outlines round blocks and surfaces are drawn: solid, dotted, dashed, broken — long strokes with gaps where
    /// the pen left the paper — or rough, a very uneven hand line.
    #[kurashi(default = PenLine::Solid, overridden_by = "a11y.high_contrast => solid")]
    pub line: PenLine,
    /// Pen pressure
    /// Outlines swell and thin along their length, as with a fountain pen.
    #[kurashi(default = 0.0, range = 0.0..=1.0, step = 0.05, overridden_by = "a11y.high_contrast => 0.0")]
    pub pressure: f64,
    /// Skips
    /// The pen skips now and then: small gaps in the outlines.
    #[kurashi(default = 0.0, range = 0.0..=1.0, step = 0.05, overridden_by = "a11y.high_contrast => 0.0")]
    pub breaks: f64,
    /// Ink flow
    /// The ink runs thinner in places: the outlines' opacity varies along them.
    #[kurashi(default = 0.0, range = 0.0..=1.0, step = 0.05, overridden_by = "a11y.high_contrast => 0.0")]
    pub fade: f64,
    /// Hand
    /// Straight lines and curves wander a little, as if drawn by hand.
    #[kurashi(default = 0.0, range = 0.0..=1.0, step = 0.05, overridden_by = "a11y.high_contrast => 0.0")]
    pub wobble: f64,
    /// Text: pen pressure
    /// Letters and icons swell and thin, as written with a fountain pen.
    #[kurashi(default = 0.0, range = 0.0..=1.0, step = 0.05, overridden_by = "a11y.high_contrast => 0.0")]
    pub text_pressure: f64,
    /// Text: skips
    /// Small breaks in letters and icons where the pen skipped.
    #[kurashi(default = 0.0, range = 0.0..=1.0, step = 0.05, overridden_by = "a11y.high_contrast => 0.0")]
    pub text_breaks: f64,
    /// Text: ink flow
    /// Letters and icons vary a little in opacity, as ink does.
    #[kurashi(default = 0.0, range = 0.0..=1.0, step = 0.05, overridden_by = "a11y.high_contrast => 0.0")]
    pub text_fade: f64,
    /// Text: hand
    /// Letters and icons wander a little off the straight line, as if written by hand.
    #[kurashi(default = 0.0, range = 0.0..=1.0, step = 0.05, overridden_by = "a11y.high_contrast => 0.0")]
    pub text_wobble: f64,
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
    /// Screen corners follow the radius
    /// The screen's corners take the corner radius, so the frame, the bars and the panels sit concentric in them (a
    /// square look leaves them square). Off: they take their own size below.
    #[kurashi(default = true, since = 5)]
    pub screen_corners_follow: bool,
    /// Screen corners
    /// Rounds the corners of every screen by this many pixels (0 = square, as the panel is).
    #[kurashi(default = 0, range = 0..=48, step = 2, unit = "px", requires = "theme.shape.screen_corners_follow == false")]
    pub screen_corners: u32,
    /// Corner radius
    /// The one radius every corner follows (K74): panels, cards and the island's views take it; buttons, toggles and
    /// smaller parts take steps of it; the frame's inner corners and the joins of the bar, the dock and the sidebars take
    /// it less the frame's thickness, so curves that sit inside one another stay concentric.
    #[kurashi(default = 18, range = 0..=48, step = 1, unit = "px", requires = "theme.shape.corners != none", since = 4)]
    pub radius: u32,
    /// Squircle curve
    /// How far a squircle's corners reach toward square: 0 is nearly round, 1 nearly square.
    // I300. Step 0.01, not 0.05: the default 0.77 is today's curve (k 0.88 in corner.js) and is off a 0.05 grid.
    #[kurashi(default = 0.77, range = 0.0..=1.0, step = 0.01, requires = "theme.shape.corners == squircle",
              since = 7)]
    pub squircle: f64,
}

// Schema v7 (I297): `glass` became `translucent` with its blur switch on; the name stays free for a liquid-glass
// material of its own.
#[derive(Debug, Clone, Copy, PartialEq, Eq, KurashiSchema)]
#[kurashi(i18n = "material")]
pub enum MaterialKind {
    Solid,
    Translucent,
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
    /// Opacity of translucent surfaces.
    #[kurashi(default = 0.85, range = 0.3..=1.0, step = 0.01,
              requires = "theme.material.kind != solid",
              overridden_by = "a11y.reduce_transparency => 1.0")]
    pub opacity: f64,
    /// Background blur
    /// Blur what is behind translucent surfaces. Forced off when the compositor cannot blur.
    #[kurashi(
        default = false,
        capability = "blur",
        requires = "theme.material.kind == translucent",
        overridden_by = "a11y.reduce_transparency => false"
    )]
    pub blur: bool,
    /// Shadows
    /// How strong the shadows under blocks and surfaces are: 0 draws none, 1 is the look's own, 2 twice as long and dark.
    #[kurashi(default = 1.0, range = 0.0..=2.0, step = 0.05,
              requires = "theme.chrome != flat", requires = "theme.chrome != line")]
    pub shadow: f64,
    /// Shadow direction
    /// Where shadows fall, in degrees round the screen: 180 straight down, 135 down to the right.
    #[kurashi(default = 180, range = 0..=359, step = 1, unit = "°", requires = "theme.material.shadow_follow == false",
              requires = "theme.chrome != flat", requires = "theme.chrome != line")]
    pub shadow_angle: u32,
    /// Shadows follow the light
    /// Shadows fall away from the material's light, longer when it stands low. A light that follows the pointer casts
    /// them from where it rests, so they never move with the pointer.
    #[kurashi(
        default = false,
        requires = "theme.texture.kind != none",
        requires = "theme.chrome != flat",
        requires = "theme.chrome != line"
    )]
    pub shadow_follow: bool,
    /// Elevation
    /// Smooth drop shadows under the shell's surfaces — sidebars, the dock, cards, the notification centre — that lift
    /// them off the desktop: a wide faint shadow all round and a softer one along the light. Automatic: on for keycap
    /// and soft looks, off for flat and line ones. Follow the light: they fall away from it, longer when it stands low.
    #[kurashi(default = Elevation::Auto, since = 7, overridden_by = "a11y.high_contrast => off")]
    pub elevation: Elevation,
    /// Elevation strength
    /// How deep the surfaces' shadows are: 0 none, 1 the look's own, 2 twice as far and dark (the blocks' shadows have
    /// their own strength above).
    #[kurashi(default = 1.0, range = 0.0..=2.0, step = 0.05, since = 7, requires = "theme.material.elevation != off")]
    pub elevation_strength: f64,
    /// Elevation follows the pointer
    /// While the light follows the pointer or the spotlight aims at it, the surfaces' shadows turn away from it too,
    /// eased; off, they fall from where the light rests.
    #[kurashi(
        default = false,
        since = 7,
        requires = "theme.material.elevation == follow",
        overridden_by = "a11y.reduce_motion => false"
    )]
    pub elevation_pointer: bool,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, KurashiSchema)]
#[kurashi(i18n = "elevation")]
pub enum Elevation {
    /// Automatic
    Auto,
    /// Off
    Off,
    /// Static
    Static,
    /// Follow the light
    Follow,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, KurashiSchema)]
pub enum MotionProfile {
    /// Expressive
    Expressive,
    Calm,
    Lively,
    /// Off
    None,
}

#[derive(Debug, Clone, PartialEq, KurashiSchema)]
pub struct Motion {
    /// Motion
    /// Character of animations: expressive (surfaces grow out of the edge on timed curves that overshoot a little),
    /// calm or lively (springs), or none at all.
    #[kurashi(default = MotionProfile::Expressive, overridden_by = "a11y.reduce_motion => none")]
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
    /// Japanese font family
    /// Fallback chain for Japanese text; the first installed family wins (K60).
    #[kurashi(default = FontFamilies::of(&["Noto Sans CJK JP", "Noto Sans JP", "IPAexGothic", "sans-serif"]),
              advanced)]
    pub family_jp: FontFamilies,
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
    /// System events
    /// Volume, brightness, power and Bluetooth changes show on the island for a moment. Off, the island does not
    /// listen to them at all.
    #[kurashi(default = true)]
    pub system_events: bool,
    /// Draw mode
    /// How the island meets the bar or the edge it grows out of. Automatic follows the layout's draw mode (K71).
    #[kurashi(default = DrawChoice::Auto, since = 3)]
    pub draw: DrawChoice,
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
    /// Cards on the right
    /// The cards on the right side from top to bottom: `clock`, `calendar`, `media`, `weather`, and mods' cards as
    /// `mod:<id>:<name>`. On the side the cards stand on, a card neither side lists comes after the listed ones. The
    /// desk's edit mode writes it (K48, K71).
    #[kurashi(default = strings(&["clock", "calendar", "media", "weather"]), advanced,
              requires = "desktop.enabled == true", since = 3)]
    pub right: Vec<String>,
    /// Cards on the left
    /// The cards on the left side from top to bottom, named as on the right.
    #[kurashi(default = strings(&[]), advanced, requires = "desktop.enabled == true", since = 3)]
    pub left: Vec<String>,
    /// Hidden cards
    /// Cards the desk leaves out, named as on either side. The desk's edit mode writes it.
    #[kurashi(default = strings(&[]), advanced, requires = "desktop.enabled == true")]
    pub hidden: Vec<String>,
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
    /// Top
    /// Under the top bar, growing out of it (I282).
    Top,
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
    /// Visibility
    /// Shown while the desktop is empty and else when the pointer rests on its edge (as before), always, on hover
    /// only, or hidden until a key or `layout.toggle` brings it out (K71).
    #[kurashi(default = Visibility::EmptyDesktop, requires = "dock.enabled == true", since = 3)]
    pub visibility: Visibility,
    /// Keep space
    /// Whether windows keep clear of the dock. Automatic keeps space only while it is always shown.
    #[kurashi(default = KeepSpace::Auto, requires = "dock.enabled == true",
              requires = "dock.visibility != hidden", since = 3)]
    pub reserve: KeepSpace,
    /// Draw mode
    /// Automatic follows the layout's draw mode.
    #[kurashi(default = DrawChoice::Auto, requires = "dock.enabled == true", since = 3)]
    pub draw: DrawChoice,
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

/// How a sidebar shows its sections (I283): stacked in one column, or one at a time as pages with tabs.
#[derive(Debug, Clone, Copy, PartialEq, Eq, KurashiSchema)]
pub enum SidebarMode {
    /// One column
    Stack,
    /// Pages with tabs
    Pages,
}

/// One struct per side (K71): the two differ in their sections' defaults and offers, and in their mode's default.
macro_rules! sidebar_side {
    ($name:ident, $section:literal, $sections:expr, $source:literal, $hidden:literal,
     $sections_label:literal, $sections_help:literal, $mode:expr) => {
        #[derive(Debug, Clone, PartialEq, KurashiSchema)]
        #[kurashi(section = $section)]
        pub struct $name {
            #[doc = $sections_label]
            #[doc = $sections_help]
            #[kurashi(default = strings(&$sections), choices_from = $source, since = 3)]
            pub sections: Vec<String>,
            /// Layout
            /// One column: every section stacked, scrolled together. Pages with tabs: one section at a time, the tabs
            /// above it.
            #[kurashi(default = $mode, since = 5)]
            pub mode: SidebarMode,
            /// Width
            /// Drag the sidebar's inner edge to change it.
            #[kurashi(default = 420, range = 320..=640, step = 10, unit = "px", since = 3)]
            pub width: u32,
            /// Visibility
            /// Hidden: opened by its key, its button in the bar or `sidebar.toggle`. On hover: rest the pointer on the
            /// screen's side. Always shown: pinned open, the windows beside it.
            #[kurashi(default = Visibility::Hidden, since = 3)]
            pub visibility: Visibility,
            /// Keep space
            /// Whether windows keep clear of it. Automatic keeps space only while it is pinned open; Always also keeps
            /// space while it is open on hover.
            #[kurashi(default = KeepSpace::Auto, requires = $hidden, since = 3)]
            pub reserve: KeepSpace,
            /// Draw mode
            /// Dynamic: from the bar (or the screen edge) to the far edge, flush to its side, joined to the bar by
            /// rounded fillets. Floating: a gap away from every edge, every corner rounded, with the look's shadow.
            /// Automatic follows the layout's draw mode.
            #[kurashi(default = DrawChoice::Auto, since = 3)]
            pub draw: DrawChoice,
        }
    };
}

sidebar_side!(
    SidebarRight,
    "right_sidebar",
    ["header", "toggles", "sliders", "notifications", "calendar"],
    "sidebar.sections",
    "sidebar.right.visibility != hidden",
    "Sections",
    "Top to bottom: you and the session, the quick tiles, the levels, notifications, the month, what plays, and the mods' panels.",
    SidebarMode::Stack
);
sidebar_side!(
    SidebarLeft,
    "left_sidebar",
    ["mod:ai:ai"],
    "sidebar.tabs",
    "sidebar.left.visibility != hidden",
    "Tabs",
    "The mods' panels (AI chat, tasks, …). A tab whose mod is not on is skipped. Empty: no left sidebar.",
    SidebarMode::Pages
);

#[derive(Debug, Clone, PartialEq, KurashiSchema)]
#[kurashi(page = "sidebar", section = "sidebar")]
pub struct Sidebar {
    #[kurashi(nested)]
    pub right: SidebarRight,
    #[kurashi(nested)]
    pub left: SidebarLeft,
    /// Open from the bar
    /// The bar's quick settings button opens the right sidebar instead of the quick settings card (and the bar leaves
    /// the right sidebar's own button out).
    #[kurashi(default = false)]
    pub from_bar: bool,
}
