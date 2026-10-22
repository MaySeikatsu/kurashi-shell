# Card W32-texture-gen — brush strokes, cracks, heights for relief shadows, sharper normals, faster tiles

**User (session 13):** "Besides 'Wrinkles' (which I really like), could we also add a 'crack' modifier that simulates a
cracked texture similar to cracks in stone surfaces, or broken glass?" — "Add a second brush stroke texture (current one
is oil painting and more like spotted strokes) and the second should look like a paint brush with lots of small hairs
painting lines over the whole canvas … but less separated and more continuous over the whole canvas (monitor)."
References (read both with your Read tool): `/tmp/nix-shell.xIMwad/claude-1000/-home-maike-Projects-kurashi-shell/ac70dfdf-3b7f-4233-a1b5-4df2cf2ab50f/images/1.png`,
`…/images/2.png` (same directory). Take the *relief* from them, not the colour: long sweeping strokes, hundreds of fine
bristle tracks running the whole length of a stroke, ridges of paint at stroke edges, dry-brush breakup where a stroke
thins — but unlike the pictures, strokes overlap and continue so the whole sheet is covered (no bare canvas islands).
Also "a stronger texture effect with more depth" — the height map you export feeds relief shadows (K61).

**Read first:** `CLAUDE.md`; `docs/tasks/README.md` (common rules); `docs/ux/texture.md` (whole, incl. "Wave 32");
DESIGN-SYSTEM "Texture and light" (the K61 formula — frozen); DECISIONS K59, K61; `crates/kurashi-texture/**` (all of it:
`generate.rs`, `paint.rs`, `wrinkle.rs`, `stone.rs`, `noise.rs`, `raster.rs`, `lib.rs` incl. `shade_at`, the tests and
`examples/sheet.rs`). BACKLOG I169, I170, I171.

**Task:**
1. **Kind `brush`** (`Kind::Brush`, a stand-in calls `paint::oil` today): a new generator (`brush.rs`). Seamless and
   deterministic like every kind. Strokes long relative to the tile (several tile-widths of path, wrapping), gently
   curved, mostly one dominant direction with some variation, layered so the sheet is fully covered; each stroke a
   bundle of fine bristle grooves (sub-pixel to ~1.5 px apart at scale 1, varying depth, some bristles running dry and
   breaking up), slight ridges along stroke edges and a thicker blob where a stroke starts. Ink: a faint pigment tone
   variation (as paint). Material values in `material()` (gloss/shininess like wet acrylic; `shadow: 1.0` already set).
2. **Cracks** (`Params.cracks` 0–1, `Params.crack_style`): applied after wrinkles to any kind. `Stone`: a jagged,
   branching network (domain-warped cellular edges + secondary hairline branches; crack width and depth taper; slightly
   raised lips). `Glass`: shards with straight edges (cellular with straight bisectors), each shard tilted a little as
   its own plane (that changes its normal → light catches shards differently), thin deep crack lines between shards,
   finer radial/conchoidal hairlines near some junctions. `cracks` scales density and depth (0 = untouched, identical
   bytes to no cracks). Ink: none from cracks (they are relief). Keep the sheet seamless.
3. **Heights for shadows:** `finish()` already exports `Tile.height` (min/max normalised) and `Tile.relief` (px). Make
   the normalisation robust (e.g. 0.5th–99.5th percentile, clamp) so one spike does not flatten the rest, and check every
   kind's `relief` is plausible (paper well under 1 px, paint/brush a few px, wrinkled/cracked more). Tune so
   `shadows = on` on `paper_dots` (kami) gives faint, short shadows at depth 1 and `paint`/`brush` clearly sculpted ones.
   `shade_at` is the contract: do not change its formula (a needed change → CONTRACT-CHANGE row).
4. **I170** finer normals: a wider or two-scale kernel so detail finer than ~2.5 px survives (bristle tracks, weave).
   **I171**: generate rows in parallel (`std::thread::scope`), bytes identical to the sequential result (test it).
   Bump `generate::VERSION`. Report the generation time per kind at scale 1 and 2 before/after.
5. **I169** (optional, if it still reads busy with the new `texture.lit` = 0.6 on dark grounds): less fibre relief under
   the ruled paper kinds. Judge on a dark contact sheet.
6. **Contact sheets** (`examples/sheet.rs`, use `shade_at` so shadows show): `frontend/shots/texture/sheet.png` (all 13
   kinds, four light directions, tinted and plain, light and dark ground), `sheet-cracks.png` (every kind with stone and
   with glass cracks at 0.5), `sheet-shadows.png` (paper_dots, fabric, stone, leather, paint, brush at depth 1 and 2.5,
   shadows off/on, light at elevation 20° and 60°). Look at them yourself and iterate until each reads as its material.

**Owned paths:** `crates/kurashi-texture/**`, `frontend/shots/texture/*.png` (top level only). Not `crates/kurashid/**`
(the daemon is the lead's), not `frontend/**` otherwise.

**Acceptance (executable):** `cargo test -p kurashi-texture` (seams, determinism incl. parallel = sequential, every kind
incl. brush with cracks both styles, heights within 0..255 with a non-zero relief for every kind) and
`cargo clippy -p kurashi-texture --all-targets -- -D warnings` green; the three sheets regenerated; report the timing
table and each kind's `relief`.

**Thrift / env:** own build dir `CARGO_TARGET_DIR=$HOME/.cache/kurashi-agents-target/w32-gen`, `CARGO_BUILD_JOBS=4` (five
agents share 12 cores). You need no sandbox. Model: judgement-heavy art — iterate on the sheets.
