#!/usr/bin/env bash
# The weather panel's states drawn in the REAL shell (W19-weather), invisibly: the real kurashid and the real Quickshell
# frontend in the headless sway sandbox. The forecast comes from a FIXTURE on loopback (KURASHI_WEATHER_API, which the
# shell never sets), so nothing reaches the network (K37). The fixture's mode says what every request gets (ok, drop:
# the connection ends with no answer, hang: no answer, 429 or 503: that status). A clock shim, preloaded into kurashid
# alone, ages the saved data past its tiers without a wait (KURASHI_TEST_TIME_FILE, test only).
#
# The states (screenshots in mods/weather/shots/): en fresh, with the hourly rain row and the seven days as crops; aging
# (45 min), stale (2 h), very stale (7 h: temperatures hidden); no place; loading (a fetch that never answers); offline
# with no data and with data (a manual refresh fails); rate limited; the places mode (the saved places); ja fresh and
# ja places mode. The one-line preview of a search result is not shot: the search is not typed in this harness.
# Checks: each state's document says what the state should say, no QML error or warning from the weather mod in qs.log,
# no panic in kurashid's log.
#   KURASHI_RENDER_NODE=/dev/dri/renderD129 KURASHI_BIN_DIR=<dir with kurashid and kurashi> \
#     timeout 1500 nix develop -c mods/weather/test-states.sh [sandbox-name]
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
NAME=${1:-w19-weather-states}   # unique per run: other runs stop any sandbox that shares a name
BIN=${KURASHI_BIN_DIR:-${CARGO_TARGET_DIR:-$ROOT/target}/debug}
OUT=$ROOT/mods/weather/shots
FX=$ROOT/crates/kurashi-mod-weather/tests/fixtures
export KURASHI_RENDER_NODE=${KURASHI_RENDER_NODE:-/dev/dri/renderD129}
# The crops of the fresh panel (grim geometry "x,y WxH", layout px of the 2560 x 1440 output): the hourly strip with its
# rain row, and the seven days. The card sits under the bar at 1080,36 and is 400 px wide.
HOURS_GEOM=${HOURS_GEOM:-"1090,278 380x112"}
DAYS_GEOM=${DAYS_GEOM:-"1090,388 380x270"}
# Where the pointer clicks the header's Places button (layout px of the 2560 x 1440 output).
PLACES_X=${PLACES_X:-1402}
PLACES_Y=${PLACES_Y:-73}
# The fixture's forecast is for 2026-10-09 14:00 in Tokyo (1791522000). The daemon's clock starts at that moment (the
# shim's offset is the difference to the real clock at the start), so the fixture's hours and days are the ones ahead.
TOKYO_1400=1791522000
BASE_OFFSET=$((TOKYO_1400 - $(date +%s)))
mkdir -p "$OUT"
FAILS=0
CHECKS=0
FINDINGS=()
finding() { FINDINGS+=("$*"); echo "finding: $*" >&2; }
fail() { echo "test-states: $*" >&2; exit 1; }
check() { # check <0|1> <label>
  CHECKS=$((CHECKS + 1))
  if [ "$1" = 1 ]; then echo "ok: $2"; else echo "FAIL: $2"; FAILS=$((FAILS + 1)); fi
}

eval "$("$ROOT/tools/bench/sandbox.sh" start "$NAME")"
R=$XDG_RUNTIME_DIR
W=$R/work
mkdir -p "$W" "$R/kurashi" "$R/weather"
cp "$BIN/kurashid" "$BIN/kurashi" "$W/"
cp "$FX/forecast_tokyo.json" "$R/weather/forecast"
cp "$FX/geocode_tokyo_ja.json" "$R/weather/search"
rm -f "$R/qs.log" "$R/kurashid.log" "$R/fixture.log"
for _ in $(seq 150); do timeout 5 swaymsg -t get_outputs >/dev/null 2>&1 && break; sleep 0.2; done
timeout 5 swaymsg -t get_outputs >/dev/null 2>&1 || fail "the headless compositor does not answer (see $R/sway.log)"

DPID=""
SHPID=""
FIXPID=""
cleanup() {
  for pid in "$SHPID" "$DPID" "$FIXPID"; do
    if [ -n "$pid" ]; then kill "$pid" 2>/dev/null || true; wait "$pid" 2>/dev/null || true; fi
  done
  "$ROOT/tools/bench/sandbox.sh" stop "$NAME" >/dev/null || true
}
trap cleanup EXIT

# Hermetic: no config, state or cache from an earlier run; the system bus is not reachable. The checkout's mods,
# i18n and frontend are the ones the shell runs (KURASHI_DATA_DIR names the checkout, as in test-peek.sh).
export XDG_CONFIG_HOME=$R/xdg/config XDG_STATE_HOME=$R/xdg/state XDG_DATA_HOME=$R/xdg/data XDG_CACHE_HOME=$R/xdg/cache
export KURASHI_DATA_DIR=$ROOT LC_ALL=C.UTF-8
K() { timeout 10 "$W/kurashi" "$@"; }
ipc() { timeout 10 python3 -I "$W/ipc.py" "$@"; }
click() { timeout 30 python3 -I "$ROOT/tools/bench/wl_pointer.py" click "$1" "$2" left >> "$R/keys.log" 2>&1 || true; sleep 0.5; }

# `ipc.py <doc>` prints the first snapshot's data of a document (stdlib only, as in test-peek.sh).
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

# The clock shim (test only): CLOCK_REALTIME plus the offset, in seconds, that $KURASHI_TEST_TIME_FILE holds (read on each
# call; 0 without the file). The data ages past its tiers without a wait of hours.
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

# The forecast service's stand-in on loopback. The mode file says what each request gets: ok (the fixture), drop (the
# connection ends with no answer: offline), hang (no answer: a fetch in flight), or a status code (429, 503).
cat > "$W/fixture.py" <<'PY'
import http.server, os, socketserver, sys, time

ROOT, MODE = sys.argv[1], sys.argv[2]


class Handler(http.server.BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.0"

    def log_message(self, fmt, *args):
        pass

    def mode(self):
        try:
            with open(MODE) as f:
                return f.read().strip() or "ok"
        except OSError:
            return "ok"

    def do_GET(self):
        mode = self.mode()
        if mode == "drop":
            self.close_connection = True
            return
        if mode == "hang":
            time.sleep(600)
            return
        if mode.isdigit():
            self.send_response(int(mode))
            self.send_header("Content-Length", "0")
            self.end_headers()
            return
        name = "search" if self.path.startswith("/v1/search") else "forecast"
        with open(os.path.join(ROOT, name), "rb") as f:
            body = f.read()
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)


class Server(socketserver.ThreadingMixIn, http.server.HTTPServer):
    daemon_threads = True


Server(("127.0.0.1", 8099), Handler).serve_forever()
PY
python3 -I "$W/fixture.py" "$R/weather" "$R/weather/mode" > "$R/fixture.log" 2>&1 &
FIXPID=$!
echo ok > "$R/weather/mode"
sleep 1
kill -0 "$FIXPID" 2>/dev/null || fail "the forecast fixture did not start (see $R/fixture.log)"

set_mode() { echo "$1" > "$R/weather/mode"; }
# set_offset <seconds past the fixture's moment>: the daemon's clock is BASE_OFFSET plus that.
set_offset() { echo $((BASE_OFFSET + $1)) > "$R/timeoffset"; }

stop_daemon() {
  if [ -n "$DPID" ]; then kill "$DPID" 2>/dev/null || true; wait "$DPID" 2>/dev/null || true; fi
  DPID=""
}
stop_shell() {
  if [ -n "$SHPID" ]; then kill "$SHPID" 2>/dev/null || true; wait "$SHPID" 2>/dev/null || true; fi
  SHPID=""
}
# A fresh daemon with the clock shim and the fixture as its forecast service, in the locale given.
start_daemon() {
  stop_daemon
  rm -rf "$XDG_CONFIG_HOME" "$XDG_STATE_HOME" "$XDG_DATA_HOME" "$XDG_CACHE_HOME"
  mkdir -p "$XDG_CONFIG_HOME" "$XDG_STATE_HOME" "$XDG_DATA_HOME" "$XDG_CACHE_HOME"
  set_offset 0
  rm -f "$KURASHI_SOCKET"
  env LC_ALL="$1" KURASHI_WEATHER_API=http://127.0.0.1:8099 KURASHI_TEST_TIME_FILE="$R/timeoffset" \
    LD_PRELOAD="$W/timeshift.so${LD_PRELOAD:+:$LD_PRELOAD}" DBUS_SYSTEM_BUS_ADDRESS="unix:path=$R/no-system-bus" \
    "$W/kurashid" >> "$R/kurashid.log" 2>&1 &
  DPID=$!
  for _ in $(seq 100); do [ -S "$KURASHI_SOCKET" ] && K ping >/dev/null 2>&1 && break; sleep 0.1; done
  K ping >/dev/null 2>&1 || fail "kurashid did not come up (see $R/kurashid.log)"
}
# The shell (this checkout's frontend) in the locale given; it reads the daemon's document as the panel does.
start_shell() {
  stop_shell
  env -u KURASHI_SOCKET LC_ALL="$1" qs -p "$ROOT/frontend" >> "$R/qs.log" 2>&1 &
  SHPID=$!
  sleep "${SHELL_WAIT:-5}"
}
# A fresh daemon and shell, the weather mod enabled: nothing saved yet.
start_all() {
  start_daemon "$1"
  start_shell "$1"
  K act mod.enable '{"id": "weather"}' >/dev/null || fail "mod.enable weather failed"
  sleep 1
}
# A saved place as the search would have answered it (the name in the locale of the run).
place_json() { # place_json <name> <admin>
  printf '{"place": {"id": "1850147", "name": "%s", "admin": "%s", "country_code": "JP", "lat": 35.6895, "lon": 139.69171, "tz": "Asia/Tokyo"}}' "$1" "$2"
}
open_panel() {
  K act mod.panel.open '{"id": "weather", "panel": "weather"}' >/dev/null || fail "mod.panel.open weather failed"
  sleep 3
}
# doc_is <python condition on d>: 0 when it holds for the mod's document now.
doc_is() { ipc mod.weather | python3 -c "import json,sys; d = json.load(sys.stdin) or {}; sys.exit(0 if ($1) else 1)" 2>/dev/null; }
# wait_doc <python condition> <seconds>: waits until the condition holds or the time is up. It never fails the run: the
# check after it records whether the condition held.
wait_doc() {
  local i
  for i in $(seq "$2"); do doc_is "$1" && return 0; sleep 1; done
  return 0
}
# shot <name>: the panel as it is, after the frames settle.
shot() {
  sleep "${WAIT:-2}"
  grim -o HEADLESS-1 "$OUT/state-$1.png"
  [ -s "$OUT/state-$1.png" ] || fail "empty screenshot $1"
  echo "shot state-$1"
}
# The places mode of the panel: the header's Places button, a search typed into the field, the first result chosen.
# The places mode: the header's Places button shows the search field and the saved places. The search is not typed here:
# the keys reach the card, but a click on the field does not give its TextInput the focus in this harness, so the one-line
# preview is covered by the unit tests (actions::preview) and has no shot.
places_mode() {
  click "$PLACES_X" "$PLACES_Y"
  sleep 1
  shot "$1-places-mode"
}

# ---- the states ---------------------------------------------------------------------------------------
echo "== en fresh: Tokyo's forecast, its hourly rain row and its seven days (and their crops)"
set_mode ok
start_all C.UTF-8
K act weather.place.add "$(place_json Tokyo Tokyo)" >/dev/null || fail "weather.place.add failed"
open_panel
wait_doc 'd.get("available") is True and d.get("tier") == "fresh"' 30
check "$(doc_is 'd.get("available") is True and d.get("tier") == "fresh"' && echo 1 || echo 0)" "fresh: the document carries the forecast and its tier"
shot en-fresh
grim -g "$HOURS_GEOM" "$OUT/state-en-hours-rain.png"
grim -g "$DAYS_GEOM" "$OUT/state-en-seven-days.png"
echo "shot state-en-hours-rain, state-en-seven-days"

echo "== en aging, stale, very stale: the refresh fails from here on, and the saved data ages with the clock"
set_mode drop
set_offset 2700
wait_doc 'd.get("tier") == "aging"' 90
check "$(doc_is 'd.get("tier") == "aging" and d.get("reason") == "mod-weather.error.offline"' && echo 1 || echo 0)" "aging: 45 min old, the refresh failing (offline, with its next try)"
shot en-aging
set_offset 7200
wait_doc 'd.get("tier") == "stale"' 90
check "$(doc_is 'd.get("tier") == "stale" and d.get("now") is not None' && echo 1 || echo 0)" "stale: 2 h old, the values kept with the tier"
shot en-stale
set_offset 25200
wait_doc 'd.get("tier") == "very_stale"' 90
check "$(doc_is 'd.get("tier") == "very_stale" and d.get("now") is None' && echo 1 || echo 0)" "very stale: 7 h old, no temperatures in the document"
shot en-very-stale
stop_shell
stop_daemon

echo "== en no place: the call to action"
set_mode ok
set_offset 0
start_all C.UTF-8
open_panel
wait_doc 'd.get("reason") == "mod-weather.no_location"' 20
check "$(doc_is 'd.get("reason") == "mod-weather.no_location" and d.get("available") is False' && echo 1 || echo 0)" "no place: the reason is no_location"
shot en-no-location
stop_shell
stop_daemon

echo "== en loading: the first fetch never answers"
set_mode hang
start_all C.UTF-8
K act weather.place.add "$(place_json Tokyo Tokyo)" >/dev/null || fail "weather.place.add failed"
open_panel
wait_doc 'd.get("reason") == "mod-weather.loading"' 15
check "$(doc_is 'd.get("reason") == "mod-weather.loading"' && echo 1 || echo 0)" "loading: the document says loading while the fetch is in flight"
WAIT=1 shot en-loading
stop_shell
stop_daemon

echo "== en offline with no data: the first fetch is refused by the connection"
set_mode drop
start_all C.UTF-8
K act weather.place.add "$(place_json Tokyo Tokyo)" >/dev/null || fail "weather.place.add failed"
open_panel
wait_doc 'd.get("reason") == "mod-weather.error.offline" and d.get("available") is False' 20
check "$(doc_is 'd.get("reason") == "mod-weather.error.offline" and d.get("available") is False' && echo 1 || echo 0)" "offline without data: the reason is offline and no values are shown"
shot en-offline-no-data
stop_shell
stop_daemon

echo "== en offline with data: a manual refresh fails and the last data stays, with the reason"
set_mode ok
start_all C.UTF-8
K act weather.place.add "$(place_json Tokyo Tokyo)" >/dev/null || fail "weather.place.add failed"
open_panel
wait_doc 'd.get("available") is True' 20
set_mode drop
K act weather.refresh '{}' >/dev/null || fail "weather.refresh failed"
wait_doc 'd.get("reason") == "mod-weather.error.offline" and d.get("available") is True' 20
check "$(doc_is 'd.get("reason") == "mod-weather.error.offline" and d.get("available") is True and d.get("now") is not None' && echo 1 || echo 0)" "offline with data: the last values stay and the reason says why"
shot en-offline-with-data
stop_shell
stop_daemon

echo "== en rate limited: the service answers 429 and says when it tries again"
set_mode 429
start_all C.UTF-8
K act weather.place.add "$(place_json Tokyo Tokyo)" >/dev/null || fail "weather.place.add failed"
open_panel
wait_doc 'd.get("reason") == "mod-weather.error.rate_limited"' 20
check "$(doc_is 'd.get("reason") == "mod-weather.error.rate_limited"' && echo 1 || echo 0)" "rate limited: the reason is rate_limited"
shot en-rate-limited
stop_shell
stop_daemon

echo "== en places: the places mode with the saved places"
set_mode ok
set_offset 0
start_all C.UTF-8
K act weather.place.add "$(place_json Tokyo Tokyo)" >/dev/null || fail "weather.place.add failed"
open_panel
wait_doc 'd.get("available") is True' 20
places_mode en
stop_shell
stop_daemon

echo "== ja: the fresh panel and the places mode in Japanese"
set_mode ok
start_all ja_JP.UTF-8
K act weather.place.add "$(place_json 東京 東京都)" >/dev/null || fail "weather.place.add failed"
open_panel
wait_doc 'd.get("available") is True' 20
shot ja-fresh
places_mode ja
stop_shell
stop_daemon

# ---- the checks of the whole run ----------------------------------------------------------------------
if grep -Eq 'ReferenceError|TypeError|binding loop|is not a function|is not defined' "$R/qs.log" 2>/dev/null; then
  finding "QML errors in qs.log: $(grep -E 'ReferenceError|TypeError|binding loop|is not a function|is not defined' "$R/qs.log" | head -3 | tr '\n' ' ')"
fi
if grep -Ei 'mods/weather|weather/qml' "$R/qs.log" 2>/dev/null | grep -Eiq 'warn|error'; then
  finding "QML warnings from the weather mod in qs.log: $(grep -Ei 'mods/weather|weather/qml' "$R/qs.log" | grep -Ei 'warn|error' | head -3 | tr '\n' ' ')"
fi
if grep -q panicked "$R/kurashid.log" 2>/dev/null; then
  finding "kurashid panicked (see $R/kurashid.log)"
fi
echo "checks: $((CHECKS - FAILS)) of $CHECKS documents as their states say (see the ok/FAIL lines above)"
if [ "$FAILS" -gt 0 ] || [ "${#FINDINGS[@]}" -gt 0 ]; then
  printf 'finding: %s\n' "${FINDINGS[@]}" >&2
  fail "$FAILS failed check(s), ${#FINDINGS[@]} finding(s); screenshots in $OUT"
fi
echo "ok: screenshots in $OUT"
