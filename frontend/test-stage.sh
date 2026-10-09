#!/usr/bin/env bash
# The island card's expanded views and the quick settings card (K24), invisibly (headless sway sandbox).
# Against kurashi-mock (--fixed-time 12:34): for each face (clock, media, volume, brightness,
# notifications, and an unknown face for the generic card) `mock face <f>`, `act island.expand`, a
# screenshot, `act ui.close`; then `act quick.toggle`, a screenshot, a click on its heading (keyboard focus),
# Tab and Space on the Bluetooth switch (the mock's adapter goes off), `act ui.close`. Each open shot must
# have runtime.ui with the expected panel and face, and a card of the width its view asks for (400 for
# media and clock, 360 otherwise), centred on the output. Each closed shot must have no card (Ma). The
# frontend logs no QML error.
#   nix develop -c frontend/test-stage.sh [sandbox-name]
# Binaries: kurashi from $KURASHI_BIN_DIR (default $CARGO_TARGET_DIR/debug or target/debug), the mock from
# $KURASHI_MOCK_BIN (default: kurashi-mock in the same dir). They are copied first, since shared target
# dirs get overwritten. The card crops in frontend/shots/stage/ are evidence to read, not just the exit
# code. On a hybrid laptop export KURASHI_RENDER_NODE first.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
NAME=${1:-fe-stage}
BIN=${KURASHI_BIN_DIR:-${CARGO_TARGET_DIR:-$ROOT/target}/debug}
MOCK_BIN=${KURASHI_MOCK_BIN:-$BIN/kurashi-mock}
OUT=$ROOT/frontend/shots/stage
mkdir -p "$OUT"
fail() { echo "test-stage: $*" >&2; exit 1; }

eval "$("$ROOT/tools/bench/sandbox.sh" start "$NAME")"
R=$XDG_RUNTIME_DIR
W=$R/work
mkdir -p "$W" "$R/kurashi"
cp "$BIN/kurashi" "$W/"
cp "$MOCK_BIN" "$W/kurashi-mock"

pids=()
stop_phase() {  # kills only the processes this script started
  for p in "${pids[@]}"; do kill "$p" 2>/dev/null || true; done
  for p in "${pids[@]}"; do wait "$p" 2>/dev/null || true; done
  pids=()
  rm -f "$KURASHI_SOCKET"
}
cleanup() {
  stop_phase
  "$ROOT/tools/bench/sandbox.sh" stop "$NAME" >/dev/null || true
}
trap cleanup EXIT

export XDG_CONFIG_HOME=$R/xdg/config XDG_STATE_HOME=$R/xdg/state \
       XDG_DATA_HOME=$R/xdg/data XDG_CACHE_HOME=$R/xdg/cache KURASHI_DATA_DIR=$ROOT LC_ALL=C.UTF-8
mkdir -p "$XDG_CONFIG_HOME" "$XDG_STATE_HOME" "$XDG_DATA_HOME" "$XDG_CACHE_HOME"

# `ipc.py <doc>` prints the first snapshot's data of a document (plain stdlib, as in test-volume.sh).
cat > "$W/ipc.py" <<'PY'
import json, os, socket, sys

sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
sock.settimeout(5)
sock.connect(os.environ["KURASHI_SOCKET"])
f = sock.makefile("rwb")


def send(msg):
    f.write((json.dumps(msg) + "\n").encode())
    f.flush()


send({"t": "hello", "v": 1, "client": "test", "caps": ["intents", "resync"]})
if json.loads(f.readline())["t"] != "welcome":
    sys.exit("ipc: no welcome")
send({"t": "sub", "id": "s", "doc": sys.argv[1]})
while True:
    line = f.readline()
    if not line:
        sys.exit("ipc: connection closed")
    m = json.loads(line)
    if m.get("id") == "s" and m["t"] in ("snap", "err"):
        if m["t"] == "err":
            sys.exit("ipc: " + json.dumps(m))
        print(json.dumps(m.get("data")))
        break
PY
ipc() { timeout 10 python3 -I "$W/ipc.py" "$@"; }
K() { timeout 10 "$W/kurashi" "$@"; }

# The card's surface (Theme.container, color.surface_container) in the output's centre column: its
# pixel count and bounding box. A card is drawn only where its surface is; a closed Stage draws nothing.
cat > "$W/analyse.py" <<'PY'
import json, sys

SURFACE = (0x25, 0x23, 0x29)   # color.surface_container in the mock's theme
TOL = 3
X0, X1, Y0, Y1 = 960, 1600, 40, 720   # the output is 2560 wide: the card is centred on 1280, under the 36 px bar


def read_ppm(data):
    # Four whitespace-separated fields (magic, width, height, maxval), one whitespace byte, the raster.
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


with open(sys.argv[1], "rb") as f:
    w, h, raster = read_ppm(f.read())
n = 0
x0 = y0 = 1 << 30
x1 = y1 = -1
for y in range(Y0, min(Y1, h)):
    row = y * w * 3
    for x in range(X0, min(X1, w)):
        o = row + x * 3
        if (abs(raster[o] - SURFACE[0]) <= TOL and abs(raster[o + 1] - SURFACE[1]) <= TOL
                and abs(raster[o + 2] - SURFACE[2]) <= TOL):
            n += 1
            x0, x1 = min(x0, x), max(x1, x)
            y0, y1 = min(y0, y), max(y1, y)
print(json.dumps({"surface": n, "bbox": [x0, y0, x1, y1] if n else None}))
PY
analyse() { timeout 60 python3 -I "$W/analyse.py" "$W/$1.ppm"; }

# ppm_shot <name> <settle s>: the PPM for the pixel check only (a closed Stage needs no look).
ppm_shot() {
  sleep "$2"
  timeout 20 grim -o HEADLESS-1 -t ppm "$W/$1.ppm" || fail "grim failed on $1"
}
# open_card <name> <panel> <face> <card width>: the panel and face in runtime.ui, the card drawn at the
# width its view asks for and centred on the output; then the crop of the card as the evidence shot.
open_card() {  # also sets card_x0 card_y0 card_x1 card_y1 (the card's surface, layout coordinates)
  local ui res cx cy
  ui=$(ipc runtime.ui) || fail "$1: runtime.ui not served"
  jq -e --arg p "$2" --arg f "$3" '.panel == $p and .face == $f' <<<"$ui" >/dev/null \
    || fail "$1: runtime.ui is $ui, not panel $2 face $3"
  res=$(analyse "$1") || fail "$1: analysis failed"
  echo "$1: $ui $res"
  jq -e --argjson w "$4" '.surface >= 15000 and .bbox != null
      and (((.bbox[2] - .bbox[0] + 1) - ($w - 2)) | fabs) <= 4
      and (((.bbox[0] + .bbox[2]) / 2 - 1280) | fabs) <= 4' <<<"$res" >/dev/null \
    || fail "$1: no card of width $4 centred on the output ($res)"
  read -r card_x0 card_y0 card_x1 card_y1 < <(jq -r '.bbox | "\(.[0]) \(.[1]) \(.[2]) \(.[3])"' <<<"$res")
  # -g takes layout coordinates (one output at 0,0 in the sandbox); -o and -g do not combine.
  cx=$((card_x0 - 24))
  cy=$((card_y0 - 24))
  ((cx < 0)) && cx=0
  ((cy < 0)) && cy=0
  timeout 20 grim -g "$cx,$cy $((card_x1 - card_x0 + 49))x$((card_y1 - card_y0 + 49))" "$OUT/$1.png" \
    || fail "grim failed on $1"
  [ -s "$OUT/$1.png" ] || fail "empty screenshot $1"
  echo "shot $1"
}
# closed_card <name>: no card is drawn after ui.close.
closed_card() {
  local res
  res=$(analyse "$1") || fail "$1: analysis failed"
  echo "$1: $res"
  jq -e '.surface < 500' <<<"$res" >/dev/null || fail "$1: a card is still drawn after ui.close ($res)"
}

start_mock() {
  rm -f "$KURASHI_SOCKET"
  RUST_LOG=info "$W/kurashi-mock" --outputs HEADLESS-1 --fixed-time 12:34 --socket "$KURASHI_SOCKET" \
    >> "$R/server.log" 2>&1 &
  pids+=("$!")
  for _ in $(seq 100); do [ -S "$KURASHI_SOCKET" ] && ipc svc.clock >/dev/null 2>&1 && return 0; sleep 0.1; done
  fail "mock did not come up (see $R/server.log)"
}
start_frontend() {
  # Without KURASHI_SOCKET: the frontend must find the socket by the protocol default, as in a live session.
  env -u KURASHI_SOCKET qs -p "$ROOT/frontend" >> "$R/qs.log" 2>&1 &
  pids+=("$!")
  for _ in $(seq 100); do grep -q 'hello.*frontend' "$R/server.log" && break; sleep 0.1; done
  grep -q 'hello.*frontend' "$R/server.log" || fail "frontend never said hello (see $R/qs.log)"
  sleep 3   # the bar's documents and the first frames
}

: > "$R/qs.log"
: > "$R/server.log"
start_mock
start_frontend

# Face (and the card width its expanded view asks for). `weather` is no island face: the generic card.
for spec in clock:400 media:400 volume:360 brightness:360 notifications:360 weather:360; do
  face=${spec%%:*}
  width=${spec##*:}
  K mock face "$face" >/dev/null
  sleep 0.3
  K act island.expand >/dev/null
  ppm_shot "island-$face" 2.5
  open_card "island-$face" island "$face" "$width"
  K act ui.close >/dev/null
  ppm_shot "closed-$face" 1.2
  closed_card "closed-$face"
done

K act quick.toggle >/dev/null
ppm_shot quick 2.5
open_card quick quick "" 360
# Keyboard: the Tab stops before the Bluetooth switch come from the data, in the card's order: the Wi-Fi switch
# when svc.network serves a state, then one stop per audio sink when svc.audio is available. A click on the card's
# heading gives the Stage its keyboard focus (on-demand layer surface); Tab that many times, then Space flips the
# switch, so the mock's adapter goes off.
net=$(ipc svc.network 2>/dev/null) || net=""
aud=$(ipc svc.audio 2>/dev/null) || aud=""
stops=0
if jq -e '(.state | type) == "string" and .state != "unavailable"' <<<"$net" >/dev/null 2>&1; then
  stops=$((stops + 1))
fi
if jq -e '.available == true' <<<"$aud" >/dev/null 2>&1; then
  stops=$((stops + $(jq '(.sinks // []) | length' <<<"$aud")))
fi
tabs=$((stops + 1))
echo "keyboard: the Bluetooth switch is Tab stop $tabs"
timeout 30 python3 -I "$ROOT/tools/bench/wl_pointer.py" click "$((card_x0 + 60))" "$((card_y0 + 24))" left \
  || fail "click on the quick card failed"
sleep 0.5
{ for _ in $(seq "$tabs"); do echo tab; sleep 0.3; done; echo space; sleep 0.5; } \
  | timeout 60 python3 -I "$ROOT/tools/bench/wl_keys.py" --serve || fail "keys failed"
sleep 1.5
bt=$(ipc svc.bluetooth) || fail "svc.bluetooth not served"
jq -e '.powered == false' <<<"$bt" >/dev/null \
  || fail "Tab $tabs times, then Space, did not flip the Bluetooth switch (svc.bluetooth $bt)"
echo "keyboard: Tab x$tabs then Space flipped the Bluetooth switch: $bt"
K act ui.close >/dev/null
ppm_shot closed-quick 1.2
closed_card closed-quick

stop_phase
if grep -q "ERROR\|TypeError\|ReferenceError\|Unable to assign\|is not defined\|is not a type\|Cannot assign\|Cannot anchor\|Binding loop" "$R/qs.log"; then
  echo "qs.log has errors:" >&2
  grep "ERROR\|TypeError\|ReferenceError\|Unable to assign\|is not defined\|is not a type\|Cannot assign\|Cannot anchor\|Binding loop" "$R/qs.log" | head >&2
  exit 1
fi
echo "ok: card crops in $OUT"
