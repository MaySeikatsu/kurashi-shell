#!/usr/bin/env bash
# The screen frame (K71, docs/ux/frame.md), headless (sway sandbox), against kurashi-mock serving staged layouts
# (KURASHI_MOCK_LAYOUT, the "*" entry: the sandbox's output is HEADLESS-1, not the fixture's DP-1) and wearing a real
# look (kurashid's theme tokens for the decor, handed to the mock with `mock.doc`, as test-look does):
#   - frame off: no `kurashi-frame` layer surface (the frontend's own requests, WAYLAND_DEBUG); on with a docked top bar:
#     three per output (row 492 b: the bar's window carries the top strip);
#   - the one-holder rule: a test window tiles inside the band with reserve on, under it with reserve off (its position
#     from sway's tree; the strips and the bar keep the zones);
#   - the band is drawn where the layout says (pixels at the band, the fillet and the cut), and the docked bar and the
#     band are one fill (flat, untextured look: the same pixel);
#   - idle: no Wayland commit in 10 s with the frame on (washi with the paper material on the shell; kami with its pen);
#   - the frontend's PSS with the frame off and on, back-to-back pairs (printed; BENCH);
#   - shots: frontend/shots/frame/<decor>/ — washi (light, dark, with the paper material), sekai (also with paper), glass,
#     win95, terminal, kami (its paper and pen): off, top bar (docked), floating bottom bar, no bar, reserve off; washi
#     also the bar on the other edges, radius 0 / 48, thickness 2 / 32, screen corners on, two outputs; a textured decor
#     also `seam.png`, the bar's end and the fillet at 8× (the grain must run on across bar and band).
#   - no QML error in the frontend's log.
#   KURASHI_BIN_DIR=<dir with kurashid, kurashi, kurashi-mock> timeout 1800 nix develop -c frontend/test-frame.sh [sandbox]
#   FRAME_DECORS="washi sekai" picks decors; FRAME_PAIRS=<n> the PSS pairs (default 3).
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
NAME=${1:-w43-frame-test}
BIN=${KURASHI_BIN_DIR:-${CARGO_TARGET_DIR:-$ROOT/target}/debug}
OUT=$ROOT/frontend/shots/frame
DECORS=${FRAME_DECORS:-washi washi-dark washi-paper sekai sekai-paper glass win95 terminal kami}
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
#   <style>[-dark][-paper]: the style, its dark scheme, the paper material (K59) on the shell. The cache (the material's
#   tiles) is kept across decors: the mock's theme names tile files in it.
tokens() { # tokens <decor> → $W/theme-<decor>.json
  local d=$1 style=${1%%-*}
  mkdir -p "$XDG_CONFIG_HOME/kurashi" "$XDG_STATE_HOME" "$XDG_DATA_HOME" "$XDG_CACHE_HOME"
  printf 'theme.style = "%s"\n' "$style" > "$XDG_CONFIG_HOME/kurashi/config.toml"
  [[ "$d" == *-dark* ]] && printf 'theme.colors.scheme = "dark"\n' >> "$XDG_CONFIG_HOME/kurashi/config.toml"
  [[ "$d" == *-paper* ]] && printf 'theme.texture.kind = "paper"\ntheme.texture.strength = 1.5\n' >> "$XDG_CONFIG_HOME/kurashi/config.toml"
  rm -f "$KURASHI_SOCKET"
  env DBUS_SYSTEM_BUS_ADDRESS="unix:path=$R/no-system-bus" PULSE_SERVER="unix:$R/no-pulse/native" \
      PULSE_RUNTIME_PATH="$R/no-pulse" "$W/kurashid" >> "$R/kurashid.log" 2>&1 &
  SRV=$!
  for _ in $(seq 100); do [ -S "$KURASHI_SOCKET" ] && K ping >/dev/null 2>&1 && break; sleep 0.1; done
  K ping >/dev/null 2>&1 || die "kurashid did not come up for $d (see $R/kurashid.log)"
  sleep 1
  # A material's tile is made in the background: wait for its file.
  if [[ "$d" == *-paper* ]]; then
    for _ in $(seq 100); do
      [ -n "$(K sub theme --count 0 --json | jq -r '.data.tokens["texture.map"] // ""')" ] && break; sleep 0.2
    done
  fi
  K sub theme --count 0 --json | jq -c '{doc: "theme", patch: {tokens: .data.tokens}}' > "$W/theme-$d.json"
  [[ "$d" == *-paper* ]] && [ "$(jq -r '.patch.tokens["texture.shell"]' "$W/theme-$d.json")" != true ] \
    && fail "$d: the material is not on the shell"
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
        # Row 510: a docked bar carries its edge's strip and holds the zone there (`holder: "bar"`).
        E[e].update(inset=0, reserve=barh, holder="bar")
if scene in ("top", "reserve-off"):
    bar("top")
elif scene == "hover":
    # A docked bar on hover carries its strip and keeps the frame's zone (the daemon's `frame_here`).
    bar("top")
    E["top"].update(visibility="hover", reserve=t)
elif scene == "floating":
    bar("bottom", "floating")
elif scene.startswith("bar-"):
    bar(scene[4:])
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
if args.get("multi"):
    # Two outputs, different settings: the first framed as staged, the second (and any other) without a frame.
    off = json.loads(json.dumps(o))
    off["frame"].update(on=False, band={k: 0 for k in band})
    for k, e in off["edges"].items():
        e.update(inset=0, reserve=barh if k == "top" else 0, holder="bar" if k == "top" else "none")
    doc["outputs"] = {args["multi"]: o, "*": off}
doc["bar_size"] = barh
# The screen's corners (K74 `screen_radius`): square unless the scene says (`screen=<px>`), as the shots before it.
doc["screen_radius"] = int(args.get("screen", 0))
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
  KURASHI_MOCK_LAYOUT=$W/layout.json "$W/kurashi-mock" --outputs "${OUTPUTS:-HEADLESS-1}" ${MOCK_ARGS:-} --socket "$KURASHI_SOCKET" >> "$R/mock.log" 2>&1 &
  SRV=$!
  for _ in $(seq 100); do [ -S "$KURASHI_SOCKET" ] && K ping >/dev/null 2>&1 && break; sleep 0.1; done
  K ping >/dev/null 2>&1 || die "kurashi-mock did not come up (see $R/mock.log)"
  K act mock.doc "$(cat "$W/theme-$d.json")" >/dev/null
  local edge=top enabled=true
  [ "$s" = floating ] && edge=bottom
  [[ "$s" == bar-* ]] && edge=${s#bar-}
  [ "$s" = nobar ] && enabled=false
  local cfg; cfg=$(jq -cn --arg e "$edge" --argjson en "$enabled" --argjson x "${CFG:-{\}}" \
    '{doc: "config", patch: {values: ({"bar.edge": {value: $e, source: {kind: "user"}}, "bar.enabled": {value: $en, source: {kind: "user"}}} + ($x | with_entries(.value = {value: .value, source: {kind: "user"}})))}}')
  K act mock.doc "$cfg" >/dev/null
  local before; before=$(stat -c %s "$R/qs.log")
  env -u KURASHI_SOCKET ${QS_ENV:-} qs -p "$ROOT/frontend" >> "$R/qs.log" 2>&1 &
  QS=$!
  sleep 4
}
shoot() { # shoot <decor> <name>: the screen (half size) and the top-left corner (4×; the bottom-left one for a bottom bar)
  mkdir -p "$OUT/$1"
  grim -s 0.5 "$OUT/$1/$2.png"
  local g="0,0 120x90"
  [ "$2" = floating ] && g="0,$((SH - 90)) 120x90"
  grim -s 4 -g "$g" "$OUT/$1/$2-corner.png"
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
  rect=""
  for _ in $(seq 50); do
    rect=$(swaymsg -t get_tree -r | jq -r --argjson p "$WIN" '.. | select(.pid? == $p) | .rect | "\(.x) \(.y) \(.width) \(.height)"' | head -1)
    [ -n "$rect" ] && break; sleep 0.1
  done
  sleep 0.8
  rect=$(swaymsg -t get_tree -r | jq -r --argjson p "$WIN" '.. | select(.pid? == $p) | .rect | "\(.x) \(.y) \(.width) \(.height)"' | head -1)
  return 0
}
close_window() { [ -n "$WIN" ] && { kill "$WIN" 2>/dev/null || true; wait "$WIN" 2>/dev/null || true; }; WIN=""; }
surfaces() { # surfaces <log offset>: kurashi-frame layer surfaces the frontend asked for since then
  tail -c +"$(( $1 + 1 ))" "$R/qs.log" | grep -c 'get_layer_surface(.*"kurashi-frame")' || true
}
commits() { tail -c +"$(( $1 + 1 ))" "$R/qs.log" | grep -c 'wl_surface#[0-9]*\.commit(' || true; }
# side_strips <log offset> <what>: under a docked top bar (washi, T, RAD) the side strips run the full height between
# the fillets' ends — from BARH + RAD to SH - T - RAD (KURASHI_FRAME_LOG's FRAMEGEO: edge, origin, size) — and the band
# is on screen just under the top fillet. Row 525: a strip that held no zone but wrote `exclusiveZone` was placed inside
# the bar's zone (BARH px short, a notch under the fillet); row 510: one that holds a zone starts inside the bar's.
side_strips() {
  local e line h want=$((SH - BARH - RAD - T - RAD)) bgp
  sleep 1
  bgp=$(pixel 960 700)
  for e in left right; do
    line=$(tail -c +"$(( $1 + 1 ))" "$R/qs.log" | grep -o "FRAMEGEO $e [0-9.]* [0-9.]* [0-9.]* [0-9.]* [a-z]*" | tail -1)
    h=$(cut -d' ' -f6 <<< "$line")
    [ "${h:-x}" = "$want" ] && say "$2: the $e strip runs $h px ($line)" \
      || fail "$2: the $e strip is '${h:-?}' px tall, not $want ($line)"
  done
  [ "$(pixel 3 $((BARH + RAD + 2)))" != "$bgp" ] || fail "$2: no band just under the top-left fillet (y $((BARH + RAD + 2)))"
  [ "$(pixel $((SW - 4)) $((BARH + RAD + 2)))" != "$bgp" ] || fail "$2: no band just under the top-right fillet"
}
pss_mib() { awk '/^Pss:/{s+=$2} END{printf "%.2f", s/1024}' "/proc/$1/smaps_rollup"; }

for d in $DECORS; do tokens "$d"; done
if [ -n "${FRAME_DEV:-}" ]; then   # development: one scene, its shot and the log's errors
  QS_ENV="KURASHI_FRAME_LOG=1 ${FRAME_DEV_ENV:-}" scene ${FRAME_DEV}; shoot dev "${FRAME_DEV// /-}"
  [ -n "${FRAME_DEV_CROP:-}" ] && grim -s 8 -g "$FRAME_DEV_CROP" "$OUT/dev/crop.png"
  if [ -n "${FRAME_DEV_ENV:-}" ]; then   # with WAYLAND_DEBUG: which surfaces commit while idle, and their namespaces
    s=$(stat -c %s "$R/qs.log"); sleep 10
    tail -c +"$((s + 1))" "$R/qs.log" | grep -o 'wl_surface#[0-9]*\.commit(' | sort | uniq -c  || true
    grep -o 'get_layer_surface(new id [^,]*, wl_surface#[0-9]*, [^)]*)' "$R/qs.log" | sed 's/new id //' | sort -u | tail -20 || true
  fi
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
  window_rect; say "frame off: test window at $rect"
  set -- $rect; [ "${1:-x}" = 0 ] && [ "${2:-x}" = "$BARH" ] || fail "frame off: the window is at $rect, not 0 $BARH"
  close_window

  off=$(stat -c %s "$R/qs.log"); QS_ENV="WAYLAND_DEBUG=client KURASHI_FRAME_LOG=1" scene washi top
  n=$(surfaces "$off"); say "frame on: $n kurashi-frame surfaces"; [ "$n" = 3 ] || fail "frame on made $n kurashi-frame surfaces, not 3 (the docked bar carries the top strip)"
  side_strips "$off" "reserve on"
  window_rect; say "frame on, reserve on: test window at $rect"
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

  off=$(stat -c %s "$R/qs.log"); QS_ENV=KURASHI_FRAME_LOG=1 scene washi reserve-off
  side_strips "$off" "reserve off"
  window_rect; say "frame on, reserve off: test window at $rect"
  set -- $rect; [ "${1:-x}" = 0 ] && [ "${2:-x}" = "$BARH" ] && [ "${3:-0}" = "$SW" ] \
    || fail "reserve off: the window is at $rect, not 0 $BARH $SW (under the band)"
  shoot washi reserve-off-window
  close_window

  # Off and on again while the shell runs (the layout changes; the band fades out and comes back).
  K act mock.doc '{"doc":"runtime.layout","patch":{"outputs":{"*":{"frame":{"on":false}}}}}' >/dev/null; sleep 1.5
  [ "$(pixel 3 600)" = "$bg" ] || fail "the band stayed after the frame went off"
  K act mock.doc '{"doc":"runtime.layout","patch":{"outputs":{"*":{"frame":{"on":true}}}}}' >/dev/null; sleep 1.5
  [ "$(pixel 3 600)" != "$bg" ] || fail "the band did not come back with the frame"

  # A docked bar on hover (session 15): hidden, the band stays on its edge and the fillets hang on the band; out, the bar
  # is the band grown thick and the fillets hang under it.
  scene washi hover
  bg=$(pixel 960 700)
  [ "$(pixel 960 3)" != "$bg" ] || fail "hover bar hidden: no band on the top edge"
  [ "$(pixel 960 $((T + 3)))" = "$bg" ] || fail "hover bar hidden: something drawn under the band (y $((T + 3)))"
  [ "$(pixel $((T + 1)) $((T + 1)))" != "$bg" ] || fail "hover bar hidden: no fillet on the band's left end"
  [ "$(pixel 3 $((T + 3)))" != "$bg" ] || fail "hover bar hidden: the left band does not reach the top band"
  shoot washi hover-hidden
  ( echo "move 960 0"; sleep 2.5; echo "move 960 600"; sleep 1 ) | python3 -I "$ROOT/tools/bench/wl_pointer.py" --serve &
  hp=$!; sleep 1.8
  [ "$(pixel 960 $((BARH - 3)))" != "$bg" ] || fail "hover bar out: no bar at y $((BARH - 3))"
  [ "$(pixel $((T + 1)) $((BARH + 1)))" != "$bg" ] || fail "hover bar out: no fillet under the bar's left end"
  shoot washi hover-out
  wait "$hp" || true

  scene washi floating
  window_rect; say "floating bottom bar: test window at $rect"
  set -- $rect; [ "${1:-x}" = "$T" ] && [ "${2:-x}" = "$T" ] && [ "${4:-0}" = $((SH - T - T - 8 - BARH - 8)) ] \
    || fail "floating bottom bar: the window is at $rect, not $T $T … $((SH - 2 * T - 16 - BARH))"
  close_window
fi

# ---- idle: textured and penned looks, the frame on ----
for ds in washi-paper:top kami:top kami:off; do
  d=${ds%:*}; sc=${ds#*:}
  [[ " $DECORS " == *" $d "* ]] || continue
  MOCK_ARGS="--fixed-time 12:00" QS_ENV=WAYLAND_DEBUG=client scene "$d" "$sc"
  # The bar clock's minute flip is the one idle commit the budget allows (K68): measure between two minutes.
  sleep 4; while [ "$(date +%-S)" -gt 35 ]; do sleep 1; done
  s=$(stat -c %s "$R/qs.log")
  # Documents patched meanwhile that nothing on this output shows (another output's layout and workspaces): every
  # patch re-reads the layout, and that must redraw nothing.
  sleep 3; K act mock.doc '{"doc":"runtime.layout","patch":{"outputs":{"DP-9":{"frame":{"on":true}}}}}' >/dev/null
  sleep 3; K act mock.doc '{"doc":"svc.workspaces","patch":{"outputs":{"DP-9":[]}}}' >/dev/null
  sleep 4; c=$(commits "$s")
  # Which surfaces committed, by namespace (the frame's strips must never; another surface's commit is reported).
  per=$(tail -c +"$((s + 1))" "$R/qs.log" | grep -o 'wl_surface#[0-9]*\.commit(' | sort | uniq -c | while read -r k sid; do
    sid=${sid%.commit(}
    ns=$(grep -o "get_layer_surface(new id [^,]*, $sid, [^)]*)" "$R/qs.log" | tail -1 | grep -o '"[^"]*")$' | tr -d '")')
    echo "${ns:-$sid}:$k"
  done | xargs || true)
  say "idle, $sc ($d): $c commits in 10 s ${per:+($per)}"
  [[ "$per" != *kurashi-frame* ]] || fail "idle with the frame on ($d): the frame's strips committed ($per)"
  [ "$c" = 0 ] || fail "idle ($d, $sc): $c commits from other surfaces ($per)"
done

# ---- one sheet: an untextured flat look, the docked bar's fill and the band's are the same pixel ----
scene kanso top
pb=$(pixel 3 $((BARH / 2))); pf=$(pixel 3 600)
say "kanso: bar fill at the end $pb, band $pf"
[ "$pb" = "$pf" ] || fail "the bar and the band are not one fill ($pb vs $pf)"

# ---- the shots ----
for d in $DECORS; do
  for s in off top floating nobar reserve-off; do scene "$d" "$s"; shoot "$d" "$s"; done
  if [ "$(jq -r '.patch.tokens["texture.shell"]' "$W/theme-$d.json")" = true ]; then
    scene "$d" top; grim -s 8 -g "0,$((BARH - 12)) 40x40" "$OUT/$d/seam.png"
  fi
  [[ "$d" == washi* ]] && for s in bar-bottom bar-left bar-right; do scene "$d" "$s"; shoot "$d" "$s"; done
  say "$OUT/$d/"
done
if [[ " $DECORS " == *" washi "* ]]; then
  scene washi top radius=0; shoot washi radius-0
  scene washi top radius=48; shoot washi radius-48
  scene washi top thickness=2; shoot washi thickness-2
  scene washi nobar thickness=32; shoot washi thickness-32
  scene washi top screen=16; shoot washi screen-corners
  # Following the radius: screen R, band 8, hole R − 8 (K74) — R 24 here, so the three curves read as concentric.
  scene washi top screen=24 radius=16; shoot washi screen-corners-follow
fi

# ---- memory: the frontend's PSS with the frame off and on, back-to-back pairs ----
for d in washi-paper kanso; do
  [ "$d" = washi-paper ] && [[ " $DECORS " != *" washi-paper "* ]] && continue
  # Separate frontends (each starts with the frame off or on).
  for i in $(seq "$PAIRS"); do
    scene "$d" off; sleep 6; a=$(pss_mib "$QS")
    scene "$d" top; sleep 6; b=$(pss_mib "$QS")
    say "PSS $d pair $i (two frontends): frame off $a MiB, on $b MiB (+$(awk -v a="$a" -v b="$b" 'BEGIN{printf "%.2f", b - a}') MiB)"
  done
  # One frontend, the frame turned off and on by the layout (no start-up noise; what an output's frame costs live).
  scene "$d" top; sleep 6
  for i in $(seq "$PAIRS"); do
    K act mock.doc '{"doc":"runtime.layout","patch":{"outputs":{"*":{"frame":{"on":false}}}}}' >/dev/null; sleep 5
    a=$(pss_mib "$QS")
    K act mock.doc '{"doc":"runtime.layout","patch":{"outputs":{"*":{"frame":{"on":true}}}}}' >/dev/null; sleep 5
    b=$(pss_mib "$QS")
    say "PSS $d pair $i (one frontend, toggled): frame off $a MiB, on $b MiB (+$(awk -v a="$a" -v b="$b" 'BEGIN{printf "%.2f", b - a}') MiB)"
  done
done

# ---- two outputs with different settings: the frame only on the one whose entry has it ----
if [[ " $DECORS " == *" washi "* ]]; then
  "$ROOT/tools/bench/sandbox.sh" output-add "$NAME" >/dev/null
  sleep 1
  off=$(stat -c %s "$R/qs.log")
  OUTPUTS=HEADLESS-1,HEADLESS-2 QS_ENV=WAYLAND_DEBUG=client scene washi top multi=HEADLESS-1
  n=$(surfaces "$off"); say "two outputs, frame on HEADLESS-1 only: $n kurashi-frame surfaces"
  [ "$n" = 3 ] || fail "two outputs, frame on one: $n kurashi-frame surfaces, not 3"
  grim -s 0.25 "$OUT/washi/two-outputs.png"
fi

# ---- niri (nested in the sandbox, winit): the zones (a window's tile size) and the layer list ----
NIRI=$(command -v niri || true); [ -z "$NIRI" ] && [ -x /run/current-system/sw/bin/niri ] && NIRI=/run/current-system/sw/bin/niri
if [ -n "$NIRI" ] && [[ " $DECORS " == *" washi "* ]]; then
  stop
  cat > "$W/niri.kdl" <<'KDL'
layout {
    gaps 0
    default-column-width { proportion 1.0; }
    focus-ring { off; }
    border { off; }
}
hotkey-overlay { skip-at-startup; }
prefer-no-csd
KDL
  SWAYWL=$WAYLAND_DISPLAY
  "$NIRI" --config "$W/niri.kdl" >> "$R/niri.log" 2>&1 &
  NIRIPID=$!
  for _ in $(seq 100); do ls "$R"/niri.*.sock >/dev/null 2>&1 && break; sleep 0.1; done
  export NIRI_SOCKET; NIRI_SOCKET=$(ls "$R"/niri.*.sock | head -1)
  NWL=$(ls "$R" | grep -E '^wayland-[0-9]+$' | grep -v "^$SWAYWL\$" | head -1)
  NO=$("$NIRI" msg -j outputs | jq -r 'keys[0]')
  NW=$("$NIRI" msg -j outputs | jq -r '.[].logical.width'); NH=$("$NIRI" msg -j outputs | jq -r '.[].logical.height')
  say "niri: output $NO ${NW}x${NH} on $NWL"
  for s in top reserve-off off; do
    WAYLAND_DISPLAY=$NWL OUTPUTS=$NO scene washi "$s"
    n=$("$NIRI" msg -j layers | jq '[.[] | select(.namespace == "kurashi-frame")] | length')
    WAYLAND_DISPLAY=$NWL env -u KURASHI_SOCKET qs -p "$W/win.qml" >> "$R/win.log" 2>&1 &
    WIN=$!
    sleep 2
    size=$("$NIRI" msg -j windows | jq -r '.[0].layout.window_size | "\(.[0]) \(.[1])"')
    say "niri $s: $n kurashi-frame layers, window $size"
    case $s in
      top) want="$((NW - 16)) $((NH - BARH - 8))"; [ "$n" = 3 ] || fail "niri: frame on made $n layers, not 3" ;;
      reserve-off) want="$NW $((NH - BARH))"; [ "$n" = 3 ] || fail "niri: frame on (reserve off) made $n layers, not 3" ;;
      off) want="$NW $((NH - BARH))"; [ "$n" = 0 ] || fail "niri: frame off made $n layers, not 0" ;;
    esac
    [ "$size" = "$want" ] || fail "niri $s: the window is $size, not $want"
    grim -s 0.5 -o HEADLESS-1 "$OUT/washi/niri-$s.png"
    close_window
  done
  stop
  kill "$NIRIPID" 2>/dev/null || true; wait "$NIRIPID" 2>/dev/null || true
else
  say "niri: not on PATH, the zones were checked on sway only"
fi

stop
if grep -E 'ERROR|qml:.*(Error|error)|TypeError|ReferenceError|is not a type|Cannot assign|Unable to assign' "$R/qs.log" \
    | grep -v 'Unable to assign \[undefined\]' >/dev/null; then
  grep -E 'Error|error|Cannot assign|Unable to assign' "$R/qs.log" | sort | uniq -c | head -20 >&2
  fail "QML errors (see $R/qs.log)"
fi
[ "$FAILS" = 0 ] || die "$FAILS checks failed"
say "ok ($OUT)"
