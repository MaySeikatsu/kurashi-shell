# Card W38-polish — small visible fixes: clock grid, calendar fallback, desk Return, side-bar toasts, DND live (I203, I196, I201, I205)

**Why:** review findings from waves 36–37 (BACKLOG rows named per item).

**Read first:** `CLAUDE.md`; `docs/tasks/README.md`; BACKLOG I196, I201, I203, I205; `docs/ux/{calendar,desktop,motion}.md`;
`frontend/components/expanded/ClockView.qml`, `mods/calendar/qml/Widget.qml`, `frontend/components/{Button,IconButton}.qml`,
`frontend/surfaces/Desktop.qml`, `frontend/test-toasts.sh`, `crates/kurashid/src/` (where `notifications.dnd` is read at start).

**Task:**
1. **I203 clock grid:** with day marks on, day numbers sit at the keycap's top edge under sekai — centre them in the keycap
   face (account for the keycap's shadow inset and the marks row); a 5-row month leaves an empty sixth row above the agenda —
   collapse it (the card height follows; motion stays smooth). Shots before/after (sekai, washi, none).
2. **I203 calendar fallback:** the widget's `island.expand {face: "clock"}` falls back to `island.expand {}` when refused.
3. **I196 desk Return:** in desk edit mode Return on a focused card key means Done (the shared Button/IconButton take Return
   first — give them a way to pass it on, e.g. an `acceptsReturn` property, default unchanged everywhere else).
4. **I201 side-bar toasts:** teach `test-toasts.sh` the side-bar crop and the `toast-card` place for `left`/`right`; run
   `MORPH_CASES="washi:calm:left sekai:lively:right"`; look at the slide-in shots; fix what they show.
5. **I205 DND live:** `notifications.dnd` follows the config at runtime (not only at start), forced or not; test.

**Owned paths:** `frontend/components/expanded/ClockView.qml`, `mods/calendar/qml/Widget.qml`, `frontend/components/{Button,IconButton}.qml`,
`frontend/surfaces/Desktop.qml` (Return only), `frontend/test-toasts.sh` + its shots, `frontend/surfaces/Toasts.qml` (only if the
shots show a bug), the kurashid file(s) for DND (notifications wiring only), `frontend/test-desk.sh`, `mods/calendar/test-calendar.sh` + shots.
Not Theme.qml/Block/SoftShadow/Bar.qml (W38-shadows).

**Acceptance:** `test-toasts.sh` (side-bar cases), `test-desk.sh`, `mods/calendar/test-calendar.sh`, `cargo test -p kurashid notif` green, with shots.

**Contract rows:** CONTRACT-CHANGE rows 435–439 only.

**Env:** `CARGO_TARGET_DIR=$HOME/.cache/kurashi-agents-target/w38-polish CARGO_BUILD_JOBS=4`; sandbox names `w38-polish-…`.
Model: haiku (max effort).
