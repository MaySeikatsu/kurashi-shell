# Card W15-quick-island-polish — UX review 1 polish for quick settings and the island

**Briefs (govern):** `docs/ux/quick-settings.md`, `docs/ux/island.md`; lead review notes in those files ("Lead review 1").
**Items:** I51 tile on-state (tonal container: accent at low alpha + accent icon, not a solid crimson fill); I52 one tile
size contract for `quick.tiles` contributions (160×56, glyph/label/subtitle props, document it in COMPOSITION.md §5 as a
proposal row in CONTRACT-CHANGE); I45 VolumeFace shows `detail.volume` ("Headphones · 40 %") when the daemon gives one;
I12 the volume slider's accessible name while audio is available; I44 expanded views for the `power` and `bluetooth`
faces (Stage maps them to the quick settings Power and Bluetooth pages instead of the generic card); B14 quick settings
open on the output of the current pointer/focus (re-pick `stageScreen` for quick too; the old binding loop's root cause
was fixed in W11 — verify with `frontend/test-stage.sh`'s keyboard step, no loop warning).

**Read first:** `docs/tasks/README.md`, both briefs, `frontend/components/{QuickPanel,QuickButton,Slider}.qml`,
`frontend/components/quick/**`, `frontend/components/faces/VolumeFace.qml`, `frontend/surfaces/Stage.qml` (views map),
`frontend/shell.qml` (`want`, `stageScreen`), `frontend/test-{quick-sections,stage,volume}.sh`.

**Owned paths:** `frontend/components/QuickPanel.qml`, `frontend/components/QuickButton.qml`, `frontend/components/Slider.qml`,
`frontend/components/quick/**`, `frontend/components/faces/VolumeFace.qml`, `frontend/surfaces/Stage.qml` (the `views`
map and `expandedFaces` only), `frontend/shell.qml` (`want`/`stageScreen` only), `frontend/test-{quick-sections,stage,volume}.sh`,
`i18n/{en,ja}/island.toml` (append one block marked `# W15-polish`). Not the daemon, not mods.
**Acceptance:** the three test scripts green in the sandbox (machine B: `KURASHI_RENDER_NODE=/dev/dri/renderD129`);
screenshots: tiles with 0/1/3 active, VolumeFace with a device detail, power and bluetooth faces' expanded views,
quick settings opened on the second output of a two-output sandbox; `just golden` (refs `tools/golden/ref-machine-b`)
— if the bar changed on purpose, say which shots and why (the lead re-records). Read every shot critically.
