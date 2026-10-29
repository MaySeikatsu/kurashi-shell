#!/usr/bin/env bash
# The Sway adapter (W26), invisibly: the REAL kurashid in the headless sway sandbox, talking to the sandbox's own
# sway over its SWAYSOCK (no fake niri, no mock):
#   1. kurashid picks the sway adapter; `kurashi doctor` names it and its capabilities;
#   2. svc.workspaces mirrors sway: two foot windows on workspaces 1 and 2 appear in `windows` with app_id foot,
#      the bar shows sway's workspaces (shot);
#   3. `kurashi act workspace.focus {idx: 1}` switches sway's workspace (sway's own get_workspaces agrees) (shot);
#   4. svc.keyboard: two layouts set by swaymsg appear; `keyboard.next` switches sway's active layout;
#   5. `window.close {id}` closes the window in sway.
#   nix develop -c frontend/test-sway-adapter.sh [sandbox-name]
# Binaries: kurashid and kurashi from $KURASHI_BIN_DIR (default $CARGO_TARGET_DIR/debug or target/debug); a Wayland
# terminal (`foot`, override with $W26_CLIENT) for the windows. Shots in frontend/shots/sway-adapter/. On a hybrid
# laptop export KURASHI_RENDER_NODE first.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
NAME=${1:-${KURASHI_SB_PREFIX:-}w26-adp-test}
BIN=${KURASHI_BIN_DIR:-${CARGO_TARGET_DIR:-$ROOT/target}/debug}
OUT=$ROOT/frontend/shots/sway-adapter
CLIENT=${W26_CLIENT:-foot}
mkdir -p "$OUT"
fail() { echo "test-sway-adapter: FAIL: $*" >&2; exit 1; }
command -v "$CLIENT" >/dev/null || fail "no $CLIENT on PATH (set W26_CLIENT to a Wayland client)"

eval "$("$ROOT/tools/bench/sandbox.sh" start "$NAME")"
R=$XDG_RUNTIME_DIR
W=$R/work
mkdir -p "$W" "$R/kurashi"
cp "$BIN/kurashid" "$BIN/kurashi" "$W/"
[ -S "$SWAYSOCK" ] || fail "the sandbox has no sway socket"
case "$SWAYSOCK" in "$R"/*) ;; *) fail "SWAYSOCK $SWAYSOCK is not the sandbox's";; esac

pids=()
cleanup() {
  for p in "${pids[@]}"; do kill "$p" 2>/dev/null || true; done
  for p in "${pids[@]}"; do wait "$p" 2>/dev/null || true; done
  "$ROOT/tools/bench/sandbox.sh" stop "$NAME" >/dev/null || true
}
trap cleanup EXIT

rm -rf "$R/xdg"
export XDG_CONFIG_HOME=$R/xdg/config XDG_STATE_HOME=$R/xdg/state \
       XDG_DATA_HOME=$R/xdg/data XDG_CACHE_HOME=$R/xdg/cache KURASHI_DATA_DIR=$ROOT LC_ALL=C.UTF-8
mkdir -p "$XDG_CONFIG_HOME/kurashi" "$XDG_STATE_HOME" "$XDG_DATA_HOME" "$XDG_CACHE_HOME"
K() { timeout 10 "$W/kurashi" "$@"; }
doc() { K sub "$1" --count 0 --json | jq -c '.data'; }
ws_json() { doc svc.workspaces; }
until_jq() {  # until_jq <doc> <jq filter> <what>: the document matches within 5 s
  for _ in $(seq 50); do doc "$1" | jq -e "$2" >/dev/null 2>&1 && { echo "ok: $3"; return 0; }; sleep 0.1; done
  echo "last $1: $(doc "$1")" >&2
  fail "$3"
}
shot() { timeout 20 grim -g "0,0 2560x120" "$OUT/$1.png" && echo "shot $OUT/$1.png"; }
sway_focused() { swaymsg -t get_workspaces -r | jq -r '.[] | select(.focused) | .name'; }

: > "$R/server.log"
env DBUS_SYSTEM_BUS_ADDRESS="unix:path=$R/no-system-bus" PULSE_SERVER="unix:$R/no-pulse/native" \
    PULSE_RUNTIME_PATH="$R/no-pulse" RUST_LOG=info "$W/kurashid" >> "$R/server.log" 2>&1 &
pids+=("$!")
for _ in $(seq 100); do [ -S "$KURASHI_SOCKET" ] && K ping >/dev/null 2>&1 && break; sleep 0.1; done
K ping >/dev/null 2>&1 || fail "kurashid did not come up (see $R/server.log)"
# The documents are refcounted (Ma): one long-lived subscriber each keeps the adapter running between snapshots.
for d in svc.workspaces svc.keyboard; do
  "$W/kurashi" sub "$d" > /dev/null 2>&1 &
  pids+=("$!")
done

# 1. The adapter.
grep -q 'compositor adapter.*sway' "$R/server.log" || { cat "$R/server.log" >&2; fail "kurashid did not pick the sway adapter"; }
echo "ok: kurashid picked the sway adapter"
K doctor > "$W/doctor.txt" || true
grep -q 'sway: workspace names, workspaces per output, keyboard layouts' "$W/doctor.txt" \
  || { cat "$W/doctor.txt" >&2; fail "doctor does not name the sway adapter"; }
echo "ok: doctor: $(grep -o 'sway: .*' "$W/doctor.txt" | head -1)"

# 2. Windows and workspaces from sway.
until_jq svc.workspaces '.outputs["HEADLESS-1"] | length >= 1 and (.[0].focused == true)' "workspace 1 on HEADLESS-1, focused"
swaymsg exec "$CLIENT" >/dev/null
until_jq svc.workspaces '[.windows[] | select(.app_id == "foot" and .output == "HEADLESS-1")] | length == 1' \
  "a foot window appears in svc.workspaces.windows"
swaymsg workspace 2 >/dev/null
swaymsg exec "$CLIENT" >/dev/null
until_jq svc.workspaces '[.windows[] | select(.app_id == "foot")] | length == 2' "a second foot window on workspace 2"
until_jq svc.workspaces '[.outputs["HEADLESS-1"][] | {idx, focused, occupied}] == [{"idx":1,"focused":false,"occupied":true},{"idx":2,"focused":true,"occupied":true}]' \
  "workspaces 1 and 2, 2 focused, both occupied"
ws_json | jq -c '.windows' | sed 's/^/windows: /'

: > "$R/qs.log"
env -u KURASHI_SOCKET qs -p "$ROOT/frontend" >> "$R/qs.log" 2>&1 &
pids+=("$!")
for _ in $(seq 100); do grep -q 'hello.*frontend' "$R/server.log" && break; sleep 0.1; done
grep -q 'hello.*frontend' "$R/server.log" || fail "frontend never said hello (see $R/qs.log)"
sleep 3
shot bar-ws2

# 3. workspace.focus through kurashid switches sway.
K act workspace.focus '{"idx":1}' >/dev/null
for _ in $(seq 30); do [ "$(sway_focused)" = 1 ] && break; sleep 0.1; done
[ "$(sway_focused)" = 1 ] || fail "workspace.focus {idx:1}: sway still on $(sway_focused)"
echo "ok: workspace.focus {idx: 1} switched sway to workspace 1"
until_jq svc.workspaces '.outputs["HEADLESS-1"][0].focused == true' "the document follows"
sleep 1
shot bar-ws1
ID2=$(ws_json | jq -r '.outputs["HEADLESS-1"][] | select(.idx == 2) | .id')
K act workspace.focus "{\"id\":$ID2}" >/dev/null
for _ in $(seq 30); do [ "$(sway_focused)" = 2 ] && break; sleep 0.1; done
[ "$(sway_focused)" = 2 ] || fail "workspace.focus {id:$ID2}: sway still on $(sway_focused)"
echo "ok: workspace.focus {id: $ID2} (a sway container id) switched to workspace 2"

# 4. Keyboard layouts. Headless sway has no keyboard of its own; a virtual one (wl_keys.py) brings its own keymap,
#    whose layouts sway reports as null and never configures (`input … xkb_layout` does not apply to it). So: the
#    input event reaches the adapter, svc.keyboard shows no layouts rather than a guess (Shōjiki), the adapter
#    survives it (a workspace switch after it is still mirrored), and keyboard.next reaches sway.
rm -f "$W/kbd"; mkfifo "$W/kbd"
python3 -I "$ROOT/tools/bench/wl_keys.py" --serve < "$W/kbd" >> "$W/kbd.log" 2>&1 &
pids+=("$!")
exec 7> "$W/kbd"
for _ in $(seq 30); do swaymsg -t get_inputs -r | jq -e 'map(select(.type == "keyboard")) | length > 0' >/dev/null && break; sleep 0.1; done
swaymsg -t get_inputs -r | jq -c '.[] | select(.type == "keyboard") | {identifier, xkb_layout_names}' | sed 's/^/sway input: /'
until_jq svc.keyboard '.layouts == []' "svc.keyboard: a virtual keyboard's unnamed layouts are not shown"
K act keyboard.next >/dev/null || fail "keyboard.next refused"
echo "ok: keyboard.next reached sway (input type:keyboard xkb_switch_layout next)"
swaymsg workspace 1 >/dev/null
until_jq svc.workspaces '.outputs["HEADLESS-1"][0].focused == true' "the adapter still follows sway after the input event"

# 5. window.close.
WID=$(ws_json | jq -r '[.windows[] | select(.focused)][0].id')
[ -n "$WID" ] && [ "$WID" != null ] || fail "no focused window"
K act window.close "{\"id\":$WID}" >/dev/null
until_jq svc.workspaces "[.windows[] | select(.id == $WID)] | length == 0" "window.close {id: $WID} closed it in sway"

if grep -E 'qml:.*(Error|error)|TypeError|ReferenceError|is not a type' "$R/qs.log" >/dev/null; then
  grep -E 'Error|error' "$R/qs.log" | head -10 >&2
  fail "QML errors (see $R/qs.log)"
fi
echo "test-sway-adapter: ok (shots in $OUT)"
