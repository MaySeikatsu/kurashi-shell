# Design system

## 1. Token layers
```
primitives (palette raw colours, type scale, spacing scale)
  → semantic roles   (surface, surface_container{lowest..highest}, on_surface, on_surface_variant,
                      outline, outline_variant, accent, on_accent, accent_container,
                      on_accent_container, secondary…, success, warning, error, on_*, scrim, shadow)
  → component tokens (bar.bg, bar.fg, button.bg.hover, slider.track, island.bg, popup.chrome …)
  → per-surface overrides (bar vs popup vs lock)
  → per-output overrides (scale, density, OLED pure-black)
```
Renderers bind **only to component tokens**. The daemon resolves everything and ships a flat
token map (`theme` document); the frontend never computes colours.

Scales: spacing 4 px base (`xs 4, sm 8, md 12, lg 16, xl 24, 2xl 32`); radius
`none|sm|md|lg|full` × `shape.radius_scale`; type scale (caption, label, body, title, display);
motion tokens (`instant, quick 120, standard 220, emphasized 320, long 500` ms) with easing roles
(`enter, exit, emphasized, continuous`) × `motion.speed`.

## 2. Palette pipeline (ordered pure `Palette → Palette` stages)
1. **source** — `wallpaper` (in-process `material-colors`; a picture path is decoded at 128 px and extracted
   once per path, mtime and size, `stages::wallpaper_file`; a monochrome picture, mean HSL saturation under
   0.08, falls back to `wa-iro` and the provenance says so) | `palette:<name>` (TOML in `palettes/`) |
   `manual` (user roles)
2. **scheme** — light/dark: `portal` (`org.freedesktop.appearance color-scheme`) | `time` | `manual`
3. **contrast** — `standard | medium | high`
4. **season** — optional seasonal drift (旬; hue/temperature nudges by 二十四節気)
5. **colorblind** — `none | protanopia | deuteranopia | tritanopia` (Machado matrices)
6. **wcag** — enforce AA (4.5:1 body, 3:1 large/UI) by adjusting `on_*` roles; report fixes
Each stage is toggleable and appears in provenance (`cfg.explain theme.color.accent`).

Status marks (K25, I27) are derived tokens, not palette roles: `color.status.on` and `color.status.off` are
graphics (3:1 on the surface); `color.status.warn` is text (4.5:1 on the surface) for activity levels and low
battery. The wallpaper mod's picker previews the `wallpaper` source with its `wallpaper.preview` dry run.

## 3. Axes (orthogonal, all user-pinnable)
| Axis | Values |
|---|---|
| `shape` | corner style `none|rounded|squircle`, `radius_scale` |
| `material` | `solid|translucent|glass`, `opacity`, `blur` (request; capability-forced off if unsupported) |
| `motion` | profile `calm|lively|none` + `speed` |
| `density` | `compact|regular|airy` (scales spacing + control sizes) |
| `typography` | family chain (resolved via fontconfig → first installed), scale |
| `icons` | glyph set (`lucide` default), weight, app-icon theme |

## 4. Styles, looks and palettes (identity without renderer branches)

**K53 — three kinds of appearance pack, each a file** (`kurashi-theme::appearance`; bundled + `~/.config/kurashi/{looks,styles}/`):

| kind | file | key | what it sets | applying it |
|---|---|---|---|---|
| **Palette** | `palettes/<n>.toml` | `theme.colors.palette` | colours only | sets the palette |
| **Look** | `looks/<n>.toml` | `theme.look` (default `kanso`) | form and feel without colour: chrome, corners, radius, material, motion, type family (`LOOK_KEYS`) + `[slots] frame` | `theme.look.apply`: resets your look keys, sets the look |
| **Style** | `styles/<n>.toml` | `theme.style` (default **`washi`**) | `look` + `palette` + density, tweaks of its own look (`STYLE_KEYS`) and a recommended scheme | `theme.style.apply`: resets every appearance key you set except light/dark, sets the style |

A look that only recolours another one is a palette. Every pack names a `category` (`modern`, `inspired`, `retro`,
`fiction`; `custom` for a user file without one) — Settings groups by it. The theme layer holds the look's recipe under
the style's (`theme: look:<n>` / `theme: style:<n>` provenance); a style's look tweaks apply only while its own look is
the one in effect. Every palette has a light and a dark scheme; light/dark is the user's mode (the quick settings'
Dark tile), a style only recommends one. Accessibility preferences, the seasonal tint, screen corners and app export
are never reset.

| style | category | look | palette | own recipe |
|---|---|---|---|---|
| washi | inspired | washi | wa-iro | light |
| kanso | modern | kanso | kanso | dark |
| material, glass, terminal | modern | same name | material / kanso / kanso | dark |
| catppuccin | modern | soft | catppuccin | dark, lively, opacity 0.92, radius ×1.3 |
| rose-pine | modern | soft | rose-pine | dark, radius ×1.15, Nunito |
| tokyo-night | modern | kanso | tokyo-night | dark, compact, calm ×1.25, opacity 0.88, radius ×0.85, mono |
| sekai, aqua | inspired | same name | same name | sekai light / aqua dark |
| win95, luna, aero, ps2, snes | retro | same name | same name | scheme; win95/snes compact |
| kawaii, yorha, hallownest, souls | fiction | same name | same name | scheme |

The tables below describe the looks (their columns other than palette); the original decor pack design follows.

### The pack design (K42)
A decor pack = **typed slots + recipe**:
- **Slots** per surface kind: `bar.frame`, `bar.background`, `popup.chrome`, `island.chrome`,
  `lock.scene`, `osd.chrome`, `button.style`. A slot is filled by a renderer component shipped in
  the pack (native tier) or left to the default.
- **Recipe** = recommended axis values + palette, applied at provenance layer `theme:<pack>`
  (below user pins). Example: `edo` recommends `palette:wa-iro`, `shape.none`, `motion.calm`,
  `typography: Noto Serif JP`; the user can still pin `shape.rounded`.

### Chrome and decor packs (K42, K45)
`theme.chrome = keycap` draws every block (bar pills, tiles, buttons, cards, the island) as a keycap: outline
(`chrome.outline` px, colour `chrome.line`), ring (`chrome.ring` px, `chrome.ring_color`), fill, and a hard shadow
(`chrome.shadow` px down, `chrome.line`). Pressed = the face sinks by the shadow and springs back
(`motion.spring.overshoot`). Flat chrome sets every width to 0. Components draw blocks through `Block.qml` only.
`theme.decor = sekai` recommends palette `sekai` (light), keycap chrome, lively motion, solid material, radius ×1.25
and Nunito, at the `theme:sekai` layer. Icons come from `Icon.qml` (Material Symbols Rounded ligatures, text-glyph
fallback).

K45 adds two chromes and makes every decor a whole look that never touches layout:

| chrome | outline | ring | shadow | soft shadow | press | bar groups |
|---|---|---|---|---|---|---|
| flat | 0 | 0 | 0 | 0 | scale 0.97 | one strip |
| keycap | 2 px `chrome.line` | 3 px | 4 px hard | 0 | sinks by the shadow | blocks |
| soft | 1 px light rim (`chrome.outline_color` × `outline_alpha`) | 0 | 0 | 18 px blur, 6 px down | scale 0.96 | blocks |
| line | 1 px outline role | 0 | 0 | 0 | none (fill flash) | blocks |

| decor | palette | chrome | corners | motion | type | icons |
|---|---|---|---|---|---|---|
| none | yours (wa-iro dark) | yours (flat) | yours | yours | yours | Rounded |
| sekai | sekai light | keycap | rounded ×1.25 | lively | Nunito | Rounded, filled, 600 |
| glass | kanso dark, glass 0.62 | soft | squircle ×1.4 | lively (settles) | Inter | Rounded, 400 |
| terminal | kanso dark, solid | line | none | calm ×1.6 | JetBrains Mono | Sharp, 300 |
| washi | wa-iro light, solid | line | rounded ×0.5 | calm | Noto Serif | Sharp, 300 |

Recipes name `theme.*` keys only. Layout (bar edge/height, desk, island placement) belongs to the user and profiles.

**Frames (W25, K50, K53).** A look's `[slots]` may name `frame = "<name>"`: art drawn over every block's edge. The
daemon reads it from the look in effect (`theme.look`, `kurashi_theme::appearance::find`) and publishes token
`decor.frame` (`""` for none);
`Theme.frame` carries it and `FrameHost.qml` (one optional child of `Block.qml`, and the lock's ground) loads
`components/frames/<Name>.qml` (kebab-case → PascalCase). The name is data; no renderer compares it (rule 4). A frame
paints from palette roles, so a pinned palette still fits; it is static (one paint per size and colour) and runs at
most a one-shot motion while visible with springs on (Ma). Kinds: `card` (≥ 120×64: the full frame), `small` (keys,
tiles, bar groups: a restrained edge or nothing), `ground` (the lock's backdrop, replacing the chrome-derived one).

| pack (W25, after shellseikatsu `Services/Modes/*.qml`) | palette | chrome | corners | motion | type chain (free fallback) | frame |
|---|---|---|---|---|---|---|
| catppuccin | catppuccin mocha | soft, translucent 0.92 | rounded ×1.3 | lively | Inter | — |
| tokyo-night | tokyo-night night | flat, translucent 0.88, compact | rounded ×0.85 | calm ×1.25 | JetBrains Mono | — |
| rose-pine | rose-pine main | soft, translucent 0.9 | rounded ×1.15 | calm | Nunito | — |
| material | material (M3 baseline) dark | flat, solid | rounded ×1 | calm | Roboto | — |
| aqua | aqua dark, glass 0.6 | soft | squircle ×1.35 | calm | SF Pro → Inter | sheen |
| yorha | yorha light | flat, solid | none | calm | Noto Serif | yorha |
| kawaii | kawaii light | soft, solid | rounded ×0.9 | lively | Quicksand → Comic Neue → Nunito | kawaii |
| win95 | win95 light | line, solid, compact | none | none | W95FA/MS Sans Serif/Tahoma → DejaVu Sans | bevel |
| luna | luna light | soft, solid | rounded ×0.6 | calm | Tahoma/Verdana → DejaVu Sans | luna |
| aero | aero light, glass 0.78 | soft | rounded ×1 | calm | Segoe UI → Noto Sans | aero |
| ps2 | ps2 dark | soft, translucent 0.92 | rounded ×0.5 | calm | SST/Zrnic → Inter | ps2 |
| snes | snes light | keycap, solid, compact | none | calm ×1.6 | Press Start 2P → JetBrains Mono | snes |
| hallownest | hallownest dark | line, translucent 0.94 | rounded ×0.6 | calm ×0.85 | Trajan Pro → Cinzel → Noto Serif | hollow |
| souls | souls dark | line, solid | none | calm ×0.8 | OptimusPrinceps → EB Garamond → Noto Serif | ornate |

## 5. Accessibility modes
`reduce_motion`, `reduce_transparency`, `high_contrast`, `large_text` force axes with
`forced_by: accessibility` (visible in Settings). Defaults follow the system portal where
available; never auto-switched silently.

## 6. Wa-iro (和色) default palette
| Role | Dark | Light | Name |
|---|---|---|---|
| surface | `#1b1a1e` | `#f3eee3` | 墨 sumi / 和紙 washi |
| on_surface | `#e9e4d8` | `#2b2a2e` | |
| accent | `#c9404b` | `#a8323b` | 紅 beni |
| secondary | `#5b7fa6` | `#284f7e` | 藍 ai |
| tertiary | `#8fa868` | `#5d7a3a` | 抹茶 matcha |
| warning | `#e0a33b` | `#b07a14` | 山吹 yamabuki |
(Final values verified by the WCAG stage in M2.)

## 7. Components (token-driven kit)
Button, IconButton, Toggle, Slider, Chip, SegmentedControl, List/ListItem, Card, Popover,
Tooltip, TextField, SettingRow (label · control · provenance chip · reset · reason), Island.
Every interactive component supports the universal input slots (left/right/middle/hover/scroll).
Focus ring only on keyboard focus (`focus-visible`). Touch targets ≥ 32 px.

## 8. The Island (島)
One container, many **faces**; shows one at a time. Morph = width/height tween + content
crossfade (`motion.emphasized`), first-frame gated. Hover → peek (slight expand + secondary
line). Left click → expanded view (island grows into a panel on the stage surface). Right click →
face picker / pin. Scroll → cycle faces. Arbitration lives in the daemon (ARCHITECTURE §5).

## 9. Motion rules
- Motion explains state change; no idle loops in core. Decorative motion only in mods, gated.
- Every animation has an owner and a visibility gate; hidden = stopped.
- Interruptible: reversing mid-animation continues from the current value.
