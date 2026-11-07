# The shell's forms on niri's windows — UX brief (session 23, I410, K91)
Status: v1. Test `frontend/test-niri-motion.sh`, in the merge set. Reviewed on nested niri on the GTX 1060, every form at four
progress values.

## Job
A window opens and closes in the form the selected style gives the shell's surfaces. Under origami a window folds out as a card
does; under glitch it arrives in slices and burns away. The user's words: "the animations should represent the same style selected
by the shell".

## How others do it
- **[nirimation](https://github.com/Xansidev/nirimation)** (MIT), **[niri-animation-collection](https://github.com/jgarza9788/niri-animation-collection)**
  (MIT) and **[liixini/shaders](https://github.com/liixini/shaders)** (MIT): hand-picked `custom-shader` blocks to paste into the
  niri config. They show what niri's hook can do and how window texture sampling goes. No code of theirs is used: every form here is a
  port of the shell's own form, and a paste could not follow the style.
- **Burn-My-Windows** (GNOME): an effect per window event, in its own settings. Effects do not follow a theme.
- **Hyprland** (`animations`), **KDE** (window effects), **macOS** (genie/scale): a fixed list of effects, none tied to the shell's motion.
- Quickshell shells (Caelestia, end-4, DankMaterialShell, Noctalia) were not checked for this brief: their animations are their own surfaces', as far as the earlier motion brief found.

## What niri can carry
`custom-shader` on `window-open`, `window-close` and `window-resize`: fragment stage only, GLSL ES 1.00 after niri's prelude, over
the window's texture and 500 px round it. So:
- **Every form of the shell is carried.** The mesh warps (fold, book, roll, genie, noren, fan, crumple) run their map backwards per
  pixel; fragment forms port across. Differences from the shell, all forced by the hook:
  - no hinge on a bar: a window hangs from its own top edge (the bar's edge is not known to the shader; I412);
  - no origin: genie's mouth, crumple's target and dissolve's first fire are the top's middle; iris opens from the middle;
  - crumple's facets are shaded on a radial map, not a true mesh of creases, and its far side is not drawn;
  - no derivatives (`#extension` would have to precede the prelude): edges are a logical pixel wide;
  - flip and book turn away from the viewer: a tall window turned toward them would cover the screen. Fan's rays are limited
    so that its rim stays inside the 500 px.
- **A user's recipes** (I418, K95) are generated from their tracks, with no port by hand: `niri_recipe.rs` writes one function per
  prop, `niri_forms/recipe.glsl` is `recipe.js` run backwards per pixel. Differences from the shell: `origin` is the top edge's middle (no
  origin reaches a shader); a blur is a 16-sample disc, so it is grainier than the shell's layer; a recipe that turns a tall window toward
  the viewer grows past the 500 px niri draws round it and is cut there, and so does a long translate. A skipped recipe falls to the next
  form in line, as on every other surface.
- **Not carried**: the workspace switch and view movement have no shader hook: they keep the curves `follow` gives them.
- `window-resize` stays niri's. The shell has no resize form.

## Design
- **One setting.** `theme.motion.windows`: Off (default) · Follow the profile (curves alone) · **Follow the profile, with its
  animations** (`forms`). Opt-in, because niri does not promise to keep the interface.
- **The form.** `motion.form.window.{open,close}` is resolved like any surface class: the user's `theme.motion.form.window.*`, the
  user's default, the pack's `[form.window]`, the pack's default. So a style's pack brings its form, and a pack can give windows
  their own.
- **Timing.** The role's curve and the form's pace, as in the shell. A single cubic and a spring are niri's own `curve` and `spring`.
  What niri has no curve for (steps, several segments) runs in the shader on a linear clock. K42's springs take the family's spring.
- **Export.** Through the theme pipeline, in `kurashi.kdl`, included after the user's own `animations` block. Colours, light,
  radius and form parameters arrive as constants, so a dissolve burns in the palette's ember.

- **Choosing by hand.** Settings › Motion's table of surfaces has a row for compositor windows, open and close, inert with its reason and a link until Window animations carries the animations (K93's PR; before it the rows were filtered out of the page).

## States
- Off, or Follow: no shader written.
- Reduce motion, profile none: niri's `animations { off }`. Flash and vestibular forms are already resolved away by the daemon.
- `none` as a window's form: that animation's `off`.
- A later niri refuses a shader: niri warns and keeps its own (the row's help says so). The daemon cannot see this (Shōjiki's limit:
  said, not detected). Each form is compiled by `just check` (glslang, ES 1.00) and in niri by the suite.
- Hyprland, MangoWM, sway: no change; the row says niri.

## Keyboard and a11y
Settings rows like any other. The window rows read inert with their reason unless `forms` is chosen. Reduce motion wins.

## Motion and budget (rule 5)
A shader runs only while a window animates: nothing at rest, no timers. A fold's cost is a small loop per pixel of the window and its
500 px margin, for its 500 ms. kurashi.kdl grows by about 10 KB. Not measured against a budget (docs/BENCH.md has none for this): I404's
measurements should add it.

## Fit
Same pack, same progress convention as `FormHost`: p 0 gone … 1 in place, a close the open's frames backwards.

## Definition of done
Every form compiled in niri on real hardware; a style's pack gives the windows its form; off changes nothing; reduce motion has none.
