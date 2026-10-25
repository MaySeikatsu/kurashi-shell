//! Sway adapter (i3-IPC on `$SWAYSOCK`, sway-ipc(7)), hand-written framing: `"i3-ipc"`, payload length and type
//! as native-endian u32, then the JSON payload. No crate: `swayipc-async` is not vendored, and the framing is
//! twenty lines.
//!
//! One connection subscribes to `workspace`, `window`, `output` and `input` events; a second, kept for the
//! session, re-reads only the domains an event touched (workspaces and the tree on a workspace event, the tree
//! on a window event, outputs on an output event, inputs on an input event; a title change is applied in place).
//! Events that arrive together are read before anything is re-read, so a burst costs one round. Nothing polls.
//!
//! Readings (ARCHITECTURE §7): window ids are container ids; `app_id`, or the X11 `window_properties.class`;
//! a workspace's `idx` is its `num` (1..=255; unnumbered ones follow the highest number on their output), so
//! `workspace.focus {idx: 3}` is `workspace number 3` as in the user's own bindings. Sway has no overview, no
//! scroll position and no screenshots of its own (`grim`/`slurp`, see [`crate::any::external_screenshot`]);
//! `output * power off` stays off until told, so screens come back through the wake guard.

use std::{
    collections::{BTreeSet, HashMap},
    path::{Path, PathBuf},
    sync::Arc,
};

use serde::Deserialize;
use serde_json::Value;
use tokio::{
    io::{AsyncRead, AsyncReadExt, AsyncWrite, AsyncWriteExt, BufReader},
    net::UnixStream,
};
use tokio_stream::Stream;

use crate::{
    Action, Capabilities, Compositor, CompositorState, Direction, Error, Event, KeyboardLayouts,
    LayoutTarget, Output, Result, Window, Workspace, WorkspaceRef,
    any::{self, Mirror, Shot, io_err},
};

pub const CAPABILITIES: Capabilities = Capabilities {
    scroll_position: false,
    overview: false,
    window_previews: false,
    blur_hint: false,
    workspace_names: true,
};

const MAGIC: &[u8; 6] = b"i3-ipc";
pub const RUN_COMMAND: u32 = 0;
pub const GET_WORKSPACES: u32 = 1;
pub const SUBSCRIBE: u32 = 2;
pub const GET_OUTPUTS: u32 = 3;
pub const GET_TREE: u32 = 4;
pub const GET_INPUTS: u32 = 100;
/// Event types carry the high bit.
pub const EVENT_WORKSPACE: u32 = 0x8000_0000;
pub const EVENT_OUTPUT: u32 = 0x8000_0001;
pub const EVENT_WINDOW: u32 = 0x8000_0003;
pub const EVENT_SHUTDOWN: u32 = 0x8000_0006;
pub const EVENT_INPUT: u32 = 0x8000_0015;
pub const SUBSCRIPTION: &str = r#"["workspace","window","output","input"]"#;

pub async fn write_msg(
    w: &mut (impl AsyncWrite + Unpin),
    ty: u32,
    payload: &[u8],
) -> std::io::Result<()> {
    let mut buf = Vec::with_capacity(14 + payload.len());
    buf.extend_from_slice(MAGIC);
    buf.extend_from_slice(&(payload.len() as u32).to_ne_bytes());
    buf.extend_from_slice(&ty.to_ne_bytes());
    buf.extend_from_slice(payload);
    w.write_all(&buf).await
}

pub async fn read_msg(r: &mut (impl AsyncRead + Unpin)) -> std::io::Result<(u32, Vec<u8>)> {
    let mut head = [0u8; 14];
    r.read_exact(&mut head).await?;
    if &head[..6] != MAGIC {
        return Err(std::io::Error::new(
            std::io::ErrorKind::InvalidData,
            "not an i3-ipc message",
        ));
    }
    let len = u32::from_ne_bytes(head[6..10].try_into().unwrap()) as usize;
    let ty = u32::from_ne_bytes(head[10..14].try_into().unwrap());
    let mut body = vec![0u8; len];
    r.read_exact(&mut body).await?;
    Ok((ty, body))
}

#[derive(Debug, Clone, Copy, Default, Deserialize)]
#[serde(default)]
struct Rect {
    x: i32,
    y: i32,
    width: i64,
    height: i64,
}

#[derive(Debug, Clone, Default, Deserialize)]
#[serde(default)]
struct SwayOutput {
    name: String,
    make: String,
    model: String,
    active: bool,
    rect: Rect,
    scale: f64,
    focused: bool,
}

#[derive(Debug, Clone, Default, Deserialize)]
#[serde(default)]
struct SwayWorkspace {
    id: u64,
    num: i64,
    name: String,
    visible: bool,
    focused: bool,
    urgent: bool,
    output: String,
}

#[derive(Debug, Clone, Default, Deserialize)]
#[serde(default)]
struct SwayInput {
    #[serde(rename = "type")]
    kind: String,
    xkb_layout_names: Vec<Option<String>>,
    xkb_active_layout_index: Option<usize>,
}

/// A view (window) from the tree.
#[derive(Debug, Clone, PartialEq)]
struct TreeWindow {
    id: u64,
    app_id: Option<String>,
    title: Option<String>,
    workspace_id: Option<u64>,
    focused: bool,
    floating: bool,
    urgent: bool,
    rect: (i32, i32, u32, u32),
}

/// Sway's replies as last read, projected into neutral types. Pure: tests feed it recorded replies.
#[derive(Debug, Default)]
pub struct SwayState {
    outputs: Vec<SwayOutput>,
    workspaces: Vec<SwayWorkspace>,
    windows: Vec<TreeWindow>,
    keyboard: Option<KeyboardLayouts>,
}

fn parse<T: for<'de> Deserialize<'de>>(body: &[u8]) -> Result<T> {
    serde_json::from_slice(body).map_err(|e| Error::Protocol(e.to_string()))
}

impl SwayState {
    pub fn set_outputs(&mut self, body: &[u8]) -> Result<()> {
        self.outputs = parse(body)?;
        Ok(())
    }

    pub fn set_workspaces(&mut self, body: &[u8]) -> Result<()> {
        self.workspaces = parse(body)?;
        Ok(())
    }

    pub fn set_tree(&mut self, body: &[u8]) -> Result<()> {
        let tree: Value = parse(body)?;
        self.windows.clear();
        walk(&tree, None, false, &mut self.windows);
        Ok(())
    }

    /// The first keyboard that names all its layouts (sway configures every keyboard alike unless told
    /// otherwise). A virtual keyboard brings its own keymap, whose layouts sway reports as `null`: it is skipped.
    pub fn set_inputs(&mut self, body: &[u8]) -> Result<()> {
        // Layouts are not worth the session: an input list we cannot read shows none.
        let inputs: Vec<SwayInput> = parse(body).unwrap_or_else(|e| {
            tracing::warn!("sway inputs unreadable: {e}");
            Vec::new()
        });
        self.keyboard = inputs.into_iter().find_map(|i| {
            let names: Option<Vec<String>> = i.xkb_layout_names.into_iter().collect();
            match names {
                Some(names) if i.kind == "keyboard" && !names.is_empty() => Some(KeyboardLayouts {
                    current: i.xkb_active_layout_index.unwrap_or(0).min(names.len() - 1),
                    names,
                }),
                _ => None,
            }
        });
        Ok(())
    }

    /// A `window` event with change `title`: the new title, without re-reading the tree.
    fn retitle(&mut self, body: &[u8]) -> bool {
        let Ok(ev) = serde_json::from_slice::<Value>(body) else {
            return false;
        };
        let (Some(id), title) = (
            ev["container"]["id"].as_u64(),
            ev["container"]["name"].as_str().map(String::from),
        ) else {
            return false;
        };
        match self.windows.iter_mut().find(|w| w.id == id) {
            Some(w) => {
                w.title = title;
                true
            }
            None => false,
        }
    }

    fn focused_window_rect(&self) -> Option<(i32, i32, u32, u32)> {
        self.windows.iter().find(|w| w.focused).map(|w| w.rect)
    }

    pub fn project(&self) -> CompositorState {
        let focused_output = self
            .workspaces
            .iter()
            .find(|w| w.focused)
            .map(|w| w.output.as_str());
        let mut outputs: Vec<Output> = self
            .outputs
            .iter()
            .filter(|o| o.active)
            .map(|o| Output {
                name: o.name.clone(),
                make: o.make.clone(),
                model: o.model.clone(),
                logical: (
                    o.rect.x,
                    o.rect.y,
                    o.rect.width.max(0) as u32,
                    o.rect.height.max(0) as u32,
                ),
                scale: if o.scale > 0.0 { o.scale } else { 1.0 },
                focused: match focused_output {
                    Some(f) => f == o.name,
                    None => o.focused,
                },
            })
            .collect();
        outputs.sort_by(|a, b| a.name.cmp(&b.name));

        let occupied: BTreeSet<u64> = self.windows.iter().filter_map(|w| w.workspace_id).collect();
        let idx = indices(
            self.workspaces
                .iter()
                .map(|w| (w.id, w.output.as_str(), w.num)),
        );
        let mut workspaces: Vec<Workspace> = self
            .workspaces
            .iter()
            .map(|w| Workspace {
                id: w.id,
                idx: idx[&w.id],
                name: Some(w.name.clone()),
                output: Some(w.output.clone()),
                focused: w.focused,
                active: w.visible,
                occupied: occupied.contains(&w.id),
                urgent: w.urgent,
            })
            .collect();
        workspaces.sort_by(|a, b| (&a.output, a.idx, a.id).cmp(&(&b.output, b.idx, b.id)));

        let mut windows: Vec<Window> = self
            .windows
            .iter()
            .map(|w| Window {
                id: w.id,
                app_id: w.app_id.clone(),
                title: w.title.clone(),
                workspace_id: w.workspace_id,
                focused: w.focused,
                floating: w.floating,
                urgent: w.urgent,
            })
            .collect();
        windows.sort_by_key(|w| w.id);

        CompositorState {
            outputs,
            workspaces,
            windows,
            overview_open: false,
            keyboard: self.keyboard.clone(),
        }
    }
}

/// `idx` per workspace id: its number when 1..=255, else after the highest number on its output, in list order.
pub(crate) fn indices<'a>(
    list: impl Iterator<Item = (u64, &'a str, i64)> + Clone,
) -> HashMap<u64, u8> {
    let mut next: HashMap<&str, u16> = HashMap::new();
    for (_, out, num) in list.clone() {
        if (1..=255).contains(&num) {
            let n = next.entry(out).or_insert(1);
            *n = (*n).max(num as u16 + 1);
        }
    }
    let mut map = HashMap::new();
    for (id, out, num) in list {
        let idx = if (1..=255).contains(&num) {
            num as u8
        } else {
            let n = next.entry(out).or_insert(1);
            let v = (*n).min(255) as u8;
            *n += 1;
            v
        };
        map.insert(id, idx);
    }
    map
}

/// Collect views under `node`. `workspace`: the enclosing workspace's id (`None` in the scratchpad).
fn walk(node: &Value, workspace: Option<u64>, floating: bool, out: &mut Vec<TreeWindow>) {
    let kind = node["type"].as_str().unwrap_or_default();
    let ws = match kind {
        "workspace" if node["name"].as_str() == Some("__i3_scratch") => None,
        "workspace" => node["id"].as_u64(),
        _ => workspace,
    };
    let children = |key: &str| node[key].as_array().cloned().unwrap_or_default();
    let (nodes, floats) = (children("nodes"), children("floating_nodes"));
    let is_view = matches!(kind, "con" | "floating_con")
        && nodes.is_empty()
        && (node.get("pid").is_some_and(|p| !p.is_null()) || node.get("shell").is_some());
    if is_view && let Some(id) = node["id"].as_u64() {
        let app_id = node["app_id"]
            .as_str()
            .or_else(|| node["window_properties"]["class"].as_str())
            .filter(|s| !s.is_empty())
            .map(String::from);
        let r: Rect = serde_json::from_value(node["rect"].clone()).unwrap_or_default();
        out.push(TreeWindow {
            id,
            app_id,
            title: node["name"].as_str().map(String::from),
            workspace_id: ws,
            focused: node["focused"].as_bool().unwrap_or(false),
            floating: floating || kind == "floating_con",
            urgent: node["urgent"].as_bool().unwrap_or(false),
            rect: (r.x, r.y, r.width.max(0) as u32, r.height.max(0) as u32),
        });
    }
    for n in &nodes {
        walk(n, ws, floating, out);
    }
    for n in &floats {
        walk(n, ws, true, out);
    }
}

/// A request connection (i3-IPC answers requests in order on one connection).
pub struct Conn(UnixStream);

impl Conn {
    pub async fn connect(path: &Path) -> Result<Self> {
        UnixStream::connect(path).await.map(Conn).map_err(io_err)
    }

    pub async fn request(&mut self, ty: u32, payload: &[u8]) -> Result<Vec<u8>> {
        let io = async {
            write_msg(&mut self.0, ty, payload).await?;
            read_msg(&mut self.0).await
        };
        let (rty, body) = tokio::time::timeout(any::REQUEST_TIMEOUT, io)
            .await
            .map_err(|_| Error::Unavailable("sway did not answer".into()))?
            .map_err(io_err)?;
        if rty != ty {
            return Err(Error::Protocol(format!("reply type {rty} to request {ty}")));
        }
        Ok(body)
    }

    /// A command; any failed part is a rejection with sway's own error text.
    pub async fn run(&mut self, command: &str) -> Result<()> {
        let body = self.request(RUN_COMMAND, command.as_bytes()).await?;
        let replies: Vec<Value> = parse(&body)?;
        match replies.iter().find(|r| r["success"] != Value::Bool(true)) {
            Some(r) => Err(Error::Rejected(
                r["error"].as_str().unwrap_or("command failed").to_string(),
            )),
            None => Ok(()),
        }
    }

    async fn fetch(&mut self, st: &mut SwayState, d: Dirty) -> Result<()> {
        if d.outputs {
            st.set_outputs(&self.request(GET_OUTPUTS, b"").await?)?;
        }
        if d.workspaces {
            st.set_workspaces(&self.request(GET_WORKSPACES, b"").await?)?;
        }
        if d.tree {
            st.set_tree(&self.request(GET_TREE, b"").await?)?;
        }
        if d.inputs {
            st.set_inputs(&self.request(GET_INPUTS, b"").await?)?;
        }
        Ok(())
    }
}

#[derive(Debug, Default, Clone, Copy, PartialEq)]
struct Dirty {
    outputs: bool,
    workspaces: bool,
    tree: bool,
    inputs: bool,
    /// Something changed in place (a title).
    touched: bool,
}

impl Dirty {
    const ALL: Dirty = Dirty {
        outputs: true,
        workspaces: true,
        tree: true,
        inputs: true,
        touched: false,
    };

    fn any(&self) -> bool {
        self.outputs || self.workspaces || self.tree || self.inputs || self.touched
    }
}

/// What a sway event makes stale.
fn classify(ty: u32, body: &[u8], st: &mut SwayState, d: &mut Dirty) -> Result<()> {
    match ty {
        EVENT_WORKSPACE => {
            d.workspaces = true;
            d.tree = true; // focus moves with the workspace (an empty one has no focused view)
        }
        EVENT_OUTPUT => {
            d.outputs = true;
            d.workspaces = true;
        }
        EVENT_WINDOW => {
            let change = serde_json::from_slice::<Value>(body)
                .ok()
                .and_then(|v| v["change"].as_str().map(String::from));
            if change.as_deref() == Some("title") && !d.tree && st.retitle(body) {
                d.touched = true;
            } else if change.as_deref() != Some("mark") {
                d.tree = true;
            }
        }
        EVENT_INPUT => d.inputs = true,
        EVENT_SHUTDOWN => return Err(Error::Unavailable("sway is shutting down".into())),
        _ => {}
    }
    Ok(())
}

pub struct SwayCompositor {
    path: PathBuf,
    mirror: Arc<Mirror>,
    task: tokio::task::JoinHandle<()>,
}

impl SwayCompositor {
    /// Start the event task for the socket at `path`. Must be called inside a tokio runtime; the task ends when
    /// the handle is dropped.
    pub fn spawn(path: impl Into<PathBuf>) -> Self {
        let path = path.into();
        let mirror = Mirror::new();
        let (m, p) = (mirror.clone(), path.clone());
        let task = tokio::spawn(async move {
            any::reconnect_loop(m.clone(), "sway", || session(p.clone(), m.clone())).await
        });
        SwayCompositor { path, mirror, task }
    }
}

impl Drop for SwayCompositor {
    fn drop(&mut self) {
        self.task.abort();
    }
}

impl Compositor for SwayCompositor {
    async fn snapshot(&self) -> Result<CompositorState> {
        self.mirror.snapshot().await
    }

    fn events(&self) -> impl Stream<Item = Event> + Send + Unpin + 'static {
        self.mirror.events()
    }

    async fn act(&self, action: Action) -> Result<()> {
        act_at(&self.path, &action).await
    }

    fn capabilities(&self) -> Capabilities {
        CAPABILITIES
    }
}

async fn session(path: PathBuf, mirror: Arc<Mirror>) -> Result<()> {
    let mut events = UnixStream::connect(&path).await.map_err(io_err)?;
    write_msg(&mut events, SUBSCRIBE, SUBSCRIPTION.as_bytes())
        .await
        .map_err(io_err)?;
    let (_, reply) = read_msg(&mut events).await.map_err(io_err)?;
    let reply: Value = parse(&reply)?;
    if reply["success"] != Value::Bool(true) {
        return Err(Error::Rejected(format!("subscribe refused: {reply}")));
    }
    // Subscribed first, then read: nothing that happens in between is missed.
    let mut req = Conn::connect(&path).await?;
    let mut st = SwayState::default();
    req.fetch(&mut st, Dirty::ALL).await?;
    mirror.publish(st.project());

    let mut rd = BufReader::new(events);
    loop {
        let mut dirty = Dirty::default();
        loop {
            let (ty, body) = read_msg(&mut rd).await.map_err(io_err)?;
            classify(ty, &body, &mut st, &mut dirty)?;
            if rd.buffer().is_empty() {
                break;
            }
        }
        if dirty.any() {
            req.fetch(&mut st, dirty).await?;
            mirror.publish(st.project());
        }
    }
}

/// What an action becomes on sway.
#[derive(Debug, Clone, PartialEq)]
pub enum Plan {
    Command(String),
    PowerOff,
    Shot(Shot),
}

/// A sway string argument, quoted.
fn quote(s: &str) -> String {
    format!("\"{}\"", s.replace('\\', "\\\\").replace('"', "\\\""))
}

fn workspace_arg(st: &CompositorState, r: &WorkspaceRef) -> Result<String> {
    match r {
        WorkspaceRef::Id(id) => st
            .workspaces
            .iter()
            .find(|w| w.id == *id)
            .and_then(|w| w.name.as_deref())
            .map(quote)
            .ok_or_else(|| Error::Rejected(format!("no workspace {id}"))),
        WorkspaceRef::Idx(i) => {
            let focused = st.outputs.iter().find(|o| o.focused).map(|o| &o.name);
            Ok(st
                .workspaces
                .iter()
                .find(|w| w.idx == *i && w.output.as_ref() == focused)
                .and_then(|w| w.name.as_deref())
                .map(quote)
                // Not there yet: sway makes it, as `workspace number N` in a binding does.
                .unwrap_or_else(|| format!("number {i}")))
        }
    }
}

/// Translate a neutral action (also what the tests pin). `st`: the state, for workspace references; `window`: the
/// focused window's rectangle, for its screenshot.
pub fn plan(
    action: &Action,
    st: &CompositorState,
    window: Option<(i32, i32, u32, u32)>,
) -> Result<Plan> {
    Ok(Plan::Command(match action {
        Action::FocusWorkspace(r) => format!("workspace {}", workspace_arg(st, r)?),
        Action::FocusWindow(id) => format!("[con_id={id}] focus"),
        Action::CloseWindow(id) => format!("[con_id={id}] kill"),
        // niri's `focus: true`: the focus follows the window.
        Action::MoveWindowToWorkspace {
            window_id,
            workspace,
        } => format!(
            "[con_id={window_id}] move container to workspace {}; [con_id={window_id}] focus",
            workspace_arg(st, workspace)?
        ),
        Action::ScrollColumn(Direction::Left) => "focus left".into(),
        Action::ScrollColumn(Direction::Right) => "focus right".into(),
        Action::SwitchLayout(t) => format!(
            "input type:keyboard xkb_switch_layout {}",
            match t {
                LayoutTarget::Next => "next".to_string(),
                LayoutTarget::Prev => "prev".to_string(),
                LayoutTarget::Index(i) => i.to_string(),
            }
        ),
        Action::PowerOffMonitors => return Ok(Plan::PowerOff),
        Action::ScreenshotRegion => return Ok(Plan::Shot(Shot::Region)),
        Action::ScreenshotScreen => {
            let o = st
                .outputs
                .iter()
                .find(|o| o.focused)
                .map(|o| o.name.clone());
            return Ok(Plan::Shot(Shot::Screen(o)));
        }
        Action::ScreenshotWindow => {
            let (x, y, w, h) = window.ok_or_else(|| Error::Rejected("no focused window".into()))?;
            return Ok(Plan::Shot(Shot::Rect(x, y, w, h)));
        }
    }))
}

/// One action on its own request connection.
pub async fn act_at(path: &Path, action: &Action) -> Result<()> {
    let mut c = Conn::connect(path).await?;
    let needs = match action {
        Action::FocusWorkspace(_) | Action::MoveWindowToWorkspace { .. } => Dirty {
            outputs: true,
            workspaces: true,
            ..Dirty::default()
        },
        Action::ScreenshotScreen => Dirty {
            outputs: true,
            workspaces: true,
            ..Dirty::default()
        },
        Action::ScreenshotWindow => Dirty {
            tree: true,
            ..Dirty::default()
        },
        _ => Dirty::default(),
    };
    let mut st = SwayState::default();
    c.fetch(&mut st, needs).await?;
    match plan(action, &st.project(), st.focused_window_rect())? {
        Plan::Command(cmd) => c.run(&cmd).await,
        Plan::Shot(s) => any::external_screenshot(s).await,
        Plan::PowerOff => {
            let on_path = path.to_path_buf();
            any::power_off_until_input(c.run("output * power off"), async move {
                Conn::connect(&on_path)
                    .await?
                    .run("output * power on")
                    .await
            })
            .await
        }
    }
}

/// The focused output's name.
pub async fn focused_output_at(path: &Path) -> Result<Option<String>> {
    let mut c = Conn::connect(path).await?;
    let mut st = SwayState::default();
    st.set_outputs(&c.request(GET_OUTPUTS, b"").await?)?;
    Ok(st
        .outputs
        .into_iter()
        .find(|o| o.active && o.focused)
        .map(|o| o.name))
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;
    use std::sync::Mutex;
    use tokio::net::UnixListener;
    use tokio::sync::mpsc;
    use tokio_stream::StreamExt;

    /// A fake sway: canned replies per request type, RUN_COMMAND payloads recorded, events pushed to the
    /// subscribed connection; `drop_events` closes it (a sway restart).
    /// The subscribed connections' senders; `None` closes one.
    type Subs = Arc<Mutex<Vec<mpsc::UnboundedSender<Option<(u32, Value)>>>>>;

    struct FakeSway {
        replies: Arc<Mutex<HashMap<u32, Value>>>,
        commands: Arc<Mutex<Vec<String>>>,
        subs: Subs,
    }

    impl FakeSway {
        fn start(path: &Path, replies: HashMap<u32, Value>) -> FakeSway {
            let fake = FakeSway {
                replies: Arc::new(Mutex::new(replies)),
                commands: Arc::default(),
                subs: Arc::default(),
            };
            let listener = UnixListener::bind(path).unwrap();
            let (replies, commands, subs) = (
                fake.replies.clone(),
                fake.commands.clone(),
                fake.subs.clone(),
            );
            tokio::spawn(async move {
                loop {
                    let (stream, _) = listener.accept().await.unwrap();
                    let (replies, commands, subs) =
                        (replies.clone(), commands.clone(), subs.clone());
                    tokio::spawn(async move {
                        let (mut rd, mut wr) = stream.into_split();
                        let (tx, mut rx) = mpsc::unbounded_channel::<Option<(u32, Value)>>();
                        loop {
                            tokio::select! {
                                msg = read_msg(&mut rd) => {
                                    let Ok((ty, body)) = msg else { return };
                                    let reply = match ty {
                                        SUBSCRIBE => {
                                            subs.lock().unwrap().push(tx.clone());
                                            json!({"success": true})
                                        }
                                        RUN_COMMAND => {
                                            commands.lock().unwrap().push(String::from_utf8(body).unwrap());
                                            json!([{"success": true}])
                                        }
                                        t => replies.lock().unwrap().get(&t).cloned().unwrap_or(json!([])),
                                    };
                                    let b = serde_json::to_vec(&reply).unwrap();
                                    if write_msg(&mut wr, ty, &b).await.is_err() { return }
                                }
                                ev = rx.recv() => match ev {
                                    Some(Some((ty, v))) => {
                                        let b = serde_json::to_vec(&v).unwrap();
                                        if write_msg(&mut wr, ty, &b).await.is_err() { return }
                                    }
                                    _ => return,
                                }
                            }
                        }
                    });
                }
            });
            fake
        }

        fn set(&self, ty: u32, v: Value) {
            self.replies.lock().unwrap().insert(ty, v);
        }

        fn push(&self, ty: u32, v: Value) {
            for s in self.subs.lock().unwrap().iter() {
                let _ = s.send(Some((ty, v.clone())));
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

    fn outputs() -> Value {
        json!([
            {"name": "HEADLESS-1", "make": "headless", "model": "headless", "active": true, "focused": true,
             "scale": 1.0, "rect": {"x": 0, "y": 0, "width": 2560, "height": 1440}},
            {"name": "HEADLESS-2", "make": "headless", "model": "headless", "active": true, "focused": false,
             "scale": 2.0, "rect": {"x": 2560, "y": 0, "width": 1280, "height": 720}},
            {"name": "OFF-1", "active": false, "rect": {"x": 0, "y": 0, "width": 0, "height": 0}}
        ])
    }

    fn workspaces(focused: i64) -> Value {
        json!([
            {"id": 4, "num": 1, "name": "1", "visible": focused != 2, "focused": focused == 1, "urgent": false, "output": "HEADLESS-1"},
            {"id": 9, "num": 2, "name": "2", "visible": focused == 2, "focused": focused == 2, "urgent": true, "output": "HEADLESS-1"},
            {"id": 12, "num": -1, "name": "mail", "visible": true, "focused": false, "urgent": false, "output": "HEADLESS-2"}
        ])
    }

    fn tree(foot_title: &str) -> Value {
        json!({"id": 1, "type": "root", "name": "root", "nodes": [
            {"id": 2, "type": "output", "name": "__i3", "nodes": [
                {"id": 3, "type": "workspace", "name": "__i3_scratch", "nodes": [], "floating_nodes": [
                    {"id": 30, "type": "floating_con", "name": "scratch", "app_id": "pad", "pid": 7, "nodes": [], "rect": {}}
                ]}
            ]},
            {"id": 5, "type": "output", "name": "HEADLESS-1", "nodes": [
                {"id": 4, "type": "workspace", "name": "1", "nodes": [
                    {"id": 20, "type": "con", "name": null, "layout": "splith", "nodes": [
                        {"id": 21, "type": "con", "name": foot_title, "app_id": "foot", "pid": 10, "focused": true,
                         "nodes": [], "rect": {"x": 0, "y": 0, "width": 1280, "height": 1440}},
                        {"id": 22, "type": "con", "name": "xterm", "app_id": null, "pid": 11,
                         "window_properties": {"class": "XTerm"}, "nodes": [], "rect": {}}
                    ]}
                ], "floating_nodes": [
                    {"id": 23, "type": "floating_con", "name": "pip", "app_id": "mpv", "pid": 12, "nodes": [], "rect": {}}
                ]},
                {"id": 9, "type": "workspace", "name": "2", "nodes": [], "floating_nodes": []}
            ]},
            {"id": 6, "type": "output", "name": "HEADLESS-2", "nodes": [
                {"id": 12, "type": "workspace", "name": "mail", "nodes": [], "floating_nodes": []}
            ]}
        ]})
    }

    fn inputs(current: usize) -> Value {
        json!([
            {"identifier": "1:1:mouse", "type": "pointer"},
            {"identifier": "0:0:wlr_virtual_keyboard_v1", "type": "keyboard", "xkb_layout_names": [null],
             "xkb_active_layout_index": 0},
            {"identifier": "0:0:kbd", "type": "keyboard", "xkb_layout_names": ["English (US)", "German"],
             "xkb_active_layout_index": current}
        ])
    }

    fn replies() -> HashMap<u32, Value> {
        HashMap::from([
            (GET_OUTPUTS, outputs()),
            (GET_WORKSPACES, workspaces(1)),
            (GET_TREE, tree("~")),
            (GET_INPUTS, inputs(0)),
        ])
    }

    fn state() -> SwayState {
        let mut st = SwayState::default();
        let b = |v: Value| serde_json::to_vec(&v).unwrap();
        st.set_outputs(&b(outputs())).unwrap();
        st.set_workspaces(&b(workspaces(1))).unwrap();
        st.set_tree(&b(tree("~"))).unwrap();
        st.set_inputs(&b(inputs(0))).unwrap();
        st
    }

    #[test]
    fn framing_round_trips() {
        let rt = tokio::runtime::Builder::new_current_thread()
            .build()
            .unwrap();
        rt.block_on(async {
            let mut buf = Vec::new();
            write_msg(&mut buf, GET_TREE, b"{}").await.unwrap();
            assert_eq!(&buf[..6], b"i3-ipc");
            assert_eq!(buf.len(), 16);
            let (ty, body) = read_msg(&mut buf.as_slice()).await.unwrap();
            assert_eq!((ty, body.as_slice()), (GET_TREE, b"{}".as_slice()));
        });
    }

    #[test]
    fn projects_outputs_workspaces_windows_and_layouts() {
        let s = state().project();
        let names: Vec<_> = s
            .outputs
            .iter()
            .map(|o| (o.name.as_str(), o.focused))
            .collect();
        assert_eq!(
            names,
            [("HEADLESS-1", true), ("HEADLESS-2", false)],
            "inactive outputs drop"
        );
        assert_eq!(s.outputs[1].logical, (2560, 0, 1280, 720));
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
                    w.urgent,
                )
            })
            .collect();
        assert_eq!(
            ws,
            [
                (4, 1, "HEADLESS-1", true, true, true, false),
                (9, 2, "HEADLESS-1", false, false, false, true),
                // Unnumbered: after the highest number on its own output (none there: 1).
                (12, 1, "HEADLESS-2", false, true, false, false),
            ]
        );
        assert_eq!(s.workspaces[2].name.as_deref(), Some("mail"));
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
                (21, Some("foot"), Some(4), true, false),
                (22, Some("XTerm"), Some(4), false, false),
                (23, Some("mpv"), Some(4), false, true),
                (30, Some("pad"), None, false, true),
            ],
            "split containers are no windows; X11 class stands in for app_id; the scratchpad has no workspace"
        );
        assert_eq!(
            s.keyboard,
            Some(KeyboardLayouts {
                names: vec!["English (US)".into(), "German".into()],
                current: 0
            })
        );
    }

    #[test]
    fn actions_become_sway_commands() {
        let s = state().project();
        let rect = state().focused_window_rect();
        assert_eq!(rect, Some((0, 0, 1280, 1440)));
        let cmd = |a: Action| match plan(&a, &s, rect).unwrap() {
            Plan::Command(c) => c,
            other => panic!("{other:?}"),
        };
        assert_eq!(
            cmd(Action::FocusWorkspace(WorkspaceRef::Idx(2))),
            r#"workspace "2""#
        );
        assert_eq!(
            cmd(Action::FocusWorkspace(WorkspaceRef::Idx(7))),
            "workspace number 7"
        );
        assert_eq!(
            cmd(Action::FocusWorkspace(WorkspaceRef::Id(12))),
            r#"workspace "mail""#
        );
        assert!(matches!(
            plan(&Action::FocusWorkspace(WorkspaceRef::Id(99)), &s, rect),
            Err(Error::Rejected(_))
        ));
        assert_eq!(cmd(Action::FocusWindow(22)), "[con_id=22] focus");
        assert_eq!(cmd(Action::CloseWindow(22)), "[con_id=22] kill");
        assert_eq!(
            cmd(Action::MoveWindowToWorkspace {
                window_id: 21,
                workspace: WorkspaceRef::Idx(2)
            }),
            r#"[con_id=21] move container to workspace "2"; [con_id=21] focus"#
        );
        assert_eq!(cmd(Action::ScrollColumn(Direction::Left)), "focus left");
        assert_eq!(
            cmd(Action::SwitchLayout(LayoutTarget::Index(1))),
            "input type:keyboard xkb_switch_layout 1"
        );
        assert_eq!(
            cmd(Action::SwitchLayout(LayoutTarget::Next)),
            "input type:keyboard xkb_switch_layout next"
        );
        assert_eq!(
            plan(&Action::PowerOffMonitors, &s, rect).unwrap(),
            Plan::PowerOff
        );
        assert_eq!(
            plan(&Action::ScreenshotScreen, &s, rect).unwrap(),
            Plan::Shot(Shot::Screen(Some("HEADLESS-1".into())))
        );
        assert_eq!(
            plan(&Action::ScreenshotWindow, &s, rect).unwrap(),
            Plan::Shot(Shot::Rect(0, 0, 1280, 1440))
        );
        assert_eq!(quote(r#"a "b"\"#), r#""a \"b\"\\""#);
    }

    async fn next(ev: &mut (impl Stream<Item = Event> + Unpin)) -> Event {
        tokio::time::timeout(std::time::Duration::from_secs(5), ev.next())
            .await
            .expect("an event")
            .unwrap()
    }

    #[tokio::test]
    async fn fake_socket_snapshot_events_actions_and_reconnect() {
        let dir = tempfile::tempdir().unwrap();
        let path = dir.path().join("sway.sock");
        let fake = FakeSway::start(&path, replies());
        let sway = SwayCompositor::spawn(&path);
        let mut ev = sway.events();
        let snap = sway.snapshot().await.unwrap();
        assert_eq!(snap, state().project());

        // A workspace switch: workspaces (and the tree) re-read, one Workspaces + Windows event.
        fake.set(GET_WORKSPACES, workspaces(2));
        fake.set(
            GET_TREE,
            tree("~")
                .to_string()
                .replace(r#""focused":true"#, r#""focused":false"#)
                .parse()
                .unwrap(),
        );
        fake.push(EVENT_WORKSPACE, json!({"change": "focus"}));
        match next(&mut ev).await {
            Event::Workspaces(w) => assert!(w.iter().any(|w| w.id == 9 && w.focused)),
            other => panic!("{other:?}"),
        }
        match next(&mut ev).await {
            Event::Windows(w) => assert!(w.iter().all(|w| !w.focused)),
            other => panic!("{other:?}"),
        }
        // A title change is applied in place (the tree reply is stale on purpose).
        fake.push(
            EVENT_WINDOW,
            json!({"change": "title", "container": {"id": 21, "name": "vim"}}),
        );
        match next(&mut ev).await {
            Event::Windows(w) => assert_eq!(w[0].title.as_deref(), Some("vim")),
            other => panic!("{other:?}"),
        }
        // A layout switch.
        fake.set(GET_INPUTS, inputs(1));
        fake.push(EVENT_INPUT, json!({"change": "xkb_layout"}));
        match next(&mut ev).await {
            Event::Keyboard(Some(k)) => assert_eq!(k.current, 1),
            other => panic!("{other:?}"),
        }
        // Actions → wire commands.
        sway.act(Action::FocusWorkspace(WorkspaceRef::Id(4)))
            .await
            .unwrap();
        sway.act(Action::CloseWindow(21)).await.unwrap();
        sway.act(Action::SwitchLayout(LayoutTarget::Prev))
            .await
            .unwrap();
        assert_eq!(
            fake.commands(),
            [
                r#"workspace "1""#,
                "[con_id=21] kill",
                "input type:keyboard xkb_switch_layout prev"
            ]
        );
        assert_eq!(
            focused_output_at(&path).await.unwrap().as_deref(),
            Some("HEADLESS-1")
        );

        // Sway restarts: Resync, then a fresh snapshot.
        fake.set(GET_WORKSPACES, workspaces(1));
        fake.drop_events();
        assert_eq!(next(&mut ev).await, Event::Resync);
        let again = sway.snapshot().await.unwrap();
        assert!(again.workspaces.iter().any(|w| w.id == 4 && w.focused));
    }

    #[tokio::test]
    async fn rejected_command_carries_sways_error() {
        let dir = tempfile::tempdir().unwrap();
        let path = dir.path().join("sway.sock");
        let listener = UnixListener::bind(&path).unwrap();
        tokio::spawn(async move {
            let (mut s, _) = listener.accept().await.unwrap();
            let (ty, _) = read_msg(&mut s).await.unwrap();
            let b = br#"[{"success":false,"parse_error":false,"error":"No matching node."}]"#;
            write_msg(&mut s, ty, b).await.unwrap();
        });
        let err = act_at(&path, &Action::FocusWindow(1)).await.unwrap_err();
        assert!(
            matches!(err, Error::Rejected(ref e) if e == "No matching node."),
            "{err:?}"
        );
    }
}
