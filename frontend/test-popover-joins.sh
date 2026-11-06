#!/usr/bin/env bash
# What opens at a bar in dynamic stands on it and merges near a corner (I428, docs/ux/layout.md "Draw modes"), on nested niri under washi, by pixels:
#   launcher  opened at its button near the top-left corner: no gap to the bar, none to the left band, a fillet into the band under its foot and one to the bar past its far side;
#             the same on a bottom bar and a left bar; floating keeps its gap
#   menu      a module's menu near the top-right corner: flush on the right band, a fillet under its foot, one into the bar on the other side
#   nix develop -c frontend/test-popover-joins.sh
# Binaries from $KURASHI_BIN_DIR, else $CARGO_TARGET_DIR/debug. Shots: frontend/shots/popover-joins/.
set -uo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
export KURASHI_NIRI_SB_NAME=${KURASHI_SB_PREFIX:-}popover-joins
export KURASHI_NIRI_SB_OUT=${POPOVER_OUT:-$ROOT/frontend/shots/popover-joins}
OUT=$KURASHI_NIRI_SB_OUT
SB="$ROOT/tools/bench/niri-sandbox.sh"
mkdir -p "$OUT"
fail() { echo "test-popover-joins: $*" >&2; "$SB" stop >/dev/null 2>&1; exit 1; }
trap '"$SB" stop >/dev/null 2>&1' EXIT
CFG=$OUT/config.toml
conf() { # conf <draw> <edge>: the one bar, with the launcher at its start and the quick button at its end
  {
    cat <<TOML
[idle]
enabled = false

[theme]
style = "washi"

[theme.material]
sheet_shadow = "off"

[layout]
draw = "$1"

[layout.frame]
enabled = true
thickness = 10

# (Its clock ticks: nested niri redraws only on damage after a screencopy, and that is what damages it here.)
[desktop]
enabled = true
clock = true
calendar = false

[modules.windows]
previews = false
[modules.workspaces]
previews = false

TOML
    for e in top bottom left right; do
      if [ "$e" = "$2" ]; then
        printf '[edges.%s]\nbar = true\nstart = ["launcher"]\nend = ["quick"]\ncenter = []\n\n' "$e"
      else
        printf '[edges.%s]\nbar = false\nstart = []\nend = []\ncenter = []\n\n' "$e"
      fi
    done
  } > "$CFG"
}
conf dynamic top
"$SB" start "$CFG" > /dev/null || fail "the sandbox did not start"
sleep 4
shot() { (. "$OUT/sway-env.sh"; timeout 8 grim "$OUT/$1.png"); }
click() { (. "$OUT/sway-env.sh"; python3 -I "$ROOT/tools/bench/wl_pointer.py" click "$1" "$2" "${3:-left}"); }
# The background of the hole is the wallpaper-less desktop's: a green; paper is light.
paper() { # paper <shot> <x> <y>: is it the sheet's paper here?
  local g; g=$(magick "$OUT/$1.png" -format "%[fx:int(255*p{$2,$3}.b)]" info:)
  [ "$g" -ge 180 ]
}
# Is it the desktop in the hole here (the sandbox's green)? The outline and the paper are not.
hole() { local d; d=$(magick "$OUT/$1.png" -format "%[fx:int(255*(p{$2,$3}.g-p{$2,$3}.r))]" info:); [ "$d" -ge 15 ]; }
# Where the card's foot lies along column x: the first row below `from` that is not paper.
# (Text and row rules are not the foot: the hole goes on for 40 px below it.)
foot() { local y; for y in $(seq "$3" 2 "$4"); do paper "$1" "$2" "$y" || paper "$1" "$2" $(( y + 40 )) || { echo "$y"; return; }; done; echo 0; }

BAR=$("$SB" act --json sub theme --count 0 2>/dev/null | head -1 | jq -r '.data.tokens["bar.height"] // 32')
BAR=${BAR%.*}; [ "$BAR" -gt 0 ] 2>/dev/null || BAR=32
# ---- top bar, by the left corner ----
click 40 15; sleep 1.5; shot top
paper top 300 $(( BAR + 4 )) || fail "launcher: a gap under the bar"
paper top 11 $(( BAR + 60 )) || fail "launcher: a gap to the left band"
Y=$(foot top 300 $(( BAR + 4 )) 900)
[ "$Y" -gt $(( BAR + 40 )) ] || fail "launcher: no card ($Y)"
# Past its foot, by the band: the fillet, paper a pixel or two out of the band's edge, then the hole.
hole top 11 $(( Y + 1 )) && fail "launcher: no fillet into the band under its foot (at 11, $(( Y + 1 )))"
paper top 300 $(( Y + 12 )) && fail "launcher: paper under the foot, away from the band"
"$SB" act act launcher.toggle > /dev/null 2>&1; sleep 1
echo "launcher, top: stands on the bar, merges with the left band, a fillet under its foot"

# ---- a module's menu near the top-right corner ----
sleep 2
click 1880 15 right; sleep 2; shot menu

paper menu 1908 $(( BAR + 40 )) || fail "menu: a gap to the right band"
Y=$(foot menu 1895 $(( BAR + 2 )) 600)
[ "$Y" -gt $(( BAR + 20 )) ] || fail "menu: no card ($Y)"
hole menu 1908 $(( Y + 1 )) && fail "menu: no fillet into the band under its foot"
click 960 700; sleep 1
echo "menu: flush on the right band, a fillet under its foot"

# ---- a bottom bar ----
conf dynamic bottom; "$SB" config "$CFG"; sleep 3
click 40 $(( 1080 - 15 )); sleep 2; shot bottom
paper bottom 300 $(( 1080 - BAR - 4 )) || fail "launcher, bottom: a gap over the bar"
paper bottom 11 $(( 1080 - BAR - 60 )) || fail "launcher, bottom: a gap to the left band"
"$SB" act act launcher.toggle > /dev/null 2>&1; sleep 1
echo "launcher, bottom: stands on the bar, merges with the left band"

# ---- floating keeps its gap ----
conf floating top; "$SB" config "$CFG"; sleep 3
click 60 25; sleep 2; shot floating
gap=
for y in $(seq 20 2 100); do hole floating 300 "$y" && { gap=$y; break; }; done
[ -n "$gap" ] || fail "floating: no gap between the bar and the card"
hole floating 12 300 || fail "floating: it lies on the left band"
"$SB" act act launcher.toggle > /dev/null 2>&1; sleep 1
[ -z "$("$SB" log 2>/dev/null | grep -E 'TypeError|ReferenceError')" ] || fail "QML errors: $("$SB" log | grep -E 'TypeError|ReferenceError' | head -5)"
echo "floating: a gap to the bar, none on the band"
echo "test-popover-joins: OK"
