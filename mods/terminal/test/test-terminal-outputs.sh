#!/usr/bin/env bash
# The terminal on two outputs (W85, docs/ux/terminal.md "Multi-output"): nested niri has one output, so this runs on the
# headless sway sandbox with two (a regression test; the look is checked on niri by test-terminal.sh):
#   1. the drop-down comes out on the focused output (the niri bind sends no output): HEADLESS-2, then HEADLESS-1;
#   2. a toggle on the other output while it is out moves it there (one session, one place);
#   3. hovering the module on HEADLESS-2's bar opens the card under it on that output, with the same session.
#   nix develop -c mods/terminal/test/test-terminal-outputs.sh
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
NAME=${1:-${KURASHI_SB_PREFIX:-}w85-term-outputs}
BIN=${KURASHI_BIN_DIR:-${CARGO_TARGET_DIR:-$ROOT/target}/debug}
fail() { echo "test-terminal-outputs: FAIL: $*" >&2; tail -20 "${R:-/tmp}/qs.log" >&2 2>/dev/null || true; exit 1; }
ok() { echo "test-terminal-outputs: ok: $*"; }
command -v qs-terminal > /dev/null || fail "qs-terminal is not on PATH (nix develop provides it)"

eval "$("$ROOT/tools/bench/sandbox.sh" start "$NAME")"
. "$ROOT/frontend/test-lib.sh"
R=$XDG_RUNTIME_DIR
W=$R/work
mkdir -p "$W"
cp "$BIN/kurashid" "$BIN/kurashi" "$W/"
pids=()
cleanup() {
  for p in "${pids[@]}"; do kill "$p" 2>/dev/null || true; done
  # (the terminal's host is the daemon's child; this sandbox's only)
  for p in $(pgrep -f "terminal/host/shell.qml" || true); do
    tr '\0' '\n' < "/proc/$p/environ" 2>/dev/null | grep -qx "XDG_RUNTIME_DIR=$R" && kill "$p" 2>/dev/null || true
  done
  "$ROOT/tools/bench/sandbox.sh" stop "$NAME" > /dev/null || true
}
trap cleanup EXIT

rm -rf "$R/xdg"
export XDG_CONFIG_HOME=$R/xdg/config XDG_STATE_HOME=$R/xdg/state XDG_DATA_HOME=$R/xdg/data XDG_CACHE_HOME=$R/xdg/cache \
       KURASHI_DATA_DIR=$ROOT LC_ALL=C.UTF-8 KURASHI_SOCKET=$R/kurashi.sock
mkdir -p "$XDG_CONFIG_HOME/kurashi" "$XDG_STATE_HOME" "$XDG_DATA_HOME" "$XDG_CACHE_HOME"
K() { timeout 10 "$W/kurashi" "$@"; }
doc() { K --json sub mod.terminal --count 0 | tail -1 | python3 -c "import json,sys; d=json.loads(sys.stdin.readline()); d=d.get('data', d); print($1)"; }
doc_is() { [ "$(doc "$1" 2>/dev/null)" = True ]; }
ui_is() { K --json sub runtime.ui --count 0 | tail -1 | grep -q "$1"; }
cat > "$XDG_CONFIG_HOME/kurashi/config.toml" <<T
[idle]
enabled = false
[theme.motion]
profile = "none"
[mods]
enabled = ["terminal"]
[mods.terminal]
shell = "bash --norc --noprofile"
[bar]
hover_card = ["mod:terminal:terminal"]
[edges.top]
start = ["workspaces"]
center = ["island"]
end = ["mod:terminal:terminal", "clock"]
T
"$ROOT/tools/bench/sandbox.sh" output-add "$NAME" > /dev/null || fail "no second output"
swaymsg output HEADLESS-1 pos 0 0 > /dev/null 2>&1
W1=$(swaymsg -t get_outputs -r | jq '.[] | select(.name == "HEADLESS-1") | .rect.width')
W2=$(swaymsg -t get_outputs -r | jq '.[] | select(.name == "HEADLESS-2") | .rect.width')
swaymsg output HEADLESS-2 pos "$W1" 0 > /dev/null 2>&1
swaymsg output '*' bg '#5d7f8f' solid_color > /dev/null 2>&1 || true

env DBUS_SYSTEM_BUS_ADDRESS="unix:path=$R/no-system-bus" PULSE_SERVER="unix:$R/no-pulse/native" PULSE_RUNTIME_PATH="$R/no-pulse" \
  "$W/kurashid" >> "$R/kurashid.log" 2>&1 &
pids+=($!)
wait_until 15 K ping || fail "kurashid did not answer"
: > "$R/qs.log"
qs -p "$ROOT/frontend" >> "$R/qs.log" 2>&1 &
pids+=($!)
wait_frontend "$R/qs.log" || fail "the frontend did not load"
wait_until 20 doc_is "d.get('available') == True" || fail "mod.terminal never came"

# 1. out on the focused output
for O in HEADLESS-2 HEADLESS-1; do
  swaymsg focus output "$O" > /dev/null
  sleep 0.5
  K act terminal.toggle > /dev/null
  wait_until 20 doc_is "d.get('rests', {}).get('dropdown', {}).get('output') == '$O' and d['host']['state'] == 'ready'" \
    || fail "the drop-down did not come out on the focused $O ($(doc "d.get('rests')"))"
  K act terminal.toggle > /dev/null
  wait_until 10 doc_is "'dropdown' not in d.get('rests', {})" || fail "the second toggle did not hide it on $O"
  ok "the drop-down comes out on the focused output ($O)"
done
TABS=$(doc "[t['id'] for t in d['tabs']]")

# 2. out on one output, a toggle on the other moves it there
K act terminal.toggle '{"output":"HEADLESS-1"}' > /dev/null
wait_until 10 doc_is "d.get('rests', {}).get('dropdown', {}).get('output') == 'HEADLESS-1'" || fail "not out on HEADLESS-1"
K act terminal.toggle '{"output":"HEADLESS-2"}' > /dev/null
wait_until 10 doc_is "d['dropdown']['open'] and d.get('rests', {}).get('dropdown', {}).get('output') == 'HEADLESS-2'" \
  || fail "a toggle on HEADLESS-2 did not move it there ($(doc "d.get('dropdown'), d.get('rests')"))"
[ "$(doc "[t['id'] for t in d['tabs']]")" = "$TABS" ] || fail "moving it changed the sessions"
K act terminal.hide > /dev/null
ok "a toggle on the other output moves it there, the same sessions"

# 3. the card under the module on HEADLESS-2's bar
wait_until 10 doc_is "'dropdown' not in d.get('rests', {})" || fail "it did not hide"
python3 -I "$ROOT/tools/bench/wl_pointer.py" move $((W1 + W2 / 2)) 400
python3 -I "$ROOT/tools/bench/wl_pointer.py" move $((W1 + W2 - 104)) 14
wait_until 10 ui_is '"panel":"mod:terminal:terminal"' || fail "hovering the module on HEADLESS-2 opened no card"
wait_until 10 doc_is "d.get('rests', {}).get('card', {}).get('output') == 'HEADLESS-2'" \
  || fail "the card is not on HEADLESS-2 ($(doc "d.get('rests')"))"
[ "$(doc "[t['id'] for t in d['tabs']]")" = "$TABS" ] || fail "the card has other sessions"
ok "the module's card opens on its own output (HEADLESS-2) with the same sessions"
echo "test-terminal-outputs: PASS"
