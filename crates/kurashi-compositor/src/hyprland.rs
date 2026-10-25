//! Hyprland adapter: requests on `.socket.sock` (one per connection: `j/monitors` → JSON, `dispatch …` → `ok`),
//! events on `.socket2.sock` (`name>>data` lines), in `$XDG_RUNTIME_DIR/hypr/$HYPRLAND_INSTANCE_SIGNATURE`
//! (Hyprland ≥ 0.40; `/tmp/hypr/…` before). The shapes are the ones `hyprctl -j` prints and that ii
//! (`services/HyprlandData.qml`) and DMS (`Services/HyprlandService.qml`, `KeyboardLayoutService.qml`) parse.
//!
//! As with Sway, an event names what went stale and only that is re-read once the burst has been read
//! (`workspacev2`, `focusedmonv2`, … → monitors and workspaces; `openwindow`, `movewindowv2`, … → clients;
//! `activelayout` → devices). Focus (`activewindowv2`), urgency (`urgent`) and titles (`windowtitlev2`) are
//! applied in place: no request, so a browser retitling every page costs nothing but the diff.
//!
//! Readings (ARCHITECTURE §7): workspaces are global (WormShell `per_output_workspaces: false`); each is shown
//! on the monitor it lives on. A numbered workspace's `idx` and `id` are its number; named ones (negative ids in
//! Hyprland) get `id` 2³² + |id| (JSON-safe, no clash) and an `idx` after the highest number on their monitor.
//! Special workspaces (scratchpads) are not workspaces here; their windows have none. Window ids are the
//! client addresses (`0x55…` as u64). `dpms off` stays off until told: the wake guard turns screens on.

use std::{
    collections::BTreeSet,
    ffi::OsStr,
    ffi::OsString,
    path::{Path, PathBuf},
    sync::Arc,
};

use serde::Deserialize;
use tokio::{
    io::{AsyncBufReadExt, AsyncReadExt, AsyncWriteExt, BufReader},
    net::UnixStream,
};
use tokio_stream::Stream;

use crate::{
    Action, Capabilities, Compositor, CompositorState, Direction, Error, Event, KeyboardLayouts,
    LayoutTarget, Output, Result, Window, Workspace, WorkspaceRef,
    any::{self, Mirror, Shot, io_err},
    sway::indices,
};

pub const CAPABILITIES: Capabilities = Capabilities {
    scroll_position: false,
    overview: false,
    window_previews: false,
    // Hyprland blurs layer surfaces by `layerrule`, which kurashid does not set (yet): no hint offered.
    blur_hint: false,
    workspace_names: true,
};

pub const REQUEST_SOCKET: &str = ".socket.sock";
pub const EVENT_SOCKET: &str = ".socket2.sock";
/// Named workspaces' ids are moved here (Hyprland gives them negative ones).
const NAMED_BASE: u64 = 1 << 32;

/// The instance directory: `$XDG_RUNTIME_DIR/hypr/<sig>` when its request socket is there, else the pre-0.40
/// `/tmp/hypr/<sig>` when that one is, else the former.
pub fn instance_dir(sig: &OsStr, runtime: Option<OsString>) -> PathBuf {
    let old = Path::new("/tmp/hypr").join(sig);
    match runtime.map(|r| PathBuf::from(r).join("hypr").join(sig)) {
        Some(new) if new.join(REQUEST_SOCKET).exists() => new,
        _ if old.join(REQUEST_SOCKET).exists() => old,
        Some(new) => new,
        None => old,
    }
}

#[derive(Debug, Clone, Default, Deserialize)]
#[serde(default)]
struct WsRef {
    id: i64,
    name: String,
}

#[derive(Debug, Clone, Default, Deserialize)]
#[serde(default)]
struct Monitor {
    name: String,
    make: String,
    model: String,
    x: i32,
    y: i32,
    width: u32,
    height: u32,
    scale: f64,
    transform: i64,
    focused: bool,
    disabled: bool,
    #[serde(rename = "activeWorkspace")]
    active_workspace: WsRef,
}

#[derive(Debug, Clone, Default, Deserialize)]
#[serde(default)]
struct HWorkspace {
    id: i64,
    name: String,
    monitor: String,
}

#[derive(Debug, Clone, Default, Deserialize)]
#[serde(default)]
struct Client {
    address: String,
    mapped: bool,
    workspace: WsRef,
    floating: bool,
    class: String,
    #[serde(rename = "initialClass")]
    initial_class: String,
    title: String,
    at: Vec<i32>,
    size: Vec<i32>,
}

#[derive(Debug, Clone, Default, Deserialize)]
#[serde(default)]
struct Keyboard {
    name: String,
    layout: String,
    variant: String,
    active_keymap: String,
    active_layout_index: Option<usize>,
    main: bool,
}

#[derive(Debug, Clone, Default, Deserialize)]
#[serde(default)]
struct Devices {
    keyboards: Vec<Keyboard>,
}

/// `0x55d1c2a3b4c0` (JSON) or `55d1c2a3b4c0` (events) → the window id.
pub fn parse_address(s: &str) -> Option<u64> {
    let s = s.trim();
    let hex = s.strip_prefix("0x").unwrap_or(s);
    u64::from_str_radix(hex, 16).ok()
}

/// A Hyprland workspace id as ours; `None` for special workspaces.
fn ws_id(id: i64, name: &str) -> Option<u64> {
    if name.starts_with("special") {
        None
    } else if id > 0 {
        Some(id as u64)
    } else {
        Some(NAMED_BASE + id.unsigned_abs())
    }
}

/// XKB names of layout codes (Noctalia `Services/KeyboardLayoutService.qml`'s `layoutMap`, reversed), so the
/// names match what niri and Sway report.
const LAYOUT_NAMES: [(&str, &str); 21] = [
    ("us", "English (US)"),
    ("gb", "English (UK)"),
    ("de", "German"),
    ("fr", "French"),
    ("es", "Spanish"),
    ("it", "Italian"),
    ("br", "Portuguese (Brazil)"),
    ("pt", "Portuguese"),
    ("ru", "Russian"),
    ("pl", "Polish"),
    ("se", "Swedish"),
    ("no", "Norwegian"),
    ("dk", "Danish"),
    ("fi", "Finnish"),
    ("hu", "Hungarian"),
    ("tr", "Turkish"),
    ("cz", "Czech"),
    ("sk", "Slovak"),
    ("jp", "Japanese"),
    ("kr", "Korean"),
    ("cn", "Chinese"),
];

fn layout_name(code: &str, variant: &str) -> String {
    let base = LAYOUT_NAMES
        .iter()
        .find(|(c, _)| *c == code)
        .map(|(_, n)| n.to_string())
        .unwrap_or_else(|| code.to_string());
    if variant.is_empty() {
        base
    } else {
        format!("{base} ({variant})")
    }
}

fn keyboard_layouts(devices: &Devices) -> Option<KeyboardLayouts> {
    let kb = devices
        .keyboards
        .iter()
        .find(|k| k.main)
        .or_else(|| devices.keyboards.first())?;
    let codes: Vec<&str> = kb.layout.split(',').map(str::trim).collect();
    if codes.iter().all(|c| c.is_empty()) {
        return None;
    }
    let variants: Vec<&str> = kb.variant.split(',').map(str::trim).collect();
    let names: Vec<String> = codes
        .iter()
        .enumerate()
        .map(|(i, c)| layout_name(c, variants.get(i).copied().unwrap_or("")))
        .collect();
    // Older Hyprland has no index: the active keymap's name, else its base name, else the first.
    let current = kb.active_layout_index.unwrap_or_else(|| {
        let base = kb.active_keymap.split(" (").next().unwrap_or_default();
        names
            .iter()
            .position(|n| *n == kb.active_keymap)
            .or_else(|| {
                names
                    .iter()
                    .position(|n| n.split(" (").next() == Some(base))
            })
            .unwrap_or(0)
    });
    Some(KeyboardLayouts {
        current: current.min(names.len().saturating_sub(1)),
        names,
    })
}

fn parse<T: for<'de> Deserialize<'de>>(body: &str) -> Result<T> {
    serde_json::from_str(body).map_err(|e| Error::Protocol(format!("{e}: {body:.80}")))
}

/// Hyprland's replies and in-place event state, projected into neutral types. Pure: tests feed it replies.
#[derive(Debug, Default)]
pub struct HyprState {
    monitors: Vec<Monitor>,
    workspaces: Vec<HWorkspace>,
    clients: Vec<Client>,
    /// `activewindowv2`; `None`: no window has focus (an empty workspace).
    active: Option<u64>,
    active_rect: Option<(i32, i32, u32, u32)>,
    urgent: BTreeSet<u64>,
    keyboard: Option<KeyboardLayouts>,
}

impl HyprState {
    pub fn set_monitors(&mut self, body: &str) -> Result<()> {
        self.monitors = parse(body)?;
        Ok(())
    }

    pub fn set_workspaces(&mut self, body: &str) -> Result<()> {
        self.workspaces = parse(body)?;
        Ok(())
    }

    pub fn set_clients(&mut self, body: &str) -> Result<()> {
        self.clients = parse(body)?;
        let live: BTreeSet<u64> = self
            .clients
            .iter()
            .filter_map(|c| parse_address(&c.address))
            .collect();
        self.urgent.retain(|a| live.contains(a));
        Ok(())
    }

    /// `j/activewindow`: `{}` when nothing has focus.
    pub fn set_active_window(&mut self, body: &str) -> Result<()> {
        let c: Client = parse(body)?;
        self.active = parse_address(&c.address);
        self.active_rect = match (self.active, c.at.as_slice(), c.size.as_slice()) {
            (Some(_), [x, y], [w, h]) => Some((*x, *y, (*w).max(0) as u32, (*h).max(0) as u32)),
            _ => None,
        };
        Ok(())
    }

    /// Layouts are not worth the session: devices we cannot read show none.
    pub fn set_devices(&mut self, body: &str) -> Result<()> {
        self.keyboard = match parse::<Devices>(body) {
            Ok(d) => keyboard_layouts(&d),
            Err(e) => {
                tracing::warn!("hyprland devices unreadable: {e}");
                None
            }
        };
        Ok(())
    }

    pub fn project(&self) -> CompositorState {
        let focused_mon = self.monitors.iter().find(|m| m.focused);
        let mut outputs: Vec<Output> = self
            .monitors
            .iter()
            .filter(|m| !m.disabled)
            .map(|m| {
                let scale = if m.scale > 0.0 { m.scale } else { 1.0 };
                let (w, h) = if m.transform % 2 == 1 {
                    (m.height, m.width)
                } else {
                    (m.width, m.height)
                };
                Output {
                    name: m.name.clone(),
                    make: m.make.clone(),
                    model: m.model.clone(),
                    logical: (
                        m.x,
                        m.y,
                        (f64::from(w) / scale).round() as u32,
                        (f64::from(h) / scale).round() as u32,
                    ),
                    scale,
                    focused: m.focused,
                }
            })
            .collect();
        outputs.sort_by(|a, b| a.name.cmp(&b.name));

        let shown: BTreeSet<i64> = self
            .monitors
            .iter()
            .map(|m| m.active_workspace.id)
            .collect();
        let focused_ws = focused_mon.map(|m| m.active_workspace.id);
        let mut occupied = BTreeSet::new();
        let mut urgent = BTreeSet::new();
        let mut windows: Vec<Window> = Vec::new();
        for c in self.clients.iter().filter(|c| c.mapped) {
            let Some(id) = parse_address(&c.address) else {
                continue;
            };
            let ws = ws_id(c.workspace.id, &c.workspace.name);
            if let Some(ws) = ws {
                occupied.insert(ws);
                if self.urgent.contains(&id) {
                    urgent.insert(ws);
                }
            }
            let app_id = [&c.class, &c.initial_class]
                .into_iter()
                .find(|s| !s.is_empty())
                .cloned();
            windows.push(Window {
                id,
                app_id,
                title: Some(c.title.clone()),
                workspace_id: ws,
                focused: self.active == Some(id),
                floating: c.floating,
                urgent: self.urgent.contains(&id),
            });
        }
        windows.sort_by_key(|w| w.id);

        let real: Vec<(u64, &HWorkspace)> = self
            .workspaces
            .iter()
            .filter_map(|w| ws_id(w.id, &w.name).map(|id| (id, w)))
            .collect();
        let idx = indices(real.iter().map(|(id, w)| {
            let num = if (1..=255).contains(&w.id) { w.id } else { -1 };
            (*id, w.monitor.as_str(), num)
        }));
        let mut workspaces: Vec<Workspace> = real
            .iter()
            .map(|(id, w)| Workspace {
                id: *id,
                idx: idx[id],
                name: Some(w.name.clone()),
                output: Some(w.monitor.clone()).filter(|m| !m.is_empty()),
                focused: focused_ws == Some(w.id),
                active: shown.contains(&w.id),
                occupied: occupied.contains(id),
                urgent: urgent.contains(id),
            })
            .collect();
        workspaces.sort_by(|a, b| (&a.output, a.idx, a.id).cmp(&(&b.output, b.idx, b.id)));

        CompositorState {
            outputs,
            workspaces,
            windows,
            overview_open: false,
            keyboard: self.keyboard.clone(),
        }
    }

    /// An event line in place; returns what must be re-read.
    fn apply(&mut self, line: &str, d: &mut Dirty) {
        let Some((name, data)) = line.split_once(">>") else {
            return;
        };
        match name {
            "workspace" | "workspacev2" | "focusedmon" | "focusedmonv2" | "createworkspace"
            | "createworkspacev2" | "destroyworkspace" | "destroyworkspacev2" | "moveworkspace"
            | "moveworkspacev2" | "renameworkspace" | "activespecial" | "activespecialv2" => {
                d.monitors = true;
                d.workspaces = true;
            }
            "monitoradded" | "monitoraddedv2" | "monitorremoved" | "monitorremovedv2"
            | "configreloaded" => *d = Dirty::ALL,
            "openwindow" | "closewindow" | "movewindow" | "movewindowv2" | "changefloatingmode" => {
                d.clients = true;
            }
            "activewindowv2" => {
                // Its rectangle (a window screenshot) is read when asked, not here.
                let addr = parse_address(data);
                self.active = addr;
                if let Some(a) = addr {
                    self.urgent.remove(&a);
                }
                d.touched = true;
            }
            "urgent" => {
                if let Some(a) = parse_address(data)
                    && Some(a) != self.active
                {
                    self.urgent.insert(a);
                    d.touched = true;
                }
            }
            "windowtitlev2" => {
                if let Some((addr, title)) = data.split_once(',')
                    && let Some(c) = self
                        .clients
                        .iter_mut()
                        .find(|c| parse_address(&c.address) == parse_address(addr))
                {
                    c.title = title.to_string();
                    d.touched = true;
                }
            }
            "activelayout" => d.devices = true,
            _ => {}
        }
    }
}

#[derive(Debug, Default, Clone, Copy, PartialEq)]
struct Dirty {
    monitors: bool,
    workspaces: bool,
    clients: bool,
    devices: bool,
    /// `j/activewindow` (the focused window and its rectangle): at sync and for a window screenshot only.
    active: bool,
    touched: bool,
}

impl Dirty {
    const ALL: Dirty = Dirty {
        monitors: true,
        workspaces: true,
        clients: true,
        devices: true,
        active: true,
        touched: false,
    };

    fn refetch(&self) -> bool {
        self.monitors || self.workspaces || self.clients || self.devices
    }
}

/// One request on its own connection (Hyprland answers one per connection, then closes).
pub async fn request(dir: &Path, cmd: &str) -> Result<String> {
    let io = async {
        let mut s = UnixStream::connect(dir.join(REQUEST_SOCKET)).await?;
        s.write_all(cmd.as_bytes()).await?;
        let mut out = String::new();
        s.read_to_string(&mut out).await?;
        Ok::<_, std::io::Error>(out)
    };
    tokio::time::timeout(any::REQUEST_TIMEOUT, io)
        .await
        .map_err(|_| Error::Unavailable("hyprland did not answer".into()))?
        .map_err(io_err)
}

/// A command whose reply is `ok`; anything else is Hyprland's refusal.
pub async fn command(dir: &Path, cmd: &str) -> Result<()> {
    let reply = request(dir, cmd).await?;
    match reply.trim() {
        "ok" => Ok(()),
        other => Err(Error::Rejected(other.to_string())),
    }
}

async fn fetch(dir: &Path, st: &mut HyprState, d: Dirty) -> Result<()> {
    if d.monitors {
        st.set_monitors(&request(dir, "j/monitors").await?)?;
    }
    if d.workspaces {
        st.set_workspaces(&request(dir, "j/workspaces").await?)?;
    }
    if d.clients {
        st.set_clients(&request(dir, "j/clients").await?)?;
    }
    if d.active {
        st.set_active_window(&request(dir, "j/activewindow").await?)?;
    }
    if d.devices {
        st.set_devices(&request(dir, "j/devices").await?)?;
    }
    Ok(())
}

pub struct HyprlandCompositor {
    dir: PathBuf,
    mirror: Arc<Mirror>,
    task: tokio::task::JoinHandle<()>,
}

impl HyprlandCompositor {
    /// Start the event task for the instance directory `dir`. Must be called inside a tokio runtime; the task
    /// ends when the handle is dropped.
    pub fn spawn(dir: impl Into<PathBuf>) -> Self {
        let dir = dir.into();
        let mirror = Mirror::new();
        let (m, d) = (mirror.clone(), dir.clone());
        let task = tokio::spawn(async move {
            any::reconnect_loop(m.clone(), "hyprland", || session(d.clone(), m.clone())).await
        });
        HyprlandCompositor { dir, mirror, task }
    }
}

impl Drop for HyprlandCompositor {
    fn drop(&mut self) {
        self.task.abort();
    }
}

impl Compositor for HyprlandCompositor {
    async fn snapshot(&self) -> Result<CompositorState> {
        self.mirror.snapshot().await
    }

    fn events(&self) -> impl Stream<Item = Event> + Send + Unpin + 'static {
        self.mirror.events()
    }

    async fn act(&self, action: Action) -> Result<()> {
        act_at(&self.dir, &action).await
    }

    fn capabilities(&self) -> Capabilities {
        CAPABILITIES
    }
}

async fn session(dir: PathBuf, mirror: Arc<Mirror>) -> Result<()> {
    // Events first, then read: nothing that happens in between is missed.
    let events = UnixStream::connect(dir.join(EVENT_SOCKET))
        .await
        .map_err(io_err)?;
    let mut st = HyprState::default();
    fetch(&dir, &mut st, Dirty::ALL).await?;
    mirror.publish(st.project());

    let mut rd = BufReader::new(events);
    let mut line = String::new();
    loop {
        let mut dirty = Dirty::default();
        loop {
            line.clear();
            if rd.read_line(&mut line).await.map_err(io_err)? == 0 {
                return Err(Error::Unavailable("event socket closed".into()));
            }
            st.apply(line.trim_end_matches('\n'), &mut dirty);
            if rd.buffer().is_empty() {
                break;
            }
        }
        if dirty.refetch() {
            fetch(&dir, &mut st, dirty).await?;
        }
        if dirty.refetch() || dirty.touched {
            mirror.publish(st.project());
        }
    }
}

/// What an action becomes on Hyprland.
#[derive(Debug, Clone, PartialEq)]
pub enum Plan {
    /// A request whose reply is `ok`.
    Command(String),
    PowerOff,
    Shot(Shot),
}

fn workspace_arg(st: &HyprState, proj: &CompositorState, r: &WorkspaceRef) -> Result<String> {
    let arg = |w: &HWorkspace| {
        if w.id > 0 {
            w.id.to_string()
        } else {
            format!("name:{}", w.name)
        }
    };
    let by_id = |id: u64| {
        st.workspaces
            .iter()
            .find(|w| ws_id(w.id, &w.name) == Some(id))
    };
    match r {
        WorkspaceRef::Id(id) => match by_id(*id) {
            Some(w) => Ok(arg(w)),
            // A numbered workspace that does not exist yet: Hyprland makes it.
            None if (1..NAMED_BASE).contains(id) => Ok(id.to_string()),
            None => Err(Error::Rejected(format!("no workspace {id}"))),
        },
        WorkspaceRef::Idx(i) => {
            let focused = proj.outputs.iter().find(|o| o.focused).map(|o| &o.name);
            Ok(proj
                .workspaces
                .iter()
                .find(|w| w.idx == *i && w.output.as_ref() == focused)
                .and_then(|w| by_id(w.id))
                .map(arg)
                .unwrap_or_else(|| i.to_string()))
        }
    }
}

/// Translate a neutral action (also what the tests pin).
pub fn plan(action: &Action, st: &HyprState) -> Result<Plan> {
    let proj = st.project();
    let addr = |id: &u64| format!("address:0x{id:x}");
    Ok(Plan::Command(match action {
        Action::FocusWorkspace(r) => {
            format!("dispatch workspace {}", workspace_arg(st, &proj, r)?)
        }
        Action::FocusWindow(id) => format!("dispatch focuswindow {}", addr(id)),
        Action::CloseWindow(id) => format!("dispatch closewindow {}", addr(id)),
        // `movetoworkspace` follows the window (niri's `focus: true`); `…silent` would not.
        Action::MoveWindowToWorkspace {
            window_id,
            workspace,
        } => format!(
            "dispatch movetoworkspace {},{}",
            workspace_arg(st, &proj, workspace)?,
            addr(window_id)
        ),
        Action::ScrollColumn(Direction::Left) => "dispatch movefocus l".into(),
        Action::ScrollColumn(Direction::Right) => "dispatch movefocus r".into(),
        // `all`: every keyboard alike, as niri and Sway switch.
        Action::SwitchLayout(t) => format!(
            "switchxkblayout all {}",
            match t {
                LayoutTarget::Next => "next".to_string(),
                LayoutTarget::Prev => "prev".to_string(),
                LayoutTarget::Index(i) => i.to_string(),
            }
        ),
        Action::PowerOffMonitors => return Ok(Plan::PowerOff),
        Action::ScreenshotRegion => return Ok(Plan::Shot(Shot::Region)),
        Action::ScreenshotScreen => {
            let o = proj
                .outputs
                .iter()
                .find(|o| o.focused)
                .map(|o| o.name.clone());
            return Ok(Plan::Shot(Shot::Screen(o)));
        }
        Action::ScreenshotWindow => {
            let (x, y, w, h) = st
                .active_rect
                .ok_or_else(|| Error::Rejected("no focused window".into()))?;
            return Ok(Plan::Shot(Shot::Rect(x, y, w, h)));
        }
    }))
}

/// One action on its own request connection(s).
pub async fn act_at(dir: &Path, action: &Action) -> Result<()> {
    let needs = match action {
        Action::FocusWorkspace(_)
        | Action::MoveWindowToWorkspace { .. }
        | Action::ScreenshotScreen => Dirty {
            monitors: true,
            workspaces: true,
            ..Dirty::default()
        },
        Action::ScreenshotWindow => Dirty {
            active: true,
            ..Dirty::default()
        },
        _ => Dirty::default(),
    };
    let mut st = HyprState::default();
    fetch(dir, &mut st, needs).await?;
    match plan(action, &st)? {
        Plan::Command(cmd) => command(dir, &cmd).await,
        Plan::Shot(s) => any::external_screenshot(s).await,
        Plan::PowerOff => {
            let on_dir = dir.to_path_buf();
            any::power_off_until_input(command(dir, "dispatch dpms off"), async move {
                command(&on_dir, "dispatch dpms on").await
            })
            .await
        }
    }
}

/// The focused monitor's name.
pub async fn focused_output_at(dir: &Path) -> Result<Option<String>> {
    let mut st = HyprState::default();
    st.set_monitors(&request(dir, "j/monitors").await?)?;
    Ok(st.monitors.into_iter().find(|m| m.focused).map(|m| m.name))
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::{Value, json};
    use std::collections::HashMap;
    use std::sync::Mutex;
    use tokio::net::UnixListener;
    use tokio::sync::mpsc;
    use tokio_stream::StreamExt;

    /// A fake Hyprland instance directory: canned `j/…` replies, other requests recorded and answered `ok`;
    /// event lines pushed to every `.socket2.sock` connection, `drop_events` closes them (a restart).
    struct FakeHypr {
        replies: Arc<Mutex<HashMap<String, Value>>>,
        commands: Arc<Mutex<Vec<String>>>,
        subs: Arc<Mutex<Vec<mpsc::UnboundedSender<Option<String>>>>>,
    }

    impl FakeHypr {
        fn start(dir: &Path, replies: HashMap<String, Value>) -> FakeHypr {
            let fake = FakeHypr {
                replies: Arc::new(Mutex::new(replies)),
                commands: Arc::default(),
                subs: Arc::default(),
            };
            let req = UnixListener::bind(dir.join(REQUEST_SOCKET)).unwrap();
            let (replies, commands) = (fake.replies.clone(), fake.commands.clone());
            tokio::spawn(async move {
                loop {
                    let (mut s, _) = req.accept().await.unwrap();
                    let mut buf = vec![0u8; 4096];
                    let n = s.read(&mut buf).await.unwrap();
                    let cmd = String::from_utf8_lossy(&buf[..n]).to_string();
                    let reply = match cmd.strip_prefix("j/") {
                        Some(what) => replies
                            .lock()
                            .unwrap()
                            .get(what)
                            .cloned()
                            .unwrap_or(json!([]))
                            .to_string(),
                        None => {
                            commands.lock().unwrap().push(cmd);
                            "ok".into()
                        }
                    };
                    let _ = s.write_all(reply.as_bytes()).await;
                }
            });
            let ev = UnixListener::bind(dir.join(EVENT_SOCKET)).unwrap();
            let subs = fake.subs.clone();
            tokio::spawn(async move {
                loop {
                    let (mut s, _) = ev.accept().await.unwrap();
                    let (tx, mut rx) = mpsc::unbounded_channel::<Option<String>>();
                    subs.lock().unwrap().push(tx);
                    tokio::spawn(async move {
                        while let Some(Some(line)) = rx.recv().await {
                            if s.write_all(line.as_bytes()).await.is_err() {
                                return;
                            }
                        }
                    });
                }
            });
            fake
        }

        fn set(&self, what: &str, v: Value) {
            self.replies.lock().unwrap().insert(what.into(), v);
        }

        /// Several lines in one write, as Hyprland sends a burst.
        fn push(&self, lines: &[&str]) {
            let text: String = lines.iter().map(|l| format!("{l}\n")).collect();
            for s in self.subs.lock().unwrap().iter() {
                let _ = s.send(Some(text.clone()));
            }
        }

        fn drop_events(&self) {
            for s in self.subs.lock().unwrap().drain(..) {
                let _ = s.send(None);
            }
        }

        fn commands(&self) -> Vec<String> {
            self.commands.lock().unwrap().clone()
        }
    }

    fn monitors(active: i64) -> Value {
        json!([
            {"id": 0, "name": "DP-1", "make": "Dell", "model": "U2720Q", "x": 0, "y": 0, "width": 3840,
             "height": 2160, "scale": 1.5, "transform": 0, "focused": true, "disabled": false,
             "activeWorkspace": {"id": active, "name": active.to_string()}, "specialWorkspace": {"id": 0, "name": ""}},
            {"id": 1, "name": "HDMI-A-1", "make": "LG", "model": "x", "x": 2560, "y": 0, "width": 1920,
             "height": 1080, "scale": 1.0, "transform": 1, "focused": false, "disabled": false,
             "activeWorkspace": {"id": -1337, "name": "mail"}}
        ])
    }

    fn workspaces() -> Value {
        json!([
            {"id": 1, "name": "1", "monitor": "DP-1", "windows": 2},
            {"id": 3, "name": "3", "monitor": "DP-1", "windows": 0},
            {"id": -1337, "name": "mail", "monitor": "HDMI-A-1", "windows": 0},
            {"id": -98, "name": "special:term", "monitor": "DP-1", "windows": 1}
        ])
    }

    fn clients() -> Value {
        json!([
            {"address": "0x55aa10", "mapped": true, "workspace": {"id": 1, "name": "1"}, "floating": false,
             "class": "foot", "initialClass": "foot", "title": "~", "at": [10, 20], "size": [800, 600]},
            {"address": "0x55aa20", "mapped": true, "workspace": {"id": 1, "name": "1"}, "floating": true,
             "class": "", "initialClass": "org.app", "title": "app"},
            {"address": "0x55aa30", "mapped": true, "workspace": {"id": -98, "name": "special:term"},
             "floating": false, "class": "kitty", "title": "scratch"},
            {"address": "0x55aa40", "mapped": false, "workspace": {"id": 1, "name": "1"}, "class": "ghost"}
        ])
    }

    fn devices(layout: Option<usize>) -> Value {
        json!({"mice": [], "keyboards": [
            {"name": "virtual", "layout": "us", "variant": "", "active_keymap": "English (US)", "main": false},
            {"name": "at-kbd", "layout": "us,de", "variant": ",neo", "active_keymap": "German (Neo 2)",
             "active_layout_index": layout, "main": true}
        ]})
    }

    fn replies() -> HashMap<String, Value> {
        HashMap::from([
            ("monitors".into(), monitors(1)),
            ("workspaces".into(), workspaces()),
            ("clients".into(), clients()),
            (
                "activewindow".into(),
                json!({"address": "0x55aa10", "at": [10, 20], "size": [800, 600]}),
            ),
            ("devices".into(), devices(Some(0))),
        ])
    }

    fn state() -> HyprState {
        let mut st = HyprState::default();
        let r = replies();
        st.set_monitors(&r["monitors"].to_string()).unwrap();
        st.set_workspaces(&r["workspaces"].to_string()).unwrap();
        st.set_clients(&r["clients"].to_string()).unwrap();
        st.set_active_window(&r["activewindow"].to_string())
            .unwrap();
        st.set_devices(&r["devices"].to_string()).unwrap();
        st
    }

    #[test]
    fn instance_dir_prefers_the_runtime_dir() {
        let rt = tempfile::tempdir().unwrap();
        let sig = OsStr::new("sig123");
        let new = rt.path().join("hypr/sig123");
        // Neither socket exists: the current layout.
        assert_eq!(instance_dir(sig, Some(rt.path().into())), new);
        std::fs::create_dir_all(&new).unwrap();
        std::fs::write(new.join(REQUEST_SOCKET), "").unwrap();
        assert_eq!(instance_dir(sig, Some(rt.path().into())), new);
        assert_eq!(instance_dir(sig, None), Path::new("/tmp/hypr/sig123"));
    }

    #[test]
    fn projects_global_workspaces_onto_their_monitors() {
        let s = state().project();
        let outs: Vec<_> = s
            .outputs
            .iter()
            .map(|o| (o.name.as_str(), o.logical, o.focused))
            .collect();
        assert_eq!(
            outs,
            [
                ("DP-1", (0, 0, 2560, 1440), true),
                ("HDMI-A-1", (2560, 0, 1080, 1920), false)
            ],
            "logical size: scaled, and swapped when rotated"
        );
        let ws: Vec<_> = s
            .workspaces
            .iter()
            .map(|w| {
                (
                    w.id,
                    w.idx,
                    w.output.as_deref().unwrap(),
                    w.focused,
                    w.active,
                    w.occupied,
                )
            })
            .collect();
        assert_eq!(
            ws,
            [
                (1, 1, "DP-1", true, true, true),
                (3, 3, "DP-1", false, false, false),
                (NAMED_BASE + 1337, 1, "HDMI-A-1", false, true, false),
            ],
            "special workspaces are none; a named one shows where it lives"
        );
        let win: Vec<_> = s
            .windows
            .iter()
            .map(|w| {
                (
                    w.id,
                    w.app_id.as_deref(),
                    w.workspace_id,
                    w.focused,
                    w.floating,
                )
            })
            .collect();
        assert_eq!(
            win,
            [
                (0x55aa10, Some("foot"), Some(1), true, false),
                (0x55aa20, Some("org.app"), Some(1), false, true),
                (0x55aa30, Some("kitty"), None, false, false),
            ],
            "unmapped clients are no windows"
        );
        assert_eq!(
            s.keyboard,
            Some(KeyboardLayouts {
                names: vec!["English (US)".into(), "German (neo)".into()],
                current: 0
            }),
            "the main keyboard; codes named as XKB names them"
        );
        // Without an index (older Hyprland): the active keymap's base name.
        let mut st = state();
        st.set_devices(&devices(None).to_string()).unwrap();
        assert_eq!(st.keyboard.unwrap().current, 1);
    }

    #[test]
    fn events_apply_in_place_or_mark_stale() {
        let mut st = state();
        let mut d = Dirty::default();
        st.apply("urgent>>55aa20", &mut d);
        st.apply("windowtitlev2>>55aa10,vim, the editor", &mut d);
        assert!(d.touched && !d.refetch());
        let s = st.project();
        assert!(s.workspaces[0].urgent);
        assert_eq!(s.windows[0].title.as_deref(), Some("vim, the editor"));
        st.apply("activewindowv2>>55aa20", &mut d);
        let s = st.project();
        assert!(!s.workspaces[0].urgent, "focus clears urgency");
        assert!(s.windows[1].focused && !s.windows[0].focused);
        st.apply("activewindowv2>>", &mut d);
        assert!(st.project().windows.iter().all(|w| !w.focused));

        let mut d = Dirty::default();
        st.apply("workspacev2>>3,3", &mut d);
        assert!(d.monitors && d.workspaces && !d.clients);
        st.apply("openwindow>>55aa50,1,foot,~", &mut d);
        assert!(d.clients);
        let mut d = Dirty::default();
        st.apply("activelayout>>at-kbd,German", &mut d);
        assert_eq!(
            d,
            Dirty {
                devices: true,
                ..Dirty::default()
            }
        );
        st.apply("nonsense", &mut d);
        st.apply("screencast>>1,0", &mut d);
        assert_eq!(
            d,
            Dirty {
                devices: true,
                ..Dirty::default()
            }
        );
    }

    #[test]
    fn actions_become_hyprland_requests() {
        let st = state();
        let cmd = |a: Action| match plan(&a, &st).unwrap() {
            Plan::Command(c) => c,
            other => panic!("{other:?}"),
        };
        assert_eq!(
            cmd(Action::FocusWorkspace(WorkspaceRef::Idx(3))),
            "dispatch workspace 3"
        );
        assert_eq!(
            cmd(Action::FocusWorkspace(WorkspaceRef::Idx(7))),
            "dispatch workspace 7"
        );
        assert_eq!(
            cmd(Action::FocusWorkspace(WorkspaceRef::Id(NAMED_BASE + 1337))),
            "dispatch workspace name:mail"
        );
        assert_eq!(
            cmd(Action::FocusWorkspace(WorkspaceRef::Id(5))),
            "dispatch workspace 5"
        );
        assert!(
            plan(
                &Action::FocusWorkspace(WorkspaceRef::Id(NAMED_BASE + 1)),
                &st
            )
            .is_err()
        );
        assert_eq!(
            cmd(Action::FocusWindow(0x55aa20)),
            "dispatch focuswindow address:0x55aa20"
        );
        assert_eq!(
            cmd(Action::CloseWindow(0x55aa20)),
            "dispatch closewindow address:0x55aa20"
        );
        assert_eq!(
            cmd(Action::MoveWindowToWorkspace {
                window_id: 0x55aa10,
                workspace: WorkspaceRef::Idx(3)
            }),
            "dispatch movetoworkspace 3,address:0x55aa10"
        );
        assert_eq!(
            cmd(Action::ScrollColumn(Direction::Right)),
            "dispatch movefocus r"
        );
        assert_eq!(
            cmd(Action::SwitchLayout(LayoutTarget::Index(1))),
            "switchxkblayout all 1"
        );
        assert_eq!(
            plan(&Action::PowerOffMonitors, &st).unwrap(),
            Plan::PowerOff
        );
        assert_eq!(
            plan(&Action::ScreenshotWindow, &st).unwrap(),
            Plan::Shot(Shot::Rect(10, 20, 800, 600))
        );
        assert_eq!(
            plan(&Action::ScreenshotScreen, &st).unwrap(),
            Plan::Shot(Shot::Screen(Some("DP-1".into())))
        );
    }

    async fn next(ev: &mut (impl Stream<Item = Event> + Unpin)) -> Event {
        tokio::time::timeout(std::time::Duration::from_secs(5), ev.next())
            .await
            .expect("an event")
            .unwrap()
    }

    #[tokio::test]
    async fn fake_sockets_snapshot_events_actions_and_reconnect() {
        let dir = tempfile::tempdir().unwrap();
        let fake = FakeHypr::start(dir.path(), replies());
        let hypr = HyprlandCompositor::spawn(dir.path());
        let mut ev = hypr.events();
        assert_eq!(hypr.snapshot().await.unwrap(), state().project());

        // A burst for one switch: read whole, re-read once, one Workspaces event.
        fake.set("monitors", monitors(3));
        fake.push(&["workspace>>3", "workspacev2>>3,3", "focusedmon>>DP-1,3"]);
        match next(&mut ev).await {
            Event::Workspaces(w) => assert!(w.iter().any(|w| w.id == 3 && w.focused)),
            other => panic!("{other:?}"),
        }
        // Focus in place, no request.
        fake.push(&["activewindowv2>>55aa20"]);
        match next(&mut ev).await {
            Event::Windows(w) => assert!(w[1].focused),
            other => panic!("{other:?}"),
        }
        fake.set("devices", devices(Some(1)));
        fake.push(&["activelayout>>at-kbd,German (Neo 2)"]);
        match next(&mut ev).await {
            Event::Keyboard(Some(k)) => assert_eq!(k.current, 1),
            other => panic!("{other:?}"),
        }

        hypr.act(Action::FocusWorkspace(WorkspaceRef::Idx(1)))
            .await
            .unwrap();
        hypr.act(Action::CloseWindow(0x55aa10)).await.unwrap();
        hypr.act(Action::SwitchLayout(LayoutTarget::Next))
            .await
            .unwrap();
        assert_eq!(
            fake.commands(),
            [
                "dispatch workspace 1",
                "dispatch closewindow address:0x55aa10",
                "switchxkblayout all next"
            ]
        );
        assert_eq!(
            focused_output_at(dir.path()).await.unwrap().as_deref(),
            Some("DP-1")
        );

        // Hyprland restarts: Resync, then a fresh snapshot.
        fake.set("monitors", monitors(1));
        fake.drop_events();
        assert_eq!(next(&mut ev).await, Event::Resync);
        let again = hypr.snapshot().await.unwrap();
        assert!(again.workspaces.iter().any(|w| w.id == 1 && w.focused));
    }

    #[tokio::test]
    async fn a_refusal_carries_hyprlands_reply() {
        let dir = tempfile::tempdir().unwrap();
        let l = UnixListener::bind(dir.path().join(REQUEST_SOCKET)).unwrap();
        tokio::spawn(async move {
            let (mut s, _) = l.accept().await.unwrap();
            let mut b = [0u8; 256];
            let _ = s.read(&mut b).await;
            s.write_all(b"Invalid dispatcher").await.unwrap();
        });
        let err = act_at(dir.path(), &Action::FocusWindow(1))
            .await
            .unwrap_err();
        assert!(
            matches!(err, Error::Rejected(ref e) if e == "Invalid dispatcher"),
            "{err:?}"
        );
    }
}
