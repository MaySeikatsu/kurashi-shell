# Card W38-shadows — drop shadows you can set, and shadows that follow the light (K67; I173b)

**Why:** the user (session 13, item d): "Shadows: static drop shadows with direction and strength set in Settings by
default; optionally dynamic ones that follow the light source." K67 (lead, merged) added `theme.material.shadow`,
`shadow_angle`, `shadow_follow` and names the tokens.

**Read first:** `CLAUDE.md`; `docs/tasks/README.md`; DECISIONS K42, K45, K59, K61, K67; DESIGN-SYSTEM §1, §7 and "Texture and
light"; `docs/ux/texture.md` ("Light"), `docs/ux/looks.md`; BACKLOG I173; `crates/kurashi-theme/src/{tokens,lib,appearance}.rs`
(chrome tokens, LOOK_KEYS), `crates/kurashid/src/theme.rs` (light tokens, `light.dir`/elevation), `frontend/core/Theme.qml`,
`frontend/components/{Block,SoftShadow}.qml` and the surfaces that draw their own shadow (grep `shadowDy`, `softDy`).

**Task:**
1. **Tokens (kurashi-theme / kurashid theme):** `shadow.dx`, `shadow.dy` (px vector for a block of the look's shadow length:
   unit direction × `chrome.shadow` (or `soft_dy` for soft chrome) × strength) and `shadow.alpha_scale` (strength → soft
   shadow alpha, clamped). Static: the direction from `shadow_angle` (180 = today's look exactly — goldens must not move at
   the defaults). Follow: away from the light's static/day/wallpaper direction, length × f(elevation) (low light longer,
   capped ≈ 2×); pointer/spotlight modes use their rest direction. Strength 0 = no shadow (blocks still lifted? decide:
   `lifted` keeps the layout, no shadow drawn). Unit tests incl. the defaults-unchanged golden.
2. **Frontend:** Block's hard keycap shadow, SoftShadow, the press sink (moves along the vector, not straight down),
   the Stage/MorphShape/ColumnShape surface shadows and the bar's own shadow read the vector. No renderer branch on
   names (rule 4). A shadow that falls sideways must not be clipped by its window: grow window slack where needed.
3. **Ma:** no repaint on pointer motion (K67); a light change (daytime) repaints once.
4. **Settings:** the three rows appear on the Look/material page with provenance; `shadow_angle` inert with its reason while
   following; a small live preview (one block) if the page has a preview slot.
5. Shots (sandbox): keycap and soft chrome × angle 180 / 135 / 225 × strength 0.5 / 1 / 2; follow with the light at 315 and
   at 45, high and low elevation; pressed key (sink along the vector); a Stage card and a sidebar. Contact sheet.
6. `docs/ux/texture.md` (or a new `docs/ux/shadows.md`) brief section: other shells (macOS window shadows, Material elevation,
   neumorphism kits, KDE Breeze shadow settings), states, a11y (high contrast: shadows as the look draws them), definition of done.

**Owned paths:** `crates/kurashi-theme/src/{tokens,lib,appearance}.rs` + tests/goldens, `crates/kurashid/src/theme.rs` (shadow
tokens only), `frontend/core/Theme.qml`, `frontend/components/{Block,SoftShadow}.qml`, `frontend/components/island/MorphShape.qml`,
`frontend/components/sidebar/ColumnShape.qml`, the bar's shadow lines in `frontend/surfaces/Bar.qml`, `settings/` pages for
the material section only, a new `frontend/test-shadows.sh` + `frontend/shots/shadows/`, `docs/ux/shadows.md`.
W37-daemon runs in parallel in `crates/kurashid/**` (not theme.rs) and Stage/Launcher.qml — don't touch those.

**Acceptance:** `cargo test -p kurashi-theme -p kurashid theme` (defaults unchanged, vector math, follow); `bash frontend/test-shadows.sh`
with the shots; `test-morph.sh` washi + sekai still green; idle frames 0 with follow on and the pointer moving.

**Contract rows:** CONTRACT-CHANGE rows 420–424 only.

**Env:** `CARGO_TARGET_DIR=$HOME/.cache/kurashi-agents-target/w38-shadows CARGO_BUILD_JOBS=6`; sandbox names `w38-shadows-…`.
Model: opus.
