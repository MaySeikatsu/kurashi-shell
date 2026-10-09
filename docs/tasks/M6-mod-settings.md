# Card M6-mod-settings — mod settings as config keys + settings pages (K22)

**Goal.** Implement K22 (read it in `docs/DECISIONS.md`).

**Owned paths:** `crates/kurashid/src/config.rs`, `crates/kurashi-config/` (only if the SchemaView
seam needs it), `crates/kurashi-mods/`, `settings/` (pages + Store), `i18n/{en,ja}/{mods,settings}.toml`,
new `crates/kurashid/tests/mod_settings.rs`. NOT `wiring.rs`/`main.rs` (another agent): if wiring
needs a call, expose a function and describe the one-line call in your report. Common rules:
`docs/tasks/README.md`.

**Read:** `docs/DECISIONS.md` K21+K22, `docs/MODS.md` (manifest `[[setting]]`), `crates/kurashi-mods/src/
{manifest,registry}.rs`, `crates/kurashid/src/config.rs` (`SchemaAdapter`, `ConfigStore`,
`schema.settings` doc), `crates/kurashid/src/wiring.rs` (`mods` fn, read-only), `settings/pages/`.

**Build:**
1. A mod-settings registry the `SchemaAdapter` consults for keys `mods.<id>.<key>`: type, default,
   range/step/unit/choices from the manifest; unknown mod keys still `unknown_key`. Updated when the
   mods registry changes (enable/disable/rescan) via a function the wiring can call.
2. Values flow through the normal layers (cfg.get/explain/apply/undo/profiles) with provenance.
   Disabled mod → its keys report `reason: "mods.disabled"` (value/source unchanged).
3. `schema.settings` gains one page per enabled mod (label = mod name key, rows from its settings).
4. Settings app renders those pages (they come from the same document; minimal extra QML).
5. i18n: the bundled mods' setting label/help keys (`mods.media.show_art`, `mods.media.seek_step`(+help),
   `mods.easter-eggs.frequency`) in en + ja.

**Acceptance:** `timeout 900 cargo test -p kurashid -p kurashi-mods -p kurashi-config` green with
`tests/mod_settings.rs` (set/get/explain a mod key with provenance; invalid value rejected with the
manifest's range; disabled → inert reason; page present only when enabled); `settings/test.sh` passes
and a new shot `7-mod-page.png` shows the Media page (Read it). clippy clean.
