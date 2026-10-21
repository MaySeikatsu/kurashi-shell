# Card W30-webdock-sidebar — the web dock as a sidebar tab, filling the sidebar

**User (session 12):** asked whether the web dock should become a sidebar tab: "It should be able to be used in the
sidebar but inside of it it fills the whole sidebar instead of being phone shaped." The web dock at its screen edge
(phone / compact / extended, `mods/webdock`) stays exactly as it is; this adds a second place for it.

**Read first (only these, then the code they name):** `CLAUDE.md`; `docs/ux/webdock.md`; `docs/ux/sidebar.md`;
DECISIONS K38–K41 (web dock, web host), K54 (sidebars); `docs/MODS.md` "Panels" (incl. `fillHeight`, row 238);
`frontend/components/sidebar/LeftColumn.qml` (tabs = mod panels, `fillHeight` binding), `frontend/core/mods.js`
(`panelOf`, `qmlOf`); `mods/webdock/mod.toml`, `mods/webdock/qml/**`, `mods/webdock/host/**` (how the dock places the
host's web card today: who owns the rect, how the host's layer surface follows it), `crates/kurashi-mod-webdock/**`.

**Contract (decided by the lead — implement exactly; anything else → a row in `docs/CONTRACT-CHANGE.md`, rows 250–259):**
- The web dock provides a **panel** (`panel:webdock` → tab value `mod:webdock:webdock`, follow the AI mod's pattern
  for the exact id) that the sidebar can show as a **left tab** (`sidebar.left`) or a **right section**
  (`sidebar.right`). The sidebar offers (`sidebar.tabs` / `sidebar.sections`) already list every loaded mod panel —
  check that it appears; the mod must be on.
- Inside the sidebar the dock is **not phone shaped**: no `PhoneFrame` bezel, no fixed phone aspect. The pins sit as a
  compact row (or column of icons — pick what reads best at 320–640 px; cite the shell you copied) and the open page
  fills the rest of the pane, edge to edge inside the sidebar's padding, using the full height on offer
  (`fillHeight`). Page view is the pin's `view` (mobile UA at that width is fine; `desktop` honoured).
- One web host, one set of loaded pages: a page open in the sidebar and the same pin at the edge dock are the same
  page (K38 budgets: `max_loaded`, `unload_after` unchanged). If both are visible at once, decide which one shows the
  live view and what the other shows (a "shown in the sidebar" placeholder is fine) — write it in the brief.
- Closing the sidebar hides the page (0 frames, Ma), it is not destroyed unless the dock's own unload rules say so.
- No new daemon state unless needed; if the host needs a new rect/placement intent, file a CONTRACT-CHANGE row and
  build against your proposal (the lead settles it at merge).

**UX brief:** add a section "In the sidebar" to `docs/ux/webdock.md` (how Vivaldi/Edge/Opera web panels and
Firefox's sidebar do it; states: no pins, page loading, crashed host, offline, blocked; keyboard: tab switching,
Esc; motion; multi-output; budget) before the code.

**Owned paths:** `mods/webdock/**` (incl. `test/`, `shots/`), `crates/kurashi-mod-webdock/**`, `i18n/{en,ja}/mod-webdock.toml`
(or the mod's existing i18n file), `docs/ux/webdock.md`, `frontend/components/sidebar/LeftColumn.qml` and
`frontend/components/sidebar/**` only where a panel needs the host's rect/visibility (keep the change generic — no
`webdock` name in sidebar code, rule 4 spirit).

**Acceptance (executable):** a sandbox test `mods/webdock/test/test-sidebar.sh` (fake host or the real one as the
existing webdock tests do; never the user's display, network off is fine — use a `file://` pin) that: sets
`sidebar.left = ["mod:webdock:…"]` with the mod on and two `file://` pins, opens the left sidebar
(`kurashi act sidebar.toggle '{"side":"left"}'`), asserts the page's rect fills the pane (log geometry as
`test-sidebar-panel.sh` does), switches pins, closes the sidebar and asserts 0 frames / the page hidden, and writes
shots `mods/webdock/shots/sidebar-{washi,sekai}.png`. Existing `mods/webdock/test/test-dock.sh` and
`frontend/test-sidebar-panel.sh` stay green. `just check` green.

**Thrift:** read only what is listed; terse report: what changed, the test output, CONTRACT-CHANGE rows, backlog ideas.
Build with `--features kurashid/test-mods` before sandbox tests (`cargo test` replaces that binary). Never start the
shell on the user's display; never contact real sites.
