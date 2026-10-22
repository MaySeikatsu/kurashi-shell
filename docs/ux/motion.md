# UX brief — one motion language: everything grows out of the bar (wave 34)

User (session 13): "I really like the two animation styles we have so far. But some surfaces don't feel as dynamic and
fluid as others — I like how the dynamic island animates, extends and feels kinda fluid, wobbly and dynamic, other
extended surfaces should behave the same and also get a similar merging animation going on into the bar."

Today only the island's kinds morph (W21/K42: `components/island/MorphShape.qml` — one shape from the pill's rect to the
card's, width and height on their own springs, a liquid neck of concave fillets where it crosses the bar's edge). Every
other surface that comes out of the bar enters with its own small motion: the quick card, session and tray menus, mod
panels and peeks slide 12–16 px and fade (Stage); the sidebars slide from their edge (a spring, no join with the bar);
the launcher slides and scales 0.96 → 1; the notification centre and the toasts slide. They read as separate windows
appearing, not as the bar reaching out.

## How others do it
- **iOS Dynamic Island**: one shape that is always the same object; it stretches into whatever it shows with a spring,
  content cross-fades inside it, and it shrinks back into the pill. The reference we already follow for the island.
- **Material 3 "container transform"**: a surface opens *from the element that launched it* — the card is that button,
  grown — and closes back into it. The formal name for what the user asks for.
- **Caelestia (Quickshell)**: the bar is part of a thin screen border; every drawer (launcher, dashboard, notifications,
  session, OSD) grows out of that border in the border's own colour, with inverted rounded corners where it meets it, so
  panels look like the frame stretching, not windows on top of it. The closest shell to the request.
- **end-4 (illogical-impulse)**: sidebars slide in from the screen edges under the bar, with rounded screen corners; the
  bar's corners and the sidebar meet with inverted corners in some configurations.
- **macOS**: Control Center and menu-bar extras open *from their menu-bar item* (a short scale + fade anchored at the
  item); Notification Center slides from the right edge as one sheet. **GNOME 4x**: quick settings drop from the panel
  button anchored at it; **KDE Plasma**: popups slide out of the panel edge they belong to. **Windows 11**: flyouts rise
  from the taskbar edge with a decelerating slide.
- **Capsule** (`capsule/animator.rs`): width leads on the way out, height leads on the way back; retargets keep velocity;
  squash and stretch mid-morph (I113) as an option.

## The model — "the bar reaches out"
Every surface that belongs to the bar is drawn as **one shape that grows out of where it came from** and folds back into
it. Same machinery as the island (one shape, two springs, liquid neck), generalised:

| surface | origin | shape at rest | join with the bar |
|---|---|---|---|
| island views (today) | the island pill | the card | neck fillets; joined/strip as today |
| quick card (incl. the phone), session menu, tray menu, mod panels | the bar widget that opened it (its rect) | the panel | neck fillets under the widget; keycap: joins its group |
| peeks (hover) | the hovered widget | the peek card | a short neck; it is a small morph, not a slide |
| left / right sidebar | the bar's end (its sidebar button, else the bar's corner on that side) | the full-height column | the column's inner top corner meets the bar's edge with a concave fillet; its outer edge stays flush with the screen |
| launcher | the island pill (centre of the bar) — or its bar button when it has one | the launcher card | neck fillets, like an island view |
| notification centre | the notifications face / bell | its card | neck fillets |
| toasts | the island pill | a free card under the bar | **buds off**: the shape drops out of the bar with a neck that thins and detaches (a drip), then stands free; it closes by fading/flicking away, not back into the bar |

Side bars (left/right): the same with axes swapped (the shape grows sideways out of the bar). Bottom bar: mirrored (as the
island's `flip`).

**Retarget**: switching between panels while one is open (quick → session, tray → quick, one mod panel → another) morphs
the shape from one panel's rect to the next's instead of closing and opening; the neck slides along the bar to the new
origin.

**Content**: the content of a surface sits where it always does and is *cut to the shape* while it moves; it fades in
late (when the shape has nearly reached its size) and out first, as the island's views do. Materials (K61 carried sheet)
come with the shape.

**Motion profiles** (the user's two styles stay):
- `calm`: springs close to critically damped — a soft settle, overshoot ≤ 3 %.
- `lively`: bouncy springs (overshoot up to the island's 8 % soft limit) **and** squash & stretch mid-morph (I113): the
  shape narrows slightly as it lengthens fast and bulges back as it lands; the neck wobbles once.
- `none` / reduce motion: cuts (no shape motion, content appears at once).

## States
Opening, open, retargeting, closing, closed; interrupted (close during open continues from the current value and
velocity); a surface whose origin is gone (the widget hidden on this output) grows from the bar's centre; multi-output:
each output's Stage/surface morphs from its own bar; the pointer leaving during a peek folds it back.

## Keyboard, a11y
Unchanged focus paths; Esc closes with the same fold. Reduce motion = cuts. No information lives only in the motion.

## Ma and budget
Springs run only during a transition (visibility-gated); idle 0 frames; one shape per open surface. A morph frame must
stay under 8 ms CPU on machine A and B's iGPU (JS path building per frame is the risk — cache sub-paths, avoid per-frame
allocations). Bench rows: frames and CPU per open/close for each surface (W33 harness).

## Fixes this must include
B32 (morph stuck at ~55 % height once), I160 (translucent head darker than body), I161 (the phone's fade-out takes the
rule copy with it), I122 (slide-ins cast no soft shadow — they become morphs with the shape's own shadow), I113.

## Definition of done
- Every surface in the table opens from its origin and folds back into it, in both profiles, with its join to the bar
  (shots at 40/120/250 ms for open and close: island view, quick, session, tray, a mod panel, a peek, left and right
  sidebar, launcher, notification centre, a toast budding; top and bottom bar; washi, sekai, kami).
- Retarget quick → session → tray without a close (shots mid-retarget).
- `lively` shows squash/stretch and one neck wobble; `calm` settles softly; `none` cuts.
- Carried material moves with every shape; no rectangle seams at the necks.
- `test-island-morph.sh`, `test-stage.sh`, `test-sidebars.sh`, `test-launcher.sh`, `test-quick.sh` green; new
  `test-morph.sh` covering the table; idle 0 frames; bench rows per surface.
