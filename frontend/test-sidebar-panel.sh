#!/usr/bin/env bash
# The edge sidebars (card W29, docs/ux/sidebar.md), invisibly (headless sway sandbox), with the REAL kurashid:
#   1. closed = no sidebar window; `sidebar.toggle {side: right}` under a top bar: the window spans the bar's bottom → the
#      screen's bottom (its height is the output's less the bar's zone, its bottom row is drawn), flush right, 420 px;
#      Esc (after a click gives it the keyboard) closes it and the window goes; opening the launcher closes it;
#   2. floating style: the column is inset by the theme's gap (the outermost column of pixels is the desk);
#   3. a left bar: the right sidebar spans the whole height; with `sidebar.from_bar` the bar's quick button opens it;
#   4. the left sidebar with the AI mod on: its tab shows the AI panel (no Ollama in the sandbox: the mod's own state);
#   5. a 1280×720 output: the column fits (the notifications shrink, the column never overflows);
#   6. shots: right panel and floating under washi, sekai, win95 and glass; left panel under washi.
#   nix develop -c frontend/test-sidebar-panel.sh [sandbox-name]
# Binaries: kurashid and kurashi from $KURASHI_BIN_DIR (default $CARGO_TARGET_DIR/debug or target/debug).
# Shots in frontend/shots/sidebar/<style>/. On a hybrid laptop export KURASHI_RENDER_NODE first.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
NAME=${1:-w29-sb-test}
BIN=${KURASHI_BIN_DIR:-${CARGO_TARGET_DIR:-$ROOT/target}/debug}
OUT=$ROOT/frontend/shots/sidebar
DECORS=${SIDEBAR_DECORS:-washi sekai win95 glass}
mkdir -p "$OUT"
fail() { echo "test-sidebar-panel: FAIL: $*" >&2; exit 1; }

eval "$("$ROOT/tools/bench/sandbox.sh" start "$NAME")"
R=$XDG_RUNTIME_DIR
W=$R/work
mkdir -p "$W" "$R/kurashi"
cp "$BIN/kurashid" "$BIN/kurashi" "$W/"

pids=()
PTR_PID=""
stop_phase() {  # kills only the processes this script started
  stop_pointer
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

rm -rf "$R/xdg"
export XDG_CONFIG_HOME=$R/xdg/config XDG_STATE_HOME=$R/xdg/state \
       XDG_DATA_HOME=$R/xdg/data XDG_CACHE_HOME=$R/xdg/cache KURASHI_DATA_DIR=$ROOT LC_ALL=C.UTF-8
mkdir -p "$XDG_CONFIG_HOME/kurashi" "$XDG_STATE_HOME" "$XDG_DATA_HOME" "$XDG_CACHE_HOME"
K() { timeout 10 "$W/kurashi" "$@"; }
BG='#8fb8c8'
swaymsg output '*' bg "$BG" solid_color >/dev/null 2>&1 || true
dims() {
  SW=$(swaymsg -t get_outputs -r | jq -r '.[] | select(.name == "HEADLESS-1") | .rect.width')
  SH=$(swaymsg -t get_outputs -r | jq -r '.[] | select(.name == "HEADLESS-1") | .rect.height')
}
dims

# Whether a pixel is the desk: "desk" or "ink" (P6 PPM of one pixel from grim).
cat > "$W/px.py" <<'PY'
import sys
ppm, bg = sys.argv[1], sys.argv[2]
B = tuple(int(bg.lstrip("#")[i:i + 2], 16) for i in (0, 2, 4))
data = open(ppm, "rb").read()
fields, i = [], 0
while len(fields) < 4:
    while data[i:i + 1].isspace():
        i += 1
    j = i
    while not data[j:j + 1].isspace():
        j += 1
    fields.append(data[i:j])
    i = j
p = data[i + 1:i + 4]
print("desk" if max(abs(p[k] - B[k]) for k in range(3)) <= 24 else "ink")
PY
px() { timeout 20 grim -g "$1,$2 1x1" -t ppm "$W/px.ppm"; python3 -I "$W/px.py" "$W/px.ppm" "$BG"; }

wait_socket() {
  for _ in $(seq 100); do [ -S "$KURASHI_SOCKET" ] && K ping >/dev/null 2>&1 && return 0; sleep 0.1; done
  fail "$1 did not come up (see $R/server.log)"
}
start_kurashid() {
  rm -f "$KURASHI_SOCKET"
  env DBUS_SYSTEM_BUS_ADDRESS="unix:path=$R/no-system-bus" PULSE_SERVER="unix:$R/no-pulse/native" \
      PULSE_RUNTIME_PATH="$R/no-pulse" "$W/kurashid" >> "$R/server.log" 2>&1 &
  pids+=("$!")
  wait_socket kurashid
}
start_frontend() {
  : > "$R/qs.log"
  env -u KURASHI_SOCKET KURASHI_SIDEBAR_GEOMETRY=1 KURASHI_BAR_GEOMETRY=1 qs -p "$ROOT/frontend" >> "$R/qs.log" 2>&1 &
  pids+=("$!")
  for _ in $(seq 100); do grep -q 'hello.*frontend' "$R/server.log" && break; sleep 0.1; done
  grep -q 'hello.*frontend' "$R/server.log" || fail "frontend never said hello (see $R/qs.log)"
  sleep 3
  start_pointer
}
start_pointer() {
  rm -f "$W/ptr"; mkfifo "$W/ptr"
  python3 -I "$ROOT/tools/bench/wl_pointer.py" --serve < "$W/ptr" >> "$W/ptr.log" 2>&1 &
  PTR_PID=$!
  exec 7> "$W/ptr"
}
stop_pointer() {
  [ -n "$PTR_PID" ] || return 0
  exec 7>&-
  wait "$PTR_PID" 2>/dev/null || true
  PTR_PID=""
}
ptr() { echo "$*" >&7; sleep 0.5; }
keys() { timeout 20 python3 -I "$ROOT/tools/bench/wl_keys.py" "$@"; }
# A shot of the region the sidebar can be in (the right or left 560 px, full height), once its slide has settled.
shot() {  # shot <name> <right|left>
  local x=0
  [ "$2" = right ] && x=$(( SW - 560 ))
  sleep 1.2
  timeout 20 grim -g "$x,0 560x$SH" "$OUT/$1.png" && echo "shot $OUT/$1.png"
}
config() {  # config <style> [toml lines…]
  { printf 'theme.style = "%s"\n' "$1"; shift; printf '%s\n' "$@"; } > "$XDG_CONFIG_HOME/kurashi/config.toml"
}
# Notifications for the list, only into the sandbox's own bus (never the session's).
notes() {
  case "${DBUS_SESSION_BUS_ADDRESS:-}" in *"$R"*) ;; *) echo "no sandbox bus: no notifications"; return 0 ;; esac
  command -v notify-send >/dev/null || return 0
  # Short toasts: they are gone (and the notes in the list) before the shot.
  notify-send -a Calendar -t 1500 "Standup" "14:00 · room 3" >/dev/null 2>&1 || true
  notify-send -a Mail -t 1500 "Aiko Tanaka" "The photos from Saturday are in the shared folder." >/dev/null 2>&1 || true
  notify-send -a Battery -t 1500 "Battery low" "12 % left" >/dev/null 2>&1 || true
  sleep 4
}
ui() { K sub runtime.ui --count 0 --json | jq -c '.data'; }
geom() { grep 'sidebar-geom' "$R/qs.log" | tail -1 | sed 's/.*sidebar-geom //'; }
# A geometry line once the compositor has sized the window and the column (the first lines come before the configure).
SETTLED=' win [0-9]+ [0-9]{3,} frame [0-9]+,[0-9]+,[1-9][0-9]*,[1-9][0-9]{2,} '
wait_geom() {  # wait_geom <grep -E pattern>
  for _ in $(seq 40); do geom | grep -Eq -- "$1" && return 0; sleep 0.25; done
  fail "no sidebar geometry matching '$1' (last: $(geom))"
}
last_window() { grep -oE 'sidebar-window (up|down) [a-z]+' "$R/qs.log" | tail -1; }
wait_window() {  # wait_window <up|down>
  for _ in $(seq 40); do last_window | grep -q "sidebar-window $1" && return 0; sleep 0.25; done
  fail "the sidebar window is not $1 (last: $(last_window))"
}
qml_errors() {
  if grep -E 'qml:.*(Error|error)|TypeError|ReferenceError|is not a type|Unable to assign|is not defined|Cannot assign' "$R/qs.log" \
      | grep -v 'Unable to assign \[undefined\]' >/dev/null; then
    grep -E 'Error|error|Unable|not defined|Cannot assign' "$R/qs.log" | head -20 >&2
    fail "QML errors (see $R/qs.log)"
  fi
}
RIGHT='{"side":"right","output":"HEADLESS-1"}'
# SIDEBAR_PHASES=146 runs only those phases (all by default).
want() { [[ "${SIDEBAR_PHASES:-123456}" == *"$1"* ]]; }
: > "$R/server.log"

# 1. A top bar, panel style: geometry, Esc, the launcher.
if want 1; then
config washi
start_kurashid
start_frontend
sleep 1
grep -q 'sidebar-window up' "$R/qs.log" && fail "a sidebar window exists while it is closed"
echo "ok: closed, no sidebar window"
K act sidebar.toggle "$RIGHT" >/dev/null
wait_window up
wait_geom "^HEADLESS-1 right panel$SETTLED"
read -r _ _ _ _ WW WH _ FR _ BEDGE BARH _ <<< "$(geom)"
[ "$BEDGE" = top ] || fail "expected a top bar, got '$BEDGE' ($(geom))"
[ "$WW" = 420 ] || fail "the panel is $WW px wide, not 420 ($(geom))"
[ "$WH" = $(( SH - BARH )) ] || fail "under a $BARH px top bar the panel is $WH px tall, not $(( SH - BARH )) ($(geom))"
[ "$FR" = "0,0,420,$WH" ] || fail "the panel's column is not flush ($FR)"
sleep 1.2
[ "$(px $(( SW - 1 )) $(( SH - 1 )))" = ink ] || fail "the panel does not reach the screen's bottom-right corner"
[ "$(px $(( SW - 410 )) $(( SH - 1 )))" = ink ] || fail "the panel's bottom row is not drawn"
[ "$(px $(( SW - 430 )) $(( SH / 2 )))" = desk ] || fail "something is drawn left of the panel"
echo "ok: right panel under the top bar: ${WW}x$WH at y=$BARH → bottom ($SW×$SH output)"
qml_errors
# The Wi-Fi tile's arrow (the first tile, under the 44 px header) opens its page over the sections; the click also gives
# the column the keyboard (on demand). Esc goes back to the sections first, the next Esc closes the sidebar.
ptr click $(( SW - 420 + 12 + (420 - 24 - 8) / 2 - 11 )) $(( BARH + 12 + 44 + 12 + 28 )) left
mkdir -p "$OUT/washi"
shot washi/page right
keys escape
sleep 0.8
ui | jq -e '.sidebar == "right"' >/dev/null || fail "Esc on a tile's page closed the sidebar ($(ui))"
echo "ok: a tile's page opens over the sections; Esc goes back first"
keys escape
for _ in $(seq 20); do ui | jq -e 'has("sidebar") | not' >/dev/null && break; sleep 0.2; done
ui | jq -e 'has("sidebar") | not' >/dev/null || fail "Esc did not close the sidebar ($(ui))"
wait_window down
echo "ok: Esc closes it and its window goes"
K act sidebar.toggle "$RIGHT" >/dev/null
wait_window up
K act launcher.toggle >/dev/null
for _ in $(seq 20); do ui | jq -e 'has("sidebar") | not' >/dev/null && break; sleep 0.2; done
ui | jq -e '(has("sidebar") | not) and .launcher == true' >/dev/null || fail "opening the launcher did not close the sidebar ($(ui))"
wait_window down
echo "ok: opening the launcher closes it"
K act launcher.toggle >/dev/null
qml_errors
stop_phase
fi

# 2. Floating: inset by the gap on every side.
if want 2; then
config washi '[sidebar]' 'style = "floating"'
: > "$R/server.log"
start_kurashid
start_frontend
K act sidebar.toggle "$RIGHT" >/dev/null
wait_geom "^HEADLESS-1 right floating$SETTLED"
read -r _ _ _ _ WW WH _ FR _ _ BARH _ GAP _ <<< "$(geom)"
[ "$FR" = "$GAP,$GAP,$(( WW - 2 * GAP )),$(( WH - 2 * GAP ))" ] || fail "the floating column is not inset by $GAP ($FR in ${WW}x$WH)"
sleep 1.2
[ "$(px $(( SW - 1 )) $(( SH / 2 )))" = desk ] || fail "the floating column touches the screen's edge"
[ "$(px $(( SW - 1 )) $(( SH - 1 )))" = desk ] || fail "the floating column touches the screen's bottom"
[ "$(px $(( SW - GAP - 20 )) $(( SH / 2 )))" = ink ] || fail "the floating column is not drawn"
echo "ok: floating: inset by $GAP px ($FR)"
qml_errors
stop_phase
fi

# 3. A left bar: the right sidebar runs edge to edge; the bar's quick button opens it with sidebar.from_bar.
if want 3; then
config washi '[bar]' 'edge = "left"' '[sidebar]' 'from_bar = true'
: > "$R/server.log"
start_kurashid
start_frontend
for _ in $(seq 40); do grep -q 'BARGEO quick ' "$R/qs.log" && break; sleep 0.25; done
read -r QX0 QY0 QX1 QY1 <<< "$(grep 'BARGEO quick ' "$R/qs.log" | tail -1 | sed 's/.*BARGEO quick //')"
[ -n "${QY1:-}" ] || fail "the left bar logged no quick button"
ptr click $(( (QX0 + QX1) / 2 )) $(( (QY0 + QY1) / 2 )) left
wait_window up
ui | jq -e '.sidebar == "right" and .sidebar_output == "HEADLESS-1" and .panel == ""' >/dev/null \
  || fail "the bar's quick button did not open the right sidebar ($(ui))"
echo "ok: with sidebar.from_bar the bar's quick button opens the right sidebar"
wait_geom "^HEADLESS-1 right panel$SETTLED"
read -r _ _ _ _ WW WH _ _ _ BEDGE _ <<< "$(geom)"
[ "$BEDGE" = left ] || fail "expected a left bar ($(geom))"
[ "$WH" = "$SH" ] || fail "beside a left bar the right panel is $WH px tall, not $SH"
sleep 1.2
[ "$(px $(( SW - 1 )) 0)" = ink ] || fail "the panel does not reach the top-right corner"
[ "$(px $(( SW - 1 )) $(( SH - 1 )))" = ink ] || fail "the panel does not reach the bottom-right corner"
echo "ok: beside a left bar the right panel spans the full height (${WW}x$WH)"
ptr click $(( (QX0 + QX1) / 2 )) $(( (QY0 + QY1) / 2 )) left
wait_window down
echo "ok: the bar's button closes it again"
qml_errors
stop_phase
fi

# 4. The left sidebar with the AI mod on.
if want 4; then
config washi
: > "$R/server.log"
start_kurashid
K act mod.enable '{"id": "ai"}' >/dev/null || fail "mod.enable ai failed"
start_frontend
K act sidebar.toggle '{"side":"left"}' >/dev/null
wait_window up
for _ in $(seq 40); do grep 'sidebar-tab ' "$R/qs.log" | tail -1 | grep -q 'mod:ai:ai true' && break; sleep 0.25; done
grep 'sidebar-tab ' "$R/qs.log" | tail -1 | grep -q 'mod:ai:ai true' \
  || fail "the left sidebar does not show the AI panel ($(grep 'sidebar-tab ' "$R/qs.log" | tail -1))"
wait_geom "^HEADLESS-1 left panel$SETTLED"
echo "ok: the left sidebar shows the AI tab ($(grep 'sidebar-tab ' "$R/qs.log" | tail -1 | sed 's/.*sidebar-tab //'))"
mkdir -p "$OUT/washi"
shot washi/left left
[ "$(px 0 $(( SH / 2 )))" = ink ] || fail "the left panel is not flush left"
K act sidebar.close >/dev/null
wait_window down
qml_errors
stop_phase
fi

# 5. A 720 px output: the column fits.
MODE="${SW}x$SH"
if want 5 && swaymsg output HEADLESS-1 mode 1280x720 >/dev/null 2>&1; then
  dims
  config washi
  : > "$R/server.log"
  start_kurashid
  start_frontend
  notes
  K act sidebar.toggle "$RIGHT" >/dev/null
  wait_geom "^HEADLESS-1 right panel$SETTLED"
  read -r _ _ _ _ WW WH _ _ _ _ BARH _ <<< "$(geom)"
  [ "$WH" = $(( SH - BARH )) ] || fail "on 720 px the panel is $WH px tall"
  mkdir -p "$OUT/washi"
  shot washi/right-720 right
  [ "$(px $(( SW - 410 )) $(( SH - 1 )))" = ink ] || fail "on 720 px the column does not reach the bottom"
  echo "ok: on a 1280×720 output the column fits (${WW}x$WH)"
  qml_errors
  stop_phase
  swaymsg output HEADLESS-1 mode "$MODE" >/dev/null 2>&1 || true
  dims
elif want 5; then
  echo "skip: the sandbox output cannot change its mode"
fi

# 6. Looks: right panel and floating under each style.
want 6 && for d in $DECORS; do
  mkdir -p "$OUT/$d"
  for style in panel floating; do
    config "$d" '[sidebar]' "style = \"$style\""
    : > "$R/server.log"
    start_kurashid
    start_frontend
    notes
    K act sidebar.toggle "$RIGHT" >/dev/null
    wait_geom "^HEADLESS-1 right $style$SETTLED"
    shot "$d/right-$style" right
    qml_errors
    stop_phase
  done
done
rm -f "$XDG_CONFIG_HOME/kurashi/config.toml"
echo "test-sidebar-panel: ok (shots in $OUT)"
