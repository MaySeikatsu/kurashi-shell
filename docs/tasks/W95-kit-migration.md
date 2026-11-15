# W95 — `Label` and the kit everywhere (session 34, I551, I557, I574; cards per folder, Haiku, two at a time)

The user's choice: a card per folder, each checked against golden screenshots and the idle budget; then `kurashi mod
check`'s notes become errors. `components/Label.qml` is the one place for how copy is drawn; 481 places still write its
block out (`renderType`/`antialiasing`/`hintingPreference` by `Theme.pixelType`), and the bundled mods import
`qs.components` instead of `qs.kit`.

## The cards (each: one folder, one branch, one worktree, its own build dir)
| Card | Folder | Places |
|---|---|---|
| W95.1 | `frontend/components/quick` | 68 in 20 files |
| W95.2 | `frontend/surfaces` | 58 in 9 |
| W95.3 | `frontend/components/expanded` | 46 in 7 |
| W95.4 | `frontend/components` (top level) | 39 in 14 |
| W95.5 | `frontend/components/{sidebar,faces,appearance,bar,lock,launcher,decor,modules,island}`, `frontend/core` | 71 in 35 |
| W95.6 | `settings/components` (its own files; the links follow the shell's) | 146 in 44 |
| W95.7 | `settings/pages`, `settings/shell.qml` | 53 in 5 |
| W95.8–W95.19 | one per bundled mod: `import qs.kit` instead of `qs.components`, `Label`, the check's notes cleared (colour literals → tokens or a decor slot, pixel sizes → `Theme.fs*`); what the kit lacks is listed for the lead, not rebuilt | per `kurashi mod check mods/<id>` |

## Rules for every card
- A `Text` becomes a `Label` only where its block is exactly Label's; a text with its own render settings stays and is
  listed. `color`, `font.pixelSize`, `font.family` equal to Label's defaults are dropped; others stay as overrides.
- No visual change: `just golden` and the folder's suites before and after (`tools/test-suites.sh --changed`), pixel
  equal where the suite compares; one niri shot per touched surface, light and dark.
- Idle: `tools/bench/measure.py` idle frames and PSS before and after for cards .1–.5 (a `Label` is a `Text`: expect no
  change; say so with the numbers).
- `python3 tools/clones.py --check`, then `--update` (the qml count falls).

## After the last card
`check.rs`: `kit_only`, `colour_literal`, `font_literal`, `copy_literal` become errors (`Level::Error`); the settings
forks of `Slider`, `Button`, `ProvenanceChip`, `FocusRing`, `Chip` are compared with the shell's and merged or their
difference named (I551); the lock faces' `errorText`/`statusText`/`submit()` move into one `LockModel` (its own card).
