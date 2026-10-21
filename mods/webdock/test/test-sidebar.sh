#!/usr/bin/env bash
# The web dock as a left-sidebar tab (W30, docs/ux/webdock.md "In the sidebar"), invisibly (headless sway sandbox), with
# the REAL kurashid, the real shell and the real web host (qs-webengine), two file:// pins, no network (K37):
#   1. the mod on, `sidebar.left = ["mod:webdock:webdock"]` accepted (the tab is offered); `sidebar.toggle {side: left}`
#      opens the sidebar on the dock's tab (sidebar-tab …=ok); the panel reports where its page area rests and the host
#      maps its sidebar window there: the window is that area, the page fills it under the navigation row, the area spans
#      the pane's width and reaches the pane's bottom (the full height on offer), and the page's own colour is on screen;
#   2. a click on the second pin's key switches the page (the daemon's sidebar pin, the host's window, the colour);
#   3. closing the sidebar unmaps the host's window (no frame afterwards), the page is frozen and stays loaded (kept);
#   4. shots mods/webdock/shots/sidebar-washi.png and sidebar-sekai.png;
#   5. the dock as a right-sidebar section (`sidebar.right`): the page is placed from the right edge, on screen.
#   nix develop -c mods/webdock/test/test-sidebar.sh [sandbox-name]
# Binaries: kurashid and kurashi from $KURASHI_BIN_DIR (default $CARGO_TARGET_DIR/debug or target/debug); build them with
# `cargo build --workspace --features kurashid/test-mods` first (a plain `cargo test` replaces that kurashid).
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
NAME=${1:-w30-webdock-sb-$$}
BIN=${KURASHI_BIN_DIR:-${CARGO_TARGET_DIR:-$ROOT/target}/debug}
SHOTS=$ROOT/mods/webdock/shots
PAGES=file://$ROOT/mods/webdock/test/pages
mkdir -p "$SHOTS"
fail() { echo "test-sidebar: FAIL: $*" >&2; exit 1; }
ok() { echo "test-sidebar: ok: $*"; }
command -v qs-webengine >/dev/null || fail "qs-webengine not on PATH (nix develop)"

eval "$("$ROOT/tools/bench/sandbox.sh" start "$NAME")"
R=$XDG_RUNTIME_DIR
W=$R/work
mkdir -p "$W" "$R/kurashi"
cp "$BIN/kurashid" "$BIN/kurashi" "$W/"
pids=()
PTR_PID=""
cleanup() {
  if [ -n "$PTR_PID" ]; then exec 7>&- || true; wait "$PTR_PID" 2>/dev/null || true; fi
  for p in "${pids[@]}"; do kill "$p" 2>/dev/null || true; done
  for p in "${pids[@]}"; do wait "$p" 2>/dev/null || true; done
  "$ROOT/tools/bench/sandbox.sh" stop "$NAME" >/dev/null || true
}
trap cleanup EXIT

export XDG_CONFIG_HOME=$R/xdg/config XDG_STATE_HOME=$R/xdg/state \
       XDG_DATA_HOME=$R/xdg/data XDG_CACHE_HOME=$R/xdg/cache KURASHI_DATA_DIR=$ROOT LC_ALL=C.UTF-8 \
       KURASHI_WEBDOCK_DEBUG=1
mkdir -p "$XDG_CONFIG_HOME/kurashi" "$XDG_STATE_HOME" "$XDG_DATA_HOME" "$XDG_CACHE_HOME"
printf 'theme.style = "washi"\n' > "$XDG_CONFIG_HOME/kurashi/config.toml"
HOSTLOG=$XDG_STATE_HOME/kurashi/webdock/host-web.log
K() { timeout 10 "$W/kurashi" "$@"; }
BG='#8fb8c8'
swaymsg output '*' bg "$BG" solid_color >/dev/null 2>&1 || true
SW=$(swaymsg -t get_outputs -r | jq -r '.[] | select(.name == "HEADLESS-1") | .rect.width')
SH=$(swaymsg -t get_outputs -r | jq -r '.[] | select(.name == "HEADLESS-1") | .rect.height')

# One field of mod.webdock: doc <python expression over d>.
doc() { K --json sub mod.webdock --count 0 | python3 -c "import json,sys; d=json.loads(sys.stdin.readline()); d=d.get('data', d); print($1)"; }
wait_doc() {  # wait_doc <expression that prints True> <seconds>
  local i
  for i in $(seq $(($2 * 4))); do [ "$(doc "$1" 2>/dev/null)" = True ] && return 0; sleep 0.25; done
  return 1
}
# The colour of one pixel of the screen as "r g b" (P6 PPM from grim).
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
px_is() { timeout 20 grim -g "$1,$2 1x1" -t ppm "$W/px.ppm"; python3 -I "$W/px.py" "$W/px.ppm" "$3"; }
wait_px() {  # wait_px <x> <y> <#rrggbb> <seconds>
  local i v
  for i in $(seq $(($4 * 2))); do v=$(px_is "$1" "$2" "$3"); [ "$v" = match ] && return 0; sleep 0.5; done
  fail "pixel $1,$2 is not $3 ($v)"
}
geom() { grep 'sidebar-geom' "$R/qs.log" | tail -1 | sed 's/.*sidebar-geom //'; }
last_window() { grep -oE 'sidebar-window (up|down) [a-z]+' "$R/qs.log" | tail -1; }
wait_window() {
  for _ in $(seq 40); do last_window | grep -q "sidebar-window $1" && return 0; sleep 0.25; done
  fail "the sidebar window is not $1 (last: $(last_window))"
}
panel_place() { { grep -F 'webdock-panel place ' "$R/qs.log" || true; } | tail -1 | sed 's/.*webdock-panel place //'; }
side_line() {  # the host's last sidebar geometry line for the pin $1
  { grep -F "webdock-debug side $1 win " "$HOSTLOG" 2>/dev/null || true; } | tail -1 | sed 's/.*webdock-debug side //'
}
count() { grep -c -F -- "$1" "$2" 2>/dev/null || true; }
qml_errors() {
  local f
  for f in "$R/qs.log" "$HOSTLOG"; do
    if grep -E 'TypeError|ReferenceError|is not a type|is not defined|Cannot assign|Binding loop|caused by' "$f" 2>/dev/null \
        | grep -v 'Unable to assign \[undefined\]' >/dev/null; then
      grep -E 'TypeError|ReferenceError|is not a type|is not defined|Cannot assign|Binding loop|caused by' "$f" | head -20 >&2
      fail "QML problems in $f"
    fi
  done
}
ptr() { echo "$*" >&7; sleep 0.5; }

# ---- 1. the daemon, the mod, the pins, the tab; then the shell ----
env DBUS_SYSTEM_BUS_ADDRESS="unix:path=$R/no-system-bus" PULSE_SERVER="unix:$R/no-pulse/native" \
    PULSE_RUNTIME_PATH="$R/no-pulse" "$W/kurashid" >> "$R/server.log" 2>&1 &
pids+=("$!")
for _ in $(seq 100); do [ -S "$KURASHI_SOCKET" ] && K ping >/dev/null 2>&1 && break; sleep 0.1; done
K ping >/dev/null 2>&1 || fail "kurashid did not come up ($R/server.log)"
K act mod.enable '{"id":"webdock"}' >/dev/null || fail "mod.enable webdock"
K set mods.webdock.pins "[{\"id\":\"site\",\"title\":\"Site\",\"target\":\"$PAGES/site.html#sidebar\"},{\"id\":\"other\",\"title\":\"Other\",\"target\":\"$PAGES/other.html\"}]" >/dev/null \
  || fail "the pins were refused"
K set sidebar.left '["mod:webdock:webdock"]' >/dev/null || fail "sidebar.left = [mod:webdock:webdock] was refused (the tab is not offered)"
ok "the dock's panel is offered as a left tab (sidebar.left accepted)"

: > "$R/qs.log"
env -u KURASHI_SOCKET KURASHI_SIDEBAR_GEOMETRY=1 qs -p "$ROOT/frontend" >> "$R/qs.log" 2>&1 &
pids+=("$!")
for _ in $(seq 100); do grep -q 'hello.*frontend' "$R/server.log" && break; sleep 0.1; done
grep -q 'hello.*frontend' "$R/server.log" || fail "the frontend never said hello ($R/qs.log)"
sleep 3
rm -f "$W/ptr"; mkfifo "$W/ptr"
python3 -I "$ROOT/tools/bench/wl_pointer.py" --serve < "$W/ptr" >> "$W/ptr.log" 2>&1 &
PTR_PID=$!
exec 7> "$W/ptr"

K act sidebar.toggle '{"side":"left","output":"HEADLESS-1"}' >/dev/null
wait_window up
for _ in $(seq 40); do grep 'sidebar-tab ' "$R/qs.log" | tail -1 | grep -q 'mod:webdock:webdock true mod:webdock:webdock=ok' && break; sleep 0.25; done
grep 'sidebar-tab ' "$R/qs.log" | tail -1 | grep -q 'mod:webdock:webdock true mod:webdock:webdock=ok' \
  || fail "the left sidebar does not show the dock's tab ($(grep 'sidebar-tab ' "$R/qs.log" | tail -1))"
ok "the left sidebar shows the web dock tab"

wait_doc "d.get('sidebar', {}).get('pin') == 'site' and 'place' in d.get('sidebar', {})" 10 \
  || fail "the panel never reported its place ($(doc "d.get('sidebar')"))"
wait_doc "d['host']['state'] == 'ready'" 60 || fail "the host never got ready: $(doc "d['host']") ($HOSTLOG)"
wait_doc "[p for p in d['pins'] if p['id'] == 'site'][0].get('loaded') == True" 60 || fail "the page never loaded"
for _ in $(seq 40); do [ -n "$(side_line site)" ] && grep -q 'webdock-debug side shown' "$HOSTLOG" && break; sleep 0.25; done
[ -n "$(side_line site)" ] || fail "the host did not show the page in its sidebar window ($HOSTLOG)"
sleep 1

# The panel's report: <output> <side> <inset> <top> <w> <h> panel <pw> <ph> at <pinset> <ptop> pitch <pitch>
read -r OUT SIDE IN TOP WW WH _ PW PH _ PIN PTOP _ PITCH <<< "$(panel_place)"
# The sidebar: <out> <side> <style> win <w> <h> frame <x,y,w,h> bar <edge> <h> gap <g> …
read -r _ _ _ _ SBW SBH _ FR _ BEDGE BARH _ <<< "$(geom)"
IFS=, read -r FX FY FW FH <<< "$FR"
[ "$OUT" = HEADLESS-1 ] && [ "$SIDE" = left ] || fail "the panel placed itself on '$OUT $SIDE'"
[ "$WW" = "$PW" ] || fail "the page area is $WW px wide, the panel $PW: it does not span the pane"
PAD=$(( PIN - FX ))
[ "$PAD" -ge 0 ] && [ "$PAD" -le 32 ] || fail "the panel sits $PAD px into the column (inset $PIN, column x $FX)"
[ "$(( PIN + PW + PAD ))" = "$(( FX + FW ))" ] || fail "the pane is not the column less its padding ($PIN+$PW+$PAD vs $FX+$FW)"
[ "$(( TOP + WH ))" = "$(( FY + FH - PAD ))" ] \
  || fail "the page area ends at $(( TOP + WH )), the pane at $(( FY + FH - PAD )): it does not take the full height"
# The host: site win <w> <h> page <x> <y> <w> <h> place …
read -r _ _ HW HH _ PX PY PGW PGH _ <<< "$(side_line site)"
[ "$HW" = "$WW" ] && [ "$HH" = "$WH" ] || fail "the host's window is ${HW}x$HH, the page area ${WW}x$WH"
[ "$PX" = 0 ] && [ "$PGW" = "$HW" ] && [ "$(( PY + PGH ))" = "$HH" ] \
  || fail "the page does not fill the window under its navigation row (page $PX $PY ${PGW}x$PGH in ${HW}x$HH)"
[ "$PY" -le 64 ] || fail "the navigation row over the page is $PY px tall"
ok "the page fills the pane: area ${WW}x$WH at $IN,$TOP in a ${SBW}x$SBH sidebar (column $FR, padding $PAD); host window ${HW}x$HH, page ${PGW}x$PGH under a $PY px row"
# The page's own colour, on screen, in the middle of the area (the sidebar sits under a top bar of BARH px).
OY=0
[ "$BEDGE" = top ] && OY=$BARH
CX=$(( IN + WW / 2 )); CY=$(( OY + TOP + WH * 3 / 4 ))
wait_px "$CX" "$CY" '#2b3a55' 10
ok "the page is on screen inside the sidebar ($CX,$CY is the page's colour)"
grep -q 'webdock-debug page site active' "$HOSTLOG" || fail "the page was not made active"
sleep 1
timeout 20 grim -g "0,0 $(( SBW + 140 ))x$SH" "$SHOTS/sidebar-washi.png" && ok "shot mods/webdock/shots/sidebar-washi.png"
qml_errors

# ---- 2. a click on the second pin's key switches the page ----
ptr click $(( PIN + PITCH + 20 )) $(( OY + PTOP + 20 )) left
wait_doc "d['sidebar'].get('pin') == 'other'" 10 || fail "the click on the second pin did not switch ($(doc "d.get('sidebar')"))"
for _ in $(seq 60); do [ -n "$(side_line other)" ] && break; sleep 0.25; done
[ -n "$(side_line other)" ] || fail "the host did not move to the other pin"
wait_doc "[p for p in d['pins'] if p['id'] == 'other'][0].get('loaded') == True" 30 || fail "the other page never loaded"
wait_px "$CX" "$CY" '#3a2b45' 10
grep -q 'webdock-debug page site frozen' "$HOSTLOG" || fail "the first page was not frozen when it left"
[ "$(doc "sorted(d['keep'])")" = "['other', 'site']" ] || fail "both pages should stay loaded: keep = $(doc "d['keep']")"
ok "a click on the second pin shows its page in the sidebar; the first stays loaded, frozen"

# ---- 3. closing the sidebar hides the page: unmapped, no frames, frozen, kept ----
hid0=$(count 'webdock-debug side hidden' "$HOSTLOG")
K act sidebar.toggle '{"side":"left"}' >/dev/null
wait_window down
for _ in $(seq 40); do [ "$(count 'webdock-debug side hidden' "$HOSTLOG")" -gt "$hid0" ] && break; sleep 0.25; done
[ "$(count 'webdock-debug side hidden' "$HOSTLOG")" -gt "$hid0" ] || fail "the host's sidebar window did not unmap"
wait_doc "'place' not in d.get('sidebar', {}) and d['sidebar'].get('pin') == 'other'" 5 \
  || fail "the daemon still places the sidebar ($(doc "d.get('sidebar')"))"
grep -q 'webdock-debug page other frozen' "$HOSTLOG" || fail "the page was not frozen when the sidebar closed"
sleep 1
f0=$(count 'webdock-debug side frame' "$HOSTLOG")
sleep 3
f1=$(count 'webdock-debug side frame' "$HOSTLOG")
[ "$f1" = "$f0" ] || fail "the host's sidebar window drew $(( f1 - f0 )) frames in 3 s after the sidebar closed"
[ "$(doc "sorted(d['keep'])")" = "['other', 'site']" ] || fail "closing destroyed a page: keep = $(doc "d['keep']")"
[ "$(doc "d['host']['state']")" = ready ] || fail "closing stopped the host"
wait_px "$CX" "$CY" "$BG" 5
ok "closing the sidebar unmaps the page's window (0 frames in 3 s), freezes the page and keeps it loaded"
qml_errors

# ---- 4. the sekai look ----
K set theme.style '"sekai"' >/dev/null || fail "theme.style sekai"
sleep 2
K act sidebar.toggle '{"side":"left","output":"HEADLESS-1"}' >/dev/null
wait_window up
wait_px "$CX" "$CY" '#3a2b45' 15
sleep 1.5
read -r _ _ _ _ SBW _ <<< "$(geom)"
timeout 20 grim -g "0,0 $(( SBW + 140 ))x$SH" "$SHOTS/sidebar-sekai.png" && ok "shot mods/webdock/shots/sidebar-sekai.png"
qml_errors

# ---- 5. a right-sidebar section: the same page, placed from the right edge ----
K act sidebar.close >/dev/null
wait_window down
K set sidebar.right '["header", "mod:webdock:webdock"]' >/dev/null || fail "sidebar.right with the dock's section was refused"
p0=$(count 'webdock-panel place HEADLESS-1 right ' "$R/qs.log")
K act sidebar.toggle '{"side":"right","output":"HEADLESS-1"}' >/dev/null
wait_window up
for _ in $(seq 40); do [ "$(count 'webdock-panel place HEADLESS-1 right ' "$R/qs.log")" -gt "$p0" ] && break; sleep 0.25; done
[ "$(count 'webdock-panel place HEADLESS-1 right ' "$R/qs.log")" -gt "$p0" ] || fail "the right section never placed its page"
read -r _ _ IN TOP WW WH _ <<< "$(panel_place)"
read -r _ _ _ _ _ _ _ _ _ BEDGE BARH _ <<< "$(geom)"
OY=0
[ "$BEDGE" = top ] && OY=$BARH
wait_doc "d['sidebar'].get('place', {}).get('side') == 'right'" 5 || fail "the daemon did not take the right placement"
wait_px $(( SW - IN - WW / 2 )) $(( OY + TOP + WH / 2 )) '#3a2b45' 15
ok "a right-sidebar section shows the page in its area (${WW}x$WH, $IN px from the right edge)"
K act sidebar.close >/dev/null
wait_window down
qml_errors
echo "test-sidebar: PASS"
