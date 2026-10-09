# Frontend bake-off (M0) — decides K3

Same probe, same task card (`tools/bakeoff/TASK-CARD.md`), five candidates, each built by a
Sonnet agent in its own worktree under `archive/bakeoff-probes/<name>/`. The lead measures with `tools/bench`.

## Candidates
1. **quickshell** — Quickshell 0.3.x (Qt 6 / QML) thin view
2. **iced** — iced 0.14 + iced_layershell / iced_sessionlock (wgpu; tiny-skia noted)
3. **slint** — Slint + own SCTK layer-shell glue (layer-shika allowed for the probe only — AGPL)
4. **gpui** — GPUI (+ gpui-component), layer-shell `WindowKind::LayerShell`
5. **gtk4** — GTK4 + Relm4 + gtk4-layer-shell

## Probe (identical everywhere)
bar on every output (clock, workspaces, volume slider bound via intents) · anchored popup with
first-frame-gated reveal · two-face Island morph (scroll/`mock.face`) · blur via
ext-background-effect-v1 · one custom shader effect · IME text field · theme tokens from the
`theme` document · one runtime-loaded mod widget from `mods.probe` (render the vocabulary).

## Metrics
**Runtime:** PSS idle (1 and 2 outputs) · PSS popup open · GPU memory · idle CPU 10 min ·
idle frames 30 s · wakeups/syscalls (`strace -c -f` 60 s, `perf stat` cs) · startup ms ·
popup input→frame ms · animation frame-time p99.
**Capability gates** (✔/✘/partial): layer-shell any edge + exclusive zone · popups on layer
surfaces · session lock · screencopy · blur binding · custom shader · IME · fractional scale ·
output hotplug.
**Developer workload:** clean build s · incremental rebuild s (1-line UI change) · live preview /
hot reload (✔/✘, latency) · probe LOC · binary size · dependency count · docs quality (1–5) ·
**agent efficiency** (turns, tokens, compile-fix iterations, unfinished items).

## Weights
runtime 35 % · capability 30 % (blur, popups, lock, IME are hard gates) · dev workload 25 % ·
ecosystem/maturity 10 %. QML stays default unless a candidate passes all gates and wins overall.

## Results (M0.7, 2026-10-09, lead re-measure)
Quiet run: one probe at a time, headless sway gles2, NVIDIA GTX 1060, `measure.py --warmup 10 --idle 30`,
binaries from the merged probe commits. Raw JSON: `archive/bakeoff-probes/<name>/bench-lead.json` (the agents' own
`bench.json` were taken while 4 other agents compiled and ran GPU clients — shared driver pages
diluted PSS; **don't use them for memory**).

### Runtime
| | quickshell | iced | slint | gpui | gtk4 |
|---|---|---|---|---|---|
| PSS 1 output (MiB) | 144.0 | 154.7 | **25.2**¹ | 148.5 | 156.1 |
| PSS popup open | 148.7 | 160.1 | 27.6 | 151.1 | 233.5² |
| PSS 2 outputs | 155.1 | 160.1 | 27.8 | 153.5 | 234.2 |
| GPU memory (MiB) | 4 | 15 | 0¹ | 18 | 6 |
| idle CPU % | 0.0 | 0.1 | 0.03 | 0.27 | 0.0 |
| idle wakeups/s | **0** | 117.8 ✘ | 1.6 | 177.9 ✘ | 0 |
| idle syscalls/s | 3.1 | 233 ✘ | **0** | 725 ✘ | 46 |
| idle commits/s | 0.03 | 0 | 0 | 61.8 ✘ | 0.7³ |
| startup ms | 143 | 356 | **54** | 339 | 489 |
| popup input→commit ms (median) | 2.0 | 2.2 | 1.8 | 22.8 | 1.9 |
| morph commits / p99 frame ms | 21 / 17.1 | 23 / 16.6 | 21 / 16.6 | 93⁴ / 16.9 | 15 / 17.5 |
| survived hotplug | ✔ | ✔ | ✔ | ✔ | ✔ |

¹ Slint probe renders on the **CPU into wl_shm** (software renderer, no GPU driver mapped). A GPU-rendered
Slint pays the same driver floor as everyone else; its memory lead is bought with CPU animation and no shaders.
² GTK popup is a second GL layer surface (+77 MiB). ³ Persisted in both runs (21 commits in 30 s; not just
the minute clock patch). ⁴ Inflated by gpui's never-ending frame loop.

Driver floor (Quickshell probe, smaps breakdown of 144 MiB): libnvidia* 26.6 · Qt libs 21.2 · other
libs (ICU data, fontconfig, …) 49.1 · anon/heap 46.4 (includes driver allocations).

### Quiet re-measure (2026-10-09 13:11–13:29, after wave 7) — record only, K3 unchanged
Probes rebuilt from `archive/bakeoff-probes/` exactly as merged (no source changes), measured one at a
time on an otherwise idle machine (no compile jobs, load < 2), same method as M0.7 (`measure.py
--warmup 10 --idle 30`, mock daemon, headless sway gles2, GTX 1060). Raw JSON:
`archive/bakeoff-probes/<name>/bench-rerun-2026-10-09.json`. Last column: today's Quickshell frontend
(`frontend/launch.sh`, the real UI, not a probe) against the same mock.

| | quickshell | iced | slint¹ | gpui | gtk4 | frontend (mock) |
|---|---|---|---|---|---|---|
| PSS 1 output (MiB) (M0.7) | **123.4** (144.0) | 118.9 (154.7) | 22.1 (25.2) | 112.9 (148.5) | 78.0 (156.1) | 118.8 |
| PSS popup open | 128.5 | 124.0 | 22.7 | 113.7 | 129.3 | 121.4 |
| PSS 2 outputs | 132.4 | 124.0 | 22.7 | 114.7 | 131.2 | 127.1 |
| idle CPU % | 0.0 | 0.17 | 0.0 | 0.43 | 0.07 | 0.0 |
| idle wakeups/s | 0.2 | 118.5 ✘ | 0.0 | 178.2 ✘ | 1.4 | 0.0 |
| idle syscalls/s | 0.0 | 229.9 ✘ | 5.9 | 719.5 ✘ | 7.6 | 4.4 |
| idle commits/s | 0.0 | 0.0 | 0.0 | 61.2 ✘ | 0.7 | 0.0 |
| startup ms | 155 | 358 | 65 | 371 | 532 | 193 |
| popup input→commit ms (median) | 2.2 | 2.3 | 2.1 | 23.4 | 1.9 | 2.6 |
| morph commits / p99 frame ms | 21 / 17.2 | 23 / 17.5 | 23 / 17.4 | 92 / 18.2 | 20 / 16.7 | 22 / 17.5 |

Reading: every probe is 15–80 MiB lighter than in M0.7, which was measured while other agents held
GPU driver pages; the quiet numbers are the better baseline. Behavioural findings are unchanged
(iced/gpui never idle; gpui commits forever; Slint is still CPU-rendered, ¹ not comparable). GTK4's
1-output PSS halved (78 MiB) but its popup still costs +51 MiB (a second GL surface), landing level
with Quickshell once opened. No result reopens K3 (its re-evaluation clause asks for IME + blur +
session lock + hot reload, which the numbers don't speak to). Re-test other frameworks once the
Quickshell version is stable.

### Capability (✔ / partial / ✘; hard gates **bold**)
| | quickshell | iced | slint | gpui | gtk4 |
|---|---|---|---|---|---|
| layer-shell + exclusive zone | ✔ | ✔ | ✔ (own SCTK backend) | ✔ (zed git) | ✔ |
| multi-output + hotplug | ✔ | ✔ (own wl_output watcher) | ✔ | partial (2nd connection, no remove) | ✔ |
| **popup on layer surface** | ✔ xdg_popup | ✔ xdg_popup | partial (2nd layer surface) | partial (2nd layer surface) | partial (2nd layer surface) |
| first-frame-gated reveal | ✔ (Qt frameSwapped) | partial (RedrawRequested) | ✔ (wl frame callback) | partial (first render) | partial (frame clock) |
| **session lock** | ✔ WlSessionLock | ✔ iced_sessionlock | ✔ SCTK | ✘ | ✘ (raw protocol only) |
| screencopy | ✔ ScreencopyView | ✘ | raw only | partial (feature) | ✘ |
| **blur ext-background-effect** | ✔ bound¹ | ✘ not done (feasible) | ✔ raw, bound¹ | ✘ KDE blur only | ✔ raw, bound¹ |
| custom shader | ✔ ShaderEffect | ✔ wgpu shader widget | ✘ CPU image | ✘ CPU quads | ✔ GLArea (GskGLShader dead) |
| **IME text-input-v3** | ✔² | partial² | ✘ (custom platform) | ✔² | ✔² |
| fractional scale | ✔ | ✔ | ✘ (fixed 1) | ✔ | ✔ |
| runtime mod UI | ✔ Loader tree | ✔ Value→Element | ✔ slint-interpreter | ✔ Value→AnyElement | ✔ widget tree |
| theme tokens at runtime | ✔ | ✔ | partial (easing recompiles) | ✔ | ✔ (generated CSS) |
| **hard gates passed** | **4/4** | 2/4 | 2/4 | 1/4 | 2/4 |

¹ Bound but unverified — headless sway has no ext-background-effect global. ² Framework capability; IME
can't be exercised headless.

### Developer workload
| | quickshell | iced | slint | gpui | gtk4 |
|---|---|---|---|---|---|
| clean build | none | ~6 min | ~255 s | 569 s | ~110 s cargo / 200 s nix |
| incremental (1 UI string) | 0 s | 13 s | 100–125 s | ~156 s | 10.4 s |
| hot reload | ✔ sub-second | ✘ | ✘ | ✘ | ✘ (CSS via Inspector) |
| probe LOC | ~520 QML+GLSL | 1169 | ~1150 + 261 .slint | 1443 | 939 |
| binary / deps | n/a | 20 MB / 346 | 27 MB / 291 | 26 MB / 594 | 1 MB / 125 |
| docs (1–5) | 3 | 2 | 3 | 2 | 3 |
| agent tokens / tool uses / minutes | **103k / 42 / 7.2** | 190k / 79 / 29.9 | 191k / 81 / 32.0 | 176k / 84 / 32.9 | 173k / 69 / 29.9 |
| compile-fix iterations | 4 (QML runtime errors) | 3 + 1 runtime | 1 | 2 | 4 + 2 pivots |
Agent numbers: same Sonnet model and card; Quickshell has no compile step, so tool-use counts are not fully
comparable — wall time and tokens are.

### Score (0–10 per axis, weighted)
| | runtime 35 % | capability 30 % | dev 25 % | ecosystem 10 % | **total** |
|---|---|---|---|---|---|
| quickshell | 8 | 9 | 10 | 7 | **8.7** |
| gtk4 | 6 | 6 | 6 | 8 | 6.2 |
| slint | 9 (CPU-rendered) | 4 | 4 | 7 | 6.1 |
| iced | 5 | 6 | 4 | 6 | 5.2 |
| gpui | 2 | 3 | 2 | 4 | 2.5 |

### Verdict → K3
Quickshell/QML is the only candidate that passes all four hard gates, wins dev workload by a wide
margin (only hot-reload option; ~4× cheaper per agent task) and is idle-silent. It does **not** win
memory: ~144 MiB is over the v0.1 PSS budget (see K16). No native candidate came close enough on
gates to justify a live niri IME/blur test. Re-evaluate if a native stack passes IME + blur + lock
with hot reload, or if Quickshell blocks a feature / feel goal (K3).
