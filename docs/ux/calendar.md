# Calendar — UX brief (card W27-calendar, roadmap v0.2 "calendar")
Status: v2. v1 is W27; W37 adds the event details, the agenda's day from the host and the bar widget's face (the rows
below marked W37). Functional and UX tracked separately in PROGRESS.

## Job
"What is on today, and what is next?" — answered where the user already looks: the clock card's agenda (the
selected day), a dot under each day of the month grid that has events, a desk card (today and the next events),
and a quiet bar widget that appears only when something starts soon. The shell **reads** calendars the user already
has (files, a sync tool's folder, a feed address, khal); it does not edit them (v1) and never hides that a feed is
old or failing (Shōjiki).

## How others do it
- **GNOME Shell date menu**: month grid with a dot under days that have events, a list of the selected day's events
  ("All day" first, then times), "No Events" for an empty day; data from Evolution Data Server (online accounts).
  GNOME Calendar: month/week views, calendars coloured, a "Calendars" menu to toggle sources, offline = cached.
- **KDE Plasma digital clock**: the popup's month view with event dots and an agenda beside it (PIM events plugin,
  holidays plugin), per-calendar colour bars; "No events for this day".
- **macOS**: menu-bar clock opens Notification Center; the Calendar widget "Up Next" shows the next event with its
  calendar's colour bar, "No more events today" and tomorrow's first; all-day events as a band on top.
- **Windows**: the Windows 10 taskbar flyout had an agenda under the month ("No events"); Windows 11 dropped it and
  points to Outlook / the widget board ("Outlook Calendar" widget: today's list, time left column).
- **DankMaterialShell** (`Services/CalendarService.qml`, `CalendarKhalBackend.qml`, `CalendarDankBackend.qml`): khal
  (`khal list --json …` over the visible month, `khal printformats` to learn the date format) or its own calendar
  daemon; per-calendar colours with a fallback palette; multi-day events copied into every day they touch, clamped to
  that day (`_clampForDay`). Dots in its dash calendar, the selected day's list beside it.
- **Noctalia**: calendar panel with events from Evolution Data Server through a helper script; dots on event days.
- **Caelestia / end-4 (ii)**: a month calendar in the dashboard/sidebar, no events of their own.
- **shellseikatsu** (`Services/CalendarService.qml`): `khal list --json title --json start-date …` over 50 days;
  copes with three khal JSON shapes (flat array, per-day arrays, one document per line).

**Taken:** GNOME/KDE's grid dots + selected-day agenda; macOS's "Up Next" shape for the desk card (next event big,
then the rest of today, then tomorrow) and its colour bar; DMS's khal command and multi-day split; shellseikatsu's
tolerant khal JSON reading; DMS's fallback palette idea (here: the theme's accent when the calendar has no colour).
**Not taken (v1):** editing/creating events, invitations/RSVP, reminders as notifications (the optional island peek
covers "soon"), week view, CalDAV login (vdirsyncer/khal do it; a feed's secret address covers Google/Proton/Nextcloud).

## Sources (mod settings)
- `sources`: records `{name, location, color, enabled}`. `location` is a `.ics` file, a folder of `.ics` files (two
  levels deep: a vdirsyncer/khal storage folder of calendars), or a feed address (`https://`, `http://`, `webcal://`).
  `name` labels the calendar; empty → the feed's `X-WR-CALNAME`, else the file or folder name.
- `khal` (bool): add `khal list` when khal is installed; absent khal → the source says so, nothing breaks.
- `refresh` (min, 5–1440, default 30): how often a feed is fetched while the mod runs. The last good copy is kept in
  `$XDG_CACHE_HOME/kurashi/calendar/` and used offline — with its age shown.
- `peek` (bool, default off) and `peek_minutes` (1–60, default 10): the island peeks "Standup in 10 min".
- The feed address is a secret: the `mod.calendar` document never repeats it (only the name and the state).

## Document `mod.calendar`
`{available, state, reason?, today, from, to, sources:[{name, kind, state, reason?, events, color?, fetched_at?}],
days: {"YYYY-MM-DD": [{id, title, start, end, all_day, location?, description? (W37, row 410), calendar, color?}]}}` for today −7 … +42 days,
recomputed on a source change, a settings change and local midnight — **never per minute**: `start`/`end` are unix
seconds and the views compute "now", "in 10 min", "ends 14:00" themselves while visible. All-day events carry the
local midnights (end exclusive). A multi-day event is listed on every day it touches (DMS). `state`: `none` (no source
set: reason `mod-calendar.no_source`), `loading` (first pass), `ready`, `error` (every source failed and nothing is
cached). Source `state`: `ready`, `loading`, `missing`, `offline` (a feed that cannot be reached: cached copy in use
when `fetched_at` is set), `error` (unreadable / not a calendar / HTTP status), `unavailable` (khal not installed).

## States (views)
- **No source**: the clock agenda's slot says "No calendar connected" with "Add a calendar" (opens the mod's
  settings); no dots; the desk card shows the same call to action; the bar widget is absent.
- **Loading**: the agenda says "Loading calendars…" (no empty-day text before the first pass).
- **Empty day**: "Nothing scheduled" (GNOME "No Events"), the dots elsewhere still help.
- **Offline / feed fails**: events from the cached copy, and a one-line note "Work: offline · copy from 2 h ago" or
  "Work: can't be read" under the agenda/desk card (never silent). A source without a copy contributes nothing.
- **All-day**: listed first with "All day" in place of a time; a band (no time column) on the desk card.
- **Multi-day**: on each day; the time column reads "until 14:00" / "from 22:00" / "All day" for middle days.
- **Recurring**: expanded by the daemon (RRULE DAILY/WEEKLY/MONTHLY/YEARLY, INTERVAL, COUNT, UNTIL, BYDAY,
  BYMONTHDAY, BYMONTH, BYSETPOS; EXDATE, RDATE, moved instances via RECURRENCE-ID; cancelled ones dropped).
- **Time zones**: TZID by IANA name (system tzdb, a bundled copy as fallback), else the file's VTIMEZONE, else local;
  all times shown in the session's local time.
- **Today / now**: in the agenda, past events of today are dimmed, the running one is marked "now" in the accent,
  and a thin now-line sits between past and future (the view's minute timer, only while shown).

## Views
- `slot:clock.expanded.day` — the selected day's agenda in the clock card (the card names this slot for the agenda;
  the card text said `aside`, which is 140 px and the weather's). Up to 6 rows `colour bar · time · title · location`,
  "+ N more". The selected day is the host's `date` (CONTRACT-CHANGE row 200, W37: the clock card passes its selection on every
  change), today when none is given. A row is a button: it opens the event's details (below).
- `slot:clock.expanded.daymark` — one dot per day with events (the colour of the first event's calendar).
- `desk:agenda` — "Up Next" card: the next (or running) event large with "in 25 min" / "now · until 11:00", then the
  rest of today and tomorrow's first events, max 6 rows; empty → "Nothing else today".
- `widget:calendar` — bar: an event icon and "Standup · 12 min" while the next timed event starts within an hour (or
  runs now: "Standup · now"); absent otherwise (Ma: nothing shown, nothing drawn). Click (or Return, Enter, Space) opens the clock card on its agenda: `island.expand {face: "clock"}` (W37, row 203), so
  the agenda shows while another face, such as media, is current. Until W37-daemon's `face` is on main, the daemon ignores
  the argument and the card opens on the current face; row 411 decides what an open card does with it.
- `island-face:calendar` (optional, `peek`): transient peek at T − `peek_minutes`.

## Event details (W37)
A row's event opens in the card: the details take the place of the day's list (a drill-down, as the quick settings
drill down; the island card has no room beside the list, and an overlay would be cut by the card's morph). Back returns
to the list, with the focus on the row.
- **Shows**: the calendar's colour bar and name (the colour is never the only sign); the title ("(No title)" when
  empty); the span, in the clock card's day format: "Thu 14 Oct · 09:15–09:30", "Thu 14 Oct · All day", "Sat 2 Aug – Tue
  5 Aug · All day" (an all-day end is exclusive, so the span ends on its last day), "Thu 14 Oct 22:00 – Fri 15 Oct
  02:00" (timed, over a night); "Now · " in the accent while it runs; the location; the description as plain text, eight
  lines at most, then elided (a link in it is text, not a button).
- **Absent, not blank**: no location or description line when the event has none (row 410: khal events and events
  without DESCRIPTION carry none); no colour bar's colour when the calendar has none (the accent stands in).
- **Closes**: Escape or Back returns to the list. A change of day closes it, and so does a refresh that drops the event,
  so it never shows an event for another day or one that was cancelled (Shōjiki).
- **Motion**: none of its own; the swap is at once and the card's morph is the only motion.
- **Read only**: no editing in v1, so Back is the only button.
- Not re-researched for W37: the earlier "How others do it" notes stand. Event editors (GNOME Calendar) and calendar
  apps (macOS, Outlook's widget) are the other shells' answers; neither fits a card, so the details stay read-only here.

## Keyboard + a11y
Rows are buttons (`Accessible.Button`; Tab reaches each, Return, Enter or Space opens its details) named "09:00–10:00, Standup, Room 4, Work"; the widget is a button ("Next event:
Standup in 12 minutes"); colour is never the only signal (the calendar name is in the accessible name, the time text
says "now"). Desk cards take no focus (K43).

## Motion, multi-output, budgets
No animation of its own; the minute timers run only while a view is visible. Every output's desk/bar shows the same
document. Daemon: file watches (inotify) only while `mod.calendar` is subscribed; feed fetches at most every
`refresh` while the service runs, or for the peek job while `peek` is on; khal at most once per pass (pass = change,
midnight, refresh). Idle with nothing subscribed and peek off: 0 wakeups.

## Definition of done
Crate tests: timezone, all-day, multi-day, weekly RRULE with EXDATE, malformed input, recurrence override, feed cache
offline. `mods/calendar/test-calendar.sh` on the real kurashid with a fixture folder + a fixture HTTP feed: clock card
agenda, day dots, desk card, bar widget under `sekai` and `none`; no QML warnings from the mod.
W37 adds to it: the keyboard steps of `test-calendar.sh` (an all-day and a timed row's details; Escape out of the
details, then out of the card; a multi-day all-day and a multi-day timed event; an empty day; tomorrow, which proves the
agenda follows the selected day), the `description` in the document (row 410), the dark scheme and Japanese once. The
widget's click with media current is not shot: no MPRIS player in the sandbox, and row 411 decides an open card's face.
