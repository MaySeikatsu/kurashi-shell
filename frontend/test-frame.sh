#!/usr/bin/env bash
# The screen frame (K71, docs/ux/frame.md), headless (sway sandbox), against kurashi-mock serving staged layouts
# (KURASHI_MOCK_LAYOUT, the "*" entry: the sandbox's output is HEADLESS-1, not the fixture's DP-1) and wearing a real
# look (kurashid's theme tokens for the decor, handed to the mock with `mock.doc`, as test-look does):
#   - frame off: no `kurashi-frame` layer surface (the frontend's own requests, WAYLAND_DEBUG); on: four per output;
#   - the one-holder rule: a test window tiles inside the band with reserve on, under it with reserve off (its position
#     from sway's tree; the strips and the bar keep the zones);
#   - the band is drawn where the layout says (pixels at the band, the fillet and the cut), and the docked bar and the
#     band are one fill (flat, untextured look: the same pixel);
#   - idle: no Wayland commit in 10 s with the frame on (textured washi);
#   - the frontend's PSS with the frame off and on, back-to-back pairs (printed; BENCH);
#   - shots: frontend/shots/frame/<decor>/ — washi (light, dark), sekai, glass, win95, terminal: off, top bar (docked),
#     floating bottom bar, no bar, reserve off; washi also radius 0 / 48, thickness 2 / 32, screen corners on.
#   - no QML error in the frontend's log.
#   KURASHI_BIN_DIR=<dir with kurashid, kurashi, kurashi-mock> timeout 1800 nix develop -c frontend/test-frame.sh [sandbox]
#   FRAME_DECORS="washi sekai" picks decors; FRAME_PAIRS=<n> the PSS pairs (default 3).
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
NAME=${1:-w43-frame-test}
BIN=${KURASHI_BIN_DIR:-${CARGO_TARGET_DIR:-$ROOT/target}/debug}
OUT=$ROOT/frontend/shots/frame
DECORS=${FRAME_DECORS:-washi washi-dark sekai glass win95 terminal}
PAIRS=${FRAME_PAIRS:-3}
FAILS=0
fail() { echo "test-frame: FAIL $*" >&2; FAILS=$((FAILS + 1)); }
die() { echo "test-frame: $*" >&2; exit 1; }
say() { echo "test-frame: $*"; }
for b in kurashid kurashi kurashi-mock; do [ -x "$BIN/$b" ] || die "no $b in $BIN (KURASHI_BIN_DIR)"; done

eval "$("$ROOT/tools/bench/sandbox.sh" start "$NAME")"
R=$XDG_RUNTIME_DIR
W=$R/work
mkdir -p "$W" "$R/kurashi"
cp "$BIN/kurashid" "$BIN/kurashi" "$BIN/kurashi-mock" "$W/"
SRV=""; QS=""; WIN=""
stop() { for v in WIN QS SRV; do p=${!v}; [ -n "$p" ] && { kill "$p" 2>/dev/null || true; wait "$p" 2>/dev/null || true; }; eval "$v="; done; }
cleanup() { stop; "$ROOT/tools/bench/sandbox.sh" stop "$NAME" >/dev/null || true; }
trap cleanup EXIT

export XDG_CONFIG_HOME=$R/xdg/config XDG_STATE_HOME=$R/xdg/state \
       XDG_DATA_HOME=$R/xdg/data XDG_CACHE_HOME=$R/xdg/cache KURASHI_DATA_DIR=$ROOT LC_ALL=C.UTF-8
K() { timeout 10 "$W/kurashi" "$@"; }
SW=1920; SH=1080
timeout 20 swaymsg output HEADLESS-1 resolution "${SW}x${SH}" >/dev/null || die "the output did not take ${SW}x${SH}"
swaymsg output '*' bg '#8fb8c8' solid_color >/dev/null
# The test window has no title bar or border, so its rect is where its content starts.
swaymsg 'default_border none' >/dev/null
swaymsg 'default_floating_border none' >/dev/null
: > "$R/qs.log"

# ---- the theme tokens of a decor: kurashid with that look, its theme document as a patch for the mock ----
tokens() { # tokens <decor> → $W/theme-<decor>.json
  local d=$1 style=${1%-dark}
  rm -rf "$R/xdg"; mkdir -p "$XDG_CONFIG_HOME/kurashi" "$XDG_STATE_HOME" "$XDG_DATA_HOME" "$XDG_CACHE_HOME"
  printf 'theme.style = "%s"\n' "$style" > "$XDG_CONFIG_HOME/kurashi/config.toml"
  [ "$d" != "$style" ] && printf 'theme.colors.scheme = "dark"\n' >> "$XDG_CONFIG_HOME/kurashi/config.toml"
  rm -f "$KURASHI_SOCKET"
  env DBUS_SYSTEM_BUS_ADDRESS="unix:path=$R/no-system-bus" PULSE_SERVER="unix:$R/no-pulse/native" \
      PULSE_RUNTIME_PATH="$R/no-pulse" "$W/kurashid" >> "$R/kurashid.log" 2>&1 &
  SRV=$!
  for _ in $(seq 100); do [ -S "$KURASHI_SOCKET" ] && K ping >/dev/null 2>&1 && break; sleep 0.1; done
  K ping >/dev/null 2>&1 || die "kurashid did not come up for $d (see $R/kurashid.log)"
  sleep 1
  K sub theme --count 0 --json | jq -c '{doc: "theme", patch: {tokens: .data.tokens}}' > "$W/theme-$d.json"
  stop
}

# ---- a staged layout ("*" entry), from the fixture's framed output ----
cat > "$W/layout.py" <<'PY'
import json, sys
fixture, scene, barh, out = sys.argv[1], sys.argv[2], int(sys.argv[3]), sys.argv[4]
args = dict(a.split("=") for a in sys.argv[5:])
doc = json.load(open(fixture))["data"]
o = json.loads(json.dumps(doc["outputs"]["DP-1"]))
t = int(args.get("thickness", 8)); r = int(args.get("radius", 16)); gap = doc["gap"]
f = o["frame"]; f.update(on=True, thickness=t, radius=r, reserve=True)
E = o["edges"]
for e in E.values():
    e.update(bar=False, draw="dynamic", visibility="always", inset=t, reserve=t, holder="frame")
    e.pop("size", None)
band = {"top": t, "bottom": t, "left": t, "right": t}
def bar(e, draw="dynamic"):
    E[e].update(bar=True, size=barh, draw=draw)
    if draw == "floating":
        E[e].update(inset=t + gap, reserve=t + gap + barh + gap)
    else:
        band[e] = 0
        E[e].update(inset=0, reserve=barh)
if scene in ("top", "reserve-off"):
    bar("top")
elif scene == "floating":
    bar("bottom", "floating")
elif scene == "nobar":
    pass
elif scene == "off":
    f.update(on=False)
    bar("top")
    band = {k: 0 for k in band}
    for k, e in E.items():
        e.update(inset=0, reserve=barh if k == "top" else 0, holder="bar" if k == "top" else "none")
if scene == "reserve-off":
    f["reserve"] = False
    for k, e in E.items():
        e.update(reserve=barh if k == "top" else 0, holder="bar" if k == "top" else "none")
f["band"] = band
doc["outputs"] = {"*": o}
doc["bar_size"] = barh
json.dump(doc, open(out, "w"))
PY

# ---- one scene: the mock with a staged layout and a decor, the frontend; then the shots ----
BARH=36
scene() { # scene <decor> <scene> [layout args…]; env CFG: extra config values (JSON object)
  local d=$1 s=$2; shift 2
  stop
  BARH=$(jq -r '.patch.tokens["bar.height"] // 36' "$W/theme-$d.json")
  python3 -I "$W/layout.py" "$ROOT/fixtures/ipc/server/snap_runtime_layout.json" "$s" "$BARH" "$W/layout.json" "$@"
  rm -f "$KURASHI_SOCKET"
  KURASHI_MOCK_LAYOUT=$W/layout.json "$W/kurashi-mock" --outputs HEADLESS-1 --socket "$KURASHI_SOCKET" >> "$R/mock.log" 2>&1 &
  SRV=$!
  for _ in $(seq 100); do [ -S "$KURASHI_SOCKET" ] && K ping >/dev/null 2>&1 && break; sleep 0.1; done
  K ping >/dev/null 2>&1 || die "kurashi-mock did not come up (see $R/mock.log)"
  K act mock.doc "$(cat "$W/theme-$d.json")" >/dev/null
  local edge=top enabled=true
  [ "$s" = floating ] && edge=bottom
  [ "$s" = nobar ] && enabled=false
  local cfg; cfg=$(jq -cn --arg e "$edge" --argjson en "$enabled" --argjson x "${CFG:-{\}}" \
    '{doc: "config", patch: {values: ({"bar.edge": {value: $e, source: {kind: "user"}}, "bar.enabled": {value: $en, source: {kind: "user"}}} + ($x | with_entries(.value = {value: .value, source: {kind: "user"}})))}}')
  K act mock.doc "$cfg" >/dev/null
  local before; before=$(stat -c %s "$R/qs.log")
  env -u KURASHI_SOCKET ${QS_ENV:-} qs -p "$ROOT/frontend" >> "$R/qs.log" 2>&1 &
  QS=$!
  sleep 4
}
shoot() { # shoot <decor> <name>: the screen (half size) and the top-left corner (4×)
  mkdir -p "$OUT/$1"
  grim -s 0.5 "$OUT/$1/$2.png"
  grim -s 4 -g "0,0 120x90" "$OUT/$1/$2-corner.png"
}
# A pixel of the screen: "r g b".
pixel() { grim -t ppm -g "$1,$2 1x1" - | tail -c 3 | od -An -tu1 | xargs; }
# The test window (an xdg toplevel sway tiles); its rect "x y w h".
window_rect() {
  cat > "$W/win.qml" <<'QML'
import QtQuick
import Quickshell
ShellRoot { FloatingWindow { color: "#c03030"; implicitWidth: 400; implicitHeight: 300 } }
QML
  env -u KURASHI_SOCKET qs -p "$W/win.qml" >> "$R/win.log" 2>&1 &
  WIN=$!
  local rect=""
  for _ in $(seq 50); do
    rect=$(swaymsg -t get_tree -r | jq -r --argjson p "$WIN" '.. | select(.pid? == $p) | .rect | "\(.x) \(.y) \(.width) \(.height)"' | head -1)
    [ -n "$rect" ] && break; sleep 0.1
  done
  sleep 0.8
  rect=$(swaymsg -t get_tree -r | jq -r --argjson p "$WIN" '.. | select(.pid? == $p) | .rect | "\(.x) \(.y) \(.width) \(.height)"' | head -1)
  echo "$rect"
}
close_window() { [ -n "$WIN" ] && { kill "$WIN" 2>/dev/null || true; wait "$WIN" 2>/dev/null || true; }; WIN=""; }
surfaces() { # surfaces <log offset>: kurashi-frame layer surfaces the frontend asked for since then
  tail -c +"$(( $1 + 1 ))" "$R/qs.log" | grep -c 'get_layer_surface(.*"kurashi-frame")' || true
}
commits() { tail -c +"$(( $1 + 1 ))" "$R/qs.log" | grep -c 'wl_surface#[0-9]*\.commit(' || true; }
pss_mib() { awk '/^Pss:/{s+=$2} END{printf "%.2f", s/1024}' "/proc/$1/smaps_rollup"; }

for d in $DECORS; do tokens "$d"; done
if [ -n "${FRAME_DEV:-}" ]; then   # development: one scene, its shot and the log's errors
  QS_ENV=KURASHI_FRAME_LOG=1 scene ${FRAME_DEV}; shoot dev "${FRAME_DEV// /-}"
  for y in 10 30 45 60 300; do echo "px 3 $y: $(pixel 3 $y)  px 7 $y: $(pixel 7 $y)"; done; stop
  grep FRAMEGEO "$R/qs.log" | tail -8
  grep -E 'WARN|ERROR|Error|error|Cannot|Unable' "$R/qs.log" | sort | uniq -c | head -30
  exit 0
fi
tokens kanso   # an untextured, flat look: the one-sheet pixel check

# ---- washi: surfaces, reserve, pixels, idle ----
if [[ " $DECORS " == *" washi "* ]]; then
  T=8; RAD=16
  off=$(stat -c %s "$R/qs.log"); QS_ENV=WAYLAND_DEBUG=client scene washi off
  n=$(surfaces "$off"); say "frame off: $n kurashi-frame surfaces"; [ "$n" = 0 ] || fail "frame off made $n kurashi-frame surfaces"
  rect=$(window_rect); say "frame off: test window at $rect"
  set -- $rect; [ "${1:-x}" = 0 ] && [ "${2:-x}" = "$BARH" ] || fail "frame off: the window is at $rect, not 0 $BARH"
  close_window

  off=$(stat -c %s "$R/qs.log"); QS_ENV=WAYLAND_DEBUG=client scene washi top
  n=$(surfaces "$off"); say "frame on: $n kurashi-frame surfaces"; [ "$n" = 4 ] || fail "frame on made $n kurashi-frame surfaces, not 4"
  s=$(stat -c %s "$R/qs.log"); sleep 10; c=$(commits "$s")
  say "idle, frame on (washi, textured): $c commits in 10 s"; [ "$c" = 0 ] || fail "idle with the frame on: $c Wayland commits in 10 s"
  rect=$(window_rect); say "frame on, reserve on: test window at $rect"
  set -- $rect
  [ "${1:-x}" = "$T" ] && [ "${2:-x}" = "$BARH" ] && [ "${3:-0}" = $((SW - 2 * T)) ] && [ "${4:-0}" = $((SH - BARH - T)) ] \
    || fail "reserve on: the window is at $rect, not $T $BARH $((SW - 2 * T)) $((SH - BARH - T))"
  close_window
  # The band at the left edge, the cut beside it, the fillet's corner under the bar's end and the cut past its arc.
  bg=$(pixel 960 700)
  [ "$(pixel 3 600)" != "$bg" ] || fail "no band at the left edge"
  [ "$(pixel $((T + 2)) 600)" = "$bg" ] || fail "something drawn in the cut beside the left band"
  [ "$(pixel $((T + 1)) $((BARH + 1)))" != "$bg" ] || fail "no fillet under the bar's left end"
  [ "$(pixel $((T + RAD - 2)) $((BARH + RAD - 2)))" = "$bg" ] || fail "the fillet reaches past its arc"
  [ "$(pixel 3 $((SH - 3)))" != "$bg" ] || fail "no band at the bottom-left corner"

  scene washi reserve-off
  rect=$(window_rect); say "frame on, reserve off: test window at $rect"
  set -- $rect; [ "${1:-x}" = 0 ] && [ "${2:-x}" = "$BARH" ] && [ "${3:-0}" = "$SW" ] \
    || fail "reserve off: the window is at $rect, not 0 $BARH $SW (under the band)"
  shoot washi reserve-off-window
  close_window

  scene washi floating
  rect=$(window_rect); say "floating bottom bar: test window at $rect"
  set -- $rect; [ "${1:-x}" = "$T" ] && [ "${2:-x}" = "$T" ] && [ "${4:-0}" = $((SH - T - T - 8 - BARH - 8)) ] \
    || fail "floating bottom bar: the window is at $rect, not $T $T … $((SH - 2 * T - 16 - BARH))"
  close_window
fi

# ---- one sheet: an untextured flat look, the docked bar's fill and the band's are the same pixel ----
scene kanso top
pb=$(pixel 3 $((BARH / 2))); pf=$(pixel 3 600)
say "kanso: bar fill at the end $pb, band $pf"
[ "$pb" = "$pf" ] || fail "the bar and the band are not one fill ($pb vs $pf)"

# ---- the shots ----
for d in $DECORS; do
  for s in off top floating nobar reserve-off; do scene "$d" "$s"; shoot "$d" "$s"; done
  say "$OUT/$d/"
done
if [[ " $DECORS " == *" washi "* ]]; then
  scene washi top radius=0; shoot washi radius-0
  scene washi top radius=48; shoot washi radius-48
  scene washi top thickness=2; shoot washi thickness-2
  scene washi nobar thickness=32; shoot washi thickness-32
  CFG='{"theme.shape.screen_corners": 16}' scene washi top; shoot washi screen-corners
fi

# ---- memory: the frontend's PSS with the frame off and on, back-to-back pairs ----
for d in washi kanso; do
  [ "$d" = washi ] && [[ " $DECORS " != *" washi "* ]] && continue
  for i in $(seq "$PAIRS"); do
    scene "$d" off; sleep 2; a=$(pss_mib "$QS")
    scene "$d" top; sleep 2; b=$(pss_mib "$QS")
    say "PSS $d pair $i: frame off $a MiB, on $b MiB (+$(awk -v a="$a" -v b="$b" 'BEGIN{printf "%.2f", b - a}') MiB)"
  done
done

stop
if grep -E 'ERROR|qml:.*(Error|error)|TypeError|ReferenceError|is not a type|Cannot assign|Unable to assign' "$R/qs.log" \
    | grep -v 'Unable to assign \[undefined\]' >/dev/null; then
  grep -E 'Error|error|Cannot assign|Unable to assign' "$R/qs.log" | sort | uniq -c | head -20 >&2
  fail "QML errors (see $R/qs.log)"
fi
[ "$FAILS" = 0 ] || die "$FAILS checks failed"
say "ok ($OUT)"
