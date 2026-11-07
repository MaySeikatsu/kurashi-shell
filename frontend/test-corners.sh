#!/usr/bin/env bash
# Corners that match (K96, docs/ux/corners.md), on nested niri under washi (radius 9) with a frame as thick as that radius, where the
# frame once had no inner corner at all:
#   match   frame, joins, windows, widgets and dock all publish the one radius; the hole's corner is drawn (pixels); the screen's outer
#           corner is the radius plus the band; niri's windows take it
#   own     each surface's own value reaches its own place and no other: the frame's, the windows', the joins'; back to Auto
#   nix develop -c frontend/test-corners.sh
# Binaries from $KURASHI_BIN_DIR, else $CARGO_TARGET_DIR/debug. Shots: frontend/shots/corners/.
set -uo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
export KURASHI_NIRI_SB_NAME=${KURASHI_SB_PREFIX:-}corners
export KURASHI_NIRI_SB_OUT=${CORNERS_OUT:-$ROOT/frontend/shots/corners}
OUT=$KURASHI_NIRI_SB_OUT
SB="$ROOT/tools/bench/niri-sandbox.sh"
mkdir -p "$OUT"
fail() { echo "test-corners: $*" >&2; "$SB" stop >/dev/null 2>&1; exit 1; }
trap '"$SB" stop >/dev/null 2>&1' EXIT

CFG=$OUT/config.toml
conf() { # conf [extra lines under theme.shape]
  printf '[idle]\nenabled = false\n\n[theme]\nstyle = "washi"\nexport = ["niri"]\n\n[theme.shape]\n%b\n[layout.frame]\nenabled = true\nthickness = 10\n\n[modules.windows]\npreviews = false\n[modules.workspaces]\npreviews = false\n' "${1:-}" > "$CFG"
}
conf
"$SB" start "$CFG" > /dev/null || fail "the sandbox did not start"
. "$OUT/niri-env.sh"
KDL=$XDG_CONFIG_HOME/niri/kurashi.kdl
tok() { "$SB" act --json sub theme --count 0 2>/dev/null | head -1 | jq -r ".data.tokens[\"radius.$1\"]"; }
lay() { "$SB" act --json sub runtime.layout --count 0 2>/dev/null | head -1 | jq -r ".data$1"; }
until_is() { # until_is <what> <want> <cmd…>
  local what=$1 want=$2 got=; shift 2
  for _ in $(seq 100); do got=$("$@"); [ "$got" = "$want" ] && return 0; sleep 0.1; done
  fail "$what is $got, not $want"
}
winr() { sed -n 's/.*geometry-corner-radius \([0-9]*\).*/\1/p' "$KDL" | head -1; }
for _ in $(seq 600); do OUTPUT=$("$SB" act --json sub runtime.layout --count 0 2>/dev/null | head -1 | jq -r '.data.outputs | keys | map(select(. != "*")) | .[0] // empty'); [ -n "$OUTPUT" ] && break; sleep 0.1; done
[ -n "${OUTPUT:-}" ] || fail "no output in the layout"

R=$(tok lg)
[ "$R" = 9 ] || fail "washi's radius is $R, not 9: this suite is about a band as thick as the radius"
for t in frame join window widget dock; do
  [ "$(tok $t)" = 9 ] || fail "radius.$t is $(tok $t), not the one radius"
done
until_is "the hole's radius" 9 lay ".outputs[\"$OUTPUT\"].frame.radius"
until_is "the screen's outer corner" 19 lay ".outputs[\"$OUTPUT\"].frame.screen_radius"
until_is "the windows' radius" 9 winr
sleep 2
"$SB" shot corner "0,1050 40x30" 4 > /dev/null
# The hole's bottom-left corner: 1 px in from the band's inner edge, on the diagonal, is the band's paper while it is rounded.
SHOT=$OUT/shots/corner.png
px() { magick "$SHOT" -format "%[fx:int(255*p{$1,$2}.r)] %[fx:int(255*p{$1,$2}.g)] %[fx:int(255*p{$1,$2}.b)]" info:; }
set -- $(px 44 76)  # (11, 1069: inside a square hole; the band's paper in a rounded one)
[ "$1" -ge 200 ] || fail "the hole's corner is square: not the band's paper there ($*)"
echo "match: every surface publishes 9; the hole has its corner; the screen's is 19; niri's windows take 9"

conf 'radius_frame = 24\nradius_windows = 4\nradius_joins = 14\nradius_widgets = 20\nradius_dock = 6\n'
"$SB" config "$CFG"
until_is "the frame's own" 24 lay ".outputs[\"$OUTPUT\"].frame.radius"
until_is "the screen's outer corner" 34 lay ".outputs[\"$OUTPUT\"].frame.screen_radius"
until_is "the windows' own" 4 winr
until_is "the joins' own" 14 lay ".join_radius"
[ "$(tok lg)" = 9 ] || fail "a surface's own moved the one radius"
[ "$(tok widget)" = 20 ] || fail "the widgets' own: $(tok widget)"
[ "$(tok dock)" = 6 ] || fail "the dock's own: $(tok dock)"
echo "own: each surface's value reaches its own place"

conf 'corners = "none"\nradius_frame = 24\n'
"$SB" config "$CFG"
until_is "the frame under a square look" 0 lay ".outputs[\"$OUTPUT\"].frame.radius"
until_is "the outer corner under a square look" 0 lay ".outputs[\"$OUTPUT\"].frame.screen_radius"
echo "square: a square look squares them all"
[ -z "$("$SB" log 2>/dev/null | grep -E 'TypeError|ReferenceError')" ] || fail "QML errors: $("$SB" log | head -5)"
echo "test-corners: OK"
