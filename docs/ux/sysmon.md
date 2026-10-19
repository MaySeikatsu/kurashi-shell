# System monitor (mod) — UX brief
Status: agreed (lead, session 5) — implementation card W12-sysmon (revised from this brief)

## Job
Answer "is my machine OK, and if not, what is eating it?" — calmly. Most of the time the answer is "fine" and the
module should be nearly invisible; when something is wrong it should say so in one place and offer the fix (end the
process). It is the **System health** family (COMPOSITION §2).

## References (research 2026-10-09, cited)
- **Waybar**: polls cpu 10 s / memory 30 s; `states` thresholds as CSS classes; `hwmon-name` instead of hwmonN
  indices (indices shift).
- **btop**: 2 s default update; process CPU vs total; `k` kills. **GNOME System Monitor**: End (lets the app save)
  vs Force Stop; **KDE** fixed its kill dialog to name SIGTERM vs SIGKILL.
- **Stats (macOS)**: sensors and Bluetooth are the costliest modules (disabling cuts CPU/power up to 50 %).
  **iStat Menus**: per-core, history, top apps, memory pressure, rules that alert on *sustained* load.
- **Windows Task Manager**: update speed High/Normal/Low/**Paused**.
- **Noctalia**: a missing source shows "unavailable", never 0; activity/critical thresholds (CPU 50/90 %, temp
  60/85 °C, RAM 60/90 %), 0 disables; GPU probed only while shown. **end-4**: ungated 3 s timer (counterexample).
- **DMS dgop**: deltas over measured elapsed time. **HyprPanel**: a click opens btop (escape hatch).
- **Kernel**: PSI pressure (`/proc/pressure/*`), `MemAvailable`, zram ratios, iostats; k10temp `Tctl` vs `Tdie`.
- **Pitfall**: polling `nvidia-smi` keeps a runtime-suspended dGPU awake (~10 W); read `power/runtime_status` first.

## Beyond the basic job — what sysmon can become
1. **Silent when fine, articulate when not**: the bar widget is optional; the real value is a **sustained-trouble
   signal** into the Island arbiter ("CPU 95 % for 30 s — firefox") with the culprit and an End button in its
   expanded view. Hysteresis + N-sample windows so it never flaps.
2. **Pressure, not just percent**: PSI ("memory pressure: some 12 %") explains slowness better than RAM %; shown in
   the panel next to the raw numbers.
3. **The process that matters**: top-8 list (CPU or memory sort, btop-style lazy sort), End (SIGTERM) and Force quit
   (SIGKILL, confirmed, signal named), "Open in btop" as escape hatch (terminal from settings).
4. **Battery meets sysmon**: discharge watts and "what drains the battery" (top CPU while on battery) — the Power
   family page in quick settings gets a "Power use" row from this mod (slot `quick.tiles` or a later
   `quick.power.detail` slot).
5. **GPU honestly**: "asleep, not sampled" for a suspended dGPU; sampled only while awake and shown.
6. **History that is cheap**: 60-sample sparklines kept in the daemon only while subscribed; nothing recorded in the
   background.

## Design
- **Bar widget** (opt-in placement): tabular digits, fixed width — "CPU 12 % · RAM 41 %" (stats chosen in settings),
  optional 30-sample sparkline; activity tint + glyph at the activity threshold, icon swap at critical (never colour
  only, never blinking). Peek: per-core max/avg, load, PSI, top process. Click → panel; middle → cycle stat; right
  → Pause / Settings / Open btop.
- **Panel** (`panel:sysmon`, ~440 px): tiles CPU · Memory · Temperature · GPU (if awake) — value, 60-sample
  sparkline, source ("Tdie · k10temp"), screen-reader text; per-core strip (collapsible; aggregate > 16 cores);
  disk/network throughput rows; top-8 processes with actions; footer "sampling every 2 s · Pause".
- **Island face** (`island-face:sysmon`, relevance only): appears after N samples over critical, shows the culprit;
  expanded view = the panel's process section.
- **Settings**: interval (1–60 s, default 2) + Paused; stats shown in the bar; thresholds per stat (0 disables);
  temperature sensor auto/by name with its source; process rows; kill confirmation.

## States
no sensor (row omitted + paths searched in settings) · VM/container (label "host values"; cgroup limits) · many
cores · dGPU suspended · counters reset after suspend (drop the sample) · no battery/swap/zram/PSI (hide rows) ·
EPERM on another user's process (action disabled with reason) · paused · ja copy.

## Fit and constraints
Ma: sampling only while subscribed (bar widget visible, panel open) **or** while the trouble signal is enabled — then
a slow 10 s sampler (opt-in, shown as "Running now: yes (watching for trouble)"). Never wake a suspended GPU. The
daemon computes deltas, thresholds, hysteresis; the view formats. Process actions are daemon actions
(`sysmon.process.term|kill {pid}`) with confirmation in the view.

## Contract notes
`mod.sysmon`: `{available, interval_s, paused, cpu:{pct, per_core?, history}, mem:{used, total, swap?, zram?,
pressure?}, temp?:{c, source}, gpu?:{state:"awake"|"asleep", util?, vram?, temp?}, disk?:{read_bps, write_bps},
net?:{rx_bps, tx_bps}, load1, procs?:[{pid, name, cpu, mem}], trouble?:{kind, since, culprit?}}`.
Session 6 (rows 82, B24, I61, I62): `gpus[]` with `primary` (the GPU the tile shows: the only awake one, else the
busiest, else the boot VGA; a runtime-suspended GPU is listed as asleep and only its `runtime_status` is read);
`procs[]` rows carry `cmd` (full command line, the a11y description) and a `name` from the executable (Nix wrapper
marks removed, desktop entry name when one matches); the shell's own processes (this daemon, another kurashid of
the same user, the Quickshell frontend and Settings) carry the refusal reason `sysmon.error.shell` /
`sysmon.error.shell_other`, and `sysmon.end` re-checks before any signal. `KURASHI_SYSMON_ROOT` (tests only) replaces
`/proc`, `/sys` and the desktop entries and records signals instead of sending them.
Session 7 (row 100, I65): `primary` is the awake GPU that drives a connected output (connector `status`, read only while
two or more GPUs are awake; `boot_vga` breaks a tie; "the busiest" no longer decides). `name` is the desktop entry's
`Name[<session language>]`, else `Name`; the index is re-read when an applications directory changes, checked only
while `mod.sysmon.procs` is subscribed; a version- or hash-named executable takes the next meaningful directory above
it, else argv[0]. A kernel refusal (EPERM) after the owner check is `sysmon.error.refused`, shown on the row. A counter
that goes backwards (after a suspend) drops that sample and resets the baseline.

## Definition of done
- [x] bar widget states: normal / activity / critical / paused / unavailable sensor (W15 state shots)
- [x] panel with tiles, sparklines, per-core, processes + End/Force quit (confirm)
- [x] trouble face after sustained load with culprit; no flapping (test with synthetic samples)
- [x] GPU asleep never sampled (test reads runtime_status first)
- [x] no sampling without subscriber / trouble watch (paused-clock test)
- [~] screenshots (done); a11y text for sparklines exists, not verified with a screen reader; peek waits for K35 frontend (W16)

## Later
Disk usage per mount · network per interface · history export · alerts as notifications.
