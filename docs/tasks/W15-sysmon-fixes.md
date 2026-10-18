# Card W15-sysmon-fixes — sysmon review findings + drawable states (B24, I61, I62, I56)

**Brief (governs):** `docs/ux/sysmon.md`. Lead screenshot review (session 6) found:
- **B24 (bug):** the shell's own processes are killable from the shell: another `kurashid` and `.quickshell-wra` show
  enabled End / Force quit; only the serving daemon's pid is protected. Protect by identity: this session's kurashid,
  its Quickshell frontend and the settings app (same session/uid, matching executables), with the reason shown.
- **I61:** names come from `comm` (15 chars). Show the executable basename (Nix wrappers: strip a leading "." and a
  trailing "-wrapped"), or the desktop entry's name when one matches; the full command line in the a11y description.
- **I62:** on a hybrid laptop the GPU tile shows the sleeping dGPU ("no utilisation reported", "–") and the active
  iGPU as a side line. The tile follows the GPU that renders (the compositor's DRM main device, or the busiest awake
  one); a runtime-suspended GPU is listed as "asleep" and never woken by sampling.
- **I56:** the states the brief lists are not drawable in tests. Add a fixture root (env `KURASHI_SYSMON_ROOT`, read
  once at start like weather's `KURASHI_WEATHER_API`; the shell never sets it) for `/proc` and `/sys`, plus a state
  script `mods/sysmon/test-states.sh` that runs the real shell in the sandbox against fixtures and screenshots: bar
  normal / activity / critical / paused / no sensor / sparkline on; panel at 360, 440 and 720 px card widths; the End /
  Force quit confirmation; the trouble face; the GPU-asleep tile.

**Read first:** `docs/tasks/README.md` (rule 3: your own build dir), the brief, `crates/kurashi-mod-sysmon/src/*`,
`mods/sysmon/qml/*`, `frontend/test-mods-live.sh` (how the live check drives a mod; don't edit it), weather's fixture
hook in `crates/kurashi-mod-weather/src/service.rs` as a pattern.

**Owned paths:** `crates/kurashi-mod-sysmon/**` **except `watch()` in `sysmon.rs`** (W15-job-active adds one call there),
`mods/sysmon/**`, `i18n/{en,ja}/mod-sysmon.toml`.
**Acceptance:** `cargo test -p kurashi-mod-sysmon` with new cases (protection by identity incl. a second kurashid of the
same user; name cleanup table; GPU choice with one asleep); `mods/sysmon/test-states.sh` green and every screenshot
Read and judged; `just mods-live` green for sysmon (machine B: `KURASHI_RENDER_NODE=/dev/dri/renderD129`). Report every
DoD item of the brief as met / not met.
