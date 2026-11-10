# W69-webdock-styles — the web dock's page in a style: notebook, phone, plain (I468)

Model: Opus (visual judgement, motion). Branch `feat/s27-webdock-styles`. Common rules: `docs/tasks/README.md`.
Build dir: `CARGO_TARGET_DIR=$HOME/.cache/kurashi-agents-target/w69`.

## Goal
`docs/BACKLOG.md` I468 (user, 2026-11-10; the user is away and cannot judge prototypes, so build to your best judgement
and list your open questions in the report): "Add different style options for the web dock (like a half of an opened
notebook, with the proper animation), still the phone style (when extended morphs into a tablet shape sideways), simple
one that just morphs out of the surface showing the webpage without phone decoration."

The web dock (`mods/webdock/`, `docs/ux/webdock.md`, `docs/ux/webdock-engine.md`) shows a pinned site in a page that
today wears a phone's frame. Wanted: a setting of the mod, **Page style**, with three choices, each thought through:

1. **Notebook** — one half of an opened spiral notebook: the page is the right-hand (or, at a left edge, left-hand)
   sheet; the spiral binding runs along the side the dock is on (wire loops through punched holes, a card cover's edge
   showing behind the sheet, a thin shadow in the gutter). The reference picture is on the machine at
   `~/.cache/kurashi-refs/s27/7.png` (a lined sheet, copper spiral, kraft cover; read it, do not copy or ship it:
   draw the binding procedurally in QML/shaders, coloured from the theme's tokens — the wire from the outline or a
   metal tone, the cover from a surface container tone, the sheet the page's ground). The web page sits inside the
   sheet's margins. **Its animation**: opening turns the sheet over the binding (a page turn about the spiral's axis:
   the motion engine has sheet forms — `book`, `fold`, `roll` in `frontend/components/motion/forms/` — reuse the form
   system or its `book` form where it fits rather than a one-off animation); closing turns it back. Under reduced motion
   and `theme.motion.profile = none`: a cut or a fade, as every surface.
2. **Phone** — what exists, kept: when the page is extended (its wide view) the phone morphs into a tablet lying
   sideways (landscape), with a continuous morph of the frame (radius, bezel, camera/notch if any) and of the page's
   size, not a swap. Check what "extended" is today in the dock's code and brief before designing; if there is no
   extended state yet, add one that is reachable by pointer and keyboard and say how in the brief.
3. **Plain** — no device: the page morphs out of the dock's surface as the shell's cards do (the shell's own join and
   radius, the theme's material and outline), showing the page alone.

For all three: the theme's tokens only (hard rule 4: no branches on a look's name); the material/texture and the pen
outline of the current look where a RoundBox would have them; keyboard reachable; the page's web content must not be
re-created when the style or the extended state changes (no reload of the site); multi-output as the dock is; Ma: no
frames at rest, the binding's drawing cached (no per-frame Canvas work).

**Brief first**: add a section "Page styles" to `docs/ux/webdock.md` before building — how others frame web/side
panels (Vivaldi/Edge/Opera side panels, Arc's Little Arc, Zen's Glance, GNOME/KDE widgets with device frames, Android
desktop-mode windows), the three styles' anatomy, states (loading, error, offline, no pin), keyboard and a11y, motion
(open, close, extend, style change while open), multi-output, budget, definition of done.

## Owned paths
`mods/webdock/**` (QML, host, mod.toml, its i18n and tests), `crates/kurashi-mod-webdock/**` only if a setting needs
daemon code, `docs/ux/webdock.md`. New shared motion pieces only if unavoidable: then a CONTRACT-CHANGE row and a
local stand-in.

**Not yours** (the lead edits them in parallel): `frontend/**` (read-only: reuse its components and forms),
`settings/**`, `crates/kurashi-schema/**`, `crates/kurashi-texture/**`, `crates/kurashi-motion/**`,
`crates/kurashi-theme/**`, `docs/DECISIONS.md`, `docs/BACKLOG.md`, `docs/PROGRESS.md`, `docs/HANDOVER.md`.

## Frozen
`crates/kurashi-ipc`, `fixtures/ipc/`, `docs/PROTOCOL.md`, `crates/kurashi-core`. Needs outside → `docs/CONTRACT-CHANGE.md`.

## Acceptance
- The mod's test (`mods/webdock/test/…`) gets steps (sandbox, condition waits, motion off except where motion is under
  test): each style draws its page with a pin open; switching the style while open keeps the page (the web view's
  object or a load counter does not change); the phone's extended state is a tablet (wider than tall) and back; the
  notebook's binding is on the dock's side at a left and a right edge; no QML error or warning; idle: 0 frames in 5 s
  with the page open and still (if a web page itself animates, use a static `file://` page).
- Screenshots on nested niri (`tools/bench/niri-sandbox.sh`, the lead platform; ONE sandbox at a time, prefix `w69-`):
  each style closed→open at three steps of its motion and at rest, the phone extended, light and dark, in
  `mods/webdock/shots/styles/`, named in the report.
- `just check` green.

## Token thrift
Read: this card, `docs/tasks/README.md`, `CLAUDE.md`, `docs/ux/webdock.md`, the dock's QML you change, the `book` form
and `SheetForm.qml` if you reuse them, the reference picture once. Terse report in the README's format, with a list
"questions for the user" (design choices you made that they may want otherwise).
