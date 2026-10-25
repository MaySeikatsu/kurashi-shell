use std::{
    path::PathBuf,
    sync::{Arc, Mutex},
    time::Duration,
};

use kurashi_compositor::{
    Action, Compositor, CompositorState, Direction, Event, WorkspaceRef,
    niri::{NiriCompositor, NiriState, to_request},
    workspaces_doc,
};
use serde_json::{Value, json};
use tokio::{
    io::{AsyncBufReadExt, AsyncWriteExt, BufReader},
    net::UnixListener,
    sync::Notify,
};
use tokio_stream::StreamExt;

fn fixture(name: &str) -> String {
    let p = PathBuf::from(env!("CARGO_MANIFEST_DIR"))
        .join("tests/fixtures")
        .join(name);
    std::fs::read_to_string(&p).unwrap_or_else(|e| panic!("{}: {e}", p.display()))
}

fn events(name: &str) -> Vec<niri_ipc::Event> {
    fixture(name)
        .lines()
        .map(|l| serde_json::from_str(l).unwrap())
        .collect()
}

fn outputs() -> std::collections::HashMap<String, niri_ipc::Output> {
    let reply: niri_ipc::Reply = serde_json::from_str(&fixture("live_outputs.json")).unwrap();
    match reply.unwrap() {
        niri_ipc::Response::Outputs(o) => o,
        other => panic!("{other:?}"),
    }
}

fn replayed_head() -> NiriState {
    let mut st = NiriState::default();
    for e in events("events_live_head.jsonl") {
        st.apply(e);
    }
    assert!(!st.is_synced(), "outputs are not part of the event stream");
    assert!(st.wants_outputs());
    st.set_outputs(outputs());
    assert!(st.is_synced());
    assert!(!st.wants_outputs());
    st
}

fn ws(id: u64, idx: u8, focused: bool, occupied: bool) -> Value {
    json!({"id": id, "idx": idx, "focused": focused, "occupied": occupied})
}

#[test]
fn replay_recorded_stream_yields_state_and_doc() {
    let st = replayed_head();
    let s = st.state();

    let names: Vec<_> = s
        .outputs
        .iter()
        .map(|o| (o.name.as_str(), o.focused))
        .collect();
    assert_eq!(names, [("DP-2", false), ("HDMI-A-1", true)]);
    assert_eq!(s.outputs[0].logical, (0, 0, 2560, 1440));
    assert_eq!(s.outputs[1].logical, (-1920, 0, 1920, 1080));
    assert_eq!(s.windows.len(), 4);
    assert!(!s.overview_open);

    let named: Vec<_> = s
        .workspaces
        .iter()
        .filter_map(|w| w.name.as_deref())
        .collect();
    assert_eq!(named, ["orga", "entertainment", "main", "work"]);
    let main = s.workspaces.iter().find(|w| w.id == 3).unwrap();
    assert!(main.active && !main.focused && main.occupied);

    assert_eq!(
        workspaces_doc(s),
        json!({"outputs": {
            "DP-2": [
                ws(1, 1, false, false), ws(2, 2, false, false), ws(3, 3, false, true),
                ws(4, 4, false, false), ws(5, 5, false, false),
            ],
            "HDMI-A-1": [ws(6, 1, true, true), ws(7, 2, false, false)],
        }})
    );
}

#[test]
fn incremental_events_emit_only_real_changes() {
    let mut st = replayed_head();
    let mut out = Vec::new();
    for e in events("events_incremental.jsonl") {
        out.push(st.apply(e));
    }
    let kinds: Vec<Vec<&str>> = out
        .iter()
        .map(|evs| {
            evs.iter()
                .map(|e| match e {
                    Event::Outputs(_) => "outputs",
                    Event::Workspaces(_) => "workspaces",
                    Event::Windows(_) => "windows",
                    Event::Overview(_) => "overview",
                    Event::Keyboard(_) => "keyboard",
                    Event::Resync => "resync",
                })
                .collect()
        })
        .collect();
    assert_eq!(
        kinds,
        [
            vec!["workspaces", "windows"], // new window: ws7 occupied, focus moves
            vec!["workspaces"],            // ws7 activated
            vec![],                        // focus timestamp: noise, stays silent
            vec!["workspaces"],            // ws5 urgent
            vec!["windows"],               // 24 closed, ws6 still holds 29
            vec!["workspaces", "windows"], // 29 closed: ws6 empty
            vec![],                        // unknown workspace: ignored, no panic
            vec!["overview"],
        ]
    );

    let s = st.state();
    assert!(s.overview_open);
    assert_eq!(
        workspaces_doc(s)["outputs"]["HDMI-A-1"],
        json!([ws(6, 1, false, false), ws(7, 2, true, true)])
    );
    assert!(s.workspaces.iter().find(|w| w.id == 5).unwrap().urgent);
    assert_eq!(s.windows.iter().filter(|w| w.focused).count(), 1);
}

/// W36 (I137): a window's urgency follows niri's `WindowUrgencyChanged` into `Window::urgent`, as a windows change;
/// the same value again is silent, and an unknown id is ignored.
#[test]
fn window_urgency_follows_the_stream() {
    let mut st = replayed_head();
    let id = st.state().windows[0].id;
    assert!(!st.state().windows[0].urgent);
    let evs = st.apply(niri_ipc::Event::WindowUrgencyChanged { id, urgent: true });
    assert!(matches!(evs.as_slice(), [Event::Windows(_)]), "{evs:?}");
    assert!(
        st.state()
            .windows
            .iter()
            .find(|w| w.id == id)
            .unwrap()
            .urgent
    );
    assert!(
        st.apply(niri_ipc::Event::WindowUrgencyChanged { id, urgent: true })
            .is_empty()
    );
    assert!(
        st.apply(niri_ipc::Event::WindowUrgencyChanged {
            id: 999_999,
            urgent: true
        })
        .is_empty()
    );
    st.apply(niri_ipc::Event::WindowUrgencyChanged { id, urgent: false });
    assert!(
        !st.state()
            .windows
            .iter()
            .find(|w| w.id == id)
            .unwrap()
            .urgent
    );
}

#[test]
fn keyboard_layouts_follow_the_stream() {
    let mut st = replayed_head();
    let k = st
        .state()
        .keyboard
        .clone()
        .expect("the live head names the layouts");
    assert_eq!(k.names, ["English (intl., with AltGr dead keys)", "German"]);
    assert_eq!(k.current, 0);
    let ev = st.apply(niri_ipc::Event::KeyboardLayoutSwitched { idx: 1 });
    assert_eq!(ev.len(), 1);
    assert!(matches!(&ev[0], Event::Keyboard(Some(k)) if k.current == 1));
    assert!(
        st.apply(niri_ipc::Event::KeyboardLayoutSwitched { idx: 1 })
            .is_empty(),
        "no change, no event"
    );
}

#[test]
fn k47_actions_serialize_as_niri_ipc_json() {
    use kurashi_compositor::LayoutTarget;
    let j = |a: Action| serde_json::to_value(to_request(&a)).unwrap();
    assert_eq!(
        j(Action::PowerOffMonitors),
        json!({"Action": {"PowerOffMonitors": {}}})
    );
    assert_eq!(
        j(Action::SwitchLayout(LayoutTarget::Next)),
        json!({"Action": {"SwitchLayout": {"layout": "Next"}}})
    );
    assert_eq!(
        j(Action::SwitchLayout(LayoutTarget::Index(1))),
        json!({"Action": {"SwitchLayout": {"layout": {"Index": 1}}}})
    );
    assert_eq!(
        j(Action::ScreenshotRegion),
        json!({"Action": {"Screenshot": {"show_pointer": false, "path": null}}})
    );
    assert_eq!(
        j(Action::ScreenshotScreen),
        json!({"Action": {"ScreenshotScreen": {"write_to_disk": true, "show_pointer": false, "path": null}}})
    );
    assert_eq!(
        j(Action::ScreenshotWindow),
        json!({"Action": {"ScreenshotWindow": {"id": null, "write_to_disk": true, "show_pointer": false, "path": null}}})
    );
}

#[test]
fn actions_serialize_as_niri_ipc_json() {
    let j = |a: Action| serde_json::to_value(to_request(&a)).unwrap();
    // K51: the dock closes a window by its id, never "the focused one" (niri-ipc's race note).
    assert_eq!(
        j(Action::CloseWindow(40)),
        json!({"Action": {"CloseWindow": {"id": 40}}})
    );
    assert_eq!(
        j(Action::FocusWorkspace(WorkspaceRef::Idx(2))),
        json!({"Action": {"FocusWorkspace": {"reference": {"Index": 2}}}})
    );
    assert_eq!(
        j(Action::FocusWorkspace(WorkspaceRef::Id(7))),
        json!({"Action": {"FocusWorkspace": {"reference": {"Id": 7}}}})
    );
    assert_eq!(
        j(Action::FocusWindow(34)),
        json!({"Action": {"FocusWindow": {"id": 34}}})
    );
    assert_eq!(
        j(Action::MoveWindowToWorkspace {
            window_id: 34,
            workspace: WorkspaceRef::Id(3)
        }),
        json!({"Action": {"MoveWindowToWorkspace":
            {"window_id": 34, "reference": {"Id": 3}, "focus": true}}})
    );
    assert_eq!(
        j(Action::ScrollColumn(Direction::Left)),
        json!({"Action": {"FocusColumnLeft": {}}})
    );
    assert_eq!(
        j(Action::ScrollColumn(Direction::Right)),
        json!({"Action": {"FocusColumnRight": {}}})
    );
}

/// Minimal niri stand-in. Event-stream connection #0 replays the recorded head and is then
/// dropped on cue; #1 serves a smaller world and stays open. Actions are recorded.
async fn fake_niri(path: PathBuf, drop_first: Arc<Notify>, actions: Arc<Mutex<Vec<String>>>) {
    let listener = UnixListener::bind(&path).unwrap();
    let mut generation = 0;
    loop {
        let (stream, _) = listener.accept().await.unwrap();
        let (rd, mut wr) = stream.into_split();
        let mut first = String::new();
        BufReader::new(rd).read_line(&mut first).await.unwrap();
        if first.contains("EventStream") {
            let gen_now = generation;
            generation += 1;
            let drop_first = drop_first.clone();
            tokio::spawn(async move {
                wr.write_all(b"{\"Ok\":\"Handled\"}\n").await.unwrap();
                if gen_now == 0 {
                    wr.write_all(fixture("events_live_head.jsonl").as_bytes())
                        .await
                        .unwrap();
                    drop_first.notified().await; // then `wr` drops: connection closes
                } else {
                    let line = fixture("events_live_head.jsonl");
                    let ws_line = line.lines().next().unwrap();
                    let mut v: Value = serde_json::from_str(ws_line).unwrap();
                    let list = v["WorkspacesChanged"]["workspaces"].as_array_mut().unwrap();
                    list.truncate(1);
                    wr.write_all(format!("{v}\n").as_bytes()).await.unwrap();
                    wr.write_all(b"{\"WindowsChanged\":{\"windows\":[]}}\n")
                        .await
                        .unwrap();
                    std::future::pending::<()>().await;
                }
            });
        } else if first.contains("Outputs") {
            wr.write_all(fixture("live_outputs.json").as_bytes())
                .await
                .unwrap();
        } else {
            actions.lock().unwrap().push(first.trim().to_string());
            wr.write_all(b"{\"Ok\":\"Handled\"}\n").await.unwrap();
        }
    }
}

#[tokio::test]
async fn dropped_connection_yields_resync_then_full_state() {
    let path = std::env::temp_dir().join(format!("kurashi-fake-niri-{}.sock", std::process::id()));
    let _ = std::fs::remove_file(&path);
    let drop_first = Arc::new(Notify::new());
    let actions = Arc::new(Mutex::new(Vec::new()));
    let server = tokio::spawn(fake_niri(path.clone(), drop_first.clone(), actions.clone()));
    // Listener must exist before the adapter first connects (it would retry, but be quick).
    while !path.exists() {
        tokio::time::sleep(Duration::from_millis(5)).await;
    }

    let niri = NiriCompositor::spawn(&path);
    let mut stream = niri.events();
    let t = Duration::from_secs(5);

    let first: CompositorState = tokio::time::timeout(t, niri.snapshot())
        .await
        .unwrap()
        .unwrap();
    assert_eq!(first.workspaces.len(), 7);
    assert_eq!(first.outputs.len(), 2);

    drop_first.notify_one();
    let saw_resync = tokio::time::timeout(t, async {
        while let Some(e) = stream.next().await {
            if e == Event::Resync {
                return true;
            }
        }
        false
    })
    .await
    .unwrap();
    assert!(saw_resync);

    // Backoff (250 ms) elapses, the adapter reconnects, snapshot is the *new* full state.
    let second = tokio::time::timeout(t, niri.snapshot())
        .await
        .unwrap()
        .unwrap();
    assert_eq!(second.workspaces.len(), 1);
    assert!(second.windows.is_empty());
    assert_eq!(second.outputs.len(), 2);

    niri.act(Action::FocusWorkspace(WorkspaceRef::Idx(2)))
        .await
        .unwrap();
    assert_eq!(
        *actions.lock().unwrap(),
        [r#"{"Action":{"FocusWorkspace":{"reference":{"Index":2}}}}"#]
    );

    server.abort();
    let _ = std::fs::remove_file(&path);
}
