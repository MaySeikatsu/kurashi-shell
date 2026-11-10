//! Config schema v1 — the first real tree. Small on purpose; the lead extends it.
//!
//! Axes follow DESIGN-SYSTEM §3, a11y modes §5 (they force axes via `overridden_by`, which the
//! daemon resolves as `forced:accessibility`), the island ARCHITECTURE §5/§6.

use std::sync::OnceLock;

use crate::{Color, FontFamilies, KurashiSchema, MotionCurve, Registry, strings};

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
    pub modules: Modules,
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
    #[kurashi(nested)]
    pub lock: Lock,
    #[kurashi(nested)]
    pub title_bar: TitleBar,
    #[kurashi(nested)]
    pub cursor: Cursor,
    #[kurashi(nested)]
    pub quick: Quick,
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
    /// Cards open
    /// Where the card a bar module opens comes out: under the module that was clicked, or at the bar's centre, under
    /// the island.
    #[kurashi(default = PopupPlace::Module, since = 7)]
    pub popups: PopupPlace,
    /// Modules that open the other way
    /// These modules' cards open at the bar's centre while cards open under their module, or under their module while
    /// cards open at the centre.
    #[kurashi(default = strings(&[]), choices_from = "modules", since = 7)]
    pub popups_other: Vec<String>,
    /// Cards follow the pointer
    /// A card that a click, a key or the command line opened moves to the screen the pointer goes to and opens there
    /// again, under the same module where that screen's bar has it. What a hover opened closes as the pointer leaves, and
    /// sidebars stay on their screen.
    #[kurashi(default = true, since = 7)]
    pub popups_follow: bool,
    /// On hover
    /// What resting the pointer on a bar module opens: its small preview, its card (a module without a card shows its
    /// preview), or its menu, as a right click does. What a hover opened closes when the pointer has left the module
    /// and what it opened; what a click opened stays.
    #[kurashi(default = BarHover::Preview, since = 7)]
    pub hover: BarHover,
    /// Modules that show their preview on hover
    /// These modules show their preview whatever the bar does on hover. A module's menu sets it too (On hover).
    #[kurashi(default = strings(&[]), choices_from = "modules", since = 7)]
    pub hover_preview: Vec<String>,
    /// Modules that open their card on hover
    /// These modules open their card whatever the bar does on hover.
    #[kurashi(default = strings(&[]), choices_from = "modules", since = 7)]
    pub hover_card: Vec<String>,
    /// Modules that open their menu on hover
    /// These modules open their menu whatever the bar does on hover.
    #[kurashi(default = strings(&[]), choices_from = "modules", since = 7)]
    pub hover_menu: Vec<String>,
}

/// What a hover on a bar module opens (I458; Caelestia's popouts open on hover).
#[derive(Debug, Clone, Copy, PartialEq, Eq, KurashiSchema)]
#[kurashi(i18n = "bar_hover")]
pub enum BarHover {
    /// Its preview
    Preview,
    /// Its card
    Card,
    /// Its menu
    Menu,
}

/// Where a bar module's card comes out (I340; Noctalia's "panel position": at the widget or centred).
#[derive(Debug, Clone, Copy, PartialEq, Eq, KurashiSchema)]
#[kurashi(i18n = "popup_place")]
pub enum PopupPlace {
    /// Under the module
    Module,
    /// At the bar's centre
    Centre,
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
    /// bevels, light and dark edges that press in (K42, K45, K80); a glowing outline; grounds painted with a brush; or
    /// sheets of torn paper.
    // K80 amends K42: under high contrast a bevel stays (its lines carry pressed and sunken), drawn in the contrast ink;
    // every other chrome is forced flat (`except`: the daemon reads the value beneath the accessibility layer).
    #[kurashi(default = Chrome::Flat, section = "shape",
              overridden_by = "a11y.high_contrast => flat except bevel")]
    pub chrome: Chrome,
    /// Frame outline
    /// A line along the frame's inner edge and the sides of what is joined to it — bars, dock, sidebars — drawn in the
    /// chrome's style. Automatic is on for Keycap and Lines, off for Flat and Soft, and glows under Glow. Glow lights
    /// the line under any chrome; On under the Glow chrome keeps the line without its light.
    // I303: the per-chrome default lives in kurashi-theme's chrome data (rule 4); the token is `frame.outline`.
    #[kurashi(default = FrameOutline::Auto, section = "shape", since = 7)]
    pub frame_outline: FrameOutline,
    /// Edge
    /// How surfaces are edged. Clean: the chrome's own boxes. Painted: every ground is laid in strokes of a brush that
    /// run past its box, in the accent thinned into the surface, with the material you picked on the paint. Ripped:
    /// surfaces are sheets of paper torn by hand, with the paper's white core along the tear. Automatic follows the
    /// chrome: painted under Painted, ripped under Ripped paper, clean under the others.
    #[kurashi(default = Edge::Auto, section = "shape")]
    pub edge: Edge,
    /// Outline ink
    /// The colour of every outline the shell draws — blocks, the frame, the shapes joined to it: the chrome's own, the
    /// text's ink (as a hand-drawn look outlines its blocks), or the accent. Looks set it with the rest of their outline.
    #[kurashi(default = OutlineInk::Outline, section = "shape", since = 7)]
    pub outline_ink: OutlineInk,
    /// Connection
    /// How a card meets the bar it opens from, apart from the chrome. Automatic: as the look and its chrome draw it.
    /// Joined: the card grows out of the bar as one shape with it. Floating: a card of its own, a gap off the bar.
    #[kurashi(default = Join::Auto, section = "connection", since = 7)]
    pub join: Join,
    /// Connection corner
    /// The corner where two joined surfaces meet — a card and its bar, the dock, a sidebar and the frame: rounded into
    /// each other, cut straight across, stepped as pixels, bulging outward as a drop, or square. Its size is the
    /// joins' radius.
    #[kurashi(default = JoinCorner::Round, section = "connection", since = 7)]
    pub join_corner: JoinCorner,
    /// Sliders
    /// How every slider is drawn, in the shell and in Settings. Automatic: the look's own. Line: a thin track and a
    /// knob. Expressive: a thick pill with a handle bar and a stop mark. Capsule: the fill is the level, no knob. Wave:
    /// the filled part is a wave that moves while you drag. Blocks: one block per step. Ink: a stroke of a brush with a
    /// blot for a knob. Glow: a lit line.
    #[kurashi(default = SliderStyle::Auto, section = "controls", since = 7)]
    pub slider: SliderStyle,
    /// Switches
    /// How every switch is drawn, in the shell and in Settings. Automatic: the look's own. Switch: a knob in a track.
    /// Expressive: the knob grows and carries a check. Capsule: a wide track, a flat knob. Lamp: a light that goes on.
    /// Stamp: a seal pressed in ink. Flip: a rocker with its two sides.
    #[kurashi(default = ToggleStyle::Auto, section = "controls", since = 7)]
    pub toggle: ToggleStyle,
    #[kurashi(nested, section = "motion")]
    pub motion: Motion,
    /// Density
    /// Scales spacing and control sizes everywhere.
    #[kurashi(default = Density::Regular, section = "layout")]
    pub density: Density,
    #[kurashi(nested, page = "fonts", section = "typography")]
    pub typography: Typography,
    #[kurashi(nested, section = "texture")]
    pub texture: Texture,
    #[kurashi(nested, section = "light")]
    pub light: Light,
    #[kurashi(nested, section = "pen")]
    pub pen: Pen,
    /// Sounds
    /// Short sounds when you unlock, when something goes wrong, when a notification arrives and when the launcher
    /// opens or closes: the style's own set, original sounds in the spirit of what it recreates (K80). Off: nothing is
    /// loaded or played.
    #[kurashi(default = false, section = "sounds", since = 7)]
    pub sounds: bool,
    /// Apps that follow
    /// Write the shell's colours for these apps whenever the theme changes: GTK, Qt, KDE, terminals, editors,
    /// browsers, Discord, Spotify, Obsidian and the compositors (K49). Each one needs one line in its own config to
    /// read the file; Settings shows it.
    #[kurashi(default = strings(&[]), choices_from = "theme.export", section = "colors")]
    pub export: Vec<String>,
    /// Fonts in apps
    /// The apps that follow take the shell's fonts: its font for GTK, Qt and KDE apps, Vesktop, Obsidian and the interface of
    /// Zen and Firefox (and the fonts their pages fall back to); its monospaced font (Monospaced font in Fonts) for the
    /// terminals (Ghostty, Kitty, WezTerm, Foot, Alacritty) and the desktop's code font. Each terminal keeps its size. Apps
    /// whose font lives in a file of your own (Spotify's user.css, Zed's settings) keep theirs, and Settings says so. Off:
    /// every app keeps its own.
    #[kurashi(default = false, section = "colors")]
    pub export_fonts: bool,
    /// Websites too
    /// Pages in Zen and Firefox use the shell's fonts instead of their own. Sites that draw their icons with a font show
    /// words or boxes where the icons were. After a restart of the browser.
    #[kurashi(
        default = false,
        section = "colors",
        requires = "theme.export_fonts == true"
    )]
    pub export_fonts_pages: bool,
    /// Window frames
    /// The compositors that follow (niri, Hyprland, MangoWM, sway) draw a frame round every window: the accent round
    /// the focused one, the outline round the others, as wide as the shell's outline. Off: each keeps its own frame
    /// setting and only takes the colours.
    #[kurashi(default = false, section = "colors", since = 7)]
    pub window_frame: bool,
    /// Window frame colour
    /// The colour round the focused window, on the compositors that follow (niri, Hyprland, MangoWM, sway): the accent,
    /// the shell's outline ink, so that frames and the shell's outlines are one colour, or a colour of the palette. Unfocused
    /// windows keep the outline; a window asking for attention keeps the error colour.
    #[kurashi(default = WindowFrameColor::Accent, section = "colors")]
    pub window_frame_color: WindowFrameColor,
    /// Material in browsers
    /// Zen and Firefox take the material on their sidebar and toolbar, as a tile, with the shell's corners. A tile is opaque,
    /// so it is left out while Translucent browser is on. A browser reads its chrome at start: it shows after a restart.
    #[kurashi(
        default = true,
        section = "colors",
        requires = "theme.texture.kind != none",
        requires = "theme.browser_translucent == false"
    )]
    pub browser_material: bool,
    /// Material strength in browsers
    /// How strongly the tile reads on the browser's chrome, against the shell's own: chrome has little text on it, so it can
    /// take more than a terminal. After a restart of the browser.
    #[kurashi(
        default = 1.6,
        range = 0.4..=3.0,
        step = 0.1,
        section = "colors",
        requires = "theme.texture.kind != none",
        requires = "theme.browser_translucent == false",
        requires = "theme.browser_material == true"
    )]
    pub browser_material_strength: f64,
    /// Translucent browser
    /// Zen's and Firefox's own interface lets what is under the window show. Zen needs its transparency setting, written
    /// to a linked profile. After a restart.
    #[kurashi(default = false, section = "colors")]
    pub browser_translucent: bool,
    /// Translucent pages
    /// Pages without a background of their own show what is under the window too. Many sites assume a white page, so this
    /// is an opt-in of its own. After a restart.
    #[kurashi(
        default = false,
        section = "colors",
        requires = "theme.browser_translucent == true"
    )]
    pub browser_translucent_pages: bool,
    /// See-through unfocused windows
    /// The compositors that follow make every window but the focused one a little transparent (niri, Hyprland and
    /// MangoWM; sway has no setting for it). Off: each keeps its own.
    #[kurashi(default = false, section = "colors", since = 7)]
    pub inactive_transparent: bool,
    /// Unfocused opacity
    #[kurashi(default = 0.9, range = 0.5..=1.0, step = 0.05, requires = "theme.inactive_transparent == true",
              section = "colors", since = 7)]
    pub inactive_opacity: f64,
    /// Window animations
    /// The compositors that follow open, close and move windows with the shell's motion: niri on its springs,
    /// Hyprland and MangoWM on its curve and duration (sway has none). Off: each keeps its own.
    #[kurashi(default = true, section = "colors", since = 7)]
    pub window_animations: bool,
    /// Titlebars
    /// The compositors that draw titlebars give them the shell's colours and font: sway its own, Hyprland through the
    /// hyprbars plugin (it must be loaded). niri and MangoWM draw none: the apps draw theirs, in the colours GTK and
    /// Qt follow. Off: each keeps its own.
    #[kurashi(default = false, section = "colors", since = 7)]
    pub window_titlebars: bool,
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
    /// Glow
    Glow,
    /// Painted (brush strokes)
    Painted,
    /// Ripped paper
    Ripped,
}

/// I471, I477: how a surface's edge is made, apart from the chrome that picks it by default.
#[derive(Debug, Clone, Copy, PartialEq, Eq, KurashiSchema)]
#[kurashi(i18n = "edge")]
pub enum Edge {
    /// Automatic
    Auto,
    /// Clean
    Clean,
    /// Painted
    Painted,
    /// Ripped
    Ripped,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, KurashiSchema)]
#[kurashi(i18n = "window_frame_color")]
pub enum WindowFrameColor {
    /// Accent
    Accent,
    /// Shell outline
    ShellOutline,
    /// Secondary
    Secondary,
    /// Tertiary
    Tertiary,
    /// Outline
    Outline,
    /// Text
    OnSurface,
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
    /// Glow
    Glow,
}

/// I472/I478 (session 28): how a bar travels to another edge.
#[derive(Debug, Clone, Copy, PartialEq, Eq, KurashiSchema)]
#[kurashi(i18n = "layout_move")]
pub enum LayoutMove {
    /// Along the sides
    Follow,
    /// Parts in the middle
    Part,
    /// Drips
    Drip,
    /// Fades
    Fade,
    /// Off
    Off,
}

/// Session 28: how a card meets its bar, apart from the chrome.
#[derive(Debug, Clone, Copy, PartialEq, Eq, KurashiSchema)]
#[kurashi(i18n = "join")]
pub enum Join {
    /// Automatic
    Auto,
    /// Joined
    Fused,
    /// Floating
    Float,
}

/// Session 28 (I270): the corner where two joined surfaces meet.
#[derive(Debug, Clone, Copy, PartialEq, Eq, KurashiSchema)]
#[kurashi(i18n = "join_corner")]
pub enum JoinCorner {
    /// Rounded
    Round,
    /// Cut
    Chamfer,
    /// Steps
    Steps,
    /// Drop
    Bulge,
    /// Square
    Square,
}

/// Session 28: the slider every surface draws.
#[derive(Debug, Clone, Copy, PartialEq, Eq, KurashiSchema)]
#[kurashi(i18n = "slider_style")]
pub enum SliderStyle {
    /// Automatic
    Auto,
    /// Line
    Line,
    /// Expressive
    Expressive,
    /// Capsule
    Capsule,
    /// Wave
    Wave,
    /// Blocks
    Blocks,
    /// Ink
    Ink,
    /// Glow
    Glow,
}

/// Session 28: the switch every surface draws.
#[derive(Debug, Clone, Copy, PartialEq, Eq, KurashiSchema)]
#[kurashi(i18n = "toggle_style")]
pub enum ToggleStyle {
    /// Automatic
    Auto,
    /// Switch
    Switch,
    /// Expressive
    Expressive,
    /// Capsule
    Capsule,
    /// Lamp
    Lamp,
    /// Stamp
    Stamp,
    /// Flip
    Flip,
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

/// K87: the shell and the apps that follow its theme in the playing track's colours, over the palette; off, the palette
/// is back as it was.
#[derive(Debug, Clone, PartialEq, KurashiSchema)]
pub struct MediaColors {
    /// Dynamic Media Color
    /// The shell and the apps that follow its theme take the colours of the track playing now. Your palette and light or
    /// dark stay as they are: turn this off and they are back.
    #[kurashi(default = false)]
    pub follow: bool,
    /// Apps follow too
    /// Apps cannot blend, so each track changes their colours at once and some of them reload. Off, only the shell takes
    /// the track's colours and the apps keep your palette.
    #[kurashi(default = true, requires = "theme.colors.media.follow == true")]
    pub apps: bool,
    /// Light or dark
    /// The cover's own colours, as the Now Playing card shows them, or your light or dark in the cover's hue. Text is kept
    /// readable either way.
    #[kurashi(default = MediaTone::Cover, requires = "theme.colors.media.follow == true")]
    pub tone: MediaTone,
    /// Change of colour
    /// How the shell goes from one track's colours to the next. Round the colour wheel passes through the colours between
    /// them, the short way or the long way.
    #[kurashi(default = MediaBlend::Fade, requires = "theme.colors.media.follow == true")]
    pub blend: MediaBlend,
    /// Length of the change
    /// The colour wheel takes half as long again, as it has further to go.
    #[kurashi(
        default = 1200,
        range = 200..=4000,
        step = 100,
        unit = "ms",
        requires = "theme.colors.media.follow == true",
        requires = "theme.colors.media.blend != direct"
    )]
    pub blend_ms: u32,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, KurashiSchema)]
pub enum MediaTone {
    /// The cover's colours
    Cover,
    /// My light or dark
    Keep,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, KurashiSchema)]
pub enum MediaBlend {
    /// Fade
    Fade,
    /// Colour wheel, the short way
    WheelClosest,
    /// Colour wheel, the long way
    WheelFurthest,
    /// At once
    Direct,
}

/// K88: the wallpaper recoloured to the theme's colours, by a lookup table, whenever the theme changes.
#[derive(Debug, Clone, PartialEq, KurashiSchema)]
pub struct WallpaperGrade {
    /// Wallpaper Color Grade
    /// Recolours the wallpaper to the theme's colours whenever they change, by Dynamic Media Color too. The picture's detail
    /// stays and the file itself is never changed: turn this off and it is back. Needs the Wallpaper mod.
    #[kurashi(default = false)]
    pub enabled: bool,
    /// How it recolours
    /// Automatic matches a colourful picture's colours to the theme's, and runs a nearly colourless one through them from
    /// shadows to highlights.
    #[kurashi(default = WallpaperGradeMode::Auto, requires = "theme.colors.wallpaper_grade.enabled == true")]
    pub mode: WallpaperGradeMode,
    /// Strength
    /// From the original picture to fully recoloured.
    #[kurashi(default = 1.0, range = 0.0..=1.0, step = 0.05, requires = "theme.colors.wallpaper_grade.enabled == true")]
    pub strength: f64,
    /// Follow the theme's brightness
    /// Off keeps the picture's own light and dark. Higher lets a dark theme darken the picture and a light one brighten it.
    #[kurashi(default = 0.0, range = 0.0..=1.0, step = 0.05, requires = "theme.colors.wallpaper_grade.enabled == true")]
    pub lightness: f64,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, KurashiSchema)]
pub enum WallpaperGradeMode {
    /// Automatic
    Auto,
    /// Match the colours
    Match,
    /// Colour balance
    Balance,
    /// Gradient map
    Gradient,
    /// Pull to the palette
    Palette,
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
    #[kurashi(default = Scheme::Auto, module = "darkmode")]
    pub scheme: Scheme,
    /// Wallpaper colours
    /// How the wallpaper's colours become the palette. Tone-matched builds calm tones around its main colour; Vibrant the
    /// same, more saturated; Prominent takes the colours that are in the picture as they are (its dark and light for
    /// ground and text, its strongest hues as accents); Mixed spreads all of the picture's prominent colours over the
    /// shell (ground, cards, lines, accents). Text stays legible in every mode. The seasonal tint, when on, still shifts
    /// these hues (I455).
    #[kurashi(default = Extraction::ToneMatched, requires = "theme.colors.palette == wallpaper")]
    pub extraction: Extraction,
    /// Colours on the controls
    /// One accent: buttons, sliders, switches and tiles all in the accent. Spread: the palette's colours over them —
    /// buttons the accent, sliders the secondary, switches and quick tiles the tertiary — so a wallpaper's other colours
    /// show as themselves. Automatic spreads them under the wallpaper's Mixed colours.
    #[kurashi(default = ControlColours::Auto)]
    pub controls: ControlColours,
    /// App icons
    /// The icons of apps in the dock, the bar's window list, the tray, the launcher and notifications: as they are, in
    /// the text's colour (a picture keeps its drawing as lighter and denser ink), in the palette's tones (dark to light
    /// in the palette's colours) or in its colours (each part takes the palette colour nearest its own hue).
    #[kurashi(default = AppIconTint::Original)]
    pub app_icons: AppIconTint,
    /// Terminals keep their own palette
    /// Terminals and the tools that run in them (fzf, Neovim, Helix, Zellij) wear a published theme as its authors
    /// made it, the 16 terminal colours included, instead of colours derived from the shell's: the palette the shell
    /// wears when it has such colours, else the published one closest to the shell's colours. Off under high contrast
    /// and the colour-blind aids, which need the shell's own colours.
    #[kurashi(default = false)]
    pub real_palettes: bool,
    /// Chrome fill
    /// What the bar, frame, panels and cards — and the apps that follow the theme — are filled with. Neutral: the
    /// palette's grey, black or white. Strong colour: the palette's strong colour. Text and controls are chosen again so
    /// they stay legible. The gradient below can run over either (I456).
    #[kurashi(default = ChromeFill::Neutral)]
    pub chrome_fill: ChromeFill,
    #[kurashi(nested)]
    pub gradient: ChromeGradient,
    #[kurashi(nested, section = "colour_flow")]
    pub flow: ColourFlow,
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
    /// solar terms. It shifts every palette's accents, a wallpaper's too, so they can look unlike the picture.
    #[kurashi(default = false, advanced)]
    pub season: bool,
    #[kurashi(nested)]
    pub media: MediaColors,
    #[kurashi(nested)]
    pub wallpaper_grade: WallpaperGrade,
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
pub enum ControlColours {
    /// Automatic
    Auto,
    /// One accent
    One,
    /// Spread
    Spread,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, KurashiSchema)]
pub enum ChromeFill {
    /// Neutral
    Neutral,
    /// Strong colour
    Strong,
}

/// Session 28: colour in motion — the gradient, the frame's line and the glow move through colours.
#[derive(Debug, Clone, PartialEq, KurashiSchema)]
pub struct ColourFlow {
    /// Colour flow
    /// Colours move: the chrome's gradient drifts, the frame's outline and its glow run through colours. It draws
    /// frames while it runs, so it is off by default and stops with the motion profile None and with reduced motion.
    #[kurashi(default = false, since = 7)]
    pub on: bool,
    /// Runs
    /// Always; only while a card, a sidebar or the launcher is open; or only while music plays.
    #[kurashi(default = FlowWhen::Active, requires = "theme.colors.flow.on == true", since = 7)]
    pub when: FlowWhen,
    /// Pattern
    /// Drift: the colours travel slowly along the line and across the gradient. Breathe: they swell and fade. Cycle:
    /// they turn round the colour wheel. Chase: a light runs along the line.
    #[kurashi(default = FlowPattern::Drift, requires = "theme.colors.flow.on == true", since = 7)]
    pub pattern: FlowPattern,
    /// Colours
    /// Tones: the accent from darker to lighter. Palette: the accent, the secondary and the tertiary run into each
    /// other. Rainbow: the whole wheel.
    #[kurashi(default = FlowColours::Palette, requires = "theme.colors.flow.on == true", since = 7)]
    pub colours: FlowColours,
    /// Gradient
    /// The chrome's gradient moves (while the gradient is on).
    #[kurashi(default = true, requires = "theme.colors.flow.on == true", since = 7)]
    pub gradient: bool,
    /// Frame outline
    /// The frame's outline and the outline of what is joined to it move through the colours (a hand-drawn stroke
    /// keeps its ink).
    #[kurashi(default = true, requires = "theme.colors.flow.on == true", since = 7)]
    pub outline: bool,
    /// Glow
    /// The frame's glow and the Glow chrome's light move through the colours.
    #[kurashi(default = true, requires = "theme.colors.flow.on == true", since = 7)]
    pub glow: bool,
    /// Speed
    /// 1 is one round in about twelve seconds.
    #[kurashi(default = 1.0, range = 0.25..=4.0, step = 0.25, requires = "theme.colors.flow.on == true", since = 7)]
    pub speed: f64,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, KurashiSchema)]
#[kurashi(i18n = "flow_when")]
pub enum FlowWhen {
    /// Always
    Always,
    /// While something is open
    Active,
    /// While music plays
    Media,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, KurashiSchema)]
#[kurashi(i18n = "flow_pattern")]
pub enum FlowPattern {
    /// Drift
    Drift,
    /// Breathe
    Breathe,
    /// Cycle
    Cycle,
    /// Chase
    Chase,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, KurashiSchema)]
#[kurashi(i18n = "flow_colours")]
pub enum FlowColours {
    /// Tones
    Tones,
    /// Palette
    Palette,
    /// Rainbow
    Rainbow,
}

/// I460: the chrome's gradient, one continuous sheet that every ground shows its own part of.
#[derive(Debug, Clone, PartialEq, KurashiSchema)]
pub struct ChromeGradient {
    /// Gradient
    /// The chrome's fill — neutral or the strong colour — runs from one tone or colour to another across the screen (or
    /// every screen), in the pattern below; text stays legible over all of it (I460).
    #[kurashi(default = false)]
    pub on: bool,
    /// Gradient colours
    /// Tones: the strong colour from darker to lighter. Colours: the palette's accent, secondary and tertiary run into
    /// each other (with the wallpaper's Mixed colours, the picture's own).
    #[kurashi(default = GradientColours::Tones, requires = "theme.colors.gradient.on == true")]
    pub colours: GradientColours,
    /// Pattern
    /// Linear runs from one edge to the other; radial from the middle out; watercolour lays large soft pools that bleed
    /// into each other; the wallpaper under it gives every spot the colour of the picture right behind it, softened.
    #[kurashi(default = GradientPattern::Linear, requires = "theme.colors.gradient.on == true")]
    pub pattern: GradientPattern,
    /// Angle from the wallpaper
    /// The gradient turns so its darker side lies where the wallpaper is lighter and its lighter side where the
    /// wallpaper is darker, so the chrome stands out from the picture behind it (no dark on dark, no light on light).
    /// Without a wallpaper picture the angle below is used.
    #[kurashi(
        default = true,
        requires = "theme.colors.gradient.on == true",
        requires = "theme.colors.gradient.pattern == linear"
    )]
    pub auto_angle: bool,
    /// Angle
    /// The direction a linear gradient runs in.
    #[kurashi(
        default = 35,
        range = 0..=359,
        step = 5,
        unit = "°",
        requires = "theme.colors.gradient.on == true",
        requires = "theme.colors.gradient.pattern == linear",
        requires = "theme.colors.gradient.auto_angle == false"
    )]
    pub angle: u32,
    /// Range of tones
    /// How far the darker and the lighter tone lie apart; text stays legible on both.
    #[kurashi(
        default = 12,
        range = 2..=30,
        step = 1,
        unit = "%",
        requires = "theme.colors.gradient.on == true",
        requires = "theme.colors.gradient.colours == tones"
    )]
    pub spread: u32,
    /// Softness
    /// How gently one colour runs into the next (under the wallpaper pattern: how much the picture is blurred).
    #[kurashi(default = 85, range = 0..=100, step = 5, unit = "%", requires = "theme.colors.gradient.on == true")]
    pub softness: u32,
    /// Pool size
    /// How large the watercolour's pools are.
    #[kurashi(
        default = 420,
        range = 120..=1600,
        step = 20,
        unit = "px",
        requires = "theme.colors.gradient.on == true",
        requires = "theme.colors.gradient.pattern == watercolour"
    )]
    pub size: u32,
    /// Across all screens
    /// One gradient over every screen together, as they stand side by side; off, each screen has its own.
    #[kurashi(default = true, requires = "theme.colors.gradient.on == true")]
    pub span_outputs: bool,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, KurashiSchema)]
pub enum GradientColours {
    /// Tones of one colour
    Tones,
    /// All its colours
    Colours,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, KurashiSchema)]
pub enum GradientPattern {
    /// Linear
    Linear,
    /// Radial
    Radial,
    /// Watercolour
    Watercolour,
    /// The wallpaper under it
    Wallpaper,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, KurashiSchema)]
pub enum Extraction {
    /// Tone-matched
    ToneMatched,
    /// Vibrant
    Vibrant,
    /// Prominent
    Prominent,
    /// Mixed
    Mixed,
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
    /// Display (pixel grid)
    Display,
    /// Tread plate (steel)
    TreadPlate,
    /// Old paper (stained)
    OldPaper,
    /// Canvas (a little dirty)
    Canvas,
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
    /// Terminals too
    /// The terminals among the apps that follow take the material: as a shader that keeps off the text where the terminal
    /// has one (Ghostty), else as a faint background picture (Kitty, WezTerm). Alacritty, Foot, Rio and Ratty can only
    /// take colours. Off: every terminal has colours alone.
    #[kurashi(default = true, requires = "theme.texture.kind != none")]
    pub terminals: bool,
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
#[kurashi(i18n = "light_outputs")]
pub enum LightOutputs {
    /// The one with the pointer
    Pointer,
    /// All monitors
    All,
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
    /// Monitors it reaches
    /// Where the pointer's light and the shadows it turns act: on the monitor the pointer is on, or on all of them, from
    /// where the pointer stands across your monitors. All repaints every monitor's surfaces as the pointer moves.
    #[kurashi(
        default = LightOutputs::Pointer,
        requires = "theme.light.mode != static",
        requires = "theme.light.mode != daytime",
        requires = "theme.light.mode != wallpaper"
    )]
    pub outputs: LightOutputs,
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
    /// The screen's corners follow the frame's: its corner radius plus its thickness on a framed screen, so the band keeps
    /// one width round the corner (a square look leaves them square). Off: they take their own size below.
    #[kurashi(default = true, since = 5)]
    pub screen_corners_follow: bool,
    /// Screen corners
    /// Rounds the corners of every screen by this many pixels (0 = square, as the panel is).
    #[kurashi(default = 0, range = 0..=48, step = 2, unit = "px", requires = "theme.shape.screen_corners_follow == false")]
    pub screen_corners: u32,
    /// Corner radius
    /// The one radius every corner follows (K74, K96): panels, cards, the island's views, the frame, merging corners,
    /// windows, the dock and desktop widgets, so they match; buttons, toggles and smaller parts take steps of it. A
    /// surface below can take its own.
    #[kurashi(default = 18, range = 0..=48, step = 1, unit = "px", requires = "theme.shape.corners != none", since = 4)]
    pub radius: u32,
    /// Frame corners
    /// The corners of the window cut into the frame. The screen's outer corners go with them, this much plus the
    /// frame's thickness. Auto: the corner radius.
    #[kurashi(default = -1, range = -1..=64, step = 1, unit = "px", requires = "theme.shape.corners != none")]
    pub radius_frame: i32,
    /// Merging corners
    /// The concave corners where a surface merges into a bar or the frame: the dock, the sidebars, the island, menus.
    /// Auto: the corner radius.
    #[kurashi(default = -1, range = -1..=64, step = 1, unit = "px", requires = "theme.shape.corners != none")]
    pub radius_joins: i32,
    /// Window corners
    /// The corners of the compositor's windows (niri, Hyprland, MangoWM; sway has none). Auto: the corner radius.
    #[kurashi(default = -1, range = -1..=64, step = 1, unit = "px", requires = "theme.shape.corners != none")]
    pub radius_windows: i32,
    /// Desktop widget corners
    /// The corners of the widgets on the desktop. Auto: the corner radius.
    #[kurashi(default = -1, range = -1..=64, step = 1, unit = "px", requires = "theme.shape.corners != none")]
    pub radius_widgets: i32,
    /// Dock corners
    /// The dock's own corners, floating or joined. Auto: the corner radius.
    #[kurashi(default = -1, range = -1..=64, step = 1, unit = "px", requires = "theme.shape.corners != none")]
    pub radius_dock: i32,
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
    /// Frame and panel shadows
    /// What the frame, the bars, the sidebars and the dock cast onto what lies beside them. Automatic: as Elevation.
    /// Follow the light, or Static along the shadow direction. Inward: evenly all round into the window cut into the
    /// frame, with no direction. Off: none.
    #[kurashi(default = SheetShadow::Auto, overridden_by = "a11y.high_contrast => off")]
    pub sheet_shadow: SheetShadow,
    /// Elevation strength
    /// How deep the surfaces' shadows are, the frame's and the panels' too: 0 none, 1 the look's own, 2 twice as far and
    /// dark (the blocks' shadows have their own strength above).
    #[kurashi(default = 1.0, range = 0.0..=2.0, step = 0.05, since = 7)]
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
#[kurashi(i18n = "sheet_shadow")]
pub enum SheetShadow {
    /// Automatic
    Auto,
    /// Follow the light
    Follow,
    /// Static
    Static,
    /// Inward
    Inward,
    /// Off
    Off,
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

/// The motion engine's settings (K83, `docs/ux/motion-engine.md`): a motion profile (a motion pack) bundles curves,
/// forms and choreography; every key below it overrides one part (`""` / `-1` / `profile` = the profile's).
#[derive(Debug, Clone, PartialEq, KurashiSchema)]
#[kurashi(page = "motion")]
pub struct Motion {
    /// Motion profile
    /// How everything moves, in one choice: the curves, the forms surfaces open and close in, and what moves when.
    /// A style recommends one; pick another, or change any part below on top of it.
    // The ids are motion packs (`motion/*.toml` and the user's); today's expressive, calm, lively and none stay ids.
    #[kurashi(default = "expressive".to_owned(), choices_from = "motion.profiles", section = "profiles",
              overridden_by = "a11y.reduce_motion => reduced")]
    pub profile: String,
    /// Animation speed
    /// Multiplies every motion duration's speed (2.0 = twice as fast).
    #[kurashi(default = 1.0, range = 0.25..=3.0, step = 0.05, section = "profiles",
              requires = "theme.motion.profile != none")]
    pub speed: f64,
    /// Blend colour changes
    /// A change of colours — a palette, light or dark, a look, the wallpaper's colours — fades over a third of a second
    /// instead of cutting. Off with reduced motion and with the motion profile None.
    #[kurashi(
        default = true,
        section = "profiles",
        requires = "theme.motion.profile != none",
        since = 7
    )]
    pub blend_colors: bool,
    /// A bar changes its edge
    /// How a bar gets to another edge of the screen. Along the sides: it slides round the corner, the shorter way.
    /// Parts: it splits in the middle and each half runs down its side. Drips: it sags, drops and settles. Fades: the
    /// new bar fades in. Off: it is there at once.
    #[kurashi(
        default = LayoutMove::Follow,
        section = "profiles",
        requires = "theme.motion.profile != none",
        since = 7
    )]
    pub layout_move: LayoutMove,
    // S21 (K86): the three tiers in page order: profiles, animation style (+ timing preset), advanced curves.
    #[kurashi(nested, section = "animation_style")]
    pub form: MotionForms,
    #[kurashi(nested, section = "timing")]
    pub timing: MotionTiming,
    /// Content
    /// When a surface's content appears as it opens: late (once the surface has nearly reached its size), with it, or
    /// row by row in a cascade.
    #[kurashi(default = MotionContent::Profile, section = "choreography")]
    pub content: MotionContent,
    /// Cascade step
    /// Milliseconds between one row's arrival and the next in a cascade (-1: the profile's).
    #[kurashi(default = -1, range = -1..=60, unit = "ms", section = "choreography", advanced)]
    pub stagger_ms: i32,
    /// Squash and stretch
    /// How much a shape narrows while it moves fast and bulges as it lands (-1: the profile's).
    #[kurashi(default = -1.0, range = -1.0..=0.15, step = 0.01, section = "choreography", advanced)]
    pub squash: f64,
    /// Jelly
    /// A wobble after a surface lands, like pudding settling (-1: the profile's; 0: none).
    #[kurashi(default = -1.0, range = -1.0..=1.0, step = 0.05, section = "choreography")]
    pub jelly: f64,
    /// Shadow while moving
    /// What a surface's shadow does during its motion: carried with the shape, or faded out and back at rest (folding
    /// forms shade themselves).
    #[kurashi(default = MotionShadow::Profile, section = "choreography", advanced)]
    pub shadow: MotionShadow,
    /// Window animations
    /// Give the compositor's window animations the profile's curves (niri). With its animations, windows also open and
    /// close the way the shell's surfaces do, through niri's custom shaders; niri keeps its own if a later version refuses
    /// one. Off: windows move as the compositor says.
    #[kurashi(default = MotionWindows::Off, section = "windows")]
    pub windows: MotionWindows,
}

/// One curve per role (K83, brief §4): `""` takes the motion profile's.
#[derive(Debug, Clone, PartialEq, KurashiSchema)]
pub struct MotionTiming {
    /// Timing preset
    /// How the profile's animations are timed: the profile's own, or a preset's curves (calm, lively …) under its forms.
    // S21 (the user's three tiers): the timing-only packs (`motion.timings`); the curves below override it per role.
    #[kurashi(default = String::new(), choices_from = "motion.timings", requires = "theme.motion.profile != none")]
    pub preset: String,
    /// Opening
    /// The curve surfaces open and grow on.
    #[kurashi(default = MotionCurve::profile(), section = "advanced_curves", requires = "theme.motion.profile != none")]
    pub open: MotionCurve,
    /// Closing
    /// The curve surfaces close and fold back on.
    #[kurashi(default = MotionCurve::profile(), section = "advanced_curves", requires = "theme.motion.profile != none")]
    pub close: MotionCurve,
    /// Quick moves
    /// The curve of small, fast moves: hover peeks, menus, a bar sliding in.
    #[kurashi(default = MotionCurve::profile(), section = "advanced_curves", requires = "theme.motion.profile != none")]
    pub fast: MotionCurve,
    /// Fades
    /// The curve of colour and opacity changes; it should not overshoot.
    #[kurashi(default = MotionCurve::profile(), section = "advanced_curves", requires = "theme.motion.profile != none")]
    pub effects: MotionCurve,
    /// Opening duration
    /// Milliseconds (0: the profile's; a spring's duration is its response).
    #[kurashi(default = 0, range = 0..=3000, unit = "ms", advanced, section = "advanced_curves",
              requires = "theme.motion.profile != none")]
    pub open_ms: u32,
    /// Closing duration
    /// Milliseconds (0: the profile's).
    #[kurashi(default = 0, range = 0..=3000, unit = "ms", advanced, section = "advanced_curves",
              requires = "theme.motion.profile != none")]
    pub close_ms: u32,
    /// Quick move duration
    /// Milliseconds (0: the profile's).
    #[kurashi(default = 0, range = 0..=3000, unit = "ms", advanced, section = "advanced_curves",
              requires = "theme.motion.profile != none")]
    pub fast_ms: u32,
    /// Fade duration
    /// Milliseconds (0: the profile's).
    #[kurashi(default = 0, range = 0..=3000, unit = "ms", advanced, section = "advanced_curves",
              requires = "theme.motion.profile != none")]
    pub effects_ms: u32,
}

/// The form surfaces open and close in (K83, brief §5–§6): a default for all, then per surface class. `""` = the next
/// one up: the surface's own → the default here → the profile's surface → the profile's default.
#[derive(Debug, Clone, PartialEq, KurashiSchema)]
pub struct MotionForms {
    /// Opens with
    /// The animation every surface opens with, unless one has its own below.
    #[kurashi(default = String::new(), choices_from = "motion.forms", requires = "theme.motion.profile != none")]
    pub open: String,
    /// Closes with
    /// The animation every surface closes with, unless one has its own below.
    #[kurashi(default = String::new(), choices_from = "motion.forms", requires = "theme.motion.profile != none")]
    pub close: String,
    #[kurashi(nested)]
    pub island: IslandForm,
    #[kurashi(nested)]
    pub panel: SurfaceForm,
    #[kurashi(nested)]
    pub peek: SurfaceForm,
    #[kurashi(nested)]
    pub launcher: SurfaceForm,
    #[kurashi(nested)]
    pub centre: SurfaceForm,
    #[kurashi(nested)]
    pub toast: SurfaceForm,
    #[kurashi(nested)]
    pub sidebar: SurfaceForm,
    #[kurashi(nested)]
    pub dock: SurfaceForm,
    #[kurashi(nested)]
    pub bar: SurfaceForm,
    #[kurashi(nested)]
    pub osd: SurfaceForm,
    #[kurashi(nested)]
    pub menu: SurfaceForm,
    #[kurashi(nested)]
    pub dialog: SurfaceForm,
    #[kurashi(nested)]
    pub window: WindowForm,
}

/// The compositor's windows (K91, `docs/ux/niri-motion.md`): the form they open and close in; `""` follows the default.
#[derive(Debug, Clone, PartialEq, KurashiSchema)]
pub struct WindowForm {
    /// Windows open with
    /// The animation a window opens with. Follows the style's unless you pick one here.
    #[kurashi(default = String::new(), choices_from = "motion.forms",
              requires = "theme.motion.windows == forms")]
    pub open: String,
    /// Windows close with
    /// The animation a window closes with. Follows the style's unless you pick one here.
    #[kurashi(default = String::new(), choices_from = "motion.forms",
              requires = "theme.motion.windows == forms")]
    pub close: String,
}

/// One surface class's forms; `""` follows the default. A form that cannot serve this class is refused by the resolver
/// with its reason (forms meta, K83).
#[derive(Debug, Clone, PartialEq, KurashiSchema)]
pub struct SurfaceForm {
    /// Opens with
    /// This surface's own opening animation ("": the default).
    #[kurashi(default = String::new(), choices_from = "motion.forms", advanced,
              requires = "theme.motion.profile != none")]
    pub open: String,
    /// Closes with
    /// This surface's own closing animation ("": the default).
    #[kurashi(default = String::new(), choices_from = "motion.forms", advanced,
              requires = "theme.motion.profile != none")]
    pub close: String,
}

/// The island's forms (K83 D3, the user): it takes every form and follows the default unless it is told not to.
#[derive(Debug, Clone, PartialEq, KurashiSchema)]
pub struct IslandForm {
    /// Island follows the default
    /// The island opens and closes its cards the way every surface does. Off: it uses its own animations below. Its
    /// faces and hover peeks keep their springs either way.
    #[kurashi(default = true, requires = "theme.motion.profile != none")]
    pub follow: bool,
    /// Island opens with
    /// The island's own opening animation.
    #[kurashi(default = String::new(), choices_from = "motion.forms",
              requires = "theme.motion.form.island.follow == false")]
    pub open: String,
    /// Island closes with
    /// The island's own closing animation.
    #[kurashi(default = String::new(), choices_from = "motion.forms",
              requires = "theme.motion.form.island.follow == false")]
    pub close: String,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, KurashiSchema)]
pub enum MotionContent {
    /// From the profile
    Profile,
    /// Late
    Late,
    /// With the surface
    With,
    /// Cascade
    Cascade,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, KurashiSchema)]
pub enum MotionShadow {
    /// From the profile
    Profile,
    /// Carried
    Carry,
    /// Faded
    Fade,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, KurashiSchema)]
pub enum MotionWindows {
    /// Off
    Off,
    /// Follow the profile
    Follow,
    /// Follow the profile, with its animations
    Forms,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, KurashiSchema)]
pub enum Density {
    Compact,
    Regular,
    Airy,
}

#[derive(Debug, Clone, PartialEq, KurashiSchema)]
pub struct Typography {
    #[kurashi(nested, section = "font_mix")]
    pub mix: FontMix,
    #[kurashi(nested, section = "text_effects")]
    pub fx: TextFx,
    /// Font family
    /// Fallback chain; the first installed family wins (resolved via fontconfig).
    #[kurashi(default = FontFamilies::of(&["Inter", "Noto Sans CJK JP", "sans-serif"]))]
    pub family: FontFamilies,
    /// Japanese font family
    /// Fallback chain for Japanese text; the first installed family wins (K60).
    #[kurashi(default = FontFamilies::of(&["Noto Sans CJK JP", "Noto Sans JP", "IPAexGothic", "sans-serif"]),
              advanced)]
    pub family_jp: FontFamilies,
    /// Monospaced font
    /// For terminals and code: fallback chain, the first installed family wins. Apps take it while Monospaced font in apps
    /// is on.
    #[kurashi(default = FontFamilies::of(&["monospace"]), since = 7)]
    pub mono: FontFamilies,
    /// Text scale
    /// Multiplies every type size token.
    #[kurashi(default = 1.0, range = 0.75..=2.0, step = 0.05,
              overridden_by = "a11y.large_text => 1.25")]
    pub scale: f64,
}

/// I473 (session 28, `docs/ux/text-effects.md`): how text looks and how fresh text appears.
#[derive(Debug, Clone, PartialEq, KurashiSchema)]
pub struct TextFx {
    /// Text effect
    /// How headings and labels are lit. Glow: a soft light in the text's own colour. CRT: a phosphor glow with a
    /// colour fringe and scan lines. Candle: a warm light that flickers. Rainbow: every letter its own colour. Shimmer:
    /// a light passes over the text now and then.
    #[kurashi(default = TextEffect::None, since = 7)]
    pub effect: TextEffect,
    /// Fresh text
    /// How text appears when its surface opens or its words change. Typed: letter by letter, as in old games.
    /// Deciphered: signs settle into the letters. From kana: Japanese letters turn into the ones that belong there.
    /// Brushed: painted in from the left. Rise: each letter rises into place. Ink: it soaks in from a blur.
    #[kurashi(default = TextSpawn::None, requires = "theme.motion.profile != none", since = 7)]
    pub spawn: TextSpawn,
    /// Applies to
    /// Headings alone (card and page titles, the clock, the island), or every label that can take it.
    #[kurashi(default = TextFxScope::Titles, since = 7)]
    pub scope: TextFxScope,
    /// Speed of fresh text
    /// 1 writes a short heading in about a third of a second.
    #[kurashi(default = 1.0, range = 0.25..=3.0, step = 0.25, requires = "theme.typography.fx.spawn != none", since = 7)]
    pub spawn_speed: f64,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, KurashiSchema)]
#[kurashi(i18n = "text_effect")]
pub enum TextEffect {
    /// None
    None,
    /// Glow
    Glow,
    /// CRT
    Crt,
    /// Candle
    Candle,
    /// Rainbow
    Rainbow,
    /// Shimmer
    Shimmer,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, KurashiSchema)]
#[kurashi(i18n = "text_spawn")]
pub enum TextSpawn {
    /// None
    None,
    /// Typed
    Type,
    /// Deciphered
    Decipher,
    /// From kana
    Kana,
    /// Brushed
    Brush,
    /// Rise
    Rise,
    /// Ink
    Ink,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, KurashiSchema)]
#[kurashi(i18n = "text_fx_scope")]
pub enum TextFxScope {
    /// Headings
    Titles,
    /// Every label
    All,
}

/// A mix of fonts per letter, so that text looks less even, as handwriting does (I176, K93, `docs/ux/fonts.md`).
#[derive(Debug, Clone, PartialEq, KurashiSchema)]
pub struct FontMix {
    /// Font mix
    /// Mixes several fonts letter by letter, so text looks less regular, as handwriting does. Handwriting takes shipped fonts;
    /// Custom takes yours. It works with any fonts; the first gives the sizes. Digits and other scripts stay as they are.
    #[kurashi(default = FontMixPreset::Off, since = 7)]
    pub preset: FontMixPreset,
    /// How many fonts
    /// How many of the fonts to mix, from the first. Two is the quietest.
    #[kurashi(default = 3, range = 2..=8, step = 1, requires = "theme.typography.mix.preset != off", since = 7)]
    pub count: u32,
    /// Fonts to mix
    /// The fonts, in order. Any installed font, your own too.
    #[kurashi(default = strings(&["Kalam", "Patrick Hand", "Handlee"]), choices_from = "fonts.installed",
              requires = "theme.typography.mix.preset == custom", since = 7)]
    pub fonts: Vec<String>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, KurashiSchema)]
pub enum FontMixPreset {
    /// Off
    Off,
    /// Handwriting
    Handwriting,
    /// Custom
    Custom,
}

// --- accessibility -------------------------------------------------------------------------------

#[derive(Debug, Clone, PartialEq, KurashiSchema)]
#[kurashi(page = "accessibility", section = "modes")]
pub struct A11y {
    /// Reduce motion
    /// Replaces movement with short fades: nothing slides, grows, folds or flashes (forces the motion profile to
    /// reduced).
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
    middle = "island.pin",
    scroll_up = "island.prev",
    scroll_down = "island.next"
))]
pub struct IslandInstance {
    /// Faces
    /// Faces this island may show, in cycling order.
    #[kurashi(
        default = strings(&["clock", "media", "notifications"]),
        choices_from = "island.faces",
        module = "island"
    )]
    pub faces: Vec<String>,
    /// Default face
    /// Face shown when nothing more relevant is happening.
    #[kurashi(default = "clock".to_owned(), choices_from = "island.faces", module = "island")]
    pub default: String,
    /// Transient duration
    /// How long a transient face (volume, brightness, notification) stays before falling back.
    #[kurashi(default = 5, range = 1..=60, unit = "s", module = "island")]
    pub ttl: u32,
    /// System events
    /// Volume, brightness, power and Bluetooth changes show on the island for a moment. Off, the island does not
    /// listen to them at all.
    #[kurashi(default = true, module = "island")]
    pub system_events: bool,
    /// Draw mode
    /// How the island meets the bar or the edge it grows out of. Automatic follows the layout's draw mode (K71).
    #[kurashi(default = DrawChoice::Auto, module = "island", since = 3)]
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
    #[kurashi(default = false, module = "focus")]
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
    #[kurashi(default = WeekStart::Auto, module = "clock")]
    pub week_start: WeekStart,
    /// Week numbers
    /// Show ISO week numbers beside the calendar's rows.
    #[kurashi(default = false, module = "clock")]
    pub week_numbers: bool,
}

// --- desktop widgets (K43) --------------------------------------------------------------------

/// How a desktop card is held (I471c, K118).
#[derive(Debug, Clone, Copy, PartialEq, Eq, KurashiSchema)]
#[kurashi(i18n = "desktop_post")]
pub enum DesktopPost {
    /// Flat
    None,
    /// Pinned
    Pin,
    /// Taped
    Tape,
}

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
    /// Side for other cards
    /// The column a card neither list below names stands in. Both columns show at once: put cards on the left and on
    /// the right below (or in the desk's edit mode, Alt+Left/Right).
    #[kurashi(default = Side::Right, per_output, requires = "desktop.enabled == true")]
    pub side: Side,
    /// Posted
    /// How the cards are held on the desktop: lying flat, held by a pin, or stuck with tape. A pinned or taped card
    /// hangs a little crooked, each its own way.
    #[kurashi(default = DesktopPost::None, requires = "desktop.enabled == true", since = 7)]
    pub post: DesktopPost,
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
    /// The cards in the right column, top to bottom: the clock, the month, what plays, the weather and the mods' cards.
    /// A card the left column names stands there instead. The desk's edit mode writes it too (K48, K71).
    #[kurashi(default = strings(&["clock", "calendar", "media", "weather"]), choices_from = "desktop.cards",
              requires = "desktop.enabled == true", since = 3)]
    pub right: Vec<String>,
    /// Cards on the left
    /// The cards in the left column, top to bottom; a card named here leaves the right column.
    #[kurashi(default = strings(&[]), choices_from = "desktop.cards", requires = "desktop.enabled == true",
              since = 3)]
    pub left: Vec<String>,
    /// Hidden cards
    /// Cards the desk leaves out, named as on either side. The desk's edit mode writes it.
    #[kurashi(default = strings(&[]), advanced, requires = "desktop.enabled == true")]
    pub hidden: Vec<String>,
}

// --- launcher --------------------------------------------------------------------------------

/// What the launcher button shows (I374).
#[derive(Debug, Clone, Copy, PartialEq, Eq, KurashiSchema)]
pub enum ButtonLogo {
    /// The look's mark
    Look,
    /// The OS logo
    Os,
    /// My own image
    Own,
}

/// Where the launcher opens (I407, docs/ux/launcher.md).
#[derive(Debug, Clone, Copy, PartialEq, Eq, KurashiSchema)]
pub enum LauncherPlace {
    /// Where it was opened
    Opened,
    /// Middle of the screen
    Centre,
    /// Out of the island
    Island,
    /// A fixed place
    Fixed,
}

#[derive(Debug, Clone, PartialEq, KurashiSchema)]
#[kurashi(page = "launcher", section = "apps")]
pub struct Launcher {
    /// Opens
    /// Where it was opened: at the button you clicked, and in the middle of the screen when opened by its key. Out of
    /// the island: it grows from the bar's island. A fixed place: where the two sliders below put it.
    #[kurashi(default = LauncherPlace::Opened, module = "launcher", since = 7)]
    pub place: LauncherPlace,
    /// Across
    /// How far across the screen it stands: 0 at the left edge, 100 at the right.
    #[kurashi(default = 50, range = 0..=100, step = 5, unit = "%", requires = "launcher.place == fixed",
              module = "launcher", since = 7)]
    pub place_x: u32,
    /// Down
    /// How far down the screen it stands: 0 at the top edge, 100 at the bottom.
    #[kurashi(default = 50, range = 0..=100, step = 5, unit = "%", requires = "launcher.place == fixed",
              module = "launcher", since = 7)]
    pub place_y: u32,
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
    /// Launcher button logo
    /// What the bar's launcher button shows: the look's own mark (or the plain apps icon), your OS's logo (from
    /// os-release; a look may tint it, the PS2 look in its four colours), or an image of your own below.
    #[kurashi(default = ButtonLogo::Look, module = "launcher", since = 7)]
    pub button_logo: ButtonLogo,
    /// Your image
    /// A PNG or SVG (an absolute path or `~/…`) for the launcher button. It stays on this machine.
    #[kurashi(default = String::new(), requires = "launcher.button_logo == own", since = 7)]
    pub button_icon: String,
    /// Logo colour
    /// The OS logo or your image as the look draws it, as it is, in the text's colour, in the palette's colours as
    /// sectors (as the PS2 look does with its four), or in the palette's tones (its drawing kept, dark to light).
    #[kurashi(default = LogoTint::Look, requires = "launcher.button_logo != look", module = "launcher")]
    pub logo_tint: LogoTint,
}

/// The launcher logo's colour (session 26).
#[derive(Debug, Clone, Copy, PartialEq, Eq, KurashiSchema)]
pub enum LogoTint {
    /// As the look draws it
    Look,
    /// Original
    Original,
    /// Text colour
    Ink,
    /// Palette colours
    Palette,
    /// Palette tones
    Tones,
}

/// The app icons' colour (session 26).
#[derive(Debug, Clone, Copy, PartialEq, Eq, KurashiSchema)]
pub enum AppIconTint {
    /// Original
    Original,
    /// Text colour
    Ink,
    /// Palette tones
    Tones,
    /// Palette colours
    Palette,
}

// --- bar modules' own options (I408, docs/ux/module-menu.md) ---------------------------------------

/// What marks a workspace in the bar.
#[derive(Debug, Clone, Copy, PartialEq, Eq, KurashiSchema)]
pub enum WorkspaceMarks {
    /// As the look draws them
    Look,
    /// Numbers
    Numbers,
    /// Dots
    Dots,
}

#[derive(Debug, Clone, PartialEq, KurashiSchema)]
#[kurashi(section = "workspaces")]
pub struct WorkspacesModule {
    /// Show empty workspaces
    /// Off: only the workspaces with windows and the one you are on.
    #[kurashi(default = true, module = "workspaces", since = 7)]
    pub empty: bool,
    /// Marks
    #[kurashi(default = WorkspaceMarks::Look, module = "workspaces", since = 7)]
    pub marks: WorkspaceMarks,
    /// Scroll to switch
    /// The mouse wheel over the workspaces moves to the next or the previous one.
    #[kurashi(default = false, module = "workspaces", since = 7)]
    pub scroll: bool,
    /// Hover previews
    /// Resting on a workspace shows what it held when you last saw it. The pictures stay in memory, for this session.
    #[kurashi(default = true, module = "workspaces", since = 7)]
    pub previews: bool,
}

#[derive(Debug, Clone, PartialEq, KurashiSchema)]
#[kurashi(section = "windows")]
pub struct WindowsModule {
    /// Most windows shown
    /// The rest go under "+N". 0: as many as the bar has room for.
    #[kurashi(default = 0, range = 0..=24, step = 1, module = "windows", since = 7)]
    pub max: u32,
    /// Middle click closes
    #[kurashi(default = true, module = "windows", since = 7)]
    pub middle_close: bool,
    /// Hover previews
    /// Resting on a window shows it as you last saw it, with its title. The pictures stay in memory, for this session.
    #[kurashi(default = true, module = "windows", since = 7)]
    pub previews: bool,
}

#[derive(Debug, Clone, PartialEq, KurashiSchema)]
#[kurashi(page = "layout")]
pub struct Modules {
    #[kurashi(nested)]
    pub workspaces: WorkspacesModule,
    #[kurashi(nested)]
    pub windows: WindowsModule,
}

// --- idle (K47) ------------------------------------------------------------------------------

#[derive(Debug, Clone, PartialEq, KurashiSchema)]
#[kurashi(page = "power", section = "idle")]
pub struct Idle {
    /// Idle actions
    /// Dim, lock, turn the screens off and suspend after a time without input. Apps that play video
    /// or calls that are on keep the screen awake (they inhibit idle).
    #[kurashi(default = true, module = "caffeine")]
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
    #[kurashi(default = true, requires = "idle.enabled == true", module = "caffeine")]
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
    #[kurashi(default = false, module = "nightlight")]
    pub enabled: bool,
    /// Warmth
    /// Colour temperature at night; lower is warmer.
    #[kurashi(default = 4000, range = 1500..=6500, step = 100, unit = "K", requires = "night_light.enabled == true", module = "nightlight")]
    pub temperature: u32,
    /// Schedule
    /// When the night colours are on. Sunset to sunrise needs the weather mod's place.
    #[kurashi(default = NightSchedule::Manual, requires = "night_light.enabled == true", module = "nightlight")]
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
    #[kurashi(default = true, module = "recorder")]
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

/// One struct per side (K71): the two differ only in their sections' defaults and their mode's default; both offer
/// every section (session 20).
macro_rules! sidebar_side {
    ($name:ident, $section:literal, $module:literal, $sections:expr, $source:literal, $hidden:literal,
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
            #[kurashi(default = $mode, module = $module, since = 5)]
            pub mode: SidebarMode,
            /// Width
            /// Drag the sidebar's inner edge to change it.
            #[kurashi(default = 420, range = 320..=640, step = 10, unit = "px", since = 3)]
            pub width: u32,
            /// Visibility
            /// Hidden: opened by its key, its button in the bar or `sidebar.toggle`. On hover: rest the pointer on the
            /// screen's side. Always shown: pinned open, the windows beside it.
            #[kurashi(default = Visibility::Hidden, module = $module, since = 3)]
            pub visibility: Visibility,
            /// Pinned
            /// Kept open, the windows beside it, while pinned (the pin in the sidebar's corner); unpinned, it goes back to
            /// the visibility above, which pinning leaves as it is.
            #[kurashi(default = false, module = $module, per_output, since = 7)]
            pub pinned: bool,
            /// Keep space
            /// Whether windows keep clear of it. Automatic keeps space only while it is pinned open; Always also keeps
            /// space while it is open on hover.
            #[kurashi(default = KeepSpace::Auto, requires = $hidden, since = 3)]
            pub reserve: KeepSpace,
            /// Draw mode
            /// Dynamic: from the bar (or the screen edge) to the far edge, flush to its side, joined to the bar by
            /// rounded fillets. Floating: a gap away from every edge, every corner rounded, with the look's shadow.
            /// Automatic follows the layout's draw mode.
            #[kurashi(default = DrawChoice::Auto, module = $module, since = 3)]
            pub draw: DrawChoice,
        }
    };
}

sidebar_side!(
    SidebarRight,
    "right_sidebar",
    "sidebar_right",
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
    "sidebar_left",
    ["mod:ai:ai"],
    "sidebar.sections",
    "sidebar.left.visibility != hidden",
    "Sections",
    "Top to bottom (or one page each, with pages and tabs): the same sections the right sidebar offers — you and the session, the quick tiles, the levels, notifications, the month, what plays — and the mods' panels (AI chat, tasks, …). A section whose mod is not on is skipped. Empty: no left sidebar.",
    SidebarMode::Pages
);

#[derive(Debug, Clone, PartialEq, KurashiSchema)]
#[kurashi(page = "sidebar", section = "sidebar")]
pub struct Sidebar {
    #[kurashi(nested)]
    pub right: SidebarRight,
    #[kurashi(nested)]
    pub left: SidebarLeft,
    /// Quick settings opens the right sidebar
    /// The bar's quick settings button opens the right sidebar instead of the quick settings card. The sidebars' own
    /// buttons stay; put them in the bar or take them out below.
    #[kurashi(default = false, module = "quick")]
    pub from_bar: bool,
}

// --- the control centre (W70, I469, docs/ux/control-centre-modules.md) -----------------------------------------------

/// The control centre's tiles by default: the ten it always showed, in their order (W13, K47); then (W71 d) the rows it
/// always showed under them as wide tiles: the sound level, the brightness, the session row.
pub const QUICK_TILES: [&str; 13] = [
    "wifi",
    "bluetooth",
    "focus",
    "volume",
    "power",
    "brightness",
    "caffeine",
    "nightlight",
    "recorder",
    "darkmode",
    "volume_level",
    "brightness_level",
    "session",
];

/// How the control centre looks (W70 stage d).
#[derive(Debug, Clone, Copy, PartialEq, Eq, KurashiSchema)]
#[kurashi(i18n = "quick_style")]
pub enum QuickStyle {
    /// A card, as the others
    Card,
    /// A phone
    Phone,
}

#[derive(Debug, Clone, PartialEq, KurashiSchema)]
#[kurashi(page = "layout", section = "control_centre")]
pub struct Quick {
    /// Control centre look
    /// A card as the shell's other cards: joined to its bar, in the look's material and outline (a look may draw its own
    /// flyout instead). Or a phone: a status row with the time, a greeting and keycap tiles inside a phone's frame.
    #[kurashi(default = QuickStyle::Card, module = "quick", advanced, since = 7)]
    pub style: QuickStyle,
    /// Control centre tiles
    /// The controls the control centre shows as tiles, in order. Each is also a module of its own that a bar, a side
    /// bar or an edge group can show. The centre's edit key changes this list too. Mods' tiles follow these. The levels
    /// and the session row are wide tiles, drawn after the others in their own order. `audio` is the old name of `volume`
    /// (sound) and still places it.
    #[kurashi(default = strings(&QUICK_TILES), choices_from = "quick.tiles", since = 7)]
    pub tiles: Vec<String>,
    #[kurashi(nested)]
    pub click: QuickClicks,
    #[kurashi(nested)]
    pub value: QuickValues,
}

/// Whether a control's module shows its value beside its mark on the bar (I475, the user: "sure why not"): one switch
/// per module that has one, each tagged for that module's menu.
#[derive(Debug, Clone, PartialEq, KurashiSchema)]
pub struct QuickValues {
    /// Wi-Fi shows the network
    /// The network's name beside the Wi-Fi mark on the bar.
    #[kurashi(default = true, module = "wifi", since = 7)]
    pub wifi: bool,
    /// Sound shows the level
    /// The output's level beside the sound mark on the bar.
    #[kurashi(default = true, module = "volume", module = "audio", since = 7)]
    pub volume: bool,
    /// Power shows the charge
    /// The battery's charge beside the power mark on the bar.
    #[kurashi(default = true, module = "power", since = 7)]
    pub power: bool,
}

/// What a click on a control's module does (W71, I475 3).
#[derive(Debug, Clone, Copy, PartialEq, Eq, KurashiSchema)]
#[kurashi(i18n = "quick_click")]
pub enum QuickClick {
    /// Opens its card
    Card,
    /// Switches it
    Switch,
}

/// A click on a control's module (W71, I475 3, docs/ux/control-centre-modules.md): its card, where its switch, its
/// options and why it cannot be used stand — or, set here or in the module's menu, the switch itself. One key per module
/// with a switch, each tagged for that module's menu; brightness has no switch and keeps its card.
#[derive(Debug, Clone, PartialEq, KurashiSchema)]
pub struct QuickClicks {
    /// A click on Wi-Fi
    /// Opens its card (the networks), or switches the radio on or off.
    #[kurashi(default = QuickClick::Card, module = "wifi", since = 7)]
    pub wifi: QuickClick,
    /// A click on Bluetooth
    /// Opens its card (the devices), or switches the adapter on or off.
    #[kurashi(default = QuickClick::Card, module = "bluetooth", since = 7)]
    pub bluetooth: QuickClick,
    /// A click on Focus
    /// Opens its card (how long), or switches do not disturb on or off.
    #[kurashi(default = QuickClick::Card, module = "focus", since = 7)]
    pub focus: QuickClick,
    /// A click on sound
    /// Opens its card (outputs, inputs, what plays), or mutes and unmutes the output, as the media key does.
    #[kurashi(default = QuickClick::Card, module = "volume", module = "audio", module = "volume_level", since = 7)]
    pub volume: QuickClick,
    /// A click on the microphone
    /// Opens its card (the inputs), or mutes and unmutes the microphone.
    #[kurashi(default = QuickClick::Card, module = "mic", since = 7)]
    pub mic: QuickClick,
    /// A click on power
    /// Opens its card (the battery and the profiles), or switches the power saver on or off.
    #[kurashi(default = QuickClick::Card, module = "power", since = 7)]
    pub power: QuickClick,
    /// A click on keep awake
    /// Opens its card, or keeps the screen awake and lets it sleep again.
    #[kurashi(default = QuickClick::Card, module = "caffeine", since = 7)]
    pub caffeine: QuickClick,
    /// A click on night light
    /// Opens its card (the warmth and the schedule), or switches the night light on or off.
    #[kurashi(default = QuickClick::Card, module = "nightlight", since = 7)]
    pub nightlight: QuickClick,
    /// A click on dark mode
    /// Opens its card, or switches between light and dark.
    #[kurashi(default = QuickClick::Card, module = "darkmode", since = 7)]
    pub darkmode: QuickClick,
    /// A click on airplane mode
    /// Opens its card (with Wi-Fi), or switches every radio off or on.
    #[kurashi(default = QuickClick::Card, module = "airplane", since = 7)]
    pub airplane: QuickClick,
    /// A click on the recorder
    /// Opens its card (start and stop, which screen, the sound, where the file goes), also while a recording runs; or
    /// starts and stops recording at once.
    #[kurashi(default = QuickClick::Card, module = "recorder", since = 7)]
    pub recorder: QuickClick,
}

// --- a style's personality (W53.0b, K80, docs/ux/styles.md "Decided") ----------------------------------------------

#[derive(Debug, Clone, PartialEq, KurashiSchema)]
#[kurashi(page = "appearance", section = "lock_screen")]
pub struct Lock {
    /// Lock screen
    /// Follow the style: the lock screen its style brings, or the plain one when it brings none. Plain: the shell's own
    /// lock screen in every style. Or one lock screen by name, whatever the style.
    #[kurashi(default = "follow".to_owned(), choices_from = "lock.faces", since = 7)]
    pub face: String,
}

/// Which buttons a Stage card's title bar draws, where the style draws a title bar (K80).
#[derive(Debug, Clone, Copy, PartialEq, Eq, KurashiSchema)]
#[kurashi(i18n = "title_buttons")]
pub enum TitleButtons {
    /// No title bar
    Off,
    /// Close only
    Close,
    /// All three
    Full,
}

/// What a title bar button does (K80). Shōjiki: a button whose action has nothing to do is not drawn.
#[derive(Debug, Clone, Copy, PartialEq, Eq, KurashiSchema)]
#[kurashi(i18n = "title_action")]
pub enum TitleAction {
    /// Close the card
    Close,
    /// Hide the card
    Hide,
    /// Full screen
    FullScreen,
    /// The app's menu, else hide
    AppMenu,
    /// No button
    None,
}

#[derive(Debug, Clone, PartialEq, KurashiSchema)]
#[kurashi(page = "appearance", section = "title_bars")]
pub struct TitleBar {
    /// Title bar buttons
    /// Where the style draws a title bar on its cards (the island's cards, quick settings, menus): no title bar, only
    /// the close button, or minimize, maximize and close. A style without title bars draws none either way.
    #[kurashi(default = TitleButtons::Full, since = 7)]
    pub buttons: TitleButtons,
    /// Close button
    #[kurashi(default = TitleAction::Close, requires = "title_bar.buttons != off", since = 7)]
    pub close: TitleAction,
    /// Maximize button
    /// Full screen: the card grows to the largest size the screen has room for.
    #[kurashi(default = TitleAction::FullScreen, requires = "title_bar.buttons == full", since = 7)]
    pub maximize: TitleAction,
    /// Minimize button
    /// The app's menu: the menu its tray icon opens, where the card belongs to an app that has one (a player); every
    /// other card hides, back to the island.
    #[kurashi(default = TitleAction::AppMenu, requires = "title_bar.buttons == full", since = 7)]
    pub minimize: TitleAction,
}

/// The decoration drawn round the pointer (K80, I317).
#[derive(Debug, Clone, Copy, PartialEq, Eq, KurashiSchema)]
#[kurashi(i18n = "cursor_decoration")]
pub enum CursorDecoration {
    /// Off
    Off,
    /// The style's own
    Style,
    /// Trail
    Trail,
    /// Sparkles
    Sparkles,
    /// Ring
    Ring,
}

#[derive(Debug, Clone, PartialEq, KurashiSchema)]
#[kurashi(page = "appearance", section = "cursor")]
pub struct Cursor {
    /// The style's pointer
    /// The pointer the style brings, set as the compositor's cursor theme (niri: `kurashi-cursor.kdl`, included from
    /// its config). Off: your own cursor theme stays.
    #[kurashi(default = false, since = 7)]
    pub theme: bool,
    /// Pointer size
    #[kurashi(default = 24, range = 16..=64, step = 4, unit = "px", requires = "cursor.theme == true", since = 7)]
    pub size: u32,
    /// Pointer decoration
    /// A trail behind the pointer, sparkles or a ring round it, drawn over everything while the pointer moves and gone
    /// when it rests. Where the compositor does not say where the pointer is, none is drawn.
    #[kurashi(default = CursorDecoration::Off, since = 7)]
    pub decoration: CursorDecoration,
}
