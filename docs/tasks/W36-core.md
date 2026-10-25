# Card W36-core — core mechanics: supervisor, island system events, Settings by page, free lists (I17, I18, I40, I54)

**Why:** the user: "we also didn't finish the core mechanics and modules of the shell". Four accepted rows; K65 (lead,
already merged) added the keys and the `settings.open {page}` shape — implement them.

**Read first:** `CLAUDE.md`; `docs/tasks/README.md`; DECISIONS K30, K65, K25 (supervisor); PROTOCOL `settings.open`;
BACKLOG I17, I18, I40, I54; `docs/ux/settings.md`, `docs/ux/wallpaper.md`; `crates/kurashid/src/{supervisor*,island*,
config}.rs` (grep for the service supervisor and the island's permanent subscriptions), `settings/` (page routing,
the list control), `mods/wallpaper/` manifest (`folders`).

**Task:**
1. **I17:** the service supervisor no longer retries every ≤ 30 s while a bus name is absent (no BlueZ, no UPower): it
   waits for `NameOwnerChanged` and starts on appearance. Unit test with a fake bus or the existing test seam.
2. **I18:** `island.main.system_events = false` drops the island's permanent svc.power / svc.bluetooth / volume /
   brightness subscriptions (refcount falls to zero when nothing else holds them) and shows no system transients; turning
   it on re-subscribes. Test: the services stop when off and nothing else subscribes.
3. **I40:** `settings.open {page}` per PROTOCOL (K65): kurashid validates the page against the schema pages and enabled
   mods (`error.settings.unknown_page`), `KURASHI_SETTINGS_PAGE` / `ipc call settings page <page>`; the Settings app
   opens on it. Use it where a page link fits (Keys: the quick-settings or launcher "Shortcuts" entry if one exists —
   don't invent new UI beyond one obvious link).
4. **I54:** free string lists (`type = "list"` without `choices`) in mod manifests; Settings edits them with the list
   control (add, remove, reorder, a path picker hint for paths); the wallpaper mod's `folders` becomes such a list, with a
   migration that reads the old colon string.
5. i18n en + ja for every new string; Settings shots for the free list (empty, three entries, invalid path) and a page
   deep link.

**Owned paths:** `crates/kurashid/src/**` except `workspaces.rs` and the niri adapter (W36-bar), `crates/kurashi-mod-api/**`,
`crates/kurashi-schema/src/__private.rs` and `generate.rs` (not `v1.rs` — the lead's), `settings/**`, `mods/wallpaper/**`,
`i18n/{en,ja}/{settings,mod-wallpaper,island}.toml`, `docs/ux/settings.md`.

**Acceptance:** `cargo test -p kurashid` (new tests for I17, I18, I40), `cargo test -p kurashi-mod-api`, `bash settings/test.sh`
with the new list and page steps and shots; `just check` green in your worktree.

**Contract rows:** use CONTRACT-CHANGE rows 385–389 only.

**Env:** `CARGO_TARGET_DIR=$HOME/.cache/kurashi-agents-target/w36-core CARGO_BUILD_JOBS=6`; sandbox names `w36-core-…`.
Model: opus.
