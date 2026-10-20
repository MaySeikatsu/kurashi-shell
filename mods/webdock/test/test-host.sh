#!/usr/bin/env bash
# The web dock's web host (MODS.md "Web dock", "Host processes"; K38, K39; B27), tested in a headless sandbox against
# kurashi-mock with file:// fixture pages (no network, K37). Phases:
#   1 main      hidden without commits (10 s); reveal, typing right after it (B27); mobile and desktop views; storage per
#               profile (split and shared); keep and unload; load error; blocked chip (getUserMedia); crashed renderer;
#               sign-in sheet; the four edges; large; then (W20-webdock-host, K40, I78) the header at 360 px and its
#               tooltip, new tabs in the dock and in the browser, home, the overflow menu (replace pin), the focus and
#               hover reports, the large header and the bottom corners. Screenshots in mods/webdock/shots/.
#   2 ja        the copy in Japanese (the blocked chip; the header with home and the overflow menu), from the mock's
#               i18n document.
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
PRAGMA_FLAGS=$(sed -n 's/^\/\/@ pragma DefaultEnv QTWEBENGINE_CHROMIUM_FLAGS = //p' "$ROOT/mods/webdock/host/shell.qml")
[ -n "$PRAGMA_FLAGS" ] || { echo "test-host: FAIL: no QTWEBENGINE_CHROMIUM_FLAGS pragma in host/shell.qml" >&2; exit 1; }
CAMERA_FLAG="--use-fake-device-for-media-stream"
R=/tmp/kurashi-sb-$NAME
MOCK= HOST= HTTP=

fail() { echo "test-host: FAIL: $*" >&2; exit 1; }
ok() { echo "test-host: ok: $*"; }
ipc() { python3 -I "$TEST/ipc.py" "$@"; }
# One keyboard and one pointer for the whole run (fds 8 and 9, opened after the sandbox starts): a keyboard that goes
# away drops the window's keyboard focus, so the keys of a step reach the window the steps before put focus on.
keys() { echo "$*" >&8; sleep 0.3; }
pointer() { echo "$*" >&9; sleep 0.6; }
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
# A region of the sandbox output (grim -g "x,y WxH"): the card, its header, or a corner of it.
shot_region() {
  sleep 2
  grim -g "$2" "$SHOTS/$1.png" 2>>"$R/logs/grim.log" || fail "grim failed on $1"
  ok "shot mods/webdock/shots/$1.png"
}
# The card on the sandbox output for a phone width $1: right edge, centred, with an 8 px margin (a region).
card_region() {
  local w=$1 h x y
  h=$(( 2 * w < 1424 ? 2 * w : 1424 ))
  x=$(( 2560 - 56 - w - 8 ))
  y=$(( (1440 - h) / 2 - 8 ))
  echo "$x,$y $((w + 16))x$((h + 16))"
}
# The phone's chrome for a phone width $1 (W21), with a 4 px margin: its top (the status row and the title, 96 px) and
# its bottom (the header's controls over the home indicator, 72 px).
header_region() {
  local w=$1 h x y
  h=$(( 2 * w < 1424 ? 2 * w : 1424 ))
  x=$(( 2560 - 56 - w - 4 ))
  y=$(( (1440 - h) / 2 - 4 ))
  echo "$x,$y $((w + 8))x96"
}
footer_region() {
  local w=$1 h x y
  h=$(( 2 * w < 1424 ? 2 * w : 1424 ))
  x=$(( 2560 - 56 - w - 4 ))
  y=$(( (1440 - h) / 2 + h - 68 ))
  echo "$x,$y $((w + 8))x72"
}
# The address the pin's view logged last ("webdock-debug url <pin> <url>", KURASHI_WEBDOCK_DEBUG=1).
last_url() {
  local line
  line=$({ grep -F -- "webdock-debug url $1 " "$R/logs/host.log" || true; } | tail -1)
  echo "${line#*webdock-debug url $1 }"
}
# Waits (up to $2 seconds) until the pin's view is at an address that matches the glob $3.
wait_url() {
  local i u
  for i in $(seq $(($2 * 10))); do
    u=$(last_url "$1")
    case "$u" in $3) return 0 ;; esac
    sleep 0.1
  done
  return 1
}
# The width of the header's title the card logged last ("webdock-debug title width <px>", test-only).
last_title_width() {
  local line
  line=$({ grep -F -- "webdock-debug title width" "$R/logs/host.log" || true; } | tail -1)
  echo "${line##* }"
}
# The card's place in the usable area, as it logged it last: "x y width height usableW usableH" (test-only).
card_geometry() {
  local line
  line=$({ grep -F -- "webdock-debug card " "$R/logs/host.log" || true; } | tail -1)
  echo "${line#*webdock-debug card }" | awk '{print $1, $2, $3, $4, $5, $6}'
}
# Waits (up to $3 seconds) until the host's log holds more lines with the text $1 than the count $2.
wait_new() {
  local i
  for i in $(seq $(($3 * 10))); do
    [ "$(logs "$1")" -gt "$2" ] && return 0
    sleep 0.1
  done
  return 1
}
# A field of mod.webdock: doc_field <python expression over d> (booleans print as True and False).
doc_field() { ipc doc mod.webdock | python3 -c "import json,sys; d=json.load(sys.stdin); print($1)"; }
# Waits (up to $3 seconds) until the mod.webdock expression $1 prints the value $2.
wait_field() {
  local i v
  for i in $(seq $(($3 * 10))); do
    v=$(doc_field "$1")
    [ "$v" = "$2" ] && return 0
    sleep 0.1
  done
  return 1
}
# The pin whose card the steps show (CUR_PIN), and the card closed and opened again on it. A close that the window did
# not have is no report (K40: the engage reports are the window's keyboard focus).
CUR_PIN=
refocus() {
  local off0 on0
  off0=$(logs 'webdock.engage {"on":false}')
  ipc act webdock.collapse '{}' >/dev/null || fail "webdock.collapse refused"
  wait_new 'webdock.engage {"on":false}' "$off0" 1 || true
  on0=$(logs 'webdock.engage {"on":true}')
  ipc act webdock.open "{\"pin\":\"$CUR_PIN\"}" >/dev/null || fail "webdock.open $CUR_PIN refused"
  take_keyboard "$on0" "$CUR_PIN"
}
# The card takes the keyboard by a press on its header: an on-demand window gets the keyboard on a press, not on a map
# (the mapping focus was lost in the sandbox, run 6). The press lands on the title, away from the buttons. $1: the engage
# count before the open; $2: the pin (for the message).
take_keyboard() {
  local g cx cy aw x y
  sleep 0.6                                # the card maps (its slide is 180 ms)
  g=$(card_geometry)                       # the card in its window: x y width height, then the window's width and height
  cx=$(echo "$g" | awk '{print $1}')
  cy=$(echo "$g" | awk '{print $2}')
  aw=$(echo "$g" | awk '{print $5}')
  # The window of a card on the right edge stands strip (56) px in from the output's right edge, as wide as the card
  # and its margin (no top bar here, so its top is the output's): the card's place on the output.
  x=$(( 2560 - 56 - aw + cx ))
  y=$cy
  pointer click $((x + 110)) $((y + 18)) left
  wait_new 'webdock.engage {"on":true}' "$1" 8 || fail "the card did not take the keyboard on $2"
  sleep 0.5                                # the page takes the focus after the window does
}
# Shows a pin's card with the keyboard on its page.
open_pin() {
  CUR_PIN=$1
  refocus
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
stop_devices() {  # the run's keyboard and pointer (the helpers' own processes)
  exec 8>&- 9>&- 2>/dev/null || true
  [ -n "${KEYS_PID:-}" ] && kill "$KEYS_PID" 2>/dev/null || true
  [ -n "${PTR_PID:-}" ] && kill "$PTR_PID" 2>/dev/null || true
}
trap 'stop_devices; stop_host; [ -n "$MOCK" ] && kill "$MOCK" 2>/dev/null || true; [ -n "$HTTP" ] && kill "$HTTP" 2>/dev/null || true; "$ROOT/tools/bench/sandbox.sh" stop "$NAME" >/dev/null 2>&1 || true' EXIT
mkdir -p "$R/kurashi" "$R/logs" "$SHOTS" "$R/xdg/config" "$R/xdg/state" "$R/xdg/data" "$R/xdg/cache"
export XDG_CONFIG_HOME=$R/xdg/config XDG_STATE_HOME=$R/xdg/state XDG_DATA_HOME=$R/xdg/data XDG_CACHE_HOME=$R/xdg/cache
export KURASHI_DATA_DIR=$ROOT LC_ALL=C.UTF-8
KEYS_FIFO=$R/keys.fifo
PTR_FIFO=$R/pointer.fifo
mkfifo "$KEYS_FIFO" "$PTR_FIFO"
python3 -I "$ROOT/tools/bench/wl_keys.py" --serve < "$KEYS_FIFO" > "$R/logs/keys.log" 2>&1 &
KEYS_PID=$!
exec 8> "$KEYS_FIFO"
python3 -I "$ROOT/tools/bench/wl_pointer.py" --serve < "$PTR_FIFO" > "$R/logs/pointer.log" 2>&1 &
PTR_PID=$!
exec 9> "$PTR_FIFO"

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

# Reveal and type (B27): the card takes the keyboard by a press on its header, then the keys reach the page. A key sent
# before the window holds the keyboard is lost; this step does not test a first keystroke that comes with the reveal.
typed0=$(logs 'webdock.engage {"on":true}')
CUR_PIN=typed
ipc act webdock.open '{"pin":"typed"}' >/dev/null || fail "webdock.open typed refused"
take_keyboard "$typed0" typed
keys h e l l o space k u r a s h i
wait_log "webdock-debug typed INPUT hello kurashi" 8 || fail "the typed text did not arrive complete (see $R/logs/host.log)"
ok "typed text arrives complete (B27)"
shot phone-right

# Mobile and desktop views: the page reports its own user agent and viewport.
ipc act webdock.open '{"pin":"mail"}' >/dev/null || fail "webdock.open mail refused"
# The page is the phone's screen (W21): 412 less the phone's frame, 8 px a side in the mock's flat chrome.
wait_log "webdock-debug mail UA mail mobile=true platform=Android inner=396" 8 || fail "mobile view not sent"
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

# Edges: the card at each edge (the strip's margin, the card centred along the edge). A healthy pin other than
# `sign`: its sheet must not follow to another pin (it did, lead review W17).
for edge in left top bottom right; do
  ipc act webdock.collapse '{}' >/dev/null
  ipc act mock.webdock "{\"edge\":\"$edge\"}" >/dev/null
  ipc act webdock.open '{"pin":"typed"}' >/dev/null
  sleep 1
  [ "$edge" = right ] || shot "edge-$edge"
done
ok "edges: left, top and bottom shot; right is the phone shot above"

# Large: the card's large size, from the right edge.
ipc act webdock.size '{"size":"large"}' >/dev/null
sleep 1
shot large-right
ipc act webdock.size '{"size":"phone"}' >/dev/null

# ---- W20-webdock-host (K40, I78): the header, new tabs, home, the overflow menu, the focus and hover reports ----
# The card at 360 px, the narrowest phone width: the header keeps the title at 120 px or more (I78).
ipc act mock.webdock '{"geometry":{"width":360}}' >/dev/null || fail "mock.webdock refused the width"
open_pin opener
wait_log "webdock-debug opener PAGE opener" 8 || fail "the opener page did not load"
sleep 1
shot_region host-phone-header "$(header_region 360)"
shot_region host-phone-footer "$(footer_region 360)"
# The tooltip of the view toggle (the pointer rests on it for 400 ms): "View: mobile" over the bottom bar (W21: the
# phone's controls spread across its bottom; the view toggle is the fourth of seven, 172 px into a 344 px screen).
pointer move 2324 1036
sleep 1
shot_region host-tooltip "$(card_region 360)"
pointer move 1000 700
ok "header: the title first, quiet controls, a tooltip on the view toggle"

# New tabs, dock (the default): window.open() without window features loads in the pin's own view.
keys tab return
wait_log "webdock-debug opener PAGE other opened" 8 || fail "window.open did not load in the pin's view (new_tabs dock)"
[ "$(logs "webdock.host.new_window")" = 0 ] || fail "window.open went to the browser in dock mode"
sleep 1
shot_region host-new-tab-in-dock "$(card_region 360)"
keys ctrl+l return                        # Ctrl+L: the header, Back; Return presses it
wait_url opener 8 '*/opener.html' || fail "Back did not return to the pin's page"
ok "new tabs (dock): window.open loads in the pin's view, and Back returns to the pin's page"

# A link with target=_blank loads in the pin's view; home shows once the page has left the pin's address.
open_pin links
wait_log "webdock-debug links PAGE links" 8 || fail "the links page did not load"
keys tab return                           # the link
wait_log "webdock-debug links PAGE other blank" 8 || fail "the link did not load in the pin's view (new_tabs dock)"
wait_url links 8 '*/other.html#blank' || fail "the view is not at the link's address"
sleep 1
[ "$(last_title_width)" -ge 120 ] || fail "the title keeps $(last_title_width) px with home shown at 360 px (I78: 120)"
shot_region host-navigated-home "$(card_region 360)"
keys ctrl+l tab return                    # Ctrl+L: Back; Tab skips the Forward that is off; Return presses Home
wait_url links 8 '*/links.html' || fail "home did not return to the pin's address"
ok "new tabs (dock): a link loads in the pin's view; home shows off the address (title 120 px or more) and returns to it"

# New tabs, browser: the link goes to the default browser (webdock.host.new_window); the page stays where it is.
ipc act mock.webdock '{"new_tabs":"browser"}' >/dev/null || fail "mock.webdock refused new_tabs"
open_pin linkb
wait_log "webdock-debug linkb PAGE links" 8 || fail "the linkb page did not load"
keys tab return                           # the link, in browser mode
wait_log 'webdock-debug sent webdock.host.new_window {"pin":"linkb","url":"file://' 8 || fail "a link in browser mode did not go to the browser"
wait_url linkb 2 '*/links.html' || fail "a link in browser mode changed the page"
ipc act mock.webdock '{"new_tabs":"dock"}' >/dev/null || fail "mock.webdock refused new_tabs"
ok "new tabs (browser): the link goes to webdock.host.new_window, and the page stays"

# The overflow menu from the keyboard: Replace pin with this page sends webdock.retarget with the page's address.
open_pin links
keys tab return                           # the link, in the dock again (a new document: the link is the first stop)
wait_url links 8 '*/other.html#blank' || fail "the link did not load in the dock again"
keys ctrl+l tab tab tab tab tab return    # Back; Tab over Home, Reload, View and Size to More (Forward is off); Return opens it
sleep 1
shot_region host-overflow-menu "$(card_region 360)"
keys tab return                           # Replace pin with this page
wait_log 'webdock-debug sent webdock.retarget {"pin":"links","url":"file://' 8 || fail "replace pin did not send webdock.retarget"
wait_field "[p for p in d['pins'] if p['id']=='links'][0]['target']" "file://$PAGES/other.html#blank" 8 \
  || fail "the pin's target did not become the page's address (webdock.retarget)"
wait_url links 2 '*/other.html#blank' || fail "replace pin moved the view"
ok "overflow menu: Replace pin with this page sends webdock.retarget; the pin's target becomes the page's address"

# Focus (K40): the window's keyboard focus is the engage report, and the dock records it as engaged. A card closed
# without focus leaves the dock hidden at once (the mock, as the daemon: an engage off is a leave).
off0=$(logs 'webdock.engage {"on":false}')
ipc act webdock.collapse '{}' >/dev/null || fail "webdock.collapse refused"
wait_new 'webdock.engage {"on":false}' "$off0" 8 || fail "the card's close was not reported (engage off)"
wait_field 'd["mode"]' hidden 4 || fail "the dock stayed open after the card lost the keyboard"
open_pin links
wait_field 'd.get("engaged", False)' True 4 || fail "the dock did not record the card's keyboard focus (engaged)"
ok "engage: the card's keyboard focus is reported on the open and off the close; the dock records engaged"
# Hover (K40): an engaged dock holds the card when the pointer leaves it. Not engaged, the card's margin (geometry.grace,
# 24 px on the side away from the strip: the surface starts 24 px left of x 2144) keeps the pointer in the card, and a
# leave beyond it hides the dock at once (no timers in the mock; the daemon's hysteresis is the margin).
pointer move 1000 700                     # out of the card: the press that took the keyboard left the pointer on it
sleep 1
in0=$(logs 'webdock.hover {"part":"card","inside":true')
out0=$(logs 'webdock.hover {"part":"card","inside":false')
pointer move 2300 720
wait_new 'webdock.hover {"part":"card","inside":true' "$in0" 8 || fail "the pointer's entry into the card was not reported"
pointer move 2100 720
wait_new 'webdock.hover {"part":"card","inside":false' "$out0" 8 || fail "the pointer's leave was not reported"
sleep 1
[ "$(doc_field 'd["mode"]')" = extended ] || fail "a leave hid the card while it was engaged"
ipc act mock.webdock '{"engaged":false}' >/dev/null || fail "mock.webdock refused engaged"
in1=$(logs 'webdock.hover {"part":"card","inside":true')
pointer move 2300 720
wait_new 'webdock.hover {"part":"card","inside":true' "$in1" 8 || fail "the pointer's second entry was not reported"
pointer move 2130 720                     # inside the 24 px margin: no leave
sleep 1
[ "$(doc_field 'd["mode"]')" = extended ] || fail "the margin hid the card"
pointer move 2100 720                     # beyond the margin: a leave, not engaged, not pinned
wait_field 'd["mode"]' hidden 4 || fail "a leave beyond the margin did not hide the card"
ok "hover: an engaged card holds on a leave; the 24 px margin keeps the card; a leave beyond it hides it at once"
open_pin links                            # the card is shown again for the large and corner shots

# Large (the header across the output) and the bottom corners of the card (the page clipped to the radius, I78).
ipc act webdock.size '{"size":"large"}' >/dev/null || fail "webdock.size large refused"
sleep 1
shot_region host-large-header "196,4 2312x44"
ipc act webdock.size '{"size":"phone"}' >/dev/null || fail "webdock.size phone refused"
sleep 1
shot_region host-rounded-bottom "2136,1040 376x56"

# A top bar (sway's bar: a layer surface with an exclusive zone, 30 px here) stays clear of the card: the card is centred
# in the usable area below it, and a phone is min(2 × width, usable − 2 gaps) tall (K40, the lead's rule). The sway config
# gets the bar and is reloaded; the base config goes back after the shot.
cp "$R/sway.conf" "$R/sway.conf.base"
printf 'bar {\n  position top\n  height 30\n  colors {\n    background #101014\n  }\n}\n' >> "$R/sway.conf"
swaymsg reload >/dev/null || fail "sway did not reload with the top bar (see $R/sway.log)"
sleep 2
read -r cx cy cw ch aw ah <<< "$(card_geometry)"
[ "$ah" = 1410 ] || fail "the usable height is $ah under a 30 px top bar (expected 1410; see $R/sway.log)"
[ "$cy" = $(( (ah - ch + 1) / 2 )) ] || fail "the card (y $cy, height $ch) is not centred in the usable area ($ah)"
shot host-top-bar
ipc act webdock.size '{"size":"large"}' >/dev/null || fail "webdock.size large refused (top bar)"
sleep 1
read -r cx cy cw ch aw ah <<< "$(card_geometry)"
[ "$cy" = 8 ] && [ "$ch" = $(( ah - 16 )) ] || fail "the large card (y $cy, height $ch) does not fill the usable area below the bar"
ipc act webdock.size '{"size":"phone"}' >/dev/null || fail "webdock.size phone refused (top bar)"
cp "$R/sway.conf.base" "$R/sway.conf"
swaymsg reload >/dev/null || fail "sway did not reload without the top bar"
sleep 1
ok "top bar: the card is centred in the usable area below it (phone), and large fills it"
ipc act mock.webdock '{"geometry":{"width":412}}' >/dev/null || fail "mock.webdock refused the width"
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
# The header in Japanese: a link opened in the pin's view (Home shown), the overflow menu opened from the keyboard.
open_pin links
wait_log "webdock-debug links PAGE links" 8 || fail "the links page did not load (ja)"
keys tab return
wait_url links 8 '*/other.html#blank' || fail "the link did not load (ja)"
keys ctrl+l tab tab tab tab tab return
sleep 1
shot_region host-ja "$(card_region 412)"
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
