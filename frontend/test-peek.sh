#!/usr/bin/env bash
# The bar's hover peeks (K35, I55, I67), drawn by the Stage, invisibly (headless sway sandbox): the tray tooltip (B9), the
# weather (B22), the island's line (I47) and sysmon's facts (docs/ux/sysmon.md), on every edge of the bar. Each phase has a
# fresh frontend and daemon; PEEK_PHASES="sides weather" runs only the named phases (the default runs them all):
#   mock-one    kurashi-mock, one output: tray tooltips (hover; the frame is clamped at the right edge), the island's line
#               (hover, held while the pointer is on it, gone after it leaves), no peek while a card is open;
#   real-top    kurashid (real), one output: sysmon and weather on the top bar (a localhost weather fixture, KURASHI_WEATHER_API),
#               the island's line from a notification on the top bar, then the bar on the bottom edge: sysmon and the island again;
#   sides       the bar on the left edge: sysmon and the island beside it; on the right edge: sysmon beside it;
#   weather     the weather peek in its states: no place, loading (a fetch that never answers), offline (the connection is
#               refused), stale (the data is three hours old, by a clock shim, and the fixture is gone so the refresh fails);
#   sysmon      the sysmon peek in its states: paused, unavailable (KURASHI_SYSMON_ROOT names a folder with no /proc), the
#               top-process line;
#   motion      reduced motion (theme profile none): the peek comes and goes at once, with no fade;
#   mock-two    kurashi-mock, two outputs: a tray peek on HEADLESS-2 lands there (the Stage retargets); the next card opens on
#               HEADLESS-1 (the Stage hands its output back);
#   measure     PSS of the frontend and Wayland commits (WAYLAND_DEBUG) per window: idle (no commits in 10 s), a peek held, the
#               fade in and the fade out (frames), a retarget, and 20 hover cycles (on output 1, and 20 retarget cycles on output 2).
# A peek is found by what changed against a baseline screenshot taken with nothing shown (so no colour is assumed), and by
# runtime.ui.peek (the source and output asked for) and by the state of the mod's document. No QML error in qs.log.
# Screenshots: frontend/shots/peek/ (read them).
#   KURASHI_RENDER_NODE=/dev/dri/renderD129 KURASHI_BIN_DIR=<dir with kurashid, kurashi, kurashi-mock> \
#     timeout 1200 nix develop -c frontend/test-peek.sh [sandbox-name]
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
NAME=${1:-peek-$$}   # unique per run: other agents' runs stop any sandbox that shares a name
BIN=${KURASHI_BIN_DIR:-${CARGO_TARGET_DIR:-$ROOT/target}/debug}
OUT=$ROOT/frontend/shots/peek
FX=$ROOT/crates/kurashi-mod-weather/tests/fixtures
mkdir -p "$OUT"
fail() { echo "test-peek: $*" >&2; exit 1; }
want() { [ -z "${PEEK_PHASES:-}" ] || [[ " $PEEK_PHASES " == *" $1 "* ]]; }

eval "$("$ROOT/tools/bench/sandbox.sh" start "$NAME")"
. "$ROOT/frontend/test-lib.sh"
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
# The clock shim (test only): CLOCK_REALTIME plus the offset, in seconds, that $KURASHI_TEST_TIME_FILE holds (read on each
# call; 0 without the file). The weather data ages past its tiers without a wait of twenty minutes. Preloaded into kurashid
# alone, in the states phase.
cat > "$W/timeshift.c" <<'C'
#define _GNU_SOURCE
#include <dlfcn.h>
#include <stdio.h>
#include <stdlib.h>
#include <time.h>

int clock_gettime(clockid_t clk, struct timespec *ts) {
  static int (*real)(clockid_t, struct timespec *);
  if (!real) real = (int (*)(clockid_t, struct timespec *))dlsym(RTLD_NEXT, "clock_gettime");
  int r = real(clk, ts);
  if (r == 0 && clk == CLOCK_REALTIME) {
    const char *path = getenv("KURASHI_TEST_TIME_FILE");
    FILE *f = path ? fopen(path, "r") : NULL;
    long long off = 0;
    if (f) {
      if (fscanf(f, "%lld", &off) != 1) off = 0;
      fclose(f);
    }
    ts->tv_sec += off;
  }
  return r;
}
C
cc -shared -fPIC -O2 -o "$W/timeshift.so" "$W/timeshift.c" -ldl || fail "the clock shim did not build"
ipc() { timeout 10 python3 -I "$W/ipc.py" "$@"; }
K() { timeout 10 "$W/kurashi" "$@"; }
# K71: the bar moves with its modules in one change (`layout.bar.move`), from the edge it stands on now.
bar_edge() {
  local e
  for e in top bottom left right; do
    if K --json get "edges.$e.bar" | grep -q '"value":true'; then
      [ "$e" = "$1" ] || K act layout.bar.move "{\"from\":\"$e\",\"to\":\"$1\"}" >/dev/null
      return
    fi
  done
  return 1
}
peek_src() { ipc runtime.ui | python3 -c 'import json,sys; d=json.load(sys.stdin) or {}; p=d.get("peek"); print(p["source"] if p else "")'; }
peek_out() { ipc runtime.ui | python3 -c 'import json,sys; d=json.load(sys.stdin) or {}; p=d.get("peek"); print(p["output"] if p else "")'; }
# doc_is <document> <python condition on d>: 0 when the condition holds for the document now (no check is recorded).
doc_is() {
  ipc "$1" | python3 -c "import json,sys; d = json.load(sys.stdin) or {}; sys.exit(0 if ($2) else 1)" 2>/dev/null
}
# doc_check <document> <python condition on d> <label>: the state the mod's document is in, so a shot shows the state it names.
doc_check() {
  if doc_is "$1" "$2"; then check 1 "$3"; else check 0 "$3"; fi
}
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
pss_mib() { awk '/^Pss:/{s+=$2} END{printf "%.2f", s/1024}' "/proc/$1/smaps_rollup"; }
size() { stat -c %s "$R/qs.log"; }
commits() { # commits <start byte>: Wayland surface commits (both bars and the Stage) logged since that offset
  tail -c +"$(( $1 + 1 ))" "$R/qs.log" | grep -c 'wl_surface#[0-9]*\.commit(' || true
}
# stage_commits <start byte>: commits of the Stage alone, the surfaces of the layer surfaces named kurashi-stage (a bar's
# own redraws are not the peek's frames)
stage_commits() {
  local ids
  ids=$(grep -o 'wl_surface#[0-9]*, wl_output#[0-9]*, [0-9]*, "kurashi-stage"' "$R/qs.log" | grep -oE 'wl_surface#[0-9]+' \
    | grep -oE '[0-9]+$' | paste -sd'|' - || true)
  [ -n "$ids" ] || { echo 0; return 0; }
  tail -c +"$(( $1 + 1 ))" "$R/qs.log" | grep -cE "wl_surface#($ids)\.commit\(" || true
}

pids=()
QS_PID=""
stop_phase() {
  { exec 3>&-; } 2>/dev/null || true   # the pointer's fifo; a bare `exec 2>/dev/null` would silence every later message
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
start_fixture() { # the weather fixture (Tokyo's forecast and search) on 8099; FIX_PID is its pid
  python3 -I -m http.server 8099 --bind 127.0.0.1 --directory "$R/weather" > "$R/fixture.log" 2>&1 &
  FIX_PID=$!
  pids+=("$FIX_PID")
  sleep 1
}
start_hang() { # a listener that accepts and never answers: a weather fetch stays in flight (the loading state)
  python3 -I -c 'import socket,time; s=socket.socket(); s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1); s.bind(("127.0.0.1", 8097)); s.listen(8); time.sleep(3600)' &
  pids+=("$!")
  sleep 0.5
}
start_real() { # start_real [VAR=value ...]: the real daemon with the given environment (the fixture's API unless one is named)
  # Every daemon starts from defaults: the config, the saved weather places and the mods' state of an earlier phase are gone.
  rm -rf "$XDG_CONFIG_HOME" "$XDG_STATE_HOME" "$XDG_DATA_HOME" "$XDG_CACHE_HOME"
  mkdir -p "$XDG_CONFIG_HOME" "$XDG_STATE_HOME" "$XDG_DATA_HOME" "$XDG_CACHE_HOME"
  rm -f "$KURASHI_SOCKET"
  env KURASHI_WEATHER_API=http://127.0.0.1:8099 DBUS_SYSTEM_BUS_ADDRESS="unix:path=$R/no-system-bus" "$@" "$W/kurashid" \
    >> "$R/kurashid.log" 2>&1 &
  pids+=("$!")
  for _ in $(seq 100); do [ -S "$KURASHI_SOCKET" ] && K ping >/dev/null 2>&1 && return 0; sleep 0.1; done
  fail "kurashid did not come up (see $R/kurashid.log)"
}
start_frontend() { # $1: extra environment for qs (WAYLAND_DEBUG=1 in the measurement only)
  local off bare; off=$(size); bare=$(screen_hash)
  QS_T0=$(now_ms)
  env -u KURASHI_SOCKET ${1:-} qs -p "$ROOT/frontend" >> "$R/qs.log" 2>&1 &
  QS_PID=$!
  pids+=("$QS_PID")
  # Was a fixed 4 s: the frontend loaded, drew and stands still (at most 4 s for that).
  wait_frontend "$R/qs.log" "$off" 4 0.6 "$bare" || fail "the frontend did not load (see $R/qs.log)"
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
# hover_top_for <source> <x>: the pointer on the top bar at x, or up to 30 px on, until the source's peek is asked for. A
# scan's first hit can sit on the boundary between two widgets, so the box is probed, not assumed. Returns 1 when none asks.
hover_top_for() {
  local d
  for d in 0 10 20 30; do
    move "$(( $2 + d ))" 17; sleep 0.9
    [ "$(peek_src)" = "$1" ] && return 0
  done
  return 1
}
# scan <x|y> <fixed> <from> <to> <step> <source>: the pointer moves along the axis (the other coordinate fixed) until the
# source's peek is asked for; prints that coordinate, or -1. Each step rests 0.6 s: the pointer's settle, then the 300 ms intent.
scan() {
  local axis=$1 fixed=$2 from=$3 to=$4 step=$5 src=$6 c
  for c in $(seq "$from" "$step" "$to"); do
    if [ "$axis" = x ]; then move "$c" "$fixed"; else move "$fixed" "$c"; fi
    sleep 0.6
    if [ "$(peek_src)" = "$src" ]; then echo "$c"; return 0; fi
  done
  echo -1
}
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
output_w() { timeout 10 swaymsg -t get_outputs | python3 -c "import json,sys; print([o['rect']['width'] for o in json.load(sys.stdin) if o['name']=='$1'][0])"; }
WEATHER_TOKYO='{"place":{"id":"1850147","name":"Tokyo","country_code":"JP","lat":35.6895,"lon":139.69171,"tz":"Asia/Tokyo"}}'

# ---- phase mock-one: kurashi-mock, one output: tray tooltips and the island's line
phase_mock_one() {
  echo "== phase mock-one: mock, one output"
  : > "$R/server.log"; : > "$R/qs.log"
  start_mock
  start_frontend
  start_pointer
  K mock face clock >/dev/null
  K act mock.island '{"detail":{"clock":"14:00 Standup"}}' >/dev/null
  sleep 1
  grab base-m1 HEADLESS-1
  # The tray icon is found, not assumed (W36: a fixed x landed on the sidebar button once that moved in beside it).
  TRAY_X=$(scan x 17 2200 2550 8 "tray::1.42/StatusNotifierItem")
  [ "$TRAY_X" -ge 0 ] || TRAY_X=2482
  echo "tray icon at x=$TRAY_X"
  move 1280 600; sleep 0.9
  move "$TRAY_X" 17; sleep 0.9
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

# ---- phase real-top: the real kurashid, one output, then the bottom edge
phase_real() {
  echo "== phase real-top: kurashid, sysmon and weather, the island's line, the bottom edge"
  : > "$R/kurashid.log"; : > "$R/qs.log"
  start_fixture
  start_real
  start_frontend
  start_pointer
  K act mod.enable '{"id":"sysmon"}' >/dev/null || fail "mod.enable sysmon failed"
  K act mod.enable '{"id":"weather"}' >/dev/null || fail "mod.enable weather failed"
  K act weather.place.add "$WEATHER_TOKYO" >/dev/null || fail "weather.place.add failed"
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
  hover_top_for mod:weather:weather "$wx" || true
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
  bar_edge bottom || fail "the bar did not move to the bottom"
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
  bar_edge top || fail "the bar did not move to the top"
  sleep 1
  qs_errors
  stop_phase
}

# ---- phase sides: the bar on the left edge, then on the right: the peek beside the bar, aligned to its widget
phase_sides() {
  echo "== phase sides: kurashid, the bar on the left edge, then on the right"
  : > "$R/kurashid.log"; : > "$R/qs.log"
  start_fixture
  start_real
  start_frontend
  start_pointer
  K act mod.enable '{"id":"sysmon"}' >/dev/null || fail "mod.enable sysmon failed"
  bar_edge left || fail "the bar did not move to the left"
  sleep 3
  # The sysmon widget on the left bar: the first y (top down, the pointer on the bar's middle) where its peek is asked for.
  sy=$(scan y 18 100 1400 30 mod:sysmon:sysmon)
  [ "$sy" -ge 0 ] || fail "no sysmon widget on the left bar"
  move 1280 600; sleep 1
  grab base-l HEADLESS-1
  move 18 "$((sy + 6))"; sleep 0.9
  check "$([ "$(peek_src)" = "mod:sysmon:sysmon" ] && echo 1 || echo 0)" "sysmon asks for its peek on the left bar"
  shot sysmon-peek-left HEADLESS-1
  check "$(drawn "$W/sysmon-peek-left.ppm" "$W/base-l.ppm" 44 "$((sy - 10))" 460 "$((sy + 150))")" \
    "the sysmon peek is drawn beside the left bar, at its widget"
  move 1280 600; sleep 0.9
  notify-send -t 20000 "Standup" "14:00 room 3" >/dev/null 2>&1 || fail "notify-send failed"
  sleep 2
  move 1280 600; sleep 0.5
  grab base-l2 HEADLESS-1
  move 18 720; sleep 0.9
  check "$([ "$(peek_src)" = "island:main" ] && echo 1 || echo 0)" "the island asks for its line on the left bar"
  shot island-peek-left HEADLESS-1
  check "$(drawn "$W/island-peek-left.ppm" "$W/base-l2.ppm" 44 570 460 870)" "the island's peek is drawn beside the left bar"
  move 1280 600; sleep 0.9
  bar_edge right || fail "the bar did not move to the right"
  sleep 3
  W1=$(output_w HEADLESS-1)
  rx=$((W1 - 18))
  sy2=$(scan y "$rx" 100 1400 30 mod:sysmon:sysmon)
  [ "$sy2" -ge 0 ] || fail "no sysmon widget on the right bar"
  move 1280 600; sleep 1
  grab base-r HEADLESS-1
  move "$rx" "$((sy2 + 6))"; sleep 0.9
  check "$([ "$(peek_src)" = "mod:sysmon:sysmon" ] && echo 1 || echo 0)" "sysmon asks for its peek on the right bar"
  shot sysmon-peek-right HEADLESS-1
  check "$(drawn "$W/sysmon-peek-right.ppm" "$W/base-r.ppm" "$((W1 - 44 - 400))" "$((sy2 - 10))" "$((W1 - 44))" "$((sy2 + 150))")" \
    "the sysmon peek is drawn beside the right bar, at its widget"
  move 1280 600; sleep 0.9
  check "$([ -z "$(peek_src)" ] && echo 1 || echo 0)" "the peek goes when the pointer leaves the right bar"
  bar_edge top || fail "the bar did not move to the top"
  sleep 1
  qs_errors
  stop_phase
}

# ---- phase weather: the weather peek in its states, each with its own daemon (the environment and the place make the state)
phase_weather() {
  echo "== phase weather: kurashid, the weather peek: no place, loading, offline, stale"
  : > "$R/kurashid.log"; : > "$R/qs.log"
  start_fixture
  start_real
  start_frontend
  start_pointer
  K act mod.enable '{"id":"weather"}' >/dev/null || fail "mod.enable weather failed"
  sleep 3
  doc_check mod.weather "d.get('reason') == 'mod-weather.no_location'" "weather with no place says so (no_location)"
  wx=$(scan x 17 1800 2480 20 mod:weather:weather)
  [ "$wx" -ge 0 ] || fail "no weather widget on the top bar (no place)"
  move 1280 600; sleep 1
  grab base-w0 HEADLESS-1
  hover_top_for mod:weather:weather "$wx" || true
  check "$([ "$(peek_src)" = "mod:weather:weather" ] && echo 1 || echo 0)" "weather asks for its peek with no place"
  shot weather-peek-noplace HEADLESS-1
  check "$(drawn "$W/weather-peek-noplace.ppm" "$W/base-w0.ppm" "$((wx - 4))" 40 2560 200)" "the no-place peek is drawn under the top bar"
  move 1280 600; sleep 0.9
  stop_phase

  : > "$R/kurashid.log"; : > "$R/qs.log"
  start_hang
  start_real KURASHI_WEATHER_API=http://127.0.0.1:8097
  start_frontend
  start_pointer
  K act mod.enable '{"id":"weather"}' >/dev/null || fail "mod.enable weather failed"
  K act weather.place.add "$WEATHER_TOKYO" >/dev/null || fail "weather.place.add failed"
  sleep 2
  doc_check mod.weather "d.get('reason') == 'mod-weather.loading'" "weather with a place and no answer yet is loading"
  wx=$(scan x 17 1800 2480 20 mod:weather:weather)
  [ "$wx" -ge 0 ] || fail "no weather widget on the top bar (loading)"
  move 1280 600; sleep 1
  grab base-w1 HEADLESS-1
  hover_top_for mod:weather:weather "$wx" || true
  check "$([ "$(peek_src)" = "mod:weather:weather" ] && echo 1 || echo 0)" "weather asks for its peek while loading"
  shot weather-peek-loading HEADLESS-1
  check "$(drawn "$W/weather-peek-loading.ppm" "$W/base-w1.ppm" "$((wx - 4))" 40 2560 200)" "the loading peek is drawn under the top bar"
  move 1280 600; sleep 0.9
  stop_phase

  : > "$R/kurashid.log"; : > "$R/qs.log"
  start_real KURASHI_WEATHER_API=http://127.0.0.1:8096
  start_frontend
  start_pointer
  K act mod.enable '{"id":"weather"}' >/dev/null || fail "mod.enable weather failed"
  K act weather.place.add "$WEATHER_TOKYO" >/dev/null || fail "weather.place.add failed"
  sleep 3
  doc_check mod.weather "d.get('reason') == 'mod-weather.error.offline'" "weather with the connection refused is offline"
  wx=$(scan x 17 1800 2480 20 mod:weather:weather)
  [ "$wx" -ge 0 ] || fail "no weather widget on the top bar (offline)"
  move 1280 600; sleep 1
  grab base-w2 HEADLESS-1
  hover_top_for mod:weather:weather "$wx" || true
  check "$([ "$(peek_src)" = "mod:weather:weather" ] && echo 1 || echo 0)" "weather asks for its peek while offline"
  shot weather-peek-offline HEADLESS-1
  check "$(drawn "$W/weather-peek-offline.ppm" "$W/base-w2.ppm" "$((wx - 4))" 40 2560 200)" "the offline peek is drawn under the top bar"
  move 1280 600; sleep 0.9
  stop_phase

  : > "$R/kurashid.log"; : > "$R/qs.log"
  start_fixture
  echo 0 > "$R/timeoffset"
  start_real KURASHI_TEST_TIME_FILE="$R/timeoffset" LD_PRELOAD="$W/timeshift.so${LD_PRELOAD:+:$LD_PRELOAD}"
  start_frontend
  start_pointer
  K act mod.enable '{"id":"weather"}' >/dev/null || fail "mod.enable weather failed"
  K act weather.place.add "$WEATHER_TOKYO" >/dev/null || fail "weather.place.add failed"
  sleep 3
  doc_check mod.weather "d.get('tier') == 'fresh'" "weather data is fresh when it arrives"
  echo 10800 > "$R/timeoffset"         # three hours on: past two refreshes (30 min), so the data is stale
  kill "$FIX_PID" 2>/dev/null || true  # the fixture is gone: the refresh fails and the data is kept
  K act weather.refresh '{}' >/dev/null || fail "weather.refresh failed"
  sleep 3
  doc_check mod.weather "d.get('tier') == 'stale'" "weather data three hours old is stale"
  wx=$(scan x 17 1800 2480 20 mod:weather:weather)
  [ "$wx" -ge 0 ] || fail "no weather widget on the top bar (stale)"
  move 1280 600; sleep 1
  grab base-w3 HEADLESS-1
  hover_top_for mod:weather:weather "$wx" || true
  check "$([ "$(peek_src)" = "mod:weather:weather" ] && echo 1 || echo 0)" "weather asks for its peek while stale"
  shot weather-peek-stale HEADLESS-1
  check "$(drawn "$W/weather-peek-stale.ppm" "$W/base-w3.ppm" "$((wx - 4))" 40 2560 200)" "the stale peek is drawn under the top bar"
  move 1280 600; sleep 0.9
  qs_errors
  stop_phase
}

# ---- phase sysmon: the sysmon peek in its states
phase_sysmon() {
  echo "== phase sysmon: kurashid, the sysmon peek: paused, unavailable, the top-process line"
  : > "$R/kurashid.log"; : > "$R/qs.log"
  start_real
  start_frontend
  start_pointer
  K act mod.enable '{"id":"sysmon"}' >/dev/null || fail "mod.enable sysmon failed"
  K act sysmon.pause '{"paused": true}' >/dev/null || fail "sysmon.pause failed"
  sleep 3
  doc_check mod.sysmon "d.get('paused') is True" "sysmon is paused"
  sx=$(scan x 17 1800 2480 20 mod:sysmon:sysmon)
  [ "$sx" -ge 0 ] || fail "no sysmon widget on the top bar (paused)"
  move 1280 600; sleep 1
  grab base-s0 HEADLESS-1
  hover_top_for mod:sysmon:sysmon "$sx" || true
  check "$([ "$(peek_src)" = "mod:sysmon:sysmon" ] && echo 1 || echo 0)" "sysmon asks for its peek while paused"
  shot sysmon-peek-paused HEADLESS-1
  check "$(drawn "$W/sysmon-peek-paused.ppm" "$W/base-s0.ppm" "$((sx - 4))" 40 "$((sx + 200))" 200)" "the paused peek is drawn under the top bar"
  move 1280 600; sleep 0.9
  qs_errors
  stop_phase

  : > "$R/kurashid.log"; : > "$R/qs.log"
  mkdir -p "$R/no-sysmon"   # a folder with no /proc under it: the sampler reads nothing (unavailable)
  start_real KURASHI_SYSMON_ROOT="$R/no-sysmon"
  start_frontend
  start_pointer
  K act mod.enable '{"id":"sysmon"}' >/dev/null || fail "mod.enable sysmon failed"
  sleep 3
  doc_check mod.sysmon "d.get('available') is False" "sysmon with no /proc is unavailable"
  sx=$(scan x 17 1800 2480 20 mod:sysmon:sysmon)
  [ "$sx" -ge 0 ] || fail "no sysmon widget on the top bar (unavailable)"
  move 1280 600; sleep 1
  grab base-s1 HEADLESS-1
  hover_top_for mod:sysmon:sysmon "$sx" || true
  check "$([ "$(peek_src)" = "mod:sysmon:sysmon" ] && echo 1 || echo 0)" "sysmon asks for its peek while unavailable"
  shot sysmon-peek-unavailable HEADLESS-1
  check "$(drawn "$W/sysmon-peek-unavailable.ppm" "$W/base-s1.ppm" "$((sx - 4))" 40 "$((sx + 200))" 200)" "the unavailable peek is drawn under the top bar"
  move 1280 600; sleep 0.9
  qs_errors
  stop_phase

  : > "$R/kurashid.log"; : > "$R/qs.log"
  start_real
  start_frontend
  start_pointer
  K act mod.enable '{"id":"sysmon"}' >/dev/null || fail "mod.enable sysmon failed"
  sleep 3
  # The top-process line is the peek's last line, from the process list the peek subscribes to while it shows. That list
  # exists only under a subscriber, so the shot is the evidence here (read it), not a one-shot document read.
  sx=$(scan x 17 1800 2480 20 mod:sysmon:sysmon)
  [ "$sx" -ge 0 ] || fail "no sysmon widget on the top bar (top process)"
  move 1280 600; sleep 1
  grab base-s2 HEADLESS-1
  hover_top_for mod:sysmon:sysmon "$sx" || true
  check "$([ "$(peek_src)" = "mod:sysmon:sysmon" ] && echo 1 || echo 0)" "sysmon asks for its peek with a top process"
  shot sysmon-peek-top-process HEADLESS-1
  check "$(drawn "$W/sysmon-peek-top-process.ppm" "$W/base-s2.ppm" "$((sx - 4))" 40 "$((sx + 200))" 240)" \
    "the peek with the top-process line is drawn under the top bar"
  move 1280 600; sleep 0.9
  qs_errors
  stop_phase
}

# ---- phase motion: reduced motion (theme profile none): the island's line comes and goes at once. No sysmon here: its widget
# commits by itself every second, and the count would then be the bar's, not the peek's.
phase_motion() {
  echo "== phase motion: kurashid, reduced motion (theme profile none)"
  : > "$R/kurashid.log"; : > "$R/qs.log"
  start_real
  start_frontend "WAYLAND_DEBUG=1"
  start_pointer
  K set theme.motion.profile none >/dev/null || fail "theme.motion.profile none was refused"
  notify-send -t 20000 "Standup" "14:00 room 3" >/dev/null 2>&1 || fail "notify-send failed"
  sleep 3
  move 1280 600; sleep 1
  grab base-m HEADLESS-1
  s=$(size); move 1280 17; sleep 0.6; in_c=$(stage_commits "$s")
  check "$([ "$(peek_src)" = "island:main" ] && echo 1 || echo 0)" "the island asks for its line with reduced motion"
  shot island-peek-reduced-motion HEADLESS-1
  check "$(drawn "$W/island-peek-reduced-motion.ppm" "$W/base-m.ppm" 1100 40 1460 200)" \
    "the reduced-motion peek is drawn under the top bar"
  s=$(size); move 1280 600; sleep 0.6; out_c=$(stage_commits "$s")
  echo "measure reduced motion: the Stage's commits: the peek came in $in_c, and went after its grace in $out_c"
  check "$([ "$in_c" -le 4 ] && [ "$out_c" -le 4 ] && echo 1 || echo 0)" \
    "reduced motion: the peek comes and goes in at most 4 frames, with no fade"
  qs_errors
  stop_phase
}

# ---- phase mock-two: kurashi-mock, two outputs: the Stage retargets to the peek's output and gives its output back
phase_two_outputs() {
  echo "== phase mock-two: mock, two outputs"
  : > "$R/server.log"; : > "$R/qs.log"
  start_mock
  start_frontend
  two_outputs
  start_pointer
  X2=$(output_x HEADLESS-2)
  move 1280 600; sleep 1
  grab base-o1 HEADLESS-1
  grab base-o2 HEADLESS-2
  move "$((X2 + ${TRAY_X:-2482}))" 17; sleep 0.9
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

# ---- phase measure: measurement (PSS of the frontend, Wayland commits from WAYLAND_DEBUG): printed; the growth is checked
phase_measure() {
  echo "== phase measure: measurement (two outputs)"
  : > "$R/server.log"; : > "$R/qs.log"
  start_mock
  start_frontend "WAYLAND_DEBUG=1"
  two_outputs
  start_pointer
  X2=$(output_x HEADLESS-2)
  move 1280 600
  # (The idle window and its PSS start at least 12 s after the launch, as with the fixed 4 s start before.)
  sleep 6; sleep_rest "$QS_T0" 12
  s=$(size); sleep 10; idle_c=$(commits "$s"); idle_pss=$(pss_mib "$QS_PID")
  echo "measure idle, no peek (10 s): commits=$idle_c pss=${idle_pss} MiB"
  check "$([ "$idle_c" = 0 ] && echo 1 || echo 0)" "idle with no peek: no Wayland commits in 10 s"
  s=$(size); move 2482 17; sleep 0.9; fade_c=$(stage_commits "$s")
  s=$(size); sleep 5; held_c=$(commits "$s"); shown_pss=$(pss_mib "$QS_PID")
  echo "measure peek on HEADLESS-1: fade-in (0.9 s) Stage commits=$fade_c, held (5 s) commits=$held_c pss=${shown_pss} MiB"
  s=$(size); move 1280 600; sleep 0.9; fadeout_c=$(stage_commits "$s")
  sleep 1; s=$(size); sleep 1; gone_c=$(commits "$s")
  echo "measure peek gone: fade-out (the 250 ms grace and the 120 ms fade, 0.9 s) Stage commits=$fadeout_c, every surface idle after it (1 s) commits=$gone_c"
  check "$([ "$gone_c" = 0 ] && echo 1 || echo 0)" "the Stage is idle again after the fade out (no commits in 1 s)"
  s=$(size); move "$((X2 + 2482))" 17; sleep 0.9; retarget_c=$(commits "$s")
  s=$(size); sleep 5; out2_c=$(commits "$s"); out2_pss=$(pss_mib "$QS_PID")
  echo "measure peek on HEADLESS-2: retarget (0.9 s) commits=$retarget_c, held (5 s) commits=$out2_c pss=${out2_pss} MiB"
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

want mock-one && phase_mock_one
want real-top && phase_real
want sides && phase_sides
want weather && phase_weather
want sysmon && phase_sysmon
want motion && phase_motion
want mock-two && phase_two_outputs
want measure && phase_measure
echo "test-peek: $FAILS failed"
[ "$FAILS" -eq 0 ] || exit 1
echo "ok: screenshots in $OUT"
