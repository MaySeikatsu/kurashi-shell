#!/usr/bin/env bash
# Wallpaper Color Grade (K88, docs/ux/wallpaper-color-grade.md) in the real daemon with the wallpaper mod, invisibly: a fake
# awww logs what it is told to show, and the bake's files are read back.
#   1. off: the picture itself is shown.
#   2. on: a baked copy is shown, in the theme's hue; the original file and the mod's own path stay.
#   3. a palette change, a mode change: a new bake. A theme seen before: the same file, nothing baked again.
#   4. a track's colours (Dynamic Media Color) grade it too.
#   5. off: the picture itself again.
# Needs: nix develop; kurashid, kurashi and examples/fake_mpris_art in $KURASHI_BIN_DIR, else built here.
set -uo pipefail
cd "$(dirname "$0")/.."
ROOT=$PWD
if ! command -v sway >/dev/null; then exec nix develop -c "$0" "$@"; fi
if [ -z "${KURASHI_BIN_DIR:-}" ]; then
  cargo build -q -p kurashid -p kurashi && cargo build -q -p kurashi-mock --example fake_mpris_art || exit 1
  BIN=${CARGO_TARGET_DIR:-$ROOT/target}/debug
else
  BIN=$KURASHI_BIN_DIR
fi
NAME=${KURASHI_SB_NAME:-wpgrade-$$}
eval "$(tools/bench/sandbox.sh start "$NAME")"
R=$XDG_RUNTIME_DIR
pids=()
FAILS=0
cleanup() {
  for p in "${pids[@]}"; do kill "$p" 2>/dev/null || true; done
  exec 7>&- 2>/dev/null || true
  tools/bench/sandbox.sh stop "$NAME" >/dev/null 2>&1 || true
}
trap cleanup EXIT
check() { if [ "$1" = 1 ]; then echo "ok: $2"; else echo "FAIL: $2"; FAILS=$((FAILS + 1)); fi; }

W=$R/work; mkdir -p "$W" "$R/fakebin" "$R/wpstate" "$R/cfg/kurashi" "$R/state" "$R/data" "$R/cache"
cp "$BIN/kurashid" "$BIN/kurashi" "$BIN/examples/fake_mpris_art" "$W/"
export XDG_CONFIG_HOME=$R/cfg XDG_STATE_HOME=$R/state XDG_DATA_HOME=$R/data XDG_CACHE_HOME=$R/cache KURASHI_DATA_DIR=$ROOT
export WP_LOG=$R/awww.log WP_STATE=$R/wpstate PATH=$R/fakebin:$PATH
: > "$WP_LOG"
cat > "$R/fakebin/awww" <<'S'
#!/bin/sh
echo "awww $*" >> "$WP_LOG"
case "$1" in
  --version) echo "awww 0.12.1" ;;
  query)
    if [ -f "$WP_STATE/daemon" ]; then
      printf '%s\n' '{"": [{"name": "HEADLESS-1", "width": 640, "height": 360, "scale": 1, "displaying": {"color": "000000"}}]}'
    else
      echo "Failed to connect to the awww-daemon socket" >&2; exit 1
    fi ;;
  kill) rm -f "$WP_STATE/daemon" ;;
esac
exit 0
S
cat > "$R/fakebin/awww-daemon" <<'S'
#!/bin/sh
echo "awww-daemon $*" >> "$WP_LOG"
touch "$WP_STATE/daemon"
S
chmod +x "$R/fakebin/awww" "$R/fakebin/awww-daemon"
PIC=$R/picture.png
magick -size 640x360 gradient:'#d08030-#203050' "$PIC"
sum0=$(md5sum "$PIC" | cut -d' ' -f1)
magick -size 96x96 xc:'#8c1c3a' "$R/cover.png"
printf 'schema_version = 1\n[idle]\nenabled = false\n[mods]\nenabled = ["wallpaper"]\n[theme]\nstyle = "yorha"\n' > "$R/cfg/kurashi/config.toml"
K() { timeout 10 "$W/kurashi" "$@"; }
PULSE_RUNTIME_PATH="$R/no-pulse" "$W/kurashid" > "$R/kurashid.log" 2>&1 & pids+=("$!")
for _ in $(seq 50); do K ping >/dev/null 2>&1 && break; sleep 0.1; done
K ping >/dev/null 2>&1 || { echo "kurashid did not start"; exit 1; }
snap() { K raw "{\"t\":\"sub\",\"id\":\"s\",\"doc\":\"$1\"}" 2>/dev/null | head -1; }
tok() { snap theme | python3 -I -c "import json,sys; print(json.loads(sys.stdin.readline())['data']['tokens'].get('$1',''))"; }
# The last picture awww was told to show.
shown() { grep -a '^awww img' "$WP_LOG" | tail -1 | grep -oE '/[^ ]+\.png' | head -1; }
# Waits until awww is shown something other than $1, and prints it.
next() { local was=$1 now; for _ in $(seq 150); do now=$(shown); [ -n "$now" ] && [ "$now" != "$was" ] && { echo "$now"; return 0; }; sleep 0.1; done; shown; return 1; }
# Hue of a picture's mean colour, 0..360.
hue() { magick "$1" -resize 1x1\! -colorspace HSL -format '%[fx:p{0,0}.r*360]' info: ; }
hue_of() { magick xc:"$1" -colorspace HSL -format '%[fx:p{0,0}.r*360]' info: ; }
near() { python3 -I -c "import sys; a,b=float('$1'),float('$2'); d=abs(a-b)%360; sys.exit(0 if min(d,360-d)<${3:-45} else 1)"; }

for _ in $(seq 50); do K act --list wallpaper 2>/dev/null | grep -q wallpaper.set && [ -f "$WP_STATE/daemon" ] && break; sleep 0.2; done
K act wallpaper.set "{\"path\":\"$PIC\"}" >/dev/null
for _ in $(seq 50); do [ "$(shown)" = "$PIC" ] && break; sleep 0.1; done
[ "$(shown)" = "$PIC" ]; check $(( $? == 0 )) "off: the picture itself is shown"

t0=$(date +%s%3N)
K set theme.colors.wallpaper_grade.enabled=true >/dev/null
a=$(next "$PIC"); r=$?; t1=$(date +%s%3N)
[ "$r" = 0 ] && [ "$a" != "$PIC" ] && [ -s "$a" ]; check $(( $? == 0 )) "on: a baked copy is shown ($(( t1 - t0 )) ms)"
case "$a" in "$R/cache/kurashi/texture/wallpaper/"*) r=1 ;; *) r=0 ;; esac; check $r "on: the copy lives in the bake's cache"
[ "$(identify -format '%wx%h' "$a")" = 640x360 ]; check $(( $? == 0 )) "on: at the output's size"
[ "$(md5sum "$PIC" | cut -d' ' -f1)" = "$sum0" ]; check $(( $? == 0 )) "on: the original file is untouched"
# The mod's document fills only for a subscriber.
K sub mod.wallpaper > /dev/null 2>&1 & pids+=("$!")
r=1
for _ in $(seq 30); do
  doc=$(snap mod.wallpaper)
  echo "$doc" | python3 -I -c "
import json,sys
d=json.loads(sys.stdin.readline())['data']
sys.exit(0 if d['outputs'] and all(o['path']=='$PIC' for o in d['outputs'].values()) else 1)" && { r=0; break; }
  sleep 0.2
done
(exit "$r")
r=$?; [ "$r" = 0 ] || echo "$doc" | cut -c1-420
check $(( r == 0 )) "on: the wallpaper document keeps the picture's own path"

# Another palette: another bake.
K set theme.colors.palette=tokyo-night >/dev/null || check 0 "the palette was refused"
b=$(next "$a"); r=$?
[ "$r" = 0 ] && [ "$b" != "$a" ]; check $(( $? == 0 )) "a palette change: a new bake ($(tok color.accent))"
K reset theme.colors.palette >/dev/null
c=$(next "$b"); r=$?
[ "$r" = 0 ] && [ "$c" = "$a" ]; check $(( $? == 0 )) "a theme seen before: the same file, not baked again"

K set theme.colors.wallpaper_grade.mode=gradient >/dev/null
d=$(next "$c"); r=$?
[ "$r" = 0 ]; check $(( $? == 0 )) "a mode change: a new bake"
K set theme.colors.wallpaper_grade.strength=0.5 >/dev/null
e=$(next "$d"); r=$?
[ "$r" = 0 ]; check $(( $? == 0 )) "a strength change: a new bake"

# A track's colours.
mkfifo "$R/player.in"; "$W/fake_mpris_art" Track Artist Album 300 "file://$R/cover.png" < "$R/player.in" > "$R/player.log" 2>&1 & player=$!; pids+=("$player")
exec 7> "$R/player.in"
K set theme.colors.media.follow=true theme.colors.wallpaper_grade.strength=1 >/dev/null
f=$(next "$e"); r=$?
for _ in $(seq 80); do [ -n "$(tok media.tint)" ] && break; sleep 0.1; done
for _ in $(seq 40); do g=$(shown); [ "$g" != "$f" ] && break; sleep 0.1; done; sleep 0.5; g=$(shown)
surface=$(tok color.surface)
near "$(hue "$g")" "$(hue_of "$surface")" 60; check $(( $? == 0 )) "Dynamic Media Color: graded to the track ($surface, picture hue $(hue "$g"))"

K set theme.colors.media.follow=false >/dev/null
K set theme.colors.wallpaper_grade.enabled=false >/dev/null
for _ in $(seq 100); do [ "$(shown)" = "$PIC" ] && break; sleep 0.1; done
[ "$(shown)" = "$PIC" ]; check $(( $? == 0 )) "off: the picture itself again"
[ "$(md5sum "$PIC" | cut -d' ' -f1)" = "$sum0" ]; check $(( $? == 0 )) "off: the original file is untouched"

grep -q panicked "$R/kurashid.log" && check 0 "no daemon panic"
[ "$FAILS" = 0 ] && echo "test-wallpaper-grade: ok" || { echo "test-wallpaper-grade: $FAILS failed"; grep -a '^awww img' "$WP_LOG" | cut -c1-140 | tail -12; exit 1; }
