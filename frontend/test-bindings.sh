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
# `swaymsg seat - cursor press` reaches no client. A virtual pointer (zwlr_virtual_pointer_v1 on the
# sandbox's own socket) clicks instead. The island is centred on the top bar: x = output centre, y = 18
# (bar.height 36, island centred in it).
click_island() {
  local w h
  read -r w h < <(swaymsg -t get_outputs -r | jq -r '.[0].rect | "\(.width) \(.height)"')
  timeout 30 python3 - "$((w / 2))" 18 "$w" "$h" <<'PY'
import os, socket, struct, sys, time

x, y, w, h = (int(a) for a in sys.argv[1:5])
settle = 0.5

sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
sock.settimeout(5)
sock.connect(os.path.join(os.environ["XDG_RUNTIME_DIR"], os.environ["WAYLAND_DISPLAY"]))
inbuf = bytearray()

DISPLAY, REG, SYNC1, SEAT, MANAGER, POINTER, SYNC2 = 1, 2, 3, 4, 5, 6, 7
BTN_LEFT = 272


def send(obj, op, payload=b""):
    sock.sendall(struct.pack("<IHH", obj, op, 8 + len(payload)) + payload)


def string(text):
    raw = text.encode() + b"\0"
    return struct.pack("<I", len(raw)) + raw + b"\0" * (-len(raw) % 4)


def read_event():
    while True:
        if len(inbuf) >= 8:
            obj, op, size = struct.unpack_from("<IHH", inbuf)
            if len(inbuf) >= size:
                body = bytes(inbuf[8:size])
                del inbuf[:size]
                return obj, op, body
        chunk = sock.recv(65536)
        if not chunk:
            sys.exit("click: compositor closed the connection")
        inbuf.extend(chunk)


# wl_display.get_registry, then sync: the globals are announced before the sync callback fires.
send(DISPLAY, 1, struct.pack("<I", REG))
send(DISPLAY, 0, struct.pack("<I", SYNC1))
globals_ = {}
while True:
    obj, op, body = read_event()
    if obj == REG and op == 0:  # wl_registry.global(name, interface, version)
        name, = struct.unpack_from("<I", body, 0)
        n, = struct.unpack_from("<I", body, 4)
        iface = body[8:8 + n - 1].decode()
        version, = struct.unpack_from("<I", body, 8 + ((n + 3) & ~3))
        globals_[iface] = (name, version)
    elif obj == SYNC1 and op == 0:
        break
    elif obj == DISPLAY and op == 0:  # wl_display.error
        sys.exit(f"click: wayland error {body!r}")


def bind(iface, max_version, new_id):
    name, version = globals_[iface]  # KeyError: the compositor does not offer it
    send(REG, 0, struct.pack("<I", name) + string(iface)
         + struct.pack("<II", min(version, max_version), new_id))


bind("wl_seat", 5, SEAT)
bind("zwlr_virtual_pointer_manager_v1", 2, MANAGER)
# create_virtual_pointer(seat, new_id): the seat gains a pointer capability for the clients.
send(MANAGER, 0, struct.pack("<II", SEAT, POINTER))


def ms():
    return int(time.monotonic() * 1000) & 0xFFFFFFFF


time.sleep(0.5)  # let clients learn about the new pointer capability before the first event
send(POINTER, 1, struct.pack("<IIIII", ms(), x, y, w, h))  # motion_absolute in the layout
send(POINTER, 4)  # frame
time.sleep(0.2)
send(POINTER, 2, struct.pack("<III", ms(), BTN_LEFT, 1))  # button pressed
send(POINTER, 4)
send(POINTER, 2, struct.pack("<III", ms(), BTN_LEFT, 0))  # button released
send(POINTER, 4)
send(DISPLAY, 0, struct.pack("<I", SYNC2))
while True:  # the compositor has processed everything above
    obj, op, body = read_event()
    if obj == SYNC2 and op == 0:
        break
    if obj == DISPLAY and op == 0:
        sys.exit(f"click: wayland error {body!r}")
time.sleep(settle)  # closing the socket destroys the virtual pointer
PY
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
