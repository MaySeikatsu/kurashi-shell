# tools/bench

Invisible, reproducible measurements of frontends (K3 bake-off, milestone budgets).

| File | Purpose |
|---|---|
| `sandbox.sh` | headless sway (gles2 by default → clients render on the GPU) with its own `XDG_RUNTIME_DIR` (`/tmp/kurashi-sb-<name>`) and private D-Bus; `start/env/stop/output-add` |
| `wl_keys.py` | virtual keyboard on the sandbox seat (zwp_virtual_keyboard_v1, raw wire): `wl_keys.py tab space`, or `--serve` (one keyboard, one key line per stdin line); only the sandbox's own socket (eval `sandbox.sh start` first; refuses anything else) |
| `wl_pointer.py` | virtual pointer on the sandbox seat (zwlr_virtual_pointer_v1, raw wire): `wl_pointer.py move x y`, `click x y left/middle/right`, `sweep x0 y0 x1 y1 s` (about 60 motion events a second), or `--serve`; x, y are layout coordinates (the layout box comes from xdg-output); same sandbox-socket rule |
| `measure.py` | passes per frontend, each in a fresh sandbox, against `kurashi-mock` or the real `kurashid` (`--daemon real`) → `results/<name>.json`. `--config FILE` (real): the daemon's user config.toml. `--script FILE` (real): a motion script (`pre` lines, `<t> act …`, `<t> sweep …`, `window s`); pass `m` measures CPU and wakeups during it, pass `b` counts its frames. `--max-load F`: waits for the 1-minute load average below F and records it. `--sandbox-prefix`: sandbox names (default `bench-`). W35: `--latency N` (real daemon) adds N popup rounds sent through one open IPC connection and splits the popup time into CLI → daemon patch → first commit; `--wl-log FILE` writes pass B's `WAYLAND_DEBUG` lines (and the frontend's log lines) with their arrival time; `--smaps-dump DIR` writes each PSS reading's mappings (KiB per path); `--popup-action NAME` measures another popup (e.g. `quick.toggle`) |
| `budget.py` | the gate: compares a result with the budget table in `docs/BENCH.md`, exits 1 on any violation |
| `w33.sh`, `w33-summary.py` | the textured-shell set (`just bench-texture`): 9 scenarios × 3 interleaved runs, medians → `results/w33-<scenario>.json` and a metric × scenario table; `W33_MAX_LOAD` (default 1.5) and `W33_PREFIX` (sandbox names) |
| `bin/` | untracked copies of `kurashid`, `kurashi`, `kurashi-mock` (the shared cargo target dir is overwritten by other worktrees, so copy right after building) |
| `testdata/` | `fail.json` (budget.py must exit 1), `unmeasurable.json` (n/a handling), `w33/` (the texture scenarios' configs and motion scripts) |

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
  popup, PSS @2 and @3 outputs (hotplug; the gate takes the mean of the two deltas), GPU MiB (`nvidia-smi -q -d PIDS`), hotplug survival.
  PSS is summed from `/proc/<pid>/smaps` **without the GPU driver's device mappings** (`/dev/nvidia*`, `/dev/dri/*`,
  `/dev/kfd`: device memory, ~1.9 TiB on two gles2 outputs in W20, I93); each reading also has `uss_*` (private clean +
  dirty, the same mappings left out) and `*_by` (PSS per mapping class: anon, lib, font, shm/QML heap, gpu_map, file).
  Numbers before W35 counted the GPU mappings (`smaps_rollup`): add `*_by.gpu_map` to compare (~8 MiB at one output on
  machine A, ~15 once the popup has been open).
- **Pass B (`WAYLAND_DEBUG=client`):** startup (launch → first `wl_surface.commit`), idle commits/s
  per surface (`idle_commits_by_layer`: by layer-shell namespace; `idle_bursts`: each burst with its wall-clock time — a
  burst at hh:mm:00 is the bar clock's minute flip), popup action → first commit latency (median of 5), island morph
  commits + frame pacing (p50/p99 gap). Lines are timestamped on arrival (libwayland stderr is unbuffered), so
  numbers are toolkit-independent. Popup rounds (W35, B37) start from rest — the popup's window (`kurashi-stage`) has
  committed nothing for 0.3 s (`popup_rounds_unsettled` counts rounds that waited 3 s in vain) — and count only that
  window's first commit; before W35 a round could start while the previous close still folded and take its next frame.
- **Pass C (`strace -f -ttt`):** idle syscalls/s + top syscalls (ptrace_scope=1 → we launch the
  frontend as a child of strace).

Caveats: headless sway lacks ext-background-effect and IME; GPU numbers are NVIDIA-specific.
Never run against the user's session; `sandbox.sh stop` kills only processes whose environ
carries the sandbox runtime dir.
