#!/usr/bin/env bash
# Toasts and the notification centre out of the bar (W34, docs/ux/motion.md), invisibly: the REAL kurashid and the REAL
# Quickshell frontend in the headless sway sandbox; notifications go only to the sandbox's own session bus (gdbus).
# Per look x profile x bar edge (MORPH_CASES):
#   1. a toast buds off the bar under the island: grims at TOAST_AT ms (40 120 250 320 400) after the Notify call; a second
#      toast pushes the first down (grims at 120 250); the stack at rest; one dismissed by the daemon drifts off (120);
#      the close control of the last one (a click) flicks it away (grims ~100 and ~200 ms after the click);
#   2. (between the rest and the drift) the notification centre grows out of the island pill: grims at MORPH_AT ms (40 120 250) after
#      `notifications.center`, at rest, and at 40 120 after `ui.close`;
#   3. I148 (first case only): no toast window while the right sidebar is open on the output (a toast sent then stays
#      hidden), and the toast comes back once the sidebar closes;
#   4. Ma (IDLE=0 skips it): with WAYLAND_DEBUG on the frontend, no Wayland commit in 5 s with the launcher open at rest
#      (but its caret's blink), a toast at rest, the centre open at rest, and none in 10 s once all three are gone again.
# The motion profile in effect is checked first (the theme document's `motion.profile`). Any FAIL, QML error or kurashid
# panic makes the run exit 1.
# Shots: frontend/shots/morph/toast-<look>-<profile>-<edge>-{bud-40,…,push-120,push-250,rest,drift-120,flick-800,flick-900}.png,
#        frontend/shots/morph/notifications-<look>-<profile>-<edge>-{open-40,open-120,open-250,rest,close-40,close-120}.png,
#        frontend/shots/morph/toast-i148-{sidebar,back}.png.
#   KURASHI_RENDER_NODE=/dev/dri/renderD128 KURASHI_BIN_DIR=<dir with kurashid and kurashi> \
#     timeout 900 nix develop -c frontend/test-toasts.sh [sandbox-name]
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
NAME=${1:-w34-surf-toasts}   # unique per run: other runs stop any sandbox that shares a name
BIN=${KURASHI_BIN_DIR:-${CARGO_TARGET_DIR:-$ROOT/target}/debug}
OUT=$ROOT/frontend/shots/morph
AT=${MORPH_AT:-40 120 250}
TOAST_AT=${TOAST_AT:-40 120 250 320 400}
MORPH_CASES=${MORPH_CASES:-washi:calm:top washi:calm:bottom washi:lively:top sekai:lively:top sekai:lively:bottom sekai:calm:top kami:calm:top kami:calm:bottom kami:lively:top sekai:none:top}
mkdir -p "$OUT"
FAILS=0
CHECKS=0
fail() { echo "test-toasts: $*" >&2; exit 1; }
check() { # check <0|1> <label>
  CHECKS=$((CHECKS + 1))
  if [ "$1" = 1 ]; then echo "ok: $2"; else echo "FAIL: $2"; FAILS=$((FAILS + 1)); fi
}

eval "$("$ROOT/tools/bench/sandbox.sh" start "$NAME")"
R=$XDG_RUNTIME_DIR
W=$R/work
mkdir -p "$W" "$R/kurashi"
cp "$BIN/kurashid" "$BIN/kurashi" "$W/"
case "${DBUS_SESSION_BUS_ADDRESS:-}" in *"$R"*) ;; *) fail "no sandbox session bus: notifications would reach the real one" ;; esac
for _ in $(seq 150); do timeout 5 swaymsg -t get_outputs >/dev/null 2>&1 && break; sleep 0.2; done

DPID=""
SHPID=""
stop_daemon() { if [ -n "$DPID" ]; then kill "$DPID" 2>/dev/null || true; wait "$DPID" 2>/dev/null || true; fi; DPID=""; }
stop_shell() { if [ -n "$SHPID" ]; then kill "$SHPID" 2>/dev/null || true; wait "$SHPID" 2>/dev/null || true; fi; SHPID=""; }
cleanup() {
  stop_shell
  stop_daemon
  if [ -n "${MORPH_LOG:-}" ]; then cp "$R/qs.log" "$MORPH_LOG" 2>/dev/null || true; fi
  "$ROOT/tools/bench/sandbox.sh" stop "$NAME" >/dev/null || true
}
trap cleanup EXIT

export XDG_CONFIG_HOME=$R/xdg/config XDG_STATE_HOME=$R/xdg/state XDG_DATA_HOME=$R/xdg/data XDG_CACHE_HOME=$R/xdg/cache
export KURASHI_DATA_DIR=$ROOT LC_ALL=C.UTF-8 KURASHI_MORPH_DEBUG=1
K() { timeout 10 "$W/kurashi" "$@"; }
ui() { K sub runtime.ui --count 0 --json | jq -c '.data'; }
# notify <app> <summary> <body> [timeout ms]: one notification on the sandbox's bus; prints its id.
notify() {
  timeout 10 gdbus call --session --dest org.freedesktop.Notifications --object-path /org/freedesktop/Notifications \
    --method org.freedesktop.Notifications.Notify "$1" 0 "" "$2" "$3" '[]' '{}' "${4:-8000}" | grep -oE '[0-9]+' | tail -1
}
start_all() { # start_all <look> [config line ...]
  stop_shell
  stop_daemon
  rm -rf "$R/xdg"
  mkdir -p "$XDG_CONFIG_HOME/kurashi" "$XDG_STATE_HOME" "$XDG_DATA_HOME" "$XDG_CACHE_HOME"
  { printf 'theme.style = "%s"\n' "$1"; shift; printf '%s\n' "$@"; } > "$XDG_CONFIG_HOME/kurashi/config.toml"
  rm -f "$KURASHI_SOCKET"
  env DBUS_SYSTEM_BUS_ADDRESS="unix:path=$R/no-system-bus" PULSE_SERVER="unix:$R/no-pulse/native" \
    PULSE_RUNTIME_PATH="$R/no-pulse" "$W/kurashid" >> "$R/kurashid.log" 2>&1 &
  DPID=$!
  for _ in $(seq 100); do [ -S "$KURASHI_SOCKET" ] && K ping >/dev/null 2>&1 && break; sleep 0.1; done
  K ping >/dev/null 2>&1 || fail "kurashid did not come up (see $R/kurashid.log)"
  swaymsg output '*' bg '#8fb8c8' solid_color >/dev/null 2>&1 || true
  : > "$R/qs.case.log"
  # QS_ENV: extra environment for the frontend only (the idle phase: WAYLAND_DEBUG=client).
  env -u KURASHI_SOCKET ${QS_ENV:-} qs -p "${FRONTEND_DIR:-$ROOT/frontend}" >> "$R/qs.case.log" 2>&1 &
  SHPID=$!
  for _ in $(seq 100); do grep -q 'hello.*frontend' "$R/kurashid.log" && break; sleep 0.1; done
  sleep "${SHELL_WAIT:-4}"
  # The notification server is the daemon's (it owns the name on the sandbox's bus).
  for _ in $(seq 50); do
    timeout 5 gdbus call --session --dest org.freedesktop.DBus --object-path /org/freedesktop/DBus \
      --method org.freedesktop.DBus.NameHasOwner org.freedesktop.Notifications 2>/dev/null | grep -q true && break
    sleep 0.1
  done
}
# burst <file prefix> <ms list> <crop> <command ...>: the command, and one grim per offset, each on its own clock.
burst() {
  local pre=$1 at=$2 crop=$3 gp=() t t0 cp
  shift 3
  t0=$(date +%s%N)
  "$@" >/dev/null &
  cp=$!
  for t in $at; do
    ( now=$(date +%s%N); w=$(( t - (now - t0) / 1000000 )); [ "$w" -gt 0 ] && sleep "$(printf '%d.%03d' $((w / 1000)) $((w % 1000)))"
      grim -g "$crop" "$pre-$t.png" ) &
    gp+=("$!")
  done
  for p in "${gp[@]}"; do wait "$p" || fail "grim failed ($pre)"; done
  wait "$cp" || fail "command failed ($pre: $*)"
}
last_window() { grep -oE 'toasts-window (up|down)' "$R/qs.case.log" | tail -1; }
wait_window() { # wait_window <up|down>
  for _ in $(seq 30); do [ "$(last_window)" = "toasts-window $1" ] && return 0; sleep 0.2; done
  return 1
}
qml_errors() {
  cat "$R/qs.case.log" >> "$R/qs.log"
  if grep -E 'ReferenceError|TypeError|binding loop|is not a function|is not defined|is not a type|Cannot assign' "$R/qs.case.log" \
      | grep -v 'Unable to assign \[undefined\]' >/dev/null; then
    echo "QML errors: $(grep -E 'ReferenceError|TypeError|binding loop|is not a function|is not defined|is not a type|Cannot assign' "$R/qs.case.log" | head -5)" >&2
    FAILS=$((FAILS + 1))
  fi
  if grep -Ei 'Toasts.qml|NotificationCenter.qml|NotificationCard.qml|BarMorph.qml' "$R/qs.case.log" | grep -Eiq 'warn|error'; then
    echo "QML warnings: $(grep -Ei 'Toasts.qml|NotificationCenter.qml|NotificationCard.qml|BarMorph.qml' "$R/qs.case.log" | head -5)" >&2
    FAILS=$((FAILS + 1))
  fi
}

: > "$R/kurashid.log"; : > "$R/qs.log"
FIRST=1
for CASE in $MORPH_CASES; do
  IFS=: read -r LOOK PROFILE EDGE <<< "$CASE"
  echo "== $LOOK $PROFILE $EDGE"
  start_all "$LOOK" "theme.motion.profile = \"$PROFILE\"" "bar.edge = \"$EDGE\""
  got=$(K sub theme --count 0 --json | jq -r '.data.tokens["motion.profile"]')
  check "$([ "$got" = "$PROFILE" ] && echo 1 || echo 0)" "$LOOK the motion profile in effect is $PROFILE ($got)"
  crop="880,0 800x720"
  [ "$EDGE" = bottom ] && crop="880,720 800x720"
  base=$OUT/toast-$LOOK-$PROFILE-$EDGE
  # A first toast and its dismissal: the first of a fresh shell also loads what the cards need.
  id=$(notify Warmup "Warming up" "…" 8000)
  wait_window up || true
  sleep 1.2
  K act notify.dismiss "{\"id\":$id}" >/dev/null
  wait_window down || true
  sleep 0.5

  # 1. A toast buds off the bar, a second pushes it down, the stack at rest, one drifts off.
  burst "$base-bud" "$TOAST_AT" "$crop" notify Calendar "Standup in 5 minutes" "Room 3 · bring the notes from Monday" 20000
  check "$(wait_window up && echo 1 || echo 0)" "$LOOK $PROFILE $EDGE: the toast window came up"
  sleep 1.2
  burst "$base-push" "120 250" "$crop" notify Mail "Aiko Tanaka" "The photos from Saturday are in the shared folder." 20000
  sleep 1.5
  grim -g "$crop" "$base-rest.png"

  # 2. The notification centre out of the island.
  nbase=$OUT/notifications-$LOOK-$PROFILE-$EDGE
  burst "$nbase-open" "$AT" "$crop" K act notifications.center
  sleep 1.5
  grim -g "$crop" "$nbase-rest.png"
  check "$(ui | jq -e '.panel == "notifications"' >/dev/null && echo 1 || echo 0)" "$LOOK $PROFILE $EDGE: the centre is open"
  check "$(last_window | grep -q down && echo 1 || echo 0)" "$LOOK $PROFILE $EDGE: no toast window while the centre is open"
  burst "$nbase-close" "40 120" "$crop" K act ui.close
  check "$(wait_window up && echo 1 || echo 0)" "$LOOK $PROFILE $EDGE: the toasts came back after the centre closed"
  sleep 0.8

  first=$(K sub svc.notifications --count 0 --json | jq -r '.data.toasts | min')
  burst "$base-drift" "120" "$crop" K act notify.dismiss "{\"id\":$first}"
  sleep 1
  toasts=$(K sub svc.notifications --count 0 --json | jq -c '.data.toasts')
  check "$(echo "$toasts" | jq -e 'length == 1' >/dev/null && echo 1 || echo 0)" "$LOOK $PROFILE $EDGE: one toast left after the dismissal ($toasts)"
  # The close control of the one left: it is flicked away (the click lands ~0.7 s after the pointer helper starts).
  # Its place from the frontend's log (`toast-card <id> <top from the bar's edge> <height>`); the close control's centre lies
  # pad + 12 px below the card's top, pad + 12 px in from its right edge.
  pad=$(K sub theme --count 0 --json | jq -r '.data.tokens["space.md"] // 12')
  read -r cid ctop ch <<< "$(grep -oE 'toast-card [0-9]+ [0-9]+ [0-9]+' "$R/qs.case.log" | tail -1 | cut -d' ' -f2-)"
  cy=$(( ctop + pad + 12 ))
  [ "$EDGE" = bottom ] && cy=$(( 1440 - ctop - ch + pad + 12 ))
  burst "$base-flick" "800 900" "$crop" timeout 20 python3 -I "$ROOT/tools/bench/wl_pointer.py" click $(( 1280 + 170 - pad - 12 )) "$cy" left
  sleep 1
  check "$(K sub svc.notifications --count 0 --json | jq -e '.data.toasts | length == 0' >/dev/null && echo 1 || echo 0)" "$LOOK $PROFILE $EDGE: the close control dismissed the last toast"


  # 3. I148: the right sidebar open on this output hides the toasts; they come back after it closes.
  if [ "$FIRST" = 1 ]; then
    K act notify.dismiss '{}' >/dev/null
    wait_window down || true
    K act sidebar.toggle '{"side":"right","output":"HEADLESS-1"}' >/dev/null
    sleep 1
    notify Battery "Battery low" "12 % left" 20000 >/dev/null
    sleep 1.5
    check "$(ui | jq -e '.sidebar == "right"' >/dev/null && echo 1 || echo 0)" "I148: the right sidebar is open"
    check "$(K sub svc.notifications --count 0 --json | jq -e '.data.toasts | length == 1' >/dev/null && echo 1 || echo 0)" "I148: the daemon shows the toast"
    check "$([ "$(last_window)" = "toasts-window down" ] && echo 1 || echo 0)" "I148: no toast window while the right sidebar is open ($(last_window))"
    grim -g "1280,0 1280x720" "$OUT/toast-i148-sidebar.png"
    K act sidebar.toggle '{"side":"right","output":"HEADLESS-1"}' >/dev/null
    check "$(wait_window up && echo 1 || echo 0)" "I148: the toast came back once the sidebar closed"
    sleep 1.2
    grim -g "$crop" "$OUT/toast-i148-back.png"
    FIRST=0
  fi
  stop_shell
  qml_errors
done
# 4. Ma: nothing draws while a surface rests, nor after it has gone.
if [ "${IDLE:-1}" = 1 ]; then
  echo "== idle"
  QS_ENV="WAYLAND_DEBUG=client" start_all washi
  commits() { tail -c +"$(( $1 + 1 ))" "$R/qs.case.log" | grep -c 'wl_surface#[0-9]*\.commit(' || true; }
  quiet() { # quiet <seconds> <label> [max]: at most max (0) commits in that window (one retry: the clock's minute may tick)
    local s c m=${3:-0}
    for _ in 1 2; do
      s=$(stat -c %s "$R/qs.case.log"); sleep "$1"; c=$(commits "$s")
      [ "$c" -le "$m" ] && break
    done
    check "$([ "$c" -le "$m" ] && echo 1 || echo 0)" "idle: $2 ($c commits in $1 s, at most $m)"
  }
  K act launcher.toggle >/dev/null; sleep 2.5
  # The open launcher's caret blinks (two frames a second); nothing else moves.
  quiet 5 "the launcher open at rest" 11
  K act ui.close >/dev/null; sleep 1.5
  notify Calendar "Standup" "Room 3" 30000 >/dev/null; sleep 2.5
  quiet 5 "a toast at rest"
  K act notifications.center >/dev/null; sleep 2.5
  quiet 5 "the centre open at rest"
  K act ui.close >/dev/null; sleep 0.5
  K act notify.dismiss '{}' >/dev/null; sleep 2
  quiet 10 "all three gone"
  stop_shell
  # The debug output is kept only when asked (IDLE_LOG=<file>; it is large).
  [ -n "${IDLE_LOG:-}" ] && cp "$R/qs.case.log" "$IDLE_LOG"
  : > "$R/qs.case.log"
fi
stop_shell
stop_daemon

if grep -q panicked "$R/kurashid.log" 2>/dev/null; then
  echo "kurashid panicked (see $R/kurashid.log)" >&2
  FAILS=$((FAILS + 1))
fi
echo "checks: $((CHECKS - FAILS < 0 ? 0 : CHECKS - FAILS)) of $CHECKS"
[ "$FAILS" -eq 0 ] || fail "$FAILS failure(s); logs in $R, screenshots in $OUT"
echo "ok: screenshots in $OUT"
