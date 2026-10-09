# Card W9-tray — wait for the watcher name instead of retrying (B4) + `item_is_menu` (row 20)

**Read first:** `docs/tasks/README.md`, `docs/BACKLOG.md` row B4, `docs/CONTRACT-CHANGE.md` row 20,
`docs/PROTOCOL.md` §7 (`svc.tray`, K27), `fixtures/ipc/server/snap_tray.json` (item 2 is menu-only),
`crates/kurashi-tray/src/{lib,item}.rs`, `crates/kurashid/src/services.rs` (read-only: the provider
restarts a failed start with backoff 250 ms → 30 s), SNI spec
(https://www.freedesktop.org/wiki/Specifications/StatusNotifierItem/StatusNotifierItem/ — `ItemIsMenu`).

**Problems:** (1) When another shell owns `org.kde.StatusNotifierWatcher`, `start` fails, and the
provider retries every ≤ 30 s while a bar subscribes: an idle wakeup for nothing (rule 5, Ma).
(2) Menu-only items (`ItemIsMenu` true) cannot be told apart, so a left click sends `tray.activate`,
which they ignore. The frontend already reads `item_is_menu === true`.

**Owned paths:** `crates/kurashi-tray/**` (src + tests). NOT kurashid, not the fixtures/PROTOCOL
(already updated by the lead), not the frontend.

**Do:**
- If the watcher name is taken: `start` succeeds into a *waiting* state — the document is
  `{available:false, items:[]}` (no new fields), and the service subscribes to `NameOwnerChanged` for the
  watcher name only; when the name is released, take it over and continue normally (`available:true`).
  No timers, no polling. If the other owner comes back later, nothing changes (we own it then).
- Read `ItemIsMenu` with the other item properties (and on `PropertiesChanged`/`NewStatus`-style refreshes
  where the item re-reads its props); serialise `item_is_menu: true` only when true (omit otherwise,
  `#[serde(skip_serializing_if)]`), matching the fixture.

**Acceptance:** private-bus tests (`crates/kurashi-tray/tests/`): (a) a fake process owns the watcher name
→ `start` returns Ok, document `available:false`; release the name → within 2 s the document turns
`available:true` and a registered item appears; no task wakes up while waiting (assert by structure:
the waiting path awaits only the NameOwnerChanged stream); (b) an item exporting `ItemIsMenu=true`
serialises with `"item_is_menu":true`, one with false/absent has no such key; (c) the serialised item
of the fixture's second entry equals `fixtures/ipc/server/snap_tray.json` item 2 field by field.
`timeout 600 cargo test -p kurashi-tray`, clippy -D warnings.
