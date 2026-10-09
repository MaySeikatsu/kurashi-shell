#!/usr/bin/env bash
# Smoke test of the frontend against the REAL kurashid, invisibly (headless sway sandbox).
#   nix develop -c frontend/test-real.sh [sandbox-name]
# Binaries: $KURASHI_BIN_DIR (default: $CARGO_TARGET_DIR/debug or target/debug) must hold
# kurashid + kurashi; they are copied first because shared target dirs get overwritten.
# The daemon runs with isolated XDG dirs and the sandbox's session bus; nothing touches the
# user's display, socket, bus or ~/.config. Screenshots land in frontend/shots/real/.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
NAME=${1:-fe-real}
BIN=${KURASHI_BIN_DIR:-${CARGO_TARGET_DIR:-$ROOT/target}/debug}
OUT=$ROOT/frontend/shots/real
mkdir -p "$OUT"

eval "$("$ROOT/tools/bench/sandbox.sh" start "$NAME")"
R=$XDG_RUNTIME_DIR
W=$R/work
mkdir -p "$W" "$R/kurashi"
cp "$BIN/kurashid" "$BIN/kurashi" "$W/"

pids=()
cleanup() {
  for p in "${pids[@]}"; do kill "$p" 2>/dev/null || true; done
  "$ROOT/tools/bench/sandbox.sh" stop "$NAME" >/dev/null || true
}
trap cleanup EXIT

export XDG_CONFIG_HOME=$R/xdg/config XDG_STATE_HOME=$R/xdg/state \
       XDG_DATA_HOME=$R/xdg/data XDG_CACHE_HOME=$R/xdg/cache KURASHI_DATA_DIR=$ROOT
mkdir -p "$XDG_CONFIG_HOME" "$XDG_STATE_HOME" "$XDG_DATA_HOME" "$XDG_CACHE_HOME"

K() { "$W/kurashi" "$@"; }
shot() { sleep "${2:-1.5}"; grim "$OUT/$1.png"; [ -s "$OUT/$1.png" ] || { echo "empty screenshot $1" >&2; exit 1; }; echo "shot $1"; }
start_daemon() {
  rm -f "$KURASHI_SOCKET"
  "$W/kurashid" >> "$R/kurashid.log" 2>&1 &
  DPID=$!; pids+=("$DPID")
  for _ in $(seq 100); do [ -S "$KURASHI_SOCKET" ] && K ping >/dev/null 2>&1 && return 0; sleep 0.1; done
  echo "kurashid did not come up (see $R/kurashid.log)" >&2; exit 1
}

: > "$R/kurashid.log"; : > "$R/qs.log"
start_daemon
qs -p "$ROOT/frontend" >> "$R/qs.log" 2>&1 &
pids+=("$!")
sleep 3

shot bar-idle
K act island.next >/dev/null
shot island-next
K act island.expand >/dev/null
shot popup-expand
K act island.expand >/dev/null   # toggle the popup closed again

# Session menu: open, look, close. Destructive entries are never pressed here (no confirm).
K act session.menu >/dev/null
shot session-menu
K act ui.close >/dev/null

kill "$DPID"; wait "$DPID" 2>/dev/null || true
shot veil-disconnected 2.5

start_daemon
shot reconnected 2.5

# The shell must still be alive and error-free of retry storms.
if grep -q "ERROR\|TypeError\|ReferenceError\|Unable to assign\|is not defined" "$R/qs.log"; then
  echo "qs.log has errors:" >&2; grep "ERROR\|TypeError\|ReferenceError\|Unable to assign\|is not defined" "$R/qs.log" | head >&2; exit 1
fi
echo "ok: screenshots in $OUT"
