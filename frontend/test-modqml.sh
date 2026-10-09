#!/usr/bin/env bash
# Mod QML in the bar, the Island and the Stage (K26, K28), invisibly (headless sway sandbox), in the real kurashid built
# with `--features test-mods`, which links the test mod `hello` (W14: this script no longer runs a proxy in front of
# kurashi-mock). The mod's components log `MODQML <what> created|destroyed` as they come and go, so the test counts what
# loads and when it goes. Steps:
#   1. mod off: `mods` lists no qml for hello, no slot is listed, and the clock card is drawn without its contributions;
#   2. mod.enable: the bar widget; the clock card's footer and aside;
#   3. mod.panel.open: the panel replaces the clock card, and the clock's slots are destroyed;
#   4. ui.close: the panel is destroyed; nothing is drawn;
#   5. the panel open, then mod.disable: the panel and the widget go; no panel is named;
#   6. the island face: raised by the mod's test action, its expanded card, cleared;
#   7. media: the backdrop and the line under the transport (the island's media face, reached with island.next);
#   8. notifications: the header row of the notifications face;
#   9. quick settings: the tile;
#  10. mod.disable with everything closed: every component the mod loaded is destroyed.
# The frontend logs no QML warning: no qml/scene WARN or ERROR, no binding loop, no reference or type error.
# Screenshots: frontend/shots/modqml/. Usage (machine B):
#   KURASHI_RENDER_NODE=/dev/dri/renderD129 KURASHI_BIN_DIR=<dir with kurashi, kurashid (test-mods)> \
#     timeout 900 nix develop -c frontend/test-modqml.sh [sandbox-name]
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
NAME=${1:-modqml-$$}   # unique per run: other agents' runs stop any sandbox that shares a name
BIN=${KURASHI_BIN_DIR:-${CARGO_TARGET_DIR:-$ROOT/target}/debug}
HELLO=$ROOT/crates/kurashid/tests/data/mods/hello
OUT=$ROOT/frontend/shots/modqml
mkdir -p "$OUT"
fail() { echo "test-modqml: $*" >&2; exit 1; }

eval "$("$ROOT/tools/bench/sandbox.sh" start "$NAME")"
R=$XDG_RUNTIME_DIR
W=$R/work
mkdir -p "$W" "$R/kurashi"
# The wayland socket can appear before the compositor serves clients (slow under load): wait until sway answers.
for _ in $(seq 150); do timeout 5 swaymsg -t get_outputs >/dev/null 2>&1 && break; sleep 0.2; done
timeout 5 swaymsg -t get_outputs >/dev/null 2>&1 || fail "the headless compositor does not answer (see $R/sway.log)"
cp "$BIN/kurashi" "$BIN/kurashid" "$W/"
grep -aq 'hello.raise' "$W/kurashid" || fail "$BIN/kurashid links no test mod: build it with --features test-mods"

pids=()
cleanup() {
  for p in "${pids[@]}"; do kill "$p" 2>/dev/null || true; done
  for p in "${pids[@]}"; do wait "$p" 2>/dev/null || true; done
  "$ROOT/tools/bench/sandbox.sh" stop "$NAME" >/dev/null || true
}
trap cleanup EXIT

rm -rf "$R/xdg"   # hermetic: a config left by an earlier run would leave `hello` enabled
export XDG_CONFIG_HOME=$R/xdg/config XDG_STATE_HOME=$R/xdg/state \
       XDG_DATA_HOME=$R/xdg/data XDG_CACHE_HOME=$R/xdg/cache KURASHI_DATA_DIR=$ROOT LC_ALL=C.UTF-8 \
       DBUS_SYSTEM_BUS_ADDRESS=unix:path=$R/no-system-bus
mkdir -p "$XDG_CONFIG_HOME" "$XDG_STATE_HOME" "$XDG_DATA_HOME/kurashi/mods/hello" "$XDG_CACHE_HOME"
# The test mod as kurashid discovers it in its data dir: the checkout's qml with the live manifest (see live.mod.toml).
cp -r "$HELLO/qml" "$XDG_DATA_HOME/kurashi/mods/hello/"
cp "$HELLO/live.mod.toml" "$XDG_DATA_HOME/kurashi/mods/hello/mod.toml"

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

# Card geometry from a screenshot (PPM): the card's surface colour in the output's centre column.
cat > "$W/analyse.py" <<'PY'
import json, sys

SURFACE = (0x25, 0x23, 0x29)   # color.surface_container, the default palette (the daemon's theme says the same)
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

ppm_shot() {  # ppm_shot <name> <seconds>: waits, then takes the whole output as a PPM for the analysis
  sleep "$2"
  timeout 20 grim -o HEADLESS-1 -t ppm "$W/$1.ppm" || fail "grim failed on $1"
}
# card <name> <width>: the card is drawn at the width asked for, centred on the output; the crop is the evidence shot.
card() {
  local res x0 y0 x1 y1 cx cy
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
# bar <name>: the whole top bar (the Island's face and the mod's widget), as evidence.
bar() { timeout 20 grim -g "0,0 2560x36" "$OUT/$1.png" || fail "grim failed on $1"; }
shot() { timeout 20 grim -o HEADLESS-1 "$OUT/$1.png" || fail "grim failed on $1"; }

# island_face <face>: cycles the island's main face (island.next) until it shows <face> (a manual choice, as a user makes).
island_face() {
  local i
  for i in $(seq 12); do
    [ "$(ipc runtime.island.main | jq -r .face)" = "$1" ] && return 0
    K act island.next >/dev/null
    sleep 0.8
  done
  fail "the island does not show $1 (main face: $(ipc runtime.island.main | jq -r .face))"
}

# Log counts: the test mod's lines in this run's qs.log (one frontend per run).
mq() { grep -c -F "MODQML $1" "$R/qs.log" || true; }
expect() {  # expect <what> <label> <count>: exactly that many so far
  local got
  got=$(mq "$1")
  [ "$got" -eq "$3" ] || fail "$2: MODQML '$1' seen $got times, want $3"
  echo "log: $2 ($1 x$got)"
}
expect_min() {  # expect_min <what> <label> <count>: at least that many so far (a view or the bar may reload a component)
  local got
  got=$(mq "$1")
  [ "$got" -ge "$3" ] || fail "$2: MODQML '$1' seen $got times, want at least $3"
  echo "log: $2 ($1 x$got)"
}
# The frontend's QML warnings: any qml or scene WARN/ERROR (quickshell's socket and compositor notices are not QML),
# binding loops, reference and type errors.
qml_warnings() {
  grep -E '(WARN|ERROR)[^:]*(qml|scene)|Binding loop|ReferenceError|TypeError|is not a function|Unable to assign|Expected a qualified' "$R/qs.log" || true
}
no_qml_warnings() {  # no_qml_warnings <label>
  local w
  w=$(qml_warnings)
  if [ -n "$w" ]; then
    echo "$w" | head -20 >&2
    finding "$1: $(echo "$w" | wc -l) QML warning line(s) in qs.log"
    return 0
  fi
  echo "log: $1: no QML warnings"
}
# balanced: every component of the mod that was created was destroyed (after the last disable).
balanced() {
  local what c d
  for what in "widget" "face" "face-expanded" "panel" "slot clock.expanded.footer" "slot clock.expanded.aside" \
      "slot media.expanded.backdrop" "slot media.expanded.below" "slot notifications.expanded.header" "slot quick.tiles"; do
    c=$(mq "$what created")
    d=$(mq "$what destroyed")
    [ "$c" -eq "$d" ] || finding "'$what': $c created, $d destroyed after mod.disable"
  done
  echo "log: created and destroyed counts compared"
}
# Findings: the run goes on and reports them all at the end (see the last lines).
FINDINGS=()
finding() { echo "FINDING: $*" >&2; FINDINGS+=("$*"); }

start_frontend() {
  : > "$R/qs.log"
  # Without KURASHI_SOCKET: the frontend must find the socket by the protocol default, as in a live session.
  env -u KURASHI_SOCKET qs -p "$ROOT/frontend" >> "$R/qs.log" 2>&1 &
  pids+=("$!")
  sleep 3   # the bar's documents and the first frames
}
wait_socket() {  # wait_socket <what>: the daemon serves svc.clock
  for _ in $(seq 100); do [ -S "$KURASHI_SOCKET" ] && ipc svc.clock >/dev/null 2>&1 && return 0; sleep 0.1; done
  fail "$1 did not come up (see $R/server.log)"
}

# ---- The run: the real kurashid (test-mods) and the frontend.
: > "$R/server.log"
RUST_LOG=info "$W/kurashid" >> "$R/server.log" 2>&1 &
pids+=("$!")
wait_socket kurashid
start_frontend

# 1. mod off: nothing of the mod is listed or drawn.
ipc mods | jq -e '[.mods[] | select(.id == "hello") | has("qml")] == [false]' >/dev/null \
  || fail "mods: hello has a qml map while it is off"
ipc runtime.slots | jq -e '. == {}' >/dev/null || fail "runtime.slots lists something while hello is off"
K act island.expand >/dev/null
card clock-mod-off 400
K act ui.close >/dev/null
closed closed-mod-off
bar bar-mod-off
expect "" "mod off: no MODQML line" 0

# 2. mod.enable: the bar widget, and the clock card's footer and aside (both ready from the primary document).
K act mod.enable '{"id":"hello"}' >/dev/null
sleep 1.5
expect_min "widget created" "enabled: bar widget loaded" 1
ipc runtime.slots | jq -e '(."clock.expanded.footer" | length) == 1 and ."clock.expanded.footer"[0].ready == true
    and (."clock.expanded.aside" | length) == 1 and ."clock.expanded.aside"[0].ready == true' >/dev/null \
  || fail "runtime.slots does not list the ready footer and aside"
bar bar-widget
K act island.expand >/dev/null
card clock-slots 400
expect_min "slot clock.expanded.footer created" "enabled: footer in the clock card" 1
expect_min "slot clock.expanded.aside created" "enabled: aside in the clock card" 1

# 3. mod.panel.open: the panel replaces the clock card; its slots are destroyed (no stale component).
panel_open() {  # panel_open <panel>: mod.panel.open for hello, then the daemon's runtime.ui names it (polled, 4 s)
  local out=$(K act mod.panel.open '{"id":"hello","panel":"'"$1"'"}' 2>&1 || true)
  for _ in $(seq 20); do
    ipc runtime.ui | jq -e --arg p "mod:hello:$1" '.panel == $p' >/dev/null && return 0
    sleep 0.2
  done
  fail "runtime.ui does not name the mod panel (act answered: $out; runtime.ui: $(ipc runtime.ui | jq -c .))"
}
panel_open hello
card mod-panel 360
expect_min "panel created" "panel open: the hello panel loads" 1
expect_min "slot clock.expanded.footer destroyed" "panel open: the footer is gone" 1
expect_min "slot clock.expanded.aside destroyed" "panel open: the aside is gone" 1

# 4. ui.close: the panel is destroyed; nothing is drawn.
K act ui.close >/dev/null
sleep 1
closed closed-panel
expect_min "panel destroyed" "closed: the panel is destroyed" 1

# 5. the panel open, then mod.disable: the panel and the widget go; the card closes; no panel is named.
panel_open hello
sleep 1
expect_min "panel created" "panel open again" 2
K act mod.disable '{"id":"hello"}' >/dev/null
sleep 2
expect_min "panel destroyed" "disabled with the panel open: the panel is destroyed" 2
expect_min "widget destroyed" "disabled: the widget is destroyed" 1
# The daemon's runtime.ui still names the panel of the mod that went off (a value not in effect): recorded, and closed
# so that the run goes on.
if ! ipc runtime.ui | jq -e '(.panel // "") == ""' >/dev/null; then
  finding "step 5: runtime.ui still names the panel after mod.disable ($(ipc runtime.ui | jq -c '{panel,popup}'))"
  K act ui.close >/dev/null
  sleep 1
fi
closed closed-disabled
bar bar-widget-gone

# 6. the island face of the mod: raised by its test action (the island shows it), expanded, then cleared.
K act mod.enable '{"id":"hello"}' >/dev/null
sleep 1.5
expect_min "widget created" "re-enabled: the widget loads again" 2
K act hello.raise '{"relevance":90}' >/dev/null
sleep 2
[ "$(ipc runtime.island.main | jq -r .face)" = hello ] || fail "the island does not show the hello face after hello.raise"
expect_min "face created" "raised: the island draws the mod face" 1
bar bar-face-hello
K act island.expand >/dev/null
sleep 2
card face-expanded 360
expect_min "face-expanded created" "the expanded face loads in the card" 1
K act ui.close >/dev/null
sleep 1
closed closed-face
expect_min "face-expanded destroyed" "closed: the expanded face is destroyed" 1
K act hello.clear >/dev/null
sleep 2
expect_min "face destroyed" "cleared: the mod face is destroyed" 1
bar bar-face-fallback

# 7. media: the backdrop and the line under the transport, in the media face's card (the face is reached by island.next).
island_face media
K act island.expand >/dev/null
sleep 2
card media-slots 400
expect_min "slot media.expanded.backdrop created" "media card: the backdrop loads" 1
expect_min "slot media.expanded.below created" "media card: the line under the transport loads" 1
K act ui.close >/dev/null
sleep 1
closed closed-media

# 8. notifications: the header row in the notifications face's card (reached by island.next).
island_face notifications
K act island.expand >/dev/null
sleep 2
card notifications-header 360
expect_min "slot notifications.expanded.header created" "notifications: the header loads" 1
K act ui.close >/dev/null
sleep 1
closed closed-notifications

# 9. quick settings: the tile at the top of the quick card.
K act quick.toggle >/dev/null
sleep 2
card quick-tiles 360
expect_min "slot quick.tiles created" "quick settings: the tile loads" 1
K act ui.close >/dev/null
sleep 1
closed closed-quick

# 10. mod.disable with everything closed: every component the mod loaded is destroyed, and nothing is still listed.
island_face clock
K act mod.disable '{"id":"hello"}' >/dev/null
sleep 2
ipc mods | jq -e '[.mods[] | select(.id == "hello") | has("qml")] == [false]' >/dev/null \
  || fail "mods: hello still has a qml map after mod.disable"
balanced
no_qml_warnings "the run"
if [ "${#FINDINGS[@]}" -gt 0 ]; then
  printf 'finding: %s\n' "${FINDINGS[@]}" >&2
  fail "${#FINDINGS[@]} finding(s); screenshots in $OUT"
fi
echo "ok: screenshots in $OUT"
