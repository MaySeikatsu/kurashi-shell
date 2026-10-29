# W56-corners — squircle and concentric corners on every visible shape (I288, I269)

Session 18. QML (+ one shader). Common rules: `docs/tasks/README.md`. Verify on niri (`tools/bench/niri-sandbox.sh`),
regressions with `just suites --changed`.

## Goal
1. **I288 — squircle everywhere.** One drop-in rounded box (`components/RoundBox.qml`): a plain `Rectangle` under round
   corners (no cost), `SquircleRect` under `theme.shape.corners = squircle` (it follows `Theme.squircle`, the curve's ratio,
   so the slider reaches it). Swap it in where a visible shape is drawn as a radiused Rectangle: the Stage's slide-in and
   peek cards, the phone frame, the dock tooltip and menus, chips, toggles, sliders, the Settings app's controls and cards
   (SectionCard, the framed navigation, Segmented, Button…). Invisible hit areas and clips stay Rectangles. Survey first:
   `grep -rn "radius:" frontend settings` (~140 uses) → a list in the report of swapped / left (with the reason).
2. **Relief's box (I288).** `frontend/shaders/relief.frag`'s rounded-box distance as a superellipse under squircle (same
   ratio; uniform), so a squircle corner has no unshaded sliver; recompile with `qsb` (devShell).
3. **I269 — concentric corners, the rest.** `Theme.nested(outer, inset)` for the Stage cards' views, the desk cards'
   tiles, the notification cards inside a section, and any nested control the survey finds.

## Acceptance
Shots on niri, rounded and squircle, the curve slider at 0 / 0.77 / 1, for: the island card, a peek, the phone, the dock
tooltip, quick settings (chips, toggles, sliders), a desk card, Settings (a page, the navigation). `just suites --changed`
green; idle silence unchanged (no new animations, the SquircleRect paths rebuild only on a size or curve change).
