# Card U-components — theme tokens, a11y and motion in shared components (UX review R.2)

**Read first:** `docs/reviews/2026-10-09-ux-review.md` (findings by number), `docs/DESIGN-SYSTEM.md` §6–§7,
`frontend/README.md`.

**Owned paths:** `frontend/core/Theme.qml`, `frontend/components/**` (all, incl. faces, LockContent,
NotificationCard — except `Island.qml` input mapping which stays as is), `crates/kurashi-theme/src/stages.rs`
(+ its tests), `i18n/{en,ja}/frontend.toml`. NOT `frontend/surfaces/`, `shell.qml`, `settings/`.
Common rules: `docs/tasks/README.md`.

**Fix:** 3 (frontend components: focus, keys, ring, Accessible.name), 4, 5 (Chip/NotificationCard
borders + the aa_pairs rows in stages.rs with a test), 10, 11 (frontend components; bind to a new
`Theme.controlH` from `control.height`, enlarge hit areas not visuals), 15, 16, 20 (expose
`Theme.fsCaption`/`fsLabel`/`onAccent`/`error`/`controlH`; replace `fs - 1/-2` in your files), 21 + 22
(ProvenanceChip: neutral edge + lock glyph, no strikethrough, reason reachable by focus).

**Build constraint (disk is nearly full):** do NOT build kurashid. Use the prebuilt binaries:
`KURASHI_BIN_DIR=/tmp/claude-1000/-home-maike-Projects-kurashi-shell/8df21996-7f7f-4b9f-9bb6-ef599b600ab1/scratchpad/bin-main`
for `frontend/test-real.sh` and `just golden` (`tools/golden/run.sh` honours it). Only
`cargo test -p kurashi-theme` with `CARGO_TARGET_DIR=$PWD/target CARGO_INCREMENTAL=0` (a small crate).

**Acceptance:** `cargo test -p kurashi-theme` green incl. the new aa pair; `frontend/test-real.sh` passes
with no QML errors; `just golden` either passes or fails only where you intended (then `--update`, Read
every new ref, commit them); restore other regenerated screenshots before committing.
