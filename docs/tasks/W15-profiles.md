# Card W15-profiles — profile load is an overlay (B13) + export/import in the Profiles page (I41)

**UX brief (governs):** `docs/ux/settings.md` (Design §6 "Profiles as stories", DoD "profiles: differ count, preview,
export/import review"). **User decision (session 6, B13): overlay** — loading a profile changes only the keys the
profile sets; every other user change stays; the preview lists exactly what changes; "Reset to defaults" stays a
separate, explicit action.

**Read first:** `docs/tasks/README.md` (all common rules), the brief, `crates/kurashi-config/src/engine.rs`
(`profile_candidate`, `review`, `load`, `held_back`, K7 sections), `crates/kurashid/src/config.rs` (`profile.*` actions,
K32 `profile.export/import`), `settings/pages/ProfilesPage.qml`, PROTOCOL §6 (`not_applied`).

**Owned paths:** `crates/kurashi-config/**`, `crates/kurashid/src/config.rs` (profile actions only), `crates/kurashid/tests/config*.rs`,
`settings/pages/ProfilesPage.qml`, new files under `settings/components/` named `Profile*.qml`, `settings/test.sh` (profile
steps only), `i18n/{en,ja}/settings.toml` (append your keys in one block marked `# W15-profiles`). Not the schema, not
`kurashi-ipc`/fixtures (needs → CONTRACT-CHANGE row).

**Do:**
1. Engine (B13): `profile_candidate` for a load replaces the profile layer **only for the keys (slots) the profile
   sets** (within `sections`), and clears user overrides **only for those keys** (so the profile takes effect there);
   every other user and profile-layer entry stays (its provenance keeps naming its own profile — K7). Update the doc
   comments. Undo stays one transaction. Tests: the reported case (user History size 210 survives loading a profile
   that does not set it; a key the profile sets replaces the user value and the preview says so); section-filtered
   loads unchanged; forced keys still `not_applied`.
2. Preview: the review lists the keys that change (before → after, with "your change replaced" for a user value the
   profile overrides) and a count of user changes kept. If that needs a new field in the reply, add it additively in
   kurashid and append a CONTRACT-CHANGE row (lead updates PROTOCOL/fixtures).
3. Profiles page (I41): export (name + path field with a sensible default under `$XDG_DATA_HOME`/home, result shows
   what was left out and why) and import (path field → review = the same preview → Apply / Cancel), using the existing
   `profile.export` / `profile.import {path, apply?}` actions. States: empty (no profiles), loading, error (translated,
   with code), not_applied list. Keyboard: Tab order, Enter applies, Esc cancels a review. Header "<profile> · N
   settings differ" per the brief.
**Acceptance:** `cargo test -p kurashi-config` and `-p kurashid --test config` green with the new cases;
`settings/test.sh` (sandbox) screenshots of: profile list, load preview showing replaced + kept, export result,
import review, error state, ja; Read them critically. Report every DoD item of the brief's profile line.
