# Card U-surfaces — honest bar config, clean Stage, launcher errors (UX review R.2)

**Read first:** `docs/reviews/2026-10-09-ux-review.md` (findings by number), `frontend/README.md`.

**Owned paths:** `frontend/surfaces/**`, `frontend/shell.qml`, `i18n/{en,ja}/frontend.toml` is owned by
U-components — put new strings in a new `i18n/{en,ja}/surfaces.toml` domain instead. NOT
`frontend/components/`, `frontend/core/`, `settings/`. Common rules: `docs/tasks/README.md`.

**Fix:**
- 1: read `bar.enabled` and `bar.edge` per output from the `config` document (provenance-resolved;
  per-output entry wins, see `settings/core/Store.qml` `prov()` for the lookup rule) — a Bar only for
  outputs with `enabled`, anchored to its edge (top/bottom/left/right; vertical bars lay out the same
  content in a column, keep it simple and calm); Stage/NotificationCenter/Toasts/Launcher offsets follow
  the bar of their output (no bar → screen edge margin).
- 2: remove the sample chips and probe TextInput from the Stage island panel; one close action.
- 6: launcher closes only on success; failures show a translated error row above the list.
- 12: anchor the disconnected glyph to the workspace row.
- 19: launcher height follows its results (min height for the empty state).
- 24: bar volume slider gets wheel handling via `input.dispatch` if a binding exists, else intent steps.
- 25: notification centre: bottom fade/scroll cue; launcher selected row single emphasis.

**Build constraint (disk nearly full):** do NOT build Rust. Use
`KURASHI_BIN_DIR=/tmp/claude-1000/-home-maike-Projects-kurashi-shell/8df21996-7f7f-4b9f-9bb6-ef599b600ab1/scratchpad/bin-main`.

**Acceptance:** `frontend/test-real.sh` passes; add steps that set `bar.edge` to `bottom` and
`bar.enabled=false` via `kurashi set` and screenshot both (Read them); `just golden` passes or is
updated intentionally (Read every new ref); restore unrelated screenshots before committing.
