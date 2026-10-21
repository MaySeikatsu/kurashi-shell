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
2. **scheme** — light/dark (K55): mode `auto` (the portal's `org.freedesktop.appearance color-scheme`, dark without
   one) | `wallpaper` (the applied picture's mean L*, light from 55) | `dark` | `light`
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
| **Style** | `styles/<n>.toml` | `theme.style` (default **`washi`**) | `look` + `palette` + density, tweaks of its own look (`STYLE_KEYS`) and a recommended scheme | `theme.style.apply`: resets every appearance key you set (light/dark too, K55: "Back to …" restores yours), sets the style |

A look that only recolours another one is a palette. Every pack names a `category` (`modern`, `inspired`, `retro`,
`fiction`; `custom` for a user file without one) — Settings groups by it. The theme layer holds the look's recipe under
the style's (`theme: look:<n>` / `theme: style:<n>` provenance); a style's look tweaks apply only while its own look is
the one in effect. Every palette has a light and a dark scheme; a style sets light or dark too (K55), and the user's mode from
before comes back with "Back to …" (`theme.scheme.restore`). Accessibility preferences, the seasonal tint, screen corners and app export
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

### Texture and light (K59)
A material is a relief, not a picture (`docs/ux/texture.md`). The daemon generates a seamless tile per material
(`crates/kurashi-texture`), resolves the light and publishes tokens; renderers sample and shade with one function,
`kurashi_texture::shade` on the CPU (wallpaper bake, Settings swatches) and `frontend/shaders/relief.frag` on the GPU —
the two are kept identical.

**Tile:** square, seamless, `texture.tile_px` device px covering `texture.tile_logical` logical px; in memory RGBA8, on
disk two PNGs (rows 280–281: Qt premultiplies textures, so normals cannot share texels with a mostly-zero alpha):
`texture.map` opaque RGB — R, G the surface normal's x, y as `2v − 1` (x right, y down; z = `sqrt(1 − x² − y²)`), B the
cavity `2v − 1` (−1 crevice, +1 crest); `texture.ink_map` white RGBA with the ink coverage in A (`""` without ink). Flat
and ink-free = (128, 128, 128) and no ink.

**Tokens** (`theme` document; all present, `texture.amp` 0 and `texture.map` "" when there is no texture):
| token | meaning |
|---|---|
| `texture.map` | absolute path of the relief PNG (opaque RGB), `""` = none |
| `texture.ink_map` | absolute path of the ink PNG (coverage in alpha), `""` = no ink |
| `texture.tile_px`, `texture.tile_logical` | the tile's side in device px, and the logical px it covers |
| `texture.scale` | the user's scale: the sheet position is divided by `tile_logical × scale` |
| `texture.amp` | the largest shade either way (strength × 0.18, capped so body text keeps 4.5:1) |
| `texture.gloss`, `texture.shininess` | the material's specular amount and exponent |
| `texture.ink`, `texture.ink_alpha` | the ink colour (a palette role per kind) and its opacity at full coverage; 0 = tint off |
| `texture.text` | the relief also shades text and icons (drawn over content instead of under it) |
| `texture.shell`, `texture.overlay` | shell surfaces draw it (scope shell / shell_wallpaper); the click-through overlay is on (scope everything) |
| `light.mode` | `static` \| `pointer` \| `daytime` \| `wallpaper` |
| `light.lamp` | `[x, y]` the wallpaper light's lamp as fractions of the output (its brightest region), `null` otherwise |
| `light.dir` | `[x, y, z]` unit vector toward the light (x right, y down, z toward the viewer) |
| `light.color` | the highlights' colour (white for static and pointer; the sun's for daytime) |
| `light.height_px` | the pointer lamp's height over the sheet, logical px |

**Shading** (per pixel; `p` is the sheet position in logical px, in output coordinates — the sheet is continuous across
windows):
```
uv   = p / (tile_logical × scale)                       wrap; t = tile(uv), bilinear, 0..1
n    = normalize(2 t.r − 1, 2 t.g − 1, sqrt(max(0, 1 − x² − y²)))
cav  = 2 t.b − 1
L    = light.dir                                        static, daytime, and pointer away from the shell
     | normalize(pointer − p, light.height_px)          pointer over a shell surface
     | normalize(lamp × output − p, light.height_px)    wallpaper (a lamp at its brightest region)
diff = dot(n, L) − L.z                                  0 on a flat sheet: the material never shifts the overall tone
H    = normalize(L + (0, 0, 1))
spec = gloss × (max(dot(n, H), 0)^shininess − H.z^shininess)
s    = clamp(amp × (2 diff + 0.5 cav + spec), −amp, amp)
shade = s < 0 ? (0, 0, 0, −s) : (light.color × s, s)    premultiplied; black at α multiplies, light screens
ink   = (texture.ink × a, a), a = t.a × ink_alpha
out   = shade + ink × (1 − shade.a)                     drawn with a normal "over" blend on the surface
```
Light from compass angle θ (0 top, 90 right) at elevation e: `L = (sin θ cos e, −cos θ cos e, sin e)`.

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
