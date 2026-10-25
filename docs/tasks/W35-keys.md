# Card W35-keys — keyboard shortcuts editable in Settings (K64, I72)

**User:** shortcuts editable in Settings instead of only through the Home-Manager module (I72, session 7), "core
mechanics" (session 13).

**Read first:** `CLAUDE.md`; `docs/tasks/README.md`; DECISIONS K49, K64; the schema struct `Keys` (`keys.*`, frozen);
`docs/niri-binds.kdl`; `nix/hm-module.nix` (niri.binds: niriDefaultKeys, the file it writes); `crates/kurashid/src/
theme_export.rs` (the pattern: our own file, include line reported, write only on change); `crates/kurashi-compositor`
(the adapters: niri first; Hyprland/Sway if cheap); `settings/` (rows, `SettingRow`, the `pickers` map in
`SettingsPages`), `settings/test.sh`.

**Task:**
1. **Daemon (`crates/kurashid/src/keys.rs`, one register line in `main.rs`):** the field → action table (launcher →
   `launcher.toggle`, notifications → `notifications.center`, sidebar_right/left → `sidebar.toggle {"side":…}`, quick
   → `quick.toggle` (check the id), session_menu → `session.menu`, lock → `session.lock`, settings → `settings.open`,
   webdock → its toggle action, volume/mute/brightness → `audio.volume.up/down`, `audio.mute.toggle`,
   `brightness.up/down`); combo validation (niri key names: modifiers Mod/Super/Ctrl/Alt/Shift + a key, XF86 keys) with
   an inert reason on a bad combo or a duplicate; with `keys.write` on, render the niri binds file (as
   docs/niri-binds.kdl: `repeat=false` except volume/brightness, `allow-when-locked=true` for media keys, `spawn`
   the kurashi binary's absolute path) and write it only on change; a Home-Manager store symlink at that path is not
   touched (state `managed`); a document `svc.keys` (or a section in an existing one — your call, PROTOCOL row via
   CONTRACT-CHANGE) with the file, include line and its presence, conflicts. niri reloads included files by itself —
   verify with `niri validate` on a temp config including the rendered file.
2. **Settings:** the "Keys" page: each row a shortcut recorder (click/Enter → "press a key combination", Esc cancels,
   Backspace clears) writing the combo string; conflicts and inert reasons shown; the include line with Copy (as
   ThemeExportStatus). Keyboard and screen-reader paths as every row.
3. **HM module:** with `programs.kurashi.niri.binds.enable`, keep today's behaviour; document in the option how to move
   to the daemon-written file (set `keys.write = true` and drop the HM bind file); no silent overlap.
4. **Tests:** daemon unit tests (render, validation, duplicates, managed symlink, write-on-change); `niri validate` of
   the rendered file (skip loudly without niri); `settings/test.sh` step for recording a combo (wl_keys.py) and the
   conflict state; shots `settings/shots/keys/`.

**Owned paths:** `crates/kurashid/src/keys.rs` (new), one line in `crates/kurashid/src/main.rs` and `lib.rs`,
`settings/**` (keys page parts), `i18n/{en,ja}/keys.toml` (new), `nix/hm-module.nix` (niri.binds doc only),
`docs/niri-binds.kdl`. Not the schema (frozen; a needed change → CONTRACT-CHANGE row).

**Acceptance:** `cargo test -p kurashid keys` + clippy clean; `settings/test.sh` green with the new step; shots.

**Env:** `CARGO_TARGET_DIR=$HOME/.cache/kurashi-agents-target/w35-keys CARGO_BUILD_JOBS=4`; sandbox names `w35-keys-…`;
never touch the user's real niri config. Model: opus.
