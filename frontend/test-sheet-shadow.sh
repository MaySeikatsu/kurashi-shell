#!/usr/bin/env bash
# What the frame, bars, sidebars and dock cast (I427, docs/ux/shadows.md "Sheet"), on nested niri under washi, by pixels at the hole's edges
# against the same background far from them:
#   off      nothing at any edge
#   static   the shadow's direction shows: darker under the top edge (falls down) than over the bottom one, and still something all round
#   follow   the light decides; the token says follow, and the edges darken
#   inward   evenly all round: top, bottom, left and right alike, and deeper than static's faint side
#   nix develop -c frontend/test-sheet-shadow.sh
# Binaries from $KURASHI_BIN_DIR, else $CARGO_TARGET_DIR/debug. Shots: frontend/shots/sheet-shadow/.
set -uo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
export KURASHI_NIRI_SB_NAME=${KURASHI_SB_PREFIX:-}sheet-shadow
export KURASHI_NIRI_SB_OUT=${SHEET_SHADOW_OUT:-$ROOT/frontend/shots/sheet-shadow}
OUT=$KURASHI_NIRI_SB_OUT
SB="$ROOT/tools/bench/niri-sandbox.sh"
mkdir -p "$OUT"
fail() { echo "test-sheet-shadow: $*" >&2; "$SB" stop >/dev/null 2>&1; exit 1; }
trap '"$SB" stop >/dev/null 2>&1' EXIT
CFG=$OUT/config.toml
conf() { # conf <mode>
  printf '[idle]\nenabled = false\n\n[theme]\nstyle = "washi"\n\n[theme.material]\nsheet_shadow = "%s"\nshadow_angle = 180\n\n[layout.frame]\nenabled = true\nthickness = 10\n\n[desktop]\nenabled = false\n\n[modules.windows]\npreviews = false\n[modules.workspaces]\npreviews = false\n' "$1" > "$CFG"
}
conf off
"$SB" start "$CFG" > /dev/null || fail "the sandbox did not start"
. "$OUT/niri-env.sh"
sleep 4
mode() { "$SB" act --json sub theme --count 0 2>/dev/null | head -1 | jq -r '.data.tokens["elevation.sheet"]'; }
set_mode() {
  conf "$1"; "$SB" config "$CFG"
  for _ in $(seq 100); do [ "$(mode)" = "$1" ] && break; sleep 0.1; done
  [ "$(mode)" = "$1" ] || fail "elevation.sheet is $(mode), not $1"
  sleep 1.5
  (. "$OUT/sway-env.sh"; timeout 8 grim "$OUT/$1.png")
}
# Luminance at a point, 0–255.
lum() { magick "$OUT/$1.png" -format "%[fx:int(255*(p{$2,$3}.r*0.2126+p{$2,$3}.g*0.7152+p{$2,$3}.b*0.0722))]" info:; }
# How much darker than the desktop far from any edge each edge of the hole is, 2 px in. The bar's foot is measured from the layout.
BARE=$("$SB" act --json sub runtime.layout --count 0 2>/dev/null | head -1 | jq -r '.data.bar_size')
BAND=10
TOP=$(( BARE + 2 )); BOT=$(( 1080 - BAND - 3 )); L=$(( BAND + 2 )); R=$(( 1920 - BAND - 3 ))
edges() { # edges <shot> → "top bottom left right" darkening
  local far; far=$(lum "$1" 960 600)
  echo "$(( far - $(lum "$1" 960 $TOP) )) $(( far - $(lum "$1" 960 $BOT) )) $(( far - $(lum "$1" $L 600) )) $(( far - $(lum "$1" $R 600) ))"
}
set_mode off
read -r t b l r < <(edges off); echo "off: $t $b $l $r"
for v in $t $b $l $r; do [ "$v" -le 2 ] || fail "off still darkens an edge ($t $b $l $r)"; done

set_mode static
read -r st sb sl sr < <(edges static); echo "static: $st $sb $sl $sr"
[ "$st" -gt $(( sb + 4 )) ] || fail "static: it should fall down: top $st, bottom $sb"
[ "$sb" -ge 2 ] || fail "static: nothing all round: bottom $sb"

set_mode follow
read -r ft fb fl fr < <(edges follow); echo "follow: $ft $fb $fl $fr"
[ $(( ft + fb + fl + fr )) -ge 10 ] || fail "follow casts nothing ($ft $fb $fl $fr)"

set_mode inward
read -r it ib il ir < <(edges inward); echo "inward: $it $ib $il $ir"
for v in $it $ib $il $ir; do
  [ "$v" -ge 10 ] || fail "inward: an edge has too little ($it $ib $il $ir)"
  [ "$(( v > it ? v - it : it - v ))" -le 4 ] || fail "inward is not even: $it $ib $il $ir"
done
[ -z "$("$SB" log 2>/dev/null | grep -E 'TypeError|ReferenceError')" ] || fail "QML errors: $("$SB" log | head -5)"
echo "test-sheet-shadow: OK"
