# Card W37-calendar — the calendar widget opens the agenda; event details; the agenda's day (K66; I140, rows 200, 203, 205)

**Why:** I140's open rows. K66 accepted `island.expand {face}` (W37-daemon builds it in parallel) and the
`clock.expanded.day` slot's `extra: {date}`.

**Read first:** `CLAUDE.md`; `docs/tasks/README.md`; `docs/ux/calendar.md`; DECISIONS K66; CONTRACT-CHANGE rows 200, 203,
205; BACKLOG I140; `mods/calendar/**` (mod.toml, qml, test-calendar.sh), `frontend/components/SlotHost.qml`,
`frontend/components/expanded/ClockView.qml` (`agendaHost`, the day marks' `extra`).

**Task:**
1. **Row 200:** SlotHost gains an `extra` property merged into each ModLoader's; ClockView passes `{date: <yyyy-MM-dd of
   sel>}` to `clock.expanded.day`; the calendar agenda reads `extra.date` and drops the parent walk.
2. **Row 203:** the bar widget sends `island.expand {face: "clock"}` (the daemon side lands in parallel; until then the
   daemon ignores the extra arg — check with `just mock` once W37-daemon's mock parity merges, or note it).
3. **Event details:** activating an agenda event (click, Enter) opens a popover in the card: title, time range (all-day,
   multi-day), location, description (plain text, links not clickable unless trivially safe), the calendar's colour;
   Escape closes; a11y names.
4. **Row 205:** move `mods.running.calendar_peek` to `i18n/{en,ja}/mods.toml` beside `mods.running.rain_alerts`.
5. Shots: agenda with the popover (light/dark, en/ja), all-day and multi-day events, empty day; the bar widget opening the
   clock card while media is current (if the daemon half is not merged yet, shoot with the mock and say so).

**Owned paths:** `mods/calendar/**`, `crates/kurashi-mod-calendar/**` (only if the popover needs a field the doc lacks —
then report it), `frontend/components/SlotHost.qml`, `frontend/components/expanded/ClockView.qml`, `i18n/{en,ja}/{mod-calendar,
mods}.toml`, `docs/ux/calendar.md`.

**Acceptance:** `bash mods/calendar/test-calendar.sh` with the new steps and shots.

**Contract rows:** CONTRACT-CHANGE rows 410–414 only.

**Env:** `CARGO_TARGET_DIR=$HOME/.cache/kurashi-agents-target/w37-calendar CARGO_BUILD_JOBS=4`; sandbox names `w37-cal-…`.
Model: haiku (max effort).
