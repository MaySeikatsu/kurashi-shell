# Card W43-timer — the timer and pomodoro mod, every variant (K73, K72; docs/ux/timer.md)

**Why:** user point 16, and the first module that ships every K72 variant, so the variant contract is proven on a real
module.

**Read first:** `CLAUDE.md`; `docs/tasks/README.md`; DECISIONS K73, K72, K28 (slots), K24 (island arbitration), K35
(peeks); `docs/ux/timer.md` (whole — it is the spec); `docs/MODS.md` (manifest, provides, native tier, settings, i18n
per mod); `docs/ux/COMPOSITION.md` §3 and the `quick.tiles` tile contract; the tasks mod as the template:
`mods/tasks/mod.toml`, `mods/tasks/qml/*`, `crates/kurashi-mod-tasks/src/*`; the sysmon/weather mods for `island-face:`,
`:expanded` and `peek:` (`mods/sysmon/qml/{Face,FaceExpanded,Peek}.qml`, their crates' relevance signals);
`crates/kurashi-mod-api` (what a native mod can register: services, actions, background work); `crates/kurashid/src/native.rs`
(registration at ~line 43, `qml_of`).

**Task:** build mod `timer` as `docs/ux/timer.md` says:
1. `crates/kurashi-mod-timer`: state, actions `timer.*` (start, pomodoro.start, pause, resume, add, skip, stop, stop_all),
   the `mod.timer` document, one deadline (the earliest end) that lives while any timer runs **even with no subscriber**
   (use `ModCtx::background` — a job that lives while the mod is on and sleeps until the earliest end, no wakeup while
   idle; touch kurashi-mod-api only if that cannot work, and say why), the end (notification with actions *+1 min*, *Stop*, *Next phase*
   through the daemon's notification path; island transient/relevance), pomodoro phase advance, persistence in
   `~/.local/state/kurashi/timer.json` (`XDG_STATE_HOME`) with ends that passed while down firing once on start. Tests:
   phase advance, pause/resume arithmetic, +1 min, restart recovery, no deadline while idle.
2. `mods/timer/mod.toml` + `qml/`: `widget:timer` (glance: ring + mm:ss, idle glyph; click = start the default preset /
   open the panel when running; scroll ±1 min), `peek:timer`, `panel:timer` (Stage card and the sidebar section:
   running timers, presets, custom field, pomodoro card), `desk:timer`, `island-face:timer` (+ `FaceExpanded.qml`),
   `slot:quick.tiles` (QuickTile contract). Views interpolate from `ends_at_ms`, redraw at 1 Hz only while a running
   countdown is visible. Mod settings as the brief lists. i18n `i18n/{en,ja}/mod-timer.toml`.
3. Register the mod in kurashid (native.rs, Cargo.toml dependency) and in `nix/package.nix` only if mods need listing there.
4. `mods/timer/test-timer.sh` (sandbox + real daemon with isolated XDG dirs, like `mods/tasks/test-tasks.sh`): start via CLI,
   every variant shot under washi and sekai (light + dark for washi, ja once), the end fired with no view open.

**Owned paths:** `crates/kurashi-mod-timer/**` (new), `mods/timer/**` (new), `i18n/{en,ja}/mod-timer.toml` (new),
`crates/kurashid/src/native.rs` (the registration line only), `crates/kurashid/Cargo.toml` (the dependency line only),
`crates/kurashi-mod-api/**` (only if step 1 needs it — say what and why). Nothing in `frontend/` outside your mod.

**Acceptance:** `cargo test -p kurashi-mod-timer` green; `kurashi act timer.start '{"minutes":1}'` with no frontend running
→ a notification after ~60 s (test with a short duration); `mods/timer/test-timer.sh` passes with the shots; idle (mod on,
no timer) = 0 frames and no daemon timer; `just check` green.

**Contract rows:** CONTRACT-CHANGE rows 500–509 only. **Env:** `CARGO_TARGET_DIR=$HOME/.cache/kurashi-agents-target/w43-timer
CARGO_BUILD_JOBS=4`; sandbox names `w43-timer-…`. Model: haiku (max effort); the lead reviews every variant against the
brief and hands it back if it is below the bar.
