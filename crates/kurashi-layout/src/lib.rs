//! The layout step (K71, K72): where every edge surface of an output stands — the frame, a bar per edge, the
//! edge modules, the dock, the sidebars and the island — as the `runtime.layout` document (PROTOCOL §3.1, fixture
//! `fixtures/ipc/server/snap_runtime_layout.json`). Pure: the daemon (and the mock) read the config values, the
//! tokens `space.sm` / `radius.lg` and the enabled mods' widgets, and publish what [`compute`] returns. Renderers draw
//! it and never re-derive an inset, a join or who holds an edge's exclusive zone.
//!
//! Every offset is in logical px from a screen edge, so no output size is needed. `band(e)` is the frame's thickness
//! on edge `e` while the frame is on and no bar stands flush there (a docked bar *is* the band, one sheet), else 0.
//! A dynamic or connected component stands flush on what is under it (the band, a docked bar or the screen edge) and
//! joins it (dynamic: fillets of `join_radius`; connected: straight, radius 0); a floating one stands `gap` off it.

use std::collections::BTreeMap;

use serde::Serialize;
use serde_json::Value;

/// The core modules (K72), in the order Settings offers them and `unplaced` lists them.
pub const CORE_MODULES: [&str; 11] = [
    "workspaces",
    "windows",
    "island",
    "volume",
    "recorder",
    "keyboard",
    "clock",
    "quick",
    "tray",
    "sidebar_left",
    "sidebar_right",
];
/// The pseudo module: every enabled mod widget no zone of the output names (where mod widgets went before K71).
pub const MODS: &str = "mods";

/// Reasons (i18n keys, `i18n/<locale>/layout.toml`).
pub const REASON_RESERVE_HIDDEN: &str = "layout.reserve.hidden";
pub const REASON_NOT_LISTED: &str = "layout.unplaced.not_listed";
pub const REASON_UNKNOWN: &str = "layout.module.unknown";
pub const REASON_MOD_OFF: &str = "layout.module.mod_off";
pub const REASON_NO_GLANCE: &str = "layout.module.no_glance";

// ---------------------------------------------------------------------------------------------------------------
// Settings as values

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize)]
#[serde(rename_all = "snake_case")]
pub enum Draw {
    Floating,
    Dynamic,
    Connected,
}

impl Draw {
    /// The config's spelling; anything else (`auto`, unknown) is `None`.
    pub fn parse(s: &str) -> Option<Self> {
        match s {
            "floating" => Some(Self::Floating),
            "dynamic" => Some(Self::Dynamic),
            "connected" => Some(Self::Connected),
            _ => None,
        }
    }
}

/// A component's own `draw`: `None` is `auto` (follow `layout.draw`).
pub type DrawSetting = Option<Draw>;

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize)]
#[serde(rename_all = "snake_case")]
pub enum Visibility {
    Always,
    Hover,
    EmptyDesktop,
    Hidden,
}

impl Visibility {
    pub fn parse(s: &str) -> Option<Self> {
        match s {
            "always" => Some(Self::Always),
            "hover" => Some(Self::Hover),
            "empty_desktop" => Some(Self::EmptyDesktop),
            "hidden" => Some(Self::Hidden),
            _ => None,
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Reserve {
    Auto,
    On,
    Off,
}

impl Reserve {
    pub fn parse(s: &str) -> Option<Self> {
        match s {
            "auto" => Some(Self::Auto),
            "on" => Some(Self::On),
            "off" => Some(Self::Off),
            _ => None,
        }
    }

    /// K71: `auto` keeps space only for `always`, `on` also while hidden by hover, `off` never; `hidden` never keeps
    /// space (the setting is inert there, `layout.reserve.hidden`).
    fn keeps(self, v: Visibility) -> bool {
        match (v, self) {
            (Visibility::Hidden, _) | (_, Reserve::Off) => false,
            (_, Reserve::On) => true,
            (v, Reserve::Auto) => v == Visibility::Always,
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, PartialOrd, Ord)]
pub enum Edge {
    Top,
    Bottom,
    Left,
    Right,
}

impl Edge {
    /// The order every search runs in (holder, island, a bar's edge): top, bottom, left, right.
    pub const ALL: [Edge; 4] = [Edge::Top, Edge::Bottom, Edge::Left, Edge::Right];

    pub fn name(self) -> &'static str {
        match self {
            Edge::Top => "top",
            Edge::Bottom => "bottom",
            Edge::Left => "left",
            Edge::Right => "right",
        }
    }

    pub fn parse(s: &str) -> Option<Self> {
        Self::ALL.into_iter().find(|e| e.name() == s)
    }

    fn index(self) -> usize {
        self as usize
    }
}

/// The three zones of an edge, start to end (a side edge's run top to bottom).
pub const ZONES: [&str; 3] = ["start", "center", "end"];

/// One edge's settings (`edges.<e>.*`).
#[derive(Debug, Clone, PartialEq)]
pub struct EdgeConfig {
    pub bar: bool,
    pub visibility: Visibility,
    pub reserve: Reserve,
    pub draw: DrawSetting,
    /// `start`, `center`, `end`: module ids as the config lists them.
    pub zones: [Vec<String>; 3],
}

impl EdgeConfig {
    /// An edge without a bar or modules, shown always, following the preset.
    pub fn empty() -> Self {
        Self {
            bar: false,
            visibility: Visibility::Always,
            reserve: Reserve::Auto,
            draw: None,
            zones: Default::default(),
        }
    }
}

#[derive(Debug, Clone, PartialEq)]
pub struct FrameConfig {
    pub enabled: bool,
    pub thickness: u32,
    pub reserve: bool,
}

#[derive(Debug, Clone, PartialEq)]
pub struct DockConfig {
    pub enabled: bool,
    pub edge: Edge,
    pub visibility: Visibility,
    pub reserve: Reserve,
    pub draw: DrawSetting,
    /// The dock's thickness across its edge (its icons and padding), for the space it keeps.
    pub size: u32,
}

#[derive(Debug, Clone, PartialEq)]
pub struct SidebarConfig {
    pub width: u32,
    pub visibility: Visibility,
    pub reserve: Reserve,
    pub draw: DrawSetting,
}

/// Everything one output's layout depends on, as the config resolves it for that output.
#[derive(Debug, Clone, PartialEq)]
pub struct OutputConfig {
    /// `bar.height` on this output: every bar's thickness, and an edge module group's.
    pub bar_size: u32,
    pub frame: FrameConfig,
    /// Top, bottom, left, right ([`Edge::ALL`] order).
    pub edges: [EdgeConfig; 4],
    pub dock: DockConfig,
    pub sidebar_right: SidebarConfig,
    pub sidebar_left: SidebarConfig,
    /// `island.main.draw`.
    pub island_draw: DrawSetting,
}

/// A mod as the layout sees it: whether it is on and the widgets (`widget:<name>`) its manifest provides, in
/// manifest order. Mods come in mod order (the registry's).
#[derive(Debug, Clone, PartialEq)]
pub struct ModWidgets {
    pub id: String,
    pub enabled: bool,
    pub widgets: Vec<String>,
}

/// The values every output shares.
#[derive(Debug, Clone, PartialEq)]
pub struct Globals {
    /// `layout.draw`, the preset an `auto` component follows.
    pub draw: Draw,
    pub reveal_delay_ms: u32,
    /// Token `space.sm`.
    pub gap: u32,
    /// Token `radius.lg`.
    pub join_radius: u32,
    /// `theme.shape.screen_corners_follow`: the screen's corners take `join_radius`.
    pub screen_follow: bool,
    /// `theme.shape.screen_corners`, the screen's corners while they do not follow.
    pub screen_corners: u32,
    /// The global `bar.height`.
    pub bar_size: u32,
}

#[derive(Debug, Clone, PartialEq)]
pub struct Input {
    pub globals: Globals,
    pub mods: Vec<ModWidgets>,
    /// By output name; `"*"` is the layout for an output the daemon does not know yet (the global values).
    pub outputs: BTreeMap<String, OutputConfig>,
}

// ---------------------------------------------------------------------------------------------------------------
// The document (field order is the fixture's: struct fields serialize in declaration order)

#[derive(Debug, Clone, PartialEq, Serialize)]
pub struct Document {
    pub draw: Draw,
    pub reveal_delay_ms: u32,
    pub gap: u32,
    pub join_radius: u32,
    pub screen_radius: u32,
    pub bar_size: u32,
    pub outputs: BTreeMap<String, OutputLayout>,
}

impl Document {
    pub fn to_value(&self) -> Value {
        serde_json::to_value(self).unwrap_or_default()
    }
}

#[derive(Debug, Clone, PartialEq, Serialize)]
pub struct OutputLayout {
    pub frame: Frame,
    pub edges: Edges,
    pub dock: Dock,
    pub sidebars: Sidebars,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub island: Option<Island>,
    pub unplaced: Vec<Unplaced>,
    pub problems: Vec<Problem>,
}

impl OutputLayout {
    pub fn edge(&self, e: Edge) -> &EdgeLayout {
        match e {
            Edge::Top => &self.edges.top,
            Edge::Bottom => &self.edges.bottom,
            Edge::Left => &self.edges.left,
            Edge::Right => &self.edges.right,
        }
    }
}

#[derive(Debug, Clone, PartialEq, Serialize)]
pub struct Frame {
    pub on: bool,
    pub thickness: u32,
    pub radius: u32,
    pub reserve: bool,
    pub band: PerEdge,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize)]
pub struct PerEdge {
    pub top: u32,
    pub bottom: u32,
    pub left: u32,
    pub right: u32,
}

impl PerEdge {
    fn of(f: impl Fn(Edge) -> u32) -> Self {
        Self {
            top: f(Edge::Top),
            bottom: f(Edge::Bottom),
            left: f(Edge::Left),
            right: f(Edge::Right),
        }
    }
}

#[derive(Debug, Clone, PartialEq, Serialize)]
pub struct Edges {
    pub top: EdgeLayout,
    pub bottom: EdgeLayout,
    pub left: EdgeLayout,
    pub right: EdgeLayout,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize)]
#[serde(rename_all = "snake_case")]
pub enum Source {
    /// Followed the preset (`draw`) or the automatic rule (`reserve`).
    Auto,
    /// The user's own value.
    Set,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize)]
#[serde(rename_all = "snake_case")]
pub enum Holder {
    Frame,
    Bar,
    Dock,
    Sidebar,
    Module,
    None,
}

#[derive(Debug, Clone, PartialEq, Serialize)]
pub struct EdgeLayout {
    pub bar: bool,
    pub draw: Draw,
    pub draw_source: Source,
    pub visibility: Visibility,
    /// Screen edge → the outer edge of the edge's surface (its bar, else its module groups).
    pub inset: u32,
    /// The edge's whole exclusive zone (px), set by `holder`.
    pub reserve: u32,
    pub reserve_source: Source,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub reserve_reason: Option<&'static str>,
    pub holder: Holder,
    pub zones: Zones,
    /// The bar's thickness; only with a bar.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub size: Option<u32>,
    /// A side bar's free length along its edge (px from the top and the bottom); only on a left or right bar.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub span: Option<Span>,
}

#[derive(Debug, Clone, PartialEq, Default, Serialize)]
pub struct Zones {
    pub start: Vec<Module>,
    pub center: Vec<Module>,
    pub end: Vec<Module>,
}

impl Zones {
    fn is_empty(&self) -> bool {
        self.start.is_empty() && self.center.is_empty() && self.end.is_empty()
    }

    fn get_mut(&mut self, i: usize) -> &mut Vec<Module> {
        match i {
            0 => &mut self.start,
            1 => &mut self.center,
            _ => &mut self.end,
        }
    }

    pub fn get(&self, i: usize) -> &[Module] {
        match i {
            0 => &self.start,
            1 => &self.center,
            _ => &self.end,
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize)]
#[serde(rename_all = "snake_case")]
pub enum Kind {
    Core,
    Mod,
}

/// A zone entry (K72): a core module, or a mod's widget as `mod:<id>:<name>` with its mod and provide.
#[derive(Debug, Clone, PartialEq, Serialize)]
pub struct Module {
    pub id: String,
    pub kind: Kind,
    #[serde(rename = "mod", skip_serializing_if = "Option::is_none")]
    pub mod_id: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub provide: Option<String>,
}

impl Module {
    fn core(id: &str) -> Self {
        Self {
            id: id.into(),
            kind: Kind::Core,
            mod_id: None,
            provide: None,
        }
    }

    fn widget(mod_id: &str, name: &str) -> Self {
        Self {
            id: format!("mod:{mod_id}:{name}"),
            kind: Kind::Mod,
            mod_id: Some(mod_id.into()),
            provide: Some(format!("widget:{name}")),
        }
    }
}

#[derive(Debug, Clone, PartialEq, Serialize)]
pub struct Unplaced {
    #[serde(flatten)]
    pub module: Module,
    pub reason: &'static str,
}

#[derive(Debug, Clone, PartialEq, Serialize)]
pub struct Problem {
    pub id: String,
    /// The config key of the zone (`edges.top.end`).
    pub zone: String,
    pub reason: &'static str,
}

#[derive(Debug, Clone, PartialEq, Serialize)]
pub struct Dock {
    pub on: bool,
    pub edge: &'static str,
    pub draw: Draw,
    pub draw_source: Source,
    pub visibility: Visibility,
    pub inset: u32,
    pub reserve: u32,
    pub reserve_source: Source,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub reserve_reason: Option<&'static str>,
    /// `frame`, `bar:<edge>` or `edge`; absent while floating.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub joins: Option<String>,
    pub radius: u32,
}

#[derive(Debug, Clone, PartialEq, Serialize)]
pub struct Sidebars {
    pub right: Sidebar,
    pub left: Sidebar,
}

#[derive(Debug, Clone, PartialEq, Serialize)]
pub struct Sidebar {
    pub draw: Draw,
    pub draw_source: Source,
    pub visibility: Visibility,
    pub width: u32,
    pub inset: u32,
    pub reserve: u32,
    pub reserve_source: Source,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub reserve_reason: Option<&'static str>,
    pub span: Span,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub joins: Option<Joins>,
    pub radius: u32,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize)]
pub struct Span {
    pub start: u32,
    pub end: u32,
}

#[derive(Debug, Clone, PartialEq, Serialize)]
pub struct Joins {
    pub start: String,
    pub end: String,
}

#[derive(Debug, Clone, PartialEq, Serialize)]
pub struct Island {
    pub edge: &'static str,
    pub zone: &'static str,
    /// `bar` when its edge has a bar, else `module` (the standalone island).
    pub host: &'static str,
    pub draw: Draw,
    pub draw_source: Source,
}

// ---------------------------------------------------------------------------------------------------------------
// The step

pub fn compute(input: &Input) -> Document {
    let g = &input.globals;
    Document {
        draw: g.draw,
        reveal_delay_ms: g.reveal_delay_ms,
        gap: g.gap,
        join_radius: g.join_radius,
        screen_radius: screen_radius(g),
        bar_size: g.bar_size,
        outputs: input
            .outputs
            .iter()
            .map(|(name, cfg)| (name.clone(), output(g, &input.mods, cfg)))
            .collect(),
    }
}

fn resolve(own: DrawSetting, preset: Draw) -> (Draw, Source) {
    match own {
        Some(d) => (d, Source::Set),
        None => (preset, Source::Auto),
    }
}

fn reserve_source(r: Reserve) -> Source {
    if r == Reserve::Auto {
        Source::Auto
    } else {
        Source::Set
    }
}

fn reserve_reason(v: Visibility) -> Option<&'static str> {
    (v == Visibility::Hidden).then_some(REASON_RESERVE_HIDDEN)
}

/// The corners of the window cut into the shell's sheet (K74): the one radius `R` (`radius.lg`), less the frame's
/// thickness on a framed output — the inner curve of a band `thickness` wide round a corner of radius `R` — so the
/// frame's inner corners, every dynamic join and the corners of what stands on the band are one radius, concentric
/// with the screen's corner and the look's panels.
fn hole_radius(cfg: &OutputConfig, g: &Globals) -> u32 {
    if cfg.frame.enabled {
        g.join_radius.saturating_sub(cfg.frame.thickness)
    } else {
        g.join_radius
    }
}

/// The screen's outer corners (K74): the radius itself by default — the frame's band runs round them and its inner
/// corner is the hole's radius, so screen, band and hole are concentric —, else `theme.shape.screen_corners`.
fn screen_radius(g: &Globals) -> u32 {
    if g.screen_follow {
        g.join_radius
    } else {
        g.screen_corners
    }
}

/// The radius of a join: dynamic's fillet (the hole's radius), connected's straight corner; floating has no join.
fn join_radius(draw: Draw, cfg: &OutputConfig, g: &Globals) -> u32 {
    if draw == Draw::Dynamic {
        hole_radius(cfg, g)
    } else {
        0
    }
}

/// One output's layout.
pub fn output(g: &Globals, mods: &[ModWidgets], cfg: &OutputConfig) -> OutputLayout {
    let draw_of = |e: Edge| resolve(cfg.edges[e.index()].draw, g.draw);
    // A bar flush on its edge: it is the frame's band there (any visibility but hidden: a hover bar's place stays the
    // band's; a hidden bar comes out over the band).
    let docked = |e: Edge| {
        let ec = &cfg.edges[e.index()];
        ec.bar && draw_of(e).0 != Draw::Floating && ec.visibility != Visibility::Hidden
    };
    let band = |e: Edge| {
        if cfg.frame.enabled && !docked(e) {
            cfg.frame.thickness
        } else {
            0
        }
    };
    let frame_reserves = cfg.frame.enabled && cfg.frame.reserve;
    // What a component standing on edge `e` stands on: a docked bar's inner edge, else the band (or the screen edge).
    let base = |e: Edge| {
        if docked(e) { cfg.bar_size } else { band(e) }
    };
    // What a component standing on `e` meets there.
    let meets = |e: Edge| {
        if docked(e) {
            format!("bar:{}", e.name())
        } else if band(e) > 0 {
            "frame".to_string()
        } else {
            "edge".to_string()
        }
    };

    let (zones, unplaced, problems) = resolve_zones(mods, cfg);

    // The dock.
    let dock_cfg = &cfg.dock;
    let (dock_draw, dock_draw_source) = resolve(dock_cfg.draw, g.draw);
    let de = dock_cfg.edge;
    let dock_under = if cfg.edges[de.index()].bar {
        edge_inset(cfg, g, de, band(de), draw_of(de).0) + cfg.bar_size
    } else {
        band(de)
    };
    let dock_inset = dock_under
        + if dock_draw == Draw::Floating {
            g.gap
        } else {
            0
        };
    let dock_keeps = dock_cfg.enabled && dock_cfg.reserve.keeps(dock_cfg.visibility);
    let dock = Dock {
        on: dock_cfg.enabled,
        edge: de.name(),
        draw: dock_draw,
        draw_source: dock_draw_source,
        visibility: dock_cfg.visibility,
        inset: dock_inset,
        reserve: if dock_keeps {
            dock_inset + dock_cfg.size
        } else {
            0
        },
        reserve_source: reserve_source(dock_cfg.reserve),
        reserve_reason: reserve_reason(dock_cfg.visibility),
        joins: (dock_draw != Draw::Floating).then(|| {
            if cfg.edges[de.index()].bar {
                format!("bar:{}", de.name())
            } else {
                meets(de)
            }
        }),
        radius: join_radius(dock_draw, cfg, g),
    };

    // A floating top/bottom bar that is not hidden: a sidebar ends a gap before it in every draw mode (I253, user
    // decision (a)) and meets nothing there.
    let floats_over = |e: Edge| {
        let ec = &cfg.edges[e.index()];
        ec.bar && ec.visibility != Visibility::Hidden && draw_of(e).0 == Draw::Floating
    };
    // Where a sidebar's end along edge `e` stands (px from that edge, before its own float gap) and what it meets.
    let sidebar_end = |e: Edge| {
        if floats_over(e) {
            (
                edge_inset(cfg, g, e, band(e), Draw::Floating) + cfg.bar_size,
                "none".to_string(),
            )
        } else {
            (base(e), meets(e))
        }
    };

    // The sidebars: from what stands on the top edge to what stands on the bottom one, flush to their side.
    let sidebar = |s: &SidebarConfig, side: Edge| {
        let (draw, draw_source) = resolve(s.draw, g.draw);
        let float = if draw == Draw::Floating { g.gap } else { 0 };
        let (top, top_meets) = sidebar_end(Edge::Top);
        let (bottom, bottom_meets) = sidebar_end(Edge::Bottom);
        // A gap off a floating bar whatever the sidebar's own draw (it already carries one when floating itself).
        let off = |e: Edge| {
            if floats_over(e) {
                g.gap.max(float)
            } else {
                float
            }
        };
        let inset = base(side) + float;
        let keeps = s.reserve.keeps(s.visibility);
        Sidebar {
            draw,
            draw_source,
            visibility: s.visibility,
            width: s.width,
            inset,
            reserve: if keeps { inset + s.width } else { 0 },
            reserve_source: reserve_source(s.reserve),
            reserve_reason: reserve_reason(s.visibility),
            span: Span {
                start: top + off(Edge::Top),
                end: bottom + off(Edge::Bottom),
            },
            joins: (draw != Draw::Floating).then_some(Joins {
                start: top_meets,
                end: bottom_meets,
            }),
            radius: join_radius(draw, cfg, g),
        }
    };
    let sidebars = Sidebars {
        right: sidebar(&cfg.sidebar_right, Edge::Right),
        left: sidebar(&cfg.sidebar_left, Edge::Left),
    };

    // The horizontal bars own the corners; a side bar runs between them (row 511): past a top/bottom bar that is not
    // hidden, else from the band.
    let across = |e: Edge| {
        let ec = &cfg.edges[e.index()];
        if ec.bar && ec.visibility != Visibility::Hidden {
            edge_inset(cfg, g, e, band(e), draw_of(e).0) + cfg.bar_size
        } else {
            band(e)
        }
    };
    let mut edge_layouts: Vec<EdgeLayout> = Vec::with_capacity(4);
    for (e, z) in Edge::ALL.into_iter().zip(zones) {
        let ec = &cfg.edges[e.index()];
        let (draw, draw_source) = draw_of(e);
        let inset = edge_inset(cfg, g, e, band(e), draw);
        let keeps = ec.reserve.keeps(ec.visibility);
        // The edge's own surface: its bar, else its module groups (as thick as a bar).
        let own = if (ec.bar || !z.is_empty()) && keeps {
            inset + cfg.bar_size
        } else {
            0
        };
        let dock_here = if dock_cfg.enabled && de == e {
            dock.reserve
        } else {
            0
        };
        let sidebar_here = match e {
            Edge::Right => sidebars.right.reserve,
            Edge::Left => sidebars.left.reserve,
            _ => 0,
        };
        // A docked bar carries its edge's frame strip (row 492 b), so it keeps the frame's part of the zone too.
        let frame_here = match (frame_reserves, docked(e)) {
            (false, _) => 0,
            (true, true) => cfg.frame.thickness,
            (true, false) => band(e),
        };
        let reserve = frame_here.max(own).max(dock_here).max(sidebar_here);
        // Exactly one surface holds the edge's exclusive zone (K71): frame > bar > dock > sidebar > module > none; on
        // a framed edge whose strip a docked bar carries, the bar (row 510).
        let holder = if frame_reserves && docked(e) {
            Holder::Bar
        } else if frame_reserves {
            Holder::Frame
        } else if ec.bar && own > 0 {
            Holder::Bar
        } else if dock_here > 0 {
            Holder::Dock
        } else if sidebar_here > 0 {
            Holder::Sidebar
        } else if own > 0 {
            Holder::Module
        } else {
            Holder::None
        };
        edge_layouts.push(EdgeLayout {
            bar: ec.bar,
            draw,
            draw_source,
            visibility: ec.visibility,
            inset,
            reserve,
            reserve_source: reserve_source(ec.reserve),
            reserve_reason: reserve_reason(ec.visibility),
            holder,
            zones: z,
            size: ec.bar.then_some(cfg.bar_size),
            span: (ec.bar && matches!(e, Edge::Left | Edge::Right)).then(|| {
                let float = if draw == Draw::Floating { g.gap } else { 0 };
                Span {
                    start: across(Edge::Top) + float,
                    end: across(Edge::Bottom) + float,
                }
            }),
        });
    }
    let mut it = edge_layouts.into_iter();
    let mut next = || it.next().expect("four edges");
    let edges = Edges {
        top: next(),
        bottom: next(),
        left: next(),
        right: next(),
    };

    let island = Edge::ALL.into_iter().find_map(|e| {
        let el = match e {
            Edge::Top => &edges.top,
            Edge::Bottom => &edges.bottom,
            Edge::Left => &edges.left,
            Edge::Right => &edges.right,
        };
        (0..3)
            .find(|&i| el.zones.get(i).iter().any(|m| m.id == "island"))
            .map(|i| {
                let (draw, draw_source) = resolve(cfg.island_draw, g.draw);
                Island {
                    edge: e.name(),
                    zone: ZONES[i],
                    host: if el.bar { "bar" } else { "module" },
                    draw,
                    draw_source,
                }
            })
    });

    OutputLayout {
        frame: Frame {
            on: cfg.frame.enabled,
            thickness: cfg.frame.thickness,
            radius: hole_radius(cfg, g),
            reserve: cfg.frame.reserve,
            band: PerEdge::of(band),
        },
        edges,
        dock,
        sidebars,
        island,
        unplaced,
        problems,
    }
}

/// Screen edge → the outer edge of edge `e`'s own surface: a docked bar stands on the screen edge; a floating bar, and
/// the modules of an edge without a bar, stand on the band (a gap off it when floating).
fn edge_inset(cfg: &OutputConfig, g: &Globals, e: Edge, band: u32, draw: Draw) -> u32 {
    let float = if draw == Draw::Floating { g.gap } else { 0 };
    if cfg.edges[e.index()].bar && draw != Draw::Floating {
        0
    } else {
        band + float
    }
}

/// The zones resolved to entries (K72): `mods` expanded to the enabled mod widgets no zone names, entries that cannot
/// be drawn moved to `problems`, and every enabled module with a glance no zone shows listed in `unplaced`.
fn resolve_zones(
    mods: &[ModWidgets],
    cfg: &OutputConfig,
) -> ([Zones; 4], Vec<Unplaced>, Vec<Problem>) {
    let named: Vec<&str> = cfg
        .edges
        .iter()
        .flat_map(|e| e.zones.iter().flatten())
        .map(String::as_str)
        .collect();
    let holds_mods = named.contains(&MODS);
    let mut expanded = false;
    let mut problems = Vec::new();
    let mut out: [Zones; 4] = Default::default();
    for e in Edge::ALL {
        for (i, list) in cfg.edges[e.index()].zones.iter().enumerate() {
            let zone = format!("edges.{}.{}", e.name(), ZONES[i]);
            let target = out[e.index()].get_mut(i);
            for id in list {
                if id == MODS {
                    // Once per output: a second `mods` would show the same widgets twice.
                    if !expanded {
                        expanded = true;
                        for m in mods.iter().filter(|m| m.enabled) {
                            for w in &m.widgets {
                                let full = format!("mod:{}:{w}", m.id);
                                if !named.contains(&full.as_str()) {
                                    target.push(Module::widget(&m.id, w));
                                }
                            }
                        }
                    }
                    continue;
                }
                match entry(mods, id) {
                    Ok(m) => target.push(m),
                    Err(reason) => problems.push(Problem {
                        id: id.clone(),
                        zone: zone.clone(),
                        reason,
                    }),
                }
            }
        }
    }
    let shown = |id: &str| {
        out.iter()
            .any(|z| (0..3).any(|i| z.get(i).iter().any(|m| m.id == id)))
    };
    let mut unplaced: Vec<Unplaced> = CORE_MODULES
        .iter()
        .filter(|id| !shown(id))
        .map(|id| Unplaced {
            module: Module::core(id),
            reason: REASON_NOT_LISTED,
        })
        .collect();
    if !holds_mods {
        for m in mods.iter().filter(|m| m.enabled) {
            for w in &m.widgets {
                let module = Module::widget(&m.id, w);
                if !shown(&module.id) {
                    unplaced.push(Unplaced {
                        module,
                        reason: REASON_NOT_LISTED,
                    });
                }
            }
        }
    }
    (out, unplaced, problems)
}

/// A listed id as a zone entry, or why it cannot be drawn.
fn entry(mods: &[ModWidgets], id: &str) -> Result<Module, &'static str> {
    if CORE_MODULES.contains(&id) {
        return Ok(Module::core(id));
    }
    let Some((mod_id, name)) = id
        .strip_prefix("mod:")
        .and_then(|rest| rest.split_once(':'))
        .filter(|(m, n)| !m.is_empty() && !n.is_empty())
    else {
        return Err(REASON_UNKNOWN);
    };
    let Some(m) = mods.iter().find(|m| m.id == mod_id) else {
        return Err(REASON_UNKNOWN);
    };
    if !m.enabled {
        return Err(REASON_MOD_OFF);
    }
    if !m.widgets.iter().any(|w| w == name) {
        return Err(REASON_NO_GLANCE);
    }
    Ok(Module::widget(mod_id, name))
}

#[cfg(test)]
mod tests;
