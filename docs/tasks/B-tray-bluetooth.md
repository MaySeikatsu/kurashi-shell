# Card B-tray-bluetooth — tray widget, tray menu, Bluetooth in the island panel, island hit area

**Read first:** `docs/PROTOCOL.md` §7 (svc.tray / svc.bluetooth) and §8 (`runtime.ui`, incl. the tray
panel, K23), `fixtures/ipc/server/snap_{tray,bluetooth}.json`, `docs/DECISIONS.md` K16/K19/K23,
`docs/DESIGN-SYSTEM.md` §6–§7, `frontend/README.md`, `frontend/surfaces/{Bar,Stage}.qml`,
`frontend/shell.qml`, `frontend/components/Island.qml`, `crates/kurashi-mock/src/state.rs`.

**Owned paths:** `frontend/surfaces/{Bar,Stage}.qml`, `frontend/shell.qml`,
`frontend/components/Island.qml` (hit area only), new `frontend/components/{Tray,TrayMenu,Bluetooth}*.qml`
(+ `components/qmldir`), `i18n/{en,ja}/frontend.toml` and `surfaces.toml`, `crates/kurashi-mock/`,
`tools/golden/run.sh` (system-bus isolation only), new `frontend/test-tray-bt.sh`.
NOT `crates/kurashid/`, `crates/kurashi-tray/`, `settings/`, `frontend/core/`, fixtures, PROTOCOL.
Common rules: `docs/tasks/README.md`.

**Build:**
1. **Mock** (`kurashi-mock`): serve `svc.tray` and `svc.bluetooth` with the fixture contents
   (`snap_tray.json`, `snap_bluetooth.json`, a second tray item with an `icon_name` only);
   `tray.{activate,secondary,scroll,menu_event}` logged + `done`; `tray.menu {id}` returns a small fixed
   tree in kurashi-tray's shape (`{id:0, enabled:true, children:[{id, label?, separator?, enabled,
   icon_name?, toggle?, checked?, children?}]}` — one separator, one checkmark, one submenu);
   `bluetooth.power {on}` / `connect|disconnect {address}` / `scan {on}` mutate the mock doc. Also add
   `available: true` to the mock's `svc.session`, `svc.media`, `svc.power` (kurashid has it, F.4).
   Unit tests beside the existing ones in `state.rs`.
2. **Tray widget** in the bar (both layouts): one icon per item (`icon_pixmap` → `data:image/png;base64,…`,
   else `icon_name` via Quickshell's icon lookup, honouring `icon_theme_path`), tooltip from `tooltip`
   (hover, no polling). Left click → `tray.activate {id, x, y}` (screen coordinates); middle →
   `tray.secondary`; wheel → `tray.scroll {id, delta, orientation}`; right click (or left when the item
   is menu-only, `status`/`has_menu` as the daemon reports) → `tray.menu.open {id}`. Nothing shown and no
   per-item delegates while `items` is empty or `available` is false. `status: "Passive"` items hidden,
   `"NeedsAttention"` marked by the theme's accent, not by motion.
3. **Tray menu in the Stage** (K23): when `runtime.ui.panel === "tray"`, the Stage card shows the menu of
   `runtime.ui.tray`, fetched once per open with `Store.act("tray.menu", {id})` (action data, not a doc);
   separators, disabled entries, checkmark/radio state, submenus inline (indent or drill-down, calm);
   click → `tray.menu_event {id, item}` then `ui.close`. Keyboard: arrows, Return, Esc. The card aligns
   to the bar's end where the tray sits (re-anchor the one Stage; never a new window per menu — K16/K19).
   `shell.qml` re-picks the Stage output for the tray panel as it does for the session menu.
4. **Bluetooth in the island panel** (Stage `island` content): watch `svc.bluetooth` only while the panel
   is open (Ma). Hidden entirely while `available` is false. Otherwise: a power Toggle
   (`bluetooth.power`), paired devices with connect/disconnect (`bluetooth.connect|disconnect`), battery
   if present, and a scan toggle (`bluetooth.scan`) showing unpaired devices while `discovering`.
   Errors from actions → translated line (never raw `msg`).
5. **Island hit area** (review #11): the island stays visually `barH - 10` tall but its pointer target is
   the full bar thickness (≥ 32 px). Note `Island` has `clip: true`, and Qt does not deliver pointer
   events to children outside a clipping parent — move/extend the MouseArea in `Bar.qml` (or an
   unclipped wrapper), keep `slots`/`activated` semantics unchanged.
6. **Golden isolation:** `tools/golden/run.sh` starts kurashid with
   `DBUS_SYSTEM_BUS_ADDRESS=unix:path=$R/no-system-bus` so svc.bluetooth is `available:false` whatever
   the host has (deterministic captures). Nothing else in the harness changes.

**Safety:** never invoke `bluetooth.*` or `tray.*` against the real daemon on the real system bus; test
actions only against the mock. Never run anything on the user's display.

**Budget:** per-output PSS is at its limit (+6.0 of ≤ +6 MiB on machine A). No new windows per output;
delegates only for existing items; Loaders inactive while empty. The lead measures `just bench-gate`.

**Build constraint:** frontend work uses the prebuilt daemon (`KURASHI_BIN_DIR`, path in the prompt);
build only `kurashi-mock` (`cargo build -p kurashi-mock && cp …` per README rule 3).

**Acceptance:** `cargo test -p kurashi-mock` green; new `frontend/test-tray-bt.sh` (sandbox + mock) captures
bar with tray, tray menu open, island panel with Bluetooth (powered, one connected device), and fails on
any QML error — Read every screenshot; `frontend/test-real.sh` passes; `just golden` with
`KURASHI_GOLDEN_REF=tools/golden/ref-machine-b` passes **unchanged** (empty tray + unavailable
Bluetooth render nothing new; the island hit area is invisible).
