#!/usr/bin/env bash
# The web dock's page styles (W69, I468; docs/ux/webdock.md "Page styles"), in a headless sandbox against kurashi-mock
# with a still file:// page (no network, K37; no caret or timer, so a card at rest draws nothing). Motion off (the
# theme's motion profile `none`) except the step that runs the notebook's page turn. Steps:
#   1 each style (phone, notebook, plain) draws the page with a pin open;
#   2 switching the style while the page is open keeps the page: no new load report, the page's own load line once;
#   3 the large size: the phone becomes a tablet (wider than tall) and back, in every style, the page kept;
#   4 the notebook's coil is on the dock's side at a right, a left, a top and a bottom edge;
#   5 the notebook's page turn runs (the sheet's layer comes and goes) with motion on;
#   6 idle: 0 surface commits in 5 s with the page open and still, in each style;
#   7 no QML error or warning in the host's log.
#   timeout 600 mods/webdock/test/test-styles.sh [sandbox-name]
#   KURASHI_BIN_DIR=<dir with kurashi-mock> (default: ${CARGO_TARGET_DIR:-target}/debug)
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
NAME=${1:-${KURASHI_SB_PREFIX:-}webdock-styles}
BIN=${KURASHI_BIN_DIR:-${CARGO_TARGET_DIR:-$ROOT/target}/debug}
TEST=$ROOT/mods/webdock/test
PAGES=file://$TEST/pages
PRAGMA_FLAGS=$(sed -n 's/^\/\/@ pragma DefaultEnv QTWEBENGINE_CHROMIUM_FLAGS = //p' "$ROOT/mods/webdock/host/shell.qml")
[ -n "$PRAGMA_FLAGS" ] || { echo "test-styles: FAIL: no QTWEBENGINE_CHROMIUM_FLAGS pragma in host/shell.qml" >&2; exit 1; }
R=/tmp/kurashi-sb-$NAME
MOCK= HOST=

fail() { echo "test-styles: FAIL: $*" >&2; exit 1; }
ok() { echo "test-styles: ok: $*"; }
ipc() { python3 -I "$TEST/ipc.py" "$@"; }
logs() { grep -c -F -- "$1" "$R/logs/host.log" || true; }
has() { grep -q -F -- "$1" "$R/logs/host.log"; }
# Waits (up to $2 seconds) until the host's log holds the text $1.
wait_log() {
  local i
  for i in $(seq $(($2 * 10))); do has "$1" && return 0; sleep 0.1; done
  return 1
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
# The last line of the host's log that starts with "webdock-debug $1", less that prefix.
last_debug() {
  local line
  line=$({ grep -F -- "webdock-debug $1 " "$R/logs/host.log" || true; } | tail -1)
  echo "${line#*webdock-debug $1 }"
}
qml_problems() {
  grep -E -- 'WARN.{0,12}(scene|qml)|caused by|is not a type|is not defined|ReferenceError|TypeError|Binding loop|Unable to assign|Cannot assign|Failed to load configuration|qml: .*[Ww]arning|QML .*: .*(Error|error)|Cannot read property|Cannot call method|unknown is not|Type .* unavailable' "$R/logs/host.log" || true
}
# A look at the screen (STYLES_PEEK=<dir>: a development aid; the review shots are taken on niri, shots-styles.sh).
peek() { [ -z "${STYLES_PEEK:-}" ] || { sleep 0.8; grim -o HEADLESS-1 "$STYLES_PEEK/$1.png" 2>/dev/null || true; }; }
mock_dock() { ipc act mock.webdock "$1" >/dev/null || fail "mock.webdock $1 refused"; }
motion() { ipc act mock.doc "{\"doc\":\"theme\",\"patch\":{\"tokens\":{\"motion.profile\":\"$1\"}}}" >/dev/null || fail "mock.doc theme refused"; }

start_mock() {
  "$BIN/kurashi-mock" --outputs HEADLESS-1 --socket "$KURASHI_SOCKET" >> "$R/logs/mock.log" 2>&1 &
  MOCK=$!
  local i
  for i in $(seq 100); do
    [ -S "$KURASHI_SOCKET" ] && ipc doc svc.clock >/dev/null 2>&1 && return 0
    sleep 0.1
  done
  fail "the mock did not come up (see $R/logs/mock.log)"
}
stop_host() {
  if [ -n "$HOST" ] && kill -0 "$HOST" 2>/dev/null; then
    kill "$HOST" 2>/dev/null || true
    wait "$HOST" 2>/dev/null || true
  fi
  HOST=
}
start_host() {  # extra environment (KEY=VALUE) as arguments
  stop_host
  local before
  before=$(grep -c -F -- 'webdock-host' "$R/logs/mock.log" || true)
  : > "$R/logs/host.log"
  env QTWEBENGINE_CHROMIUM_FLAGS="$PRAGMA_FLAGS" KURASHI_SCOPE_MOD=webdock KURASHI_SCOPE_TOKEN=6f1c2a9e4b7d0835 \
    KURASHI_CLIENT=webdock-host KURASHI_WEBDOCK_DEBUG=1 KURASHI_WEBDOCK_HOLD="$R/hold" "$@" \
    qs-webengine -p "$ROOT/mods/webdock/host/shell.qml" > "$R/logs/host.log" 2>&1 &
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
commits() { grep -c -E -- 'wl_surface@[0-9]+\.commit' "$R/logs/host.log" || true; }
# A style is in effect once the card has logged it (absent page_style = phone, logged only on a change).
set_style() {
  local n
  n=$(logs "webdock-debug style $1")
  mock_dock "{\"page_style\":\"$1\"}"
  [ "$1" = "$CUR_STYLE" ] || wait_new "webdock-debug style $1" "$n" 5 || fail "the card did not take the style $1"
  CUR_STYLE=$1
}
CUR_STYLE=phone

"$ROOT/tools/bench/sandbox.sh" stop "$NAME" >/dev/null 2>&1 || true
rm -rf "$R"
eval "$("$ROOT/tools/bench/sandbox.sh" start "$NAME")"
trap 'stop_host; [ -n "$MOCK" ] && kill "$MOCK" 2>/dev/null || true; "$ROOT/tools/bench/sandbox.sh" stop "$NAME" >/dev/null 2>&1 || true' EXIT
mkdir -p "$R/logs" "$R/xdg/config" "$R/xdg/state" "$R/xdg/data" "$R/xdg/cache"
export XDG_CONFIG_HOME=$R/xdg/config XDG_STATE_HOME=$R/xdg/state XDG_DATA_HOME=$R/xdg/data XDG_CACHE_HOME=$R/xdg/cache
export KURASHI_DATA_DIR=$ROOT LC_ALL=C.UTF-8
: > "$R/hold"

start_mock
motion none
mock_dock "{\"pins\":[{\"id\":\"still\",\"kind\":\"web\",\"title\":\"Still\",\"target\":\"$PAGES/still.html#still\",\"view\":\"mobile\",\"profile\":\"still\"}],\"edge\":\"right\",\"size\":\"phone\"}"
start_host WAYLAND_DEBUG=1
ok "the host said hello"

# ---- 1, 2: each style draws the page; a style change keeps it ----
ipc act webdock.open '{"pin":"still"}' >/dev/null || fail "webdock.open still refused"
wait_log 'webdock.host.loaded {"pin":"still"}' 20 || fail "the still page never loaded (see $R/logs/host.log)"
wait_log "STILL still loaded" 5 || fail "the still page's own load line is missing"
loads0=$(logs 'webdock.host.loaded {"pin":"still"}')
own0=$(logs "STILL still loaded")
for s in notebook plain phone notebook; do
  set_style "$s"
  sleep 1
  [ "$(logs 'webdock.host.loaded {"pin":"still"}')" = "$loads0" ] || fail "the style $s reloaded the page"
  [ "$(logs "STILL still loaded")" = "$own0" ] || fail "the style $s re-made the page"
  peek "style-$s"
  ok "style $s: the page is drawn and kept (1 load)"
done

# ---- 3: the large size in every style; the phone's is a tablet ----
for s in phone notebook plain; do
  set_style "$s"
  n=$(logs "webdock-debug wide 1 ")
  ipc act webdock.size '{"size":"large"}' >/dev/null || fail "webdock.size large refused"
  wait_new "webdock-debug wide 1 " "$n" 8 || fail "$s: the large size never came to rest"
  read -r _ w h <<< "$(last_debug wide)"
  peek "large-$s"
  [ "$w" -gt "$h" ] || fail "$s: large is $w x $h, not wider than tall"
  n=$(logs "webdock-debug wide 0 ")
  ipc act webdock.size '{"size":"phone"}' >/dev/null || fail "webdock.size phone refused"
  wait_new "webdock-debug wide 0 " "$n" 8 || fail "$s: the phone size never came back"
  read -r _ w2 h2 <<< "$(last_debug wide)"
  [ "$w2" -lt "$h2" ] || fail "$s: the phone size is $w2 x $h2, not taller than wide"
  [ "$(logs 'webdock.host.loaded {"pin":"still"}')" = "$loads0" ] || fail "$s: the size change reloaded the page"
  ok "$s: large is $w x $h (wider than tall), phone $w2 x $h2, the page kept"
done

# ---- 4: the notebook's coil is on the dock's side ----
set_style notebook
for e in left top bottom right; do
  n=$(logs "webdock-debug coil $e $e")
  mock_dock "{\"edge\":\"$e\"}"
  wait_new "webdock-debug coil $e $e" "$n" 5 || fail "at a $e edge the coil is not on the $e (last: $(last_debug coil))"
  peek "notebook-$e"
  ok "notebook at a $e edge: the coil on the $e"
done
[ "$(logs 'webdock.host.loaded {"pin":"still"}')" = "$loads0" ] || fail "an edge change reloaded the page"

# ---- 5: the page turn, with motion on ----
motion calm
sleep 0.5
n=$(logs "motion: sheet layer up")
ipc act webdock.collapse '{}' >/dev/null
sleep 2
ipc act webdock.open '{"pin":"still"}' >/dev/null
wait_new "motion: sheet layer up" "$n" 5 || fail "the notebook opened without its page turn"
r=$(logs "motion: sheet layer")
wait_log "released" 6 || fail "the page turn's layer was not released"
ok "notebook: the page turns over the binding and its layer goes at rest"
if [ -n "${STYLES_PEEK:-}" ]; then
  for p in 0.2 0.45 0.7 0.9; do echo "open $p" > "$R/hold"; peek "turn-$p"; done
  : > "$R/hold"
fi
motion none
sleep 1

# ---- 6: idle, 0 commits with the page open and still ----
for s in phone notebook plain; do
  set_style "$s"
  sleep 2
  c0=$(commits)
  sleep 5
  c1=$(commits)
  [ "$c0" = "$c1" ] || fail "$s: the card committed $((c1 - c0)) frames in 5 s at rest"
  ok "$s: 0 commits in 5 s with the page open and still"
done

# ---- 7: no QML problem ----
bad=$(qml_problems)
[ -z "$bad" ] || fail "QML problems in the host log:
$bad"
ok "no QML error or warning in the host's log"
echo "test-styles: PASS"
