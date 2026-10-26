# Card W45-edge — edge modules, the standalone island, the clock on the full variant table (K71, K72; points 8, 9, 11)

**Why:** user points 8 (widgets pinned to the frame edges, Caelestia-like, extending on hover), 9 (every module in
every variant), 11 (the island on its own). W43 resolves the zones (`runtime.layout.edges.<e>.zones`, `holder: module`),
W44-bar made every bar item a module component (`frontend/components/modules/**`, `ModuleHost`, `ModuleLink`) that
assumes no bar. An edge without a bar still draws nothing for its zones.

**Read first:** `CLAUDE.md`; `docs/tasks/README.md`; DECISIONS K71, K72, K35 (peeks), K65 (springs); `docs/ux/edge-modules.md`
(whole: it is the spec), `docs/ux/layout.md` (Visibility, the mode table's "island / edge module" row), `docs/ux/frame.md`,
`docs/ux/timer.md` (the glance); PROTOCOL §3.1 + `fixtures/ipc/server/snap_runtime_layout.json` (the bottom edge's timer
group); `frontend/components/modules/**`, `frontend/components/bar/{ZoneHost,ZoneRow,ZoneColumn,BarGroup}.qml` (how a
bar hosts a zone — reuse, do not fork), `frontend/core/{ShellLayout,EdgeStrips,EdgeReveal,Peeks,PeekSource}.qml`,
`frontend/components/island/{IslandGeom,MorphShape}.qml`, `frontend/surfaces/{Bar,Stage}.qml` (read only),
`frontend/shell.qml`, MODS.md (the provides).

**Task:**
1. **Edge module groups** (`frontend/surfaces/EdgeModules.qml`, Variants in shell.qml): per output, per edge whose
   `bar` is false, one group per non-empty zone at the zone's place along the edge (start / centre / end; side edges top →
   bottom), its modules side by side through ModuleHost, grown out of the band (or the screen edge) by the edge's draw:
   dynamic = the island's neck fillets into the band, connected = straight neck, floating = a pill `gap` off the band.
   Visibility from the edge: always (glances out; the group windows keep the zone only when the document names `module`
   the holder — exactly one window holds), hover (nothing at rest but the shared strip; the dwell on the **zone's span**
   reveals that group only — `EdgeStrips.posOf`), empty_desktop, hidden (`runtime.ui.shown` lists
   `module:<edge>:<zone>@<output>`; `layout.toggle` and Esc/click elsewhere put it away). Grow on the island's spring;
   reduced motion cuts. At rest a hover group loads no module (Loader inactive) and costs no window beyond the strip.
2. **Glance → peek → expanded:** hover/focus on a module shows its peek (Stage-hosted, from the group's own edge and
   window origin — **row 514**: PeekSource asks with the host's edge/origin instead of `Peeks.edgeOf(output)`; drop
   the `Peeks.place` stand-in once every source uses it); a click opens its expanded view from the anchor registry as a bar
   glance does. A group never hides while one of its peeks, menus or cards is open or it holds focus.
3. **Keyboard + a11y:** a group revealed by key takes focus (OnDemand), Tab walks its modules, Enter opens the expanded
   view, Esc folds back; each module's accessible name from its glance.
4. **Standalone island (point 11):** `island` in a zone of a bar-less edge is the standalone island in its group (the
   island module as in the bar; IslandGeom gets its place through its public API — a row if it needs a change); with
   `island.main.system_events` a transient face (volume, brightness, power, Bluetooth) grows the collapsed group out for its
   TTL, then folds back; the island card opens from it.
5. **Clock retrofit (K72 proof, BACKLOG I223):** the clock module gets a peek of its own (date, week, the next agenda
   item or alarm when one exists, a second time zone when set — read what the daemon already offers; a row if a field is
   missing), and the K72 variant table for the clock is documented in MODS.md's module table (glance, peek, expanded =
   the island clock card, desk card, sidebar = the calendar section, island face; quick tile: none, with the reason).
6. **Timer:** the timer mod's glance in an edge group (the fixture's bottom-centre group): shots of every visibility at
   rest/revealed (closes the timer brief's open edge-module shots).
7. Tests `frontend/test-edge-modules.sh` (mock; `layout.toggle` now works there; real kurashid for reserve): each
   visibility × draw × frame on/off for a bottom-centre and a right-start group (washi, sekai); hover on the zone's span
   reveals only that group, dwell + 400 ms hide; peek and expanded from an edge module; keyboard path; standalone island
   on the top band with a transient volume face while collapsed; reserve with a test window when always + holder module;
   idle frames 0 at rest (hover and always); PSS per shown group (≤ +3 MiB, BENCH entry). Shots
   `frontend/shots/edge-modules/<decor>/`.

**Out of scope:** fullscreen (I237), the redesign edit mode (I220), Settings (edge zones are already editable there).

**Owned paths:** `frontend/surfaces/EdgeModules.qml` (new), `frontend/shell.qml` (its Variants only),
`frontend/components/modules/**`, `frontend/components/edge/**` (new, if needed), `frontend/core/{Peeks,PeekSource}.qml`
(row 514), `mods/timer/**` (shots/tests only), `docs/MODS.md` (the clock's variant row), `i18n/{en,ja}/edge-modules.toml`
(new), `frontend/test-edge-modules.sh`, `frontend/shots/edge-modules/**`, `docs/BENCH.md` (your entry). Not Bar/Stage/
Frame/Dock/Sidebar, `components/{bar,sidebar,island}/**`, `core/EdgeReveal.qml` (W44-follow runs beside you and owns
them: code against their current API; needs → rows).

**Acceptance:** the brief's definition of done items for edge modules, the standalone island and the clock; test green;
`just check` green; budgets in BENCH.

**Contract rows:** CONTRACT-CHANGE rows 550–559 only. **Env:** `CARGO_TARGET_DIR=$HOME/.cache/kurashi-agents-target/w45-edge
CARGO_BUILD_JOBS=4 CARGO_INCREMENTAL=0` (the disk is tight); sandbox names `w45-edge-…`, remove your sandbox dirs when
done; `idle.enabled = false` in sandbox configs. Model: opus.
