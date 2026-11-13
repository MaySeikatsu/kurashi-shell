# Workspace switch motion (session 32)

The user (session 32, with four close-ups of the bar): "When switching workspaces, animate the bar symbol fluently — it
fluently morphs over to the other workspace, maybe with a little wobble if the default motion profile has that." Build at
least three animations.

## How others do it
- **end-4 (illogical-impulse), Caelestia** (Quickshell): one active indicator under the numbers that slides with an
  expressive curve; Caelestia stretches it toward the target before it lands.
- **DankMaterialShell, Noctalia**: the focused pill widens and the indicator glides; no liquid look.
- **HyprPanel**: the active workspace's icon swaps, no travel.
- **Android page indicators** ("worm", "jumping dot", "liquid" in many apps): the front edge leads, the back catches up;
  the liquid kind pinches a neck between two bulbs — the look in the user's pictures.
- **GNOME** (the overview's dots), **KDE** (pager), **COSMIC**, **macOS** (Spaces), **Windows** (Task View): no travelling
  mark on the panel.

## The design
One mark for the focused workspace lies over the row's keys (`components/bar/WorkspaceMark.qml`) and travels; the keys keep
their own looks (occupied, empty) and no longer light themselves. The numbers are drawn over the mark; each turns to the
mark's ink by how much of it the mark covers, so a number the mark passes reads all the way.
`modules.workspaces.motion` (the module's right-click menu and Settings › Layout):
- **goo** (default, "Liquid"): the end in the direction of travel leads, the other trails; while it is drawn out the middle
  thins to a neck (at most a third of the height each side, never two pieces), and it settles into one key.
- **stretch**: the same two ends, no neck (a worm).
- **slide**: both ends together; the pill glides.
- **off**: each key lights on its own (as before).

**Wobble** is the motion profile's, never a renderer branch (rule 4): with springs (`motion.kind = spring`) the ends spring
on `motion.spring.spring`/`damping` (a low damping overshoots and settles — the lively profiles wobble, the calm ones do
not); timed motion uses `stdMs` and `motion.spring.overshoot` (OutBack); motion off (`motion.spring.on = false`) snaps.

## States
- One workspace, or the focused one hidden by "Show empty: off": the mark rests on the focused key; nothing travels.
- A workspace added or removed: the keys move; the mark follows its key's box (it is a goal, not a fixed place).
- Module made or the bar reloaded: the first goal is taken as it is (no travel from the row's start).
- Columns (a side bar): dots as before, no travelling mark (not in this round).
- Dots and the M3 navigation look (`workspace.mark = indicator`) travel too, in their own colours (accent, `selected`).

## Keyboard and a11y
Nothing new to reach: the keys keep their taps; the mark is decoration (no accessible name). A screen reader reads the
numbers as before.

## Budget (Ma)
Nothing runs at rest: the ends animate only when the focused key changes, the shape repaints only then (Behaviors with a
0.25 px epsilon). No timer, no polling.

## Definition of done
Three styles plus off, chosen from the module's menu; the wobble from the motion profile; seen on nested niri mid-switch
(shots in the PR); `frontend/test-ws-motion.sh` checks that mid-switch the mark spans between the keys and that it rests
on the new key; motion off snaps.
