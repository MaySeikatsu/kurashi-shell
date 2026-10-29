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
| Flat or line chrome | No shadow; the three rows are inert and Settings names the chrome that blocks (row 423, row 467) |
| Settings' own controls (Button, SectionCard) | The hard shadow only: under soft chrome they cast none (a decision since W39, not a gap) |
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
- [x] Surfaces outside W38 that draw their own straight-down shadow follow the vector (CONTRACT row 422; W39-shadows2, W42-shadows3 + lead row 465).
- [ ] A left sidebar's sideways shadow (CONTRACT row 421).
- [ ] Inert reason under flat/line chrome (CONTRACT row 423).

# Elevation (W57, I310)

Status: decided (session 18, K78 — "Decided" at the end); code next (W57)

## Job
What the user asked for (session 17): "a shadowing system with a drop shadow that can also apply to the bar, the frame, the
sidebars and every other overlaying component where a shadow makes sense, to elevate them and show depth — static … or
dynamic (reacting to the lighting system)", and "like smooth shadows". K67 above shadows the *blocks* (keycap's hard
shadow, soft's blurred one); this section shadows the *surfaces* — frame band, bars, sidebars, dock, cards, popups, toasts,
the launcher — onto the desktop and the windows under them. Under keycap the block's hard shadow stays its own; elevation
adds the smooth one under the surface the blocks sit on.

## How others do it
- **Material 3**: elevation levels 0–5 = 0, 1, 3, 6, 8, 12 dp (to verify); a shadow is a key light (offset, sharper) plus
  an ambient light (all round, wide, faint) — M2's CSS has three layers, umbra/penumbra/ambient; M3 also shows elevation
  by surface tone, mostly in dark. Hover raises a level, press lowers it. Lesson: one ladder of heights, two lights per
  shadow. <https://m3.material.io/styles/elevation/applying-elevation>,
  <https://m2.material.io/design/environment/light-shadows.html>
- **macOS**: the WindowServer draws window, menu and popover shadows from the window's *alpha shape*
  (`NSWindow.invalidateShadow()` recomputes it after the shape changes); the key window's shadow is deeper than the
  others'. Not adjustable. Lesson: the shadow follows the shape, and depth says what is in front.
  <https://developer.apple.com/documentation/appkit/nswindow/invalidateshadow()>
- **Windows 11 / Fluent 2**: depth = shadow + stroke; the shadow tokens `shadow2 … shadow64` are each a key + ambient
  pair, darker in the dark theme (about 2× the opacity — to verify). Layering puts controls, cards, tooltips, flyouts and
  dialogs at increasing Z (values to verify). Contrast themes drop the shadow for a stroke (to verify).
  <https://fluent2.microsoft.design/elevation>,
  <https://learn.microsoft.com/en-us/windows/apps/design/signature-experiences/layering>
- **GNOME**: Mutter draws server-side shadows per window *class* (normal, dialog, menu, popup-menu, …; focused and
  unfocused radius, offset, opacity) (`src/compositor/meta-shadow-factory.c`); libadwaita's CSD windows draw their own in
  a buffer margin that `xdg_surface.set_window_geometry` excludes. The top bar casts none.
  <https://gitlab.gnome.org/GNOME/mutter/-/blob/main/src/compositor/meta-shadow-factory.c>
- **KDE**: Breeze's size (none … very large), strength and colour (above); Plasma panels and menus hand KWin nine-patch
  shadow tiles over the `org_kde_kwin_shadow` protocol and KWin draws them outside the surface.
  <https://wayland.app/protocols/kde-shadow>
- **COSMIC**: shadows from the theme, not from a light (who draws them — cosmic-comp or libcosmic — to verify).
- **niri** (checked: wiki, 25.02+): `layout { shadow { … } }` for windows and `layer-rule { match namespace=…; shadow {
  on; softness; spread; offset; color } }` for layer surfaces, **opt-in** per rule. One set of options per rule — no
  second layer to configure; CSS box-shadow semantics (softness = blur radius; the layer-rule example `softness 40
  spread 5 offset x=0 y=5 color "#00000064"`). It follows `geometry-corner-radius` with **one radius for all corners**
  (Layout page), and is drawn "behind the entire surface, including the invisible margins" — the wiki tells clients to
  drop their own. <https://github.com/YaLTeR/niri/blob/main/docs/wiki/Configuration:-Layer-Rules.md>,
  <https://github.com/YaLTeR/niri/blob/main/docs/wiki/Configuration:-Layout.md>
- **Hyprland**: `decoration { shadow { enabled; range; render_power (1–4, falloff); sharp; color; color_inactive; offset;
  scale } }` for windows; layer-surface shadows to verify. **SwayFX**: `shadows`, `shadow_blur_radius`, and `layer_effects
  <namespace> shadows enable` (to verify). Plain sway: none.
- **Quickshell shells**: Caelestia's `Elevation` (an M3 `level` on a `RectangularShadow`), end-4's
  `StyledRectangularShadow`, DankMaterialShell's and Noctalia's fixed drop shadows (each to verify) — all fixed and
  straight down, none follow a light. Qt 6.9's `RectangularShadow` is analytic (no blur passes):
  <https://doc.qt.io/qt-6/qml-qtquick-effects-rectangularshadow.html>.
- **"Smooth shadows"**: layered shadows (Tobias Ahlin <https://tobiasahlin.com/blog/layered-smooth-box-shadows/>,
  Philipp Brumm's generator <https://shadows.brumm.af/>), hue-matched rather than grey shadows (Josh Comeau
  <https://www.joshwcomeau.com/css/designing-shadows/>); the analytic rounded-rect shadow: Evan Wallace
  <https://madebyevan.com/shaders/fast-rounded-rectangle-shadows/>.

Kurashi's take: M3's two lights per shadow and a short ladder of levels; macOS's shape-true shadow; Fluent's darker dark
theme; K67's one light for everything — and nothing moves at rest.

## Model
Names are *proposed*; the tokens are a contract change (rule 6: a `docs/CONTRACT-CHANGE.md` row, the lead decides).
- **Level per surface role**, from the decor pack (rule 4: identity in packs, no renderer branch on a surface's name):

  | Level | Roles | Ambient blur / alpha | Key distance / blur / alpha |
  |---|---|---|---|
  | 0 | desktop cards, the wallpaper | — | — |
  | 1 | frame band, docked bars | 12 px / 0.08 | 2 px / 4 px / 0.14 |
  | 2 | dock, sidebars, floating bars, the island | 20 px / 0.10 | 4 px / 8 px / 0.16 |
  | 3 | cards and popups (Stage, quick settings, notification centre, menus, tooltips) | 28 px / 0.12 | 8 px / 14 px / 0.18 |
  | 4 | toasts, the launcher, OSD, polkit | 40 px / 0.14 | 12 px / 20 px / 0.20 |

  Starting values (ours, not cited), tuned against niri shots. The ambient layer sits under the surface with no offset;
  the key layer is offset along the shadow vector. Spread 0; corners those of the surface.
- **Strength** (0–2) scales distance, blur and alpha together (K67's cap: alpha never past 0.9). See question 6.
- **Mode** `theme.elevation.mode = off | static | follow` (default: question 5). *static*: the vector is K67's
  `shadow_angle` (one light for blocks and surfaces), distance/softness/opacity as the table × strength. *follow*: from
  `theme.light` — a directional light (`static`, `daytime`) gives one vector per output; a lamp (`wallpaper`, `pointer`,
  `spotlight`) gives each surface the direction away from the lamp at that surface's centre (a point light, the relief
  shader's own formula — CPU = GPU, as `shade_at`); a low light lengthens the key (× tan 40° / tan elevation, 0.5…2, as
  K67), the ambient never moves.
- **Chrome-independent**: flat and line have elevation too (K67's row-423 inertness concerns block shadows only).
- **Colour**: `color.shadow` from the palette — near-black tinted toward the surface's hue, never neutral grey on washi;
  the dark scheme raises both alphas (× 1.6, starting value) and widens the ambient.

## Where shadows fall
- **Joined = one sheet.** Band, docked bar, a sidebar or dock joined by fillets, and a card grown out of the bar (K75:
  "popups are the sheet they grow out of") are one silhouette at the *base's* level (the band's, 1): one continuous
  shadow, none between the joined parts.
- **Floating = its own level.** A floating bar, dock or sidebar (a `gap` from the band) and a detached card cast at their
  level onto the band and the desktop.
- **The band onto the hole** is one inset shadow of the hole's rounded rect (`R − thickness`, concentric, K74), offset
  along the vector — one analytic function in **screen coordinates** (as the texture's tiles), so the four strips meet
  without a seam and their corners do not darken four times.
- **Pixel ownership.** Top-layer windows overlap; a shadow pixel is painted by exactly one window — the field of the
  output's union silhouette (the max of the parts' shadows, never their sum) inside the window's own region, minus
  regions owned by another joined window. No seam, no double darkness at a join.
- Outward sides (toward the screen edge) need no shadow: it would fall off-screen.
- **Onto windows**: the band and the bars stand on the Top layer, so their shadow covers the windows' edges in the hole.
  Physical, but it darkens app content: question 4.

## Who draws it
Idle cost is 0 frames either way (a static shadow is drawn once with its window). The difference is fidelity and reach:
- **niri layer-rule** (kurashid writing an include, as `kurashi-binds.kdl`): no client cost, no window growth, animates
  with niri's layer animations. But one layer (not the two-light look); one rectangle with one radius per *surface*, so
  it shadows the frame strips' whole `band + radius` rectangles, fillets and all, and can neither cast into the hole nor
  follow a fillet or a squircle; static (a rewrite and reload per change: fine for the sun, never for a lamp); niri-only.
  It fits only a surface whose window *is* one rounded rect (per namespace, to verify: `kurashi-stage` holds several
  cards in one window, so it does not). The card's "(b) for static on niri" does not survive the frame's geometry.
- **Client-drawn** (recommended, question 1): one shadow component in the existing windows. Each window grows by the
  shadow's reach **on inward-facing sides only**, and the margin stays outside three things: the **input mask** (clicks
  pass through), the **`blurRegion`** (K75: the backdrop blur keeps the shape's corners, never a square into the shadow)
  and the **exclusive zone** (set explicitly, unchanged). Layer-shell has no window geometry (unlike libadwaita's
  `set_window_geometry`), so a client margin and a niri rule on one surface would shadow the margin: one route per
  surface, never both. The same look on niri, sway, Hyprland, Mango.
- **Risk**: a user's own niri `layer-rule { shadow { on } }` matching `kurashi-*` doubles the shadow; the daemon cannot
  see niri's rules (`niri msg` exposes none). Settings' help says so (Shōjiki).
- No new surface: no full-screen shadow window (frame.md rejected the full-screen `MultiEffect`); BENCH's ≤ 4 mapped
  surfaces per output holds.

## Smoothness and corners
- Two layers (ambient + key), each an **analytic** Gaussian of the rounded rect (Wallace's erf form; `RectangularShadow`
  is the same idea): constant cost per pixel whatever the blur, no blur passes, no offscreen layer.
- **Squircle** (W56, `theme.shape.corners = squircle`): no closed form; the shadow smooths the superellipse's SDF with the
  layer's sigma (the same ratio as `relief.frag`'s box). At these blurs the error against a true convolution is
  sub-pixel (check by shot).
- **Dither**: ±½ LSB triangular noise in the shader before 8-bit output — a 0.10 alpha over a `#121212` ground spans only
  a few levels across 40 px and bands otherwise. So a custom shader (qsb, devShell), not stock `RectangularShadow`.
- **Hard shadows** stay K67's: keycap's block shadow is not smoothed.

## States
| State | What is drawn |
|---|---|
| Off | Nothing; windows lose their margin; K67's block shadows unchanged |
| Static | The table × strength along `shadow_angle`; 0 frames |
| Follow, directional light at rest / moving (the sun) | One vector; one repaint per change, a cut (K67) |
| Follow, lamp at rest | Per-surface direction away from the lamp; 0 frames |
| Follow, pointer lamp moving | Question 3 (rest direction, or live and eased) |
| Follow without a material | Question 2 (follows a shell-wide light, or inert with K67's reason) |
| Reduce motion | Follow casts from the light's rest; every change a cut |
| High contrast (`forced_by: accessibility`) | Off; the outline carries the edge (line chrome's rule, else a 1 px outline token) |
| Reduce transparency | Unchanged (a shadow is not a translucent surface) |
| Dark / light scheme | Alphas × 1.6 / × 1 (starting values); colour from `color.shadow` |
| Dark wallpaper under a light scheme | Scheme-based in v1 (the ground under a band is windows too); wallpaper luminance later |
| Fullscreen window | The frame steps aside, its shadow with it; popups over fullscreen keep theirs |
| Hover bar / dock sliding in | The shadow is in the window: it travels and fades with the surface |
| Joined ↔ floating (a sidebar pinned, unpinned) | The silhouette changes; one repaint, no seam during the move (pixel read) |
| Keycap / soft / flat / line | Keycap's and soft's block shadows stay; elevation under the surface in all four |
| Non-niri compositor | Identical (client-drawn) |
| Daemon away | Theme.qml fallback: off (never a shadow that is not in effect, rule 2) |

## Settings
Appearance → **Depth** (a new section; K67's Material rows move here, the light stays under Material or moves per
question 2): **Elevation** (segmented: Off · Static · Follow the light), **Strength** (0–2), **Direction** (K67's slider),
and under *More*: **Distance**, **Softness**, **Opacity** (multipliers on the table). All schema rows (rule 3): search,
reset, undo, the provenance chip (default / you / Nix / accessibility).
- **Preview**: a miniature of the output — its wallpaper thumbnail, band, a bar, a sidebar, the dock and a card at their
  levels — drawn by the same component with the daemon's tokens (what you see is what is on); in Follow a small lamp
  marks the light; dragging in the preview sets Direction (the slider is its keyboard twin). The shell itself changes
  live behind Settings.
- **Inert reasons** (rule 2): Direction under Follow ("Follows the light — set it under Light"); every row under Off
  ("Elevation is off"); every row under high contrast ("Forced off by High contrast"); Follow per question 2 without a
  material; a Nix-set value shows its source and is read-only. Help names the niri double-shadow risk.

## Keyboard and a11y
Segmented control: arrows, Home/End; sliders: arrows, PageUp/Down, Home/End; labels and help from the schema (i18n keys
in `i18n/{en,ja}/`). The preview is `Accessible.ignored` (the values are in the rows). Shadows never carry meaning: focus,
selection and state stay readable with elevation off.

## Motion
Shadows appear, slide and fade with their surface (they are in its window). A change of setting, vector or silhouette is a
cut (K67). The only exception is question 3's eased pointer follow, gated by visibility and reduce motion.

## Multi-output
Each output its own silhouette and light: static and the sun one vector everywhere; the wallpaper lamp per output's
wallpaper; the pointer lamp only on the output under the pointer, the others at rest. Shadows clip at the output's edge.

## Budget (Ma, docs/BENCH.md)
- Idle frames: 0 in every mode at rest (BENCH: ≤ 1 fps total, only the clock's minute flip); a light or setting change:
  one repaint per affected window, then 0.
- Memory: the margins grow buffers by ≈ edge length × reach × 4 B × buffer count per inward side (to measure, PSS or GPU
  memory); must fit BENCH's ≤ +6 MiB per extra output, the material's allowance unchanged.
- Mapped surfaces unchanged (≤ 4 per output). The shader is analytic; no per-frame daemon work.
- Pointer follow (if chosen): frames only on windows the pointer light already repaints (W58), budgeted in BENCH.

## Definition of done
- [ ] Tokens and schema rows through a CONTRACT-CHANGE row; fixtures and `docs/PROTOCOL.md` by the lead.
- [ ] Shots **on niri** (patterned wallpaper): Off / Static / Follow × flat, keycap, soft, line × band + bar + sidebar +
  dock + a card, light and dark scheme; Follow with the light at 315° and 45°, high and low.
- [ ] Joins: pixel read (grim + `magick … txt:`) across every strip corner and fillet join — no seam, no double darkness.
- [ ] Margins outside input, blur region and exclusive zone: a click 2 px into a shadow reaches the window under it; the
  blur's corners unchanged (K75 shots); window placement unchanged.
- [ ] Banding: the shadow's luminance profile on `#121212` and `#f3eee3` grounds has no plateau wider than 4 px.
- [ ] Squircle corners: the shadow follows the curve (shot at 4× zoom).
- [ ] Idle 0 frames in every mode at rest; one repaint after a light change; PSS per output within budget (BENCH entry).
- [ ] Settings: the rows, the preview, every inert reason and provenance; high contrast forces off.
- [ ] The sway suites stay green (regression); `docs/ux/README.md` lists the brief.

## Later (BACKLOG candidates for the lead)
- Hover/press lift: a card or dock item rises a level on hover, sinks on press (M3).
- Wallpaper-luminance adaptation: darker shadows over a dark wallpaper (the daemon already measures it).
- Tonal elevation in dark: a level also picks a lighter surface tone (the decor pack's choice).
- niri layer-rule shadows for plain single-rect surfaces, if the margins break the PSS budget.

## Design questions for the user
1. **Who draws the shadows?** (a) The shell, in its own windows, everywhere — two layers, true shapes, joins, follow,
   every compositor; costs buffer memory for the margins. (b) Hybrid: niri's layer rules for plain single-rect surfaces
   in static mode, the shell for the rest — two looks side by side. (c) niri only, static — one layer, rectangles, no
   frame or fillet shadows. **Recommend (a)**; (b) only if the margins measure over budget.
2. **Is the light shell-wide?** (a) Yes: `theme.light` stops depending on the material; relief, block shadows and
   elevation all read it, so Follow works under flat and line. (b) No: Follow stays inert without a material (K67's
   reason). **Recommend (a)** — "one light for everything", and elevation is chrome-independent.
3. **Do elevation shadows move with the pointer lamp and the spotlight?** (a) No: they cast from the lamp's rest (K67
   today; 0 frames). (b) Yes, eased (a slow spring, never jitter), only while the pointer light already repaints (W58),
   off under reduce motion — amends K67 (a DECISIONS entry). **Recommend (b)** once W58 lands, (a) until then.
4. **Do the band and the bars cast onto app windows?** (a) Yes, as physics says (darkens a few pixels of window content
   at the hole's edge). (b) Only floating surfaces (level ≥ 2) cast; the band and docked bars stay flat. (c) Yes, with a
   short reach (key only, no ambient). **Recommend (c)**: depth without fogging the windows' edges.
5. **Which looks ship with elevation on?** (a) All looks, Static. (b) Soft and keycap looks Static, flat and line Off
   (one click to switch on). (c) Off everywhere until switched on. **Recommend (b)**: flat and line read as deliberately
   shadowless.
6. **How fine are the controls?** (a) One Strength shared with K67's block shadows, plus mode and direction; levels only
   from the decor pack. (b) Separate Strengths for blocks and for elevation. (c) (b) plus per-role level overrides under
   Advanced. **Recommend (b)**: a keycap look may want hard keys and a faint lift; per-role knobs are decor-pack work.

## Decided (user, session 18 — K78)
1. **The shell draws every elevation shadow** (a): two layers, true shapes and joins, every compositor; niri's layer
   rules are not used for them.
2. **The light is shell-wide** (a): `theme.light` no longer depends on the material; relief, block shadows and elevation
   read it, so Follow works under flat and line.
3. **Shadows may follow the pointer lamp and the spotlight — as a toggle** (user: "yes, but expose it as an option"):
   eased, only while the pointer light already repaints (W58), off under reduced motion; off = they cast from the
   lamp's rest (K67's rule, which K78 amends for this option only).
4. **The band and docked bars cast onto windows with a short reach** (c): the key layer only, no ambient.
5. **Defaults:** soft and keycap looks ship with elevation Static; flat and line looks Off (one switch away).
6. **Controls:** separate strengths for block shadows (K67) and elevation, plus mode and direction; levels per surface
   role from the decor pack.
