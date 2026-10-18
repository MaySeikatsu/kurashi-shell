#!/usr/bin/env bash
# The bar's hover peeks (K35, I55), drawn by the Stage, invisibly (headless sway sandbox): the tray tooltip (B9), the
# weather (B22), the island's line (I47) and sysmon's facts (docs/ux/sysmon.md). Four phases, each with a fresh frontend:
#   kurashi-mock, one output    tray tooltips (hover; the frame is clamped at the right edge), the island's line (hover,
#                               held while the pointer is on it, gone after it leaves), no peek while a card is open;
#   kurashid (real), one output sysmon and weather on the top bar (a localhost weather fixture, KURASHI_WEATHER_API), the
#                               island's line from a notification on the top bar, then the bar on the bottom edge:
#                               sysmon and the island again;
#   kurashi-mock, two outputs   a tray peek on HEADLESS-2 lands there (the Stage retargets); the next card opens on
#                               HEADLESS-1 (the Stage hands its output back);
#   measurement                 PSS of the frontend and Wayland commits (WAYLAND_DEBUG) per window: idle, a peek held, the
#                               fade in, a retarget, and 20 hover cycles (on output 1, and 20 retarget cycles on output 2).
# A peek is found by what changed against a baseline screenshot taken with nothing shown (so no colour is assumed), and by
# runtime.ui.peek (the source and output asked for). No QML error in qs.log. Screenshots: frontend/shots/peek/ (read them).
#   KURASHI_RENDER_NODE=/dev/dri/renderD129 KURASHI_BIN_DIR=<dir with kurashid, kurashi, kurashi-mock> \
#     timeout 900 nix develop -c frontend/test-peek.sh [sandbox-name]
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
NAME=${1:-fe-peek}
BIN=${KURASHI_BIN_DIR:-${CARGO_TARGET_DIR:-$ROOT/target}/debug}
OUT=$ROOT/frontend/shots/peek
FX=$ROOT/crates/kurashi-mod-weather/tests/fixtures
mkdir -p "$OUT"
fail() { echo "test-peek: $*" >&2; exit 1; }

eval "$("$ROOT/tools/bench/sandbox.sh" start "$NAME")"
R=$XDG_RUNTIME_DIR
W=$R/work
FIFO=$R/pointer.fifo
mkdir -p "$W" "$R/kurashi" "$R/weather/v1"
cp "$BIN/kurashi" "$BIN/kurashid" "$BIN/kurashi-mock" "$W/"
cp "$FX/forecast_tokyo.json" "$R/weather/v1/forecast"
cp "$FX/geocode_tokyo_ja.json" "$R/weather/v1/search"
# Hermetic daemon and frontend: isolated XDG dirs, no system bus (the sandbox's own session bus only).
export XDG_CONFIG_HOME=$R/xdg/config XDG_STATE_HOME=$R/xdg/state XDG_DATA_HOME=$R/xdg/data XDG_CACHE_HOME=$R/xdg/cache \
       KURASHI_DATA_DIR=$ROOT LC_ALL=C.UTF-8
mkdir -p "$XDG_CONFIG_HOME" "$XDG_STATE_HOME" "$XDG_DATA_HOME" "$XDG_CACHE_HOME"

# `ipc.py <doc>` prints the first snapshot's data of a document (stdlib only, as in test-stage.sh).
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
# `diff.py <a.ppm> <b.ppm> x0 y0 x1 y1`: pixels of the rectangle (x1, y1 exclusive) that differ from the baseline by more
# than 24 in some channel. A peek or a card is many hundreds of such pixels; nothing else moves in these rectangles.
cat > "$W/diff.py" <<'PY'
import sys


def read(path):
    with open(path, "rb") as f:
        data = f.read()
    toks, i = [], 0
    while len(toks) < 4:
        while data[i:i + 1].isspace():
            i += 1
        j = i
        while not data[j:j + 1].isspace():
            j += 1
        toks.append(data[i:j])
        i = j
    return int(toks[1]), data[i + 1:]


aw, a = read(sys.argv[1])
bw, b = read(sys.argv[2])
x0, y0, x1, y1 = map(int, sys.argv[3:7])
n = 0
for y in range(y0, y1):
    s, e = (y * aw + x0) * 3, (y * aw + x1) * 3
    ra, rb = a[s:e], b[s:e]
    for k in range(0, len(ra), 3):
        if abs(ra[k] - rb[k]) > 24 or abs(ra[k + 1] - rb[k + 1]) > 24 or abs(ra[k + 2] - rb[k + 2]) > 24:
            n += 1
print(n)
PY
ipc() { timeout 10 python3 -I "$W/ipc.py" "$@"; }
K() { timeout 10 "$W/kurashi" "$@"; }
peek_src() { ipc runtime.ui | python3 -c 'import json,sys; d=json.load(sys.stdin) or {}; p=d.get("peek"); print(p["source"] if p else "")'; }
peek_out() { ipc runtime.ui | python3 -c 'import json,sys; d=json.load(sys.stdin) or {}; p=d.get("peek"); print(p["output"] if p else "")'; }
changed() { timeout 30 python3 -I "$W/diff.py" "$@"; }   # changed <ppm> <baseline ppm> x0 y0 x1 y1
drawn() { [ "$(changed "$@")" -gt 1500 ] && echo 1 || echo 0; }
undrawn() { [ "$(changed "$@")" -lt 300 ] && echo 1 || echo 0; }
# grab <name> <output>: a baseline or a capture as a PPM (for the change checks only)
grab() { timeout 20 grim -o "$2" -t ppm "$W/$1.ppm" || fail "grim failed on $1"; }
# shot <name> <output>: the PNG for the record and the PPM for the checks
shot() { timeout 20 grim -o "$2" "$OUT/$1.png" || fail "grim failed on $1"; grab "$1" "$2"; }
FAILS=0
check() { # check <0|1> <label>
  if [ "$1" = 1 ]; then echo "ok: $2"; else echo "FAIL: $2"; FAILS=$((FAILS + 1)); fi
}

pids=()
QS_PID=""
stop_phase() {
  exec 3>&- 2>/dev/null || true
  for p in ${pids[@]+"${pids[@]}"}; do kill "$p" 2>/dev/null || true; done
  for p in ${pids[@]+"${pids[@]}"}; do wait "$p" 2>/dev/null || true; done
  pids=()
  rm -f "$KURASHI_SOCKET" "$FIFO"
}
cleanup() {
  stop_phase
  "$ROOT/tools/bench/sandbox.sh" stop "$NAME" >/dev/null || true
}
trap cleanup EXIT

start_mock() { # the mock serves the socket; its first output is HEADLESS-1
  rm -f "$KURASHI_SOCKET"
  "$W/kurashi-mock" --outputs HEADLESS-1 --fixed-time 12:34 --socket "$KURASHI_SOCKET" >> "$R/server.log" 2>&1 &
  pids+=("$!")
  for _ in $(seq 100); do [ -S "$KURASHI_SOCKET" ] && ipc svc.clock >/dev/null 2>&1 && return 0; sleep 0.1; done
  fail "mock did not come up (see $R/server.log)"
}
start_real() { # the real daemon: the weather fixture server, then kurashid with the fixture as its weather API
  rm -f "$KURASHI_SOCKET"
  python3 -I -m http.server 8099 --bind 127.0.0.1 --directory "$R/weather" > "$R/fixture.log" 2>&1 &
  pids+=("$!")
  KURASHI_WEATHER_API=http://127.0.0.1:8099 DBUS_SYSTEM_BUS_ADDRESS="unix:path=$R/no-system-bus" "$W/kurashid" \
    >> "$R/kurashid.log" 2>&1 &
  pids+=("$!")
  for _ in $(seq 100); do [ -S "$KURASHI_SOCKET" ] && K ping >/dev/null 2>&1 && return 0; sleep 0.1; done
  fail "kurashid did not come up (see $R/kurashid.log)"
}
start_frontend() { # $1: extra environment for qs (WAYLAND_DEBUG=1 in the measurement only)
  env -u KURASHI_SOCKET ${1:-} qs -p "$ROOT/frontend" >> "$R/qs.log" 2>&1 &
  QS_PID=$!
  pids+=("$QS_PID")
  sleep 4
}
# One virtual pointer per phase, started after the outputs it may point at exist (its layout is fixed at start).
start_pointer() {
  rm -f "$FIFO"
  mkfifo "$FIFO"
  timeout 900 python3 -I "$ROOT/tools/bench/wl_pointer.py" --serve < "$FIFO" > "$R/pointer.log" 2>&1 &
  pids+=("$!")
  exec 3> "$FIFO"
  sleep 1
}
move() { echo "move $1 $2" >&3; }
qs_errors() {
  local bad
  bad=$(grep -i "typeerror\|referenceerror\|not a type\|binding loop\|unable to assign\|is not defined\|cannot assign" "$R/qs.log" \
    | grep -v "portal\|background effect" || true)
  if [ -n "$bad" ]; then
    echo "$bad" | head -5
    check 0 "qs.log has no QML error"
  else
    check 1 "qs.log has no QML error"
  fi
}
two_outputs() { # adds HEADLESS-2 to this sandbox's sway session, once
  if [ "$(timeout 10 swaymsg -t get_outputs | python3 -c 'import json,sys; print(len(json.load(sys.stdin)))')" -lt 2 ]; then
    timeout 20 "$ROOT/tools/bench/sandbox.sh" output-add "$NAME" >/dev/null || fail "output-add failed"
    sleep 3
  fi
}
output_x() { timeout 10 swaymsg -t get_outputs | python3 -c "import json,sys; print([o['rect']['x'] for o in json.load(sys.stdin) if o['name']=='$1'][0])"; }

# ---- phase 1: kurashi-mock, one output: tray tooltips and the island's line
phase_mock_one() {
  echo "== phase 1: mock, one output"
  : > "$R/server.log"; : > "$R/qs.log"
  start_mock
  start_frontend
  start_pointer
  K mock face clock >/dev/null
  K act mock.island '{"detail":{"clock":"14:00 Standup"}}' >/dev/null
  sleep 1
  grab base-m1 HEADLESS-1
  move 2482 17; sleep 0.9
  check "$([ "$(peek_src)" = "tray::1.42/StatusNotifierItem" ] && echo 1 || echo 0)" "the tray item asks for its tooltip peek"
  shot tray-tooltip HEADLESS-1
  check "$(drawn "$W/tray-tooltip.ppm" "$W/base-m1.ppm" 2380 40 2560 200)" "the tooltip's frame is drawn at the right edge (clamped inside the output)"
  move 1280 17; sleep 0.9
  check "$([ "$(peek_src)" = "island:main" ] && echo 1 || echo 0)" "the island asks for its line on hover"
  shot island-peek-top HEADLESS-1
  check "$(drawn "$W/island-peek-top.ppm" "$W/base-m1.ppm" 1100 40 1460 200)" "the island's peek is drawn under the top bar"
  move 1280 60; sleep 0.8
  check "$([ "$(peek_src)" = "island:main" ] && echo 1 || echo 0)" "the peek holds while the pointer is on it"
  move 1280 600; sleep 0.9
  check "$([ -z "$(peek_src)" ] && echo 1 || echo 0)" "the peek goes once the pointer has left it and the grace has passed"
  K act island.expand >/dev/null
  sleep 1.2
  move 1280 17; sleep 0.9
  check "$([ -z "$(peek_src)" ] && echo 1 || echo 0)" "no peek is asked for while a card is open"
  shot no-peek-card-open HEADLESS-1
  K act ui.close >/dev/null
  sleep 0.5
  qs_errors
  stop_phase
}

# ---- phase 2: the real kurashid, one output, then the bottom edge
phase_real() {
  echo "== phase 2: kurashid, sysmon and weather, the island's line, the bottom edge"
  : > "$R/kurashid.log"; : > "$R/qs.log"
  start_real
  start_frontend
  start_pointer
  K act mod.enable '{"id":"sysmon"}' >/dev/null || fail "mod.enable sysmon failed"
  K act mod.enable '{"id":"weather"}' >/dev/null || fail "mod.enable weather failed"
  K act weather.place.add '{"place":{"id":"1850147","name":"Tokyo","country_code":"JP","lat":35.6895,"lon":139.69171,"tz":"Asia/Tokyo"}}' >/dev/null \
    || fail "weather.place.add failed"
  sleep 4
  # The widgets' x: the sweep moves the pointer in steps, and a peek asks after 300 ms on each widget it rests on.
  sx=""; wx=""
  for x in $(seq 1800 20 2480); do
    move "$x" 17; sleep 0.55
    case "$(peek_src)" in
      mod:sysmon:sysmon) [ -n "$sx" ] || sx=$x ;;
      mod:weather:weather) [ -n "$wx" ] || wx=$x ;;
    esac
    [ -n "$sx" ] && [ -n "$wx" ] && break
  done
  [ -n "$sx" ] || fail "no sysmon widget found on the top bar"
  [ -n "$wx" ] || fail "no weather widget found on the top bar"
  move 1280 600; sleep 1
  grab base-r-top HEADLESS-1
  move "$((sx + 30))" 17; sleep 0.9
  check "$([ "$(peek_src)" = "mod:sysmon:sysmon" ] && echo 1 || echo 0)" "sysmon asks for its peek on hover (mod:sysmon:sysmon)"
  shot sysmon-peek-top HEADLESS-1
  check "$(drawn "$W/sysmon-peek-top.ppm" "$W/base-r-top.ppm" "$((sx - 4))" 40 "$((sx + 200))" 200)" \
    "the sysmon peek is drawn under the top bar at its widget"
  move "$((wx + 20))" 17; sleep 0.9
  check "$([ "$(peek_src)" = "mod:weather:weather" ] && echo 1 || echo 0)" "weather asks for its peek on hover (mod:weather:weather)"
  shot weather-peek-top HEADLESS-1
  check "$(drawn "$W/weather-peek-top.ppm" "$W/base-r-top.ppm" "$((wx - 4))" 40 2560 200)" \
    "the weather peek is drawn under the top bar at its widget (clamped at the right edge)"
  move 1280 600; sleep 0.9
  # The island's line: a notification is the island's notifications face, and its line is the summary.
  notify-send -t 20000 "Standup" "14:00 room 3" >/dev/null 2>&1 || fail "notify-send failed"
  sleep 2
  move 1280 600; sleep 0.5
  grab base-r-top2 HEADLESS-1
  move 1280 17; sleep 0.9
  check "$([ "$(peek_src)" = "island:main" ] && echo 1 || echo 0)" "the island asks for its line on the top bar"
  shot island-peek-real-top HEADLESS-1
  check "$(drawn "$W/island-peek-real-top.ppm" "$W/base-r-top2.ppm" 1100 40 1460 200)" \
    "the island's peek is drawn under the top bar (real daemon)"
  move 1280 600; sleep 0.9
  K set bar.edge bottom >/dev/null
  sleep 3
  move 1280 600; sleep 0.5
  grab base-r-bottom HEADLESS-1
  move "$((sx + 30))" 1423; sleep 0.9
  check "$([ "$(peek_src)" = "mod:sysmon:sysmon" ] && echo 1 || echo 0)" "sysmon asks for its peek on the bottom bar"
  shot sysmon-peek-bottom HEADLESS-1
  check "$(drawn "$W/sysmon-peek-bottom.ppm" "$W/base-r-bottom.ppm" "$((sx - 4))" 1100 "$((sx + 200))" 1395)" \
    "the sysmon peek is drawn above the bottom bar"
  move 1280 1423; sleep 0.9
  check "$([ "$(peek_src)" = "island:main" ] && echo 1 || echo 0)" "the island asks for its line on the bottom bar"
  shot island-peek-bottom HEADLESS-1
  check "$(drawn "$W/island-peek-bottom.ppm" "$W/base-r-bottom.ppm" 1100 1100 1460 1395)" \
    "the island's peek is drawn above the bottom bar"
  move 1280 600; sleep 0.9
  K act island.expand >/dev/null
  sleep 1.2
  move "$((sx + 30))" 1423; sleep 0.9
  check "$([ -z "$(peek_src)" ] && echo 1 || echo 0)" "no peek is asked for on the bottom bar while a card is open"
  K act ui.close >/dev/null
  K set bar.edge top >/dev/null
  sleep 1
  qs_errors
  stop_phase
}

# ---- phase 3: kurashi-mock, two outputs: the Stage retargets to the peek's output and gives its output back
phase_two_outputs() {
  echo "== phase 3: mock, two outputs"
  : > "$R/server.log"; : > "$R/qs.log"
  start_mock
  start_frontend
  two_outputs
  start_pointer
  X2=$(output_x HEADLESS-2)
  move 1280 600; sleep 1
  grab base-o1 HEADLESS-1
  grab base-o2 HEADLESS-2
  move "$((X2 + 2482))" 17; sleep 0.9
  check "$([ "$(peek_out)" = "HEADLESS-2" ] && echo 1 || echo 0)" "the tray peek is asked on HEADLESS-2"
  shot tray-tooltip-output2 HEADLESS-2
  check "$(drawn "$W/tray-tooltip-output2.ppm" "$W/base-o2.ppm" 2380 40 2560 200)" "the peek is drawn on HEADLESS-2"
  shot tray-tooltip-output1-empty HEADLESS-1
  check "$(undrawn "$W/tray-tooltip-output1-empty.ppm" "$W/base-o1.ppm" 2380 40 2560 200)" "HEADLESS-1 shows no peek"
  move 1280 600; sleep 0.9
  check "$([ -z "$(peek_src)" ] && echo 1 || echo 0)" "the peek goes when the pointer leaves"
  K act island.expand >/dev/null
  sleep 1.2
  shot card-output1 HEADLESS-1
  shot card-output2-empty HEADLESS-2
  check "$([ "$(changed "$W/card-output1.ppm" "$W/base-o1.ppm" 1100 40 1460 200)" -gt 5000 ] && echo 1 || echo 0)" \
    "the next card opens on the focused output, HEADLESS-1 (the Stage handed its output back)"
  check "$([ "$(changed "$W/card-output2-empty.ppm" "$W/base-o2.ppm" 1100 40 1460 200)" -lt 500 ] && echo 1 || echo 0)" \
    "the card is not drawn on HEADLESS-2"
  K act ui.close >/dev/null
  sleep 0.5
  qs_errors
  stop_phase
}

# ---- phase 4: measurement (PSS of the frontend, Wayland commits from WAYLAND_DEBUG): printed; the growth is checked
pss_mib() { awk '/^Pss:/{s+=$2} END{printf "%.2f", s/1024}' "/proc/$1/smaps_rollup"; }
size() { stat -c %s "$R/qs.log"; }
commits() { # commits <start byte>: Wayland surface commits (both bars and the Stage) logged since that offset
  tail -c +"$(( $1 + 1 ))" "$R/qs.log" | grep -c 'wl_surface#[0-9]*\.commit(' || true
}
phase_measure() {
  echo "== phase 4: measurement (two outputs)"
  : > "$R/server.log"; : > "$R/qs.log"
  start_mock
  start_frontend "WAYLAND_DEBUG=1"
  two_outputs
  start_pointer
  X2=$(output_x HEADLESS-2)
  move 1280 600
  sleep 6
  s=$(size); sleep 10; idle_c=$(commits "$s"); idle_pss=$(pss_mib "$QS_PID")
  echo "measure idle, no peek (10 s): commits=$idle_c pss=${idle_pss} MiB"
  s=$(size); move 2482 17; sleep 0.9; fade_c=$(commits "$s")
  s=$(size); sleep 5; held_c=$(commits "$s"); shown_pss=$(pss_mib "$QS_PID")
  echo "measure peek on HEADLESS-1: fade-in (0.9 s) commits=$fade_c, held (5 s) commits=$held_c pss=${shown_pss} MiB"
  s=$(size); move 1280 600; sleep 0.9; move "$((X2 + 2482))" 17; sleep 0.9; retarget_c=$(commits "$s")
  s=$(size); sleep 5; out2_c=$(commits "$s"); out2_pss=$(pss_mib "$QS_PID")
  echo "measure peek on HEADLESS-2: retarget (1.8 s) commits=$retarget_c, held (5 s) commits=$out2_c pss=${out2_pss} MiB"
  move 1280 600; sleep 1
  # Warm-up, as bench's cycle test: the first peeks allocate their caches once; the measured window is after them.
  for _ in $(seq 20); do move 2482 17; sleep 0.6; move 1280 600; sleep 0.6; done
  sleep 2
  pss0=$(pss_mib "$QS_PID"); s=$(size)
  for _ in $(seq 20); do move 2482 17; sleep 0.6; move 1280 600; sleep 0.6; done
  cyc_c=$(commits "$s"); pss1=$(pss_mib "$QS_PID")
  echo "measure 20 hover cycles on HEADLESS-1: commits=$cyc_c ($(( cyc_c / 20 )) per cycle), pss ${pss0} -> ${pss1} MiB"
  for _ in $(seq 20); do move "$((X2 + 2482))" 17; sleep 0.6; move 1280 600; sleep 0.6; done
  sleep 2
  pss2=$(pss_mib "$QS_PID"); s=$(size)
  for _ in $(seq 20); do move "$((X2 + 2482))" 17; sleep 0.6; move 1280 600; sleep 0.6; done
  rc_c=$(commits "$s"); pss3=$(pss_mib "$QS_PID")
  echo "measure 20 retarget cycles on HEADLESS-2: commits=$rc_c ($(( rc_c / 20 )) per cycle), pss ${pss2} -> ${pss3} MiB"
  growth=$(python3 -c "print(round(float('$pss1') - float('$pss0'), 2))")
  growth2=$(python3 -c "print(round(float('$pss3') - float('$pss2'), 2))")
  echo "measure PSS growth over 20 cycles: hover ${growth} MiB, retarget ${growth2} MiB (budget 1 MiB)"
  check "$(python3 -c "print(1 if float('$growth') <= 1.0 and float('$growth2') <= 1.0 else 0)")" \
    "20 hover cycles and 20 retarget cycles each add at most 1 MiB of PSS"
  qs_errors
  stop_phase
}

phase_mock_one
phase_real
phase_two_outputs
phase_measure
echo "test-peek: $FAILS failed"
[ "$FAILS" -eq 0 ] || exit 1
echo "ok: screenshots in $OUT"
