# Card C-services — one refcounted service provider, with bus reconnect

**Read first:** `crates/kurashid/src/services.rs` (`ServiceProvider`), `crates/kurashid/src/wiring.rs`
(`RefcountedService`, `tray_with`, `bluetooth_with`, `service_action`), `crates/kurashi-services/src/util.rs`
(`ServiceHandle`, `follow`, `ended`), `docs/CONTRACT-CHANGE.md` rows 15–16, `docs/ARCHITECTURE.md`
(services, Ma), review R.1 finding on bus loss.

**Owned paths:** `crates/kurashid/src/services.rs`, `crates/kurashid/src/wiring.rs` (service parts only:
`RefcountedService`, `tray*`, `bluetooth*`, `service_action`, the provider at ~line 707 — NOT the
`runtime.ui` actions at the top), `crates/kurashid/src/main.rs` (provider construction lines only),
`crates/kurashi-services/src/util.rs`, `crates/kurashi-tray/src/lib.rs` (handle type only, if needed),
new `crates/kurashid/tests/services_reconnect.rs`. NOT `crates/kurashi-services/src/session.rs`
(card L-logind owns it), not the service `start` signatures of other modules.
Common rules: `docs/tasks/README.md`.

**Do:**
1. **Fold** `RefcountedService` into `ServiceProvider` (CONTRACT-CHANGE row 16): one provider type,
   generic over the handle type (`H: Send + 'static`, dropped = stopped) so kurashi-tray keeps its own
   handle, with the bus connect function injected (`ConnectFn`; `Bus::Session/System` become the two
   stock connect fns). svc.tray / svc.bluetooth / media / power / session / network / brightness all use it.
   Behaviour unchanged: start on first subscriber, stop on last, a start that finishes after `stop` is
   discarded (generation), actions never start a service (`error.service.not_running`).
2. **Reconnect** at connection level: today a lost bus (dbus-daemon restart, BlueZ/system bus hiccup)
   leaves the service `available:false` forever. While the provider has subscribers and its running
   service ends (task finished / stream ended / connection closed), restart it with backoff
   (250 ms → 30 s, reset after a healthy minute); a failed initial connect retries the same way. Stop
   cancels any pending retry. No timer exists while nobody subscribes (Ma). Log each retry once at
   `info`, not per attempt at `warn`.
3. Remove the RefcountedService copy and its now-dead helpers; mark row 16 in your report (the lead
   updates the table).

**Acceptance:** new `crates/kurashid/tests/services_reconnect.rs` on a private `dbus-daemon` (pattern:
existing tray/bluetooth tests in `wiring.rs`): subscribe → service available → kill the bus daemon →
document goes `available:false` → start a new bus daemon at the same address → document returns to
`available:true` within 5 s, without re-subscribing; unsubscribe → no retry task left (assert via the
provider's state). Plus the existing tray/bluetooth/media tests unchanged and green;
`cargo clippy -p kurashid --all-targets -- -D warnings`; `cargo test -p kurashid -p kurashi-services -p kurashi-tray`.
