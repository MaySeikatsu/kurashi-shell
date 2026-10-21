//! Compositor abstraction for `kurashid` (ARCHITECTURE §7).
//!
//! The daemon talks to one [`Compositor`]; adapters (niri, Hyprland, Sway; MangoWM later) translate their
//! native IPC into the neutral types here, and [`any`] picks one at startup. No core changes per adapter.
//!
//! Events are *domain-level*: each carries the full, new list for the domain that changed
//! (outputs, workspaces, windows). That keeps them idempotent, so a subscriber that applies a
//! replayed event after a snapshot ends up in the same state, and lets the adapter drop noise
//! (focus timestamps, layout geometry) by diffing before it emits — Ma: no spurious wakeups.

pub mod any;
mod doc;
pub mod fake;
pub mod globals;
pub mod hyprland;
pub mod idle;
pub mod niri;
pub mod sway;
mod types;

pub use any::AnyCompositor;
pub use doc::workspaces_doc;
pub use tokio_stream::Stream;
pub use types::{
    Action, Capabilities, CompositorState, Direction, Event, KeyboardLayouts, LayoutTarget, Output,
    Window, Workspace, WorkspaceRef, diff,
};

#[derive(Debug, thiserror::Error)]
pub enum Error {
    /// The compositor connection is gone (or never came up); the adapter is reconnecting.
    #[error("compositor unavailable: {0}")]
    Unavailable(String),
    /// The compositor understood the request and refused it.
    #[error("compositor rejected request: {0}")]
    Rejected(String),
    #[error("compositor protocol error: {0}")]
    Protocol(String),
}

pub type Result<T> = std::result::Result<T, Error>;

/// What the daemon needs from a compositor. Not object-safe by design (edition 2024 `async fn`
/// in traits); the daemon is generic over the adapter chosen at startup.
pub trait Compositor: Send + Sync {
    /// Full current state. Waits while the adapter is (re)connecting and not yet in sync, so it
    /// never returns a value that is not in effect (Shōjiki).
    fn snapshot(&self) -> impl Future<Output = Result<CompositorState>> + Send;

    /// Incremental events. [`Event::Resync`] means: drop what you hold and call
    /// [`snapshot`](Self::snapshot) again (connection lost, or this subscriber lagged).
    fn events(&self) -> impl Stream<Item = Event> + Send + Unpin + 'static;

    /// Fire an action at the compositor. State changes arrive through [`events`](Self::events).
    fn act(&self, action: Action) -> impl Future<Output = Result<()>> + Send;

    fn capabilities(&self) -> Capabilities;
}
