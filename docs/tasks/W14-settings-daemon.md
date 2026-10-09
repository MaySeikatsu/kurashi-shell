# Card W14-settings-daemon — the daemon/CLI side Settings' brief still needs (BACKLOG I25, I35–I38)

**UX brief:** `docs/ux/settings.md` (DoD 4 and 7) and `docs/ux/weather.md` ("Set place" opens Settings).
**Read first:** `docs/tasks/README.md`, the briefs, `docs/PROTOCOL.md` §5/§6, `crates/kurashi-config/src/engine.rs` (profiles),
`crates/kurashid/src/{config,wiring}.rs`, `crates/kurashi/src/main.rs` (CLI), `settings/shell.qml` (`KURASHI_SETTINGS_KEY`,
`ipc call settings jump <key>` exist), `tools/bench/wl_keys.py`.
**Owned paths:** `crates/kurashi-config/**` (profile export/import), `crates/kurashid/src/config.rs` (profile actions, preview),
`crates/kurashid/src/wiring.rs` `fn ui` (only `settings.open`), `crates/kurashi/src/**` (CLI), `crates/kurashid/tests/settings_daemon.rs`
(new), `i18n/{en,ja}/{config,session,schema}.toml` (add keys), `docs/PROTOCOL.md` §5/§6 rows for what you add (allowed),
`tools/bench/wl_keys.py` (modifiers + Escape), `crates/kurashid/src/island.rs` only for face labels if needed.
**Do:** (1) I35 `profile.export {name, path}` (drops machine-local keys: per-output values, paths) and `profile.import {path}`
→ returns a review diff (dry-run), `profile.import {path, apply:true}` applies as one transaction; `profile.preview` lists keys
held by Nix/forced as `not_applied: [{key, reason}]`. (2) I36 `kurashi settings [<key>]`: if a Settings window answers
`qs ipc`, call `jump`; else spawn `qs -p <settings dir>` with `KURASHI_SETTINGS_KEY` (settings dir from `KURASHI_DATA_DIR` /
the package share dir); refuse an unknown key with the schema's message. (3) I25 action `settings.open {key?}`: the daemon
runs the same launcher (detached, no shell), returns `unavailable` with a key when Settings is not installed. (4) I37 face
labels: `schema.settings` choices for `island.faces` carry labels for every registered face (core catalogue keys for
bluetooth/power/…; mod faces from their manifest name). (5) I38 `wl_keys.py` gains `alt+up`, `shift+tab`, `ctrl+…`, `escape`.
**Acceptance:** `crates/kurashid/tests/settings_daemon.rs`: export/import round trip (machine-local keys dropped), import
review diff, preview lists a Nix-forced key as not applied, `settings.open` spawns a fake settings binary on a temp PATH with
the key in its env; CLI unit tests; face labels present for every core face; `python3 tools/bench/wl_keys.py alt+up` usage
works in a sandbox. clippy -D warnings, fmt.
