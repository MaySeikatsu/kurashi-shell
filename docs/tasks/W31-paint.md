# Card W31-paint — oil paint with deep brush strokes

**User (session 12):** "a texture that emulates the texture of painted brush strokes with deep ductus/brush lines would
be a nice texture too (maybe something like a canvas texture)". Same bar as the other materials: "a real world
feeling", "a high quality result"; colourless relief (ink only as a slight pigment tone, switchable off).

**Read first:** `docs/tasks/README.md` (common rules), `docs/ux/texture.md` (table row `paint`), DESIGN-SYSTEM "Texture and
light" (frozen formula and tile layout), `crates/kurashi-texture/src/` — especially `weave.rs` (the canvas you build on),
`raster.rs`, `noise.rs`, `generate.rs` (the `Kind::Paint` placeholder dispatch) and `tests/materials.rs`.

**Task:** `Kind::Paint` (new module, e.g. `paint.rs`): impasto oil paint on primed canvas, as seen on a real painting under
a raking light.
- **Strokes**: a few dozen overlapping strokes per tile, each a curved path (a gentle arc or S) of varying length and
  width, laid in loose families of similar direction (a painter works in passages), crossing at times. Later strokes lie
  over earlier ones.
- **Ductus / bristles**: inside a stroke, many fine parallel grooves along its path (the bristles' tracks) with uneven
  depth; the paint body thickest mid-stroke, thinning and breaking up (dry brush) toward the tail, with a raised ridge
  of pushed paint where a stroke starts or stops, and slightly raised edges along its sides.
- **Canvas**: the canvas weave from `weave.rs` showing through where the paint is thin (tails, gaps), muted under thick
  passages.
- Ink (tint on): a slight pigment-tone variation that follows the strokes (thicker paint a touch darker), alpha low;
  tint off: none. Gloss from `material()` (0.3 / 24) — keep or tune.
- Seamless in both axes (strokes that cross an edge continue on the other side), deterministic, ≤ 300 ms per tile in
  release, wrinkles still work.

**Owned paths:** `crates/kurashi-texture/src/{paint,generate}.rs` (+ new modules), `crates/kurashi-texture/tests/**`,
`crates/kurashi-texture/examples/**`, `frontend/shots/texture/*.png`. In `lib.rs` only the `Kind::Paint` line of
`material()` if a constant must change. Bump `generate::VERSION`.

**Acceptance:** crate tests green (seams, determinism, timing, add paint to the golden/variant lists as the others are);
`sheet.png`, `ui-paint.png` and `detail-paint.png` (1:1 384×256, amp 0.12, 315°/40°, on `#f3eee3`) regenerated and
committed. Look at the 1:1 detail yourself and iterate until it reads as a painting's surface at a glance and stays calm
enough behind UI text at amp 0.09. `cargo clippy -p kurashi-texture --all-targets -- -D warnings`, `cargo fmt`.
`export CARGO_TARGET_DIR=$HOME/.cache/kurashi-agents-target/W31-paint CARGO_BUILD_JOBS=8`. No GUI.
