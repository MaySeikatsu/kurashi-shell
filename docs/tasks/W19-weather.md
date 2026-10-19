# Card W19-weather — weather panel polish that is not about colour (I82, I57; row 72)

**Decision (lead):** fix what the UX review found, except colours (those wait for the design pass with the user, I63).
Weather without a saved place uses the new slot reason (row 72, on main: `ModCtx::slot(name).set_reason`) so its clock
aside shows a call to action (the aside QML is W19-calendar's).
**Brief:** `docs/ux/weather.md` (panel, places, states, DoD).

**Read first:** `docs/tasks/README.md` (rules), I82 and I57 in `docs/BACKLOG.md`, `docs/ux/weather.md`, MODS.md
"Native mods" (slots, `ModCtx::slot`), `crates/kurashi-mod-weather/src/**`, `mods/weather/qml/{Panel,Face,FaceExpanded,
Peek}.qml`, `mods/weather/qml/Weather.js`, `mods/weather/shots/` (state shots and how they are made).

**Owned paths:** `crates/kurashi-mod-weather/**`, `mods/weather/qml/{Panel,Face,FaceExpanded,Peek}.qml`,
`mods/weather/qml/Weather.js`, new components under `mods/weather/qml/` (not `slots/`), `mods/weather/shots/**`, the
weather state-shot script(s), `i18n/{en,ja}/mod-weather.toml` (append a block marked `# W19-weather`). Not yours:
`mods/weather/qml/Widget.qml` (W19-side-bars), `mods/weather/qml/slots/**` and `mods/weather/mod.toml` (W19-calendar).

**Do:**
1. **Hourly rain:** each hour shows its chance of rain as a readable value (e.g. "30%" under the glyph when ≥ 10 %, or a
   labelled rain row) instead of unlabeled 3 px dashes; no scale-less marks.
2. **Seven days:** each day's bar sits at its own position within the week's span (min → max), so the days differ at a
   glance; today marked; values stay as text.
3. **Places preview:** a candidate shows a one-line forecast (now: glyph, temperature, condition; today's high/low)
   fetched for its coordinates through the mod (an action that answers data, cached; refused offline with a reason)
   instead of coordinates and a time zone; coordinates move to the a11y description.
4. **No place:** while no place is saved the mod sets `ctx.slot("clock.expanded.aside").set_reason(Some(
   "mod-weather.no_location"))` (and `None` once one is saved); unit-tested with a recording `Hooks`.
5. **Copy:** the credit line fits 368 px (shorter copy or two deliberate lines); the panel's states re-shot (fresh,
   aging, stale, very stale, no place, offline with/without data, loading, rate limited, ja).

**Acceptance:** `cargo test -p kurashi-mod-weather` (preview action with a fixture forecast, refused offline, slot
reason set and cleared), `cargo clippy -p kurashi-mod-weather --all-targets -- -D warnings`; the weather state-shot
script green (fixtures, no network, K37) with the re-shot states plus the hourly rain, the seven days and a places
preview; no QML warnings.
