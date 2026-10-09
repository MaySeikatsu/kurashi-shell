# Card M4-compositor — `kurashi-compositor` (trait + niri adapter)

**Goal.** One `Compositor` trait the daemon talks to; niri is the first adapter (Hyprland,
MangoWM, Sway later — adapters only, no core changes).

**Owned paths:** `crates/kurashi-compositor/`. Common rules: `docs/tasks/README.md` (read first).

**Read:** `docs/ARCHITECTURE.md` §7, `docs/PROTOCOL.md` §8 (`svc.workspaces` shape),
`crates/kurashi-mock/src/main.rs` (`workspaces_doc` — your output must match that shape).

**Build:**
1. Types: `Output { name, make, model, logical: (x,y,w,h), scale, focused }`,
   `Workspace { id, idx, name, output, focused, active, occupied, urgent }`,
   `Window { id, app_id, title, workspace_id, focused, floating }`, `CompositorState`.
2. `#[async_trait]`-free async trait (edition 2024 `async fn` in traits or boxed futures):
   `snapshot() -> CompositorState`, `events() -> impl Stream<Item = Event>` (incremental events +
   `Event::Resync` after reconnect — subscribers drop state and await a fresh snapshot),
   `act(Action) -> Result<()>` (focus workspace idx/id, focus window, move window to workspace,
   scroll column left/right — keep the enum small), `capabilities() -> Capabilities` (bitflags-ish:
   `scroll_position`, `overview`, `window_previews`, `blur_hint`, `workspace_names`).
3. `niri` adapter using the `niri-ipc` crate matching **niri 26.04** (the user's version): one
   event-stream connection (`Request::EventStream`) maintaining state incrementally; separate
   short-lived request connections for actions; reconnect with backoff 250 ms → 4 s, then emit
   `Resync`. No polling.
4. `FakeCompositor` (scriptable, for daemon/frontend tests) behind a `fake` feature or public module.
5. `fn workspaces_doc(&CompositorState) -> serde_json::Value` producing exactly the
   `svc.workspaces` shape (`{"outputs":{"<name>":[{id,idx,focused,occupied},…]}}`) — superset
   fields allowed only if you add a CONTRACT-CHANGE row for them.

**Live niri:** the user is running niri. You MAY connect to `$NIRI_SOCKET` to *record fixtures*
using read-only requests (`Version`, `Outputs`, `Workspaces`, `Windows`, `FocusedOutput`,
`EventStream` for ≤ 30 s). You must NEVER send `Request::Action` or any state-changing request to
the live compositor. Scrub window titles in recorded fixtures (replace with `"title-N"`).

**Acceptance (one command):** `cargo test -p kurashi-compositor` green, including: replaying a
recorded niri event-stream fixture (`tests/fixtures/*.jsonl`) produces the expected
`CompositorState` and `workspaces_doc`; a test that a dropped connection yields `Resync` then a
full state (using a fake unix-socket server in the test); action serialization matches niri-ipc
JSON. Clippy `-D warnings`.
