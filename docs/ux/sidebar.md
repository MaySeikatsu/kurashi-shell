# Sidebars — UX brief (card W29-sidebar)
Status: v1 built (W29-sidebar). Test `frontend/test-sidebar-panel.sh`; shots `frontend/shots/sidebar/<decor>/*.png`.

## Job
A tall column at a screen edge that holds "the rest of the shell" in one glance, without stacking popups: on the right
the machine (who I am, the switches, the levels, what came in, the month, what plays); on the left the tools I talk to
(the AI chat, tasks, lyrics — mod panels as tabs). It reaches from the bar to the far edge (or edge to edge when no
bar sits on that side), it is one surface while open and **no surface at all while closed** (Ma), and it is a core
surface of its own — the web dock (mod `webdock`) stays what it is.

## References (research 2026-10-21; what was taken)
- **end-4 illogical-impulse** (`~/.config/quickshell/ii/modules/ii/sidebarRight/SidebarRight.qml`,
  `SidebarRightContent.qml`, `sidebarLeft/SidebarLeft.qml`): a `PanelWindow` anchored top+bottom+side with
  `exclusiveZone: 0` — the compositor stops it at the bar, no arithmetic of our own; content loaded only while open;
  Esc on the content hides it; header row (avatar, uptime, settings/lock/power), quick toggles, sliders (volume,
  brightness, mic), a centre group (notifications | volume mixer tabs) that takes the free height, a bottom group
  (calendar | todo | pomodoro tabs). Left: a tab bar over AI chat / translator panes. Keys `Super+N` / `Super+A`.
  Taken: the anchors and zone, load-while-open, the section order, "the list takes the free height", left = tabs.
  Not taken: the Hyprland focus grab (not on niri), the always-on IpcHandler state in the frontend (rule 1: the
  daemon owns which sidebar is open).
- **shellseikatsu** (`docs/BUGS.md`): its sidebar subtracted `barMargin + barH` from its own height and offset `y`
  assuming a horizontal bar — wrong under a side bar and when the bar sat on the sidebar's side; its window ate the
  desktop's clicks until it got an input mask; it rendered behind a bar on the same side. Avoided here by letting the
  compositor place it (exclusive zone 0 respects the bar's zone on every side) and by masking input to the column.
- **macOS Notification Center**: slides in from the right under the menu bar, full height, widgets above the
  notifications; Esc or a click away closes it. Taken: the slide from the edge, full height below the bar.
- **Windows 11**: `Win+N` = notifications + calendar on the right, `Win+A` = quick settings; the Widgets board slides
  from the left. Taken: right = notifications + calendar + switches, left = a board of panels.
- **GNOME 46 / KDE Plasma 6 / COSMIC**: no edge sidebar — a date-menu dropdown with notifications + calendar (GNOME),
  tray popups (KDE), applet popups (COSMIC). Their quick settings are our quick card; the sidebar does not replace it.
- **Caelestia / DankMaterialShell / Noctalia / HyprPanel**: dashboards and control centres drop from the bar as
  cards; DMS and Noctalia keep notifications in their own popout. Taken: "Open from the bar" as an option, not the
  default — the quick card stays the bar button's default.

## Design
- `sidebar.style` — **Panel** (default): flush to its side, outer corners square, the two inner corners rounded by
  `radius.lg`, fill `Theme.panel` (translucent/glass per material, blurred where the compositor can), outline per chrome.
  **Floating**: the same column inset by `space.sm` on every side, every corner rounded, the look's shadow (Block:
  keycap ring + hard shadow, soft shadow, line outline).
- `sidebar.width` 420 px (320..640). The column never exceeds the output (width clamped to the output less a gap).
- **Right** (`sidebar.right`, ordered pick list): `header` (avatar letter, user name, Settings, Lock, Session menu),
  `toggles` (the quick tiles — Wi-Fi, Bluetooth, Focus, Audio, Power saver, Keep awake, Night light, Record — and the
  `quick.tiles` mod tiles; a tile's arrow opens its quick-settings page over the column, ← / Esc back), `sliders`
  (volume, brightness when there is a backlight, microphone: mute switch and level), `notifications` (DnD switch,
  Clear all, the list — it takes the free height and scrolls inside itself), `calendar` (ClockView: month grid, the
  agenda slot when the calendar mod fills it), `media` (MediaView, only while something plays), and any loaded mod
  panel `mod:<id>:<panel>`.
- **Left** (`sidebar.left`): one tab per mod panel; the tab bar on top, the panel under it (scrolls when taller).
  A tab whose mod is not loaded or off is skipped; with none left the column says which tabs are missing and why,
  with a button to the setting (Shōjiki). Settings marks such a value "not available now".
- **Opening**: `sidebar.toggle {side, output?}` (keys `Mod+Shift+N` right, `Mod+A` left in `docs/niri-binds.kdl` —
  `Mod+N` stays the notification centre, CONTRACT row 233; the bar button with `sidebar.from_bar`),
  `sidebar.open`, `sidebar.close`. One at a time: opening a sidebar closes the island card / quick card / launcher and
  the other sidebar; opening any of those closes the sidebar (the daemon decides). The sidebar opens on the output
  that asked (`output`), else the focused one, latched while open.
- **Closing**: Esc, the same toggle, the bar button, `sidebar.close`, `ui.close`, another panel.

## States
closed (no window) · opening/closing (slide) · open · empty sections: no notifications ("No notifications"),
nothing playing (media section takes no space), no backlight (no brightness row), no audio server (level rows
unavailable with the reason), no session service (Lock hidden), locked session (notifications hidden, as the island
view) · left: every tab missing (empty state with reasons) · daemon away (Store stale veil as everywhere) · ja copy ·
720 px output (the list shrinks to its minimum, then the column scrolls).

## Keyboard + a11y
Focus on demand (layer-shell OnDemand): a click or the first key gives the column the keyboard. Tab walks the
sections top to bottom (every control is a Tab stop), the toggle grid keeps its arrows, Esc backs out of a tile page
first, then closes. Left: Ctrl+PageUp/PageDown switch tabs; the tab buttons are Tab stops with their names.
Every control has an accessible name; state is never colour alone (switch knob side, tile badge, text).

## Motion
Slides in from its edge on the theme's spring (`motion.spring.*`), out on the standard curve; `Theme.springOn` false
(motion none, reduced motion) → it appears and goes at once. Only the slide animates; idle open = 0 frames.

## Multi-output
One window, on the asking output, never one per output. A per-output bar edge is honoured (the compositor's zones).

## Fit and budget
Island / Stage: exclusive with the Stage's panels and the launcher (daemon). Quick settings: the toggles reuse the
quick tiles and pages, the card itself is unchanged (and stays the bar default). Settings: own page `sidebar`.
Budget: closed = no window, no subscription; open = one layer window (the Stage's card is closed meanwhile) — its
cost is bounded like the launcher's; every section watches its documents only while the sidebar is open.

## Definition of done
- [x] right sidebar under a top bar spans bar bottom → screen bottom; beside a left bar it spans the full height
- [x] floating style inset by the gap; panel style flush with square outer corners
- [x] left sidebar shows the AI tab (or the empty state with reasons)
- [x] Esc closes; opening the launcher closes it; closed = no window
- [x] shots: right panel + floating under washi, sekai, win95, glass; left panel under washi
- [ ] uptime in the header (row 236) · mic level slider (row 237) · mod panels that fill the pane (row 238)
- [ ] no toasts over the open right sidebar (row 234)
- [ ] click outside to close (niri has no focus grab for layer surfaces yet)
- [ ] measured: a window per open (the card's "closed = no window") vs the Stage's K16 note that map/unmap cycles
  left ~5 MiB of heap per cycle — run 20 open/close cycles and record USS in BENCH

## Later
Paper-notebook sidebar style (BACKLOG I144) · detachable left panels (ii's detach/pin) · tabs inside right sections
(ii's notifications | mixer) · a swipe from the edge.
