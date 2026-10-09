#!/usr/bin/env bash
# Quiet re-measure: archived probes (unchanged) + the current frontend against the mock + the
# real-stack budget gate. One headless sandbox at a time; run ONLY on an otherwise idle machine
# (check `uptime` and `pgrep -c rustc` first). Run inside `nix develop` at the repo root, after
#   tools/bench/build-probes.sh   and   release binaries copied to tools/bench/bin/ (see BENCH.md).
# Results: tools/bench/results/rerun-<name>.json (+ logs/), gate verdict at the end of logs/bench-gate.log.
set -uo pipefail
R=$(git -C "$(dirname "$0")" rev-parse --show-toplevel)
P=$R/archive/bakeoff-probes
L=$R/tools/bench/results/logs
mkdir -p "$L"
cd "$R"
m() { local name=$1; shift; echo "### $name $(date +%H:%M:%S)"; timeout 600 python3 tools/bench/measure.py --name "$name" --warmup 10 --idle 30 -- "$@" > "$L/m-$name.log" 2>&1; echo "rc=$?"; }
libs() { nix develop "$1" -c sh -c 'printf %s "$LD_LIBRARY_PATH"' 2>/dev/null; }

m rerun-quickshell qs -p "$P/quickshell"
[ -x "$P/gtk4/result/bin/probe-gtk4" ] && m rerun-gtk4 "$P/gtk4/result/bin/probe-gtk4"
[ -x "$P/slint/target/release/kurashi-probe-slint" ] && m rerun-slint env "LD_LIBRARY_PATH=$(libs "$P/slint")" "$P/slint/target/release/kurashi-probe-slint"
[ -x "$P/iced/target/release/kurashi-probe-iced" ] && m rerun-iced env "LD_LIBRARY_PATH=$(libs "$P/iced")" "$P/iced/target/release/kurashi-probe-iced"
[ -x "$P/gpui/target/release/probe-gpui" ] && m rerun-gpui "$P/gpui/run.sh"
m rerun-frontend-mock "$R/frontend/launch.sh"
echo "### bench-gate $(date +%H:%M:%S)"
timeout 900 just bench-gate > "$L/bench-gate.log" 2>&1; echo "rc=$?"
tail -9 "$L/bench-gate.log"
python3 - "$R" <<'PY'
import json, sys, pathlib
r = pathlib.Path(sys.argv[1]) / "tools/bench/results"
keys = ["pass_a.pss_mib_1out", "pass_a.pss_mib_popup", "pass_a.pss_mib_2out", "pass_a.idle_cpu_pct",
        "pass_a.wakeups_per_s", "pass_c.idle_syscalls_per_s", "pass_b.idle_commits_per_s",
        "pass_b.startup_ms", "pass_b.popup_latency_ms_median", "pass_b.morph_commits",
        "pass_b.morph_frame_ms_p99"]
def get(d, k):
    for p in k.split("."):
        d = d.get(p) if isinstance(d, dict) else None
    return d
for n in ["quickshell", "iced", "slint", "gpui", "gtk4", "frontend-mock"]:
    f = r / f"rerun-{n}.json"
    if f.exists():
        d = json.loads(f.read_text())
        print(n.ljust(14), " ".join(f"{k.split('.')[1]}={get(d, k)}" for k in keys))
PY
