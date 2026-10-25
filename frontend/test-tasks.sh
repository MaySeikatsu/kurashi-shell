#!/usr/bin/env bash
# The bar's window list (W36; docs/ux/window-list.md) and the side bar's layout chip and REC dot (I131), invisibly
# (headless sway sandbox), by a virtual pointer and keyboard against kurashi-mock wearing the real daemon's theme, for
# each colour scheme (light, dark):
#   1. a top bar: one button per window of the active workspace, the icon chain (a desktop entry's icon, an entry found
#      by StartupWMClass, an icon named after the app id, the first letter, the window symbol for no app id); the peek
#      fetches the title on a rest (`window.title`); the menu (right click) closes by keyboard (Down… Return); a middle
#      click closes; a drag onto workspace chip 2 moves the window (`window.move`, the view follows); an urgent window
#      hops then keeps its dot, and does not hop with reduced motion; many windows end in "+N"; an empty workspace
#      shows no list;
#   2. a left bar: the same list in a column under the workspaces (middle click, drag, peek, urgent, "+N"), and the
#      recording mark and the layout chip inside the bar's width, in the lower column, not overlapping.
#   nix develop -c frontend/test-tasks.sh [sandbox-name]
# Binaries: kurashid, kurashi and kurashi-mock from $KURASHI_BIN_DIR (default $CARGO_TARGET_DIR/debug or target/debug).
# Shots in frontend/shots/tasks/<scheme>/. On a hybrid laptop export KURASHI_RENDER_NODE first.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
NAME=${1:-w36-bar-tasks}
BIN=${KURASHI_BIN_DIR:-${CARGO_TARGET_DIR:-$ROOT/target}/debug}
OUT=$ROOT/frontend/shots/tasks
SCHEMES=${TASKS_SCHEMES:-light dark}
STYLE=${TASKS_STYLE:-sekai}
mkdir -p "$OUT"
fail() { echo "test-tasks: FAIL: $*" >&2; exit 1; }

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
# Hermetic apps (the host's entries stay out): desktop entries with plain SVG icons (hicolor).
SHARE=$R/xdg/share
export XDG_DATA_DIRS=$SHARE
mkdir -p "$SHARE/applications" "$SHARE/icons/hicolor/scalable/apps"
printf '[Icon Theme]\nName=Hicolor\nDirectories=scalable/apps\n\n[scalable/apps]\nSize=48\nMinSize=16\nMaxSize=512\nType=Scalable\n' \
  > "$SHARE/icons/hicolor/index.theme"
icon() {  # icon <name> <colour> <letter>
  printf '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 48 48"><rect x="4" y="4" width="40" height="40" rx="11" fill="%s"/><text x="24" y="33" font-size="24" font-family="sans-serif" font-weight="bold" text-anchor="middle" fill="#fff">%s</text></svg>\n' \
    "$2" "$3" > "$SHARE/icons/hicolor/scalable/apps/$1.svg"
}
app() {  # app <id> <name> <colour> <letter> [StartupWMClass]
  printf '[Desktop Entry]\nType=Application\nName=%s\nExec=true\nIcon=%s\n' "$2" "$1" > "$SHARE/applications/$1.desktop"
  [ -z "${5:-}" ] || printf 'StartupWMClass=%s\n' "$5" >> "$SHARE/applications/$1.desktop"
  icon "$1" "$3" "$4"
}
app firefox Firefox '#e66000' F
app foot Foot '#3b6ea5' T
# Found only by its StartupWMClass (the window's app id differs in case and from the desktop id).
app org.gimp.GIMP GIMP '#5c5543' G gimp-2.99
# No desktop entry, but an icon named after the app id's last part.
icon iconic '#7a4fa0' I
K() { timeout 10 "$W/kurashi" "$@"; }
BG='#8fb8c8'
swaymsg output '*' bg "$BG" solid_color >/dev/null 2>&1 || true
SW=$(swaymsg -t get_outputs -r | jq -r '.[] | select(.name == "HEADLESS-1") | .rect.width')
SH=$(swaymsg -t get_outputs -r | jq -r '.[] | select(.name == "HEADLESS-1") | .rect.height')

# A drag: press at one point, travel, release at another (wl_pointer.py has clicks only; this reuses its pointer).
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
start_frontend() {
  : > "$R/qs.log"
  env -u KURASHI_SOCKET KURASHI_TASKS_LOG=1 KURASHI_BAR_GEOMETRY=1 qs -p "$ROOT/frontend" >> "$R/qs.log" 2>&1 &
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
drag() {  # drag x0 y0 x1 y1: the serve pointer steps aside (one pointer at a time), then comes back
  stop_pointer
  timeout 20 python3 -I "$W/drag.py" "$ROOT/tools/bench" "$@" >> "$W/ptr.log" 2>&1 || fail "drag helper failed (see $W/ptr.log)"
  start_pointer
}
keys() { timeout 20 python3 -I "$ROOT/tools/bench/wl_keys.py" "$@"; }
shot() {  # shot <name> [geometry]
  if [ -n "${2:-}" ]; then timeout 20 grim -g "$2" "$SHOTS/$1.png"; else timeout 20 grim "$SHOTS/$1.png"; fi
  echo "shot $SHOTS/$1.png"
}
mockdoc() { K act mock.doc "$1" >/dev/null; }
cfgval() {  # cfgval <key> <json value>: a user value in the mock's config document
  mockdoc "{\"doc\":\"config\",\"patch\":{\"values\":{\"$1\":{\"value\":$2,\"source\":\"user\"}}}}"
}
# The scene: windows as {id, app, ws}; `tasks` (active workspace 1, or the given one) derived from them. urgent ids as $URGENT.
URGENT=""
scene() {  # scene <json [[id, app, ws], …]> [focused id]
  local spec=$1 foc=${2:-13}
  local wins
  wins=$(jq -c --argjson foc "$foc" --arg urg ",$URGENT," \
    '[.[] | .[0] as $id | {id: $id, app_id: .[1], workspace: .[2], output: "HEADLESS-1", focused: ($id == $foc),
             urgent: ($urg | contains("," + ($id | tostring) + ","))}]' <<< "$spec")
  local tasks
  tasks=$(jq -c '[.[] | select(.workspace == 1) | {id, app_id, focused, urgent}]' <<< "$wins")
  mockdoc "{\"doc\":\"svc.workspaces\",\"patch\":{\"windows\":$wins,\"tasks\":{\"*\":$tasks,\"HEADLESS-1\":$tasks}}}"
}
BASE='[[11,"firefox",1],[12,"firefox",2],[13,"foot",1],[14,"net.example.NoEntry",1],[15,"GIMP-2.99",1],[16,"",1],[17,"org.example.Iconic",1]]'
# The last tasks-geom line of this edge.
geom() { grep "tasks-geom HEADLESS-1 $1" "$R/qs.log" | tail -1 | sed 's/.*tasks-geom //'; }
wait_geom() {  # wait_geom <edge> <grep pattern>
  for _ in $(seq 40); do geom "$1" | grep -qE -- "$2" && return 0; sleep 0.25; done
  fail "no tasks geometry on $1 matching '$2' (last: $(geom "$1"))"
}
wait_nogeom() {  # wait_nogeom <edge> <key>: a geometry line without that button (the list reflowed)
  for _ in $(seq 40); do geom "$1" | tr ' ' '\n' | grep -q "^$2@" || return 0; sleep 0.25; done
  fail "button $2 stayed on $1 (last: $(geom "$1"))"
}
wait_log() {  # wait_log <grep pattern> <what>
  for _ in $(seq 30); do grep -qE -- "$1" "$R/qs.log" && { echo "ok: $2"; return 0; }; sleep 0.2; done
  fail "$2: no log line matching '$1'"
}
# Centre of a button or chip from the last geometry line: "<key>@x,y,size,…" (window = output coordinates: the bar is on
# the top or left edge).
xy_of() {  # xy_of <edge> <key>
  local t x y w h
  t=$(geom "$1" | tr ' ' '\n' | grep "^$2@" | head -1) || fail "no $2 in: $(geom "$1")"
  IFS=, read -r x y w h _ <<< "${t#*@}"
  case "$2" in ws*) echo "$(( x + w / 2 )) $(( y + h / 2 ))" ;; *) echo "$(( x + w / 2 )) $(( y + w / 2 ))" ;; esac
}
kind_of() { geom "$1" | tr ' ' '\n' | grep "^$2@" | head -1 | cut -d, -f4; }
win_field() {  # win_field <id> <field>: a window's field in the served document ("gone" when absent)
  K sub svc.workspaces --count 0 --json | jq -r --argjson id "$1" --arg f "$2" \
    '[.data.windows[] | select(.id == $id)] | if length == 0 then "gone" else (.[0][$f] | tostring) end'
}
expect_gone() {
  for _ in $(seq 20); do [ "$(win_field "$1" id)" = gone ] && { echo "ok: $2"; return 0; }; sleep 0.2; done
  fail "$2: window $1 is still there"
}
qml_errors() {
  if grep -E 'qml:.*(Error|error)|TypeError|ReferenceError|is not a type|Unable to assign|is not defined|Binding loop' "$R/qs.log" \
      | grep -v 'Unable to assign \[undefined\]' >/dev/null; then
    grep -E 'Error|error|Unable|not defined|Binding loop' "$R/qs.log" | head -20 >&2
    fail "QML errors (see $R/qs.log)"
  fi
}

: > "$R/server.log"
# 0. The theme per scheme, as the real daemon serves it.
for sc in $SCHEMES; do
  printf 'theme.style = "%s"\n[theme.colors]\nscheme = "%s"\n' "$STYLE" "$sc" > "$XDG_CONFIG_HOME/kurashi/config.toml"
  start_kurashid
  K sub theme --count 0 --json | jq -c '{doc: "theme", patch: .data}' > "$W/theme-$sc.json"
  stop_phase
done
rm -f "$XDG_CONFIG_HOME/kurashi/config.toml"

for sc in $SCHEMES; do
  SHOTS=$OUT/$sc
  mkdir -p "$SHOTS"
  echo "== scheme $sc"
  # ---- 1. the top bar ----
  start_mock
  mockdoc "$(cat "$W/theme-$sc.json")"
  start_frontend
  URGENT=""
  scene "$BASE"
  wait_geom top '11@.* 13@.* 14@.* 15@.* 16@.* 17@'
  # Icons settle asynchronously: wait until the pictures are in.
  wait_geom top '11@[^ ]*,image,.* 15@[^ ]*,image,.* 17@[^ ]*,image,'
  echo "geometry: $(geom top)"
  for pair in 11:image 13:image 14:letter 15:image 16:generic 17:image; do
    k=$(kind_of top "${pair%%:*}")
    [ "$k" = "${pair#*:}" ] || fail "window ${pair%%:*}: icon '$k', want '${pair#*:}'"
  done
  echo "ok: icons — entry, StartupWMClass, icon by app id: picture; no entry: letter; no app id: window symbol"
  ptr move $(( SW / 2 )) $(( SH / 2 ))
  shot row "0,0 ${SW}x48"
  # The peek: a rest on Firefox fetches its title.
  read -r X Y <<< "$(xy_of top 11)"
  ptr move "$X" "$Y"
  wait_log 'tasks-peek 11 ok Kurashi-shell' "a rest on a window fetches its title (window.title)"
  sleep 0.4
  shot peek "0,0 900x140"
  ptr move $(( SW / 2 )) $(( SH / 2 ))
  # The menu by keyboard: Focus, Move to 2…5, Close → Down ×5, Return closes foot's window.
  read -r X Y <<< "$(xy_of top 13)"
  ptr click "$X" "$Y" right
  sleep 0.8
  shot menu "0,0 900x380"
  keys down down down down down return
  expect_gone 13 "the menu's Close window closed foot's window by keyboard"
  wait_nogeom top 13
  # A middle click closes.
  read -r X Y <<< "$(xy_of top 14)"
  ptr click "$X" "$Y" middle
  expect_gone 14 "a middle click closed the window without a desktop entry"
  wait_nogeom top 14
  ptr move $(( SW / 2 )) $(( SH / 2 ))
  # Urgent: the window hops once, then keeps its dot.
  URGENT=17
  scene '[[11,"firefox",1],[12,"firefox",2],[15,"GIMP-2.99",1],[16,"",1],[17,"org.example.Iconic",1]]' 11
  wait_log 'tasks-urgent 17 hop' "an urgent window hops"
  sleep 1.2
  wait_geom top '17@[^ ]*,image,1'
  shot urgent "0,0 600x48"
  # Reduced motion: the dot without the hop.
  mockdoc '{"doc":"theme","patch":{"tokens":{"motion.spring.on":false}}}'
  URGENT=15,17
  scene '[[11,"firefox",1],[12,"firefox",2],[15,"GIMP-2.99",1],[16,"",1],[17,"org.example.Iconic",1]]' 11
  wait_log 'tasks-urgent 15 still' "with reduced motion an urgent window does not hop"
  mockdoc "$(cat "$W/theme-$sc.json")"
  mockdoc '{"doc":"theme","patch":{"tokens":{"motion.spring.on":true}}}'
  URGENT=""
  # A drag onto workspace chip 2 moves the window there; the view follows.
  scene '[[11,"firefox",1],[12,"firefox",2],[15,"GIMP-2.99",1],[16,"",1],[17,"org.example.Iconic",1]]' 11
  wait_geom top 'ws2@'
  read -r X0 Y0 <<< "$(xy_of top 15)"
  read -r X1 Y1 <<< "$(xy_of top ws2)"
  drag "$X0" "$Y0" "$X1" "$Y1"
  wait_log 'tasks-move 15 2' "a drop on chip 2 asks to move the window (window.move)"
  for _ in $(seq 20); do [ "$(win_field 15 workspace)" = 2 ] && break; sleep 0.2; done
  [ "$(win_field 15 workspace)" = 2 ] || fail "window 15 is on workspace $(win_field 15 workspace), want 2"
  wait_geom top '12@.* 15@'
  echo "ok: the window moved to workspace 2 and the list follows it"
  shot moved "0,0 600x48"
  # Many windows: the row ends in "+N" before the island.
  many=$(jq -c -n '[range(30; 110) | [., (["firefox","foot","GIMP-2.99","net.example.NoEntry"][. % 4]), 1]]')
  scene "$many" 31
  wait_geom top 'more@'
  echo "ok: many windows end in $(geom top | tr ' ' '\n' | grep '^more@')"
  shot many "0,0 ${SW}x48"
  read -r X Y <<< "$(xy_of top more)"
  ptr click "$X" "$Y" left
  sleep 0.8
  shot many-menu "0,0 ${SW}x700"
  keys escape
  sleep 0.4
  # An empty workspace: no list.
  scene '[[12,"firefox",2]]' 12
  wait_geom top 'HEADLESS-1 top( ws[0-9]+@[^ ]*)*$'
  shot empty "0,0 600x48"
  echo "ok: an empty workspace shows no window list"
  qml_errors

  # ---- 2. the left bar ----
  cfgval bar.edge '"left"'
  mockdoc '{"doc":"svc.recorder","patch":{"recording":true}}'
  URGENT=""
  scene "$BASE"
  wait_geom left '11@.* 13@.* 17@'
  wait_geom left '11@[^ ]*,image,.* 17@[^ ]*,image,'
  echo "geometry: $(geom left)"
  # The column: every button inside the bar's width, below the workspaces, one under the other.
  geom left | tr ' ' '\n' | grep -E '^[0-9]+@' | while IFS=@, read -r id x y s _; do
    [ "$x" -ge 0 ] && [ $(( x + s )) -le 36 ] || { echo "window $id at x $x size $s leaves the bar" >&2; exit 1; }
  done || fail "a window button leaves the side bar"
  ys=$(geom left | tr ' ' '\n' | grep -E '^[0-9]+@' | cut -d@ -f2 | cut -d, -f2 | paste -sd' ')
  [ "$(tr ' ' '\n' <<< "$ys" | sort -n | paste -sd' ')" = "$ys" ] || fail "the column is not top to bottom ($ys)"
  echo "ok: the window list is a column inside the side bar ($ys)"
  # The recording mark and the layout chip (the mock names two layouts): inside the bar, apart from each other.
  sleep 0.6
  rec=$(grep 'BARGEO rec ' "$R/qs.log" | tail -1 | sed 's/.*BARGEO rec //')
  lay=$(grep 'BARGEO layout ' "$R/qs.log" | tail -1 | sed 's/.*BARGEO layout //')
  [ -n "$rec" ] || fail "the side bar shows no recording mark"
  [ -n "$lay" ] || fail "the side bar shows no layout chip"
  read -r rx0 ry0 rx1 ry1 <<< "$rec"
  read -r lx0 ly0 lx1 ly1 <<< "$lay"
  [ "$rx0" -ge 0 ] && [ "$rx1" -le 36 ] && [ "$lx0" -ge 0 ] && [ "$lx1" -le 36 ] || fail "REC ($rec) or layout ($lay) leaves the bar"
  [ "$ry1" -le "$ly0" ] || [ "$ly1" -le "$ry0" ] || fail "REC ($rec) and layout ($lay) overlap"
  echo "ok: the REC mark ($rec) and the layout chip ($lay) fit the side bar"
  shot side "0,0 120x$SH"
  read -r X Y <<< "$(xy_of left 11)"
  ptr move "$X" "$Y"
  wait_log 'tasks-peek 11 ok' "the side bar's peek fetches the title"
  sleep 0.4
  shot side-peek "0,0 900x400"
  ptr move $(( SW / 2 )) $(( SH / 2 ))
  read -r X Y <<< "$(xy_of left 14)"
  ptr click "$X" "$Y" middle
  expect_gone 14 "a middle click closes in the side bar too"
  wait_nogeom left 14
  ptr move $(( SW / 2 )) $(( SH / 2 ))
  URGENT=17
  scene '[[11,"firefox",1],[12,"firefox",2],[15,"GIMP-2.99",1],[16,"",1],[17,"org.example.Iconic",1]]' 11
  wait_geom left '17@[^ ]*,image,1'
  sleep 1.2
  shot side-urgent "0,0 120x500"
  URGENT=""
  scene '[[11,"firefox",1],[12,"firefox",2],[15,"GIMP-2.99",1],[16,"",1],[17,"org.example.Iconic",1]]' 11
  wait_geom left 'ws3@'
  read -r X0 Y0 <<< "$(xy_of left 16)"
  read -r X1 Y1 <<< "$(xy_of left ws3)"
  drag "$X0" "$Y0" "$X1" "$Y1"
  for _ in $(seq 20); do [ "$(win_field 16 workspace)" = 3 ] && break; sleep 0.2; done
  [ "$(win_field 16 workspace)" = 3 ] || fail "side bar: window 16 is on workspace $(win_field 16 workspace), want 3"
  echo "ok: a drag in the side bar moved the window to workspace 3"
  scene "$many" 31
  wait_geom left 'more@'
  echo "ok: the side bar's column ends in $(geom left | tr ' ' '\n' | grep '^more@')"
  shot side-many "0,0 120x$SH"
  qml_errors
  stop_phase
done
echo "test-tasks: ok (shots in $OUT)"
