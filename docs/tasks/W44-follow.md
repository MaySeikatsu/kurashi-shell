# Card W44-follow — the bar and surface review items: Stage under any bar, one reveal model, holders, openings (K71)

**Why:** the W44-bar and W44-surfaces reviews left stand-ins and gaps that the user sees as soon as they pick a floating
bar, a bar on another edge, two sidebars, or the frame. The daemon side (rows 510, 511, 513, 520, 523) is on main.

**Read first:** `CLAUDE.md`; `docs/tasks/README.md`; DECISIONS K71; `docs/ux/layout.md`, `docs/ux/frame.md`;
PROTOCOL §3.1 (the settled rules incl. rows 510/511: `holder: "bar"` on an edge a docked bar carries, `edges.<side>.span`);
CONTRACT-CHANGE rows 510–525 (their reasons are the spec); `frontend/surfaces/{Bar,Frame,Stage,Dock,Sidebar}.qml`,
`frontend/core/{EdgeReveal,ShellLayout}.qml`, `frontend/components/sidebar/{EdgeHold,SidebarGeom,ColumnShape}.qml`,
`frontend/components/island/IslandGeom.qml`, `frontend/surfaces/BarConfig.qml`.

**Task:**
1. **Row 512 (Stage):** the island card's morph, the groups' foot and the peeks follow the island's own bar
   (`IslandGeom.pillOf(output).edge/inset/dx`) and that bar's inset, not `BarConfig.edge` and the screen edge: correct
   under a floating top bar, a bottom bar, and with the island on a bottom bar beside a top bar. Peeks hang from the
   bar that owns their source.
2. **Rows 510/511 in the views:** Bar.qml drops its stand-ins: holds its zone when `holder === "bar"` (no more
   `carries && holder === "frame"`), and a side bar runs along `ed.span.start/end` (drop `across()`); framegeom's `docked`
   agrees with the daemon (a hidden bar is not the band: the frame draws that edge's strip).
3. **Row 524:** fold EdgeHold into EdgeReveal (one reveal model: a pointer resting on the edge keeps the surface out
   until it leaves; the surface leaves its outermost 2 px out of its input region), used by the dock, the sidebars and the
   bars (drop the bar's own 1.2 s hold); delete EdgeHold.qml.
4. **Row 525:** every non-holder window that writes `exclusiveZone` (Frame.qml's strips, any other) uses
   `Binding on exclusiveZone { when: holder … }` so it stays `ExclusionMode.Ignore`; measure a frame strip's placement
   under a top bar before/after (the side strips must run the full height).
5. **Row 521:** SidebarGeom keyed by output **and side** (`set(output, side, edge, from, to)`, `openingsOf(output)`);
   the bar's rule opens under every column that meets it (both sidebars out; a column joining a top and a bottom bar).
6. **The joined dock's paper:** dynamic/connected docks get the look's Relief/TileSheet like the floating Block
   (`texture.shell` on): shot washi-paper, all three modes.
7. Run the tests the W44 agents skipped: `frontend/test-texture.sh` (KURASHI_SIDEBAR_HOLD now holds the slide progress:
   fix the test if its meaning moved), `mods/webdock/test/test-sidebar.sh` (needs `--features test-mods`; checks the
   Placement change), test-sidebars.sh `bars` part.
8. Tests: extend test-bars.sh / test-frame.sh / test-sidebar-panel.sh / test-dock.sh for items 1–6 (Stage morph origin
   under a floating and a bottom bar: the card's first frame touches the pill; two sidebars with a line chrome: two
   openings; a frame strip's height under a top bar). Shots under the existing folders.

**Out of scope:** row 522 (floating sidebar × floating bar) is the user's decision — leave as is; PeekSource (row 514)
is W45-edge's.

**Owned paths:** `frontend/surfaces/{Bar,BarConfig,Frame,Stage,Dock,Sidebar}.qml`, `frontend/core/EdgeReveal.qml`,
`frontend/components/{bar,sidebar,island}/**`, `frontend/test-{bars,frame,sidebars,sidebar-panel,dock,texture}.sh`,
their shots, `mods/webdock/test/**` (fixes only), `docs/BENCH.md` (your entry). Not `frontend/core/PeekSource.qml`,
not `frontend/components/modules/**` or `frontend/shell.qml` (W45-edge), not the daemon.

**Acceptance:** each item driven in the sandbox (sway; niri nested where W43-frame did); the listed suites green;
`just check` green; idle frames 0 with a hover bar, a hover dock and a pinned sidebar at rest.

**Contract rows:** CONTRACT-CHANGE rows 540–549 only. **Env:** `CARGO_TARGET_DIR=$HOME/.cache/kurashi-agents-target/w44-follow
CARGO_BUILD_JOBS=4 CARGO_INCREMENTAL=0` (the disk is tight); sandbox names `w44-follow-…`, remove your sandbox dirs when
done; `idle.enabled = false` in sandbox configs. Model: opus.
