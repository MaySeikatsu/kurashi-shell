#!/usr/bin/env bash
# The frontend suites, in parallel (session 17, user's workflow). Each suite owns its sandbox (its own runtime dir, socket,
# bus), so several run side by side; a suite that fails under that load runs again alone, and only a failure alone counts
# (idle-silence and budget checks are timing-sensitive). Binaries are built once, first.
#
#   tools/test-suites.sh                 the merge set (below)
#   tools/test-suites.sh --changed [ref] only the suites a change touches (files changed since `ref`, default main, plus the
#                                        working tree): a suite named after a changed file, or whose script names it;
#                                        a change inside one mod (crates/kurashi-mod-<id>, mods/<id>, i18n/*/mod-<id>.toml)
#                                        runs that mod's suites; a suite's `# covers: <path prefix> …` line (its first
#                                        12 lines) claims paths under crates/ and i18n/; any other change to
#                                        frontend/core, crates/ or i18n/ runs the merge set (I545)
#   --list                               print the suites the arguments select and stop (no build, no run)
#   A suite's `# needs: example:<package>/<name> feature:test-mods` line (its first 12 lines) names what the plain build
#   lacks; the runner builds it (I579).
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
LIST=0
PICK=()
while [ $# -gt 0 ]; do
  case "$1" in
    -j) JOBS=$2; shift 2 ;;
    --changed) MODE=changed; shift; if [ $# -gt 0 ] && [[ "$1" != -* ]] && git rev-parse -q --verify "$1" >/dev/null; then REF=$1; shift; fi ;;
    --all) MODE=all; shift ;;
    --list) LIST=1; shift ;;
    *) [ "$MODE" = merge ] && MODE=pick; PICK+=("$1"); shift ;;   # (with --changed or --all: added to that set)
  esac
done

# The set the lead runs before a merge (session 16–17); the others run with --all or by name.
MERGE_SET=(mods/handwriting/test-outlines.sh mods/webdock/test/test-real.sh mods/webdock/test/test-card.sh mods/webdock/test/test-background.sh card-edges light-outputs corners sheet-shadow popover-joins window-frame terminals browsers stage quick-sections dock sidebars sidebar-panel bars edge-modules frame polkit island-join settings settings-dock motion recipes dynamic-media wallpaper-grade module-menu context-menus mods/webdock/test/test-page-menu.sh niri-motion previews font-mix bar-fit mods/handwriting/test-handwriting.sh bar-hover colour-blend quick-modules glow edges follow outline media-idle ws-motion settings-groups osd appearance-menu mods/terminal/test/test-terminal-outputs.sh mods/sessions/test/test-sessions.sh mod-contract mod-host launcher media mods/lyrics/test-lyrics.sh)
path_of() {
  case "$1" in
    */*) echo "$1" ;;
    settings) echo settings/test.sh ;;
    settings-dock) echo settings/test-dock.sh ;;
    settings-groups) echo settings/test-groups.sh ;;
    greeter) echo greeter/test.sh ;;
    *) echo "frontend/test-$1.sh" ;;
  esac
}
# I546: the mods keep their suites in `mods/<id>/test/` or beside the manifest; `shots-*.sh` and `real-shell.sh` there are
# review helpers, not suites.
ALL=$(ls frontend/test-*.sh settings/test*.sh greeter/test.sh mods/*/test/test-*.sh mods/*/test-*.sh 2>/dev/null | grep -v -e 'test-launch.sh' -e 'test-lib.sh')
# I555: the core reads these mods' crates or documents by name, so a change inside them is not theirs alone.
CORE_COUPLED=" weather wallpaper "
# I319: every run's sandboxes carry a prefix of their own, so two runners (the lead's and an agent's) never share a
# sandbox dir or kill each other's processes. A prefix given from outside wins.
export KURASHI_SB_PREFIX=${KURASHI_SB_PREFIX:-r$$-}

suites=()
case "$MODE" in
  merge) for s in "${MERGE_SET[@]}"; do suites+=("$(path_of "$s")"); done ;;
  all) mapfile -t suites <<< "$ALL" ;;
  pick) for s in "${PICK[@]}"; do suites+=("$(path_of "$s")"); done ;;
  changed)
    files=$( { git diff --name-only "$REF"...HEAD; git diff --name-only; git diff --name-only --cached; } | sort -u)
    declare -A want=() covers=()
    for t in $ALL; do covers[$t]=$(sed -n '1,12s/^# covers: *//p' "$t" | tr '\n' ' '); done
    full=0
    for f in $files; do
      claimed=0
      mod=
      case "$f" in
        crates/kurashi-mod-*/*) mod=${f#crates/kurashi-mod-}; mod=${mod%%/*} ;;
        i18n/*/mod-*.toml) mod=$(basename "$f" .toml); mod=${mod#mod-} ;;
        mods/*/*) mod=${f#mods/}; mod=${mod%%/*} ;;
      esac
      if [ -n "$mod" ] && [ -d "mods/$mod" ] && [[ "$CORE_COUPLED" != *" $mod "* ]]; then
        for t in $ALL; do case "$t" in "mods/$mod/"*) want[$t]=1 ;; esac; done
        claimed=1
      fi
      for t in $ALL; do
        for c in ${covers[$t]}; do case "$f" in "$c"*) want[$t]=1; claimed=1 ;; esac; done
      done
      case "$f" in
        frontend/core/*|frontend/shell.qml|crates/*|i18n/*|Cargo.lock) [ "$claimed" = 1 ] || full=1 ;;
      esac
      case "$f" in frontend/*|settings/*|mods/*|greeter/*) ;; *) continue ;; esac
      stem=$(basename "${f%.*}")
      [ -n "$stem" ] || continue
      lower=$(echo "$stem" | tr '[:upper:]' '[:lower:]')
      for t in $ALL; do
        if [ "$(basename "$t" .sh)" = "test-$lower" ] || grep -qw -- "$stem" "$t"; then want[$t]=1; fi
      done
    done
    # What the change names always runs; the merge set joins it for a change nothing claimed.
    suites=("${!want[@]}")
    if [ "$full" = 1 ]; then
      for s in "${MERGE_SET[@]}"; do suites+=("$(path_of "$s")"); done
    fi ;;
esac
if [ "$MODE" != pick ]; then for s in "${PICK[@]}"; do suites+=("$(path_of "$s")"); done; fi
mapfile -t suites < <(printf '%s\n' "${suites[@]}" | awk 'NF && !seen[$0]++')
if [ ${#suites[@]} -eq 0 ]; then echo "test-suites: nothing to run"; exit 0; fi
if [ "$LIST" = 1 ]; then printf '%s\n' "${suites[@]}"; exit 0; fi

# B124 (session 31): a run under a nearly full disk wrote empty sandbox env files and ran a shell on the user's display.
# Each suite's sandbox takes up to ~1 GB until a green run removes it: refuse to start under KURASHI_SUITES_MIN_GB free.
min_gb=${KURASHI_SUITES_MIN_GB:-20}
free_gb=$(( $(df -Pk /tmp | awk 'NR == 2 {print $4}') / 1048576 ))
if [ "$free_gb" -lt "$min_gb" ]; then
  echo "test-suites: refused: $free_gb GB free in /tmp, under $min_gb (old sandboxes: /tmp/kurashi-sb-*)"; exit 1
fi
OUT=${KURASHI_SUITES_OUT:-/tmp/kurashi-suites/$(date +%Y%m%d-%H%M%S)}
mkdir -p "$OUT"
export CARGO_TARGET_DIR=${CARGO_TARGET_DIR:-$ROOT/target}
echo "test-suites: ${#suites[@]} suite(s), $JOBS at a time; logs in $OUT"
touch "$OUT/.started"
if ! cargo build -p kurashid -p kurashi -p kurashi-mock > "$OUT/build.log" 2>&1; then
  echo "test-suites: build failed (see $OUT/build.log)"; exit 1
fi
# I579 (W96): what a suite needs beyond the three binaries, named in its first 12 lines:
#   # needs: example:<package>/<name> feature:test-mods
# An example is built into $CARGO_TARGET_DIR/debug/examples (where the suites look). A suite that needs the daemon with
# `--features test-mods` (the linked test mod `hello`) gets a folder of its own with that daemon, so every other suite
# still runs the daemon as it ships.
needs_of() { sed -n '1,12s/^# needs: *//p' "$1" | tr ' ' '\n' | awk 'NF'; }
declare -A want_example=() needs_feature=()
for s in "${suites[@]}"; do
  [ -f "$s" ] || continue
  for n in $(needs_of "$s"); do
    case "$n" in
      example:*/*) want_example[${n#example:}]=1 ;;
      feature:test-mods) needs_feature[$s]=1 ;;
      *) echo "test-suites: $s: unknown need '$n'"; exit 1 ;;
    esac
  done
done
for e in "${!want_example[@]}"; do
  if ! cargo build -p "${e%%/*}" --example "${e##*/}" >> "$OUT/build.log" 2>&1; then
    echo "test-suites: example $e did not build (see $OUT/build.log)"; exit 1
  fi
done
FEATURE_BIN=$OUT/bin-test-mods
if [ ${#needs_feature[@]} -gt 0 ]; then
  mkdir -p "$FEATURE_BIN"
  if ! cargo build -p kurashid --features test-mods >> "$OUT/build.log" 2>&1; then
    echo "test-suites: kurashid --features test-mods did not build (see $OUT/build.log)"; exit 1
  fi
  cp "$CARGO_TARGET_DIR/debug/kurashid" "$CARGO_TARGET_DIR/debug/kurashi" "$CARGO_TARGET_DIR/debug/kurashi-mock" "$FEATURE_BIN/"
  [ -d "$CARGO_TARGET_DIR/debug/examples" ] && ln -s "$CARGO_TARGET_DIR/debug/examples" "$FEATURE_BIN/examples"
  # (and the daemon as it ships again, for the others)
  if ! cargo build -p kurashid >> "$OUT/build.log" 2>&1; then
    echo "test-suites: build failed (see $OUT/build.log)"; exit 1
  fi
fi

run_one() {   # run_one <script> <log> → prints "rc seconds"
  local s=$1 log=$2 t0=$(date +%s)
  if [ -n "${needs_feature[$s]:-}" ]; then
    KURASHI_BIN_DIR=$FEATURE_BIN timeout 1800 "$s" > "$log" 2>&1
  else
    timeout 1800 "$s" > "$log" 2>&1
  fi
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
# K153: a suite that fails on `main` too, with the BACKLOG row that holds it (tools/suites-known-failing.txt), is reported
# and does not fail the run; one that passes says so, so its line goes.
declare -A known=()
while read -r script row; do
  case "$script" in ''|'#'*) continue ;; esac
  known[$script]=$row
done < "$ROOT/tools/suites-known-failing.txt"
for s in "${suites[@]}"; do
  case "${rc[$s]}" in
    0|"0 (alone"*) [ -z "${known[$s]:-}" ] || echo "test-suites: $s passes: take its line out of tools/suites-known-failing.txt (${known[$s]})" ;;
    *) if [ -n "${known[$s]:-}" ]; then echo "test-suites: $s fails as on main: known ${known[$s]}"; else bad=1; fi ;;
  esac
done
# I375: a green run leaves no sandboxes behind (a failed one keeps them for its logs; `sandbox.sh start` clears those after
# a day). Only dirs this run made, and none a process still has as its runtime dir.
if [ "$bad" = 0 ]; then
  for d in /tmp/kurashi-sb-*; do
    [ -d "$d" ] && [ ! -L "$d" ] && [ -O "$d" ] && [ "$d" -nt "$OUT/.started" ] || continue
    grep -qslaF "XDG_RUNTIME_DIR=$d" /proc/[0-9]*/environ 2>/dev/null && continue
    rm -rf -- "$d" 2>/dev/null || true
  done
fi
exit $bad
