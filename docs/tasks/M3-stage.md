# Card M3-stage — frontend Stage sizing + per-output popups (K16 budget)

**Goal.** The frontend skeleton passes everything except memory: with the popup open or with 2
outputs PSS jumps from 144 to ~220 MiB because each `Stage` is a full-output overlay surface.
Get back under the K16 budget (≤ 150 MiB @1 output, ≤ +6 MiB per extra output, popup open
included) without losing first-frame-gated reveal, input masking or Escape handling.

**Owned paths:** `frontend/` (only `surfaces/`, `core/Store.qml` if needed, `README.md`, `shots/`).
Common rules: `docs/tasks/README.md`.

**Read:** `frontend/README.md`, `frontend/surfaces/*.qml`, `frontend/shell.qml`,
`archive/bakeoff-probes/quickshell/Bar.qml` (the probe used `PopupWindow` = xdg_popup and measured 148.7 MiB with the
popup open), `docs/ARCHITECTURE.md` §4, `docs/BENCH.md` budgets.

**Do:**
1. Measure first (`measure.py --name stage-before … -- qs -p frontend`) and find where the memory
   goes (full-screen buffer per output? Stage mapped on every output?). Write the finding in
   your report.
2. Size the Stage to its content (or switch the popup to `PopupWindow` on the bar if that is
   clearly cheaper — then explain how OSD/toasts would live without a full-screen surface).
   Only the output whose Island was clicked shows the popup: `runtime.ui.popup` is global today,
   so pick the focused output from `svc.workspaces` (the focused workspace's output) — no new
   protocol.
3. Keep Ma: 0 idle commits; nothing mapped at idle except bars.

**Acceptance (one command, repo root, inside `nix develop`):**
`python3 tools/bench/measure.py --name frontend --warmup 10 --idle 30 -- qs -p frontend` →
`pss_mib_popup` ≤ 150, `pss_mib_2out` ≤ `pss_mib_1out` + 6, `idle_commits_per_s` ≤ 0.05,
`popup_latency_ms_median` and `morph_commits` non-null, survived hotplug. Report before/after.
