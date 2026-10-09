# Card M5-ui-launcher — app launcher surface

**Owned paths:** `frontend/surfaces/Launcher.qml`, `frontend/components/Launcher*.qml`,
`i18n/{en,ja}/launcher.toml`, one line in `frontend/shell.qml`. Common rules: `docs/tasks/README.md`.

**Common for wave-5 UI cards:** build on the frontend core API (`Store.watch/unwatch/docs/act/intent/query`, `Theme`, `I18n` — see `frontend/README.md`); token-only styling; strings via `I18n.tr` with keys in `i18n/{en,ja}/<your-domain>.toml` (you own your domain files); every animation visibility-gated; test only in `tools/bench/sandbox.sh` with a real `kurashid` (isolated XDG dirs, sandbox bus — see `frontend/test-real.sh`); add exactly one line to `frontend/shell.qml` to instantiate your surface (the lead resolves trivial conflicts); new QML types in the folder `qmldir`. Acceptance always includes: `just bench-gate` still green (idle 0 frames, budgets) and sandbox screenshots you verified.

**Build:** a centered layer surface with exclusive keyboard focus while open (opened via
`runtime.ui.launcher` — add a CONTRACT-CHANGE row requesting the field and a `launcher.toggle` action;
until then test with an IPC hook like settings/ does), search field (IME-capable TextInput), results from
`Store.query("launcher", q)` (stale ids dropped), keyboard nav (↑↓, Enter → `act launcher.launch {id}`,
Esc closes), app icons via Quickshell icon lookup with a text fallback, results update per keystroke
without animation churn; reveal on first frame; 0 frames when closed. Test with fake .desktop files in
the sandbox's `XDG_DATA_HOME/applications` (never launch real apps: point `launcher.terminal` at
`true` and use `Exec=true` entries).
