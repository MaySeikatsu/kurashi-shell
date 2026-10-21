# UX brief — Material textures, light and 紙 (K59, K60; I163)

A **texture** is the material the shell is made of: paper, fabric, stone, metal, leather, wood. It is a relief, not a
picture: a height field lit by one light, so it adds depth (light and shade) and never colour of its own — any style,
palette and scheme stays itself underneath. A **light** decides where that depth comes from: fixed, following the
pointer, or following the sun. **紙 (kami)** is the first style built on it: a notebook page written with a blue pen.

User (session 12): "These textures shouldn't have color but kinda act more like a normal map in video games that gives
elements depth and a real world feeling." … "faint ink in the theme's color is fine as well as slight colors if it
enhances the effect … important would be that it's possible to toggle it to no color." … "I prefer the continuous sheet
as a default." … light modes static (position configurable) / dynamic (from the pointer) / daytime (sunrise to sunset,
position and colour) … text untextured by default, with an option to texture it "to make the texture feel
uninterrupted (if you write on leather or a paper the font also adjusts to the texture)".

## How others do it
- **Windows Fluent Acrylic** layers a 2 % noise texture over blur and tint "to give the material a tactile feel"; the
  noise is static and colourless — our `paper` grain at low strength is the same idea. **Fluent Reveal highlight**
  (Windows 10) lit borders and fills from the pointer's position: the reference for the pointer light — it was
  dropped in Windows 11 partly because it lit everything at once; ours lights a relief, never edges or text.
- **iOS 6 / OS X 10.7–10.8 skeuomorphism** (linen, leather Calendar, felt Game Center, paper Notes): materials as
  bitmaps with baked light — they went stale because the light was painted in, fixed and inconsistent between apps,
  and colour came with the texture. We keep one light for every surface, and no colour unless asked.
- **iOS 26 / visionOS Liquid Glass**: specular highlights react to device motion and gaze — light as a live input, the
  reference for "the light moves, the material stays".
- **GNOME, KDE, COSMIC, macOS today**: flat, no materials. KDE Plasma themes (SVG) can carry bitmaps but nothing lit.
- **Quickshell shells (Caelestia, end-4, DankMaterialShell, Noctalia)**: none ship a material texture; rice configs
  add film grain with Hyprland's `decoration:screen_shader` — a whole-screen shader (I164: our Hyprland adapter can use
  it later for a true blend over apps).
- **Notebook apps (GoodNotes, Notability, Apple Notes "lines and grids")**: plain, dotted, lined and squared paper as
  page templates — rulings in a faint blue, a red margin line; dots for UI-like layouts because they do not fight
  baselines. **Excalidraw / rough.js**: hand-drawn outlines (two passes, a slight wobble, a seed per shape so they never
  shimmer) read as sketched yet stay crisp and professional.
- **Games**: normal maps lit by a scene light (tangent-space normals, Lambert + a small specular) — exactly the model,
  with the light as a token.

## Model
`theme.texture` (what material), `theme.light` (where its light comes from), `theme.colors.ink` (the text colour). The
daemon generates the texture as a seamless tile (`crates/kurashi-texture`, deterministic, seeded) and resolves the
light; the frontend only samples and shades (one shader, `Relief`), the wallpaper bake reuses the same tile and math on
the CPU. Tokens in DESIGN-SYSTEM "Texture and light", PROTOCOL §8.

### Textures (`theme.texture.kind`, default `none`)
| kind | relief | ink (tinted, `theme.texture.tint`) | gloss |
|---|---|---|---|
| paper | fine fibres, felt pores, a slow cloud (formation) | faint fibres | matte |
| paper_dots | paper + a 5 mm dot grid | dots in the secondary role | matte |
| paper_lines | paper + ruled lines, a margin | lines in secondary | matte |
| paper_grid | paper + a 5 mm square grid | grid in secondary | matte |
| fabric | a plain weave of twisted threads, slubs | thread shade | matte |
| wool | felted knit loops, fuzz | — | matte |
| stone | fractal grain, pits and fine cracks | mineral speckle | low |
| halftone | printed Ben-Day dots on rough stock (a comic page) | dots in on_surface | matte |
| metal | brushed lines and random scratches | — | high, anisotropic |
| leather | pebbled grain cells, pores, creases | — | medium |
| wood | growth rings and long pores along the grain | late-wood tone | low |
| paint | oil paint on canvas: brush strokes with deep bristle grooves (ductus), ridges where a stroke ends, the canvas weave under thin passages | pigment tone | medium |

`theme.texture.wrinkles` (0–1) crumples any of them: folds and creases with sharp ridges (crumpled paper, creased
leather). `strength` (0–1) and `scale` (0.5–3) are the user's. With `tint` off the ink is relief only: rulings, dots
and grids are pressed into the sheet (blind embossing) instead of printed — no colour at all.

### Scope (`theme.texture.scope`, default `shell`)
| scope | how | cost |
|---|---|---|
| shell | every shell surface (bar, island, panels, sidebars, desk, launcher, notifications, lock, OSD) shades its blocks | one texture per window, a shader pass over blocks only; repaints only when they do |
| wallpaper | the daemon bakes the relief into the picture before awww/swww shows it | none at runtime; a re-bake (≈0.2 s CPU, fade) when the picture, texture or light changes |
| shell_wallpaper | both | both |
| everything | a click-through overlay over each output (apps included) | one full-output layer surface; fullscreen windows lose direct scanout; shows in screenshots and screencasts — Settings says so |

The sheet is continuous by default: a block shows the part of the sheet that lies where it is on the output, so the bar,
the island and a panel look cut from one page. Shading is exact for shade (black at α multiplies what is under it) and
a screen blend for light, so even the `everything` overlay modulates apps instead of veiling them.

### Text (`theme.texture.text`, default off)
Off: text and icons sit on the material, crisp. On: the relief shades text and icons too, as ink sinks into paper or
is pressed into leather. The legibility cap still holds (below).

### Light (`theme.light.mode`, default `static`)
- **static**: from `theme.light.angle` (compass degrees, where the light comes from; 315° = top left) at
  `theme.light.elevation` (10–80°; low light = long shadows = deeper relief). Neutral white.
- **pointer**: a lamp at the pointer, `elevation` sets its height. It follows the pointer over shell surfaces — a
  Wayland client learns the pointer's position only over its own surfaces — and glides back to the static light when
  the pointer leaves them (Settings says so; Shōjiki). The wallpaper bake keeps the static light.
- **daytime**: the sun of the weather mod's place (the same NOAA equations as the night light): sunrise from the left,
  noon from above, sunset from the right; low sun is long-shadowed and warm (gold, then red at the horizon), noon
  neutral, night a faint cool moonlight from above. Without a place it follows a 06:00–18:00 day and says so.
- **wallpaper** (user, session 12: "it shines onto the canvas from the bright(est) point(s) of the wallpaper"): a lamp
  at the wallpaper's brightest region — the peak of its smoothed luminance and the light-weighted centre of the bright
  pixels around it, so a sun or a window, never the average of two far highlights — in that region's colour (halfway to
  white), `elevation` its height. A flat picture (no region stands out) lights from above and says so. The wallpaper
  bake uses the same lamp, so the baked relief and the shell's agree.

### 紙 kami — the style (K60)
A clean notebook page: warm white (light) or blue-black (dark) paper, `paper_dots` relief at medium strength, a
hand-drawn outline round every block (`frame = "sketch"`: two seeded pen passes with pressure, a little overshoot at
the corners), Kalam for Latin and Klee One for Japanese, ink in **blue-black** on light paper and **light blue** on dark
paper, the accent a red correction pen, motion calm, corners slightly rounded. Polished enough to present: everything
aligned, no jitter, no clutter, legible at the default sizes.

### Text colour (`theme.colors.ink`, default `palette`)
The palette's own text colour, or an ink: `blue`, `black`, `sepia`, `red`, `green`, `violet` (each with a light- and
a dark-scheme shade) or `custom` (`theme.colors.ink_custom`, one colour for both). It colours text and icons
(`on_surface`, and `on_surface_variant` mixed from it); the WCAG stage keeps it AA on the surfaces and the theme notes
say when it nudged it. 紙 sets `blue`.

## States
- **none**: no texture, nothing loaded, no shader (0 cost).
- **generating**: the first use of a kind generates its tile (≈50–300 ms, a blocking thread); the shell keeps the
  previous texture (or none) until the token arrives — no flash.
- **unsupported**: a renderer without shader support (software) shows no texture; the theme note says so.
- **wallpaper scope without the wallpaper mod / backend**: the row is inert with the reason ("needs the wallpaper mod").
- **daytime without a place**: the fallback day with a note; **pointer** off shell surfaces: rests (above).
- **high contrast / reduce transparency**: texture forced off (`forced_by: accessibility`); **reduce motion**: the
  pointer light does not glide (snaps), daytime still moves (it is a state, not an animation).
- **style applied**: a style sets its texture (or none) — your own comes back with "Back to …" (`theme.texture.restore`,
  as K55 for light/dark).

## Settings
Appearance › **Texture** section after Palette: a grid of material cards (each the real tile, lit by the light in effect,
drawn by the daemon as a small preview image) with "None" first; then Strength, Scale, Wrinkles, Ink and colour,
Texture over text, Where (shell / wallpaper / both / everything, the cost line under "everything"). **Light** section:
mode pills; for static a dial — a lit relief disc you drag (or arrow keys: 15° steps; Page Up/Down: elevation) — with
the angle and elevation as numbers beside it; for daytime the sun's position now and the place it comes from. Text
colour sits with Palette (ink swatches, then a colour field for custom).

## Keyboard, a11y
Every control is a normal schema row (keyboard as Settings). The legibility cap: the shade amplitude under text is
capped so body text keeps 4.5:1 against the darkest and lightest point of the relief (`texture.amp`, with a note when
the cap bites). Texture over text is off by default. High contrast forces textures off.

## Motion and Ma
Static: the texture never animates. The pointer light repaints relief items only while the pointer moves over them; the
glide back is one 500 ms animation (`motion.long`), gated by visibility. Daytime: a daemon timer every 5 minutes only
while the mode is daytime (the light changes by under 1.5° in that time). The `everything` overlay commits a frame only
when the light changes.

## Multi-output
One sheet per output, registered in output coordinates. The tile is generated at the largest output scale. Wallpaper
bakes per output size.

## Budget
Tile 512×512 device px RGBA (1 MiB; 4 MiB at scale 2) per window that shows texture; the shader is one texture fetch +
a dozen ALU ops per pixel. Idle: 0 frames, 0 wakeups (static/daytime between ticks). Bench row in BENCH.md when merged.

## Definition of done
- Twelve kinds generate seamless, deterministic tiles (tests: seams, determinism, value ranges) and look like their
  material in a contact sheet (`frontend/shots/texture/sheet.png`), each lit from four directions, tinted and plain.
- The shell under each scope shows the texture continuous across bar, island and panels (pixel test: a row of samples
  across two windows continues), text crisp with `text` off, shaded with it on.
- The three light modes move the relief as described (shots at 4 static angles, pointer at 2 positions, daytime at
  07:00 / 12:00 / 18:30 with a fake clock).
- The wallpaper bake: a baked picture under awww in the sandbox, re-baked on a texture change, original picture untouched.
- 紙 in light and dark on every surface (`frontend/shots/look/kami/`, `kami-dark/`), presentable: the lead reviews.
- Settings: material cards, light dial, ink swatches (`settings/shots/appearance/texture-*.png`).
- `just check`, all suites green; BENCH row for shell scope idle frames 0 and PSS delta.
