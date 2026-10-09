# Card M2-theme — `kurashi-theme` (palette pipeline → flat token map)

**Goal.** The daemon resolves every colour, size, radius, font and duration and ships a flat
token map (the `theme` document). Renderers never compute colours (rule 4).

**Owned paths:** `crates/kurashi-theme/`, `palettes/` (repo root, new). Common rules:
`docs/tasks/README.md` (read first).

**Read:** `docs/DESIGN-SYSTEM.md` (all, short), `crates/kurashi-mock/src/main.rs` `theme_doc()`
(the token key style the frontend already binds to — your map must contain every one of those
keys), `docs/VISION.md` only the Shun (旬) paragraph.

**Build:**
1. Palette TOML format in `palettes/` (document it at the top of each file): name, kind
   (dark/light pair), roles. Ship ≥ 3: `wa-iro` (DESIGN-SYSTEM §6), a neutral `kanso` (low-chroma
   mono), and one high-contrast. Role set = DESIGN-SYSTEM §1 semantic roles.
2. Pipeline of pure `Palette → Palette` stages, each toggleable and each returning notes for
   provenance (e.g. `wcag: on_accent #f0e0e0 → #fff6f1 (3.9 → 4.6:1)`):
   source (`palette:<name>` | `manual` roles | `wallpaper` via the `material-colors` crate on a
   blocking thread from a downscaled image), scheme (light/dark input — the portal is not yours),
   contrast (standard/medium/high), season (旬: 二十四節気 computed from a date — small hue /
   temperature nudge, off by default), colorblind (Machado 2009 matrices, severity 1.0),
   wcag (AA: 4.5:1 body, 3:1 large/UI, fix `on_*` roles, report).
3. Axes → scales (DESIGN-SYSTEM §1/§3): spacing (4 px base) × density, radius × `radius_scale`
   (and shape none → 0), type scale, motion tokens (`quick/standard/emphasized/long` ms ×
   `motion.speed`, profile `none` → 0) + easing roles as cubic-bezier arrays.
4. Component tokens (`bar.bg`, `bar.fg`, `island.bg`, `popup.chrome`, `slider.track`,
   `button.bg.hover`, …) derived from roles; per-surface overrides; OLED pure-black option.
5. Output `TokenMap = BTreeMap<String, serde_json::Value>` with keys like the mock
   (`color.surface`, `color.surface_alpha`, `radius.md`, `space.md`, `font.family`,
   `font.family_jp`, `font.size.body`, `motion.standard_ms`, `motion.easing.enter`, `bar.height`, …).
6. Fonts: resolve a family chain to the first installed family through a trait
   (`FontProvider`), with an `fc-list`-based impl (subprocess is fine in the daemon) and a fake for tests.
7. Input is a plain `ThemeInput` struct (palette name, scheme, axes values, toggles) — the lead
   maps resolved config onto it later; don't depend on schema/config crates.
Exporters (GTK/kitty/…) are out of scope for this card.

**Acceptance (one command):** `cargo test -p kurashi-theme` green, including: golden token maps
for `wa-iro` dark + light (`tests/golden/*.json`, `UPDATE_GOLDEN=1` regenerates); a test that
every bundled palette × scheme × contrast passes AA after the wcag stage; a test that the map
contains every key of the mock's `theme_doc()`; Machado matrix sanity; season stage determinism
for fixed dates; material-colors source from a generated 16×16 image. Clippy `-D warnings`.
