#!/usr/bin/env bash
# The handwriting mod (K94, I415; docs/ux/handwriting.md), on nested niri, by hand: a font named on the keyboard, letters drawn with the pointer in the box,
# Retry clearing one, Save and next moving on and showing it in the overview, Make font putting a real font in the font folder, a second version
# making a second font, Use it making them the mix and the shell's text changing, and Delete taking it all away.
#   nix develop -c mods/handwriting/test-handwriting.sh
set -uo pipefail
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
export KURASHI_NIRI_SB_NAME=${KURASHI_SB_PREFIX:-}handwriting
export KURASHI_NIRI_SB_OUT=${HANDWRITING_OUT:-$ROOT/mods/handwriting/shots}
export KURASHI_HANDWRITING_LOG=1
OUT=$KURASHI_NIRI_SB_OUT
SB="$ROOT/tools/bench/niri-sandbox.sh"
mkdir -p "$OUT"
fail() { echo "test-handwriting: $*" >&2; "$SB" stop >/dev/null 2>&1; exit 1; }
trap '"$SB" stop >/dev/null 2>&1' EXIT
CFG=$OUT/config.toml
cat > "$CFG" <<TOML
[idle]
enabled = false
[theme]
style = "kami"
[theme.motion]
profile = "none"
[modules.windows]
previews = false
[modules.workspaces]
previews = false
[mods]
enabled = ["handwriting"]
TOML
"$SB" start "$CFG" > /dev/null || fail "the sandbox did not start"
. "$OUT/niri-env.sh"
BIN=${KURASHI_BIN_DIR:-${CARGO_TARGET_DIR:-$ROOT/target}/debug}
K() { timeout 15 "$BIN/kurashi" "$@"; }
Q=$XDG_RUNTIME_DIR/qs.log
ptr() { (. "$OUT/sway-env.sh"; python3 -I "$ROOT/tools/bench/wl_pointer.py" "$@"); }
keys() { (. "$OUT/sway-env.sh"; python3 -I "$ROOT/tools/bench/wl_keys.py" "$@"); }
doc() { K sub mod.handwriting --count 0 2>/dev/null | head -1; }
font() { doc | python3 -c "import json,sys; f=json.load(sys.stdin)['data']['fonts']; print(json.dumps(f[0]['$1'], separators=(',',':')) if f else '')"; }
until_() { for _ in $(seq 75); do "$@" && return 0; sleep 0.2; done; return 1; }
at() { grep -a "handwriting-place $1 " "$Q" | tail -1 | sed "s/.*handwriting-place $1 //"; }
shot() { "$SB" shot "$1" "0,0 1920x1080" 0.6 > /dev/null; }

K act mod.panel.open '{"id":"handwriting","panel":"handwriting"}' > /dev/null || fail "the panel did not open"
for _ in $(seq 50); do [ -n "$(at name)" ] && break; sleep 0.2; done
sleep 1.5
# The card stands in the middle of the output, and the log says where the panel is in its window: the window's coordinates to the screen's.
read -r nx ny _ _ < <(at name)
offset() { read -r px _ pw _ < <(at panel); OFF=$(( (1920 - pw) / 2 - px )); }
offset
ptr click $((nx + OFF + 10)) $((ny + 8)) left
sleep 0.4
keys m y space h a n d return
has_font() { [ "$(font name)" = '"my hand"' ]; }
until_ has_font || fail "the font was not created: $(doc | cut -c1-200)"
sleep 1
echo "created: on the keyboard"

read -r bx by bw bh < <(at box)
read -r sx sy _ _ < <(at save)
read -r rx ry _ _ < <(at retry)
read -r mx my _ _ < <(at make)
[ "$bw" -gt 100 ] || fail "no box"
unit() { python3 -c "print($bh/1300)"; }
stroke() { # stroke u0,v0 u1,v1 … : font units to the screen
  python3 -c "
import sys
u=$bh/1300; cx=$bx+$OFF+$bw/2; base=$by+1000*u
print('draw '+' '.join(f'{int(cx+float(a.split(\",\")[0])*u)},{int(base-float(a.split(\",\")[1])*u)}' for a in sys.argv[1:]))" "$@"
}
draw() { # shell words of a stroke line go to wl_pointer
  # shellcheck disable=SC2046
  ptr $(stroke "$@")
}
save() { ptr click $((sx + OFF + 20)) $((sy + 10)) left; sleep 0.7; }
A() { draw -200,0 -100,240 0,720 100,300 200,0; draw -120,240 0,260 120,230; }

# Retry takes it away: a saved letter after it is only the second drawing.
draw -300,0 300,700
ptr click $((rx + OFF + 15)) $((ry + 10)) left
sleep 0.3
A
sleep 0.3
shot drawing
save
done1() { [ "$(font done)" = "[1,0,0]" ]; }
until_ done1 || fail "the letter was not saved: $(font done)"
echo "drawn: A, with a Retry before it, saved"
draw -160,720 -150,300 -160,0
draw -160,720 40,700 120,560 20,400 -150,370 100,330 170,160 60,20 -160,0
save
done2() { [ "$(font done)" = "[2,0,0]" ]; }
until_ done2 || fail "the second letter did not follow: $(font done)"
echo "next: B followed, and was saved"
shot overview

# Make font.
ptr click $((mx + OFF + 15)) $((my + 8)) left
fam1() { [ "$(font families)" = '["my hand 1"]' ]; }
until_ fam1 || fail "no font made: $(font families)"
FILE=$XDG_DATA_HOME/fonts/kurashi-hand-my-hand-1.ttf
[ -f "$FILE" ] || fail "no file $FILE"
fc-scan --format '%{family}\n' "$FILE" | grep -qxF "my hand 1" || fail "the file is not called so: $(fc-scan --format '%{family}' "$FILE")"
fc-scan --format '%{charset}\n' "$FILE" | grep -q '41-42' || fail "A and B are not in it: $(fc-scan --format '%{charset}' "$FILE")"
echo "made: my hand 1, A and B in it, nothing not drawn"
shot made

# A second version: only A, and two fonts come out.
K act handwriting.glyph.save '{"id":"my-hand","version":2,"char":"A","strokes":[[[-220,0],[0,700],[210,10]],[[-110,250],[130,260]]]}' > /dev/null || fail "save to version 2"
K act handwriting.font.make '{"id":"my-hand"}' > /dev/null || fail "make"
fam2() { [ "$(font families)" = '["my hand 1","my hand 2"]' ]; }
until_ fam2 || fail "the second version made no font: $(font families)"
fc-scan --format '%{charset}\n' "$XDG_DATA_HOME/fonts/kurashi-hand-my-hand-2.ttf" | grep -q '41-42' || fail "version 2 did not borrow B"
echo "versions: the second borrows what it has not drawn"

# Use it: they become the mix.
K set theme.typography.mix.preset=custom theme.typography.mix.count=2 'theme.typography.mix.fonts=["my hand 1","my hand 2"]' > /dev/null || fail "the shell did not take the fonts"
state() { K sub theme --count 0 2>/dev/null | head -1 | python3 -c "import json,sys; print(json.load(sys.stdin)['data']['tokens'].get('font.mix.state'))"; }
on() { [ "$(state)" = on ]; }
until_ on || fail "the mix did not come on: $(state)"
echo "used: the drawn fonts are the mix"
K set theme.typography.mix.preset=off > /dev/null
K act handwriting.font.delete '{"id":"my-hand"}' > /dev/null || fail "delete"
sleep 0.5
[ ! -e "$FILE" ] || fail "delete left the font"
[ ! -e "$XDG_DATA_HOME/kurashi/handwriting/my-hand.json" ] || fail "delete left the drawing"
echo "deleted: drawing and fonts gone"
"$SB" log 14 | grep -v 'host portal' | grep -iE 'TypeError|ReferenceError|handwriting.*(warn|error)' && fail "the frontend complained"
echo "test-handwriting: OK"
