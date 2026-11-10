#!/usr/bin/env bash
# Open on hover (I458, K113, docs/ux/bar-hover.md) and the joined preview (I457), on the REAL kurashid, invisibly
# (headless sway sandbox), by a virtual pointer:
#   1. `bar.hover = preview` (the default): resting on quick settings opens nothing.
#   2. `bar.hover = card`: resting on it opens its card; the card stays while the pointer is on the module and on the
#      card; it closes once the pointer has left both. A press in the card keeps it after the pointer leaves.
#   3. a card a click opened is not closed by the pointer leaving, and a hover on another module does not replace it.
#   4. `bar.hover_menu = ["clock"]`: the clock opens its menu on hover while the bar opens cards; leaving closes it.
#      `bar.hover_preview = ["quick"]` holds quick settings back under `bar.hover = card`.
#   5. a workspace's preview under a look with a tooltip part: no QML error or warning (seen joined on niri by the lead).
#   nix develop -c frontend/test-bar-hover.sh [sandbox-name]
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
NAME=${1:-${KURASHI_SB_PREFIX:-}s27-hover-test}
BIN=${KURASHI_BIN_DIR:-${CARGO_TARGET_DIR:-$ROOT/target}/debug}
fail() { echo "test-bar-hover: FAIL: $*" >&2; exit 1; }

eval "$("$ROOT/tools/bench/sandbox.sh" start "$NAME")"
. "$ROOT/frontend/test-lib.sh"
R=$XDG_RUNTIME_DIR
W=$R/work
mkdir -p "$W"
cp "$BIN/kurashid" "$BIN/kurashi" "$W/"
pids=()
cleanup() {
  for p in "${pids[@]}"; do kill "$p" 2>/dev/null || true; done
  "$ROOT/tools/bench/sandbox.sh" stop "$NAME" >/dev/null || true
}
trap cleanup EXIT

rm -rf "$R/xdg"
export XDG_CONFIG_HOME=$R/xdg/config XDG_STATE_HOME=$R/xdg/state XDG_DATA_HOME=$R/xdg/data XDG_CACHE_HOME=$R/xdg/cache \
       KURASHI_DATA_DIR=$ROOT LC_ALL=C.UTF-8 KURASHI_SOCKET=$R/kurashi.sock
mkdir -p "$XDG_CONFIG_HOME/kurashi" "$XDG_STATE_HOME" "$XDG_DATA_HOME" "$XDG_CACHE_HOME"
CONF=$XDG_CONFIG_HOME/kurashi/config.toml
K() { timeout 10 "$W/kurashi" "$@"; }
base='[idle]
enabled = false
[theme.motion]
profile = "none"
[edges.top]
start = ["workspaces"]
center = ["island"]
end = ["quick", "clock"]'
hover_is() { K get bar.hover | grep -q "\"$1\""; }
conf() { printf '%s\n%s\n' "$base" "$1" > "$CONF"; }
printf '%s\n' "$base" > "$CONF"

env DBUS_SYSTEM_BUS_ADDRESS="unix:path=$R/no-system-bus" PULSE_SERVER="unix:$R/no-pulse/native" PULSE_RUNTIME_PATH="$R/no-pulse" \
  "$W/kurashid" >> "$R/kurashid.log" 2>&1 &
pids+=($!)
wait_until 15 K ping || fail "kurashid did not answer"
: > "$R/qs.log"
qs -p "$ROOT/frontend" >> "$R/qs.log" 2>&1 &
pids+=($!)
wait_frontend "$R/qs.log" || fail "the frontend did not load"

# One pointer for the whole run (`--serve`): a pointer made per move is gone again when its tool exits, and the bar
# then hears a leave half a second after every move, so nothing could rest on a module.
rm -f "$R/ptr.fifo"
mkfifo "$R/ptr.fifo"
python3 -I "$ROOT/tools/bench/wl_pointer.py" --serve < "$R/ptr.fifo" &
pids+=($!)
exec 9> "$R/ptr.fifo"
mv_to() { echo "move $1 $2" >&9; sleep 0.15; }
ptr() { echo "click $1 $2 ${3:-left}" >&9; sleep 0.25; }
doc() { K sub "$1" --count 0 2>/dev/null | head -1; }
ui_is() { doc runtime.ui | grep -q "$1"; }
closed() { ui_is '"panel":""' && ui_is '"tray":""'; }
# Where a module stands: the middle of its anchor on the bar (`module:<id>`, what the Stage opens a card under).
W_OUT=$(swaymsg -t get_outputs | python3 -c 'import json,sys; print(json.load(sys.stdin)[0]["rect"]["width"])')
H_OUT=$(swaymsg -t get_outputs | python3 -c 'import json,sys; print(json.load(sys.stdin)[0]["rect"]["height"])')
# The end zone, from the right: the clock, then quick settings (found by a right click's menu, which names its module).
find_module() { # find_module <id> → X: scans the end zone for the x whose right click opens module:<id>
  local x
  for x in $(seq $(( W_OUT - 16 )) -12 $(( W_OUT - 400 ))); do
    ptr "$x" 14 right
    if wait_until 1 ui_is "\"tray\":\"module:$1\""; then K act ui.close > /dev/null; wait_until 3 closed; echo "$x"; return 0; fi
    ui_is '"tray":""' || { K act ui.close > /dev/null; wait_until 3 closed; }
  done
  return 1
}
QX=$(find_module quick) || fail "quick settings not found on the bar"
CX=$(find_module clock) || fail "the clock not found on the bar"
AWAY_X=$(( W_OUT / 2 )); AWAY_Y=$(( H_OUT - 200 ))
mv_to "$AWAY_X" "$AWAY_Y"

# ---- 1. the default: a hover opens no card ----
hover_is preview || fail "bar.hover is not preview by default: $(K get bar.hover)"
mv_to "$QX" 14
sleep 1.2
closed || fail "preview: resting on quick settings opened something: $(doc runtime.ui)"
mv_to "$AWAY_X" "$AWAY_Y"
echo "ok: bar.hover = preview opens no card"

# ---- 2. card: opens on hover, stays on the module and the card, closes after both are left ----
conf '[bar]
hover = "card"'
wait_until 5 hover_is card || fail "bar.hover = card was not taken"
mv_to "$QX" 14
wait_until 3 ui_is '"panel":"quick"' || fail "card: resting on quick settings opened no card: $(doc runtime.ui)"
sleep 1.2
ui_is '"panel":"quick"' || fail "card: the card closed while the pointer rested on its module"
# onto the card (it hangs under its module)
mv_to "$(( QX - 60 ))" 200
sleep 1.2
ui_is '"panel":"quick"' || fail "card: the card closed while the pointer was on it"
mv_to "$AWAY_X" "$AWAY_Y"
wait_until 3 closed || fail "card: the card stayed after the pointer left it: $(doc runtime.ui)"
echo "ok: bar.hover = card opens on hover, stays under the pointer, closes when it leaves"

mv_to "$QX" 14
wait_until 3 ui_is '"panel":"quick"' || fail "card: no card the second time"
mv_to "$(( QX - 60 ))" 200
sleep 0.4
# a press on the card's own ground (its top padding), not on a control
ptr "$(( QX - 60 ))" 46
mv_to "$AWAY_X" "$AWAY_Y"
sleep 1.2
ui_is '"panel":"quick"' || fail "card: a card the user pressed in closed when the pointer left: $(doc runtime.ui)"
K act ui.close > /dev/null
wait_until 3 closed || fail "ui.close did not close the kept card"
echo "ok: a press in the card keeps it"

# ---- 3. what a click opened is left alone ----
ptr "$QX" 14
wait_until 3 ui_is '"panel":"quick"' || fail "click: no card"
mv_to "$AWAY_X" "$AWAY_Y"
sleep 1.2
ui_is '"panel":"quick"' || fail "click: a clicked card closed when the pointer left"
K act ui.close > /dev/null
wait_until 3 closed || fail "ui.close did not close the clicked card"
echo "ok: a card a click opened stays"

# ---- 4. a module's own choice ----
conf '[bar]
hover = "card"
hover_menu = ["clock"]
hover_preview = ["quick"]'
menu_set() { K get bar.hover_menu | grep -q clock; }
wait_until 5 menu_set || fail "bar.hover_menu was not taken"
mv_to "$CX" 14
wait_until 3 ui_is '"tray":"module:clock"' || fail "menu: resting on the clock opened no menu: $(doc runtime.ui)"
mv_to "$AWAY_X" "$AWAY_Y"
wait_until 3 closed || fail "menu: the menu stayed after the pointer left: $(doc runtime.ui)"
mv_to "$QX" 14
sleep 1.2
closed || fail "hover_preview: quick settings opened its card though it is held to its preview: $(doc runtime.ui)"
mv_to "$AWAY_X" "$AWAY_Y"
echo "ok: bar.hover_menu and bar.hover_preview hold for their modules"

# ---- 5. the joined preview draws without an error ----
conf '[theme]
style = "kami"'
sleep 1.5
OUTN=$(swaymsg -t get_outputs | python3 -c 'import json,sys; print(json.load(sys.stdin)[0]["name"])')
K act ui.peek "{\"source\":\"workspace:1\",\"output\":\"$OUTN\",\"x\":120,\"w\":24,\"edge\":\"top\"}" > /dev/null || true
sleep 1
K act ui.peek '{}' > /dev/null || true
sleep 0.5
if grep -E "qml|QML" "$R/qs.log" | grep -iE "error|TypeError|ReferenceError|Binding loop" | grep -v desktopentry | head -3 | grep -q .; then
  grep -E "qml|QML" "$R/qs.log" | grep -iE "error|TypeError|ReferenceError|Binding loop" | head -5 >&2
  fail "the frontend logged a QML error"
fi
echo "ok: the frontend logs no QML error"
echo "test-bar-hover: all checks passed"
