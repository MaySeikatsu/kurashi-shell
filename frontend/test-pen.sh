#!/usr/bin/env bash
# The pen (K62, docs/ux/texture.md "The pen"), headless, against the real kurashid:
#   - the committed pen_text.frag.qsb is the build of its source;
#   - pen off is pixel-identical to main's frontend (bar and quick card, washi and sekai): `git archive main frontend`;
#   - shots of each line style and each outline modifier alone at 0.6 on the quick card and the bar (line chrome, light
#     and dark; flat chrome, which has no outline for the pen to draw), the text modifiers on the card, kami with its
#     own pen (light and dark);
#   - idle with the pen on (a rough line, every outline and text modifier): no Wayland commit in 10 s, bar and quick
#     card; the frontend's PSS with the text layers off and on (printed);
#   - no QML or shader error in the frontend's log.
# Shots: frontend/shots/pen/ (evidence to look at: they must look like a fountain pen, a dotted line, a hand).
#   KURASHI_BIN_DIR=<dir with kurashid, kurashi> timeout 1200 nix develop -c frontend/test-pen.sh [sandbox-name]
#   Machine B: export KURASHI_RENDER_NODE=/dev/dri/renderD129 first. PEN_BASE=<git ref> picks the pen-off
#   reference (default: where this branch left main).
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
NAME=${1:-w32-pen}
BIN=${KURASHI_BIN_DIR:-${CARGO_TARGET_DIR:-$ROOT/target}/debug}
BASE=${PEN_BASE:-$(git -C "$ROOT" merge-base HEAD main)}
OUT=$ROOT/frontend/shots/pen
TMP=$(mktemp -d)
mkdir -p "$OUT"
FAILS=0
fail() { echo "test-pen: FAIL $*" >&2; FAILS=$((FAILS + 1)); }
say() { echo "test-pen: $*"; }

# ---- the shader is its source's build ----
qsb --glsl "100es,120,150" --hlsl 50 --msl 12 -o "$TMP/pen_text.frag.qsb" "$ROOT/frontend/shaders/pen_text.frag" \
  || fail "pen_text.frag does not compile with qsb"
cmp -s "$TMP/pen_text.frag.qsb" "$ROOT/frontend/shaders/pen_text.frag.qsb" \
  || fail "pen_text.frag.qsb is not the build of pen_text.frag (run: just shaders)"

# ---- the reference frontend (pen off must draw exactly what it draws) ----
mkdir -p "$TMP/base"
git -C "$ROOT" archive "$BASE" frontend | tar -x -C "$TMP/base"

eval "$("$ROOT/tools/bench/sandbox.sh" start "$NAME")"
R=$XDG_RUNTIME_DIR
W=$R/work
mkdir -p "$W" "$R/kurashi"
cp "$BIN/kurashid" "$BIN/kurashi" "$W/"
DMN=""; QS=""
stop_qs() { [ -n "$QS" ] && { kill "$QS" 2>/dev/null || true; wait "$QS" 2>/dev/null || true; }; QS=""; }
cleanup() {
  stop_qs
  [ -n "$DMN" ] && { kill "$DMN" 2>/dev/null || true; wait "$DMN" 2>/dev/null || true; }
  "$ROOT/tools/bench/sandbox.sh" stop "$NAME" >/dev/null || true
  rm -rf "$TMP"
}
trap cleanup EXIT

rm -rf "$R/xdg"
export XDG_CONFIG_HOME=$R/xdg/config XDG_STATE_HOME=$R/xdg/state \
       XDG_DATA_HOME=$R/xdg/data XDG_CACHE_HOME=$R/xdg/cache KURASHI_DATA_DIR=$ROOT LC_ALL=C.UTF-8
mkdir -p "$XDG_CONFIG_HOME/kurashi" "$XDG_STATE_HOME" "$XDG_DATA_HOME" "$XDG_CACHE_HOME"
printf 'theme.style = "washi"\n' > "$XDG_CONFIG_HOME/kurashi/config.toml"
K() { timeout 10 "$W/kurashi" "$@"; }

: > "$R/server.log"; : > "$R/qs.log"
env DBUS_SYSTEM_BUS_ADDRESS="unix:path=$R/no-system-bus" \
    PULSE_SERVER="unix:$R/no-pulse/native" PULSE_RUNTIME_PATH="$R/no-pulse" \
    "$W/kurashid" >> "$R/server.log" 2>&1 &
DMN=$!
for _ in $(seq 100); do [ -S "$KURASHI_SOCKET" ] && K ping >/dev/null 2>&1 && break; sleep 0.1; done
K ping >/dev/null 2>&1 || { echo "test-pen: kurashid did not come up (see $R/server.log)" >&2; exit 1; }
swaymsg output '*' bg '#8fb8c8' solid_color >/dev/null 2>&1 || true

start_qs() { # start_qs <frontend dir> [extra env]: the frontend, once it said hello
  local before; before=$(grep -c 'hello.*frontend' "$R/server.log" || true)
  env -u KURASHI_SOCKET ${2:-} qs -p "$1" >> "$R/qs.log" 2>&1 &
  QS=$!
  for _ in $(seq 100); do
    [ "$(grep -c 'hello.*frontend' "$R/server.log" || true)" -gt "$before" ] && break; sleep 0.1
  done
  sleep 3
}
# Settle: the theme patch reaches the frontend and every canvas has painted.
set_pen() { K reset theme.pen >/dev/null 2>&1 || true; [ $# -gt 0 ] && { K set "$@" >/dev/null || fail "set $* refused"; }; sleep 1.2; }
QUICK="1080,34 400x570"
BAR="0,0 1400x34"
shoot() { # shoot <name>: the bar (left half, 2×) and the quick card (2×)
  grim -s 2 -g "$BAR" "$OUT/$1-bar.png"
  K act quick.toggle >/dev/null; sleep 1.5
  grim -s 2 -g "$QUICK" "$OUT/$1-quick.png"
  K act quick.toggle >/dev/null; sleep 0.9
  say "$OUT/$1-{bar,quick}.png"
}
# Two minutes never straddle one comparison: wait while the clock is about to tick.
quiet_minute() { while [ "$(date +%-S)" -gt 35 ]; do sleep 1; done; }

# ---- pen off = main, pixel for pixel ----
for style in washi sekai; do
  K set theme.style="$style" >/dev/null
  set_pen
  for attempt in 1 2; do
    quiet_minute
    start_qs "$TMP/base/frontend"
    grim -t ppm "$TMP/base-bar.ppm"
    K act quick.toggle >/dev/null; sleep 1.5; grim -t ppm "$TMP/base-quick.ppm"; K act quick.toggle >/dev/null; sleep 0.9
    stop_qs
    start_qs "$ROOT/frontend"
    grim -t ppm "$TMP/new-bar.ppm"
    K act quick.toggle >/dev/null; sleep 1.5; grim -t ppm "$TMP/new-quick.ppm"; K act quick.toggle >/dev/null; sleep 0.9
    stop_qs
    if cmp -s "$TMP/base-bar.ppm" "$TMP/new-bar.ppm" && cmp -s "$TMP/base-quick.ppm" "$TMP/new-quick.ppm"; then
      say "pen off, $style: pixel-identical to $BASE (bar, quick card)"; break
    fi
    [ "$attempt" = 2 ] && fail "pen off, $style: the screen differs from $BASE's frontend"
  done
done

# ---- the shots ----
start_qs "$ROOT/frontend"
K set theme.style=washi >/dev/null
for line in solid dotted dashed broken rough; do
  if [ "$line" = solid ]; then set_pen; else set_pen theme.pen.line="$line"; fi
  shoot "line-$line"
done
for m in pressure breaks fade wobble; do set_pen theme.pen.$m=0.6; shoot "mod-$m"; done
set_pen theme.pen.line=rough theme.pen.pressure=0.6 theme.pen.breaks=0.6 theme.pen.fade=0.6 theme.pen.wobble=0.6
shoot "all-rough"
for m in pressure breaks fade wobble; do set_pen theme.pen.text_$m=0.6; shoot "text-$m"; done
set_pen theme.pen.text_pressure=0.6 theme.pen.text_breaks=0.6 theme.pen.text_fade=0.6 theme.pen.text_wobble=0.6
shoot "text-all"
K set theme.colors.scheme=dark >/dev/null
for line in dotted dashed broken rough; do
  set_pen theme.pen.line="$line" theme.pen.pressure=0.6 theme.pen.fade=0.6
  shoot "dark-$line"
done
set_pen theme.pen.line=solid theme.pen.pressure=0.6 theme.pen.breaks=0.6 theme.pen.fade=0.6 theme.pen.wobble=0.6 \
  theme.pen.text_pressure=0.6 theme.pen.text_breaks=0.6 theme.pen.text_fade=0.6 theme.pen.text_wobble=0.6
shoot "dark-all"
# Flat chrome draws no outline (only hairlines where a block asks for one), so the line has nothing to draw; the text
# modifiers still apply.
K set theme.colors.scheme=light theme.chrome=flat >/dev/null
set_pen theme.pen.line=dotted theme.pen.text_pressure=0.6 theme.pen.text_fade=0.6
shoot "flat-dotted-text"
K reset theme.chrome >/dev/null
# Kami with its own pen (the look's pressure 0.35), light and dark; and kami's pen with a line style.
K set theme.style=kami >/dev/null
set_pen; shoot "kami"
set_pen theme.pen.line=rough; shoot "kami-rough"
K set theme.colors.scheme=dark >/dev/null
set_pen; shoot "kami-dark"
stop_qs

# ---- idle with the pen on, and the text layers' memory ----
pss_mib() { awk '/^Pss:/{s+=$2} END{printf "%.2f", s/1024}' "/proc/$1/smaps_rollup"; }
commits() { tail -c +"$(( $1 + 1 ))" "$R/qs.log" | grep -c 'wl_surface#[0-9]*\.commit(' || true; }
K set theme.style=washi theme.colors.scheme=light >/dev/null
set_pen theme.pen.line=rough theme.pen.pressure=0.6 theme.pen.breaks=0.6 theme.pen.fade=0.6 theme.pen.wobble=0.6
start_qs "$ROOT/frontend" "WAYLAND_DEBUG=1"
K act quick.toggle >/dev/null; sleep 3
pss_off=$(pss_mib "$QS")
set_pen theme.pen.line=rough theme.pen.pressure=0.6 theme.pen.breaks=0.6 theme.pen.fade=0.6 theme.pen.wobble=0.6 \
  theme.pen.text_pressure=0.6 theme.pen.text_breaks=0.6 theme.pen.text_fade=0.6 theme.pen.text_wobble=0.6
sleep 3
pss_on=$(pss_mib "$QS")
say "frontend PSS with the quick card open: text layers off ${pss_off} MiB, on ${pss_on} MiB"
for what in "quick card open" "bar only"; do
  [ "$what" = "bar only" ] && { K act quick.toggle >/dev/null; sleep 3; }
  quiet_minute
  s=$(stat -c %s "$R/qs.log"); sleep 10; c=$(commits "$s")
  say "idle, pen on, $what: $c commits in 10 s"
  [ "$c" = 0 ] || fail "idle with the pen on ($what): $c Wayland commits in 10 s"
done
stop_qs

if grep -E 'qml:.*(Error|error)|TypeError|ReferenceError|is not a type|Failed to compile shader|graphics pipeline' "$R/qs.log" \
    | grep -v 'Unable to assign \[undefined\]' >/dev/null; then
  grep -E 'Error|error|shader|pipeline' "$R/qs.log" | sort | uniq -c | head -20 >&2
  fail "QML or shader errors (see $R/qs.log)"
fi
[ "$FAILS" = 0 ] || { echo "test-pen: $FAILS failure(s)" >&2; exit 1; }
say "ok ($OUT)"
