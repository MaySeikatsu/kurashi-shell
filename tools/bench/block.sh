#!/usr/bin/env bash
# What a Block costs (W39-block, I199/I204): `tools/bench/block/shell.qml` makes quick-tile pairs (two Blocks each) in a
# headless sway sandbox against the real kurashid, per look, and this script reports the creation time per round
# (median) and the anonymous memory per pair (PSS_Anon with 500 pairs held minus none, from smaps_rollup).
#   nix develop -c tools/bench/block.sh [frontend dir …]      (default: this checkout's frontend)
# BLOCK_LOOKS (default "sekai glass washi terminal kami"), BLOCK_N (pairs per round, 100), BLOCK_ROUNDS (15),
# BLOCK_HOLD (500), BLOCK_SANDBOX (sandbox name, w39-block-bench). Binaries from $KURASHI_BIN_DIR, else
# $CARGO_TARGET_DIR/release. Compare two frontends in one run, e.g. HEAD's: `git archive HEAD frontend | tar -x -C /tmp/ref`.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
NAME=${BLOCK_SANDBOX:-w39-block-bench}
BIN=${KURASHI_BIN_DIR:-${CARGO_TARGET_DIR:-$ROOT/target}/release}
LOOKS=${BLOCK_LOOKS:-sekai glass washi terminal kami}
FRONTENDS=("$@")
[ ${#FRONTENDS[@]} -gt 0 ] || FRONTENDS=("$ROOT/frontend")
fail() { echo "block.sh: FAIL: $*" >&2; exit 1; }

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

export XDG_CONFIG_HOME=$R/xdg/config XDG_STATE_HOME=$R/xdg/state \
       XDG_DATA_HOME=$R/xdg/data XDG_CACHE_HOME=$R/xdg/cache KURASHI_DATA_DIR=$ROOT LC_ALL=C.UTF-8
rm -rf "$R/xdg"; mkdir -p "$XDG_CONFIG_HOME/kurashi" "$XDG_STATE_HOME" "$XDG_DATA_HOME" "$XDG_CACHE_HOME"
: > "$XDG_CONFIG_HOME/kurashi/config.toml"
K() { timeout 10 "$W/kurashi" "$@"; }
env DBUS_SYSTEM_BUS_ADDRESS="unix:path=$R/no-system-bus" PULSE_SERVER="unix:$R/no-pulse/native" \
    PULSE_RUNTIME_PATH="$R/no-pulse" "$W/kurashid" > "$R/server.log" 2>&1 &
pids+=("$!")
for _ in $(seq 100); do [ -S "$KURASHI_SOCKET" ] && K ping >/dev/null 2>&1 && break; sleep 0.1; done
K ping >/dev/null 2>&1 || fail "kurashid did not come up (see $R/server.log)"

anon_kib() { awk '/^Pss_Anon:/ {print $2}' "/proc/$1/smaps_rollup"; }

i=0
for fe in "${FRONTENDS[@]}"; do
  i=$((i + 1))
  H=$W/h$i
  rm -rf "$H"; mkdir -p "$H/tools/bench/block"
  cp "$ROOT/tools/bench/block/shell.qml" "$H/tools/bench/block/"
  cp -r "$fe" "$H/frontend"
  for look in $LOOKS; do
    K set theme.style="$look" >/dev/null || fail "theme.style=$look refused"
    K set theme.motion.profile=calm >/dev/null || true
    sleep 1
    log=$W/qs-$i-$look.log
    env -u KURASHI_SOCKET KURASHI_SOCKET="$KURASHI_SOCKET" qs -p "$H/tools/bench/block" > "$log" 2>&1 &
    qs=$!
    pids+=("$qs")
    empty= held=
    for _ in $(seq 600); do
      if [ -z "$empty" ] && grep -q "BLOCKBENCH mark empty" "$log"; then sleep 2.5; empty=$(anon_kib "$qs"); fi
      if [ -z "$held" ] && grep -q "BLOCKBENCH mark held" "$log"; then sleep 2.5; held=$(anon_kib "$qs"); fi
      grep -q "BLOCKBENCH done" "$log" && break
      kill -0 "$qs" 2>/dev/null || break
      sleep 0.1
    done
    kill "$qs" 2>/dev/null || true; wait "$qs" 2>/dev/null || true
    grep -q "BLOCKBENCH done" "$log" || { tail -20 "$log"; fail "the harness did not finish ($log)"; }
    hold=$(grep -o "mark held [0-9]*" "$log" | awk '{print $3}')
    python3 -I - "$fe" "$look" "$empty" "$held" "$hold" "$log" <<'PY'
import re, statistics, sys
fe, look, empty, held, hold, log = sys.argv[1:]
text = open(log).read()
ms = [int(m) for m in re.findall(r"BLOCKBENCH round \d+ ms (\d+)", text)]
theme = re.search(r"BLOCKBENCH theme (.*)", text).group(1)
warm = ms[3:] or ms
n = int(re.search(r"n=(\d+)", theme).group(1))
per = (int(held) - int(empty)) / int(hold)
print("%-10s %-40s rounds %s | median %.1f ms / %d pairs = %.0f us per Block | anon %.2f KiB per Block  [%s]" % (
    look, fe[-40:], ms, statistics.median(warm), n, statistics.median(warm) * 1000 / n / 2, per / 2, theme))
PY
  done
done
