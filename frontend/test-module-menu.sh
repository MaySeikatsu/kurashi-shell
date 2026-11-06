#!/usr/bin/env bash
# Where the launcher opens (I407, docs/ux/launcher.md) and a module's right-click menu (I408, docs/ux/module-menu.md), on
# the REAL kurashid, invisibly (headless sway sandbox), by a virtual pointer and keyboard:
#   1. `launcher.place = opened` (the default): by its key in the middle of the output, by a click at the button, from the
#      launcher's own bar module; `centre` is the middle for a click too; `fixed` puts it at `place_x`/`place_y`; `island`
#      hangs it from the bar.
#   2. a right click on the clock opens `module:clock` (the Stage's `tray` panel); a menu row changes the setting and the
#      menu stays; Escape closes it; the workspaces' right click opens their own.
#   nix develop -c frontend/test-module-menu.sh [sandbox-name]
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
NAME=${1:-${KURASHI_SB_PREFIX:-}s23-menu-test}
BIN=${KURASHI_BIN_DIR:-${CARGO_TARGET_DIR:-$ROOT/target}/debug}
fail() { echo "test-module-menu: FAIL: $*" >&2; exit 1; }

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
       KURASHI_DATA_DIR=$ROOT LC_ALL=C.UTF-8 KURASHI_SOCKET=$R/kurashi.sock KURASHI_LAUNCHER_LOG=1
mkdir -p "$XDG_CONFIG_HOME/kurashi" "$XDG_STATE_HOME" "$XDG_DATA_HOME" "$XDG_CACHE_HOME"
CONF=$XDG_CONFIG_HOME/kurashi/config.toml
K() { timeout 10 "$W/kurashi" "$@"; }
base='[idle]
enabled = false
[theme.motion]
profile = "none"
[edges.top]
start = ["launcher", "workspaces"]
end = ["clock"]'
conf() { printf '%s\n%s\n' "$1" "$base" > "$CONF"; sleep 1.5; }
printf '%s\n' "$base" > "$CONF"

env DBUS_SYSTEM_BUS_ADDRESS="unix:path=$R/no-system-bus" PULSE_SERVER="unix:$R/no-pulse/native" PULSE_RUNTIME_PATH="$R/no-pulse" \
  "$W/kurashid" >> "$R/kurashid.log" 2>&1 &
pids+=($!)
wait_until 15 K ping || fail "kurashid did not answer"
: > "$R/qs.log"
qs -p "$ROOT/frontend" >> "$R/qs.log" 2>&1 &
pids+=($!)
wait_frontend "$R/qs.log" || fail "the frontend did not load"

ptr() { python3 -I "$ROOT/tools/bench/wl_pointer.py" click "$1" "$2" "${3:-left}"; }
keys() { python3 -I "$ROOT/tools/bench/wl_keys.py" "$@"; }
doc() { K sub "$1" --count 0 2>/dev/null | head -1; }
ui_is() { doc runtime.ui | grep -q "$1"; }

# Opens by `how`, waits for the place line, closes; PLACE X Y WW WH SW SH hold what it logged.
placed() {
  local since; since=$(log_size "$R/qs.log")
  "$@" >/dev/null
  wait_for "$R/qs.log" 'launcher-place ' 8 "$since" || fail "no place logged for: $*"
  read -r PLACE SW SH X Y WW WH FOOT < <(tail -c +"$(( since + 1 ))" "$R/qs.log" | grep -a 'launcher-place ' | tail -1 | sed 's/.*launcher-place //')
  K act launcher.toggle >/dev/null
  wait_until 5 ui_is '"launcher":false' || fail "the launcher did not close"
  sleep 0.3
}
near() { [ "$(( $1 > $2 ? $1 - $2 : $2 - $1 ))" -le "${3:-2}" ]; }

# ---- 1. where it opens ----
placed K act launcher.toggle
[ "$PLACE" = centre ] || fail "by key: place $PLACE, wanted centre"
near "$X" "$(( (SW - WW) / 2 ))" || fail "by key: x $X of $SW (window $WW) is not the middle"
echo "ok: by key: the middle of the output"

placed ptr 24 14
[ "$PLACE" = at ] || fail "by click: place $PLACE, wanted at"
[ "$X" -lt "$(( SW / 4 ))" ] && [ "$Y" -lt 80 ] || fail "by click: at $X,$Y, wanted under the button"
echo "ok: by click: at the button"

conf '[launcher]
place = "centre"'
placed ptr 24 14
[ "$PLACE" = centre ] || fail "centre, by click: place $PLACE"
near "$X" "$(( (SW - WW) / 2 ))" || fail "centre, by click: x $X"
echo "ok: place = centre: the middle for a click too"

conf '[launcher]
place = "fixed"
place_x = 100
place_y = 0'
placed K act launcher.toggle
[ "$PLACE" = fixed ] || fail "fixed: place $PLACE"
near "$X" "$(( SW - WW ))" && [ "$Y" -eq 0 ] || fail "fixed 100,0: at $X,$Y (window $WW of $SW)"
echo "ok: place = fixed: where the sliders say"

conf '[launcher]
place = "island"'
placed K act launcher.toggle
[ "$PLACE" = island ] || fail "island: place $PLACE"
echo "ok: place = island: out of the island"

# ---- 2. a module's own menu ----
W_OUT=$(swaymsg -t get_outputs | python3 -c 'import json,sys; print(json.load(sys.stdin)[0]["rect"]["width"])')
conf ''
ptr "$(( W_OUT - 40 ))" 14 right
wait_until 5 ui_is '"tray":"module:clock"' || fail "a right click on the clock opened no menu: $(doc runtime.ui)"
echo "ok: the clock's right click opens its menu"
sleep 0.5
# (the card takes the keyboard on demand: sway gives it on a click, so one on its title first)
ptr "$(( W_OUT - 335 ))" 63
sleep 0.2
# Down, Down: First day of the week, Week numbers; Enter sets it and the menu stays.
keys down down return
clock_on() { K get clock.week_numbers | grep -q true; }
wait_until 5 clock_on || fail "the menu's row did not set clock.week_numbers: $(K get clock.week_numbers)"
ui_is '"tray":"module:clock"' || fail "the menu closed after a change"
echo "ok: a row changes the setting and the menu stays"
keys escape
wait_until 5 ui_is '"tray":""' || fail "Escape did not close the menu"
echo "ok: Escape closes it"
sleep 0.5

ptr 70 14 right
wait_until 5 ui_is '"tray":"module:workspaces"' || fail "a right click on the workspaces opened no menu: $(doc runtime.ui)"
echo "ok: the workspaces' right click opens their own menu"
echo "test-module-menu: all ok"
