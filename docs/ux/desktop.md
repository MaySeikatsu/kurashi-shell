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
