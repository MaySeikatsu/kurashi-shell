# Card M3-memory — memory headroom (Kaizen) + leak-cycle gate

**Goal.** Get ≥ 20 MiB of headroom under the K16 budget (target: real stack ≤ 130 MiB @1 output
with every surface present, mock popup ≤ 135 MiB) **and** make open/close leaks visible to the gate.
You are the only agent in `frontend/` and `tools/bench/` right now.

**Owned paths:** `frontend/` (all), `tools/bench/`. Common rules: `docs/tasks/README.md`.

**Read:** `docs/DECISIONS.md` K16, K19; `docs/BENCH.md` (latest gate: 137.9 MiB real, 150.5 mock
popup); `frontend/README.md`; `tools/bench/README.md`.

**Do:**
1. **Measure first, per surface:** PSS with each surface (Bar, Stage, Island faces, Toasts, Center,
   Launcher, Lock) removed one at a time (real daemon, several runs, report mean ± spread). Write the
   table into your report and `docs`-free: put it in `frontend/README.md` § Memory.
2. **Cycle test in the bench:** a pass that opens/closes each panel 20× (`act island.expand`,
   `act notifications.center`, `act launcher.toggle`, `act ui.close`) and reports PSS delta; budget
   row: **≤ 2 MiB growth over 20 cycles** (add it to `budget.py`; the lead adds the BENCH.md row —
   put the exact row text in your report).
3. **Trim:** content of rarely used surfaces created lazily via `Loader { active: … }` *inside* a
   permanently mapped surface (never unmap per open — K19 leak), or kept but with `asynchronous`
   components; drop dead probe bits (Bar `clockText/mediaText`, `mods.probe` watch when absent);
   avoid duplicate `Watch`es of the same doc; check font/glyph caches (one font family + JP fallback);
   image caches for art/icons (`sourceSize`, `cache: false` where one-off). Re-measure after each step.
4. Keep everything else green: idle 0 frames, popup ≤ 1 frame, `frontend/test-real.sh`.

**Acceptance:** `just bench-gate` (alone, real daemon) 0 violations incl. the new cycle row, PSS
@1 out ≤ 130 MiB; mock bench popup ≤ 135 MiB. If the target is unreachable, report the per-surface
table and the best you got — do not change budgets.
