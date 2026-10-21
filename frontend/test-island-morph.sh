#!/usr/bin/env bash
# The island's morph (W21, docs/ux/island.md "Session 9 morph"), invisibly (headless sway sandbox), against the REAL
# kurashid: frames grabbed while the island's card grows out of the bar pill and folds back into it, as evidence that it
# is one continuous shape. For each step (`kurashi act island.expand`, then `ui.close`) three grims are started at
# MORPH_AT ms (default 40 120 250) after the action, cropped to the bar's centre; then the card at rest. Files:
# frontend/shots/island/morph-<tag>-{open,close}-<ms>.png and morph-<tag>-rest.png. Fails only on a server that does not
# come up or on a QML error.
#   nix develop -c frontend/test-island-morph.sh [tag] [config-toml-line ...]
#   e.g. frontend/test-island-morph.sh sekai 'theme.style = "sekai"'
#        frontend/test-island-morph.sh wa-iro 'theme.style = "none"'
# MORPH_FACE=media|volume|... picks the face (`island.next` until runtime.island.main has it is not done: the real daemon
# picks the face; the default is the clock). Machine B: export KURASHI_RENDER_NODE first.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
TAG=${1:-sekai}
shift || true
LINES=("$@")
[ ${#LINES[@]} -eq 0 ] && LINES=('theme.style = "sekai"')
NAME=${MORPH_SANDBOX:-w21-isl-morph}-$TAG
BIN=${KURASHI_BIN_DIR:-${CARGO_TARGET_DIR:-$ROOT/target}/debug}
OUT=$ROOT/frontend/shots/island
AT=${MORPH_AT:-40 120 250}
CROP=${MORPH_CROP:-860,0 840x520}
mkdir -p "$OUT"
fail() { echo "test-island-morph: $*" >&2; exit 1; }

eval "$("$ROOT/tools/bench/sandbox.sh" start "$NAME")"
R=$XDG_RUNTIME_DIR
W=$R/work
mkdir -p "$W" "$R/kurashi"
cp "$BIN/kurashid" "$BIN/kurashi" "$W/"
pids=()
cleanup() {
  for p in "${pids[@]}"; do kill "$p" 2>/dev/null || true; done
  for p in "${pids[@]}"; do wait "$p" 2>/dev/null || true; done
  "$ROOT/tools/bench/sandbox.sh" stop "$NAME" >/dev/null || true
}
trap cleanup EXIT

rm -rf "$R/xdg"
export XDG_CONFIG_HOME=$R/xdg/config XDG_STATE_HOME=$R/xdg/state \
       XDG_DATA_HOME=$R/xdg/data XDG_CACHE_HOME=$R/xdg/cache KURASHI_DATA_DIR=$ROOT LC_ALL=C.UTF-8
mkdir -p "$XDG_CONFIG_HOME/kurashi" "$XDG_STATE_HOME" "$XDG_DATA_HOME" "$XDG_CACHE_HOME"
printf '%s\n' "${LINES[@]}" > "$XDG_CONFIG_HOME/kurashi/config.toml"
K() { timeout 10 "$W/kurashi" "$@"; }

: > "$R/server.log"; : > "$R/qs.log"
env DBUS_SYSTEM_BUS_ADDRESS="unix:path=$R/no-system-bus" \
    PULSE_SERVER="unix:$R/no-pulse/native" PULSE_RUNTIME_PATH="$R/no-pulse" \
    "$W/kurashid" >> "$R/server.log" 2>&1 &
pids+=("$!")
for _ in $(seq 100); do [ -S "$KURASHI_SOCKET" ] && K ping >/dev/null 2>&1 && break; sleep 0.1; done
K ping >/dev/null 2>&1 || fail "kurashid did not come up (see $R/server.log)"
swaymsg output '*' bg '#8fb8c8' solid_color >/dev/null 2>&1 || true
env -u KURASHI_SOCKET qs -p "$ROOT/frontend" >> "$R/qs.log" 2>&1 &
pids+=("$!")
for _ in $(seq 100); do grep -q 'hello.*frontend' "$R/server.log" && break; sleep 0.1; done
grep -q 'hello.*frontend' "$R/server.log" || fail "frontend never said hello (see $R/qs.log)"
sleep 3

# burst <name> <action>: the action, and one grim per MORPH_AT offset, each started on its own clock.
burst() {
  local gp=() t t0 ap
  t0=$(date +%s%N)
  K act "$2" >/dev/null &
  ap=$!
  for t in $AT; do
    ( now=$(date +%s%N); wait_ms=$(( t - (now - t0) / 1000000 )); [ "$wait_ms" -gt 0 ] && sleep "$(printf '0.%03d' "$wait_ms")"
      grim -g "$CROP" "$OUT/morph-$TAG-$1-$t.png" ) &
    gp+=("$!")
  done
  for p in "${gp[@]}"; do wait "$p" || fail "grim failed ($1)"; done
  wait "$ap" || fail "act $2 failed"
  for t in $AT; do echo "test-island-morph: $OUT/morph-$TAG-$1-$t.png"; done
}

grim -g "$CROP" "$OUT/morph-$TAG-pill.png"
# MORPH_CYCLES=n: n plain open/close cycles first, each card at rest grabbed (a stalled morph shows there).
for i in $(seq "${MORPH_CYCLES:-0}"); do
  K act island.expand >/dev/null; sleep 2.5
  grim -g "$CROP" "$R/cycle-$i.png"; echo "test-island-morph: cycle $i: $R/cycle-$i.png"
  K act ui.close >/dev/null; sleep 1.2
done
burst open island.expand
sleep 1.5
grim -g "$CROP" "$OUT/morph-$TAG-rest.png"
echo "test-island-morph: $OUT/morph-$TAG-rest.png"
burst close ui.close
sleep 1.5
grim -g "$CROP" "$OUT/morph-$TAG-after.png"
if grep -E 'qml:.*(Error|error)|TypeError|ReferenceError|is not a type' "$R/qs.log" | grep -v 'Unable to assign \[undefined\]' >/dev/null; then
  grep -E 'Error|error|Warn|warn' "$R/qs.log" | head -20 >&2
  fail "QML errors (see $R/qs.log)"
fi
grep -iE 'warn' "$R/qs.log" | head -10 || true
echo "test-island-morph: ok"
