#!/usr/bin/env bash
# `theme.light.outputs` (K101, docs/ux/texture.md): two outputs (headless sway, against the real kurashid), the light from the
# pointer. Moving the pointer along the first output's bar relights the second output's bar under All monitors, and leaves it as it
# was under The one with the pointer. Read from the second bar's pixels; nothing else draws there.
#   nix develop -c frontend/test-light-outputs.sh
set -uo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
NAME=${KURASHI_SB_PREFIX:-}light-outputs
BIN=${KURASHI_BIN_DIR:-${CARGO_TARGET_DIR:-$ROOT/target}/debug}
fail() { echo "test-light-outputs: FAIL: $*" >&2; exit 1; }
eval "$("$ROOT/tools/bench/sandbox.sh" start "$NAME")"
. "$ROOT/frontend/test-lib.sh"
R=$XDG_RUNTIME_DIR; W=$R/work; mkdir -p "$W" "$R/kurashi"
cp "$BIN/kurashid" "$BIN/kurashi" "$W/"
pids=()
cleanup() {
  for p in "${pids[@]}"; do kill "$p" 2>/dev/null || true; done
  for p in "${pids[@]}"; do wait "$p" 2>/dev/null || true; done
  "$ROOT/tools/bench/sandbox.sh" stop "$NAME" > /dev/null || true
}
trap cleanup EXIT
"$ROOT/tools/bench/sandbox.sh" output-add "$NAME" > /dev/null || fail "no second output"
swaymsg output HEADLESS-1 pos 0 0 > /dev/null 2>&1
W1=$(swaymsg -t get_outputs -r | jq '.[] | select(.name == "HEADLESS-1") | .rect.width')
swaymsg output HEADLESS-2 pos "$W1" 0 > /dev/null 2>&1
CROP="$W1,0 400x30"
swaymsg output '*' bg '#8fb8c8' solid_color > /dev/null 2>&1 || true
rm -rf "$R/xdg"
export XDG_CONFIG_HOME=$R/xdg/config XDG_STATE_HOME=$R/xdg/state XDG_DATA_HOME=$R/xdg/data XDG_CACHE_HOME=$R/xdg/cache KURASHI_DATA_DIR=$ROOT LC_ALL=C.UTF-8
mkdir -p "$XDG_CONFIG_HOME/kurashi" "$XDG_STATE_HOME" "$XDG_DATA_HOME" "$XDG_CACHE_HOME"
cat > "$XDG_CONFIG_HOME/kurashi/config.toml" <<T
[idle]
enabled = false
[theme]
style = "kami"
[theme.motion]
profile = "none"
[theme.texture]
kind = "leather"
depth = 1.0
[theme.light]
mode = "pointer"
outputs = "pointer"
elevation = 10
[edges.top]
bar = true
start = ["workspaces"]
center = []
end = []
T
K() { timeout 10 "$W/kurashi" "$@"; }
: > "$R/server.log"; : > "$R/qs.log"
env DBUS_SYSTEM_BUS_ADDRESS="unix:path=$R/no-system-bus" PULSE_SERVER="unix:$R/no-pulse/native" PULSE_RUNTIME_PATH="$R/no-pulse" \
  "$W/kurashid" >> "$R/server.log" 2>&1 &
pids+=("$!")
for _ in $(seq 100); do [ -S "$KURASHI_SOCKET" ] && K ping > /dev/null 2>&1 && break; sleep 0.1; done
BARE=$(screen_hash)
env -u KURASHI_SOCKET qs -p "$ROOT/frontend" >> "$R/qs.log" 2>&1 &
pids+=("$!")
wait_frontend "$R/qs.log" 0 15 0.6 "$BARE" || fail "the frontend did not load"
sleep 2
# (one pointer for the whole run: a pointer that goes away after its move is a leave, and the lamp rests before the shot)
rm -f "$R/ptr.fifo"; mkfifo "$R/ptr.fifo"
python3 -I "$ROOT/tools/bench/wl_pointer.py" --serve < "$R/ptr.fifo" > /dev/null 2>&1 &
pids+=("$!")
exec 9> "$R/ptr.fifo"
ptr() { echo "$*" >&9; }
moved() { # the second bar with the pointer at each end of the first bar's strip: how many pixels differ
  ptr move 300 14; sleep 1; wait_settled 6 0.8 "$CROP"; grim -g "$CROP" "$R/a.png"
  grim -g "$CROP" "$R/a2.png"
  ptr move $(( W1 - 40 )) 14; sleep 1; wait_settled 6 0.8 "$CROP"; grim -g "$CROP" "$R/b.png"
  ptr move 960 500; sleep 1
  local steady n
  steady=$(magick compare -metric AE "$R/a.png" "$R/a2.png" null: 2>&1 | cut -d' ' -f1)
  n=$(magick compare -metric AE "$R/a.png" "$R/b.png" null: 2>&1 | cut -d' ' -f1)
  cp "$R/a.png" "$R/shot-$1-a.png"; cp "$R/b.png" "$R/shot-$1-b.png"
  echo "test-light-outputs: the second bar: $n px differ across the move ($steady with no move)"
  [ "${n%.*}" -gt 100 ]
}
[ "$(K --json get theme.light.outputs | jq -r .value)" = pointer ] || fail "the default is not the pointer's monitor"
moved pointer && fail "the pointer on one monitor relit the other under The one with the pointer"
echo "test-light-outputs: the pointer's monitor only: the other stands still"
K set theme.light.outputs '"all"' > /dev/null || fail "theme.light.outputs refused"
sleep 2
[ "$(K sub theme --count 0 --json | head -1 | jq -r '.data.tokens["light.outputs"]')" = all ] || fail "the token did not follow"
moved all || fail "the pointer on one monitor did not relight the other under All monitors"
echo "test-light-outputs: all monitors: the other follows"
if grep -E 'qml:.*(Error|error)|TypeError|ReferenceError|is not a type' "$R/qs.log" | grep -v 'Unable to assign \[undefined\]' > /dev/null; then
  grep -E 'TypeError|ReferenceError|is not a type' "$R/qs.log" | head -5 >&2; fail "QML errors"
fi
echo "test-light-outputs: ok"
