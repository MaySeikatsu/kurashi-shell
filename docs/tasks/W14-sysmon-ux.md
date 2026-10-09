# Card W14-sysmon-ux — sysmon to its brief (BACKLOG B18, I29, I30)

**UX brief (governs):** `docs/ux/sysmon.md`. Read its DoD and the W12-sysmon report gaps in BACKLOG I30.
**Owned paths:** `crates/kurashi-mod-sysmon/**`, `mods/sysmon/**`, `i18n/{en,ja}/mod-sysmon.toml`.
**Do:** B18 panel fits the Stage card at every width (no clipped columns; long names elide with full name in a11y); I29
temperature: prefer Tdie/Tccd, label the sensor, make the Tctl offset honest (default critical for a Tctl-only source 95 °C or
a per-source default) and show which sensor is used; I30: bar tabular figures + fixed width, optional 30-sample sparkline, peek
(per-core max/avg, load, PSI, top process), middle click cycles stat, right click Pause/Settings/"Open in btop" (terminal from a
setting, `exec:` capability), Pause in Settings, "paths searched" for no sensor, "host values" label in VM/container, battery
power-use row (as a `quick.tiles` slot or panel row). Mods import `qs.core`/`qs.components` (MODS.md). Do not build the
background-job API (W14-mod-runtime does; adopt it only if it is on main when you finish).
**Acceptance:** crate tests for the new logic; screenshots through the real shell (`frontend/test-mods-live.sh` if on main, else
the sandbox with `mod.enable sysmon` + `mod.panel.open`), every DoD item met / not met.

**Since this card was written (lead):** sysmon: the watch is `job:watch` and `show` is a list setting (K33); remove the unused `show_*` i18n keys; make a paused watch not report running (I48 job `active` flag if you need it — coordinate via a CONTRACT-CHANGE row). Mods import `qs.core`/`qs.components` only. The live check is
`just mods-live` (real shell, every mod, raw-key + QML-warning scan; ~10 min, `KURASHI_RENDER_NODE=/dev/dri/renderD129`,
tool timeout ≥ 15 min) — it must be green for your mod; screenshots under `frontend/shots/modslive/`.
