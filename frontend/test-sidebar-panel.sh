#!/usr/bin/env bash
# The edge sidebars (card W29, docs/ux/sidebar.md), invisibly (headless sway sandbox), with the REAL kurashid:
#   1. closed = no sidebar window; `sidebar.toggle {side: right}` under a top bar: the column spans the bar's bottom → the
#      screen's bottom (W44: geometry from runtime.layout, logged in output coordinates; the window ignores zones and
#      covers the output while it catches clicks), flush right, 420 px;
#      Esc (after a click gives it the keyboard) closes it and the window goes; opening the launcher closes it;
#   2. floating: the column is inset by the theme's gap on every side, below the bar (the outermost pixels are the desk);
#   3. a left bar: the right sidebar spans the whole height; with `sidebar.from_bar` the bar's quick button opens it;
#   4. the left sidebar with the AI mod on: its tab shows the AI panel (no Ollama in the sandbox: the mod's own state);
#   5. a 1280×720 output: the column fits (the notifications shrink, the column never overflows);
#   6. shots: right panel and floating under washi, sekai, win95 and glass; left panel under washi;
#   8–11 (W44, K71): every sidebar row of the layout's mode table (washi, sekai × top/bottom bar × frame × draw × side),
#      hover reveal of each side, pinned with a test window beside it and no idle frame, drag/double-click/keyboard resize.
#   O (row 521, terminal's line chrome): both sidebars pinned open the top bar's rule twice; a bottom bar turned on spans
#      the width under them and opens its rule under both (four openings). SIDEBAR_PHASES="123456789PRO" picks the parts.
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
start_frontend() {  # start_frontend [VAR=value …]
  : > "$R/qs.log"
  env -u KURASHI_SOCKET KURASHI_SIDEBAR_GEOMETRY=1 KURASHI_BAR_GEOMETRY=1 "$@" qs -p "$ROOT/frontend" >> "$R/qs.log" 2>&1 &
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
# K71: config lines for a bar on edge $1 with today's modules and none on top (what `layout.bar.move` writes). Root
# keys: they go before any `[table]` line.
bar_lines() {
  [ "$1" = top ] && return
  printf '%s\n' "edges.top.bar = false" "edges.top.start = []" "edges.top.center = []" "edges.top.end = []" \
    "edges.$1.bar = true" "edges.$1.start = [\"sidebar_left\", \"workspaces\", \"windows\"]" \
    "edges.$1.center = [\"island\"]" \
    "edges.$1.end = [\"volume\", \"mods\", \"recorder\", \"keyboard\", \"clock\", \"quick\", \"tray\", \"sidebar_right\"]"
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
# SIDEBAR_PHASES=146 runs only those phases (all by default; W44's: 8 layout, 9 hover, P pinned, R resize).
want() { [[ "${SIDEBAR_PHASES:-123456789PRO}" == *"$1"* ]]; }
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
[ "$WW" = "$SW" ] || fail "the window is $WW px wide, not the output's $SW (the catcher; $(geom))"
[ "$WH" = "$SH" ] || fail "the window is $WH px tall, not the output's $SH (it ignores zones; $(geom))"
[ "$FR" = "$(( SW - 420 )),$BARH,420,$(( SH - BARH ))" ] || fail "the panel's column is not flush under the bar or not 420 px wide ($FR)"
sleep 1.2
[ "$(px $(( SW - 1 )) $(( SH - 1 )))" = ink ] || fail "the panel does not reach the screen's bottom-right corner"
[ "$(px $(( SW - 410 )) $(( SH - 1 )))" = ink ] || fail "the panel's bottom row is not drawn"
[ "$(px $(( SW - 430 )) $(( SH / 2 )))" = desk ] || fail "something is drawn left of the panel"
echo "ok: right panel under the top bar: $FR ($SW×$SH output)"
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
config washi '[sidebar.right]' 'draw = "floating"' '[sidebar.left]' 'draw = "floating"'
: > "$R/server.log"
start_kurashid
start_frontend
K act sidebar.toggle "$RIGHT" >/dev/null
wait_geom "^HEADLESS-1 right floating$SETTLED"
read -r _ _ _ _ WW WH _ FR _ _ BARH _ GAP _ <<< "$(geom)"
[ "$FR" = "$(( SW - GAP - 420 )),$(( BARH + GAP )),420,$(( SH - BARH - 2 * GAP ))" ] || fail "the floating column is not inset by $GAP from the bar and the edges ($FR)"
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
config washi "$(bar_lines left)" '[sidebar]' 'from_bar = true'
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
read -r _ _ _ _ WW WH _ FR _ BEDGE _ <<< "$(geom)"
geom | grep -q ' joins edge,edge ' || fail "beside a left bar the right panel should meet the screen's edges ($(geom))"
[ "${FR#*,}" = "0,420,$SH" ] || fail "beside a left bar the right panel is not the full height ($FR)"
sleep 1.2
[ "$(px $(( SW - 1 )) 0)" = ink ] || fail "the panel does not reach the top-right corner"
[ "$(px $(( SW - 1 )) $(( SH - 1 )))" = ink ] || fail "the panel does not reach the bottom-right corner"
echo "ok: beside a left bar the right panel spans the full height ($FR)"
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
  read -r _ _ _ _ WW WH _ FR _ _ BARH _ <<< "$(geom)"
  [ "${FR##*,}" = $(( SH - BARH )) ] || fail "on 720 px the column is ${FR##*,} px tall"
  mkdir -p "$OUT/washi"
  shot washi/right-720 right
  [ "$(px $(( SW - 410 )) $(( SH - 1 )))" = ink ] || fail "on 720 px the column does not reach the bottom"
  echo "ok: on a 1280×720 output the column fits ($FR)"
  qml_errors
  stop_phase
  swaymsg output HEADLESS-1 mode "$MODE" >/dev/null 2>&1 || true
  dims
elif want 5; then
  echo "skip: the sandbox output cannot change its mode"
fi

# 7. The bar's sidebar buttons (I154; the modules `sidebar_left` / `sidebar_right` of the bar's zones, K71): under a top bar and a left bar, a click on
#    the right button opens the right sidebar, on the left one the left sidebar, a second click closes it.
if want 7; then
for edge in top left; do
  config washi "$(bar_lines "$edge")"
  : > "$R/server.log"
  start_kurashid
  start_frontend
  for side in right left; do
    for _ in $(seq 40); do grep -q "SIDEBARBTN $side " "$R/qs.log" && break; sleep 0.25; done
    read -r X0 Y0 X1 Y1 <<< "$(grep "SIDEBARBTN $side " "$R/qs.log" | tail -1 | sed "s/.*SIDEBARBTN $side //")"
    [ -n "${Y1:-}" ] || fail "the $edge bar logged no $side sidebar button"
    # The bar's window sits at the output's origin for a top or left bar: its boxes are screen coordinates.
    ptr click $(( (X0 + X1) / 2 )) $(( (Y0 + Y1) / 2 )) left
    wait_window up
    ui | jq -e --arg s "$side" '.sidebar == $s and .sidebar_output == "HEADLESS-1"' >/dev/null \
      || fail "the $edge bar's $side button did not open the $side sidebar ($(ui))"
    ptr click $(( (X0 + X1) / 2 )) $(( (Y0 + Y1) / 2 )) left
    wait_window down
    echo "ok: $edge bar: the $side button opens the $side sidebar and closes it"
  done
  qml_errors
  stop_phase
done
fi

# ---- W44 (K71; docs/ux/layout.md, docs/ux/sidebar.md): the sidebars from runtime.layout ----
# 8. Every sidebar row of the mode table: washi and sekai × a top and a bottom bar × the frame off and on × floating,
#    dynamic, connected, both sides. The column's rect (logged in output coordinates) is the layout's: `inset` from its
#    side, `span.start` from the top, `span.end` from the bottom, `width` wide. Shots
#    frontend/shots/sidebar/layout/<decor>/<bar>-frame<off|on>-<draw>-<side>.png.
# 9. Hover (point 14): with `visibility = "hover"` a rest on its edge reveals each side, a pointer resting there keeps it,
#    leaving the column hides it (its window goes).
# 10. Pinned (`always`): the column stays with no toggle, keeps its zone (a test window tiles beside it), and commits no
#    frame at rest.
# 11. Resize (point 12): a drag of the inner edge writes sidebar.right.width on release (real kurashid), a double click
#    resets it to the default, Ctrl+Left by 10 px a press while the column has the keyboard.
lay() { K sub runtime.layout --count 0 --json | jq -c ".data.outputs[\"HEADLESS-1\"].sidebars.$1"; }
# The column's rect the layout gives: "x,y,w,h" in output coordinates.
want_rect() {
  local l x
  l=$(lay "$1")
  read -r INS W0 S0 S1 <<< "$(echo "$l" | jq -r '"\(.inset) \(.width) \(.span.start) \(.span.end)"')"
  x=$INS; [ "$1" = right ] && x=$(( SW - INS - W0 ))
  echo "$x,$S0,$W0,$(( SH - S0 - S1 ))"
}
open_side() {  # open_side <side>: toggled open, at rest
  local n; n=$(grep -c "sidebar-rest $1 " "$R/qs.log" || true)
  K act sidebar.toggle "{\"side\":\"$1\",\"output\":\"HEADLESS-1\"}" >/dev/null
  for _ in $(seq 60); do [ "$(grep -c "sidebar-rest $1 " "$R/qs.log" || true)" -gt "$n" ] && return 0; sleep 0.1; done
  fail "the $1 sidebar did not come to rest ($(geom))"
}
close_side() {
  K act sidebar.close >/dev/null
  for _ in $(seq 60); do last_window | grep -q "sidebar-window down $1" && return 0; sleep 0.1; done
  fail "the $1 sidebar's window did not go"
}
side_geom() { grep "sidebar-geom HEADLESS-1 $1 " "$R/qs.log" | tail -1 | sed 's/.*sidebar-geom //'; }
cat > "$W/drag.py" <<'PY'
import struct, sys, time
sys.path.insert(0, sys.argv[1])
import wl_pointer as wp
x0, y0, x1, y1 = (int(v) for v in sys.argv[2:6])
mode = sys.argv[6] if len(sys.argv) > 6 else "drag"
p = wp.Pointer()
p.motion(x0, y0)
p.roundtrip()
time.sleep(0.4)
def press(state):
    p.send(p.pointer, 2, struct.pack("<III", wp.ms(), wp.BUTTONS["left"], state))
    p.send(p.pointer, 4)
    p.roundtrip()
if mode == "double":
    press(1); time.sleep(0.05); press(0); time.sleep(0.08); press(1); time.sleep(0.05); press(0)
else:
    press(1); time.sleep(0.2); p.sweep(x0, y0, x1, y1, 0.8); time.sleep(0.5); press(0)
p.settle()
PY
drag() { stop_pointer; timeout 20 python3 -I "$W/drag.py" "$ROOT/tools/bench" "$@" >> "$W/ptr.log" 2>&1 || fail "drag failed"; start_pointer; }
cfgv() { K sub config --count 0 --json | jq -c ".data.values[\"$1\"] | {value, kind: .source.kind}"; }

if want 8; then
  LOUT=$OUT/layout
  for d in ${SIDEBAR_LAYOUT_DECORS:-washi sekai}; do
    mkdir -p "$LOUT/$d"
    config "$d" 'idle.enabled = false'
    : > "$R/server.log"
    start_kurashid
    start_frontend
    for bar in top bottom; do
      [ "$bar" = bottom ] && { K act layout.bar.move '{"from":"top","to":"bottom"}' >/dev/null || fail "layout.bar.move refused"; }
      for frame in off on; do
        fr=false; [ "$frame" = on ] && fr=true
        for draw in floating dynamic connected; do
          K set layout.frame.enabled=$fr "layout.draw=\"$draw\"" >/dev/null || fail "set refused"
          sleep 0.8
          for side in right left; do
            open_side "$side"
            tag="$d $bar frame $frame $draw $side"
            want=$(want_rect "$side")
            got=$(side_geom "$side" | sed 's/.* frame \([^ ]*\) .*/\1/')
            [ "$got" = "$want" ] || fail "$tag: the column stands at $got, the layout says $want ($(side_geom "$side"))"
            side_geom "$side" | grep -q " draw $draw " || fail "$tag: drawn as $(side_geom "$side")"
            x=0; [ "$side" = right ] && x=$(( SW - 560 ))
            sleep 0.3
            timeout 20 grim -g "$x,0 560x$SH" "$LOUT/$d/$bar-frame$frame-$draw-$side.png" && echo "shot $LOUT/$d/$bar-frame$frame-$draw-$side.png"
            echo "ok: $tag: $got ($(side_geom "$side" | sed 's/.* joins \([^ ]*\) .*/\1/'))"
            close_side "$side"
          done
        done
      done
      [ "$bar" = bottom ] && K act layout.bar.move '{"from":"bottom","to":"top"}' >/dev/null
    done
    qml_errors
    stop_phase
  done
fi

if want 9; then
  config washi 'idle.enabled = false' '[sidebar.right]' 'visibility = "hover"' '[sidebar.left]' 'visibility = "hover"'
  : > "$R/server.log"
  start_kurashid
  start_frontend
  for side in right left; do
    ex=0; [ "$side" = right ] && ex=$(( SW - 1 ))
    ptr move $(( SW / 2 )) $(( SH / 2 ))
    sleep 0.8
    n=$(grep -c "sidebar-rest $side " "$R/qs.log" || true)
    ptr move "$ex" $(( SH / 2 ))
    for _ in $(seq 40); do [ "$(grep -c "sidebar-rest $side " "$R/qs.log" || true)" -gt "$n" ] && break; sleep 0.1; done
    [ "$(grep -c "sidebar-rest $side " "$R/qs.log" || true)" -gt "$n" ] || fail "hover: a rest on the $side edge did not reveal it"
    sleep 2
    last_window | grep -q "sidebar-window up $side" || fail "hover: the $side column went while the pointer rested on the edge"
    [ "$(grep -c "sidebar-rest $side " "$R/qs.log" || true)" = $(( n + 1 )) ] || fail "hover: the $side column came and went while the pointer rested"
    mkdir -p "$OUT/layout"
    timeout 20 grim -g "$([ "$side" = right ] && echo $(( SW - 560 )) || echo 0),0 560x$SH" "$OUT/layout/hover-$side.png"
    ptr move $(( SW / 2 )) $(( SH / 2 ))
    for _ in $(seq 40); do last_window | grep -q "sidebar-window down $side" && break; sleep 0.1; done
    last_window | grep -q "sidebar-window down $side" || fail "hover: the $side column stayed after the pointer left"
    ui | jq -e 'has("sidebar") | not' >/dev/null || fail "hover opened runtime.ui.sidebar ($(ui))"
    echo "ok: hover: the $side edge's dwell reveals it, a resting pointer keeps it, leaving hides it"
  done
  qml_errors
  stop_phase
fi

if want P; then  # 10. pinned
  swaymsg 'default_border none' >/dev/null; swaymsg 'default_floating_border none' >/dev/null
  config washi 'idle.enabled = false' '[sidebar.right]' 'visibility = "always"'
  : > "$R/server.log"
  start_kurashid
  start_frontend WAYLAND_DEBUG=1
  for _ in $(seq 60); do grep -q "sidebar-rest right " "$R/qs.log" && break; sleep 0.1; done
  grep -q "sidebar-rest right " "$R/qs.log" || fail "pinned: the right column did not come out by itself"
  side_geom right | grep -q " holder 420 " || fail "pinned: the column does not hold its zone ($(side_geom right))"
  printf 'import QtQuick\nimport Quickshell\nShellRoot { FloatingWindow { color: "#c03030"; implicitWidth: 400; implicitHeight: 300 } }\n' > "$W/win.qml"
  # (Without the pointer's fifo: a writer it inherits would keep the pointer from ever seeing EOF.)
  env -u KURASHI_SOCKET qs -p "$W/win.qml" >> "$R/win.log" 2>&1 7>&- &
  WIN=$!; pids+=("$WIN")
  rect=""
  for _ in $(seq 50); do
    rect=$(swaymsg -t get_tree -r | jq -r --argjson p "$WIN" '.. | select(.pid? == $p) | .rect | "\(.x) \(.y) \(.width) \(.height)"' | head -1)
    [ -n "$rect" ] && break; sleep 0.1
  done
  sleep 1
  rect=$(swaymsg -t get_tree -r | jq -r --argjson p "$WIN" '.. | select(.pid? == $p) | .rect | "\(.x) \(.y) \(.width) \(.height)"' | head -1)
  read -r WX WY WWID WHEI <<< "$rect"
  [ $(( WX + WWID )) -le $(( SW - 420 )) ] || fail "pinned: the test window ($rect) does not tile beside the column"
  echo "ok: pinned: a test window tiles beside it ($rect)"
  timeout 20 grim -s 0.5 "$OUT/layout/pinned.png"
  sleep 1
  s=$(stat -c %s "$R/qs.log"); sleep 5
  SBS=$(grep -oE 'get_layer_surface\(new id zwlr_layer_surface_v1#[0-9]+, wl_surface#[0-9]+, [^"]*"kurashi-sidebar"' "$R/qs.log" \
    | tail -1 | grep -oE 'wl_surface#[0-9]+')
  [ -n "$SBS" ] || fail "idle: the pinned sidebar's surface is not in the Wayland log"
  c=$(tail -c +"$((s + 1))" "$R/qs.log" | grep -c "${SBS}\.commit(" || true)
  [ "$c" = 0 ] || fail "idle: the pinned sidebar committed $c frames in 5 s"
  echo "ok: idle: the pinned sidebar commits no frame at rest"
  qml_errors
  stop_phase
fi

# O. Openings (row 521, line chrome: terminal): both sidebars pinned under a top bar open its rule twice — the rule runs
#    only between the two columns (BARRULE, KURASHI_BAR_GEOMETRY) — and a bottom bar turned on meanwhile spans the whole
#    width under them (the pinned columns, which hold their zones, wait for it: a holder mapped after them is placed
#    between their zones) with its rule opened under both columns too: four openings, two per column.
if want O; then
  config terminal 'idle.enabled = false' '[sidebar.right]' 'visibility = "always"' '[sidebar.left]' 'visibility = "always"'
  : > "$R/server.log"
  start_kurashid
  start_frontend
  for _ in $(seq 60); do [ "$(grep -c 'sidebar-rest ' "$R/qs.log" || true)" -ge 2 ] && break; sleep 0.1; done
  sleep 1.5
  rule() { grep -o "BARRULE HEADLESS-1 $1 .*" "$R/qs.log" | tail -1 | sed "s/BARRULE HEADLESS-1 $1 //"; }
  opens() { grep -o "sidebar-opening $1 .*" "$R/qs.log" | tail -1 | sed "s/sidebar-opening $1 //"; }
  WL=$(lay left | jq -r .width); WR=$(lay right | jq -r .width)
  [ "$(rule top)" = "$WL-$(( SW - WR ))" ] || fail "openings: the top rule is '$(rule top)', not $WL-$(( SW - WR )) (two openings)"
  [ "$(opens left)" = "top:0,$WL" ] && [ "$(opens right)" = "top:$(( SW - WR )),$SW" ] \
    || fail "openings: the columns publish '$(opens left)' and '$(opens right)'"
  mkdir -p "$OUT/layout"
  timeout 20 grim -s 0.5 "$OUT/layout/openings-two.png"
  echo "ok: openings: both pinned columns open the top bar's rule ($(rule top))"
  K set edges.bottom.bar=true >/dev/null || fail "edges.bottom.bar = true was refused"
  sleep 3
  b=$(grep -o 'BARWIN HEADLESS-1 bottom .*' "$R/qs.log" | tail -1 | sed 's/BARWIN HEADLESS-1 bottom //')
  BH=$(K sub theme --count 0 --json | jq -r '.data.tokens["bar.height"] // 32')
  [ "$b" = "0 $(( SH - BH )) $SW $BH shown" ] || fail "openings: the bottom bar's window is '$b', not the whole width"
  [ "$(px 3 $(( SH - BH / 2 )))" = ink ] && [ "$(px $(( SW - 3 )) $(( SH - BH / 2 )))" = ink ] \
    || fail "openings: the bottom bar does not reach the output's corners under the columns"
  [ "$(rule bottom)" = "$WL-$(( SW - WR ))" ] || fail "openings: the bottom rule is '$(rule bottom)', not $WL-$(( SW - WR ))"
  [ "$(opens left)" = "top:0,$WL bottom:0,$WL" ] && [ "$(opens right)" = "top:$(( SW - WR )),$SW bottom:$(( SW - WR )),$SW" ] \
    || fail "openings: a column joining a top and a bottom bar publishes '$(opens left)' and '$(opens right)'"
  timeout 20 grim -s 0.5 "$OUT/layout/openings-top-bottom.png"
  timeout 20 grim -s 4 -g "$(( WL - 30 )),$(( SH - BH - 30 )) 60x60" "$OUT/layout/openings-bottom-join.png"
  echo "ok: openings: a bottom bar spans the width under the pinned columns and opens its rule under both ($(rule bottom))"
  qml_errors
  stop_phase
fi

if want R; then  # 11. resize
  config washi 'idle.enabled = false'
  : > "$R/server.log"
  start_kurashid
  start_frontend
  open_side right
  drag $(( SW - 420 )) $(( SH / 2 )) $(( SW - 520 )) $(( SH / 2 ))
  for _ in $(seq 30); do [ "$(cfgv sidebar.right.width)" = '{"value":520,"kind":"user"}' ] && break; sleep 0.2; done
  [ "$(cfgv sidebar.right.width)" = '{"value":520,"kind":"user"}' ] || fail "resize: a drag of 100 px wrote $(cfgv sidebar.right.width)"
  for _ in $(seq 30); do side_geom right | grep -q ",520,$(( SH - 32 )) " && break; sleep 0.2; done
  side_geom right | grep -q "frame $(( SW - 520 ))," || fail "resize: the column is not 520 px wide ($(side_geom right))"
  timeout 20 grim -g "$(( SW - 700 )),0 700x300" "$OUT/layout/resized.png"
  echo "ok: resize: the drag wrote sidebar.right.width = 520 on release"
  drag $(( SW - 520 )) $(( SH / 2 )) $(( SW - 520 )) $(( SH / 2 )) double
  for _ in $(seq 30); do cfgv sidebar.right.width | grep -q '"kind":"default"' && break; sleep 0.2; done
  cfgv sidebar.right.width | grep -q '"value":420,"kind":"default"' || fail "resize: a double click did not reset ($(cfgv sidebar.right.width))"
  echo "ok: resize: a double click resets it to the default"
  ptr click $(( SW - 410 )) $(( SH / 2 )) left
  sleep 0.5
  keys ctrl+left ctrl+left ctrl+left
  for _ in $(seq 30); do [ "$(cfgv sidebar.right.width)" = '{"value":450,"kind":"user"}' ] && break; sleep 0.2; done
  [ "$(cfgv sidebar.right.width)" = '{"value":450,"kind":"user"}' ] || fail "resize: Ctrl+Left ×3 wrote $(cfgv sidebar.right.width)"
  echo "ok: resize: Ctrl+Left by 10 px a press (one write: 450)"
  qml_errors
  stop_phase
fi

# 6. Looks: right panel and floating under each style.
want 6 && for d in $DECORS; do
  mkdir -p "$OUT/$d"
  for style in panel floating; do
    # K71: the panel is the sidebar's automatic draw mode (dynamic), floating its own.
    draw=auto; [ "$style" = floating ] && draw=floating
    config "$d" '[sidebar.right]' "draw = \"$draw\"" '[sidebar.left]' "draw = \"$draw\""
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
