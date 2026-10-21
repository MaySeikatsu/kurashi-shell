#!/usr/bin/env bash
# The app dock (K51, docs/ux/dock.md), invisibly (headless sway sandbox), by a virtual pointer and keyboard:
#   1. kurashi-mock with fake windows (firefox ×2, foot focused, an app with no desktop entry) and two pins (firefox,
#      Files): the dock shows pinned then running tiles; a click on Firefox focuses its first window, a second click
#      the next one (the cycle); right-click on foot → the menu (shot) → Escape; right-click → "Close window" removes
#      foot's window (`window.close`); autohide: the dock hides, a rest on the bottom edge reveals it, leaving hides it;
#   2. the REAL kurashid: the dock with its pins; right-click Firefox → "Unpin from dock" writes `dock.pinned`
#      (one cfg.apply), and the tile goes;
#   3. looks: the dock under the decors sekai, glass, terminal and none (the real daemon's theme worn by the mock);
#   4. with DOCK_MEASURE=1: idle commits of the dock's surfaces (hidden and shown, 10 s each) and its USS per output
#      (dock on and hidden vs off, medians of three alternating runs; shown vs hidden once) — docs/BENCH.md "Mods".
#   nix develop -c frontend/test-dock.sh [sandbox-name]
# Binaries: kurashid, kurashi and kurashi-mock from $KURASHI_BIN_DIR (default $CARGO_TARGET_DIR/debug or target/debug).
# Shots in frontend/shots/dock/<decor>/. On a hybrid laptop export KURASHI_RENDER_NODE first.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
NAME=${1:-w25-dck-test}
BIN=${KURASHI_BIN_DIR:-${CARGO_TARGET_DIR:-$ROOT/target}/debug}
OUT=$ROOT/frontend/shots/dock
DECORS=${DOCK_DECORS:-sekai glass terminal none}
mkdir -p "$OUT"
fail() { echo "test-dock: FAIL: $*" >&2; exit 1; }

eval "$("$ROOT/tools/bench/sandbox.sh" start "$NAME")"
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
  env -u KURASHI_SOCKET KURASHI_DOCK_GEOMETRY=1 "$@" qs -p "$ROOT/frontend" >> "$R/qs.log" 2>&1 &
  QS_PID=$!
  pids+=("$QS_PID")
  for _ in $(seq 100); do grep -q 'hello.*frontend' "$R/server.log" && break; sleep 0.1; done
  grep -q 'hello.*frontend' "$R/server.log" || fail "frontend never said hello (see $R/qs.log)"
  sleep 3
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
ink() {  # ink <x> <y> <w> <h>: the non-desk pixels of that region
  timeout 20 grim -g "$1,$2 ${3}x${4}" -t ppm "$W/ink.ppm"
  python3 -I "$W/ink.py" "$W/ink.ppm" "$BG"
}
# The last geometry line: "dock-geom <out> win <w> <h> <key>@<x>,<y>,<size> …" (window coordinates).
geom() { grep 'dock-geom' "$R/qs.log" | tail -1 | sed 's/.*dock-geom //'; }
wait_geom() {  # wait_geom <grep pattern>: a geometry line that matches
  for _ in $(seq 40); do geom | grep -q -- "$1" && return 0; sleep 0.25; done
  fail "no dock geometry matching '$1' (last: $(geom))"
}
# Screen centre of a tile (bottom edge: the window is centred on the output's bottom).
tile_xy() {
  local g ww wh t x y s
  g=$(geom); ww=$(echo "$g" | awk '{print $3}'); wh=$(echo "$g" | awk '{print $4}')
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
  cfgval dock.autohide "${1:-false}"
  cfgval dock.pinned '["firefox","org.gnome.Nautilus"]'
  cfgval dock.enabled true
}
qml_errors() {
  if grep -E 'qml:.*(Error|error)|TypeError|ReferenceError|is not a type|Unable to assign|is not defined' "$R/qs.log" \
      | grep -v 'Unable to assign \[undefined\]' >/dev/null; then
    grep -E 'Error|error|Unable|not defined' "$R/qs.log" | head -20 >&2
    fail "QML errors (see $R/qs.log)"
  fi
}

: > "$R/server.log"

# 0. The decors' themes, as the real daemon serves them.
for d in $DECORS; do
  printf 'theme.style = "%s"\n' "$d" > "$XDG_CONFIG_HOME/kurashi/config.toml"
  start_kurashid
  K sub theme --count 0 --json | jq -c '{doc: "theme", patch: .data}' > "$W/theme-$d.json"
  stop_phase
done
rm -f "$XDG_CONFIG_HOME/kurashi/config.toml"

# 1. The mock: tiles, focus by click and the cycle, the menu, close, autohide.
FIRST=${DECORS%% *}
start_mock
mockdoc "$(cat "$W/theme-$FIRST.json")"
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
cfgval dock.autohide true
sleep 1.2
BAND_Y=$(( SH - 120 ))
n=$(ink 0 "$BAND_Y" "$SW" 120)
[ "$n" -lt 50 ] || fail "autohide: the dock still shows ($n px)"
echo "ok: autohide hides the dock ($n px)"
ptr move $(( SW / 2 )) $(( SH - 1 ))
sleep 1.2
n=$(ink 0 "$BAND_Y" "$SW" 120)
[ "$n" -gt 500 ] || fail "autohide: a rest on the edge did not reveal the dock ($n px)"
echo "ok: a rest on the bottom edge reveals the dock ($n px)"
shot "$FIRST/revealed"
ptr move $(( SW / 2 )) $(( SH / 2 ))
sleep 1.4
n=$(ink 0 "$BAND_Y" "$SW" 120)
[ "$n" -lt 50 ] || fail "autohide: the dock stayed after the pointer left ($n px)"
echo "ok: the dock hides after the pointer left ($n px)"
qml_errors
stop_phase

# 2. The real kurashid: Unpin by the menu writes dock.pinned.
printf 'theme.style = "%s"\n[dock]\nenabled = true\nautohide = false\npinned = ["firefox", "org.gnome.Nautilus"]\n' "$FIRST" \
  > "$XDG_CONFIG_HOME/kurashi/config.toml"
: > "$R/server.log"
start_kurashid
start_frontend
wait_geom 'firefox@.*org.gnome.nautilus@'
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
    ids=$(grep -oE 'wl_surface#[0-9]+, wl_output#[0-9]+, [0-9]+, "kurashi-dock(-edge)?"' "$R/qs.log" | grep -oE 'wl_surface#[0-9]+' \
      | grep -oE '[0-9]+$' | paste -sd'|' - || true)
    [ -n "$ids" ] || { echo none; return 0; }
    tail -c +"$(( $1 + 1 ))" "$R/qs.log" | grep -cE "wl_surface#($ids)\.commit\(" || true
  }
  scene_hidden() { mock_scene true; }
  start_mock; mockdoc "$(cat "$W/theme-$FIRST.json")"
  start_frontend WAYLAND_DEBUG=1
  scene_hidden
  sleep 5; c0=$(size); sleep 10; hid=$(dock_commits "$c0")
  cfgval dock.autohide false
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
        if [ "$rep" = 1 ]; then cfgval dock.autohide false; sleep 6; shown_u=$(uss_mib "$QS_PID"); fi
      else off_u="$off_u $u"; fi
      stop_phase
    done
  done
  m_on=$(median $on_u); m_off=$(median $off_u)
  echo "measure: USS dock on (hidden, edge window only) ${m_on} MiB, off ${m_off} MiB: per output $(python3 -I -c "print(round(${m_on} - ${m_off}, 2))") MiB (runs on:${on_u} off:${off_u})"
  echo "measure: the first show (run 1): +$(python3 -I -c "print(round(${shown_u} - $(echo $on_u | awk '{print $1}'), 2))") MiB USS over hidden (the dock window, made then kept)"
fi
echo "test-dock: ok (shots in $OUT)"
