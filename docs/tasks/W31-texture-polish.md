# Card W31-texture-polish — fabric, wool, wood and metal that read as the real thing

**User (session 12):** textures that "replicate the texture of real life objects … give elements depth and a real world
feeling" — "please do your best at getting a high quality result". Lead's review of W31-texture-gen
(`frontend/shots/texture/ui-*.png`, `sheet.png`): leather, stone, dotted/lined/squared paper and halftone are good.
Four are not yet convincing:
- **fabric** reads as graph paper: a regular square grid of lines. Real plain-weave linen/canvas at UI scale shows
  *threads*: each warp and weft thread a rounded ridge whose highlight sits on its crown, threads slightly uneven in
  width and spacing (no two rows alike), slubs (thicker stretches), a fine fibre fuzz, and the over/under alternation as
  small rounded "pillows" — not lines between cells. Try a 3–4 px thread pitch with jitter, or offer a canvas look.
- **wool** is faint and reads as a diagonal twill. Make a knit: columns of V-shaped stitches (each V two plump, rounded
  loops with a soft valley between columns), a fuzzy halo from fibre noise, gentle unevenness per stitch. It must read as
  knit at amp 0.09 under the default light (315°/40°) — both legs of the V lit/shaded distinctly.
- **wood** reads as stacked parallel lines (planks of tape). Real wood: growth rings as *flowing, slightly converging and
  diverging* bands (cathedral arches in flat-sawn boards where the ring set is cut at an angle), wider early-wood and
  narrow darker late-wood (ink), long thin pores along the grain, occasional ray flecks, rare knots with rings bending
  round them; boards of different widths with fine seams. Must still wrap seamlessly in both axes.
- **metal** has long scratches that cross the whole card at random angles and look busy; the brushed grain is too weak.
  Real brushed/scratched steel: a dense, fine, uniform brushed streak along one direction is the dominant feature
  (anisotropic, many short varying streaks), plus a *few* short light scratches in mostly similar directions, and a
  couple of tiny dings. Calm at a glance, rich up close.
Also look again at **paper** (plain): very faint at amp 0.09 — a touch more fibre/formation relief, still quiet.

**Read first:** `docs/tasks/README.md` (common rules), `docs/ux/texture.md`, DESIGN-SYSTEM "Texture and light" (frozen
formula), `crates/kurashi-texture/src/` (your earlier card's code: weave.rs, wood.rs, metal.rs, paper.rs).

**Owned paths:** `crates/kurashi-texture/src/{weave,wood,metal,paper,noise,wrinkle,generate}.rs` (+ new modules in the
crate), `crates/kurashi-texture/tests/**`, `crates/kurashi-texture/examples/**`, `frontend/shots/texture/*.png`. Keep the
public API in `lib.rs` (do not edit lib.rs unless a material constant in `material()` must change — then only that).
Bump `generate::VERSION`.

**Acceptance:** all crate tests (seams, determinism, timing ≤ 300 ms release) green; `sheet.png` and `ui-*.png` regenerated;
add `detail-<kind>.png` (a 1:1 384×256 window at amp 0.12, light 315°/40°, on `#f3eee3`) for fabric, wool, wood, metal,
paper and commit them. Look at each 1:1 detail yourself and iterate; report honestly what still falls short.
`cargo clippy -p kurashi-texture --all-targets -- -D warnings`, `cargo fmt`.
`export CARGO_TARGET_DIR=$HOME/.cache/kurashi-agents-target/W31-texture-polish CARGO_BUILD_JOBS=8`.
