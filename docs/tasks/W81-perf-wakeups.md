# W81 — Performance: animations that wake every window, the pinned sidebar's frame cost (B119, B120; Opus)

**Base.** `feat/s32-combined` (reset to `origin/feat/s32-combined` if your HEAD lacks it).
**Goal.** Measure first on nested niri with the user's look (`theme.look = "washi"`, two pinned sidebars as in the user's
profile if you can build it; `tools/bench/` has the tools: `just bench`, commits per window), then fix, then measure
again. Numbers into `docs/BENCH.md` (before/after, method).
- **B119:** any QML animation that starts draws a frame in every window of the shell (Qt's threaded render loop; a
  lyric line's highlight drew ~18 windows). Find the idle-time Behaviors/animations that start while nothing visible
  changes (bars, island, desk, sidebars) and gate them (rule 5: every animation/timer has a visibility gate), and find
  whether a running animation in one window really makes the others render (if it is Qt's render loop itself, say so
  with the evidence and what would avoid it: e.g. `QSG_RENDER_LOOP`, one animation driver per window).
- **B120:** a pinned sidebar costs ~11 ms of CPU per frame (mostly the render thread's swap) and 17–19 % of what is left
  while music plays (7.5 frames a second from the colour flow). Profile one frame (what redraws, layer count, effect
  sizes, ShaderEffect sources), cut it.
**Owned paths.** `frontend/**` except `frontend/components/ModuleMenu.qml` (W80), `frontend/components/sidebar/
SettingsSection.qml` and `frontend/core/Peeks.qml` (the lead's); `docs/BENCH.md`; `tools/bench/**`.
**Acceptance.** Before/after numbers for both (commits per second per window at rest and with the colour flow / an
animation running), the affected suites green (`just suites --changed`, never one by one), no visual change (shots
before/after on niri of the bar and a pinned sidebar). Build dir `~/.cache/kurashi-agents-target/w81`. Time box: report
by 12:40 with what is done.
