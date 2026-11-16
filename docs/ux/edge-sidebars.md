# Sidebars on the top and bottom edges — UX brief (I607, K165)
Status: v1 built in session 36 (`frontend/surfaces/SidebarSheet.qml`); the definition of done below says what is met.
Source: the user, session 36 — "I also want to add sidebars on the top and bottom of the screen, they could maybe
have different size options, but the shown one from the terminal could be one option, so that it has a full width
option and an option that shows it just over 2/3 of the screen or however large that surface is."

## Job
The side sidebars hold "the rest of the shell" as a tall column. Some things want to be **wide and low** instead: a
terminal, a web page, the wallpaper pictures, a notes page next to a task list. A sidebar on the top or the bottom edge
is that: a sheet that comes out of the edge, as wide as the user says, and holds the same sections and mod panels the
side ones do. It is the terminal's drop-down made general — the same place, the same join, the same sizes — so that
whatever the user likes to have "down there" opens the way the terminal does.

## Others
Looked up on 2026-11-16 (every fact with its source in `docs/ux/edge-sidebars.research.md`; what could not be confirmed
is listed there as such — GNOME, macOS and Windows document no width, height or closing rule for their panels).
- **Caelestia** (Quickshell): a dashboard anchored to the **top** edge and a launcher to the **bottom** edge, both
  centred; they open on hover into the edge zone (a gate per drawer) or by a drag past a threshold, and close when
  the pointer leaves unless a key opened them. One instance per screen.
  https://github.com/caelestia-dots/shell/blob/main/modules/drawers/Panels.qml
- **Noctalia**: every panel is *attached* (against the bar's inward edge, borderless on that side, a layer surface of
  its own) or *floating* (8 px off the edge by default); with two bars on one edge the attachment is ambiguous and
  needs a named anchor bar. Width is a setting (the control centre: 700 px, 600–1200); no panel has a height key.
  https://docs.noctalia.dev/noctalia/v5.4.1/configuration/shell/
- **DankMaterialShell**: popouts "are anchored to the bar and slide out accordingly", on whichever edge the bar is.
  https://duxlabs.dev/docs/dms/layers
- **COSMIC**: panels on any edge; with "Extend panel to screen edges" off a panel "shrinks in width and hugs the
  content, which will be centered"; gap and extend are separate switches; corners at the screen boundary are square.
  https://github.com/pop-os/cosmic-epoch/issues/102
- **KDE Plasma 6**: panels on any edge; 6.0 replaced "Windows Can Cover" with "Dodge Windows", and users miss having
  the clock and tray stay visible. https://community.kde.org/Plasma/Plasma_6
- **Drop-down terminals**: Yakuake defaults to 90 % of the width and 50 % of the height, on the screen that holds the
  pointer, and stays open when the focus leaves (https://lxr.kde.org/source/utilities/yakuake/app/config/yakuake.kcfg);
  Guake: 100 % × 50 %, hiding on focus loss only when asked; ddterm could not give a real width for years — "one of
  the window's dimensions still takes full screen size" (https://github.com/ddterm/gnome-shell-extension-ddterm/issues/129).
- **GNOME, macOS, Windows 11**: no general top or bottom drawer. Their top-edge panels (quick settings, Control
  Centre) hang from the bar's corner at a fixed size; Windows' Widgets board comes from the side.

**Taken.** One sheet type with an edge and a width mode (Caelestia, COSMIC: full, or a centred part); attached to the
bar on its edge, the look's card where there is none (Noctalia's two kinds, chosen by what stands on the edge, not by
a setting); width and height as shares of the screen (the drop-down terminals), with the terminal sheet's own numbers;
click outside and Esc close it, said in the brief (most shells do not document theirs); the screen is the one that
asked, else the focused one (Yakuake's pointer screen is our focused output). **Not taken.** Hover at the edge as the
way in (Caelestia's default for the dashboard): the edge already reveals a hidden bar and the edge modules, and a
sheet half the screen tall that opens by accident is worse than a key. A height the content decides (Noctalia): a
sheet that changes height with its page moves under the pointer.

## Design
- **Where.** `sidebar.top` and `sidebar.bottom`. Each exists only while it has sections (`sidebar.<edge>.sections`,
  empty by default): a shell that does not use them has no window, no key and no command for them.
- **What it holds.** The sections the side sidebars offer and the mods' panels, **one page each with tabs** (the left
  sidebar's layout). A wide sheet with every section stacked in one column would be a narrow column in a wide box; pages
  use the width. Side-by-side columns are "Later".
- **Size.** *Width* (`sidebar.<edge>.span`): **a part of the edge, centred** (default) or **the whole edge**. A part is
  66 % of the screen's width (`sidebar.<edge>.length`, 30–100, Advanced). The whole edge stops at what stands on the
  left and right edges (a side bar, the frame's band). *Height* (`sidebar.<edge>.height`, 20–95 % of the screen, default
  45, Advanced): the terminal sheet's default, so the two look alike. A panel that can fill a height is handed it
  (`fillHeight`, as in the left sidebar).
- **How it meets the bar.** On an edge with a bar or the frame's band the sheet hangs from it and is one sheet with it
  (JoinedCard: the fillets of the bar's cards, in the bar's material). On a bare edge it is the look's card, flush to
  the edge. It never covers its bar: it starts where the bar ends.
- **Opening.** `sidebar.toggle {side: "top" | "bottom", output?}`, `sidebar.open`, and the commands `> Top sidebar` /
  `> Bottom sidebar` (`sidebar.top.toggle`, `sidebar.bottom.toggle`). No default key: the user binds one (Settings ›
  Keys lists the actions). Without sections the action is refused with the reason the left sidebar gives
  ("no sections"). One at a time with the Stage's cards, the launcher and the other sidebars; it opens on the output
  that asked, else the focused one, and stays there while open.
- **Closing.** Esc, the same toggle, a click outside it, `sidebar.close`, `ui.close`, anything else that opens.
- **Not in v1** (and why): pinning with reserved space (a pinned top sheet would push every window down by half the
  screen: it needs a "narrow strip" size first); hover at the edge (the edge already reveals a hidden bar and the edge
  modules there); a bar button (the bar's ends belong to the side sidebars; a module for it is a small follow-up).

## States
closed (no window) · opening / closing (the slide out of the edge; cut when motion is off) · open · no sections (no
sidebar: the action is refused and says why) · a section whose mod is off or not loaded (its tab is skipped; with none
left the column says which and why, with the way to the setting — the left sidebar's own empty state) · daemon away
(the Store's veil) · a narrow output (the part is never under 30 % of the width; the sheet never exceeds the output) ·
two outputs (one sheet, on the asking output) · a top sheet on an output whose bar is at the bottom (it hangs from the
bare top edge as the look's card; the bottom one joins the bar).

## Keyboard and a11y
The sheet takes the keyboard on demand when it opens. Tab walks the tabs and the page; Ctrl+PageUp / Ctrl+PageDown
switch pages (the left sidebar's keys); Esc closes. Every tab is a Tab stop with its name; the page's controls bring
their own names. State is never colour alone (the chosen tab carries the tab bar's mark).

## Motion
The sheet slides out of its edge over the standard duration on the enter curve and back on the continuous one — the
terminal sheet's motion. Motion off (profile none, reduce motion): a cut. Idle open: 0 frames.

## Multi-output
One window, on the asking output. A per-output bar edge is honoured (the sheet reads `runtime.layout` for its output).

## Fit and budget
Island / Stage: exclusive with the Stage's cards and the launcher (the daemon's `runtime.ui.sidebar`). Sidebars: the
same sections, the same tab column (`LeftColumn`), the same open-on-output rule (`OpenOn`). Terminal: the same geometry
and frame (`SheetGeom`, `SheetFrame`) — the terminal's sheet stays the terminal mod's own surface. Settings: page
Sidebar, sections "Top sidebar" and "Bottom sidebar"; the share and the height are Advanced.
Budget: closed = no window and no subscription; open = one layer window plus a click-away window; its sections watch
their documents only while it is open.

## Definition of done
- [x] a top sheet under a top bar joins it; on a bare edge (the bottom, with the bar on top) it is the look's card. Not seen: a bottom sheet under a bottom bar
- [x] part (66 %) and full widths, at the default height (other heights not looked at)
- [x] a mod panel (Tasks) and core sections (Calendar, Notifications) show as pages; a panel that fills the height is not checked
- [ ] Esc, the toggle and a click outside close it; closed = no window
- [ ] refused without sections, with the reason
- [x] seen on nested niri in light and dark (the default look)
- [ ] a suite: opens, the page is drawn, closes, no window after (not built yet if unticked)

## Later
Side-by-side columns in a wide sheet · a strip size that can be pinned and reserves space · "as wide as what it holds"
(a panel's own width) · a bar module that opens it · a swipe from the edge · the terminal's sheet as a section of it.
