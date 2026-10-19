# Card W17-records — the `records` setting type, end to end (K38, contract row 89; I68)

**Decision (lead, session 7):** a mod setting can be a **list of records** whose fields the manifest declares — the web
dock's pins (`{id, title, target, view, profile, icon}`) are the first. One schema (rule 3): the manifest type maps to a
schema type with one validator; Settings gets a generic records editor; the CLI and Nix set it like any key.
**Brief:** `docs/ux/webdock.md` (pins), `docs/ux/settings.md` (control kit, provenance chips, keyboard).

**Read first:** `docs/tasks/README.md` (rules), MODS.md "Manifest" — **"Records"** (the frozen syntax, value shape and
error paths), DECISIONS K6 + K22 + K15, `crates/kurashi-mods/src/manifest.rs` (how `list` was added, I26),
`crates/kurashid/src/config.rs` `setting_meta`, `crates/kurashi-schema/src/{leaf,meta,generate,registry}.rs` (`Ty`,
`validate_value`, the `schema.settings` controls), the Settings page code that draws `pick_list`
(`settings/pages/`, `settings/components/`), `settings/test.sh`, `crates/kurashid/tests/honesty.rs`.

**Owned paths:** `crates/kurashi-mods/src/manifest.rs`, `crates/kurashi-schema/**`, `crates/kurashid/src/config.rs`
(the mod-setting mapping only), `crates/kurashid/tests/honesty.rs` (records keys), new
`crates/kurashid/tests/records.rs` + a test mod under `crates/kurashid/tests/data/mods/records/**`, `settings/**`,
`i18n/{en,ja}/{config,settings,mods}.toml` (append blocks marked `# W17-records`). Not yours: `crates/kurashid/src/
{native,server,main}.rs` and `crates/kurashi-mod-api/` (W17-webdock-daemon), `crates/kurashi-mock/`, `mods/webdock/`.

**Do:**
1. **Manifest:** `type = "records"` with `[[setting.field]]` exactly as MODS.md "Records": field types string, url,
   enum, bool, int; `required`, `default` (required unless `required = true`), `pattern = "slug"`, `schemes`, `choices`,
   `range`, `label`; setting-level `unique`, `item_label`; the default validated against the fields. Stable error codes
   (`mods.error.<code>`, paths like `setting[2].field[1].schemes`) with i18n.
2. **Schema:** a records `Ty` carrying the field descriptors; `validate_value` normalises (absent optional fields take
   their defaults) and refuses unknown fields, missing required ones, bad types, a slug outside `[a-z0-9-]{1,32}`, a URL
   that is not absolute or whose scheme is not listed, a duplicate `unique` value — each error names
   `mods.<id>.<key>[<n>].<field>`. `schema.settings` describes the control (`records`, fields with their controls,
   `unique`, `item_label`). The value travels as a JSON array of objects (cfg.get, documents, provenance) and is stored as
   a TOML array of tables in the user config.
3. **Settings editor** (generic, `settings/components/`): rows showing `item_label` with the provenance chip of the
   key; add (a form of the fields' existing controls; Enter submits, Escape cancels), edit, move up/down, remove; empty
   state; a field error shown at the field (the daemon's `rejected` path); every change is one `apply set` of the whole
   list (undo works as for any key); forced (Nix) → read-only with the reason. Keyboard: Tab order, arrows in the list,
   FocusRing for keyboard focus only; a11y names per row.
4. **CLI/Nix:** `kurashi set mods.<id>.<key> '<json array>'` works (check; fix in your paths if the parsing is in the
   schema); a records value set in the Nix layer shows as forced (honesty test).

**Acceptance:** `cargo test -p kurashi-mods -p kurashi-schema` and `cargo test -p kurashid --test records --test
honesty` green: manifest accept/refuse cases (each code), normalisation, every error path, unique, TOML round trip,
`cfg.get` shape, a forced records key inert with its reason. `timeout 900 settings/test.sh` green (real daemon in the
sandbox, KURASHI_BIN_DIR as the script supports) with new shots of the test mod's records page: empty, two rows, the add
form, a field error, a forced key, ja. `cargo clippy` on your crates `--all-targets -- -D warnings`.
