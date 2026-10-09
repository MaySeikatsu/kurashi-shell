# Card W10-settings — mod pages in the sidebar, Load/Unload, Select + PickList controls (K25, I9)

**Read first:** `docs/tasks/README.md`, `docs/DECISIONS.md` K25 (+ addendum), `docs/MODS.md` "States, persistence
and Settings", `docs/PROTOCOL.md` §5 (`mods` doc, "Choices from the daemon"), `fixtures/ipc/server/snap_mods.json`,
`settings/**` (shell.qml sidebar, pages/{ModsPage,SettingsPages}.qml, components/SettingRow.qml, core/Store.qml),
`docs/reviews/2026-10-09-ux-review.md` (a11y/hit-target rules), `i18n/{en,ja}/settings.toml`.

**Contract (frozen):** pages with `"mod":"<id>"` are mod pages (one per loaded mod); `mods` doc entry `state`
(`available|disabled|enabled|invalid`) + `running`; actions `mod.load/unload/enable/disable {id}`; rows with
`control: "select"` (`choices [{value,label,enabled?,reason?}]`) and `control: "pick_list"` (ordered subset of
`choices` for a string list).

**Owned paths:** `settings/**`, `i18n/{en,ja}/settings.toml`. Nothing else.

**Do:** (1) Sidebar: mod pages sorted alphabetically **among** the core pages (by translated label), each with a
small indicator: hollow ring = loaded-off (`disabled`), filled dot = on (`enabled`); colours from the theme tokens
`color.status.on/off` (fall back to `accent`/`dim` when absent), never colour alone: shape + accessible text
("Media — on"). (2) A mod page starts with its on/off Toggle (sends `mod.enable/disable`; inert with reason when
forced), its description, and "Running now: yes/no" (`settings.mods.running_*` keys); then its generated rows.
(3) Mods page: `available` rows get "Load" (`mod.load`), loaded rows "Remove from Settings" (`mod.unload`), invalid
rows show their errors; detected-only mods have no sidebar page. (4) `select` → a dropdown (popup list inside the
settings window, keyboard: Up/Down/Enter/Esc, disabled options greyed with their reason as a second line);
`pick_list` → the ordered list with add (from remaining choices), remove, move up/down. Both ≥ 32 px hits, focus ring.

**Acceptance:** extend `settings/test.sh` (build kurashid from main per its header; on machine B
`KURASHI_RENDER_NODE=/dev/dri/renderD129`): screenshot the sidebar with `media` loaded-off and `easter-eggs` on,
the media page, the Mods page, the palette dropdown open, and `island.main.faces` pick list; one keyboard step
selects another palette (the daemon's `config` doc shows it). Read every screenshot; describe them in your report.
