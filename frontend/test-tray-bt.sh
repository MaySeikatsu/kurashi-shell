#!/usr/bin/env bash
# Tray and Bluetooth against the MOCK, invisibly (headless sway sandbox). Checks:
#   - the bar draws the mock's two tray items at its end (screenshot),
#   - a left click on an item sends tray.activate with its screen position (the mock logs it),
#   - a right click opens that item's menu in the Stage (runtime.ui: panel "tray", tray = its id;
#     screenshot), and a second right click on it closes the menu,
#   - the island panel lists Bluetooth: powered, one connected keyboard; a scan lists the nearby
#     device (screenshots), and the adapter's state in the mock matches what was asked,
#   - the frontend logs no QML error.
#   nix develop -c frontend/test-tray-bt.sh [sandbox-name]
# Binary: kurashi-mock from $KURASHI_MOCK_BIN (default $CARGO_TARGET_DIR/debug, else target/debug),
# copied first because shared target dirs are overwritten. The mock serves the fixture contents: no
# real daemon, no system bus, no user display. Screenshots land in frontend/shots/tray-bt/ and are
# evidence to read, not just the exit code. On a hybrid laptop export KURASHI_RENDER_NODE first.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
NAME=${1:-fe-tray-bt}
MOCK_BIN=${KURASHI_MOCK_BIN:-${CARGO_TARGET_DIR:-$ROOT/target}/debug/kurashi-mock}
OUT=$ROOT/frontend/shots/tray-bt
mkdir -p "$OUT"
fail() { echo "test-tray-bt: $*" >&2; exit 1; }

eval "$("$ROOT/tools/bench/sandbox.sh" start "$NAME")"
R=$XDG_RUNTIME_DIR
W=$R/work
mkdir -p "$W" "$R/kurashi"
cp "$MOCK_BIN" "$W/kurashi-mock"

pids=()
cleanup() {
  for p in "${pids[@]}"; do kill "$p" 2>/dev/null || true; done
  "$ROOT/tools/bench/sandbox.sh" stop "$NAME" >/dev/null || true
}
trap cleanup EXIT

export XDG_CONFIG_HOME=$R/xdg/config XDG_STATE_HOME=$R/xdg/state \
       XDG_DATA_HOME=$R/xdg/data XDG_CACHE_HOME=$R/xdg/cache KURASHI_DATA_DIR=$ROOT LC_ALL=C.UTF-8
mkdir -p "$XDG_CONFIG_HOME" "$XDG_STATE_HOME" "$XDG_DATA_HOME" "$XDG_CACHE_HOME"

# One protocol exchange with the socket: `ipc.py act <action> <args-json>` (exit 1 on err) or
# `ipc.py sub <doc>` (prints the first snapshot's data). Plain stdlib, no daemon knowledge here.
cat > "$W/ipc.py" <<'PY'
import json, os, socket, sys

sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
sock.settimeout(5)
sock.connect(os.environ["KURASHI_SOCKET"])
f = sock.makefile("rwb")


def send(msg):
    f.write((json.dumps(msg) + "\n").encode())
    f.flush()


def reply(rid):
    while True:
        line = f.readline()
        if not line:
            sys.exit("ipc: connection closed")
        m = json.loads(line)
        if m.get("id") == rid and m["t"] in ("done", "err", "snap"):
            return m


send({"t": "hello", "v": 1, "client": "test", "caps": ["intents", "resync"]})
if json.loads(f.readline())["t"] != "welcome":
    sys.exit("ipc: no welcome")
if sys.argv[1] == "act":
    args = json.loads(sys.argv[3]) if len(sys.argv) > 3 else {}
    send({"t": "act", "id": "a", "action": sys.argv[2], "args": args})
    m = reply("a")
    print(json.dumps(m))
    sys.exit(0 if m["t"] == "done" else 1)
send({"t": "sub", "id": "s", "doc": sys.argv[2]})
print(json.dumps(reply("s").get("data")))
PY
ipc() { timeout 10 python3 -I "$W/ipc.py" "$@"; }

# The mock: fixed clock, one output; its socket is the sandbox's.
: > "$R/mock.log"; : > "$R/qs.log"
RUST_LOG=info "$W/kurashi-mock" --outputs HEADLESS-1 --fixed-time 14:07 --socket "$KURASHI_SOCKET" \
  >> "$R/mock.log" 2>&1 &
pids+=("$!")
for _ in $(seq 100); do [ -S "$KURASHI_SOCKET" ] && ipc sub svc.clock >/dev/null 2>&1 && break; sleep 0.1; done
ipc sub svc.clock >/dev/null 2>&1 || fail "mock did not come up (see $R/mock.log)"

qs -p "$ROOT/frontend" >> "$R/qs.log" 2>&1 &
pids+=("$!")
sleep 3

# Output geometry, and where the bar's end puts the tray (theme: pad 12, bar 36, icons 36 wide, 12 apart;
# the tray is the last thing in the right-hand row, so its last item ends one pad from the edge).
read -r SW SH < <(swaymsg -t get_outputs -r | jq -r '.[0].rect | "\(.width) \(.height)"')
PAD=12; BARH=36; HALF=$((BARH / 2))
RIGHT_ITEM_X=$((SW - PAD - BARH / 2))             # "Network", the second item
LEFT_ITEM_X=$((RIGHT_ITEM_X - PAD - BARH))        # "Nextcloud", the fixture's item

shot() { # <name> [settle-seconds]
  sleep "${2:-1.5}"
  timeout 20 grim -o HEADLESS-1 "$OUT/$1.png" || fail "grim failed on $1"
  [ -s "$OUT/$1.png" ] || fail "empty screenshot $1"
  echo "shot $1"
}

# A virtual pointer clicks inside the sandbox (its seat has no pointer device); same protocol as
# frontend/test-bindings.sh. click <x> <y> <left|middle|right>.
click() {
  timeout 30 python3 -I - "$1" "$2" "$SW" "$SH" "$3" <<'PY'
import os, socket, struct, sys, time

x, y, w, h = (int(a) for a in sys.argv[1:5])
button = {"left": 272, "right": 273, "middle": 274}[sys.argv[5]]

sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
sock.settimeout(5)
sock.connect(os.path.join(os.environ["XDG_RUNTIME_DIR"], os.environ["WAYLAND_DISPLAY"]))
inbuf = bytearray()

DISPLAY, REG, SYNC1, SEAT, MANAGER, POINTER, SYNC2 = 1, 2, 3, 4, 5, 6, 7


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


send(DISPLAY, 1, struct.pack("<I", REG))
send(DISPLAY, 0, struct.pack("<I", SYNC1))
globals_ = {}
while True:
    obj, op, body = read_event()
    if obj == REG and op == 0:
        name, = struct.unpack_from("<I", body, 0)
        n, = struct.unpack_from("<I", body, 4)
        iface = body[8:8 + n - 1].decode()
        version, = struct.unpack_from("<I", body, 8 + ((n + 3) & ~3))
        globals_[iface] = (name, version)
    elif obj == SYNC1 and op == 0:
        break
    elif obj == DISPLAY and op == 0:
        sys.exit(f"click: wayland error {body!r}")


def bind(iface, max_version, new_id):
    name, version = globals_[iface]
    send(REG, 0, struct.pack("<I", name) + string(iface)
         + struct.pack("<II", min(version, max_version), new_id))


bind("wl_seat", 5, SEAT)
bind("zwlr_virtual_pointer_manager_v1", 2, MANAGER)
send(MANAGER, 0, struct.pack("<II", SEAT, POINTER))


def ms():
    return int(time.monotonic() * 1000) & 0xFFFFFFFF


time.sleep(0.5)
send(POINTER, 1, struct.pack("<IIIII", ms(), x, y, w, h))
send(POINTER, 4)
time.sleep(0.2)
send(POINTER, 2, struct.pack("<III", ms(), button, 1))
send(POINTER, 4)
send(POINTER, 2, struct.pack("<III", ms(), button, 0))
send(POINTER, 4)
send(DISPLAY, 0, struct.pack("<I", SYNC2))
while True:
    obj, op, body = read_event()
    if obj == SYNC2 and op == 0:
        break
    if obj == DISPLAY and op == 0:
        sys.exit(f"click: wayland error {body!r}")
time.sleep(0.5)
PY
}

# 1. The bar: the mock's two items at the bar's end.
shot bar-tray 2

# 2. A left click on the first item sends tray.activate with the item's screen position.
click "$LEFT_ITEM_X" "$HALF" left
sleep 1
# tracing colours its fields: the checks read a copy with the escape codes removed.
plain_log() { sed 's/\x1b\[[0-9;]*m//g' "$R/mock.log" > "$R/mock.plain"; }
plain_log
grep -q 'tray action: logged in the mock.*id=:1.42/StatusNotifierItem' "$R/mock.plain" \
  || fail "left click did not reach the mock as tray.activate for Nextcloud (see $R/mock.log)"
grep -q "tray action: logged in the mock.*x=$LEFT_ITEM_X y=$HALF" "$R/mock.plain" \
  || fail "tray.activate carried the wrong screen position (want x=$LEFT_ITEM_X y=$HALF)"
echo "ok: left click -> tray.activate at x=$LEFT_ITEM_X y=$HALF"

# 2b. The island's pointer target is the bar's full thickness: a click 2 px from the top edge, above
# the pill, opens the island panel (its bound left click). Closed again before the tray checks.
click "$((SW / 2))" 2 left
sleep 1.5
panel=$(ipc sub runtime.ui | jq -r '.panel')
[ "$panel" = "island" ] || fail "a click above the island pill did not open the island panel (panel \"$panel\")"
echo "ok: click 2 px above the island pill opens the island panel"
ipc act ui.close >/dev/null
sleep 1

# 3. A right click on the second item opens its menu in the Stage.
click "$RIGHT_ITEM_X" "$HALF" right
sleep 1.5
panel=$(ipc sub runtime.ui | jq -r '.panel + " " + .tray')
[ "$panel" = "tray :1.57/StatusNotifierItem" ] || fail "right click: runtime.ui is \"$panel\""
echo "ok: right click -> runtime.ui panel tray, item Network"
shot tray-menu 1.5

# 3b. A submenu opens in place: the Account row (second row group) lists its radio entries.
click 2400 178 left
sleep 1.2
shot tray-submenu 1

# 4. The same right click again closes it (K23: the same item toggles the panel).
click "$RIGHT_ITEM_X" "$HALF" right
sleep 1.5
panel=$(ipc sub runtime.ui | jq -r '.panel')
[ "$panel" = "" ] || fail "second right click did not close the tray menu (panel \"$panel\")"
echo "ok: second right click closes the tray menu"

# 5. The island panel with Bluetooth: powered, one connected keyboard.
ipc act island.expand >/dev/null || fail "island.expand refused"
shot island-bluetooth 2
bt=$(ipc sub svc.bluetooth | jq -r '[.powered, ([.devices[] | select(.connected)] | length)] | @tsv')
[ "$bt" = "$(printf 'true\t1')" ] || fail "mock bluetooth state is \"$bt\", want powered and one connected device"

# 6. A scan lists the nearby device; the adapter state is what the mock was asked for.
ipc act bluetooth.scan '{"on": true}' >/dev/null || fail "bluetooth.scan refused"
shot island-bluetooth-scan 1.5

# 6b. Connect on the unpaired device: the mock refuses it (BlueZ needs pairing), and the panel shows
# the translated call-failed line, not the daemon's key.
click 1404 260 left
shot island-bluetooth-error 1.5
[ "$(ipc sub svc.bluetooth | jq -r '.discovering')" = "true" ] || fail "scan did not start in the mock"
ipc act bluetooth.scan '{"on": false}' >/dev/null || fail "bluetooth.scan off refused"
ipc act ui.close >/dev/null

# The frontend must not log QML errors, and the mock must not have logged an unknown action.
errors='ERROR\|TypeError\|ReferenceError\|Unable to assign\|is not defined'
if grep -q "$errors" "$R/qs.log"; then
  grep "$errors" "$R/qs.log" | head >&2
  fail "frontend log has errors (see $R/qs.log)"
fi
plain_log
if grep -q 'unknown_action\|unknown action' "$R/mock.plain"; then
  fail "the mock refused an action (see $R/mock.log)"
fi
echo "ok: screenshots in $OUT"
