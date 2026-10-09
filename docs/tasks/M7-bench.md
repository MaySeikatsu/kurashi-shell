# Card M7-bench — budgets as automated acceptance (rule 9)

**Goal.** `docs/BENCH.md` budgets become a command that passes or fails, for the real stack
(kurashid + frontend), not just the mock — so every frontend/daemon change can be gated.

**Owned paths:** `tools/bench/`. Common rules: `docs/tasks/README.md` (read first).

**Read:** `tools/bench/measure.py`, `tools/bench/sandbox.sh`, `docs/BENCH.md` (budgets, K16),
`docs/DECISIONS.md` K16, `frontend/README.md`, `crates/kurashid/src/main.rs` (what env it needs).

**Build:**
1. `measure.py --daemon real|mock` (default mock): `real` starts the built `kurashid` inside the
   sandbox with fully isolated `XDG_CONFIG_HOME/STATE/DATA/CACHE`, `KURASHI_SOCKET`, the sandbox's
   `DBUS_SESSION_BUS_ADDRESS`, no `NIRI_SOCKET`. Daemon PSS/CPU/wakeups are measured and reported
   separately from the frontend's (budget "daemon + frontend" idle CPU).
2. Commit counting relies on `WAYLAND_DEBUG=client` (libwayland only): detect a client that
   prints no wayland debug at all and report `commits: "unmeasurable"` instead of 0 (Shōjiki).
3. `tools/bench/budget.py <result.json> [--budgets docs/BENCH.md]`: parse the budget table, compare,
   print a pass/fail table, exit non-zero on any violation. Budgets measured headless that can't
   apply (e.g. GPU) are marked n/a, not passed.
4. `tools/bench/README.md`: how to run the gate: e.g.
   `python3 tools/bench/measure.py --name frontend-real --daemon real -- qs -p frontend && python3 tools/bench/budget.py tools/bench/results/frontend-real.json`.
   (Adding a `just` recipe is the lead's job — put the exact line in your report.)
5. Binaries: copy `kurashid`/`kurashi`/`kurashi-mock` from the shared target dir right after
   building (they get overwritten by other worktrees, see common rules).

**Acceptance (one command):** the README gate line runs green against the current `frontend/`
with `--daemon real` — or, if a budget genuinely fails, `budget.py` exits non-zero and your report
names the failing budget with numbers (that is a valid outcome; do not tune budgets). Plus a
self-test: `python3 tools/bench/budget.py tools/bench/testdata/fail.json` exits 1.
