# Timer and pomodoro — UX brief (K73; card W43-timer)
Status: agreed (lead, session 14, user point 16)

## Job
Start a countdown or a pomodoro in two keystrokes or one click, see it run without looking for it, and be told —
once, clearly — when it ends, even with every view closed. The first module that ships every variant (K72): bar/edge
glance, peek, expanded card, desk card, sidebar panel, island face (a live activity), quick tile.

## References (cited)
- **end-4 ii** (`modules/ii/sidebarRight/pomodoro/`): pomodoro in the right sidebar's bottom tabs (focus 25, break 5,
  long break 15 every 4), start/pause/reset, a ring; notifications at phase ends. Taken: the cycle and its defaults,
  the sidebar place. **GNOME Clocks** timers: several named timers, presets, "+1 min" while running, an alarm sound.
  **macOS** Clock timers in the Dynamic Island / menu bar (Live Activity: remaining time compact, ring minimal).
  **Android** Clock: timer notification with +1 min / pause / stop. **KDE** Timer plasmoid: presets, title. **Noctalia
  / DMS**: pomodoro widgets in the bar with the remaining time and a ring.
- **Ours**: the island's live activities (island.md "Beyond" 2), the media position interpolation (`(position, rate,
  timestamp)`), notifications (K22 server) for the end.

## Beyond the basic job
Several timers at once (a tea timer while a pomodoro runs: the island's secondary glyph, island.md "Beyond" 1); the
pomodoro's focus phase can turn on Do Not Disturb (a setting, off by default) and off again at the break; the
calendar's agenda could later offer "focus until the next event" (BACKLOG).

## Design
- **State (daemon, `mod.timer`):** `timers: [{id, kind: countdown|pomodoro, label, phase: focus|short_break|
  long_break (pomodoro), round, rounds, duration_ms, running, ends_at_ms (running) | remaining_ms (paused)}]`, plus
  `presets`. Actions: `timer.start {minutes?, label?}` (default the last preset), `timer.pomodoro.start`,
  `timer.pause {id}`, `timer.resume {id}`, `timer.add {id, minutes}` (+1 min), `timer.skip {id}` (pomodoro: next
  phase), `timer.stop {id}`, `timer.stop_all`. One deadline in the daemon (the earliest end) while any timer runs;
  none otherwise. The end: a notification (title from the label or the phase, body "Time is up" / "Break — 5 min",
  actions *+1 min*, *Stop*, *Next phase*), an island transient face, and for a pomodoro the next phase starts by
  itself (setting `auto_advance`, default on).
- **Glance (`widget:timer`):** the nearest end — a small ring + `mm:ss` (≥ 1 h: `h:mm`), the phase's glyph for a
  pomodoro; idle: a timer glyph only (click = start the default preset). Scroll: ±1 min on the nearest timer.
- **Peek (`peek:timer`):** each timer's label, remaining time and end clock time ("ends 14:25").
- **Expanded / sidebar (`panel:timer`):** the running timers (ring, label, remaining, pause/resume, +1 min, stop) over
  a preset row (5, 10, 25 min, the user's own `presets`), a custom field (`mm` or `mm:ss`, Enter starts), the pomodoro
  card (phase, round n of 4, start/pause/skip/reset).
- **Desk card (`desk:timer`):** the pomodoro ring large with its phase and round, or the nearest countdown; idle: the
  presets.
- **Island face (`island-face:timer`):** a live activity while a timer runs: ring + remaining; relevance below media
  playing and above the clock; its end is a transient with the TTL. `:expanded` = the panel.
- **Quick tile (`slot:quick.tiles`):** "Timer" — on while one runs (subtitle: remaining), tap = start/pause the
  nearest, page = the panel.
- **Settings (mod settings):** `presets` (minutes list, default 5, 10, 25), `focus_minutes` 25, `short_break_minutes`
  5, `long_break_minutes` 15, `rounds` 4, `auto_advance` true, `focus_dnd` false, `sound` true (the notification's
  sound hint).
- **Ticking:** views interpolate from `ends_at_ms` and redraw at 1 Hz only while a running countdown is visible;
  under reduce motion the ring steps without easing.

## States
idle (no timers) · one countdown running / paused · several (nearest first) · pomodoro in each phase · end (transient +
notification) while the bar is hidden / the screen is locked (the notification waits; the lock shows nothing
private) · daemon restart (running timers survive: state in `~/.local/state/kurashi/timer.json`, ends that passed while
down fire once on start with "ended at 14:25") · DND on (the notification follows DND; the island
transient still shows) · ja copy · 1 h+ timers.

## Keyboard + a11y
Panel: Tab through presets, the custom field (Enter starts), each timer's buttons; Space pauses the focused timer.
Accessible names say the remaining time ("Tea, 4 minutes 12 seconds left"); the ring is never the only cue (text).

## Fit and constraints
Rule 1: all time logic in the daemon; views interpolate. Ma: no timer runs, nothing wakes; a visible running countdown
costs 1 frame/s. Budget: mod `loaded, off` ~0; `on` + idle ≤ 1 MiB; daemon wakeups only at deadlines. Contracts: mod
manifest provides, `mod.timer` doc (MODS.md §mod documents), actions `timer.*`.

## Definition of done
- [ ] start / pause / resume / +1 min / skip / stop from the panel, the CLI (`kurashi act timer.start '{"minutes":5}'`)
      and the glance
- [ ] the end fires with every view closed (no subscriber), and after a daemon restart
- [ ] every variant drawn: glance (bar and edge module), peek, panel (Stage and sidebar), desk card, island live face,
      quick tile — shots under washi and sekai, light + dark, ja
- [ ] idle: 0 frames, no daemon timer; running + hidden: 0 frames
- [ ] `cargo test -p kurashi-mod-timer` covers phase advance, pause arithmetic, restart recovery

## Later
Stopwatch · alarms at a clock time · "focus until the next event" · sounds of our own — BACKLOG rows.
