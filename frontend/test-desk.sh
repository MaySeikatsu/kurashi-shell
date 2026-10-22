#!/usr/bin/env bash
# The desk's order and edit mode in the REAL shell (W24-desk-settings, K48 (4)), invisibly: the real kurashid and the real
# Quickshell frontend in the headless sway sandbox, `desktop.enabled = true`, the tasks mod on (its two desk cards). Per
# decor (sekai, none):
#   1. the column follows `desktop.order` set with `kurashi set` (calendar first), unlisted cards after;
#   2. the "Edit" key under the pointer opens edit mode: every card shows (placeholders for those with nothing to show);
#      by keys only from there — Alt+Down moves the focused card (clock) below the next, Down moves the focus, Space hides
#      a card (media), Return is Done: `desktop.order` and `desktop.media` are written as ONE change (one undo puts both
#      back);
#   3. edit mode again, Alt+Down, then Escape: nothing is written.
# Checks print ok / FAIL; any FAIL, QML error or kurashid panic makes the run exit 1.
# Shots: frontend/shots/desk/{ordered,hover,edit,edit-moved,saved}-{sekai,none}.png (the desk column).
#   KURASHI_RENDER_NODE=/dev/dri/renderD129 KURASHI_BIN_DIR=<dir with kurashid and kurashi> \
#     timeout 900 nix develop -c frontend/test-desk.sh [sandbox-name]
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
NAME=${1:-w24-dsk-1}   # unique per run: other runs stop any sandbox that shares a name
BIN=${KURASHI_BIN_DIR:-${CARGO_TARGET_DIR:-$ROOT/target}/debug}
OUT=$ROOT/frontend/shots/desk
DECORS=${DECORS:-sekai none}
# Machine B's iGPU when it exists; elsewhere sandbox.sh picks the display GPU (boot_vga).
[ -e /dev/dri/renderD129 ] && export KURASHI_RENDER_NODE=${KURASHI_RENDER_NODE:-/dev/dri/renderD129}
# The desk column (layout px of the 2560 x 1440 output): 300 px wide, 32 px from the right edge, under the bar.
DESK_GEOM=${DESK_GEOM:-"2200,20 360x1400"}
mkdir -p "$OUT"
FAILS=0
CHECKS=0
fail() { echo "test-desk: $*" >&2; exit 1; }
check() { # check <0|1> <label>
  CHECKS=$((CHECKS + 1))
  if [ "$1" = 1 ]; then echo "ok: $2"; else echo "FAIL: $2"; FAILS=$((FAILS + 1)); fi
}

eval "$("$ROOT/tools/bench/sandbox.sh" start "$NAME")"
R=$XDG_RUNTIME_DIR
W=$R/work
mkdir -p "$W" "$R/kurashi"
cp "$BIN/kurashid" "$BIN/kurashi" "$W/"
rm -f "$R/qs.log" "$R/kurashid.log" "$R/keys.log"
for _ in $(seq 150); do timeout 5 swaymsg -t get_outputs >/dev/null 2>&1 && break; sleep 0.2; done
timeout 5 swaymsg -t get_outputs >/dev/null 2>&1 || fail "the headless compositor does not answer (see $R/sway.log)"

DPID=""
SHPID=""
KPID=""
PPID_=""
stop_daemon() { if [ -n "$DPID" ]; then kill "$DPID" 2>/dev/null || true; wait "$DPID" 2>/dev/null || true; fi; DPID=""; }
stop_shell() { if [ -n "$SHPID" ]; then kill "$SHPID" 2>/dev/null || true; wait "$SHPID" 2>/dev/null || true; fi; SHPID=""; }
stop_keys() { if [ -n "$KPID" ]; then exec 3>&- 2>/dev/null || true; kill "$KPID" 2>/dev/null || true; wait "$KPID" 2>/dev/null || true; fi; KPID=""; }
stop_pointer() { if [ -n "$PPID_" ]; then exec 4>&- 2>/dev/null || true; kill "$PPID_" 2>/dev/null || true; wait "$PPID_" 2>/dev/null || true; fi; PPID_=""; }
cleanup() {
  stop_pointer
  stop_keys
  stop_shell
  stop_daemon
  "$ROOT/tools/bench/sandbox.sh" stop "$NAME" >/dev/null || true
}
trap cleanup EXIT

# Hermetic: no config, state or cache from an earlier run; the system bus is not reachable.
export XDG_CONFIG_HOME=$R/xdg/config XDG_STATE_HOME=$R/xdg/state XDG_DATA_HOME=$R/xdg/data XDG_CACHE_HOME=$R/xdg/cache
export KURASHI_DATA_DIR=$ROOT LC_ALL=C.UTF-8
VAULT=$R/vault
K() { timeout 10 "$W/kurashi" "$@"; }
# The value of a key as JSON (cfg.get), and one raw request.
val() { K raw "{\"t\":\"cfg.get\",\"id\":\"v\",\"key\":\"$1\"}" | python3 -c 'import json,sys; m=json.loads(sys.stdin.readline()); print(json.dumps(m["v"]["value"], separators=(",", ":")))'; }
wait_val() { local i; for i in $(seq 25); do [ "$(val "$1")" = "$2" ] && return 0; sleep 0.2; done; return 0; }
# The theme's bar height token: where the desk column starts (Desktop.qml margins).
bar_h() {
  python3 -I - <<'PY'
import json, os, socket
s = socket.socket(socket.AF_UNIX); s.settimeout(5); s.connect(os.environ["KURASHI_SOCKET"]); f = s.makefile("rwb")
def send(m): f.write((json.dumps(m) + "\n").encode()); f.flush()
send({"t": "hello", "v": 1, "client": "test", "caps": []}); f.readline()
send({"t": "sub", "id": "s", "doc": "theme"})
while True:
    m = json.loads(f.readline())
    if m.get("id") == "s" and m["t"] == "snap":
        print(int(m["data"]["tokens"].get("bar.height", 36))); break
PY
}
shot() { # shot <name>
  sleep "${WAIT:-1.5}"
  grim -g "$DESK_GEOM" "$OUT/$1.png"
  [ -s "$OUT/$1.png" ] || fail "empty screenshot $1"
  echo "shot $1"
}
kp() { for k in "$@"; do echo "$k" >&3; sleep 0.35; done; }
DEFAULT='["clock","calendar","media","weather"]'

start_all() { # start_all <decor>
  stop_pointer
  stop_keys
  stop_shell
  stop_daemon
  rm -rf "$R/xdg" "$VAULT"
  mkdir -p "$XDG_CONFIG_HOME/kurashi" "$XDG_STATE_HOME" "$XDG_DATA_HOME" "$XDG_CACHE_HOME" "$VAULT"
  printf -- '- [ ] Buy rice\n- [ ] Call the dentist\n' > "$VAULT/Tasks.md"
  cat > "$XDG_CONFIG_HOME/kurashi/config.toml" <<TOML
theme.style = "$1"
desktop.enabled = true

[mods.tasks]
file = "$VAULT/Tasks.md"
notes_file = "$VAULT/Note.md"
TOML
  rm -f "$KURASHI_SOCKET"
  env DBUS_SYSTEM_BUS_ADDRESS="unix:path=$R/no-system-bus" PULSE_SERVER="unix:$R/no-pulse/native" \
    PULSE_RUNTIME_PATH="$R/no-pulse" "$W/kurashid" >> "$R/kurashid.log" 2>&1 &
  DPID=$!
  for _ in $(seq 100); do [ -S "$KURASHI_SOCKET" ] && K ping >/dev/null 2>&1 && break; sleep 0.1; done
  K ping >/dev/null 2>&1 || fail "kurashid did not come up (see $R/kurashid.log)"
  K act mod.enable '{"id": "tasks"}' >/dev/null || fail "mod.enable tasks failed"
  swaymsg output '*' bg '#8fb8c8' solid_color >/dev/null 2>&1 || true
  env -u KURASHI_SOCKET qs -p "$ROOT/frontend" >> "$R/qs.log" 2>&1 &
  SHPID=$!
  sleep "${SHELL_WAIT:-5}"
  # One virtual keyboard for the whole run (a keyboard that goes away drops the focus).
  rm -f "$R/keys.fifo"
  mkfifo "$R/keys.fifo"
  python3 -I "$ROOT/tools/bench/wl_keys.py" --serve < "$R/keys.fifo" >> "$R/keys.log" 2>&1 &
  KPID=$!
  exec 3> "$R/keys.fifo"
  # And one pointer: a hover lasts as long as it does.
  rm -f "$R/pointer.fifo"
  mkfifo "$R/pointer.fifo"
  python3 -I "$ROOT/tools/bench/wl_pointer.py" --serve < "$R/pointer.fifo" >> "$R/keys.log" 2>&1 &
  PPID_=$!
  exec 4> "$R/pointer.fifo"
}
# The Edit key: on the column's top-right corner while the pointer is over the desk. The pointer moves there first (the
# hover shows the key; a name given takes a shot of that), then presses; then it leaves the desk.
edit_key() {
  local top; top=$(( $(bar_h) + 28 ))
  echo "move 2490 $(( top + 22 ))" >&4
  sleep 1
  [ -z "${1:-}" ] || shot "$1"
  echo "click 2490 $(( top + 22 )) left" >&4
  sleep 0.8
  echo "move 1200 700" >&4
  sleep 0.5
}

for DECOR in $DECORS; do
  echo "== $DECOR: the order from kurashi set"
  start_all "$DECOR"
  K set desktop.order '["calendar","mod:tasks:tasks","clock"]' | grep -q '^applied' || fail "kurashi set desktop.order was not applied"
  wait_val desktop.order '["calendar","mod:tasks:tasks","clock"]'
  check "$([ "$(val desktop.order)" = '["calendar","mod:tasks:tasks","clock"]' ] && echo 1 || echo 0)" "$DECOR kurashi set wrote the order"
  shot "ordered-$DECOR"
  K raw '{"t":"apply","id":"r","ops":[{"reset":"desktop.order"}]}' | grep -q applied || fail "the order reset was refused"
  wait_val desktop.order "$DEFAULT"

  echo "== $DECOR: edit mode by keys, Done"
  edit_key "hover-$DECOR"
  shot "edit-$DECOR"
  kp alt+down down space
  shot "edit-moved-$DECOR"
  kp return
  wait_val desktop.media false
  # The mod cards come after, in the order the mods document lists them (row 123): both are there, once.
  check "$(val desktop.order | python3 -c 'import json,sys; o = json.load(sys.stdin); sys.exit(0 if o[:4] == ["calendar","clock","media","weather"] and sorted(o[4:]) == ["mod:tasks:notes","mod:tasks:tasks"] else 1)' && echo 1 || echo 0)" "$DECOR Done wrote the order with the clock below the calendar ($(val desktop.order))"
  check "$([ "$(val desktop.media)" = false ] && echo 1 || echo 0)" "$DECOR Space hid the media card (desktop.media = $(val desktop.media))"
  shot "saved-$DECOR"
  K raw '{"t":"undo","id":"u"}' | grep -q applied || fail "undo was refused"
  wait_val desktop.media true
  check "$([ "$(val desktop.order)" = "$DEFAULT" ] && [ "$(val desktop.media)" = true ] && echo 1 || echo 0)" "$DECOR one undo put the order and the switch back (one change)"

  echo "== $DECOR: edit mode, Escape"
  edit_key
  kp alt+down escape
  sleep 1
  check "$([ "$(val desktop.order)" = "$DEFAULT" ] && echo 1 || echo 0)" "$DECOR Escape wrote nothing ($(val desktop.order))"
done
stop_pointer
stop_keys
stop_shell
stop_daemon

if grep -Eq 'ReferenceError|TypeError|binding loop|is not a function|is not defined|is not a type' "$R/qs.log" 2>/dev/null; then
  echo "QML errors in qs.log: $(grep -E 'ReferenceError|TypeError|binding loop|is not a function|is not defined|is not a type' "$R/qs.log" | head -5)" >&2
  FAILS=$((FAILS + 1))
fi
if grep -Ei 'Desktop.qml' "$R/qs.log" 2>/dev/null | grep -Eiq 'warn|error'; then
  echo "QML warnings from the desk: $(grep -Ei 'Desktop.qml' "$R/qs.log" | head -5)" >&2
  FAILS=$((FAILS + 1))
fi
if grep -q panicked "$R/kurashid.log" 2>/dev/null; then
  echo "kurashid panicked (see $R/kurashid.log)" >&2
  FAILS=$((FAILS + 1))
fi
echo "checks: $((CHECKS - FAILS < 0 ? 0 : CHECKS - FAILS)) of $CHECKS"
[ "$FAILS" -eq 0 ] || fail "$FAILS failure(s); logs in $R, screenshots in $OUT"
echo "ok: screenshots in $OUT"
