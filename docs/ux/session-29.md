# Session 29 — UX brief: smooth openings, one line, Bridge, shaped sheets
Status: built in one session (2026-11-11) from the user's bug report (eleven screenshots); seen on nested niri by the
lead as bursts and read as pixels; **the user has judged none of it in motion**. The web dock's part has its own
sections in `docs/ux/webdock.md` ("Background pages", "The card's size", "Which place shows the page").

## 1. Openings that do not stutter (K135)
**Job.** "Spawn animations of surfaces feel and look stuttery … like low frame rate", with "barely load".
**What was wrong, measured.** (a) With music playing the colour flow redrew every window at the display's rate: the
shell at 125 % of a core (B99). (b) A motion form's first frames were its slowest and fell inside the motion (B90).
(c) A bar redrew its rule on every frame of a neighbour's growing fillets, and cut it over the neighbour's whole span
before anything stood there (B109). (d) A closing sidebar's window shrank and drew one frame out of place (B103).
(e) The month grid filled in cell by cell after the rest (B108).
**Others.** GNOME Shell and KWin draw a popup's content once into a texture and animate that; Android and iOS hold a
transition until the first frame of the new surface is drawn ("starting window", `UIViewPropertyAnimator` after
layout); Caelestia and DankMaterialShell keep their panels loaded and animate a clip. None animates a surface that is
still being made.
**Design.** The colour clock steps and rests while a surface moves; a form warms up before it travels
(`docs/ux/motion-engine.md` "Warm start"); the rule is cut once, when the form covers it; the grid is made with its view.
**States.** Reduced motion and profile None: nothing changes (no form, no wait). A form that fails to load, a window
that never shows a frame: the travel starts after 300 ms as before. A toggle back during the wait: the surface stays.
**Budget.** Idle unchanged (0 frames; the clock is a Timer only while the flow's moment is there). An opening moves two
frames later. Latency before that is B101 and B102 (the user's call).
**Definition of done.** Every moving frame of a sidebar's opening within one frame time on the user's machine, both
monitors, music playing: **not proven** (nested niri only). The shell's CPU with music playing read again on the live
session after a rebuild: **owed**.

## 2. One line round the screen (K136)
**Job.** "Cards don't follow outline color"; "curves look disconnected … like there is a pixel missing"; stepped
corners that break "depending on the monitor".
**Design.** A surface's line is the frame's line wherever the frame draws one. A rule runs under the tail of each
fillet that joins it. Corner shapes are drawn as insets of one contour, so an outline keeps its width round a stair, a
cut and an outward quarter.
**Definition of done.** Read as pixels at 16× on nested niri: round, cut, steps, outward quarter and square at radii
20, 25 and 31, a card on its bar, a pinned sidebar on the bar and the frame: met. Fractional scale and the user's two
monitors: not seen.

## 3. Bridge (K137)
**Job.** The keycap and soft chrome's small bridges as a choice of "Cards join their bar", not baked into the chrome.
**Others.** Material's attached menus hang flush; macOS menu-bar extras hang a card by a small arrow (a neck); GNOME's
popovers the same; Noctalia and end-4 join by fillets (our Dynamic).
**Design.** A fifth choice, Bridge. On blocks it is the keycap's own. On a strip the card stands `max(8, gap)` off the
bar and the neck hangs from the strip's edge under the module; the island's pill stays in the bar.
**Keyboard and a11y.** Unchanged: the card's focus and names are its content's.
**Definition of done.** Seen under line, flat, keycap and soft on a bottom bar: met. Top and side bars, the launcher,
toasts, peeks, the Settings picture looked at in Settings: not (I491).

## 4. Shaped sheets (K136 (4), I489 (3))
**Job.** The corner shape on every sheet, not only the joined ones.
**Design.** A sheet of its own (the floating card, a sidebar's section, the notification centre, toasts) takes the
shape; blocks inside a card keep their rounding until the user decides (I492).
**Definition of done.** The floating card and a sidebar section at steps, cut, outward quarter and square: met. Toasts
and the notification centre: built, not shot.
