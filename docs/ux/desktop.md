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
