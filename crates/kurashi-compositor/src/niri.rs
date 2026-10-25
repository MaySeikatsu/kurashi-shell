//! niri adapter (niri 26.04, `niri-ipc` 26.4).
//!
//! One long-lived `EventStream` connection feeds [`NiriState`]; actions and the `Outputs` lookup
//! use separate short-lived request connections. Nothing polls: the event stream pushes, and
//! outputs (which niri does not stream) are re-read only when the set of workspace outputs
//! changes (K-compositor: hotplug always creates/removes a workspace on that output).

use std::{
    collections::{BTreeSet, HashMap},
    path::{Path, PathBuf},
    sync::{Arc, Mutex},
    time::Duration,
};

use niri_ipc::{Reply, Request, Response, WorkspaceReferenceArg};
use tokio::{
    io::{AsyncBufReadExt, AsyncWriteExt, BufReader},
    net::UnixStream,
    sync::{broadcast, watch},
};
use tokio_stream::{Stream, StreamExt, wrappers::BroadcastStream};

use crate::{
    Action, Capabilities, Compositor, CompositorState, Direction, Error, Event, LayoutTarget,
    Output, Result, Window, Workspace, WorkspaceRef, diff,
};

const BACKOFF_START: Duration = Duration::from_millis(250);
const BACKOFF_MAX: Duration = Duration::from_secs(4);

/// niri's state, kept incrementally from its event stream and projected into neutral types.
///
/// Pure (no IO) so a recorded stream can be replayed in tests. Unlike
/// `niri_ipc::state::EventStreamState` it never panics on an event for an unknown id — a
/// shell must survive a compositor that is ahead of or behind it.
#[derive(Default)]
pub struct NiriState {
    workspaces: HashMap<u64, niri_ipc::Workspace>,
    windows: HashMap<u64, niri_ipc::Window>,
    outputs: HashMap<String, niri_ipc::Output>,
    overview: bool,
    keyboard: Option<niri_ipc::KeyboardLayouts>,
    got_workspaces: bool,
    got_windows: bool,
    /// Workspace output names at the time outputs were last read (`None`: never).
    outputs_for: Option<BTreeSet<String>>,
    current: CompositorState,
}

impl NiriState {
    pub fn state(&self) -> &CompositorState {
        &self.current
    }

    /// Initial burst complete: workspaces, windows and outputs all known.
    pub fn is_synced(&self) -> bool {
        self.got_workspaces && self.got_windows && self.outputs_for.is_some()
    }

    /// Outputs must be (re)read: workspaces are known and their output set moved since last read.
    pub fn wants_outputs(&self) -> bool {
        self.got_workspaces && self.outputs_for.as_ref() != Some(&self.workspace_output_names())
    }

    fn workspace_output_names(&self) -> BTreeSet<String> {
        self.workspaces
            .values()
            .filter_map(|w| w.output.clone())
            .collect()
    }

    pub fn set_outputs(&mut self, outputs: HashMap<String, niri_ipc::Output>) -> Vec<Event> {
        self.outputs = outputs;
        self.outputs_for = Some(self.workspace_output_names());
        self.reproject()
    }

    /// Apply one niri event; returns the neutral events that actually changed something.
    pub fn apply(&mut self, event: niri_ipc::Event) -> Vec<Event> {
        use niri_ipc::Event as N;
        match event {
            N::WorkspacesChanged { workspaces } => {
                self.workspaces = workspaces.into_iter().map(|w| (w.id, w)).collect();
                self.got_workspaces = true;
            }
            N::WorkspaceUrgencyChanged { id, urgent } => {
                if let Some(w) = self.workspaces.get_mut(&id) {
                    w.is_urgent = urgent;
                }
            }
            N::WorkspaceActivated { id, focused } => {
                if let Some(output) = self.workspaces.get(&id).map(|w| w.output.clone()) {
                    for w in self.workspaces.values_mut() {
                        let hit = w.id == id;
                        if w.output == output {
                            w.is_active = hit;
                        }
                        if focused {
                            w.is_focused = hit;
                        }
                    }
                }
            }
            N::WindowsChanged { windows } => {
                self.windows = windows.into_iter().map(|w| (w.id, w)).collect();
                self.got_windows = true;
            }
            N::WindowOpenedOrChanged { window } => {
                let (id, focused) = (window.id, window.is_focused);
                self.windows.insert(id, window);
                if focused {
                    for w in self.windows.values_mut().filter(|w| w.id != id) {
                        w.is_focused = false;
                    }
                }
            }
            N::WindowClosed { id } => {
                self.windows.remove(&id);
            }
            N::WindowFocusChanged { id } => {
                for w in self.windows.values_mut() {
                    w.is_focused = Some(w.id) == id;
                }
            }
            N::WindowUrgencyChanged { id, urgent } => {
                if let Some(w) = self.windows.get_mut(&id) {
                    w.is_urgent = urgent;
                }
            }
            N::OverviewOpenedOrClosed { is_open } => self.overview = is_open,
            // K47 `svc.keyboard`: the configured layouts, then each switch.
            N::KeyboardLayoutsChanged { keyboard_layouts } => {
                self.keyboard = Some(keyboard_layouts)
            }
            N::KeyboardLayoutSwitched { idx } => {
                if let Some(k) = self.keyboard.as_mut() {
                    k.current_idx = idx;
                }
            }
            // Layouts, timestamps, casts, config, screenshots: not in our state, and
            // ignoring them is what keeps an idle shell silent.
            _ => return Vec::new(),
        }
        self.reproject()
    }

    fn reproject(&mut self) -> Vec<Event> {
        let new = self.project();
        let events = diff(&self.current, &new);
        self.current = new;
        events
    }

    fn project(&self) -> CompositorState {
        let focused_output = self
            .workspaces
            .values()
            .find(|w| w.is_focused)
            .and_then(|w| w.output.clone());
        let occupied: BTreeSet<u64> = self
            .windows
            .values()
            .filter_map(|w| w.workspace_id)
            .collect();

        let mut outputs: Vec<Output> = self
            .outputs
            .values()
            // A disabled output has no logical geometry and nothing to draw on.
            .filter_map(|o| {
                let l = o.logical.as_ref()?;
                Some(Output {
                    name: o.name.clone(),
                    make: o.make.clone(),
                    model: o.model.clone(),
                    logical: (l.x, l.y, l.width, l.height),
                    scale: l.scale,
                    focused: focused_output.as_deref() == Some(o.name.as_str()),
                })
            })
            .collect();
        outputs.sort_by(|a, b| a.name.cmp(&b.name));

        let mut workspaces: Vec<Workspace> = self
            .workspaces
            .values()
            .map(|w| Workspace {
                id: w.id,
                idx: w.idx,
                name: w.name.clone(),
                output: w.output.clone(),
                focused: w.is_focused,
                active: w.is_active,
                occupied: occupied.contains(&w.id),
                urgent: w.is_urgent,
            })
            .collect();
        workspaces.sort_by(|a, b| (&a.output, a.idx, a.id).cmp(&(&b.output, b.idx, b.id)));

        let mut windows: Vec<Window> = self
            .windows
            .values()
            .map(|w| Window {
                id: w.id,
                app_id: w.app_id.clone(),
                title: w.title.clone(),
                workspace_id: w.workspace_id,
                focused: w.is_focused,
                floating: w.is_floating,
                urgent: w.is_urgent,
            })
            .collect();
        windows.sort_by_key(|w| w.id);

        CompositorState {
            outputs,
            workspaces,
            windows,
            overview_open: self.overview,
            keyboard: self.keyboard.as_ref().map(|k| crate::KeyboardLayouts {
                names: k.names.clone(),
                current: usize::from(k.current_idx),
            }),
        }
    }
}

/// Translate a neutral action into the exact niri request (also what the tests pin).
pub fn to_request(action: &Action) -> Request {
    use niri_ipc::Action as N;
    let reference = |r: &WorkspaceRef| match r {
        WorkspaceRef::Id(id) => WorkspaceReferenceArg::Id(*id),
        WorkspaceRef::Idx(i) => WorkspaceReferenceArg::Index(*i),
    };
    Request::Action(match action {
        Action::FocusWorkspace(r) => N::FocusWorkspace {
            reference: reference(r),
        },
        Action::FocusWindow(id) => N::FocusWindow { id: *id },
        Action::CloseWindow(id) => N::CloseWindow { id: Some(*id) },
        Action::MoveWindowToWorkspace {
            window_id,
            workspace,
        } => N::MoveWindowToWorkspace {
            window_id: Some(*window_id),
            reference: reference(workspace),
            focus: true,
        },
        Action::ScrollColumn(Direction::Left) => N::FocusColumnLeft {},
        Action::ScrollColumn(Direction::Right) => N::FocusColumnRight {},
        Action::PowerOffMonitors => N::PowerOffMonitors {},
        Action::SwitchLayout(t) => N::SwitchLayout {
            layout: match t {
                LayoutTarget::Next => niri_ipc::LayoutSwitchTarget::Next,
                LayoutTarget::Prev => niri_ipc::LayoutSwitchTarget::Prev,
                LayoutTarget::Index(i) => niri_ipc::LayoutSwitchTarget::Index(*i),
            },
        },
        // niri's own UI and clipboard (K47); the files go where niri's `screenshot-path` says.
        Action::ScreenshotRegion => N::Screenshot {
            show_pointer: false,
            path: None,
        },
        Action::ScreenshotScreen => N::ScreenshotScreen {
            write_to_disk: true,
            show_pointer: false,
            path: None,
        },
        Action::ScreenshotWindow => N::ScreenshotWindow {
            id: None,
            write_to_disk: true,
            show_pointer: false,
            path: None,
        },
    })
}

/// One action on its own request connection, without the event stream a [`NiriCompositor`] keeps:
/// what the daemon's one-shot actions (idle, screenshots, layouts) use.
pub async fn act_at(path: &Path, action: &Action) -> Result<()> {
    match request(path, to_request(action)).await? {
        Response::Handled => Ok(()),
        other => Err(Error::Protocol(format!("unexpected reply {other:?}"))),
    }
}

/// The focused output's name (the recorder's default output), on its own request connection.
pub async fn focused_output_at(path: &Path) -> Result<Option<String>> {
    match request(path, Request::FocusedOutput).await? {
        Response::FocusedOutput(o) => Ok(o.map(|o| o.name)),
        other => Err(Error::Protocol(format!("unexpected reply {other:?}"))),
    }
}

struct Inner {
    path: PathBuf,
    state: Mutex<NiriState>,
    ready: watch::Sender<bool>,
    tx: broadcast::Sender<Event>,
}

pub struct NiriCompositor {
    inner: Arc<Inner>,
    task: tokio::task::JoinHandle<()>,
}

impl NiriCompositor {
    /// Connect to `$NIRI_SOCKET`. Must be called inside a tokio runtime.
    pub fn from_env() -> Result<Self> {
        let path = std::env::var_os("NIRI_SOCKET")
            .ok_or_else(|| Error::Unavailable("NIRI_SOCKET is not set".into()))?;
        Ok(Self::spawn(PathBuf::from(path)))
    }

    /// Start the event-stream task for the socket at `path`. Must be called inside a tokio
    /// runtime; the task ends when the compositor handle is dropped.
    pub fn spawn(path: impl Into<PathBuf>) -> Self {
        let inner = Arc::new(Inner {
            path: path.into(),
            state: Mutex::new(NiriState::default()),
            ready: watch::channel(false).0,
            tx: broadcast::channel(256).0,
        });
        let task = tokio::spawn(run(inner.clone()));
        Self { inner, task }
    }
}

impl Drop for NiriCompositor {
    fn drop(&mut self) {
        self.task.abort();
    }
}

impl Compositor for NiriCompositor {
    async fn snapshot(&self) -> Result<CompositorState> {
        let mut rx = self.inner.ready.subscribe();
        rx.wait_for(|r| *r)
            .await
            .map_err(|_| Error::Unavailable("adapter stopped".into()))?;
        Ok(self.inner.state.lock().unwrap().state().clone())
    }

    fn events(&self) -> impl Stream<Item = Event> + Send + Unpin + 'static {
        // A lagging subscriber missed events: the honest answer is Resync, not a silent gap.
        BroadcastStream::new(self.inner.tx.subscribe()).map(|r| r.unwrap_or(Event::Resync))
    }

    async fn act(&self, action: Action) -> Result<()> {
        act_at(&self.inner.path, &action).await
    }

    fn capabilities(&self) -> Capabilities {
        // niri's IPC has no scroll offset, previews or blur hint (as of 26.04).
        Capabilities {
            overview: true,
            workspace_names: true,
            ..Capabilities::default()
        }
    }
}

/// One request on its own connection (the protocol allows several; actions are rare, so no pool).
async fn request(path: &Path, req: Request) -> Result<Response> {
    let stream = UnixStream::connect(path)
        .await
        .map_err(|e| Error::Unavailable(e.to_string()))?;
    let (rd, mut wr) = stream.into_split();
    let mut line = serde_json::to_string(&req).map_err(|e| Error::Protocol(e.to_string()))?;
    line.push('\n');
    let io = |e: std::io::Error| Error::Unavailable(e.to_string());
    wr.write_all(line.as_bytes()).await.map_err(io)?;
    wr.shutdown().await.map_err(io)?;
    line.clear();
    BufReader::new(rd).read_line(&mut line).await.map_err(io)?;
    let reply: Reply = serde_json::from_str(&line).map_err(|e| Error::Protocol(e.to_string()))?;
    reply.map_err(Error::Rejected)
}

async fn run(inner: Arc<Inner>) {
    let mut backoff = BACKOFF_START;
    loop {
        let synced = session(&inner).await;
        // Whatever we held is no longer known to be in effect.
        *inner.state.lock().unwrap() = NiriState::default();
        inner.ready.send_replace(false);
        let _ = inner.tx.send(Event::Resync);
        if synced {
            backoff = BACKOFF_START;
        }
        tokio::time::sleep(backoff).await;
        backoff = (backoff * 2).min(BACKOFF_MAX);
    }
}

/// One connection's lifetime. Returns whether it reached sync before ending.
async fn session(inner: &Inner) -> bool {
    let mut synced = false;
    if let Err(e) = stream_events(inner, &mut synced).await {
        tracing::warn!("niri event stream ended: {e}");
    }
    synced
}

async fn stream_events(inner: &Inner, synced: &mut bool) -> Result<()> {
    let io = |e: std::io::Error| Error::Unavailable(e.to_string());
    let stream = UnixStream::connect(&inner.path).await.map_err(io)?;
    let (rd, mut wr) = stream.into_split();
    wr.write_all(b"\"EventStream\"\n").await.map_err(io)?;
    wr.shutdown().await.map_err(io)?;
    let mut rd = BufReader::new(rd);
    let mut line = String::new();

    rd.read_line(&mut line).await.map_err(io)?;
    let reply: Reply = serde_json::from_str(&line).map_err(|e| Error::Protocol(e.to_string()))?;
    reply.map_err(Error::Rejected)?;

    loop {
        line.clear();
        if rd.read_line(&mut line).await.map_err(io)? == 0 {
            return Err(Error::Unavailable("connection closed".into()));
        }
        let event: niri_ipc::Event = match serde_json::from_str(&line) {
            Ok(e) => e,
            Err(e) => {
                // A newer niri may add events; losing one we cannot parse is not worth the session.
                tracing::debug!("skipping unparsable niri event: {e}");
                continue;
            }
        };
        let events = inner.state.lock().unwrap().apply(event);
        publish(inner, events);

        let wants = inner.state.lock().unwrap().wants_outputs();
        if wants {
            match request(&inner.path, Request::Outputs).await? {
                Response::Outputs(outputs) => {
                    let events = inner.state.lock().unwrap().set_outputs(outputs);
                    publish(inner, events);
                }
                other => return Err(Error::Protocol(format!("unexpected reply {other:?}"))),
            }
        }
        if !*synced && inner.state.lock().unwrap().is_synced() {
            *synced = true;
            inner.ready.send_replace(true);
        }
    }
}

fn publish(inner: &Inner, events: Vec<Event>) {
    for e in events {
        let _ = inner.tx.send(e);
    }
}
