//! Scriptable in-memory compositor for daemon / frontend tests.

use std::sync::Mutex;

use tokio::sync::broadcast;
use tokio_stream::{Stream, StreamExt, wrappers::BroadcastStream};

use crate::{Action, Capabilities, Compositor, CompositorState, Event, Result, diff};

pub struct FakeCompositor {
    state: Mutex<CompositorState>,
    actions: Mutex<Vec<Action>>,
    caps: Capabilities,
    tx: broadcast::Sender<Event>,
}

impl FakeCompositor {
    pub fn new(state: CompositorState) -> Self {
        Self {
            state: Mutex::new(state),
            actions: Mutex::new(Vec::new()),
            caps: Capabilities {
                overview: true,
                workspace_names: true,
                ..Capabilities::default()
            },
            tx: broadcast::channel(256).0,
        }
    }

    /// Replace the state and emit the events a real adapter would.
    pub fn set_state(&self, new: CompositorState) {
        let mut cur = self.state.lock().unwrap();
        for ev in diff(&cur, &new) {
            let _ = self.tx.send(ev);
        }
        *cur = new;
    }

    /// Simulate a reconnect: subscribers get `Resync`, then see `new` on `snapshot()`.
    pub fn resync(&self, new: CompositorState) {
        *self.state.lock().unwrap() = new;
        let _ = self.tx.send(Event::Resync);
    }

    /// Actions received so far, in order.
    pub fn actions(&self) -> Vec<Action> {
        self.actions.lock().unwrap().clone()
    }

    pub fn with_capabilities(mut self, caps: Capabilities) -> Self {
        self.caps = caps;
        self
    }
}

impl Compositor for FakeCompositor {
    async fn snapshot(&self) -> Result<CompositorState> {
        Ok(self.state.lock().unwrap().clone())
    }

    fn events(&self) -> impl Stream<Item = Event> + Send + Unpin + 'static {
        BroadcastStream::new(self.tx.subscribe()).map(|r| r.unwrap_or(Event::Resync))
    }

    async fn act(&self, action: Action) -> Result<()> {
        self.actions.lock().unwrap().push(action);
        Ok(())
    }

    fn capabilities(&self) -> Capabilities {
        self.caps
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::{Workspace, WorkspaceRef};

    fn ws(id: u64, focused: bool) -> Workspace {
        Workspace {
            id,
            idx: id as u8,
            name: None,
            output: Some("A".into()),
            focused,
            active: focused,
            occupied: false,
            urgent: false,
        }
    }

    #[tokio::test]
    async fn scripted_events_and_actions() {
        let fake = FakeCompositor::new(CompositorState::default());
        let mut ev = fake.events();
        let next = CompositorState {
            workspaces: vec![ws(1, true)],
            ..Default::default()
        };
        fake.set_state(next.clone());
        assert_eq!(
            ev.next().await,
            Some(Event::Workspaces(next.workspaces.clone()))
        );
        fake.set_state(next.clone()); // unchanged: silent
        fake.resync(CompositorState::default());
        assert_eq!(ev.next().await, Some(Event::Resync));
        fake.act(Action::FocusWorkspace(WorkspaceRef::Idx(2)))
            .await
            .unwrap();
        assert_eq!(fake.actions().len(), 1);
    }
}
