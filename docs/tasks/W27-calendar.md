# Card W27-calendar — calendar events mod (roadmap v0.2 "calendar"; the clock card's "No calendar is connected")

**User (session 10):** "as complete and usable as possible … take actual code from DMS, Noctalia, Caelestia, ii if they
solved it." Efficient: QML prototypes with placeholder events first, the crate in one go, few compiles.

**References (copy what solves it, note the source):** DMS `…/scratchpad/insp/DankMaterialShell/quickshell/Services/{CalendarService,CalendarKhalBackend,CalendarDankBackend}.qml`
(and its Go side under `…/DankMaterialShell/core/` — grep `calendar`/`ics`); shellseikatsu
`~/Documents/projects/quickshell/shellseikatsu/Services/CalendarService.qml`. (`…/scratchpad` =
`/tmp/claude-1000/-home-maike-Projects-kurashi-shell/dbcea378-a7d4-4c51-ac59-ac9689ce0b5f/scratchpad`.)

**Read first:** `CLAUDE.md`; DECISIONS K26/K28 (native mods, slots), K46 (`desk:`), K47; `docs/MODS.md`; templates:
the weather mod (`mods/weather`, `crates/kurashi-mod-weather`: slots `clock.expanded.aside` and `clock.expanded.daymark`,
network capability, background jobs) and the tasks mod (`crates/kurashi-mod-tasks`: files, watches); the clock card
(`frontend/components/expanded/ClockView.qml`) and the desk (`frontend/surfaces/Desktop.qml`, `desk:` cards).

**Owned paths:** new `crates/kurashi-mod-calendar/**`, new `mods/calendar/**`, the workspace members line, one
dependency + one registration line in kurashid, `i18n/{en,ja}/mod-calendar.toml`, `docs/ux/calendar.md` (UX brief
first: GNOME Calendar/Shell, KDE, macOS, Windows, DMS, Noctalia; states: no source, offline, a feed that fails, all-day,
multi-day, recurring, time zones, today/now line, empty day), a test script `mods/calendar/test-calendar.sh`. Contract
rows ≥ 200. Sandbox names `w27-cal-`. **Not yours:** core surfaces (use the slots and `desk:`), the compositor, the
launcher.

**Do:**
1. Sources (mod settings): local `.ics` files/folders (vdirsyncer/khal storage dirs work as folders of `.ics`), ICS URLs
   (Google/Proton/Nextcloud "secret address" — network capability, refresh interval, cached copy used offline), and
   optionally `khal list` when khal is installed (DMS backend). Parse with an ICS crate if one is in Cargo.lock, else
   a careful small parser: VEVENT, DTSTART/DTEND with TZID + VTIMEZONE (or the `chrono-tz` names), all-day DATE,
   RRULE (DAILY/WEEKLY/MONTHLY/YEARLY with INTERVAL, COUNT, UNTIL, BYDAY; EXDATE), SUMMARY, LOCATION.
2. Document `mod.calendar`: `{state, sources:[{name, state, reason?}], days: {"YYYY-MM-DD": [{id, title, start, end,
   all_day, location?, calendar, color?}]}}` for a window (today −7 … +42 days), recomputed at midnight and on change;
   no per-minute churn (the views compute "now"/"in 10 min").
3. Views: `slot:clock.expanded.aside` = the selected day's agenda in the clock card (beside the weather's aside, the
   slot takes several mods); `slot:clock.expanded.daymark` = a dot per day with events; a desk card (`desk:agenda`:
   today + next events); a bar widget (next event in N min, hidden when none); an island face is optional (a 10-minute
   "next meeting" peek, behind a setting).
4. Ma: refresh jobs only while the mod is on; file watches only while the document is watched.

**Acceptance:** crate tests (ICS fixtures: timezone, all-day, multi-day, RRULE weekly with EXDATE, malformed),
clippy; `mods/calendar/test-calendar.sh` (real kurashid, fixture `.ics` folder + a fixture HTTP feed) with shots of the
clock card agenda, day dots, desk card, bar widget under `sekai` and `none`. Report (terse).
