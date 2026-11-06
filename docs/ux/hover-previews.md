# Hover previews — UX brief (session 23, I284, I285, K92)
Status: v1. Test `frontend/test-previews.sh`, in the merge set. Reviewed on nested niri (kanso).

## Job
Rest the pointer on a window's button and see that window; rest it on a workspace and see what it holds, in column order, without going
there. The user chose last-seen stills: a picture of when you last saw it, not a live one.

## How others do it
- **KDE Plasma**, **Windows 11**: live thumbnails on hover, from the compositor's own window textures.
- **macOS**: none on hover; the Dock's App Exposé and Mission Control show them.
- **GNOME**: the Activities overview has them; the panel has none.
- **Caelestia**: live, through Hyprland's toplevel export (`modules/bar/popouts`). Other Quickshell shells were not checked for this brief.
- **niri's overview**: live, and only inside niri.
On niri 26.04 a shell has no such route: capture is whole-output (`zwlr_screencopy_manager_v1`), and `screenshot-window` always overwrites the
clipboard (measured). So: stills of the output, cropped to the windows.

## Where a tiled window stands
niri tells a tiled window's column, place and size, not where it stands: `tile_pos_in_workspace_view` is floating windows' only, and the view's
scroll and the gaps are not told. `kurashi_compositor::locate` reads them from the still: the columns' edges are a pattern with two unknowns (scroll,
gap), and the workspace's active window is on screen. Each candidate is scored by how much of its edges' length shows a step in the still, counted
rather than summed, so a line of text does not beat a window's edge. **A pattern that does not stand out gives no crop.** Never a wrong picture:
the window's preview then has its title alone, and the workspace its whole still.
Known limits: a window hidden behind a floating one, or the back of a tabbed column, is not told; both come out as whatever covered them or no crop.
On sway and Hyprland the workspace's still works, windows have no crop yet (I413).

## When it captures (rule 5)
Only while a module with previews on is out (`Watch` on `svc.previews`: the service is refcounted; no module, no capture). Then, per output:
1.2 s after its active workspace, focused window or windows change (the compositor's animations are over by then; a title change is not a reason);
and when the pointer reaches the bar (`preview.refresh`). At most one round per 1.5 s. No timer runs between changes. Skipped while locked, in the
overview, or with a card, the launcher or a peek over the windows. The picture is what the workspace last looked like when it was on screen and settled.

Nested niri (the test platform) stops redrawing after any screencopy until something damages it, `grim` included; on a TTY niri's redraws come from the vblank. The first thing to check on a real session: a window animation running when a round lands (it should not stop).

## Privacy
Pictures are files in `$XDG_RUNTIME_DIR/kurashi-previews` (tmpfs, 0700), scaled down (480 × 300 a window, 640 × 360 a workspace), gone with the window, the
last subscriber or the session. They never reach disk or the document's other readers beyond their paths. A window under niri's `block-out-from` comes out
blocked, as in any capture. Off: `modules.windows.previews`, `modules.workspaces.previews`, in each module's right-click menu. **On by default**, since the user
asked for them; a privacy-minded default is worth revisiting before a public release (I414).

## Design
- **One surface.** The Stage's peek (K35): sources `window:<id>`, `workspace:<id>`. So it grows out of the bar in the look's peek form, on any edge, with the look's
  tooltip part and the same grace; the pointer on it keeps it; a click takes it away.
- **Window.** The picture, the title, the app. "Last seen 5 min ago" when it is over a minute old (Shōjiki: this is not the window now). The drag's "Move to workspace N" stays
  the button's own small peek. Previews off: the button's title peek as before.
- **Workspace.** Its name or number; its windows side by side in niri's column order when each has a picture (I285), else the whole still with the windows' names. The workspace you are on has
  no preview: you are looking at it.

## States
- Never seen: "Not seen yet", with the title and app.
- Workspace with no windows: "Empty".
- No capture on this compositor (`available: false`): titles only, as before.
- A window closed while its peek is up: the peek loses its picture; the next rest has none.
- Locked: nothing captured; the bar is not there to hover.

## Keyboard and a11y
The peek is the pointer's. Workspaces and window buttons have no tab stop yet on a bar (I67); once they have, `PeekSource` already answers to focus. The pictures are `Accessible.ignored`: the lines say it.

## Motion
The peek's form (`motion.form.peek.*`). Reduce motion as any peek. Pictures are not animated.

## Budget
A round: one output copy, a crop and a PNG per window on screen. Not yet measured on the 1060; I404's measurements should add it (a screencopy has a GPU readback). Between rounds: nothing.

## Definition of done
Crops are exact on nested niri (colours in the suite). The clipboard is untouched. Off leaves no process, file or timer.
