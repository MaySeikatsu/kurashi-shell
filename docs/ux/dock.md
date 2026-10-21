# App dock — UX brief (K51, card W25-dock)
Status: v1 built (W25-dock). Shots `frontend/shots/dock/<decor>/*.png`; test `frontend/test-dock.sh`.

## Job
Start the apps you keep and get back to the ones that run, from one edge, without a bar's window list per workspace.
It must cost nothing while it is off or hidden (Ma, K41: opt-in, per output), never cover a fullscreen window, and tell
the truth about what runs (a dot per window, the focused one lit; an app without a desktop entry still shows).

## References (what was taken)
- **macOS Dock**: pinned apps then running ones (a separator between), a dot per running app, click = bring the app
  forward, right-click menu ("Keep in Dock", "Quit"), autohide by touching the edge, magnify on hover (optional).
  The reveal is a short delay on the edge; the dock hides when the pointer leaves.
- **Windows 11 taskbar**: grouped by app, click cycles the app's windows, middle-click = new window, the focused app's
  indicator wider/lit; tooltips with the name; "Pin to taskbar" / "Unpin" / "Close window" / "Close all windows".
- **GNOME dash** (overview): favourites then running, a dot per window (up to four), click = most recent window,
  again = next; middle = new window; right = "Add to/Remove from Favourites", "Quit".
- **KDE task manager** (icons-only): grouped, cycling on click, middle-click new instance, "Pin to Task Manager".
- **DMS** `Modules/Dock/DockAppButton.qml`: `handleLeftClick` — no window → launch the entry; one → focus; more →
  `cycleGroupedToplevels()` (index of the focused one + 1, mod n); middle = launch; right = the context menu; up to
  four indicator dots. Copied: the cycle rule and the dot count cap.
- **DMS** `Modules/Dock/DockContextMenuBase.qml`: the context menu is an overlay over the whole output while open, a
  press outside closes it. Copied: a popup of a layer surface without keyboard gets no keys (measured), the overlay does.
- **Noctalia** `Modules/Dock/Dock.qml`: peek area + `showTimer`/`hideTimer`, hide only when neither the dock, an app,
  nor the peek area is hovered. Copied: one "pointer inside" truth fed by every part, timers re-checking on fire.
- **ii** `modules/ii/dock/Dock.qml`: `reveal` also while no window is active (an empty desk has nothing to cover).
  Copied: the dock shows while the output's workspace has no windows.
- **Ours** `mods/webdock/qml/surfaces/dock.qml` (K40): a 4 px edge window with a 2 px hover zone along the whole edge
  (`mask` = the zone), 250 ms reveal, 400 ms hide. Copied for the autohide edge.

## v1
- Per output while `dock.enabled` there; `dock.edge` bottom | left | right. Pinned (`dock.pinned`, desktop ids) in
  order, then — while `dock.show_running` — running apps that are not pinned, in first-window order. A thin rule
  separates the two groups when both exist.
- Windows from `svc.workspaces.windows` (every window, `{id, app_id, workspace, output, focused}`), grouped by app:
  an app's desktop entry is `DesktopEntries.heuristicLookup(app_id)` (the bar's lookup); a pinned id matches a window
  whose entry id or app id equals it (case-insensitive).
- Tile = a `Block` (decor chrome: keycap tiles, soft glass pill, line boxes) of `dock.icon_size`; the dock body is a
  Block too. Under each tile: one dot per window (max 4), the focused one in the accent and wider (focus not by colour
  alone). Hover: the tile lifts (a light fill); with `Theme.springOn` the icon magnifies 1.15 with the theme spring.
- Tooltip: the entry's name (or the app id) in a popup over the tile after 400 ms of hover, click-through.
- Click: no window → `launcher.launch {id}`; windows → focus the app's most recent one (the last one seen focused,
  else the first); again (the app already focused) → the next of its windows (DMS cycle). Middle: launch (new window).
  Right: a menu over the tile (an overlay on the output while open, DMS; the tile stays lit): the app's name, then
  "Pin to dock" / "Unpin from dock" (one `cfg.apply` of the whole `dock.pinned` list; inert with the reason while the
  list is forced), "New window" (inert without a desktop entry), "Close window" / "Close n windows" (`window.close {id}`
  each). A press outside or Escape closes it; a left click on the dock while it is open only closes it. A rejected write
  changes nothing in the dock (no optimistic pin, Shōjiki) and the menu shows `dock.error.write` — once Store passes an
  `err` reply to an `apply` callback (it drops it today; backlog).
- Autohide (`dock.autohide`): a 4 px edge window (2 px input zone) along the edge; a rest of 250 ms reveals, the dock
  hides 400 ms after the pointer left the edge, the dock and the menu. Also shown while the output's active workspace
  is empty (ii) and while its menu is open. Exclusive zone only when autohide is off.
- Layer `top`: a fullscreen window covers it (niri and sway draw fullscreen over the top layer), so it never covers
  a fullscreen window — nor does its edge zone receive the pointer there.
- Placement: the usable area (`ExclusionMode.Normal`), so a bar on the same edge stays outside it.

## States
| State | What shows |
|---|---|
| off (`dock.enabled` false on the output) | no surface at all, no subscription |
| empty (nothing pinned, nothing runs) | a small body with one hint tile ("Right-click an app to keep it here") — never a 0-px dock |
| only pinned | the pinned tiles, no dots, no separator |
| many apps | tiles shrink to fit the output (min 24 px), past that the list scrolls (wheel) inside the body |
| urgent window | not in the document yet (CONTRACT-CHANGE row 160 asks for `urgent`); no faked state |
| no desktop entry | the app id's first letter on the tile, the app id as the name; Pin is offered (a desktop id may exist) |
| daemon away | last state, dimmed (`Theme.staleOpacity`), clicks refused by Store |
| multi-output | one dock per output where enabled; each shows every app (the windows of all outputs), like macOS/Windows |

## Keyboard and a11y
Every tile is `Accessible.Button` with the app's name and its window count in the description. The menu takes the
keyboard while open (Up/Down move, Return/Enter/Space run, Escape closes). The dock itself takes no keyboard focus (it
must never steal it from the app); a key to focus the dock waits for the bindings work (backlog).

## Motion
Reveal/hide: the body slides from the edge by its thickness (`Theme.stdMs`, enter curve), then the window unmaps
(0 frames hidden). Magnify on hover only while `Theme.springOn`; no idle animation, no timer while nothing is hovered.

## Ma / budget
No surface while off; hidden = one 4 px transparent edge window per output; the dock window is made on the first show
and kept (unmapped while hidden). Measured (`DOCK_MEASURE=1 frontend/test-dock.sh`, docs/BENCH.md "Mods"): 0 commits in
10 s hidden and shown; +6.9 MiB USS with the dock on and hidden (one output, with the component load), +2.2 MiB on the
first show. The tooltip and the menu exist only while shown.

## Later (backlog)
Drag to reorder pins (DMS long-press drag), window previews in the tooltip (needs screencopy per window), urgent
bounce (needs `urgent`), a launcher tile, per-output "only this output's windows", focus key.
