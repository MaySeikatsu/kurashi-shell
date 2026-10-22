# Card W34-morph-sidebar — the sidebars grow out of the bar and merge into it (one morph language, part 2)

**User (session 13):** "other extended surfaces should behave the same [as the island] and also get a similar merging
animation going on into the bar." Keep calm and lively.

**Read first:** `CLAUDE.md`; `docs/tasks/README.md`; **`docs/ux/motion.md`** (the sidebar row and the profiles);
`docs/ux/sidebar.md`; DECISIONS K54, K58; `frontend/surfaces/Sidebar.qml`, `frontend/components/sidebar/**`,
`frontend/components/island/MorphShape.qml` (read-only: its neck/fillet geometry is the reference for the join),
`frontend/components/Relief.qml` header (carried sheet), `frontend/test-sidebars.sh`, `frontend/test-sidebar-panel.sh`.

**Task:**
1. **Origin and join:** the sidebar opens out of the bar's end on its side (from its sidebar button's rect when there is
   one — read the anchor registry W34-morph-stage builds if it has landed; otherwise from the bar's corner). At rest the
   column's inner top corner meets the bar's edge with a concave fillet in the column's own colours (the bar and the
   column read as one sheet); its outer edge stays flush with the screen. Bottom bar mirrored; side bars: the column
   grows along the bar.
2. **Motion:** one shape — the column grows from the origin (width and height on their own springs, as the island) and
   folds back into it; content cut to the shape, fading in late; carried material moves with it. `calm` soft settle,
   `lively` bouncy with a squash on landing (tokens only, no profile-name branches); `none` cuts.
3. **Polish while there:** I152 click outside closes (no layer focus grab on niri: an invisible catcher on the other
   outputs/area is the usual way — mind K16 window costs), I150 if cheap (uptime needs a daemon value — skip if so),
   20 open/close cycles without USS growth (K16), the panel style and floating style both join correctly.
4. **Tests/shots:** extend `frontend/test-sidebars.sh`: mid-open shots at 40/120/250 ms (left, right; calm, lively;
   washi, sekai, kami; top and bottom bar), at rest the fillet pixels match the bar's colour, click-outside closes;
   shots → `frontend/shots/sidebar/morph/`. `test-sidebar-panel.sh`, `test-texture.sh`, `test-pen.sh` stay green.

**Owned paths:** `frontend/surfaces/Sidebar.qml`, `frontend/components/sidebar/**`, `frontend/test-sidebars.sh`,
`frontend/test-sidebar-panel.sh`, `frontend/shots/sidebar/**`. Read-only: MorphShape and the anchor registry (another
card owns them; a needed API → CONTRACT-CHANGE row). Not Stage/Launcher/Toasts/Theme.qml/crates.

**Acceptance:** `frontend/test-sidebars.sh` exits 0 with the new checks and shots; the suites above green; idle 0 frames.

**Env:** `KURASHI_BIN_DIR=$HOME/.cache/kurashi-agents-target/lead/debug`; no cargo. Sandbox names `w34-side-…`. Machine
A. Four agents share the machine.
