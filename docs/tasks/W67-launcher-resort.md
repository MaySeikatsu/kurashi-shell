# W67-launcher-resort — results that rearrange while you type (I424)

Model: Opus (motion judgement on a hot path). Branch `feat/s26-launcher-resort`. Common rules: `docs/tasks/README.md`.
Build dir: `CARGO_TARGET_DIR=$HOME/.cache/kurashi-agents-target/w67`.

## Goal
`docs/BACKLOG.md` I424, confirmed by the user 2026-11-07 and asked for again 2026-11-09: while typing in the launcher the
results **sort and redraw as Caelestia's do** — rows that stay slide to their new places, rows that are new come in, rows
that drop out leave — instead of the list being replaced on every keystroke.

Today: `frontend/surfaces/Launcher.qml` keeps `property var results: []` and replaces the whole array on each reply
(`lp.results = items || []`, ~line 331), so every delegate is made again. Wanted:
- A keyed model: diff each new result list against the shown one by a stable key (the result's id: desktop id for apps,
  the action/command/clip id otherwise — read the result shapes the daemon sends; `kind` + id). Apply moves, inserts and
  removes to a `ListModel` (or equivalent) so surviving delegates are kept.
- Motion from the theme (DESIGN-SYSTEM §9, `docs/ux/motion.md`): `move`/`displaced` slide on the theme's curve and
  duration, `add` fades/slides in, `remove` fades out; all off under reduced motion (Theme's reduce flag) and at
  `Theme.springOn == false` if that is the shell's convention. A fast typist must never see rows pile up: interruptible
  transitions, no queue.
- Selection follows its item by key when it survives a re-sort (not the index), else the first selectable row — today's
  `settle()` rule.
- Grid mode (start apps grid, `cols`) and list mode both. Keygroup rows stay unselectable.
- Ma: no animation or timer while the launcher is hidden; the model is cleared on hide as today.
- How Caelestia does it: read `caelestia-dots/shell` `modules/launcher/` (AppList / the list's `move`/`add` transitions)
  for the feel; cite what you took in the brief section below. No code copied.
- Add a short section "Results while typing" to `docs/ux/launcher.md` (states, motion, reduced motion, a11y: the
  accessible selection follows the item).

## Owned paths
`frontend/surfaces/Launcher.qml`, `frontend/components/launcher/**`, `docs/ux/launcher.md`, `frontend/test-launcher.sh`.

## Frozen
`crates/kurashi-ipc`, `fixtures/ipc/`, `docs/PROTOCOL.md`, the daemon (`crates/kurashi-launcher` is read-only: the result
shape is a contract). Needs outside → `docs/CONTRACT-CHANGE.md`.

## Acceptance
- `frontend/test-launcher.sh` gets steps (condition waits, motion off except where motion is under test): type `fi`, then
  `fir`: a row present in both keeps its delegate (log its object id or a creation counter under a test env flag) and
  ends at its new index; the selection stays on the same item when it survives; a fast burst of 8 keystrokes ends with
  the right final list and no stale rows.
- Seen on nested niri (`tools/bench/niri-sandbox.sh`): a short screen recording or frame sequence of a re-sort, paths in
  the report.
- `just suites --changed` green (failures re-run alone), `just check` green. Never start anything on the user's display.

## Report
The README's report format.
