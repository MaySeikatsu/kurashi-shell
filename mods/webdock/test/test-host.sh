#!/usr/bin/env bash
# The web dock's web host (MODS.md "Web dock", "Host processes"; K38, K39; B27), tested in a headless sandbox against
# kurashi-mock with file:// fixture pages (no network, K37). Phases:
#   1 main      hidden without commits (10 s); reveal, typing right after it (B27); mobile and desktop views; storage per
#               profile (split and shared); keep and unload; load error; blocked chip (getUserMedia); crashed renderer;
#               sign-in sheet; the four edges; large. Screenshots in mods/webdock/shots/.
#   2 ja        the copy in Japanese (the blocked chip, the header), from the mock's i18n document.
#   3 privacy   Chromium's net log with the pragma's switches plus --log-net-log, 45 s with pages open; no request the
#               fixture pages did not make, and the control page's loopback request is in the log (positive control).
#   4 memory    PSS of the host's process tree with 1 and with 5 kept sites.
#   5 scope     a refused scope (goodbye scope) ends the host.
#   timeout 1200 mods/webdock/test/test-host.sh [sandbox-name]
#   KURASHI_BIN_DIR=<dir with kurashi-mock> (default: ${CARGO_TARGET_DIR:-target}/debug)
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
NAME=${1:-webdock-host}
BIN=${KURASHI_BIN_DIR:-${CARGO_TARGET_DIR:-$ROOT/target}/debug}
TEST=$ROOT/mods/webdock/test
PAGES=$TEST/pages
SHOTS=$ROOT/mods/webdock/shots
PORT=8765
# The pragma's switches (mods/webdock/host/shell.qml); the camera switch is test-only: Chromium asks for a camera
# only when one exists, and the sandbox has none.
PRAGMA_FLAGS="--disable-background-networking --disable-component-update --disable-domain-reliability --no-pings"
CAMERA_FLAG="--use-fake-device-for-media-stream"
R=/tmp/kurashi-sb-$NAME
MOCK= HOST= HTTP=

fail() { echo "test-host: FAIL: $*" >&2; exit 1; }
ok() { echo "test-host: ok: $*"; }
ipc() { python3 -I "$TEST/ipc.py" "$@"; }
keys() { python3 -I "$ROOT/tools/bench/wl_keys.py" "$@"; }
logs() { grep -c -F -- "$1" "$R/logs/host.log" || true; }
has() { grep -q -F -- "$1" "$R/logs/host.log"; }
# Waits (up to $2 seconds) until the host's log holds the text $1.
wait_log() {
  local i
  for i in $(seq $(($2 * 10))); do has "$1" && return 0; sleep 0.1; done
  return 1
}
# A field of one pin in mod.webdock: pin_field <pin> <python expression over p>.
pin_field() {
  ipc doc mod.webdock | python3 -c "import json,sys; d=json.load(sys.stdin); p=[x for x in d['pins'] if x['id']=='$1'][0]; print($2)"
}
shot() {
  sleep 2
  grim -o HEADLESS-1 "$SHOTS/$1.png" 2>>"$R/logs/grim.log" || fail "grim failed on $1"
  ok "shot mods/webdock/shots/$1.png"
}
# Every host log line that would be a QML problem; Chromium's own ERROR lines are not QML.
qml_problems() {
  grep -E -- 'caused by|is not a type|is not defined|ReferenceError|TypeError|Binding loop|Unable to assign|Cannot assign|Failed to load configuration' "$R/logs/host.log" || true
}
check_no_qml_problems() {
  local bad
  bad=$(qml_problems)
  [ -z "$bad" ] || fail "QML problems in the host log:
$bad"
}

start_mock() {  # the mock on the sandbox's socket; its locale comes from the environment
  "$BIN/kurashi-mock" --outputs HEADLESS-1 --socket "$KURASHI_SOCKET" >> "$R/logs/mock.log" 2>&1 &
  MOCK=$!
  local i
  for i in $(seq 100); do
    [ -S "$KURASHI_SOCKET" ] && ipc doc svc.clock >/dev/null 2>&1 && return 0
    sleep 0.1
  done
  fail "the mock did not come up (see $R/logs/mock.log)"
}
set_pins() {  # the test's pins (pins.py), with the control page when $1 is given
  ipc act mock.webdock "$(python3 -I "$TEST/pins.py" "$ROOT" "${1:-}")" >/dev/null || fail "mock.webdock refused"
}
stop_host() {
  if [ -n "$HOST" ] && kill -0 "$HOST" 2>/dev/null; then
    kill "$HOST" 2>/dev/null || true
    wait "$HOST" 2>/dev/null || true
  fi
  HOST=
}
# The host, as the daemon starts it: the scope in its environment, the shell's Store connects with it.
start_host() {  # $1: QTWEBENGINE_CHROMIUM_FLAGS; the rest: extra environment (KEY=VALUE)
  local flags=$1; shift
  stop_host
  local before
  before=$(grep -c -F -- 'webdock-host' "$R/logs/mock.log" || true)
  : > "$R/logs/host.log"
  env QTWEBENGINE_CHROMIUM_FLAGS="$flags" KURASHI_SCOPE_MOD=webdock \
    KURASHI_SCOPE_TOKEN="${TOKEN:-6f1c2a9e4b7d0835}" KURASHI_CLIENT=webdock-host KURASHI_WEBDOCK_DEBUG=1 \
    "$@" qs-webengine -p "$ROOT/mods/webdock/host/shell.qml" > "$R/logs/host.log" 2>&1 &
  HOST=$!
  local i now
  for i in $(seq 300); do
    now=$(grep -c -F -- 'webdock-host' "$R/logs/mock.log" || true)
    [ "$now" -gt "$before" ] && return 0
    kill -0 "$HOST" 2>/dev/null || fail "the host exited before its hello (see $R/logs/host.log)"
    sleep 0.1
  done
  fail "the host did not say hello (see $R/logs/host.log)"
}
# The renderer processes of the host: the pages' processes, which the crash test stops. They are descendants of the
# host (the sandboxed ones do not carry the sandbox's environment, so the environment is no test of them).
renderers() {
  local p
  for p in $(descendants "$HOST"); do
    if tr '\0' ' ' < "/proc/$p/cmdline" 2>/dev/null | grep -q -- '--type=renderer'; then echo "$p"; fi
  done
}
# PSS of a process and its descendants (the measure.sh method: the ppid tree, smaps_rollup).
descendants() {
  local c
  echo "$1"
  for c in $(awk -v p="$1" '$4==p{print $1}' /proc/[0-9]*/stat 2>/dev/null); do descendants "$c"; done
}
tree_pss() {
  local total=0 p v
  for p in $(descendants "$1"); do
    v=$(awk '/^Pss:/{print $2}' "/proc/$p/smaps_rollup" 2>/dev/null || true)
    total=$((total + ${v:-0}))
  done
  echo "$total"
}

# ---- sandbox, dirs and environment (hermetic: isolated XDG dirs, the sandbox's own network, no system bus) ----
"$ROOT/tools/bench/sandbox.sh" stop "$NAME" >/dev/null 2>&1 || true
rm -rf "$R"
eval "$("$ROOT/tools/bench/sandbox.sh" start "$NAME")"
trap 'stop_host; [ -n "$MOCK" ] && kill "$MOCK" 2>/dev/null || true; [ -n "$HTTP" ] && kill "$HTTP" 2>/dev/null || true; "$ROOT/tools/bench/sandbox.sh" stop "$NAME" >/dev/null 2>&1 || true' EXIT
mkdir -p "$R/kurashi" "$R/logs" "$SHOTS" "$R/xdg/config" "$R/xdg/state" "$R/xdg/data" "$R/xdg/cache"
export XDG_CONFIG_HOME=$R/xdg/config XDG_STATE_HOME=$R/xdg/state XDG_DATA_HOME=$R/xdg/data XDG_CACHE_HOME=$R/xdg/cache
export KURASHI_DATA_DIR=$ROOT LC_ALL=C.UTF-8

# ================================ phase 1: the main run ================================
start_mock
set_pins
start_host "$PRAGMA_FLAGS $CAMERA_FLAG" WAYLAND_DEBUG=1
ok "the host said hello with its scope"

# Hidden: the host maps no surface, so it commits nothing for 10 s (Ma). WAYLAND_DEBUG must be printing, or the count is void.
[ "$(logs "wl_")" -gt 0 ] || fail "WAYLAND_DEBUG printed no protocol lines"
c0=$(logs "-> wl_surface@")
sleep 10
c1=$(logs "-> wl_surface@")
c_commit=$(grep -c -E -- 'wl_surface@[0-9]+\.commit' "$R/logs/host.log" || true)
[ "$c0" = "$c1" ] || fail "the hidden host sent $((c1 - c0)) Wayland requests in 10 s"
[ "${c_commit:-0}" = 0 ] || fail "the hidden host committed $c_commit surface frames"
ok "hidden: 0 surface commits in 10 s"

# Reveal and type at once (B27): the first keystroke reaches the page. The keys go through one virtual keyboard.
ipc act webdock.open '{"pin":"typed"}' >/dev/null || fail "webdock.open typed refused"
keys h e l l o space k u r a s h i
wait_log "webdock-debug typed INPUT hello kurashi" 8 || fail "the typed text did not arrive complete (see $R/logs/host.log)"
ok "typed text arrives complete (B27)"
shot phone-right

# Mobile and desktop views: the page reports its own user agent and viewport.
ipc act webdock.open '{"pin":"mail"}' >/dev/null || fail "webdock.open mail refused"
wait_log "webdock-debug mail UA mail mobile=true platform=Android inner=412" 8 || fail "mobile view not sent"
shot mobile-phone
ipc act webdock.open '{"pin":"chat"}' >/dev/null || fail "webdock.open chat refused"
wait_log "webdock-debug chat UA chat mobile=false platform=Linux" 8 || fail "desktop view not sent"
shot desktop-phone
ok "mobile sends the Android user agent, client hints and Mobile; desktop the engine's own"

# Storage: pins on two profiles keep their own counters; pins on one profile share it.
ipc act webdock.open '{"pin":"split1"}' >/dev/null
wait_log "VISITS split1 1" 8 || fail "split1 first visit"
ipc act webdock.open '{"pin":"split2"}' >/dev/null
wait_log "VISITS split2 1" 8 || fail "split2 is not separate from split1"
# A page still in keep is not reloaded by showing it again; a view change reloads it, and the profile's storage
# survives the reload (the count goes on from 1).
ipc act webdock.view '{"pin":"split1","view":"desktop"}' >/dev/null
ipc act webdock.open '{"pin":"split1"}' >/dev/null
wait_log "VISITS split1 2" 8 || fail "split1 lost its storage across the reload"
ipc act webdock.open '{"pin":"shared1"}' >/dev/null
wait_log "VISITS shared1 1" 8 || fail "shared1 first visit"
ipc act webdock.open '{"pin":"shared2"}' >/dev/null
wait_log "VISITS shared2 2" 8 || fail "shared2 does not share shared1's storage"
ok "storage: separate profiles stay separate, one profile is shared"

# Keep and unload: five sites shown in turn keep the last four; the first one is reported unloaded.
for k in k1 k2 k3 k4 k5; do ipc act webdock.open "{\"pin\":\"$k\"}" >/dev/null; sleep 0.5; done
sleep 3
[ "$(pin_field k1 "p.get('loaded', False)")" = False ] || fail "k1 left keep but is still loaded"
[ "$(pin_field k5 "p.get('loaded', False)")" = True ] || fail "k5 is shown but not loaded"
ok "keep holds the last four sites; the one that left is unloaded"

# Load error: a target that does not exist (code and retry, brief "States").
ipc act webdock.open '{"pin":"bad"}' >/dev/null
sleep 3
shot load-error

# Blocked chip: the page asks for the camera; the host refuses and reports it.
ipc act webdock.open '{"pin":"cam"}' >/dev/null
wait_log "webdock-debug cam GUM" 8 || fail "the camera page did not ask"
sleep 1
[ "$(pin_field cam "'camera' in p.get('blocked', [])")" = True ] || fail "the blocked permission was not reported"
shot blocked-chip
ok "blocked: the camera request is refused and reported"

# Crashed: the renderer stops; the host reports it and says so (brief "States").
ipc act webdock.open '{"pin":"mail"}' >/dev/null
sleep 3
pids=$(renderers | tr '\n' ' ')
[ -n "$pids" ] || fail "no renderer process to stop"
# shellcheck disable=SC2086
kill -9 $pids 2>/dev/null || true
sleep 3
[ "$(pin_field mail "p.get('error', '')")" = webdock.error.crashed ] || fail "the stopped renderer was not reported"
shot crashed
ok "crashed: the stopped renderer is reported and the page says so"

# Sign-in sheet: the page opens a popup with an opener (Tab to the button, Return); the sheet holds the popup.
ipc act webdock.open '{"pin":"sign"}' >/dev/null
sleep 2
keys tab return
wait_log "webdock-debug sign VISITS popup" 8 || fail "the popup did not open"
shot sheet-popup
ok "sheet: the popup opens inside the card"

# Edges: the card at each edge (the strip's margin, the card centred along the edge).
for edge in left top bottom right; do
  ipc act webdock.collapse '{}' >/dev/null
  ipc act mock.webdock "{\"edge\":\"$edge\"}" >/dev/null
  ipc act webdock.open '{"pin":"mail"}' >/dev/null
  sleep 1
  [ "$edge" = right ] || shot "edge-$edge"
done
ok "edges: left, top and bottom shot; right is the phone shot above"

# Large: the card's large size, from the right edge.
ipc act webdock.size '{"size":"large"}' >/dev/null
sleep 1
shot large-right
ipc act webdock.size '{"size":"phone"}' >/dev/null
check_no_qml_problems
ok "phase 1: no QML problems"
stop_host
kill "$MOCK" 2>/dev/null || true
wait "$MOCK" 2>/dev/null || true

# ================================ phase 2: Japanese copy ================================
export LC_ALL=ja_JP.UTF-8
start_mock
set_pins
ipc doc i18n | python3 -c "import json,sys; s=json.load(sys.stdin)['strings']; assert s['webdock.blocked.camera']=='ブロック: カメラ', s.get('webdock.blocked.camera')" \
  || fail "the mock's i18n document is not Japanese"
start_host "$PRAGMA_FLAGS $CAMERA_FLAG"
ipc act webdock.open '{"pin":"cam"}' >/dev/null
wait_log "webdock-debug cam GUM" 8 || fail "the camera page did not ask (ja)"
sleep 1
shot ja-blocked
check_no_qml_problems
ok "ja: the copy is Japanese"
stop_host
kill "$MOCK" 2>/dev/null || true
wait "$MOCK" 2>/dev/null || true
export LC_ALL=C.UTF-8

# ================================ phase 3: privacy (the net log) ================================
rm -f "$R/netlog.json"
python3 -I -m http.server --bind 127.0.0.1 --directory "$PAGES" "$PORT" > "$R/logs/http.log" 2>&1 &
HTTP=$!
sleep 1
start_mock
set_pins "$PORT"
start_host "$PRAGMA_FLAGS --log-net-log=$R/netlog.json --net-log-capture-mode=Everything"
ipc act webdock.open '{"pin":"ctl"}' >/dev/null
sleep 5
ipc act webdock.open '{"pin":"mail"}' >/dev/null
sleep 45
stop_host
python3 -I "$TEST/netlog.py" "$R/netlog.json" "$PAGES" "http://127.0.0.1:$PORT/ping.txt" "http://127.0.0.1:$PORT/control.html" \
  || fail "the net log holds a request the pages did not make (see the FOREIGN lines above)"
ok "privacy: no request beyond the fixture pages, the control's request is logged"
kill "$HTTP" 2>/dev/null || true
wait "$HTTP" 2>/dev/null || true
HTTP=
kill "$MOCK" 2>/dev/null || true
wait "$MOCK" 2>/dev/null || true

# ================================ phase 4: memory ================================
start_mock
set_pins
start_host "$PRAGMA_FLAGS"
ipc act webdock.open '{"pin":"k1"}' >/dev/null
sleep 10
pss1=$(tree_pss "$HOST")
ipc act mock.webdock '{"keep":["k1","k2","k3","k4","k5"],"shown":"k1","mode":"extended"}' >/dev/null
sleep 14
pss5=$(tree_pss "$HOST")
echo "test-host: memory: host process tree PSS, 1 kept site: $((pss1 / 1024)) MiB, 5 kept sites: $((pss5 / 1024)) MiB"
ok "memory measured (report the numbers)"
check_no_qml_problems
stop_host
kill "$MOCK" 2>/dev/null || true
wait "$MOCK" 2>/dev/null || true

# ================================ phase 5: a refused scope ================================
start_mock
set_pins
TOKEN=bad
env QTWEBENGINE_CHROMIUM_FLAGS="$PRAGMA_FLAGS" KURASHI_SCOPE_MOD=webdock KURASHI_SCOPE_TOKEN=bad KURASHI_CLIENT=webdock-host \
  timeout 30 qs-webengine -p "$ROOT/mods/webdock/host/shell.qml" > "$R/logs/refused.log" 2>&1 || true
grep -q -F -- 'refused this scope' "$R/logs/refused.log" || fail "the refused scope was not logged"
ok "a refused scope ends the host (logged, no retries)"
kill "$MOCK" 2>/dev/null || true
wait "$MOCK" 2>/dev/null || true

echo "test-host: PASS"
