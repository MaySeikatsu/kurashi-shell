# Card W9-config-profiles — config history + profiles in the `config` document, profile error codes, Settings follows (rows 21–22, B5, B6, B8)

**Read first:** `docs/tasks/README.md`, `docs/BACKLOG.md` rows B5, B6, B8, `docs/CONTRACT-CHANGE.md` rows 21–22,
`docs/DECISIONS.md` K27, `docs/PROTOCOL.md` §5 (`config` document), `fixtures/ipc/server/snap_config.json`,
`crates/kurashid/src/config.rs` (doc builder ~l.375, `undo`, profile actions ~l.611, `watch` ~l.700),
`crates/kurashi-config/src/engine.rs` (`can_undo`, `list_profiles`, user profiles dir), `i18n/{en,ja}/config.toml`,
`settings/core/Store.qml`, `settings/pages/{ProfilesPage,ModsPage}.qml`, `settings/test.sh`.

**Contract (frozen, already in PROTOCOL/fixture — implement exactly):** the `config` document gains
`"history":{"can_undo":bool,"can_redo":bool}` (current after every apply, undo, redo, profile load and
external reload) and `"profiles":[{"name":…,"bundled":bool}]` (same list and order as `profile.list`),
kept current when files appear in / vanish from the user profiles dir (extend the existing watcher;
debounced like the config file). Profile action errors: `ActionError::Invalid(<i18n key>)` with keys
`config.error.profile_{not_found,invalid_name,unreadable,parse,write}` (pick the set the
`ConfigError` variants need; add en + ja strings to `i18n/{en,ja}/config.toml`).

**Owned paths:** `crates/kurashid/src/config.rs`, `crates/kurashi-config/**` (only if `can_redo` or a
profiles-dir path helper is missing), `crates/kurashid/tests/` (new test file), `i18n/{en,ja}/config.toml`,
`settings/**` **except** `settings/keys.py`, `i18n/{en,ja}/settings.toml`.
NOT `kurashi-ipc`, fixtures, PROTOCOL, `wiring.rs`, `main.rs`.

**Do (daemon):** add both fields to the doc builder; publish after every path that changes them; the
watcher also watches the profiles dir (create it lazily if missing? no — watch the parent and filter).
**Do (settings):** `Store.qml` takes Undo/Redo enabled state from `config.history` (drop the
reply-derived `canUndo/canRedo`); ProfilesPage renders `config.profiles` live (keep `profile.list`
only as a fallback when the field is absent — an older daemon); action errors show the translated
`msg` key (`Store.actError` already maps keys). B8: an invalid mod row reads one clear sentence (no
"mod.toml is missing (mod.toml)" duplication), and a row's "Rejected" line clears on the next change of
that row or after a successful action elsewhere.

**Acceptance:** (1) `crates/kurashid/tests/config_doc.rs`: apply → `history.can_undo` true; undo →
`can_redo` true; a profile file written into the user profiles dir appears in `profiles` within 2 s;
`profile.load` of a missing name → `err` with `msg` = an existing `config.error.profile_*` key that has
en + ja strings. `timeout 600 cargo test -p kurashid --test config_doc`, clippy -D warnings on touched crates.
(2) `settings/test.sh` (extend it; never touch the user's config) shows Undo enabled right after
opening when the daemon already has history (seed by `kurashi set` before Settings starts), and a
profile file created while the Profiles page is open appears without reconnect — screenshots under
`settings/shots/`, describe them in your report.
