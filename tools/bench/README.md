# tools/bench

Invisible, reproducible measurements of frontends (K3 bake-off, milestone budgets).

| File | Purpose |
|---|---|
| `sandbox.sh` | headless sway (gles2 by default → clients render on the GPU) with its own `XDG_RUNTIME_DIR` (`/tmp/kurashi-sb-<name>`) and private D-Bus; `start/env/stop/output-add` |
| `measure.py` | 3 passes per frontend, each in a fresh sandbox, against `kurashi-mock` or the real `kurashid` (`--daemon real`) → `results/<name>.json` |
| `budget.py` | the gate: compares a result with the budget table in `docs/BENCH.md`, exits 1 on any violation |
| `bin/` | untracked copies of `kurashid`, `kurashi`, `kurashi-mock` (the shared cargo target dir is overwritten by other worktrees, so copy right after building) |
| `testdata/` | `fail.json` (budget.py must exit 1), `unmeasurable.json` (n/a handling) |

## The gate (budgets as acceptance, CLAUDE.md rule 9)
```sh
export CARGO_TARGET_DIR=$HOME/.cache/kurashi-agents-target
nix develop -c cargo build --release -p kurashid -p kurashi -p kurashi-mock
mkdir -p tools/bench/bin && cp $CARGO_TARGET_DIR/release/{kurashid,kurashi,kurashi-mock} tools/bench/bin/
nix develop -c python3 tools/bench/measure.py --name frontend-real --daemon real -- qs -p frontend \
  && python3 tools/bench/budget.py tools/bench/results/frontend-real.json
python3 tools/bench/budget.py tools/bench/testdata/fail.json   # self-test: must exit 1
```
`--daemon real` starts `kurashid` in the sandbox with `XDG_{CONFIG,STATE,DATA,CACHE}_HOME` under the
sandbox runtime dir, the sandbox's own `DBUS_SESSION_BUS_ADDRESS`, no `NIRI_SOCKET`, and this
checkout as `KURASHI_DATA_DIR`. Daemon CPU/PSS/wakeups are reported as `daemon_*` next to the
frontend's; the "daemon + frontend" CPU budget uses `idle_cpu_pct_total`. The popup is driven
with `act island.expand` and the morph with `act island.next` (the real daemon has no `mock.*`).

`budget.py` rows are n/a (shown, not passed; exit 0 unless `--strict`) when the value cannot be
measured: no `WAYLAND_DEBUG` output from the client (`commits: "unmeasurable"`, never 0), or CPU
without a real daemon. "Popup input → first frame" is gated as one 60 Hz frame (16.7 ms).
Idle CPU is measured over `--idle` seconds (default 30; the budget names 10 min, pass `--idle 600`
for the full window). Mapped surfaces = layer surfaces whose last attach had a buffer, one output.
The per-output PSS delta is taken against the reading after the popup was closed again, so
popup memory that stays resident is not charged to the second output.

```sh
cargo build --release -p kurashi-mock -p kurashi
python3 tools/bench/measure.py --name <name> [--warmup 10 --idle 30 --passes abc] -- <run command>
```
- **Pass A (clean):** idle CPU %, wakeups/s (ctx switches, all threads), PSS @1 output, PSS with
  popup, PSS @2 outputs (hotplug), GPU MiB (`nvidia-smi -q -d PIDS`), hotplug survival.
- **Pass B (`WAYLAND_DEBUG=client`):** startup (launch → first `wl_surface.commit`), idle commits/s
  per surface, popup action → first commit latency (median of 5), island morph commits + frame
  pacing (p50/p99 gap). Lines are timestamped on arrival (libwayland stderr is unbuffered), so
  numbers are toolkit-independent.
- **Pass C (`strace -f -ttt`):** idle syscalls/s + top syscalls (ptrace_scope=1 → we launch the
  frontend as a child of strace).

Caveats: headless sway lacks ext-background-effect and IME; GPU numbers are NVIDIA-specific.
Never run against the user's session; `sandbox.sh stop` kills only processes whose environ
carries the sandbox runtime dir.
