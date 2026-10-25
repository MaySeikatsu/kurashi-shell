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
- Not yet (v3): free placement and sizes (SekaiPop); a "+" shelf for cards of mods that are off. Per-card hide for mod
  cards came in v4.

## v4 — hidden cards for every card, titles, order, the Edit key (W36; K65 `desktop.hidden`; I136, I119)
- **Hidden.** Every card has an eye in edit mode (Space on the card or on its eye does the same). A core card's eye writes
  its own switch (`desktop.<card>`, the one Settings shows). A mod card has no switch, so its eye writes `desktop.hidden`
  (K65). The desk leaves out a card whose switch is off or whose id is listed in `desktop.hidden` (a core id may be listed
  by hand too). Done writes the order, the switches and the list as ONE apply: one undo puts all of it back; Escape writes
  nothing.
- **Hidden, shown in place.** A hidden card takes no room outside edit mode, and it is not made: a mod card's documents are
  not watched (Ma). In edit mode it keeps its place, with a "Hidden" chip (words, not dimming alone): dimmed content when
  it has some, else its placeholder, which says when it shows.
- **Set above the user (Shōjiki).** When a layer above the user (Nix) forces a card's switch, or the list for a mod card,
  that card's eye is off, and the edit bar says why in words: "Some of these are set above your config (Nix): their eyes
  are off."
- **Titles.** A mod card's name (placeholder, accessible name) is `mod-<id>.desk.<name>` in en and ja (the tasks mod:
  "Tasks" / "タスク", "Note" / "メモ", in `i18n/*/mod-tasks.toml`). Without a key it is the manifest name, followed by the
  card's name when that differs from the mod's id. A card with content draws its own caption, which the mod translates.
- **Order.** A mod's cards follow the manifest's `provides` order, which the mods document carries. The `qml` map is sorted
  by key, so it cannot give the order; the note used to sit above the list.
- **Edit key.** On hover, above the first card: its bottom sits 2 px above the keycaps, which start at the card's padding, so
  it covers no content (it used to cover the clock's last digit). The first card sits 28 px under the bar; where the key
  is taller (sekai) 36 px, so the key keeps 8 px from the bar.
- **Keyboard.** In edit mode the cards' own controls (the tasks checkbox, "+ Add") are out of the Tab order: each card's
  keys are the stops (up, down, eye). Space toggles, Alt+Up/Down moves, Up/Down move the focus. Return is Done from a card;
  from a focused card key Return presses that key (the Button convention), so Done is also a Tab stop, and Escape always
  cancels.
- **Shots:** `frontend/shots/desk/{ordered,hover,edit,edit-moved,saved,hidden-edit,hidden-desk,forced-edit,offline-edit,ja-hover,ja-edit}-{sekai,none}.png`
  (`frontend/test-desk.sh`). `forced-edit`: a value forced by `managed.toml` (the eye is off, the bar says why);
  `offline-edit`: kurashid stopped, Done refused, the bar says the save did not happen.
- **Definition of done (v4, W36).** Met, by `frontend/test-desk.sh` (16 checks, both decors) or the shots named above:
  hide and show for every card, staged, one apply, one undo; hidden cards left out of the desk and "Hidden" in edit mode;
  Tab to a card's eye and Space (the clock and the tasks card are driven; the other cards use the same key chain); Escape
  writes nothing; Return is Done from a card; titles in en and ja; the order of a mod's cards is the manifest's; the Edit
  key clear of the digits; a forced value shows its eye off and the reason in words; a refused save says so.
  Not met, or not checked: the eyes of the other four cards are not driven by a test; ThemeExportStatus's `~` change has
  code only (no test or shot); the hidden mod card's loader is not made outside edit mode by construction (Ma), not
  measured; the screen-reader names are in the code, not checked with a reader; no multi-output run; no all-hidden desk shot.
- **Not yet:** Return on a focused card key presses that key, not Done (the shared Button and IconButton take Return first;
  fixing it means a change in `components/`); titles of third-party mods (contract row 397); the `provides` order as a
  documented contract (row 396).
