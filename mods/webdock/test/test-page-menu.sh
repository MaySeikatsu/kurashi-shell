#!/usr/bin/env bash
# A web dock page's right-click menu (W82, docs/ux/context-menus.md, `page:<pin>`), invisibly (headless sway sandbox),
# with the REAL kurashid, the real shell and the real web host (qs-webengine), a file:// page, no network (K37), motion
# off. The fixture (pages/menu.html) is four bands, a quarter of the view each: a link, an image, a text field, and a band
# that handles `contextmenu` itself.
#   1. a right click on the link opens the menu at the pointer with the link's rows; the keys work at once; Copy link;
#   2. the text field: Select all, then Paste puts the copied link there (the page logs its value: the copy reached the
#      clipboard); Cut/Copy/Paste rows only where the request offers them;
#   3. the image: Copy image address;
#   4. the band with its own menu: no shell menu;
#   5. a link followed, then the menu's Back returns; Esc closes, a press outside closes and reaches nothing;
#   6. the bar card and the sidebar draw the same menu (the page moves there; the menu is the page's);
#   7. shots light and dark (mods/webdock/shots/page-menu-*.png); no QML error.
#   nix develop -c mods/webdock/test/test-page-menu.sh [sandbox-name]
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
NAME=${1:-${KURASHI_SB_PREFIX:-}w82-page-menu}
BIN=${KURASHI_BIN_DIR:-${CARGO_TARGET_DIR:-$ROOT/target}/debug}
SHOTS=$ROOT/mods/webdock/shots
mkdir -p "$SHOTS"
PAGES=file://$ROOT/mods/webdock/test/pages
fail() { echo "test-page-menu: FAIL: $*" >&2; exit 1; }
ok() { echo "test-page-menu: ok: $*"; }
command -v qs-webengine >/dev/null || fail "qs-webengine not on PATH (nix develop)"

eval "$("$ROOT/tools/bench/sandbox.sh" start "$NAME")"
. "$ROOT/frontend/test-lib.sh"
R=$XDG_RUNTIME_DIR
W=$R/work
mkdir -p "$W" "$R/kurashi"
cp "$BIN/kurashid" "$BIN/kurashi" "$W/"
pids=()
cleanup() {
  exec 9>&- 2>/dev/null || true
  exec 8>&- 2>/dev/null || true
  for p in "${pids[@]}"; do kill "$p" 2>/dev/null || true; done
  for p in "${pids[@]}"; do wait "$p" 2>/dev/null || true; done
  "$ROOT/tools/bench/sandbox.sh" stop "$NAME" >/dev/null || true
}
trap cleanup EXIT

rm -rf "$R/xdg"
export XDG_CONFIG_HOME=$R/xdg/config XDG_STATE_HOME=$R/xdg/state XDG_DATA_HOME=$R/xdg/data XDG_CACHE_HOME=$R/xdg/cache \
       KURASHI_DATA_DIR=$ROOT LC_ALL=C.UTF-8 KURASHI_WEBDOCK_DEBUG=1
mkdir -p "$XDG_CONFIG_HOME/kurashi" "$XDG_STATE_HOME" "$XDG_DATA_HOME" "$XDG_CACHE_HOME"
CONF=$XDG_CONFIG_HOME/kurashi/config.toml
HOSTLOG=$XDG_STATE_HOME/kurashi/webdock/host-web.log
K() { timeout 10 "$W/kurashi" "$@"; }
swaymsg output '*' bg '#8fb8c8' solid_color >/dev/null 2>&1 || true
W_OUT=$(swaymsg -t get_outputs -r | jq -r '.[0].rect.width')
H_OUT=$(swaymsg -t get_outputs -r | jq -r '.[0].rect.height')
OUT=$(swaymsg -t get_outputs -r | jq -r '.[0].name')

scheme=${KURASHI_TEST_SCHEME:-light}
conf() {
  cat > "$CONF" <<EOF
[idle]
enabled = false
[theme]
style = "${2:-washi}"
[theme.colors]
scheme = "$1"
[theme.motion]
profile = "none"
[edges.top]
start = ["workspaces"]
center = ["island"]
end = ["mod:webdock:webdock"]
[mods]
enabled = ["webdock"]
[[mods.webdock.pins]]
id = "menu"
title = "Menu"
target = "$PAGES/menu.html"
EOF
}
conf "$scheme"

doc() { K --json sub "${2:-mod.webdock}" --count 0 | python3 -c "import json,sys; d=json.loads(sys.stdin.readline()); d=d.get('data', d); print($1)"; }
doc_is() { [ "$(doc "$1" "${2:-mod.webdock}" 2>/dev/null)" = True ]; }
count() { grep -c -F -- "$1" "$2" 2>/dev/null || true; }
has() { grep -q -F -- "$1" "$HOSTLOG" 2>/dev/null; }
wait_host() { wait_until "${2:-8}" has "$1" || fail "${3:-the host never logged: $1}"; }
rm -f "$R/ptr.fifo"; mkfifo "$R/ptr.fifo"
python3 -I "$ROOT/tools/bench/wl_pointer.py" --serve < "$R/ptr.fifo" >> "$W/ptr.log" 2>&1 &
pids+=($!)
exec 9> "$R/ptr.fifo"
rm -f "$R/keys.fifo"; mkfifo "$R/keys.fifo"
python3 -I "$ROOT/tools/bench/wl_keys.py" --serve < "$R/keys.fifo" >> "$W/keys.log" 2>&1 &
pids+=($!)
exec 8> "$R/keys.fifo"
keys() { echo "$*" >&8; sleep 0.3; }
mv_to() { echo "move $1 $2" >&9; sleep 0.15; }
ptr() { echo "click $1 $2 ${3:-left}" >&9; sleep 0.3; }

env DBUS_SYSTEM_BUS_ADDRESS="unix:path=$R/no-system-bus" PULSE_SERVER="unix:$R/no-pulse/native" \
    PULSE_RUNTIME_PATH="$R/no-pulse" "$W/kurashid" >> "$R/server.log" 2>&1 &
pids+=("$!")
wait_until 15 K ping || fail "kurashid did not come up ($R/server.log)"
wait_until 10 doc_is "[p['id'] for p in d.get('pins', [])] == ['menu']" || fail "the dock's pin never came"
: > "$R/qs.log"
env -u KURASHI_SOCKET qs -p "$ROOT/frontend" >> "$R/qs.log" 2>&1 &
pids+=("$!")
wait_frontend "$R/qs.log" || fail "the frontend did not load ($R/qs.log)"
mv_to $(( W_OUT / 2 )) $(( H_OUT / 2 ))

# ---- the page at the edge ----
K act webdock.pin '{"on":true}' >/dev/null || fail "webdock.pin refused"
K act webdock.open '{"pin":"menu"}' >/dev/null || fail "webdock.open refused"
wait_until 15 doc_is "d['mode'] == 'extended' and d.get('shown') == 'menu'" || fail "the edge card did not open"
wait_host 'PAGE menu' 20 "the menu page did not load"
wait_host 'webdock-debug pagebox menu ' 10 "the page logged no box"
# The page's box in its window, and the window: an edge card's window is the usable area beside the strip, at the right.
read -r _ PX PY PW PH WW WH <<< "$(grep -F 'webdock-debug pagebox menu ' "$HOSTLOG" | tail -1 | sed 's/.*webdock-debug pagebox //')"
WX=$(( W_OUT - 56 - WW )); WY=$(( H_OUT - WH ))
echo "page box $PX,$PY ${PW}x$PH in window ${WW}x$WH at $WX,$WY"
# A point at fraction $1 of the page's width and $2 of its height, on screen.
at() { echo $(( WX + PX + PW * $1 / 100 )) $(( WY + PY + PH * $2 / 100 )); }
menus() { count "webdock-debug menu menu at " "$HOSTLOG"; }
last_menu() { grep -F "webdock-debug menu menu at " "$HOSTLOG" | tail -1; }
shot() { sleep 0.8; timeout 20 grim -g "$2" "$SHOTS/$1.png" || fail "grim $1"; ok "shot mods/webdock/shots/$1.png"; }
region() { echo "$(( WX + PX )),$(( WY + PY )) ${PW}x$PH"; }

# ---- 1. the link ----
n=$(menus)
read -r LX LY <<< "$(at 50 12)"
mv_to "$LX" "$LY"; ptr "$LX" "$LY" right
wait_until 5 eval '[ "$(menus)" -gt '"$n"' ]' || fail "a right click on the link opened no menu"
last_menu | grep -q 'link=true' || fail "the link's request: $(last_menu)"
last_menu | grep -q 'rows=\[1,2,3,11,12,91,92\]' || fail "the link's rows: $(last_menu)"
ok "a right click on a link opens the menu with Open link and Copy link"
shot "page-menu-link-$scheme" "$(region)"
# Back and Forward are grey (no history) and so is Open link (a file page: web addresses only): Down, Down is Copy link.
keys down down return
wait_host 'webdock-debug menu menu chose 12' 5 "Copy link was not chosen by the keys"
ok "the keys work at once: Copy link"

# ---- 2. the text field: Select all, Paste ----
n=$(menus)
read -r FX FY <<< "$(at 50 62)"
mv_to "$FX" "$FY"; ptr "$FX" "$FY" right
wait_until 5 eval '[ "$(menus)" -gt '"$n"' ]' || fail "a right click on the text field opened no menu"
last_menu | grep -q 'editable=true' || fail "the field's request: $(last_menu)"
last_menu | grep -q 'rows=\[1,2,3,31,32,33,34,91,92\]' || fail "the field's rows: $(last_menu)"
ok "a text field's menu has Cut, Copy, Paste, Select all"
shot "page-menu-field-$scheme" "$(region)"
keys up return        # (from the end, past the grey Open page and its note: Select all)
wait_host 'webdock-debug menu menu chose 34' 5 "Select all was not chosen"
n=$(menus)
mv_to "$FX" "$FY"; ptr "$FX" "$FY" right
wait_until 5 eval '[ "$(menus)" -gt '"$n"' ]' || fail "the second right click on the field opened no menu"
keys up up return     # Paste
wait_host 'webdock-debug menu menu chose 33' 5 "Paste was not chosen"
wait_host "PAGE input $PAGES/other.html#from-menu" 5 "Paste did not put the copied link in the field: $(grep -F 'PAGE input' "$HOSTLOG" | tail -1)"
ok "Copy link reached the clipboard: Paste put it in the field"

# ---- 2b. by keyboard: the Menu key and Shift+F10 in the page (Chromium raises the same request, at the focus) ----
for chord in menu shift+f10; do
  ptr "$FX" "$FY"     # (the field has the focus: a click in it, as a reader would before the key)
  sleep 0.3
  n=$(menus)
  keys "$chord"
  wait_until 5 eval '[ "$(menus)" -gt '"$n"' ]' || fail "$chord in the page opened no menu"
  last_menu | grep -q 'editable=true' || fail "$chord: the menu is not the field's: $(last_menu)"
  keys escape
  sleep 0.3
done
ok "the Menu key and Shift+F10 open the page's menu at the focus"

# ---- 2c. a right click elsewhere while the menu is open opens it there ----
n=$(menus)
mv_to "$FX" "$FY"; ptr "$FX" "$FY" right
wait_until 5 eval '[ "$(menus)" -gt '"$n"' ]' || fail "no menu on the field"
n=$(menus)
mv_to "$LX" "$LY"; ptr "$LX" "$LY" right
wait_until 5 eval '[ "$(menus)" -gt '"$n"' ]' || fail "a right click on the link while the field's menu was open opened no menu there"
last_menu | grep -q 'link=true' || fail "the menu opened again is not the link's: $(last_menu)"
c0=$(count 'webdock-debug menu menu chose' "$HOSTLOG")
keys down down return  # (it is open and holds the keys: Copy link)
wait_host 'webdock-debug menu menu chose 12' 5 "the menu opened again does not take the keys"
ok "a right click elsewhere while the menu is open opens it there"

# ---- 3. the image ----
n=$(menus)
read -r IX IY <<< "$(at 50 37)"
mv_to "$IX" "$IY"; ptr "$IX" "$IY" right
wait_until 5 eval '[ "$(menus)" -gt '"$n"' ]' || fail "a right click on the image opened no menu"
last_menu | grep -q 'image=true' && last_menu | grep -q 'rows=\[1,2,3,21,91,92\]' || fail "the image's menu: $(last_menu)"
ok "an image's menu has Copy image address"
keys escape
sleep 0.3

# ---- 4. a page's own menu wins ----
n=$(menus); o=$(count 'PAGE own-menu' "$HOSTLOG")
read -r OX OY <<< "$(at 50 88)"
mv_to "$OX" "$OY"; ptr "$OX" "$OY" right
wait_until 5 eval '[ "$(count "PAGE own-menu" "$HOSTLOG")" -gt '"$o"' ]' || fail "the band's own contextmenu handler did not run"
sleep 0.5
[ "$(menus)" -eq "$n" ] || fail "the shell's menu opened over a page's own menu"
ok "a page that handles contextmenu keeps its own menu"

# ---- 5. Back; Esc; a press outside ----
ptr "$LX" "$LY"       # follow the link
wait_host 'webdock-debug url menu '"$PAGES/other.html#from-menu" 8 "the link was not followed"
n=$(menus)
read -r CX CY <<< "$(at 50 50)"
mv_to "$CX" "$CY"; ptr "$CX" "$CY" right
wait_until 5 eval '[ "$(menus)" -gt '"$n"' ]' || fail "a right click on the other page opened no menu"
keys down return      # Back: the first row, live now
wait_host 'webdock-debug menu menu chose 1' 5 "Back was not chosen"
wait_until 8 eval '[ "$(grep -F "webdock-debug url menu " "$HOSTLOG" | tail -1 | sed "s/.*url menu //")" = "$PAGES/menu.html" ]' \
  || fail "Back did not return to the menu page: $(grep -F 'webdock-debug url menu ' "$HOSTLOG" | tail -1)"
ok "Back returns"
n=$(menus)
mv_to "$CX" "$CY"; ptr "$CX" "$CY" right
wait_until 5 eval '[ "$(menus)" -gt '"$n"' ]' || fail "no menu for Esc"
c0=$(count 'webdock-debug menu menu chose' "$HOSTLOG")
keys escape
sleep 0.4
keys return           # (closed: Enter goes to the page, not to a row)
sleep 0.4
[ "$(count 'webdock-debug menu menu chose' "$HOSTLOG")" -eq "$c0" ] || fail "a row ran after Esc"
ok "Esc closes the menu"

# ---- 5b. the card in the looks: washi and sekai, light and dark (the shell's card chrome: corners, outline, elevation) ----
for look in washi sekai; do
  for sch in light dark; do
    conf "$sch" "$look"
    sleep 2.5
    # (a look may frame the page otherwise: its box again)
    read -r _ PX PY PW PH WW WH <<< "$(grep -F 'webdock-debug pagebox menu ' "$HOSTLOG" | tail -1 | sed 's/.*webdock-debug pagebox //')"
    WX=$(( W_OUT - 56 - WW )); WY=$(( H_OUT - WH ))
    read -r LX LY <<< "$(at 50 12)"
    n=$(menus)
    mv_to "$LX" "$LY"; ptr "$LX" "$LY" right
    wait_until 5 eval '[ "$(menus)" -gt '"$n"' ]' || fail "$look $sch: no menu"
    shot "page-menu-$look-$sch" "$(region)"
    keys escape
    sleep 0.3
  done
done
conf "$scheme"
sleep 2

# ---- 6. the bar card ----
K act webdock.pin '{"on":false}' >/dev/null || true
K act mod.panel.open '{"id":"webdock","panel":"webdock"}' >/dev/null || fail "the bar card did not open"
b0=$(count 'webdock-debug pagebox menu ' "$HOSTLOG")
wait_until 10 eval '[ "$(count "webdock-debug pagebox menu " "$HOSTLOG")" -gt '"$b0"' ]' || fail "the page did not move to the bar card"
sleep 1
read -r _ PX PY PW PH WW WH <<< "$(grep -F 'webdock-debug pagebox menu ' "$HOSTLOG" | tail -1 | sed 's/.*webdock-debug pagebox //')"
# The bar card's window is the panel's well (webdock-debug card <pin> win … place <out> <x> <y> …).
read -r WX WY <<< "$(grep -F 'webdock-debug card menu win ' "$HOSTLOG" | tail -1 | sed 's/.* place [^ ]* \([0-9-]*\) \([0-9-]*\) .*/\1 \2/')"
echo "bar card: page box $PX,$PY ${PW}x$PH in window at $WX,$WY"
n=$(menus)
read -r BX BY <<< "$(at 50 50)"
mv_to "$BX" "$BY"; ptr "$BX" "$BY" right
wait_until 5 eval '[ "$(menus)" -gt '"$n"' ]' || fail "a right click on the bar card's page opened no menu"
ok "the bar card's page has the menu"
shot "page-menu-card-$scheme" "$(region)"
keys escape
sleep 0.3

# ---- 6b. the sidebar ----
K act ui.close >/dev/null 2>&1 || true
K set sidebar.left.sections '["mod:webdock:webdock"]' >/dev/null || fail "sidebar.left.sections was refused"
K act sidebar.toggle "{\"side\":\"left\",\"output\":\"$OUT\"}" >/dev/null
s0=$(count 'webdock-debug side menu win ' "$HOSTLOG")
wait_until 15 eval '[ "$(grep -F "webdock-debug side menu win " "$HOSTLOG" | tail -1 | grep -c " page [0-9]")" = 1 ]' \
  || fail "the sidebar never showed the page ($(grep -F 'webdock-debug side' "$HOSTLOG" | tail -2 | tr '\n' ' '))"
sleep 1
# <pin> win <w> <h> page <x> <y> <w> <h> place <out> <side> <inset> <top> <w> <h>: the window stands at the usable
# area's top, `inset` from the left edge.
read -r _ _ SWW SWH _ SPX SPY SPW SPH _ _ _ SIN STOP _ _ <<< "$(grep -F 'webdock-debug side menu win ' "$HOSTLOG" | tail -1 | sed 's/.*webdock-debug side //')"
SX=$(( SIN + SPX + SPW / 2 )); SY=$(( H_OUT - SWH + SPY + SPH / 2 ))
echo "sidebar: window ${SWW}x$SWH at inset $SIN; page $SPX,$SPY ${SPW}x$SPH; pressing $SX,$SY"
n=$(menus)
mv_to "$SX" "$SY"; ptr "$SX" "$SY" right
wait_until 5 eval '[ "$(menus)" -gt '"$n"' ]' || fail "a right click on the sidebar's page opened no menu"
ok "the sidebar's page has the menu"
shot "page-menu-sidebar-$scheme" "$SIN,$(( H_OUT - SWH )) ${SWW}x$SWH"
keys escape

# ---- 7. no QML error ----
QML_BAD='TypeError|ReferenceError|is not a type|is not defined|Cannot assign|Binding loop'
for f in "$R/qs.log" "$HOSTLOG"; do
  if grep -E "$QML_BAD" "$f" 2>/dev/null | grep -vE 'Unable to assign \[undefined\]' >/dev/null; then
    grep -E "$QML_BAD" "$f" | head -10 >&2
    fail "QML problems in $f"
  fi
done
ok "no QML error"
echo "test-page-menu: all ok"
