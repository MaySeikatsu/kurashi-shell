//! The dock's state and its document (K38, K40, MODS.md "Web dock"): the pins the settings name, the mode and the
//! shown pin, the hover and focus state with its deadlines (K40), the host's reports and the host's lifecycle as
//! far as the state decides it. Pure: `lib.rs` feeds it actions, settings, host states and the clock (`Instant`s),
//! and publishes [`Dock::doc`]. Everything here is what the daemon owns (rule 1).

use std::collections::BTreeMap;
use std::path::{Component, Path, PathBuf};
use std::time::Duration;

use kurashi_mod_api::{HostState, Settings};
use serde_json::{Map, Value, json};
use tokio::time::Instant;

/// The hysteresis every part's input region adds around what it draws (MODS.md: `geometry.grace`).
pub const GRACE_PX: u32 = 24;
/// A rest on an edge reveals the dock after `REVEAL`, or after `REVEAL_SHARED` on an edge that borders another output
/// (K40: the pointer crossing from the other output must not open the dock).
pub const REVEAL: Duration = Duration::from_millis(250);
pub const REVEAL_SHARED: Duration = Duration::from_millis(500);
/// A dock that nothing holds (no part inside, not pinned, not engaged) hides after `HIDE` (K40).
pub const HIDE: Duration = Duration::from_millis(400);
/// A page that played sound counts as playing for this long after its last sound (W73, docs/ux/webdock.md "Background
/// pages"): the gap between two tracks and a player paused for a moment keep their page awake, loaded and the engine up.
pub const AUDIBLE_GRACE: Duration = Duration::from_secs(10 * 60);
/// The permissions a page can be blocked on (MODS.md: `webdock.host.blocked`).
pub const PERMISSIONS: &[&str] = &[
    "camera",
    "microphone",
    "location",
    "notifications",
    "screen",
    "clipboard",
    "download",
    "other",
];

/// Where the dock's card is (MODS.md: `mode`).
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Mode {
    Hidden,
    Compact,
    Extended,
}

impl Mode {
    fn name(self) -> &'static str {
        match self {
            Self::Hidden => "hidden",
            Self::Compact => "compact",
            Self::Extended => "extended",
        }
    }
}

/// The card's width: a phone column, or a share of the output (MODS.md: `size`).
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Size {
    Phone,
    Large,
}

impl Size {
    fn name(self) -> &'static str {
        match self {
            Self::Phone => "phone",
            Self::Large => "large",
        }
    }
}

/// The user agent a site is shown with (MODS.md: `view`).
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum View {
    Mobile,
    Desktop,
}

impl View {
    pub fn name(self) -> &'static str {
        match self {
            Self::Mobile => "mobile",
            Self::Desktop => "desktop",
        }
    }
}

/// The view a pin's setting asks for: its own, or the default (`default_view`).
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ViewSetting {
    Default,
    Mobile,
    Desktop,
}

/// What a pin shows: a site (`web`), or a kurashi view of a mod (`mod:<id>:<panel>`, `view`).
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Kind {
    Web,
    View,
}

/// Where a link that asks for a new tab goes (MODS.md: `new_tabs`): the pin's own view, or the default browser.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum NewTabs {
    Dock,
    Browser,
}

impl NewTabs {
    fn name(self) -> &'static str {
        match self {
            Self::Dock => "dock",
            Self::Browser => "browser",
        }
    }
}

/// How the card frames its page (`page_style`, W69; docs/ux/webdock.md "Page styles"): a phone (a tablet in the large
/// size), one half of an opened spiral notebook, or the shell's plain card.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum PageStyle {
    Phone,
    Notebook,
    Plain,
}

impl PageStyle {
    fn name(self) -> &'static str {
        match self {
            Self::Phone => "phone",
            Self::Notebook => "notebook",
            Self::Plain => "plain",
        }
    }
}

/// The bar card's size (`card_size`, W73; docs/ux/webdock.md "The card's size"): the edge card's own box (`dock`,
/// W74: `width` × twice that, the default), a phone's, a tablet's or a small laptop's viewport.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum CardSize {
    Dock,
    Phone,
    Tablet,
    Wide,
}

impl CardSize {
    /// The order the card's size key steps through (W74), the default first.
    const CYCLE: [Self; 4] = [Self::Dock, Self::Phone, Self::Tablet, Self::Wide];

    fn name(self) -> &'static str {
        match self {
            Self::Dock => "dock",
            Self::Phone => "phone",
            Self::Tablet => "tablet",
            Self::Wide => "wide",
        }
    }

    fn parse(name: &str) -> Option<Self> {
        Self::CYCLE.into_iter().find(|s| s.name() == name)
    }
}

/// The `card_size` a press of the bar card's size key writes (W74, `webdock.card_size {size?}`): the size asked for,
/// else the one after the value in effect (an unknown value counts as the default). A value the configuration forces is
/// not the user's to change: refused, as the key is inert (rule 2).
pub fn card_size_step(
    current: Option<&str>,
    want: Option<&str>,
    forced: bool,
) -> Result<&'static str, DockError> {
    if forced {
        return Err(DockError::Forced);
    }
    if let Some(want) = want {
        return CardSize::parse(want)
            .map(CardSize::name)
            .ok_or(DockError::CardSize);
    }
    let now = current.and_then(CardSize::parse).unwrap_or(CardSize::Dock);
    let at = CardSize::CYCLE.iter().position(|s| *s == now).unwrap_or(0);
    Ok(CardSize::CYCLE[(at + 1) % CardSize::CYCLE.len()].name())
}

/// What the strip lists (`content`, W78; docs/ux/webdock.md "Local mode"): the sites, or the shell's own views.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Content {
    Online,
    Local,
}

impl Content {
    fn name(self) -> &'static str {
        match self {
            Self::Online => "online",
            Self::Local => "local",
        }
    }

    fn parse(name: &str) -> Option<Self> {
        match name {
            "online" => Some(Self::Online),
            "local" => Some(Self::Local),
            _ => None,
        }
    }

    /// Whether the strip lists a pin of this kind in this mode: Online the sites, Local the shell's own views (the
    /// user, session 32: "sites only"; CONTRACT-CHANGE 760).
    fn lists(self, kind: Kind) -> bool {
        match self {
            Self::Online => kind == Kind::Web,
            Self::Local => kind == Kind::View,
        }
    }
}

/// The `content` a press of the strip's switch writes (W78, `webdock.content {content?}`): the mode asked for, else the
/// other one than the value in effect (an unknown value counts as online). Refused while the configuration forces it.
pub fn content_step(
    current: Option<&str>,
    want: Option<&str>,
    forced: bool,
) -> Result<&'static str, DockError> {
    if forced {
        return Err(DockError::Forced);
    }
    if let Some(want) = want {
        return Content::parse(want)
            .map(Content::name)
            .ok_or(DockError::Content);
    }
    Ok(match current.and_then(Content::parse) {
        Some(Content::Local) => Content::Online.name(),
        _ => Content::Local.name(),
    })
}

/// The three places a pin's page can show in (W73, docs/ux/webdock.md "Which place shows the page").
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Spot {
    Edge,
    Sidebar,
    Card,
}

impl Spot {
    /// The place an action names (`edge`, `sidebar` or `card`; W76 `webdock.browse`).
    pub fn parse(name: &str) -> Option<Self> {
        match name {
            "edge" => Some(Self::Edge),
            "sidebar" => Some(Self::Sidebar),
            "card" => Some(Self::Card),
            _ => None,
        }
    }

    fn name(self) -> &'static str {
        match self {
            Self::Edge => "edge",
            Self::Sidebar => "sidebar",
            Self::Card => "card",
        }
    }
}

/// A part of the dock the pointer or the keyboard can be in (K40): the screen edge that reveals the dock, the strip
/// and the card (the mod's own card for a site, the shell's for a view).
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Part {
    Edge,
    Strip,
    Card,
}

impl Part {
    /// The part an action names (`edge`, `strip` or `card`).
    pub fn parse(name: &str) -> Option<Self> {
        match name {
            "edge" => Some(Self::Edge),
            "strip" => Some(Self::Strip),
            "card" => Some(Self::Card),
            _ => None,
        }
    }
}

/// The parts the pointer is inside, on the dock's output.
#[derive(Debug, Clone, Copy, Default, PartialEq, Eq)]
struct Inside {
    edge: bool,
    strip: bool,
    card: bool,
}

impl Inside {
    fn any(self) -> bool {
        self.edge || self.strip || self.card
    }

    fn set(&mut self, part: Part, on: bool) {
        match part {
            Part::Edge => self.edge = on,
            Part::Strip => self.strip = on,
            Part::Card => self.card = on,
        }
    }
}

/// What the dock waits for (K40): a reveal from an edge the pointer rests on, or a hide once nothing holds the dock.
/// At most one is pending: a reveal only while hidden, a hide only while shown.
#[derive(Debug, Clone, PartialEq, Eq)]
enum Pending {
    Reveal { at: Instant, output: String },
    Hide { at: Instant },
}

impl Pending {
    fn at(&self) -> Instant {
        match self {
            Self::Reveal { at, .. } | Self::Hide { at } => *at,
        }
    }
}

/// One pin as the settings name it (MODS.md: the `pins` records).
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct PinSpec {
    pub id: String,
    pub title: String,
    pub target: String,
    pub kind: Kind,
    pub view: ViewSetting,
    /// The profile the site's storage lives in: the pin's own, or its id.
    pub profile: String,
    /// "Keep running in the background" (W73): never frozen while loaded, never unloaded by the dock's rules.
    pub background: bool,
    /// W76: a page the daemon serves that the settings do not hold (`temporary` in the document); `None` for a row.
    pub temp: Option<Temp>,
}

/// A temporary page (W76, docs/ux/webdock.md "Round three"): what "+" opened (until it is pinned, its place leaves it, or
/// Esc in its empty field), or a pin unpinned with "Unpin but keep open" (until the dock's rules unload it).
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Temp {
    Browse,
    Kept,
}

/// The profile every page opened from "+" shares (W76): a browser's default profile. A pin made from such a page keeps it.
pub const BROWSE_PROFILE: &str = "browse";
/// The search engine when `search` is unset or not an `http`/`https` URL (W76): DuckDuckGo; `{q}` is the words.
pub const DEFAULT_SEARCH: &str = "https://duckduckgo.com/?q={q}";
/// A remembered card box is at least this big on each side (W76, `sizes`).
pub const MIN_BOX: u32 = 300;
/// … and at most this (a sanity bound: the shell clamps to the output it is drawn on).
pub const MAX_BOX: u32 = 8192;

/// Why an action or a host report is refused (its i18n key is in [`DockError::key`]).
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum DockError {
    UnknownPin,
    /// The pin is a view, and a view has no address or view mode of its own.
    NotASite,
    Size,
    View,
    Permission,
    Icon,
    /// A required argument is missing or of the wrong type.
    Argument,
    /// An address that is not `https`, `http` or `file` (`add`, `retarget`).
    Address,
    /// A `card_size` that is not one of the sizes (W74).
    CardSize,
    /// The configuration forces the setting a control would write (W74: the card's size key).
    Forced,
    /// A `content` that is not `online` or `local` (W78).
    Content,
}

impl DockError {
    pub fn key(self) -> &'static str {
        match self {
            Self::UnknownPin => "webdock.error.unknown_pin",
            Self::NotASite => "webdock.error.not_a_site",
            Self::Size => "webdock.error.size",
            Self::View => "webdock.error.view",
            Self::Permission => "webdock.error.permission",
            Self::Icon => "webdock.error.icon",
            Self::Argument => "webdock.error.argument",
            Self::Address => "webdock.error.address",
            Self::CardSize => "webdock.error.card_size",
            Self::Forced => "webdock.error.forced",
            Self::Content => "webdock.error.content",
        }
    }
}

/// The settings the dock reads (MODS.md "Web dock"), with the manifest's defaults for any the feed does not carry.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Config {
    pub width: u32,
    pub large: u32,
    /// The strip's width in px (`strip`; `geometry.strip`).
    pub strip: u32,
    pub edge: String,
    pub default_view: View,
    /// Minutes the host runs unused before it stops; 0 = never.
    pub unload_after: u32,
    pub max_loaded: u32,
    /// A rest on an edge reveals the dock (`hover`).
    pub hover: bool,
    /// A hover reveal counts as opening the edge, so it takes a page another place shows (`hover_takes_page`, W74).
    pub hover_takes_page: bool,
    /// The bar module shows the shown pin's image beside its own (`bar_site`, I495).
    pub bar_site: bool,
    /// While a page plays sound the bar module shows its image and its title (`bar_playing`, I495).
    pub bar_playing: bool,
    /// The engine fetches a page's own icon for the strip and the bar (`site_icons`, session 31).
    pub site_icons: bool,
    /// A reveal opens the card of the shown pin again (`reopen_last`).
    pub reopen_last: bool,
    /// The dock stays open: nothing hides it (`pinned`).
    pub pinned: bool,
    /// A pinned strip reserves its width on the output (`reserve`; the card always overlays).
    pub reserve: bool,
    pub indicator: bool,
    pub new_tabs: NewTabs,
    pub page_style: PageStyle,
    pub card_size: CardSize,
    /// W78: what the strip lists (`content`).
    pub content: Content,
    /// W76: the search engine "+" and the address field search with (`search`; `{q}` is the words).
    pub search: String,
    /// W76: the card's box the user dragged, per output (`sizes` rows: output → width × height).
    pub sizes: BTreeMap<String, (u32, u32)>,
    /// Session 33 (K150): the launcher prefix that opens or searches in the dock (`launcher_prefix`, `/` by default;
    /// empty: none).
    pub launcher_prefix: String,
}

impl Config {
    fn read(settings: &Settings) -> Self {
        let number = |key: &str, default: u32| {
            settings
                .get(key)
                .and_then(|v| v.as_u64())
                .and_then(|v| u32::try_from(v).ok())
                .unwrap_or(default)
        };
        let flag = |key: &str, default: bool| {
            settings
                .get(key)
                .and_then(|v| v.as_bool())
                .unwrap_or(default)
        };
        Self {
            width: number("width", 412),
            large: number("large", 90),
            strip: number("strip", 56),
            edge: settings
                .get("edge")
                .and_then(|v| v.as_str().map(str::to_string))
                .unwrap_or_else(|| "right".into()),
            default_view: match settings
                .get("default_view")
                .as_ref()
                .and_then(Value::as_str)
            {
                Some("desktop") => View::Desktop,
                _ => View::Mobile,
            },
            unload_after: number("unload_after", 60),
            max_loaded: number("max_loaded", 4).max(1),
            hover: flag("hover", true),
            hover_takes_page: flag("hover_takes_page", true),
            bar_site: flag("bar_site", false),
            bar_playing: flag("bar_playing", false),
            site_icons: flag("site_icons", true),
            reopen_last: flag("reopen_last", true),
            pinned: flag("pinned", false),
            reserve: flag("reserve", false),
            indicator: flag("indicator", true),
            new_tabs: match settings.get("new_tabs").as_ref().and_then(Value::as_str) {
                Some("browser") => NewTabs::Browser,
                _ => NewTabs::Dock,
            },
            page_style: match settings.get("page_style").as_ref().and_then(Value::as_str) {
                Some("notebook") => PageStyle::Notebook,
                Some("plain") => PageStyle::Plain,
                _ => PageStyle::Phone,
            },
            card_size: settings
                .get("card_size")
                .as_ref()
                .and_then(Value::as_str)
                .and_then(CardSize::parse)
                .unwrap_or(CardSize::Dock),
            content: settings
                .get("content")
                .as_ref()
                .and_then(Value::as_str)
                .and_then(Content::parse)
                .unwrap_or(Content::Online),
            search: settings
                .get("search")
                .as_ref()
                .and_then(Value::as_str)
                .filter(|s| s.starts_with("https://") || s.starts_with("http://"))
                .unwrap_or(DEFAULT_SEARCH)
                .to_string(),
            sizes: sizes_of(&records_of(settings, "sizes")),
            launcher_prefix: settings
                .get("launcher_prefix")
                .as_ref()
                .and_then(Value::as_str)
                .unwrap_or("/")
                .trim()
                .to_string(),
        }
    }
}

/// What the dock knows about one pin, from the host's reports (MODS.md "Web dock": `loaded`, `icon`, `audible`,
/// `blocked`, `error`).
#[derive(Debug, Clone, Default, PartialEq, Eq)]
struct PinState {
    loaded: bool,
    audible: bool,
    blocked: Vec<String>,
    error: Option<String>,
    /// A `file://` URL under the icon cache.
    icon: Option<String>,
    /// The end of the grace after the page's last sound (W73, [`AUDIBLE_GRACE`]); `None` while it plays or never did.
    grace: Option<Instant>,
    /// The page's title as the host last reported it with its sound (I495): what a player's page names.
    page_title: Option<String>,
    /// W76: where the page is while that is not its pin's address (`webdock.host.url`; `at` in the document).
    at: Option<String>,
    /// W76: reloads asked for in the pin's menu (`webdock.reload`), a counter the host answers.
    reload: u32,
}

/// The side of the sidebar window the dock's panel sits in (W30, `webdock.sidebar`).
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Side {
    Left,
    Right,
}

impl Side {
    pub fn parse(name: &str) -> Option<Self> {
        match name {
            "left" => Some(Self::Left),
            "right" => Some(Self::Right),
            _ => None,
        }
    }

    fn name(self) -> &'static str {
        match self {
            Self::Left => "left",
            Self::Right => "right",
        }
    }
}

/// Where the sidebar panel's page area is at rest (W30, `webdock.sidebar {on: true, …}`): on `output`, in a layer
/// window anchored to the usable area's top and to `side`; `inset` px in from that side's edge, `top` px down from the
/// usable area's top, `width` × `height`. The host maps its sidebar window there.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Place {
    pub output: String,
    pub side: Side,
    pub inset: u32,
    pub top: u32,
    pub width: u32,
    pub height: u32,
}

/// Where the bar card's page area rests (W72, `webdock.card {on: true, …}`): on `output`, `x`, `y` logical px from the
/// output's top-left corner (zones ignored, as the shell's Stage window), `width` × `height`. The host maps its card
/// window there.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct CardPlace {
    pub output: String,
    pub x: u32,
    pub y: u32,
    pub width: u32,
    pub height: u32,
}

/// The bar card's page (W72, docs/ux/webdock.md "In the bar's card"): its own pin (kept while the card is closed), its
/// place while the card rests open, the pointer in the host's window over it and the user's use of it (a press, or the
/// keyboard asked for the page), and two counters the shell and the host answer: a close the page asked for (Esc, "Show
/// at the edge") and the keyboard asked for the page.
#[derive(Debug, Default)]
struct Card {
    pin: Option<String>,
    place: Option<CardPlace>,
    hover: bool,
    engaged: bool,
    close: u32,
    focus: u32,
}

pub struct Dock {
    /// The bar card's page (W72).
    card: Card,
    /// W73 ("last opened wins"): when each place last opened on a pin or had one picked, as a running count (0 = never);
    /// of the open places that show a pin, the latest shows its page.
    stamp: u64,
    edge_at: u64,
    side_at: u64,
    card_at: u64,
    /// The pin the sidebar panel shows (W30), kept while the sidebar is closed.
    side_pin: Option<String>,
    /// The sidebar panel's page area while the panel is at rest in an open sidebar; `None` otherwise.
    place: Option<Place>,
    /// Session 32 (the user): the pointer in the host's window over the sidebar's page (`webdock.side_page`), so a
    /// sidebar opened by hover holds while it rests there. Only while `place` is set.
    side_hover: bool,
    pins: Vec<PinSpec>,
    states: BTreeMap<String, PinState>,
    /// Web pins by the time they were last shown, most recent first.
    recent: Vec<String>,
    config: Config,
    mode: Mode,
    shown: Option<String>,
    size: Size,
    /// The output the dock is on: the one a reveal came from, or the one an action named.
    output: Option<String>,
    /// A part took keyboard focus and has not lost it (`webdock.engage`). Only a shown dock is engaged.
    engaged: bool,
    /// The parts the pointer is inside, on the dock's output.
    inside: Inside,
    pending: Option<Pending>,
    host: HostState,
    profiles: PathBuf,
    icons: PathBuf,
    /// The settings the configuration forces, each with the source that forces it (I91: `forced` on `mod.webdock`).
    forced: BTreeMap<String, String>,
    /// W76: the temporary pages (also in `pins`, after the rows); a row with the same id wins over one.
    temps: Vec<PinSpec>,
    /// W76: a pin made from a temporary page → that page's id, so the host renames the page instead of loading it again.
    adopted: BTreeMap<String, String>,
    /// W76: the last number a "+" page's id took (`browse-<n>`).
    browse_seq: u32,
}

impl Dock {
    /// The dock as the settings say it is now, hidden, with the host off.
    pub fn new(settings: &Settings, profiles: PathBuf, icons: PathBuf) -> Self {
        let mut dock = Self {
            card: Card::default(),
            stamp: 0,
            edge_at: 0,
            side_at: 0,
            card_at: 0,
            side_pin: None,
            place: None,
            side_hover: false,
            pins: Vec::new(),
            states: BTreeMap::new(),
            recent: Vec::new(),
            config: Config::read(settings),
            mode: Mode::Hidden,
            shown: None,
            size: Size::Phone,
            output: None,
            engaged: false,
            inside: Inside::default(),
            pending: None,
            host: HostState::Off,
            profiles,
            icons,
            forced: BTreeMap::new(),
            temps: Vec::new(),
            adopted: BTreeMap::new(),
            browse_seq: 0,
        };
        dock.apply_settings(settings, Instant::now());
        dock
    }

    /// The settings the configuration forces, with the source that forces each (I91). The settings feed carries no
    /// provenance yet (CONTRACT-CHANGE 374), so the caller passes what it knows; nothing is forced without it.
    pub fn with_forced(mut self, forced: BTreeMap<String, String>) -> Self {
        self.forced = forced;
        self
    }

    /// The forced settings changed (a layer started or stopped forcing one, row 374).
    pub fn set_forced(&mut self, forced: BTreeMap<String, String>) {
        self.forced = forced;
    }

    /// Takes the settings in effect: pins, and the values the dock reads. A pin that is gone takes its state with it.
    /// A changed `hover` or `pinned` brings the pending deadline in line with the state (K40).
    pub fn apply_settings(&mut self, settings: &Settings, now: Instant) {
        let content = self.config.content;
        self.config = Config::read(settings);
        self.pins = pins_of(&rows_of(settings));
        // W76: the temporary pages stay after the rows; a row of the same id (an undone unpin) takes its page back.
        let rows = self.pins.clone();
        self.temps.retain(|t| !rows.iter().any(|p| p.id == t.id));
        self.pins.extend(self.temps.iter().cloned());
        self.adopted
            .retain(|new, _| rows.iter().any(|p| &p.id == new));
        // A pin moved to where its page is ("Update pin to this page"): the page is at home now.
        for p in &self.pins {
            if let Some(st) = self.states.get_mut(&p.id)
                && st
                    .at
                    .as_deref()
                    .is_some_and(|at| bare(at) == bare(&p.target))
            {
                st.at = None;
            }
        }
        self.states
            .retain(|id, _| self.pins.iter().any(|p| &p.id == id));
        self.recent
            .retain(|id| self.pins.iter().any(|p| &p.id == id && p.kind == Kind::Web));
        // A pin that is gone cannot be shown: the card closes with it.
        if self
            .shown
            .as_ref()
            .is_some_and(|s| !self.pins.iter().any(|p| &p.id == s))
        {
            self.shown = None;
            if self.mode == Mode::Extended {
                self.mode = Mode::Compact;
            }
        }
        // The sidebar's pin goes with its pin too; an open sidebar shows the first pin instead.
        if self
            .side_pin
            .as_ref()
            .is_some_and(|s| !self.pins.iter().any(|p| &p.id == s))
        {
            self.side_pin = None;
        }
        self.default_side_pin();
        // W72: the bar card's pin likewise.
        if self
            .card
            .pin
            .as_ref()
            .is_some_and(|s| !self.pins.iter().any(|p| &p.id == s))
        {
            self.card.pin = None;
        }
        self.default_card_pin();
        // W78: the strip's mode changed (the switch, `kurashi undo`, Settings, the file): a card of the other kind goes.
        // Only on a change — a site opened by name in Local stays through any other write.
        if self.config.content != content {
            self.content_changed();
        }
        self.sanitize();
        self.settle(now);
    }

    /// `webdock.sidebar`: the sidebar panel's page area at rest (`Some`), or the panel moved, hid or went (`None`).
    /// An open sidebar with no pin of its own shows the first pin. True when it shows a site (the host starts).
    /// `fresh` (W73): the panel's first rest since it was made — the sidebar opened on the dock, which stamps it; a rest
    /// after a slide or a scroll does not.
    pub fn place(&mut self, place: Option<Place>, fresh: bool) -> bool {
        if fresh && place.is_some() {
            self.stamp(Spot::Sidebar);
        }
        if place.is_none() {
            self.side_hover = false;
        }
        self.place = place;
        self.default_side_pin();
        match self.side_web() {
            Some(id) => {
                self.touch(&id);
                true
            }
            None => false,
        }
    }

    /// `webdock.sidebar_select {pin}`: the sidebar shows `pin`. True when the sidebar is open on a site (the host
    /// starts); a closed sidebar keeps the pin for its next opening.
    pub fn side_select(&mut self, pin: &str) -> Result<bool, DockError> {
        let (id, _) = self.find(pin)?;
        self.side_pin = Some(id);
        self.stamp(Spot::Sidebar);
        Ok(match self.side_web() {
            Some(id) => {
                self.touch(&id);
                true
            }
            None => false,
        })
    }

    fn default_side_pin(&mut self) {
        if self.place.is_some() && self.side_pin.is_none() {
            self.side_pin = self
                .pins
                .iter()
                .find(|p| p.temp.is_none())
                .map(|p| p.id.clone());
        }
    }

    /// The site the open sidebar shows, if it shows one.
    fn side_web(&self) -> Option<String> {
        self.place.as_ref()?;
        self.side_pin.clone().filter(|id| self.is_web(id))
    }

    /// `webdock.card` (W72): the bar card's page area at rest (`Some`), or the card moved, closed or went (`None`; the
    /// pointer and the use of the host's window over it go with it — its unmap sends no leave). An open card with no
    /// pin of its own shows the first pin. True when it shows a site (the host starts). `fresh` (W73): the card's first
    /// rest since it opened, which stamps it; a rest after a move or a resize does not.
    pub fn card_place(&mut self, place: Option<CardPlace>, fresh: bool) -> bool {
        if fresh && place.is_some() {
            self.stamp(Spot::Card);
        }
        if place.is_none() {
            self.card.hover = false;
            self.card.engaged = false;
        }
        self.card.place = place;
        self.default_card_pin();
        self.touch_card()
    }

    /// `webdock.card_select {pin}` (W72): the bar card shows `pin`. True when the card is open on a site (the host
    /// starts); a closed card keeps the pin for its next opening.
    pub fn card_select(&mut self, pin: &str) -> Result<bool, DockError> {
        let (id, _) = self.find(pin)?;
        self.card.pin = Some(id);
        self.stamp(Spot::Card);
        Ok(self.touch_card())
    }

    /// `webdock.card_page {hover, engaged}` (W72): the pointer in the host's window over the card and the user using it. Only
    /// while the card is placed: a late report after the card closed is dropped.
    pub fn card_page(&mut self, hover: bool, engaged: bool) {
        if self.card.place.is_some() {
            self.card.hover = hover;
            self.card.engaged = engaged;
        }
    }

    /// `webdock.side_page {hover}` (session 32): the pointer in the host's window over the sidebar's page. Only while the
    /// page area is placed.
    pub fn side_page(&mut self, hover: bool) {
        self.side_hover = hover && self.place.is_some();
    }

    /// `webdock.card_close {}` (W72): the page asked the card to close (Esc it did not take, "Show at the edge"); the
    /// shell's panel answers with `ui.close`. Only while the card is placed.
    pub fn card_close(&mut self) {
        if self.card.place.is_some() {
            self.card.close = self.card.close.wrapping_add(1);
            self.card_closed();
        }
    }

    /// W76: the bar card closed (its Esc, or the shell saw it close: `webdock.card {closed}`): the "+" page it showed goes,
    /// and the card shows its first pin when it opens again.
    /// The card lets the page go; [`Dock::sweep`] drops it unless another place shows it now ("Show at the edge", "Keep open
    /// at the edge" move a "+" page to the edge before the card closes).
    pub fn card_closed(&mut self) {
        if let Some(id) = self.card.pin.clone()
            && self
                .temp_of(&id)
                .is_some_and(|t| t.temp == Some(Temp::Browse))
        {
            self.card.pin = None;
            self.default_card_pin();
            self.sweep();
        }
    }

    /// `webdock.card_focus {}` (W72): the keyboard is asked for the page (Tab past the card's keys); the host's window
    /// takes it once. Only while the card shows a site.
    pub fn card_focus(&mut self) {
        if self.card_web().is_some() {
            self.card.focus = self.card.focus.wrapping_add(1);
        }
    }

    fn default_card_pin(&mut self) {
        if self.card.place.is_some() && self.card.pin.is_none() {
            self.card.pin = self
                .pins
                .iter()
                .find(|p| p.temp.is_none())
                .map(|p| p.id.clone());
        }
    }

    fn touch_card(&mut self) -> bool {
        match self.card_web() {
            Some(id) => {
                self.touch(&id);
                true
            }
            None => false,
        }
    }

    /// The site the open bar card shows, if it shows one (W72).
    fn card_web(&self) -> Option<String> {
        self.card.place.as_ref()?;
        self.card.pin.clone().filter(|id| self.is_web(id))
    }

    // ---- W76: temporary pages, the address field, the menu's reload, the page's address ----

    /// `webdock.browse {place, output?}` (W76, "+"): a new temporary page, empty, shown in `place` (the edge card opens
    /// extended on it; the bar card and the sidebar pick it). A "+" page that place showed before is dropped. Returns its
    /// id; the host starts (it draws the address field).
    pub fn browse(&mut self, place: Spot, output: Option<&str>) -> String {
        let id = loop {
            self.browse_seq += 1;
            let id = format!("browse-{}", self.browse_seq);
            if !self.pins.iter().any(|p| p.id == id) {
                break id;
            }
        };
        let pin = PinSpec {
            id: id.clone(),
            title: String::new(),
            target: String::new(),
            kind: Kind::Web,
            view: ViewSetting::Default,
            profile: BROWSE_PROFILE.into(),
            background: false,
            temp: Some(Temp::Browse),
        };
        self.temps.push(pin.clone());
        self.pins.push(pin);
        match place {
            Spot::Edge => {
                self.mode = Mode::Extended;
                self.shown = Some(id.clone());
                if let Some(output) = output {
                    self.output = Some(output.into());
                }
            }
            Spot::Card => self.card.pin = Some(id.clone()),
            Spot::Sidebar => self.side_pin = Some(id.clone()),
        }
        self.stamp(place);
        self.touch(&id);
        self.sweep();
        self.sanitize();
        id
    }

    /// Session 33 (K150): the launcher prefix in effect (`launcher_prefix`; empty: none).
    pub fn launcher_prefix(&self) -> &str {
        &self.config.launcher_prefix
    }

    /// Session 33 (K150, the launcher): a temporary page already at `url`, shown in `place` — "+" with the address typed.
    pub fn browse_to(&mut self, place: Spot, output: Option<&str>, url: &str) -> String {
        let id = self.browse(place, output);
        for p in self.pins.iter_mut().chain(self.temps.iter_mut()) {
            if p.id == id {
                p.target = url.to_string();
            }
        }
        id
    }

    /// Session 33 (K150): the launcher's rows for `text` after the dock's prefix — the pins it matches (title or
    /// address), then the address it names or a search for it. Empty text: every pin. (key, name, sub, icon, pin or
    /// text) — the caller words them.
    pub fn launcher_rows(&self, text: &str) -> Vec<LaunchRow> {
        let t = text.trim().to_lowercase();
        let mut out: Vec<LaunchRow> = self
            .pins
            .iter()
            .filter(|p| p.temp.is_none() && p.kind == Kind::Web)
            .filter(|p| {
                t.is_empty()
                    || p.title.to_lowercase().contains(&t)
                    || p.target.to_lowercase().contains(&t)
            })
            .map(|p| LaunchRow::Pin {
                id: p.id.clone(),
                title: if p.title.is_empty() {
                    p.target.clone()
                } else {
                    p.title.clone()
                },
                target: p.target.clone(),
            })
            .collect();
        if let Some(url) = resolve(text, &self.config.search) {
            // (a search is the engine's address with the words in it; anything else is the address the text names)
            let engine = self.config.search.split("{q}").next().unwrap_or_default();
            out.push(if !engine.is_empty() && url.starts_with(engine) {
                LaunchRow::Search {
                    words: text.trim().to_string(),
                    url,
                }
            } else {
                LaunchRow::Address { url }
            });
        }
        out
    }

    /// `webdock.go {pin, text}` (W76, the address field): the address `text` names, or a search for it with the user's
    /// engine. A temporary page's address follows (its home is where it went last); a pin stays at its own. Returns the
    /// address the host loads.
    pub fn go(&mut self, pin: &str, text: &str) -> Result<String, DockError> {
        if !self.is_web(pin) {
            return Err(DockError::NotASite);
        }
        let url = resolve(text, &self.config.search).ok_or(DockError::Argument)?;
        let temp = self.pin(pin)?.temp.is_some();
        if temp {
            for p in self.pins.iter_mut().chain(self.temps.iter_mut()) {
                if p.id == pin {
                    p.target.clone_from(&url);
                }
            }
        }
        Ok(url)
    }

    /// `webdock.drop {pin}` (W76): Esc in a "+" page's empty field; the page goes. Not a pin of the settings.
    pub fn drop_temp(&mut self, pin: &str) -> Result<(), DockError> {
        if self.pin(pin)?.temp != Some(Temp::Browse) {
            return Err(DockError::UnknownPin);
        }
        self.forget_temp(pin);
        Ok(())
    }

    /// `webdock.unpin {pin}` (W76, "Unpin but keep open"): the pin becomes a temporary page of the same id (its page
    /// and its profile stay); the caller removes its row. A page that is not loaded has nothing to keep and goes with it.
    pub fn unpin_keep(&mut self, pin: &str) -> Result<(), DockError> {
        let p = self.pin(pin)?;
        if p.kind != Kind::Web {
            return Err(DockError::NotASite);
        }
        if p.temp.is_some() {
            return Err(DockError::UnknownPin);
        }
        let mut kept = p.clone();
        kept.temp = Some(Temp::Kept);
        self.temps.retain(|t| t.id != pin);
        self.temps.push(kept.clone());
        if let Some(slot) = self.pins.iter_mut().find(|p| p.id == pin) {
            *slot = kept;
        }
        Ok(())
    }

    /// A refused unpin (the write failed): the page is the pin's again.
    pub fn unpin_undo(&mut self, pin: &str) {
        if self
            .temp_of(pin)
            .is_some_and(|t| t.temp == Some(Temp::Kept))
        {
            self.temps.retain(|t| t.id != pin);
            if let Some(p) = self.pins.iter_mut().find(|p| p.id == pin) {
                p.temp = None;
            }
        }
    }

    /// The temporary page `id`, if `pin` names one (W76: `webdock.add {from}`).
    pub fn temp_of(&self, pin: &str) -> Option<&PinSpec> {
        self.temps.iter().find(|t| t.id == pin)
    }

    /// The ids no new pin may take (W76): the temporary pages' (a pin of the same id would take its page).
    pub fn temp_ids(&self) -> Vec<String> {
        self.temps.iter().map(|t| t.id.clone()).collect()
    }

    /// W76 "Pin": the new pin `to` (its row is written and applied) takes the temporary page `from` — the places that
    /// showed it, its loaded state, its place in the shown order — and the document says `was` on it, so the host renames
    /// the page (no reload).
    pub fn adopt(&mut self, from: &str, to: &str) {
        if from == to || self.temp_of(from).is_none() || !self.pins.iter().any(|p| p.id == to) {
            return;
        }
        for place in [&mut self.shown, &mut self.card.pin, &mut self.side_pin] {
            if place.as_deref() == Some(from) {
                *place = Some(to.to_string());
            }
        }
        for r in &mut self.recent {
            if r == from {
                *r = to.to_string();
            }
        }
        if let Some(mut st) = self.states.remove(from) {
            st.at = None;
            self.states.insert(to.to_string(), st);
        }
        self.temps.retain(|t| t.id != from);
        self.pins.retain(|p| p.id != from);
        self.adopted.insert(to.to_string(), from.to_string());
    }

    /// `webdock.reload {pin}` (W76, the pin's menu): the host reloads the loaded page (a counter it answers once).
    pub fn reload(&mut self, pin: &str) -> Result<(), DockError> {
        self.web_pin(pin)?;
        let st = self.states.entry(pin.to_string()).or_default();
        if !st.loaded {
            return Err(DockError::Argument);
        }
        st.reload = st.reload.wrapping_add(1);
        Ok(())
    }

    /// `webdock.host.url {pin, url}` (W76): the page's address now; kept while it is not the pin's own (`at`).
    /// A pin that is gone already (a "+" page dropped while its page moved on) is no error: there is nothing to keep.
    pub fn page_url(&mut self, pin: &str, url: &str) -> Result<(), DockError> {
        let Ok(p) = self.pin(pin) else {
            return Ok(());
        };
        let target = p.target.clone();
        self.web_pin(pin)?;
        let st = self.states.entry(pin.to_string()).or_default();
        st.at = (bare(url) != bare(&target) && !url.is_empty()).then(|| url.to_string());
        Ok(())
    }

    /// Where the page of `pin` is while that is not its address (W76: "Update pin to this page").
    pub fn at(&self, pin: &str) -> Option<String> {
        self.states.get(pin).and_then(|st| st.at.clone())
    }

    /// W76: the temporary pages that are no longer wanted go: a "+" page that no place shows any more (its card closed,
    /// another pin picked; a hover hide keeps `shown`), a kept page the host no longer keeps (the dock's rules).
    pub fn sweep(&mut self) {
        let keep = self.keep();
        let gone: Vec<String> = self
            .temps
            .iter()
            .filter(|t| match t.temp {
                Some(Temp::Browse) => ![&self.shown, &self.card.pin, &self.side_pin]
                    .iter()
                    .any(|p| p.as_deref() == Some(t.id.as_str())),
                _ => !keep.contains(&t.id),
            })
            .map(|t| t.id.clone())
            .collect();
        for id in gone {
            self.forget_temp(&id);
        }
    }

    fn forget_temp(&mut self, id: &str) {
        self.temps.retain(|t| t.id != id);
        self.pins.retain(|p| p.id != id);
        self.states.remove(id);
        self.recent.retain(|r| r != id);
        if self.shown.as_deref() == Some(id) {
            self.shown = None;
            if self.mode == Mode::Extended {
                self.mode = Mode::Compact;
            }
        }
        if self.card.pin.as_deref() == Some(id) {
            self.card.pin = None;
            self.default_card_pin();
        }
        if self.side_pin.as_deref() == Some(id) {
            self.side_pin = None;
            self.default_side_pin();
        }
    }

    /// The host's state as the daemon reports it. Without a connected host nothing is loaded or audible (Shōjiki).
    /// A host that crashed takes its card with it: the card's leave and the focus loss never come, so the dock
    /// forgets them (K40), or it would stay open for good.
    pub fn set_host(&mut self, state: HostState) {
        if state != HostState::Ready {
            for st in self.states.values_mut() {
                st.loaded = false;
                st.audible = false;
                st.grace = None;
            }
        }
        if matches!(state, HostState::Failed { .. } | HostState::Missing) && state != self.host {
            self.inside.card = false;
            self.engaged = false;
            // (W72: the bar card's page window went with the host too)
            self.card.hover = false;
            self.card.engaged = false;
            self.settle(Instant::now());
        }
        self.host = state;
    }

    /// The card opens on `pin`, extended (`webdock.open`). True when the pin is a site, which starts the host.
    pub fn open(&mut self, pin: &str, output: Option<&str>) -> Result<bool, DockError> {
        let (id, kind) = self.find(pin)?;
        self.mode = Mode::Extended;
        self.shown = Some(id.clone());
        self.stamp(Spot::Edge);
        if let Some(output) = output {
            self.output = Some(output.into());
        }
        if kind == Kind::Web {
            self.touch(&id);
        }
        self.sanitize();
        Ok(kind == Kind::Web)
    }

    /// The ids of the pins the strip lists (W78, `strip`, in the document while it is not every pin): the mode's, in
    /// the rows' order, no temporary page.
    pub fn strip(&self) -> Vec<String> {
        let content = self.config.content;
        self.pins
            .iter()
            .filter(|p| p.temp.is_none() && content.lists(p.kind))
            .map(|p| p.id.clone())
            .collect()
    }

    /// After the strip's mode changed (W78): a card that shows a pin of the other kind is put away, the strip stays.
    /// True when it was.
    pub fn content_changed(&mut self) -> bool {
        let other = self.mode == Mode::Extended
            && self
                .shown
                .as_deref()
                .and_then(|id| self.pin(id).ok())
                .is_some_and(|p| !self.config.content.lists(p.kind));
        if other {
            self.collapse();
        }
        other
    }

    /// The strip only (`webdock.collapse`): the card closes, the pin stays loaded.
    pub fn collapse(&mut self) {
        self.mode = Mode::Compact;
        self.shown = None;
        self.sanitize();
    }

    /// Out of sight, the shown pin kept (`webdock.hide`). Nothing engages a hidden dock.
    pub fn hide(&mut self) {
        self.mode = Mode::Hidden;
        self.engaged = false;
        self.sanitize();
    }

    /// `webdock.toggle`: from hidden, the shown pin's card or the strip, with the keyboard in the dock (`engaged`);
    /// otherwise hidden. True when the card opens on a site, which starts the host.
    pub fn toggle(&mut self, output: Option<&str>) -> bool {
        if let Some(output) = output {
            self.output = Some(output.into());
        }
        self.pending = None;
        if self.mode != Mode::Hidden {
            self.mode = Mode::Hidden;
            self.engaged = false;
            return false;
        }
        self.engaged = true;
        match self.shown.clone() {
            Some(shown) => {
                self.mode = Mode::Extended;
                self.stamp(Spot::Edge);
                let web = self.is_web(&shown);
                if web {
                    self.touch(&shown);
                }
                web
            }
            None => {
                self.mode = Mode::Compact;
                false
            }
        }
    }

    /// `webdock.back`: Escape on the dock's chrome steps back (K40). Extended goes to compact with no card; compact
    /// goes to hidden unless the dock is pinned.
    pub fn back(&mut self) {
        match self.mode {
            Mode::Extended => {
                self.mode = Mode::Compact;
                self.shown = None;
            }
            Mode::Compact if !self.config.pinned => {
                self.mode = Mode::Hidden;
                self.engaged = false;
            }
            Mode::Compact | Mode::Hidden => {}
        }
        self.sanitize();
    }

    /// `webdock.select {pin, output?}`: a click on a pin shows it extended. A click on the shown pin's icon puts its
    /// card away (compact, no `shown`; the pin stays loaded). True when the card opens on a site (the host starts).
    pub fn select(&mut self, pin: &str, output: Option<&str>) -> Result<bool, DockError> {
        let (id, kind) = self.find(pin)?;
        if let Some(output) = output {
            self.output = Some(output.into());
        }
        if self.mode == Mode::Extended && self.shown.as_deref() == Some(id.as_str()) {
            self.mode = Mode::Compact;
            self.shown = None;
            self.sanitize();
            return Ok(false);
        }
        self.mode = Mode::Extended;
        self.shown = Some(id.clone());
        self.stamp(Spot::Edge);
        if kind == Kind::Web {
            self.touch(&id);
        }
        self.sanitize();
        Ok(kind == Kind::Web)
    }

    /// `webdock.size`: phone or large; no argument toggles.
    pub fn size(&mut self, size: Option<&str>) -> Result<(), DockError> {
        self.size = match size {
            Some("phone") => Size::Phone,
            Some("large") => Size::Large,
            Some(_) => return Err(DockError::Size),
            None if self.size == Size::Phone => Size::Large,
            None => Size::Phone,
        };
        Ok(())
    }

    /// `webdock.hover {part, inside, output, shared?}` (K40): the pointer entered or left a part on `output`.
    /// A hidden dock takes the edge alone: an edge the pointer is inside (with `hover` on) arms a reveal, and leaving
    /// that edge on the same output disarms it. A shown dock is on one output: another output's reports are ignored,
    /// and the first report latches the output when none is set. Every change settles the pending hide.
    pub fn hover(&mut self, part: Part, inside: bool, output: &str, shared: bool, now: Instant) {
        if part == Part::Edge && !self.config.hover {
            return;
        }
        if self.mode == Mode::Hidden {
            // A strip or a card report from a hidden dock is late, and changes nothing.
            if part == Part::Edge {
                self.hover_edge_hidden(inside, output, shared, now);
            }
        } else {
            if self
                .output
                .as_deref()
                .is_some_and(|latched| latched != output)
            {
                return;
            }
            if self.output.is_none() {
                self.output = Some(output.into());
            }
            self.inside.set(part, inside);
        }
        self.settle(now);
    }

    /// `webdock.engage {on}`: a part took (or lost) keyboard focus (K40). Losing it counts as a leave, and a hidden
    /// dock is never engaged.
    pub fn engage(&mut self, on: bool, now: Instant) {
        if self.mode != Mode::Hidden {
            self.engaged = on;
            self.settle(now);
        }
    }

    /// The pending deadline falls due at `now` or before it: a reveal shows the dock (the card of `shown` when
    /// `reopen_last` is on), a hide hides it and keeps `shown`. True when a reveal opens a site (the host starts).
    pub fn tick(&mut self, now: Instant) -> bool {
        if !self.pending.as_ref().is_some_and(|p| p.at() <= now) {
            return false;
        }
        match self.pending.take() {
            Some(Pending::Reveal { output, .. }) => {
                self.output = Some(output);
                self.mode = Mode::Compact;
                match self.shown.clone().filter(|_| self.config.reopen_last) {
                    Some(shown) => {
                        self.mode = Mode::Extended;
                        // W74 (docs/ux/webdock.md "Which place shows the page"): with `hover_takes_page` off a hover
                        // reveal is no opening: the edge ranks below every open place (the stamp of an earlier
                        // deliberate open must not carry over), so it shows the page only when no other place does.
                        if self.config.hover_takes_page {
                            self.stamp(Spot::Edge);
                        } else {
                            self.edge_at = 0;
                        }
                        let web = self.is_web(&shown);
                        if web {
                            self.touch(&shown);
                        }
                        web
                    }
                    None => false,
                }
            }
            Some(Pending::Hide { .. }) => {
                // Checked again: a hide only ever closes a dock that nothing holds.
                if !self.held() {
                    self.mode = Mode::Hidden;
                    self.engaged = false;
                }
                false
            }
            None => false,
        }
    }

    /// The moment the pending reveal or hide falls due, for the supervisor's timer (rule 5: none while none is pending).
    pub fn due_at(&self) -> Option<Instant> {
        self.pending.as_ref().map(Pending::at)
    }

    /// The site `pin` is a web pin (for `webdock.host.new_window`): its id, or an unknown-pin refusal.
    pub fn web_pin(&self, pin: &str) -> Result<(), DockError> {
        self.pin(pin).and_then(|p| match p.kind {
            Kind::Web => Ok(()),
            Kind::View => Err(DockError::UnknownPin),
        })
    }

    /// `webdock.host.loaded`: the site runs in the host. `icon` (its favicon) is accepted only under the icon
    /// cache; otherwise the pin loads without it and the report is refused.
    pub fn loaded(&mut self, pin: &str, icon: Option<&str>) -> Result<(), DockError> {
        self.web_pin(pin)?;
        let id = pin.to_string();
        let icons = self.icons.clone();
        let st = self.states.entry(id).or_default();
        st.loaded = true;
        st.error = None;
        st.blocked.clear();
        match icon {
            None => Ok(()),
            Some(path) => match icon_url(path, &icons) {
                Some(url) => {
                    st.icon = Some(url);
                    Ok(())
                }
                None => Err(DockError::Icon),
            },
        }
    }

    /// `webdock.host.unloaded`: the site left the host (discarded, or the host let it go).
    /// A pin that is gone already (the user removed it, then the host let its page go) is no error: its state
    /// went with the pin, so the late report has nothing left to change (B93).
    pub fn unloaded(&mut self, pin: &str) -> Result<(), DockError> {
        if self.web_pin(pin).is_err() {
            self.states.remove(pin);
            return Ok(());
        }
        let st = self.states.entry(pin.to_string()).or_default();
        st.loaded = false;
        st.audible = false;
        st.grace = None;
        // W76: a page that unloads opens at its pin's address again ("home").
        st.at = None;
        Ok(())
    }

    /// `webdock.host.audible`: the site plays sound, or stopped. An audible pin is kept loaded, whatever the cap, and
    /// so is one in its grace after the last sound (W73, [`AUDIBLE_GRACE`]): the silence between two tracks, a pause.
    pub fn audible(&mut self, pin: &str, on: bool, now: Instant) -> Result<(), DockError> {
        self.web_pin(pin)?;
        let st = self.states.entry(pin.to_string()).or_default();
        if on {
            st.grace = None;
        } else if st.audible {
            st.grace = Some(now + AUDIBLE_GRACE);
        }
        st.audible = on;
        Ok(())
    }

    /// The page's title the host reports with its sound (I495); a pin that is not a known web pin is ignored.
    pub fn page_title(&mut self, pin: &str, title: Option<String>) {
        if self.web_pin(pin).is_err() {
            return;
        }
        if let Some(t) = title {
            self.states.entry(pin.to_string()).or_default().page_title = Some(t);
        }
    }

    /// The moment the first grace after a sound ends, for the supervisor's timer (rule 5: none while none runs).
    pub fn grace_due(&self) -> Option<Instant> {
        self.states.values().filter_map(|st| st.grace).min()
    }

    /// The graces that ended by `now` end: their pins go back to the dock's rules. True when one ended.
    pub fn expire(&mut self, now: Instant) -> bool {
        let mut any = false;
        for st in self.states.values_mut() {
            if st.grace.is_some_and(|g| g <= now) {
                st.grace = None;
                any = true;
            }
        }
        any
    }

    /// `webdock.host.blocked`: the page asked for a permission the host refused (cleared by its next load).
    pub fn blocked(&mut self, pin: &str, permission: &str) -> Result<(), DockError> {
        self.web_pin(pin)?;
        if !PERMISSIONS.contains(&permission) {
            return Err(DockError::Permission);
        }
        let st = self.states.entry(pin.to_string()).or_default();
        if !st.blocked.iter().any(|p| p == permission) {
            st.blocked.push(permission.into());
        }
        Ok(())
    }

    /// `webdock.host.crashed`: the page's renderer stopped; it is shown as stopped until its next load.
    pub fn crashed(&mut self, pin: &str) -> Result<(), DockError> {
        self.web_pin(pin)?;
        let st = self.states.entry(pin.to_string()).or_default();
        st.loaded = false;
        st.audible = false;
        st.grace = None;
        st.error = Some("webdock.error.crashed".into());
        Ok(())
    }

    /// The host runs now, and nothing web is shown, audible, in its grace after a sound or a loaded background pin
    /// (W73), so the idle clock runs (MODS.md "Lifecycle").
    pub fn is_idle(&self) -> bool {
        self.host.is_running()
            && !self.web_visible()
            && !self.pins.iter().any(|p| self.holds(&p.id))
    }

    /// How long the host may stay idle before it stops; `None` = never.
    pub fn unload_after(&self) -> Option<Duration> {
        (self.config.unload_after > 0)
            .then(|| Duration::from_secs(u64::from(self.config.unload_after) * 60))
    }

    /// The pins the host keeps loaded (MODS.md): the most recently shown sites, up to `max_loaded`, then beyond the cap
    /// any site that holds itself (audible, in its grace, a background pin: W73) or is on screen. Nothing while the
    /// host does not run.
    pub fn keep(&self) -> Vec<String> {
        if !self.host.is_running() {
            return Vec::new();
        }
        let web: Vec<String> = self
            .recent
            .iter()
            .filter(|id| self.is_web(id))
            .cloned()
            .collect();
        let cap = self.config.max_loaded as usize;
        let (first, rest) = web.split_at(web.len().min(cap));
        let mut keep = first.to_vec();
        // Beyond the cap: an audible site, and a site on screen (the edge card's, the sidebar's and the bar card's at once,
        // W30, W72).
        let shown = self.edge_web();
        let side = self.side_web();
        let card = self.card_web();
        keep.extend(
            rest.iter()
                .filter(|id| {
                    self.holds(id)
                        || shown.as_deref() == Some(id.as_str())
                        || side.as_deref() == Some(id.as_str())
                        || card.as_deref() == Some(id.as_str())
                })
                .cloned(),
        );
        keep
    }

    /// `mod.webdock` (fixture `snap_mod_webdock.json`): absent keys, no nulls.
    pub fn doc(&self) -> Value {
        let views = self.profile_views();
        let pins: Vec<Value> = self.pins.iter().map(|p| self.pin_doc(p, &views)).collect();
        let mut host = json!({"state": self.host.name()});
        if let Some(reason) = self.host.reason() {
            host["reason"] = json!(reason);
        }
        if let Some(detail) = self.host.detail() {
            host["detail"] = json!(detail);
        }
        let mut doc = json!({
            "available": true,
            "mode": self.mode.name(),
            "size": self.size.name(),
            "pinned": self.config.pinned,
            "engaged": self.engaged,
            "hover": self.config.hover,
            "reserve": self.config.reserve,
            "indicator": self.config.indicator,
            "new_tabs": self.config.new_tabs.name(),
            "edge": self.config.edge,
            "geometry": {
                "strip": self.config.strip,
                "width": self.config.width,
                "large": self.config.large,
                "grace": GRACE_PX,
            },
            "keep": self.keep(),
            "pins": pins,
            "host": host,
            "dirs": {
                "profiles": self.profiles.to_string_lossy(),
                "icons": self.icons.to_string_lossy(),
            },
        });
        if let Some(shown) = &self.shown {
            doc["shown"] = json!(shown);
        }
        if let Some(output) = &self.output {
            doc["output"] = json!(output);
        }
        // W69: the page style; absent while it is the phone (the default), so a document from before it reads the same.
        if self.config.page_style != PageStyle::Phone {
            doc["page_style"] = json!(self.config.page_style.name());
        }
        // W73: the bar card's size, absent while the default (W74: `dock`, the edge card's size); and the place that
        // shows the edge card's page when that is another one (absent while the edge card shows it).
        if self.config.card_size != CardSize::Dock {
            doc["card_size"] = json!(self.config.card_size.name());
        }
        // W78: the strip's mode, absent while online (the default); `strip` while it lists fewer than every pin (Online
        // with a view pinned, or Local), so a document with sites only reads as before.
        if self.config.content != Content::Online {
            doc["content"] = json!(self.config.content.name());
        }
        let strip = self.strip();
        if strip.len() != self.pins.iter().filter(|p| p.temp.is_none()).count() {
            doc["strip"] = json!(strip);
        }
        // I495 (session 30): the bar module's views, named only while on.
        if self.config.bar_site {
            doc["bar_site"] = json!(true);
        }
        // (session 31: named only while off — the engine then fetches no page icon, K38's proof)
        if !self.config.site_icons {
            doc["site_icons"] = json!(false);
        }
        if self.config.bar_playing {
            doc["bar_playing"] = json!(true);
        }
        // B117: named only while off (the shell keeps the edge's hover zone reachable over an open card while it is on).
        if !self.config.hover_takes_page {
            doc["hover_takes_page"] = json!(false);
        }
        if let Some(at) = self.elsewhere(Spot::Edge) {
            doc["elsewhere"] = json!(at.name());
        }
        // W76: the card's box per output where the user dragged it (absent while none is).
        if !self.config.sizes.is_empty() {
            let sizes: Map<String, Value> = self
                .config
                .sizes
                .iter()
                .map(|(out, (w, h))| (out.clone(), json!({"width": w, "height": h})))
                .collect();
            doc["sizes"] = Value::Object(sizes);
        }
        // I91: the settings the configuration forces and their sources; absent when nothing is forced (no nulls).
        if !self.forced.is_empty() {
            doc["forced"] = json!(self.forced);
        }
        // W30: the sidebar's pin and, while the panel is at rest in an open sidebar, its page area (absent otherwise).
        if self.side_pin.is_some() || self.place.is_some() {
            let mut side = json!({});
            if let Some(pin) = &self.side_pin {
                side["pin"] = json!(pin);
            }
            if let Some(p) = &self.place {
                side["place"] = json!({
                    "output": p.output,
                    "side": p.side.name(),
                    "inset": p.inset,
                    "top": p.top,
                    "width": p.width,
                    "height": p.height,
                });
            }
            if let Some(at) = self.elsewhere(Spot::Sidebar) {
                side["elsewhere"] = json!(at.name());
            }
            if self.side_hover && self.place.is_some() {
                side["hover"] = json!(true);
            }
            doc["sidebar"] = side;
        }
        // W72: the bar card's pin, its page area while the card rests open, and the host window's reports and the two
        // counters while they are set (absent otherwise; CONTRACT-CHANGE row 719).
        let c = &self.card;
        if c.pin.is_some() || c.place.is_some() || c.close > 0 || c.focus > 0 {
            let mut card = json!({});
            if let Some(pin) = &c.pin {
                card["pin"] = json!(pin);
            }
            if let Some(p) = &c.place {
                card["place"] = json!({
                    "output": p.output,
                    "x": p.x,
                    "y": p.y,
                    "width": p.width,
                    "height": p.height,
                });
            }
            if c.hover {
                card["hover"] = json!(true);
            }
            if c.engaged {
                card["engaged"] = json!(true);
            }
            if c.close > 0 {
                card["close"] = json!(c.close);
            }
            if c.focus > 0 {
                card["focus"] = json!(c.focus);
            }
            if let Some(at) = self.elsewhere(Spot::Card) {
                card["elsewhere"] = json!(at.name());
            }
            doc["card"] = card;
        }
        doc
    }

    fn pin_doc(&self, p: &PinSpec, views: &BTreeMap<String, View>) -> Value {
        let kind = match p.kind {
            Kind::Web => "web",
            Kind::View => "view",
        };
        let mut out = json!({"id": p.id, "kind": kind, "title": p.title, "target": p.target});
        // I91: the pins are one setting (`pins`); a forced list names its source on each pin (the strip's menu reads it).
        if let Some(source) = self.forced.get("pins").filter(|_| p.temp.is_none()) {
            out["forced_by"] = json!(source);
        }
        // W76: a temporary page (not a row of the settings), and the page a new pin took over (the host renames it).
        if p.temp.is_some() {
            out["temporary"] = json!(true);
        }
        if let Some(was) = self.adopted.get(&p.id) {
            out["was"] = json!(was);
        }
        if p.kind == Kind::Web {
            let view = views
                .get(&p.profile)
                .copied()
                .unwrap_or(self.config.default_view);
            let st = self.states.get(&p.id).cloned().unwrap_or_default();
            out["view"] = json!(view.name());
            out["profile"] = json!(p.profile);
            out["loaded"] = json!(st.loaded);
            // I495 (session 30): an icon the host saved before (an earlier run, a page since unloaded) shows until the
            // page reports one again.
            if let Some(icon) = st.icon.or_else(|| {
                let saved = self.icons.join(format!("{}.png", icon_name(&p.id)));
                saved.is_file().then(|| file_url(&saved))
            }) {
                out["icon"] = json!(icon);
            }
            if st.audible {
                out["audible"] = json!(true);
                if let Some(t) = st.page_title.as_ref().filter(|t| !t.is_empty()) {
                    out["page_title"] = json!(t);
                }
            }
            // W73: the pin keeps running in the background; its page stays Active though hidden and silent.
            if p.background {
                out["background"] = json!(true);
            }
            if self.is_awake(&p.id) {
                out["awake"] = json!(true);
            }
            if !st.blocked.is_empty() {
                out["blocked"] = json!(st.blocked);
            }
            if let Some(error) = st.error {
                out["error"] = json!(error);
            }
            // W76: where the page is while that is not its address, and the menu's reloads.
            if let Some(at) = st.at {
                out["at"] = json!(at);
            }
            if st.reload > 0 {
                out["reload"] = json!(st.reload);
            }
        }
        out
    }

    /// The view each profile shows (MODS.md: the first pin of a profile decides, and `webdock.view` writes it to all).
    fn profile_views(&self) -> BTreeMap<String, View> {
        let mut views = BTreeMap::new();
        for p in self.pins.iter().filter(|p| p.kind == Kind::Web) {
            let view = match p.view {
                ViewSetting::Mobile => View::Mobile,
                ViewSetting::Desktop => View::Desktop,
                ViewSetting::Default => self.config.default_view,
            };
            views.entry(p.profile.clone()).or_insert(view);
        }
        views
    }

    /// The edge of a hidden dock (K40). An enter arms the reveal on its output (kept when it is already armed there,
    /// so a repeated report does not push the deadline back). A leave of the armed edge disarms it. A leave of another
    /// output's edge is not the pointer leaving the armed one, so it changes nothing.
    fn hover_edge_hidden(&mut self, inside: bool, output: &str, shared: bool, now: Instant) {
        let armed = match &self.pending {
            Some(Pending::Reveal { output, .. }) => Some(output.clone()),
            _ => None,
        };
        match (inside, armed) {
            (true, Some(armed)) if armed == output => {}
            (true, _) => {
                // The edge's output is the dock's from the arm on (K40); a leave that disarms the reveal keeps it.
                self.inside.edge = true;
                self.output = Some(output.into());
                let delay = if shared { REVEAL_SHARED } else { REVEAL };
                self.pending = Some(Pending::Reveal {
                    at: now + delay,
                    output: output.into(),
                });
            }
            (false, Some(armed)) if armed != output => {}
            (false, armed) => {
                self.inside.edge = false;
                if armed.is_some() {
                    self.pending = None;
                }
            }
        }
    }

    /// Brings the pending deadline in line with the state (K40). A hidden dock keeps a reveal only while its edge is
    /// inside and `hover` is on. A shown dock is held by a part inside, by `pinned` or by `engaged`; when nothing
    /// holds it, a hide is armed, and an armed hide is kept (its deadline is not pushed back by later reports).
    fn settle(&mut self, now: Instant) {
        self.sanitize();
        match self.mode {
            Mode::Hidden => {
                let edge_holds = self.config.hover && self.inside.edge;
                if !edge_holds && matches!(self.pending, Some(Pending::Reveal { .. })) {
                    self.pending = None;
                }
            }
            Mode::Compact | Mode::Extended => {
                if self.held() {
                    self.pending = None;
                } else if self.pending.is_none() {
                    self.pending = Some(Pending::Hide { at: now + HIDE });
                }
            }
        }
    }

    /// Something keeps a shown dock open: a part inside, `pinned`, or the keyboard in the dock.
    fn held(&self) -> bool {
        self.inside.any() || self.config.pinned || self.engaged
    }

    /// A reveal is only pending while the dock is hidden, and a hide only while it is shown.
    fn sanitize(&mut self) {
        let stale = match self.pending {
            Some(Pending::Reveal { .. }) => self.mode != Mode::Hidden,
            Some(Pending::Hide { .. }) => self.mode == Mode::Hidden,
            None => false,
        };
        if stale {
            self.pending = None;
        }
    }

    /// A site is on screen: the edge card's, the open sidebar's (W30) or the open bar card's (W72).
    fn web_visible(&self) -> bool {
        self.edge_web().is_some() || self.side_web().is_some() || self.card_web().is_some()
    }

    /// The site the edge card shows, if it shows one.
    fn edge_web(&self) -> Option<String> {
        (self.mode == Mode::Extended)
            .then(|| self.shown.clone())
            .flatten()
            .filter(|s| self.is_web(s))
    }

    /// The site holds itself loaded and the engine up (W73): it plays, it is in its grace after a sound, or it is a
    /// background pin that was opened (in `recent`).
    fn holds(&self, id: &str) -> bool {
        self.states
            .get(id)
            .is_some_and(|st| st.audible || st.grace.is_some())
            || self.is_background(id)
    }

    /// A background pin that was opened, so its page is loaded while the host runs (W73).
    fn is_background(&self, id: &str) -> bool {
        self.pins
            .iter()
            .any(|p| p.id == id && p.kind == Kind::Web && p.background)
            && self.recent.iter().any(|r| r == id)
    }

    /// Its page must stay Active though it may be hidden and silent (W73, `awake`): in its grace, or a loaded
    /// background pin. Not while it plays: the engine keeps a sounding page Active itself.
    fn is_awake(&self, id: &str) -> bool {
        let st = self.states.get(id);
        !st.is_some_and(|st| st.audible)
            && (st.is_some_and(|st| st.grace.is_some())
                || (self.is_background(id) && st.is_some_and(|st| st.loaded)))
    }

    fn stamp(&mut self, spot: Spot) {
        self.stamp += 1;
        let at = self.stamp;
        match spot {
            Spot::Edge => self.edge_at = at,
            Spot::Sidebar => self.side_at = at,
            Spot::Card => self.card_at = at,
        }
    }

    /// The place that shows the page of the site `id` (W73, "last opened wins"): of the open places showing it, the
    /// one stamped last; on a tie (nothing stamped, a shell that predates `fresh`) the sidebar, then the bar card.
    fn holder(&self, id: &str) -> Option<Spot> {
        let mut best: Option<(u64, u8, Spot)> = None;
        let places = [
            (self.side_web(), self.side_at, 2, Spot::Sidebar),
            (self.card_web(), self.card_at, 1, Spot::Card),
            (self.edge_web(), self.edge_at, 0, Spot::Edge),
        ];
        for (web, at, rank, spot) in places {
            if web.as_deref() == Some(id) && best.is_none_or(|(a, r, _)| (at, rank) > (a, r)) {
                best = Some((at, rank, spot));
            }
        }
        best.map(|(_, _, spot)| spot)
    }

    /// The place that shows the page of the site `spot` shows, when that is another place (W73: `elsewhere`).
    fn elsewhere(&self, spot: Spot) -> Option<Spot> {
        let web = match spot {
            Spot::Edge => self.edge_web(),
            Spot::Sidebar => self.side_web(),
            Spot::Card => self.card_web(),
        }?;
        self.holder(&web).filter(|h| *h != spot)
    }

    fn is_web(&self, id: &str) -> bool {
        self.pins.iter().any(|p| p.id == id && p.kind == Kind::Web)
    }

    fn pin(&self, id: &str) -> Result<&PinSpec, DockError> {
        self.pins
            .iter()
            .find(|p| p.id == id)
            .ok_or(DockError::UnknownPin)
    }

    fn find(&self, id: &str) -> Result<(String, Kind), DockError> {
        self.pin(id).map(|p| (p.id.clone(), p.kind))
    }

    /// Moves a web pin to the front of the shown order.
    fn touch(&mut self, id: &str) {
        self.recent.retain(|r| r != id);
        self.recent.insert(0, id.to_string());
    }
}

/// The rows of the `pins` setting as the settings feed carries them now. A write reaches the feed before it returns,
/// so an action that follows a write reads the rows it wrote.
pub fn rows_of(settings: &Settings) -> Vec<Map<String, Value>> {
    records_of(settings, "pins")
}

/// The rows of a records setting `key` as the feed carries them.
pub fn records_of(settings: &Settings, key: &str) -> Vec<Map<String, Value>> {
    match settings.get(key) {
        Some(Value::Array(items)) => items
            .into_iter()
            .filter_map(|v| match v {
                Value::Object(m) => Some(m),
                _ => None,
            })
            .collect(),
        _ => Vec::new(),
    }
}

/// The `pins` rows after `webdock.view` on `pin`: every web pin of its profile takes `view` (QtWebEngine sets the
/// user agent per profile). Every other field of every row stays.
pub fn view_rows(
    rows: &[Map<String, Value>],
    pin: &str,
    view: View,
) -> Result<Vec<Value>, DockError> {
    let pins = pins_of(rows);
    let target = pins
        .iter()
        .find(|p| p.id == pin)
        .ok_or(DockError::UnknownPin)?;
    if target.kind != Kind::Web {
        return Err(DockError::NotASite);
    }
    let profile = target.profile.clone();
    let mut out = rows.to_vec();
    for p in pins
        .iter()
        .filter(|p| p.kind == Kind::Web && p.profile == profile)
    {
        if let Some(row) = out
            .iter_mut()
            .find(|r| r.get("id").and_then(Value::as_str) == Some(p.id.as_str()))
        {
            row.insert("view".into(), json!(view.name()));
        }
    }
    Ok(into_values(out))
}

/// The `pins` rows after `webdock.add {url, title?}`, and the new pin's id (K40). A site's address (`https`, `http`
/// or `file`) becomes a web pin: its id is the host without `www.` (a file's name), slugged and kept to 32 characters,
/// with `-2`, `-3`… when taken; its name is the title, else the host.
#[cfg(test)]
pub fn add_row(
    rows: &[Map<String, Value>],
    url: &str,
    title: Option<&str>,
) -> Result<(Vec<Value>, String), DockError> {
    add_row_with(rows, url, title, &[], None)
}

/// `add_row`, with ids that are taken outside the rows (W76: the temporary pages') and the profile a pin made from a
/// temporary page keeps (its storage: the page's cookies stay with it).
pub fn add_row_with(
    rows: &[Map<String, Value>],
    url: &str,
    title: Option<&str>,
    also_taken: &[String],
    profile: Option<&str>,
) -> Result<(Vec<Value>, String), DockError> {
    let view = view_target(url);
    if !web_address(url) && view.is_none() {
        return Err(DockError::Address);
    }
    let taken: Vec<&str> = rows
        .iter()
        .filter_map(|r| r.get("id").and_then(Value::as_str))
        .chain(also_taken.iter().map(String::as_str))
        .collect();
    // W78: a view (`mod:<id>:<name>`) is named by its view's name, a site by its host.
    let id = unique_id(&slug_of(view.map_or_else(|| id_text(url), |v| v.1)), &taken);
    let name = title
        .filter(|t| !t.is_empty())
        .map_or_else(|| host_of(url).unwrap_or(&id).to_string(), str::to_string);
    let mut out = rows.to_vec();
    let mut row = Map::from_iter([
        ("id".to_string(), json!(id)),
        ("title".to_string(), json!(name)),
        ("target".to_string(), json!(url)),
    ]);
    if let Some(profile) = profile.filter(|p| !p.is_empty() && *p != id) {
        row.insert("profile".into(), json!(profile));
    }
    out.push(row);
    Ok((into_values(out), id))
}

/// The `pins` rows without `pin` (`webdock.remove`).
pub fn remove_row(rows: &[Map<String, Value>], pin: &str) -> Result<Vec<Value>, DockError> {
    let index = row_index(rows, pin)?;
    let mut out = rows.to_vec();
    out.remove(index);
    Ok(into_values(out))
}

/// The `pins` rows with `pin` moved to index `to` (`webdock.move`, 0-based); the index is clamped to the list.
pub fn move_row(rows: &[Map<String, Value>], pin: &str, to: i64) -> Result<Vec<Value>, DockError> {
    let index = row_index(rows, pin)?;
    let mut out = rows.to_vec();
    let row = out.remove(index);
    let at = usize::try_from(to.max(0))
        .unwrap_or(usize::MAX)
        .min(out.len());
    out.insert(at, row);
    Ok(into_values(out))
}

/// The `pins` rows with a web pin's `target` replaced by `url` (`webdock.retarget`, "replace the pin with this page").
/// A view pin is refused, and so is any address but `https`, `http` or `file`.
pub fn retarget_row(
    rows: &[Map<String, Value>],
    pin: &str,
    url: &str,
) -> Result<Vec<Value>, DockError> {
    let index = row_index(rows, pin)?;
    if !pins_of(rows)
        .iter()
        .any(|p| p.id == pin && p.kind == Kind::Web)
    {
        return Err(DockError::NotASite);
    }
    if !web_address(url) {
        return Err(DockError::Address);
    }
    let mut out = rows.to_vec();
    out[index].insert("target".into(), json!(url));
    Ok(into_values(out))
}

/// The `sizes` rows (W76) after `webdock.resize {output, width?, height?}`: the output's row replaced by `size`, or
/// removed when `size` is `None` (the default again). Each side must be within [`MIN_BOX`]..=[`MAX_BOX`].
pub fn sizes_rows(
    rows: &[Map<String, Value>],
    output: &str,
    size: Option<(u32, u32)>,
) -> Result<Vec<Value>, DockError> {
    if output.is_empty() {
        return Err(DockError::Argument);
    }
    let mut out: Vec<Map<String, Value>> = rows
        .iter()
        .filter(|r| r.get("output").and_then(Value::as_str) != Some(output))
        .cloned()
        .collect();
    if let Some((w, h)) = size {
        if !(MIN_BOX..=MAX_BOX).contains(&w) || !(MIN_BOX..=MAX_BOX).contains(&h) {
            return Err(DockError::Argument);
        }
        out.push(Map::from_iter([
            ("output".to_string(), json!(output)),
            ("width".to_string(), json!(w)),
            ("height".to_string(), json!(h)),
        ]));
    }
    Ok(into_values(out))
}

/// The remembered boxes the `sizes` rows name, output → (width, height); a row out of range is skipped.
fn sizes_of(rows: &[Map<String, Value>]) -> BTreeMap<String, (u32, u32)> {
    let side = |r: &Map<String, Value>, k: &str| {
        r.get(k)
            .and_then(Value::as_u64)
            .and_then(|v| u32::try_from(v).ok())
            .filter(|v| (MIN_BOX..=MAX_BOX).contains(v))
    };
    rows.iter()
        .filter_map(|r| {
            let out = r.get("output")?.as_str().filter(|o| !o.is_empty())?;
            Some((out.to_string(), (side(r, "width")?, side(r, "height")?)))
        })
        .collect()
}

/// What the address field's text names (W76): an address (`https`, `http`, `file`) as it is; a bare host with a
/// dot and a known shape (`example.com/a`, `localhost:8080`, `10.0.0.2`) with `https://` (`http://` for localhost and an
/// IPv4 address); anything else — words, `javascript:`, `data:`, another scheme — a search with `engine`, `{q}` the
/// words (appended when the engine has no `{q}`). `None` for an empty text.
pub fn resolve(text: &str, engine: &str) -> Option<String> {
    let text = text.trim();
    if text.is_empty() {
        return None;
    }
    if web_address(text) {
        return Some(text.to_string());
    }
    // An absolute path is a local file, as a browser's address bar reads it.
    if text.starts_with('/') && !text.starts_with("//") && !text.contains(char::is_whitespace) {
        return Some(format!("file://{text}"));
    }
    if !text.contains(char::is_whitespace) {
        let host_port = text.split(['/', '?', '#']).next().unwrap_or("");
        let (host, port) = match host_port.rsplit_once(':') {
            Some((h, p)) => (h, Some(p)),
            None => (host_port, None),
        };
        let port_ok = port
            .is_none_or(|p| !p.is_empty() && p.len() <= 5 && p.bytes().all(|b| b.is_ascii_digit()));
        let ipv4 = host.split('.').count() == 4
            && host
                .split('.')
                .all(|o| !o.is_empty() && o.len() <= 3 && o.bytes().all(|b| b.is_ascii_digit()));
        let named = host.contains('.')
            && host
                .bytes()
                .all(|b| b.is_ascii_alphanumeric() || b == b'-' || b == b'.')
            && host
                .rsplit('.')
                .next()
                .is_some_and(|tld| tld.len() >= 2 && tld.bytes().all(|b| b.is_ascii_alphabetic()))
            && !host.starts_with('.')
            && !host.contains("..");
        if port_ok && (host == "localhost" || ipv4) {
            return Some(format!("http://{text}"));
        }
        if port_ok && named {
            return Some(format!("https://{text}"));
        }
    }
    let q = query_encode(text);
    Some(if engine.contains("{q}") {
        engine.replace("{q}", &q)
    } else {
        format!("{engine}{q}")
    })
}

/// The words of a search as a query value: unreserved characters as they are, a space as `+`, the rest `%XX`.
fn query_encode(text: &str) -> String {
    let mut out = String::new();
    for b in text.bytes() {
        match b {
            b'A'..=b'Z' | b'a'..=b'z' | b'0'..=b'9' | b'-' | b'.' | b'_' | b'~' => {
                out.push(char::from(b))
            }
            b' ' => out.push('+'),
            _ => out.push_str(&format!("%{b:02X}")),
        }
    }
    out
}

/// An address without its fragment and its trailing slashes (the host's home rule, WebPage.bare).
fn bare(url: &str) -> &str {
    let url = url.split('#').next().unwrap_or("");
    url.trim_end_matches('/')
}

fn row_index(rows: &[Map<String, Value>], pin: &str) -> Result<usize, DockError> {
    rows.iter()
        .position(|r| r.get("id").and_then(Value::as_str) == Some(pin))
        .ok_or(DockError::UnknownPin)
}

fn into_values(rows: Vec<Map<String, Value>>) -> Vec<Value> {
    rows.into_iter().map(Value::Object).collect()
}

/// The pins the rows name, the first of each id.
fn pins_of(rows: &[Map<String, Value>]) -> Vec<PinSpec> {
    let mut pins: Vec<PinSpec> = Vec::new();
    for row in rows {
        if let Some(pin) = parse_pin(row)
            && !pins.iter().any(|p| p.id == pin.id)
        {
            pins.push(pin);
        }
    }
    pins
}

/// One row of the `pins` setting as a pin; a row that is not a pin (no id, no target, a target with another scheme)
/// is skipped. The settings' validator refuses such rows, so this is for a value the feed carries in another shape.
fn parse_pin(row: &Map<String, Value>) -> Option<PinSpec> {
    let id = row.get("id")?.as_str()?.to_string();
    let target = row.get("target")?.as_str()?.to_string();
    let title = row
        .get("title")
        .and_then(Value::as_str)
        .filter(|t| !t.is_empty())
        .map_or_else(|| id.clone(), str::to_string);
    let kind = if target.starts_with("mod:") {
        Kind::View
    } else if ["https://", "http://", "file:"]
        .iter()
        .any(|scheme| target.starts_with(scheme))
    {
        Kind::Web
    } else {
        return None;
    };
    let view = match row.get("view").and_then(Value::as_str) {
        Some("mobile") => ViewSetting::Mobile,
        Some("desktop") => ViewSetting::Desktop,
        _ => ViewSetting::Default,
    };
    let profile = row
        .get("profile")
        .and_then(Value::as_str)
        .filter(|p| !p.is_empty())
        .map_or_else(|| id.clone(), str::to_string);
    Some(PinSpec {
        id,
        title,
        target,
        kind,
        view,
        profile,
        background: row.get("background").and_then(Value::as_bool) == Some(true),
        temp: None,
    })
}

/// A view's target `mod:<id>:<name>` as (mod, name), both non-empty slugs (W78: `webdock.add` takes one); else None.
fn view_target(target: &str) -> Option<(&str, &str)> {
    let (module, name) = target.strip_prefix("mod:")?.split_once(':')?;
    let slug = |s: &str| {
        !s.is_empty()
            && s.chars()
                .all(|c| c.is_ascii_lowercase() || c.is_ascii_digit() || c == '-' || c == '_')
    };
    (slug(module) && slug(name)).then_some((module, name))
}

/// A web pin's address: `https`, `http` or `file`, with something after the scheme (MODS.md: a pin's `target`
/// schemes without `mod:`, which names a view).
fn web_address(url: &str) -> bool {
    ["https://", "http://", "file:"].iter().any(|scheme| {
        url.strip_prefix(scheme)
            .is_some_and(|rest| !rest.is_empty())
    })
}

/// The host of an `http` or `https` address: the authority without the user name and the port.
fn host_of(url: &str) -> Option<&str> {
    let rest = url
        .strip_prefix("https://")
        .or_else(|| url.strip_prefix("http://"))?;
    let authority = rest.split(['/', '?', '#']).next()?;
    let host = authority.rsplit('@').next()?.split(':').next()?;
    (!host.is_empty()).then_some(host)
}

/// The text a pin's id is made of: the host of a web address, else the file name of a `file` address without its
/// extension.
fn id_text(url: &str) -> &str {
    match host_of(url) {
        Some(host) => host,
        None => url
            .rsplit('/')
            .find(|part| !part.is_empty())
            .map_or("", |name| {
                name.rsplit_once('.').map_or(name, |(stem, _)| stem)
            }),
    }
}

/// The `slug` of the `pins` records (kurashi-schema: `[a-z0-9-]`, 1 to 32 characters) for `text`: `www.` dropped,
/// lowercased, every other run of characters one hyphen, the ends trimmed. Empty becomes `site`.
fn slug_of(text: &str) -> String {
    let text = text.strip_prefix("www.").unwrap_or(text);
    let mut slug = String::new();
    for c in text.chars() {
        if c.is_ascii_alphanumeric() {
            slug.push(c.to_ascii_lowercase());
        } else if !slug.ends_with('-') {
            slug.push('-');
        }
    }
    let kept: String = slug.trim_matches('-').chars().take(32).collect();
    let kept = kept.trim_end_matches('-');
    if kept.is_empty() {
        "site".into()
    } else {
        kept.to_string()
    }
}

/// `base` when no row has it, else `base-2`, `base-3`… for the first that is free, with `base` cut to fit 32 characters.
fn unique_id(base: &str, taken: &[&str]) -> String {
    if !taken.contains(&base) {
        return base.into();
    }
    let mut n = 2;
    loop {
        let suffix = format!("-{n}");
        let stem: String = base.chars().take(32 - suffix.len()).collect();
        let candidate = format!("{}{suffix}", stem.trim_end_matches('-'));
        if !taken.contains(&candidate.as_str()) {
            return candidate;
        }
        n += 1;
    }
}

/// The file name the host gives a pin's icon (`WebPage.saveIcon`): the id with anything but `[A-Za-z0-9_.-]` as `_`.
fn icon_name(id: &str) -> String {
    id.chars()
        .map(|c| {
            if c.is_ascii_alphanumeric() || matches!(c, '_' | '.' | '-') {
                c
            } else {
                '_'
            }
        })
        .collect()
}

/// The `file://` URL of an icon the host reports, if it is an absolute path under the icon cache with no `..`
/// (MODS.md: `webdock.host.loaded` accepts an icon only under `dirs.icons`).
fn icon_url(path: &str, icons: &Path) -> Option<String> {
    let p = Path::new(path);
    let inside = p.is_absolute()
        && p.starts_with(icons)
        && !p
            .components()
            .any(|c| matches!(c, Component::ParentDir | Component::CurDir));
    inside.then(|| file_url(p))
}

/// `file://` URL of an absolute path, percent-encoded outside the unreserved characters.
fn file_url(path: &Path) -> String {
    let mut url = String::from("file://");
    for b in path.to_string_lossy().bytes() {
        match b {
            b'A'..=b'Z' | b'a'..=b'z' | b'0'..=b'9' | b'-' | b'.' | b'_' | b'~' | b'/' => {
                url.push(char::from(b));
            }
            _ => url.push_str(&format!("%{b:02X}")),
        }
    }
    url
}

#[cfg(test)]
mod tests {
    use super::*;
    use kurashi_mod_api::Values;
    use tokio::sync::watch;

    /// Settings as the feed carries them: the manifest's defaults, with `pins` as given.
    fn settings_with(pins: Value, overrides: &[(&str, Value)]) -> Settings {
        let mut v = Values::new();
        v.insert("pins".into(), pins);
        v.insert("default_view".into(), json!("mobile"));
        v.insert("width".into(), json!(412));
        v.insert("large".into(), json!(90));
        v.insert("edge".into(), json!("right"));
        v.insert("unload_after".into(), json!(60));
        v.insert("max_loaded".into(), json!(4));
        v.insert("hover".into(), json!(true));
        v.insert("reopen_last".into(), json!(true));
        v.insert("pinned".into(), json!(false));
        v.insert("reserve".into(), json!(false));
        v.insert("indicator".into(), json!(true));
        v.insert("strip".into(), json!(56));
        v.insert("new_tabs".into(), json!("dock"));
        for (k, val) in overrides {
            v.insert((*k).into(), val.clone());
        }
        Settings::new(watch::channel(v).1)
    }

    fn rows() -> Value {
        json!([
            {"id": "mail", "title": "Mail", "target": "https://mail.example.org/", "view": "default", "profile": "", "icon": ""},
            {"id": "chat", "title": "Chat", "target": "https://chat.example.org/", "view": "desktop", "profile": "", "icon": ""},
            {"id": "weather", "title": "Weather", "target": "mod:weather:weather", "view": "default", "profile": "", "icon": ""},
        ])
    }

    fn dock(overrides: &[(&str, Value)]) -> Dock {
        Dock::new(
            &settings_with(rows(), overrides),
            PathBuf::from("/d/profiles"),
            PathBuf::from("/c/icons"),
        )
    }

    /// A dock shown on `DP-1` with `mail` extended and the host ready, so that hover events land on it.
    fn shown(now: Instant) -> Dock {
        let mut d = dock(&[]);
        d.set_host(HostState::Ready);
        d.open("mail", Some("DP-1")).unwrap();
        d.hover(Part::Card, true, "DP-1", false, now);
        d
    }

    #[test]
    fn a_rest_on_the_edge_reveals_after_250_ms_and_500_on_a_shared_edge() {
        let t0 = Instant::now();
        let mut d = dock(&[]);
        d.open("mail", None).unwrap();
        d.hide();
        d.hover(Part::Edge, true, "DP-1", false, t0);
        assert_eq!(d.due_at(), Some(t0 + REVEAL));
        assert!(!d.tick(t0 + Duration::from_millis(249)), "not yet");
        assert_eq!(d.doc()["mode"], "hidden");
        assert!(d.tick(t0 + REVEAL), "reveal fires at 250 ms");
        assert_eq!(
            d.doc()["mode"],
            "extended",
            "reopen_last brings back the card"
        );
        assert_eq!(d.doc()["output"], "DP-1");

        let mut d = dock(&[]);
        d.hover(Part::Edge, true, "DP-1", true, t0);
        assert_eq!(d.due_at(), Some(t0 + REVEAL_SHARED));
        d.tick(t0 + REVEAL_SHARED);
        assert_eq!(d.doc()["mode"], "compact", "nothing shown: the strip only");
    }

    #[test]
    fn leaving_the_edge_before_the_reveal_disarms_it_and_another_outputs_leave_does_not() {
        let t0 = Instant::now();
        let mut d = dock(&[]);
        d.hover(Part::Edge, true, "DP-1", false, t0);
        d.hover(
            Part::Edge,
            false,
            "DP-1",
            false,
            t0 + Duration::from_millis(100),
        );
        assert_eq!(d.due_at(), None, "the leave disarms");
        assert!(!d.tick(t0 + REVEAL));
        assert_eq!(d.doc()["mode"], "hidden");

        // The pointer moved from DP-2's edge onto DP-1's: DP-2's leave arrives after DP-1's enter.
        let mut d = dock(&[]);
        d.hover(Part::Edge, true, "DP-1", false, t0);
        d.hover(
            Part::Edge,
            false,
            "DP-2",
            false,
            t0 + Duration::from_millis(10),
        );
        assert_eq!(
            d.due_at(),
            Some(t0 + REVEAL),
            "the other output's leave keeps DP-1's reveal"
        );
    }

    #[test]
    fn hover_off_ignores_the_edge_and_leaves_the_strip_alone() {
        let t0 = Instant::now();
        let mut d = dock(&[("hover", json!(false))]);
        d.hover(Part::Edge, true, "DP-1", false, t0);
        assert_eq!(d.due_at(), None);
        assert!(!d.tick(t0 + REVEAL));
        assert_eq!(d.doc()["mode"], "hidden");
        assert_eq!(d.doc()["hover"], false);
    }

    #[test]
    fn reopen_last_off_reveals_the_strip_only_and_keeps_the_shown_pin() {
        let t0 = Instant::now();
        let mut d = dock(&[("reopen_last", json!(false))]);
        d.open("chat", Some("DP-1")).unwrap();
        d.hide();
        d.hover(Part::Edge, true, "DP-1", false, t0);
        d.tick(t0 + REVEAL);
        assert_eq!(d.doc()["mode"], "compact");
        assert_eq!(
            d.doc()["shown"],
            "chat",
            "the pin is kept for the next open"
        );
    }

    #[test]
    fn a_shown_dock_hides_400_ms_after_the_last_part_leaves_and_any_part_entering_disarms_it() {
        let t0 = Instant::now();
        let mut d = shown(t0);
        d.hover(Part::Card, false, "DP-1", false, t0);
        assert_eq!(d.due_at(), Some(t0 + HIDE));
        d.hover(
            Part::Strip,
            true,
            "DP-1",
            false,
            t0 + Duration::from_millis(100),
        );
        assert_eq!(d.due_at(), None, "entering a part disarms the hide");
        d.hover(
            Part::Strip,
            false,
            "DP-1",
            false,
            t0 + Duration::from_millis(200),
        );
        assert_eq!(
            d.due_at(),
            Some(t0 + Duration::from_millis(600)),
            "a new hide, from the new leave"
        );
        assert!(
            !d.tick(t0 + Duration::from_millis(600)),
            "a hide starts no site"
        );
        assert_eq!(d.doc()["mode"], "hidden");
        assert_eq!(d.doc()["shown"], "mail", "hide keeps the shown pin");
    }

    #[test]
    fn a_hide_keeps_its_deadline_while_the_pointer_stays_outside() {
        let t0 = Instant::now();
        let mut d = shown(t0);
        d.hover(Part::Card, false, "DP-1", false, t0);
        d.hover(
            Part::Strip,
            false,
            "DP-1",
            false,
            t0 + Duration::from_millis(50),
        );
        assert_eq!(
            d.due_at(),
            Some(t0 + HIDE),
            "later reports do not push the hide back"
        );
    }

    #[test]
    fn the_engage_handoff_from_strip_to_card_does_not_hide() {
        let t0 = Instant::now();
        let mut d = shown(t0);
        d.engage(true, t0);
        d.hover(Part::Strip, true, "DP-1", false, t0);
        d.hover(Part::Card, true, "DP-1", false, t0);
        d.hover(
            Part::Strip,
            false,
            "DP-1",
            false,
            t0 + Duration::from_millis(10),
        );
        d.engage(false, t0 + Duration::from_millis(10));
        assert_eq!(d.due_at(), None, "the card is inside");
        d.engage(true, t0 + Duration::from_millis(20));
        d.hover(
            Part::Card,
            false,
            "DP-1",
            false,
            t0 + Duration::from_millis(30),
        );
        assert_eq!(d.due_at(), None, "the card's focus holds it");
        assert_eq!(d.doc()["engaged"], true);
    }

    #[test]
    fn pinned_and_engaged_hold_the_dock_open() {
        let t0 = Instant::now();
        let mut d = shown(t0);
        d.engage(true, t0);
        d.hover(Part::Card, false, "DP-1", false, t0);
        assert_eq!(d.due_at(), None, "engaged holds");
        d.engage(false, t0);
        assert_eq!(
            d.due_at(),
            Some(t0 + HIDE),
            "losing focus counts as a leave"
        );

        let mut d = dock(&[("pinned", json!(true))]);
        d.set_host(HostState::Ready);
        d.open("mail", None).unwrap();
        d.hover(Part::Card, false, "DP-1", false, t0);
        assert_eq!(d.due_at(), None, "pinned ignores the leave");
        assert_eq!(d.doc()["pinned"], true);
    }

    #[test]
    fn unpinning_with_nothing_inside_arms_the_hide() {
        let t0 = Instant::now();
        let mut d = dock(&[("pinned", json!(true))]);
        d.open("mail", None).unwrap();
        d.hover(Part::Card, false, "DP-1", false, t0);
        assert_eq!(d.due_at(), None);
        let unpinned = settings_with(rows(), &[("pinned", json!(false))]);
        d.apply_settings(&unpinned, t0 + Duration::from_secs(1));
        assert_eq!(
            d.due_at(),
            Some(t0 + Duration::from_secs(1) + HIDE),
            "unpinned returns to the rules above"
        );
    }

    #[test]
    fn other_output_events_are_ignored_while_shown_and_the_first_report_latches_the_output() {
        let t0 = Instant::now();
        let mut d = shown(t0);
        d.hover(Part::Card, false, "DP-1", false, t0);
        assert_eq!(d.due_at(), Some(t0 + HIDE));
        d.hover(
            Part::Card,
            true,
            "DP-2",
            false,
            t0 + Duration::from_millis(10),
        );
        assert_eq!(
            d.due_at(),
            Some(t0 + HIDE),
            "another output's enter does not hold it"
        );
        d.hover(
            Part::Strip,
            false,
            "DP-2",
            false,
            t0 + Duration::from_millis(20),
        );
        assert_eq!(d.due_at(), Some(t0 + HIDE), "nor its leave move the hide");
        d.hover(
            Part::Card,
            true,
            "DP-1",
            false,
            t0 + Duration::from_millis(30),
        );
        assert_eq!(d.due_at(), None, "this output's enter disarms it");
        assert_eq!(d.doc()["output"], "DP-1");
    }

    #[test]
    fn rapid_enter_and_leave_twenty_times_ends_in_a_consistent_state() {
        let t0 = Instant::now();
        let mut d = dock(&[]);
        for i in 0..20u64 {
            let at = t0 + Duration::from_millis(i * 10);
            d.hover(Part::Edge, i % 2 == 0, "DP-1", false, at);
        }
        // The last event (i = 19) is a leave: nothing is armed and nothing reveals.
        assert_eq!(d.due_at(), None);
        assert!(!d.tick(t0 + Duration::from_secs(5)));
        assert_eq!(d.doc()["mode"], "hidden");

        // Twenty alternations, then an enter that stays: one reveal, 250 ms after that enter, then shown.
        let mut d = dock(&[]);
        for i in 0..20u64 {
            let at = t0 + Duration::from_millis(i * 10);
            d.hover(Part::Edge, i % 2 == 0, "DP-1", false, at);
        }
        d.hover(
            Part::Edge,
            true,
            "DP-1",
            false,
            t0 + Duration::from_millis(200),
        );
        assert_eq!(d.due_at(), Some(t0 + Duration::from_millis(200) + REVEAL));
        d.tick(t0 + Duration::from_millis(450));
        assert_eq!(d.doc()["mode"], "compact");
    }

    #[test]
    fn toggle_reveals_with_the_keyboard_in_the_dock_and_hides_without_it() {
        let t0 = Instant::now();
        let mut d = dock(&[]);
        d.open("chat", None).unwrap();
        d.hide();
        d.toggle(Some("DP-1"));
        assert_eq!(d.doc()["mode"], "extended");
        assert_eq!(d.doc()["engaged"], true);
        d.toggle(None);
        assert_eq!(d.doc()["mode"], "hidden");
        assert_eq!(d.doc()["engaged"], false);
        d.hover(Part::Card, false, "DP-1", false, t0);
        assert_eq!(d.due_at(), None, "a hidden dock arms no hide");

        let mut d = dock(&[]);
        d.toggle(None);
        assert_eq!(d.doc()["mode"], "compact", "nothing shown: the strip");
    }

    #[test]
    fn select_shows_a_pin_and_a_second_click_on_the_shown_pin_puts_its_card_away() {
        let mut d = dock(&[]);
        d.set_host(HostState::Ready);
        assert!(d.select("mail", None).unwrap(), "a site starts the host");
        assert_eq!(d.doc()["mode"], "extended");
        assert_eq!(d.doc()["shown"], "mail");
        assert_eq!(d.doc()["keep"], json!(["mail"]));

        assert!(d.select("chat", None).unwrap());
        assert_eq!(d.doc()["shown"], "chat");
        assert!(
            !d.select("chat", None).unwrap(),
            "the same pin again: compact"
        );
        assert_eq!(d.doc()["mode"], "compact");
        assert!(d.doc().get("shown").is_none());
        assert_eq!(
            d.doc()["keep"],
            json!(["chat", "mail"]),
            "the pin stays loaded"
        );

        assert!(!d.select("weather", None).unwrap(), "a view starts no host");
        assert_eq!(d.doc()["mode"], "extended");
        assert_eq!(d.select("zzz", None), Err(DockError::UnknownPin));
    }

    #[test]
    fn forced_settings_are_published_with_their_source() {
        let forced =
            dock(&[]).with_forced(BTreeMap::from([("pinned".to_string(), "nix".to_string())]));
        assert_eq!(
            forced.doc()["forced"]["pinned"],
            "nix",
            "the forced pinned names its source"
        );
        assert!(
            dock(&[]).doc().get("forced").is_none(),
            "nothing forced: no block (no nulls)"
        );
    }

    #[test]
    fn forced_pins_name_their_source_on_each_pin() {
        let d = dock(&[]).with_forced(BTreeMap::from([("pins".to_string(), "nix".to_string())]));
        let pins = d.doc()["pins"].clone();
        assert!(pins.as_array().is_some_and(|p| !p.is_empty()));
        for pin in pins.as_array().into_iter().flatten() {
            assert_eq!(pin["forced_by"], "nix");
        }
        assert!(dock(&[]).doc()["pins"][0].get("forced_by").is_none());
    }

    #[test]
    fn back_steps_extended_to_compact_and_compact_to_hidden_unless_pinned() {
        let mut d = dock(&[]);
        d.open("mail", None).unwrap();
        d.back();
        assert_eq!(d.doc()["mode"], "compact");
        assert!(
            d.doc().get("shown").is_none(),
            "extended to compact clears the card"
        );
        d.back();
        assert_eq!(d.doc()["mode"], "hidden");
        d.back();
        assert_eq!(d.doc()["mode"], "hidden", "hidden stays hidden");

        let mut d = dock(&[("pinned", json!(true))]);
        d.collapse();
        d.back();
        assert_eq!(d.doc()["mode"], "compact", "pinned: stays compact");
    }

    #[test]
    fn add_derives_the_id_from_the_host_and_takes_the_next_free_suffix() {
        let rows = rows_list(json!([
            {"id": "mail", "title": "Mail", "target": "https://mail.example.org/"},
        ]));
        let (out, id) = add_row(&rows, "https://www.Example.org/a?b=c", None).unwrap();
        assert_eq!(id, "example-org");
        let row = out.last().unwrap();
        assert_eq!(
            row["title"], "www.Example.org",
            "the title is the host when none is given"
        );
        assert_eq!(row["target"], "https://www.Example.org/a?b=c");

        let rows = rows_list(json!([
            {"id": "example-org", "title": "A", "target": "https://example.org/"},
            {"id": "example-org-2", "title": "B", "target": "https://example.org/b"},
        ]));
        let (out, id) = add_row(&rows, "https://example.org/", Some("Docs")).unwrap();
        assert_eq!(id, "example-org-3", "the first free suffix");
        assert_eq!(
            out.last().unwrap()["title"],
            "Docs",
            "the argument is the title"
        );
        assert_eq!(out.len(), 3);

        let (_, id) = add_row(&[], "file:///home/u/Notes.html", None).unwrap();
        assert_eq!(id, "notes", "a file names its pin by its file name");
        let long = format!("https://{}.example.org/", "a".repeat(40));
        let (_, id) = add_row(&[], &long, None).unwrap();
        assert_eq!(id.len(), 32, "the slug keeps 32 characters");
    }

    #[test]
    fn add_refuses_any_address_but_https_http_and_file() {
        assert_eq!(
            add_row(&[], "javascript:alert(1)", None),
            Err(DockError::Address)
        );
        assert_eq!(add_row(&[], "mod:weather", None), Err(DockError::Address));
        assert_eq!(add_row(&[], "mod::x", None), Err(DockError::Address));
        assert_eq!(add_row(&[], "mod:a:B/../c", None), Err(DockError::Address));
        assert_eq!(add_row(&[], "https://", None), Err(DockError::Address));
        assert_eq!(
            add_row(&[], "ftp://example.org/", None),
            Err(DockError::Address)
        );
    }

    #[test]
    fn move_clamps_the_index_and_keeps_every_other_row_as_it_was() {
        let rows = rows_list(rows());
        let out = move_row(&rows, "weather", 0).unwrap();
        assert_eq!(out[0]["id"], "weather");
        assert_eq!(out[1]["id"], "mail");
        let out = move_row(&rows, "mail", 99).unwrap();
        assert_eq!(out.last().unwrap()["id"], "mail", "clamped to the end");
        let out = move_row(&rows, "chat", -4).unwrap();
        assert_eq!(out[0]["id"], "chat", "clamped to the start");
        assert_eq!(
            out[1],
            Value::Object(rows[0].clone()),
            "the other rows keep their fields"
        );
        assert_eq!(move_row(&rows, "zzz", 0), Err(DockError::UnknownPin));
    }

    #[test]
    fn retarget_refuses_a_view_pin_and_javascript_and_keeps_the_other_fields() {
        let rows = rows_list(rows());
        assert_eq!(
            retarget_row(&rows, "weather", "https://example.org/"),
            Err(DockError::NotASite)
        );
        assert_eq!(
            retarget_row(&rows, "mail", "javascript:alert(1)"),
            Err(DockError::Address)
        );
        let out = retarget_row(&rows, "mail", "https://example.org/new").unwrap();
        assert_eq!(out[0]["target"], "https://example.org/new");
        assert_eq!(
            out[0]["title"], "Mail",
            "every other field of the row stays"
        );
        assert_eq!(out[0]["view"], "default");
        assert_eq!(
            out[1],
            Value::Object(rows[1].clone()),
            "other rows are untouched"
        );
    }

    #[test]
    fn a_view_write_keeps_every_other_field_and_a_view_pin_is_not_a_site() {
        let rows = rows_list(json!([
            {"id": "a", "title": "A", "target": "https://a.example.org/", "view": "default", "profile": "work", "icon": "x"},
            {"id": "b", "title": "B", "target": "https://b.example.org/", "view": "desktop", "profile": "work", "icon": ""},
            {"id": "w", "title": "W", "target": "mod:weather:weather", "view": "default", "profile": "", "icon": ""},
        ]));
        let out = view_rows(&rows, "b", View::Mobile).unwrap();
        assert_eq!(out[0]["view"], "mobile", "a shares b's profile");
        assert_eq!(out[1]["view"], "mobile");
        assert_eq!(out[0]["icon"], "x", "the other fields stay");
        assert_eq!(out[0]["title"], "A");
        assert_eq!(
            view_rows(&rows, "w", View::Mobile),
            Err(DockError::NotASite)
        );
    }

    /// W69: `page_style` is absent while it is the phone (the fixture's document) and names the style otherwise.
    #[test]
    fn the_page_style_is_published_unless_it_is_the_phone() {
        assert!(dock(&[]).doc().get("page_style").is_none());
        assert!(
            dock(&[("page_style", json!("phone"))])
                .doc()
                .get("page_style")
                .is_none()
        );
        for style in ["notebook", "plain"] {
            let d = dock(&[("page_style", json!(style))]);
            assert_eq!(d.doc()["page_style"], style);
        }
        // An unknown value (a hand-edited config past validation) reads as the phone.
        assert!(
            dock(&[("page_style", json!("scroll"))])
                .doc()
                .get("page_style")
                .is_none()
        );
    }

    /// Row 250: once the sidebar shows the dock, `sidebar {pin, place}` carries the fixture variant's keys.
    #[test]
    fn the_sidebar_keys_match_their_fixture() {
        let fixture: Value = serde_json::from_str(include_str!(
            "../../../fixtures/ipc/server/snap_mod_webdock_sidebar.json"
        ))
        .unwrap();
        let fixture = &fixture["data"]["sidebar"];
        let mut d = dock(&[]);
        d.set_host(HostState::Ready);
        d.side_select("mail").unwrap();
        d.place(
            Some(Place {
                output: "DP-1".into(),
                side: Side::Left,
                inset: 12,
                top: 60,
                width: 396,
                height: 1336,
            }),
            true,
        );
        let doc = d.doc();
        assert_eq!(keys(&doc["sidebar"]), keys(fixture), "the sidebar");
        assert_eq!(
            keys(&doc["sidebar"]["place"]),
            keys(&fixture["place"]),
            "its place"
        );
        assert_eq!(doc["sidebar"]["place"]["side"], "left");
    }

    fn card_place() -> CardPlace {
        CardPlace {
            output: "DP-1".into(),
            x: 1480,
            y: 540,
            width: 412,
            height: 640,
        }
    }

    /// W72: the bar card is absent until used; an open card shows the first pin, counts as shown (kept past the cap, the
    /// idle clock waits), and its place, reports and counters go as documented.
    #[test]
    fn the_bar_card_shows_the_first_pin_and_counts_as_shown() {
        let mut d = dock(&[("max_loaded", json!(1))]);
        assert!(d.doc().get("card").is_none(), "no card key before use");
        d.set_host(HostState::Ready);
        // (the edge shows chat, so mail is past a cap of one but on screen in the card)
        d.open("chat", Some("DP-1")).unwrap();
        assert!(
            d.card_place(Some(card_place()), true),
            "an open card on a site starts the host"
        );
        let doc = d.doc();
        assert_eq!(doc["card"]["pin"], "mail", "the first pin");
        assert_eq!(doc["card"]["place"]["x"], 1480);
        assert_eq!(doc["card"]["place"]["output"], "DP-1");
        assert!(doc["card"].get("hover").is_none() && doc["card"].get("close").is_none());
        let mut keep = d.keep();
        keep.sort();
        assert_eq!(
            keep,
            vec!["chat", "mail"],
            "the card's site is kept past the cap"
        );
        assert!(!d.is_idle(), "a site in the card is shown");

        d.card_page(true, true);
        d.card_close();
        d.card_focus();
        let doc = d.doc();
        assert_eq!(doc["card"]["hover"], true);
        assert_eq!(doc["card"]["engaged"], true);
        assert_eq!(doc["card"]["close"], 1);
        assert_eq!(doc["card"]["focus"], 1);

        // Closed: the place, the pointer and the keyboard go; the pin and the counters stay; late reports are dropped.
        assert!(!d.card_place(None, false));
        d.card_page(true, false);
        d.card_close();
        d.card_focus();
        let doc = d.doc();
        assert!(doc["card"].get("place").is_none() && doc["card"].get("hover").is_none());
        assert!(doc["card"].get("engaged").is_none());
        assert_eq!(doc["card"]["pin"], "mail");
        assert_eq!(doc["card"]["close"], 1);
        assert_eq!(doc["card"]["focus"], 1);

        // A view pin in the card starts nothing; a closed card keeps a pick for its next opening.
        assert!(!d.card_select("weather").unwrap());
        assert!(d.card_select("nope").is_err());
        assert!(
            !d.card_place(Some(card_place()), true),
            "a view pin needs no host"
        );
        assert!(d.card_select("mail").unwrap());
    }

    /// W72: a host that fails takes the card window's pointer and keyboard with it.
    #[test]
    fn a_failed_host_forgets_the_bar_cards_pointer() {
        let mut d = dock(&[]);
        d.set_host(HostState::Ready);
        d.card_place(Some(card_place()), true);
        d.card_page(true, true);
        d.set_host(HostState::Missing);
        let doc = d.doc();
        assert!(doc["card"].get("hover").is_none() && doc["card"].get("engaged").is_none());
    }

    #[test]
    fn the_document_has_the_fixture_keys() {
        let fixture: Value = serde_json::from_str(include_str!(
            "../../../fixtures/ipc/server/snap_mod_webdock.json"
        ))
        .unwrap();
        let fixture = &fixture["data"];
        let t0 = Instant::now();
        let mut d = dock(&[]);
        d.set_host(HostState::Ready);
        d.open("mail", Some("DP-1")).unwrap();
        d.engage(true, t0);
        // The fixture's marks: mail loaded with its icon; chat crashed, blocked and audible; weather a view.
        d.loaded("mail", Some("/c/icons/mail.png")).unwrap();
        d.crashed("chat").unwrap();
        d.blocked("chat", "camera").unwrap();
        d.audible("chat", true, t0).unwrap();
        let doc = d.doc();
        assert_eq!(keys(&doc), keys(fixture), "the top level");
        assert_eq!(
            keys(&doc["geometry"]),
            keys(&fixture["geometry"]),
            "the geometry"
        );
        assert_eq!(keys(&doc["host"]), keys(&fixture["host"]), "the host");
        assert_eq!(keys(&doc["dirs"]), keys(&fixture["dirs"]), "the dirs");
        for i in 0..3 {
            assert_eq!(keys(&doc["pins"][i]), keys(&fixture["pins"][i]), "pin {i}");
        }
        assert_eq!(doc["geometry"]["grace"], GRACE_PX);
        assert_eq!(doc["engaged"], true);
        assert_eq!(doc["pins"][1]["error"], "webdock.error.crashed");
    }

    fn place_left() -> Place {
        Place {
            output: "DP-1".into(),
            side: Side::Left,
            inset: 12,
            top: 60,
            width: 396,
            height: 1300,
        }
    }

    #[test]
    fn the_sidebar_is_absent_until_used_and_an_open_sidebar_shows_the_first_pin() {
        let mut d = dock(&[]);
        assert!(
            d.doc().get("sidebar").is_none(),
            "no sidebar key before use"
        );
        d.set_host(HostState::Ready);
        assert!(
            d.place(Some(place_left()), true),
            "the first pin is a site: the host starts"
        );
        let doc = d.doc();
        assert_eq!(doc["sidebar"]["pin"], "mail");
        assert_eq!(
            doc["sidebar"]["place"],
            json!({"output": "DP-1", "side": "left", "inset": 12, "top": 60, "width": 396, "height": 1300})
        );
        assert_eq!(doc["keep"], json!(["mail"]), "the sidebar's site is kept");
        assert!(!d.is_idle(), "a site in the sidebar is shown");
        // Closing the sidebar hides the page but keeps it loaded and keeps the pin for next time.
        assert!(!d.place(None, false));
        let doc = d.doc();
        assert_eq!(doc["sidebar"], json!({"pin": "mail"}));
        assert_eq!(doc["keep"], json!(["mail"]));
        assert!(
            d.is_idle(),
            "nothing shown: the idle clock runs (unload_after unchanged)"
        );
    }

    #[test]
    fn sidebar_select_switches_pins_and_a_view_pin_does_not_start_the_host() {
        let mut d = dock(&[]);
        d.set_host(HostState::Ready);
        assert!(
            !d.side_select("chat").unwrap(),
            "a closed sidebar starts nothing"
        );
        assert_eq!(d.doc()["keep"], json!([]), "nor loads anything");
        assert!(d.place(Some(place_left()), true));
        assert_eq!(
            d.doc()["sidebar"]["pin"],
            "chat",
            "the chosen pin, not the first"
        );
        assert!(
            !d.side_select("weather").unwrap(),
            "a view is drawn by the shell"
        );
        assert!(d.is_idle(), "a view in the sidebar is not a site on screen");
        assert_eq!(d.side_select("nope"), Err(DockError::UnknownPin));
    }

    #[test]
    fn the_edge_and_the_sidebar_keep_both_sites_beyond_the_cap() {
        let mut d = dock(&[("max_loaded", json!(1))]);
        d.set_host(HostState::Ready);
        d.open("mail", Some("DP-1")).unwrap();
        d.side_select("chat").unwrap();
        d.place(Some(place_left()), true);
        let keep = d.doc()["keep"].clone();
        assert_eq!(keep, json!(["chat", "mail"]), "both on screen, cap 1");
        d.collapse();
        assert_eq!(
            d.doc()["keep"],
            json!(["chat"]),
            "the edge's site leaves at the cap"
        );
    }

    #[test]
    fn a_removed_sidebar_pin_falls_back_to_the_first_pin_while_open() {
        let mut d = dock(&[]);
        d.side_select("chat").unwrap();
        d.place(Some(place_left()), true);
        let rows = json!([
            {"id": "mail", "title": "Mail", "target": "https://mail.example.org/", "view": "default", "profile": "", "icon": ""},
        ]);
        d.apply_settings(&settings_with(rows, &[]), Instant::now());
        assert_eq!(d.doc()["sidebar"]["pin"], "mail");
    }

    fn keys(v: &Value) -> Vec<String> {
        let mut k: Vec<String> = v
            .as_object()
            .map(|m| m.keys().cloned().collect())
            .unwrap_or_default();
        k.sort();
        k
    }

    fn rows_list(v: Value) -> Vec<Map<String, Value>> {
        match v {
            Value::Array(items) => items
                .into_iter()
                .filter_map(|v| match v {
                    Value::Object(m) => Some(m),
                    _ => None,
                })
                .collect(),
            _ => Vec::new(),
        }
    }

    #[test]
    fn an_icon_is_accepted_only_under_the_cache_and_without_parent_steps() {
        let icons = Path::new("/c/webdock/icons");
        assert_eq!(
            icon_url("/c/webdock/icons/mail.png", icons).as_deref(),
            Some("file:///c/webdock/icons/mail.png")
        );
        assert_eq!(icon_url("/c/webdock/icons2/mail.png", icons), None);
        assert_eq!(icon_url("/c/webdock/icons/../../etc/passwd", icons), None);
        assert_eq!(icon_url("icons/mail.png", icons), None);
        assert_eq!(icon_url("/etc/passwd", icons), None);
    }

    #[test]
    fn a_pin_is_web_or_view_by_its_target_and_shares_a_profile_by_name() {
        let row = |id: &str, target: &str, profile: &str| {
            let mut m = Map::new();
            m.insert("id".into(), json!(id));
            m.insert("target".into(), json!(target));
            m.insert("profile".into(), json!(profile));
            m
        };
        let web = parse_pin(&row("mail", "https://mail.example.org/", "work")).unwrap();
        assert_eq!(web.kind, Kind::Web);
        assert_eq!(web.profile, "work");
        let own = parse_pin(&row("chat", "https://chat.example.org/", "")).unwrap();
        assert_eq!(own.profile, "chat");
        let view = parse_pin(&row("weather", "mod:weather:weather", "")).unwrap();
        assert_eq!(view.kind, Kind::View);
        assert!(parse_pin(&row("x", "javascript:alert(1)", "")).is_none());
    }

    fn pin_of<'a>(doc: &'a Value, id: &str) -> &'a Value {
        doc["pins"]
            .as_array()
            .unwrap()
            .iter()
            .find(|p| p["id"] == id)
            .unwrap()
    }

    /// W73 (I488): the silence between two tracks keeps a player past the cap, awake, and the engine up, for the grace;
    /// after it the pin goes back to the rules and the idle clock may run.
    #[test]
    fn a_player_past_the_cap_is_kept_awake_through_the_grace_after_its_sound() {
        let t0 = Instant::now();
        let mut d = dock(&[("max_loaded", json!(1))]);
        d.set_host(HostState::Ready);
        d.open("mail", Some("DP-1")).unwrap();
        d.loaded("mail", None).unwrap();
        d.audible("mail", true, t0).unwrap();
        d.open("chat", Some("DP-1")).unwrap();
        assert_eq!(d.keep(), vec!["chat", "mail"], "playing past the cap");
        assert!(
            pin_of(&d.doc(), "mail").get("awake").is_none(),
            "a sounding page needs no mark"
        );

        // The track ends: silent, but in its grace.
        let t1 = t0 + Duration::from_secs(180);
        d.audible("mail", false, t1).unwrap();
        assert_eq!(d.keep(), vec!["chat", "mail"], "the gap keeps the player");
        let doc = d.doc();
        assert_eq!(pin_of(&doc, "mail")["awake"], true);
        assert!(
            pin_of(&doc, "mail").get("audible").is_none(),
            "audible stays the engine's word"
        );
        d.collapse();
        assert!(!d.is_idle(), "a player in its grace holds the engine");
        assert_eq!(d.grace_due(), Some(t1 + AUDIBLE_GRACE));

        // The next track starts within the grace: the grace goes; it ends again later.
        d.audible("mail", true, t1 + Duration::from_secs(2))
            .unwrap();
        assert_eq!(d.grace_due(), None);
        let t2 = t1 + Duration::from_secs(400);
        d.audible("mail", false, t2).unwrap();
        assert!(!d.expire(t2 + AUDIBLE_GRACE - Duration::from_secs(1)));
        assert!(d.keep().contains(&"mail".to_string()));
        assert!(d.expire(t2 + AUDIBLE_GRACE), "the grace ends");
        assert_eq!(d.grace_due(), None);
        assert_eq!(d.keep(), vec!["chat"], "past the grace the cap applies");
        assert!(pin_of(&d.doc(), "mail").get("awake").is_none());
        assert!(d.is_idle(), "nothing holds the engine now");

        // A first "not audible" report (no sound before it) starts no grace; a host that stops takes the grace with it.
        d.audible("chat", false, t2).unwrap();
        assert_eq!(d.grace_due(), None);
        d.audible("chat", true, t2).unwrap();
        d.audible("chat", false, t2).unwrap();
        assert!(d.grace_due().is_some());
        d.set_host(HostState::Off);
        assert_eq!(d.grace_due(), None);
    }

    /// W73: a background pin, once opened, is kept past the cap, awake while loaded, and holds the engine; one that was
    /// never opened changes nothing.
    #[test]
    fn a_background_pin_is_kept_awake_and_holds_the_engine_once_opened() {
        let mut rows = rows();
        rows.as_array_mut().unwrap().push(json!(
            {"id": "radio", "title": "Radio", "target": "https://radio.example.org/", "background": true}
        ));
        let mut d = Dock::new(
            &settings_with(rows, &[("max_loaded", json!(1))]),
            PathBuf::from("/d/profiles"),
            PathBuf::from("/c/icons"),
        );
        d.set_host(HostState::Ready);
        assert_eq!(pin_of(&d.doc(), "radio")["background"], true);
        assert!(pin_of(&d.doc(), "mail").get("background").is_none());
        d.open("mail", Some("DP-1")).unwrap();
        d.collapse();
        assert!(d.is_idle(), "a background pin never opened holds nothing");
        assert_eq!(d.keep(), vec!["mail"]);

        d.open("radio", Some("DP-1")).unwrap();
        d.loaded("radio", None).unwrap();
        d.open("chat", Some("DP-1")).unwrap();
        let mut keep = d.keep();
        keep.sort();
        assert_eq!(keep, vec!["chat", "radio"], "kept past the cap");
        assert_eq!(pin_of(&d.doc(), "radio")["awake"], true);
        d.collapse();
        assert!(!d.is_idle(), "a loaded background pin holds the engine");
    }

    /// W73 (I488 (4)): of the open places that show a pin, the one opened or picked last shows its page; the others say
    /// where it is. A re-rest (a move, a resize) steals nothing; a close hands the page to the next one.
    #[test]
    fn the_place_opened_last_shows_the_page_and_the_others_say_where() {
        let mut d = dock(&[]);
        d.set_host(HostState::Ready);
        d.open("mail", Some("DP-1")).unwrap();
        assert!(d.doc().get("elsewhere").is_none(), "one place: it shows it");

        // The bar card opens on mail after the edge: the card shows it.
        d.card_place(Some(card_place()), true);
        let doc = d.doc();
        assert_eq!(doc["elsewhere"], "card");
        assert!(doc["card"].get("elsewhere").is_none());

        // "Show here" at the edge (webdock.open) takes it back; the card's re-rest after a move does not.
        d.open("mail", Some("DP-1")).unwrap();
        assert_eq!(d.doc()["card"]["elsewhere"], "edge");
        d.card_place(None, false);
        d.card_place(Some(card_place()), false);
        assert_eq!(
            d.doc()["card"]["elsewhere"],
            "edge",
            "a re-rest steals nothing"
        );
        assert!(d.doc().get("elsewhere").is_none());
        d.card_select("mail").unwrap();
        assert_eq!(
            d.doc()["elsewhere"],
            "card",
            "a pick in the card brings it there"
        );

        // The sidebar opens on mail last: it shows it, both others say so.
        d.side_select("mail").unwrap();
        d.place(Some(place_left()), true);
        let doc = d.doc();
        assert_eq!(doc["elsewhere"], "sidebar");
        assert_eq!(doc["card"]["elsewhere"], "sidebar");
        assert!(doc["sidebar"].get("elsewhere").is_none());

        // The sidebar closes: the card (the latest of the others) shows it again.
        d.place(None, false);
        let doc = d.doc();
        assert!(doc["card"].get("elsewhere").is_none());
        assert_eq!(doc["elsewhere"], "card");

        // Different pins show in every place at once.
        d.card_select("chat").unwrap();
        let doc = d.doc();
        assert!(doc.get("elsewhere").is_none() && doc["card"].get("elsewhere").is_none());
    }

    /// A rest on the edge of a hidden dock, until its reveal falls due.
    fn hover_reveal(d: &mut Dock, t0: Instant) {
        d.hide();
        d.hover(Part::Edge, true, "DP-1", false, t0);
        d.tick(t0 + REVEAL);
        assert_eq!(d.doc()["mode"], "extended", "the reveal reopens the card");
    }

    /// W74 (A, the default): a hover reveal of the edge counts as opening it, so it takes the page the bar card shows.
    #[test]
    fn a_hover_reveal_takes_the_page_by_default() {
        let t0 = Instant::now();
        let mut d = dock(&[]);
        d.set_host(HostState::Ready);
        d.open("mail", Some("DP-1")).unwrap();
        d.hide();
        d.card_place(Some(card_place()), true);
        assert!(
            d.doc()["card"].get("elsewhere").is_none(),
            "the card shows mail"
        );
        hover_reveal(&mut d, t0);
        let doc = d.doc();
        assert_eq!(doc["card"]["elsewhere"], "edge", "the reveal took the page");
        assert!(doc.get("elsewhere").is_none());
    }

    /// W74 (B, `hover_takes_page = false`): only a deliberate open takes the page; a hover-revealed edge ranks below every
    /// open place — also after an earlier deliberate open of the edge — and shows the page when no other place does.
    #[test]
    fn with_hover_takes_page_off_a_hover_reveal_takes_nothing() {
        let t0 = Instant::now();
        let mut d = dock(&[("hover_takes_page", json!(false))]);
        d.set_host(HostState::Ready);

        // No other place: the hover-revealed edge shows the page.
        d.open("mail", Some("DP-1")).unwrap();
        hover_reveal(&mut d, t0);
        assert!(d.doc().get("elsewhere").is_none(), "alone, it shows it");

        // The card opens on mail: it shows the page. A hover reveal leaves it there, the edge says where.
        d.hide();
        d.card_place(Some(card_place()), true);
        hover_reveal(&mut d, t0);
        let doc = d.doc();
        assert_eq!(doc["elsewhere"], "card", "the edge says it is in the card");
        assert!(doc["card"].get("elsewhere").is_none(), "the card keeps it");

        // An old stamp does not carry over: the edge opened on purpose (it takes the page), hidden, then hover-revealed.
        d.open("mail", Some("DP-1")).unwrap();
        assert_eq!(
            d.doc()["card"]["elsewhere"],
            "edge",
            "a deliberate open takes it"
        );
        hover_reveal(&mut d, t0);
        assert_eq!(
            d.doc()["elsewhere"],
            "card",
            "the hover reveal after a deliberate open steals nothing"
        );

        // "Show here" at the edge (webdock.open) takes it.
        d.open("mail", Some("DP-1")).unwrap();
        assert_eq!(d.doc()["card"]["elsewhere"], "edge");
        // The dock's key (webdock.toggle) is deliberate too.
        d.toggle(None);
        d.card_select("mail").unwrap();
        assert_eq!(
            d.doc()["card"].get("elsewhere"),
            None,
            "hidden: the card has it"
        );
        d.toggle(None);
        assert_eq!(d.doc()["card"]["elsewhere"], "edge", "the key takes it");
        // A click on a pin of the strip too: another pin, then mail again.
        d.hide();
        d.card_select("mail").unwrap();
        hover_reveal(&mut d, t0);
        assert_eq!(d.doc()["elsewhere"], "card");
        d.select("chat", None).unwrap();
        d.select("mail", None).unwrap();
        assert_eq!(
            d.doc()["card"]["elsewhere"],
            "edge",
            "a click on the pin takes it"
        );

        // The card closes while a hover-revealed edge is open: the page comes to the edge.
        d.hide();
        d.card_select("mail").unwrap();
        hover_reveal(&mut d, t0);
        assert_eq!(d.doc()["elsewhere"], "card");
        d.card_place(None, false);
        assert!(
            d.doc().get("elsewhere").is_none(),
            "the edge is the only place left"
        );
    }

    /// W74: the setting carries its provenance like every mod setting.
    #[test]
    fn a_forced_hover_takes_page_is_published_with_its_source() {
        let mut forced = BTreeMap::new();
        forced.insert("hover_takes_page".to_string(), "nix".to_string());
        let d = dock(&[("hover_takes_page", json!(false))]).with_forced(forced);
        assert_eq!(d.doc()["forced"]["hover_takes_page"], "nix");
    }

    /// B117: the document names `hover_takes_page` only while it is off.
    #[test]
    fn hover_takes_page_is_published_only_while_off() {
        assert!(dock(&[]).doc().get("hover_takes_page").is_none());
        assert_eq!(
            dock(&[("hover_takes_page", json!(false))]).doc()["hover_takes_page"],
            false
        );
    }

    /// W73, W74: the bar card's size is published unless it is the default (`dock`, the edge card's size).
    #[test]
    fn the_card_size_is_published_unless_it_is_the_dock() {
        assert!(dock(&[]).doc().get("card_size").is_none());
        assert!(
            dock(&[("card_size", json!("dock"))])
                .doc()
                .get("card_size")
                .is_none()
        );
        for size in ["phone", "tablet", "wide"] {
            assert_eq!(dock(&[("card_size", json!(size))]).doc()["card_size"], size);
        }
    }

    /// W74: the card's size key steps dock → phone → tablet → wide → dock, takes a named size, refuses a bad one, and is
    /// refused while the configuration forces the setting.
    #[test]
    fn the_size_key_steps_through_the_sizes_and_is_inert_when_forced() {
        assert_eq!(card_size_step(None, None, false), Ok("phone"));
        assert_eq!(card_size_step(Some("dock"), None, false), Ok("phone"));
        assert_eq!(card_size_step(Some("phone"), None, false), Ok("tablet"));
        assert_eq!(card_size_step(Some("tablet"), None, false), Ok("wide"));
        assert_eq!(card_size_step(Some("wide"), None, false), Ok("dock"));
        assert_eq!(
            card_size_step(Some("nonsense"), None, false),
            Ok("phone"),
            "an unknown value counts as the default"
        );
        assert_eq!(
            card_size_step(Some("phone"), Some("wide"), false),
            Ok("wide")
        );
        assert_eq!(
            card_size_step(None, Some("huge"), false),
            Err(DockError::CardSize)
        );
        assert_eq!(
            card_size_step(Some("phone"), None, true),
            Err(DockError::Forced)
        );
        assert_eq!(DockError::Forced.key(), "webdock.error.forced");
    }

    /// I495 (session 30): the page's title rides with its sound into the pin's doc, only while it sounds; the bar
    /// module's views are named in the doc only while on.
    #[test]
    fn a_sounding_page_names_its_title_and_the_bar_views_follow_their_settings() {
        let now = Instant::now();
        let mut d = dock(&[]);
        assert!(d.doc().get("bar_site").is_none() && d.doc().get("bar_playing").is_none());
        d.audible("mail", true, now).unwrap();
        d.page_title("mail", Some("Song — Artist".into()));
        let pin = |d: &Dock| d.doc()["pins"].as_array().unwrap()[0].clone();
        assert_eq!(pin(&d)["page_title"], "Song — Artist");
        d.audible("mail", false, now).unwrap();
        assert!(pin(&d).get("page_title").is_none(), "silent: no title");
        d.page_title("weather", Some("x".into()));
        d.page_title("nobody", Some("x".into()));
        let d = dock(&[("bar_site", json!(true)), ("bar_playing", json!(true))]);
        assert_eq!(d.doc()["bar_site"], true);
        assert_eq!(d.doc()["bar_playing"], true);
    }

    /// I495: an icon the host saved in an earlier run shows before the page reports one again.
    #[test]
    fn a_saved_icon_shows_before_the_page_loads() {
        let dir =
            std::env::temp_dir().join(format!("kurashi-webdock-icons-{}", std::process::id()));
        std::fs::create_dir_all(&dir).unwrap();
        std::fs::write(dir.join("mail.png"), b"png").unwrap();
        let d = Dock::new(
            &settings_with(rows(), &[]),
            PathBuf::from("/d/profiles"),
            dir.clone(),
        );
        let pins = d.doc()["pins"].clone();
        assert_eq!(pins[0]["icon"], json!(file_url(&dir.join("mail.png"))));
        assert!(pins[1].get("icon").is_none(), "no file, no icon");
        assert_eq!(icon_name("a b/ç"), "a_b__");
        std::fs::remove_dir_all(&dir).unwrap();
    }

    // ---- W76 (docs/ux/webdock.md "Round three") ----

    #[test]
    fn the_address_field_loads_addresses_and_searches_everything_else() {
        let e = DEFAULT_SEARCH;
        assert_eq!(
            resolve("https://a.example/x", e).unwrap(),
            "https://a.example/x"
        );
        assert_eq!(
            resolve("  file:///tmp/p.html ", e).unwrap(),
            "file:///tmp/p.html"
        );
        assert_eq!(resolve("example.com", e).unwrap(), "https://example.com");
        assert_eq!(
            resolve("www.example.org/a?b=1", e).unwrap(),
            "https://www.example.org/a?b=1"
        );
        assert_eq!(
            resolve("localhost:8080/x", e).unwrap(),
            "http://localhost:8080/x"
        );
        assert_eq!(resolve("10.0.0.2", e).unwrap(), "http://10.0.0.2");
        assert_eq!(resolve("/tmp/p.html", e).unwrap(), "file:///tmp/p.html");
        assert_eq!(
            resolve("rust borrow checker", e).unwrap(),
            "https://duckduckgo.com/?q=rust+borrow+checker"
        );
        // Never loaded: another scheme is words.
        assert_eq!(
            resolve("javascript:alert(1)", e).unwrap(),
            "https://duckduckgo.com/?q=javascript%3Aalert%281%29"
        );
        assert!(
            resolve("data:text/html,x", e)
                .unwrap()
                .starts_with("https://duckduckgo.com/?q=data%3A")
        );
        assert!(
            resolve("example", e)
                .unwrap()
                .starts_with("https://duckduckgo.com/"),
            "no dot: a word"
        );
        assert!(
            resolve("a..b.com", e)
                .unwrap()
                .starts_with("https://duckduckgo.com/")
        );
        assert!(resolve("   ", e).is_none());
        assert_eq!(
            resolve("x y", "https://s.example/search?q=").unwrap(),
            "https://s.example/search?q=x+y"
        );
    }

    #[test]
    fn the_search_setting_must_be_a_web_address_else_duckduckgo() {
        let d = dock(&[("search", json!("javascript:{q}"))]);
        assert_eq!(d.config.search, DEFAULT_SEARCH);
        let d = dock(&[("search", json!("https://s.example/?q={q}"))]);
        assert_eq!(d.config.search, "https://s.example/?q={q}");
    }

    #[test]
    fn plus_opens_a_temporary_page_the_strip_does_not_list_and_its_place_drops() {
        let mut d = dock(&[]);
        d.set_host(HostState::Ready);
        let id = d.browse(Spot::Edge, Some("DP-1"));
        let doc = d.doc();
        assert_eq!(doc["mode"], "extended");
        assert_eq!(doc["shown"], json!(id));
        let p = pin_of(&doc, &id);
        assert_eq!(p["temporary"], true);
        assert_eq!(p["target"], "");
        assert_eq!(p["profile"], BROWSE_PROFILE);
        assert!(doc["keep"].as_array().unwrap().contains(&json!(id)));
        // Enter: an address; the temporary page's address follows, a pin's stays.
        assert_eq!(d.go(&id, "example.com").unwrap(), "https://example.com");
        assert_eq!(pin_of(&d.doc(), &id)["target"], "https://example.com");
        assert_eq!(
            d.go("mail", "other.example").unwrap(),
            "https://other.example"
        );
        assert_eq!(
            pin_of(&d.doc(), "mail")["target"],
            "https://mail.example.org/"
        );
        assert_eq!(d.go("weather", "x"), Err(DockError::NotASite));
        // A hover hide keeps it (shown stays); the card's close drops it.
        d.hide();
        d.sweep();
        assert!(d.temp_of(&id).is_some(), "a hide keeps the page");
        d.toggle(None);
        d.collapse();
        d.sweep();
        assert!(d.temp_of(&id).is_none(), "closing drops it");
        assert!(
            d.doc()["pins"]
                .as_array()
                .unwrap()
                .iter()
                .all(|p| p["id"] != json!(id))
        );
        // Another pin picked in the bar card drops its "+" page; a second "+" replaces the first.
        d.card_place(Some(card_place()), true);
        let c1 = d.browse(Spot::Card, None);
        let c2 = d.browse(Spot::Card, None);
        assert_ne!(c1, c2);
        assert!(d.temp_of(&c1).is_none() && d.temp_of(&c2).is_some());
        d.card_select("chat").unwrap();
        d.sweep();
        assert!(d.temp_of(&c2).is_none());
        // Esc in the empty field drops it; a pin cannot be dropped that way.
        let s = d.browse(Spot::Sidebar, None);
        d.drop_temp(&s).unwrap();
        assert!(d.temp_of(&s).is_none());
        assert_eq!(d.drop_temp("mail"), Err(DockError::UnknownPin));
        // The shell saw the card close (`webdock.card {on: false, closed: true}`): the same.
        let c4 = d.browse(Spot::Card, None);
        d.card_place(None, false);
        assert!(d.temp_of(&c4).is_some(), "a move keeps it");
        d.card_closed();
        assert!(d.temp_of(&c4).is_none(), "a close drops it");
        d.card_place(Some(card_place()), false);
        // A "+" page the card moved to the edge ("Show at the edge", "Keep open at the edge") survives the card's close.
        let c5 = d.browse(Spot::Card, None);
        d.open(&c5, Some("DP-1")).unwrap();
        d.card_closed();
        assert!(d.temp_of(&c5).is_some(), "the edge shows it now");
        assert_eq!(d.doc()["shown"], json!(c5));
        d.collapse();
        d.sweep();
        assert!(d.temp_of(&c5).is_none(), "the edge closed: it goes");
        // The bar card's Esc (card_close) drops its "+" page and shows the first pin again.
        let c3 = d.browse(Spot::Card, None);
        d.card_close();
        assert!(d.temp_of(&c3).is_none());
        assert_eq!(d.doc()["card"]["pin"], "mail");
    }

    #[test]
    fn a_settings_reload_keeps_the_temporary_pages() {
        let mut d = dock(&[]);
        d.set_host(HostState::Ready);
        let id = d.browse(Spot::Edge, None);
        d.apply_settings(
            &settings_with(rows(), &[("width", json!(500))]),
            Instant::now(),
        );
        assert!(d.temp_of(&id).is_some());
        assert_eq!(d.doc()["shown"], json!(id));
    }

    #[test]
    fn pin_takes_the_temporary_page_with_its_profile_and_no_reload() {
        let mut d = dock(&[]);
        d.set_host(HostState::Ready);
        let id = d.browse(Spot::Edge, Some("DP-1"));
        d.go(&id, "https://news.example/a").unwrap();
        d.loaded(&id, None).unwrap();
        let rows = rows_list(rows());
        let (written, new) = add_row_with(
            &rows,
            "https://news.example/a",
            Some("News"),
            &d.temp_ids(),
            d.temp_of(&id).map(|t| t.profile.as_str()),
        )
        .unwrap();
        assert_eq!(new, "news-example");
        assert_eq!(written[3]["profile"], BROWSE_PROFILE);
        d.apply_settings(&settings_with(Value::Array(written), &[]), Instant::now());
        d.adopt(&id, &new);
        let doc = d.doc();
        assert_eq!(doc["shown"], json!(new));
        let p = pin_of(&doc, &new);
        assert_eq!(p["was"], json!(id), "the host renames the page");
        assert_eq!(p["loaded"], true, "the page passed over loaded");
        assert!(p.get("temporary").is_none());
        assert!(d.temp_of(&id).is_none());
        assert!(doc["keep"].as_array().unwrap().contains(&json!(new)));
        assert!(!doc["keep"].as_array().unwrap().contains(&json!(id)));
    }

    #[test]
    fn a_new_pin_never_takes_a_temporary_pages_id() {
        let (_, id) =
            add_row_with(&[], "https://browse-1/", None, &["browse-1".into()], None).unwrap();
        assert_eq!(id, "browse-1-2");
    }

    #[test]
    fn unpin_but_keep_open_keeps_the_page_until_the_rules_unload_it_and_undo_brings_the_pin_back() {
        let mut d = dock(&[]);
        d.set_host(HostState::Ready);
        d.open("mail", Some("DP-1")).unwrap();
        d.loaded("mail", None).unwrap();
        d.unpin_keep("mail").unwrap();
        // The row goes (the caller writes it); the page stays a temporary page of the same id.
        let without: Vec<Value> = rows().as_array().unwrap()[1..].to_vec();
        d.apply_settings(
            &settings_with(Value::Array(without.clone()), &[]),
            Instant::now(),
        );
        d.sweep();
        let doc = d.doc();
        assert_eq!(pin_of(&doc, "mail")["temporary"], true);
        assert_eq!(pin_of(&doc, "mail")["loaded"], true);
        assert_eq!(doc["shown"], "mail");
        // Undo: the row is back, the page is the pin's again (no new page).
        d.apply_settings(&settings_with(rows(), &[]), Instant::now());
        assert!(pin_of(&d.doc(), "mail").get("temporary").is_none());
        assert!(d.temp_of("mail").is_none());
        // Unpinned again, then shown pins push it past the cap: the rules unload it and it goes.
        d.unpin_keep("mail").unwrap();
        d.apply_settings(
            &settings_with(Value::Array(without), &[("max_loaded", json!(1))]),
            Instant::now(),
        );
        d.open("chat", None).unwrap();
        d.sweep();
        assert!(
            d.temp_of("mail").is_none(),
            "past the cap the kept page goes"
        );
        assert_eq!(d.unpin_keep("weather"), Err(DockError::NotASite));
        // A refused write gives the page back to its pin.
        d.open("chat", None).unwrap();
        d.unpin_keep("chat").unwrap();
        d.unpin_undo("chat");
        assert!(d.temp_of("chat").is_none());
        assert!(pin_of(&d.doc(), "chat").get("temporary").is_none());
    }

    #[test]
    fn the_menus_reload_and_the_pages_address() {
        let mut d = dock(&[]);
        d.set_host(HostState::Ready);
        assert_eq!(
            d.reload("mail"),
            Err(DockError::Argument),
            "not loaded: nothing to reload"
        );
        d.loaded("mail", None).unwrap();
        d.reload("mail").unwrap();
        d.reload("mail").unwrap();
        assert_eq!(pin_of(&d.doc(), "mail")["reload"], 2);
        d.page_url("mail", "https://mail.example.org/#inbox")
            .unwrap();
        assert!(
            pin_of(&d.doc(), "mail").get("at").is_none(),
            "home, the fragment aside"
        );
        d.page_url("mail", "https://mail.example.org/thread/7")
            .unwrap();
        assert_eq!(
            pin_of(&d.doc(), "mail")["at"],
            "https://mail.example.org/thread/7"
        );
        assert_eq!(
            d.at("mail").as_deref(),
            Some("https://mail.example.org/thread/7")
        );
        d.unloaded("mail").unwrap();
        assert!(d.at("mail").is_none(), "unloaded: it opens at home again");
        assert_eq!(d.page_url("weather", "x"), Err(DockError::UnknownPin));
    }

    #[test]
    fn the_card_sizes_are_rows_per_output_and_published_while_any() {
        assert!(dock(&[]).doc().get("sizes").is_none());
        let rows = sizes_rows(&[], "DP-1", Some((500, 900))).unwrap();
        let rows = sizes_rows(&rows_list(Value::Array(rows)), "HDMI-1", Some((400, 400))).unwrap();
        let rows = sizes_rows(&rows_list(Value::Array(rows)), "DP-1", Some((520, 880))).unwrap();
        assert_eq!(rows.len(), 2);
        let d = dock(&[("sizes", Value::Array(rows.clone()))]);
        assert_eq!(
            d.doc()["sizes"]["DP-1"],
            json!({"width": 520, "height": 880})
        );
        assert_eq!(
            d.doc()["sizes"]["HDMI-1"],
            json!({"width": 400, "height": 400})
        );
        let reset = sizes_rows(&rows_list(Value::Array(rows)), "DP-1", None).unwrap();
        assert_eq!(reset.len(), 1);
        assert_eq!(
            sizes_rows(&[], "DP-1", Some((100, 900))),
            Err(DockError::Argument)
        );
        assert_eq!(
            sizes_rows(&[], "", Some((500, 900))),
            Err(DockError::Argument)
        );
        // A row out of range (edited by hand) is not read.
        let d = dock(&[(
            "sizes",
            json!([{"output": "DP-1", "width": 10, "height": 900}]),
        )]);
        assert!(d.doc().get("sizes").is_none());
    }

    // ---- W78: Local mode ----

    #[test]
    fn content_step_flips_takes_a_named_mode_and_is_refused_when_forced() {
        assert_eq!(content_step(None, None, false), Ok("local"));
        assert_eq!(content_step(Some("online"), None, false), Ok("local"));
        assert_eq!(content_step(Some("local"), None, false), Ok("online"));
        assert_eq!(
            content_step(Some("bogus"), None, false),
            Ok("local"),
            "unknown counts as online"
        );
        assert_eq!(
            content_step(Some("local"), Some("local"), false),
            Ok("local")
        );
        assert_eq!(
            content_step(None, Some("web"), false),
            Err(DockError::Content)
        );
        assert_eq!(
            content_step(None, Some("local"), true),
            Err(DockError::Forced)
        );
    }

    #[test]
    fn the_strip_lists_the_sites_online_and_the_views_local_never_a_temporary_page() {
        let mut d = dock(&[]);
        assert_eq!(d.strip(), ["mail", "chat"]);
        let doc = d.doc();
        assert!(doc.get("content").is_none(), "online is the default");
        assert_eq!(
            doc["strip"],
            json!(["mail", "chat"]),
            "a view pinned: the strip names the sites"
        );
        let temp = d.browse(Spot::Edge, Some("DP-1"));
        assert!(
            !d.strip().contains(&temp),
            "a temporary page is never listed"
        );
        let mut d = dock(&[("content", json!("local"))]);
        assert_eq!(d.doc()["strip"], json!(["weather"]));
        assert_eq!(d.doc()["content"], "local");
        let temp = d.browse(Spot::Edge, Some("DP-1"));
        assert_eq!(
            d.doc()["strip"],
            json!(["weather"]),
            "{temp} is not listed in Local either"
        );
        assert_eq!(
            dock(&[("content", json!("x"))]).doc()["strip"],
            json!(["mail", "chat"]),
            "unknown: online"
        );
    }

    #[test]
    fn the_pointer_on_the_sidebars_page_is_named_only_while_the_page_is_placed() {
        let mut d = dock(&[]);
        d.side_page(true);
        assert!(
            d.doc().get("sidebar").is_none(),
            "no place: nothing to hold"
        );
        let place = Place {
            output: "DP-1".into(),
            side: Side::Right,
            inset: 8,
            top: 40,
            width: 360,
            height: 800,
        };
        d.place(Some(place), true);
        d.side_page(true);
        assert_eq!(d.doc()["sidebar"]["hover"], true);
        d.side_page(false);
        assert!(d.doc()["sidebar"].get("hover").is_none());
        d.side_page(true);
        d.place(None, false);
        assert!(
            d.doc()
                .get("sidebar")
                .and_then(|s| s.get("hover"))
                .is_none(),
            "the place going takes the hover with it"
        );
    }

    #[test]
    fn switching_puts_away_a_card_of_the_other_kind_and_keeps_one_of_its_own() {
        let mut d = dock(&[]);
        d.set_host(HostState::Ready);
        d.open("mail", Some("DP-1")).unwrap();
        let local = settings_with(rows(), &[("content", json!("local"))]);
        // the settings alone (the switch, an undo, Settings, the file) put a site's card away in Local
        d.apply_settings(&local, Instant::now());
        assert_eq!(
            d.doc()["mode"],
            "compact",
            "a site's card goes when the strip lists views"
        );
        d.open("weather", Some("DP-1")).unwrap();
        assert!(!d.content_changed(), "a view's card stays in Local");
        assert_eq!(d.doc()["shown"], "weather");
        d.apply_settings(&settings_with(rows(), &[]), Instant::now());
        assert_eq!(
            d.doc()["mode"],
            "compact",
            "Online lists the sites (session 32): a view's card goes"
        );
        d.apply_settings(&local, Instant::now());
        // a pin of the other kind opened by name still shows: the mode filters the strip, not what is shown
        d.open("chat", Some("DP-1")).unwrap();
        assert_eq!(d.doc()["shown"], "chat");
        assert!(
            d.content_changed(),
            "content_changed puts it away when asked"
        );
        d.open("chat", Some("DP-1")).unwrap();
        d.apply_settings(&local, Instant::now());
        assert_eq!(
            d.doc()["shown"],
            "chat",
            "a write that does not change the mode keeps a site opened by name"
        );
    }

    #[test]
    fn add_takes_a_view_target_named_by_its_view() {
        let (out, id) = add_row(&[], "mod:notes:notes", Some("Notes")).unwrap();
        assert_eq!(id, "notes");
        assert_eq!(out[0]["target"], "mod:notes:notes");
        assert_eq!(out[0]["title"], "Notes");
        let rows = rows_list(rows());
        let (out, id) = add_row(&rows, "mod:weather:weather", None).unwrap();
        assert_eq!(id, "weather-2", "a taken id gets a suffix");
        assert_eq!(
            out.last().unwrap()["title"],
            "weather-2",
            "no title: the id"
        );
        assert!(
            parse_pin(out.last().unwrap().as_object().unwrap())
                .is_some_and(|p| p.kind == Kind::View)
        );
    }
}

/// One launcher row of the dock's (session 33, K150).
#[derive(Debug, Clone, PartialEq)]
pub enum LaunchRow {
    Pin {
        id: String,
        title: String,
        target: String,
    },
    Address {
        url: String,
    },
    Search {
        words: String,
        url: String,
    },
}
