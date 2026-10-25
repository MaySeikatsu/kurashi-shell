# Card W35-perf — popup latency, idle frames, memory (B37, B34, B35/B7, I93)

**Why:** the W33 bench (docs/BENCH.md "2026-10-22 — wave 32, textured shell") found budget misses not explained by the
textures: popup input → first commit 45–118 ms (budget 16.7; 2026-10-09 gate 2.6–7.3 ms) — B37; idle commits 2.0/3.1 per
second in two scenarios — B34 (rule 5: idle is silent); frontend PSS 178 MiB at one output (budget 150) and +9.3…10.5
MiB per extra output (+6) — B35/B7; and the PSS reader counts the gles2 GPU mapping — I93. Budgets are acceptance
criteria (rule 9).

**Read first:** `CLAUDE.md`; `docs/tasks/README.md`; `docs/BENCH.md` (budgets, the W33 section and the 2026-10-09 gates);
`tools/bench/README.md`, `measure.py`, `w33.sh`; DECISIONS K16 (surfaces on demand) and the B7 attribution notes in
BACKLOG; `frontend/shell.qml`, `frontend/surfaces/Stage.qml` (the expand path), `frontend/core/Store.qml`.

**Task:**
1. **I93 first:** the PSS reader skips the GPU/driver mappings (or reports USS beside PSS) so per-output numbers mean
   something on gles2; note the change in BENCH.
2. **B37 popup latency:** measure the parts — `kurashi` CLI start + handshake, daemon action → document patch, frontend
   patch → Stage map → first commit — with timestamps (WAYLAND_DEBUG, daemon tracing, a `--latency` probe in measure.py
   that drives the popup through an already-open IPC connection so CLI start-up is not counted). Bisect against the
   2026-10-09 gate commit if the frontend part regressed (`git bisect` with the gate as the test). Fix what is ours.
3. **B34 idle frames:** find what commits 2–3 times a second at idle in `none`/`kami` (per-surface commit ids from
   WAYLAND_DEBUG → which window; then which item: a running animation, a Timer, a Canvas). Fix it (visibility gate, Ma).
4. **B35/B7 memory:** attribute the 178 MiB (QML engine, fonts, images, per-window scene graphs, Relief tiles) with A/B
   runs; cut what is cheap and safe (lazy Loaders for hidden surfaces, image sourceSize, shared tile sheets, font
   fallbacks); report what remains with numbers so the lead and the user can decide the budget.
5. Re-run `just bench-gate` and `just bench-texture` at the end (quiet machine: you are the only agent then) and add a
   BENCH section with before/after.

**Owned paths:** `tools/bench/**`, `docs/BENCH.md` (append), and the frontend files your fixes need — list them in the
report; coordinate: the lead merges W34 (morph) before you start, so Stage/Sidebar/Launcher/Toasts are free.

**Acceptance:** `just bench-gate` popup ≤ 16.7 ms median or a documented, measured reason; idle frames 0 in every
W33 scenario; PSS numbers with the fixed reader and a cut list with deltas.

**Env:** `CARGO_TARGET_DIR=$HOME/.cache/kurashi-agents-target/w35-perf CARGO_BUILD_JOBS=10` (release builds for benches);
sandbox names `w35-perf-…`; check the load average before each measurement (the W33 harness does). Model: opus.
