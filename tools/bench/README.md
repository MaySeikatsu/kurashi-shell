# tools/bench

Invisible, reproducible measurements of frontends (K3 bake-off, milestone budgets).

| File | Purpose |
|---|---|
| `sandbox.sh` | headless sway (gles2 by default → clients render on the GPU) with its own `XDG_RUNTIME_DIR` (`/tmp/kurashi-sb-<name>`) and private D-Bus; `start/env/stop/output-add` |
| `measure.py` | 3 passes per frontend, each in a fresh sandbox, against `kurashi-mock` → `results/<name>.json` |

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
