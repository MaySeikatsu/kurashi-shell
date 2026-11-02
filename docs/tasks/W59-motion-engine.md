# W59 — the motion engine (overview, waves, frozen contract)

Session 19 plan. **UX brief:** `docs/ux/motion-engine.md` (read §3–§9 and §13 before any card). **Decision:** K83
(the user answered D1–D4 in session 19; K83 records them).
Common rules: `docs/tasks/README.md`. Every user-facing card is reviewed on **niri** shots (`tools/bench/niri-sandbox.sh`).

## Cards and waves
| wave | card | what | owner paths (summary) | model | depends on |
|---|---|---|---|---|---|
| A | W59.0 | contract: schema keys, `Curve` leaf + `curve` control, token shapes, fixture, PROTOCOL, i18n skeleton, shader build glob | schema, config tests, fixtures, PROTOCOL, justfile/flake shader lines, `i18n/*/motion.toml` | **lead** (Opus) | — |
| A | W59.1 | daemon: `kurashi-motion` crate, motion packs, tokens from packs, today bit-exact | `crates/kurashi-motion/`, `motion/`, tokens.rs §motion, looks' motion keys, styles' recipes | Opus | W59.0 |
| A | W59.2 | frontend core: curves.js, Driver, FormHost, Accents, Stagger, scrub; Glide/MorphSprings/Entrance on it, pixel-identical | `frontend/core/motion/`, `frontend/components/motion/`, Glide, MorphSprings, Entrance | Opus | W59.0 |
| B | W59.3 | every surface class through FormHost with its origin; shape forms expand · iris · stamp · outline | `frontend/surfaces/*` motion parts, MorphShape/IslandGeom, `components/motion/forms/{Expand,Iris,Stamp,Outline}.qml` | Opus | W59.1, W59.2, D2/D3 |
| B | W59.6 | Settings Motion page: preview stage, profile gallery, curve control, form picker, provenance | `settings/` motion files, `i18n/*/motion.toml` (strings) | Opus | W59.0, W59.2 |
| C | W59.4 | sheet forms (paper): fold (1/2 axes), roll (+scroll), book, crumple; sheet layer lifecycle, hinge, shadow/blur handover | `components/motion/forms/{Fold,Roll,Book,Crumple,SheetForm}.qml`, `shaders/motion/{fold,roll,book,crumple}.*` | Opus | W59.3 |
| C | W59.5 | genie, crt, drop, liquid | `components/motion/forms/{Genie,Crt,Drop,Liquid}.qml`, `shaders/motion/{genie,crt,drop}.*`, liquid neck in MorphShape (coordinate with W59.3's merge) | Opus | W59.3 (W59.4's SheetForm merged first) |
| D | W59.7 | recipes: daemon validation + `Recipe.qml` + Settings recipe list (read-only editor: TOML + preview) | `crates/kurashi-motion/src/recipe.rs`, `components/motion/forms/Recipe.qml`, settings recipe view | Opus | W59.1, W59.6 |
| D | W59.8 | wave-3 forms: fan, noren, pixelate, glitch, dissolve | `components/motion/forms/{Fan,Noren,Pixelate,Glitch,Dissolve}.qml`, their shaders | Haiku 5.5 max (one agent per two forms), lead reviews | W59.4 |
| E | W59.9 | profiles per style (§12 after D4), niri export (curves/springs; opt-in custom-shader windows), bench `tools/bench/motion.sh`, DESIGN-SYSTEM §motion rewrite | `motion/*.toml` (new packs), `styles/*.toml` recipes, export.rs niri part, tools/bench/motion.sh | lead + Opus | all |

Run in parallel only where owner paths are disjoint (A: W59.1 ∥ W59.2; B: W59.3 ∥ W59.6; C: W59.4 then W59.5's
merge; D: W59.7 ∥ W59.8). Push `main` before spawning. One `CARGO_TARGET_DIR` per card (B23).

## Frozen contract (W59.0 implements exactly this; later cards code against it)
### Schema (`theme.motion`, `crates/kurashi-schema/src/v1.rs`) — no version bump (no rename: today's profile values stay valid ids)
| key | type | default | notes |
|---|---|---|---|
| `theme.motion.profile` | `MotionPackId` (string, validated against the pack registry; choices listed from it) | `"expressive"` | `overridden_by = "a11y.reduce_motion => reduced"` (D1) |
| `theme.motion.speed` | f64 0.25–3.0 | 1.0 | unchanged |
| `theme.motion.timing.{open,close,fast,effects}` | `Curve` (control `curve`) | `""` = the profile's | canonical strings, brief §4 |
| `theme.motion.timing.{open,close,fast,effects}_ms` | u32 0–3000, advanced | 0 = the profile's | `requires = profile != none` |
| `theme.motion.form.{open,close}` | `FormId` (string, validated against `motion.forms` meta) | `""` | the default for every surface |
| `theme.motion.form.<surface>.{open,close}` | `FormId` | `""` = `form.{open,close}`, then the profile's | surfaces: `island panel peek launcher centre toast sidebar dock bar osd menu dialog`; a form whose meta does not list the surface is invalid there (diag + reason); every form lists `island` (D3) |
| `theme.motion.form.island.follow` | bool | `true` | D3: the island follows `form.{open,close}`; off → `form.island.*` apply (they carry `requires = theme.motion.form.island.follow == false` and read inert with the reason while following) |
| `theme.motion.content` | enum `profile late with cascade` | `profile` | |
| `theme.motion.stagger_ms` | i32 −1…60 | −1 = the profile's | `requires = content == cascade` (or the profile's cascade) |
| `theme.motion.squash` | f64 −1, 0…0.15 | −1 | |
| `theme.motion.jelly` | f64 −1, 0…1 | −1 | |
| `theme.motion.shadow` | enum `profile carry fade` | `profile` | |
| `theme.motion.windows` | enum `off follow` (W59.9 wires it; W59.0 adds the key, inert with reason until then) | `off` | niri window animations follow the profile's curves |
The settings page attribute: `page = "motion"`; the two motion rows leave `appearance` (Appearance keeps a link row).
`Curve` validation (daemon): parse per brief §4; x ∈ [0,1], y ∈ [−1,2], segments end at (1,1), spring response
50–3000 ms, bounce −0.5…0.9, steps 1–60; errors carry `config.diag.curve.*` keys.

### Tokens (theme document, beside today's — those stay, derived)
```
motion.profile                      "origami"                 (string id; today's 4 unchanged)
motion.curve.<role>                 role ∈ open close fast effects
    {"kind":"cubic","ms":500,"points":[x1,y1,x2,y2,ex,ey,…]}     (QML bezierCurve order, last point 1,1)
    {"kind":"spring","ms":550,"response":550,"bounce":0.45}
    {"kind":"spring_q","ms":0,"spring":4.0,"damping":0.45}      (K42 integrator; calm, lively)
    {"kind":"steps","ms":67,"n":4}
motion.form.<surface>.open|close    "fold"                    (resolved: user surface > user default > pack surface > pack default)
motion.form_params.<form>           {"panels":3,"axes":2,"crease":0.35}   (only forms in use)
motion.accent.squash|jelly|overshoot_cap|stagger_ms  numbers;  motion.accent.content "late|with|cascade";  motion.accent.shadow "carry|fade"
motion.forms                        {"fold":{"family":"sheet","surfaces":[…],"retarget":"finish","overshoot":false,"flags":["vestibular"],"tier":"mesh"},…}
motion.recipe.<id>                  (W59.7) {"tracks":[{"prop":"scale","keys":[[0,0.6],[0.7,1.05],[1,1]],"curve":{…}}]}
```
`motion.profile = none` (or the a11y force) → every `motion.form.*` = `"none"` and every curve `{"kind":"none"}`.
Fixture: the theme golden(s) gain these keys (`fixtures/ipc/server/*theme*`, M3-golden); PROTOCOL §theme lists them.

### Motion pack (`motion/<id>.toml`)
```toml
name = "origami"
base = "expressive"     # row 641: what today's K42/K74 machinery does under the pack (expressive|calm|lively|none|reduced)
# Blocks layer (row 641): [timing], [form](+[params]), [accents] are this pack's when present (an empty table = the
# defaults), else the style's pack's — so expressive/calm/lively/none are timing-only profiles over the style's forms.
label = "config.choice.motion.origami"        # i18n
description = "config.choice.motion.origami.desc"
[timing]            # curve strings (brief §4) and durations
open = "paper"        open_ms = 520
close = "paper"       close_ms = 420
fast = "cubic-bezier(0.2, 0, 0, 1)"  fast_ms = 260
effects = "effects"   effects_ms = 180
[form]              # defaults, then per surface
open = "fold"
close = "fold"
[form.peek]  open = "grow"   close = "grow"
[form.toast] open = "drop"   close = "crumple"
# no [form.island]: the island follows the default (D3) unless the user turns island.follow off
[params.fold] panels = 0  axes = 2  crease = 0.35   # 0 = auto
[accents] content = "late"  stagger_ms = 0  squash = 0  jelly = 0  shadow = "fade"
[curves]            # user packs: named custom curves ("Save as preset…")
my-snap = "segments(…)"
[recipes.my-pop]    # W59.7
```
Built-ins W59.1 ships: `expressive calm lively none reduced fluent aqua material snes ps2 kawaii` (bit-exact today).
New profiles (`origami sumi pop liquid phosphor glitch ember outline pudding`) come with their forms (W59.4/5/8); W59.9
makes kami recommend `origami`, terminal `phosphor`, and gives the `aqua` pack (aqua + vibrancy) `genie` on dock and toasts
(D4); washi stays as it is; the rest are offers.

### Frontend interfaces (W59.2 creates; W59.3–W59.8 use)
- `Theme.motionCurve(role)`, `Theme.motionForm(surface, dir)`, `Theme.formParams(form)`, `Theme.accent(name)`,
  `Theme.formMeta(form)` — plain readers of the tokens above (Theme.qml stays the token gate).
- `Driver { to; role: "auto"|…; value; velocity; progress; running; direction; function track(p); function release(v);
  function snap(v) }` — FrameAnimation-driven, running only while moving; honours `KURASHI_MOTION_SCRUB`.
- `FormHost { surface; edge; origin /* rect in host coords */; progress; direction; source /* item */; readonly form;
  readonly family; readonly busy }` — latches `form` when a transition starts; for `family = sheet` it loads
  `forms/<Form>.qml` (Loader active only while 0 < p < 1) with `{source, progress, edge, origin, params, size}`.
- A sheet form component: `SheetForm.qml` (W59.4) is the base — the `ShaderEffectSource` (live while busy, `hideSource`),
  hinge geometry, the shadow/blur handover signals, a `GridMesh` resolution property, a log line on create/release
  (`motion: sheet layer up <surface> <form>` / `… released`).
