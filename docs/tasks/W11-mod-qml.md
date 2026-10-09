# Card W11-mod-qml — the frontend loads native mod components on demand (K26)

**Read first:** `docs/tasks/README.md`, `docs/MODS.md` "Native mods", `docs/PROTOCOL.md` §5 (`mods` doc `qml` map) and
§8 (`runtime.ui`: panel `mod:<id>:<name>` opened by `mod.panel.open {id, panel}` — lead adds this before the card
starts), `frontend/shell.qml`, `frontend/surfaces/Stage.qml`, `frontend/surfaces/Bar.qml`, `frontend/core/Store.qml`.

**Owned paths:** `frontend/core/ModLoader.qml` (new), `frontend/surfaces/Stage.qml` (one Loader for `mod:*` panels),
`frontend/surfaces/Bar.qml` (mod widget slot replaces the probe-era `mods.probe` Repeater + its Watch — measure
per-output PSS before/after with `just bench-gate` on a quiet machine, or report that you could not),
`frontend/components/ModNode.qml` (delete if unused after that), `frontend/test-modqml.sh` (new), and a test mod's
QML under `crates/kurashid/tests/data/mods/hello/qml/` (from W11-native-mods).

**Do:** `ModLoader { provide: "panel:hello" }` resolves the URL from the `mods` doc (`qml["panel:hello"]`) and
instantiates it with a `Loader` only while active (panel open / widget placed); unloads when the mod is disabled
(entry gone) — no stale component. Stage: `runtime.ui.panel` starting with `mod:` shows that mod panel in the card.
Bar: widgets of enabled mods that provide `widget:*` and are placed (for now: all enabled mod widgets, end of the
right row). Never preload; a missing/invalid file logs once and shows nothing (no crash).

**Acceptance:** sandbox with real kurashid (prebuilt from main after W11-native-mods, test mod dir via
`KURASHI_MODS_DIR` or the mechanism W11-native-mods documents): mod off → no component instantiated (Store/console
log), `mod.enable hello` + `mod.panel.open {id:"hello", panel:"hello"}` → screenshot shows the hello panel;
`mod.disable hello` → panel gone, Stage closed. Read the screenshots.
