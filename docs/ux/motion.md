# UX brief — one motion language: everything grows out of the bar (wave 34)
> **Note (K71, session 14):** the sidebar no longer grows out of the bar button — it slides in from its screen edge
> (`docs/ux/layout.md`); every other surface's motion here stands.

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

## As built (W34, W36)
- **One spring family.** Every shape that grows out of the bar — the Stage's panels and peeks, the launcher and the
  notification centre (BarMorph), a toast's snap-back — runs on `components/island/MorphSprings.qml`: three axes in px
  (the shape's centre along the bar, its width, its foot), each a damped spring from `motion.spring.spring/damping`
  integrated as QML's SpringAnimation does; the travel and width lead on the way out, the foot on the way back (K42);
  a new target keeps place and velocity (open, close, retarget); the overshoot is soft-limited to 3 % (calm) … 8 %
  (lively) of the travel; `motion.spring.squash` (lively 0.06, else 0) narrows the shape while its foot moves fast and
  lets it bulge as it lands, and the neck's fillets swell and thin once with the landing (`neckScale`). A small shape
  (a peek) is stiffer (`stiffness`), same damping ratio. The sidebars keep their own two springs (width, height; the
  free end cannot overshoot the screen's edge, so the rebound goes into the width) with the same constants and the same
  lively squash; their origin is the sidebar button (`IslandGeom` registry, `sidebar:<side>`), see `sidebar.md`.
- **Rest place.** A panel that grew out of a bar widget (quick settings and the phone, a tray menu, a mod's panel)
  rests **under that widget**, centred on it and kept `space.pad` inside the output: the container transform — the
  card is the button grown — and under keycap/soft chrome its neck stays on the widget's block instead of letting go
  (before W36 the card rested centred and detached from its group mid-way). The island's views, the session menu (no
  widget), the launcher and the centre rest centred under the pill. A widget not on this output: the old place.
- **Toasts.** The drip keeps its designed timeline (grow out of the bar's edge, pull past the place, the thread
  thins and snaps); from the snap on, the card's top and width are MorphSprings: it springs back up to its place and
  from pulled-thin to its width (lively: past it into a bulge, the height following so the area stays), and the stub
  and bump melt back. Without a top or bottom bar the card slides in 32 px from the screen's edge as it fades in
  (`Theme.stdMs`), and leaves by the same flick and drift as on the bar (before W36 both were cuts).
- **No wait before the first frame (I192).** The Stage makes its view asynchronously; the card takes the size that view
  had the last time it was shown (per kind, a mod panel per name) until it is made, so the shape grows at once and the
  view fades in when it is there. Only a view's very first open holds the growth (the shape stays at its origin) until
  the view is made; a retarget to a view not made yet keeps the present card's size meanwhile. Quick settings: patch →
  first Stage commit 102 → 12 ms (W36, machine A, load ~8).
- **Polkit (I128).** While a polkit dialog is up (`runtime.ui.polkit`) the Stage steps aside: no panel or peek opens,
  no keyboard focus; an open panel folds away and is closed at the daemon (`ui.close` keeps the polkit flag), so it does
  not come back when the dialog goes; a panel asked for meanwhile is closed the same way.
- **Known:** the first spring step lands ~3 frames (≈ 40 ms) after the shape's first frame on every surface — Qt's
  animation timer starting, not the springs (the pre-W36 SpringAnimation shows the same). The quick card's view
  (QuickPanel, ~60 ms of work) is made in slices between the shape's first frames on the same thread, so under load
  (machine A at load ~8) its visible growth starts ~100 ms after the first commit even with a cached size; the first
  open of a session holds at the button until the view is made (≥ 120 ms). A lighter QuickPanel is the real fix.

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
