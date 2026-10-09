# Card M4-wire-tray-bt — wire tray + Bluetooth into kurashid; shutdown and lockout fixes

**Owned paths:** `crates/kurashid/src/{main.rs,wiring.rs,doctor.rs}`, `crates/kurashi-tray/`,
`crates/kurashi-auth/`, `i18n/{en,ja}/{session,doctor}.toml`, `fixtures/ipc/` (new fixtures for
`svc.tray`, `svc.bluetooth` only), `crates/kurashi-ipc/tests/` (only to register those fixtures).
NOT `hub.rs`/`server.rs`/`clock.rs`/`workspaces.rs`/`services.rs` (F-hub-server), not `config.rs`
(M1-inert-reasons). Common rules: `docs/tasks/README.md`.

**Read:** `crates/kurashi-tray/src/lib.rs` (start/Commands), `crates/kurashi-services/src/bluetooth.rs`,
`crates/kurashid/src/{main.rs,wiring.rs,services.rs}` (refcounted `ServiceProvider` pattern),
`crates/kurashid/src/doctor.rs`, `crates/kurashi-auth/src/session.rs`.

**Build:**
1. `svc.tray` (session bus) and `svc.bluetooth` (system bus) as refcounted providers: start on first
   subscriber, drop the handle on last. Actions: `tray.activate {id,x,y}`, `tray.secondary {id,x,y}`,
   `tray.scroll {id,delta,orientation}`, `tray.menu {id}` (returns the tree in `done.data`),
   `tray.menu_event {id,item}`; `bluetooth.power {on}`, `bluetooth.connect {address}`,
   `bluetooth.disconnect {address}`, `bluetooth.scan {on}`. Errors → i18n keys. Not subscribed →
   error, never auto-start a provider from an action.
2. Tray: add optional `icon_theme_path` to the item doc (needed to resolve libappindicator icons).
3. Golden fixtures for both docs (no nulls) registered in the ipc fixture test.
4. Shutdown hang (review R.1 #3): main must not wait forever on a blocking PAM conversation. Build
   the runtime manually with `shutdown_timeout` (e.g. 2 s) after `serve` returns, and/or cancel open
   lock conversations before returning. Regression test with a fake two-prompt authenticator.
5. Lockout guard: if the K20 `locked` marker exists at startup but the PAM service `kurashi` is missing,
   still start locked (never unlock on restart) but log an error and make `kurashi doctor` report a
   failing `pam_service` check with the fix ("enable programs.kurashi in the NixOS module").
   `kurashi doctor` also reports `pam_service` when not locked.
6. Review #14: `watch_while_open` spawns a blocking task on every hub event; only act when
   `runtime.ui.launcher` actually changed.

**Acceptance:** `timeout 900 cargo test -p kurashid -p kurashi-tray -p kurashi-auth -p kurashi-ipc`
green with tests for 1 (subscribe → started, last unsubscribe → stopped, action without subscriber →
error), 4, 5; clippy clean.
