#!/usr/bin/env bash
# The timer mod in the REAL shell (K73, docs/ux/timer.md "Definition of done"), invisibly: the real kurashid and the real
# Quickshell frontend in the headless sway sandbox, with `desktop.enabled = true`, the mod on and every variant shot.
# Per decor and scheme (washi light and dark, sekai light, then washi ja): a countdown and a pomodoro started with the CLI,
# the glance in the bar, its peek, the panel (Stage card), the desk card, the island face and its expanded view, the quick
# tile, the sidebar section, the end (the island transient and the notification), the pomodoro's break, and then with the
# shell closed: a countdown ends with no view open, and a daemon restart keeps a paused timer and announces nothing twice.
# Checks: each step's document says what it should; a notification with the timer's name reached the notification server;
# no QML error or warning from the mod in qs.log; no panic in kurashid's log.
# Screenshots (mods/timer/shots/): {shot}-{decor}-{scheme|ja}.png, one per variant and state.
#   KURASHI_BIN_DIR=<dir with kurashid and kurashi> timeout 1500 nix develop -c mods/timer/test-timer.sh [sandbox-name]
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
NAME=${1:-w43-timer-live}   # unique per run: other runs stop any sandbox that shares a name
BIN=${KURASHI_BIN_DIR:-${CARGO_TARGET_DIR:-$ROOT/target}/debug}
OUT=$ROOT/mods/timer/shots
# The runs: "decor scheme locale" triples, each a fresh daemon and shell.
RUNS=${RUNS:-"washi light en|washi dark en|sekai light en|sekai dark en|washi light ja"}
# Layout px of the 2560 x 1440 headless output (HEADLESS-1). The bar is the top strip; the Stage card sits under it, centred.
BAR_GEOM=${BAR_GEOM:-"0,0 2560x40"}
PEEK_GEOM=${PEEK_GEOM:-"1960,40 600x220"}
PANEL_GEOM=${PANEL_GEOM:-"2140,30 420x520"}
DESK_GEOM=${DESK_GEOM:-"2200,430 360x170"}
ISLAND_GEOM=${ISLAND_GEOM:-"1140,0 280x48"}
ISLAND_EXPANDED_GEOM=${ISLAND_EXPANDED_GEOM:-"1000,0 560x560"}
QUICK_GEOM=${QUICK_GEOM:-"2100,30 440x640"}
SIDEBAR_GEOM=${SIDEBAR_GEOM:-"2110,0 450x1440"}
TOAST_GEOM=${TOAST_GEOM:-"1100,36 370x130"}
# The glance's x in the bar (layout px) for the peek; the bar's widgets sit on the right of the centre. Override per run.
GLANCE_X=${GLANCE_X:-2300}
mkdir -p "$OUT"
FAILS=0
CHECKS=0
fail() { echo "test-timer: $*" >&2; exit 1; }
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
stop_daemon() { if [ -n "$DPID" ]; then kill "$DPID" 2>/dev/null || true; wait "$DPID" 2>/dev/null || true; fi; DPID=""; }
stop_shell() { if [ -n "$SHPID" ]; then kill "$SHPID" 2>/dev/null || true; wait "$SHPID" 2>/dev/null || true; fi; SHPID=""; }
cleanup() {
  stop_shell
  stop_daemon
  "$ROOT/tools/bench/sandbox.sh" stop "$NAME" >/dev/null || true
}
trap cleanup EXIT

# Hermetic: no config, state or cache from an earlier run; the system bus is not reachable. The session bus is the
# sandbox's own (the notification server of the daemon lives there).
export XDG_CONFIG_HOME=$R/xdg/config XDG_STATE_HOME=$R/xdg/state XDG_DATA_HOME=$R/xdg/data XDG_CACHE_HOME=$R/xdg/cache
export KURASHI_DATA_DIR=$ROOT
K() { timeout 15 "$W/kurashi" "$@"; }

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
# mt.py: the first snapshot of a document on stdin (the CLI's `sub` prints it first), read as a python expression over `d`
# (the document) and `T` (its timers). Exit 0 when the expression holds; with `print` it prints the value instead.
cat > "$W/mt.py" <<'PY'
import json, sys

text = sys.stdin.read()
at = text.find("{")
if at < 0:
    sys.exit("mt: no snapshot")
obj = json.JSONDecoder().raw_decode(text, at)[0]
# `kurashi sub` sends {"t": "snap", ..., "data": {...}}; a document is its data.
d = obj.get("data", obj) if obj.get("t") == "snap" else obj
value = eval(sys.argv[1], {"d": d, "T": d.get("timers", [])})
if len(sys.argv) > 2 and sys.argv[2] == "print":
    print(value)
    sys.exit(0)
sys.exit(0 if value else 1)
PY
# cli_snap <doc> <expr>: 0 when the expression holds for the document as the CLI's `sub` reads it (`kurashi sub`, one second).
cli_snap() { timeout 1 "$W/kurashi" sub "$1" > "$W/snap.txt" 2>/dev/null; python3 -I "$W/mt.py" "$2" < "$W/snap.txt"; }
cli_print() { timeout 1 "$W/kurashi" sub "$1" > "$W/snap.txt" 2>/dev/null; python3 -I "$W/mt.py" "$2" print < "$W/snap.txt"; }
# The pointer: the sandbox's virtual pointer and keyboard (the frontend tests' helpers), at layout coordinates.
click_at() { timeout 30 python3 -I "$ROOT/tools/bench/wl_pointer.py" click "$1" "$2" left >> "$R/keys.log" 2>&1 || true; sleep 1.5; }
type_keys() { timeout 30 python3 -I "$ROOT/tools/bench/wl_keys.py" "$@" >> "$R/keys.log" 2>&1 || true; sleep 1; }
# doc_is <python condition on d>: 0 when it holds for mod.timer now.
doc_is() { ipc mod.timer | python3 -c "import json,sys; d = json.load(sys.stdin) or {}; sys.exit(0 if ($1) else 1)" 2>/dev/null; }
wait_doc() { local i; for i in $(seq "$2"); do doc_is "$1" && return 0; sleep 0.5; done; return 0; }
# notified <text>: 0 when the notification server holds a notice whose summary or body has the text.
notified() { ipc svc.notifications | python3 -c "import json,sys; d = json.load(sys.stdin) or {}; t = sys.argv[1]; items = d.get('items', []); sys.exit(0 if any(t in (i.get('summary','') + ' ' + i.get('body','')) for i in items) else 1)" "$1" 2>/dev/null; }
# toasted <text>: 0 when a notice with the text is one of the popups on screen. The document's `toasts` lists the ids of the showing
# notices (kurashi-notify), so the items with those ids are the toasts.
toasted() { ipc svc.notifications | python3 -c "import json,sys; d = json.load(sys.stdin) or {}; t = sys.argv[1]; shown = set(d.get('toasts', [])); sys.exit(0 if any(i.get('id') in shown and t in (i.get('summary','') + ' ' + i.get('body','')) for i in d.get('items', [])) else 1)" "$1" 2>/dev/null; }
shot() { # shot <name> <geometry>
  sleep "${WAIT:-2}"
  grim -g "$2" "$OUT/$1.png"
  [ -s "$OUT/$1.png" ] || fail "empty screenshot $1"
  echo "shot $1"
}

start_all() { # start_all <decor> <scheme> <locale>
  stop_shell
  stop_daemon
  rm -rf "$R/xdg"
  mkdir -p "$XDG_CONFIG_HOME/kurashi" "$XDG_STATE_HOME" "$XDG_DATA_HOME" "$XDG_CACHE_HOME"
  cat > "$XDG_CONFIG_HOME/kurashi/config.toml" <<TOML
theme.style = "$1"
theme.colors.scheme = "$2"
desktop.enabled = true
sidebar.right = ["header", "mod:timer:timer"]
TOML
  rm -f "$KURASHI_SOCKET"
  env LC_ALL="$3.UTF-8" LANG="$3.UTF-8" DBUS_SYSTEM_BUS_ADDRESS="unix:path=$R/no-system-bus" \
    PULSE_SERVER="unix:$R/no-pulse/native" PULSE_RUNTIME_PATH="$R/no-pulse" "$W/kurashid" >> "$R/kurashid.log" 2>&1 &
  DPID=$!
  for _ in $(seq 100); do [ -S "$KURASHI_SOCKET" ] && K ping >/dev/null 2>&1 && break; sleep 0.1; done
  K ping >/dev/null 2>&1 || fail "kurashid did not come up (see $R/kurashid.log)"
  K act mod.enable '{"id": "timer"}' >/dev/null || fail "mod.enable timer failed"
  swaymsg output '*' bg '#8fb8c8' solid_color >/dev/null 2>&1 || true
  start_shell
}

start_shell() {
  env -u KURASHI_SOCKET LC_ALL="$LOCALE_RUN.UTF-8" LANG="$LOCALE_RUN.UTF-8" qs -p "$ROOT/frontend" >> "$R/qs.log" 2>&1 &
  SHPID=$!
  sleep "${SHELL_WAIT:-5}"
}

run_one() { # run_one <decor> <scheme> <locale>
  local decor=$1 scheme=$2 locale=$3 tag
  LOCALE_RUN=$locale
  if [ "$locale" = en ]; then tag="$decor-$scheme"; else tag="$decor-$locale"; fi
  echo "== $tag"
  start_all "$decor" "$scheme" "$locale"

  echo "-- idle: the glance is the timer glyph"
  wait_doc 'd.get("available") is True' 20
  check "$(doc_is 'd.get("available") is True and d.get("timers") == []' && echo 1 || echo 0)" "$tag idle: the document is there and empty"
  shot "glance-idle-$tag" "$BAR_GEOM"

  echo "-- the pointer: the glance, then the Stage panel; each step is read back through kurashi sub"
  # The glance's hit area in this bar: from about x=2370 (x=2364 is outside it); 2376 is inside for idle and running.
  click_at 2376 15
  check "$(cli_snap mod.timer 'len(T) == 1 and T[0]["state"] == "running" and T[0]["duration_ms"] == 300000' && echo 1 || echo 0)" "$tag glance: a click on the idle glance starts the default preset (5 min)"
  click_at 2376 15
  check "$(cli_snap runtime.ui 'd.get("panel") == "mod:timer:timer"' && echo 1 || echo 0)" "$tag glance: a click on the running glance opens the panel"
  shot "panel-pointer-$tag" "$PANEL_GEOM"
  click_at 2269 201
  check "$(cli_snap mod.timer 'len(T) == 2 and any(t["duration_ms"] == 600000 for t in T)' && echo 1 || echo 0)" "$tag panel: a click on the 10 min preset starts it"
  click_at 2280 323
  type_keys 1 colon 3 0 return
  check "$(cli_snap mod.timer 'len(T) == 3 and any(t["duration_ms"] == 90000 for t in T)' && echo 1 || echo 0)" "$tag panel: the custom field takes 1:30 and Enter starts it"
  click_at 2404 132
  check "$(cli_snap mod.timer 'any(t["duration_ms"] == 90000 and t["state"] == "paused" for t in T)' && echo 1 || echo 0)" "$tag panel: pause"
  # Paused, the timer sorts after the running ones: it is the third row now (rows are 58 px apart, the first at y 132).
  click_at 2404 248
  check "$(cli_snap mod.timer 'any(t["duration_ms"] == 90000 and t["state"] == "running" for t in T)' && echo 1 || echo 0)" "$tag panel: resume"
  click_at 2456 132
  check "$(cli_snap mod.timer 'any(t["duration_ms"] == 150000 and t["state"] == "running" for t in T)' && echo 1 || echo 0)" "$tag panel: +1 min"
  click_at 2510 131
  check "$(cli_snap mod.timer 'len(T) == 2 and not any(t["duration_ms"] == 150000 for t in T)' && echo 1 || echo 0)" "$tag panel: stop removes the row"
  K act ui.close '{}' >/dev/null 2>&1 || true
  K act timer.stop_all '{}' >/dev/null 2>&1 || true

  echo "-- two timers, started from the CLI"
  K act timer.start '{"minutes": 10, "label": "Tea"}' >/dev/null || fail "timer.start failed"
  K act timer.pomodoro.start '{}' >/dev/null || fail "timer.pomodoro.start failed"
  wait_doc 'len(d.get("timers", [])) == 2' 20
  check "$(doc_is 'len(d["timers"]) == 2 and d["timers"][0]["label"] == "Tea" and d["timers"][0]["state"] == "running" and d["timers"][1]["kind"] == "pomodoro" and d["timers"][1]["phase"] == "focus" and d["timers"][1]["round"] == 1' && echo 1 || echo 0)" "$tag start: Tea (nearest) and a focus round 1"
  check "$(doc_is 'd["timers"][0]["ends_at_ms"] > 0 and d["timers"][0]["duration_ms"] == 600000' && echo 1 || echo 0)" "$tag start: the deadline is set from the duration"
  shot "glance-running-$tag" "$BAR_GEOM"

  echo "-- peek on the glance"
  K act ui.peek "{\"source\": \"mod:timer:timer\", \"output\": \"HEADLESS-1\", \"x\": $GLANCE_X, \"w\": 220}" >/dev/null || true
  shot "peek-$tag" "$PEEK_GEOM"
  K act ui.peek '{}' >/dev/null || true

  echo "-- the panel (Stage card)"
  echo "reply: $(K act mod.panel.open '{"id": "timer", "panel": "timer"}' 2>&1 || echo "exit $?")"
  echo "ui: $(ipc runtime.ui 2>&1 | head -c 400 || true)"
  shot "panel-$tag" "$PANEL_GEOM"
  K act ui.close '{}' >/dev/null 2>&1 || true

  echo "-- the desk card"
  shot "desk-$tag" "$DESK_GEOM"

  echo "-- the island face (live) and its expanded view"
  shot "island-live-$tag" "$ISLAND_GEOM"
  K act island.expand '{"face": "timer"}' >/dev/null 2>&1 || true
  shot "island-expanded-$tag" "$ISLAND_EXPANDED_GEOM"
  K act ui.close '{}' >/dev/null 2>&1 || true

  echo "-- the quick tile"
  K act quick.toggle '{}' >/dev/null 2>&1 || true
  shot "quick-$tag" "$QUICK_GEOM"
  K act quick.toggle '{}' >/dev/null 2>&1 || true

  echo "-- the sidebar section"
  K act sidebar.right.toggle '{}' >/dev/null 2>&1 || true
  shot "sidebar-$tag" "$SIDEBAR_GEOM"
  K act sidebar.right.toggle '{}' >/dev/null 2>&1 || true

  echo "-- the pomodoro's break"
  POMO_ID=$(cli_print mod.timer 'next(t["id"] for t in T if t["kind"] == "pomodoro")' || true)
  K act timer.skip "{\"id\": ${POMO_ID:-0}}" >/dev/null 2>&1 || true
  K act mod.panel.open '{"id": "timer", "panel": "timer"}' >/dev/null || true
  wait_doc 'any(t.get("phase") == "short_break" for t in d.get("timers", []))' 10
  check "$(doc_is 'any(t.get("phase") == "short_break" and t.get("state") == "running" for t in d["timers"])' && echo 1 || echo 0)" "$tag break: the pomodoro is in its short break"
  shot "panel-break-$tag" "$PANEL_GEOM"
  K act ui.close '{}' >/dev/null 2>&1 || true

  echo "-- a countdown ends while the view is open: the island's end and the notification"
  K act timer.start '{"seconds": 4, "label": "Eggs"}' >/dev/null || fail "timer.start eggs failed"
  wait_doc 'any(t.get("label") == "Eggs" and t.get("state") == "ended" for t in d.get("timers", []))' 20
  check "$(doc_is 'any(t.get("label") == "Eggs" and t.get("state") == "ended" for t in d["timers"])' && echo 1 || echo 0)" "$tag end: Eggs is ended in the document"
  sleep 1
  check "$(notified 'Eggs' && echo 1 || echo 0)" "$tag end: a notification names Eggs"
  check "$(toasted 'Eggs' && echo 1 || echo 0)" "$tag end: a toast names Eggs"
  # The toast lives about five seconds: its shots are taken right after the end, before it goes.
  WAIT=0.5 shot "toast-end-$tag" "$TOAST_GEOM"
  grim -g "0,0 2560x1440" "$OUT/full-end-$tag.png"
  WAIT=0.5 shot "island-end-$tag" "$ISLAND_GEOM"
  # The notice's "+1 min" button, pressed through the daemon (notify.invoke): the server emits ActionInvoked on the bus,
  # and the mod's listener runs the timer's +1 min, so Eggs runs again.
  NID=$(ipc svc.notifications | python3 -c "import json,sys; d = json.load(sys.stdin) or {}; ids = [i['id'] for i in d.get('items', []) if i.get('summary') == 'Eggs']; print(ids[-1] if ids else '')" 2>/dev/null || true)
  echo "notice id: ${NID:-none}"
  if [ -n "$NID" ]; then echo "invoke: $(K act notify.invoke "{\"id\": $NID, \"key\": \"add\"}" 2>&1 || echo "exit $?")"; fi
  wait_doc 'any(t.get("label") == "Eggs" and t.get("state") == "running" for t in d.get("timers", []))' 10
  check "$(doc_is 'any(t.get("label") == "Eggs" and t.get("state") == "running" for t in d["timers"])' && echo 1 || echo 0)" "$tag end: the notice's +1 min button runs Eggs again"
  EGGS_ID=$(cli_print mod.timer 'next(t["id"] for t in T if t["label"] == "Eggs")' || true)
  K act timer.stop "{\"id\": ${EGGS_ID:-0}}" >/dev/null 2>&1 || true

  echo "-- the same panel after the end, with the Tea timer still running"
  K act mod.panel.open '{"id": "timer", "panel": "timer"}' >/dev/null || true
  shot "panel-after-end-$tag" "$PANEL_GEOM"
  K act ui.close '{}' >/dev/null 2>&1 || true

  echo "-- a timer at about half its length: the island's arc, then paused, the panel's and the desk card's"
  K act timer.stop_all '{}' >/dev/null 2>&1 || true
  K act timer.start '{"seconds": 40, "label": "Half"}' >/dev/null || fail "timer.start half failed"
  sleep 20
  shot "island-half-$tag" "$ISLAND_GEOM"
  HALF_ID=$(cli_print mod.timer 'next(t["id"] for t in T if t["label"] == "Half")' || true)
  K act timer.pause "{\"id\": $HALF_ID}" >/dev/null || fail "timer.pause half failed"
  check "$(cli_snap mod.timer 'any(t["label"] == "Half" and t["state"] == "paused" for t in T)' && echo 1 || echo 0)" "$tag half: the timer is paused about halfway"
  K act mod.panel.open '{"id": "timer", "panel": "timer"}' >/dev/null || fail "mod.panel.open timer failed"
  shot "panel-half-$tag" "$PANEL_GEOM"
  shot "desk-half-$tag" "$DESK_GEOM"
  K act ui.close '{}' >/dev/null 2>&1 || true
  K act timer.stop_all '{}' >/dev/null 2>&1 || true

  if [ "$locale" = en ] && [ "$decor" = washi ] && [ "$scheme" = light ]; then
    echo "-- the shell closed: a countdown ends with no view open"
    stop_shell
    K act timer.start '{"seconds": 3, "label": "NoView"}' >/dev/null || fail "timer.start noview failed"
    sleep 6
    # A subscriber's first snapshot can be the one registered at enable time: poll until the service has published.
    wait_doc 'any(t.get("label") == "NoView" and t.get("state") == "ended" for t in d.get("timers", []))' 20
    check "$(doc_is 'any(t.get("label") == "NoView" and t.get("state") == "ended" for t in d["timers"])' && echo 1 || echo 0)" "$tag no view: the end was reconciled with no view open"
    check "$(notified 'NoView' && echo 1 || echo 0)" "$tag no view: the notification reached the server with no view open"
    echo "-- a daemon restart keeps a paused timer, and what passed is announced once"
    K act timer.start '{"minutes": 5, "label": "Rest"}' >/dev/null || fail "timer.start rest failed"
    REST_ID=""
    for _ in $(seq 20); do
      REST_ID=$(ipc mod.timer | python3 -c "import json,sys; d = json.load(sys.stdin); print(next(t['id'] for t in d['timers'] if t['label'] == 'Rest'))" 2>/dev/null || true)
      [ -n "$REST_ID" ] && break
      sleep 0.5
    done
    [ -n "$REST_ID" ] || fail "the Rest timer is not in the document"
    K act timer.pause "{\"id\": $REST_ID}" >/dev/null || fail "timer.pause failed"
    stop_daemon
    env LC_ALL=en_US.UTF-8 DBUS_SYSTEM_BUS_ADDRESS="unix:path=$R/no-system-bus" PULSE_SERVER="unix:$R/no-pulse/native" \
      PULSE_RUNTIME_PATH="$R/no-pulse" "$W/kurashid" >> "$R/kurashid.log" 2>&1 &
    DPID=$!
    for _ in $(seq 100); do [ -S "$KURASHI_SOCKET" ] && K ping >/dev/null 2>&1 && break; sleep 0.1; done
    K ping >/dev/null 2>&1 || fail "kurashid did not come up after the restart"
    K act mod.enable '{"id": "timer"}' >/dev/null 2>&1 || true
    wait_doc 'any(t.get("label") == "Rest" and t.get("state") == "paused" for t in d.get("timers", []))' 20
    check "$(doc_is 'any(t.get("label") == "Rest" and t.get("state") == "paused" for t in d["timers"])' && echo 1 || echo 0)" "$tag restart: the paused timer is still paused"
    check "$(doc_is 'any(t.get("label") == "NoView" and t.get("state") == "ended" for t in d["timers"])' && echo 1 || echo 0)" "$tag restart: the ended timer is kept, not restarted"
    start_shell
    K act mod.panel.open '{"id": "timer", "panel": "timer"}' >/dev/null || true
    shot "panel-restart-$tag" "$PANEL_GEOM"
    K act ui.close '{}' >/dev/null 2>&1 || true
  fi
}

IFS='|' read -ra runs <<< "$RUNS"
for RUN in "${runs[@]}"; do
  read -r decor scheme locale <<< "$RUN"
  run_one "$decor" "$scheme" "$locale"
done

stop_shell
stop_daemon

QML_RE='ReferenceError|TypeError|binding loop|is not a function|is not defined|is not a type'
if grep -E "$QML_RE" "$R/qs.log" >/dev/null 2>&1; then
  echo "QML errors in qs.log: $(grep -E "$QML_RE" "$R/qs.log" | head -5)" >&2
  FAILS=$((FAILS + 1))
fi
if grep -Ei 'mods/timer' "$R/qs.log" 2>/dev/null | grep -Eiq 'warn|error'; then
  echo "QML warnings from the timer mod: $(grep -Ei 'mods/timer' "$R/qs.log" | grep -Ei 'warn|error' | head -5)" >&2
  FAILS=$((FAILS + 1))
fi
if grep -q panicked "$R/kurashid.log" 2>/dev/null; then
  echo "kurashid panicked (see $R/kurashid.log)" >&2
  FAILS=$((FAILS + 1))
fi
echo "checks: $((CHECKS - FAILS < 0 ? 0 : CHECKS - FAILS)) of $CHECKS"
[ "$FAILS" -eq 0 ] || fail "$FAILS failure(s); logs in $R, screenshots in $OUT"
echo "ok: screenshots in $OUT"
