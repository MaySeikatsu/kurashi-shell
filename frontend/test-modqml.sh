#!/usr/bin/env bash
# Mod QML in the bar, the Island and the card (K26, K28), invisibly (headless sway sandbox). The test mod `hello`
# (its QML in $KURASHI_MOD_HELLO, default crates/kurashid/tests/data/mods/hello/qml) logs `MODQML <what> created`
# and `... destroyed` for every component it instantiates, so the test can count them. The daemon serves `mods`,
# `runtime.slots` and `mod.panel.open` for `hello`: a build of kurashid that links it, or kurashi-mock once it does.
# $KURASHI_MODQML_DAEMON (an executable) stands in for that: it listens on $KURASHI_SOCKET and forwards everything
# to the mock at $KURASHI_MOCK_SOCKET. Steps:
#   1. mod off: the bar and the clock card instantiate nothing of the mod;
#   2. mod.enable hello: the bar widget loads; the clock card shows the footer and aside slots, never the `day`
#      contribution (ready false); the card is 400 px wide and centred under the island;
#   3. mod.panel.open {id, panel}: the card shows the hello panel, 360 px and centred; the clock slots are destroyed;
#   4. ui.close: the panel is destroyed and no card is drawn;
#   5. the panel open, then mod.disable hello: the panel and the widget are destroyed, the card closes, runtime.ui
#      names no panel;
#   6. with the mod on, `mock face hello` draws the mod's face and its expanded card; with it off, the clock stands in.
# The frontend logs no QML error and no ModLoader failure. Screenshots: frontend/shots/modqml/.
#   nix develop -c frontend/test-modqml.sh [sandbox-name]
# Binaries as in test-stage.sh: the CLI from $KURASHI_BIN_DIR (default $CARGO_TARGET_DIR/debug or target/debug), the
# mock from $KURASHI_MOCK_BIN. They are copied first, since shared target dirs get overwritten.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
NAME=${1:-fe-modqml}
BIN=${KURASHI_BIN_DIR:-${CARGO_TARGET_DIR:-$ROOT/target}/debug}
MOCK_BIN=${KURASHI_MOCK_BIN:-$BIN/kurashi-mock}
HELLO=${KURASHI_MOD_HELLO:-$ROOT/crates/kurashid/tests/data/mods/hello}
DAEMON=${KURASHI_MODQML_DAEMON:-}
OUT=$ROOT/frontend/shots/modqml
mkdir -p "$OUT"
fail() { echo "test-modqml: $*" >&2; exit 1; }

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
  rm -f "$KURASHI_SOCKET" "$R/mock.sock"
}
cleanup() {
  stop_phase
  "$ROOT/tools/bench/sandbox.sh" stop "$NAME" >/dev/null || true
}
trap cleanup EXIT

export XDG_CONFIG_HOME=$R/xdg/config XDG_STATE_HOME=$R/xdg/state \
       XDG_DATA_HOME=$R/xdg/data XDG_CACHE_HOME=$R/xdg/cache KURASHI_DATA_DIR=$ROOT LC_ALL=C.UTF-8
mkdir -p "$XDG_CONFIG_HOME" "$XDG_STATE_HOME" "$XDG_DATA_HOME" "$XDG_CACHE_HOME"

# `ipc.py <doc>` prints the first snapshot's data of a document (plain stdlib, as in test-stage.sh).
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

# The card's surface (Theme.container, color.surface_container) in the output's centre column: its bounding box.
cat > "$W/analyse.py" <<'PY'
import json, sys

SURFACE = (0x25, 0x23, 0x29)   # color.surface_container in the mock's theme
TOL = 3
X0, X1, Y0, Y1 = 960, 1600, 40, 900   # the output is 2560 wide: a card is centred on 1280, under the 36 px bar


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

# card <name> <width>: the card is drawn at the width asked for, centred on the output; the crop is the evidence shot.
card() {
  local res cx cy x0 y0 x1 y1
  ppm_shot "$1" 2.5
  res=$(analyse "$1") || fail "$1: analysis failed"
  echo "$1: $res"
  jq -e --argjson w "$2" '.surface >= 15000 and .bbox != null
      and (((.bbox[2] - .bbox[0] + 1) - ($w - 2)) | fabs) <= 4
      and (((.bbox[0] + .bbox[2]) / 2 - 1280) | fabs) <= 4' <<<"$res" >/dev/null \
    || fail "$1: no card of width $2 centred on the output ($res)"
  read -r x0 y0 x1 y1 < <(jq -r '.bbox | "\(.[0]) \(.[1]) \(.[2]) \(.[3])"' <<<"$res")
  cx=$((x0 - 24)); cy=$((y0 - 24))
  ((cx < 0)) && cx=0
  ((cy < 0)) && cy=0
  timeout 20 grim -g "$cx,$cy $((x1 - x0 + 49))x$((y1 - y0 + 49))" "$OUT/$1.png" || fail "grim failed on $1"
}
# closed <name>: no card is drawn (Ma: the Stage is empty once closed).
closed() {
  local res
  ppm_shot "$1" 1.5
  res=$(analyse "$1") || fail "$1: analysis failed"
  echo "$1: $res"
  jq -e '.surface < 500' <<<"$res" >/dev/null || fail "$1: a card is still drawn ($res)"
}
# bar <name>: the bar's middle and right part (the Island and the widget slot), as evidence.
bar() { timeout 20 grim -g "1100,0 1460x40" "$OUT/$1.png" || fail "grim failed on $1"; }
ppm_shot() {
  sleep "$2"
  timeout 20 grim -o HEADLESS-1 -t ppm "$W/$1.ppm" || fail "grim failed on $1"
}
# Log counts: the test mod's QML lines (the frontend's qs.log), cumulative since the frontend started.
mq() { grep -c -F "MODQML $1" "$R/qs.log" || true; }
expect() {  # expect <what> <count> <want>
  local got
  got=$(mq "$1")
  [ "$got" -eq "$3" ] || fail "$2: MODQML '$1' seen $got times, want $3"
  echo "log: $2 ($1 x$got)"
}

start_daemon() {
  rm -f "$KURASHI_SOCKET" "$R/mock.sock"
  if [ -n "$DAEMON" ]; then
    export KURASHI_MOCK_SOCKET=$R/mock.sock KURASHI_MOD_HELLO=$HELLO
    RUST_LOG=info "$W/kurashi-mock" --outputs HEADLESS-1 --fixed-time 12:34 --socket "$KURASHI_MOCK_SOCKET" \
      >> "$R/server.log" 2>&1 &
    pids+=("$!")
    for _ in $(seq 100); do [ -S "$KURASHI_MOCK_SOCKET" ] && break; sleep 0.1; done
    "$DAEMON" >> "$R/server.log" 2>&1 &
    pids+=("$!")
  else
    RUST_LOG=info "$W/kurashi-mock" --outputs HEADLESS-1 --fixed-time 12:34 --socket "$KURASHI_SOCKET" \
      >> "$R/server.log" 2>&1 &
    pids+=("$!")
  fi
  for _ in $(seq 100); do [ -S "$KURASHI_SOCKET" ] && ipc svc.clock >/dev/null 2>&1 && return 0; sleep 0.1; done
  fail "daemon did not come up (see $R/server.log)"
}
start_frontend() {
  # Without KURASHI_SOCKET: the frontend must find the socket by the protocol default, as in a live session.
  env -u KURASHI_SOCKET qs -p "$ROOT/frontend" >> "$R/qs.log" 2>&1 &
  pids+=("$!")
  for _ in $(seq 100); do grep -q 'hello.*frontend' "$R/server.log" && break; sleep 0.1; done
  sleep 3   # the bar's documents and the first frames
}

: > "$R/qs.log"
: > "$R/server.log"
start_daemon
start_frontend

# 1. mod off: the clock card (and the bar) instantiate nothing of the mod.
mods=$(ipc mods) || fail "the mods document is not served (the daemon must serve it for hello)"
jq -e '[.mods[] | select(.id == "hello") | has("qml")] == [false]' <<<"$mods" >/dev/null \
  || fail "mods: hello has a qml map while it is off"
K act island.expand >/dev/null
card clock-mod-off 400
K act ui.close >/dev/null
closed closed-mod-off
expect "" "mod off: no MODQML line" 0

# 2. mod.enable: the bar widget, and the clock card's footer and aside (the day contribution is not ready).
K act mod.enable '{"id":"hello"}' >/dev/null
sleep 1.5
expect "widget created" "enabled: bar widget loaded" 1
slots=$(ipc runtime.slots) || fail "runtime.slots is not served (the daemon must serve it for hello)"
jq -e '(."clock.expanded.footer" | length) == 1 and ."clock.expanded.footer"[0].ready == true
    and ((."clock.expanded.day" // []) | map(select(.ready == true)) | length) == 0' <<<"$slots" >/dev/null \
  || fail "runtime.slots does not list the ready footer and no ready day contribution"
bar island-widget
K act island.expand >/dev/null
card clock-slots 400
expect "slot clock.expanded.footer created" "enabled: footer in the clock card" 1
expect "slot clock.expanded.aside created" "enabled: aside in the clock card" 1
expect "slot clock.expanded.day created" "not ready: the day contribution never loads" 0

# 3. mod.panel.open: the panel replaces the clock card; its slots are destroyed (no stale component).
K act mod.panel.open '{"id":"hello","panel":"hello"}' >/dev/null
ipc runtime.ui | jq -e '.panel == "mod:hello:hello"' >/dev/null || fail "runtime.ui does not name the mod panel"
card mod-panel 360
expect "panel created" "panel open: the hello panel loads" 1
expect "slot clock.expanded.footer destroyed" "panel open: the footer is gone" 1
expect "slot clock.expanded.aside destroyed" "panel open: the aside is gone" 1

# 4. ui.close: the panel is destroyed; nothing is drawn.
K act ui.close >/dev/null
closed closed-panel
expect "panel destroyed" "closed: the panel is destroyed" 1

# 5. the panel open, then mod.disable: the panel and the widget go; the card closes; no panel is named.
K act mod.panel.open '{"id":"hello","panel":"hello"}' >/dev/null
sleep 2
expect "panel created" "panel open again" 2
K act mod.disable '{"id":"hello"}' >/dev/null
sleep 2
expect "panel destroyed" "disabled with the panel open: the panel is destroyed" 2
expect "widget destroyed" "disabled: the widget is destroyed" 1
ipc runtime.ui | jq -e '(.panel // "") == ""' >/dev/null || fail "runtime.ui still names a panel after mod.disable"
closed closed-disabled

# 6. the island face of the mod: drawn with the mod on, the clock stands in with it off.
K act mod.enable '{"id":"hello"}' >/dev/null
sleep 1.5
K mock face hello >/dev/null
sleep 2
expect "face created" "enabled: the island draws the mod face" 1
bar island-face-hello
K act island.expand >/dev/null
card face-expanded 360
expect "face-expanded created" "the expanded face loads in the card" 1
K act ui.close >/dev/null
closed closed-face
expect "face-expanded destroyed" "closed: the expanded face is destroyed" 1
K act mod.disable '{"id":"hello"}' >/dev/null
sleep 2
expect "face destroyed" "disabled: the mod face is destroyed" 1
bar island-face-fallback

stop_phase
if grep -q "ERROR\|TypeError\|ReferenceError\|Unable to assign\|is not defined\|is not a type\|Cannot assign\|Cannot anchor\|Binding loop\|ModLoader: cannot load\|Expected a qualified" "$R/qs.log"; then
  echo "qs.log has errors:" >&2
  grep "ERROR\|TypeError\|ReferenceError\|Unable to assign\|is not defined\|is not a type\|Cannot assign\|Cannot anchor\|Binding loop\|ModLoader: cannot load\|Expected a qualified" "$R/qs.log" | head >&2
  exit 1
fi
echo "ok: screenshots in $OUT"
