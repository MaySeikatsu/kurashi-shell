# Frontend bake-off (M0) — decides K3

Same probe, same task card (`tools/bakeoff/TASK-CARD.md`), five candidates, each built by a
Sonnet agent in its own worktree under `probes/<name>/`. The lead measures with `tools/bench`.

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

## Results
| | quickshell | iced | slint | gpui | gtk4 |
|---|---|---|---|---|---|
| _(filled in M0.7)_ | | | | | |
