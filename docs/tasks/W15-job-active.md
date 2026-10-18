# Card W15-job-active — honest "Running now" (I48, CONTRACT row 73)

**Brief:** `docs/ux/settings.md` (mod pages: "Running now: <reasons>") and `docs/ux/sysmon.md` (a paused watch is not
running). Decision (lead, row 73): a job can say it is idle; an inactive job's reason leaves `running_reasons`.

**Read first:** `docs/tasks/README.md`, `crates/kurashi-mod-api/src/lib.rs` (`JobCtx`, `Job`), `crates/kurashid/src/native.rs`
(job runner, `running.reasons`, `mods` document), `crates/kurashid/tests/native_mods.rs` (paused-clock job tests),
`crates/kurashi-mod-sysmon/src/sysmon.rs` (`watch()`), `settings/components/ModHead.qml`, `settings/pages/ModsPage.qml`.

**Owned paths:** `crates/kurashi-mod-api/**`, `crates/kurashid/src/native.rs`, `crates/kurashid/tests/native_mods.rs`,
`crates/kurashi-mod-sysmon/src/sysmon.rs` (the one call), `crates/kurashi-mod-weather/src/` (only if its rain job has an
idle state worth reporting), `settings/components/ModHead.qml`, `settings/pages/ModsPage.qml`,
`i18n/{en,ja}/settings.toml` (append one block marked `# W15-job-active`).

**Do:** `JobCtx::set_active(bool)` (default active when the job starts); the daemon drops the job's reason from
`running_reasons` while it is inactive and republishes the `mods` document on a change (no polling; a change notifies).
`running` = non-empty reasons, as before. Sysmon's watch calls `set_active(cfg.watch && not paused)`. Settings: the mod
head and the Mods page show "Running now: <reason>, <reason>" from `running_reasons` (translated keys) instead of
yes/no, and "Not running" when empty; a11y name carries the same text.
**Acceptance:** a kurashid test (paused clock) where a job goes inactive → its reason leaves `running_reasons` and
`running` turns false, then active again; sysmon test for the paused watch; `settings/test.sh` screenshot of a mod page
with two reasons and with none (mock or real daemon). Clippy/fmt/tests for every crate you touched.
