#!/usr/bin/env bash
# Island input bindings against the REAL kurashid, invisibly (headless sway sandbox): a click must run
# the action the user bound, through input.dispatch, and nothing else.
#   nix develop -c frontend/test-bindings.sh [sandbox-name]
# Binaries: $KURASHI_BIN_DIR (default: $CARGO_TARGET_DIR/debug or target/debug) must hold kurashid and
# kurashi; they are copied first, as in test-real.sh. Nothing touches the user's display, socket or config.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
NAME=${1:-fe-bindings}
BIN=${KURASHI_BIN_DIR:-${CARGO_TARGET_DIR:-$ROOT/target}/debug}

eval "$("$ROOT/tools/bench/sandbox.sh" start "$NAME")"
R=$XDG_RUNTIME_DIR
W=$R/work
mkdir -p "$W" "$R/kurashi"
cp "$BIN/kurashid" "$BIN/kurashi" "$W/"
rm -rf "$R/xdg"   # hermetic: the sandbox dir outlives a run, and a leftover override would skew it

pids=()
cleanup() {
  for p in "${pids[@]}"; do kill "$p" 2>/dev/null || true; done
  "$ROOT/tools/bench/sandbox.sh" stop "$NAME" >/dev/null || true
}
trap cleanup EXIT

export XDG_CONFIG_HOME=$R/xdg/config XDG_STATE_HOME=$R/xdg/state \
       XDG_DATA_HOME=$R/xdg/data XDG_CACHE_HOME=$R/xdg/cache KURASHI_DATA_DIR=$ROOT
mkdir -p "$XDG_CONFIG_HOME" "$XDG_STATE_HOME" "$XDG_DATA_HOME" "$XDG_CACHE_HOME"

K() { timeout 10 "$W/kurashi" "$@"; }
start_daemon() {
  rm -f "$KURASHI_SOCKET"
  "$W/kurashid" >> "$R/kurashid.log" 2>&1 &
  DPID=$!; pids+=("$DPID")
  for _ in $(seq 100); do [ -S "$KURASHI_SOCKET" ] && K ping >/dev/null 2>&1 && return 0; sleep 0.1; done
  echo "kurashid did not come up (see $R/kurashid.log)" >&2; exit 1
}

# What the daemon resolves for island.main's left click ("" = unbound), read from the bindings doc
# itself, so a failure shows whether the daemon or the click is at fault.
daemon_left() { K sub bindings --count 0 | jq -r '.data["island.main"].left.action // ""'; }
expect_left() { # <action|"">
  local got; got=$(daemon_left)
  [ "$got" = "$1" ] || { echo "FAIL: daemon resolves left to \"$got\", want \"$1\"" >&2; exit 1; }
}

# A click needs a pointer, and the sandbox seat has none (WLR_LIBINPUT_NO_DEVICES, headless backend), so
# `swaymsg seat - cursor press` reaches no client. tools/bench/wl_pointer.py clicks instead: a virtual pointer
# on the sandbox's own socket, at layout coordinates. The island is centred on the top bar: x = output centre,
# y = 18 (bar.height 36, island centred in it).
click_island() {
  local w
  w=$(swaymsg -t get_outputs -r | jq -r '.[0].rect.width')
  timeout 30 python3 -I "$ROOT/tools/bench/wl_pointer.py" click "$((w / 2))" 18 left
}

# The daemon acts asynchronously: poll (bounded) for the expected panel.
panel_is() { grep -q "\"panel\":\"$1\"" <<<"$(K sub runtime.ui --count 0 || true)"; }
expect_panel() { # <panel> <what>
  for _ in $(seq 25); do
    if panel_is "$1"; then echo "ok: $2 (panel \"$1\")"; return 0; fi
    sleep 0.2
  done
  echo "FAIL: $2: expected panel \"$1\", got $(K sub runtime.ui --count 0 || true)" >&2
  exit 1
}
# Negative check: give a wrongly fired action time to land before looking.
expect_unchanged() { # <panel> <what>
  sleep 1.5
  if panel_is "$1"; then echo "ok: $2 (panel still \"$1\")"; else echo "FAIL: $2: panel changed" >&2; exit 1; fi
}

: > "$R/kurashid.log"; : > "$R/qs.log"
start_daemon
qs -p "$ROOT/frontend" >> "$R/qs.log" 2>&1 &
pids+=("$!")
sleep 3

# 1. Bound: left -> notifications.center opens the notification center.
K set island.main.input.left notifications.center >/dev/null
expect_left notifications.center
sleep 1   # the frontend takes the bindings patch before the click
click_island
expect_panel notifications "bound left click runs notifications.center"

# 2. Unbound: an absent slot does nothing. Start from a closed panel so a stray action shows up.
K act ui.close >/dev/null
K set island.main.input.left "" >/dev/null
expect_left ""
sleep 1
click_island
expect_unchanged "" "unbound left click does nothing"

# 3. Default: reset to island.expand opens the island panel.
K reset island.main.input.left >/dev/null
expect_left island.expand
sleep 1
click_island
expect_panel island "default left click opens the island panel"

# The frontend must not log QML errors (a bad binding shows up here, not as a silent no-op).
if grep -q "ERROR\|TypeError\|ReferenceError\|Unable to assign\|is not defined" "$R/qs.log"; then
  echo "qs.log has errors:" >&2
  grep "ERROR\|TypeError\|ReferenceError\|Unable to assign\|is not defined" "$R/qs.log" | head >&2
  exit 1
fi
echo "ok: island clicks go through input.dispatch (bound, unbound, default)"
