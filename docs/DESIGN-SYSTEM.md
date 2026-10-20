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

## 4. Decor packs (identity without renderer branches)
A decor pack = **typed slots + recipe**:
- **Slots** per surface kind: `bar.frame`, `bar.background`, `popup.chrome`, `island.chrome`,
  `lock.scene`, `osd.chrome`, `button.style`. A slot is filled by a renderer component shipped in
  the pack (native tier) or left to the default.
- **Recipe** = recommended axis values + palette, applied at provenance layer `theme:<pack>`
  (below user pins). Example: `edo` recommends `palette:wa-iro`, `shape.none`, `motion.calm`,
  `typography: Noto Serif JP`; the user can still pin `shape.rounded`.

### Chrome and the `sekai` decor (K42)
`theme.chrome = keycap` draws every block (bar pills, tiles, buttons, cards, the island) as a keycap: outline
(`chrome.outline` px, colour `chrome.line`), ring (`chrome.ring` px, `chrome.ring_color`), fill, and a hard shadow
(`chrome.shadow` px down, `chrome.line`). Pressed = the face sinks by the shadow and springs back
(`motion.spring.overshoot`). Flat chrome sets every width to 0. Components draw blocks through `Block.qml` only.
`theme.decor = sekai` recommends palette `sekai` (light), keycap chrome, lively motion, solid material, radius ×1.25
and Nunito, at the `theme:sekai` layer. Icons come from `Icon.qml` (Material Symbols Rounded ligatures, text-glyph
fallback).

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
