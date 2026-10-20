# Card W25-dock — an app dock (K51; roadmap v0.2 "dock")

**User (session 10):** "as complete and usable as possible … take actual code from Caelestia, Noctalia, DMS, ii if they
solved it." Efficient: QML prototype with placeholder windows first, then the small Rust part, few compiles.

**References (copy what solves it, note the source):** DMS `/tmp/claude-1000/-home-maike-Projects-kurashi-shell/dbcea378-a7d4-4c51-ac59-ac9689ce0b5f/scratchpad/insp/DankMaterialShell/quickshell/Modules/Dock/**`,
Noctalia `~/Downloads/github/quickshell/noctalia-shell/Modules/Dock/**`, ii `~/.config/quickshell/ii/modules/ii/dock/**`
(grep), and our own web dock's edge-strip reveal (`mods/webdock/qml/surfaces/dock.qml`, K40 hover machine).

**Read first:** `CLAUDE.md`; DECISIONS K16, K40, K44, **K51**; schema `Dock` (`dock.*`); PROTOCOL `svc.workspaces`
(`windows`, `window.close`); `crates/kurashid/src/workspaces.rs` (`document()`, `tasks`), the compositor adapter
(`crates/kurashi-compositor/src/{types,niri,fake}.rs`: window list, actions), `frontend/surfaces/Bar.qml` (`taskRow`:
DesktopEntries lookup, `window.focus`), `frontend/components/{Block,Icon,IconButton}.qml`, `frontend/shell.qml`.

**Owned paths:** `crates/kurashid/src/workspaces.rs` (`windows` in the document, `window.close` action), the
compositor adapter's close-window action (`crates/kurashi-compositor/**`, narrow), `crates/kurashi-mock/**` (parity:
`windows`, `window.close`), new `frontend/surfaces/Dock.qml` (+ registration in `shell.qml` Variants and `qmldir`),
`docs/ux/dock.md` (new UX brief first: macOS, Windows taskbar, GNOME dash, KDE task manager, DMS, Noctalia, ii;
states: empty, only pinned, many apps (overflow/scroll), urgent, no desktop entry for an app, multi-output;
keyboard; motion; Ma), `i18n/{en,ja}/dock.toml`, test script `frontend/test-dock.sh`. **Not yours:** primitives,
other surfaces, settings, schema. Sandbox names `w25-dck-`.

**Do:**
1. Daemon: `windows` (all windows, id order, `{id, app_id, workspace, output, focused}`) and `window.close {id}`.
2. Dock surface per output while `dock.enabled` on it: pinned apps (DesktopEntries by id, icon + tooltip name) then
   running ones grouped by `app_id` (dots under an app = its window count, the focused one lit); click = focus the
   app's most recent window, again = next window; launch when none (`launcher.launch` with the desktop id); middle =
   new window (launch); right = menu (Pin/Unpin → writes `dock.pinned` with one `cfg.apply`; Close window(s)).
   Drawn with `Block` so every decor styles it (keycap tiles, soft glass pill, line boxes). Magnify on hover is optional
   and only while `Theme.springOn`.
3. Autohide: a thin edge window (as the web dock's strip) reveals the dock on hover (250 ms), hides 400 ms after the
   pointer leaves; never covers a fullscreen window; exclusive zone only when autohide is off.
4. Ma: no surface while off; 0 frames while idle; the edge window costs ~nothing (measure USS like K41 and write the
   number in `docs/BENCH.md` "Mods"/opt-in section).

**Acceptance:** `cargo test -p kurashid` (windows doc, close action) + clippy; `frontend/test-dock.sh` (mock with
fake windows: pinned + running, focus by click, pin by menu → `dock.pinned`, autohide reveal by pointer) with shots
under `sekai`, `glass`, `terminal`, `none`. Report (terse).
