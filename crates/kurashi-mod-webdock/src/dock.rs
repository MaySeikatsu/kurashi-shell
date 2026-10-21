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
}

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
    /// A reveal opens the card of the shown pin again (`reopen_last`).
    pub reopen_last: bool,
    /// The dock stays open: nothing hides it (`pinned`).
    pub pinned: bool,
    /// A pinned strip reserves its width on the output (`reserve`; the card always overlays).
    pub reserve: bool,
    pub indicator: bool,
    pub new_tabs: NewTabs,
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
            reopen_last: flag("reopen_last", true),
            pinned: flag("pinned", false),
            reserve: flag("reserve", false),
            indicator: flag("indicator", true),
            new_tabs: match settings.get("new_tabs").as_ref().and_then(Value::as_str) {
                Some("browser") => NewTabs::Browser,
                _ => NewTabs::Dock,
            },
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

pub struct Dock {
    /// The pin the sidebar panel shows (W30), kept while the sidebar is closed.
    side_pin: Option<String>,
    /// The sidebar panel's page area while the panel is at rest in an open sidebar; `None` otherwise.
    place: Option<Place>,
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
}

impl Dock {
    /// The dock as the settings say it is now, hidden, with the host off.
    pub fn new(settings: &Settings, profiles: PathBuf, icons: PathBuf) -> Self {
        let mut dock = Self {
            side_pin: None,
            place: None,
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
        };
        dock.apply_settings(settings, Instant::now());
        dock
    }

    /// Takes the settings in effect: pins, and the values the dock reads. A pin that is gone takes its state with it.
    /// A changed `hover` or `pinned` brings the pending deadline in line with the state (K40).
    pub fn apply_settings(&mut self, settings: &Settings, now: Instant) {
        self.config = Config::read(settings);
        self.pins = pins_of(&rows_of(settings));
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
        self.sanitize();
        self.settle(now);
    }

    /// `webdock.sidebar`: the sidebar panel's page area at rest (`Some`), or the panel moved, hid or went (`None`).
    /// An open sidebar with no pin of its own shows the first pin. True when it shows a site (the host starts).
    pub fn place(&mut self, place: Option<Place>) -> bool {
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
            self.side_pin = self.pins.first().map(|p| p.id.clone());
        }
    }

    /// The site the open sidebar shows, if it shows one.
    fn side_web(&self) -> Option<String> {
        self.place.as_ref()?;
        self.side_pin.clone().filter(|id| self.is_web(id))
    }

    /// The host's state as the daemon reports it. Without a connected host nothing is loaded or audible (Shōjiki).
    /// A host that crashed takes its card with it: the card's leave and the focus loss never come, so the dock
    /// forgets them (K40), or it would stay open for good.
    pub fn set_host(&mut self, state: HostState) {
        if state != HostState::Ready {
            for st in self.states.values_mut() {
                st.loaded = false;
                st.audible = false;
            }
        }
        if matches!(state, HostState::Failed { .. } | HostState::Missing) && state != self.host {
            self.inside.card = false;
            self.engaged = false;
            self.settle(Instant::now());
        }
        self.host = state;
    }

    /// The card opens on `pin`, extended (`webdock.open`). True when the pin is a site, which starts the host.
    pub fn open(&mut self, pin: &str, output: Option<&str>) -> Result<bool, DockError> {
        let (id, kind) = self.find(pin)?;
        self.mode = Mode::Extended;
        self.shown = Some(id.clone());
        if let Some(output) = output {
            self.output = Some(output.into());
        }
        if kind == Kind::Web {
            self.touch(&id);
        }
        self.sanitize();
        Ok(kind == Kind::Web)
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
    pub fn unloaded(&mut self, pin: &str) -> Result<(), DockError> {
        self.web_pin(pin)?;
        let st = self.states.entry(pin.to_string()).or_default();
        st.loaded = false;
        st.audible = false;
        Ok(())
    }

    /// `webdock.host.audible`: the site plays sound. An audible pin is kept loaded, whatever the cap.
    pub fn audible(&mut self, pin: &str, on: bool) -> Result<(), DockError> {
        self.web_pin(pin)?;
        self.states.entry(pin.to_string()).or_default().audible = on;
        Ok(())
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
        st.error = Some("webdock.error.crashed".into());
        Ok(())
    }

    /// The host runs now, and nothing web is shown or audible, so the idle clock runs (MODS.md "Lifecycle").
    pub fn is_idle(&self) -> bool {
        self.host.is_running() && !self.web_visible() && !self.any_audible()
    }

    /// How long the host may stay idle before it stops; `None` = never.
    pub fn unload_after(&self) -> Option<Duration> {
        (self.config.unload_after > 0)
            .then(|| Duration::from_secs(u64::from(self.config.unload_after) * 60))
    }

    /// The pins the host keeps loaded (MODS.md): the most recently shown sites, up to `max_loaded`, then any
    /// audible site beyond the cap. Nothing while the host does not run.
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
        // Beyond the cap: an audible site, and a site on screen (the edge card's and the sidebar's at once, W30).
        let shown = self.edge_web();
        let side = self.side_web();
        keep.extend(
            rest.iter()
                .filter(|id| {
                    self.is_audible(id)
                        || shown.as_deref() == Some(id.as_str())
                        || side.as_deref() == Some(id.as_str())
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
            doc["sidebar"] = side;
        }
        doc
    }

    fn pin_doc(&self, p: &PinSpec, views: &BTreeMap<String, View>) -> Value {
        let kind = match p.kind {
            Kind::Web => "web",
            Kind::View => "view",
        };
        let mut out = json!({"id": p.id, "kind": kind, "title": p.title, "target": p.target});
        if p.kind == Kind::Web {
            let view = views
                .get(&p.profile)
                .copied()
                .unwrap_or(self.config.default_view);
            let st = self.states.get(&p.id).cloned().unwrap_or_default();
            out["view"] = json!(view.name());
            out["profile"] = json!(p.profile);
            out["loaded"] = json!(st.loaded);
            if let Some(icon) = st.icon {
                out["icon"] = json!(icon);
            }
            if st.audible {
                out["audible"] = json!(true);
            }
            if !st.blocked.is_empty() {
                out["blocked"] = json!(st.blocked);
            }
            if let Some(error) = st.error {
                out["error"] = json!(error);
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

    /// A site is on screen: the edge card's, or the open sidebar's (W30).
    fn web_visible(&self) -> bool {
        self.edge_web().is_some() || self.side_web().is_some()
    }

    /// The site the edge card shows, if it shows one.
    fn edge_web(&self) -> Option<String> {
        (self.mode == Mode::Extended)
            .then(|| self.shown.clone())
            .flatten()
            .filter(|s| self.is_web(s))
    }

    fn any_audible(&self) -> bool {
        self.states.values().any(|st| st.audible)
    }

    fn is_audible(&self, id: &str) -> bool {
        self.states.get(id).is_some_and(|st| st.audible)
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
    match settings.get("pins") {
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
pub fn add_row(
    rows: &[Map<String, Value>],
    url: &str,
    title: Option<&str>,
) -> Result<(Vec<Value>, String), DockError> {
    if !web_address(url) {
        return Err(DockError::Address);
    }
    let taken: Vec<&str> = rows
        .iter()
        .filter_map(|r| r.get("id").and_then(Value::as_str))
        .collect();
    let id = unique_id(&slug_of(id_text(url)), &taken);
    let name = title
        .filter(|t| !t.is_empty())
        .map_or_else(|| host_of(url).unwrap_or(&id).to_string(), str::to_string);
    let mut out = rows.to_vec();
    out.push(Map::from_iter([
        ("id".to_string(), json!(id)),
        ("title".to_string(), json!(name)),
        ("target".to_string(), json!(url)),
    ]));
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
    })
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
        assert_eq!(
            add_row(&[], "mod:weather:weather", None),
            Err(DockError::Address)
        );
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
        d.audible("chat", true).unwrap();
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
            d.place(Some(place_left())),
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
        assert!(!d.place(None));
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
        assert!(d.place(Some(place_left())));
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
        d.place(Some(place_left()));
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
        d.place(Some(place_left()));
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
}
