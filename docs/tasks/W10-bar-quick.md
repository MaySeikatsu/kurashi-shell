# Card W10-bar-quick — a quick-settings button in the bar (K24, I2)

**Read first:** `docs/tasks/README.md`, `docs/DECISIONS.md` K24, `frontend/surfaces/Bar.qml`,
`frontend/components/{IconButton,TrayIcon}.qml`, `docs/PROTOCOL.md` §8 (`quick.toggle`, `runtime.ui.panel`).

**Owned paths:** `frontend/surfaces/Bar.qml` (right row / bottom column only: one new item),
`frontend/components/QuickButton.qml` (new), `frontend/components/qmldir` (one line — coordinate: W10-stage-panels
also adds lines; append yours at the end), `i18n/{en,ja}/frontend.toml` (add keys), `frontend/test-quick.sh` (new).

**Do:** a QuickButton at the end of the bar's right row (before the tray; both layouts): a small glyph (e.g. "◐"
or a settings glyph from the font), bar-thickness hit area (≥ 32 px), hover/focus states from tokens, a11y name
`frontend.quick.open` (en "Quick settings", ja "クイック設定"), shown "pressed" while `runtime.ui.panel === "quick"`.
Left click → `Store.act("quick.toggle")`. Per-output cost: one lightweight item (no Loader/Repeater; B7 budget).

**Acceptance:** `frontend/test-quick.sh` against `kurashi-mock` in the sandbox: a virtual-pointer click on the
button (use `tools/bench/wl_pointer.py` if present on main, else the helper in `frontend/test-bindings.sh`) makes
`runtime.ui.panel` `quick` (read with `kurashi sub runtime.ui` or the mock log); a second click closes it.
Screenshot the bar's right end, Read it, describe it. `frontend/test-real.sh` still passes.
