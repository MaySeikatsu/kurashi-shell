# Drop shadows — strength, direction, and shadows that follow the light (K67, I173b)

What the user asked for (session 13, item d): "static drop shadows with direction and strength set in Settings by default;
optionally dynamic ones that follow the light source." This brief covers the blocks' and surfaces' drop shadows: the
keycap's hard shadow, the soft chrome's blurred one and the press that sinks onto it. The relief's own shadows (grain,
threads) are the texture's (`docs/ux/texture.md`); true cast shadows across windows need the compositor (out of scope).

## How others do it

- **macOS**: one window shadow, always below and slightly larger at the bottom (a light above the screen); focused windows
  cast deeper ones. Not adjustable — the direction is part of the system's look. Lesson: one light for everything; depth
  says what is in front.
- **Material (M2/M3 elevation)**: a key light from above and an ambient light; shadows fall straight down and grow with
  elevation. M3 adds tonal elevation instead of shadows on dark themes. Lesson: shadow length is height; the direction is
  never per component.
- **Neumorphism kits** (soft UI generators): a light angle and a distance/intensity slider drive a light and a dark shadow
  on opposite sides. Lesson: angle + strength is the natural pair of controls; too strong reads muddy (our alpha cap).
- **KDE Breeze**: Window Decorations → shadow size (none … very large) and strength (opacity), colour; the direction is
  fixed (down). Lesson: "none" must really be none, and strength scales both size and darkness.
- **Quickshell shells** (Caelestia, end-4, DankMaterialShell, Noctalia): a fixed `DropShadow`/`RectangularShadow`
  offset down, sometimes a size option; none follow a light. **COSMIC/GNOME**: fixed shadows from the theme.
- **Games / skeuomorphic UIs**: drop shadows from the scene's sun; low sun = long shadows. Our daytime light is that sun.

Kurashi's take: the defaults are the look's own (keycap 4 px hard, soft 6 px blurred, straight down). Settings has
strength (0–2) and direction (degrees); with a material on, shadows can instead fall away from the material's light, longer
when it stands low — one light for the relief and the shadows.

## Model

One vector for the whole shell, resolved by the daemon (`kurashi_theme::tokens::shadow_tokens`):

- `shadow.dx`, `shadow.dy` = unit direction × the look's length (`chrome.shadow`, or `chrome.soft_dy` for soft chrome) ×
  strength. Direction: `theme.material.shadow_angle` (0 up, 90 right, 180 down, 135 down-right), or, with
  `theme.material.shadow_follow` in effect, away from `light.dir`, the length × `tan 40° / tan elevation` within 0.5…2 (the
  light's default height 40° gives the look's own length).
- `shadow.alpha_scale` = strength, capped so a soft shadow never passes 0.9 opacity ("twice as long and dark").
- The pointer's lamp and the spotlight cast from their **rest** direction (the static angle): shadows never move with the
  pointer. The sun (daytime) moves them every few minutes — one repaint per change. The wallpaper's light: from its bright
  spot; a flat or missing picture lights from above, which is today's shadow.
- `chrome.shadow` / `chrome.soft_dy` stay the look's lengths and the **room a block keeps** below its face: changing the
  shadow never moves layout. A longer or sideways shadow reaches past that room (the bar centres face + shadow together so
  they stay in its window).

## States

| State | What is drawn |
|---|---|
| Default (strength 1, 180°) | Exactly today's shadows (pixel-checked against the frontend before K67) |
| Strength 0 | No shadow at all; a keycap press flashes its fill (nothing to sink onto), blocks keep their room (no layout jump) |
| Strength 0.5 / 2 | Half / twice as long; soft shadows half / twice as dark (capped) |
| Sideways (90°, 270°) | The hard shadow beside the key; the press sinks sideways |
| Upwards (0°) | The shadow above the face (it reaches out of the block's room; the bar keeps it in its window) |
| Following, light low / high | Longer (≤ 2×) / shorter (≥ ½) |
| Following, light overhead | No direction: the static angle decides |
| Following without a material | Inert (`requires theme.texture.kind != none`); Settings says why; the static angle is in effect |
| Direction while following | Inert; Settings says "Only applies while Shadows follow the light is off" |
| Flat or line chrome | No shadow whatever the rows say (tokens 0, 0; CONTRACT row 423 asks for an inert reason) |
| No theme yet (daemon away) | Theme.qml's fallbacks are today's shadows |

## Settings

Appearance → Material: **Shadows** (slider 0–2, "you/default" chip, reset), **Shadow direction** (slider, degrees, inert
while following), **Shadows follow the light** (switch, inert without a material). Under Shadows one preview block of the
look in effect casts the shadow in effect (the daemon's tokens: what you see is what is on). The rows are schema rows
(rule 3): search, reset, undo and provenance come free.

## Keyboard and a11y

- The rows are ordinary schema sliders and a switch: Tab, arrows, Home/End; their labels and help are the schema's.
- The preview is decorative (`Accessible.ignored`): the numbers are in the rows.
- High contrast forces the material off, so following is inert there and shadows are the look's as it draws them; strength
  still applies (a user may want stronger edges). Shadows never carry meaning on their own.
- Reduce motion: the press sink follows the motion profile as before (no animation under `none`).

## Motion

The sink travels the vector with the same spring as before (70 ms down, `stdMs + 60` back with the overshoot). A new
direction (a settings change, the sun moving) is a cut: shadows never animate across the screen.

## Multi-output

One light, one vector for every output (the light's angle is screen-relative). Per-output overrides are not offered.

## Budget (Ma)

No per-frame work: the vector is three tokens; the hard shadow is one Rectangle (or one path layer for the island, Stage
and sidebar shapes, moved by its `x`); the soft shadow one static `RectangularShadow`. Pointer motion never reaches the
daemon's shadow tokens. `frontend/test-shadows.sh` checks: 0 frames while the pointer sweeps with following on (static
light and the pointer's lamp), one repaint and then 0 frames after a light change.

## Definition of done

- [x] Defaults draw exactly what they drew before (token goldens: only the three keys added; pixel identity of bar, island
  card and quick settings under keycap, soft, flat and line looks, `SHADOW_REF`).
- [x] Strength and direction act on Block (hard shadow, soft shadow, press sink), SoftShadow, MorphShape, ColumnShape and
  the bar's groups; shots of keycap and soft × 180/135/225 × 0.5/1/2 (`frontend/shots/shadows/sheet.png`).
- [x] Following: away from the light at 315° and 45°, high and low; the pointer's lamp casts from rest; inert without a
  material; the direction inert while following — shown in Settings with the reason.
- [x] Pressed key sinks along the vector (`sheet-press.png`).
- [x] Ma: 0 frames while the pointer moves; a light change repaints once.
- [x] Settings rows with provenance and a live preview block.
- [ ] Surfaces outside W38 that draw their own straight-down shadow follow the vector (CONTRACT row 422).
- [ ] A left sidebar's sideways shadow (CONTRACT row 421).
- [ ] Inert reason under flat/line chrome (CONTRACT row 423).
