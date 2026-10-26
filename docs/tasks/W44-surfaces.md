# Card W44-surfaces — dock and sidebars in every draw mode; sidebars slide, resize, open on hover; desk on both sides (K71)

**Why:** user points 2, 3, 5, 12, 14, 15. W43 landed `runtime.layout` (dock and sidebars: draw, visibility, inset, span,
joins, radius, reserve) and the shared hover strip; the dock and sidebars still draw one fixed way.

**Read first:** `CLAUDE.md`; `docs/tasks/README.md`; DECISIONS K71 (user decisions: preset dynamic; sidebars slide in from
their screen edge in every mode, replacing W34's grow-from-the-button), K65 (springs), K51 (dock), W29/W34 sidebar notes;
`docs/ux/layout.md` (whole), `docs/ux/dock.md`, `docs/ux/sidebar.md` (states, keyboard, a11y — the motion section is
superseded); PROTOCOL §3.1 and the fixture; `frontend/core/{ShellLayout,EdgeStrips,EdgeReveal}.qml` (use them: never an edge
window of your own); `frontend/surfaces/{Dock,Sidebar,Desktop}.qml`, `frontend/components/sidebar/**`,
`frontend/components/island/MorphShape.qml` (the neck's fillet — reuse it for joins); CONTRACT-CHANGE row 486 (decided here).

**Task:**
1. **Dock:** draw modes from `ShellLayout.of(output).dock` — floating (a gap off the band/bar, every corner rounded, as
   today), dynamic (sits on the band or the bar on its edge, `joins`, concave fillets of `radius` into it, its free corners
   rounded; image 4, 6), connected (the same, straight sides; image 5). Visibility `always | hover | empty_desktop |
   hidden` through `EdgeReveal` (replace its own edge window) and `runtime.ui.shown` (`dock@<output>`); `ExclusionMode.Ignore`
   at `inset` unless the document names the dock `holder`.
2. **Sidebars:** slide in from their screen edge in every mode (the content and the fillets to the bar stay; springs,
   interruptible; reduce motion cuts); geometry from `sidebars.<side>` (`inset`, `span`, `joins`, `radius`, `width`):
   dynamic = flush to its side, from the bar (or band) to the band, fillets where it meets a bar (image 9); beside a floating
   bar it reaches the band (image 10); connected = straight joins; floating = gap on every side. Visibility: `hidden`
   (default: key, bar button, `sidebar.toggle`), `hover` (point 14: `EdgeReveal` on its side edge with the dwell; closes
   400 ms after the pointer leaves the column unless it holds focus), `always` (pinned open, holds its zone when the document
   names it `holder` — windows tile beside it), `empty_desktop`.
3. **Resize (point 12):** an 8 px grip along the inner edge, cursor `col-resize`, live while dragging (the column follows,
   the content re-lays out), written on release as `sidebar.<side>.width` (config set, one undo step), clamped to the
   schema range and the output less a gap; double-click resets to the default (remove the user value); Ctrl+Left/Right
   by 10 px while the sidebar has focus; the grip has an accessible name.
4. **Row 486:** `layout.toggle {target: "sidebar:<side>"}` drives `sidebar.toggle {side, output}` in the daemon (one truth:
   `runtime.ui.sidebar`; no `shown` entry for sidebars) — `crates/kurashid/src/{wiring,actions}.rs` (that part only), a test.
5. **Desk on both sides (point 15):** `desktop.left` and `desktop.right` columns at once, each in its order; cards neither
   lists stand on `desktop.side`; the desk's edit mode moves a card between columns (drag or a "move to other side"
   control) and writes both lists.
6. Tests: `frontend/test-dock.sh`, `frontend/test-sidebars.sh` / `test-sidebar-panel.sh`, `frontend/test-desk.sh` extended:
   each draw mode × top bar and bottom bar (washi, sekai), frame on and off; hover open of each sidebar and the dock (pointer
   to the edge, dwell, leave); pinned sidebar with a test window beside it; drag-resize (pointer press/move/release), its
   written width, double-click reset, keyboard resize; desk with cards on both sides. Shots
   `frontend/shots/{dock,sidebar,desk}/…` (new names, keep the old ones' meaning).

**Owned paths:** `frontend/surfaces/{Dock,Sidebar,Desktop}.qml`, `frontend/components/sidebar/**` (not `SidebarGeom.qml`:
W44-bar), desk components used only by Desktop.qml, `frontend/test-{dock,sidebars,sidebar-panel,desk}.sh` and their shots,
`crates/kurashid/src/{wiring,actions}.rs` (row 486 only) and a test in `crates/kurashid/tests/`. Not Bar/BarConfig/Frame/shell.qml
(W44-bar), not `settings/`.

**Acceptance:** every dock and sidebar row of docs/ux/layout.md's mode table shot in washi and sekai with the frame on and off;
hover reveal, pinned with reserve, drag-resize and keyboard resize driven in the sandbox; desk on both sides; row 486 test;
idle frames 0 with a pinned sidebar and a hover dock at rest; `just check` green.

**Contract rows:** CONTRACT-CHANGE rows 520–529 only. **Env:** `CARGO_TARGET_DIR=$HOME/.cache/kurashi-agents-target/w44-surfaces
CARGO_BUILD_JOBS=4`; sandbox names `w44-surfaces-…`; `idle.enabled = false` in sandbox configs (I241). Model: opus.
