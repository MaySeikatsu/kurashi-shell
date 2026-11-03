# W62 — Texture "Display" (pixel grid, after the YoRHa wallpaper) (session 20, user)

**Goal.** A new `theme.texture.kind` = `display`: the look of an LCD/CRT pixel grid as on the YoRHa wallpaper — a fine,
regular lattice of small square cells (≈3–4 px pitch at 1×) with darker gaps between them, very low contrast, so a flat
dark surface reads as "seen through a screen". Reference screenshot (local only, do not commit):
`/tmp/claude-1000/-home-maike-Projects-kurashi-shell/88202c82-a229-490f-9f8f-1d8c173e4389/scratchpad/ref/yorha.png`.
It must sit on the pixel grid (no blur/shimmer at 1×; at fractional scales keep it crisp or soften honestly), take the
material's light like the other kinds, and be offered wherever the kinds are (Settings' texture cards, the wallpaper's
own material, the ghostty terminal shader recipe — `ghostty_shader::KINDS` and its test require every kind to have one).
Optionally let the `yorha` style pick it if that improves the style (`styles/yorha.toml`) — say so in the report.

**Owned paths.** `crates/kurashi-schema/src/v1.rs` (`TextureKind` only) + goldens (`UPDATE_GOLDEN=1`), the texture tile
generator(s) and shader(s) in `crates/kurashi-theme/src/` and `frontend/shaders/` (find every consumer that mirrors the
kinds: DESIGN-SYSTEM "Texture and light" names three), `crates/kurashid/src/texture.rs`, `settings/components/TextureCards.qml`
(only if a card needs an entry), `i18n/{en,ja}/` (choice label), `styles/yorha.toml` (optional), `docs/DESIGN-SYSTEM.md`
(the kind's line), `docs/ux/texture.md` (append).

**Frozen.** Protocol; `theme_export.rs`, `export.rs` and `templates/` except `ghostty_shader.rs` (another branch edits
the export — touch only the shader recipe file).

**Acceptance.** `just check` green (incl. the glslang compile of every kind); `just suites --changed` green; on niri
(`tools/bench/niri-sandbox.sh`, a dark palette, e.g. style yorha): a screenshot of a panel with `display` at 1× and one
zoomed crop read with `magick … txt:` showing the regular cell/gap pattern. Report paths (local, untracked).

**Model.** Haiku (max effort): the scope is clear, the kind is mirrored by rule.

**Thrift.** Read `docs/ux/texture.md`, DESIGN-SYSTEM "Texture and light", the files above. Terse report. Build in
`CARGO_TARGET_DIR=$HOME/.cache/kurashi-agents-target/W62`. No AI attribution in commits.
