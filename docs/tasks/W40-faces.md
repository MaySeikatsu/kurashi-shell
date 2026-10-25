# Card W40-faces — `island.main.faces` restricts (K68; I209)

**Why:** the user chose (K68): the faces list restricts which faces the island may show, as its label says. Today
kurashi-island only orders by it (`Decision.faces` = every registered face; unlisted ones follow).

**Read first:** `CLAUDE.md`; `docs/tasks/README.md`; DECISIONS K24, K30, K65, K66, **K68** (incl. its two limits); PROTOCOL
`runtime.island.*` and `island.expand {face}`; `docs/ux/island.md`; `crates/kurashi-island/src/lib.rs` (`rank`, `ordered`,
`primary`, `activities`), `crates/kurashid/src/island.rs`, the schema `IslandInstance` (`faces`, `default`), Settings' faces control.

**Task:**
1. kurashi-island: a face not in the configured list is not offered (`Decision.faces`), never wins by relevance or as the
   default, and is not reachable by cycling; system transients (the faces `island.main.system_events` governs) are exempt.
   An empty list = every face (a safe fallback). Unit tests for each rule.
2. kurashid: `island.expand {face}` for an unlisted face is `invalid` `island.error.unknown_face`; the calendar widget's
   fallback (`island.expand {}`) is then reached — check it.
3. Defaults: a user on the default list keeps every face they see today. Decide and implement: e.g. the schema default
   becomes "the core three + every enabled mod's face" (a computed default from the island.faces source), or a mod face is
   listed by default unless the user's own list exists. Never write the user's config behind their back. Document in
   `docs/ux/island.md`.
4. Settings: unlisted faces appear as addable choices with their provenance; the help text says "Faces this island may
   show, in cycling order" (v1.rs doc comment is the lead's — propose the text in your report; the generated en string follows).
5. Mock parity.

**Owned paths:** `crates/kurashi-island/**`, `crates/kurashid/src/island.rs` (+ tests), `crates/kurashi-mock/**` (island only),
`mods/calendar/qml/Widget.qml` (only if the fallback needs a fix), `settings/` faces control only, `docs/ux/island.md`.

**Acceptance:** `cargo test -p kurashi-island -p kurashid island -p kurashi-mock`; a test-island step or a mock check showing an
unlisted mod face hidden and the default list unchanged for a default user; `just check` green.

**Contract rows:** CONTRACT-CHANGE rows 450–454 only.

**Env:** `CARGO_TARGET_DIR=$HOME/.cache/kurashi-agents-target/w40-faces CARGO_BUILD_JOBS=4`; sandbox names `w40-faces-…`.
Model: haiku (max effort).
