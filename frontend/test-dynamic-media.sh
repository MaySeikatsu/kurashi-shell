#!/usr/bin/env bash
# Dynamic Media Color (K87, docs/ux/dynamic-media-color.md) in the REAL shell, invisibly: the real kurashid, a fake MPRIS
# player with covers (crates/kurashi-mock/examples/fake_mpris_art.rs) on the sandbox's bus.
#   1. off: a playing track leaves the theme alone.
#   2. on: the cover's colours are the theme (a look's list tokens too), the scheme in effect follows them, a note says why.
#   3. a new cover: the bar moves through colours in between under `fade`, lands on the new ones, the frontend stops.
#   4. `direct` cuts. 5. `keep` stays light. 6. no track: the palette is back.
#   7. off: every token as it was, and the config holds only the switch.
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
NAME=${KURASHI_SB_NAME:-dynmedia-$$}
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

W=$R/work; mkdir -p "$W" "$R/covers" "$R/cfg/kurashi" "$R/state" "$R/data" "$R/cache"
cp "$BIN/kurashid" "$BIN/kurashi" "$BIN/examples/fake_mpris_art" "$W/"
export XDG_CONFIG_HOME=$R/cfg XDG_STATE_HOME=$R/state XDG_DATA_HOME=$R/data XDG_CACHE_HOME=$R/cache KURASHI_DATA_DIR=$ROOT
CFG=$R/cfg/kurashi/config.toml
printf 'schema_version = 1\n[idle]\nenabled = false\n[theme]\nstyle = "yorha"\n[theme.motion]\nprofile = "calm"\n' > "$CFG"
magick -size 96x96 xc:'#1d4e89' "$R/covers/blue.png"
magick -size 96x96 xc:'#8c1c3a' "$R/covers/red.png"
K() { timeout 10 "$W/kurashi" "$@"; }
PULSE_RUNTIME_PATH="$R/no-pulse" "$W/kurashid" > "$R/kurashid.log" 2>&1 & daemon_pid=$!; pids+=("$daemon_pid")
for _ in $(seq 50); do K ping >/dev/null 2>&1 && break; sleep 0.1; done
K ping >/dev/null 2>&1 || { echo "kurashid did not start"; exit 1; }
env -u KURASHI_SOCKET qs -p "$ROOT/frontend" > "$R/qs.log" 2>&1 & pids+=("$!")
snap() { K raw "{\"t\":\"sub\",\"id\":\"s\",\"doc\":\"$1\"}" 2>/dev/null | head -1; }
# A read that fails ends the run: an empty answer must never pass for "unchanged".
theme() {
  local t
  for _ in 1 2 3 4 5; do
    t=$(snap theme | python3 -I -c "import json,sys; d=json.loads(sys.stdin.readline()); print(json.dumps(d['data'], sort_keys=True))" 2>/dev/null) && [ -n "$t" ] && { echo "$t"; return 0; }
    sleep 0.2
  done
  echo "test-dynamic-media: FAIL: cannot read the theme document" >&2; kill -TERM $$; exit 1
}
tok() { theme | python3 -I -c "import json,sys; d=json.load(sys.stdin); print(json.dumps(d['tokens'].get('$1')).strip('\"'))"; }
app() { theme | python3 -I -c "import json,sys; d=json.load(sys.stdin); print(d['appearance'].get('$1'))"; }
wait_tok() { for _ in $(seq 60); do [ "$(tok "$1")" "${3:-=}" "$2" ] && return 0; sleep 0.1; done; return 1; }
# The bar's colour on screen: a pixel of the top bar away from its modules.
bar() { timeout 5 grim -g "1100,3 1x1" -t ppm - 2>/dev/null | magick ppm:- -format '%[hex:p{0,0}]' info: 2>/dev/null; }
for _ in $(seq 100); do [ -n "$(bar)" ] && break; sleep 0.1; done; sleep 2

base=$(theme)
surface0=$(tok color.surface)
bar0=$(bar)

mkfifo "$R/player.in"; "$W/fake_mpris_art" "Track" "Artist" "Album" 300 "file://$R/covers/blue.png" < "$R/player.in" > "$R/player.log" 2>&1 & player_pid=$!; pids+=("$player_pid")
exec 7> "$R/player.in"
for _ in $(seq 80); do snap svc.media | grep -q art_colors && break; sleep 0.1; done
sleep 0.5
[ "$(theme)" = "$base" ]; check $(( $? == 0 )) "off: a playing track leaves the theme alone"

K set theme.colors.media.follow=true >/dev/null
wait_tok media.tint "" != ; check $(( $? == 0 )) "on: media.tint names the cover"
art=$(snap svc.media | python3 -I -c "import json,sys; print(json.loads(sys.stdin.readline())['data']['art_colors']['bg'])")
[ "$(tok color.surface)" = "$art" ]; check $(( $? == 0 )) "on: the surface is the cover's ($art)"
fill=$(tok decor.bar.fill); case "$fill" in *"$art"*) r=1 ;; *) r=0 ;; esac; check $r "on: a look's list token follows (decor.bar.fill $fill)"
[ "$(app scheme_effective)" = dark ]; check $(( $? == 0 )) "on: the scheme in effect follows the cover (dark on a light style)"
[ "$(app scheme_detail)" = media ]; check $(( $? == 0 )) "on: the scheme says why"
theme | grep -q theme.note.media_colors; check $(( $? == 0 )) "on: a note says why the palette is not in effect"
[ "$(app palette)" = "$(echo "$base" | python3 -I -c "import json,sys; print(json.load(sys.stdin)['appearance']['palette'])")" ]; check $(( $? == 0 )) "on: the palette in the document is still the user's"
sleep 2.2
barBlue=$(bar)
[ "$barBlue" != "$bar0" ]; check $(( $? == 0 )) "on: the bar on screen left the palette ($bar0 -> $barBlue)"

# A new cover under `fade`: colours in between.
K set theme.colors.media.blend_ms=2000 >/dev/null
echo "art file://$R/covers/red.png" >&7
tintBlue=$(tok media.tint)
wait_tok media.tint "$tintBlue" != ; seen=""
for _ in 1 2 3 4 5 6 7 8; do seen="$seen $(bar)"; sleep 0.2; done
sleep 2.0
barRed=$(bar)
n=$(echo "$seen" | tr ' ' '\n' | grep -v '^$' | sort -u | wc -l)
[ "$n" -ge 4 ]; check $(( $? == 0 )) "fade: $n colours on the way ($barBlue ->$seen -> $barRed)"
[ "$barRed" != "$barBlue" ]; check $(( $? == 0 )) "fade: the bar landed on the new cover"
sleep 0.3; [ "$(bar)" = "$barRed" ]; check $(( $? == 0 )) "fade: it rests"

# `direct` cuts.
K set theme.colors.media.blend=direct >/dev/null; sleep 0.3
echo "art file://$R/covers/blue.png" >&7
tintRed=$(tok media.tint); wait_tok media.tint "$tintRed" != ; sleep 0.2
[ "$(bar)" = "$barBlue" ]; check $(( $? == 0 )) "direct: at once"
K set theme.colors.media.blend=wheel_closest >/dev/null

# `keep`: the style's light.
K set theme.colors.media.tone=keep >/dev/null; sleep 0.4
[ "$(app scheme_effective)" = light ]; check $(( $? == 0 )) "keep: stays light"
K set theme.colors.media.tone=cover >/dev/null; sleep 0.3

# A daemon started with the switch on and a track already playing: the common case after a login.
tintNow=$(tok media.tint)
kill "$daemon_pid" 2>/dev/null; wait "$daemon_pid" 2>/dev/null
for _ in $(seq 30); do K ping >/dev/null 2>&1 || break; sleep 0.1; done
PULSE_RUNTIME_PATH="$R/no-pulse" "$W/kurashid" >> "$R/kurashid.log" 2>&1 & daemon_pid=$!; pids+=("$daemon_pid")
for _ in $(seq 50); do K ping >/dev/null 2>&1 && break; sleep 0.1; done
wait_tok media.tint "$tintNow" = ; check $(( $? == 0 )) "start: a new daemon with the switch on follows the track playing"

# No track: the palette is back; the switch stays on.
kill "$player_pid" 2>/dev/null; exec 7>&-
wait_tok media.tint "" = ; check $(( $? == 0 )) "no track: the palette is back"
[ "$(tok color.surface)" = "$surface0" ]; check $(( $? == 0 )) "no track: the surface is the palette's"

# Off: as it was, in the document and the file.
K set theme.colors.media.follow=false >/dev/null; sleep 0.5
python3 -I - "$base" "$(theme)" <<'PY'
import json,sys
a,b=json.loads(sys.argv[1]),json.loads(sys.argv[2])
d=[k for k in set(a['tokens'])|set(b['tokens']) if a['tokens'].get(k)!=b['tokens'].get(k) and not k.startswith('media.blend')]
sys.exit(1 if d else 0) if not d else print("differ:",d[:8]) or sys.exit(1)
PY
check $(( $? == 0 )) "off: every colour token as it was"
grep -qE 'palette|scheme' "$CFG"; check $(( $? != 0 )) "the config holds no palette or scheme of ours"

grep -qE 'TypeError|ReferenceError|is not a type' "$R/qs.log" && { grep -E 'TypeError|ReferenceError|is not a type' "$R/qs.log" | head -5 | cut -c1-160; check 0 "no QML errors"; }
grep -q panicked "$R/kurashid.log" && check 0 "no daemon panic"
[ "$FAILS" = 0 ] && echo "test-dynamic-media: ok" || { echo "test-dynamic-media: $FAILS failed"; exit 1; }
