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
    Dock, DockError, Part, View, add_row, move_row, remove_row, retarget_row, rows_of, view_rows,
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
        let dock = Dock::new(&settings, self.dirs.profiles(), self.dirs.icons());
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

    /// `webdock.add {url, title?}` → `{pin}`: a new web pin at the end of the list (K40).
    async fn add(&self, args: &Value) -> Result<Option<Value>, ActionError> {
        let url = str_arg(args, "url").ok_or_else(|| dock_error(DockError::Argument))?;
        let (rows, id) =
            add_row(&rows_of(&self.settings), url, str_arg(args, "title")).map_err(dock_error)?;
        self.writer
            .set("pins", Value::Array(rows))
            .await
            .map_err(settings_error)?;
        Ok(Some(json!({"pin": id})))
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

    /// `webdock.retarget {pin, url}`: "replace the pin with this page" (a web pin's address; K40).
    async fn retarget(&self, args: &Value) -> Result<Option<Value>, ActionError> {
        let pin = pin_arg(args)?;
        let url = str_arg(args, "url").ok_or_else(|| dock_error(DockError::Argument))?;
        let rows = retarget_row(&rows_of(&self.settings), pin, url).map_err(dock_error)?;
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
        self.with_dock(|d| d.audible(pin, on).map_err(dock_error))?;
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
    sync_action(ctx, s, "webdock.open_external", |s, a| {
        s.open_external_action(&a)
    })?;
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
    write_action(ctx, s, "webdock.add", |s, a| async move { s.add(&a).await })?;
    write_action(ctx, s, "webdock.remove", |s, a| async move {
        s.remove(&a).await
    })?;
    write_action(ctx, s, "webdock.move", |s, a| async move {
        s.move_pin(&a).await
    })?;
    write_action(ctx, s, "webdock.retarget", |s, a| async move {
        s.retarget(&a).await
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
        // The hover deadline exists only while a reveal or a hide is pending (K40, rule 5).
        let due = shared.dock.lock().expect("dock lock").due_at();
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
