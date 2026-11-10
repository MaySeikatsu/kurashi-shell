# W70-control-centre-modules — each control of the control centre a module of its own; the centre a container (I469)

Model: Opus (cross-cutting frontend work, many small UX judgements). Common rules: `docs/tasks/README.md`.
Branch `feat/s27-control-modules`, **based on `origin/feat/s27-desktop-posted`** (the tip of the session's stack, not
`main`: it has the open-on-hover work in `ModuleHost.qml` and `Peeks.qml` this card builds on).
Build dir: `CARGO_TARGET_DIR=$HOME/.cache/kurashi-agents-target/w70`.

## Goal
`docs/BACKLOG.md` I469 and the brief `docs/ux/control-centre-modules.md` (on the base branch; read it first, it is the
design). User, 2026-11-10, away until the morning: "Give each of the control centers sub-modules/options their own
dedicated fully thought through module that can also be pinned to the bar, sidebar etc. - so that they can be pinned to
a surface separately and one doesn't need the whole control center pinned. Also rework the style of the control center
to match the rest of the bars design. Keep the Phone one as an option that can be enabled (maybe as easteregg) but
generally clean it up and let it look more modern. Also add the options to pin custom module shortcuts to the control
center and resort them instead of just the fixed pins it has now." They asked for best-judgement builds, with the
questions collected for them afterwards, and nothing half-baked: **finish stages in order and stop at a stage's end**
rather than leaving one half done. Commit per stage; each stage leaves `just check` and the named suites green.

## Stages (the brief's "Order of work")
(a) **Extract.** Each control of `frontend/components/QuickPanel.qml` (Wi-Fi, airplane, Bluetooth, Focus, audio out,
    mic, power profile, brightness, keep awake, night light, record, dark mode) becomes a small QML type under
    `frontend/components/quick/` holding its state, its labels, its `Request` and its refusal text: one source for a
    tile, a bar glance and a card. QuickPanel uses them; no behaviour change; `frontend/test-quick-sections.sh` green.
(b) **Bar modules.** A core module per control (ids as the brief lists; `recorder`, `volume`, `keyboard` exist: reuse,
    do not duplicate): a glance (icon, and a value where one is short: battery percent, the Wi-Fi's state), a click
    that does the control's obvious thing (toggle, or open its card where a toggle would be destructive or ambiguous),
    its card (the page QuickPanel shows for it: networks, devices, sinks, profiles, schedule) and its right-click menu
    (the module menu, I408) — states: off, unavailable with its reason (Shōjiki: inert, said why), busy, error; keyboard;
    a11y names; i18n en/ja; bar fit (`docs/ux/bar-fit.md`: say whether the module is elastic and give its compact
    form); open-on-hover (`bar.hover`, K113: give each a `hoverSurface`). They must appear in the zone lists' choices
    (`choices_from = "modules"`), so Settings › Layout can add them to a bar, a sidebar or an edge group.
(c) **The container.** `quick.tiles`: the ordered list of module ids the centre shows as tiles (default: today's set
    and order), any module with a tile face allowed (mods: a `tile:<name>` provide — if that needs MODS.md/manifest
    changes, write the CONTRACT-CHANGE row and support core modules only). Add, remove and re-sort in the centre itself
    (an edit mode as the desktop widgets have: drag, and Alt+arrows by keyboard) and in Settings (the list control).
(d) **Restyle.** The centre is a card as every other (the shell's join, material, outline; tiles are `Block`s); the
    phone frame becomes `quick.style = phone`, off by default; `test-quick-sections.sh` covers both.

## Owned paths
`frontend/components/QuickPanel.qml`, `frontend/components/quick/**`, `frontend/components/QuickButton.qml`,
`frontend/components/modules/**` (new module files; in `ModuleHost.qml` only the `core` map, the component list and a
module's `hoverSurface`), `frontend/test-quick-sections.sh` and a new `frontend/test-quick-modules.sh`,
`crates/kurashi-schema/src/v1.rs` (the `quick.*` keys and the module ids only) with its goldens,
`i18n/{en,ja}/quick.toml` (new domain) and the generated schema strings, the daemon's module list if the ids are
enumerated there (find where `"clock"`/`"volume"` are listed as modules), `docs/ux/control-centre-modules.md`.

**Not yours**: `frontend/core/Peeks.qml`, `frontend/surfaces/Stage.qml` beyond what a card's view registration needs
(say so in the report), `settings/**`, `crates/kurashi-theme/**`, `crates/kurashi-texture/**`, `crates/kurashi-motion/**`,
`mods/**`, `docs/DECISIONS.md`, `docs/BACKLOG.md`, `docs/PROGRESS.md`, `docs/HANDOVER.md`.

## Frozen
`crates/kurashi-ipc`, `fixtures/ipc/`, `docs/PROTOCOL.md`, `crates/kurashi-core`. Needs outside → `docs/CONTRACT-CHANGE.md`
(use row numbers from 710 up: 696–701 are taken twice already).

## Acceptance
- Per stage: `just check`; `frontend/test-quick-sections.sh`; from (b) on a new `frontend/test-quick-modules.sh`
  (sandbox, condition waits, motion off, one persistent virtual pointer via `tools/bench/wl_pointer.py --serve` as
  `frontend/test-bar-hover.sh` does): a bar with the new modules shows each; a click toggles what it should (read the
  service document or the daemon's log); an unavailable one is inert and says why; the menu opens; idle 0 frames.
- Screenshots on nested niri (`tools/bench/niri-sandbox.sh`; ONE sandbox at a time, prefix `w70-`): the bar with the
  modules, two modules' cards, the centre restyled and as a phone, the edit mode; light and dark.
- The report lists what each stage reached, and "questions for the user".

## Token thrift
Read: this card, `docs/tasks/README.md`, `CLAUDE.md`, the brief, `docs/ux/bar-hover.md`, `docs/ux/bar-fit.md`'s rules for
modules, `QuickPanel.qml`, two existing modules as patterns (`Volume.qml`, `Clock.qml`), `ModuleHost.qml`,
`ModuleBase.qml`. Do not read `Stage.qml` whole (grep it). Terse report in the README's format.
