# Card W42-tiles — a lighter QuickTile and cheaper frames (I211, I199, I192)

**Why:** the quick settings card is the shell's slowest open: 22–29 ms warm under washi after W41 (target ≤ 16.7 for a popup's
first frame), 12 ms under sekai. W39-block measured where it goes: each QuickTile ~0.7 ms, of which the badge Blocks ~0.2 and the
rest QuickTile's own tree (texts, icons, two MouseAreas, the focus ring, bindings). Frames other than Paper cost per Block too:
kami (Sketch.qml) 0.8 ms, snes 0.75 ms, against ~0.1 ms for the Block itself.

**Read first:** `CLAUDE.md`; `docs/tasks/README.md`; BENCH "W39-block" (quick card attribution) and "W41 icons"; DESIGN-SYSTEM
quick tile tokens (`quick.tile.on.*`, K66); `docs/ux/` quick settings brief; `frontend/components/quick/QuickTile.qml`,
`frontend/components/QuickPanel.qml`, `frontend/components/FocusRing.qml`, `frontend/components/frames/{FrameBase,Sketch,Snes,Paper}.qml`,
`frontend/components/frames/papercache.js` (W41's memo — the same idea may serve Sketch/Snes); `tools/bench/quick-open.sh`,
`tools/bench/block.sh`, `tools/bench/block-identity.sh`.

**Task:**
1. QuickTile: one hit area (press/hover/long-press/secondary from one MouseArea or TapHandler+HoverHandler pair), the chevron
   and focus ring made only when needed (Loader on `activeFocus` / has-detail), static texts without bindings that never change;
   keyboard and a11y exactly as today (Tab order, Space/Enter, the detail key, Accessible names and roles).
2. Sketch and Snes frames: find what each Block pays (per-Block generated paths or strings, Canvas, repeated images) and memoise
   or share it like papercache.js; keep the look.
3. Measure: quick card warm median per look — washi, sekai, kami, snes, kanso — before/after pairs in one run
   (`quick-open.sh` takes several frontend dirs); `block.sh` per-Block cost for kami and snes before/after.

**Owned paths:** `frontend/components/quick/QuickTile.qml`, `frontend/components/QuickPanel.qml` (tile use only),
`frontend/components/frames/Sketch.qml`, `frontend/components/frames/Snes.qml`, new `frontend/components/frames/*cache.js`,
`tools/bench/**`, `docs/BENCH.md` (your entry).

**Acceptance:** `block-identity.sh` 0 strong pixels across its looks × scenes (add kami and snes to the run if absent); quick card
warm washi ≤ 18 ms and no look slower than before (pairs, same run); kami/snes per-Block cost down (numbers); keyboard path through
the quick card unchanged (the quick test, or a scripted Tab/Space run); `just check` green.

**Contract rows:** CONTRACT-CHANGE rows 475–479 only.

**Env:** `CARGO_TARGET_DIR=$HOME/.cache/kurashi-agents-target/w42-tiles CARGO_BUILD_JOBS=4`; sandbox names `w42-tiles-…`.
The machine is loaded: always pairs in one run. Model: haiku (max effort).
