use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct Output {
    pub name: String,
    pub make: String,
    pub model: String,
    /// Logical position and size: `(x, y, width, height)`.
    pub logical: (i32, i32, u32, u32),
    pub scale: f64,
    pub focused: bool,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct Workspace {
    pub id: u64,
    /// 1-based position on its output.
    pub idx: u8,
    pub name: Option<String>,
    /// `None` for a workspace not (yet) bound to an output.
    pub output: Option<String>,
    pub focused: bool,
    /// Visible on its output (exactly one per output; `focused` implies `active`).
    pub active: bool,
    /// Holds at least one window.
    pub occupied: bool,
    pub urgent: bool,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct Window {
    pub id: u64,
    pub app_id: Option<String>,
    pub title: Option<String>,
    pub workspace_id: Option<u64>,
    pub focused: bool,
    pub floating: bool,
}

/// Everything the daemon mirrors. Lists are sorted (outputs by name, workspaces by output then
/// idx, windows by id) so equal states compare equal and docs are stable.
#[derive(Debug, Clone, Default, PartialEq, Serialize, Deserialize)]
pub struct CompositorState {
    pub outputs: Vec<Output>,
    pub workspaces: Vec<Workspace>,
    pub windows: Vec<Window>,
    pub overview_open: bool,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub enum Event {
    Outputs(Vec<Output>),
    Workspaces(Vec<Workspace>),
    Windows(Vec<Window>),
    Overview(bool),
    /// Drop all held state and fetch a fresh snapshot.
    Resync,
}

/// Events that turn `old` into `new` (empty when equal).
pub fn diff(old: &CompositorState, new: &CompositorState) -> Vec<Event> {
    let mut out = Vec::new();
    if old.outputs != new.outputs {
        out.push(Event::Outputs(new.outputs.clone()));
    }
    if old.workspaces != new.workspaces {
        out.push(Event::Workspaces(new.workspaces.clone()));
    }
    if old.windows != new.windows {
        out.push(Event::Windows(new.windows.clone()));
    }
    if old.overview_open != new.overview_open {
        out.push(Event::Overview(new.overview_open));
    }
    out
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum Direction {
    Left,
    Right,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub enum WorkspaceRef {
    Id(u64),
    /// 1-based index on the focused output.
    Idx(u8),
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub enum Action {
    FocusWorkspace(WorkspaceRef),
    FocusWindow(u64),
    MoveWindowToWorkspace {
        window_id: u64,
        workspace: WorkspaceRef,
    },
    /// Scroll the tiling view one column.
    ScrollColumn(Direction),
}

/// Optional features an adapter may offer; the UI hides what is `false` instead of faking it.
#[derive(Debug, Clone, Copy, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct Capabilities {
    pub scroll_position: bool,
    pub overview: bool,
    pub window_previews: bool,
    pub blur_hint: bool,
    pub workspace_names: bool,
}
