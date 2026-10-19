# Card W18-sysmon — sysmon follow-ups: the main GPU, program names, undrawn states (I65)

**Decision (lead):** finish what W15-sysmon-fixes left (BACKLOG I65). The GPU tile follows the GPU that drives the
displays; program names are what a person calls the program, in the UI language; every state the brief lists is drawn
and screenshotted.
**Brief:** `docs/ux/sysmon.md` (states, process actions, contract notes, DoD).

**Read first:** `docs/tasks/README.md` (rules), I65/I56/I61/I62 in `docs/BACKLOG.md`, `docs/ux/sysmon.md`,
`docs/tasks/W15-sysmon-fixes.md`, `crates/kurashi-mod-sysmon/src/**`, `mods/sysmon/{mod.toml,qml/**,test-states.sh}`,
`frontend/launch.sh` (how the launcher finds the DRM main device today — read only).

**Owned paths:** `crates/kurashi-mod-sysmon/**`, `mods/sysmon/**`, `i18n/{en,ja}/mod-sysmon.toml`. Not yours:
`frontend/**` (W18-peeks owns the peek tests; if the sysmon peek needs a change, make it in `mods/sysmon/qml/Peek.qml`
and say so), `crates/kurashid/**`.

**Do:**
1. **Main GPU (I62 follow-up):** `gpus[].primary` marks the GPU that drives the connected outputs (from `/sys/class/drm`:
   the card whose connectors are `connected`; `boot_vga` as the tie-breaker; one primary when there are GPUs), not the
   first found. A runtime-suspended dGPU is never woken to decide (read `power/runtime_status` first).
2. **Names (I61 follow-up):** desktop-entry `Name[<lang>]` in the daemon's language (ja), falling back to `Name`;
   the index is rebuilt when an applications directory changes, watched only while `mod.sysmon.procs` has a subscriber
   (Ma); a version-like executable name ("2.1.302", a hash) takes the next meaningful path part or argv[0]'s program.
3. **States (brief "States"):** VM/container host label; more than 16 cores (the per-core view stays readable);
   counters after a suspend (no spike: a counter that went backwards resets the baseline); a process row whose signal
   is refused (EPERM) says so; ja copy. Each as a fixture state for `mods/sysmon/test-states.sh`
   (`KURASHI_SYSMON_ROOT`) with a screenshot.

**Acceptance:** `cargo test -p kurashi-mod-sysmon` (new tests for each point: primary GPU on a two-GPU fixture with
the dGPU suspended, localized names, version-like names, counter reset, EPERM row), `cargo clippy -p kurashi-mod-sysmon
--all-targets -- -D warnings`; `timeout 900 mods/sysmon/test-states.sh` green with new shots in `mods/sysmon/shots/`.
