# Card M0-mock-parity — kurashi-mock serves what the frontend now uses

**Goal.** Frontend work against `kurashi-mock` sees the same documents/actions as the real daemon.

**Owned paths:** `crates/kurashi-mock/` only. Common rules: `docs/tasks/README.md`.

**Read:** `crates/kurashi-mock/src/` (all), `docs/PROTOCOL.md` §8 + the `runtime.ui` row,
`crates/kurashid/src/{wiring.rs,bindings.rs}` (shapes to mirror), `frontend/core/Store.qml` (what it
subscribes to).

**Build:** in the mock, with the same shapes as kurashid:
1. `runtime.ui` `{popup, panel, launcher}` + actions `island.expand`, `notifications.center`,
   `session.menu`, `launcher.toggle`, `ui.close` (keep `probe.popup.toggle`).
2. `bindings` doc with the island defaults (`island.main`: left `island.expand`, right `island.pin`,
   scroll_up `island.prev`, scroll_down `island.next`, source `default`) + `input.dispatch`.
3. `svc.brightness` (fake 0.5) + `brightness.up/down`, `session.lock` and
   `session.{suspend,logout,reboot,poweroff}` returning error code `session.confirm_required`
   without `{confirm:true}` (with confirm: succeed as a no-op and log).
4. `kurashi mock face <name>` keeps working for `brightness`.

**Acceptance:** `cargo test -p kurashi-mock` green with tests for each item; running the mock and
`qs -p frontend` in a sandbox logs no `unknown_doc`/`unknown_action` for these. clippy clean.
