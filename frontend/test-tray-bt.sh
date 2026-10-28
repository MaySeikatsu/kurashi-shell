#!/usr/bin/env bash
# Tray and Bluetooth against the MOCK, invisibly (headless sway sandbox). Checks:
#   - the bar draws the mock's two tray items at its end (screenshot),
#   - a left click on an item sends tray.activate with its screen position (the mock logs it),
#   - a right click opens that item's menu in the Stage (runtime.ui: panel "tray", tray = its id;
#     screenshot), and a second right click on it closes the menu,
#   - quick settings opens its Bluetooth page: powered, one connected keyboard; a scan lists the nearby
#     device (screenshots), and the adapter's state in the mock matches what was asked,
#   - a click on the nearby device's Connect (found in the shot) is refused by the mock: the document keeps
#     both devices as they were, and the card shows the translated call-failed line,
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
RIGHT_ITEM_X=$((SW - 2 * PAD - BARH - BARH / 2))  # "Network", the second item (before the right sidebar button, I154)
LEFT_ITEM_X=$((RIGHT_ITEM_X - PAD - BARH))        # "Nextcloud", the fixture's item

shot() { # <name> [settle-seconds]
  sleep "${2:-1.5}"
  timeout 20 grim -o HEADLESS-1 "$OUT/$1.png" || fail "grim failed on $1"
  [ -s "$OUT/$1.png" ] || fail "empty screenshot $1"
  echo "shot $1"
}

# A virtual pointer clicks inside the sandbox (its seat has no pointer device): tools/bench/wl_pointer.py, the
# helper frontend/test-bindings.sh uses too. click <x> <y> <left|middle|right>, at layout coordinates.
click() {
  timeout 30 python3 -I "$ROOT/tools/bench/wl_pointer.py" click "$1" "$2" "$3"
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

# 5. Quick settings, then its Bluetooth page (docs/ux/quick-settings.md: a tile's arrow, or Right on the tile, opens its page
#    in the card): powered, one connected keyboard. The card is 400 px and centred on the output; a click on its left
#    padding (inert) gives the card the keyboard focus. Tab five times reaches the Bluetooth tile (the three status segments,
#    then the Wi-Fi tile), and Right opens its page.
ipc act quick.toggle >/dev/null || fail "quick.toggle refused"
sleep 2
click "$((SW / 2 - 195))" 300 left
sleep 0.5
{ for _ in 1 2 3 4 5; do echo tab; sleep 0.4; done; echo right; sleep 1.5; } \
  | timeout 60 python3 -I "$ROOT/tools/bench/wl_keys.py" --serve || fail "keys failed"
shot quick-bluetooth 1
bt=$(ipc sub svc.bluetooth | jq -r '[.powered, ([.devices[] | select(.connected)] | length)] | @tsv')
[ "$bt" = "$(printf 'true\t1')" ] || fail "mock bluetooth state is \"$bt\", want powered and one connected device"

# 6. A scan lists the nearby device; the adapter state is what the mock was asked for.
ipc act bluetooth.scan '{"on": true}' >/dev/null || fail "bluetooth.scan refused"
shot quick-bluetooth-scan 1.5

# 6b. Connect on the nearby (unpaired) device, which is listed while the scan runs. The mock refuses it: BlueZ
# needs a pairing. The button is found in the shot (connect.py), not at a fixed place. The outcome is asserted:
# the keyboard stays connected and the nearby device stays unconnected (a Disconnect would have changed the
# document), and the translated call-failed line is drawn in the error colour.
# Colours: the theme's tokens, or the frontend's own fallbacks (Theme.qml) where the theme lacks them.
token() {  # token <name> <fallback>: a colour token of the theme document, as hex without '#'
  local v
  v=$(ipc sub theme 2>/dev/null | jq -r --arg k "$1" '.tokens[$k] // empty' 2>/dev/null || true)
  v=${v#\#}
  echo "${v:-$2}"
}
# connect.py locate <ppm> <surface> <containerHigh> <accent> <error>: the Connect button, the lowest containerHigh band
# at the card's right edge (x and y of its centre). The card is the bar's sheet (I277: color.surface).
# connect.py error <ppm> <same colours>: the number of error-colour pixels inside the card.
cat > "$W/connect.py" <<'PY'
import sys

mode, ppm = sys.argv[1], sys.argv[2]
SURFACE, HIGH, ACCENT, ERROR = (tuple(int(c[i:i + 2], 16) for i in (0, 2, 4)) for c in sys.argv[3:7])
X0, X1, Y0, Y1 = 960, 1600, 40, 1000   # the output is 2560 wide: the card is centred on 1280, under the 36 px bar


def read_ppm(data):
    fields, i = [], 0
    while len(fields) < 4:
        while data[i:i + 1].isspace():
            i += 1
        j = i
        while not data[j:j + 1].isspace():
            j += 1
        fields.append(data[i:j])
        i = j
    if fields[0] != b"P6" or fields[3] != b"255":
        raise SystemExit(f"not an 8-bit P6 image: {fields}")
    return int(fields[1]), int(fields[2]), data[i + 1:]


with open(ppm, "rb") as f:
    w, h, raster = read_ppm(f.read())


def px(x, y):
    o = (y * w + x) * 3
    return raster[o], raster[o + 1], raster[o + 2]


def near(c, colour, tol):
    return all(abs(c[k] - colour[k]) <= tol for k in range(3))


def card():
    xs, ys = [], []
    for y in range(Y0, min(Y1, h)):
        for x in range(X0, min(X1, w)):
            if near(px(x, y), SURFACE, 3):
                xs.append(x)
                ys.append(y)
    if not xs:
        raise SystemExit("no card in the shot")
    return min(xs), min(ys), max(xs), max(ys)


def bands(column, lo, hi, colour, tol):
    # Runs of rows in one column with the colour (gaps of up to 3 rows join a run), of button height only.
    runs = []
    for y in range(max(lo, 0), min(hi, h - 1) + 1):
        if near(px(column, y), colour, tol):
            if runs and y - runs[-1][1] <= 4:
                runs[-1][1] = y
            else:
                runs.append([y, y])
    return [r for r in runs if 26 <= r[1] - r[0] + 1 <= 30]


x0, y0, x1, y1 = card()
if mode == "locate":
    # (no Close button since I279: the lowest button band in the card is Connect)
    connect = bands(x1 - 19, y0, y1, HIGH, 4)   # a button's right padding, clear of its label
    if not connect:
        raise SystemExit("no Connect button in the card")
    a, b = connect[-1]
    print(x1 - 19, (a + b) // 2)
elif mode == "error":
    print(sum(near(px(x, y), ERROR, 12) for y in range(y0, min(y1, h - 1) + 1)
              for x in range(x0, min(x1, w - 1) + 1)))
else:
    raise SystemExit(f"unknown mode {mode}")
PY
COLOURS=("$(token color.surface 1b1a1e)" "$(token color.surface_container_high 2f2c33)" \
  "$(token color.accent c9404b)" "$(token color.error e46962)")
timeout 20 grim -o HEADLESS-1 -t ppm "$W/scan.ppm" || fail "grim failed on scan.ppm"
read -r CONNECT_X CONNECT_Y < <(timeout 60 python3 -I "$W/connect.py" locate "$W/scan.ppm" "${COLOURS[@]}") \
  || fail "no Connect button in the card in the scan shot (connect.py)"
click "$CONNECT_X" "$CONNECT_Y" left
sleep 1.5
bt=$(ipc sub svc.bluetooth)
jq -e '([.devices[] | select(.address == "AA:BB:CC:DD:EE:FF") | .connected] == [true])
  and ([.devices[] | select(.address == "11:22:33:44:55:66") | .connected] == [false])
  and .discovering == true' <<<"$bt" >/dev/null \
  || fail "the click at $CONNECT_X,$CONNECT_Y did not reach the nearby device's Connect (svc.bluetooth $bt)"
timeout 20 grim -o HEADLESS-1 -t ppm "$W/error.ppm" || fail "grim failed on error.ppm"
lines=$(timeout 60 python3 -I "$W/connect.py" error "$W/error.ppm" "${COLOURS[@]}") || fail "connect.py error failed"
[ "$lines" -ge 20 ] || fail "no call-failed line in the card after Connect ($lines error-colour pixels)"
shot quick-bluetooth-error 0.5
echo "ok: Connect at $CONNECT_X,$CONNECT_Y: the mock refused it, the document keeps both devices, the card shows the call-failed line ($lines px)"
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
