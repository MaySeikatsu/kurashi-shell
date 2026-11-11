# UX brief — the motion engine: timing × form × choreography, per surface, as profiles (W59, session 19)
> Extends `docs/ux/motion.md` (W34/W36 "the bar reaches out", K42 springs, K74 expressive curves) and `styles.md`'s
> "Motion kinds" (K80/W53.0a: `motion.style`, `stepped`, `rubber`, `bleed`). Everything there stays and becomes presets
> of this engine; nothing the user sees today changes unless they (or a new style default they accept) pick it.

User (session 19): "I like the current animation styles and want to keep them, but I want to extend on the animation
system … a modern, expandable, well thought out motion engine … logically splitting the animation into separate parts,
so the user can set and control the animation curves, switch between different motion curves and separately choose
between different animation styles. Then we could have unique animation profiles per style set … Expose the options in
a dedicated motion menu, and allow users to set up their own custom bezier curves and animation styles." Forms they
named: origami fold (Kami's default), crumpling paper, rolling carpet, fluid morph from the clicked shape, simple
expand, raindrop, notebook, CRT zap, magic-lamp genie; curves: modern fluid bouncy, pudding, harsh accel/decel that
smooths out before stopping. "High quality and polished, no prototype."

## 1. Today (what this generalises)
- **User controls:** `theme.motion.profile` (expressive · calm · lively · none) and `theme.motion.speed`. That is all.
- **Daemon** (`kurashi-theme/src/tokens.rs` §motion): the profile picks `motion.kind` (timed · spring · stepped · none),
  K74's four timed roles `motion.timed.{open,close,fast,effects}_{ms,curve}` (Caelestia's M3 expressive values), K42's
  spring family `motion.spring.{on,overshoot,spring,damping,squash}`. A **look** may override form and curves through
  `[decor] motion.style|steps|*_ms|*_curve` (fluent, aqua, material, snes, ps2, kawaii do) — not user-settable, not
  shown in Settings, no provenance.
- **Frontend:** `core/Glide.qml` (one value on curve or spring: bar, dock, edge modules), `island/MorphSprings.qml` (the
  three-axis morph of every shape that grows out of the bar: Stage panels and peeks, launcher, centre, toasts; the
  sidebar's own two springs), `decor/Entrance.qml` (the look's form drawn on a card's *content*: slide, zoom, fade, flip,
  bleed, stepped). The island keeps its own springs (K42 identity).
- So there are really **two timing families and seven forms**, chosen by profile and look; the axes the user asks to
  separate are fused.

## 2. How others do it
- **Hyprland** — the closest to the ask: named curves (`bezier = myCurve, 0.05, 0.9, 0.1, 1.05`) and per-event lines
  (`animation = windowsIn, 1, 7, myCurve, popin 80%`): *event × on/off × speed × curve × style(+param)*. Styles per event
  family (windows: slide, popin, gnomed; workspaces: slide, slidevert, fade, slidefade). Power users love it; there is no
  GUI and no preview. We take the split and the param syntax, and add the GUI, preview and provenance.
- **Compiz Animation plugin** (+ Add-On, Jokes) — the classic catalogue: per event (open, close, minimize, focus, shade)
  an effect (Magic Lamp, Fold, Horizontal Folds, Curved Fold, Roll Up, Burn, Beam Up, Dream, Domino, Explode, Airplane
  (a folded paper plane!), Glide, Razr, Skewer, Wave, Zoom) with a duration and a window-type match. Proof that fold,
  roll, genie and burn read well on UI; also proof that too many knobs per effect overwhelm — we keep params few.
- **KDE Plasma / KWin** — effects as plugins: Magic Lamp, Wobbly Windows (the "pudding"), Fall Apart, Squash, Glide,
  Sheet, Scale, Fade; one global "Animation speed" slider; effects are scriptable (JS + GLSL) → user-made effects exist.
- **niri** — per animation `spring { damping-ratio stiffness epsilon }` or `easing { duration-ms curve }`
  (incl. `cubic-bezier`), and **custom GLSL shaders** for window-open/close/resize (`niri_progress`, geometry uniforms).
  We already export an `animations` block (export.rs); the engine maps onto it exactly (§9).
- **macOS / iOS / SwiftUI** — springs everywhere, interruptible and velocity-preserving; the 2023 spring API is
  `duration + bounce` (bounce 0 = critically damped) instead of stiffness/damping/mass — understandable by humans. macOS
  Genie and Scale for minimise, menu-bar extras scale+fade from their item, Reduce Motion **replaces movement with
  dissolves** rather than cutting.
- **Material 3 Expressive (2025)** — a *motion physics system*: springs split into **spatial** (position, size; may
  overshoot) and **effects** (colour, opacity; never overshoot), each fast/default/slow; container transform, shared
  axis, fade through; M3 still ships cubic tokens for the non-spring world. Our open/close/fast vs effects roles are this
  split already.
- **GNOME / libadwaita** — `AdwSpringAnimation` (damping ratio, mass, stiffness) + `AdwTimedAnimation` (easing), one
  global "animations on/off"; minimal choice, high polish. **Windows 11** — fixed composition curves, connected
  animations, no user choice. **COSMIC** — minimal, one toggle.
- **Quickshell shells** — Caelestia: M3 expressive tokens, one blob shape for border + drawers (our K74 reference);
  end-4: M3 curves, sliding sidebars; DankMaterialShell / Noctalia: an animation-speed setting, a few curve presets;
  **HyprPanel** (AGS): a `transition` per menu (crossfade · slide_down …) — per-surface form choice in a GUI.
- **Web tooling** — cubic-bezier.com and easings.net: the editor (two handles on a graph, a ball racing a reference) and
  the vocabulary (easeOutBack, easeInOutExpo …) users already know. Our editor accepts their notation.
- **Not doing:** asset animations (Lottie, Rive) — they'd be a parallel motion language beside the tokens (rule 4) and
  can't follow the shape, material or join.

## 3. The model — five independent axes, bundled as profiles
```
                   ┌ timing  (how time maps to progress)     curve per role: open · close · fast · effects
 motion profile ───┼ form    (what progress does to a sheet)  per surface class, open and close separately
 (a motion pack)   ├ choreography (who moves when)            content timing, stagger, origin, retarget
                   ├ accents (secondary motion)               squash & stretch, jelly, overshoot cap, shadow
                   └ speed   (one multiplier)                 theme.motion.speed, as today
```
- **Timing** is a **curve**: cubic (one or more segments) · spring (duration + bounce) · steps(n) · linear. The *kind*
  (timed/spring/stepped) is derived from the curve, never chosen separately — so a control can't sit inert.
- **Form** is the transformation of the whole surface as a function of progress `p ∈ [0,1]` (past 1 while a curve
  overshoots): grow, slide, fold, roll, genie … (§5). Open and close may differ (unfold, crumple away).
- **Choreography**: content fades in late / with / cascades (stagger by row, derived from the host's progress — no extra
  timers), the origin (the pressed module's rect, the bar edge, the screen edge, the click point), and how a retarget
  (quick → session while open) moves.
- **Accents**: squash & stretch (today's lively `squash`), **jelly** (an area-preserving wobble after landing — pudding),
  the overshoot cap, what the elevation shadow does during the form (carry · fade).
- **Profile** = one named bundle of all of it = a **motion pack** (`motion/<id>.toml`, like `looks/` and `styles/`). A
  style recommends one (`theme.motion.profile` at the style's provenance layer, K53), the user can pick another and
  override any single axis on top. Today's four profiles and the six looks' `[decor] motion.*` become packs (pixel-
  identical: §11).

**Precedence** (Shōjiki, rule 2 — every control shows which layer it comes from):
`built-in default < style's recommended profile < user's profile pick < user's per-axis override < a11y force`.
Settings: "Opens with: Fold — from profile Origami (style Kami)"; changed by the user: "yours · Reset to Origami's".

## 4. Timing — curve presets and the custom curve
Canonical text form (one `Curve` leaf, parsed and validated by the daemon, accepted by the editor's paste field):
`cubic-bezier(x1, y1, x2, y2)` · `segments(x1 y1 x2 y2 ex ey, …)` (QML `bezierCurve` order) · `spring(<ms>, <bounce>)` ·
`steps(<n>)` · `linear` · or a preset id. x of every control point ∈ [0, 1] (monotonic time); y ∈ [−1, 2].
Springs: mass 1, `stiffness = (2π / response)²`, `damping = 4π (1 − bounce) / response` (bounce ≥ 0; < 0 overdamped,
`damping = 4π / (response (1 + bounce))`), bounce ∈ [−0.5, 0.9] — SwiftUI's model, mapped 1:1 onto niri's
`damping-ratio = 1 − bounce` and `stiffness`. The response is the role's duration.

| preset | kind | values | feel / used by |
|---|---|---|---|
| `expressive` | cubic | `[0.38, 1.21, 0.22, 1]` 500 ms | K74 default spatial (Caelestia) — **today's default** |
| `emphasized` | segments | K74's close curve, 400 ms | M3 emphasized — today's close |
| `effects` | cubic | `[0.34, 0.8, 0.34, 1]` 200 ms | content fades — never overshoots |
| `standard` | cubic | `[0.2, 0, 0, 1]` | M3 standard |
| `decelerate` / `accelerate` | cubic | `[0, 0, 0, 1]` / `[0.3, 0, 1, 1]` | fluent's / exits |
| `ease` | cubic | `[0.25, 0.1, 0.25, 1]` | CSS ease — aqua |
| `snap` | segments | in-out quint to 0.9 by t 0.42, then a long soft ease-out to 1 | the user's "harsh acceleration and deceleration, smoothing out before stopping" |
| `anticipate` | cubic | `[0.68, −0.55, 0.27, 1.55]` | pulls back, then overshoots (easeInOutBack) |
| `drop` | segments | gravity in, two small bounces (6 %, 1.5 %) | the raindrop's fall, stamping |
| `paper` | cubic | `[0.3, 0.7, 0.1, 1]` | soft landing without overshoot — origami, scroll |
| `calm` · `lively` | spring_q | K42's `(4.0, 0.45)` · `(3.2, 0.26)` in SpringAnimation units | **today's** calm/lively, kept bit-exact (internal kind, not user-editable) |
| `gentle` | spring | `spring(450, 0)` | critically damped |
| `fluid` | spring | `spring(500, 0.25)` | the user's "modern fluid bouncy" |
| `bouncy` | spring | `spring(550, 0.45)` | playful |
| `pudding` | spring | `spring(650, 0.65)` + profile's jelly | wobbles home |
| `steps(n)` | steps | n held frames | snes, pixel looks (today's `stepped_curve`) |

**Custom curves.** Any role takes a custom curve. The editor (§8) writes the canonical string into the user's config
(`theme.motion.timing.open = "cubic-bezier(…)"`); "Save as preset…" stores it by name in a **user motion pack**
(`$XDG_CONFIG_HOME/kurashi/motion/<name>.toml`, `[curves]`), which then lists with the built-ins. No schema maps needed.

## 5. Forms — the catalogue
Two families, because they draw differently (D2, user: the hinge stays joined):
- **Shape forms** — the silhouette stays the live vector shape (MorphShape/IslandGeom): joined to the bar with its neck,
  the elevation shadow, the carried material (K61) and the compositor blur region all follow every frame, as today.
  They retarget (a shape morphs into the next panel's).
- **Sheet forms** — the whole card (fill, material, border, content) is captured into **one layer only while it moves**
  (`ShaderEffectSource`, released at rest — as `bleed`'s blur layer is today) and drawn through a `ShaderEffect`
  (vertex warp on a `GridMesh` and/or a fragment pass). The edge that touches the bar is the **hinge** and stays on it
  (the join's fillets fade in over the last 15 % of p); the elevation shadow fades out at the start and in at rest, the
  warp draws its own shading from the mesh normal (a fold's crease is darker than any static shadow could be); a
  translucent material draws at its solid fallback while warped and the blur region returns at rest (blurring a moving
  3-D fold through the compositor is neither possible nor honest). Retarget: finish the form at `fast`, then shape-morph.

| form | family | technique | open → close | params (few, in packs) | default for |
|---|---|---|---|---|---|
| `grow` | shape | MorphSprings (K42/K74) | grows out of its origin, folds back | — | expressive · calm · lively (**today**) |
| `slide` · `zoom` · `fade` · `flip` · `bleed` · `stepped` | as today (Entrance) | transforms; bleed = layer blur | | | fluent/aqua · — · ps2 · — · washi · snes (**today**) |
| `rubber` | — | alias: `slide` + `anticipate`/rubber curve (kept for kawaii's pack) | | | kawaii (**today**) |
| `expand` | shape | clip-rect reveal from the origin edge, content still | the user's "simple panel expand" | — | — |
| `liquid` | shape | the pressed module's own rect and radius morph into the card; smooth-min neck that stretches and necks off; width leads, height lags | the user's "fluidly growing out and morphing from the clicked shape" | neck (0–1) | glass |
| `iris` | shape | circular clip from the click point (M3 circular reveal) | | — | — |
| `drop` | shape + frag | a drop (r ≈ 6 px) leaves the origin, falls on `drop` to the card's centre, lands as a ripple whose wavefront refracts what's beneath and reveals the card; close: contracts to a drop that rises home (or evaporates on a toast) | the user's "raindrop" | ring width, refraction | toasts in sumi (ink drop) |
| `stamp` | shape | lands from 1.06× with the shadow tightening, a press-squash on contact (hanko) | | — | pop (sekai) |
| `outline` | shape | an outline rectangle steps from the origin to the card in 6–8 frames, then the card appears at once (Windows 95's zoom rect) | | frames | win95 |
| `fold` | sheet · vertex | **origami**: the card folded accordion-wise into N panels stacked on the hinge; panels unfold one after another (per-panel lag) with perspective and crease shading; `axes = 2`: first a small square unfolds sideways, then down (a letter, then its half) | the user's Kami default; close refolds | panels 2–5 (auto by size), axes 1·2, crease | origami (kami) |
| `book` | sheet · vertex | split at a spine; closed it's one half with a cover tone (the card's `cover` role), the halves swing open flat with a slight page curl | the user's "notebook" | spine (auto · centre · hinge) | — |
| `roll` | sheet · vertex | rolled into a cylinder at the hinge; it rolls out unrolling the sheet behind it, the back of the paper shaded with the `backside` role; `scroll` variant: two rollers from the centre (makimono) | the user's "carpet" | radius 10–28, variant | sidebars in origami/sumi, bar reveal |
| `crumple` | sheet · vertex+frag | close: creases grow (hashed per-vertex displacement + noise normals), the sheet balls up toward its centroid, the ball drops into its origin or flicks off (toast dismiss); open: the reverse, wrinkles smoothing out last | the user's "crumbling paper" | crumple 0–1 | toast close in origami |
| `genie` | sheet · vertex | magic lamp: the far edge funnels into the origin module along a curve, then the body slides in (macOS's two phases); open = it pours out of the lamp | the user's "magic lamp" (added mid-session) | bend 0–1 | genie (aqua option, dock) |
| `crt` | sheet · frag | on: a dot → a horizontal line (40 %) → full height (60 %) with bloom, barrel and fading scanlines; off: collapse to a line, to a dot, afterglow. **Flash-safe**: luminance step ≤ 20 %, one flash per transition | the user's "old CRT TV" | glow, scanlines | phosphor (terminal) |
| `fan` | sheet · vertex | *sensu*: the card in N ribs about a pivot at the origin, ribs open in sequence | (lead idea, Japanese) | ribs 5–12 | wave 3 |
| `noren` | sheet · vertex | N strips drop in with stagger, each with a small pendulum sway (shop curtain) | (lead idea, Japanese) | strips | wave 3 |
| `pixelate` | sheet · frag | mosaic resolves 32 → 1 px in steps | (lead idea) | — | ps2/snes option |
| `glitch` | sheet · frag | slices offset with RGB split, decaying; never full-screen flicker, < 3 Hz | (lead idea) | — | yorha |
| `dissolve` | sheet · frag | noise threshold with a glowing edge (burning paper, embers) | (lead idea) | edge role | souls, hallownest |
| `splat` | sheet · frag | drops of ink land one after another and spread (lobes, droplets, a smooth union, a last flood); the card shows where ink landed a moment before | user (session 27: Splatoon's ink) | drops 3–12, ink role | — |
| `brush` | sheet · frag | strokes laid forth and back, slightly diagonal, away from the bar; bristle streaks at the edges, a head that runs dry; fresh paint is the ink and turns into the card | user (session 27) | strokes 2–12, slope, ink role | — |
| `snake` | sheet · frag | the card as a grid of cells drawn by a snake: along a row, down one, back; the head a cell in the text's colour, the body in the ink | user (session 27: the snake game) | cell px, length, ink role | — |

Each form declares (in code, published as `motion.forms` meta): **surfaces** it may serve, **family**, **retarget**
(morph · finish-then-morph), **overshoot** (whether p > 1 is drawn or clamped), **flags** `vestibular` (large rotation,
zoom, depth) and `flash` (luminance steps) — what reduce motion and photosensitivity rules key on — and a **cost tier**
(transform · layer · mesh).

**Custom forms — yes, in two tiers.**
1. **Recipes** (declarative, in a user motion pack, wave 3): a form built from tracks over progress — `opacity`,
   `scale`/`scale_x`/`scale_y`, `translate` (fraction of size or px, along/across the edge), `rotate_x|y|z`, `skew`,
   `blur`, `clip` (inset · iris · wipe), plus the built-in sheet forms' params (fold panels, roll radius, genie bend…) as
   tracks. Each track: keyframes `[[p, v], …]` and its own curve. The daemon validates (known props, ranges, key order),
   Settings previews it, the frontend evaluates it with one generic `Recipe.qml`. Covers "pop in and tilt", "drop and
   squash", "slide with a blur trail" — most of what users invent.
2. **Mod forms** (code, later): a mod of the QML tier (W11) registers a form component (and precompiled `.qsb` shaders —
   Qt 6 can't compile GLSL at run time); it appears in the pickers with the mod's name. Raw GLSL in config is not
   offered (security and quality: a broken shader would blank a surface).

### Recipes — the reference (W59.7, as built)
A recipe is your own animation, written in a motion pack — no code, nothing to compile. Put it in any `.toml` file in
`~/.config/kurashi/motion/` (`$XDG_CONFIG_HOME/kurashi/motion/`). Every recipe that is valid becomes a form like the
built-in ones: it is listed in every form picker of Settings › Motion (by its label), any `theme.motion.form.*` key may
name it, and the pack it is in may use it as its own forms. A pack is read again when the shell starts or the appearance
changes (no file watch yet).

```toml
[recipes.<id>]               # the id: lowercase letters, digits and dashes; not a built-in form's (fold, slide …)
label = "…"                  # what the pickers show (plain text, or an i18n key); default: the id
base = "slide"               # optional: a content form the tracks run on top of — slide rubber zoom fade flip bleed stepped
pivot = "centre"             # what scale, rotate and skew turn about: centre · edge (the side it comes from) · origin
[[recipes.<id>.track]]       # 1–12 tracks, one per prop
prop = "scale"
keys = [[0, 0.6], [0.7, 1.06], [1, 1]]   # 1–16 keys [progress, value]; progress 0 = closed … 1 = open, rising
curve = "ease-out"           # optional easing of each segment between two keys (CSS keyframes); default linear
unit = "px"                  # translate tracks only: fraction (of the surface's size, default) or px
```

| prop | range | at rest | meaning |
|---|---|---|---|
| `opacity` | 0 … 1 | 1 | |
| `scale` · `scale_x` · `scale_y` | 0 … 3 | 1 | size (both, width, height), about the pivot |
| `translate_along` | −2 … 2 (px: ±4000) | 0 | along the way the surface comes in; positive = toward its edge (up for a card from a top bar) |
| `translate_across` | −2 … 2 (px: ±4000) | 0 | parallel to that edge; positive = right (top/bottom edges) or down (side edges) |
| `rotate_x` · `rotate_y` · `rotate_z` | −180 … 180 ° | 0 | tilt top/bottom, tilt left/right (with perspective, as `flip`), turn in the plane |
| `skew_x` · `skew_y` | −60 … 60 ° | 0 | slant |
| `blur` | 0 … 64 px | 0 | draws through a layer while it moves |
| `clip_inset` | 0 … 0.5 | 0 | cuts every side by that fraction of the size |
| `clip_iris` | 0 … 1 | 1 | a circle round the pivot; 1 reaches the farthest corner |
| `clip_wipe` | 0 … 1 | 1 | uncovers the surface from its edge |

**How it runs.** One generic `components/motion/forms/Recipe.qml` evaluates every track from the surface's one progress
(no timers). The progress itself already moves on the role's curve (`timing.open` / `timing.close`), so a track's own
`curve` shapes only its segments — presets (`ease-out`, `snap`, `rubber`, …), written curves (`cubic-bezier(…)`,
`steps(4)`, `spring(400ms, 0.4)`) and a pack's named `[curves]` all work. Before its first key a track holds that key's
value. A **close runs the same tracks from 1 back to 0**. Progress past 1 (an overshooting role curve) is clamped: write
an overshoot as keys (`[0.7, 1.06]`). The transforms apply to the surface's content, as the other content forms do; a
blur or a clip makes a layer only while the surface is away from rest, and it is released at rest (Ma).

**The rest rule.** At progress 1 every prop must be at rest, so an open surface is exactly the motion-off frame: a track
whose last key is before 1 is held to its rest value from there, and a key at 1 with any other value is an error.

**Checked by the daemon**, each with a reason Settings shows in words under the recipe (`config.diag.recipe.*`): unknown
prop or key, a form's own param (`fold.crease`: not animatable by recipes yet), a prop animated twice, no keys or more
than 16, more than 12 tracks, a key that is no `[number, number]`, progress outside 0 … 1 or going back, a value out of
its range, a key at 1 off rest, a curve that does not parse or names no pack's curve, a unit on a non-translate track,
an unknown base or pivot, an id that is a built-in form's or not an identifier, the same id in two packs (the first
pack, in file-name order, counts). **A recipe with any problem is skipped whole**; a profile or a setting naming it falls
back to the next form in line (the surface's default, then the profile's).

**Reduce motion.** A recipe that turns more than 30° (`rotate_*`) or scales outside 0.8 … 1.2 (`scale*`) — or sits on
`flip` — is flagged `vestibular` automatically; under reduce motion it never plays (the `reduced` profile fades) and
Settings says so on its card.

**In Settings › Motion › Your animations** every recipe has a card: its pack and file (with *Open the pack file*), what it
animates, where it is in use, the reduce-motion note, a small preview (*Play opening* / *Play closing*, and a scrubber
for any frame) drawn by the same `Recipe.qml` the shell runs; a skipped recipe lists its reasons instead.

**Three worked examples** — `crates/kurashi-motion/tests/recipes-brief.toml`, verbatim (the crate's tests and
`frontend/test-recipes.sh` load this file, so the examples cannot drift):

```toml
# ~/.config/kurashi/motion/mine.toml — a motion pack with three recipes (docs/ux/motion-engine.md §5 "Recipes").
# Its recipes show in every form picker; picking the profile "mine" also uses them as its forms.
name = "mine"
label = "Mine"
description = "Pops in with a tilt; toasts drop in, sidebars slide in through a blur."

[form]
open = "pop-tilt"
close = "fade"
[form.toast]
open = "drop-squash"
[form.sidebar]
open = "slide-blur"
close = "slide-blur"

# 1. Pop and tilt: grows from 60 % past its full size and tips back level as it settles.
[recipes.pop-tilt]
label = "Pop and tilt"
[[recipes.pop-tilt.track]]
prop = "scale"
keys = [[0, 0.6], [0.7, 1.06], [1, 1]]
curve = "ease-out"
[[recipes.pop-tilt.track]]
prop = "rotate_z"
keys = [[0, -6], [0.7, 1.5], [1, 0]]
curve = "ease-out"
[[recipes.pop-tilt.track]]
prop = "opacity"
keys = [[0, 0], [0.35, 1]]

# 2. Drop and squash: falls 48 px into place, squashes against its edge and springs back.
[recipes.drop-squash]
label = "Drop and squash"
pivot = "edge"
[[recipes.drop-squash.track]]
prop = "translate_along"
unit = "px"
keys = [[0, 48], [0.55, 0]]
curve = "ease-in"
[[recipes.drop-squash.track]]
prop = "scale_y"
keys = [[0, 1.08], [0.55, 1.08], [0.7, 0.86], [0.85, 1.03], [1, 1]]
curve = "ease-in-out"
[[recipes.drop-squash.track]]
prop = "scale_x"
keys = [[0, 0.95], [0.55, 0.95], [0.7, 1.1], [0.85, 0.98], [1, 1]]
curve = "ease-in-out"
[[recipes.drop-squash.track]]
prop = "opacity"
keys = [[0, 0], [0.25, 1]]

# 3. Slide with blur: today's slide, seen through a blur that clears before it lands.
[recipes.slide-blur]
label = "Slide with blur"
base = "slide"
[[recipes.slide-blur.track]]
prop = "blur"
keys = [[0, 24], [0.8, 0]]
curve = "ease-out"
[[recipes.slide-blur.track]]
prop = "opacity"
keys = [[0, 0], [0.5, 1]]
```
- *Pop and tilt* starts at 60 % of its size — a zoom, so it is `vestibular`: reduce motion skips it.
- *Drop and squash* stays within 0.8 … 1.2 and turns nothing; its squash is about the edge it hangs from (`pivot = "edge"`),
  so it stays joined to its bar.
- *Slide with blur* runs today's `slide` underneath and adds a blur that clears by 80 % of the way.

**Not yet** (card W59.7 leaves them open): tracks on a sheet form's params with a sheet `base` (fold, roll, genie … — they
need SheetForm to take a recipe), a recipe per surface class (recipes serve every class), and a file watch on the packs.

## 6. Surfaces — where forms apply
Fixed classes (a schema struct, so Settings can generate a table): `island` · `panel` (Stage cards: quick, tray,
session, mod panels) · `peek` · `launcher` · `centre` · `toast` · `sidebar` · `dock` · `bar` (hover/auto-hide reveal) ·
`osd` · `menu` (tray submenus, context menus) · `dialog` (polkit). A form not allowed for a class is not offered there;
a value forced elsewhere shows why it's inert (rule 2). Defaults: `peek`, `osd`, `menu` use `fast` and their profile's
lightest form (a fold on a 40-px peek is noise); `toast` has its own open/close (drop, crumple, flick).
**The island** (D3, user): "It should get every animation style too and also use it by default. The animation style for
the island should be able to be set up separately though … a setting to follow the animation or use its own." So the
island takes **every** form, and **follows** the default form unless `theme.motion.form.island.follow` is off; then its own
`theme.motion.form.island.{open,close}` apply (inert with the reason while following — the `screen_corners_follow`
pattern, K74). What a form animates on the island is its **open/close** (pill → card and back): the pill is the origin
and the hinge (the card unfolds, rolls or pours out of the pill). Face changes in the pill (clock → volume) and hover
peeks keep K42's springs — they are the island's own life, not an opening. A retarget between island views morphs.

## 7. Choreography and interaction
- **Content**: `late` (fades in at p ≥ 0.6 and out first — today's), `with`, `cascade` (rows/tiles arrive in order:
  child pᵢ = clamp((p − i·s) / (1 − n·s)), s = `stagger_ms`/duration; one host progress, no timers, Ma).
- **Origin**: the pressed module's rect (`IslandGeom` registry, I340's rule), else the bar's centre, else the screen
  edge. Genie, liquid, drop and iris need the rect; fold/roll/book use its edge as the hinge.
- **Interruptible** (§9 of DESIGN-SYSTEM): a reversal continues the **form in flight** from its current p and velocity
  (a half-unfolded card refolds even if its close form is crumple); a cubic retarget keeps velocity by choosing the new
  curve's first handle so its start slope matches; springs keep velocity natively.
- **Gesture-ready**: the driver can be *tracked* (`track(p)`) and *released* with a velocity (`release(v)` → spring to
  the nearest end). Wired now for the Settings scrubber; drag-to-dismiss toasts and swipe sidebars are backlog (I346).
- **Sound** (svc.sound, off by default): a form may name a cue (paper rustle on fold, a tick on stepped) — backlog I348.

## 8. The Motion page (Settings)
A dedicated page `motion` (generated from the schema, rule 3, with two custom controls), replacing the two motion rows in
Appearance (which keep a link "Motion…").
1. **Preview stage** (sticky, top): a miniature bar with buttons for each surface class over a patterned ground; click
   one (or Space on it) to open its sample card with the current settings; a **scrubber** (drag p 0 → 1 to inspect any
   frame: the driver's `track`), **Compare** (hold: the previous setting), and the shell's own **Animation speed** row
   (S21, the user: speed is tried where the forms are tried — it replaced the preview-only ½× · ¼×; provenance, Reset and
   inert reasons as on any row). It plays on change and on demand; it never loops by itself (Ma) and stops while the
   window is hidden. Each form runs at its **pace** (forms meta, S21), in the preview as in the shell.
2. **Profiles** (S21: whole presets only): a card per motion pack that names its forms (built-in, style-recommended
   marked, user packs) — curves, forms and accents in one pick — each with a still at p = 0.5 and a play-on-hover/focus
   thumbnail; picking one is a single config op with an undo toast. A timing-only pack (calm, lively, expressive) shows
   here only while it is the profile in effect.
3. **Animation style**: default open/close, then a table *Surface | Opens | Closes* (rows a form doesn't fit show a reason).
4. **Timing** (S21): **Timing preset** — the profile's own, or a timing-only pack's curves and spring family (calm,
   lively, expressive, a user's curve pack) under the profile's forms (`theme.motion.timing.preset`, offers
   `motion.timings`).
5. **Advanced curves** (S21): one row per role (Opens · Closes · Quick moves · Fades) with the **curve control**, and their
   durations (advanced). They override the preset per role.
6. **Choreography & accents**: content (late · with · cascade), stagger, squash, jelly, shadow during motion.
7. **Accessibility**: reduce-motion state with a link; every row shows the inert reason while it's forced.

**Curve control** (new schema control `curve`, leaf `Curve`): a 240 × 240 graph (y −0.5 … 1.5 so overshoot shows) with
two draggable handles, the reference linear diagonal, a ball racing a linear ghost on play; tabs **Cubic · Spring ·
Steps · Presets**; the Spring tab shows duration + bounce (stiffness/damping in "Advanced") and the response plot with
overshoot % and settle time; a paste field taking `cubic-bezier(…)`, easings.net names, `spring(…)`, Hyprland's
`x0, y0, x1, y1`. Keyboard: Tab to a handle, arrows nudge 0.01 (Shift 0.1), Enter commits, Esc reverts; screen readers
read "Handle 1, x 0.38, y 1.21". Invalid input says why (x outside 0…1) and nothing is applied.

**Form picker**: a dropdown with a tiny animated glyph per form (plays on focus only), filtered by surface class.

## 9. Engine architecture (for the cards)
- **Daemon** (`crates/kurashi-motion`, new, pure): curve model + parser/formatter (`cubic-bezier`, `segments`, `spring`,
  `steps`, presets), validation with reasons, spring math (response/bounce ↔ stiffness/damping, settle time, sampled
  plot for Settings), motion packs (built-in `motion/*.toml` + user dir, the same loader rules as looks), profile
  resolution (`style → profile → user axes → a11y`) into tokens. `kurashi-theme/tokens.rs` calls it instead of its
  inline §motion. The niri export (`export.rs`) maps open/close curves and springs onto niri's `animations` — and,
  opt-in, a form's fragment shader onto niri's `window-open`/`window-close` `custom-shader` (crt, dissolve, iris,
  pixelate translate; fold/roll can't — niri shaders have no mesh) — card W59.9.
- **Tokens** (frozen by W59.0; new, beside today's which stay derived for compatibility):
  `motion.profile` (string id) · `motion.curve.{open,close,fast,effects}` =
  `{kind: "cubic"|"spring"|"spring_q"|"steps", ms, points?|response?+bounce?|spring?+damping?|n?}` ·
  `motion.form.<surface>.{open,close}` (form id) · `motion.form_params.<form>` (object) ·
  `motion.accent.{squash, jelly, overshoot_cap, stagger_ms, content, shadow}` · `motion.recipe.<id>` (wave 3) ·
  `motion.forms` (meta: per form `{family, surfaces, retarget, overshoot, flags, tier}`).
- **Frontend**: `core/motion/curves.js` (cubic segments by Newton + bisection, analytic damped spring with v₀,
  steps, the K42 integrator for `spring_q`, retarget slope matching) · `core/motion/Driver.qml` (one FrameAnimation-
  driven progress per surface: `to`, `value`, `velocity`, `running`, `track/release`, `scrub`; runs only while moving)
  — `Glide` and `MorphSprings`' timed path move onto it · `components/motion/FormHost.qml` (successor of `Entrance`,
  which stays as a thin alias): latches the form per transition from `motion.form.<surface>.<dir>`, hands shape forms
  to the morph and loads a sheet form (`components/motion/forms/<Form>.qml`) through a Loader that is active only
  while 0 < p < 1 · `components/motion/Accents.qml` (jelly/squash as an area-preserving Scale) ·
  `components/motion/Stagger.qml` (attached progress for children) · `shaders/motion/*.vert|frag` (qsb: the justfile
  and flake compile `.frag` only today — W59.4 adds `.vert`).
- **Deterministic tests**: `KURASHI_MOTION_SCRUB=<p>` holds every Driver at p (shots by progress, not by sleeping);
  a log line per sheet layer created/released.

## 10. States
Closed (nothing drawn, no layer) · opening · open (at rest: exactly the motion-off frame) · closing · interrupted
(reversal from current p and velocity) · retargeting · origin gone (from the bar's centre) · first open of a view not made
yet (I192: the form holds at p = 0 at its origin until the view exists, then runs; a sheet form needs one rendered frame
of content first) · forced off (reduce motion) · pack missing/invalid (falls back to the style's, then `expressive`, with
the diagnostic in Settings) · multi-output (each output's surface runs its own driver from its own bar) · scale 1.5 (layer
textures at device pixels) · pixel looks (stepped curves step the warp too; at rest exactly on the grid).

### Warm start (session 29, K135)
A sheet form's first frames were its slowest: the form is made, and the surface is drawn into its layer for the first
time (every glyph, picture and shader of a window that did not exist a moment ago). They fell inside the motion, so an
opening began with two or three long frames. A surface that says `SurfaceForm.warm` and gives its FormHost the run
(`FormHost.run`) gets this instead:
- **Asked to open:** the form is made and takes its picture while the progress stands at 0. Nothing is seen (the form
  and what it leaves outside its picture, the surface's shadows, are drawn at an opacity the eye cannot see, just above
  the one the scene graph skips). The travel starts on the second frame swapped with the form in it; `primeReady` is
  the surface's word that its content is made.
- **Asked to close:** the same at 1: the form shows the card as it stands, then travels.
- **Asked back before it began:** the surface is told it has landed where it stood.
- **Limits:** 300 ms after the form exists, 1.2 s without a host: then the travel starts as it used to.
- **Neighbours:** `covers` says when what the surface joins should count it as there (past 90 % of an opening, not
  while closing); a bar leaves its rule out then, once, at the fillets' rest size.
- **The colour clock** (`ColorFlow`) rests from the moment a transition is asked for until it has landed.
Cost: two frames before an opening moves; about 75 ms before a sidebar's close moves (B100). Wired: sidebar, the Stage's
card, launcher, dock.

## 11. Accessibility, Ma and budget
- **Reduce motion** (D1, user: short fades): forces the built-in `reduced` profile — every form `fade`, `effects` curve
  ≤ 150 ms, no accents, `vestibular`/`flash` forms never — instead of today's cuts, as macOS and WCAG 2.3.3 suggest;
  `none` stays a profile anyone can pick. No information lives only in motion; focus paths unchanged.
- **Photosensitivity**: `flash` forms limited to one luminance step ≤ 20 % per transition, never > 3 per second.
- **Ma**: idle = 0 frames, 0 layers, 0 timers; a sheet form's layer and Loader exist only while 0 < p < 1; recipe tracks
  evaluate from the one progress; thumbnails in Settings play on hover/focus only.
- **Budget** (BENCH rows per form, machine A and B's iGPU, at 1× and 1.5×): CPU per motion frame p95 ≤ 8 ms (the W34
  rule); GPU frame ≤ 4 ms for mesh forms at 1×; PSS during a sheet form ≤ +12 MiB and back to baseline ± 1 MiB within
  2 s of rest; frames during a transition = its duration × refresh, 0 after.
- **Pixel-identity of today**: expressive, calm, lively, none and the six looks' motion resolve to the same tokens and
  frames as before (theme goldens unchanged but for the new keys; `test-morph.sh` shots identical).

## 12. Profiles per style (D4; S21)
The user chose (session 19): **kami → origami, terminal → phosphor (CRT), aqua and vibrancy → genie on the dock and
toasts**; and (session 21) **every style brings its own animation** — the table below, accepted as proposed. A style's
pack is its look's `theme.motion.profile` (`looks/*.toml`), a pack per look in `motion/`.
| style | profile | open / close | notes |
|---|---|---|---|
| kami | **origami** | fold / fold | sidebar `roll`, toast `drop` / `crumple`; paper curves |
| washi (default) | washi | bleed / bleed | unchanged; **sumi** (scroll sidebar, ink-drop toasts) ships as an offer |
| yorha | yorha | **pixelate** / pixelate | mechanical, no overshoot |
| souls | souls | **dissolve** / dissolve | slow |
| win95 | win95 | **outline** / outline | linear clock (the 95 zoom rectangle) |
| snes | snes | **pixelate** / pixelate | `steps(8)`: the console's mosaic |
| terminal | phosphor | crt / crt | menus `stepped` |
| aqua | aqua | **genie** / genie | everywhere |
| vibrancy | vibrancy | zoom / zoom | dock and toasts `genie` |
| glass | **liquid** | liquid / liquid | |
| material | material | grow / grow | |
| kawaii | kawaii | **stamp** / grow | jelly 0.35 |
| sekai | **pop** | stamp / grow | a key press |
| hallownest | hallownest | **bleed** / bleed | ink in the void |
| ps2 | ps2 | **iris** / iris | the glowing orb, slow |
| kanso | **kanso** (new) | **expand** / expand | plain, quiet |
| luna | luna | **slide** / slide | |
| aero | aero | zoom / zoom | |
| fluent | fluent | slide / slide | |

**Pace (S21).** A sheet form tells a longer story than a slide (a fold per panel, a bead that gathers, falls and
spreads); at a 240 ms profile curve the user could not see raindrop or origami. Each form has a `pace` in the forms meta
— a factor on the curve's duration (drop 1.9; genie, noren 1.5; fold, book, fan, crumple 1.4; roll, dissolve 1.3;
pixelate, iris 1.2; crt, glitch, outline, stamp 1.1; the rest 1) — that the form's Driver and the preview stretch the
curve by; speed and the user's durations still scale it.

## 13. Definition of done
- Schema v8 + migration; every axis in Settings' Motion page with provenance and inert reasons; today's behaviour
  pixel-identical (goldens, `test-morph.sh`).
- Curve editor: cubic, spring, steps, presets, paste formats, keyboard and screen-reader paths; "Save as preset" writes a
  user pack that lists after a reload.
- Every form in waves 1–2 on every surface class it allows, shot on **niri** at p = 0.15 / 0.5 / 0.85 / 1 (scrubbed),
  top and bottom bar, washi, kami, sekai, glass, terminal, light and dark, 1× and 1.5×; p = 1 equals the motion-off frame;
  reversal mid-way and retarget shots.
- Reduce motion and photosensitivity rules hold (shots under reduce motion: fades only).
- `frontend/test-motion.sh` (new) green in `just suites`; `just check`; bench rows within §11's budget; idle 0 frames.
- Profiles of §12 (origami, phosphor, aqua's genie) accepted by the user on their niri (UX column in PROGRESS).
- The island: every form opens and closes it out of the pill; `form.island.follow` off + its own form works; faces and peeks keep K42.
