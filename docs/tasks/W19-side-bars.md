# Card W19-side-bars — bar widgets on left and right bars (I85)

**Decision (lead):** a bar on the left or right edge is a first-class bar. Its widgets take a **vertical form** (glyph
over a short value, or the glyph alone with the value in the peek) instead of overflowing a ~32 px bar. The keyboard
path into bar widgets is not in this card (I67 open).
**Briefs:** `docs/ux/island.md` (the pill), `docs/ux/sysmon.md` and `docs/ux/weather.md` (their widgets),
DESIGN-SYSTEM §7–§9.

**Read first:** `docs/tasks/README.md` (rules), I85 in `docs/BACKLOG.md`, `frontend/surfaces/{Bar,BarConfig}.qml` (the
`verticalLayout` exists), `frontend/components/{Island,TrayIcon}.qml`, `frontend/components/faces/`,
`mods/sysmon/qml/Widget.qml`, `mods/weather/qml/Widget.qml`, `crates/kurashid/tests/data/mods/hello/qml/Widget.qml`,
`frontend/shots/peek/sysmon-peek-left.png` (the overflow), `frontend/test-peek.sh` (how it starts side bars).

**Owned paths:** `frontend/surfaces/Bar.qml`, `frontend/components/{Island,TrayIcon}.qml`, `frontend/components/faces/**`,
`mods/sysmon/qml/Widget.qml`, `mods/weather/qml/Widget.qml`, `crates/kurashid/tests/data/mods/hello/qml/Widget.qml`,
new `frontend/test-sidebars.sh` + `frontend/shots/sidebars/**`, `i18n/{en,ja}/frontend.toml` (append a block marked
`# W19-side-bars`). Not yours: `frontend/surfaces/Stage.qml`, `frontend/components/SlotHost.qml`,
`frontend/components/expanded/**` (W19-calendar), any other file under `mods/weather/` or `mods/wallpaper/`
(W19-weather, W19-wallpaper), `crates/**` except the hello widget.

**Do:**
1. The bar hands every widget `vertical: true` on a left/right bar (a property mod widgets may declare; ModLoader
   passes it when declared). Core widgets (island pill, clock, workspaces, tray) and the sysmon, weather and hello
   widgets draw a vertical form: nothing crosses the bar's width, text never rotates, the value shortens (e.g. "42%",
   "21°") or moves to the peek; a11y names keep the full value.
2. The island pill on a side bar is a compact column (face glyph + one short line); secondary and overflow marks stack.
3. Widget spacing and order follow the horizontal bar's, top to bottom; the bar's length holds all default widgets on a
   1080 px tall output without clipping (overflowing widgets hide from the end, with the hidden count).

**Acceptance:** `timeout 900 frontend/test-sidebars.sh` (mock + real daemon for the mod widgets, sandbox) green with
shots for left and right bars: default widgets, sysmon/weather/hello on, a long tray, a narrow (720 px tall) output,
ja; every widget's bounding box inside the bar (asserted from the QML item geometry the test logs, not only by eye);
no QML warnings. `frontend/test-peek.sh` and `frontend/test-stage.sh` still green.
