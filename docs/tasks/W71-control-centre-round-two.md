# W71-control-centre-round-two — the user's answers on the control centre, built (I475)

Model: Opus (frontend, many small UX judgements). Common rules: `docs/tasks/README.md`.
Branch `feat/s27-control-round-two`, based on `origin/main`. Build dir:
`CARGO_TARGET_DIR=$HOME/.cache/kurashi-agents-target/w71`.

## Goal
`docs/BACKLOG.md` I475 (the user's answers of 2026-11-10 to PR #38), on top of W70 (K121,
`docs/ux/control-centre-modules.md`, `docs/tasks/W70-control-centre-modules.md`). Read the brief and I475 first; revise
the brief with what you build. The user's words decide; where they leave room, choose and list the choice under
"questions for the user".

## Stages (each its own commit; stop at the end of a finished stage rather than leave one half done)
a. **Click opens a card, for every control module.** Wi-Fi, Bluetooth, power and brightness do; now focus, mic, keep
   awake, night light, dark mode and airplane too: the card is the control's page (its switch, its options from the
   schema, its reason when inert). A control with no page yet gets one (`frontend/components/quick/`): small, complete,
   keyboard reachable. A per-module override keeps "click switches" possible (the module's menu, a schema row).
   Esc on a card a module opened closes the card (it went back to the tiles before).
b. **Glances with values.** Wi-Fi shows the network's name, sound its level (and mute), beside the icon, elided to fit
   the bar; hover opens the card as `bar.hover` says (the bar's shared default, the module's override).
c. **One sound module.** `audio` (mute, card, wheel) and `volume` (slider) become one module with both; a config that
   names either keeps working (the old id maps to the new one, said in the schema's help), `kurashi_layout`'s lists and
   the fixtures stay valid; B71 (the wheel's `acceptedDevices`) goes with it.
d. **Levels and the session row as tiles.** The volume and brightness sliders and the session row become entries of
   `quick.tiles` (wide tiles), there by default, movable and removable in the centre's edit mode, and pinnable to a bar
   as modules.
e. **The phone is an advanced setting.** `quick.style = phone` is offered only with advanced settings on (the schema's
   advanced flag, as other rows use it); the looks whose decor asks for the phone open as the card (CONTRACT-CHANGE 712:
   the dead decor key: write what should happen to it, do not edit `crates/kurashi-theme`).
f. **The recorder.** A bar module that is always there (a button), whose hover or click opens a recorder surface:
   start/stop, what is recorded (screen, region, window as the daemon offers), microphone on/off, the running time
   while recording, where the file goes, the last recording. Brief first (a section in the brief: how GNOME, KDE
   Spectacle, COSMIC, macOS's toolbar, Windows' Snipping Tool, Caelestia, DankMaterialShell do it; states incl. no
   portal, no permission, recording, error; keyboard; a11y), then build against what the daemon's recorder service
   already offers; what it lacks goes to CONTRACT-CHANGE.
g. **The sidebar** (I474): `TogglesSection.qml` reads the controls and `quick.tiles`; a sidebar section can be a single
   control module.

Also in reach, if a stage touches them: B70 (the `drawFamily` binding loop), B72 (`ownKey` narrowed to the module that
opened the page), B73 (PhoneFrame a Loader in card style; an unknown tile id is a problem with its reason; Bluetooth's
switch while unavailable), B74 (suite steps for the keyboard on a bar module and the forced state; a press-and-hold for
`tools/bench/wl_pointer.py` so drag re-sort is tested), B75 (look the other shells up for the brief's "Others").

## Owned paths
`frontend/components/quick/**`, `frontend/components/modules/**` (the control modules, `Volume.qml`, `Quick.qml`,
`ModuleHost.qml` only for the hover/click branch), `frontend/components/QuickPanel.qml`, `frontend/components/sidebar/TogglesSection.qml`,
`frontend/surfaces/Stage.qml` (the quick card's lines only), `frontend/test-quick-modules.sh`,
`frontend/test-quick-sections.sh`, `crates/kurashi-schema/src/v1.rs` (the `quick.*` and module rows only; regenerate the
goldens and `i18n/en/schema.toml`, write `i18n/ja/schema.toml` by hand), `crates/kurashi-layout/**` (module lists),
`i18n/{en,ja}/quick.toml`, `tools/bench/wl_pointer.py` (press-and-hold), `docs/ux/control-centre-modules.md`.

**Not yours** (the lead edits them in parallel): `frontend/components/SoftShadow.qml`, `SheetShadow.qml`, `Block.qml`,
`RoundBox.qml`, `island/MorphShape.qml`, `bar/**`, `frontend/surfaces/Bar.qml`, `frontend/components/motion/**`,
`frontend/shaders/**`, `crates/kurashi-theme/**`, `crates/kurashi-motion/**`, `settings/**`, `docs/DECISIONS.md`,
`docs/BACKLOG.md`, `docs/PROGRESS.md`, `docs/HANDOVER.md`.

## Frozen
`crates/kurashi-ipc`, `fixtures/ipc/`, `docs/PROTOCOL.md`, `crates/kurashi-core`. Needs outside → a row in
`docs/CONTRACT-CHANGE.md` (numbers from 713 up) and a local stand-in.

## Acceptance
- `frontend/test-quick-modules.sh` and `frontend/test-quick-sections.sh` extended for every stage (mock or real daemon as
  they are now; condition waits; motion off): each module's click opens its card and Esc closes it; the override
  switches instead; the glance shows a name and a level; one sound module, an old config with `audio` or `volume` still
  places it; the levels and the session row move and leave in edit mode; the phone is not offered without advanced
  settings; the recorder's surface opens, starts and stops (mock); the sidebar follows `quick.tiles`; idle 0 frames; no
  QML error or warning.
- Screenshots on nested niri (`tools/bench/niri-sandbox.sh`; ONE sandbox at a time, name it `w71`; stop it when done and
  remove `/tmp/kurashi-sb-*w71*` dirs you made, B77), light and dark, in the report: the bar with glances, each new card,
  the recorder's surface in its states, edit mode with the wide tiles, the sidebar.
- `just check` green; `tools/test-suites.sh quick-modules quick-sections stage bar-hover module-menu sidebar-panel` green
  (a failure alone counts). Do not run more than one suite runner at a time: the lead runs suites too.

## Token thrift
Read: this card, `docs/tasks/README.md`, `CLAUDE.md`, the brief, I475/I474 and B70–B75 in the backlog, W70's card, the
files you change. Terse report in the README's format with "questions for the user".
