# Card W37-ghostty — the material in the terminal (I174)

**Why:** the user (session 13, item f): terminal textures. Ghostty's `custom-shader` (GLSL, Shadertoy-style, the
rendered terminal in `iChannel0`) can carry the shell's material; foot, kitty and alacritty have no shader hook (colours
only — already exported, K49).

**Read first:** `CLAUDE.md`; `docs/tasks/README.md`; DECISIONS K49 (+ amendment), K59, K61; `docs/ux/texture.md`;
DESIGN-SYSTEM's texture formula section; BACKLOG I174; `crates/kurashi-theme/src/export.rs` (targets, `Output`, the
unfilled rule), `crates/kurashid/src/theme_export.rs`, the ghostty template; `crates/kurashi-texture/src/lib.rs`
(`shade_at`, kinds, `Material`) and `frontend/shaders/relief.frag` (or wherever `relief.frag` lives) for the look to match.

**Task:**
1. Find what ghostty's custom shaders allow (docs: `custom-shader`, `custom-shader-animation`, uniforms; no external
   textures). Write the findings in the brief (step 5).
2. **Generated shader:** the ghostty export also writes `ghostty/shaders/kurashi.glsl` and adds `custom-shader = …` to
   the theme file, only while the material is on for the shell (`theme.texture.*` resolved tokens) — otherwise no shader
   line (and the old file is emptied/removed the way K49's legacy rule does). The shader is a procedural relief close to
   the active kind (paper fibre, washi, stone, brush, …: hash/value noise; per-kind parameters baked from the tokens),
   the static light (`light.dir`, colour, `lit`) and depth baked in as constants, `texture.cracks` if cheap.
3. **Readability first:** the relief touches only background pixels (compare `iChannel0` with the baked background
   colour; text, cursor and selections pass through untouched); contrast of text stays within 1 % of the plain theme.
   `custom-shader-animation` stays off — the shader is static (Ma: no frames when the terminal is idle).
4. A unit test per kind: the generated GLSL compiles (`glslangValidator` from nixpkgs, Shadertoy wrapper as ghostty
   uses it) and contains no unfilled placeholder; a golden of one generated shader.
5. Brief `docs/ux/terminal-texture.md` (other terminals and shells: what ghostty/kitty/wezterm/foot allow; states:
   material off, kind without a procedural match, ghostty missing; budget: GPU cost per frame).
6. Shots: ghostty in a sandbox (ghostty from nixpkgs: `nix shell nixpkgs#ghostty`, never the user's config — set
   `XDG_CONFIG_HOME` to a temp dir) with `ls --color`, `htop`-like text, for two kinds × light/dark, beside the plain
   theme; a zoomed crop showing text untouched.

**Owned paths:** `crates/kurashi-theme/src/export.rs` and its templates (ghostty only), a new
`crates/kurashi-theme/src/ghostty_shader.rs` (or in kurashi-texture if the relief math lives better there — then only new
files there), `crates/kurashid/src/theme_export.rs` (only what multi-file output needs), `docs/ux/terminal-texture.md`,
a new `tools/test-ghostty.sh` + `tools/shots/ghostty/`.

**Acceptance:** `cargo test -p kurashi-theme` (GLSL compile per kind, golden) and `bash tools/test-ghostty.sh` with shots.

**Contract rows:** CONTRACT-CHANGE rows 400–404 only (e.g. a new export target name or schema key).

**Env:** `CARGO_TARGET_DIR=$HOME/.cache/kurashi-agents-target/w37-ghostty CARGO_BUILD_JOBS=6`; sandbox names `w37-ghostty-…`.
Model: opus.
