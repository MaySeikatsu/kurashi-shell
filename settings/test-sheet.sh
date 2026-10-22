#!/usr/bin/env bash
# Settings as a sheet (K63, docs/ux/settings.md "Settings as a sheet"), in a headless sway sandbox with an isolated kurashid
# and the shell's bar running; never touches the real session.
#   settings/test-sheet.sh                        → exit 0, settings/shots/sheet/*.png and settings/shots/appearance/w32-*.png
#   KURASHI_BIN_DIR=<dir> settings/test-sheet.sh  → kurashid + kurashi from <dir>; no cargo build
# Checks: the sheet is a layer surface (layer-shell requests in the app's Wayland log: namespace kurashi-settings, the
# Overlay layer, all four anchors, exclusive keyboard, no exclusive zone) on the focused output, centred on it at 1040 × 740
# (the app's own geometry and the screenshot: the desktop around it dimmed by the scrim); 0 frames while open and still;
# a deep link through the daemon (`kurashi settings <key>`) jumps the open sheet; a live switch to the window and back
# keeps the page; Esc on an open dropdown closes the dropdown only, Esc on a slider's preview puts it back only, the next
# Esc closes the sheet (the process ends); a click on the backdrop closes it; the close button closes it.
# Shots: the sheet over the desktop with the bar under the styles kami (line chrome; light and dark), sekai (keycap) and
# aqua (soft), and the wave 32 rows (K61, K62) in the sheet: the spotlight on the Light dial, the light colours, the brush
# card, the wallpaper's own material cards, the pen section.
set -euo pipefail
cd "$(dirname "$0")/.."
ROOT=$PWD
if ! command -v qs >/dev/null || ! command -v sway >/dev/null; then
  exec nix develop -c "$0" "$@"
fi
BIN=$(mktemp -d)
if [ -n "${KURASHI_BIN_DIR:-}" ]; then
  cp "$KURASHI_BIN_DIR/kurashid" "$KURASHI_BIN_DIR/kurashi" "$BIN/"
else
  export CARGO_TARGET_DIR=${CARGO_TARGET_DIR:-$HOME/.cache/kurashi-agents-target}
  cargo build -q -p kurashid -p kurashi
  cp "$CARGO_TARGET_DIR/debug/kurashid" "$CARGO_TARGET_DIR/debug/kurashi" "$BIN/"
fi
NAME=${KURASHI_SB_NAME:-setsheet-$$}
envfile=$(mktemp)
tools/bench/sandbox.sh start "$NAME" > "$envfile"
# shellcheck disable=SC1090
. "$envfile"; rm -f "$envfile"
R=$XDG_RUNTIME_DIR
pids=()
qs_pid=""
cleanup() {
  rm -rf "$BIN"
  for p in "${pids[@]}"; do kill "$p" 2>/dev/null || true; done
  tools/bench/sandbox.sh stop "$NAME" >/dev/null || true
}
trap cleanup EXIT
fail() { echo "FAIL: $*"; exit 1; }

OUT=settings/shots/sheet
W32=settings/shots/appearance
mkdir -p "$R/cfg/kurashi" "$R/state" "$R/data" "$R/cache" "$OUT" "$W32"
export XDG_CONFIG_HOME=$R/cfg XDG_STATE_HOME=$R/state XDG_DATA_HOME=$R/data XDG_CACHE_HOME=$R/cache
export KURASHI_DATA_DIR=$ROOT
# qs and kurashi from the daemon's PATH: `settings.open` probes and starts the app with them.
export PATH=$BIN:$PATH
cat > "$R/cfg/kurashi/config.toml" <<'T'
schema_version = 2
[theme]
style = "kami"
[theme.colors]
scheme = "light"
[settings]
window = "sheet"
T
"$BIN/kurashid" > "$R/kurashid.log" 2>&1 & pids+=("$!")
for _ in $(seq 50); do [ -S "$KURASHI_SOCKET" ] && break; sleep 0.1; done
[ -S "$KURASHI_SOCKET" ] || { cat "$R/kurashid.log"; fail "kurashid did not start"; }
K() { "$BIN/kurashi" "$@"; }
apply() { K raw "{\"t\":\"apply\",\"id\":\"a\",\"ops\":$1}" | grep -q applied || fail "apply refused: $1"; }
Q() { qs -p settings ipc call settings "$@"; }
# A desktop to dim: a plain colour, the bar on top of it.
swaymsg output '*' bg '#7f9fae' solid_color >/dev/null
env -u KURASHI_SOCKET qs -p "$ROOT/frontend" > "$R/frontend.log" 2>&1 & pids+=("$!")
sleep 3

# The app with its Wayland requests logged (the layer-shell check reads them).
start_qs() {   # [deep link key]
  env -u KURASHI_SOCKET WAYLAND_DEBUG=client KURASHI_SETTINGS_KEY="${1:-}" qs -p settings >> "$R/settings.log" 2>&1 &
  qs_pid=$!; pids+=("$qs_pid")
  for _ in $(seq 100); do Q current >/dev/null 2>&1 && break; sleep 0.2; done
  Q current >/dev/null 2>&1 || { tail -20 "$R/settings.log"; fail "settings did not start"; }
  for _ in $(seq 50); do [[ "$(Q host)" == sheet* ]] && break; sleep 0.2; done
  sleep 1
}
# The process ends within 3 s, or the test fails with $1.
gone() { for _ in $(seq 30); do kill -0 "$qs_pid" 2>/dev/null || return 0; sleep 0.1; done; fail "$1"; }
alive() { sleep 0.8; kill -0 "$qs_pid" 2>/dev/null || fail "$1"; }
# The sheet's rectangle: "sheet x,y WxH on OUTPUT SWxSH".
geom() { Q host | sed -E 's/^sheet ([0-9]+),([0-9]+) ([0-9]+)x([0-9]+) on ([^ ]+) ([0-9]+)x([0-9]+)$/\1 \2 \3 \4 \5 \6 \7/'; }
# The material cards' swatches are made on a thread of the daemon's after a change of style, scheme or light: a shot waits
# until no new swatch has appeared for a moment (at most a minute).
settle() {
  local n=-1 m
  for _ in $(seq 40); do
    m=$(ls "$R/cache/kurashi/texture/swatch" 2>/dev/null | grep -c '\.png$' || true)
    [ "$m" = "$n" ] && [ "$m" -gt 0 ] && break
    n=$m; sleep 1.5
  done
  sleep 1
}
shot() { settle; grim -o HEADLESS-1 "$OUT/$1.png"; [ -s "$OUT/$1.png" ]; }
crop() { settle; read -r x y w h _ _ _ <<< "$(geom)"; grim -g "$x,$y ${w}x$h" "$W32/$1.png"; [ -s "$W32/$1.png" ]; }

# --- 1. a layer surface on the focused output, centred, over a dimmed desktop ---------------------------------------
start_qs theme.texture.kind
[[ "$(Q host)" == sheet* ]] || fail "the config names the sheet, the app shows $(Q host)"
log=$(sed 's/\x1b\[[0-9;]*m//g' "$R/settings.log")
grep -qE 'get_layer_surface\(.*"kurashi-settings"' <<< "$log" || fail "no layer surface named kurashi-settings"
grep -qE 'get_layer_surface\(.*, 3, "kurashi-settings"' <<< "$log" || fail "the sheet is not on the Overlay layer"
grep -qE 'zwlr_layer_surface_v1[@#][0-9]+\.set_anchor\(15\)' <<< "$log" || fail "the sheet is not anchored to all four edges"
grep -qE 'zwlr_layer_surface_v1[@#][0-9]+\.set_keyboard_interactivity\(1\)' <<< "$log" || fail "the sheet does not take the keyboard exclusively"
grep -qE 'zwlr_layer_surface_v1[@#][0-9]+\.set_exclusive_zone\(-1\)' <<< "$log" || fail "the sheet reserves room (exclusive zone)"
read -r x y w h out sw shh <<< "$(geom)"
[ "$out" = HEADLESS-1 ] || fail "the sheet is on $out, not the focused output"
[ "$w" -eq "$(( sw * 9 / 10 < 1040 ? sw * 9 / 10 : 1040 ))" ] && [ "$h" -eq "$(( shh * 9 / 10 < 740 ? shh * 9 / 10 : 740 ))" ] \
  || fail "the sheet is ${w}x$h on ${sw}x$shh"
[ $(( 2 * x + w - sw )) -ge -2 ] && [ $(( 2 * x + w - sw )) -le 2 ] && [ $(( 2 * y + h - shh )) -ge -2 ] && [ $(( 2 * y + h - shh )) -le 2 ] \
  || fail "the sheet is not centred: $x,$y ${w}x$h on ${sw}x$shh"
grim -t ppm -o HEADLESS-1 "$R/open.ppm"
python3 -I - "$R/open.ppm" "$x" "$y" "$w" "$h" <<'PY' || fail "the desktop round the sheet is not dimmed, or the sheet not drawn"
import sys
p, x, y, w, h = sys.argv[1], *map(int, sys.argv[2:])
d = open(p, "rb").read()
parts, pos = [], 0
while len(parts) < 4:
    while d[pos:pos + 1].isspace(): pos += 1
    e = pos
    while not d[e:e + 1].isspace(): e += 1
    parts.append(d[pos:e]); pos = e
pos += 1
W = int(parts[1])
px = lambda X, Y: tuple(d[pos + 3 * (Y * W + X): pos + 3 * (Y * W + X) + 3])
bg = (0x7f, 0x9f, 0xae)
corner = px(20, int(parts[2]) - 20)          # the desktop, below the sheet
inside = px(x + w // 2, y + h - 12)          # the sheet's own ground
dimmed = all(c < b * 0.8 for c, b in zip(corner, bg))
print(f"desktop {bg} -> {corner} under the scrim; sheet ground {inside}")
sys.exit(0 if dimmed and inside != corner else 1)
PY
echo "layer surface: kurashi-settings, Overlay, anchored on all edges, exclusive keyboard; ${w}x$h at $x,$y on $out ${sw}x$shh"
shot kami-light

# --- 2. idle: no frame while open and still (Ma) ----------------------------------------------------------------------
Q goto bar; sleep 2
f0=$(Q frames); sleep 3; f1=$(Q frames)
[ "$f0" = "$f1" ] || fail "the open sheet drew $((f1 - f0)) frames in 3 s while still"
echo "idle: 0 frames in 3 s with the sheet open"

# --- 3. a deep link through the daemon jumps the open sheet ------------------------------------------------------------
Q goto bar
K settings theme.pen.line | grep -q "moved to" || fail "kurashi settings did not reach the open sheet"
for _ in $(seq 25); do [ "$(Q current)" = appearance ] && break; sleep 0.2; done
[ "$(Q current)" = appearance ] || fail "the deep link did not open the pen's page ($(Q current))"
[ "$(Q scrollY)" -gt 0 ] || fail "the deep link did not scroll to the pen's row"
crop w32-pen
echo "deep link: kurashi settings theme.pen.line jumped the open sheet (scroll $(Q scrollY))"

# --- 4. a live re-host keeps the page and the scroll -------------------------------------------------------------------
Q scroll 2000; sleep 0.3   # well above the end, so neither host clamps it
y0=$(Q scrollY)
K set settings.window '"window"' | grep -q '^applied' || fail "settings.window window refused"
for _ in $(seq 50); do [ "$(Q host)" = window ] && break; sleep 0.2; done
[ "$(Q host)" = window ] || fail "no re-host to the window ($(Q host))"
sleep 0.5
[ "$(Q current)" = appearance ] && [ "$(Q scrollY)" = "$y0" ] || fail "the window is on $(Q current) at $(Q scrollY), not appearance at $y0"
K set settings.window '"sheet"' | grep -q '^applied' || fail "settings.window sheet refused"
for _ in $(seq 50); do [[ "$(Q host)" == sheet* ]] && break; sleep 0.2; done
[[ "$(Q host)" == sheet* ]] || fail "no re-host back to the sheet ($(Q host))"
sleep 0.5
[ "$(Q current)" = appearance ] && [ "$(Q scrollY)" = "$y0" ] || fail "the sheet came back on $(Q current) at $(Q scrollY)"
kill -0 "$qs_pid" 2>/dev/null || fail "the app ended on a re-host"
echo "re-host: sheet → window → sheet, the same process on appearance at scroll $y0"

# --- 5. the wave 32 rows in the sheet ---------------------------------------------------------------------------------
apply '[{"set":"theme.texture.kind","value":"brush"},{"set":"theme.light.mode","value":"spotlight"},{"set":"theme.light.angle","value":20},{"set":"theme.light.beam","value":30},{"set":"theme.light.color","value":"warm"}]'
Q jump theme.texture.kind
crop w32-brush-card
Q jump theme.light.mode
crop w32-light-spotlight
Q jump theme.light.color
crop w32-light-colours
apply '[{"set":"theme.texture.scope","value":"shell_wallpaper"},{"set":"theme.texture.wallpaper.own","value":true},{"set":"theme.texture.wallpaper.kind","value":"stone"}]'
Q jump theme.texture.wallpaper.own
crop w32-wallpaper-cards
echo "wave 32 rows: shots in $W32/w32-*.png"

# --- 6. Esc: a dropdown and a preview take theirs first; then the sheet closes ---------------------------------------
rm -f "$R/keys.fifo"; mkfifo "$R/keys.fifo"
python3 -I tools/bench/wl_keys.py --serve < "$R/keys.fifo" & pids+=("$!")
exec 3> "$R/keys.fifo"
kp() { for k in "$@"; do echo "$k" >&3; sleep 0.3; done; }
Q goto appearance
Q openChoice theme.pen.line
sleep 0.5
kp escape
alive "Esc on an open dropdown closed the sheet"
radius0=$(K raw '{"t":"cfg.get","id":"r","key":"theme.shape.radius_scale"}' | python3 -I -c 'import json,sys; print(json.loads(sys.stdin.readline())["v"]["value"])')
Q jump theme.shape.radius_scale
sleep 0.5
Q focusList >/dev/null
for _ in $(seq 150); do [ "$(Q focused)" = "slider:theme.shape.radius_scale" ] && break; echo tab >&3; sleep 0.2; done
[ "$(Q focused)" = "slider:theme.shape.radius_scale" ] || fail "Tab did not reach the radius slider ($(Q focused))"
kp right
for _ in $(seq 25); do [ "$(Q previewState)" != none ] && break; sleep 0.2; done
[ "$(Q previewState)" != none ] || fail "Right on the radius slider opened no preview"
kp escape
alive "Esc on a preview closed the sheet instead of putting the preview back"
for _ in $(seq 25); do [ "$(Q previewState)" = none ] && break; sleep 0.2; done
[ "$(Q previewState)" = none ] || fail "Esc did not put the preview back ($(Q previewState))"
kp escape
gone "Esc did not close the sheet"
sleep 0.5
radius1=$(K raw '{"t":"cfg.get","id":"r","key":"theme.shape.radius_scale"}' | python3 -I -c 'import json,sys; print(json.loads(sys.stdin.readline())["v"]["value"])')
[ "$radius1" = "$radius0" ] || fail "the radius is $radius1 after the put back and close, was $radius0"
exec 3>&-
echo "Esc: the dropdown closed first, the preview was put back next, then the sheet closed (radius $radius1)"

# --- 7. a click on the backdrop closes; the close button closes ---------------------------------------------------------
start_qs
read -r x y w h out sw shh <<< "$(geom)"
timeout 30 python3 -I tools/bench/wl_pointer.py click 40 $((shh - 40)) left
gone "a click on the backdrop did not close the sheet"
start_qs
read -r x y w h out sw shh <<< "$(geom)"
timeout 30 python3 -I tools/bench/wl_pointer.py click $((x + w - 12 - 16)) $((y + 26)) left
gone "the close button did not close the sheet"
echo "backdrop click and close button: each closed the sheet"

# --- 8. the sheet under other chrome and in dark ----------------------------------------------------------------------
apply '[{"reset":"theme.texture.kind"},{"reset":"theme.light.mode"},{"reset":"theme.light.angle"},{"reset":"theme.light.beam"},{"reset":"theme.light.color"},{"reset":"theme.texture.scope"},{"reset":"theme.texture.wallpaper.own"},{"reset":"theme.texture.wallpaper.kind"}]'
apply '[{"set":"theme.colors.scheme","value":"dark"}]'
start_qs theme.texture.kind
shot kami-dark
for style in sekai aqua; do
  K raw "{\"t\":\"act\",\"id\":\"s\",\"action\":\"theme.style.apply\",\"args\":{\"name\":\"$style\"}}" | grep -q done || fail "style $style"
  sleep 1.5
  shot "$style"
done
apply '[{"set":"theme.colors.scheme","value":"light"}]'
shot aqua-light

# --- the QML log: no errors from the settings process ------------------------------------------------------------------
if sed 's/\x1b\[[0-9;]*m//g' "$R/settings.log" | grep -aE 'ReferenceError|TypeError|is not a function|Cannot assign|Unable to assign|SyntaxError|Expected token|anchors' | grep -q .; then
  sed 's/\x1b\[[0-9;]*m//g' "$R/settings.log" | grep -aE 'ReferenceError|TypeError|is not a function|Cannot assign|Unable to assign|SyntaxError|Expected token|anchors' | head -20
  fail "QML errors in the settings log"
fi
echo "ok: settings as a sheet; shots in $OUT and $W32/w32-*.png"
