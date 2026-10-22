#!/bin/sh
# W33 (docs/BENCH.md "2026-10-22"): the textured shell on the real stack. Nine scenarios (testdata/w33/*.toml) × three
# runs, interleaved (run 1 of every scenario, then run 2, then run 3) so drift during the set hits them alike. Each run is
# one measure.py call: pass a (idle CPU, wakeups, PSS), pass b (idle frames, popup, motion frames), pass m (motion CPU and
# wakeups); sandboxes w33-*; the load gate (--max-load 1.5) runs before every run and its result is in the run's JSON.
# Results: results/w33-<scenario>-r<run>.json, then w33-summary.py writes the medians (results/w33-<scenario>.json) and
# the table. Run inside `nix develop` (as the other bench recipes do): sh tools/bench/w33.sh [scenario ...]
set -u
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
cd "$ROOT" || exit 1
ALL="none kami paint-shadows spotlight pen-text controls carried fixed everything"
SCEN=${*:-$ALL}
status=0

# The motion script of a scenario, if it has one (the scripts live next to the configs).
script_of() {
  case $1 in
    spotlight) echo spotlight ;;
    pen-text) echo pen-text ;;
    carried | fixed) echo sidebar-cycle ;;
    *) echo "" ;;
  esac
}

for run in 1 2 3; do
  for s in $SCEN; do
    script=$(script_of "$s")
    extra=""
    [ -n "$script" ] && extra="--script tools/bench/testdata/w33/$script.script"
    # shellcheck disable=SC2086  # $extra is one optional flag pair, split on purpose
    python3 tools/bench/measure.py --name "w33-$s-r$run" --daemon real --config "tools/bench/testdata/w33/$s.toml" \
      $extra --passes abm --idle 10 --cycles 0 --max-load 1.5 --load-wait 600 --sandbox-prefix "" \
      -- frontend/launch.sh > /dev/null || { echo "w33: run $s r$run failed" >&2; status=1; }
  done
done

python3 tools/bench/w33-summary.py $SCEN || status=1
exit "$status"
