# Card W36-motion — every extended surface moves like the island (I190, I192, I128)

**Why:** the user: "I like how the dynamic island animates, extends and feels kinda fluid, wobbly and dynamic, other extended
surfaces should behave the same and also get a similar merging animation going on into the bar." W34 put the Stage panels
on MorphShape/MorphSprings and the sidebars on ColumnShape; I190 lists what is still uneven. W35-perf found the quick
settings card waits 62–65 ms for QuickPanel to build before its first frame (I192).

**Read first:** `CLAUDE.md`; `docs/tasks/README.md` (common rules); `docs/ux/motion.md`, `docs/ux/sidebar.md`,
`docs/ux/polkit.md`; DESIGN-SYSTEM §9 (motion); BACKLOG rows I190, I192, I128; BENCH "2026-10-25 — W35 perf" (the clock
fix pattern); `frontend/components/island/{MorphShape,MorphSprings,IslandGeom}.qml`, `frontend/surfaces/{Stage,Launcher,
Toasts,NotificationCenter,Sidebar}.qml`, `frontend/components/sidebar/{ColumnShape,SidebarGeom}.qml`.

**Task:**
1. **One spring family.** BarMorph (launcher, notification centre, toasts) keeps its own squash/wobble — move it onto
   MorphSprings so every surface grows out of the bar with the same `motion.spring.*` tokens (incl. `squash`) and the
   same "neck" that merges into the bar rule. Keep both motion styles the user likes (the current tokens' presets).
2. **Sidebar origin from the anchor registry** (`IslandGeom.rectOf(out, "sidebar:<side>")`, row 364) so the column grows
   out of its bar button like the island card grows out of the island.
3. **Quick card rest** under keycap/soft chrome: it rests centred and detaches from its group — rest under the button
   it came from (or explain in the brief why centred is right).
4. **I192:** the Stage's view Loader becomes asynchronous; the shape grows at once to the size that view had last time
   (cache per view kind), and holds growth only on a view's very first open. Quick settings ≤ 16.7 ms to first commit
   (measure with `tools/bench/measure.py --latency 10 --popup-action quick.toggle`). Fix ClockView's double build
   (`onOpenChanged` reads a stale `wantedKind`).
5. **First cold launcher open stalls ~220 ms:** find and fix (same pattern, or pre-warm only what is cheap).
6. **I128:** while `runtime.ui.polkit` is true the Stage and the island step aside (no open, no expand, no focus); a
   panel that was open folds away and does not come back by itself.
7. Toasts' sidebar fallback cut; test-peek's tray x hitting the sidebar button; update `docs/ux/motion.md` and
   `docs/ux/sidebar.md` motion text to what is built (you own them).

**Owned paths:** `frontend/surfaces/{Stage,Launcher,Toasts,NotificationCenter,Sidebar}.qml`,
`frontend/components/island/**` (not FlipText), `frontend/components/sidebar/**`, `frontend/components/launcher/**`,
`frontend/components/expanded/ClockView.qml`, `frontend/components/QuickPanel.qml`, `frontend/test-{morph,stage,peek,
toasts,sidebars,sidebar-panel,launcher,island-morph,island-join,polkit}.sh` and their shots, `docs/ux/{motion,sidebar}.md`.
Not Bar.qml (W36-bar owns it) — if the bar rule needs a change, put it in your report.

**Acceptance:** `bash frontend/test-morph.sh` and `test-stage.sh` pass with new shots showing launcher, centre, toasts,
quick card and both sidebars mid-growth (neck into the bar) and at rest, both motion presets; `measure.py --latency 10`
popup ≤ 16.7 ms for `island.expand` and `quick.toggle`; a polkit step in `test-polkit.sh`; idle frames 0.

**Contract rows:** if needed, use CONTRACT-CHANGE rows 380–384 only.

**Env:** `CARGO_TARGET_DIR=$HOME/.cache/kurashi-agents-target/w36-motion CARGO_BUILD_JOBS=6`; sandbox names `w36-motion-…`.
Model: opus.
