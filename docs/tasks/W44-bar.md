# Card W44-bar — bars on every edge, driven by zones; visibility, reserve, floating (K71, K72; docs/ux/layout.md)

**Why:** user points 4, 6, 7, 10 (base). W43 landed the contract: `runtime.layout` names, per output, which edges carry a
bar, each bar's draw mode, visibility, inset, reserve, holder and its zones resolved to module entries. The bar still
draws its fixed rows on one edge. This card makes the bars what the document says.

**Read first:** `CLAUDE.md`; `docs/tasks/README.md`; DECISIONS K71, K72, K59 (TileSheet per window), K65 (one spring
family); `docs/ux/layout.md` (whole), `docs/ux/frame.md` (Design), `docs/ux/edge-modules.md` (Design: zones, the module
table); PROTOCOL §3.1 (incl. the settled rules) and `fixtures/ipc/server/snap_runtime_layout.json`;
`frontend/core/{ShellLayout,EdgeStrips,EdgeReveal}.qml` (use them: one hover strip per edge is shared — never make an edge
window of your own); `frontend/surfaces/{Bar,BarConfig,Frame}.qml`, `frontend/shell.qml`, `frontend/core/Light.qml`,
`frontend/components/island/IslandGeom.qml`, `frontend/core/Peeks.qml`; CONTRACT-CHANGE rows 490 and 492 (decided here).

**Task:**
1. **Module components:** move each core bar item out of Bar.qml into `frontend/components/modules/<Name>.qml`
   (`workspaces`, `windows`, `island`, `volume`, `recorder`, `keyboard`, `clock`, `quick`, `tray`, `sidebar_left`,
   `sidebar_right`), each drawing itself for a horizontal or a vertical host (`vertical`, `thickness`, `output`, `edge`
   properties), and `ModuleHost.qml` that loads an entry `{id, kind, mod?, provide?}` — a core component by id, a mod's
   `widget:` through ModLoader with its peek (PeekSource) and anchor (AnchorReport) as today. Later cards reuse these for
   edge modules (W45-edge), so nothing in them may assume it sits in a Bar.
2. **Bars from the document:** one Bar window per output and edge whose `edges.<e>.bar` is true (shell.qml), its rows
   (horizontal) or columns (vertical) from `zones.start/center/end` through ModuleHost; the groups/strip per chrome as
   today. The default layout must be **pixel-identical** to main's bar (washi, sekai, terminal; top; shots compared like
   W43-layout did, against a same-day main build). Side bars keep their fit/overflow rules (`+N`). BarConfig keeps its
   API for the other readers but takes insets from ShellLayout.
3. **Draw:** floating = a rounded pill in **every** chrome (the bar's own strip, rounded ends, the look's shadow; image 8 —
   sekai's floating bar shows its groups on one pill, not loose keys); dynamic/connected = flush, the frame's band on its
   edge. The island's neck (IslandGeom openings) and the sidebar's join (SidebarGeom) follow a floating bar's inset.
4. **Visibility and reserve:** `always` as today; `hover` and `empty_desktop` via `EdgeReveal` on the bar's edge (empty
   desktop: the output's active workspace has no window — `svc.workspaces.tasks`, as the dock reads it) with a slide in
   from the edge on the motion springs; `hidden` shown while `runtime.ui.shown` lists `bar:<edge>@<output>`. The bar's
   window holds the edge's zone only when the document's `holder` is `bar` (else `ExclusionMode.Ignore` at `inset`).
   While hidden, a bar costs no window (or an unmapped one kept after the first show, like the dock: measure which costs
   less and keep that).
5. **Row 492 (b):** a docked bar's window carries its edge's frame strip (the band is the bar there; the inner fillets
   hang under its ends), so Frame.qml makes no strip on an edge whose band is 0 under a docked bar. Measure per-output PSS
   with the frame on before/after (pairs) and record it.
6. **Row 490:** `Light.originOf` returns a window's own `sheetOrigin` when it declares one; drop Frame.qml's `sheetCarry`
   stand-in (texture `sheet = fixed` and `carried` both line up — an 8× seam shot each).
7. Tests: extend `frontend/test-frame.sh` or add `frontend/test-bars.sh` (mock; stage layouts with `KURASHI_MOCK_LAYOUT` or
   set config through the mock): default top bar pixel-identical; bars on top+bottom (image 6), left, all four; a module
   moved between zones and bars; floating bar on each edge under washi and sekai; hover/empty-desktop/hidden reveal (drive
   the pointer to the edge with the sandbox's pointer tool; `kurashi act layout.toggle '{"target":"bar:bottom"}'`);
   reserve auto/on/off with a test window's position (sway; niri nested if available — W43-frame showed it works).
   Shots `frontend/shots/bars/<decor>/`.

**Owned paths:** `frontend/surfaces/{Bar,BarConfig,Frame}.qml`, `frontend/shell.qml` (the Bar and Frame Variants),
`frontend/components/modules/**` (new), `frontend/components/bar/**`, `frontend/components/island/IslandGeom.qml`,
`frontend/components/sidebar/SidebarGeom.qml` (inset only), `frontend/core/Light.qml` (`originOf`), `frontend/core/Peeks.qml`
(edge/inset only), `frontend/test-bars.sh` / `frontend/test-frame.sh`, `frontend/shots/{bars,frame}/**`, `docs/BENCH.md`
(your entry). Not Dock/Sidebar/Desktop (W44-surfaces), not `settings/` (W44-settings), not the daemon.

**Acceptance:** default bar pixel-identical to main (report the comparison); every row of docs/ux/layout.md's mode table
for the bar shot in washi and sekai; bars on 2/3/4 edges; reveal modes driven by the pointer and by `layout.toggle`; reserve
measured with a window; frame-on PSS per output before/after (b); idle frames 0; `just check` green.

**Contract rows:** CONTRACT-CHANGE rows 510–519 only. **Env:** `CARGO_TARGET_DIR=$HOME/.cache/kurashi-agents-target/w44-bar
CARGO_BUILD_JOBS=4`; sandbox names `w44-bar-…`; set `idle.enabled = false` in sandbox configs (I241: the idle lock blanks long
runs). Model: opus.
