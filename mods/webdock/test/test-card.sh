#!/usr/bin/env bash
# The web dock's page in the bar module's card (W72, docs/ux/webdock.md "In the bar's card"), invisibly (headless sway
# sandbox), with the REAL kurashid, the real shell and the real web host (qs-webengine), two file:// pins, no network (K37),
# motion off (`theme.motion.profile = "none"`: the page appears at rest with a cut):
#   1. a top bar with the dock's module at its end: the card opens (`mod.panel.open`); the panel reports its well on the
#      output and the host maps its card window there: the window's rect is the well's, inside the card, under the pins
#      row; the page fills it under the navigation row and its colour is on screen;
#   2. closing the card unmaps the window (0 frames in 3 s), the page stays loaded; reopening shows it with no new load;
#   3. a click on the second pin's key switches the page; back to the first: no new load of either;
#   4. the same pin at the edge while the card shows it: the card keeps the page (no load); the edge takes it once the card
#      closes (no load);
#   5. `bar.hover = card`: a rest on the module opens the card; the pointer moved into the page keeps it; leaving closes it;
#   6. Tab past the card's keys hands the keyboard to the page; a click in the page gives it the keyboard (typed text
#      arrives either way); Esc closes the card;
#   7. a bottom bar: the same geometry checks; shots mods/webdock/shots/card-{top,bottom}.png;
#   8. no pin: the well says how to add one; no QML error or warning in the shell or the host.
#   nix develop -c mods/webdock/test/test-card.sh [sandbox-name]
# Binaries: kurashid and kurashi from $KURASHI_BIN_DIR (default $CARGO_TARGET_DIR/debug or target/debug).
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
NAME=${1:-${KURASHI_SB_PREFIX:-}w72-webdock-card}
BIN=${KURASHI_BIN_DIR:-${CARGO_TARGET_DIR:-$ROOT/target}/debug}
SHOTS=$ROOT/mods/webdock/shots
mkdir -p "$SHOTS"
PAGES=file://$ROOT/mods/webdock/test/pages
fail() { echo "test-card: FAIL: $*" >&2; exit 1; }
ok() { echo "test-card: ok: $*"; }
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
BG='#8fb8c8'
swaymsg output '*' bg "$BG" solid_color >/dev/null 2>&1 || true
W_OUT=$(swaymsg -t get_outputs -r | jq -r '.[0].rect.width')
H_OUT=$(swaymsg -t get_outputs -r | jq -r '.[0].rect.height')
OUT=$(swaymsg -t get_outputs -r | jq -r '.[0].name')

pins="[[mods.webdock.pins]]
id = \"site\"
title = \"Site\"
target = \"$PAGES/site.html#card\"
[[mods.webdock.pins]]
id = \"other\"
title = \"Other\"
target = \"$PAGES/other.html\""
base='[idle]
enabled = false
[theme]
style = "washi"
[theme.motion]
profile = "none"
[mods]
enabled = ["webdock"]'
top_bar='[edges.top]
start = ["workspaces"]
center = ["island"]
end = ["mod:webdock:webdock"]'
bottom_bar='[edges.top]
bar = false
start = []
center = []
end = []
[edges.bottom]
bar = true
start = ["workspaces"]
center = ["island"]
end = ["mod:webdock:webdock"]'
conf() { printf '%s\n%s\n%s\n' "$base" "$1" "${2-$pins}" > "$CONF"; }
conf "$top_bar"

# ---- helpers ----
doc() { K --json sub "${2:-mod.webdock}" --count 0 | python3 -c "import json,sys; d=json.loads(sys.stdin.readline()); d=d.get('data', d); print($1)"; }
doc_is() { [ "$(doc "$1" "${2:-mod.webdock}" 2>/dev/null)" = True ]; }
panel_open() { doc_is "d.get('panel') == 'mod:webdock:webdock'" runtime.ui; }
panel_closed() { doc_is "d.get('panel', '') == ''" runtime.ui; }
cat > "$W/px.py" <<'PY'
import sys
data = open(sys.argv[1], "rb").read()
fields, i = [], 0
while len(fields) < 4:
    while data[i:i + 1].isspace():
        i += 1
    j = i
    while not data[j:j + 1].isspace():
        j += 1
    fields.append(data[i:j])
    i = j
p = data[i + 1:i + 4]
want = tuple(int(sys.argv[2].lstrip("#")[k:k + 2], 16) for k in (0, 2, 4))
print("match" if max(abs(p[k] - want[k]) for k in range(3)) <= 12 else "other #%02x%02x%02x" % tuple(p))
PY
px_is() { timeout 20 grim -g "$1,$2 1x1" -t ppm "$W/px.ppm"; [ "$(python3 -I "$W/px.py" "$W/px.ppm" "$3")" = match ]; }
wait_px() { wait_until "$4" px_is "$1" "$2" "$3" || fail "pixel $1,$2 is not $3 ($(timeout 20 grim -g "$1,$2 1x1" -t ppm "$W/px.ppm"; python3 -I "$W/px.py" "$W/px.ppm" "$3"))"; }
count() { grep -c -F -- "$1" "$2" 2>/dev/null || true; }
loads() { count "sent webdock.host.loaded {\"pin\":\"$1\"}" "$HOSTLOG"; }
# The panel's last report: <output> <x> <y> <w> <h> panel <px> <py> <pw> <ph> pitch <pitch>
panel_card() { { grep -F 'webdock-panel card ' "$R/qs.log" || true; } | tail -1 | sed 's/.*webdock-panel card //'; }
# The host's last card window line for the pin $1: <pin> win <w> <h> page <x> <y> <w> <h> place <out> <x> <y> <w> <h>
card_line() { { grep -F "webdock-debug card $1 win " "$HOSTLOG" 2>/dev/null || true; } | tail -1 | sed 's/.*webdock-debug card //'; }
# QML problems and the scene's and QML's warnings (a refusal while the daemon or the shell goes away is not one).
QML_BAD='TypeError|ReferenceError|is not a type|is not defined|Cannot assign|Binding loop|caused by|failed to transition|WARN.{0,12}(scene|qml)'
QML_OK='Unable to assign \[undefined\]|refused: unavailable disconnected|refused this scope|refused this host'
qml_errors() {
  local f
  for f in "$R/qs.log" "$HOSTLOG"; do
    if grep -E "$QML_BAD" "$f" 2>/dev/null | grep -vE "$QML_OK" >/dev/null; then
      grep -E "$QML_BAD" "$f" | grep -vE "$QML_OK" | head -20 >&2
      fail "QML problems in $f"
    fi
  done
}
rm -f "$R/ptr.fifo"; mkfifo "$R/ptr.fifo"
python3 -I "$ROOT/tools/bench/wl_pointer.py" --serve < "$R/ptr.fifo" >> "$W/ptr.log" 2>&1 &
pids+=($!)
exec 9> "$R/ptr.fifo"
# One keyboard for the whole run too: without a keyboard on the seat the compositor sends no keyboard focus at all.
rm -f "$R/keys.fifo"; mkfifo "$R/keys.fifo"
python3 -I "$ROOT/tools/bench/wl_keys.py" --serve < "$R/keys.fifo" >> "$W/keys.log" 2>&1 &
pids+=($!)
exec 8> "$R/keys.fifo"
keys() { echo "$*" >&8; sleep 0.3; }
mv_to() { echo "move $1 $2" >&9; sleep 0.15; }
ptr() { echo "click $1 $2 ${3:-left}" >&9; sleep 0.25; }

# ---- the daemon, the mod, the pins; then the shell ----
env DBUS_SYSTEM_BUS_ADDRESS="unix:path=$R/no-system-bus" PULSE_SERVER="unix:$R/no-pulse/native" \
    PULSE_RUNTIME_PATH="$R/no-pulse" "$W/kurashid" >> "$R/server.log" 2>&1 &
pids+=("$!")
wait_until 15 K ping || fail "kurashid did not come up ($R/server.log)"
wait_until 10 doc_is "[p['id'] for p in d.get('pins', [])] == ['site', 'other']" || fail "the dock's pins never came ($(K get mods.enabled))"
: > "$R/qs.log"
env -u KURASHI_SOCKET qs -p "$ROOT/frontend" >> "$R/qs.log" 2>&1 &
pids+=("$!")
wait_frontend "$R/qs.log" || fail "the frontend did not load ($R/qs.log)"
mv_to $(( W_OUT / 2 )) $(( H_OUT / 2 ))

# check_geometry <pin> <bar edge>: the host's window is the well the panel reported, inside the card, under the pins row.
check_geometry() {
  local pin=$1 edge=$2
  wait_until 20 grep -qF "webdock-panel card $OUT " "$R/qs.log" || fail "the panel never reported its well ($R/qs.log)"
  wait_until 60 doc_is "d['host']['state'] == 'ready'" || fail "the host never got ready: $(doc "d['host']") ($HOSTLOG)"
  wait_until 60 doc_is "[p for p in d['pins'] if p['id'] == '$pin'][0].get('loaded') == True" || fail "the page never loaded"
  wait_until 20 grep -qF 'webdock-debug card shown' "$HOSTLOG" || fail "the host did not map its card window ($HOSTLOG)"
  local want; want=$(panel_card)
  read -r O X Y WW WH _ PX PY PW PH _ PITCH <<< "$want"
  wait_until 10 eval '[ "$(card_line '"$pin"' | sed "s/.* place //")" = "$O $X $Y $WW $WH" ]' \
    || fail "the host's place ($(card_line "$pin")) is not the panel's well ($want)"
  read -r _ _ HW HH _ GX GY GW GH _ <<< "$(card_line "$pin")"
  [ "$HW" = "$WW" ] && [ "$HH" = "$WH" ] || fail "the host's window is ${HW}x$HH, the well ${WW}x$WH"
  [ "$GX" = 0 ] && [ "$GW" = "$HW" ] && [ "$(( GY + GH ))" = "$HH" ] && [ "$GY" -le 64 ] \
    || fail "the page does not fill the window under its navigation row (page $GX $GY ${GW}x$GH in ${HW}x$HH)"
  # inside the panel (the card's content), under the pins row
  [ "$X" -ge "$PX" ] && [ $(( X + WW )) -le $(( PX + PW )) ] && [ $(( Y + WH )) -le $(( PY + PH )) ] \
    || fail "the well ($X,$Y ${WW}x$WH) is not inside the panel ($PX,$PY ${PW}x$PH)"
  [ $(( Y - PY )) -ge 40 ] || fail "the well starts $(( Y - PY )) px under the panel's top: over the pins row"
  case "$edge" in
    top) [ "$Y" -lt $(( H_OUT / 2 )) ] || fail "a top bar's card well starts at $Y" ;;
    bottom) [ $(( Y + WH )) -gt $(( H_OUT / 2 )) ] && [ $(( Y + WH )) -le "$H_OUT" ] || fail "a bottom bar's card well ends at $(( Y + WH ))" ;;
  esac
  CX=$(( X + WW / 2 )); CY=$(( Y + WH * 3 / 4 ))
  ok "$edge bar: the host's window is the well ($O $X,$Y ${WW}x$WH) inside the card's panel ($PX,$PY ${PW}x$PH), page ${GW}x$GH under a $GY px row"
}

# ---- 1. a top bar: the card shows the page in its well ----
K act mod.panel.open '{"id":"webdock","panel":"webdock"}' >/dev/null
wait_until 5 panel_open || fail "the card did not open"
check_geometry site top
wait_px "$CX" "$CY" '#2b3a55' 15
ok "the page is on screen inside the card ($CX,$CY is the page's colour)"
wait_until 5 doc_is "d['card'].get('pin') == 'site' and 'place' in d['card']" || fail "the daemon's card: $(doc "d.get('card')")"
sleep 0.5
timeout 20 grim -g "$(( PX - 40 )),0 $(( PW + 80 ))x$(( PY + PH + 40 ))" "$SHOTS/card-top.png" && ok "shot mods/webdock/shots/card-top.png"
qml_errors

# ---- 2. close: unmapped, no frames, kept; reopen: no new load ----
L0=$(loads site)
[ "$L0" -ge 1 ] || fail "no load report for the page ($HOSTLOG)"
hid0=$(count 'webdock-debug card hidden' "$HOSTLOG")
K act ui.close >/dev/null
wait_until 5 panel_closed || fail "the card did not close"
wait_until 10 eval '[ "$(count "webdock-debug card hidden" "$HOSTLOG")" -gt '"$hid0"' ]' || fail "the host's card window did not unmap"
wait_until 5 doc_is "'place' not in d['card'] and d['card'].get('pin') == 'site'" || fail "the daemon still places the card ($(doc "d.get('card')"))"
grep -q 'webdock-debug page site frozen' "$HOSTLOG" || fail "the page was not frozen when the card closed"
sleep 1
f0=$(count 'webdock-debug card frame' "$HOSTLOG")
sleep 3
f1=$(count 'webdock-debug card frame' "$HOSTLOG")
[ "$f1" = "$f0" ] || fail "the host's card window drew $(( f1 - f0 )) frames in 3 s after the card closed"
[ "$(doc "'site' in d['keep']")" = True ] || fail "closing destroyed the page: keep = $(doc "d['keep']")"
K act mod.panel.open '{"id":"webdock","panel":"webdock"}' >/dev/null
wait_until 5 panel_open || fail "the card did not open again"
wait_px "$CX" "$CY" '#2b3a55' 15
[ "$(loads site)" = "$L0" ] || fail "reopening reloaded the page ($L0 → $(loads site) loads)"
ok "closing unmaps the card's window (0 frames in 3 s), keeps the page; reopening shows it with no new load"

# ---- 3. the second pin and back: no reload ----
ptr $(( PX + PITCH + 20 )) $(( PY + 20 ))
wait_until 10 doc_is "d['card'].get('pin') == 'other'" || fail "the click on the second pin did not switch ($(doc "d.get('card')"))"
wait_until 30 doc_is "[p for p in d['pins'] if p['id'] == 'other'][0].get('loaded') == True" || fail "the other page never loaded"
wait_px "$CX" "$CY" '#3a2b45' 15
LO=$(loads other)
ptr $(( PX + 20 )) $(( PY + 20 ))
wait_until 10 doc_is "d['card'].get('pin') == 'site'" || fail "the click on the first pin did not switch back"
wait_px "$CX" "$CY" '#2b3a55' 15
ptr $(( PX + PITCH + 20 )) $(( PY + 20 ))
wait_px "$CX" "$CY" '#3a2b45' 15
ptr $(( PX + 20 )) $(( PY + 20 ))
wait_px "$CX" "$CY" '#2b3a55' 15
[ "$(loads site)" = "$L0" ] && [ "$(loads other)" = "$LO" ] || fail "switching pins reloaded a page (site $L0 → $(loads site), other $LO → $(loads other))"
ok "the pin keys switch the card's page and back, with no reload"

# ---- 4. the same pin at the edge: last opened wins (W73, I488 (4)) ----
# The edge card opens on the card's pin after the card: the edge shows the page, the card says where it is with "Show here";
# that key brings it back to the card; closing the card hands it to the edge again. No move reloads the page.
hid0=$(count 'webdock-debug card hidden' "$HOSTLOG")
shown0=$(count 'webdock-debug card shown' "$HOSTLOG")
n0=$(count "webdock-panel notice This page is shown at the screen's edge" "$R/qs.log")
K act webdock.pin '{"on":true}' >/dev/null || fail "webdock.pin refused"   # (the edge card stays while the pointer is away)
K act webdock.open '{"pin":"site"}' >/dev/null
wait_until 5 doc_is "d['mode'] == 'extended' and d.get('shown') == 'site'" || fail "the edge card did not open"
wait_until 5 doc_is "d['card'].get('elsewhere') == 'edge' and 'elsewhere' not in d" \
  || fail "the daemon does not give the page to the edge opened last ($(doc "(d.get('elsewhere'), d['card'].get('elsewhere'))"))"
wait_until 10 eval '[ "$(count "webdock-debug card hidden" "$HOSTLOG")" -gt '"$hid0"' ]' || fail "the card's window kept the page"
wait_until 5 eval '[ "$(count "webdock-panel notice This page is shown at the screen'"'"'s edge" "$R/qs.log")" -gt '"$n0"' ]' \
  || fail "the card does not say its pin is shown at the edge"
wait_px $(( W_OUT - 56 - 206 )) $(( H_OUT / 2 + 120 )) '#2b3a55' 15
ok "the edge opened after the card shows the page; the card says so"
# "Show here" in the card's well (the panel logs where its key is on the output).
wait_until 5 grep -qF 'webdock-panel here ' "$R/qs.log" || fail "the card's notice has no Show here key"
read -r HX HY <<< "$({ grep -F 'webdock-panel here ' "$R/qs.log" || true; } | tail -1 | sed 's/.*webdock-panel here //')"
e0=$(count "webdock-debug edge notice This page is shown in the bar's card" "$HOSTLOG")
mv_to "$HX" "$HY"
ptr "$HX" "$HY"
wait_until 5 doc_is "d.get('elsewhere') == 'card' and 'elsewhere' not in d['card']" || fail "Show here did not bring the page to the card ($(doc "(d.get('elsewhere'), d['card'].get('elsewhere'))"))"
wait_until 10 eval '[ "$(count "webdock-debug card shown" "$HOSTLOG")" -gt '"$shown0"' ]' || fail "the card's window did not take the page back"
wait_px "$CX" "$CY" '#2b3a55' 15
wait_until 5 eval '[ "$(count "webdock-debug edge notice This page is shown in the bar'"'"'s card" "$HOSTLOG")" -gt '"$e0"' ]' \
  || fail "the edge card does not say the page is in the bar's card"
ok "Show here in the card brings the page back; the edge card says it is in the bar's card"
K act ui.close >/dev/null
wait_until 5 panel_closed || fail "the card did not close"
wait_until 5 doc_is "'elsewhere' not in d" || fail "the edge did not get the page back when the card closed"
wait_px $(( W_OUT - 56 - 206 )) $(( H_OUT / 2 + 120 )) '#2b3a55' 15
[ "$(loads site)" = "$L0" ] || fail "moving the page between the card and the edge reloaded it ($L0 → $(loads site))"
K act webdock.hide >/dev/null
K act webdock.pin '{"on":false}' >/dev/null
ok "the same pin at the edge: the place opened last shows the page, Show here moves it, closing hands it on; no reload"
qml_errors

# ---- 4b. the same pin in the sidebar: the card opened after the sidebar takes the page; closed, the sidebar has it ----
K set sidebar.left.sections '["mod:webdock:webdock"]' >/dev/null || fail "sidebar.left.sections with the dock was refused"
K act webdock.sidebar_select '{"pin":"site"}' >/dev/null
K act sidebar.toggle "{\"side\":\"left\",\"output\":\"$OUT\"}" >/dev/null
wait_until 10 doc_is "'place' in d.get('sidebar', {})" || fail "the sidebar never placed the dock's page ($(doc "d.get('sidebar')"))"
wait_until 10 grep -qF 'webdock-debug side shown' "$HOSTLOG" || fail "the host did not show the page in the sidebar"
shown0=$(count 'webdock-debug card shown' "$HOSTLOG")
side0=$(count 'webdock-debug side shown' "$HOSTLOG")
n0=$(count "webdock-panel notice This page is shown in the bar's card" "$R/qs.log")
K act mod.panel.open '{"id":"webdock","panel":"webdock"}' >/dev/null
wait_until 5 panel_open || fail "the card did not open beside the sidebar"
if doc_is "'place' in d.get('sidebar', {})"; then
  wait_until 10 eval '[ "$(count "webdock-debug card shown" "$HOSTLOG")" -gt '"$shown0"' ]' \
    || fail "the card opened after the sidebar did not take the page"
  wait_until 5 doc_is "d['sidebar'].get('elsewhere') == 'card'" || fail "the daemon kept the page in the sidebar ($(doc "d.get('sidebar')"))"
  wait_until 5 eval '[ "$(count "webdock-panel notice This page is shown in the bar'"'"'s card" "$R/qs.log")" -gt '"$n0"' ]' \
    || fail "the sidebar does not say its pin is shown in the bar's card"
  wait_px "$CX" "$CY" '#2b3a55' 15
  K act ui.close >/dev/null
  wait_until 5 panel_closed || fail "the card did not close"
  doc_is "'place' in d.get('sidebar', {})" || fail "closing the card closed the sidebar"
  wait_until 10 eval '[ "$(count "webdock-debug side shown" "$HOSTLOG")" -gt '"$side0"' ]' \
    || fail "the sidebar did not take the page back once the card closed"
  ok "the same pin in the sidebar: the card opened later shows the page, the sidebar says so; closed, the sidebar has it again"
  K act sidebar.toggle '{"side":"left"}' >/dev/null
  wait_until 10 doc_is "'place' not in d.get('sidebar', {})" || fail "the sidebar did not close"
else
  ok "(opening the card closed the sidebar: no both-at-once case to check)"
fi
[ "$(loads site)" = "$L0" ] || fail "the page moved between the sidebar and the card with a reload ($L0 → $(loads site))"
K act ui.close >/dev/null
wait_until 5 panel_closed || true
K act sidebar.close >/dev/null || true
K set sidebar.left.sections '[]' >/dev/null || true
qml_errors

# ---- 5. hover: the pointer from the module into the page keeps the card ----
# Where the module stands: the x whose right click opens its menu (`module:mod:webdock:webdock`), scanning the end zone.
tray_is() { doc_is "d.get('tray', '') == '$1'" runtime.ui; }
MX=""; MY=14
for x in $(seq $(( W_OUT - 8 )) -8 $(( W_OUT - 200 ))); do
  ptr "$x" "$MY" right
  if wait_until 1 tray_is module:mod:webdock:webdock; then MX=$x; K act ui.close >/dev/null; wait_until 3 panel_closed; break; fi
  tray_is "" || { K act ui.close >/dev/null; wait_until 3 tray_is ""; }
done
[ -n "$MX" ] || fail "the dock's module was not found on the bar"
wait_until 3 tray_is "" || fail "the module's menu did not close"
mv_to $(( W_OUT / 3 )) $(( H_OUT / 2 ))
K set bar.hover '"card"' >/dev/null || fail "bar.hover = card was refused"
wait_until 5 eval 'K get bar.hover | grep -q card'
mv_to "$MX" "$MY"
wait_until 5 panel_open || fail "resting on the module opened no card ($(doc "d" runtime.ui))"
wait_until 10 eval '[ "$(card_line site | sed "s/.* place //")" = "$O $X $Y $WW $WH" ]' || true
wait_until 10 grep -qF 'webdock-debug card shown' "$HOSTLOG"
sleep 0.6
mv_to "$MX" $(( PY + 20 ))
mv_to "$CX" "$CY"
wait_until 5 doc_is "d['card'].get('hover') == True" || fail "the host did not report the pointer in its window"
sleep 1.5
panel_open || fail "the card closed while the pointer was on its page"
mv_to $(( PX + 4 )) "$CY"
sleep 1.2
panel_open || fail "the card closed when the pointer went from the page onto the card"
mv_to "$CX" "$CY"
sleep 0.5
mv_to $(( W_OUT / 3 )) $(( H_OUT / 2 ))
wait_until 4 panel_closed || fail "the card stayed after the pointer left the page and the card"
ok "bar.hover = card: the pointer from the module into the page keeps the card; page → card keeps it; leaving closes it"

# ---- 6. a click in the page gives it the keyboard; Esc closes the card ----
K set bar.hover '"preview"' >/dev/null
K act mod.panel.open '{"id":"webdock","panel":"webdock"}' >/dev/null
wait_until 5 panel_open || fail "the card did not open"
wait_px "$CX" "$CY" '#2b3a55' 15
# By keyboard: a click on the first pin's key gives the card the keys; Tab walks the keys and, past the settings key,
# hands the keyboard to the page (`webdock.card_focus`); typed text arrives; Esc closes the card.
ptr $(( PX + 20 )) $(( PY + 20 ))
for _ in 1 2 3 4 5; do
  keys tab
  doc_is "d['card'].get('focus', 0) >= 1" && break
done
wait_until 5 doc_is "d['card'].get('focus', 0) >= 1" || fail "Tab past the card's keys did not ask the keyboard for the page"
wait_until 5 grep -qF 'webdock-debug card keyboard in' "$HOSTLOG" || fail "the page did not take the keyboard it was asked for"
keys k b
wait_until 5 grep -qF 'INPUT kb' "$HOSTLOG" || fail "typing after Tab did not reach the page ($HOSTLOG)"
# I482 (the user, session 28): with the keys in the page the first Esc is the page's and the card stays; the second,
# within a moment, closes the card.
keys escape
wait_until 5 grep -qF 'ESCAPE seen' "$HOSTLOG" || fail "the first Esc did not reach the page ($HOSTLOG)"
sleep 0.4
panel_open || fail "the first Esc in the page closed the card (it is the page's)"
keys escape
wait_until 5 panel_closed || fail "the second Esc in the page did not close the card (keyboard path)"
ok "Tab past the card's keys hands the keyboard to the page; typed text arrives; Esc goes to the page, a second Esc closes the card"
K act mod.panel.open '{"id":"webdock","panel":"webdock"}' >/dev/null
wait_until 5 panel_open || fail "the card did not open"
wait_px "$CX" "$CY" '#2b3a55' 15
read -r _ _ _ _ _ _ GY _ <<< "$(card_line site)"
# the page's text field: under the heading (site.html: an h1, then the input)
mv_to $(( X + 60 )) $(( Y + GY + 100 ))
sleep 0.3
ptr $(( X + 60 )) $(( Y + GY + 100 ))
wait_until 5 doc_is "d['card'].get('engaged') == True" || fail "a click in the page was not reported (engaged)"
keys h i
wait_until 5 grep -qE 'INPUT [a-z]*hi$' "$HOSTLOG" || fail "typing did not reach the page ($HOSTLOG)"
keys escape
sleep 0.4
panel_open || fail "the first Esc after a click in the page closed the card"
keys escape
wait_until 5 panel_closed || fail "the second Esc in the page did not close the card"
ok "a click in the page gives it the keyboard (typed text arrives); Esc twice closes the card"

# ---- 6b. I482 (the user, session 28): a click on the module opens the card, a second click closes it; the edge dock stays ----
mv_to $(( W_OUT / 3 )) $(( H_OUT / 2 ))
ptr "$MX" "$MY"
wait_until 5 panel_open || fail "a click on the module opened no card ($(doc "d" runtime.ui))"
doc_is "d.get('mode', 'hidden') == 'hidden'" || fail "a click on the module opened the dock at the edge ($(doc "d.get('mode')"))"
wait_until 10 grep -qF 'webdock-debug card shown' "$HOSTLOG" || true
ptr "$MX" "$MY"
wait_until 5 panel_closed || fail "a second click on the module did not close the card"
ok "a click on the module opens the card and leaves the edge dock; a second click closes it"
qml_errors

# ---- 7. a bottom bar ----
conf "$bottom_bar"
wait_until 10 eval 'K get edges.bottom.bar | grep -q true' || fail "the bottom bar config was not taken"
sleep 1
n0=$(count 'webdock-panel card ' "$R/qs.log")
K act mod.panel.open '{"id":"webdock","panel":"webdock"}' >/dev/null
wait_until 5 panel_open || fail "the card did not open on a bottom bar"
wait_until 10 eval '[ "$(count "webdock-panel card " "$R/qs.log")" -gt '"$n0"' ]' || fail "the panel did not report on a bottom bar"
check_geometry site bottom
wait_px "$CX" "$CY" '#2b3a55' 15
sleep 0.5
timeout 20 grim -g "$(( PX - 40 )),$(( PY - 40 )) $(( PW + 80 ))x$(( H_OUT - PY + 40 ))" "$SHOTS/card-bottom.png" && ok "shot mods/webdock/shots/card-bottom.png"
K act ui.close >/dev/null
wait_until 5 panel_closed || true
qml_errors

# ---- 8. no pin: the well says how to add one ----
conf "$bottom_bar" ""
wait_until 10 doc_is "d['pins'] == []" || fail "the pins were not emptied"
K act mod.panel.open '{"id":"webdock","panel":"webdock"}' >/dev/null
wait_until 5 panel_open || fail "the card did not open without pins"
wait_until 5 grep -qF 'webdock-panel notice Pin a site' "$R/qs.log" || fail "the empty card does not say how to add a pin"
K act ui.close >/dev/null
ok "no pin: the card's well says how to add one"
qml_errors
echo "test-card: PASS"
