# Bench

Measured numbers per milestone. Method: `just bench …` (see `tools/bench/README.md`).
Always record: date, commit, machine, compositor, renderer, outputs, profile.

Machine A: 12 cores, 31 GiB RAM, NVIDIA GTX 1060 6 GB (driver 580.178), NixOS, niri 26.04.
Machine B: laptop, AMD Ryzen 7 6800H (8 cores / 16 threads), 38 GiB RAM, **hybrid GPU**: Radeon 680M iGPU
(Mesa 26.2.2, boot GPU — niri renders on it) + NVIDIA RTX 3070 Laptop 8 GB (open kernel module 595.99.02,
runtime PM), NixOS 26.11, niri 26.04. Procedure: `docs/RUNBOOK-MACHINE-B.md`. The sandbox picks the first
render node (renderD128 = the NVIDIA dGPU here); `KURASHI_RENDER_NODE=/dev/dri/renderD129` measures on the
iGPU, the GPU this machine's session actually uses.

**Per-machine baselines.** Budgets apply on every target machine; numbers are only comparable
within one machine (GPU driver floor differs: NVIDIA vs Mesa). Take each machine's baseline
**quiet**: no other compile jobs or agent sessions running (check `uptime` load ≈ idle), one
`just bench-gate` at a time. A result taken under load is labelled as such and never used as a
baseline.

## Budgets (v0.1)
| Metric | Budget |
|---|---|
| Idle frames, all windows, 30 s | ≤ 1 fps total |
| Idle CPU, daemon + frontend, 10 min | < 0.5 % |
| PSS frontend, core profile | ≤ 150 MiB @1 output, ≤ +6 MiB per extra output, measured vs. popup-closed (K16, K19; was ≤ 50 % of shellseikatsu) |
| Popup input → first frame | ≤ 1 frame after map |
| PSS growth over 20 panel open/close cycles (island, notification center, launcher; after 20 warm-up rounds) | ≤ 2 MiB |
| Mapped surfaces per output at idle | ≤ 4 |

## Baseline — shellseikatsu (2026-10-08, Quickshell 0.3.1, Qt 6.11.2, niri, 1 output)
| Metric | Value |
|---|---|
| RSS | 272–275 MB |
| PSS | 216 MB |
| Anonymous | 173 MB (QML JS heap 34 MB) |
| Avg CPU (1 h) | 3.5 % |
| Idle frames (after 2026-10-08 fixes, headless) | ~0.8 fps |

## Results

### 2026-10-22 — wave 32, textured shell (machine A, quiet)
`just bench-texture` = `tools/bench/w33.sh` on the real stack: nine scenarios × three interleaved runs (`measure.py --daemon real --config <scenario> --passes abm --idle 10 --warmup 10 --cycles 0 --max-load 1.5`, `frontend/launch.sh`), medians by `w33-summary.py` (`tools/bench/results/w33-<scenario>.json`, raw runs `-r1` to `-r3`; results are gitignored). Measured tree: `191fd68` (the driver's pass selection is the only change after `72db4d6`, which the first run of the set recorded; the measuring code is the same). Binaries: release build of `8cbce81` (no crate changed). Machine A: 12 cores, GTX 1060 (driver 580.178), headless sway on renderD128 (gles2), one 2560×1440 output. Load (1 min) at the start of each run was 0.36–1.10: all 27 runs quiet, none waited. The idle window is 10 s, not the budgets' windows (idle CPU is a 10 min budget, frames 30 s), so those rows are screens.

| scenario | theme in effect (checked in each run) | motion, after the rest measurements |
|---|---|---|
| none | no texture | – |
| kami | style kami: paper dots 0.55, shadows on, pen 0.35 | – |
| paint-shadows | oil paint, shadows on, depth 2 | – |
| spotlight | oil paint, `light.mode` spotlight | pointer swept across the bar for 5 s |
| pen-text | kami + `pen.text_*` 0.6 | quick card opened and held |
| controls | leather, `texture.controls` on | – |
| carried | squared paper, sheet carried | right sidebar opened and closed five times |
| fixed | squared paper, sheet fixed | as carried |
| everything | squared paper, scope everything (overlay) | – |

Medians of three runs; PSS and CPU of the frontend unless marked; `–` = not measured in that scenario.

| metric | none | kami | paint-shadows | spotlight | pen-text | controls | carried | fixed | everything |
|---|---|---|---|---|---|---|---|---|---|
| idle frames, 10 s (commits/s) | 2 | 3.1 | 0 | 0 | 0 | 0 | 0 | 0 | 0 |
| idle CPU, frontend (%) | 0.000 | 0.000 | 0.000 | 0.000 | 0.000 | 0.000 | 0.000 | 0.000 | 0.000 |
| idle CPU, daemon (%) | 8.348 | 8.746 | 8.445 | 8.545 | 8.844 | 8.546 | 8.348 | 8.447 | 8.349 |
| wakeups/s, frontend | 0.1 | 0.1 | 0.1 | 0.1 | 0.1 | 0.1 | 0.1 | 0.1 | 0.1 |
| wakeups/s, daemon | 34.1 | 32 | 31.9 | 38 | 32.9 | 33 | 33 | 32.7 | 33.1 |
| PSS frontend @1 output (MiB) | 177.6 | 201.0 | 227.8 | 221.9 | 203.8 | 211.9 | 225.8 | 225.8 | 249.9 |
| PSS per extra output (MiB, vs popup closed) | +10.50 | +10.60 | +19.80 | +20.05 | +10.60 | +18.90 | +17.85 | +19.05 | +42.40 |
| PSS daemon (MiB) | 27.3 | 29.8 | 33.4 | 32.8 | 30.6 | 29.7 | 30.9 | 31.4 | 30.5 |
| popup input → first commit (ms) | 85.1 | 45.0 | 104.1 | 101.7 | 48.4 | 104.3 | 102.4 | 102.6 | 81.8 |
| mapped layer surfaces, idle, 1 output | 3 | 3 | 3 | 3 | 3 | 3 | 3 | 3 | 4 |
| motion window (s) | – | – | – | 7.1 | 8.1 | – | 15.1 | 15.1 | – |
| motion frames (commits/s, all surfaces) | – | – | – | 140.1 | 3.6 | – | 30.5 | 30.5 | – |
| motion CPU, frontend (%) | – | – | – | 7.64 | 1.24 | – | 13.94 | 13.08 | – |
| motion CPU, daemon (%) | – | – | – | 8.63 | 9.05 | – | 8.70 | 8.70 | – |
| motion wakeups/s, frontend | – | – | – | 1020.8 | 22.1 | – | 332.8 | 341.1 | – |
| PSS frontend after motion (MiB) | – | – | – | 223.0 | 219.2 | – | 278.4 | 275.1 | – |

**Against the budgets** (`budget.py` on the medians). Passing: mapped surfaces (3; 4 with `everything`, at the limit) and idle frames in the six scenarios with the texture on (0 fps). Failing in every scenario: PSS at one output (178–250 MiB against 150), PSS per extra output (+10.5 to +42.4 MiB against +6), popup → first commit (45–104 ms against 16.7 ms) and idle CPU of daemon + frontend (8.3–8.8 % against 0.5 %). Also failing: idle frames in `none` (2.0 fps) and `kami` (3.1 fps). Not run: the open/close cycle row (`--cycles 0`).

**Deltas against `none`.** PSS at one output: +23 MiB kami (the look), +26 pen-text, +34 controls, +44 spotlight, +48 carried and fixed, +50 paint-shadows, +72 everything. Per extra output the texture adds +7 to +10 MiB (paint +9.3, spotlight +9.6, controls +8.4, carried +7.4, fixed +8.6), the overlay adds +32 (`everything`), and kami and pen-text add +0.1. The daemon's PSS grows by +2 to +6 MiB. Idle CPU and wakeups differ from `none` by nothing beyond the loop below. Popup: no texture effect (85 ms in `none`, 82 in `everything`, 102–104 ms in paint, spotlight, controls, carried and fixed); the kami look is lower (45–48 ms), not explained.

**Motion.** `spotlight`: 140 commits/s during the 7.1 s sweep (about 60 pointer events/s), frontend CPU 7.6 %, about 1,020 wakeups/s. `carried` and `fixed`: 30.5 frames/s over the 15 s of ten toggles, frontend CPU 13.9 % and 13.1 %, about 340 wakeups/s; the sheet mode changes what is drawn, not how often. `pen-text`: the quick card's own animation, 3.6 frames/s over 8.1 s, frontend CPU 1.2 %. The daemon stays at its idle level during every motion (8.6–9.1 %).

**Finding: the daemon's 8 % idle load is a config-watch loop, not the texture.** The daemon alone, with no frontend, idles at 8.2 % CPU and 37 wakeups/s when its config.toml exists, and at 0.00 % and 0 wakeups/s without one (diagnostic runs in the sandbox, not in the table). The default gate, which has no config file, measured 0.166 %. strace shows the loop: each read of config.toml by the daemon raises an inotify `IN_OPEN` (mask 0x20) on that file. The watcher in `crates/kurashid/src/config.rs` (`watch()`, notify 8.2.0, whose inotify backend subscribes to OPEN; its callback does not filter `EventKind::Access`) takes that for an edit, waits 150 ms and calls `store.reload()`, which reads config.toml, managed.toml, styles/, looks/ and profiles/ again. That is about 5.5 reloads a second and about 3,600 `statx` a second, with the frontend absent. Any config.toml triggers it. Not changed here (kurashid is outside this card's paths): ignore `Access` events in the callback, or drop `IN_OPEN` from the mask, then measure again. Check the other notify watchers of directories the daemon reads (`crates/kurashi-mod-tasks/src/service.rs`) for the same loop.

**Not resolved.** (1) Popup → first commit: 118 ms in the default gate with no texture (the 2026-10-09 gate measured 2.6–7.3 ms). The gate has no config file, so it is not the loop; the cause is not identified. (2) Idle frames of 2.0 to 3.1 fps in `none` and `kami` but 0 in the other seven scenarios: one diagnostic run of `none` saw no commits in 10 s, so the cause is unknown and may be transient.

**Default gate on this tree** (`just bench-gate`, no texture, default passes, 30 s idle): idle frames 0.67 fps (pass), idle CPU 0.166 % (pass), PSS 174.8 MiB with +9.3 per output (fail; limits 150 and +6), popup 118.2 ms (fail), +2.32 MiB over 20 panel cycles (fail; limit 2), mapped 3 (pass). Three violations; the gate exits 1 as designed.

### 2026-10-19 — web dock host (W17, machine B iGPU, headless sway, shared machine; `mods/webdock/test/test-host.sh` phase 4)
Total PSS of the web host's process tree (patched Quickshell + QtWebEngine 6.11 / Chromium 140: host, zygotes,
renderers) with local fixture pages: **1 kept site 389–393 MiB, 5 kept sites 403–420 MiB** (two runs). The host is its
own process (K38): it is not counted in the frontend budget (K16) and is gone after `unload_after` (0 MiB). Hidden: 0
Wayland requests and commits in 10 s. Phase 0 for comparison: plain Quickshell window 97 MiB, WebKitGTK window 294 MiB
(`archive/spikes/webengine-phase0/README.md`). Real web apps cost more; re-measure on a quiet machine.

### 2026-10-09 — harness self-test / Quickshell floor (commit eca978f)
Trivial Quickshell bar (one `PanelWindow` per screen, one `Text`), headless sway gles2,
NVIDIA GTX 1060. Not a probe — a lower bound for "anything on Quickshell".
| Metric | Value |
|---|---|
| PSS @1 output | **110.1 MiB** |
| PSS @2 outputs | 112.8 MiB (+2.7 per output) |
| GPU memory | 4 MiB |
| Idle CPU / wakeups / commits / syscalls | 0 / 0 / 0 / 0 |
| Startup (launch → first commit) | 172 ms |
→ ~40 % of shellseikatsu's 272 MB RSS is Quickshell/Qt baseline before any feature exists.

### 2026-10-09 — M0 bake-off, lead quiet re-measure (branch feat/m0-bakeoff)
One probe at a time, headless sway gles2, GTX 1060, `--warmup 10 --idle 30`. Full matrix: `BAKEOFF.md`.
| | quickshell | iced | slint (CPU) | gpui | gtk4 |
|---|---|---|---|---|---|
| PSS 1 out / popup / 2 out (MiB) | 144.0 / 148.7 / 155.1 | 154.7 / 160.1 / 160.1 | 25.2 / 27.6 / 27.8 | 148.5 / 151.1 / 153.5 | 156.1 / 233.5 / 234.2 |
| idle wakeups/s · syscalls/s · commits/s | 0 · 3.1 · 0.03 | 118 · 233 · 0 | 1.6 · 0 · 0 | 178 · 725 · 61.8 | 0 · 46 · 0.7 |
| startup ms · popup ms | 143 · 2.0 | 356 · 2.2 | 54 · 1.8 | 339 · 22.8 | 489 · 1.9 |
Quickshell probe vs budget: idle frames ✔, idle CPU ✔, popup ✔, PSS 144 ✔ under K16 (✘ under old 108).

### 2026-10-09 — bench gate, real stack (M7.2, `just bench-gate`)
Real `kurashid` (isolated dirs, sandbox bus) + `frontend/` (main 3f40f8b), headless sway gles2, 30 s idle.
| Metric | Value | Budget |
|---|---|---|
| idle frames | 0 fps | ≤ 1 ✔ |
| idle CPU daemon + frontend | 0 % | < 0.5 % ✔ (30 s window; `--idle 600` for 10 min) |
| PSS frontend @1 output | 95.0–119.7 MiB | ≤ 150 ✔ |
| PSS per extra output (vs popup-closed) | +0.8 MiB | ≤ +6 ✔ |
| popup input → first frame | 7.3 ms | ≤ 16.7 ✔ |
| mapped layer surfaces idle (1 output) | 1 | ≤ 4 ✔ |
| daemon PSS / CPU / wakeups | 8.5 MiB / 0 % / 0 | — |

### 2026-10-09 13:25 — bench gate after wave 7 (0470378), quiet machine A
Real `kurashid` + full UI via `frontend/launch.sh` (NVIDIA EGL pin), release binaries from main,
no other compile jobs (the first quiet baseline for machine A).
| idle fps | idle CPU | PSS @1 out | per extra output | popup → frame | 20-cycle growth | mapped surfaces | result |
|---|---|---|---|---|---|---|---|
| 0.03 | 0 % | 104.3 MiB | **+6.0** | 2.6 ms | +0.63 MiB | 3 | **0 violations** |
Headroom: 46 MiB at 1 output (was 12 before M3.2). The per-output row sits exactly at its limit
(+6.0 vs ≤ +6): watch it — the next surface added per output must pay for itself.
Same frontend against the mock: 118.8 MiB @1 out, 0 wakeups/s (`docs/BAKEOFF.md` re-measure).

### 2026-10-09 15:15–15:35 — bench gate after wave 8, quiet machine B iGPU (313f094)
Tray widget + tray menu + Bluetooth panel, hybrid EGL pin (Mesa on the Radeon), release binaries from main,
`KURASHI_RENDER_NODE=/dev/dri/renderD129`, load < 1, 4 runs.
| run | idle fps | idle CPU | PSS @1 out | per extra output | popup → frame | 20-cycle growth | result |
|---|---|---|---|---|---|---|---|
| 1 | 0 | 0 % | 115.5 MiB | **+6.5** ✘ | 3.6 ms | +1.30 MiB | 1 violation |
| 2 | 0.03 | 0 % | 114.5 MiB | +5.9 | 3.3 ms | +0.50 MiB | 0 violations |
| 3 | — | — | 114.3 MiB | **+6.7** ✘ | — | — | 1 violation |
| 4 | — | — | 114.9 MiB | +4.7 | — | — | 0 violations |
@1 output dropped ~10 MiB (123.5–126.9 → 114.3–115.5) as the Mesa-pin experiment predicted. **Per extra
output sits on its limit: mean ≈ +5.95, 2 of 4 runs over by ≤ 0.7 MiB** (before the wave: +4.5–5.6, so
within the ±1 MiB run-to-run spread — not yet attributable to wave 8). Budget unchanged (lead/user
decision); next step: attribute (A/B 6b13d56 vs 313f094, ≥ 3 runs each) and cut per-output cost.

### 2026-10-09 14:09–14:40 — bench gate, quiet machine B (e72690f)
Real `kurashid` + full UI via `frontend/launch.sh`, release binaries from main, no compile jobs (load < 1).
| GPU (render node) | idle fps | idle CPU | PSS @1 out | per extra output | popup → frame | 20-cycle growth | mapped surfaces | result |
|---|---|---|---|---|---|---|---|---|
| RTX 3070 dGPU (D128), run 1 | 0.03 | **5.80 %** ✘ | 106.1 MiB | +2.1 | 3.4 ms | +0.12 MiB | 3 | 1 violation |
| RTX 3070 dGPU (D128), run 2 | 0.03 | **5.73 %** ✘ | 106.2 MiB | +2.3 | 3.2 ms | +0.30 MiB | 3 | 1 violation |
| RTX 3070 dGPU (D128), run 3 | — | 0 % | — | — | — | — | — | 0 violations |
| Radeon 680M iGPU (D129), run 1 | 0.03 | 0.07 % | 126.9 MiB | +5.6 | 3.1 ms | −0.14 MiB | 3 | **0 violations** |
| Radeon 680M iGPU (D129), run 2 | 0 | 0 % | 123.5 MiB | +4.5 | 3.4 ms | +0.32 MiB | 3 | **0 violations** |
| iGPU, Mesa EGL pinned (experiment) | 0 | 0 % | 114.4 MiB | +5.1 | 3.0 ms | +1.80 MiB | 3 | 0 violations |

**The dGPU idle-CPU failures are a runtime-PM artefact, not a frontend loop:** a per-second timeline shows
0 ticks for ~45 s, then ~1.7 s of CPU on qs's *main thread* (inside the NVIDIA driver) exactly while the
RTX 3070 is `resuming` from runtime suspend (`/sys/bus/pci/devices/0000:01:00.0/power/runtime_status`),
then 0 again. A 30 s window that catches a resume fails; one that doesn't reads 0 %. Two consequences: on
the dGPU a resume also blocks the UI thread for ~2 s, and a hybrid laptop should never render the shell on
the dGPU (it also keeps the dGPU in use). niri renders on the iGPU here, so the **iGPU rows are machine B's
baseline**. Raw JSON: `tools/bench/baselines/machine-b-2026-10-09/` (dGPU gate JSON not kept).
Headroom on the iGPU: 23–27 MiB at 1 output; per extra output **+4.5–5.6 of ≤ +6** — as tight as machine
A. glvnd loads both EGL vendors on a hybrid (`launch.sh` pins only with one render node): pinning Mesa on
the iGPU saves ~10 MiB (114.4 MiB) → Kaizen card (pin the vendor of the GPU the session renders on).
Golden screenshots on machine B are pixel-identical to machine A's refs (same Nix fonts, pixman).

### 2026-10-09 — bench gate after wave 5 (b39974d): full UI on the real stack
Bar + Stage + island faces + toasts/center + launcher + lock, real `kurashid`, serial run.
| idle fps | idle CPU | PSS @1 out | per extra output | popup → frame | mapped surfaces | result |
|---|---|---|---|---|---|---|
| 0.03 | 0 % | 137.9 MiB | +4.0 | 3.9 ms | 3 | **0 violations** (headroom 12 MiB) |
Earlier "exited early / 6.4 fps" readings came from parallel agents sharing sandbox names — fixed
(sandbox names carry the pid).

## Mods (K41: an enabled mod's own cost, mod on vs off)
| Mod | Machine / renderer | Idle frames | Per output | Once | 20-cycle growth | Note |
|---|---|---|---|---|---|---|
| webdock (shell side, W20) | B, gles2 renderD129 | 0 commits / 10 s hidden | +6.2 MiB USS (median of 3; runs swing ~40 MiB) | +3.8 MiB USS (shared dock window, first reveal) | −0.9 MiB | PSS unusable on 2 outputs under gles2 (a ~1.9 TiB mapping, I93); bar widget +0.8 MiB PSS. Web host process: not yet measured (I79/BENCH) |
| webdock (web host process tree, W20) | B, sandbox | 0 commits / 10 s | — | 405–417 MiB PSS with 1 site kept; 409–434 MiB with 5 (two runs each); 0 sites: not measured | — | Own process (K38), gone after `unload_after`; Phase 0 was 255–262 MiB for one view in the hosting process alone |
| app dock (core, opt-in `dock.enabled`, W25-dock, K51) | B, gles2 renderD129, 1 output | 0 commits / 10 s hidden (autohide), 0 / 10 s shown | +6.9 MiB USS hidden (dock on vs off, medians of three: 152.5 vs 145.7; one output, so this includes the once-per-shell component load; the 4 px edge window is the only surface) | +2.2 MiB USS on the first show (the dock window, made then kept) | not measured | `DOCK_MEASURE=1 frontend/test-dock.sh`; absolute USS swung ~50 MiB between sessions on this shared machine (106 vs 152 MiB), deltas held |
