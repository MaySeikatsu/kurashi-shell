# The bar's window list — UX brief (session 9 K44, card W36-bar; I102, I131, I137)
Status: v1 (W36). Shots `frontend/shots/tasks/<scheme>/*.png`; test `frontend/test-tasks.sh`. (The card named
`docs/ux/tasks.md`, which is the to-do mod's brief, K46; this is the window list's own.)

## Job
Show the windows of the workspace in front of you, one icon each, and let you reach, close or move one without the
compositor's overview: on every bar edge, at a glance, honest about which window is focused and which asks for
attention — and silent while nothing changes.

## How others do it
- **GNOME** (dash in the overview; the "Window List" extension at the bottom): one button per window with icon and title,
  middle-click closes (extension), drag a window onto a workspace thumbnail moves it (overview), urgent windows pulse.
- **KDE Plasma task manager**: icons-only or with titles; hover shows a tooltip with the title and a live thumbnail;
  middle-click closes (configurable), drag onto the pager moves, demands-attention flashes the button orange a few times,
  then stays highlighted; a vertical panel stacks the buttons.
- **Windows 11 taskbar**: hover = thumbnail with the title; middle-click opens a new instance (not close); a window that
  wants attention flashes, then keeps an orange bar under its icon until focused.
- **macOS Dock**: bounces an app that needs attention (once, or until handled for critical requests); no per-window list.
- **COSMIC** (app list applet): icons with window dots, middle-click new window, drag between workspaces in the workspace
  overview.
- **Quickshell shells**: Caelestia and end-4 keep a workspace strip with app icons; DankMaterialShell's `RunningApps`
  widget lists windows with an icon, middle-click closes, the title in a tooltip and an icon fallback chain
  (desktop entry → app id as icon name → a letter). Noctalia's taskbar marks urgent windows in the error colour.
- **HyprPanel**: a "taskbar" per workspace in the workspace module, icons from a mapping table, no title.

**Taken:** KDE's flash-then-steady urgency (here a short hop, then a steady mark), DMS's middle-click close and icon
chain (plus StartupWMClass), KDE's drag onto the pager, the title in a hover peek (no thumbnails: they need screencopy per
window). **Not taken:** titles in the bar (they churn: a browser retitles on every page), grouping by app (the dock does
that), middle-click = new window (Windows; the dock has New window).

## Design
- One button per window of the output's active workspace (`svc.workspaces.tasks`), in id order, after the workspaces —
  in a row on a top or bottom bar, in a column under the workspaces on a left or right bar. Square, `barH − 12`.
- Icon: the desktop entry (`DesktopEntries.heuristicLookup`, then an entry whose `StartupWMClass` equals the app id,
  case-insensitive), its icon; else an icon named after the app id (as is, lower case, the last part of a reverse-DNS
  id); else the app's first letter; a window without an app id gets a generic window symbol. Never blank.
- Focused: the selected fill plus a short mark under (beside, on a side bar) the icon — not colour alone.
- Click focuses (`window.focus`). Middle-click closes (`window.close`). Drag onto a workspace chip moves the window there
  (`window.move`; the chip under the pointer is ringed while dragging; the view follows the window, as niri's bind does).
  Right-click opens a menu: the title, "Focus", "Move to workspace N" for each other workspace of the output,
  "Close window".
- Peek: after 400 ms of rest the window's title (fetched then with `window.title`; never in the document) and the app's
  name, in a small card beside the button (below a top bar, above a bottom one, beside a side bar), click-through. While
  dragging, the peek says "Move to workspace N".
- Urgent (`urgent`): when a window starts asking, its button hops three times (≈ 0.7 s, the theme's spring), then keeps a
  steady dot in the warning colour at its corner until the window stops asking; "needs attention" in its name.
- Overflow: buttons up to the island (row) or down to the island (column); the rest as one "+N" chip whose name says how
  many windows are not shown.
- Side bars (I131): the keyboard layout chip (the layout's short name, ≤ 3 letters) and the recording mark (the red dot
  over "REC") sit in the side bar's lower column before the clock and count in its fit like every other item.

## States
| State | What shows |
|---|---|
| empty (no window on the workspace) | no buttons and no group block; the workspaces stand alone |
| one / several | the buttons; the focused one lit and marked |
| many (more than fit) | the leading buttons and "+N" (name: "N more windows") |
| no desktop entry / no icon | the icon by app id, else the first letter; no app id: the window symbol |
| urgent | hop (only with `motion.spring.on`; none otherwise), then the steady dot; name says "needs attention" |
| title missing | the peek says "Untitled window" |
| title request fails / window gone | the peek says "This window is gone." |
| action refused | the menu shows "That did not work. Try again." (Shōjiki: nothing changes optimistically) |
| daemon away | the bar's veil (last state, dimmed); clicks are refused by Store |
| multi-output | each bar shows its own output's active workspace (`tasks.<output>`) |

## Keyboard and a11y
Every button is `Accessible.Button` named after the app (with ", focused" / ", needs attention") and described by the
gestures. The bar takes no keyboard focus (it must never steal it); the menu does while open (an overlay with exclusive
keyboard, as the dock's): Up/Down move, Return/Enter/Space run, Escape closes — that is the keyboard path to close and
move. A key that opens the window list waits for the bindings work (backlog, as the dock's focus key).

## Motion
The hop is the only animation and runs once per urgency start, gated on the bar's visibility and `Theme.springOn`
(reduced motion = no hop, the dot at once). The drag ghost follows the pointer; nothing else moves; no idle frames.

## Fit, Ma, budget
Rule 1: the list is the daemon's (`tasks`); the frontend lays it out and sends actions. No polling: the title is fetched
once per peek. The peek and the menu exist only while shown. Idle: 0 frames (no timers but the 400 ms peek intent while
the pointer rests on a button).

## Definition of done
`bash frontend/test-tasks.sh` green with shots in light and dark: row and column, empty, many (+N), no icon (letter and
window symbol), StartupWMClass match, urgent (hop then dot), peek, menu, drag-to-workspace, middle-click close; side bar
with the layout chip and REC dot (geometry asserted); `cargo test -p kurashid workspaces`; strings in en and ja.

## Later (backlog)
Thumbnails in the peek (screencopy per window), a focus key for the list, reorder by drag (niri column order), the list
of all workspaces (per-output option), grouping windows of one app.
