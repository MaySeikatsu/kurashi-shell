#!/usr/bin/env bash
# The pen (K62, docs/ux/texture.md "The pen"), headless, against the real kurashid:
#   - the committed pen_text.frag.qsb is the build of its source;
#   - pen off draws what main's frontend draws (desk with bar and toasts, quick card, island, sidebar; washi, sekai; `git archive <base> frontend`),
#     pixel for pixel up to the ±1 level of glyph rasterisation that two runs of the same frontend differ by;
#   - shots of each line style and each outline modifier alone at 0.6 on the quick card and the bar (line chrome, light
#     and dark; flat chrome, which has no outline for the pen to draw), the text modifiers on the card, kami with its
#     own pen (light and dark);
#   - phase 2, the surfaces' own outlines: each line style on the island open and closed, the bar's rule, the toasts and
#     the right sidebar (line chrome; dark; flat; the joined island under sekai; kami) -> shots/pen/surfaces/;
#   - idle with the pen on (a rough line, every outline and text modifier): no Wayland commit in 10 s, quick card open,
#     bar only, island open; the frontend's PSS with the text layers off and on (printed);
#   - no QML or shader error in the frontend's log.
# Shots: frontend/shots/pen/ (evidence to look at: they must look like a fountain pen, a dotted line, a hand).
#   KURASHI_BIN_DIR=<dir with kurashid, kurashi> timeout 1200 nix develop -c frontend/test-pen.sh [sandbox-name]
#   Machine B: export KURASHI_RENDER_NODE=/dev/dri/renderD129 first. PEN_BASE=<git ref> picks the pen-off
#   reference (default: where this branch left main). PEN_ONLY=identity stops after that check; PEN_KEEP=<dir> keeps
#   its PPMs; PEN_NEW=<frontend dir> compares another frontend (PEN_NEW=<base export> is the noise control).
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
  rm -rf "$TMP"
  # Last: once the sandbox is gone, a command started from this shell can no longer join its network namespace.
  "$ROOT/tools/bench/sandbox.sh" stop "$NAME" >/dev/null || true
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
# ppmdiff <a> <b> <label>: exit 0 when no channel of any pixel differs by more than 1. Two runs of the SAME frontend
# differ by exactly that (measured: main against itself, 40–100 text pixels off by one level, the GPU's glyph
# rasterisation), so ±1 is noise; a changed outline or fill differs by far more. Prints what differs.
cat > "$TMP/ppmdiff.py" <<'PY'
import sys


def read(path):
    data = open(path, "rb").read()
    fields, i = [], 0
    while len(fields) < 4:
        while data[i:i + 1].isspace():
            i += 1
        j = i
        while not data[j:j + 1].isspace():
            j += 1
        fields.append(data[i:j])
        i = j
    return int(fields[1]), int(fields[2]), data[i + 1:]


wa, ha, a = read(sys.argv[1])
wb, hb, b = read(sys.argv[2])
if (wa, ha) != (wb, hb):
    print(f"test-pen: {sys.argv[3]}: sizes differ {wa}x{ha} vs {wb}x{hb}")
    sys.exit(1)
noise, n, x0, y0, x1, y1 = 0, 0, wa, ha, -1, -1
row = wa * 3
for y in range(ha):
    ra, rb = a[y * row:(y + 1) * row], b[y * row:(y + 1) * row]
    if ra == rb:
        continue
    for x in range(wa):
        pa, pb = ra[x * 3:x * 3 + 3], rb[x * 3:x * 3 + 3]
        if pa == pb:
            continue
        if max(abs(pa[k] - pb[k]) for k in range(3)) <= 1:
            noise += 1
            continue
        n += 1
        x0, y0, x1, y1 = min(x0, x), min(y0, y), max(x1, x), max(y1, y)
if n:
    print(f"test-pen: {sys.argv[3]}: {n} pixels differ in x {x0}..{x1}, y {y0}..{y1} ({noise} more by one level)")
    sys.exit(1)
print(f"test-pen: {sys.argv[3]}: identical ({noise} pixels one level off: rendering noise)")
PY
# Two critical notifications (they stay): toasts, the island's notification view and the sidebar's list all show cards.
notify-send -u critical "Standup" "14:00 room 3" >/dev/null 2>&1 || fail "notify-send failed"
notify-send -u critical "Battery low" "12 % left" >/dev/null 2>&1 || fail "notify-send failed"
sleep 1
cap() { # cap <prefix>: the desk with the bar and the toasts, the quick card, the open island, the right sidebar
  grim -t ppm "$TMP/$1-bar.ppm"
  K act quick.toggle >/dev/null; sleep 1.5; grim -t ppm "$TMP/$1-quick.ppm"; K act quick.toggle >/dev/null; sleep 0.9
  K act island.expand >/dev/null; sleep 1.8; grim -t ppm "$TMP/$1-island.ppm"; K act island.expand >/dev/null; sleep 1.2
  K act sidebar.toggle '{"side":"right"}' >/dev/null; sleep 1.6; grim -t ppm "$TMP/$1-sidebar.ppm"
  K act sidebar.toggle '{"side":"right"}' >/dev/null; sleep 1.2
}
for style in washi sekai; do
  K set theme.style="$style" >/dev/null
  set_pen
  for attempt in 1 2; do
    quiet_minute
    start_qs "$TMP/base/frontend"; cap base; stop_qs
    start_qs "${PEN_NEW:-$ROOT/frontend}"; cap new; stop_qs
    same=1
    for part in bar quick island sidebar; do
      python3 -I "$TMP/ppmdiff.py" "$TMP/base-$part.ppm" "$TMP/new-$part.ppm" "pen off, $style, $part" || same=0
    done
    [ -n "${PEN_KEEP:-}" ] && cp "$TMP"/base-*.ppm "$TMP"/new-*.ppm "$PEN_KEEP/"
    [ "$same" = 1 ] && break
    [ "$attempt" = 2 ] && fail "pen off, $style: the screen differs from $BASE's frontend"
  done
done

[ "${PEN_ONLY:-}" = identity ] && { [ "$FAILS" = 0 ] && exit 0 || exit 1; }

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

# ---- phase 2: the surfaces' own outlines (Stage card, island shape, the bar's rule, sidebar, toasts) ----
SURF=$OUT/surfaces
mkdir -p "$SURF"
surf() { # surf <name>: the island open and closed, the bar, the toasts, the right sidebar
  K act island.expand >/dev/null; sleep 1.8
  grim -s 2 -g "1040,0 480x470" "$SURF/$1-island-open.png"
  K act island.expand >/dev/null; sleep 1.2
  grim -s 2 -g "1040,0 480x44" "$SURF/$1-island-closed.png"
  grim -g "0,0 2560x40" "$SURF/$1-bar.png"
  grim -s 2 -g "2180,28 380x200" "$SURF/$1-toasts.png"
  K act sidebar.toggle '{"side":"right"}' >/dev/null; sleep 1.6
  grim -g "1960,0 600x900" "$SURF/$1-sidebar.png"
  K act sidebar.toggle '{"side":"right"}' >/dev/null; sleep 1.2
  say "$SURF/$1-{island-open,island-closed,bar,toasts,sidebar}.png"
}
K set theme.style=washi theme.colors.scheme=light >/dev/null
for line in solid dotted dashed broken rough; do
  if [ "$line" = solid ]; then set_pen; else set_pen theme.pen.line="$line"; fi
  surf "line-$line"
done
set_pen theme.pen.line=rough theme.pen.pressure=0.6 theme.pen.breaks=0.6 theme.pen.fade=0.6 theme.pen.wobble=0.6
surf "all-rough"
set_pen theme.pen.pressure=0.6 theme.pen.breaks=0.6 theme.pen.fade=0.6 theme.pen.wobble=0.6
surf "all-solid"
K set theme.colors.scheme=dark >/dev/null
set_pen theme.pen.line=dashed theme.pen.pressure=0.6; surf "dark-dashed"
K set theme.colors.scheme=light theme.chrome=flat >/dev/null
set_pen theme.pen.line=dashed; surf "flat-dashed"
K reset theme.chrome >/dev/null
# The joined island (keycap chrome: head, neck and body in one line).
K set theme.style=sekai >/dev/null
set_pen theme.pen.line=broken; surf "sekai-broken"
set_pen theme.pen.line=rough; surf "sekai-rough"
K set theme.style=kami >/dev/null
set_pen; surf "kami"
K set theme.colors.scheme=dark >/dev/null
set_pen; surf "kami-dark"
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
for what in "quick card open" "bar only" "island open"; do
  [ "$what" = "bar only" ] && { K act quick.toggle >/dev/null; sleep 3; }
  [ "$what" = "island open" ] && { K act island.expand >/dev/null; sleep 3; }
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
