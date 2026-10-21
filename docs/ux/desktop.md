# Desktop widgets — UX brief (K43, session 9)
Status: v1 built (lead). Functional ✅, UX: first pass (screenshots `frontend/shots/look/sekai*/bar.png`).

## Job
Glanceable cards on the desk, under the windows: the time, this month, what plays, the weather. They are what the
desktop shows between windows, so they must be calm (Ma), honest (a missing value is a dash or no card, never a zero)
and never steal input from apps.

## References
- **SekaiPop** (Blapples/SekaiPop, `modules/sekai/desktopWidgets/`): clock as keycap digits with a day-progress bar,
  weather with hourly strip, month calendar, to-do, palette, user card, sticky notes, lyrics; every widget draggable,
  resizable and optional via "Edit Desktop".
- **KDE Plasma** desktop widgets (plasmoids on the desktop containment), **GNOME** has none (extensions only),
  **macOS Sonoma** desktop widgets (dimmed while an app is focused), **Windows 11** widgets board (a separate panel).
- **Vitreus** "Desk": a draggable sheet off the edge with timers.

## v1 (this session)
- Per output, opt-in (`desktop.enabled`, per output; the `sekai` decor recommends it), side `left|right`, each card
  switchable (`desktop.clock|calendar|media|weather`).
- Bottom layer, content-sized, no keyboard focus, input only on the media buttons.
- Cards: clock (four keys, colon in the accent, date, day progress — changes on the minute patch only, the changed
  digit drops in with a spring), calendar (week start = `clock.week_start`), now playing (hidden while nothing has a
  title; buttons disabled with the player's `can`), weather (only while the weather mod serves `now`).
- States: no daemon → cards keep the last values (Store veil semantics); no media → card absent; weather off / no
  place → card absent (the mod's own surfaces explain why).

## Later (backlog)
Drag to place and resize (SekaiPop "Edit Desktop"), to-do and notes cards (need a daemon notes/todo service), lyrics,
dim while a window is focused (macOS), multi-output placement presets, keyboard path (a desktop focus key).

## v2 — cards from mods (K46, row 120; W22-tasks)
- Any enabled mod may add cards with `desk:<name>` (`qml/desk/<name>.qml`). Desktop.qml lists them after the core cards
  (`Mods.deskCards`), one ModLoader each at the column's width, loaded only while the desk is shown (Ma). A card sets
  its own `implicitHeight`; one of height 0 takes no room and no gap (it is hidden by the column, so it watches its
  document for its lifetime rather than while visible).
- The list is rebuilt only when the card URLs change: the `mods` document also changes when a mod starts or stops running,
  and a new model would remake every card (and re-subscribe it) on each such change.
- First users: the tasks mod (docs/ux/tasks.md) — `tasks` (open count, up to seven items, tick by click, "+ Add" opens
  the panel) and `notes` (the note's first lines; hidden while empty). Shots: `mods/tasks/shots/{missing,desk,empty}-{sekai,none}.png`.
- Still keyboard-less (K43): a card ticks and opens the Stage; editing lives in the panel.
- Open: cards follow the `qml` map's key order (row 123); per-card show/hide like `desktop.<card>` for mod cards.

## v3 — order and edit mode (K48 (4), W24-desk-settings)
References: **SekaiPop** "Edit Desktop" (Super+Shift+E: a full-screen editor, drag to move, a shelf to add, Undo);
**macOS Sonoma** "Edit Widgets" (the desktop comes forward, widgets jiggle, Done); **KDE Plasma** "Enter Edit Mode"
(the desktop zooms out, a toolbar with Done); **iOS** jiggle mode; **DMS** `DesktopWidgetsTab` (a list in Settings).
- **Order** is layout (`desktop.order`, the user's and profiles', never a decor's — K45): core ids and `mod:<id>:<name>`.
  The column shows the listed cards in that order, then every card the list does not name (core first, then mods' in mod
  order), so a new mod card is never lost. `kurashi set desktop.order '[…]'` works as well as the edit mode.
- **Way in**: an "Edit" key on the column's top-right corner while the pointer is over the desk (no global action, no
  key binding needed). The desk has no keyboard focus outside edit mode (K43).
- **Edit mode**: the column moves to the top layer and holds the keyboard (exclusive) — a bottom-layer surface with
  on-demand focus would only get keys after a second click (sway, niri), and Escape must always work; done or cancelled,
  it goes back to the bottom layer with no focus, and the compositor gives the focus back to the window. A bar on top
  says what this is, with Cancel and Done, a one-line hint, and a refusal line. Every card shows: one with nothing to show
  now (no player, no weather place, an empty mod card) shows a placeholder with its name and when it shows. Cards get an
  accent outline (the focused or dragged one the focus ring), a one-time wiggle on entry (three swings, none with reduced
  motion: Ma, no endless jiggle), and their own keys: up, down, and the eye (show/hide, core cards only: mod cards have no
  switch yet — backlog). A hidden card stays in place dimmed with a "Hidden" chip (words, not dimming alone).
- **Pointer**: drag a card anywhere (it follows the pointer and the others make room — Column move transition); clicks
  never reach the card's own keys while editing.
- **Keyboard** (WCAG 2.5.7: never drag-only): the first card has the focus; Up/Down move it, Alt+Up/Down move the card,
  Space hides/shows it, Tab reaches the card keys and Cancel/Done, Return is Done, Escape cancels.
- **Saving**: nothing is written while editing (the switches are staged); Done sends the order (if it changed) and the
  changed switches as ONE `apply` — one undo step. A refusal keeps edit mode open with the reason; no daemon says so.
  A layer above the user's (Nix) that sets the order: the bar says so and the move keys are off; a forced switch's eye
  is off.
- **Multi-output**: each output's desk has its own edit mode; the order is global, so the other outputs follow on Done.
- Shots: `frontend/shots/desk/{ordered,edit,edit-moved,saved}-{sekai,none}.png` (`frontend/test-desk.sh`).
- Not yet: per-card hide for mod cards (needs a key, backlog); free placement and sizes (SekaiPop); a "+" shelf for cards
  of mods that are off.
