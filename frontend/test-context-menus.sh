#!/usr/bin/env bash
# Right-click menus everywhere (W82, docs/ux/context-menus.md), on the REAL kurashid, invisibly (headless sway sandbox), by a
# virtual pointer and keyboard. The look is checked on nested niri (tools/bench/niri-sandbox.sh); this is the regression:
#   1. a right click on the wallpaper opens the desktop's menu (`desktop:<output>`) with its corner at the pointer; the
#      keys work at once: Down, Enter flips Dark mode (`theme.colors.scheme`) and the menu stays; Esc closes it;
#   2. near the output's far corner the card turns left and up, still on the output;
#   3. a right click on an empty part of the bar opens the bar's menu (`bar:<output>/top`); a row changes its setting
#      (`bar.popups_follow`) and the menu stays; a right click on the clock still opens the clock's own menu;
#   4. the keyboard path without a pointer: `tray.menu.open {id: desktop}` opens it centred, Esc closes;
#   5. the desktop widgets' cards answer the right click with the same menu;
#   6. shots light and dark (frontend/shots/context-menu-*.png); no QML error.
#   nix develop -c frontend/test-context-menus.sh [sandbox-name]
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
NAME=${1:-${KURASHI_SB_PREFIX:-}w82-ctx-menus}
BIN=${KURASHI_BIN_DIR:-${CARGO_TARGET_DIR:-$ROOT/target}/debug}
SHOTS=$ROOT/frontend/shots
mkdir -p "$SHOTS"
fail() { echo "test-context-menus: FAIL: $*" >&2; exit 1; }
ok() { echo "test-context-menus: ok: $*"; }

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
       KURASHI_DATA_DIR=$ROOT LC_ALL=C.UTF-8 KURASHI_SOCKET=$R/kurashi.sock KURASHI_STAGE_DEBUG=1
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
end = ["clock"]'
conf() { printf '%s\n%s\n' "$1" "$base" > "$CONF"; sleep 1.5; }
printf '%s\n' "$base" > "$CONF"
swaymsg output '*' bg '#5d7f8f' solid_color >/dev/null 2>&1 || true
# A layer above the user (K15) forces one of the bar's rows: the menu shows it grey and says who holds it.
printf '[_managed]\nenforce = true\n\n[bar]\ncard_keep_loaded = true\n' > "$XDG_CONFIG_HOME/kurashi/managed.toml"

env DBUS_SYSTEM_BUS_ADDRESS="unix:path=$R/no-system-bus" PULSE_SERVER="unix:$R/no-pulse/native" PULSE_RUNTIME_PATH="$R/no-pulse" \
  "$W/kurashid" >> "$R/kurashid.log" 2>&1 &
pids+=($!)
wait_until 15 K ping || fail "kurashid did not answer"
: > "$R/qs.log"
qs -p "$ROOT/frontend" >> "$R/qs.log" 2>&1 &
pids+=($!)
wait_frontend "$R/qs.log" || fail "the frontend did not load"

OUT=$(swaymsg -t get_outputs -r | jq -r '.[0].name')
W_OUT=$(swaymsg -t get_outputs -r | jq -r '.[0].rect.width')
H_OUT=$(swaymsg -t get_outputs -r | jq -r '.[0].rect.height')
ptr() { python3 -I "$ROOT/tools/bench/wl_pointer.py" click "$1" "$2" "${3:-left}"; }
keys() { python3 -I "$ROOT/tools/bench/wl_keys.py" "$@"; }
doc() { K sub "$1" --count 0 2>/dev/null | head -1; }
ui_is() { doc runtime.ui | grep -q "$1"; }
closed() { ui_is '"tray":""'; }
# The last place the Stage logged for a menu at the pointer: TARGET OUTN CX CY CW CH PX PY.
placed_line() {
  local since=$1
  wait_for "$R/qs.log" 'stage-menu ' 8 "$since" || fail "no menu place logged"
  sleep 0.4
  read -r TARGET OUTN CX CY CW CH PX PY < <(tail -c +"$(( since + 1 ))" "$R/qs.log" | grep -a 'stage-menu ' | tail -1 | sed 's/.*stage-menu //')
}
close_menu() { keys escape; wait_until 5 closed || fail "Esc did not close the menu: $(doc runtime.ui)"; sleep 0.4; }
shot() { sleep 0.6; timeout 20 grim -g "$2" "$SHOTS/$1.png" || fail "grim $1"; ok "shot frontend/shots/$1.png"; }

# ---- 1. the desktop: at the pointer, the keys at once, a toggle applies and the menu stays ----
since=$(log_size "$R/qs.log")
ptr 600 500 right
wait_until 5 ui_is "\"tray\":\"desktop:$OUT\"" || fail "a right click on the wallpaper opened no menu: $(doc runtime.ui)"
placed_line "$since"
[ "$TARGET" = "desktop:$OUT" ] && [ "$PX" = 600 ] && [ "$PY" = 500 ] || fail "the menu logged $TARGET at $PX,$PY"
[ "$CX" -eq 600 ] && [ "$CY" -eq 500 ] || fail "the card stands at $CX,$CY, not at the pointer 600,500"
ok "a right click on the wallpaper opens the desktop's menu at the pointer"
shot context-menu-desktop "$CX,$CY ${CW}x${CH}"
dark_was=$(K get theme.colors.scheme | tr -d ' "' | sed 's/.*=//')
# Down, Enter: the first row (no wallpaper mod): Dark mode.
keys down return
scheme_changed() { [ "$(K get theme.colors.scheme | tr -d ' "' | sed 's/.*=//')" != "$dark_was" ]; }
wait_until 5 scheme_changed || fail "Dark mode did not change theme.colors.scheme (still $dark_was)"
ui_is "\"tray\":\"desktop:$OUT\"" || fail "the menu closed after a change"
ok "the keys work at once: Dark mode applies ($dark_was → $(K get theme.colors.scheme | sed 's/.*= *//')) and the menu stays"
shot context-menu-desktop-dark "$CX,$CY ${CW}x${CH}"
close_menu
ok "Esc closes it"

# ---- 2. the far corner: turned left and up, on the output ----
since=$(log_size "$R/qs.log")
ptr $(( W_OUT - 20 )) $(( H_OUT - 20 )) right
wait_until 5 ui_is "\"tray\":\"desktop:$OUT\"" || fail "the corner's right click opened no menu"
placed_line "$since"
[ $(( CX + CW )) -le "$W_OUT" ] && [ $(( CY + CH )) -le "$H_OUT" ] && [ "$CX" -lt $(( W_OUT - 20 )) ] \
  || fail "the corner's card at $CX,$CY ${CW}x$CH leaves the ${W_OUT}x$H_OUT output"
[ $(( CX + CW )) -le $(( W_OUT - 20 )) ] || fail "the card did not turn left of the pointer ($CX + $CW)"
ok "near the far corner the card turns left and up, on the output"
close_menu

# ---- 3. the bar's empty part; a row applies; the clock keeps its own ----
since=$(log_size "$R/qs.log")
ptr $(( W_OUT * 3 / 4 )) 14 right
wait_until 5 ui_is "\"tray\":\"bar:$OUT/top\"" || fail "a right click on the bar's empty part opened no menu: $(doc runtime.ui)"
placed_line "$since"
[ "$PX" = $(( W_OUT * 3 / 4 )) ] || fail "the bar's menu logged the pointer at $PX"
ok "a right click on the bar's empty part opens the bar's menu at the pointer"
rows=$(tail -c +"$(( since + 1 ))" "$R/qs.log" | grep -a 'stage-menu-rows ' | tail -1 | sed 's/.*stage-menu-rows //')
case "$rows" in *"|-Keep a closed card ready|-forced: "*) ;; *) fail "the forced row is not grey with its reason: $rows" ;; esac
case "$rows" in *"|+Edit layout…") ;; *) fail "the bar's menu does not end in Edit layout…: $rows" ;; esac
ok "a forced row stays, grey, and says who holds it ($(echo "$rows" | grep -o 'forced: [^|]*'))"
shot context-menu-bar "$CX,$CY ${CW}x${CH}"
# Rows: edges.top.bar, .visibility, .reserve, .draw, bar.height, bar.popups, bar.popups_follow (7th).
keys down down down down down down down return
follow_off() { K get bar.popups_follow | grep -q false; }
wait_until 5 follow_off || fail "the bar menu's row did not set bar.popups_follow: $(K get bar.popups_follow)"
ui_is "\"tray\":\"bar:$OUT/top\"" || fail "the bar's menu closed after a change"
ok "a bar row changes its setting (bar.popups_follow) and the menu stays"
close_menu
ptr "$(( W_OUT - 40 ))" 14 right
wait_until 5 ui_is '"tray":"module:clock"' || fail "the clock's right click no longer opens its own menu: $(doc runtime.ui)"
ok "a module keeps its own right click"
close_menu

# ---- 4. by key: the action without a pointer opens it centred ----
since=$(log_size "$R/qs.log")
sleep 1.6   # (older than a fresh press)
K act tray.menu.open '{"id":"desktop"}' >/dev/null
wait_until 5 ui_is '"tray":"desktop"' || fail "tray.menu.open {id: desktop} opened nothing"
placed_line "$since"
[ "$PX" = - ] || fail "a menu opened by key took a stale pointer $PX,$PY"
near() { [ "$(( $1 > $2 ? $1 - $2 : $2 - $1 ))" -le "${3:-2}" ]; }
near "$CX" $(( (W_OUT - CW) / 2 )) || fail "by key: card x $CX is not centred"
ok "the action opens it without a pointer, centred"
close_menu

# ---- 5. the desktop widgets' cards ----
conf '[desktop]
enabled = true
side = "left"'
sleep 1.5
since=$(log_size "$R/qs.log")
ptr 160 220 right
wait_until 5 ui_is "\"tray\":\"desktop:$OUT\"" || fail "a right click on a desktop card opened no menu: $(doc runtime.ui)"
placed_line "$since"
near "$PX" 160 1 && near "$PY" 220 1 || fail "the card's right click logged the pointer at $PX,$PY"
ok "the desktop widgets answer the right click with the desktop's menu"
close_menu

# ---- 6. no QML error ----
if grep -E 'TypeError|ReferenceError|is not a type|is not defined|Cannot assign|Binding loop' "$R/qs.log" | grep -v 'Unable to assign \[undefined\]' >/dev/null; then
  grep -E 'TypeError|ReferenceError|is not a type|is not defined|Cannot assign|Binding loop' "$R/qs.log" | head -10 >&2
  fail "QML problems in the shell's log"
fi
ok "no QML error"
echo "test-context-menus: all ok"
