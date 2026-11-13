#!/usr/bin/env bash
# The web dock's page in the bar module's card (W72, docs/ux/webdock.md "In the bar's card"), invisibly (headless sway
# sandbox), with the REAL kurashid, the real shell and the real web host (qs-webengine), two file:// pins, no network (K37),
# motion off (`theme.motion.profile = "none"`: the page appears at rest with a cut):
#   1. a top bar with the dock's module at its end: the card opens (`mod.panel.open`); the panel reports its well on the
#      output and the host maps its card window there: the window's rect is the well's, inside the card, under the pins
#      row; the page fills it under the navigation row and its colour is on screen;
#   1b. W74: the default well is the edge card's box (`width` × twice that) — I504: within the Stage's card limit
#      (`bar.card_max_height`, ½ the screen), so on 2560 × 1440 the well takes the panel's room; one press of the card's
#      size key steps it to phone (the well resizes, no reload); `kurashi undo` brings the default back;
#   2. closing the card unmaps the window (0 frames in 3 s), the page stays loaded; reopening shows it with no new load;
#   3. a click on the second pin's key switches the page; back to the first: no new load of either;
#   4. the same pin at the edge while the card shows it: the card keeps the page (no load); the edge takes it once the card
#      closes (no load);
#   4c. W74: `hover_takes_page = false`: a rest on the screen's edge reveals the dock and an always-open left sidebar keeps
#      the pin's page, the edge card says so and its Show here (pressed on screen) takes it; `true` (the default): a rest
#      takes the page (an open Stage card's click-away window covers the edge zone, so the bar card cannot meet a hover);
#   5. `bar.hover = card`: a rest on the module opens the card; the pointer moved into the page keeps it; leaving closes it;
#   6. Tab past the card's keys hands the keyboard to the page; a click in the page gives it the keyboard (typed text
#      arrives either way); Esc closes the card;
#   6c. W76 (docs/ux/webdock.md "Round three"): "+" in the card → its address field → a local page loads → "Pin": the pin is
#      in `mods.webdock.pins` (profile `browse`), the page renamed, not loaded again; the title is the field (another page,
#      the pin keeps its address); "Keep open at the edge" moves the page to the edge, pinned; the bar card's grip resizes
#      the well (written per output, the card follows);
#   6d. W76: the strip's pin menu — Reload (the counter, a new load), Update pin to this page, Unpin but keep open (the row
#      goes, the page stays), `kurashi undo` brings the pin back;
#   6e. W76: the edge card's grip (drag, Ctrl+arrows, double click) and its keep-open key;
#   7. a bottom bar: the same geometry checks; shots mods/webdock/shots/card-{top,bottom}.png;
#   8. no pin: the well says how to add one; no QML error or warning in the shell or the host.
#   Part "local" alone (W78, docs/ux/webdock.md "Local mode"; `test-card.sh local [sandbox-name]`): the timer and tasks
#   mods on, two sites; the edge strip's switch flips `mods.webdock.content` to local (the strip lists no site); "+" lists
#   the mods' views (timer's panel, tasks' panel, the notes desk card), a press pins and opens one (its panel in the card);
#   "+" again marks it pinned; the switch back lists every pin; `kurashi undo` steps the add back.
#   nix develop -c mods/webdock/test/test-card.sh [local] [sandbox-name]
# Binaries: kurashid and kurashi from $KURASHI_BIN_DIR (default $CARGO_TARGET_DIR/debug or target/debug).
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
PART=all
if [ "${1:-}" = local ]; then PART=local; shift; fi
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
# (part "local": mods with views — the timer's panel, the tasks' panel and its notes desk card)
[ "$PART" = local ] && base=${base/'enabled = ["webdock"]'/'enabled = ["webdock", "timer", "tasks"]'}
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

# ---- local (W78): the strip's switch, the local chooser, a view pin opened in Local mode ----
if [ "$PART" = local ]; then
  # Tiles and controls in the dock's window (right edge, the usable height under the top bar): <x> <y> <win w> <win h>.
  at() { { grep -F "webdock-debug $1 " "$R/qs.log" || true; } | tail -1 | sed "s/.*webdock-debug $1 //"; }
  screen_of() { read -r SX SY SWW SWH <<< "$(at "$1")"; TX=$(( W_OUT - SWW + SX )); TY=$(( H_OUT - SWH + SY )); }
  press() { screen_of "$1"; mv_to "$TX" "$TY"; ptr "$TX" "$TY"; }
  wait_until 5 doc_is "'content' not in d and 'strip' not in d" || fail "online is not the default ($(doc "d.get('content')"))"
  K act webdock.pin '{"on":true}' >/dev/null
  K act webdock.toggle "{\"output\":\"$OUT\"}" >/dev/null
  wait_until 10 eval '[ -n "$(at strip\ ctl:content)" ]' || fail "the strip logged no switch"
  wait_until 5 eval '[ "$(at rows)" = "online site,other" ]' || fail "online: the strip lists $(at rows)"
  press "strip ctl:content"
  wait_until 5 doc_is "d.get('content') == 'local' and d.get('strip') == []" || fail "the switch did not go local ($(doc "(d.get('content'), d.get('strip'))"))"
  K get mods.webdock.content | grep -qF '= "local"' || fail "mods.webdock.content is $(K get mods.webdock.content)"
  wait_until 5 eval '[ "$(at rows)" = "local " ]' || fail "local: the strip lists '$(at rows)'"
  ok "the switch: mods.webdock.content local, the strip lists no site"
  press "strip ctl:add"
  wait_until 5 eval '[ -n "$(at local\ count)" ]' || fail "\"+\" in Local did not open the chooser"
  for t in mod:timer:timer mod:tasks:tasks mod:tasks:notes; do
    wait_until 3 eval '[ -n "$(at "local $t")" ]' || fail "the chooser does not offer $t ($(grep -F 'webdock-debug local' "$R/qs.log" | tail -5 | tr '\n' ' '))"
  done
  [ -z "$(at 'local mod:webdock:webdock')" ] || fail "the chooser offers the dock's own panel"
  [ -z "$(at 'local mod:timer:timer' | grep -v '^- ')" ] || fail "timer is marked pinned before it is"
  ok "\"+\" in Local lists the mods' views: the timer's and tasks' panels, the notes desk card; not the dock's own"
  read -r _ LX LY SWW SWH <<< "$(at 'local mod:timer:timer')"
  mv_to $(( W_OUT - SWW + LX )) $(( H_OUT - SWH + LY )); ptr $(( W_OUT - SWW + LX )) $(( H_OUT - SWH + LY ))
  wait_until 5 doc_is "[p['target'] for p in d['pins'] if p['id'] == 'timer'] == ['mod:timer:timer'] and d.get('strip') == ['timer']" \
    || fail "the timer's view was not pinned ($(doc "(d['pins'], d.get('strip'))"))"
  wait_until 5 doc_is "d['mode'] == 'extended' and d.get('shown') == 'timer'" || fail "the new view pin did not open ($(doc "(d['mode'], d.get('shown'))"))"
  wait_until 5 grep -qF 'webdock-debug view panel:timer true' "$R/qs.log" || fail "the view card did not load the timer's panel"
  wait_until 5 eval '[ "$(at rows)" = "local timer" ]' || fail "local: the strip lists '$(at rows)' after the add"
  ok "a press pins mod:timer:timer and opens it: the card shows the timer's panel in Local mode"
  press "strip ctl:add"
  wait_until 5 eval '[ "$(at "local mod:timer:timer" | cut -d" " -f1)" = timer ]' || fail "\"+\" does not mark the timer pinned ($(at 'local mod:timer:timer'))"
  keys escape
  ok "\"+\" again marks the timer's view pinned"
  press "strip ctl:content"
  wait_until 5 doc_is "'content' not in d and 'strip' not in d" || fail "the switch did not go back online"
  wait_until 5 eval '[ "$(at rows)" = "online site,other,timer" ]' || fail "online: the strip lists '$(at rows)'"
  ok "the switch back: online lists every pin (the sites, then the view)"
  K undo >/dev/null; K undo >/dev/null
  wait_until 5 doc_is "[p['id'] for p in d['pins']] == ['site', 'other'] and d.get('content') == 'local'" \
    || fail "two undo steps did not take back the switch and the add ($(doc "([p['id'] for p in d['pins']], d.get('content'))"))"
  ok "kurashi undo: the switch and the add are one step each"
  qml_errors
  echo "test-card: PASS (local)"
  exit 0
fi

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
# Session 31 (I495): the page's own icon is saved while the card shows it and the pin names it (the strip and the bar draw
# it in place of the letter).
wait_until 10 doc_is "any(p['id'] == 'site' and str(p.get('icon') or '').startswith('file://') for p in d['pins'])" \
  || fail "the page's icon was not saved for its pin ($(doc "[(p['id'], p.get('icon')) for p in d['pins']]"))"
ok "the page's icon is saved and named on its pin"
wait_until 5 doc_is "d['card'].get('pin') == 'site' and 'place' in d['card']" || fail "the daemon's card: $(doc "d.get('card')")"
sleep 0.5
timeout 20 grim -g "$(( PX - 40 )),0 $(( PW + 80 ))x$(( PY + PH + 40 ))" "$SHOTS/card-top.png" && ok "shot mods/webdock/shots/card-top.png"
qml_errors

# ---- 1b. W74: the default size is the edge card's; the size key steps it, one undo step takes it back ----
# The edge card's phone box is `width` (412) × twice that; the well (the row and the page) takes it — I504: within the
# Stage's limit (½ the screen's height: 720 on 1440), the panel asking for no more than the card holds (Panel.stageRoom).
[ "$WW" = 412 ] || fail "the default card's well is ${WW} wide, not the edge card's 412"
{ [ "$WH" = 824 ] || { [ "$WH" -lt 824 ] && [ "$PH" -le $(( H_OUT / 2 )) ]; }; } \
  || fail "the default card's well is ${WW}x$WH (panel ${PW}x$PH): neither the edge card's 412x824 nor the Stage's limit"
ROOM=$WH                                 # the well's height when the limit holds it (824 when it does not)
PHONE_H=$(( ROOM < 796 ? ROOM : 796 ))
doc_is "'card_size' not in d" || fail "the default size is published: $(doc "d.get('card_size')")"
ok "the default card's well is the edge card's box within the Stage's limit (${WW}x$WH), card_size absent"
wait_until 5 grep -qF 'webdock-panel sizekey ' "$R/qs.log" || fail "the card has no size key"
read -r SX SY SNAME _ <<< "$({ grep -F 'webdock-panel sizekey ' "$R/qs.log" || true; } | tail -1 | sed 's/.*webdock-panel sizekey //')"
[ "$SNAME" = dock ] || fail "the size key names $SNAME, not dock"
L1=$(loads site)
mv_to "$SX" "$SY"
ptr "$SX" "$SY"
wait_until 5 doc_is "d.get('card_size') == 'phone'" || fail "a press of the size key did not step to phone ($(doc "d.get('card_size')"))"
# (the phone's well is 412 × 796; the limit may hold it as it held the default)
if [ "$PHONE_H" != "$ROOM" ]; then
  wait_until 10 eval '[ "$(panel_card | cut -d" " -f4,5)" = "412 '"$PHONE_H"'" ]' || fail "the well did not take the phone size ($(panel_card))"
fi
check_geometry site top
[ "$WW" = 412 ] && [ "$WH" = "$PHONE_H" ] || fail "the phone card's well is ${WW}x$WH, not 412x$PHONE_H"
wait_px "$CX" "$CY" '#2b3a55' 15
[ "$(loads site)" = "$L1" ] || fail "the size change reloaded the page ($L1 → $(loads site))"
ok "one press of the size key: card_size phone, the well 412x$PHONE_H, the page moved with it, no reload"
timeout 10 "$W/kurashi" undo >/dev/null || fail "kurashi undo was refused"
wait_until 5 doc_is "'card_size' not in d" || fail "one undo did not bring the default size back ($(doc "d.get('card_size')"))"
wait_until 10 eval '[ "$(panel_card | cut -d" " -f4,5)" = "412 '"$ROOM"'" ]' || fail "the well did not go back to 412x$ROOM ($(panel_card))"
check_geometry site top
wait_px "$CX" "$CY" '#2b3a55' 15
ok "one undo takes the size key's write back (the well 412x$ROOM again)"
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
# B117 (session 29, the lead's 73a3bce2): the edge dock coming out closes an open card, as a click elsewhere does. So the
# edge opened while the card shows the page takes it and the card closes; the card opened again (the place opened last)
# takes it back and the edge card says where it is; its "Show here" brings it to the edge, the card's "Show here" back to
# the card; closing the card hands it to the edge. No move reloads the page.
hid0=$(count 'webdock-debug card hidden' "$HOSTLOG")
K act webdock.pin '{"on":true}' >/dev/null || fail "webdock.pin refused"   # (the edge card stays while the pointer is away)
K act webdock.open '{"pin":"site"}' >/dev/null
wait_until 5 doc_is "d['mode'] == 'extended' and d.get('shown') == 'site'" || fail "the edge card did not open"
wait_until 5 panel_closed || fail "the edge dock coming out did not close the bar card (B117)"
wait_until 5 doc_is "'elsewhere' not in d" || fail "the edge does not show the page ($(doc "d.get('elsewhere')"))"
wait_until 10 eval '[ "$(count "webdock-debug card hidden" "$HOSTLOG")" -gt '"$hid0"' ]' || fail "the card's window kept the page"
wait_px $(( W_OUT - 56 - 206 )) $(( H_OUT * 2 / 3 + 40 )) '#2b3a55' 15
ok "the edge opened while the card shows the page: the card closes (B117), the edge shows the page"
shown0=$(count 'webdock-debug card shown' "$HOSTLOG")
e0=$(count "webdock-debug edge notice This page is shown in the bar's card" "$HOSTLOG")
here0=$(count 'webdock-debug edge here ' "$HOSTLOG")
K act mod.panel.open '{"id":"webdock","panel":"webdock"}' >/dev/null
wait_until 5 panel_open || fail "the card did not open beside the edge"
wait_until 5 doc_is "d.get('elsewhere') == 'card' and 'elsewhere' not in d['card']" \
  || fail "the card opened last did not take the page ($(doc "(d.get('elsewhere'), d['card'].get('elsewhere'))"))"
wait_until 10 eval '[ "$(count "webdock-debug card shown" "$HOSTLOG")" -gt '"$shown0"' ]' || fail "the card's window did not take the page"
wait_px "$CX" "$CY" '#2b3a55' 15
wait_until 5 eval '[ "$(count "webdock-debug edge notice This page is shown in the bar'"'"'s card" "$HOSTLOG")" -gt '"$e0"' ]' \
  || fail "the edge card does not say the page is in the bar's card"
ok "the card opened after the edge takes the page; the edge card says it is in the bar's card"
# The edge card's "Show here" (its middle in the window; the window ends at the strip, under the top bar).
wait_until 5 eval '[ "$(count "webdock-debug edge here " "$HOSTLOG")" -gt '"$here0"' ]' || fail "the edge card logged no Show here key"
read -r EHX EHY EAW EAH <<< "$({ grep -F 'webdock-debug edge here ' "$HOSTLOG" || true; } | tail -1 | sed 's/.*webdock-debug edge here //')"
n0=$(count "webdock-panel notice This page is shown at the screen's edge" "$R/qs.log")
K act webdock.open '{"pin":"site"}' >/dev/null      # (Show here at the edge is `webdock.open`; the click-away layer covers it)
wait_until 5 doc_is "d['card'].get('elsewhere') == 'edge' and 'elsewhere' not in d" \
  || fail "Show here at the edge did not take the page ($(doc "(d.get('elsewhere'), d['card'].get('elsewhere'))"))"
wait_until 5 eval '[ "$(count "webdock-panel notice This page is shown at the screen'"'"'s edge" "$R/qs.log")" -gt '"$n0"' ]' \
  || fail "the card does not say its pin is shown at the edge"
wait_until 5 grep -qF 'webdock-panel here ' "$R/qs.log" || fail "the card's notice has no Show here key"
read -r HX HY <<< "$({ grep -F 'webdock-panel here ' "$R/qs.log" || true; } | tail -1 | sed 's/.*webdock-panel here //')"
shown0=$(count 'webdock-debug card shown' "$HOSTLOG")
mv_to "$HX" "$HY"
ptr "$HX" "$HY"
wait_until 5 doc_is "d.get('elsewhere') == 'card' and 'elsewhere' not in d['card']" || fail "Show here did not bring the page to the card ($(doc "(d.get('elsewhere'), d['card'].get('elsewhere'))"))"
wait_until 10 eval '[ "$(count "webdock-debug card shown" "$HOSTLOG")" -gt '"$shown0"' ]' || fail "the card's window did not take the page back"
wait_px "$CX" "$CY" '#2b3a55' 15
ok "Show here at the edge takes the page; the card says so, and its Show here brings it back"
K act ui.close >/dev/null
wait_until 5 panel_closed || fail "the card did not close"
wait_until 5 doc_is "'elsewhere' not in d" || fail "the edge did not get the page back when the card closed"
wait_px $(( W_OUT - 56 - 206 )) $(( H_OUT * 2 / 3 + 40 )) '#2b3a55' 15
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

# ---- 4c. W74: a hover reveal of the edge and a page another place shows (`hover_takes_page`) ----
# While a Stage card is open the click-away window covers the usable area, edge zone included, so the pointer cannot
# reveal the dock over an open bar card; the place a hover reveal meets on screen is a sidebar that stays open
# (`visibility = always`, no catcher). B (off): a rest on the right edge while the left sidebar shows the pin reveals the
# dock, the sidebar keeps the page and the edge card says where it is; its Show here, pressed on screen, takes it. A (on,
# the default): a rest takes the page. (The edge dock's `shown` is `site` from step 4; `reopen_last` reopens its card.)
EDGE_Y=$(( H_OUT * 2 / 3 ))
K set sidebar.left.sections '["mod:webdock:webdock"]' >/dev/null || fail "sidebar.left.sections with the dock was refused"
K act webdock.sidebar_select '{"pin":"site"}' >/dev/null
K set sidebar.left.visibility '"always"' >/dev/null || fail "sidebar.left.visibility = always was refused"
wait_until 15 doc_is "'place' in d.get('sidebar', {}) and d['sidebar'].get('pin') == 'site' and 'elsewhere' not in d['sidebar']" \
  || fail "the always-open sidebar never placed the dock's page ($(doc "d.get('sidebar')"))"
wait_until 10 grep -qF 'webdock-debug side shown' "$HOSTLOG" || fail "the host did not show the page in the sidebar"
K set mods.webdock.hover_takes_page false >/dev/null || fail "mods.webdock.hover_takes_page = false was refused"
wait_until 5 eval 'K get mods.webdock.hover_takes_page | grep -q false' || fail "hover_takes_page = false was not taken"
sh0=$(count 'webdock-debug side hidden' "$HOSTLOG")
e0=$(count "webdock-debug edge notice This page is shown in the sidebar" "$HOSTLOG")
here0=$(count 'webdock-debug edge here ' "$HOSTLOG")
mv_to $(( W_OUT / 2 )) $(( H_OUT / 2 ))
mv_to $(( W_OUT - 1 )) "$EDGE_Y"
wait_until 5 doc_is "d['mode'] == 'extended' and d.get('shown') == 'site'" || fail "a rest on the edge did not reveal the dock ($(doc "(d['mode'], d.get('shown'))"))"
wait_until 5 doc_is "d.get('elsewhere') == 'sidebar' and 'elsewhere' not in d['sidebar']" \
  || fail "hover_takes_page off: the hover reveal took the page ($(doc "(d.get('elsewhere'), d['sidebar'].get('elsewhere'))"))"
wait_until 10 eval '[ "$(count "webdock-debug edge notice This page is shown in the sidebar" "$HOSTLOG")" -gt '"$e0"' ]' \
  || fail "the hover-revealed edge card does not say the page is in the sidebar"
sleep 1
[ "$(count 'webdock-debug side hidden' "$HOSTLOG")" = "$sh0" ] || fail "the sidebar's window lost the page to a hover reveal"
ok "hover_takes_page off: a hover reveal leaves the page in the sidebar; the edge card says where it is"
# Its "Show here" on screen: the host logs the key's middle in its window (right edge: the window ends at the strip, its
# height is the usable area under the top bar).
wait_until 5 eval '[ "$(count "webdock-debug edge here " "$HOSTLOG")" -gt '"$here0"' ]' || fail "the edge card logged no Show here key"
read -r EHX EHY EAW EAH <<< "$({ grep -F 'webdock-debug edge here ' "$HOSTLOG" || true; } | tail -1 | sed 's/.*webdock-debug edge here //')"
HX=$(( W_OUT - 56 - EAW + EHX )); HY=$(( H_OUT - EAH + EHY ))
mv_to "$HX" "$HY"
ptr "$HX" "$HY"
wait_until 5 doc_is "'elsewhere' not in d and d['sidebar'].get('elsewhere') == 'edge'" \
  || fail "Show here at $HX,$HY on the hover-revealed edge did not take the page ($(doc "(d.get('elsewhere'), d['sidebar'].get('elsewhere'))"))"
wait_until 10 eval '[ "$(count "webdock-debug side hidden" "$HOSTLOG")" -gt '"$sh0"' ]' || fail "the sidebar's window kept the page"
wait_px $(( W_OUT - 56 - 206 )) $(( H_OUT * 2 / 3 + 40 )) '#2b3a55' 15
ok "Show here pressed on the hover-revealed edge card takes the page"
K act webdock.hide >/dev/null
wait_until 5 doc_is "d['mode'] == 'hidden' and 'elsewhere' not in d['sidebar']" || fail "the hidden edge did not hand the page back to the sidebar"
# A (on): a rest takes it.
K set mods.webdock.hover_takes_page true >/dev/null || fail "mods.webdock.hover_takes_page = true was refused"
wait_until 5 eval 'K get mods.webdock.hover_takes_page | grep -q true' || fail "hover_takes_page = true was not taken"
sh0=$(count 'webdock-debug side hidden' "$HOSTLOG")
mv_to $(( W_OUT / 2 )) $(( H_OUT / 2 ))
mv_to $(( W_OUT - 1 )) "$EDGE_Y"
wait_until 5 doc_is "d['mode'] == 'extended'" || fail "a rest on the edge did not reveal the dock again"
wait_until 5 doc_is "d['sidebar'].get('elsewhere') == 'edge' and 'elsewhere' not in d" \
  || fail "hover_takes_page on: the hover reveal did not take the page ($(doc "(d.get('elsewhere'), d['sidebar'].get('elsewhere'))"))"
wait_until 10 eval '[ "$(count "webdock-debug side hidden" "$HOSTLOG")" -gt '"$sh0"' ]' || fail "the sidebar's window kept the page"
ok "hover_takes_page on (the default): a hover reveal takes the page from the sidebar"
K act webdock.hide >/dev/null
mv_to $(( W_OUT / 2 )) $(( H_OUT / 2 ))
wait_until 5 doc_is "d['mode'] == 'hidden' and 'elsewhere' not in d['sidebar']" || fail "the sidebar did not get the page back"
[ "$(loads site)" = "$L0" ] || fail "a hover reveal moved the page with a reload ($L0 → $(loads site))"
K reset mods.webdock.hover_takes_page >/dev/null || true
K set sidebar.left.visibility '"hidden"' >/dev/null || true
wait_until 10 doc_is "'place' not in d.get('sidebar', {})" || fail "the sidebar did not close"
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
for _ in 1 2 3 4 5 6 7 8; do   # (the pins, +, keep, size, settings: session 31 added the keep key)
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

# ---- 6c. W76: "+" → the address field → a page → Pin; the title field; keep open at the edge; the bar card's grip ----
cp "$ROOT/mods/webdock/test/pages/other.html" "$R/o.html"
cp "$ROOT/mods/webdock/test/pages/site.html" "$R/s.html"
type_text() { keys $(python3 -I "$ROOT/mods/webdock/test/keytokens.py" "$1") "${@:2}"; }
# The card's keys on the output, from the host's log: title <x> <y> pin <x> <y> keep <x> <y> (pin "- -" while hidden).
card_keys() { { grep -F "webdock-debug card keys $1 " "$HOSTLOG" 2>/dev/null || true; } | tail -1 | sed "s/.*webdock-debug card keys $1 //"; }
pin_of() { doc "[p for p in d['pins'] if p['id'] == '$1'][0].get('$2')"; }
mv_to $(( W_OUT / 3 )) $(( H_OUT / 2 ))
n0=$(count 'webdock-panel addkey ' "$R/qs.log")
K act mod.panel.open '{"id":"webdock","panel":"webdock"}' >/dev/null
wait_until 5 panel_open || fail "the card did not open"
wait_px "$CX" "$CY" '#2b3a55' 15
wait_until 5 eval '[ "$(count "webdock-panel addkey " "$R/qs.log")" -gt '"$n0"' ]' || fail "the card logged no + key"
read -r AX AY <<< "$({ grep -F 'webdock-panel addkey ' "$R/qs.log" || true; } | tail -1 | sed 's/.*webdock-panel addkey //')"
mv_to "$AX" "$AY"
ptr "$AX" "$AY"
wait_until 5 doc_is "d['card'].get('pin', '').startswith('browse-')" || fail "+ did not open a temporary page in the card ($(doc "d.get('card')"))"
TMP=$(doc "d['card']['pin']")
[ "$(pin_of "$TMP" temporary)" = True ] && [ "$(pin_of "$TMP" target)" = "" ] || fail "the + page is not an empty temporary page"
wait_until 10 grep -qF "webdock-debug field $TMP open" "$HOSTLOG" || fail "the + page's address field did not open"
sleep 0.5
type_text "$R/o.html" return
wait_until 10 doc_is "[p for p in d['pins'] if p['id'] == '$TMP'][0].get('target') == 'file://$R/o.html'" \
  || fail "the typed path did not become the page's address ($(pin_of "$TMP" target))"
wait_until 20 doc_is "[p for p in d['pins'] if p['id'] == '$TMP'][0].get('loaded') == True" || fail "the + page never loaded"
wait_px "$CX" "$CY" '#3a2b45' 15
ok "+ in the card: a temporary page, its address field open and focused; a typed path loads"
LT=$(loads "$TMP")
wait_until 10 eval '[ "$(card_keys "$TMP" | awk "{print \$5}")" != "-" ] && [ -n "$(card_keys "$TMP")" ]' || fail "the card logged no Pin key ($(card_keys "$TMP"))"
read -r _ TX TY _ PKX PKY _ KX KY <<< "$(card_keys "$TMP")"
mv_to "$PKX" "$PKY"
ptr "$PKX" "$PKY"
wait_until 10 doc_is "d['card'].get('pin') == 'o' and 'o' in [p['id'] for p in d['pins']]" || fail "Pin did not make the page a pin ($(doc "d.get('card')"))"
K get mods.webdock.pins | grep -qF "file://$R/o.html" || fail "the new pin is not in mods.webdock.pins ($(K get mods.webdock.pins))"
[ "$(pin_of o profile)" = browse ] && [ "$(pin_of o was)" = "$TMP" ] || fail "the new pin is not the + page's ($(pin_of o profile), was $(pin_of o was))"
doc_is "'$TMP' not in [p['id'] for p in d['pins']]" || fail "the temporary page is still served"
wait_until 10 grep -qF "webdock-debug rename $TMP o" "$HOSTLOG" || fail "the host did not rename the page"
sleep 1
[ "$(loads o)" = 0 ] && [ "$(loads "$TMP")" = "$LT" ] || fail "Pin loaded the page again (o $(loads o), $TMP $LT → $(loads "$TMP"))"
wait_px "$CX" "$CY" '#3a2b45' 15
ok "Pin: the page is the pin o (in mods.webdock.pins, profile browse), renamed in the host, not loaded again"
# The title is the field: another address in the same page; the pin keeps its own.
wait_until 10 eval '[ -n "$(card_keys o)" ]' || fail "the card logged no keys for o"
read -r _ TX TY _ _ _ _ KX KY <<< "$(card_keys o)"
mv_to "$TX" "$TY"
ptr "$TX" "$TY"
wait_until 5 grep -qF "webdock-debug field o edit" "$HOSTLOG" || fail "a click on the title did not open the field"
type_text "$R/s.html" return
wait_px "$CX" "$CY" '#2b3a55' 15
wait_until 5 doc_is "[p for p in d['pins'] if p['id'] == 'o'][0].get('at') == 'file://$R/s.html'" || fail "the page's address was not reported ($(pin_of o at))"
[ "$(pin_of o target)" = "file://$R/o.html" ] || fail "going elsewhere moved the pin ($(pin_of o target))"
ok "a click on the title opens the field: another page in the same view, the pin stays at its address (at = s.html)"
# The bar card's grip (W76): the edge away from a top bar is the well's foot; up by 60 → the box per output, the card follows.
check_geometry o top
read -r O X Y WW WH _ <<< "$(panel_card)"
LR=$(loads o)
GX=$(( X + WW / 2 )); GY=$(( Y + WH - 3 ))
mv_to "$GX" "$GY"
echo "draw $GX,$GY $GX,$(( GY - 20 )) $GX,$(( GY - 40 )) $GX,$(( GY - 60 ))" >&9; sleep 1
wait_until 10 doc_is "d.get('sizes', {}).get('$OUT') == {'width': $WW, 'height': $(( WH - 60 ))}" \
  || fail "the grip did not write the box ($(doc "d.get('sizes')"))"
wait_until 10 eval '[ "$(panel_card | cut -d" " -f4,5)" = "'"$WW $(( WH - 60 ))"'" ]' || fail "the card did not follow the box ($(panel_card))"
[ "$(loads o)" = "$LR" ] || fail "the resize reloaded the page ($LR → $(loads o))"
ok "the bar card's grip: up 60 px writes sizes[$OUT] = ${WW}x$(( WH - 60 )) and the well follows, no reload"
K act webdock.resize "{\"output\":\"$OUT\"}" >/dev/null || fail "webdock.resize (reset) refused"
wait_until 10 doc_is "'sizes' not in d" || fail "the reset kept the box"
# The side grip (the card stands at the screen's right: its left edge) 40 px left: only the width is written — the height
# stays the box's (twice `width`: 824), not the well's height the Stage's limit holds it to (W76).
wait_until 10 eval '[ "$(panel_card | cut -d" " -f4,5)" = "412 '"$ROOM"'" ]' || fail "the well did not go back to 412x$ROOM after the reset ($(panel_card))"
check_geometry o top
read -r O X Y WW WH _ <<< "$(panel_card)"
GX=$(( X + 3 )); GY=$(( Y + WH / 2 ))
mv_to "$GX" "$GY"
echo "draw $GX,$GY $(( GX - 20 )),$GY $(( GX - 40 )),$GY" >&9; sleep 1
# (the width only roughly: the window moves left as it grows and sway configures it a little later, so the pointer's
# offset is read against a place one step behind — the page follows, not to the pixel; the height is the point here)
wait_until 10 doc_is "d.get('sizes', {}).get('$OUT', {}).get('height') == 824 and d['sizes']['$OUT']['width'] > $(( WW + 20 ))" \
  || fail "the side grip did not write the width alone ($(doc "d.get('sizes')"), well ${WW}x$WH)"
ok "the bar card's side grip: wider writes the width alone ($(doc "d['sizes']['$OUT']"); height 824 kept, the well ${WW}x$WH)"
K act webdock.resize "{\"output\":\"$OUT\"}" >/dev/null || fail "webdock.resize (reset) refused"
wait_until 10 doc_is "'sizes' not in d" || fail "the reset kept the box"
# Session 31 (the user: the pin keeps the bar's card open while other content has the focus): kept (`ui.keep`), a click
# on the desk passes through and the card stays; let go, the next click elsewhere closes it.
K act ui.keep '{"on":true}' >/dev/null || fail "ui.keep refused"
wait_until 5 doc_is "d.get('kept') == d.get('panel') and d.get('panel', '') != ''" runtime.ui \
  || fail "ui.keep did not keep the open card ($(doc "(d.get('panel'), d.get('kept'))" runtime.ui))"
ptr $(( W_OUT / 4 )) $(( H_OUT / 2 ))
sleep 1
panel_closed && fail "a click elsewhere closed the kept card"
K act ui.keep '{"on":false}' >/dev/null || fail "ui.keep off refused"
wait_until 5 doc_is "'kept' not in d" runtime.ui || fail "ui.keep off left the card kept"
ptr $(( W_OUT / 4 )) $(( H_OUT / 2 ))
wait_until 5 panel_closed || fail "let go, a click elsewhere did not close the card"
ok "a kept bar card stays through a click elsewhere; let go, a click elsewhere closes it"
# (the steps below use the strip at the edge, as "Keep open at the edge" left it before session 31)
K act webdock.open '{"pin":"o"}' >/dev/null || fail "webdock.open refused"
K act webdock.pin '{"on":true}' >/dev/null || fail "webdock.pin refused"
wait_until 5 doc_is "d['mode'] == 'extended' and d.get('shown') == 'o' and d['pinned'] == True" \
  || fail "the edge did not open pinned on o ($(doc "(d['mode'], d.get('shown'), d['pinned'])"))"
qml_errors

# ---- 6d. W76: the pin's menu on the strip: Reload, Update pin to this page, Unpin but keep open ----
# Tiles in the dock's window (right edge, the usable height under the top bar): <id> <x> <y> <win w> <win h>.
strip_at() { { grep -F "webdock-debug strip $1 " "$R/qs.log" || true; } | tail -1 | sed "s/.*webdock-debug strip $1 //"; }
wait_until 10 eval '[ -n "$(strip_at o)" ]' || fail "the strip logged no tile for o"
read -r SX SY SWW SWH <<< "$(strip_at o)"
TX=$(( W_OUT - SWW + SX )); TY=$(( H_OUT - SWH + SY ))
menu() { mv_to "$TX" "$TY"; ptr "$TX" "$TY" right; sleep 0.6; }
r0=$(loads o)
menu
keys tab tab return                              # Move up has the keyboard (Move down is off for the last pin); Remove; Reload
wait_until 5 doc_is "[p for p in d['pins'] if p['id'] == 'o'][0].get('reload') == 1" || fail "Reload in the menu did not ask the page ($(pin_of o reload))"
K act webdock.open '{"pin":"o"}' >/dev/null
wait_until 20 eval '[ "$(loads o)" -gt '"$r0"' ]' || fail "the page did not reload ($r0 → $(loads o))"
ok "the menu's Reload reloads the pin's page"
wait_until 5 doc_is "[p for p in d['pins'] if p['id'] == 'o'][0].get('at') == 'file://$R/s.html'" || fail "the page's address went ($(pin_of o at))"
menu
keys tab tab tab return                          # … Reload, Update pin to this page (live: the page is not at home)
wait_until 5 eval 'K get mods.webdock.pins | grep -qF "file://$R/s.html"' || fail "Update pin to this page did not move the pin ($(K get mods.webdock.pins))"
wait_until 5 doc_is "[p for p in d['pins'] if p['id'] == 'o'][0].get('target') == 'file://$R/s.html' and 'at' not in [p for p in d['pins'] if p['id'] == 'o'][0]" \
  || fail "the pin's address is not the page's ($(pin_of o target), at $(pin_of o at))"
ok "the menu's Update pin to this page: the pin's address is where its page is"
menu
keys tab tab tab return                          # … Reload, Unpin but keep open (Update is inert now: the page is at home)
wait_until 5 eval '! K get mods.webdock.pins | grep -qF "\"o\""' || fail "Unpin but keep open kept the row ($(K get mods.webdock.pins))"
wait_until 5 doc_is "[p for p in d['pins'] if p['id'] == 'o'][0].get('temporary') == True and [p for p in d['pins'] if p['id'] == 'o'][0].get('loaded') == True" \
  || fail "the unpinned page was not kept open ($(doc "[p for p in d['pins'] if p['id'] == 'o']"))"
sleep 1
U=$(timeout 10 "$W/kurashi" undo) || fail "kurashi undo was refused"
echo "test-card: undo: $U"
wait_until 10 doc_is "'temporary' not in [p for p in d['pins'] if p['id'] == 'o'][0]" \
  || fail "undo did not bring the pin back ($(doc "[(p['id'], p.get('temporary')) for p in d['pins']]"); rows $(K get mods.webdock.pins | head -1 | sed "s/^[^=]*= //; s/ (.*\$//" | python3 -c "import sys,json; print([r[\"id\"] for r in json.load(sys.stdin)])"))"
ok "the menu's Unpin but keep open: the row goes, the page stays; undo brings the pin back with its page"
qml_errors

# ---- 6e. W76: the edge card's grip and its keep-open key ----
K act webdock.open '{"pin":"site"}' >/dev/null
wait_until 10 grep -qF "webdock-debug grips $OUT " "$HOSTLOG" || fail "the edge card logged no grips"
sleep 0.6
read -r EX EY EW EH AW AH <<< "$({ grep -F "webdock-debug grips $OUT " "$HOSTLOG" || true; } | tail -1 | sed "s/.*webdock-debug grips $OUT //")"
WX=$(( W_OUT - 56 - AW )); WY=$(( H_OUT - AH ))   # the card's window: right edge, the usable height
GX=$(( WX + EX )); GY=$(( WY + EY + EH / 2 ))
mv_to "$GX" "$GY"
echo "draw $GX,$GY $(( GX - 20 )),$GY $(( GX - 40 )),$GY $(( GX - 60 )),$GY" >&9; sleep 1
wait_until 10 doc_is "d.get('sizes', {}).get('$OUT') == {'width': $(( EW + 60 )), 'height': $EH}" \
  || fail "the edge grip did not write the box ($(doc "d.get('sizes')"), card ${EW}x$EH)"
ok "the edge card's grip: 60 px wider writes sizes[$OUT] = $(( EW + 60 ))x$EH"
keys ctrl+l ctrl+left ctrl+left
wait_until 5 doc_is "d.get('sizes', {}).get('$OUT', {}).get('width') == $(( EW + 80 ))" || fail "Ctrl+Left twice did not widen the card by 20 ($(doc "d.get('sizes')"))"
ok "Ctrl+Left on the card's chrome: 10 px a press, written once"
sleep 0.6
read -r EX EY EW2 EH2 AW AH <<< "$({ grep -F "webdock-debug grips $OUT " "$HOSTLOG" || true; } | tail -1 | sed "s/.*webdock-debug grips $OUT //")"
WX=$(( W_OUT - 56 - AW )); GX=$(( WX + EX ))
mv_to "$GX" "$GY"
echo "click $GX $GY left" >&9; echo "click $GX $GY left" >&9; sleep 1
if wait_until 5 doc_is "'sizes' not in d"; then ok "a double click on the grip resets the box"
else K act webdock.resize "{\"output\":\"$OUT\"}" >/dev/null; ok "(the double click was not seen as one here; reset by the action)"; fi
wait_until 10 grep -qF 'webdock-debug keep ' "$HOSTLOG" || fail "the edge card logged no keep key"
read -r KX KY KW KH KS <<< "$({ grep -F 'webdock-debug keep ' "$HOSTLOG" || true; } | tail -1 | sed 's/.*webdock-debug keep //')"
[ "$KS" = on ] || fail "the keep key is not lit while pinned ($KS)"
mv_to $(( W_OUT - 56 - KW + KX )) $(( H_OUT - KH + KY ))
ptr $(( W_OUT - 56 - KW + KX )) $(( H_OUT - KH + KY ))
wait_until 5 doc_is "d['pinned'] == False" || fail "the edge card's keep key did not unpin the dock"
wait_until 5 eval '{ grep -F "webdock-debug keep " "$HOSTLOG" || true; } | tail -1 | grep -q " off$"' || fail "the keep key stayed lit"
ok "the edge card's keep key: lit while pinned; a press lets the dock hide"
K act webdock.hide >/dev/null
mv_to $(( W_OUT / 3 )) $(( H_OUT / 2 ))
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
