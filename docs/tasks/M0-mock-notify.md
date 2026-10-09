# Card M0-mock-notify — mock serves notifications, launcher query, instance, fixed clock

**Owned paths:** `crates/kurashi-mock/` only. Common rules: `docs/tasks/README.md`.

**Read:** `crates/kurashi-mock/src/` (just reworked: `State::act`), `crates/kurashid/src/wiring.rs`
(`notifications_with_facts`, `launcher` — shapes to mirror), `crates/kurashid/src/server.rs` (query),
`frontend/surfaces/{Toasts,NotificationCenter,Launcher}.qml` (what they use).

**Build (same shapes as kurashid):**
1. `svc.notifications` with 3 fake notifications (one critical, one with actions) + `notify.dismiss`,
   `notify.invoke`, `notify.mark_read`, `notify.dnd`; `kurashi mock notify <summary>` adds one.
2. Launcher `query` answering from ~10 fake apps (substring match is enough) + `launcher.launch`
   (logs, no spawn).
3. `welcome.instance`: a random id per mock process.
4. `--fixed-time HH:MM` flag: the clock doc reports that time and never ticks (deterministic
   screenshots for golden tests).

**Acceptance:** `timeout 600 cargo test -p kurashi-mock` green with a test per item; in a sandbox the
mock + `qs -p frontend` log no `unknown_doc`/`unknown_action` while opening notification center and
launcher. clippy clean.
