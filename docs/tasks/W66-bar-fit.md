# W66-bar-fit — a crowded bar never overlaps; its modules sit centred, sized and drawn alike (B48 + module polish)

Model: Opus (layout allocation and visual judgement). Branch `fix/s26-bar-fit`. Common rules: `docs/tasks/README.md`.
Build dir: `CARGO_TARGET_DIR=$HOME/.cache/kurashi-agents-target/w66`.

## Goal
1. **B48, zones overlap** (`docs/BACKLOG.md` B48; user screenshot: a long window title in the start zone runs under the
   battery/CPU/RAM/temperature modules after it, toward the centre). Cause found by the lead: `frontend/components/bar/ZoneRow.qml:107`
   gives a host `room` from where it stands to the next zone, ignoring its own zone's modules after it; the end zone has no
   limit against the centre (`frontend/surfaces/Bar.qml` ~819–855). Wanted — **one allocation per bar row, never an overlap**:
   - fixed modules take their natural width; elastic ones (window title/list, media title, lyrics…) share what is left and
     elide (full text stays the accessible name and the hover peek);
   - the centre zone keeps the bar's middle while it fits; when one side would hit it, it shifts by the least amount;
   - when still too little room: modules collapse by a priority, text → icon only → into an overflow ("…" button opening the
     hidden ones in the module menu/peek, keyboard reachable). Pick the priority rule, document it.
   - Vertical bars (`ZoneColumn.qml`) already shorten values (I85): check the same overlap cannot happen there.
   - Write a short UX brief `docs/ux/bar-fit.md` first (CLAUDE.md "UX bar": GNOME/KDE panel, Waybar `max-length`, HyprPanel,
     Caelestia/Noctalia/DankMaterialShell bars, macOS menu bar's hiding of status items; states: roomy, tight, overflowing,
     one output narrow + one wide; keyboard + a11y; motion of a module collapsing; budget: no extra frames at idle (rule 5)).
2. **Module polish** (user screenshot of their live bar, session 26): some modules are not vertically/horizontally centred,
   seem off, are wrongly sized, or their icon does not resemble what it opens. Named by the user: the **control centre** and
   the **web player** (web dock) icons. Audit every bar module on one bar in nested niri (`tools/bench/niri-sandbox.sh`):
   icon optical size equal across modules, centred on the bar's midline (measure with grim + `magick … txt:`, not by eye),
   consistent spacing, and each icon a clear picture of its job (control centre = the quick-settings/sliders kind, web
   player = a play/browser glyph; the shell's icon font: see how `frontend/components/Icon.qml` picks glyphs). Modules live in
   `frontend/components/modules/`, mod widgets under `mods/*/` (their bar QML). List each change with before/after crops.

## Owned paths
`frontend/components/bar/**`, `frontend/surfaces/Bar.qml`, `frontend/components/modules/**`, the bar-widget QML of
`mods/*/` (not their daemon code), `frontend/components/Icon.qml` only if the glyph map needs entries, `docs/ux/bar-fit.md`,
i18n keys for new strings (`i18n/{en,ja}/bar.toml` or the domain's file), a new suite `frontend/test-bar-fit.sh`.
Not: `frontend/components/sidebar/**` and `frontend/surfaces/Sidebar.qml` (card W65 runs in parallel).

## Frozen
`crates/kurashi-ipc`, `fixtures/ipc/`, `docs/PROTOCOL.md`. A new config key (e.g. a per-module priority) is a schema change:
propose it in `docs/CONTRACT-CHANGE.md` and use a frontend default meanwhile.

## Acceptance
- `frontend/test-bar-fit.sh` (condition waits, motion off, see W55 in the README): a bar with a long window title + sysmon +
  many end modules at 1280 px wide → no two modules' rects intersect (read their geometry), the centre zone's middle within
  1 px of the bar's middle while it fits, an overflow appears when nothing more fits; at 1920 px nothing collapses.
- Before/after screenshots on nested niri of the user's kind of bar (start: volume, title, sysmon; centre: tasks, timer,
  weather; end: the rest, as in the screenshot) — paths in the report.
- `just suites --changed` green (failures re-run alone count), `just check` green.
- The user tests on their live session afterwards; never start anything on the real display.

## Report
The README's report format, plus the brief's definition-of-done items as met / not met.
