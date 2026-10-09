#!/usr/bin/env bash
# The quick settings card's sections (K24, W12) against kurashi-mock, invisibly (headless sway sandbox):
# Wi-Fi, Power, Audio output and Bluetooth, each from its own document. Checks:
#   - quick.toggle opens the card (runtime.ui panel "quick"); its screenshot shows the card, 360 px wide and
#     centred on the output;
#   - a pointer click on the Wi-Fi switch sends network.wifi: svc.network.wifi_enabled flips;
#   - a pointer click on a non-default sink row sends audio.sink.default: that sink becomes svc.audio's default;
#   - keyboard: a click on the heading gives the Stage its focus, Tab reaches the Wi-Fi switch and Return flips
#     it back, Tab walks to the original default's row and Return makes it the default again, and the focus then
#     stays on the chosen row (one more Tab and Return move the default on);
#   - ui.close closes the card (Ma: no card drawn), and the frontend logs no QML error.
#   nix develop -c frontend/test-quick-sections.sh [sandbox-name]
# The mock must serve svc.network, svc.audio's `available` and `sinks`, and the actions network.wifi and
# audio.sink.default (W12-quick-daemon); without them the test stops at the precondition, after the first shot.
# Binaries: kurashi and kurashi-mock from $KURASHI_BIN_DIR (default $CARGO_TARGET_DIR/debug, else target/debug),
# copied first, since shared target dirs get overwritten. The shots in frontend/shots/quick-sections/ are
# evidence to read, not just the exit code. On a hybrid laptop export KURASHI_RENDER_NODE first.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
NAME=${1:-fe-quick-sections}
BIN=${KURASHI_BIN_DIR:-${CARGO_TARGET_DIR:-$ROOT/target}/debug}
MOCK_BIN=${KURASHI_MOCK_BIN:-$BIN/kurashi-mock}
OUT=$ROOT/frontend/shots/quick-sections
mkdir -p "$OUT"
fail() { echo "test-quick-sections: $*" >&2; exit 1; }

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
K() { timeout 10 "$W/kurashi" "$@"; }
# doc <name>: the document's data as JSON, or nothing when the daemon does not serve it.
doc() { K sub "$1" --count 0 --json 2>/dev/null | jq -c 'select(.t == "snap") | .data' || true; }
panel() { doc runtime.ui | jq -r '.panel // ""' 2>/dev/null || true; }

# The card's surface (Theme.container, color.surface_container) in the output's centre column: its pixel
# count and bounding box. A card is drawn only where its surface is; a closed Stage draws nothing.
cat > "$W/analyse.py" <<'PY'
import json, sys

SURFACE = tuple(int(sys.argv[2][i:i + 2], 16) for i in (0, 2, 4))
TOL = 3
X0, X1, Y0, Y1 = 960, 1600, 40, 1000   # the output is 2560 wide: the card is centred on 1280, under the 36 px bar


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

# rows.py: the screen y of an audio row, from the default sink's ring: 16 px tall, drawn in the accent colour
# (its border and its dot), 16 px into the card. The rows are 40 px apart (32 px rows, 8 px gaps).
cat > "$W/rows.py" <<'PY'
import sys

ppm = sys.argv[1]
x0, y0, y1, d, j = (int(v) for v in sys.argv[2:7])
ACCENT = tuple(int(sys.argv[7][i:i + 2], 16) for i in (0, 2, 4))
PITCH = 40
TOL = 8
X = x0 + 24   # the ring's centre column


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
# The ring's accent rows (border, dot, border) in its column, grouped where the gaps are small (the interior
# is the card's surface, 3 rows each side of the dot). The audio rows lie within +100..+340 px of the top.
hits = [y for y in range(y0 + 100, min(y1, h - 1, y0 + 340) + 1)
        if all(abs(raster[(y * w + X) * 3 + k] - ACCENT[k]) <= TOL for k in range(3))]
clusters = []
for y in hits:
    if clusters and y - clusters[-1][1] <= 5:
        clusters[-1][1] = y
    else:
        clusters.append([y, y])
rings = [c for c in clusters if 12 <= c[1] - c[0] + 1 <= 18]
if len(rings) != 1:
    raise SystemExit(f"want one default ring, found {clusters}")
a, b = rings[0]
print(round((a + b) / 2 + (j - d) * PITCH))
PY

# ppm_shot <name> <settle s>: the PPM the card analysis reads (the output, not a crop).
ppm_shot() {
  sleep "$2"
  timeout 20 grim -o HEADLESS-1 -t ppm "$W/$1.ppm" || fail "grim failed on $1"
}
# card_shot <name> <settle s>: the open card's bounding box (card_x0 card_y0 card_x1 card_y1, layout
# coordinates) and a crop of it as the evidence shot.
card_shot() {
  local res cx cy
  ppm_shot "$1" "$2"
  res=$(timeout 60 python3 -I "$W/analyse.py" "$W/$1.ppm" "$(token color.surface_container 252329)") \
    || fail "$1: analysis failed"
  echo "$1: $res"
  jq -e '.surface >= 15000 and .bbox != null
      and (((.bbox[2] - .bbox[0] + 1) - 358) | fabs) <= 4
      and (((.bbox[0] + .bbox[2]) / 2 - 1280) | fabs) <= 4' <<<"$res" >/dev/null \
    || fail "$1: no card 360 px wide centred on the output ($res)"
  read -r card_x0 card_y0 card_x1 card_y1 < <(jq -r '.bbox | "\(.[0]) \(.[1]) \(.[2]) \(.[3])"' <<<"$res")
  cx=$((card_x0 - 24))
  cy=$((card_y0 - 24))
  ((cx < 0)) && cx=0
  ((cy < 0)) && cy=0
  timeout 20 grim -g "$cx,$cy $((card_x1 - card_x0 + 49))x$((card_y1 - card_y0 + 49))" "$OUT/$1.png" \
    || fail "grim failed on $1"
  [ -s "$OUT/$1.png" ] || fail "empty screenshot $1"
  echo "shot $1"
}
# token <name> <fallback>: a colour token of the daemon's theme document, else the frontend's own fallback for it
# (the colour Theme.qml draws without the token), as hex without '#'.
token() {
  local v
  v=$(doc theme | jq -r --arg k "$1" '.tokens[$k] // empty' 2>/dev/null || true)
  v=${v#\#}
  echo "${v:-$2}"
}
# row_y <ppm> <default index> <index>: the screen y of audio row <index>, from the default row's ring in that shot.
row_y() {
  timeout 60 python3 -I "$W/rows.py" "$1" "$card_x0" "$card_y0" "$card_y1" "$2" "$3" "$accent" \
    || fail "no default sink ring in $1 (rows.py)"
}
click() {  # click <x> <y>: a left click of the virtual pointer, at layout coordinates
  timeout 30 python3 -I "$ROOT/tools/bench/wl_pointer.py" click "$1" "$2" left || fail "click at $1,$2 failed"
}

start_mock() {
  rm -f "$KURASHI_SOCKET"
  RUST_LOG=info "$W/kurashi-mock" --outputs HEADLESS-1 --fixed-time 12:34 --socket "$KURASHI_SOCKET" \
    >> "$R/server.log" 2>&1 &
  pids+=("$!")
  for _ in $(seq 100); do [ -S "$KURASHI_SOCKET" ] && K sub svc.clock --count 0 --json >/dev/null 2>&1 && return 0; sleep 0.1; done
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

# Layout offset (sandbox fonts; the card is 360 px with 16 px margins): the Wi-Fi switch's centre lies WIFI_DX px
# left of the card's right edge and WIFI_DY px below its top (measured in the shot). The audio rows are found in
# the shot (rows.py). A click that misses changes nothing, and the document check after it fails.
WIFI_DX=35
WIFI_DY=62

: > "$R/qs.log"
: > "$R/server.log"
start_mock
start_frontend

# 1. The card opens on the quick panel and shows its four sections (the shot is the evidence).
K act quick.toggle >/dev/null || fail "quick.toggle refused"
for _ in $(seq 25); do [ "$(panel)" = quick ] && break; sleep 0.2; done
[ "$(panel)" = quick ] || fail "quick.toggle did not open the quick panel (runtime.ui panel \"$(panel)\")"
card_shot quick-open 1.5
echo "ok: quick.toggle opens the card (panel quick)"

# 2. The data the sections show (the mock must serve these to act on them).
net=$(doc svc.network)
[ -n "$net" ] && jq -e '.state | type == "string"' <<<"$net" >/dev/null \
  || fail "the mock does not serve svc.network (W12-quick-daemon): ${net:-no document}"
aud=$(doc svc.audio)
jq -e '.available == true and ((.sinks // []) | length) >= 2' <<<"$aud" >/dev/null \
  || fail "the mock's svc.audio has no available sinks (W12-quick-daemon): ${aud:-no document}"
pw=$(doc svc.power)
echo "svc.power: $pw"
echo "svc.network: $net"
echo "svc.audio sinks: $(jq -c '.sinks' <<<"$aud")"

# 3. A click on the Wi-Fi switch flips svc.network.wifi_enabled (the document follows NetworkManager).
wifi0=$(jq -r '.wifi_enabled' <<<"$net")
flipped=$([ "$wifi0" = true ] && echo false || echo true)
click $((card_x1 - WIFI_DX)) $((card_y0 + WIFI_DY))
sleep 1.5
wifi1=$(doc svc.network | jq -r '.wifi_enabled')
[ "$wifi1" = "$flipped" ] || fail "a click on the Wi-Fi switch did not flip svc.network.wifi_enabled ($wifi0 -> $wifi1)"
echo "ok: click on the Wi-Fi switch: wifi_enabled $wifi0 -> $wifi1"
card_shot quick-wifi-clicked 1.0

# 4. A click on a non-default sink row makes it the default (audio.sink.default).
orig_default=$(jq -r '[.sinks | to_entries[] | select(.value.default == true) | .key] | first // empty' <<<"$aud")
j=$(jq -r '[.sinks | to_entries[] | select(.value.default != true) | .key] | first // empty' <<<"$aud")
[ -n "$j" ] && [ -n "$orig_default" ] || fail "the sinks need a default and a non-default one: $(jq -c '.sinks' <<<"$aud")"
want=$(jq -r --argjson j "$j" '.sinks[$j].id' <<<"$aud")
accent=$(token color.accent c9404b)
ty=$(row_y "$W/quick-wifi-clicked.ppm" "$orig_default" "$j")
echo "sink row $j: centre y $ty (default row $orig_default)"
click $((card_x0 + 180)) "$ty"
sleep 1.5
now=$(doc svc.audio | jq -r '[.sinks[] | select(.default == true) | .id] | first // empty')
[ "$now" = "$want" ] || fail "a click on sink row $j did not make it the default (default id \"$now\", want \"$want\")"
echo "ok: click on sink row $j: default id $want"
card_shot quick-sink-clicked 1.0

# 5. Keyboard, on one virtual keyboard for the whole part: a keyboard that goes away makes the compositor drop
#    the window's keyboard focus (wl_keys.py's one-shot calls would), so the keys go through a FIFO to one
#    long-running keyboard. A click on the heading gives the Stage its focus; Tab reaches the Wi-Fi switch (Return
#    flips it back); Tab walks down the sinks to the original default's row (Return makes it the default again);
#    and one more Tab and Return make the next row the default, which shows that the focus stayed on the row it
#    chose (the rows update in place).
mkfifo "$W/keys.fifo"
timeout 120 python3 -I "$ROOT/tools/bench/wl_keys.py" --serve < "$W/keys.fifo" >> "$R/keys.log" 2>&1 &
pids+=("$!")
exec 3> "$W/keys.fifo"
press() {  # press <key>...: one line per key to the helper, a short pause after each
  local k
  for k in "$@"; do
    printf '%s\n' "$k" >&3 || fail "the keyboard helper stopped (see $R/keys.log)"
    sleep 0.4
  done
}
click $((card_x0 + 60)) $((card_y0 + 24))
press tab return
sleep 1
wifi2=$(doc svc.network | jq -r '.wifi_enabled')
[ "$wifi2" = "$wifi0" ] || fail "Tab and Return did not flip the Wi-Fi switch back ($wifi1 -> $wifi2)"
echo "ok: keyboard: Tab and Return flipped the Wi-Fi switch back to $wifi2"
steps=()
for _ in $(seq $((orig_default + 1))); do steps+=(tab); done
press "${steps[@]}" return
sleep 1
now=$(doc svc.audio | jq -r '[.sinks[] | select(.default == true) | .id] | first // empty')
want=$(jq -r --argjson j "$orig_default" '.sinks[$j].id' <<<"$aud")
[ "$now" = "$want" ] || fail "keyboard: Tab to sink row $orig_default and Return did not restore the default (id \"$now\", want \"$want\")"
echo "ok: keyboard: Tab to sink row $orig_default and Return: default id $want"
if [ $((orig_default + 1)) -lt "$(jq '.sinks | length' <<<"$aud")" ]; then
  press tab return
  sleep 1
  want=$(jq -r --argjson j "$((orig_default + 1))" '.sinks[$j].id' <<<"$aud")
  now=$(doc svc.audio | jq -r '[.sinks[] | select(.default == true) | .id] | first // empty')
  [ "$now" = "$want" ] || fail "focus did not stay on sink row $orig_default: Tab and Return made id \"$now\" the default, want \"$want\""
  echo "ok: keyboard: the focus stayed on the chosen row: Tab and Return made row $((orig_default + 1)) the default"
fi
card_shot quick-keyboard 0.8
exec 3>&-

# 6. ui.close: the card is gone (Ma).
K act ui.close >/dev/null || fail "ui.close refused"
ppm_shot quick-closed 1.5
closed=$(timeout 60 python3 -I "$W/analyse.py" "$W/quick-closed.ppm" "$(token color.surface_container 252329)")
jq -e '.surface < 500' <<<"$closed" >/dev/null || fail "a card is still drawn after ui.close ($closed)"
echo "ok: ui.close: no card drawn"

stop_phase
errors='ERROR\|TypeError\|ReferenceError\|Unable to assign\|is not defined\|is not a type\|Cannot assign\|Cannot anchor\|Binding loop\|non-existent property'
if grep -q "$errors" "$R/qs.log"; then
  echo "qs.log has errors:" >&2
  grep "$errors" "$R/qs.log" | head >&2
  exit 1
fi
echo "ok: sections, clicks and keys; screenshots in $OUT"
