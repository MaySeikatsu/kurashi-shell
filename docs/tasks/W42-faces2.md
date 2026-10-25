# Card W42-faces2 — island faces follow-ups (K68; I212)

**Why:** W40 made `island.main.faces` restrict (K68). Its report left gaps (rows 451, 452, 454; I212).

**Read first:** `CLAUDE.md`; `docs/tasks/README.md`; DECISIONS K68; PROTOCOL `runtime.island.main` (`faces`, `unlisted`),
`island.expand {face}`; `docs/ux/island.md`; `crates/kurashi-island/src/lib.rs`, `crates/kurashid/src/island.rs`,
`crates/kurashid/src/config.rs` (`TRANSIENT_FACES`, the faces offers), `crates/kurashi-config/src/engine.rs` (`save_profile`),
`crates/kurashi-config/src/tests.rs` (`save_profile_snapshots_…`).

**Task (lead rulings in bold):**
1. Row 451: a card open on a face the list then drops — **the daemon closes the card** (the expanded state clears, as a
   collapse does); a test.
2. Row 452: a list whose every face is unavailable (only mods that are off) — **the island falls back to `clock`** (always
   registered) and the document says so (`faces: ["clock"]`), so the frontend draws what the daemon reports; Island.qml then
   needs no "" special case — remove it if it exists only for this. A test; one line in `docs/ux/island.md`.
3. `save_profile` drops a value equal to the schema default, so a profile saved with exactly the default three faces loses the
   list and stops restricting on load. **Rule: a value the user set (source = the user's config) is saved even when it equals
   the default**; forced values stay out as today. Update the config test and add one for this; report every other golden or
   test the rule moves.
4. `keys_sway` tests fail under a sandbox `XDG_RUNTIME_DIR` (env sensitivity): make them set or clear what they read.
5. Row 454: the stale comment/steps in `mods/calendar/qml/Widget.qml` and `mods/calendar/test-calendar.sh` (lines ~382–383).
6. Screenshots of Settings' faces control (default list, a restricted list with an unlisted mod face offered back), en + ja.

**Owned paths:** `crates/kurashi-island/**`, `crates/kurashid/src/island.rs`, `crates/kurashid/src/config.rs` (faces only),
`crates/kurashid/src/keys*.rs` (tests only), `crates/kurashid/tests/**` (island/settings/keys tests), `crates/kurashi-config/src/engine.rs`
(`save_profile` only) + its tests, `crates/kurashi-mock/**` (island only), `frontend/components/Island.qml` (the "" case only),
`mods/calendar/qml/Widget.qml`, `mods/calendar/test-calendar.sh`, `docs/ux/island.md`.

**Acceptance:** `cargo test -p kurashi-island -p kurashi-config -p kurashid`; the new tests named in the report; `just check` green
(also with `XDG_RUNTIME_DIR` set to a fresh dir); the screenshots.

**Contract rows:** CONTRACT-CHANGE rows 470–474 only.

**Env:** `CARGO_TARGET_DIR=$HOME/.cache/kurashi-agents-target/w42-faces2 CARGO_BUILD_JOBS=4`; sandbox names `w42-faces2-…`.
Model: haiku (max effort).
