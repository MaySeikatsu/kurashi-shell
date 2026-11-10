#!/usr/bin/env bash
# Every change of colour fades (I472 step 1, K117; core/ColorBlend.qml), on the REAL kurashid, invisibly (headless sway):
#   1. `theme.motion.blend_colors` on (the default), dark → light: the bar is seen on a colour that is neither the dark
#      ground nor the light one on the way, and ends on the light one.
#   2. off: the change is a cut: no sample between the two grounds.
#   3. no QML error.
#   nix develop -c frontend/test-colour-blend.sh [sandbox-name]
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
NAME=${1:-${KURASHI_SB_PREFIX:-}s27-blend-test}
BIN=${KURASHI_BIN_DIR:-${CARGO_TARGET_DIR:-$ROOT/target}/debug}
fail() { echo "test-colour-blend: FAIL: $*" >&2; exit 1; }

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
# (the default motion profile: the fade is off under `none`. No texture, so the bar's ground is one flat colour.)
conf() { printf '[idle]\nenabled = false\n[theme.texture]\nkind = "none"\n[theme.colors]\nscheme = "%s"\n[theme.motion]\nblend_colors = %s\n' "$1" "$2" > "$CONF"; }
conf dark true

env DBUS_SYSTEM_BUS_ADDRESS="unix:path=$R/no-system-bus" PULSE_SERVER="unix:$R/no-pulse/native" PULSE_RUNTIME_PATH="$R/no-pulse" \
  "$W/kurashid" >> "$R/kurashid.log" 2>&1 &
pids+=($!)
wait_until 15 K ping || fail "kurashid did not answer"
: > "$R/qs.log"
qs -p "$ROOT/frontend" >> "$R/qs.log" 2>&1 &
pids+=($!)
wait_frontend "$R/qs.log" || fail "the frontend did not load"
sleep 1

# The bar's ground: a pixel in the bar's strip, clear of every module (a quarter of the way along, 3 px down).
W_OUT=$(swaymsg -t get_outputs | python3 -c 'import json,sys; print(json.load(sys.stdin)[0]["rect"]["width"])')
PX="$(( W_OUT / 4 )),3 1x1"
px() { grim -g "$PX" -t ppm - | tail -c 3 | od -An -tx1 | tr -d ' \n'; }
# Samples the pixel for about 2.5 s as fast as grim goes, after `$@` ran; prints the distinct colours in order seen.
watch_change() {
  "$@"
  local seen="" c
  local end=$(( $(now_ms) + 2500 ))
  while [ "$(now_ms)" -lt "$end" ]; do
    c=$(px)
    case " $seen " in *" $c "*) ;; *) seen="$seen $c" ;; esac
  done
  echo "$seen"
}
DARK=$(px)
SEEN=$(watch_change conf light true)
LIGHT=$(px)
[ "$DARK" != "$LIGHT" ] || fail "the scheme change did not change the bar's ground ($DARK)"
N=$(echo "$SEEN" | wc -w)
[ "$N" -ge 3 ] || fail "blend on: the bar went from $DARK to $LIGHT with nothing between (seen:$SEEN)"
echo "ok: with the blend on the bar passes $(( N - 2 )) colours between $DARK and $LIGHT"

SEEN=$(watch_change conf dark false)
BACK=$(px)
[ "$BACK" = "$DARK" ] || fail "blend off: the bar did not return to $DARK (is $BACK)"
for c in $SEEN; do
  [ "$c" = "$DARK" ] || [ "$c" = "$LIGHT" ] || fail "blend off: the bar was seen on $c, between $LIGHT and $DARK (seen:$SEEN)"
done
echo "ok: with the blend off the change is a cut"

if grep -E "qml|QML" "$R/qs.log" | grep -iE "error|TypeError|ReferenceError|Binding loop" | grep -v desktopentry | head -3 | grep -q .; then
  grep -E "qml|QML" "$R/qs.log" | grep -iE "error|TypeError|ReferenceError|Binding loop" | head -5 >&2
  fail "the frontend logged a QML error"
fi
echo "ok: the frontend logs no QML error"
echo "test-colour-blend: all checks passed"
