# Card W39-block — a lighter Block, and the idle windows' memory (I199, I204, I194)

**Why:** Block is in every keycap, tile and card. W37-quick found the quick tile grid (10 tiles × 2 Blocks) is most of
QuickPanel's ~60 ms build; W35-perf left PSS at 152–154 MiB for one output (budget 150) with the idle Stage (~8 MiB) and
Launcher (~7.5 MiB) windows and Material Symbols (8.2 MiB) as candidates. The budget itself is a pending user decision
(I194) — cut what is cheap and safe either way.

**Read first:** `CLAUDE.md`; `docs/tasks/README.md`; `docs/BENCH.md` ("2026-10-25 — W35 perf" and its attribution table);
`tools/bench/README.md`; BACKLOG I194, I199, I204; `frontend/components/{Block,SoftShadow,FocusRing}.qml`, `frontend/components/QuickPanel.qml`,
`frontend/surfaces/{Stage,Launcher}.qml` (lazy parts), DESIGN-SYSTEM §7.

**Task:**
1. **Block:** measure what one Block costs to create (QML profiler or timestamps over 200 instances) and per-instance
   memory; make it cheaper without changing a pixel: fewer child items (merge rectangles; shadow/ring only when their
   widths are > 0 via Loader or `visible`-gated components), no per-instance Behaviors/animations unless pressed, cheaper
   bindings. Pixel-identical shots across flat/keycap/soft/line chrome (compare with HEAD like W38's `SHADOW_REF`).
2. **QuickPanel first frame:** with the lighter Block, measure again (W37-quick method: patch → view made, 7 warm opens,
   first open); target ≤ 8 ms warm.
3. **Idle windows:** what of the idle Stage and Launcher windows can be made lazily without breaking K16 (a persistent
   Stage — the destroy/recreate leak) or the launcher's cold-open time (W37-daemon: ≤ 40 ms frame gap)? Cut what's safe.
4. **Icon font:** Material Symbols Sharp resident almost whole (8.2 MiB): try a static instance or a subset of the glyphs
   the shell uses (generated at build time in Nix from a glyph list); measure.
5. I204: the quick tile's accent badge on its on-state container is 2.39:1 in dark wa-iro — tune
   `quick.tile.on.badge` in kurashi-theme to ≥ 3:1 for graphics without changing the look's identity.
6. `just bench-gate` before/after; a BENCH section with the numbers and what is left.

**Owned paths:** `frontend/components/{Block,SoftShadow,FocusRing}.qml`, `frontend/components/QuickPanel.qml`,
`frontend/surfaces/{Stage,Launcher}.qml` (lazy-loading only), `nix/` font derivation files (new), `crates/kurashi-theme/src/tokens.rs`
(the badge token only), `tools/bench/**`, `docs/BENCH.md` (append). Not the shadow lines of other surfaces (W39-shadows2).

**Acceptance:** pixel-identical chrome shots vs HEAD; QuickPanel warm build before/after; `just bench-gate` with PSS @1 output
reported; `just check` green.

**Contract rows:** CONTRACT-CHANGE rows 445–449 only.

**Env:** `CARGO_TARGET_DIR=$HOME/.cache/kurashi-agents-target/w39-block CARGO_BUILD_JOBS=6` (release builds for benches);
sandbox names `w39-block-…`; check the load average before measuring. Model: opus.
