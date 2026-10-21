#!/usr/bin/env bash
# The calendar mod in the REAL shell (W27-calendar), invisibly: the real kurashid and the real Quickshell frontend in the
# headless sway sandbox, `desktop.enabled = true`, the mod on, a fixture vdirsyncer-style folder (written here with
# times around the moment of the run, floating local time) and a fixture HTTP feed on 127.0.0.1 (inside the sandbox's
# network namespace). No real calendar and no network is read. Per decor (sekai, none): the document, the desk card, the
# bar widget (an event starts in ~25 min) and the clock card (agenda + day dots); then the feed goes away and a refresh
# makes it `offline` with its copy kept (desk card); then a restart without sources: the agenda's call to action.
# Checks: each step's document says what it should; no QML error or warning from the mod; no panic in kurashid's log.
# Screenshots (mods/calendar/shots/): {desk,bar,clock,desk-offline,clock-nosource}-{sekai,none}.png.
#   KURASHI_RENDER_NODE=/dev/dri/renderD129 KURASHI_BIN_DIR=<dir with kurashid and kurashi> \
#     timeout 900 nix develop -c mods/calendar/test-calendar.sh [sandbox-name]
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
NAME=${1:-w27-cal-live}   # unique per run: other runs stop any sandbox that shares a name
BIN=${KURASHI_BIN_DIR:-${CARGO_TARGET_DIR:-$ROOT/target}/debug}
OUT=$ROOT/mods/calendar/shots
DECORS=${DECORS:-sekai none}
PORT=${PORT:-8127}
export KURASHI_RENDER_NODE=${KURASHI_RENDER_NODE:-/dev/dri/renderD129}
# Regions of the 2560 x 1440 output (layout px): the desk column, the bar's right end, the island's expanded card.
DESK_GEOM=${DESK_GEOM:-"2200,30 360x900"}
BAR_GEOM=${BAR_GEOM:-"1660,0 900x48"}
CLOCK_GEOM=${CLOCK_GEOM:-"960,0 640x900"}
mkdir -p "$OUT"
FAILS=0
CHECKS=0
fail() { echo "test-calendar: $*" >&2; exit 1; }
check() { # check <0|1> <label>
  CHECKS=$((CHECKS + 1))
  if [ "$1" = 1 ]; then echo "ok: $2"; else echo "FAIL: $2"; FAILS=$((FAILS + 1)); fi
}

eval "$("$ROOT/tools/bench/sandbox.sh" start "$NAME")"
R=$XDG_RUNTIME_DIR
W=$R/work
mkdir -p "$W" "$R/kurashi"
cp "$BIN/kurashid" "$BIN/kurashi" "$W/"
rm -f "$R/qs.log" "$R/kurashid.log"
for _ in $(seq 150); do timeout 5 swaymsg -t get_outputs >/dev/null 2>&1 && break; sleep 0.2; done
timeout 5 swaymsg -t get_outputs >/dev/null 2>&1 || fail "the headless compositor does not answer (see $R/sway.log)"

DPID=""
SHPID=""
HPID=""
stop_daemon() { if [ -n "$DPID" ]; then kill "$DPID" 2>/dev/null || true; wait "$DPID" 2>/dev/null || true; fi; DPID=""; }
stop_shell() { if [ -n "$SHPID" ]; then kill "$SHPID" 2>/dev/null || true; wait "$SHPID" 2>/dev/null || true; fi; SHPID=""; }
stop_feed() { if [ -n "$HPID" ]; then kill "$HPID" 2>/dev/null || true; wait "$HPID" 2>/dev/null || true; fi; HPID=""; }
cleanup() {
  stop_shell
  stop_daemon
  stop_feed
  "$ROOT/tools/bench/sandbox.sh" stop "$NAME" >/dev/null || true
}
trap cleanup EXIT

# Hermetic: no config, state or cache from an earlier run; the system bus is not reachable.
export XDG_CONFIG_HOME=$R/xdg/config XDG_STATE_HOME=$R/xdg/state XDG_DATA_HOME=$R/xdg/data XDG_CACHE_HOME=$R/xdg/cache
export KURASHI_DATA_DIR=$ROOT LC_ALL=C.UTF-8
CALS=$R/calendars
FEEDDIR=$R/feed
K() { timeout 10 "$W/kurashi" "$@"; }

# Floating local times (no TZID: the session's zone), around now.
ts() { date -d "$1" +%Y%m%dT%H%M00; }
d8() { date -d "$1" +%Y%m%d; }
write_fixtures() {
  rm -rf "$CALS" "$FEEDDIR"
  mkdir -p "$CALS/work" "$CALS/home" "$FEEDDIR"
  printf 'Work\n' > "$CALS/work/displayname"
  printf '#3d7dd8\n' > "$CALS/work/color"
  printf 'Home\n' > "$CALS/home/displayname"
  printf '#d8843d\n' > "$CALS/home/color"
  ev() { # ev <file> <uid> <summary> <dtstart line> <dtend line> [extra lines...]
    local f=$1 uid=$2 sum=$3 s=$4 e=$5; shift 5
    { printf 'BEGIN:VCALENDAR\r\nVERSION:2.0\r\nPRODID:-//kurashi//test-calendar//EN\r\nBEGIN:VEVENT\r\n'
      printf 'UID:%s\r\nSUMMARY:%s\r\n%s\r\n%s\r\n' "$uid" "$sum" "$s" "$e"
      for x in "$@"; do printf '%s\r\n' "$x"; done
      printf 'END:VEVENT\r\nEND:VCALENDAR\r\n'; } > "$f"
  }
  ev "$CALS/work/past.ics" past "Inbox zero" "DTSTART:$(ts '-2 hours')" "DTEND:$(ts '-90 min')"
  ev "$CALS/work/next.ics" next "Design review" "DTSTART:$(ts '+25 min')" "DTEND:$(ts '+85 min')" "LOCATION:Room 4"
  ev "$CALS/work/standup.ics" standup "Standup" "DTSTART:$(d8 '-14 days')T091500" "DTEND:$(d8 '-14 days')T093000" \
    "RRULE:FREQ=WEEKLY;BYDAY=MO,TU,WE,TH,FR" "EXDATE:$(d8 '+1 day')T091500"
  ev "$CALS/work/late.ics" late "1:1 with Aiko" "DTSTART:$(ts '+3 hours')" "DTEND:$(ts '+210 min')"
  ev "$CALS/home/holiday.ics" holiday "Bunka no hi" "DTSTART;VALUE=DATE:$(d8 today)" "DTEND;VALUE=DATE:$(d8 '+1 day')"
  ev "$CALS/home/trip.ics" trip "Trip to Kyoto" "DTSTART;VALUE=DATE:$(d8 '+2 days')" "DTEND;VALUE=DATE:$(d8 '+5 days')"
  ev "$CALS/home/dinner.ics" dinner "Dinner at Ume" "DTSTART:$(d8 '+1 day')T190000" "DTEND:$(d8 '+1 day')T210000"
  { printf 'BEGIN:VCALENDAR\r\nVERSION:2.0\r\nX-WR-CALNAME:Team\r\nBEGIN:VEVENT\r\nUID:feed-1\r\nSUMMARY:Team lunch\r\n'
    printf 'DTSTART:%s\r\nDTEND:%s\r\nEND:VEVENT\r\n' "$(ts '+40 min')" "$(ts '+70 min')"   # still today in an evening run
    printf 'BEGIN:VEVENT\r\nUID:feed-2\r\nSUMMARY:Sprint planning\r\nDTSTART:%sT100000\r\nDTEND:%sT113000\r\nEND:VEVENT\r\n' \
      "$(d8 '+7 days')" "$(d8 '+7 days')"
    printf 'END:VCALENDAR\r\n'; } > "$FEEDDIR/team.ics"
}
start_feed() {
  stop_feed
  python3 -I -m http.server "$PORT" --bind 127.0.0.1 --directory "$FEEDDIR" >> "$R/feed.log" 2>&1 &
  HPID=$!
  for _ in $(seq 50); do python3 -I -c "import socket; socket.create_connection(('127.0.0.1', $PORT), 0.2)" 2>/dev/null && break; sleep 0.1; done
}

# `ipc.py <doc>` prints the first snapshot's data of a document (stdlib only, as in mods/tasks/test-tasks.sh).
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
# doc_is <python condition on d, t (today's titles)>: 0 when it holds for mod.calendar now.
doc_is() {
  ipc mod.calendar | python3 -c "
import json, sys
d = json.load(sys.stdin) or {}
t = [e['title'] for e in (d.get('days') or {}).get(d.get('today', ''), [])]
src = d.get('sources') or []
sys.exit(0 if ($1) else 1)" 2>/dev/null
}
wait_doc() { local i; for i in $(seq "$2"); do doc_is "$1" && return 0; sleep 0.5; done; return 0; }
shot() { # shot <name> <geometry>
  sleep "${WAIT:-2}"
  grim -g "$2" "$OUT/$1.png"
  [ -s "$OUT/$1.png" ] || fail "empty screenshot $1"
  echo "shot $1"
}

start_all() { # start_all <decor> <with sources: 1|0>
  stop_shell
  stop_daemon
  rm -rf "$R/xdg"
  mkdir -p "$XDG_CONFIG_HOME/kurashi" "$XDG_STATE_HOME" "$XDG_DATA_HOME" "$XDG_CACHE_HOME"
  {
    printf 'theme.style = "%s"\ndesktop.enabled = true\n\n[mods.calendar]\n' "$1"
    if [ "$2" = 1 ]; then
      printf 'sources = [\n  { name = "", location = "%s", color = "", enabled = true },\n' "$CALS"
      printf '  { name = "Team", location = "http://127.0.0.1:%s/team.ics", color = "#4caf7d", enabled = true },\n]\n' "$PORT"
    fi
  } > "$XDG_CONFIG_HOME/kurashi/config.toml"
  rm -f "$KURASHI_SOCKET"
  env DBUS_SYSTEM_BUS_ADDRESS="unix:path=$R/no-system-bus" PULSE_SERVER="unix:$R/no-pulse/native" \
    PULSE_RUNTIME_PATH="$R/no-pulse" "$W/kurashid" >> "$R/kurashid.log" 2>&1 &
  DPID=$!
  for _ in $(seq 100); do [ -S "$KURASHI_SOCKET" ] && K ping >/dev/null 2>&1 && break; sleep 0.1; done
  K ping >/dev/null 2>&1 || fail "kurashid did not come up (see $R/kurashid.log)"
  K act mod.enable '{"id": "calendar"}' >/dev/null || fail "mod.enable calendar failed"
  swaymsg output '*' bg '#8fb8c8' solid_color >/dev/null 2>&1 || true
  env -u KURASHI_SOCKET qs -p "$ROOT/frontend" >> "$R/qs.log" 2>&1 &
  SHPID=$!
  sleep "${SHELL_WAIT:-5}"
}

for DECOR in $DECORS; do
  echo "== $DECOR: folder + feed"
  write_fixtures
  start_feed
  start_all "$DECOR" 1
  wait_doc 'd.get("state") == "ready" and len(src) == 2 and src[1].get("state") == "ready"' 30
  check "$(doc_is 'd.get("state") == "ready" and src[0].get("kind") == "folder" and src[1].get("kind") == "feed" and src[1].get("name") == "Team"' && echo 1 || echo 0)" "$DECOR: both sources ready"
  check "$(doc_is '"Bunka no hi" in t and "Design review" in t and "Team lunch" in t and t[0] == "Bunka no hi"' && echo 1 || echo 0)" "$DECOR: today lists the folder's and the feed's events, all-day first"
  check "$(doc_is 'not any("127.0.0.1" in json.dumps(s) for s in src)' && echo 1 || echo 0)" "$DECOR: the feed address is not in the document"
  shot "desk-$DECOR" "$DESK_GEOM"
  shot "bar-$DECOR" "$BAR_GEOM"
  K act island.expand >/dev/null || fail "island.expand failed"
  shot "clock-$DECOR" "$CLOCK_GEOM"
  K act ui.close '{}' >/dev/null 2>&1 || true

  echo "== $DECOR: the feed goes away"
  stop_feed
  K act calendar.refresh '{}' >/dev/null || fail "calendar.refresh failed"
  wait_doc 'src[1].get("state") == "offline"' 30
  check "$(doc_is 'src[1].get("state") == "offline" and src[1].get("fetched_at") and "Team lunch" in t' && echo 1 || echo 0)" "$DECOR offline: the copy stays, with its age"
  shot "desk-offline-$DECOR" "$DESK_GEOM"

  echo "== $DECOR: no calendar set"
  start_all "$DECOR" 0
  wait_doc 'd.get("state") == "none"' 20
  check "$(doc_is 'd.get("state") == "none" and d.get("reason") == "mod-calendar.no_source"' && echo 1 || echo 0)" "$DECOR none: the document says no calendar is set"
  K act island.expand >/dev/null || fail "island.expand failed"
  shot "clock-nosource-$DECOR" "$CLOCK_GEOM"
  K act ui.close '{}' >/dev/null 2>&1 || true
done
stop_shell
stop_daemon

if grep -Eq 'ReferenceError|TypeError|binding loop|is not a function|is not defined|is not a type' "$R/qs.log" 2>/dev/null; then
  echo "QML errors in qs.log: $(grep -E 'ReferenceError|TypeError|binding loop|is not a function|is not defined|is not a type' "$R/qs.log" | head -5)" >&2
  FAILS=$((FAILS + 1))
fi
if grep -Ei 'mods/calendar' "$R/qs.log" 2>/dev/null | grep -Eiq 'warn|error'; then
  echo "QML warnings from the calendar mod: $(grep -Ei 'mods/calendar' "$R/qs.log" | grep -Ei 'warn|error' | head -5)" >&2
  FAILS=$((FAILS + 1))
fi
if grep -q panicked "$R/kurashid.log" 2>/dev/null; then
  echo "kurashid panicked (see $R/kurashid.log)" >&2
  FAILS=$((FAILS + 1))
fi
echo "checks: $((CHECKS - FAILS < 0 ? 0 : CHECKS - FAILS)) of $CHECKS"
[ "$FAILS" -eq 0 ] || fail "$FAILS failure(s); logs in $R, screenshots in $OUT"
echo "ok: screenshots in $OUT"
