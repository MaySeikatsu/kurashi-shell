#!/usr/bin/env bash
# The island card's expanded views and the quick settings card (K24), invisibly (headless sway sandbox).
# Against kurashi-mock (--fixed-time 12:34): for each face (clock, media, volume, brightness,
# notifications, power and bluetooth, and an unknown face for the generic card) `mock face <f>`, `act island.expand`, a
# screenshot, `act ui.close`; then `act quick.toggle`, a screenshot, a click on its heading (keyboard focus),
# Tab and Space on the Bluetooth switch (the mock's adapter goes off), `act ui.close`. Each open shot must
# have runtime.ui with the expected panel and face, and a card of the width its view asks for (400 for
# media, clock, quick, power and bluetooth; 360 otherwise), centred on the output. Each closed shot must have no card (Ma). The
# frontend logs no QML error.
#   nix develop -c frontend/test-stage.sh [sandbox-name]
# Binaries: kurashi from $KURASHI_BIN_DIR (default $CARGO_TARGET_DIR/debug or target/debug), the mock from
# $KURASHI_MOCK_BIN (default: kurashi-mock in the same dir). They are copied first, since shared target
# dirs get overwritten. The card crops in frontend/shots/stage/ are evidence to read, not just the exit
# code. On a hybrid laptop export KURASHI_RENDER_NODE first.
# W13 (docs/ux/island.md): after the cards above, the island's pill (the secondary glyph with "+2", the stale mark, the
# power and bluetooth faces, the peek while the pointer is on it) and the family views in the states the mock can make:
# the clock by keyboard (Tab to the grid, arrows move the day) and stale; the media view with a live stream (chosen by
# keyboard; no progress, transport reasons); the notifications view with do not disturb by keyboard and timed, and Clear
# all by keyboard to the empty state; the volume view muted. Shots: frontend/shots/island/ (read them, not just the exit code).
# Not reachable here: locked redaction (runtime.lock is fixed in the mock), Home and PageUp/PageDown (no key names in
# wl_keys.py), several-players progress with seek on a second track, and the other displays' reason (one output).
# W16 (B14, row 80), last: two outputs, and the quick card opens on the focused one. The mock marks only the focused
# output's workspace as focused (`mock.focus {output}` moves it), so the shell's focusedScreen() picks that output: the
# card is drawn there, not on the other. Shots: frontend/shots/stage/b14-quick-out*.png. The sandbox's network is
# probed again here (`sandbox.sh netcheck`): a connection from inside must fail (I58).
# W19 (docs/ux/island.md "Clock", COMPOSITION §3; before the two outputs): the clock's day marks of weather and hello, the
# weather aside with a reason (row 72), the grid in Japanese with the week starting on Sunday (auto), on Monday (config)
# and with ISO week numbers. Shots: frontend/shots/island/clock-*.png.
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

start_mock() {  # MOCK_LC: the locale the mock reads from its environment (kurashid's rule); this shell keeps its own
  rm -f "$KURASHI_SOCKET"
  RUST_LOG=info LC_ALL="${MOCK_LC:-$LC_ALL}" "$W/kurashi-mock" --outputs HEADLESS-1 --fixed-time 12:34 --socket "$KURASHI_SOCKET" \
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
# power and bluetooth open the quick card's Power and Bluetooth pages (I44) in the quick card's 400 px width (row 79).
for spec in clock:400 media:400 volume:360 brightness:360 notifications:360 power:400 bluetooth:400 weather:360; do
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
open_card quick quick "" 400
# Keyboard (docs/ux/quick-settings.md): a click on the card's inert left padding gives the Stage its keyboard focus;
# Tab five times reaches the Bluetooth tile (three status segments, then the Wi-Fi tile), Enter toggles it, so the mock's
# adapter goes off.
timeout 30 python3 -I "$ROOT/tools/bench/wl_pointer.py" click "$((card_x0 + 4))" "$((card_y0 + 140))" left \
  || fail "click on the quick card failed"
sleep 0.5
{ for _ in 1 2 3 4 5; do echo tab; sleep 0.3; done; echo return; sleep 0.5; } \
  | timeout 60 python3 -I "$ROOT/tools/bench/wl_keys.py" --serve || fail "keys failed"
sleep 1.5
bt=$(ipc svc.bluetooth) || fail "svc.bluetooth not served"
jq -e '.powered == false' <<<"$bt" >/dev/null \
  || fail "Tab x5, then Return on the Bluetooth tile, did not switch Bluetooth off (svc.bluetooth $bt)"
echo "keyboard: Tab x5 then Return toggled the Bluetooth tile: $bt"
K act ui.close >/dev/null
ppm_shot closed-quick 1.2
closed_card closed-quick

# ---- W13 island views (docs/ux/island.md). The pill first; then the views, each state drawn and read.
ISL=$ROOT/frontend/shots/island
mkdir -p "$ISL"
PTR=$ROOT/tools/bench/wl_pointer.py
KEYS_PY=$ROOT/tools/bench/wl_keys.py
# isl_shot <name>: the bar's centre strip (the pill and its secondary glyph, overflow, tail labels).
isl_shot() { timeout 20 grim -g "900,0 760x60" "$ISL/$1.png" || fail "grim failed on $1"; echo "shot island/$1"; }
# view_shot <name> <card width>: the card as it stands, centred on the output, with a margin round it.
view_shot() {
  local x=$((1280 - $2 / 2 - 24))
  timeout 20 grim -g "$x,24 $(( $2 + 48 ))x760" "$ISL/$1.png" || fail "grim failed on $1"
  echo "shot island/$1"
}
# heading_click <card x0> <card y0>: a click on the card's heading (no action) gives the Stage its keyboard focus.
heading_click() {
  timeout 30 python3 -I "$PTR" click "$(( $1 + 60 ))" "$(( $2 + 24 ))" left || fail "click on the card failed"
  sleep 0.5
}
# keys <key...>: presses the keys in order on one virtual keyboard.
keys() {
  { for k in "$@"; do echo "$k"; sleep 0.3; done; sleep 0.5; } | timeout 60 python3 -I "$KEYS_PY" --serve || fail "keys failed: $*"
}

# The pill: the secondary glyph and the overflow, then the peek while the pointer stays on the island (a held pointer:
# a one-shot move would leave at once and take the peek with it), the stale mark, the power and bluetooth faces.
K mock face clock >/dev/null
K act mock.island '{"secondary":"media","overflow":2,"stale_at":null,"detail":{"clock":"10:00 Standup"}}' >/dev/null
sleep 1
jq -e '.secondary == "media" and .overflow == 2' <<<"$(ipc runtime.island.main)" >/dev/null \
  || fail "the island has no secondary and overflow in effect"
isl_shot pill-secondary
{ echo "move 1280 16"; sleep 3; } | timeout 20 python3 -I "$PTR" --serve &
hover_pid=$!
sleep 1.2
# The peek is the Stage's now (K35), under the bar: a taller crop than the pill's.
timeout 20 grim -g "900,0 760x160" "$ISL/pill-peek.png" || fail "grim failed on pill-peek"; echo "shot island/pill-peek"
wait "$hover_pid" || true
K act mock.island "{\"secondary\":null,\"overflow\":0,\"stale_at\":{\"clock\":$(( $(date +%s) * 1000 - 3600000 ))}}" >/dev/null
sleep 1
isl_shot pill-stale
K act mock.island '{"stale_at":null}' >/dev/null
K mock face power >/dev/null
K act mock.island '{"detail":{"power":"On battery · 60 % · 1 h 15 min left"}}' >/dev/null
sleep 1
isl_shot pill-power
K mock face bluetooth >/dev/null
K act mock.island '{"detail":{"bluetooth":"Keyboard · 80 %"}}' >/dev/null
sleep 1
isl_shot pill-bluetooth
K mock face clock >/dev/null
K act mock.island '{"detail":{"clock":"10:00 Standup"}}' >/dev/null

# Clock: by keyboard (Tab x5 to the grid: the weather aside is the first stop; Right x3 and Down: Friday the 9th to Monday
# the 19th), then stale.
K act island.expand >/dev/null
ppm_shot clock-keys 2.5
open_card clock-keys island clock 400
heading_click "$card_x0" "$card_y0"
# The keyboard stays up for the shot: when it goes away the window loses its focus, and the ring with it.
{ for k in tab tab tab tab tab right right right down; do echo "$k"; sleep 0.3; done; sleep 2.5; } \
  | timeout 60 python3 -I "$KEYS_PY" --serve &
keys_pid=$!
sleep 3.2
view_shot clock-keys-moved 400
wait "$keys_pid" || fail "keys failed on the clock grid"
K act ui.close >/dev/null
ppm_shot closed-clock-keys 1.2
closed_card closed-clock-keys
K act mock.island "{\"stale_at\":{\"clock\":$(( $(date +%s) * 1000 - 3600000 ))}}" >/dev/null
K act island.expand >/dev/null
sleep 2.5
view_shot clock-stale 400
K act ui.close >/dev/null
K act mock.island '{"stale_at":null}' >/dev/null
sleep 1.2

# Media: a live stream chosen by keyboard (Tab x2 to the second player, Space): no progress, the transport reasons;
# then the track is chosen back by its action.
K mock face media >/dev/null
K act island.expand >/dev/null
ppm_shot media-live 2.5
open_card media-live island media 400
heading_click "$card_x0" "$card_y0"
keys tab tab space
sleep 1.5
jq -e '[.players[] | select(.active == true)][0].name == "Firefox"' <<<"$(ipc svc.media)" >/dev/null \
  || fail "Space on the second player did not select Firefox"
view_shot media-live 400
K act media.player.select '{"id":"org.mpris.MediaPlayer2.mpv"}' >/dev/null
sleep 1
K act ui.close >/dev/null
sleep 1.2

# Notifications: do not disturb by keyboard (Tab x2 to the switch, Space: on, until turned off), then timed to 14:30,
# then Clear all by keyboard (Tab, Return) to the empty state.
K act notify.dnd '{"on":false}' >/dev/null
K mock face notifications >/dev/null
K act island.expand >/dev/null
ppm_shot notif-keys 2.5
open_card notif-keys island notifications 360
heading_click "$card_x0" "$card_y0"
keys tab tab space
sleep 1
jq -e '.dnd == true and (.dnd_until == null)' <<<"$(ipc svc.notifications)" >/dev/null \
  || fail "Space on the do-not-disturb switch did not turn it on"
view_shot notif-dnd-on 360
K act notify.dnd "{\"on\":true,\"until\":$(date -d '2026-10-09 14:30' +%s%3N)}" >/dev/null
sleep 1
view_shot notif-dnd-until 360
K act ui.close >/dev/null
sleep 1.2
# Reopened, the focus starts on the card again: Tab reaches Clear all first, Return presses it.
K act island.expand >/dev/null
ppm_shot notif-clear 2.5
open_card notif-clear island notifications 360
heading_click "$card_x0" "$card_y0"
keys tab return
sleep 1
jq -e '(.items | length) == 0' <<<"$(ipc svc.notifications)" >/dev/null \
  || fail "Return on Clear all did not clear the notifications"
view_shot notif-empty 360
K act notify.dnd '{"on":false}' >/dev/null
K act ui.close >/dev/null
sleep 1.2

# Volume: muted (the level is shown as muted, not as a stale number).
K mock face volume >/dev/null
K act island.expand >/dev/null
ppm_shot volume-muted 2.5
open_card volume-muted island volume 360
K act audio.mute.toggle >/dev/null
sleep 1
view_shot volume-muted 360
K act audio.mute.toggle >/dev/null
K act ui.close >/dev/null
sleep 1.2

# ---- W19 calendar (docs/ux/island.md "Clock", docs/ux/weather.md "Clock view integration", COMPOSITION §3): the day marks of
# weather and hello (row 71), the weather aside with a reason (row 72), then Japanese: the weeks start on Sunday (auto),
# on Monday (config) and show the week numbers (I46). Shots: frontend/shots/island/clock-*.png (read them, not just the code).
# clock_card <name> <card width>: the clock view is open at that width and centred; sets card_x0..card_y1 (the check that
# open_card makes, without its shot in frontend/shots/stage/).
clock_card() {
  local res
  ppm_shot "$1" 2.5
  res=$(analyse "$1") || fail "$1: analysis failed"
  jq -e '.panel == "island" and .face == "clock"' <<<"$(ipc runtime.ui)" >/dev/null \
    || fail "$1: the clock view is not open ($(ipc runtime.ui))"
  echo "$1: $res"
  jq -e --argjson w "$2" '.surface >= 15000 and .bbox != null
      and (((.bbox[2] - .bbox[0] + 1) - ($w - 2)) | fabs) <= 4
      and (((.bbox[0] + .bbox[2]) / 2 - 1280) | fabs) <= 4' <<<"$res" >/dev/null \
    || fail "$1: no card of width $2 centred on the output ($res)"
  read -r card_x0 card_y0 card_x1 card_y1 < <(jq -r '.bbox | "\(.[0]) \(.[1]) \(.[2]) \(.[3])"' <<<"$res")
}
# start_frontend_again: the frontend after a restart of the mock; the hello line it waits for is a new one.
start_frontend_again() {
  local before
  before=$(grep -c 'hello.*frontend' "$R/server.log" || true)
  env -u KURASHI_SOCKET qs -p "$ROOT/frontend" >> "$R/qs.log" 2>&1 &
  pids+=("$!")
  for _ in $(seq 100); do [ "$(grep -c 'hello.*frontend' "$R/server.log" || true)" -gt "$before" ] && break; sleep 0.1; done
  [ "$(grep -c 'hello.*frontend' "$R/server.log" || true)" -gt "$before" ] || fail "frontend never said hello (see $R/qs.log)"
  sleep 3
}

K mock face clock >/dev/null
K act island.expand >/dev/null
# (a) The day marks: weather's forecast glyphs for 9 to 15 October, and hello's dot on the 14th beside them.
clock_card clock-marks 400
view_shot clock-marks 400
# (b) The aside with a reason (row 72): no place saved. The aside says "No place set" and offers "Set place", in its box.
cur=$(ipc runtime.slots) || fail "runtime.slots not served"
K act mock.doc "$(jq -nc --argjson s "$cur" '{doc: "runtime.slots", patch: {"clock.expanded.aside": ($s["clock.expanded.aside"] | map(. + {reason: "mod-weather.no_location"}))}}')" >/dev/null \
  || fail "mock.doc refused the aside's reason"
sleep 1.5
jq -e '.["clock.expanded.aside"][0].reason == "mod-weather.no_location"' <<<"$(ipc runtime.slots)" >/dev/null \
  || fail "the aside's reason is not in runtime.slots"
clock_card clock-aside-reason 400
view_shot clock-aside-reason 400
K act mock.doc "$(jq -nc --argjson s "$cur" '{doc: "runtime.slots", patch: {"clock.expanded.aside": $s["clock.expanded.aside"]}}')" >/dev/null \
  || fail "mock.doc refused the aside without its reason"
sleep 1.5
# (c) Japanese: the mock and the frontend restart with ja_JP.UTF-8 (kurashid reads the locale from the environment). The
# weeks start on Sunday by auto; then on Monday by config; then with week numbers by config.
K act ui.close >/dev/null
stop_phase
MOCK_LC=ja_JP.UTF-8 start_mock
start_frontend_again
[ "$(ipc i18n | jq -r .locale)" = ja ] || fail "the frontend's locale is not ja"
K mock face clock >/dev/null
K act island.expand >/dev/null
clock_card clock-ja-sunday 400
view_shot clock-ja-sunday 400
# The keys on the Japanese grid: Tab x5 to the grid, Right x2 and Down: Friday the 9th to Sunday the 18th, the first column.
heading_click "$card_x0" "$card_y0"
{ for k in tab tab tab tab tab right right down; do echo "$k"; sleep 0.3; done; sleep 2.5; } \
  | timeout 60 python3 -I "$KEYS_PY" --serve &
keys_pid=$!
sleep 3.5
view_shot clock-ja-sunday-keys 400
wait "$keys_pid" || fail "keys failed on the Japanese grid"
# Monday by config: the 18th sits in the last column now, and the grid follows.
K act mock.doc '{"doc":"config","patch":{"values":{"clock.week_start":{"value":"monday"}}}}' >/dev/null \
  || fail "mock.doc refused the week start"
sleep 1.5
clock_card clock-ja-monday 400
view_shot clock-ja-monday 400
# Week numbers by config: one ISO number beside each row.
K act mock.doc '{"doc":"config","patch":{"values":{"clock.week_numbers":{"value":true}}}}' >/dev/null \
  || fail "mock.doc refused the week numbers"
sleep 1.5
clock_card clock-ja-monday-weeks 400
view_shot clock-ja-monday-weeks 400
K act ui.close >/dev/null
stop_phase

# ---- W16, B14 (row 80): two outputs. The mock and the frontend restart with HEADLESS-2 in the list; the outputs are
# sway's, so the card's pixels come from `grim -o` of each.
# holder: the outputs whose workspace list holds the focus, as the shell reads it (`focusedScreen()`), comma-separated.
holder() { jq -r '[.outputs | to_entries[] | select(.key != "*") | select(.value | any(.focused)) | .key] | join(",")' <<<"$(ipc svc.workspaces)"; }
# focus_on <output>: mock.focus, then the document holds the focus on that output alone.
focus_on() {
  K act mock.focus "{\"output\":\"$1\"}" >/dev/null || fail "mock.focus $1 was refused"
  for _ in $(seq 25); do [ "$(holder)" = "$1" ] && return 0; sleep 0.2; done
  fail "svc.workspaces holds the focus on '$(holder)', not on $1"
}
# card_on <output> <name>: the quick card (400 px, centred) is drawn on that output; its crop is the evidence shot.
card_on() {
  local res x0 y0 x1 y1 off
  timeout 20 grim -o "$1" -t ppm "$W/$2.ppm" || fail "grim failed on $1"
  res=$(analyse "$2") || fail "$2: analysis failed"
  echo "$2 on $1: $res"
  jq -e '.surface >= 15000 and .bbox != null and (((.bbox[2] - .bbox[0] + 1) - 398) | fabs) <= 4
      and (((.bbox[0] + .bbox[2]) / 2 - 1280) | fabs) <= 4' <<<"$res" >/dev/null \
    || fail "$2: no quick card of width 400 centred on $1 ($res)"
  read -r x0 y0 x1 y1 < <(jq -r '.bbox | "\(.[0]) \(.[1]) \(.[2]) \(.[3])"' <<<"$res")
  off=$(timeout 10 swaymsg -t get_outputs -r | jq -r --arg o "$1" '.[] | select(.name == $o) | .rect.x')
  timeout 20 grim -g "$((off + x0 - 24)),$((y0 - 24)) $((x1 - x0 + 49))x$((y1 - y0 + 49))" "$OUT/$2.png" \
    || fail "grim failed on $2"
}
# none_on <output> <name>: no card is drawn on that output.
none_on() {
  local res
  timeout 20 grim -o "$1" -t ppm "$W/$2.ppm" || fail "grim failed on $1"
  res=$(analyse "$2") || fail "$2: analysis failed"
  jq -e '.surface < 500' <<<"$res" >/dev/null || fail "$2: a card is drawn on $1 ($res)"
}

# The sandbox's network: a connection from inside it must fail (I58), logged with this step.
"$ROOT/tools/bench/sandbox.sh" netcheck "$NAME" || fail "the sandbox reaches a network"

stop_phase
"$ROOT/tools/bench/sandbox.sh" output-add "$NAME" >/dev/null || fail "output-add failed"
for _ in $(seq 50); do
  [ "$(timeout 10 swaymsg -t get_outputs -r | jq '[.[] | select(.active)] | length')" -ge 2 ] && break
  sleep 0.2
done
[ "$(timeout 10 swaymsg -t get_outputs -r | jq '[.[] | select(.active)] | length')" -ge 2 ] || fail "sway has no second output"
rm -f "$KURASHI_SOCKET"
RUST_LOG=info "$W/kurashi-mock" --outputs HEADLESS-1,HEADLESS-2 --fixed-time 12:34 --socket "$KURASHI_SOCKET" \
  >> "$R/server.log" 2>&1 &
pids+=("$!")
for _ in $(seq 100); do [ -S "$KURASHI_SOCKET" ] && ipc svc.clock >/dev/null 2>&1 && break; sleep 0.1; done
ipc svc.clock >/dev/null 2>&1 || fail "mock did not come up with two outputs (see $R/server.log)"
before=$(grep -c 'hello.*frontend' "$R/server.log" || true)
env -u KURASHI_SOCKET qs -p "$ROOT/frontend" >> "$R/qs.log" 2>&1 &
pids+=("$!")
for _ in $(seq 100); do [ "$(grep -c 'hello.*frontend' "$R/server.log" || true)" -gt "$before" ] && break; sleep 0.1; done
[ "$(grep -c 'hello.*frontend' "$R/server.log" || true)" -gt "$before" ] || fail "frontend never said hello (see $R/qs.log)"
sleep 3

focus_on HEADLESS-2
K act quick.toggle >/dev/null
sleep 2.5
jq -e '.panel == "quick"' <<<"$(ipc runtime.ui)" >/dev/null || fail "quick.toggle did not open the quick card"
card_on HEADLESS-2 b14-quick-out2
none_on HEADLESS-1 b14-quick-out2-other
K act quick.toggle >/dev/null
sleep 1.2
none_on HEADLESS-2 b14-closed-out2

focus_on HEADLESS-1
K act quick.toggle >/dev/null
sleep 2.5
jq -e '.panel == "quick"' <<<"$(ipc runtime.ui)" >/dev/null || fail "quick.toggle did not open the quick card on the first output"
card_on HEADLESS-1 b14-quick-out1
none_on HEADLESS-2 b14-quick-out1-other
K act ui.close >/dev/null
sleep 1.2
none_on HEADLESS-1 b14-closed-out1

stop_phase
if grep -q "ERROR\|TypeError\|ReferenceError\|Unable to assign\|is not defined\|is not a type\|Cannot assign\|Cannot anchor\|Binding loop" "$R/qs.log"; then
  echo "qs.log has errors:" >&2
  grep "ERROR\|TypeError\|ReferenceError\|Unable to assign\|is not defined\|is not a type\|Cannot assign\|Cannot anchor\|Binding loop" "$R/qs.log" | head >&2
  exit 1
fi
echo "ok: card crops in $OUT"
