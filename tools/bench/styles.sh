#!/bin/sh
# I330 (session 18): every style on the real stack, at rest — idle CPU and wakeups, PSS at one and two outputs, idle
# frames (commits/s) and mapped surfaces, popup latency — one measure.py run per style (passes a and b, no cycles), the
# load gate before each (--max-load 1.5, or $STYLES_MAX_LOAD). The config is the style alone with idle locking off.
# Results: results/styles-<style>.json, then a table on stdout (and results/styles-summary.md).
# Run inside `nix develop` after `cargo build --workspace --release`:  sh tools/bench/styles.sh [style ...]
set -u
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
cd "$ROOT" || exit 1
ALL=$(ls styles/*.toml | xargs -n1 basename | sed 's/\.toml$//')
SEL=${*:-$ALL}
CONF=$(mktemp -d)
status=0
for s in $SEL; do
  printf 'theme.style = "%s"\n[idle]\nenabled = false\n' "$s" > "$CONF/$s.toml"
  python3 tools/bench/measure.py --name "styles-$s" --daemon real --config "$CONF/$s.toml" --passes ab --cycles 0 \
    --idle "${STYLES_IDLE:-20}" --max-load "${STYLES_MAX_LOAD:-1.5}" --load-wait 120 --sandbox-prefix styles- \
    -- frontend/launch.sh > "$CONF/$s.log" 2>&1 || { echo "styles: $s failed (see $CONF/$s.log)" >&2; status=1; }
done
python3 - "$SEL" <<'PY' | tee tools/bench/results/styles-summary.md
import json, sys
rows = []
for s in sys.argv[1].split():
    try:
        d = json.load(open(f"tools/bench/results/styles-{s}.json"))
    except OSError:
        rows.append(f"| {s} | (no result) |||||||")
        continue
    a, b = d.get("pass_a") or {}, d.get("pass_b") or {}
    rows.append("| {} | {} | {} | {} | {} | {} | {} | {} |".format(
        s, a.get("idle_cpu_pct"), a.get("wakeups_per_s"), a.get("pss_mib_1out"), a.get("pss_mib_2out"),
        b.get("idle_commits_per_s"), b.get("mapped_layer_surfaces_idle"), b.get("popup_latency_ms_median")))
print("| style | idle CPU % | wakeups/s | PSS 1 out (MiB) | PSS 2 out | idle commits/s | mapped | popup ms |")
print("|---|---|---|---|---|---|---|---|")
print("\n".join(rows))
PY
exit $status
