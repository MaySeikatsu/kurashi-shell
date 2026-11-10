#!/usr/bin/env bash
# The painted and the torn edge (I471, I477, K124; components/PaintStroke.qml, PaintBands.qml, EdgeWarp.qml,
# shaders/paint_stroke.frag, edge_warp.frag, sheet_edge.frag), on the REAL kurashid, invisibly (headless sway):
#   1. `theme.chrome = painted`: the theme says `edge.style = painted`; the bar's groups stand on paint (many pixels
#      tinted by the accent, none under Flat), in dark and in light; `theme.edge = painted` under the Lines chrome paints
#      too (the edge apart from the chrome), and `theme.edge = clean` under Painted does not.
#   2. `theme.chrome = ripped` on a framed output: `edge.style = ripped`; the bar's lower edge is torn (where the sheet
#      ends wanders by several px along the bar) and clean under Flat (a straight line).
#   3. idle: 0 frames in 3 s under each; no QML error.
#   nix develop -c frontend/test-edges.sh [sandbox-name]
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
NAME=${1:-${KURASHI_SB_PREFIX:-}s27-edges-test}
BIN=${KURASHI_BIN_DIR:-${CARGO_TARGET_DIR:-$ROOT/target}/debug}
fail() { echo "test-edges: FAIL: $*" >&2; exit 1; }

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
       KURASHI_DATA_DIR=$ROOT LC_ALL=C.UTF-8 KURASHI_SOCKET=$R/kurashi.sock
mkdir -p "$XDG_CONFIG_HOME/kurashi" "$XDG_STATE_HOME" "$XDG_DATA_HOME" "$XDG_CACHE_HOME"
CONF=$XDG_CONFIG_HOME/kurashi/config.toml
K() { timeout 10 "$W/kurashi" "$@"; }
# (no texture: the ground is one flat colour; the clock is the only minute-by-minute change, and it is off the samples)
conf() { printf '[idle]\nenabled = false\n[theme]\nchrome = "%s"\n[theme.texture]\nkind = "none"\n[theme.colors]\nscheme = "%s"\n' "$1" "$2" > "$CONF"; }
conf glow dark

env DBUS_SYSTEM_BUS_ADDRESS="unix:path=$R/no-system-bus" PULSE_SERVER="unix:$R/no-pulse/native" PULSE_RUNTIME_PATH="$R/no-pulse" \
  "$W/kurashid" >> "$R/kurashid.log" 2>&1 &
pids+=($!)
wait_until 15 K ping || fail "kurashid did not answer"
: > "$R/qs.log"
WAYLAND_DEBUG=1 qs -p "$ROOT/frontend" >> "$R/qs.log" 2>&1 &
pids+=($!)
wait_frontend "$R/qs.log" || fail "the frontend did not load"
sleep 1


W_OUT=$(swaymsg -t get_outputs | python3 -c 'import json,sys; print(json.load(sys.stdin)[0]["rect"]["width"])')
token() { K --json sub theme --count 0 | python3 -I -c '
import json,sys
def find(o):
    if isinstance(o, dict):
        if "tokens" in o: return o["tokens"]
        for v in o.values():
            r = find(v)
            if r is not None: return r
print(json.dumps(find(json.loads(sys.stdin.readline())).get(sys.argv[1])))' "$1"; }
# The bar's band as a picture; prints "<tinted> <strong>": pixels whose red stands out from green and blue by more than
# 12 (light of the accent, which is red in the default palette) and by more than 90 (the outline itself).
# conf2 <chrome> <edge> <scheme> [framed]
conf2() {
  printf '[idle]\nenabled = false\n[theme]\nchrome = "%s"\nedge = "%s"\n[theme.texture]\nkind = "none"\n[theme.colors]\nscheme = "%s"\n' "$1" "$2" "$3" > "$CONF"
  [ "${4:-}" = framed ] && printf '[layout.frame]\nenabled = true\nreserve = true\nthickness = 10\n' >> "$CONF"
  sleep 2; wait_settled 5 0.5
}
# Pixels of the bar's band tinted by the accent (red stands out from green and blue by more than 12).
tinted() {
  grim -g "0,0 ${W_OUT}x40" -t ppm "$R/band.ppm"
  python3 -I - "$R/band.ppm" <<'PY'
import sys
d = open(sys.argv[1], 'rb').read()
p = d.split(b'\n', 3)
w, h = map(int, p[1].split()); px = p[3]
print(sum(1 for i in range(0, w * h * 3, 3) if px[i] - max(px[i + 1], px[i + 2]) > 12))
PY
}
for scheme in dark light; do
  conf2 painted auto "$scheme"
  [ "$(token edge.style)" = '"painted"' ] || fail "$scheme: edge.style is $(token edge.style) under the Painted chrome"
  p=$(tinted)
  conf2 flat auto "$scheme"
  [ "$(token edge.style)" = '"clean"' ] || fail "$scheme: edge.style is $(token edge.style) under Flat"
  f=$(tinted)
  [ "$p" -ge 800 ] && [ "$p" -ge $(( f * 4 + 1 )) ] || fail "$scheme: the bar's groups stand on no paint under Painted ($p tinted px; $f under Flat)"
  echo "ok: $scheme: $p px of paint on the bar under Painted, $f under Flat"
done
conf2 line painted light
[ "$(token edge.style)" = '"painted"' ] || fail "theme.edge = painted under Lines: edge.style is $(token edge.style)"
p=$(tinted)
conf2 painted clean light
[ "$(token edge.style)" = '"clean"' ] || fail "theme.edge = clean under Painted: edge.style is $(token edge.style)"
c=$(tinted)
[ "$p" -ge 800 ] && [ "$c" -lt $(( p / 4 )) ] || fail "the edge apart from the chrome: $p px of paint with edge = painted under Lines, $c with edge = clean under Painted"
echo "ok: the edge apart from the chrome: paint under Lines with theme.edge = painted ($p px), none with clean under Painted ($c)"

# 2. The torn edge of a framed bar: for every column, the last row of the bar's paper above the desktop.
wander() {
  grim -g "0,0 ${W_OUT}x90" -t ppm "$R/band.ppm"
  python3 -I - "$R/band.ppm" <<'PY'
import sys
d = open(sys.argv[1], 'rb').read()
p = d.split(b'\n', 3)
w, h = map(int, p[1].split()); px = p[3]
ys = []
for x in range(120, w - 120, 3):
    # (from the desktop upwards: what is written on the bar is not the bar's edge)
    for y in range(h - 2, 10, -1):
        i = (y * w + x) * 3
        if min(px[i], px[i + 1], px[i + 2]) >= 150:
            ys.append(y); break
ys.sort()
if len(ys) < 50: print(0); sys.exit(0)
print(ys[int(len(ys) * 0.97)] - ys[int(len(ys) * 0.03)])
PY
}
conf2 ripped auto light framed
[ "$(token edge.style)" = '"ripped"' ] || fail "edge.style is $(token edge.style) under the Ripped paper chrome"
r=$(wander)
conf2 flat auto light framed
s=$(wander)
[ "$r" -ge 3 ] && [ "$s" -le 1 ] || fail "the framed bar's edge: it wanders $r px under Ripped (at least 3 wanted) and $s px under Flat (a line)"
echo "ok: the framed bar's lower edge wanders $r px under Ripped paper and $s px under Flat"

# 3. idle and errors
commits() { grep -c 'wl_surface#[0-9]*\.commit(' "$R/qs.log" || true; }
for chrome in painted ripped; do
  conf2 "$chrome" auto light framed
  wait_settled 3 0.6
  c0=$(commits); sleep 3
  idle=$(( $(commits) - c0 ))
  [ "$idle" = 0 ] || fail "idle: the shell committed $idle frames in 3 s under $chrome"
  echo "ok: idle, 0 frames in 3 s under $chrome"
done
if grep -E "qml|QML" "$R/qs.log" | grep -iE "error|TypeError|ReferenceError|Binding loop" | grep -v desktopentry | head -3 | grep -q .; then
  grep -E "qml|QML" "$R/qs.log" | grep -iE "error|TypeError|ReferenceError|Binding loop" | head -5 >&2
  fail "the frontend logged a QML error"
fi
echo "ok: the frontend logs no QML error"
echo "test-edges: all checks passed"
