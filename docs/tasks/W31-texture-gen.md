# Card W31-texture-gen — real materials for the texture tiles

**User (session 12):** textures "that replicate the texture of real life objects" — paper with a slight grainy feel
(plain, dotted, lined, squared), wool or fabric, rough stone, print (a printed comic page), scratched metal, leather,
wood — "they shouldn't have color but kinda act more like a normal map in video games that gives elements depth and a
real world feeling" … "slight colors if it enhances the effect", always switchable to no colour … "maybe even crumbled
paper with some wrinkles" … "please do your best at getting a high quality result".

**Read first:** `CLAUDE.md`; `docs/ux/texture.md` (the whole brief); `docs/DESIGN-SYSTEM.md` "Texture and light" (tile
layout, tokens, the shading formula — frozen); DECISIONS K59; `crates/kurashi-texture/src/*.rs` (the lead's skeleton:
the API is frozen, `generate.rs` is a placeholder you replace); `frontend/components/frames/Paper.qml` (washi's fibre
grain, for the paper's character).

**Task:** make `kurashi_texture::generate` produce convincing, seamless, deterministic relief tiles for all eleven
kinds, plus wrinkles and the tint/plain variants, and tune `material()` (gloss, shininess, ink role/alpha). Viewed at
the default strength (`amp` 0.09) on a UI-like surface the material must read as itself at a glance, stay quiet behind
text, and never look like digital noise. Techniques that work (choose freely):
- **paper**: short curved raised fibres of varied width (as washi's), felted pores, a slow "formation" cloud of fibre
  density; tiny amplitude. Ink (tint): faint fibre pigment.
- **paper_dots / paper_lines / paper_grid**: paper + rulings at a 24 logical px pitch (tile_logical a multiple of it):
  dots ≈2.2 px across, lines ≈1 px, anti-aliased. Tint on: the rulings are ink only (A channel), no relief; tint off:
  blind-embossed (a dent with soft shoulders), A = 0.
- **fabric**: plain weave, threads going over/under with a rounded profile, per-thread width and twist striations,
  occasional slubs, fine fuzz. **wool**: knit stitches (V loops in columns) or felt, with a soft fuzzy halo.
- **stone**: domain-warped ridged fBm, pits (cellular), hairline cracks along cell edges, mineral speckle as ink.
- **halftone**: Ben-Day dots on a 45° lattice that still tiles (lattice vectors (p, p) and (p, −p)), radius following a
  slow tone field, slight dot gain on rough stock; dots are ink (relief only from the stock), plain: slightly raised.
- **metal**: brushed streaks along x (stretched 1D noise), random straight scratches of varied length/depth/angle, a few
  soft dents; high gloss.
- **leather**: pebble grain (cellular, rounded cell tops, creased gaps), pores, a slow wrinkle; medium gloss.
- **wood**: growth rings along a periodically warped grain (planks), elongated pores along the grain, late-wood tone as
  ink; the pattern must wrap in both axes.
- **wrinkles** (0..1, any kind): crumpled facets (cellular cells, each a tilted plane) with sharp ridged creases at their
  edges and a few long folds — 0 adds nothing.
Tiles: logical size per kind of your choice (≤ 1024 logical; rulings/halftone a multiple of their pitch), device size
`logical × device_scale` capped at 1024 px (scale the logical size down if needed). Normals from the height field by
central differences with a per-kind depth; B = normalised cavity. Bump `generate::VERSION`. `tile_file` should load a
cached PNG instead of regenerating it (keep the signature).

**Owned paths:** `crates/kurashi-texture/**` (keep the public API's names and signatures and `shade` exactly as in
DESIGN-SYSTEM — an API or formula change you need → a row in `docs/CONTRACT-CHANGE.md` 270–279, never in place),
`frontend/shots/texture/**`, `Cargo.lock`.

**Acceptance (executable):**
- `cargo test -p kurashi-texture`: per kind and tint/plain and wrinkles 0/0.6 — deterministic; seamless (the mean
  absolute difference of the height-derived channels across the wrap edge, both axes, is ≤ 1.5× the mean across interior
  neighbour columns/rows); value ranges (a flat-ish material averages near (128, 128, 128)); tint off ⇒ A = 0 everywhere;
  rulings at their pitch (sample the A channel); generation time in release ≤ 300 ms per tile at device_scale 1 (an
  `#[ignore]` timing test you run with `--release -- --ignored`).
- `cargo run -p kurashi-texture --release --example sheet -- frontend/shots/texture/` writes `sheet.png` (every kind ×
  light from 4 directions, tint and plain, on a light paper `#f3eee3` and a dark `#1b1a1e` ground, at amp 0.09, labelled)
  and `ui-<kind>.png` (a 640×360 mock: a 36 px bar with three blocks and a card with two lines of text, wa-iro light,
  the sheet continuous across bar and card, light from 315°/40°). **Look at every image yourself** (Read shows images)
  and iterate until each material is convincing; say in the report which ones you are least happy with.
- `cargo clippy -p kurashi-texture --all-targets -- -D warnings`, `cargo fmt`.

**Thrift:** read only what is listed; terse report (what each kind does, sheet paths, timings, CONTRACT-CHANGE rows,
ideas). `export CARGO_TARGET_DIR=$HOME/.cache/kurashi-agents-target/W31-texture-gen CARGO_BUILD_JOBS=8`. No GUI; this
card needs no sandbox.
