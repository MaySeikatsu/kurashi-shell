#!/usr/bin/env bash
# Smoke test of the frontend against the REAL kurashid, invisibly (headless sway sandbox).
#   nix develop -c frontend/test-real.sh [sandbox-name]
# Binaries: $KURASHI_BIN_DIR (default: $CARGO_TARGET_DIR/debug or target/debug) must hold
# kurashid + kurashi; they are copied first because shared target dirs get overwritten.
# The daemon runs with isolated XDG dirs and the sandbox's session bus; nothing touches the
# user's display, socket, bus or ~/.config. Screenshots land in frontend/shots/real/.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
NAME=${1:-${KURASHI_SB_PREFIX:-}fe-real}
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
# K71: the bar moves with its modules in one change (`layout.bar.move`), from the edge it stands on now.
bar_edge() {
  local e
  for e in top bottom left right; do
    if K --json get "edges.$e.bar" | grep -q '"value":true'; then
      [ "$e" = "$1" ] || K act layout.bar.move "{\"from\":\"$e\",\"to\":\"$1\"}" >/dev/null
      return
    fi
  done
  return 1
}
shot() { sleep "${2:-1.5}"; grim "$OUT/$1.png"; [ -s "$OUT/$1.png" ] || { echo "empty screenshot $1" >&2; exit 1; }; echo "shot $1"; }
start_daemon() {
  rm -f "$KURASHI_SOCKET"
  # The system bus is a socket that does not exist: the island panel subscribes svc.bluetooth, which
  # must not reach the host's BlueZ from a test.
  DBUS_SYSTEM_BUS_ADDRESS="unix:path=$R/no-system-bus" "$W/kurashid" >> "$R/kurashid.log" 2>&1 &
  DPID=$!; pids+=("$DPID")
  for _ in $(seq 100); do [ -S "$KURASHI_SOCKET" ] && K ping >/dev/null 2>&1 && return 0; sleep 0.1; done
  echo "kurashid did not come up (see $R/kurashid.log)" >&2; exit 1
}

: > "$R/kurashid.log"; : > "$R/qs.log"
start_daemon
# Without KURASHI_SOCKET: the frontend must find the socket by the protocol default, as in a live
# session (nix run, the HM service), where nothing sets it.
env -u KURASHI_SOCKET qs -p "$ROOT/frontend" >> "$R/qs.log" 2>&1 &
pids+=("$!")
# The frontend must actually be connected: screenshots of a disconnected bar passed this test once.
for _ in $(seq 50); do grep -q 'hello.*frontend' "$R/kurashid.log" && break; sleep 0.1; done
grep -q 'hello.*frontend' "$R/kurashid.log" || { echo "frontend never said hello to kurashid (see $R/qs.log)" >&2; exit 1; }
sleep 3

shot bar-idle
K act island.next >/dev/null
shot island-next
K act island.expand >/dev/null
shot popup-expand
K act island.expand >/dev/null   # toggle the popup closed again

# Bar placement from the config document: a bottom bar (the island panel must open above it),
# then no bar, then back to the default (K71: `layout.bar.move` moves the bar with its modules).
bar_edge bottom || fail "the bar did not move to the bottom"
shot bar-bottom
K act island.expand >/dev/null
shot popup-bottom
K act island.expand >/dev/null
K set edges.bottom.bar=false >/dev/null
shot bar-disabled
K set edges.bottom.bar=true >/dev/null
bar_edge top || fail "the bar did not move back to the top"

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
