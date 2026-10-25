# Card W37-daemon — daemon follow-ups: island face, forced services, polkit, launcher icons, Settings links (K66; I198, I200)

**Why:** wave 36 left daemon halves behind frontend stand-ins (rows 380, 381, 387), and K66 accepted rows 103 and 203.

**Read first:** `CLAUDE.md`; `docs/tasks/README.md`; DECISIONS K24, K47, K65, K66; PROTOCOL `runtime.ui` row (island.expand,
polkit), §6 `settings.open`, §7 service documents (`forced_by`); BACKLOG I198, I200; CONTRACT-CHANGE rows 103, 203, 380,
381, 387; `crates/kurashid/src/{wiring,config,island,launcher*}.rs` (grep), `crates/kurashi-mock/`, the `kurashi` CLI crate,
`frontend/surfaces/{Launcher,Stage}.qml` (the `warmQueue` and the polkit `ui.close` stand-in).

**Task:**
1. **Row 203:** `island.expand {face}` opens the card on that face (validated against the island's faces;
   `island.error.unknown_face`), latched into `runtime.ui.face`. Mock parity. Unit test.
2. **Row 103:** the six service documents carry `forced_by` when a forced config key holds their switch (find which keys:
   wifi/bluetooth/dnd/nightlight/… — the tiles' switches; a forced key = `source` nix/managed/mode with `forced_by`). Tests.
3. **Row 381:** while `runtime.ui.polkit` is true kurashid refuses Stage panel and peek actions (`ui.error.polkit`) and
   closes an open panel when it turns true; then remove Stage.qml's `ui.close` stand-in (keep its gates). Test.
4. **Row 380:** launcher result rows carry `icon_path` (resolved in the daemon from the icon theme, cached); Launcher.qml
   loads it with an asynchronous Image and the `warmQueue` warm-up goes. Cold first open stays without a stall
   (`frontend/test-launcher.sh` + the cold-open timing the W36-motion report used).
5. **Row 387 and I40 rest:** a launcher command "Shortcuts" (and "Settings: <page>" for schema pages, if cheap) that sends
   `settings.open {page}`; `kurashi settings --page <page>` in the CLI; mock parity for `settings.open {page}`; move
   `error.settings.unknown_page` / `error.config.not_a_path` next to their siblings (session/schema domains).
6. **I200:** when the system bus itself is absent, the supervisor waits (watch for the bus socket, or back off to a
   long cap with no wakeups) instead of retrying every 30 s forever. Test.

**Owned paths:** `crates/kurashid/**` except `theme_export.rs` (W37-ghostty), `crates/kurashi-mock/**`, the `kurashi` CLI
crate, `frontend/surfaces/{Launcher,Stage}.qml`, `frontend/components/launcher/**`, `frontend/test-{launcher,polkit,stage}.sh`,
`i18n/{en,ja}/{session,schema,settings,launcher,island}.toml`, `docs/ux/launcher.md`.

**Acceptance:** `cargo test -p kurashid -p kurashi-mock` with the new tests; `test-launcher.sh`, `test-polkit.sh`, `test-stage.sh`
green; `just check` green.

**Contract rows:** CONTRACT-CHANGE rows 405–409 only.

**Env:** `CARGO_TARGET_DIR=$HOME/.cache/kurashi-agents-target/w37-daemon CARGO_BUILD_JOBS=6`; sandbox names `w37-daemon-…`.
Model: opus.
