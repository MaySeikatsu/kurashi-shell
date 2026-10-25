# Card W37-quick — quick settings polish (K66; I86, row 104)

**Why:** I86's open items and K66's `quick.tile.on.*` tokens. The six tiles already draw a forced state; W37-daemon makes the
service documents send `forced_by` in parallel.

**Read first:** `CLAUDE.md`; `docs/tasks/README.md`; `docs/ux/quick-settings.md`; DECISIONS K66; DESIGN-SYSTEM §7 (quick tile
tokens); BACKLOG I86; `frontend/components/QuickPanel.qml`, `frontend/components/quick/**`, `frontend/test-quick*.sh`;
`crates/kurashi-theme/src/tokens.rs` (how component tokens are emitted) and its goldens.

**Task:**
1. **Row 104:** kurashi-theme emits `quick.tile.on.{bg,badge,fg}` from the palette (accent / selected roles, contrast ≥ 4.5
   for fg on bg); Theme.qml-side readers in the quick tile use them with the current look as fallback. Golden updated.
2. **Wallpaper tile:** bring back Random / Pause / Resume and the rotation line as a long-press / right-click menu on the
   tile (or drop the unused `mod-wallpaper.tile.random|pause|resume|rotating` keys and say why); right-click on a tile's main
   zone opens that menu or the tile's page — never nothing.
3. **Focus** when the contribution list changes (a mod tile appears/disappears while the card has focus): the focus stays
   on the same tile or moves to its neighbour; test it.
4. **forced_by:** verify each tile draws "Set by {by}" from its document's `forced_by` (mock docs with the field); shots.
5. **Lighter QuickPanel** (I199): it takes ~60 ms to build; find what is expensive (measure with the W35 harness or timestamps)
   and make the first frame cheaper (lazy pages, Loader for the media row, fewer Blocks) — report before/after.

**Owned paths:** `frontend/components/QuickPanel.qml`, `frontend/components/quick/**`, `frontend/components/QuickButton.qml`,
`frontend/test-quick.sh`, `frontend/test-quick-sections.sh` + shots, `crates/kurashi-theme/src/tokens.rs` (+ its tests and
goldens), `i18n/{en,ja}/quick.toml`, the wallpaper tile files under `mods/wallpaper/qml/` (tile only),
`i18n/{en,ja}/mod-wallpaper.toml` (tile keys only), `docs/ux/quick-settings.md`.

**Acceptance:** `bash frontend/test-quick.sh` and `test-quick-sections.sh` with new steps and shots; `cargo test -p kurashi-theme`;
QuickPanel build time before/after.

**Contract rows:** CONTRACT-CHANGE rows 415–419 only.

**Env:** `CARGO_TARGET_DIR=$HOME/.cache/kurashi-agents-target/w37-quick CARGO_BUILD_JOBS=4`; sandbox names `w37-quick-…`.
Model: haiku (max effort).
