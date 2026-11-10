#!/usr/bin/env bash
# The Glow chrome glows (B79; components/SoftShadow.qml's ring, shaders/glow_ring.frag), on the REAL kurashid, invisibly
# (headless sway):
#   1. under `theme.chrome = glow` the theme says the soft shadow is light (`chrome.soft_glow`), and the bar's band
#      holds light: many pixels tinted by the accent that are neither the outline nor the ground, far more than under
#      `line`, in dark and in light;
#   2. on a framed output the bar's rule is unbroken under the groups; the frame's edge throws light over the desktop
#      (falling with the distance) under the Glow chrome with Automatic and under any chrome with `frame_outline =
#      glow`, and none with `on`;
#   3. idle: 0 frames in 3 s (the ring is static); no QML error.
#   nix develop -c frontend/test-glow.sh [sandbox-name]
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
NAME=${1:-${KURASHI_SB_PREFIX:-}s27-glow-test}
BIN=${KURASHI_BIN_DIR:-${CARGO_TARGET_DIR:-$ROOT/target}/debug}
fail() { echo "test-glow: FAIL: $*" >&2; exit 1; }

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
tint() {
  grim -g "0,0 ${W_OUT}x48" -t ppm "$R/band.ppm"
  python3 -I - "$R/band.ppm" <<'PY'
import sys
d = open(sys.argv[1], 'rb').read()
p = d.split(b'\n', 3)
w, h = map(int, p[1].split()); px = p[3]
soft = strong = 0
for i in range(0, w * h * 3, 3):
    r, g, b = px[i], px[i + 1], px[i + 2]
    k = r - max(g, b)
    if k > 90: strong += 1
    elif k > 12: soft += 1
print(soft, strong)
PY
}
for scheme in dark light; do
  conf glow "$scheme"; wait_until 10 sh -c '[ "$('"$W/kurashi"' get theme.chrome | cut -d\" -f2)" = glow ]' || true
  sleep 1.5; wait_settled 4 0.5
  [ "$(token chrome.soft_glow)" = true ] || fail "$scheme: the theme does not say chrome.soft_glow under the Glow chrome ($(token chrome.soft_glow))"
  read -r gsoft gstrong <<< "$(tint)"
  conf line "$scheme"; sleep 1.5; wait_settled 4 0.5
  [ "$(token chrome.soft_glow)" = false ] || fail "$scheme: chrome.soft_glow is on under the Line chrome"
  read -r lsoft lstrong <<< "$(tint)"
  [ "$gsoft" -ge 1500 ] && [ "$gsoft" -ge $(( lsoft * 4 + 1 )) ] \
    || fail "$scheme: the bar holds no light under Glow ($gsoft tinted px; $lsoft under Line)"
  echo "ok: $scheme: $gsoft px of light on the bar under Glow ($gstrong of outline), $lsoft under Line"
done

# 2. A framed output (the user's layout: the frame on, groups on the bar's strip): the bar's rule is one unbroken line,
#    also under the groups (no gap where a group stands), and the frame's edge throws light over the desktop that falls
#    with the distance.
# framed <chrome> <frame_outline>: the framed output under that chrome and choice, settled.
framed() {
  printf '[idle]\nenabled = false\n[layout.frame]\nenabled = true\nreserve = true\nthickness = 10\n[theme]\nchrome = "%s"\nframe_outline = "%s"\n[theme.texture]\nkind = "none"\n[theme.colors]\nscheme = "light"\n' "$1" "$2" > "$CONF"
  sleep 2; wait_settled 5 0.5
}
# frame_light <want: lit|dark> <what>: the rule is unbroken, and the light over the desktop under it is there (falling
# with the distance) or not.
frame_light() {
  grim -g "0,0 ${W_OUT}x90" -t ppm "$R/band.ppm"
  python3 -I - "$R/band.ppm" "$1" "$2" <<'PY' || fail "framed, $2: the bar's rule is broken, or the frame's light is not as it should be ($1)"
import sys
d = open(sys.argv[1], 'rb').read()
want, what = sys.argv[2], sys.argv[3]
p = d.split(b'\n', 3)
w, h = map(int, p[1].split()); px = p[3]
def k(x, y):
    i = (y * w + x) * 3
    return px[i] - max(px[i + 1], px[i + 2])
x0, x1 = 80, w - 80          # clear of the frame's corners
def off_paper(x, y):
    i = (y * w + x) * 3
    return min(px[i], px[i + 1], px[i + 2]) < 200
# The rule: the first row down the band that is no longer the bar's paper anywhere (the line; under it the desktop).
span = x1 - x0
y = n = None
for yy in range(12, h - 20):
    c = sum(1 for x in range(x0, x1) if off_paper(x, yy))
    if c >= span * 0.5:
        y, n = yy, c
        break
if y is None:
    sys.exit(f"{what}: no rule found under the bar")
if n < span * 0.97:
    sys.exit(f"{what}: the rule at y={y} covers {n} of {span} px: broken")
def mean(yy): return sum(max(0, k(x, yy)) for x in range(x0, x1)) / span
near, far = mean(y + 4), mean(y + 14)
print(f"ok: framed, {what}: the rule at y={y} is unbroken; the light over the desktop is {near:.1f} at 4 px and {far:.1f} at 14 px")
if want == "lit": sys.exit(0 if near > 4 and near > far * 1.5 else 1)
sys.exit(0 if near < 2 else 1)
PY
}
# The Glow chrome: Automatic lights the frame; On keeps the line without its light. The Lines chrome: Glow lights it.
framed glow auto; frame_light lit "Glow chrome, Automatic"
framed glow on; frame_light dark "Glow chrome, On (the line alone)"
framed line glow; frame_light lit "Lines chrome, frame outline Glow"
framed line on; frame_light dark "Lines chrome, On"

# 3. idle and errors
wait_settled 3 0.6
commits() { grep -c 'wl_surface#[0-9]*\.commit(' "$R/qs.log" || true; }
c0=$(commits); sleep 3
idle=$(( $(commits) - c0 ))
[ "$idle" = 0 ] || fail "idle: the shell committed $idle frames in 3 s under the Glow chrome"
echo "ok: idle, 0 frames in 3 s under the Glow chrome"
if grep -E "qml|QML" "$R/qs.log" | grep -iE "error|TypeError|ReferenceError|Binding loop" | grep -v desktopentry | head -3 | grep -q .; then
  grep -E "qml|QML" "$R/qs.log" | grep -iE "error|TypeError|ReferenceError|Binding loop" | head -5 >&2
  fail "the frontend logged a QML error"
fi
echo "ok: the frontend logs no QML error"
echo "test-glow: all checks passed"
