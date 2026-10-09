# Card M4-bluetooth — BlueZ service (not wired)

**Goal.** `svc.bluetooth` provider in `kurashi-services`, event-driven, refcountable.

**Owned paths:** new `crates/kurashi-services/src/bluetooth.rs`, one `pub mod bluetooth;` line in
`crates/kurashi-services/src/lib.rs`, `crates/kurashi-services/Cargo.toml` (deps only),
`crates/kurashi-services/tests/` (new files only). Common rules: `docs/tasks/README.md`.

**Read:** `crates/kurashi-services/src/{lib.rs,util.rs,network.rs,power.rs}` (mirror the pattern
and its tests exactly), BlueZ D-Bus API (org.bluez Adapter1/Device1, ObjectManager).

**Build:**
1. `start(sink) -> ServiceHandle` on the **system** bus (address injectable for tests): ObjectManager
   `GetManagedObjects` once, then InterfacesAdded/Removed + PropertiesChanged signals; no polling.
2. Doc `{available, powered, discovering, devices:[{address, name, icon?, paired, connected,
   battery?}]}` sorted connected → paired → name; omit absent fields (no nulls). No adapter →
   `{available:false}`.
3. Commands: `set_powered(bool)`, `connect(addr)`, `disconnect(addr)`, `start_discovery()` /
   `stop_discovery()` (discovery auto-stops when the handle drops).

**Acceptance:** `cargo test -p kurashi-services` green, including a test with a fake `org.bluez`
object tree on a private `dbus-daemon`: adapter+device appear, `Connected` change updates the doc,
device removal removes it, `set_powered` reaches the fake. clippy clean.
