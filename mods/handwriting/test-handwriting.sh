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
# The log says where the window stands on its output and where the panel is in it: the window's coordinates to the screen's.
read -r nx ny _ _ < <(at name)
offset() { read -r OFF _ _ _ < <(at win); }
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
# ---- the ways in, the options and where it opens (K102) ----
K act ui.close > /dev/null 2>&1; sleep 1
opt() { K set "mods.handwriting.$1" "$2" > /dev/null || fail "mods.handwriting.$1 refused"; }
K --json get mods.handwriting.panel_place | jq -e '.value == "opened"' > /dev/null || fail "panel_place is not a setting"
# Where it opens: the card's window, by the log's panel place, centred and in a corner.
place() { K act mod.panel.open '{"id":"handwriting","panel":"handwriting"}' > /dev/null || fail "opening the panel"; sleep 2; "$SB" shot "place-$1" "0,0 1920x1080" 0.6 > /dev/null; K act ui.close > /dev/null; sleep 1; }
paper() { magick "$OUT/shots/place-$1.png" -format "%[fx:int(255*p{$2,$3}.b)]" info:; }
opt panel_place '"centre"'; sleep 1; place centre
opt panel_place '"bottom_right"'; sleep 1; place bottom_right
opt panel_place '"top_left"'; sleep 1; place top_left
opt panel_place '"opened"'; sleep 1; place opened
# (shots at 0.6: paper where the card should stand, the desk elsewhere)
is_paper() { [ "$(paper "$1" "$2" "$3")" -ge 170 ] || fail "$1: no card at $2,$3"; }
is_desk() { [ "$(paper "$1" "$2" "$3")" -lt 170 ] || fail "$1: a card at $2,$3"; }
is_paper centre 576 324; is_desk centre 60 50
is_paper bottom_right 1080 610; is_desk bottom_right 576 324
is_paper top_left 60 50; is_desk top_left 1080 610
is_paper opened 1090 50; is_desk opened 576 324
echo "where it opens: centre, corners, under the bar"
# The options reach the document and the panel. (A subscriber the while: the service runs while something watches, as the panel does.)
"$BIN/kurashi" sub mod.handwriting > /dev/null 2>&1 &
WATCH=$!
sleep 1
for k in letters default_pen spacing guides shadow next_letter; do K --json get "mods.handwriting.$k" > /dev/null || fail "no setting $k"; done
opt letters '"extended"'; opt guides false; opt shadow false; opt next_letter false; sleep 1
K sub mod.handwriting --count 0 --json 2>/dev/null | head -1 | jq -e '.data.charset | contains("ß")' > /dev/null || fail "letters did not reach the document"
K sub mod.handwriting --count 0 --json 2>/dev/null | head -1 | jq -e '.data.options == {guides: false, shadow: false, next_letter: false}' > /dev/null || fail "options did not reach the document"
opt default_pen '"bold"'; sleep 1
K act handwriting.font.create '{"name":"bold one"}' > /dev/null || fail "create with a bold pen"
K sub mod.handwriting --count 0 --json 2>/dev/null | head -1 | jq -e '[.data.fonts[] | select(.name == "bold one") | .pen] == [84]' > /dev/null || fail "a new font did not take the pen"
# Spacing: the same drawing made wider.
K act handwriting.glyph.save '{"id":"bold-one","version":1,"char":"ß","strokes":[[[0,0],[0,700]]]}' > /dev/null || fail "ß refused"
K act handwriting.font.make '{"id":"bold-one"}' > /dev/null || fail "make with an accent"
fc-scan --format '%{charset}\n' "$XDG_DATA_HOME/fonts/kurashi-hand-bold-one-1.ttf" | grep -q 'df' || fail "ß is not in the font: $(fc-scan --format '%{charset}' "$XDG_DATA_HOME/fonts/kurashi-hand-bold-one-1.ttf")"
K act handwriting.font.delete '{"id":"bold-one"}' > /dev/null
kill "$WATCH" 2>/dev/null
echo "options: letters, lines, shadow, go on, pen and an accent in a made font"

"$SB" log 14 | grep -v 'host portal' | grep -iE 'TypeError|ReferenceError|handwriting.*(warn|error)' && fail "the frontend complained"
echo "test-handwriting: OK"
