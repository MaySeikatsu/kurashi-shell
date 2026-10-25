# Card W38-keys — keyboard shortcut follow-ups (I189)

**Why:** W35-keys left follow-ups (BACKLOG I189). Shortcuts are core mechanics the user asked to finish.

**Read first:** `CLAUDE.md`; `docs/tasks/README.md`; `docs/ux/keys.md`; DECISIONS K64 (+ amendment); BACKLOG I189;
`crates/kurashid/src/keys.rs`, `crates/kurashi-schema/src/{__private,generate}.rs` (how a control kind is chosen),
`settings/pages/SettingsPages.qml` (`pickerOf`), the ShortcutRecorder, `crates/kurashi-mock/`, `tools/bench/wl_keys.py`.

**Task:**
1. A schema control kind `shortcut` (attribute or by type) emitted in `settings_meta.json`; Settings picks the recorder from it
   and drops the `keys.` prefix check in `pickerOf`. Golden updated. (Schema *types* in `v1.rs` stay the lead's — if v1.rs needs
   an attribute on the `Keys` fields, add it there; that one edit is allowed.)
2. `svc.keys` in kurashi-mock (same shape as kurashid, PROTOCOL `svc.keys` row) so Settings › Keys works under `just mock`.
3. `wl_keys.py`: a `super` modifier.
4. The written niri binds carry `hotkey-overlay-title` (i18n'd action label in the user's language) so niri's own cheat
   sheet names kurashi's shortcuts; `niri validate` still passes.
5. Sway and Hyprland binds files (`keys.write` for those adapters): Sway's `bindsym … exec kurashi act <action> '<json>'`
   quoting, Hyprland `bind = …, exec, …`; same header/foreign/managed rules as niri (K64 amendment). Unit tests per adapter.
6. The recorder maps shifted symbols back on non-US layouts too (use the xkb keysym, not a US table) — or document the limit.
7. `SETTINGS_HOST=sheet settings/test.sh` keys steps with the inhibitor pass.

**Owned paths:** `crates/kurashid/src/keys.rs`, `crates/kurashi-schema/src/{__private,generate}.rs` + goldens (and the `Keys`
attribute in `v1.rs` only), `settings/**` (keys page, recorder, `pickerOf`), `crates/kurashi-mock/**` (svc.keys only),
`tools/bench/wl_keys.py`, `i18n/{en,ja}/keys.toml`, `docs/ux/keys.md`.

**Acceptance:** `cargo test -p kurashid keys -p kurashi-schema -p kurashi-mock`; `bash settings/test.sh` (window and sheet host) keys steps.

**Contract rows:** CONTRACT-CHANGE rows 425–429 only.

**Env:** `CARGO_TARGET_DIR=$HOME/.cache/kurashi-agents-target/w38-keys CARGO_BUILD_JOBS=4`; sandbox names `w38-keys-…`.
Model: haiku (max effort).
