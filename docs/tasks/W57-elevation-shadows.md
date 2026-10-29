# W57-elevation-shadows — drop shadows that lift the shell's surfaces, static or following the light (I310)

Session 18. **UX brief first:** extend `docs/ux/shadows.md` (K67) with a section "Elevation" before code (CLAUDE.md UX
bar), then this card's code. Common rules: `docs/tasks/README.md`.

## Ask (user, session 17)
"A shadowing system with a drop shadow that can also apply to the bar, the frame, the sidebars and every other overlaying
component where a shadow makes sense, to elevate them and show depth — static (shadow position etc. set by hand) or
dynamic (reacting to the lighting system)."

## Today (K67)
Blocks get keycap's hard shadow or soft's blurred one along one shadow vector (`theme.material.shadow`, `shadow_angle`,
`shadow_follow` = away from the material's light); flat and line chrome have none; the shell's large surfaces (bar
strip, frame band, sidebars, dock) cast nothing onto the desktop.

## Design questions for the brief (decide with the user)
- **Model.** An elevation per surface role (frame/bar 1, dock and sidebars 2, cards and popups 3, toasts and the launcher
  4): the drop shadow's softness, distance and opacity grow with it; one global strength and a mode `off | static |
  follow light`, chrome-independent (flat and line can have elevation too). Static: angle, distance, softness, opacity by
  hand; follow: from `theme.light` (the wallpaper's lamp, the pointer, the spotlight — see W58), long and soft when the
  light is low.
- **Where shadows fall.** The frame band and the bars cast onto the desktop (the hole) and onto windows; sidebars and the
  dock onto the desktop and the band; cards onto what is under them. Joined shapes (fillets) cast one continuous shadow
  with what they join.
- **Who draws it (efficiency, Ma).** (a) Client-side `RectangularShadow`/`MultiEffect` in each surface's window: needs
  the window to grow by the shadow's reach (input region unchanged), redraws when the light moves — fine at rest, costs
  frames while a pointer light moves. (b) niri draws layer-surface shadows itself (`layer-rule { match namespace=…;
  shadow { on; softness; spread; offset; color } }`, geometry-corner-radius): no client cost, follows the surface's shape,
  but static and niri-only; kurashid already writes niri config includes (keys) and could write these from the settings.
  Recommended: (b) for `static` on niri, (a) for `follow light` and other compositors; the brief records it.
- States: off, static, follow (light at rest, light moving), reduced motion (static at the light's rest), high contrast
  (off or outline-only), multi-output (each output's own light).

## Acceptance (after the brief)
Shots on niri per mode × chrome (flat, keycap, line) for bar + frame + sidebar + dock + a card; light moving: frames
budgeted (BENCH), idle 0 frames; Settings shows the mode, the elevation preview and why a control is inert (rule 2).
