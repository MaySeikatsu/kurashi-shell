//! The dock's state and its document (K38, MODS.md "Web dock"): the pins the settings name, the mode and the shown
//! pin, the host's reports and the host's lifecycle as far as the state decides it. Pure: `lib.rs` feeds it actions,
//! settings and host states, and publishes [`Dock::doc`]. Everything here is what the daemon owns (rule 1).

use std::collections::BTreeMap;
use std::path::{Component, Path, PathBuf};
use std::time::Duration;

use kurashi_mod_api::{HostState, Settings};
use serde_json::{Map, Value, json};

/// The strip's width until the shell's strip exists (MODS.md: `geometry.strip`).
pub const STRIP_PX: u32 = 56;
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
    /// The pin's row in the settings, so that a write keeps every field of every row.
    row: usize,
}

/// Why an action or a host report is refused (its i18n key is in [`DockError::key`]).
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum DockError {
    UnknownPin,
    Size,
    View,
    Permission,
    Icon,
    /// A required argument is missing or of the wrong type.
    Argument,
}

impl DockError {
    pub fn key(self) -> &'static str {
        match self {
            Self::UnknownPin => "webdock.error.unknown_pin",
            Self::Size => "webdock.error.size",
            Self::View => "webdock.error.view",
            Self::Permission => "webdock.error.permission",
            Self::Icon => "webdock.error.icon",
            Self::Argument => "webdock.error.argument",
        }
    }
}

/// The settings the dock reads (MODS.md "Web dock": `default_view`, `width`, `large`, `edge`, `unload_after`,
/// `max_loaded`), with the manifest's defaults for any the feed does not carry.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Config {
    pub width: u32,
    pub large: u32,
    pub edge: String,
    pub default_view: View,
    /// Minutes the host runs unused before it stops; 0 = never.
    pub unload_after: u32,
    pub max_loaded: u32,
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
        Self {
            width: number("width", 412),
            large: number("large", 90),
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

pub struct Dock {
    /// Every object row of the `pins` setting, in order; a `view` write edits them and keeps the rest.
    rows: Vec<Map<String, Value>>,
    pins: Vec<PinSpec>,
    states: BTreeMap<String, PinState>,
    /// Web pins by the time they were last shown, most recent first.
    recent: Vec<String>,
    config: Config,
    mode: Mode,
    shown: Option<String>,
    size: Size,
    output: Option<String>,
    host: HostState,
    profiles: PathBuf,
    icons: PathBuf,
}

impl Dock {
    /// The dock as the settings say it is now, hidden, with the host off.
    pub fn new(settings: &Settings, profiles: PathBuf, icons: PathBuf) -> Self {
        let mut dock = Self {
            rows: Vec::new(),
            pins: Vec::new(),
            states: BTreeMap::new(),
            recent: Vec::new(),
            config: Config::read(settings),
            mode: Mode::Hidden,
            shown: None,
            size: Size::Phone,
            output: None,
            host: HostState::Off,
            profiles,
            icons,
        };
        dock.apply_settings(settings);
        dock
    }

    /// Takes the settings in effect: pins, and the values the dock reads. A pin that is gone takes its state with it.
    pub fn apply_settings(&mut self, settings: &Settings) {
        self.config = Config::read(settings);
        self.rows = match settings.get("pins") {
            Some(Value::Array(items)) => items
                .into_iter()
                .filter_map(|v| match v {
                    Value::Object(m) => Some(m),
                    _ => None,
                })
                .collect(),
            _ => Vec::new(),
        };
        self.pins.clear();
        for (index, row) in self.rows.iter().enumerate() {
            if let Some(pin) = parse_pin(row, index)
                && !self.pins.iter().any(|p| p.id == pin.id)
            {
                self.pins.push(pin);
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
    }

    /// The host's state as the daemon reports it. Without a connected host nothing is loaded or audible (Shōjiki).
    pub fn set_host(&mut self, state: HostState) {
        if state != HostState::Ready {
            for st in self.states.values_mut() {
                st.loaded = false;
                st.audible = false;
            }
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
        Ok(kind == Kind::Web)
    }

    /// The strip only (`webdock.collapse`): the card closes, the pin stays loaded.
    pub fn collapse(&mut self) {
        self.mode = Mode::Compact;
        self.shown = None;
    }

    /// Out of sight, the shown pin kept (`webdock.hide`).
    pub fn hide(&mut self) {
        self.mode = Mode::Hidden;
    }

    /// `webdock.toggle`: from hidden, the shown pin's card or the strip; otherwise hidden. True when the card
    /// opens on a site, which starts the host.
    pub fn toggle(&mut self, output: Option<&str>) -> bool {
        if let Some(output) = output {
            self.output = Some(output.into());
        }
        if self.mode != Mode::Hidden {
            self.mode = Mode::Hidden;
            return false;
        }
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

    /// The `pins` rows after `webdock.view` on `pin`: every pin of its profile gets `view`, the rest is kept.
    /// The dock does not change: the settings feed brings the new rows back once the write is in effect.
    pub fn view_rows(&self, pin: &str, view: View) -> Result<Vec<Value>, DockError> {
        let target = self.pin(pin)?;
        if target.kind != Kind::Web {
            return Err(DockError::View);
        }
        let profile = target.profile.clone();
        let mut rows = self.rows.clone();
        for p in self
            .pins
            .iter()
            .filter(|p| p.kind == Kind::Web && p.profile == profile)
        {
            rows[p.row].insert("view".into(), json!(view.name()));
        }
        Ok(rows.into_iter().map(Value::Object).collect())
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
        keep.extend(rest.iter().filter(|id| self.is_audible(id)).cloned());
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
            "edge": self.config.edge,
            "geometry": {
                "strip": STRIP_PX,
                "width": self.config.width,
                "large": self.config.large,
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

    fn web_visible(&self) -> bool {
        self.mode == Mode::Extended && self.shown.as_deref().is_some_and(|s| self.is_web(s))
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

/// One row of the `pins` setting as a pin; a row that is not a pin (no id, no target, a target with another scheme)
/// is skipped. The settings' validator refuses such rows, so this is for a value the feed carries in another shape.
fn parse_pin(row: &Map<String, Value>, row_index: usize) -> Option<PinSpec> {
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
        row: row_index,
    })
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
        let web = parse_pin(&row("mail", "https://mail.example.org/", "work"), 0).unwrap();
        assert_eq!(web.kind, Kind::Web);
        assert_eq!(web.profile, "work");
        let own = parse_pin(&row("chat", "https://chat.example.org/", ""), 1).unwrap();
        assert_eq!(own.profile, "chat");
        let view = parse_pin(&row("weather", "mod:weather:weather", ""), 2).unwrap();
        assert_eq!(view.kind, Kind::View);
        assert!(parse_pin(&row("x", "javascript:alert(1)", ""), 3).is_none());
    }
}
