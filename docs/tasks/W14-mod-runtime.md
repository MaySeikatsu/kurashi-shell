# Card W14-mod-runtime — background jobs, list settings, capabilities, unlinked native mods

**Read first:** `docs/tasks/README.md`, `docs/MODS.md`, `docs/DECISIONS.md` K25, K26, K28, `docs/BACKLOG.md` I23, I26, I28,
B15, `crates/kurashi-mod-api/`, `crates/kurashi-mods/src/{manifest,registry}.rs`, `crates/kurashid/src/{native,wiring}.rs`,
`crates/kurashid/tests/native_mods.rs`, the three mods (`crates/kurashi-mod-{weather,sysmon,wallpaper}`, `mods/*/mod.toml`).

**Owned paths:** `crates/kurashi-mod-api/**`, `crates/kurashi-mods/**`, `crates/kurashid/src/native.rs`, the mods part of
`crates/kurashid/src/wiring.rs`, `crates/kurashid/tests/native_mods.rs`, `crates/kurashid/tests/data/mods/hello/**`,
`crates/kurashi-mod-hello/**`, `docs/MODS.md` (document what you add — the lead allows it), `i18n/{en,ja}/mods.toml`, and the
*adoption* lines in the three mod crates/manifests (only to switch them to the new APIs: weather's rain watch and sysmon's
watch to the background-job API, sysmon's four `show_*` bools to one `show` list, capability names).

**Do:** (1) I23 `ModCtx::background(name, reason_key, FnOnce(JobCtx) -> Future)`: a task that runs while the mod is enabled
and the job is wanted (a setting), cancelled on disable; the `mods` doc entry gains `running_reasons: [<i18n key>]` (subscriber
services report `"mods.running.subscribed"`, jobs their reason) — Settings' "Running now" line reads it. (2) I26 manifest
`type = "list"` with `choices = [...]` → config key of string lists, `control: pick_list`; validation of members. (3) I28
`KNOWN_CAPABILITIES` += `fs:read`, `proc:signal`, `exec:<binary>`, `network`; mods declare what they use. (4) B15: enabling a
native-tier mod whose manifest provides daemon kinds (service/action/island-face/choices) but has no linked `NativeMod` is
refused with `mods.error.not_built` (frontend-only provides stay enable-able) — check bundled `media`/`easter-eggs` and
decide per their provides; document it.

**Acceptance:** native_mods tests: job runs only while enabled+wanted, appears in `running_reasons`, stops on disable (paused
clock); list setting validates + renders `pick_list` in `schema.settings`; capability validation; unlinked native mod with
daemon provides refused, frontend-only one allowed. Adopted mods still pass their own tests. clippy -D warnings, fmt.
