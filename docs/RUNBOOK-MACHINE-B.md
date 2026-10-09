# Runbook — benchmark baseline on a second machine ("machine B")

Self-contained: assumes **no prior context** (no Claude memory, no chat history). Read
`CLAUDE.md` first (project rules), then follow this top to bottom. Machine A (where everything so
far was measured) is: 12 cores, 31 GiB RAM, NVIDIA GTX 1060 6 GB (driver 580.178), NixOS, niri 26.04.

## Why
The shell must meet the budgets in `docs/BENCH.md` on **every** target machine, and numbers are only
comparable within one machine (the GPU driver's memory floor differs: NVIDIA vs Mesa). This run
gives machine B its first quiet baseline, and re-measures the archived bake-off probes there.
**K3 (renderer = Quickshell) is fixed**: this is a record, not a re-decision. Do **not** modify or
extend anything under `archive/bakeoff-probes/` — other frameworks may be re-tested once the
Quickshell version is stable.

## Safety rules (from CLAUDE.md — binding)
- Never start the shell on the user's display. Everything here runs in a **headless sway sandbox**
  (`tools/bench/sandbox.sh`, own `XDG_RUNTIME_DIR` under `/tmp/kurashi-sb-*`, own D-Bus).
- Kill only PIDs you started (or whose environ carries the sandbox runtime dir). Never `pkill`.
- If the user runs another shell (e.g. shellseikatsu via `quickshell -p ./`), never touch it.
- No AI attribution / Co-Authored-By lines in commits.

## 0. Prerequisites
- Nix with flakes enabled; `git`; ~25 GB free disk (probe builds are large; gpui alone ~10 GB).
- A DRM render node (`ls /dev/dri/renderD*`) for the gles2 sandbox renderer. Without one the sandbox
  falls back to pixman (slower; note it in the results).
- 45–60 minutes with **no other compile jobs** during the measuring part (step 4). Check with
  `uptime` (load average ≈ idle) and `pgrep -c rustc` (0).

## 1. Get the repo and the toolchain
```sh
git clone git@github.com:MaySeikatsu/kurashi-shell.git ~/Projects/kurashi-shell
cd ~/Projects/kurashi-shell
nix develop -c just check        # fmt + clippy + all tests; must be green before measuring
```
Record the machine: CPU model + cores (`nproc`, `lscpu | grep 'Model name'`), RAM (`free -g`),
GPU + driver (`lspci | grep -i vga`; NVIDIA: `cat /proc/driver/nvidia/version`; else
`glxinfo -B` if available), distro, compositor in daily use.

## 2. Build what gets measured (compile phase — load is fine here)
```sh
# Release daemon/CLI/mock from main, copied where measure.py looks first:
nix develop -c sh -c 'unset CARGO_TARGET_DIR; cargo build --release -p kurashid -p kurashi -p kurashi-mock'
mkdir -p tools/bench/bin && cp target/release/{kurashid,kurashi,kurashi-mock} tools/bench/bin/
# The five archived probes (quickshell needs no build), in parallel; logs in tools/bench/results/logs/:
tools/bench/build-probes.sh      # JOBS=4 by default; expect 10–30 min (gpui is the long pole)
```
All four must print `rc=0`. If one fails, note the error and measure the rest — don't fix probes.

## 3. Golden screenshots (machine-specific references)
References depend on installed fonts, so machine B keeps its own set and never overwrites
`tools/golden/ref/` (machine A's):
```sh
nix develop -c sh -c 'KURASHI_BIN_DIR=$PWD/target/release KURASHI_GOLDEN_REF=tools/golden/ref-machine-b tools/golden/run.sh --update'
```
Open every PNG in `tools/golden/ref-machine-b/` and check it looks right (bar, island panel,
notification centre, launcher, session menu), then run it again without `--update`: it must pass
twice in a row (deterministic). Commit `tools/golden/ref-machine-b/`.

## 4. Measure (quiet phase — nothing else running)
```sh
uptime; pgrep -c rustc            # load ≈ idle, 0 rustc
nix develop -c tools/bench/rerun-probes.sh
```
~20 minutes. It measures, one sandbox at a time: the 5 probes and today's frontend against the mock
(`measure.py --warmup 10 --idle 30`, the M0.7 method), then `just bench-gate` (real `kurashid` +
full UI, budgets from `docs/BENCH.md`). It prints the gate table and one summary line per probe.
Raw JSON: `tools/bench/results/rerun-*.json`, `tools/bench/results/frontend-real.json` (gitignored).

## 5. Record and commit
1. `docs/BENCH.md`: fill in the "Machine B" line at the top (hardware from step 1) and add a section
   `### <date> — bench gate, quiet machine B (<commit>)` with the same table columns as machine A's
   `13:25` row (idle fps, idle CPU, PSS @1 out, per extra output, popup → frame, 20-cycle growth,
   mapped surfaces, result) and one line on headroom. If any budget fails, say which and by how much;
   **do not change budgets** — that is a decision for the lead/user.
2. `docs/BAKEOFF.md`: under "Quiet re-measure", add a machine-B table with the same rows/columns as
   machine A's, plus one paragraph comparing the two machines.
3. Copy each probe JSON (and the gate JSONs) to `tools/bench/baselines/<machine>-<date>/` —
   `archive/` stays untouched (user rule, session 4).
4. `docs/PROGRESS.md`: add a row `B.2 | Quiet baseline machine B | ✅ | <commit>, <one-line result>`.
5. Work on a branch, commit with a conventional message (`docs(bench): machine B baseline`),
   `git merge --no-ff` into `main`, push.

## Interpreting results (what matters)
- **Budgets** (BENCH.md) are acceptance criteria: idle ≤ 1 fps, idle CPU < 0.5 %, PSS ≤ 150 MiB @1
  output and ≤ +6 MiB per extra output, popup ≤ 1 frame, ≤ 2 MiB growth over 20 panel cycles, ≤ 4
  mapped surfaces per output. On machine A the per-output row sits exactly at +6.0 — watch it.
- `frontend/launch.sh` pins the NVIDIA EGL vendor only with NVIDIA and exactly one render node (saves
  ~13 MiB); on AMD/Intel or hybrid laptops it changes nothing — expect a different PSS floor.
- Slint's probe renders on the CPU, so its memory is not comparable to the GPU-rendered probes.
- **Hybrid GPUs:** the sandbox takes the first render node, which may be the dGPU. Find the GPU the
  session renders on (`/sys/class/drm/card*/device/boot_vga`, the compositor's open `/dev/dri` fds) and
  run the gate there too: `KURASHI_RENDER_NODE=/dev/dri/renderD<n> just bench-gate`. An NVIDIA dGPU with
  runtime PM costs ~1.7 s of client CPU per resume; an idle window that catches one fails the CPU budget.
- A noisy machine shows up as PSS swings of ±15 MiB between runs of the same build: re-run then.
