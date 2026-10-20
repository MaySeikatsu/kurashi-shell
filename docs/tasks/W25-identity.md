# Card W25-identity — identity packs ported from shellseikatsu (K50; v0.3 "identity packs (game/OS decor)")

**User (session 10):** "Shellseikatsu (especially on the theme integrations and replicating similar styles) … don't
just draw inspiration but actual code snippets … if they solve a problem already." Decors are looks only (K45): never a
layout key. **Leave out every Cyberpunk preset** (Cyberpunk, Cyberpunk2077): the user plans an "isekai" decor of their
own (I117) and will send inspiration first. Efficient: QML prototypes first, few compiles.

**Sources (the user's own project — copy freely):** `~/Documents/projects/quickshell/shellseikatsu/`
- presets: `Services/Modes/*.qml` (+ `ModePresets.qml`), palettes in `Services/Appearance.qml` (`_<name>Palette()`
  functions near line 1359), frames `Widgets/ThemeDecor/*.qml` (+ `Widgets/ThemeDecor.qml`, `BevelBorder.qml`,
  `ShadowRing.qml`, `GlassSheen.qml`, `ScreenCorners.qml`), lockscreen styles `Panels/Lockscreen/`.

**Read first:** `CLAUDE.md`; DECISIONS K42, K45, **K50**; DESIGN-SYSTEM "Chrome and decor packs"; `decors/*.toml`
(format), `palettes/*.toml` (format + `crates/kurashi-theme/src/palette.rs` `BUNDLED`), `crates/kurashi-theme/src/decor.rs`,
`frontend/components/Block.qml`, `frontend/core/Theme.qml`, `frontend/test-look.sh`, `docs/ux/looks.md`.

**Owned paths:** new `palettes/*.toml` + their `BUNDLED` lines and `config.choice.palette.*` labels; new `decors/*.toml`
+ their `BUNDLED` lines in `decor.rs` and labels in `i18n/{en,ja}/decors.toml`; `crates/kurashid/src/theme.rs` **only**
to add the frame token (below); new `frontend/components/frames/**` and a `FrameHost.qml` used by `Block.qml` (a
single optional child, no other Block change); `frontend/components/LockContent.qml` (lock backdrops per frame);
`frontend/shots/look/**`; `docs/ux/looks.md` (append the pack list with sources); `nix/hm-module.nix` (only if a font
package exists in nixpkgs for a pack). **Not yours:** surfaces, settings, other Rust. Sandbox names `w25-idt-`.

**Contract (yours to implement as written):** a decor file may have `[slots]` with `frame = "<name>"`; the theme
document gains token `decor.frame` (`""` when none) for the active decor (read the decor in `theme.rs` from
`theme.decor` + `kurashi_theme::decor::find`; note it in a doc comment and in DESIGN-SYSTEM). Frontend: `Theme.frame`
(add it in `frontend/core/Theme.qml` — the one line you may add there), `FrameHost` loads
`components/frames/<Name>.qml` by that name (a component per frame, drawn over a card's edge: corners, ornaments,
bevels; static, no animation unless `Theme.springOn` and visible). No renderer compares a decor's name (rule 4): the
frame name is data.

**Do:** port ~12 presets with their palettes, recipes (palette, scheme, chrome flat/keycap/soft/line, corners, radius
scale, motion, material, font chain with free fallbacks) and frames where shellseikatsu has one: Catppuccin, Tokyo
Night, Rosé Pine, NieR/YoRHa (YorhaFrame), Kawaii (KawaiiFrame), Retro/Win95 (bevel), Windows XP, Windows 7, PS2
(Ps2Frame), SNES (SnesFrame), Hollow Knight (HollowFrame), Dark Souls (StoneFrame/OrnateFrame), Material, macOS-like.
Each palette passes the AA test (`every_palette_scheme_contrast_passes_aa_after_wcag`); each decor passes the K45
test. Fonts not in nixpkgs stay in the chain with free fallbacks.

**Acceptance:** `cargo test -p kurashi-theme -p kurashid` green; `frontend/test-look.sh <decor> 'theme.decor = "<decor>"'`
for every new pack (bar, island, quick, launcher, lock) — read them and fix what looks wrong; a contact sheet
`frontend/shots/look/identity-sheet.png` (one row per pack, montage via a small python script without PIL if needed,
or keep individual shots and list them). Report (terse): packs, sources, shots, failures quoted, follow-ups.
