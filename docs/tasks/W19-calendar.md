# Card W19-calendar — calendar day marks, week start, week numbers, slot setup states (I46; rows 71, 72)

**Decision (lead, session 7; on main):** row 71 — slot `clock.expanded.daymark`: the month grid instantiates each
contribution once per visible day cell with the required property `date` (`yyyy-mm-dd`); a mark is at most 14 × 14 px
under the day number; up to three contributions side by side. Row 72 — a `runtime.slots` entry may carry `reason` (an
i18n key) while its mod says the contribution needs setup; the host hands `reason` to the contribution, which shows a
call to action. Schema keys `clock.week_start` (`auto` | `monday` | `sunday` | `saturday`; auto: Sunday for ja, Monday
otherwise) and `clock.week_numbers` (bool). See COMPOSITION §3, PROTOCOL `runtime.slots`, MODS.md.
**Briefs:** `docs/ux/island.md` (clock view), `docs/ux/weather.md` ("Clock view integration"), `docs/ux/COMPOSITION.md`.

**Read first:** `docs/tasks/README.md` (rules), rows 71–72 in `docs/CONTRACT-CHANGE.md`, I46 in `docs/BACKLOG.md`,
`frontend/components/expanded/ClockView.qml`, `frontend/components/SlotHost.qml`, `frontend/core/ModLoader.qml`,
`mods/weather/qml/slots/clock.expanded.aside.qml`, `mods/weather/qml/Weather.js` (read: `mod.weather.days`),
`crates/kurashi-mock/src/{state,documents}.rs` (`runtime.slots`), `crates/kurashid/tests/data/mods/hello/`,
`frontend/test-stage.sh` (clock view steps).

**Owned paths:** `frontend/components/expanded/ClockView.qml`, `frontend/components/SlotHost.qml`,
`frontend/core/ModLoader.qml` (only to pass `date`/`reason` when declared), `crates/kurashi-mock/**`,
`mods/weather/qml/slots/**` (the aside and a new `clock.expanded.daymark.qml`), `mods/weather/mod.toml` (add
`slot:clock.expanded.daymark`), `crates/kurashid/tests/data/mods/hello/{qml/slots/**,live.mod.toml,mod.toml}` (a
hello day mark), `frontend/test-stage.sh`, `frontend/shots/island/**`, `i18n/{en,ja}/frontend.toml` (append a block
marked `# W19-calendar`). Not yours: `frontend/surfaces/Bar.qml` (W19-side-bars), `crates/kurashi-mod-weather/**` and
the rest of `mods/weather/qml/` (W19-weather), `crates/kurashid/src/**` (the daemon side of rows 71–72 is on main).

**Do:**
1. **Day marks:** ClockView hosts `clock.expanded.daymark` per visible cell (only while the view is shown; no objects
   when no mod contributes); weather's day mark shows the forecast glyph for the dates `mod.weather.days` covers and
   nothing for other dates; hello draws a dot on one fixed date (test).
2. **Week start and numbers:** the grid follows `clock.week_start` (auto by the UI language) and shows ISO week
   numbers when `clock.week_numbers` is on; keyboard navigation (arrows, Home/End, PgUp/PgDn) still lands on the right
   days.
3. **Needs setup:** SlotHost passes `reason` to contributions that declare it; weather's aside with a reason shows "No
   place set" + "Set place" (opens Settings on the weather place key, `settings.open {key}`), never an empty box. Fix the
   aside's last line sitting on the box edge (I82).
4. **Mock parity:** `runtime.slots` entries for a daymark contribution and a `reason` the test can set
   (`mock.doc` from W18 works for it), the schema keys in the mock's config.

**Acceptance:** `timeout 900 frontend/test-stage.sh` green with new clock shots: day marks (weather + hello), week
starting Sunday (ja) and Monday, week numbers on, the aside with a reason, keyboard on the grid; `cargo test -p
kurashi-mock`, clippy on it; `just mods-live` green (the weather and hello day marks load through the real daemon); no
QML warnings.
