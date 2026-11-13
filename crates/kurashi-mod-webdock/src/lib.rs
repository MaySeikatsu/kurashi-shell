//! The web dock: pins at a screen edge, each a site shown by the web host or a view of a mod (K38, MODS.md
//! "Web dock", docs/ux/webdock.md). The daemon owns the mode, the shown pin, the hover and focus state with its
//! deadlines (K40), the pins (settings) and the host's lifecycle; the shell and the host render `mod.webdock` and
//! send these actions. The state lives here, not in the service, so the actions work without a subscriber. Nothing
//! runs while the dock is hidden and the host is off (rule 5): the supervisor sleeps until an action, a settings
//! change, a host change, a hover deadline or the idle deadline.

mod dock;
mod open;

use std::collections::BTreeMap;
use std::future::Future;
use std::path::{Path, PathBuf};
use std::sync::{Arc, Mutex};

use dock::{
    CardPlace, Dock, DockError, Part, Place, Side, Spot, View, add_row_with, card_size_step,
    content_step, move_row, records_of, remove_row, retarget_row, rows_of, sizes_rows, view_rows,
};
pub use open::{Opener, SystemOpener};

use kurashi_mod_api::{
    ActionError, HostHandle, HostSpec, HostState, ModCtx, ModError, NativeMod, Publish, Settings,
    SettingsError, SettingsWriter,
};
use serde_json::{Value, json};
use tokio::runtime::Handle;
use tokio::sync::{Notify, watch};
use tokio::time::Instant;

/// The mod's id: its directory name, its document is `mod.webdock`, its actions are `webdock.*`.
const ID: &str = "webdock";

/// The directories the dock keeps (MODS.md "Web dock": `dirs`): the sites' profiles, and the favicon cache.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Dirs {
    pub data: PathBuf,
    pub cache: PathBuf,
}

impl Dirs {
    /// The daemon's directories for this mod: `$XDG_DATA_HOME/kurashi/webdock` and `$XDG_CACHE_HOME/kurashi/webdock`.
    pub fn from_env() -> Self {
        Self {
            data: xdg("XDG_DATA_HOME", ".local/share"),
            cache: xdg("XDG_CACHE_HOME", ".cache"),
        }
    }

    /// Both under `root` (tests): `root/data/webdock` and `root/cache/webdock`, the paths the daemon's host
    /// directories take when its XDG roots are redirected (`kurashid::native::hosts::HostEnv`).
    pub fn rooted(root: &Path) -> Self {
        Self {
            data: root.join("data").join(ID),
            cache: root.join("cache").join(ID),
        }
    }

    fn profiles(&self) -> PathBuf {
        self.data.join("profiles")
    }

    fn icons(&self) -> PathBuf {
        self.cache.join("icons")
    }
}

fn xdg(var: &str, fallback: &str) -> PathBuf {
    let base = std::env::var_os(var)
        .filter(|v| !v.is_empty())
        .map(PathBuf::from)
        .unwrap_or_else(|| {
            PathBuf::from(std::env::var_os("HOME").unwrap_or_default()).join(fallback)
        });
    base.join("kurashi").join(ID)
}

/// The web dock mod. Linked into kurashid by `native::linked()`.
pub struct Webdock {
    dirs: Dirs,
    opener: Arc<dyn Opener>,
}

impl Webdock {
    /// The daemon's configuration: the XDG directories, the system's browser.
    pub fn new() -> Self {
        Self::with(Dirs::from_env(), Arc::new(SystemOpener))
    }

    /// Any directories and browser (tests record the browser's calls).
    pub fn with(dirs: Dirs, opener: Arc<dyn Opener>) -> Self {
        Self { dirs, opener }
    }
}

impl Default for Webdock {
    fn default() -> Self {
        Self::new()
    }
}

impl NativeMod for Webdock {
    fn id(&self) -> &'static str {
        ID
    }

    fn enable(&self, ctx: &mut ModCtx) -> Result<(), ModError> {
        // The supervisor runs on the daemon's runtime, as the wallpaper's does: without one the enable is refused.
        let runtime =
            Handle::try_current().map_err(|_| ModError::Failed("webdock.error.runtime".into()))?;
        let settings: Settings = ctx.settings().clone();
        let host = ctx.host(
            "web",
            HostSpec {
                binary: "qs-webengine".into(),
                args: vec!["-p".into(), "{mod_dir}/host/shell.qml".into()],
                env: BTreeMap::new(),
            },
        )?;
        let writer = ctx.settings_writer();
        // I495 (session 30): the host saves the pages' icons here; it cannot make the directory itself (QML). Should it
        // fail, the host's save fails and the strip keeps the letters it showed before.
        let _ = std::fs::create_dir_all(self.dirs.icons());
        let dock = Dock::new(&settings, self.dirs.profiles(), self.dirs.icons())
            .with_forced(forced_of(&settings));
        let initial = dock.doc();
        let (doc, _) = watch::channel(initial.clone());
        // Subscribed now, not in the supervisor: a state the daemon writes before the task first runs is still seen.
        let host_rx = host.state();
        let shared = Arc::new(Shared {
            dock: Mutex::new(dock),
            notify: Notify::new(),
            doc,
            host,
            opener: self.opener.clone(),
            writer,
            settings: settings.clone(),
        });

        let serve = shared.clone();
        ctx.service(ID, initial, move |publish: Publish, _settings| {
            let serve = serve.clone();
            async move {
                let mut rx = serve.doc.subscribe();
                loop {
                    let doc = rx.borrow_and_update().clone();
                    publish(doc);
                    if rx.changed().await.is_err() {
                        break;
                    }
                }
            }
        })?;

        register_actions(ctx, &shared)?;
        // Spawned last: a refused registration returns before anything runs.
        runtime.spawn(supervise(shared, settings, host_rx));
        Ok(())
    }
}

/// What the actions, the host's reports and the supervisor share.
struct Shared {
    dock: Mutex<Dock>,
    /// Woken by every action, so the idle clock and the hover deadline are taken again.
    notify: Notify,
    doc: watch::Sender<Value>,
    host: HostHandle,
    opener: Arc<dyn Opener>,
    writer: SettingsWriter,
    /// The mod's settings feed: the `pins` and `pinned` a write reads back at once (the feed is synchronous).
    settings: Settings,
}

impl Shared {
    /// Runs `change` on the dock, then publishes the document. The change's result is returned even when it is
    /// a refusal that still applied (an icon the host sent that is not under the cache).
    fn with_dock<T>(
        &self,
        change: impl FnOnce(&mut Dock) -> Result<T, ActionError>,
    ) -> Result<T, ActionError> {
        let result = {
            let mut dock = self.dock.lock().expect("dock lock");
            let result = change(&mut dock);
            self.refresh(&mut dock);
            result
        };
        self.notify.notify_one();
        result
    }

    /// The host's state as it is now, then the document as the dock builds it, published when it changed.
    fn refresh(&self, dock: &mut Dock) {
        dock.set_host(self.host.state().borrow().clone());
        // W76: temporary pages nothing shows or keeps any more go before the document is built.
        dock.sweep();
        let doc = dock.doc();
        self.doc.send_if_modified(|current| {
            if *current == doc {
                false
            } else {
                *current = doc;
                true
            }
        });
    }

    fn refresh_now(&self) {
        let mut dock = self.dock.lock().expect("dock lock");
        self.refresh(&mut dock);
    }

    fn reload(&self, settings: &Settings) {
        let mut dock = self.dock.lock().expect("dock lock");
        dock.apply_settings(settings, Instant::now());
        // A force that starts or ends wakes `changed()` too (row 374): the strip's inert marks follow it.
        dock.set_forced(forced_of(settings));
        self.refresh(&mut dock);
    }

    /// The idle clock (MODS.md "Lifecycle"): the moment the host became idle, plus `unload_after`; `None` while the
    /// host is not idle, or never unloads.
    fn idle_deadline(&self, idle_since: &mut Option<Instant>) -> Option<Instant> {
        let dock = self.dock.lock().expect("dock lock");
        if !dock.is_idle() {
            *idle_since = None;
            return None;
        }
        let since = *idle_since.get_or_insert_with(Instant::now);
        dock.unload_after().map(|after| since + after)
    }

    /// The deadline passed: the host stops if it is still idle. Its state change empties `keep` and the loaded marks.
    /// True when it asked the host to stop.
    fn unload_when_idle(&self) -> bool {
        let idle = self.dock.lock().expect("dock lock").is_idle();
        if idle {
            self.host.stop();
        }
        idle
    }

    /// A reveal or a hide is due (K40). True when a reveal opens a site, which starts the host.
    fn fire_hover(&self) -> bool {
        let now = Instant::now();
        self.with_dock(|d| Ok(d.tick(now))).unwrap_or(false)
    }

    fn open(&self, args: &Value) -> Result<Option<Value>, ActionError> {
        let pin = pin_arg(args)?;
        let starts =
            self.with_dock(|d| d.open(pin, str_arg(args, "output")).map_err(dock_error))?;
        if starts {
            self.host.start();
        }
        Ok(None)
    }

    fn collapse(&self) -> Result<Option<Value>, ActionError> {
        self.with_dock(|d| {
            d.collapse();
            Ok(())
        })?;
        Ok(None)
    }

    fn hide(&self) -> Result<Option<Value>, ActionError> {
        self.with_dock(|d| {
            d.hide();
            Ok(())
        })?;
        Ok(None)
    }

    fn toggle(&self, args: &Value) -> Result<Option<Value>, ActionError> {
        let starts = self.with_dock(|d| Ok(d.toggle(str_arg(args, "output"))))?;
        if starts {
            self.host.start();
        }
        Ok(None)
    }

    fn size(&self, args: &Value) -> Result<Option<Value>, ActionError> {
        self.with_dock(|d| d.size(str_arg(args, "size")).map_err(dock_error))?;
        Ok(None)
    }

    /// `webdock.hover {part, inside, output, shared?}` (K40): a pointer report from the shell or the host.
    fn hover(&self, args: &Value) -> Result<Option<Value>, ActionError> {
        let part = str_arg(args, "part")
            .and_then(Part::parse)
            .ok_or_else(|| dock_error(DockError::Argument))?;
        let inside = args["inside"]
            .as_bool()
            .ok_or_else(|| dock_error(DockError::Argument))?;
        let output = str_arg(args, "output").ok_or_else(|| dock_error(DockError::Argument))?;
        let shared = opt_bool(args, "shared")?.unwrap_or(false);
        let now = Instant::now();
        self.with_dock(|d| {
            d.hover(part, inside, output, shared, now);
            Ok(())
        })?;
        Ok(None)
    }

    /// `webdock.engage {on}`: a part took or lost keyboard focus (K40).
    fn engage(&self, args: &Value) -> Result<Option<Value>, ActionError> {
        let on = args["on"]
            .as_bool()
            .ok_or_else(|| dock_error(DockError::Argument))?;
        let now = Instant::now();
        self.with_dock(|d| {
            d.engage(on, now);
            Ok(())
        })?;
        Ok(None)
    }

    /// `webdock.select {pin, output?}`: a click on a pin on the strip (K40). A site starts the host.
    fn select(&self, args: &Value) -> Result<Option<Value>, ActionError> {
        let pin = pin_arg(args)?;
        let starts =
            self.with_dock(|d| d.select(pin, str_arg(args, "output")).map_err(dock_error))?;
        if starts {
            self.host.start();
        }
        Ok(None)
    }

    /// `webdock.sidebar {on, output?, side?, inset?, top?, width?, height?}` (W30): the sidebar panel's page area at
    /// rest (`on: true`, every field), or gone (`on: false`). An open sidebar on a site starts the host.
    fn sidebar(&self, args: &Value) -> Result<Option<Value>, ActionError> {
        let on = args["on"]
            .as_bool()
            .ok_or_else(|| dock_error(DockError::Argument))?;
        let place = if on {
            let num = |key: &str| {
                args[key]
                    .as_u64()
                    .and_then(|n| u32::try_from(n).ok())
                    .ok_or_else(|| dock_error(DockError::Argument))
            };
            let width = num("width")?;
            let height = num("height")?;
            if width == 0 || height == 0 {
                return Err(dock_error(DockError::Argument));
            }
            Some(Place {
                output: str_arg(args, "output")
                    .ok_or_else(|| dock_error(DockError::Argument))?
                    .to_string(),
                side: str_arg(args, "side")
                    .and_then(Side::parse)
                    .ok_or_else(|| dock_error(DockError::Argument))?,
                inset: num("inset")?,
                top: num("top")?,
                width,
                height,
            })
        } else {
            None
        };
        // W73: `fresh` marks the panel's first rest (the sidebar opened on the dock: "last opened wins").
        let fresh = opt_bool(args, "fresh")?.unwrap_or(false);
        if self.with_dock(|d| Ok(d.place(place, fresh)))? {
            self.host.start();
        }
        Ok(None)
    }

    /// `webdock.sidebar_select {pin}` (W30): the sidebar shows `pin`; an open sidebar on a site starts the host.
    fn sidebar_select(&self, args: &Value) -> Result<Option<Value>, ActionError> {
        let pin = pin_arg(args)?;
        if self.with_dock(|d| d.side_select(pin).map_err(dock_error))? {
            self.host.start();
        }
        Ok(None)
    }

    /// `webdock.card {on, output?, x?, y?, width?, height?}` (W72): the bar card's page area at rest on its output
    /// (`on: true`, every field; logical px from the output's top-left corner), or gone (`on: false`). An open card on a
    /// site starts the host.
    fn card(&self, args: &Value) -> Result<Option<Value>, ActionError> {
        let on = args["on"]
            .as_bool()
            .ok_or_else(|| dock_error(DockError::Argument))?;
        let place = if on {
            let num = |key: &str| {
                args[key]
                    .as_u64()
                    .and_then(|n| u32::try_from(n).ok())
                    .ok_or_else(|| dock_error(DockError::Argument))
            };
            let width = num("width")?;
            let height = num("height")?;
            if width == 0 || height == 0 {
                return Err(dock_error(DockError::Argument));
            }
            Some(CardPlace {
                output: str_arg(args, "output")
                    .ok_or_else(|| dock_error(DockError::Argument))?
                    .to_string(),
                x: num("x")?,
                y: num("y")?,
                width,
                height,
            })
        } else {
            None
        };
        // W73: `fresh` marks the card's first rest since it opened ("last opened wins").
        let fresh = opt_bool(args, "fresh")?.unwrap_or(false);
        // W76: `closed` — the card closed (not a move): a "+" page it showed goes.
        let closed = opt_bool(args, "closed")?.unwrap_or(false);
        if self.with_dock(|d| {
            let starts = d.card_place(place, fresh);
            if closed {
                d.card_closed();
            }
            Ok(starts)
        })? {
            self.host.start();
        }
        Ok(None)
    }

    /// `webdock.card_select {pin}` (W72): the bar card shows `pin`; an open card on a site starts the host.
    fn card_select(&self, args: &Value) -> Result<Option<Value>, ActionError> {
        let pin = pin_arg(args)?;
        if self.with_dock(|d| d.card_select(pin).map_err(dock_error))? {
            self.host.start();
        }
        Ok(None)
    }

    /// `webdock.side_page {hover}` (session 32, the host): the pointer in its window over the sidebar's page.
    fn side_page(&self, args: &Value) -> Result<Option<Value>, ActionError> {
        let hover = opt_bool(args, "hover")?.unwrap_or(false);
        self.with_dock(|d| {
            d.side_page(hover);
            Ok(None)
        })
    }

    /// `webdock.card_page {hover, engaged}` (W72, the host): the pointer in its window over the card, and the user using it.
    fn card_page(&self, args: &Value) -> Result<Option<Value>, ActionError> {
        let hover = opt_bool(args, "hover")?.unwrap_or(false);
        let engaged = opt_bool(args, "engaged")?.unwrap_or(false);
        self.with_dock(|d| {
            d.card_page(hover, engaged);
            Ok(None)
        })
    }

    /// `webdock.back {}`: Escape on the dock's chrome (K40).
    fn back(&self) -> Result<Option<Value>, ActionError> {
        self.with_dock(|d| {
            d.back();
            Ok(())
        })?;
        Ok(None)
    }

    /// `webdock.view {pin, view}`: every pin of the profile takes the view, through the settings (undoable, K38).
    /// The dock shows it once the settings feed brings the rows back.
    async fn view(&self, args: &Value) -> Result<Option<Value>, ActionError> {
        let pin = pin_arg(args)?;
        let view = match args["view"].as_str() {
            Some("mobile") => View::Mobile,
            Some("desktop") => View::Desktop,
            _ => return Err(dock_error(DockError::View)),
        };
        let rows = view_rows(&rows_of(&self.settings), pin, view).map_err(dock_error)?;
        self.writer
            .set("pins", Value::Array(rows))
            .await
            .map_err(settings_error)?;
        Ok(None)
    }

    /// `webdock.pin {on?}`: the `pinned` setting; without an argument the value in effect flips (K40).
    async fn pin(&self, args: &Value) -> Result<Option<Value>, ActionError> {
        let on = opt_bool(args, "on")?;
        let current = self
            .settings
            .get("pinned")
            .and_then(|v| v.as_bool())
            .unwrap_or(false);
        self.writer
            .set("pinned", json!(on.unwrap_or(!current)))
            .await
            .map_err(settings_error)?;
        Ok(None)
    }

    /// `webdock.card_size {size?}` (W74): the bar card's size key — the size named, else the next one after the value
    /// in effect — written through the settings (one undoable step). Refused while the configuration forces it.
    async fn card_size(&self, args: &Value) -> Result<Option<Value>, ActionError> {
        let current = self.settings.get("card_size");
        let next = card_size_step(
            current.as_ref().and_then(Value::as_str),
            str_arg(args, "size"),
            self.settings.forced_by("card_size").is_some(),
        )
        .map_err(dock_error)?;
        self.writer
            .set("card_size", json!(next))
            .await
            .map_err(settings_error)?;
        Ok(None)
    }

    /// `webdock.content {content?}` (W78, the strip's switch): `online` or `local`, else the other one than the value in
    /// effect, written through the settings (one undoable step); a card of the other kind is put away. Refused while
    /// the configuration forces it.
    async fn content(&self, args: &Value) -> Result<Option<Value>, ActionError> {
        let current = self.settings.get("content");
        let next = content_step(
            current.as_ref().and_then(Value::as_str),
            str_arg(args, "content"),
            self.settings.forced_by("content").is_some(),
        )
        .map_err(dock_error)?;
        self.writer
            .set("content", json!(next))
            .await
            .map_err(settings_error)?;
        // The feed has the value already (a write reaches it before it returns): the strip and the card change in one
        // document.
        let settings = self.settings.clone();
        self.with_dock(|d| {
            d.apply_settings(&settings, Instant::now());
            d.content_changed();
            Ok(())
        })?;
        Ok(None)
    }

    /// `webdock.add {url, title?, from?}` → `{pin}`: a new web pin at the end of the list (K40). W76: `from` a temporary
    /// page ("Pin" in its toolbar): the new pin keeps that page's profile and takes its page (the places that showed
    /// it, no reload: the host renames the page it has).
    async fn add(&self, args: &Value) -> Result<Option<Value>, ActionError> {
        let url = str_arg(args, "url").ok_or_else(|| dock_error(DockError::Argument))?;
        let from = str_arg(args, "from").map(str::to_owned);
        let (taken, profile) = {
            let dock = self.dock.lock().expect("dock lock");
            let profile = from
                .as_deref()
                .and_then(|f| dock.temp_of(f))
                .map(|t| t.profile.clone());
            (dock.temp_ids(), profile)
        };
        let (rows, id) = add_row_with(
            &rows_of(&self.settings),
            url,
            str_arg(args, "title"),
            &taken,
            profile.as_deref(),
        )
        .map_err(dock_error)?;
        self.writer
            .set("pins", Value::Array(rows))
            .await
            .map_err(settings_error)?;
        if let Some(from) = from {
            // The feed has the new row already (a write reaches it before it returns); the dock takes it now, so the
            // page passes to the pin in one document.
            let settings = self.settings.clone();
            self.with_dock(|d| {
                d.apply_settings(&settings, Instant::now());
                d.adopt(&from, &id);
                Ok(())
            })?;
        }
        Ok(Some(json!({"pin": id})))
    }

    /// `webdock.browse {place, output?}` → `{pin}` (W76, "+"): a temporary page in that place, its address field open.
    fn browse(&self, args: &Value) -> Result<Option<Value>, ActionError> {
        let place = str_arg(args, "place")
            .and_then(Spot::parse)
            .ok_or_else(|| dock_error(DockError::Argument))?;
        let id = self.with_dock(|d| Ok(d.browse(place, str_arg(args, "output"))))?;
        self.host.start();
        Ok(Some(json!({"pin": id})))
    }

    /// `webdock.go {pin, text}` → `{url}` (W76, the address field): the address the text names or a search for it.
    fn go(&self, args: &Value) -> Result<Option<Value>, ActionError> {
        let pin = pin_arg(args)?;
        let text = args["text"]
            .as_str()
            .ok_or_else(|| dock_error(DockError::Argument))?;
        let url = self.with_dock(|d| d.go(pin, text).map_err(dock_error))?;
        Ok(Some(json!({"url": url})))
    }

    /// `webdock.unpin {pin}` (W76, "Unpin but keep open"): the row goes (one undo step), the page stays as a temporary
    /// page until the dock's rules unload it.
    async fn unpin(&self, args: &Value) -> Result<Option<Value>, ActionError> {
        let pin = pin_arg(args)?;
        if self.settings.forced_by("pins").is_some() {
            return Err(dock_error(DockError::Forced));
        }
        let rows = remove_row(&rows_of(&self.settings), pin).map_err(dock_error)?;
        self.with_dock(|d| d.unpin_keep(pin).map_err(dock_error))?;
        if let Err(e) = self.writer.set("pins", Value::Array(rows)).await {
            // The row stays: so does the pin (its page was never anything else).
            let _ = self.with_dock(|d| {
                d.unpin_undo(pin);
                Ok(())
            });
            return Err(settings_error(e));
        }
        Ok(None)
    }

    /// `webdock.resize {output, width?, height?}` (W76): the card's box on that output, remembered in `sizes` (one undo
    /// step); no size returns the output to the default. Refused while the configuration forces `sizes`.
    async fn resize(&self, args: &Value) -> Result<Option<Value>, ActionError> {
        if self.settings.forced_by("sizes").is_some() {
            return Err(dock_error(DockError::Forced));
        }
        let output = str_arg(args, "output").ok_or_else(|| dock_error(DockError::Argument))?;
        let side = |k: &str| -> Result<Option<u32>, ActionError> {
            match args.get(k) {
                None | Some(Value::Null) => Ok(None),
                Some(v) => v
                    .as_u64()
                    .and_then(|n| u32::try_from(n).ok())
                    .map(Some)
                    .ok_or_else(|| dock_error(DockError::Argument)),
            }
        };
        let size = match (side("width")?, side("height")?) {
            (Some(w), Some(h)) => Some((w, h)),
            (None, None) => None,
            _ => return Err(dock_error(DockError::Argument)),
        };
        let rows =
            sizes_rows(&records_of(&self.settings, "sizes"), output, size).map_err(dock_error)?;
        self.writer
            .set("sizes", Value::Array(rows))
            .await
            .map_err(settings_error)?;
        Ok(None)
    }

    /// `webdock.remove {pin}`: the pin's row goes; the card closes with it (the settings feed does that).
    async fn remove(&self, args: &Value) -> Result<Option<Value>, ActionError> {
        let pin = pin_arg(args)?;
        let rows = remove_row(&rows_of(&self.settings), pin).map_err(dock_error)?;
        self.writer
            .set("pins", Value::Array(rows))
            .await
            .map_err(settings_error)?;
        Ok(None)
    }

    /// `webdock.move {pin, to}`: the pin to index `to` (0-based, clamped to the list).
    async fn move_pin(&self, args: &Value) -> Result<Option<Value>, ActionError> {
        let pin = pin_arg(args)?;
        let to = args["to"]
            .as_i64()
            .ok_or_else(|| dock_error(DockError::Argument))?;
        let rows = move_row(&rows_of(&self.settings), pin, to).map_err(dock_error)?;
        self.writer
            .set("pins", Value::Array(rows))
            .await
            .map_err(settings_error)?;
        Ok(None)
    }

    /// `webdock.retarget {pin, url?}`: "replace the pin with this page" (a web pin's address; K40). W76: without `url`,
    /// the page's address the host reported (`at`; the pin's menu, "Update pin to this page").
    async fn retarget(&self, args: &Value) -> Result<Option<Value>, ActionError> {
        let pin = pin_arg(args)?;
        let url = match str_arg(args, "url") {
            Some(url) => url.to_string(),
            None => self
                .dock
                .lock()
                .expect("dock lock")
                .at(pin)
                .ok_or_else(|| dock_error(DockError::Argument))?,
        };
        let rows = retarget_row(&rows_of(&self.settings), pin, &url).map_err(dock_error)?;
        self.writer
            .set("pins", Value::Array(rows))
            .await
            .map_err(settings_error)?;
        Ok(None)
    }

    /// "Open in browser": http and https only, through the system's default browser.
    fn open_external(&self, url: &str) -> Result<(), ActionError> {
        if !open::web_url(url) {
            return Err(ActionError::Invalid("webdock.error.url".into()));
        }
        if !self.opener.installed() {
            return Err(ActionError::Unavailable("webdock.error.no_browser".into()));
        }
        self.opener.open(url).map_err(ActionError::Internal)
    }

    fn open_external_action(&self, args: &Value) -> Result<Option<Value>, ActionError> {
        let url =
            str_arg(args, "url").ok_or_else(|| ActionError::Invalid("webdock.error.url".into()))?;
        self.open_external(url)?;
        Ok(None)
    }

    fn host_loaded(&self, args: &Value) -> Result<Option<Value>, ActionError> {
        let pin = pin_arg(args)?;
        self.with_dock(|d| d.loaded(pin, str_arg(args, "icon")).map_err(dock_error))?;
        Ok(None)
    }

    /// `webdock.host.url {pin, url}` (W76): the page's address changed.
    fn host_url(&self, args: &Value) -> Result<Option<Value>, ActionError> {
        let pin = pin_arg(args)?;
        let url = args["url"]
            .as_str()
            .ok_or_else(|| dock_error(DockError::Argument))?;
        self.with_dock(|d| d.page_url(pin, url).map_err(dock_error))?;
        Ok(None)
    }

    fn host_unloaded(&self, args: &Value) -> Result<Option<Value>, ActionError> {
        let pin = pin_arg(args)?;
        self.with_dock(|d| d.unloaded(pin).map_err(dock_error))?;
        Ok(None)
    }

    fn host_audible(&self, args: &Value) -> Result<Option<Value>, ActionError> {
        let pin = pin_arg(args)?;
        let on = args["on"]
            .as_bool()
            .ok_or_else(|| dock_error(DockError::Argument))?;
        let now = Instant::now();
        // I495 (session 30): the page's title rides along (a player's page names its track there: Spotify, YouTube),
        // for the bar module's playing view.
        let title = str_arg(args, "title").map(str::to_owned);
        self.with_dock(|d| {
            d.audible(pin, on, now).map_err(dock_error)?;
            d.page_title(pin, title);
            Ok(())
        })?;
        Ok(None)
    }

    fn host_blocked(&self, args: &Value) -> Result<Option<Value>, ActionError> {
        let pin = pin_arg(args)?;
        let permission =
            str_arg(args, "permission").ok_or_else(|| dock_error(DockError::Permission))?;
        self.with_dock(|d| d.blocked(pin, permission).map_err(dock_error))?;
        Ok(None)
    }

    fn host_new_window(&self, args: &Value) -> Result<Option<Value>, ActionError> {
        let pin = pin_arg(args)?;
        self.with_dock(|d| d.web_pin(pin).map_err(dock_error))?;
        let url =
            str_arg(args, "url").ok_or_else(|| ActionError::Invalid("webdock.error.url".into()))?;
        self.open_external(url)?;
        Ok(None)
    }

    fn host_crashed(&self, args: &Value) -> Result<Option<Value>, ActionError> {
        let pin = pin_arg(args)?;
        self.with_dock(|d| d.crashed(pin).map_err(dock_error))?;
        Ok(None)
    }
}

/// The settings the configuration forces, each with its source (I91), from the daemon's provenance feed (row 374).
const SETTING_KEYS: [&str; 23] = [
    "pins",
    "site_icons",
    "sizes",
    "search",
    "bar_site",
    "bar_playing",
    "default_view",
    "width",
    "large",
    "edge",
    "unload_after",
    "max_loaded",
    "hover",
    "hover_takes_page",
    "reopen_last",
    "pinned",
    "reserve",
    "indicator",
    "strip",
    "new_tabs",
    "page_style",
    "card_size",
    "content",
];

fn forced_of(settings: &Settings) -> BTreeMap<String, String> {
    SETTING_KEYS
        .iter()
        .filter_map(|k| Some(((*k).to_string(), settings.forced_by(k)?)))
        .collect()
}

fn dock_error(e: DockError) -> ActionError {
    ActionError::Invalid(e.key().into())
}

fn settings_error(e: SettingsError) -> ActionError {
    let key = e.i18n_key().to_string();
    match e {
        SettingsError::Unavailable => ActionError::Unavailable(key),
        _ => ActionError::Invalid(key),
    }
}

fn str_arg<'a>(args: &'a Value, key: &str) -> Option<&'a str> {
    args[key].as_str().filter(|s| !s.is_empty())
}

/// An optional boolean argument: absent or null is `None`; anything else that is not a boolean is refused.
fn opt_bool(args: &Value, key: &str) -> Result<Option<bool>, ActionError> {
    match args.get(key) {
        None | Some(Value::Null) => Ok(None),
        Some(v) => v
            .as_bool()
            .map(Some)
            .ok_or_else(|| dock_error(DockError::Argument)),
    }
}

fn pin_arg(args: &Value) -> Result<&str, ActionError> {
    str_arg(args, "pin").ok_or_else(|| dock_error(DockError::UnknownPin))
}

/// An action that answers at once, from the dock's state.
fn sync_action<F>(ctx: &mut ModCtx, s: &Arc<Shared>, id: &str, f: F) -> Result<(), ModError>
where
    F: Fn(&Shared, Value) -> Result<Option<Value>, ActionError> + Send + Sync + 'static,
{
    let s = s.clone();
    ctx.action(id, &format!("action.{id}"), move |args| {
        let result = f(s.as_ref(), args);
        async move { result }
    })
}

/// An action that writes the settings (the pins, `pinned`) and so awaits the settings writer.
fn write_action<F, Fut>(ctx: &mut ModCtx, s: &Arc<Shared>, id: &str, f: F) -> Result<(), ModError>
where
    F: Fn(Arc<Shared>, Value) -> Fut + Send + Sync + 'static,
    Fut: Future<Output = Result<Option<Value>, ActionError>> + Send + 'static,
{
    let s = s.clone();
    ctx.action(id, &format!("action.{id}"), move |args| f(s.clone(), args))
}

fn register_actions(ctx: &mut ModCtx, s: &Arc<Shared>) -> Result<(), ModError> {
    sync_action(ctx, s, "webdock.open", |s, a| s.open(&a))?;
    sync_action(ctx, s, "webdock.collapse", |s, _| s.collapse())?;
    sync_action(ctx, s, "webdock.hide", |s, _| s.hide())?;
    sync_action(ctx, s, "webdock.toggle", |s, a| s.toggle(&a))?;
    sync_action(ctx, s, "webdock.size", |s, a| s.size(&a))?;
    sync_action(ctx, s, "webdock.hover", |s, a| s.hover(&a))?;
    sync_action(ctx, s, "webdock.engage", |s, a| s.engage(&a))?;
    sync_action(ctx, s, "webdock.select", |s, a| s.select(&a))?;
    sync_action(ctx, s, "webdock.back", |s, _| s.back())?;
    sync_action(ctx, s, "webdock.sidebar", |s, a| s.sidebar(&a))?;
    sync_action(ctx, s, "webdock.sidebar_select", |s, a| {
        s.sidebar_select(&a)
    })?;
    sync_action(ctx, s, "webdock.card", |s, a| s.card(&a))?;
    sync_action(ctx, s, "webdock.card_select", |s, a| s.card_select(&a))?;
    sync_action(ctx, s, "webdock.card_page", |s, a| s.card_page(&a))?;
    sync_action(ctx, s, "webdock.side_page", |s, a| s.side_page(&a))?;
    sync_action(ctx, s, "webdock.card_close", |s, _| {
        s.with_dock(|d| {
            d.card_close();
            Ok(None)
        })
    })?;
    sync_action(ctx, s, "webdock.card_focus", |s, _| {
        s.with_dock(|d| {
            d.card_focus();
            Ok(None)
        })
    })?;
    sync_action(ctx, s, "webdock.open_external", |s, a| {
        s.open_external_action(&a)
    })?;
    // W76: "+", the address field, the menu's reload, the page's address.
    sync_action(ctx, s, "webdock.browse", |s, a| s.browse(&a))?;
    sync_action(ctx, s, "webdock.go", |s, a| s.go(&a))?;
    sync_action(ctx, s, "webdock.drop", |s, a| {
        let pin = pin_arg(&a)?;
        s.with_dock(|d| d.drop_temp(pin).map_err(dock_error))?;
        Ok(None)
    })?;
    sync_action(ctx, s, "webdock.reload", |s, a| {
        let pin = pin_arg(&a)?;
        s.with_dock(|d| d.reload(pin).map_err(dock_error))?;
        Ok(None)
    })?;
    sync_action(ctx, s, "webdock.host.url", |s, a| s.host_url(&a))?;
    sync_action(ctx, s, "webdock.host.loaded", |s, a| s.host_loaded(&a))?;
    sync_action(ctx, s, "webdock.host.unloaded", |s, a| s.host_unloaded(&a))?;
    sync_action(ctx, s, "webdock.host.audible", |s, a| s.host_audible(&a))?;
    sync_action(ctx, s, "webdock.host.blocked", |s, a| s.host_blocked(&a))?;
    sync_action(ctx, s, "webdock.host.new_window", |s, a| {
        s.host_new_window(&a)
    })?;
    sync_action(ctx, s, "webdock.host.crashed", |s, a| s.host_crashed(&a))?;

    write_action(
        ctx,
        s,
        "webdock.view",
        |s, a| async move { s.view(&a).await },
    )?;
    write_action(ctx, s, "webdock.pin", |s, a| async move { s.pin(&a).await })?;
    write_action(ctx, s, "webdock.card_size", |s, a| async move {
        s.card_size(&a).await
    })?;
    write_action(ctx, s, "webdock.add", |s, a| async move { s.add(&a).await })?;
    write_action(ctx, s, "webdock.content", |s, a| async move {
        s.content(&a).await
    })?;
    write_action(ctx, s, "webdock.remove", |s, a| async move {
        s.remove(&a).await
    })?;
    write_action(ctx, s, "webdock.move", |s, a| async move {
        s.move_pin(&a).await
    })?;
    write_action(ctx, s, "webdock.retarget", |s, a| async move {
        s.retarget(&a).await
    })?;
    write_action(
        ctx,
        s,
        "webdock.unpin",
        |s, a| async move { s.unpin(&a).await },
    )?;
    write_action(ctx, s, "webdock.resize", |s, a| async move {
        s.resize(&a).await
    })?;
    Ok(())
}

/// The dock's loop. It ends when the mod is disabled, which closes the settings feed.
async fn supervise(
    shared: Arc<Shared>,
    mut settings: Settings,
    mut host: watch::Receiver<HostState>,
) {
    let mut idle_since: Option<Instant> = None;
    loop {
        let deadline = shared.idle_deadline(&mut idle_since);
        // The hover deadline exists only while a reveal or a hide is pending (K40, rule 5); the grace's end only while a
        // page that played sound is in its grace (W73).
        let (due, grace) = {
            let dock = shared.dock.lock().expect("dock lock");
            (dock.due_at(), dock.grace_due())
        };
        tokio::select! {
            changed = settings.changed() => {
                if !changed {
                    break;
                }
                shared.reload(&settings);
            }
            () = changed_or_pending(&mut host) => shared.refresh_now(),
            () = shared.notify.notified() => {}
            () = sleep_until_or_pending(deadline) => {
                // The clock starts again from here: a host that does not report `Off` at once must not keep the
                // deadline in the past (a tight loop of stops).
                if shared.unload_when_idle() {
                    idle_since = None;
                }
            }
            () = sleep_until_or_pending(due) => {
                if shared.fire_hover() {
                    shared.host.start();
                }
            }
            () = sleep_until_or_pending(grace) => {
                // The page goes back to the dock's rules: `keep` and `awake` change, the idle clock may start.
                let now = Instant::now();
                let _ = shared.with_dock(|d| Ok(d.expire(now)));
            }
        }
    }
}

/// Resolves when the host's state changed; never if its sender is gone (the loop then waits on the others).
async fn changed_or_pending(rx: &mut watch::Receiver<HostState>) {
    if rx.changed().await.is_err() {
        std::future::pending::<()>().await;
    }
}

async fn sleep_until_or_pending(at: Option<Instant>) {
    match at {
        Some(at) => tokio::time::sleep_until(at).await,
        None => std::future::pending().await,
    }
}
