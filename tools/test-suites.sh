#!/usr/bin/env bash
# The frontend suites, in parallel (session 17, user's workflow). Each suite owns its sandbox (its own runtime dir, socket,
# bus), so several run side by side; a suite that fails under that load runs again alone, and only a failure alone counts
# (idle-silence and budget checks are timing-sensitive). Binaries are built once, first.
#
#   tools/test-suites.sh                 the merge set (below)
#   tools/test-suites.sh --changed [ref] only the suites a change touches (files changed since `ref`, default main, plus the
#                                        working tree): a suite named after a changed file, or whose script names it;
#                                        a change to frontend/core, crates/ or i18n/ runs the merge set
#   tools/test-suites.sh --all           every suite script
#   tools/test-suites.sh dock frame …    these (frontend/test-<name>.sh, or a path); after --changed/--all: added
#   -j N                                 parallel jobs (default 4)
#
# Run inside `nix develop`. Logs and the summary: $KURASHI_SUITES_OUT (/tmp/kurashi-suites/<time>/).
# Visual acceptance still happens on niri (tools/bench/niri-sandbox.sh): these are regression tests.
set -uo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
JOBS=4
MODE=merge
REF=main
PICK=()
while [ $# -gt 0 ]; do
  case "$1" in
    -j) JOBS=$2; shift 2 ;;
    --changed) MODE=changed; shift; if [ $# -gt 0 ] && [[ "$1" != -* ]] && git rev-parse -q --verify "$1" >/dev/null; then REF=$1; shift; fi ;;
    --all) MODE=all; shift ;;
    *) [ "$MODE" = merge ] && MODE=pick; PICK+=("$1"); shift ;;   # (with --changed or --all: added to that set)
  esac
done

# The set the lead runs before a merge (session 16–17); the others run with --all or by name.
MERGE_SET=(stage quick-sections dock sidebars sidebar-panel bars edge-modules frame polkit island-join settings)
path_of() {
  case "$1" in
    */*) echo "$1" ;;
    settings) echo settings/test.sh ;;
    greeter) echo greeter/test.sh ;;
    *) echo "frontend/test-$1.sh" ;;
  esac
}
ALL=$(ls frontend/test-*.sh settings/test*.sh greeter/test.sh mods/*/test/*.sh 2>/dev/null | grep -v 'test-launch.sh')

suites=()
case "$MODE" in
  merge) for s in "${MERGE_SET[@]}"; do suites+=("$(path_of "$s")"); done ;;
  all) mapfile -t suites <<< "$ALL" ;;
  pick) for s in "${PICK[@]}"; do suites+=("$(path_of "$s")"); done ;;
  changed)
    files=$( { git diff --name-only "$REF"...HEAD; git diff --name-only; git diff --name-only --cached; } | sort -u)
    if echo "$files" | grep -qE '^(frontend/core/|frontend/shell\.qml|crates/|i18n/|Cargo\.lock)'; then
      for s in "${MERGE_SET[@]}"; do suites+=("$(path_of "$s")"); done
    else
      declare -A want=()
      for f in $files; do
        case "$f" in frontend/*|settings/*|mods/*|greeter/*) ;; *) continue ;; esac
        stem=$(basename "${f%.*}")
        [ -n "$stem" ] || continue
        lower=$(echo "$stem" | tr '[:upper:]' '[:lower:]')
        for t in $ALL; do
          if [ "$(basename "$t" .sh)" = "test-$lower" ] || grep -qw -- "$stem" "$t"; then want[$t]=1; fi
        done
      done
      suites=("${!want[@]}")
    fi ;;
esac
if [ "$MODE" != pick ]; then for s in "${PICK[@]}"; do suites+=("$(path_of "$s")"); done; fi
mapfile -t suites < <(printf '%s\n' "${suites[@]}" | awk 'NF && !seen[$0]++')
if [ ${#suites[@]} -eq 0 ]; then echo "test-suites: nothing to run"; exit 0; fi

OUT=${KURASHI_SUITES_OUT:-/tmp/kurashi-suites/$(date +%Y%m%d-%H%M%S)}
mkdir -p "$OUT"
export CARGO_TARGET_DIR=${CARGO_TARGET_DIR:-$ROOT/target}
echo "test-suites: ${#suites[@]} suite(s), $JOBS at a time; logs in $OUT"
if ! cargo build -p kurashid -p kurashi -p kurashi-mock > "$OUT/build.log" 2>&1; then
  echo "test-suites: build failed (see $OUT/build.log)"; exit 1
fi

run_one() {   # run_one <script> <log> → prints "rc seconds"
  local s=$1 log=$2 t0=$(date +%s)
  timeout 1800 "$s" > "$log" 2>&1
  echo "$? $(( $(date +%s) - t0 ))"
}
declare -A rc=() secs=()
running=0
for s in "${suites[@]}"; do
  [ -x "$s" ] || [ -f "$s" ] || { echo "test-suites: no such suite: $s"; continue; }
  name=$(echo "$s" | sed 's|/|_|g; s|\.sh$||')
  ( r=$(run_one "$s" "$OUT/$name.log"); echo "$r" > "$OUT/$name.rc" ) &
  running=$((running + 1))
  if [ "$running" -ge "$JOBS" ]; then wait -n; running=$((running - 1)); fi
done
wait

failed=()
for s in "${suites[@]}"; do
  name=$(echo "$s" | sed 's|/|_|g; s|\.sh$||')
  read -r r t < "$OUT/$name.rc" 2>/dev/null || { r=99; t=0; }
  rc[$s]=$r; secs[$s]=$t
  [ "$r" = 0 ] || failed+=("$s")
done
# A failure under load runs again alone: only one that repeats counts.
for s in "${failed[@]}"; do
  name=$(echo "$s" | sed 's|/|_|g; s|\.sh$||')
  read -r r t <<< "$(run_one "$s" "$OUT/$name.alone.log")"
  rc[$s]="$r (alone; ${rc[$s]} under load)"; secs[$s]="${secs[$s]}+$t"
done

{
  printf '%-44s %-28s %s\n' suite result seconds
  for s in "${suites[@]}"; do printf '%-44s %-28s %s\n' "$s" "${rc[$s]}" "${secs[$s]}"; done
} | tee "$OUT/summary.txt"
bad=0
for s in "${suites[@]}"; do case "${rc[$s]}" in 0|"0 (alone"*) ;; *) bad=1 ;; esac; done
exit $bad
