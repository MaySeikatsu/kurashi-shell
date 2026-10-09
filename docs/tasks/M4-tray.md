# Card M4-tray — StatusNotifierItem tray (new crate, not wired)

**Goal.** System tray support (SNI) as a refcountable service in a new crate `crates/kurashi-tray`.

**Owned paths:** new `crates/kurashi-tray/` only. Common rules: `docs/tasks/README.md`.

**Read:** `crates/kurashi-services/src/{util.rs,media.rs}` (DocSink/Emitter/ServiceHandle pattern to
mirror), `crates/kurashi-notify/src/lib.rs` (non-stealing bus-name claim + private-bus tests),
spec: https://www.freedesktop.org/wiki/Specifications/StatusNotifierItem/ (KDE flavour
`org.kde.StatusNotifierWatcher`).

**Build:**
1. Watcher: claim `org.kde.StatusNotifierWatcher` with DoNotQueue — never steal; if another watcher
   owns it, act as a host of that watcher instead. Register as host.
2. Item tracking via signals only (NameOwnerChanged, NewIcon/NewTitle/NewStatus …); no polling.
3. `start(sink) -> ServiceHandle` emitting `svc.tray` `{available, items:[{id, title, icon_name,
   icon_pixmap?: {w,h,png_base64}, status, tooltip?, has_menu}]}` (no nulls: omit absent fields).
4. Commands: `activate(id, x, y)`, `secondary_activate`, `scroll(id, delta, orientation)`;
   menus (com.canonical.dbusmenu) → `menu(id) -> Value` tree + `menu_event(id, item_id)`.
5. Drop stops everything (threads/tasks joined, names released).

**Acceptance:** `cargo test -p kurashi-tray` green on a private `dbus-daemon` (pattern in
kurashi-notify tests): fake item registers → appears in the doc; title change → doc updates;
item exits → removed; second watcher present → we don't steal. clippy clean.
