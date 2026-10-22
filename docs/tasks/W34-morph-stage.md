# Card W34-morph-stage — every Stage panel grows out of its bar widget (one morph language, part 1)

**User (session 13):** "I like how the dynamic island animates, extends and feels kinda fluid, wobbly and dynamic, other
extended surfaces should behave the same and also get a similar merging animation going on into the bar." Keep the two
motion styles (calm, lively) — the user likes them.

**Read first:** `CLAUDE.md`; `docs/tasks/README.md`; **`docs/ux/motion.md` (the brief — whole)**; `docs/ux/island.md`
"Session 9 morph" and the join sections; DECISIONS K16, K42; DESIGN-SYSTEM §9 motion; `frontend/surfaces/Stage.qml`,
`frontend/components/island/{MorphShape,IslandGeom,CompactFace}.qml`, `frontend/components/Relief.qml` header (carried
sheet, mask), the pen lines in MorphShape (W32-pen phase 2), `frontend/test-island-morph.sh`, `frontend/test-stage.sh`.

**Task:**
1. **Origins:** generalise `IslandGeom` into an anchor registry any bar widget reports its rect to (per output): the
   quick button, the tray icons, sidebar buttons, mod widgets, peek sources. Only the rect lines in those components
   (`QuickButton`, `TrayIcon`, `SidebarButton`, the Bar's mod widget slot, the peek sources in Bar.qml) — nothing else
   there.
2. **Morph for every Stage panel:** quick (incl. the phone with `ownChrome`), session menu, tray menu, mod panels and
   peeks open as the island's views do: one MorphShape from the origin's rect to the panel's rect, two springs, the
   liquid neck at the bar's edge (keycap: joins its group), content cut to the shape and faded in late / out first. A
   panel whose origin is not on this output grows from the bar's centre.
3. **Retarget:** switching panels while one is open (quick → session → tray, mod → mod, island view → quick) morphs the
   shape to the new rect with the neck sliding along the bar — no close/open.
4. **Profiles:** `calm` soft settle (overshoot ≤ 3 %), `lively` bouncy (≤ 8 % soft limit) **plus squash & stretch
   mid-morph and one neck wobble on landing (I113)**, `none`/reduce motion cuts. In MorphShape, so the island gets it too.
   All from tokens (`Theme.spring/damping/overshoot`, profile tokens) — no renderer branches on profile names (rule 4):
   if you need a token (e.g. `motion.spring.squash`), add a CONTRACT-CHANGE row and code against a local default.
5. **Fixes:** B32 (morph stuck ~55 %: find the SpringAnimation stop cause), I160 (translucent head darker than the body —
   one layer of translucency), I161 (the phone's fade takes the rule copy with it), I122 (morphing panels get the
   shape's soft shadow).
6. **Ma/budget:** springs only during a transition; idle 0 frames; measure CPU per morph frame (no per-frame
   allocations in path building; cache the parts that do not change).
7. **Tests/shots:** new `frontend/test-morph.sh` (open/close at 40/120/250 ms for quick, session, tray, a mod panel
   (hello), a peek; retarget mid-shots; calm vs lively; top and bottom bar; washi, sekai, kami) → `frontend/shots/morph/`;
   `test-island-morph.sh`, `test-island-join.sh`, `test-stage.sh`, `test-quick.sh`, `test-peek.sh`, `test-texture.sh`,
   `test-pen.sh` stay green.

**Owned paths:** `frontend/surfaces/Stage.qml`, `frontend/components/island/**`, the rect-reporting lines in
`frontend/components/{QuickButton,TrayIcon,SidebarButton}.qml` and in `frontend/surfaces/Bar.qml`,
`frontend/components/phone/**`, `frontend/components/expanded/**` (only if a view needs a cut/fade hook),
`frontend/test-morph.sh`, `frontend/shots/morph/**`, `frontend/shots/island/**`. Not Sidebar/Launcher/
NotificationCenter/Toasts (other W34 cards — they reuse MorphShape read-only; keep its API compatible and document any
addition in its header), not `Theme.qml`, not `crates/**`.

**Acceptance:** `frontend/test-morph.sh` exits 0 with its shots; the suites above green. The lead reviews the shots
against `docs/ux/motion.md` — it must feel like the island everywhere.

**Env:** `KURASHI_BIN_DIR=$HOME/.cache/kurashi-agents-target/lead/debug` (daemon from main); no cargo. Sandbox names
`w34-stage-…`. Machine A: no `KURASHI_RENDER_NODE` (export `/dev/dri/renderD128` if a suite asks for renderD129). Four
agents share the machine.
