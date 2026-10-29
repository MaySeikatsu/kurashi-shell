#!/usr/bin/env bash
# The app dock (K51, docs/ux/dock.md), invisibly (headless sway sandbox), by a virtual pointer and keyboard:
#   1. kurashi-mock with fake windows (firefox ×2, foot focused, an app with no desktop entry) and two pins (firefox,
#      Files): the dock shows pinned then running tiles; a click on Firefox focuses its first window, a second click
#      the next one (the cycle); right-click on foot → the menu (shot) → Escape; right-click → "Close window" removes
#      foot's window (`window.close`); autohide: the dock hides, a rest on the bottom edge reveals it, leaving hides it;
#      W36 (I137): an urgent window's app hops, then keeps its mark (shot); the mock's launcher takes kurashid's ids;
#   2. the REAL kurashid: the dock with its pins; dragging Files before Firefox writes the new order (`dock.pinned`);
#      right-click Firefox → "Unpin from dock" writes `dock.pinned` (one cfg.apply), and the tile goes;
#   3. looks: the dock under the decors sekai, glass, terminal and none (the real daemon's theme worn by the mock);
#   (after 3) the first decor in the light scheme: look, urgent, left edge, empty -> shots/dock/<decor>-light/;
#   6. (W44, K71) draw modes from runtime.layout: washi and sekai × top and bottom bar × frame off and on × floating,
#      dynamic, connected (shots/dock/layout/<decor>/); hover through the shared edge strip (a resting pointer keeps it),
#      hidden by runtime.ui.shown, empty_desktop; idle commits of a hover dock at rest;
#   5. (after 6) a second output to the right: a right-edge dock on HEADLESS-1 waits 500 ms to reveal (the shared edge),
#      HEADLESS-2's own right edge 250 ms;
#   7. (W44-follow) the joined dock's paper: washi with the paper material, floating/dynamic/connected on the edge and on a
#      bottom bar: the body carries the relief, the bar's rule opens under a joined dock (shots/dock/layout/washi-paper/);
#   4. with DOCK_MEASURE=1: idle commits of the dock's surfaces (hidden and shown, 10 s each) and its USS per output
#      (dock on and hidden vs off, medians of three alternating runs; shown vs hidden once) — docs/BENCH.md "Mods".
#   nix develop -c frontend/test-dock.sh [sandbox-name]
# Binaries: kurashid, kurashi and kurashi-mock from $KURASHI_BIN_DIR (default $CARGO_TARGET_DIR/debug or target/debug).
# Shots in frontend/shots/dock/<decor>/. On a hybrid laptop export KURASHI_RENDER_NODE first.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
NAME=${1:-${KURASHI_SB_PREFIX:-}w25-dck-test}
BIN=${KURASHI_BIN_DIR:-${CARGO_TARGET_DIR:-$ROOT/target}/debug}
OUT=$ROOT/frontend/shots/dock
DECORS=${DOCK_DECORS:-sekai glass terminal none}
mkdir -p "$OUT"
fail() { echo "test-dock: FAIL: $*" >&2; exit 1; }

eval "$("$ROOT/tools/bench/sandbox.sh" start "$NAME")"
. "$ROOT/frontend/test-lib.sh"
R=$XDG_RUNTIME_DIR
W=$R/work
mkdir -p "$W" "$R/kurashi"
cp "$BIN/kurashid" "$BIN/kurashi" "$BIN/kurashi-mock" "$W/"

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
# Hermetic apps: three desktop entries with plain SVG icons (hicolor); the host's entries stay out.
SHARE=$R/xdg/share
export XDG_DATA_DIRS=$SHARE
mkdir -p "$SHARE/applications" "$SHARE/icons/hicolor/scalable/apps"
printf '[Icon Theme]\nName=Hicolor\nDirectories=scalable/apps\n\n[scalable/apps]\nSize=48\nMinSize=16\nMaxSize=512\nType=Scalable\n' \
  > "$SHARE/icons/hicolor/index.theme"
app() {  # app <id> <name> <colour> <letter>
  printf '[Desktop Entry]\nType=Application\nName=%s\nExec=true\nIcon=%s\n' "$2" "$1" > "$SHARE/applications/$1.desktop"
  printf '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 48 48"><rect x="4" y="4" width="40" height="40" rx="11" fill="%s"/><text x="24" y="33" font-size="24" font-family="sans-serif" font-weight="bold" text-anchor="middle" fill="#fff">%s</text></svg>\n' \
    "$3" "$4" > "$SHARE/icons/hicolor/scalable/apps/$1.svg"
}
app firefox Firefox '#e66000' F
app foot Foot '#3b6ea5' T
app org.gnome.Nautilus Files '#6a8f3a' N
K() { timeout 10 "$W/kurashi" "$@"; }
BG='#8fb8c8'
swaymsg output '*' bg "$BG" solid_color >/dev/null 2>&1 || true
SW=$(swaymsg -t get_outputs -r | jq -r '.[] | select(.name == "HEADLESS-1") | .rect.width')
SH=$(swaymsg -t get_outputs -r | jq -r '.[] | select(.name == "HEADLESS-1") | .rect.height')

# How much of a region is not the desk: the dock's pixels (P6 PPM from grim). Prints the count.
cat > "$W/ink.py" <<'PY'
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
raster = data[i + 1:]
n = sum(1 for o in range(0, len(raster) - 2, 3) if max(abs(raster[o + k] - B[k]) for k in range(3)) > 24)
print(n)
PY

# A drag: press, travel, release (wl_pointer.py has clicks only; this reuses its pointer).
cat > "$W/drag.py" <<'PY'
import struct, sys, time
sys.path.insert(0, sys.argv[1])
import wl_pointer as wp
x0, y0, x1, y1 = (int(v) for v in sys.argv[2:6])
p = wp.Pointer()
p.motion(x0, y0)
p.roundtrip()
time.sleep(0.4)
p.send(p.pointer, 2, struct.pack("<III", wp.ms(), wp.BUTTONS["left"], 1))
p.send(p.pointer, 4)
p.roundtrip()
time.sleep(0.2)
p.sweep(x0, y0, x1, y1, 0.8)
time.sleep(0.5)
p.send(p.pointer, 2, struct.pack("<III", wp.ms(), wp.BUTTONS["left"], 0))
p.send(p.pointer, 4)
p.settle()
PY
drag() {
  stop_pointer
  timeout 20 python3 -I "$W/drag.py" "$ROOT/tools/bench" "$@" >> "$W/ptr.log" 2>&1 || fail "drag helper failed (see $W/ptr.log)"
  start_pointer
}

wait_socket() {
  for _ in $(seq 100); do [ -S "$KURASHI_SOCKET" ] && K ping >/dev/null 2>&1 && return 0; sleep 0.1; done
  fail "$1 did not come up (see $R/server.log)"
}
start_mock() {
  rm -f "$KURASHI_SOCKET"
  RUST_LOG=info "$W/kurashi-mock" --outputs HEADLESS-1 --fixed-time 14:07 --socket "$KURASHI_SOCKET" >> "$R/server.log" 2>&1 &
  pids+=("$!")
  wait_socket mock
}
start_kurashid() {
  rm -f "$KURASHI_SOCKET"
  env DBUS_SYSTEM_BUS_ADDRESS="unix:path=$R/no-system-bus" PULSE_SERVER="unix:$R/no-pulse/native" \
      PULSE_RUNTIME_PATH="$R/no-pulse" "$W/kurashid" >> "$R/server.log" 2>&1 &
  pids+=("$!")
  wait_socket kurashid
}
start_frontend() {  # start_frontend [VAR=value ...]
  : > "$R/qs.log"
  local bare; bare=$(screen_hash)
  env -u KURASHI_SOCKET KURASHI_DOCK_GEOMETRY=1 "$@" qs -p "$ROOT/frontend" >> "$R/qs.log" 2>&1 &
  QS_PID=$!
  pids+=("$QS_PID")
  for _ in $(seq 100); do grep -q 'hello.*frontend' "$R/server.log" && break; sleep 0.1; done
  grep -q 'hello.*frontend' "$R/server.log" || fail "frontend never said hello (see $R/qs.log)"
  # Was a fixed 3 s: the frontend loaded, drew and stands still (at most 3 s for that).
  wait_frontend "$R/qs.log" 0 3 0.6 "$bare" || fail "the frontend did not load (see $R/qs.log)"
  start_pointer
}
# One virtual pointer per phase (a pointer that goes away ends every hover), made once the frontend is up.
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
shot() { timeout 20 grim "$OUT/$1.png" && echo "shot $OUT/$1.png"; }
# The bottom band without the screen's corners (K74: they follow the radius, up to 48 px): where only the dock draws.
band_ink() { ink 48 "$1" $(( SW - 96 )) 120; }
ink() {  # ink <x> <y> <w> <h>: the non-desk pixels of that region
  timeout 20 grim -g "$1,$2 ${3}x${4}" -t ppm "$W/ink.ppm"
  python3 -I "$W/ink.py" "$W/ink.ppm" "$BG"
}
# The last geometry line: "dock-geom <out> reveal <ms> urgent <keys|-> win <w> <h> <key>@<x>,<y>,<size> …" (window
# coordinates).
geom() { grep 'dock-geom' "$R/qs.log" | tail -1 | sed 's/.*dock-geom //'; }
wait_geom() {  # wait_geom <grep pattern>: a geometry line that matches
  for _ in $(seq 40); do geom | grep -q -- "$1" && return 0; sleep 0.25; done
  fail "no dock geometry matching '$1' (last: $(geom))"
}
# Screen centre of a tile (bottom edge: the window is centred on the output's bottom).
tile_xy() {
  local g ww wh t x y s
  g=$(geom); ww=$(echo "$g" | sed 's/.* win \([0-9]*\) .*/\1/'); wh=$(echo "$g" | sed 's/.* win [0-9]* \([0-9]*\).*/\1/')
  t=$(echo "$g" | tr ' ' '\n' | grep "^$1@" | head -1) || fail "no tile $1 in: $g"
  IFS=, read -r x y s <<< "${t#*@}"
  echo "$(( (SW - ww) / 2 + x + s / 2 )) $(( SH - wh + y + s / 2 ))"
}
win_focused() { K sub svc.workspaces --count 0 --json | jq -r '[.data.windows[] | select(.focused) | .id] | join(",")'; }
expect_focus() {
  local got=""
  for _ in $(seq 20); do got=$(win_focused); [ "$got" = "$1" ] && { echo "ok: $2 (focused $1)"; return 0; }; sleep 0.2; done
  fail "$2: expected window $1 focused, got '$got'"
}
mockdoc() { K act mock.doc "$1" >/dev/null; }
cfgval() {  # cfgval <key> <json value>: a user value in the mock's config document
  mockdoc "{\"doc\":\"config\",\"patch\":{\"values\":{\"$1\":{\"value\":$2,\"source\":\"user\"}}}}"
}
WINDOWS='[{"id":11,"app_id":"firefox","workspace":1,"output":"HEADLESS-1","focused":false},
 {"id":12,"app_id":"firefox","workspace":2,"output":"HEADLESS-1","focused":false},
 {"id":13,"app_id":"foot","workspace":1,"output":"HEADLESS-1","focused":true},
 {"id":14,"app_id":"net.example.NoEntry","workspace":1,"output":"HEADLESS-1","focused":false}]'
TASKS='{"*":[{"id":11,"app_id":"firefox","focused":false},{"id":13,"app_id":"foot","focused":true}],
 "HEADLESS-1":[{"id":11,"app_id":"firefox","focused":false},{"id":13,"app_id":"foot","focused":true}]}'
mock_scene() {  # mock_scene [autohide]: the fake windows, two pins, the dock on (autohide off unless given)
  mockdoc "{\"doc\":\"svc.workspaces\",\"patch\":{\"windows\":$(echo "$WINDOWS" | jq -c .),\"tasks\":$(echo "$TASKS" | jq -c .)}}"
  # K71 `dock.visibility`: autohide was `empty_desktop` (the default), off `always`.
  if [ "${1:-false}" = true ]; then cfgval dock.visibility '"empty_desktop"'; else cfgval dock.visibility '"always"'; fi
  cfgval dock.pinned '["firefox","org.gnome.Nautilus"]'
  cfgval dock.enabled true
}
dock_commits() {  # dock_commits <start byte>: commits of the dock's layer surfaces (and the shared edge strips) since then
  local ids
  ids=$(grep -oE 'wl_surface#[0-9]+, wl_output#[0-9]+, [0-9]+, "kurashi-(dock|edge)"' "$R/qs.log" | grep -oE 'wl_surface#[0-9]+' \
    | grep -oE '[0-9]+$' | paste -sd'|' - || true)
  [ -n "$ids" ] || { echo none; return 0; }
  tail -c +"$(( $1 + 1 ))" "$R/qs.log" | grep -cE "wl_surface#($ids)\.commit\(" || true
}
qml_errors() {
  if grep -E 'qml:.*(Error|error)|TypeError|ReferenceError|is not a type|Unable to assign|is not defined' "$R/qs.log" \
      | grep -v 'Unable to assign \[undefined\]' >/dev/null; then
    grep -E 'Error|error|Unable|not defined' "$R/qs.log" | head -20 >&2
    fail "QML errors (see $R/qs.log)"
  fi
}

: > "$R/server.log"

# 0. The decors' themes, as the real daemon serves them (and the layout phase's, W44).
LAYOUT_DECORS=${DOCK_LAYOUT_DECORS-washi sekai}
for d in $(echo $DECORS $LAYOUT_DECORS | tr ' ' '\n' | awk '!s[$0]++'); do
  # Motion off (W55): the steps check where the dock ends up and its dwell (`reveal <ms>`), not a slide's course.
  printf 'theme.style = "%s"\ntheme.motion.profile = "none"\n' "$d" > "$XDG_CONFIG_HOME/kurashi/config.toml"
  start_kurashid
  K sub theme --count 0 --json | jq -c '{doc: "theme", patch: .data}' > "$W/theme-$d.json"
  stop_phase
done
# The first decor in the light scheme too (W36: the dock's states in light and dark).
FIRST0=${DECORS%% *}
printf 'theme.style = "%s"\ntheme.motion.profile = "none"\n[theme.colors]\nscheme = "light"\n' "$FIRST0" > "$XDG_CONFIG_HOME/kurashi/config.toml"
start_kurashid
K sub theme --count 0 --json | jq -c '{doc: "theme", patch: .data}' > "$W/theme-$FIRST0-light.json"
stop_phase
# The first decor with its own motion too: step 1 checks the urgent tile's hop, a motion.
printf 'theme.style = "%s"\n' "$FIRST0" > "$XDG_CONFIG_HOME/kurashi/config.toml"
start_kurashid
K sub theme --count 0 --json | jq -c '{doc: "theme", patch: .data}' > "$W/theme-$FIRST0-motion.json"
stop_phase
rm -f "$XDG_CONFIG_HOME/kurashi/config.toml"

# 1. The mock: tiles, focus by click and the cycle, the menu, close, autohide (the decor's own motion: the hop).
FIRST=${DECORS%% *}
start_mock
mockdoc "$(cat "$W/theme-$FIRST-motion.json")"
start_frontend
mock_scene
mkdir -p "$OUT/$FIRST"
wait_geom 'firefox@.*org.gnome.nautilus@.*foot@.*net.example.noentry@'
echo "geometry: $(geom)"
ptr move $(( SW / 2 )) $(( SH / 2 ))
sleep 0.5
shot "$FIRST/dock"
read -r FX FY <<< "$(tile_xy firefox)"
ptr click "$FX" "$FY" left
expect_focus 11 "a click on Firefox focuses its first window"
ptr click "$FX" "$FY" left
expect_focus 12 "a second click cycles to its next window"
# The tooltip: a rest on the tile names the app.
ptr move "$FX" "$FY"
sleep 1
shot "$FIRST/tooltip"
read -r TX TY <<< "$(tile_xy foot)"
ptr click "$TX" "$TY" right
sleep 1
shot "$FIRST/menu"
keys escape
sleep 0.6
n=$(ink $(( TX - 150 )) $(( TY - 260 )) 300 200)
[ "$n" -lt 50 ] || fail "Escape did not close the menu ($n px above the tile)"
echo "ok: Escape closes the menu"
ptr click "$TX" "$TY" right
sleep 0.8
# Rows: Pin, New window, Close window → Down Down Return.
keys down down return
for _ in $(seq 20); do
  K sub svc.workspaces --count 0 --json | jq -e '[.data.windows[].id] | index(13) == null' >/dev/null && break; sleep 0.2
done
K sub svc.workspaces --count 0 --json | jq -e '[.data.windows[].id] | index(13) == null' >/dev/null \
  || fail "the menu's Close window did not close foot's window"
echo "ok: the menu's Close window closed window 13 (window.close)"
for _ in $(seq 40); do geom | grep -q 'foot@' || break; sleep 0.25; done
geom | grep -q 'foot@' && fail "foot's tile stayed after its last window closed ($(geom))"
echo "ok: foot's tile went with its window"
shot "$FIRST/closed"
# Urgent (W36, I137): the app without a desktop entry asks for attention — its tile hops, then keeps the mark.
mockdoc "{\"doc\":\"svc.workspaces\",\"patch\":{\"windows\":$(echo "$WINDOWS" | jq -c '[.[] | select(.id != 13) | .urgent = (.id == 14)]')}}"
for _ in $(seq 20); do grep -q 'dock-urgent net.example.noentry hop' "$R/qs.log" && break; sleep 0.2; done
grep -q 'dock-urgent net.example.noentry hop' "$R/qs.log" || fail "the urgent app's tile did not hop"
wait_geom 'urgent net.example.noentry '
echo "ok: an urgent window's tile hops, then keeps its mark"
sleep 1.4
shot "$FIRST/urgent"
# The mock's launcher takes kurashid's desktop ids (I137): the dock sends `firefox`, not `firefox.desktop`.
K act launcher.launch '{"id":"firefox"}' >/dev/null || fail "the mock refused launcher.launch {id: firefox}"
echo "ok: the mock's launcher.launch takes a desktop id without .desktop"
# The tile without a desktop entry: the menu offers Pin (New window inert). The mock refuses config writes: the
# dock shows no pin it was not given (Shōjiki) — the tile stays among the running apps.
read -r NX NY <<< "$(tile_xy net.example.noentry)"
ptr click "$NX" "$NY" right
sleep 0.8
shot "$FIRST/menu-no-entry"
keys return
sleep 0.8
geom | grep -q 'org.gnome.nautilus@[^ ]* net.example.noentry@' \
  || fail "a refused pin moved the tile ($(geom))"
echo "ok: a refused pin changes nothing"
keys escape
sleep 0.5
# Autohide: away from the dock it hides; a rest on the edge reveals it; leaving hides it again.
ptr move $(( SW / 2 )) $(( SH / 2 ))
cfgval dock.visibility '"empty_desktop"'
BAND_Y=$(( SH - 120 ))
# (The fixed 1.2 / 1.2 / 1.4 s are now at most that long: until the band shows what the check wants. Each starts from
# the other state, so a wait that ends early has seen the change.)
wait_until 1.2 eval '[ "$(band_ink "$BAND_Y")" -lt 50 ]' || true
n=$(band_ink "$BAND_Y")
[ "$n" -lt 50 ] || fail "autohide: the dock still shows ($n px)"
echo "ok: autohide hides the dock ($n px)"
ptr move $(( SW / 2 )) $(( SH - 1 ))
wait_until 1.2 eval '[ "$(band_ink "$BAND_Y")" -gt 500 ]' || true
n=$(band_ink "$BAND_Y")
[ "$n" -gt 500 ] || fail "autohide: a rest on the edge did not reveal the dock ($n px)"
echo "ok: a rest on the bottom edge reveals the dock ($n px)"
wait_settled 1.2 0.4 "0,$(( SH - 240 )) ${SW}x240"   # (the slide ended: the shot at rest)
shot "$FIRST/revealed"
ptr move $(( SW / 2 )) $(( SH / 2 ))
wait_until 1.4 eval '[ "$(band_ink "$BAND_Y")" -lt 50 ]' || true
n=$(band_ink "$BAND_Y")
[ "$n" -lt 50 ] || fail "autohide: the dock stayed after the pointer left ($n px)"
echo "ok: the dock hides after the pointer left ($n px)"
qml_errors
stop_phase

# 2. The real kurashid: Unpin by the menu writes dock.pinned.
printf 'theme.style = "%s"\ntheme.motion.profile = "none"\n[dock]\nenabled = true\nvisibility = "always"\npinned = ["firefox", "org.gnome.Nautilus"]\n' "$FIRST" \
  > "$XDG_CONFIG_HOME/kurashi/config.toml"
: > "$R/server.log"
start_kurashid
start_frontend
wait_geom 'firefox@.*org.gnome.nautilus@'
# Drag Files before Firefox (W36, I137): one write of the new order.
read -r FX FY <<< "$(tile_xy firefox)"
read -r NX NY <<< "$(tile_xy org.gnome.nautilus)"
drag "$NX" "$NY" $(( FX - 6 )) "$FY"
pinned=""
for _ in $(seq 20); do
  pinned=$(K sub config --count 0 --json | jq -c '.data.values["dock.pinned"].value')
  [ "$pinned" = '["org.gnome.Nautilus","firefox"]' ] && break; sleep 0.2
done
[ "$pinned" = '["org.gnome.Nautilus","firefox"]' ] || fail "dragging Files before Firefox did not reorder dock.pinned (got $pinned)"
wait_geom 'org.gnome.nautilus@.*firefox@'
echo "ok: a drag reordered the pins: dock.pinned = $pinned (real kurashid)"
shot "$FIRST/reordered"
read -r FX FY <<< "$(tile_xy firefox)"
ptr click "$FX" "$FY" right
sleep 0.8
shot "$FIRST/real-menu"
keys return
pinned=""
for _ in $(seq 20); do
  pinned=$(K sub config --count 0 --json | jq -c '.data.values["dock.pinned"].value')
  [ "$pinned" = '["org.gnome.Nautilus"]' ] && break; sleep 0.2
done
[ "$pinned" = '["org.gnome.Nautilus"]' ] || fail "Unpin did not write dock.pinned (got $pinned)"
echo "ok: Unpin from dock wrote dock.pinned = $pinned (real kurashid)"
wait_geom 'win [0-9]* [0-9]* org.gnome.nautilus@[^ ]*$'
echo "ok: the Firefox tile went"
qml_errors
stop_phase
rm -f "$XDG_CONFIG_HOME/kurashi/config.toml"

# 3. Looks under every decor (the mock wearing the daemon's theme).
for d in $DECORS; do
  mkdir -p "$OUT/$d"
  start_mock
  mockdoc "$(cat "$W/theme-$d.json")"
  start_frontend
  mock_scene
  wait_geom 'net.example.noentry@'
  ptr move $(( SW / 2 )) $(( SH / 2 ))
  sleep 0.6
  timeout 20 grim -g "0,$(( SH - 200 )) ${SW}x200" "$OUT/$d/look.png" && echo "shot $OUT/$d/look.png"
  if [ "$d" = "$FIRST" ]; then
    # The left edge, then the empty state (nothing pinned, nothing running: one tile that opens the launcher).
    cfgval dock.edge '"left"'
    wait_geom 'win [0-9]* [0-9]* firefox@'
    sleep 0.6
    timeout 20 grim -g "0,$(( SH / 2 - 300 )) 300x600" "$OUT/$d/left.png" && echo "shot $OUT/$d/left.png"
    cfgval dock.edge '"bottom"'
    cfgval dock.pinned '[]'
    mockdoc '{"doc":"svc.workspaces","patch":{"windows":[]}}'
    wait_geom 'win [0-9]* [0-9]* +@[^ ]*$'
    sleep 0.6
    timeout 20 grim -g "0,$(( SH - 200 )) ${SW}x200" "$OUT/$d/empty.png" && echo "shot $OUT/$d/empty.png"
  fi
  qml_errors
  stop_phase
done
# 4. Cost (opt-in: DOCK_MEASURE=1).
if [ "${DOCK_MEASURE:-0}" = 1 ]; then
  uss_mib() { awk '/^Private_(Clean|Dirty):/{s+=$2} END{printf "%.2f", s/1024}' "/proc/$1/smaps_rollup"; }
  median() { python3 -I -c 'import statistics,sys; print(round(statistics.median([float(x) for x in sys.argv[1:]]), 2))' "$@"; }
  size() { stat -c %s "$R/qs.log"; }
  dock_commits() {  # dock_commits <start byte>: commits of the dock's layer surfaces since that offset
    local ids
    ids=$(grep -oE 'wl_surface#[0-9]+, wl_output#[0-9]+, [0-9]+, "kurashi-(dock|edge)"' "$R/qs.log" | grep -oE 'wl_surface#[0-9]+' \
      | grep -oE '[0-9]+$' | paste -sd'|' - || true)
    [ -n "$ids" ] || { echo none; return 0; }
    tail -c +"$(( $1 + 1 ))" "$R/qs.log" | grep -cE "wl_surface#($ids)\.commit\(" || true
  }
  scene_hidden() { mock_scene true; }
  start_mock; mockdoc "$(cat "$W/theme-$FIRST.json")"
  start_frontend WAYLAND_DEBUG=1
  scene_hidden
  sleep 5; c0=$(size); sleep 10; hid=$(dock_commits "$c0")
  cfgval dock.visibility '"always"'
  sleep 5; c0=$(size); sleep 10; shown=$(dock_commits "$c0")
  stop_phase
  [ "$hid" = 0 ] || fail "idle: the hidden dock committed $hid times in 10 s"
  [ "$shown" = 0 ] || fail "idle: the shown dock committed $shown times in 10 s"
  echo "ok: idle 0 commits in 10 s hidden, 0 shown"
  on_u=""; off_u=""; shown_u=""
  for rep in 1 2 3; do
    for run in on off; do
      start_mock; mockdoc "$(cat "$W/theme-$FIRST.json")"
      start_frontend
      if [ "$run" = on ]; then scene_hidden; else mockdoc "{\"doc\":\"svc.workspaces\",\"patch\":{\"windows\":$(echo "$WINDOWS" | jq -c .),\"tasks\":$(echo "$TASKS" | jq -c .)}}"; fi
      sleep 10
      u=$(uss_mib "$QS_PID")
      if [ "$run" = on ]; then
        on_u="$on_u $u"
        if [ "$rep" = 1 ]; then cfgval dock.visibility '"always"'; sleep 6; shown_u=$(uss_mib "$QS_PID"); fi
      else off_u="$off_u $u"; fi
      stop_phase
    done
  done
  m_on=$(median $on_u); m_off=$(median $off_u)
  echo "measure: USS dock on (hidden, edge window only) ${m_on} MiB, off ${m_off} MiB: per output $(python3 -I -c "print(round(${m_on} - ${m_off}, 2))") MiB (runs on:${on_u} off:${off_u})"
  echo "measure: the first show (run 1): +$(python3 -I -c "print(round(${shown_u} - $(echo $on_u | awk '{print $1}'), 2))") MiB USS over hidden (the dock window, made then kept)"
fi
# The first decor in the light scheme: the dock, an urgent app, the left edge and the empty state.
LOUT=$OUT/$FIRST-light
mkdir -p "$LOUT"
start_mock
mockdoc "$(cat "$W/theme-$FIRST-light.json")"
start_frontend
mock_scene
wait_geom 'net.example.noentry@'
ptr move $(( SW / 2 )) $(( SH / 2 ))
sleep 0.6
timeout 20 grim -g "0,$(( SH - 200 )) ${SW}x200" "$LOUT/look.png" && echo "shot $LOUT/look.png"
mockdoc "{\"doc\":\"svc.workspaces\",\"patch\":{\"windows\":$(echo "$WINDOWS" | jq -c '[.[] | .urgent = (.id == 14)]')}}"
wait_geom 'urgent net.example.noentry '
sleep 1.4
timeout 20 grim -g "0,$(( SH - 200 )) ${SW}x200" "$LOUT/urgent.png" && echo "shot $LOUT/urgent.png"
cfgval dock.edge '"left"'
wait_geom 'win [0-9]* [0-9]* firefox@'
sleep 0.6
timeout 20 grim -g "0,$(( SH / 2 - 300 )) 300x600" "$LOUT/left.png" && echo "shot $LOUT/left.png"
cfgval dock.edge '"bottom"'
cfgval dock.pinned '[]'
mockdoc '{"doc":"svc.workspaces","patch":{"windows":[]}}'
wait_geom 'win [0-9]* [0-9]* +@[^ ]*$'
sleep 0.6
timeout 20 grim -g "0,$(( SH - 200 )) ${SW}x200" "$LOUT/empty.png" && echo "shot $LOUT/empty.png"
qml_errors
stop_phase

# 6. Draw modes and visibility from runtime.layout (K71, W44; docs/ux/layout.md's mode table): under washi and sekai, a
#    top and a bottom bar, the frame off and on, each of floating / dynamic / connected (the mock computes the layout
#    from its config as kurashid does). Asserted from the geometry line and the pixels at the dock's base: floating
#    stands a gap off the band or bar (the gap under it is the desk); dynamic sits on it with a concave fillet beside its
#    base (ink just outside its corner); connected sits on it with straight sides (desk there). Shots
#    frontend/shots/dock/layout/<decor>/<bar>-frame<off|on>-<draw>.png. Then visibility through the shared edge strip
#    (`hover`: a dwell on the edge reveals it, a pointer resting there keeps it, leaving hides it; `hidden`: only while
#    runtime.ui.shown lists dock@HEADLESS-1; `empty_desktop`: shown on an empty desk) and idle commits at rest (0).
LOUT=$OUT/layout
geomf() { geom | tr ' ' '\n' | grep -A1 -x -- "$1" | tail -1; }   # a field of the last geometry line
# The bar on `top` or `bottom`, with a few modules (layout.bar.move's result; the other edge's zones empty).
setbar() {
  local on=$1 off=top
  [ "$on" = top ] && off=bottom
  cfgval "edges.$off.bar" false; cfgval "edges.$on.bar" true
  for z in start center end; do cfgval "edges.$off.$z" '[]'; done
  cfgval "edges.$on.start" '["workspaces"]'; cfgval "edges.$on.center" '["island"]'; cfgval "edges.$on.end" '["clock","quick"]'
}
px1() { [ "$(ink "$1" "$2" 1 1)" -gt 0 ] && echo ink || echo desk; }
for d in $LAYOUT_DECORS; do
  mkdir -p "$LOUT/$d"
  start_mock
  mockdoc "$(cat "$W/theme-$d.json")"
  start_frontend
  mock_scene
  ptr move $(( SW / 2 )) $(( SH / 2 ))
  for bar in top bottom; do
    setbar "$bar"
    for frame in off on; do
      if [ "$frame" = on ]; then cfgval layout.frame.enabled true; else cfgval layout.frame.enabled false; fi
      for draw in floating dynamic connected; do
        cfgval layout.draw "\"$draw\""
        wait_geom "draw $draw "
        # The layout's inset for the dock (the document is the truth: never re-derived here).
        want=$(K sub runtime.layout --count 0 --json | jq -r '.data.outputs["HEADLESS-1"].dock.inset')
        for _ in $(seq 20); do [ "$(geomf inset)" = "$want" ] && break; sleep 0.25; done
        [ "$(geomf inset)" = "$want" ] || fail "$d $bar frame $frame $draw: the dock stands at $(geomf inset), the layout says $want ($(geom))"
        # Was a fixed 0.8 s: the dock's corner of the screen stands still (at most 0.8 s).
        wait_settled 0.8 0.3 "$(( SW / 2 - 350 )),$(( SH - 220 )) 700x220"
        IFS=, read -r BX BY BW BH <<< "$(geomf body)"
        WW=$(geomf win); left=$(( (SW - WW) / 2 + BX ))
        base=$(( SH - want ))
        tag="$d $bar frame $frame $draw"
        [ "$(px1 $(( SW / 2 )) $(( base - 3 )))" = ink ] || fail "$tag: no dock at its base (y $(( base - 3 )))"
        case $draw in
          floating) # the gap under it: the desk, unless a band or a bar lies there
            if [ "$bar" = top ] && [ "$frame" = off ]; then
              [ "$(px1 $(( SW / 2 )) $(( SH - 2 )))" = desk ] || fail "$tag: the floating dock touches the screen's edge"
            fi
            [ "$(px1 $(( left - 3 )) $(( base - 2 )))" = desk ] || fail "$tag: something beside the floating dock's base" ;;
          dynamic) # K74: the fillet's radius is the layout's (R less the band on a framed output: washi's 9 − 8 = 1 px)
            jr=$(K sub runtime.layout --count 0 --json | jq -r '.data.outputs["HEADLESS-1"].dock.radius')
            if [ "${jr:-0}" -ge 4 ]; then
              [ "$(px1 $(( left - 2 )) $(( base - 2 )))" = ink ] || fail "$tag: no fillet beside the dock's base (radius $jr)"
            else
              echo "test-dock: $tag: the join's radius is $jr px (K74), the fillet is not pixel-checked"
            fi ;;
          connected) [ "$(px1 $(( left - 3 )) $(( base - 2 )))" = desk ] || fail "$tag: the connected dock's side is not straight" ;;
        esac
        timeout 20 grim -g "$(( SW / 2 - 350 )),$(( SH - 220 )) 700x220" "$LOUT/$d/$bar-frame$frame-$draw.png" \
          && echo "shot $LOUT/$d/$bar-frame$frame-$draw.png"
        echo "ok: $tag: inset $want, $(geomf joins) joins"
      done
    done
  done
  qml_errors
  if [ "$d" = "${LAYOUT_DECORS%% *}" ]; then
    # Visibility through the shared strip (no window of the dock's own: the strips' namespace is kurashi-edge).
    setbar top; cfgval layout.frame.enabled false; cfgval layout.draw '"dynamic"'
    cfgval dock.visibility '"hover"'
    # (The waits that end in a change are at most their old fixed time, until the band shows the change; the 2 s rest
    # and the `hidden` second stay: they check that nothing changes.)
    ptr move $(( SW / 2 )) $(( SH / 2 ))
    wait_until 1.2 eval '[ "$(band_ink $(( SH - 120 )))" -lt 50 ]' || true
    n=$(band_ink $(( SH - 120 )))
    [ "$n" -lt 50 ] || fail "hover: the dock shows away from the edge ($n px)"
    ptr move $(( SW / 2 + 300 )) $(( SH - 1 ))
    wait_until 1.2 eval '[ "$(band_ink $(( SH - 120 )))" -gt 500 ]' || true
    n=$(band_ink $(( SH - 120 )))
    [ "$n" -gt 500 ] || fail "hover: a rest on the edge did not reveal the dock ($n px)"
    sleep 2
    n=$(band_ink $(( SH - 120 )))
    [ "$n" -gt 500 ] || fail "hover: the dock went while the pointer rested on the edge ($n px)"
    timeout 20 grim -g "$(( SW / 2 - 350 )),$(( SH - 220 )) 700x220" "$LOUT/$d/hover-revealed.png"
    ptr move $(( SW / 2 )) $(( SH / 2 ))
    wait_until 1.4 eval '[ "$(band_ink $(( SH - 120 )))" -lt 50 ]' || true
    n=$(band_ink $(( SH - 120 )))
    [ "$n" -lt 50 ] || fail "hover: the dock stayed after the pointer left ($n px)"
    echo "ok: hover: the dwell reveals it, a resting pointer keeps it, leaving hides it"
    cfgval dock.visibility '"hidden"'
    sleep 1
    [ "$(band_ink $(( SH - 120 )))" -lt 50 ] || fail "hidden: the dock shows"
    mockdoc '{"doc":"runtime.ui","patch":{"shown":["dock@HEADLESS-1"]}}'
    wait_until 1.2 eval '[ "$(band_ink $(( SH - 120 )))" -gt 500 ]' || true
    [ "$(band_ink $(( SH - 120 )))" -gt 500 ] || fail "hidden: runtime.ui.shown did not bring the dock out"
    mockdoc '{"doc":"runtime.ui","patch":{"shown":[]}}'
    wait_until 1.2 eval '[ "$(band_ink $(( SH - 120 )))" -lt 50 ]' || true
    [ "$(band_ink $(( SH - 120 )))" -lt 50 ] || fail "hidden: the dock stayed after shown dropped it"
    echo "ok: hidden: out only while runtime.ui.shown lists dock@HEADLESS-1"
    cfgval dock.visibility '"empty_desktop"'
    mockdoc '{"doc":"svc.workspaces","patch":{"tasks":{"*":[],"HEADLESS-1":[]}}}'
    wait_until 1.2 eval '[ "$(band_ink $(( SH - 120 )))" -gt 500 ]' || true
    [ "$(band_ink $(( SH - 120 )))" -gt 500 ] || fail "empty_desktop: the dock is not shown on an empty desk"
    echo "ok: empty_desktop: shown on an empty desk"
    qml_errors
    stop_phase
    # Ma: a hover dock at rest, hidden and revealed (the pointer resting on the edge), commits no frame in 5 s.
    start_mock; mockdoc "$(cat "$W/theme-$d.json")"
    start_frontend WAYLAND_DEBUG=1
    mock_scene
    cfgval dock.visibility '"hover"'
    ptr move $(( SW / 2 )) $(( SH / 2 ))
    # (Each fixed 3 s before a window is now: no commit for 1 s, at most 3 s. The 5 s windows stay.)
    wait_log_quiet "$R/qs.log" 'wl_surface#[0-9]*\.commit\(' 1 3
    c0=$(stat -c %s "$R/qs.log"); sleep 5; hid=$(dock_commits "$c0")
    ptr move $(( SW / 2 + 300 )) $(( SH - 1 ))
    wait_log_quiet "$R/qs.log" 'wl_surface#[0-9]*\.commit\(' 1 3
    c0=$(stat -c %s "$R/qs.log"); sleep 5; out=$(dock_commits "$c0")
    [ "$hid" = 0 ] || [ "$hid" = none ] || fail "idle: the hover dock, hidden, committed $hid times in 5 s"
    [ "$out" = 0 ] || fail "idle: the revealed dock at rest committed $out times in 5 s"
    echo "ok: idle: a hover dock at rest commits nothing (hidden: $hid, revealed: $out)"
  fi
  stop_phase
done
# 7. (W44-follow) The joined dock's paper: the real kurashid with washi and the paper material on the shell; floating,
#    dynamic and connected, on the screen's edge and on a bottom bar. A joined dock carries the look's relief as the
#    floating Block does — its body's padding row is not one flat colour — and, on a bar under a ruled chrome, opens the
#    bar's rule under itself (BARRULE: the gap covers the dock's base). Shots frontend/shots/dock/layout/washi-paper/.
if [ -z "${DOCK_SKIP_PAPER:-}" ]; then
  POUT=$LOUT/washi-paper
  mkdir -p "$POUT"
  printf 'idle.enabled = false\ntheme.style = "washi"\ntheme.motion.profile = "none"\ntheme.texture.kind = "paper"\ntheme.texture.strength = 1.5\n' \
    > "$XDG_CONFIG_HOME/kurashi/config.toml"
  printf 'dock.enabled = true\ndock.visibility = "always"\ndock.pinned = ["firefox", "org.gnome.Nautilus", "foot"]\n' \
    >> "$XDG_CONFIG_HOME/kurashi/config.toml"
  start_kurashid
  for _ in $(seq 100); do [ -n "$(K sub theme --count 0 --json | jq -r '.data.tokens["texture.map"] // ""')" ] && break; sleep 0.2; done
  start_frontend KURASHI_BAR_GEOMETRY=1
  # The distinct colours along a row of the screen: "<n>".
  colours() { timeout 20 grim -g "$1,$2 ${3}x1" -t ppm "$W/row.ppm"; python3 -I -c '
import sys
d = open(sys.argv[1], "rb").read()
f, i = [], 0
while len(f) < 4:
    while d[i:i + 1].isspace(): i += 1
    j = i
    while not d[j:j + 1].isspace(): j += 1
    f.append(d[i:j]); i = j
p = d[i + 1:]
print(len({p[k:k + 3] for k in range(0, len(p) - 2, 3)}))' "$W/row.ppm"; }
  for where in edge bar; do
    [ "$where" = bar ] && { K set edges.bottom.bar=true >/dev/null || fail "edges.bottom.bar = true refused"; }
    for draw in floating dynamic connected; do
      K set "dock.draw=\"$draw\"" >/dev/null || fail "dock.draw = $draw refused"
      wait_geom "draw $draw "
      # Was a fixed 1.2 s: the dock's part of the screen stands still (at most 1.2 s).
      wait_settled 1.2 0.4 "0,$(( SH - 240 )) ${SW}x240"
      inset=$(K sub runtime.layout --count 0 --json | jq -r '.data.outputs["HEADLESS-1"].dock.inset')
      IFS=, read -r BX BY BW BH <<< "$(geomf body)"
      WW=$(geomf win); left=$(( (SW - WW) / 2 + BX ))
      # A row of the body's top padding, over the tiles (the body stands `inset` from the screen's edge, BH tall with its
      # hard shadow), clear of its rounded corners.
      n=$(colours $(( left + 24 )) $(( SH - inset - BH + 4 )) $(( BW - 48 )))
      tag="paper $where $draw"
      [ "$n" -ge 6 ] && echo "ok: $tag: the dock's body carries the relief ($n colours along its padding row)" \
        || fail "$tag: the dock's body is flat ($n colours along its padding row): no material"
      if [ "$where" = bar ] && [ "$draw" != floating ]; then
        r=$(grep -o 'BARRULE HEADLESS-1 bottom .*' "$R/qs.log" | tail -1 | sed 's/BARRULE HEADLESS-1 bottom //')
        # Two segments, the gap between them covering the dock's base.
        g0=$(sed -n 's/^0-\([0-9]*\),\([0-9]*\)-[0-9]*$/\1/p' <<< "$r"); g1=$(sed -n 's/^0-\([0-9]*\),\([0-9]*\)-[0-9]*$/\2/p' <<< "$r")
        [ -n "$g0" ] && [ "$g0" -le "$left" ] && [ "$g1" -ge $(( left + BW )) ] \
          && echo "ok: $tag: the bar's rule opens under the dock ($r; base $left..$(( left + BW )))" \
          || fail "$tag: the bar's rule is '$r', it does not open under the dock's base $left..$(( left + BW ))"
      fi
      timeout 20 grim -s 2 -g "$(( SW / 2 - 200 )),$(( SH - 120 )) 400x120" "$POUT/$where-$draw.png" && echo "shot $POUT/$where-$draw.png"
    done
  done
  qml_errors
  stop_phase
  rm -f "$XDG_CONFIG_HOME/kurashi/config.toml"
fi

# 5. A shared edge (I137): HEADLESS-2 comes to the right of HEADLESS-1; a right-edge dock on HEADLESS-1 reveals after
# 500 ms (the pointer crosses that edge on its way to the other output), HEADLESS-2's outer edge after 250 ms.
timeout 20 "$ROOT/tools/bench/sandbox.sh" output-add "$NAME" >/dev/null || fail "output-add failed"
# Was a fixed 2 s: until sway lists the second output (at most 2 s).
wait_until 2 eval '[ "$(swaymsg -t get_outputs -r | jq length)" -ge 2 ]' || true
start_mock
mockdoc "$(cat "$W/theme-$FIRST.json")"
start_frontend
mock_scene
cfgval dock.edge '"right"'
reveal_of() { { grep "dock-geom $1 " "$R/qs.log" | tail -1 | sed -n 's/.* reveal \([0-9]*\) .*/\1/p'; } || true; }
r1=""; r2=""
for _ in $(seq 40); do
  r1=$(reveal_of HEADLESS-1); r2=$(reveal_of HEADLESS-2)
  [ "$r1" = 500 ] && [ "$r2" = 250 ] && break; sleep 0.25
done
[ "$r1" = 500 ] || fail "the dock on HEADLESS-1's shared right edge reveals after '$r1' ms, want 500"
[ "$r2" = 250 ] || fail "the dock on HEADLESS-2's outer right edge reveals after '$r2' ms, want 250"
echo "ok: reveal 500 ms on the shared edge, 250 ms on the outer one"
qml_errors
stop_phase
echo "test-dock: ok (shots in $OUT)"
