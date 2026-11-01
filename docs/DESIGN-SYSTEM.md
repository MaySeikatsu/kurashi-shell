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
`none|sm|md|lg|full` from the one radius `shape.radius` R (K74: `lg = R`, `md = 2R/3`, `sm = R/3`; the frame's inner
corners and every dynamic join `R − thickness`, concentric); type scale (caption, label, body, title, display);
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
| `shape` | corner style `none|rounded|squircle`, `radius` (px, K74), `screen_corners_follow` (screen corners = R, default on) / `screen_corners` (px, while off) |
| `material` | `solid|translucent` (schema v7: glass is translucent + `blur`; the name is kept for a future liquid-glass material), `opacity`, `blur` (translucent only; request, capability-forced off if unsupported) |
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
`theme.decor = sekai` recommends palette `sekai` (light), keycap chrome, lively motion, solid material, radius 23
and Nunito, at the `theme:sekai` layer. Icons come from `Icon.qml` by ligature name (K69): `font.icons` is the shell's
subset "Kurashi Symbols Rounded" (line chrome: "Kurashi Symbols Sharp" first) when installed, else the full Material
Symbols family of that cut, else "" and components draw their text glyph. When `font.icons` is the subset,
`font.icons_fallback` names the full family of the same cut ("" otherwise). Icon draws in three tiers: the theme's
family; a name that renders wider than 1.5 × size (letters, not one ligature) moves to the fallback family; a name
neither draws shows its glyph, or a bullet when it has none, never a word.

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
| glass | kanso dark, translucent 0.62 + blur | soft | squircle ×1.4 | lively (settles) | Inter | Rounded, 400 |
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
(Session 16: catppuccin, tokyo-night and rose-pine are palettes now, not styles — a style that was only a palette is a palette choice; migration `v5_to_v6` keeps a config's appearance. The rows below are history.)
| catppuccin | catppuccin mocha | soft, translucent 0.92 | rounded ×1.3 | lively | Inter | — |
| tokyo-night | tokyo-night night | flat, translucent 0.88, compact | rounded ×0.85 | calm ×1.25 | JetBrains Mono | — |
| rose-pine | rose-pine main | soft, translucent 0.9 | rounded ×1.15 | calm | Nunito | — |
| material | material (M3 baseline) dark | flat, solid | rounded ×1 | calm | Roboto | — |
| aqua | aqua dark, translucent 0.6 + blur | soft | squircle ×1.35 | calm | SF Pro → Inter | sheen |
| yorha | yorha light | flat, solid | none | calm | Noto Serif | yorha |
| kawaii | kawaii light | soft, solid | rounded ×0.9 | lively | Quicksand → Comic Neue → Nunito | kawaii |
| win95 | win95 light | line, solid, compact | none | none | W95FA/MS Sans Serif/Tahoma → DejaVu Sans | bevel |
| luna | luna light | soft, solid | rounded ×0.6 | calm | Tahoma/Verdana → DejaVu Sans | luna |
| aero | aero light, translucent 0.78 + blur | soft | rounded ×1 | calm | Segoe UI → Noto Sans | aero |
| ps2 | ps2 dark | soft, translucent 0.92 | rounded ×0.5 | calm | SST/Zrnic → Inter | ps2 |
| snes | snes light | keycap, solid, compact | none | calm ×1.6 | Press Start 2P → JetBrains Mono | snes |
| hallownest | hallownest dark | line, translucent 0.94 | rounded ×0.6 | calm ×0.85 | Trajan Pro → Cinzel → Noto Serif | hollow |
| souls | souls dark | line, solid | none | calm ×0.8 | OptimusPrinceps → EB Garamond → Noto Serif | ornate |

### Decor slots and metrics (W53.0a, K80; docs/ux/styles.md "The shared system")
The system grows to fit each style 1:1 (K80 decided 8): everything a style is — its window and frame decorations,
bevels, OS colours, how things move, fonts, symbols, materials, controls — is data in its look, never a renderer branch
(rule 4). A family card writes toml and decor parts only.

**Slots** (`[slots]` in a look, `appearance::SLOTS`): `frame`, `title`, `start`, `tray`, `menu`, `scroll`, `tooltip`,
`focus`, `button`, `slider`, `toggle`, `lock`, `sounds`, `bar` (W53.2), `dock` (W53.4). Each is a component name (a slug; `""` or left out = the
default, today's shell), published as `decor.<slot>`. A host loads `components/decor/<slot>/<Name>.qml` (kebab →
Pascal, `DecorHost.qml`) and never compares the name; without a slot nothing is made and the caller draws its own
default, so a look without it stays pixel-identical. Contracts: `decor/<slot>/<Slot>Base.qml`. Hosts:

| host | slot | the caller | its default |
|---|---|---|---|
| `TitleHost` | title | top of a Stage card, the launcher, polkit, the session menu (title, icon, `focused`, `canClose`, `buttons`; `close`, `button(name)`) | 0 px, nothing |
| `StartHost` | start | the bar's `launcher` module (W53.0b): `pressed`, `open`, `vertical`; label `decor.start.label` with `[decor] start.label` | the plain icon button |
| `TrayWell` | tray | under the tray group | `tray.sunken`: a sunken bevel; else nothing |
| `MenuStyle` | menu | tray/dock menus, launcher rows: `rowH(own)`, `radius(own)`, `highlight`, `separator`, `rowBackground` | the caller's rows |
| `ScrollStyle` | scroll | every ScrollBar: `width(own)`, `arrows`, `thumb`, `part` | the thin bar |
| `TooltipStyle` | tooltip | dock tooltip, peeks: `fill(own)`, `ink(own)`, `tail`, `part` | the caller's |
| `BarGround` | bar | under the bar's strip (W53.2: the strip leaves its own fill out while a part draws), `edge` | the strip's fill |
| `DockGround` | dock | the dock's floating body (W53.4, row 605: the Block steps aside while a part draws), `edge`, `mirror` (the icon list), `icon`; `tiles`, `indicator` for the caller | the dock's Block |
| `Pattern` | (metrics) | window-sized Blocks (≥ 120 × 64 with a fill), the Stage card's ground, parts that ask (a menu bar, a caption, a dock, a skin) | nothing |
| `WindowEdge` | (metrics) | a captioned Stage card under a look without the bevel chrome: `border.width` px of `border.color` (W53.2) | BevelEdge under bevel looks (row 595) |
| `FocusRing` | (metrics) | every focusable control | `ring` 1 px |
| `Entrance` | (metrics) | a surface's content, `progress` 0…1 from `edge` | `grow` = K74 (the wrapper does nothing) |

Shipped parts: `title/Caption.qml` (a caption drawn from the metrics alone: solid or gradient fill, active and inactive,
text side and weight, buttons in glyph/bevel/gel/plate/dot chrome on either side; it draws only buttons that act —
close while `canClose`, the caller's `buttons`). `BevelEdge.qml` is the bevel any part may use. W53.1 adds the bevel era's parts, named
`classic` so any bevel look can use them: `title/Classic.qml` (raised `title.button_w` × `title.button_h` keys with their
marks on whole pixels — it honours both TitleHost's names and Stage's `[{id, action}]`, `full`, `pressed(id)`),
`start/Classic.qml` (a raised start button with an original four-pane mark), `tray/Status.qml` (a 1 px status well),
`menu`, `scroll`, `tooltip`, `button`, `toggle` and `slider` `Classic.qml`, and the helpers `PixelLabel.qml` (bitmap type:
native, unsmoothed, bold as GDI's overstrike) and `Checker.qml` (the 50 % dither); lock face `LogonFace.qml`.
W53.2 adds the glossy and glass eras' parts, named by idiom: `title/Gloss.qml` (a vertical glossy band with a bright top
line and a dark foot, `title.gloss`; rounded `title.button_radius` plates with a light rim, the close plate in
`title.close_fill`; the title in `font.title` with `title.text_effect`), `title/Glass.qml` (the card's glass as the
band, a joined button group hanging from the top edge — `title.button_w` keys and a `title.close_w` gel — the title in a
glow), `start/Pill.qml` (a glossy pill the bar's thickness, square on the screen side; `start.fill`, `font.start`,
`start.size`, `start.italic`) with the skin `start/GlossMenu.qml` (header, rule, two-tone body, footer), `start/Orb.qml`
(a glass sphere) with `start/GlassMenu.qml` (a glass frame round a white pane), `bar/Gloss.qml` and `bar/Glass.qml`
(`bar.fill`, `bar.edge`, `bar.gloss`; contract `bar/BarBase.qml`, lit on the side facing the screen), `tray/Gloss.qml`
(`tray.fill`), `tooltip/Balloon.qml` (one outline with a wedge tail, `tooltip.radius`, `tooltip.border`),
`menu/Flat.qml` (a band, `menu.separator` honoured) and `menu/Capsule.qml` (7's list highlight), `button/Gloss.qml` and
`button/Glass.qml`, the helpers `CaptionGlyph.qml` (×, _, □, restore at any size, with a rim) and `PaneMark.qml` (the
original four-pane start mark from roles), and the lock faces `WelcomeFace.qml` and `LogonGlassFace.qml`.
W53.4 adds the Mac eras' parts: `title/Lights.qml` (the traffic lights — close, minimize, zoom always in the Mac's order
on `title.buttons`' side, a button the daemon does not list leaves its place empty; `title.close_fill`/`min_fill`/`max_fill`
roles brought to a lamp's brightness; gels with `title.gloss`, flat discs at 0; marks on hover of the group; the band
patterned), `bar/Menu.qml` (a menu bar: `bar.fill` at the material's alpha, the pattern, a hairline in `bar.edge` and
a shade beyond it while opaque), `start/Mark.qml` (the menu bar's first item: `MenuMark.qml`, an original setting-sun
mark — never Apple's logo — gel with `start.gloss`; held open it is a menu title: the full-height `menu.fill` band under
`menu.highlight = bar`, an inset rounded one otherwise) with the skins `start/DropMenu.qml` (a pull-down hanging square
from the bar, 5 px far corners, patterned) and `start/Popover.qml` (a vibrancy panel, double hairline rim),
`button/Gel.qml` (Aqua's capsule gel; the default button pulses `button.pulse` times, then rests), `menu/Gel.qml` (a
gel band, `menu.gloss`), `dock/Shelf.qml` (the Dock's body: translucent `dock.fill`, a glassy lip, with
`dock.reflection` a shelf line and the icons' mirror under it — one ShaderEffectSource redrawn only when the icons
change), the helper `Pattern.qml` (one tiled image from `decor/textures/`, tools/styles/patterns.py, CC0) and the lock
faces `LoginWindowFace.qml` and `SonomaFace.qml`. Push buttons host the button slot (row 604: `Button.qml`, the Block
`bare` under the part; `ButtonBase.ink` names the label's ink) and a toast balloon's tail points at the island (row 603).
`frontend/StyleSheet.qml` shows every part of the look in effect and its lock face in any state on the sandbox's own
Quickshell (`KURASHI_SHEET=parts|lock|lock-error|lock-caps|lock-busy|lock-wait|lock-prompt|lock-secondary`).

**Metrics** (`[decor]` in a look, `appearance::DECOR_KEYS`: one list with kinds, ranges and defaults, rule 3). Values
are numbers, switches, words, palette **role names** (published as colours, never hex in a look), bézier curves or font
chains; nested tables flatten (`[decor.title] height = 18` = `"title.height" = 18`); a key outside the list or a value
outside its kind is refused and reported like a foreign recipe key. Every key is published as `decor.<key>` with its
default filled in:

| group | keys (default) |
|---|---|
| caption | `title.height` (24), `title.fill` ([title, title_end]), `title.fill_inactive`, `title.on` (on_title), `title.fill_dir` (horizontal), `title.align` (start), `title.weight` (700), `title.close` (glyph · bevel · gel · plate · dot), `title.buttons` (end · start), `title.radius` (-1), `title.on_inactive` ("" = `title.on`), `title.button_w`/`title.button_h` (0 = the part's own), `title.button_gap` (-1), `title.inset` (-1), `title.close_w` (0 = `button_w`), `title.close_fill` ("" = the part's), `title.button_radius` (-1), `title.family` ([]; resolved as `font.title`), `title.size` (0), `title.text_effect` (none · shadow · glow), `title.gloss` (0) |
| window border | `border.width` (0), `border.color` (outline) |
| bevel | `bevel.width` (1), `bevel.press_offset` (1) |
| menu | `menu.row` (0 = own), `menu.highlight` (capsule · bar · inset), `menu.separator` (line · etched · space), `menu.radius` (-1), `menu.fill`/`menu.on` (the highlighted row's band and text roles; "" = the caller's selection) |
| scroll bar | `scroll.width` (0 = own), `scroll.arrows` (false), `scroll.thumb` (pill · flat · bevel · gel) |
| tooltip | `tooltip.fill`, `tooltip.on` ("" = own), `tooltip.tail` (false), `tooltip.radius` (-1), `tooltip.border` ("") |
| tray, separators, bar | `tray.sunken` (false), `separator.style` (line · etched · none), `bar.group` (block · none: no raised block round each bar group, one strip — row 596), `tray.fill` (""), `bar.fill` ([]), `bar.edge` (""), `bar.gloss` (0) |
| Mac eras (W53.4) | `title.min_fill`, `title.max_fill` ("" = warning, success), `pattern.kind` (none · stripes · brushed), `pattern.period` (4), `pattern.strength` (0), `dock.fill` ([]), `dock.radius` (-1), `dock.reflection` (0), `dock.indicator` (dots · dot · triangle), `dock.tiles` (block · none), `button.radius` (-1), `button.gloss` (0), `button.pulse` (0), `button.pulse_ms` (1500), `start.gloss` (0), `menu.gloss` (0) |
| focus | `focus.style` (ring · dotted · double · halo), `focus.offset` (0; negative = inside), `focus.width` (1) |
| start | `start.label` (false), `start.fill` ([]), `start.family` ([]; resolved as `font.start`), `start.size` (0), `start.italic` (false) |
| type | `type.pixel` (false), `type.pixel_step` (1) |
| symbols | `icons.family` ([] = the shell's), `icon.size` (0 = body + 4), `icon.scale` (1), `icon.fill`, `icon.weight` (-1 = the chrome's) |
| motion | `motion.style` (grow · slide · zoom · fade · flip · stepped · rubber), `motion.steps` (4 frames at 60 Hz per step), `motion.{open,close,fast,effects}_ms` (0 = K74's), `motion.{…}_curve` ([] = K74's; 4 numbers = one cubic) |
| materials | `material.glow` (0), `material.glow_color` (accent), `material.glow_radius` (12), `material.bloom` (0), `material.bloom_radius` (16), `material.sheen` (0) |
| pixel grid | `pixel` (0) |

**Palette roles** (derived when a palette leaves them out, as `line`/`ring`): `title`, `title_end`, `title_inactive`,
`title_inactive_end`, `on_title` (accent → 45 % lighter; outline → 30 % lighter; the best ink); `bevel_light`,
`bevel_light2`, `bevel_dark2`, `bevel_dark` (the face — the high container — mixed toward white 0.9/0.5 and black
0.33/0.9 on light grounds, 0.45/0.2 and 0.4/0.8 on dark ones); `info`, `on_info` (a pale warning tint: 98's #ffffe1);
`desk` (secondary). The WCAG stage keeps `on_title` on `title` and `on_info` on `info` at 4.5:1.

**The bevel chrome** (`theme.chrome = bevel`, K80): no outline, ring or shadow; two pairs of 1 px lines over the face's
edge — `bevel.light`/`bevel.dark` outside, `bevel.light2`/`bevel.dark2` inside, light from the top left, the dark lines
over the light ones at the top-right and bottom-left corners (98.css) — in whole device px (`Theme.crisp`). Pressed: the
pairs swap and the content moves `bevel.press_offset` px down-right (no sink, shrink or flash). `Block.sunken` draws a
well (a text field, the tray) swapped at rest. `bevel.width`/`press_offset` are 0 under every other chrome. **High
contrast keeps the bevel** (K80 amends K42): the theme draws it in the contrast ink (outer pair `on_surface`, inner
`on_surface_variant`/`outline`) — the schema's coupling still forces `flat` until the daemon can exempt one value
(CONTRACT-CHANGE).

**Motion personality.** `motion.style` is the form (`Theme.motionStyle`; `Entrance.qml` draws slide/zoom/fade/flip for a
surface that adopts it), the look's own curves and durations replace K74's timed ones, `rubber` overshoots on arrival,
and `stepped` makes `motion.kind = stepped` (a timed kind: `Theme.timed` holds) whose curves are staircases — each step
held `motion.steps` frames — so every timed surface moves in jumps. Profile `none` (reduce motion forces it) wins over
all of it: kind and style `none`, no curves.

**Type and symbols.** A look's `theme.typography.family`/`family_jp` chains (free stand-ins installed by Home-Manager,
nothing proprietary bundled). `type.pixel` publishes `font.pixel` (Text `renderType: NativeRendering`) and snaps every
`font.size.*` to whole `type.pixel_step`s. `icons.family` puts a style's own symbol font (Material ligature names) first
when installed — the shell's family becomes its `font.icons_fallback` — and `icon.size`/`icon.scale` size the icons
(`Theme.iconSize`, `Theme.iconScale`).

**Materials next to blur.** `glow.*` (a halo round blocks in a role's colour), `bloom.*` (a lighter halo of the block's
own colour) and `sheen.strength` (a gloss over the upper half: Vista/7) are static `RectangularShadow`s and a gradient,
made in `Block` only while the look has them (0 frames idle). High contrast turns them off.

### Texture and light (K59)
A material is a relief, not a picture (`docs/ux/texture.md`). The daemon generates a seamless tile per material
(`crates/kurashi-texture`), resolves the light and publishes tokens; renderers sample and shade with one function,
`kurashi_texture::shade` on the CPU (wallpaper bake, Settings swatches) and `frontend/shaders/relief.frag` on the GPU —
the two are kept identical. A third consumer (I174, row 404): `crates/kurashi-theme/src/ghostty_shader.rs` mirrors
`shade_with` without the beam and the relief shadows, on a procedural relief per kind instead of the tile, with the
light baked in as constants (ghostty's `custom-shader`, background pixels only; `docs/ux/terminal-texture.md`).

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
| `texture.depth` | K61: steepens the normals' slope (1 = as generated) |
| `texture.shadow` | K61: relief shadows, 0 (off) … 1; `texture.height_map` the opaque grey height PNG while > 0 (`""` otherwise) |
| `texture.relief_px` | K61: the logical px the height map's 0…255 range stands on the sheet (`tile.relief × depth × scale`) |
| `texture.lit` | K61 (I169): the weight of the light half — 1, or 0.6 on a dark ground (highlights read stronger there) |
| `texture.controls` | K61: the relief also lies over controls (buttons, sliders, switches, chips, icons); never over pictures |
| `texture.sheet` | K61: `carried` (a moving surface takes its sheet along and lands on the continuous one) \| `fixed` \| `separate` |
| `light.pin`, `light.beam` | K61: the spotlight's lamp `[x, y]` (fractions of the output; `null` in other modes) at `light.height_px`, and its beam's half-angle in degrees |
| `pen.line`, `pen.{pressure,breaks,fade,wobble}`, `pen.text_{…}` | K62: the outline style and the pen modifiers (0…1) for outlines and for text and icons |

**Two consumers (row 342):** Settings links the shell's `Relief.qml`, `TileSheet.qml`, `LightSense.qml`, `core/Light.qml`
and `shaders/` (git symlinks under `settings/`), and its own `core/Theme.qml` mirrors the frontend Theme's `tex*`, `light*`
and `longMs` names: renaming one renames both.

**Height map (K61):** `<tile>-height.png`, opaque grey (R = G = B), 0 and 255 the tile's 0.5th and 99.5th height percentile (clamped beyond), sampled
with the same wrapped bilinear taps as the tile; the range in logical px beside it (`<tile>-height.relief`, the daemon's
`texture.relief_px` before depth and scale).

**Shading** (per pixel; `p` is the sheet position in logical px, in output coordinates — the sheet is continuous across
windows; `kurashi_texture::shade_at` is the reference, `relief.frag` mirrors it):
```
uv   = p / (tile_logical × scale)                       wrap; t = tile(uv), bilinear, 0..1
xy   = (2 t.r − 1, 2 t.g − 1)
n    = normalize(depth · xy, sqrt(max(0, 1 − |xy|²)))                        K61 depth
cav  = 2 t.b − 1
L    = light.dir                                        static, daytime, and pointer away from the shell
     | normalize(pointer − p, light.height_px)          pointer over a shell surface
     | normalize(lamp × output − p, light.height_px)    wallpaper (a lamp at its brightest region)
     | normalize(pin × output − p, light.height_px)     spotlight (K61; the pin at the edge in the light's direction)
k    = 1, or for the spotlight: the beam from lamp3 = (pin × output, height_px) toward (aim, 0) — aim the pointer, the
       output's middle at rest — c = dot(normalize((p, 0) − lamp3), normalize((aim, 0) − lamp3));
       k = 0.3 + 0.7 · smoothstep(cos beam, cos(beam / 2), c)
sh   = 0, or with texture.shadow > 0 and |L.xy| > 0.001: d = L.xy / |L.xy|, rise = L.z / |L.xy|,
       len = min(relief_px / max(rise, 0.05), 24); h(q) = height(q) × relief_px;
       occ = max over i = 1…8 of h(p + d·len·i/8) − h(p) − len·i/8 · rise  (and 0);
       sh = shadow · clamp(occ / max(0.25 relief_px, 0.15), 0, 1)
diff = dot(n, L) − L.z                                  0 on a flat sheet: the material never shifts the overall tone
H    = normalize(L + (0, 0, 1))
spec = gloss × (max(dot(n, H), 0)^shininess − H.z^shininess)
v    = k × amp × (2 diff + 0.5 cav + spec − 2 sh);  v = v > 0 ? v × lit : v
s    = clamp(v, −amp, amp)
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
Shadow vector (K67, row 420): `shadow.dx`, `shadow.dy` (px for a block of the look's shadow length: direction ×
`chrome.shadow` or `soft_dy` × strength; following the light, away from `light.dir`, × tan 40°/tan elevation clamped
0.5–2) and `shadow.alpha_scale` (soft shadow opacity scale, capped at 0.9 opacity). Renderers read the vector for the
hard shadow, the soft shadow's offset and the press sink; `chrome.shadow`/`soft_dy` stay the room a block keeps.
Quick tile on state (K66/row 104): `quick.tile.on.bg` (the tonal container), `quick.tile.on.badge` (the glyph's
badge), `quick.tile.on.fg` (the label ink on the container, AA at every contrast level; row 415), resolved by
kurashi-theme as `color.selected` / accent / `color.on_selected`;
absent tokens fall back to the frontend's tonal look (accent at 22 % / 30 % alpha, accent glyph).

## 8. The Island (島)
One container, many **faces**; shows one at a time. Morph = width/height tween + content
crossfade (`motion.emphasized`), first-frame gated. Hover → peek (slight expand + secondary
line). Left click → expanded view (island grows into a panel on the stage surface). Right click →
face picker / pin. Scroll → cycle faces. Arbitration lives in the daemon (ARCHITECTURE §5).

## 9. Motion rules
- Motion explains state change; no idle loops in core. Decorative motion only in mods, gated.
- Every animation has an owner and a visibility gate; hidden = stopped.
- Interruptible: reversing mid-animation continues from the current value.
