//! `svc.workspaces` backed by the compositor adapter (ARCHITECTURE §7). The adapter — and with
//! it the compositor event stream — exists only while someone subscribes (Ma); actions spin up
//! a short-lived adapter when nobody is watching.

use std::sync::{Arc, Mutex};

use kurashi_compositor::{
    Action, Compositor, CompositorState, Event, WorkspaceRef, workspaces_doc,
};
use serde_json::{Value, json};
use tokio_stream::StreamExt;

use crate::actions::{ActionError, ActionRegistry};
use crate::hub::{Hub, Provider};

pub const DOC: &str = "svc.workspaces";

type Factory<C> = Arc<dyn Fn() -> C + Send + Sync>;
/// A window action: its id, its label key and the adapter action it becomes.
type WindowAction = (&'static str, &'static str, fn(u64) -> Action);

/// The document plus the `"*"` alias (the focused output's list) that frontends use for outputs
/// the compositor hasn't named yet (PROTOCOL §8).
pub fn document(state: &CompositorState) -> Value {
    let mut doc = workspaces_doc(state);
    let focused = state
        .outputs
        .iter()
        .find(|o| o.focused)
        .map(|o| o.name.clone());
    if let Some(outputs) = doc["outputs"].as_object_mut() {
        let alias = focused
            .and_then(|f| outputs.get(&f).cloned())
            .or_else(|| outputs.values().next().cloned())
            .unwrap_or_else(|| json!([]));
        outputs.insert("*".into(), alias);
    }
    doc["tasks"] = tasks(state);
    doc["windows"] = windows(state);
    doc
}

/// `windows` (K51, the dock): every window in id order as `{id, app_id, workspace, output, focused}`. `workspace` is
/// the workspace id and `output` its output's name, `null` while the compositor has placed it on neither; no titles
/// (the reason `tasks` has none).
fn windows(state: &CompositorState) -> Value {
    let list: Vec<Value> = state
        .windows
        .iter()
        .map(|w| {
            let output = w
                .workspace_id
                .and_then(|id| state.workspaces.iter().find(|ws| ws.id == id))
                .and_then(|ws| ws.output.clone());
            json!({
                "id": w.id,
                "app_id": w.app_id.clone().unwrap_or_default(),
                "workspace": w.workspace_id,
                "output": output,
                "focused": w.focused,
            })
        })
        .collect();
    Value::Array(list)
}

/// `tasks`: per output, the windows of its active workspace in id order, as `{id, app_id, focused}` (session 9: the
/// bar's window list). Titles stay out on purpose: a browser retitles on every page, and a title is not drawn.
fn tasks(state: &CompositorState) -> Value {
    let mut map = serde_json::Map::new();
    for o in &state.outputs {
        let active = state
            .workspaces
            .iter()
            .find(|w| w.active && w.output.as_deref() == Some(o.name.as_str()))
            .map(|w| w.id);
        let list: Vec<Value> = state
            .windows
            .iter()
            .filter(|w| active.is_some() && w.workspace_id == active)
            .map(|w| json!({"id": w.id, "app_id": w.app_id.clone().unwrap_or_default(), "focused": w.focused}))
            .collect();
        if o.focused {
            map.insert("*".into(), Value::Array(list.clone()));
        }
        map.insert(o.name.clone(), Value::Array(list));
    }
    Value::Object(map)
}

pub struct WorkspacesProvider<C> {
    factory: Factory<C>,
    task: Mutex<Option<tokio::task::JoinHandle<()>>>,
}

impl<C: Compositor + 'static> WorkspacesProvider<C> {
    pub fn new(factory: impl Fn() -> C + Send + Sync + 'static) -> Arc<Self> {
        Arc::new(WorkspacesProvider {
            factory: Arc::new(factory),
            task: Mutex::new(None),
        })
    }

    /// `workspace.focus {idx}` / `{id}`, `window.focus {id}`, `window.close {id}` (K51).
    pub fn register_actions(self: &Arc<Self>, actions: &mut ActionRegistry) {
        let window_actions: [WindowAction; 2] = [
            ("window.focus", "action.window.focus", Action::FocusWindow),
            ("window.close", "action.window.close", Action::CloseWindow),
        ];
        for (name, label, make) in window_actions {
            let wf = self.factory.clone();
            actions.register(name, label, move |args: Value| {
                let factory = wf.clone();
                async move {
                    let id = args
                        .get("id")
                        .and_then(Value::as_u64)
                        .ok_or_else(|| ActionError::Invalid(format!("{name} needs id")))?;
                    factory()
                        .act(make(id))
                        .await
                        .map_err(|e| ActionError::Unavailable(e.to_string()))?;
                    Ok(None)
                }
            });
        }
        let factory = self.factory.clone();
        actions.register(
            "workspace.focus",
            "action.workspace.focus",
            move |args: Value| {
                let factory = factory.clone();
                async move {
                    let target = if let Some(id) = args.get("id").and_then(Value::as_u64) {
                        WorkspaceRef::Id(id)
                    } else if let Some(idx) = args.get("idx").and_then(Value::as_u64) {
                        WorkspaceRef::Idx(u8::try_from(idx).map_err(|_| {
                            ActionError::Invalid(format!("workspace idx {idx} out of range"))
                        })?)
                    } else {
                        return Err(ActionError::Invalid(
                            "workspace.focus needs idx or id".into(),
                        ));
                    };
                    factory()
                        .act(Action::FocusWorkspace(target))
                        .await
                        .map_err(|e| ActionError::Unavailable(e.to_string()))?;
                    Ok(None)
                }
            },
        );
    }
}

impl<C: Compositor + 'static> Provider for WorkspacesProvider<C> {
    fn start(&self, hub: Arc<Hub>) {
        let compositor = (self.factory)();
        let task = tokio::spawn(async move {
            let mut events = compositor.events();
            let mut state = match compositor.snapshot().await {
                Ok(s) => s,
                Err(e) => {
                    tracing::warn!(error = %e, "compositor snapshot failed");
                    CompositorState::default()
                }
            };
            let _ = hub.set(DOC, document(&state), None);
            crate::texture::set_outputs(&state.outputs);
            while let Some(ev) = events.next().await {
                match ev {
                    Event::Outputs(o) => {
                        crate::texture::set_outputs(&o);
                        state.outputs = o;
                    }
                    Event::Workspaces(w) => state.workspaces = w,
                    Event::Windows(w) => state.windows = w,
                    Event::Overview(open) => state.overview_open = open,
                    // svc.keyboard has its own provider (K47); this document does not show layouts.
                    Event::Keyboard(_) => continue,
                    Event::Resync => {
                        // Waits until the adapter is back in sync (never stale, Shōjiki).
                        if let Ok(s) = compositor.snapshot().await {
                            state = s;
                            let _ = hub.push_snapshot(DOC, document(&state));
                        }
                        continue;
                    }
                }
                let _ = hub.set(DOC, document(&state), None);
            }
        });
        // An adapter left running after the replacement would keep forwarding events, unwatched.
        let old = self.task.lock().expect("task lock").replace(task);
        if let Some(old) = old {
            old.abort();
        }
    }

    fn stop(&self) {
        // Aborting drops the adapter, which closes the compositor connection.
        if let Some(t) = self.task.lock().expect("task lock").take() {
            t.abort();
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use kurashi_compositor::fake::FakeCompositor;
    use kurashi_compositor::{Output, Window, Workspace};

    /// The fake isn't `Clone`; every provider start gets a handle to the same fake.
    struct Shared(Arc<FakeCompositor>);

    impl Compositor for Shared {
        fn snapshot(
            &self,
        ) -> impl Future<Output = kurashi_compositor::Result<CompositorState>> + Send {
            self.0.snapshot()
        }
        fn events(&self) -> impl kurashi_compositor::Stream<Item = Event> + Send + Unpin + 'static {
            self.0.events()
        }
        fn act(&self, a: Action) -> impl Future<Output = kurashi_compositor::Result<()>> + Send {
            self.0.act(a)
        }
        fn capabilities(&self) -> kurashi_compositor::Capabilities {
            self.0.capabilities()
        }
    }

    fn state(focused_idx: u8) -> CompositorState {
        CompositorState {
            outputs: vec![Output {
                name: "DP-1".into(),
                make: String::new(),
                model: String::new(),
                logical: (0, 0, 2560, 1440),
                scale: 1.0,
                focused: true,
            }],
            workspaces: (1..=3)
                .map(|i| Workspace {
                    id: i as u64,
                    idx: i,
                    name: None,
                    output: Some("DP-1".into()),
                    focused: i == focused_idx,
                    active: i == focused_idx,
                    occupied: false,
                    urgent: false,
                })
                .collect(),
            ..Default::default()
        }
    }

    fn window(id: u64, app_id: Option<&str>, workspace_id: Option<u64>, focused: bool) -> Window {
        Window {
            id,
            app_id: app_id.map(String::from),
            title: Some("churns".into()),
            workspace_id,
            focused,
            floating: false,
        }
    }

    /// K51: `windows` lists every window of every workspace in id order with its workspace and that workspace's
    /// output; an unplaced window has `null` for both, a window without app id an empty one; no titles.
    #[test]
    fn windows_lists_every_window_with_workspace_and_output() {
        let mut st = state(1);
        st.workspaces.push(Workspace {
            id: 9,
            idx: 1,
            name: None,
            output: None,
            focused: false,
            active: false,
            occupied: true,
            urgent: false,
        });
        st.windows = vec![
            window(3, Some("foot"), Some(2), false),
            window(5, Some("firefox"), Some(1), true),
            window(7, None, Some(9), false),
            window(8, Some("mpv"), None, false),
        ];
        let doc = document(&st);
        assert_eq!(
            doc["windows"],
            json!([
                {"id": 3, "app_id": "foot", "workspace": 2, "output": "DP-1", "focused": false},
                {"id": 5, "app_id": "firefox", "workspace": 1, "output": "DP-1", "focused": true},
                {"id": 7, "app_id": "", "workspace": 9, "output": null, "focused": false},
                {"id": 8, "app_id": "mpv", "workspace": null, "output": null, "focused": false},
            ])
        );
        // `tasks` still holds only the active workspace's windows.
        assert_eq!(
            doc["tasks"]["DP-1"],
            json!([{"id": 5, "app_id": "firefox", "focused": true}])
        );
        assert_eq!(document(&CompositorState::default())["windows"], json!([]));
    }

    /// K51: `window.close {id}` asks the adapter to close exactly that window; no id is refused before it.
    #[tokio::test]
    async fn window_close_closes_that_window_and_needs_an_id() {
        let fake = Arc::new(FakeCompositor::new(state(1)));
        let f = fake.clone();
        let provider = WorkspacesProvider::new(move || Shared(f.clone()));
        let mut actions = ActionRegistry::default();
        provider.register_actions(&mut actions);
        actions
            .invoke("window.close", json!({"id": 40}))
            .await
            .unwrap();
        actions
            .invoke("window.focus", json!({"id": 41}))
            .await
            .unwrap();
        let refused = actions.invoke("window.close", json!({})).await.unwrap_err();
        assert_eq!(refused.kind(), "invalid");
        assert_eq!(
            fake.actions(),
            vec![Action::CloseWindow(40), Action::FocusWindow(41)]
        );
    }

    #[tokio::test]
    async fn follows_compositor_and_stops_with_last_subscriber() {
        let fake = Arc::new(FakeCompositor::new(state(1)));
        let hub = Hub::new();
        let f = fake.clone();
        let provider = WorkspacesProvider::new(move || Shared(f.clone()));
        hub.register(DOC, json!({"outputs": {}}), Some(provider.clone()));

        hub.subscribe(DOC).unwrap();
        let wait_for = |want: u64| {
            let hub = hub.clone();
            async move {
                for _ in 0..100 {
                    let d = hub.snapshot(DOC).unwrap().1;
                    let focused = d["outputs"]["*"]
                        .as_array()
                        .and_then(|l| l.iter().find(|w| w["focused"] == json!(true)))
                        .map(|w| w["idx"].as_u64().unwrap());
                    if focused == Some(want) {
                        return d;
                    }
                    tokio::time::sleep(std::time::Duration::from_millis(5)).await;
                }
                panic!("never saw idx {want} focused");
            }
        };
        let d = wait_for(1).await;
        assert_eq!(d["outputs"]["DP-1"], d["outputs"]["*"]);
        fake.set_state(state(3));
        wait_for(3).await;
        hub.unsubscribe(DOC);
        assert!(provider.task.lock().unwrap().is_none());
    }

    #[tokio::test]
    async fn restart_and_stop_leave_no_compositor_task_behind() {
        let fake = Arc::new(FakeCompositor::new(state(1)));
        let hub = Hub::new();
        hub.register(DOC, json!({"outputs": {}}), None);
        let f = fake.clone();
        let provider = WorkspacesProvider::new(move || Shared(f.clone()));
        provider.start(hub.clone());
        // A second start replaces the first adapter: the first must be aborted, not orphaned.
        provider.start(hub.clone());
        provider.stop();
        tokio::time::sleep(std::time::Duration::from_millis(20)).await;
        let settled = hub.snapshot(DOC).unwrap().1;
        fake.set_state(state(3));
        tokio::time::sleep(std::time::Duration::from_millis(20)).await;
        assert_eq!(
            hub.snapshot(DOC).unwrap().1,
            settled,
            "a compositor task outlived stop and kept forwarding events"
        );
    }
}
