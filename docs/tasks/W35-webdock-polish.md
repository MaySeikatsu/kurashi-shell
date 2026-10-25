# Card W35-webdock-polish — web dock fixes from the audit (I90, I91, I98, I99, I100)

**Read first:** `CLAUDE.md`; `docs/tasks/README.md`; `docs/ux/webdock.md`; DECISIONS K38–K41, K56; the five rows in
`docs/BACKLOG.md` (I90, I91, I98, I99, I100) and the files they cite (`mods/webdock/qml/**`, `mods/webdock/host/**`,
`crates/kurashi-mod-webdock/src/**`); `mods/webdock/test/*`, `frontend/test-dock.sh`.

**Task (each item: fix, test, shot where visible):**
1. **I98** first keystrokes lost after a keybind reveal: request keyboard focus as the card maps (before the first
   frame) or buffer keys until the page has focus; test with `tools/bench/wl_keys.py` typing right after the reveal.
2. **I99** reduced motion: under profile `none` the card fades over a short fixed duration (or the motion token meant
   for reduced motion) instead of cutting, if the brief allows; header buttons reach the 32 px control rule — find a
   layout that keeps the title readable at 360 px (overflow menu exists).
3. **I100** top/bottom edges keep a bar on the same axis clear (use the usable area like the side edges), in the shell
   window and the host's card.
4. **I90** a view card's body has inner padding and Tab reaches a view panel's own controls.
5. **I91** `mod.webdock` carries `forced_by` for settings Nix forces, so the strip's toggles are inert with the reason
   (rule 2; the frontend already reads `pin.forced_by`).

**Owned paths:** `mods/webdock/**`, `crates/kurashi-mod-webdock/**`, `i18n/{en,ja}/mod-webdock*.toml`, `frontend/test-dock.sh`
(webdock steps only). Not `kurashid` beyond nothing (a needed hook → CONTRACT-CHANGE row).

**Acceptance:** `mods/webdock/test/*` relevant suites and `frontend/test-dock.sh` green; `cargo test -p kurashi-mod-webdock`
+ clippy; shots for I99/I100/I90.

**Env:** `CARGO_TARGET_DIR=$HOME/.cache/kurashi-agents-target/w35-webdock CARGO_BUILD_JOBS=4`; daemon for sandbox runs
built into that dir (`--features kurashid/test-mods`); sandbox names `w35-wd-…`; machine A (`KURASHI_RENDER_NODE=/dev/dri/renderD128`
if a suite asks for renderD129). Model: haiku (max).
