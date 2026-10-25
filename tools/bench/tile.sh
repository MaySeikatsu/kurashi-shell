#!/usr/bin/env bash
# What a quick tile costs (W42-tiles): `tools/bench/tile/shell.qml` makes TILE_N QuickTiles (each with its two Blocks, its
# Icons, Texts and areas) TILE_ROUNDS times per look, in a headless sway sandbox against the real kurashid, and this script
# reports the creation time per tile (median of the warm rounds) and the CPU per tile (the process's utime + stime over the
# rounds: the steadier figure on a loaded machine). The frontends run one after the other per look, so the load hits all
# of them alike; the quick card's own method is tools/bench/quick-open.sh.
#   nix develop -c tools/bench/tile.sh <frontend dir> [<frontend dir> …]     (default: this checkout's frontend)
# TILE_LOOKS (default "washi sekai kami snes kanso"), TILE_N (tiles per round, 120), TILE_ROUNDS (15), TILE_SANDBOX
# (default w42-tiles-tile). Binaries from $KURASHI_BIN_DIR, else $CARGO_TARGET_DIR/release.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
NAME=${TILE_SANDBOX:-w42-tiles-tile}
BIN=${KURASHI_BIN_DIR:-${CARGO_TARGET_DIR:-$ROOT/target}/release}
LOOKS=${TILE_LOOKS:-washi sekai kami snes kanso}
FRONTENDS=("$@")
[ ${#FRONTENDS[@]} -gt 0 ] || FRONTENDS=("$ROOT/frontend")
fail() { echo "tile.sh: FAIL: $*" >&2; exit 1; }

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
# utime + stime of a process in clock ticks (/proc/<pid>/stat fields 14 and 15, after the comm's closing parenthesis).
cpu_ticks() { sed 's/.*) //' "/proc/$1/stat" | awk '{print $12 + $13}'; }
env DBUS_SYSTEM_BUS_ADDRESS="unix:path=$R/no-system-bus" PULSE_SERVER="unix:$R/no-pulse/native" \
    PULSE_RUNTIME_PATH="$R/no-pulse" "$W/kurashid" > "$R/server.log" 2>&1 &
pids+=("$!")
for _ in $(seq 100); do [ -S "$KURASHI_SOCKET" ] && K ping >/dev/null 2>&1 && break; sleep 0.1; done
K ping >/dev/null 2>&1 || fail "kurashid did not come up (see $R/server.log)"

i=0
for fe in "${FRONTENDS[@]}"; do
  i=$((i + 1))
  rm -rf "$W/t$i"; mkdir -p "$W/t$i"
  cp "$ROOT/tools/bench/tile/shell.qml" "$W/t$i/"
  cp -r "$fe" "$W/t$i/frontend"
done
for look in $LOOKS; do
  K set theme.style="$look" >/dev/null || fail "theme.style=$look refused"
  K set theme.motion.profile=calm >/dev/null || true
  sleep 1
  i=0
  for fe in "${FRONTENDS[@]}"; do
    i=$((i + 1))
    H=$W/t$i
    log=$W/tile-$i-$look.log
    env -u KURASHI_SOCKET KURASHI_SOCKET="$KURASHI_SOCKET" qs -p "$H" > "$log" 2>&1 &
    qs=$!
    pids+=("$qs")
    # The process's CPU time (utime + stime, clock ticks) from the theme line to the end of the rounds: the rounds' work
    # alone, which the machine's load moves far less than the wall clock does.
    cpu0= cpu1=
    for _ in $(seq 600); do
      if [ -z "$cpu0" ] && grep -q "TILEBENCH theme" "$log"; then cpu0=$(cpu_ticks "$qs"); fi
      grep -q "TILEBENCH done" "$log" && break
      kill -0 "$qs" 2>/dev/null || break
      sleep 0.1
    done
    if grep -q "TILEBENCH done" "$log"; then cpu1=$(cpu_ticks "$qs"); fi
    kill "$qs" 2>/dev/null || true; wait "$qs" 2>/dev/null || true
    grep -q "TILEBENCH done" "$log" || { tail -20 "$log"; fail "the harness did not finish ($log)"; }
    python3 -I - "$fe" "$look" "$log" "${cpu0:-0}" "${cpu1:-0}" "$(getconf CLK_TCK)" <<'PY'
import re, statistics, sys
fe, look, log, cpu0, cpu1, hz = sys.argv[1:]
text = open(log).read()
ms = [int(m) for m in re.findall(r"TILEBENCH round \d+ ms (\d+)", text)]
n = int(re.search(r"TILEBENCH theme n=(\d+)", text).group(1))
rounds = len(ms)
warm = ms[3:] or ms
med = statistics.median(warm)
cpu_us = (int(cpu1) - int(cpu0)) * 1e6 / int(hz) / (rounds * n)
print("%-7s %-40s wall median %.0f us/tile (rounds %s) | CPU %.0f us/tile over %d rounds" % (
    look, fe[-40:], med * 1000 / n, " ".join(str(m) for m in ms), cpu_us, rounds))
PY
  done
done
