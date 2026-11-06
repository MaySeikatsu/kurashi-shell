#!/usr/bin/env bash
# The font mix (I176, K93; docs/ux/fonts.md), on nested niri: the preset builds a font and publishes it, the shell draws in it (the same
# bar differs from the font alone), the family is in the file, count changes the file, a font not installed is named and left out, too few
# say so and leave the plain family, `font.mix.preview` builds without touching the config, and off goes back pixel for pixel.
#   nix develop -c frontend/test-font-mix.sh
set -uo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
export KURASHI_NIRI_SB_NAME=${KURASHI_SB_PREFIX:-}font-mix
export KURASHI_NIRI_SB_OUT=${FONT_MIX_OUT:-$ROOT/frontend/shots/font-mix}
OUT=$KURASHI_NIRI_SB_OUT
SB="$ROOT/tools/bench/niri-sandbox.sh"
mkdir -p "$OUT"
fail() { echo "test-font-mix: $*" >&2; "$SB" stop >/dev/null 2>&1; exit 1; }
trap '"$SB" stop >/dev/null 2>&1' EXIT
CFG=$OUT/config.toml
conf() { # conf <toml lines of [theme.typography.mix]>
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
[edges.top]
start = ["launcher"]
center = ["island"]
end = ["clock"]
[theme.typography.mix]
$1
TOML
}
conf 'preset = "off"'
"$SB" start "$CFG" > /dev/null || fail "the sandbox did not start"
. "$OUT/niri-env.sh"
BIN=${KURASHI_BIN_DIR:-${CARGO_TARGET_DIR:-$ROOT/target}/debug}
K() { timeout 15 "$BIN/kurashi" "$@"; }
tok() { K sub theme --count 0 2>/dev/null | head -1 | python3 -c "import json,sys; print(json.dumps(json.load(sys.stdin)['data']['tokens'].get('$1')))"; }
until_tok() { for _ in $(seq 100); do [ "$(tok "$1")" = "$2" ] && return 0; sleep 0.1; done; return 1; }
set_conf() { conf "$1"; "$SB" config "$CFG" > /dev/null; }
shot() { "$SB" shot "$1" "0,0 1920x90" 1 > /dev/null; sleep 0.1; }
K act launcher.toggle > /dev/null 2>&1 || true
until_tok font.mix.state '"off"' || fail "off: state $(tok font.mix.state)"
[ "$(tok font.mix.file)" = '""' ] || fail "off: a file $(tok font.mix.file)"
sleep 1
shot off
PLAIN=$OUT/shots/off.png
PLAIN_AT=$(date +%H%M)
echo "off: nothing built"

set_conf 'preset = "handwriting"'
until_tok font.mix.state '"on"' || fail "the preset did not come on: $(tok font.mix.state) $(tok font.mix.missing)"
file=$(tok font.mix.file | tr -d '"'); fam=$(tok font.mix.family | tr -d '"')
[ -f "$file" ] || fail "no file $file"
case "$fam" in "Kurashi Mix "*) ;; *) fail "family $fam" ;; esac
fc-scan --format '%{family}\n' "$file" | grep -qxF "$fam" || fail "the file is not called $fam: $(fc-scan --format '%{family}' "$file")"
echo "handwriting: $(basename "$file"), $(stat -c %s "$file") bytes"
sleep 1.5
shot three
d=$(magick compare -metric AE "$PLAIN" "$OUT/shots/three.png" null: 2>&1 | cut -d' ' -f1)
[ "${d%.*}" -gt 20 ] || fail "the bar did not change with the mix ($d px)"
echo "drawn: the bar's text changed ($d px)"

set_conf $'preset = "handwriting"\ncount = 2'
first=$file
for _ in $(seq 100); do file=$(tok font.mix.file | tr -d '"'); [ -n "$file" ] && [ "$file" != "$first" ] && break; sleep 0.1; done
[ "$file" != "$first" ] || fail "count made no new font"
echo "count: another font ($(basename "$file"))"

set_conf $'preset = "custom"\ncount = 3\nfonts = ["Kalam", "No Such Font Kurashi", "Handlee"]'
until_tok font.mix.state '"on"' || fail "custom: $(tok font.mix.state)"
for _ in $(seq 50); do [ "$(tok font.mix.missing)" = '["No Such Font Kurashi"]' ] && break; sleep 0.1; done
[ "$(tok font.mix.missing)" = '["No Such Font Kurashi"]' ] || fail "the missing font is not named: $(tok font.mix.missing)"
echo "custom: a font not installed is named, the rest still mix"

set_conf $'preset = "custom"\ncount = 2\nfonts = ["No Such Font Kurashi", "Handlee"]'
until_tok font.mix.state '"too_few"' || fail "too few: $(tok font.mix.state)"
[ "$(tok font.mix.file)" = '""' ] || fail "too few: a file"
echo "too few: the plain family, and it says so"

preview=$(K act font.mix.preview '{"fonts":["Kalam","Gochi Hand"]}' | python3 -c "import json,sys; print(json.loads(sys.stdin.readline())['data']['file'])")
[ -f "$preview" ] || fail "preview: no file ($preview)"
until_tok font.mix.state '"too_few"' || fail "preview changed the state: $(tok font.mix.state)"
echo "preview: built, the config untouched"

set_conf 'preset = "off"'
until_tok font.mix.state '"off"' || fail "off again: $(tok font.mix.state)"
sleep 1.5
shot off2
# (the bar's clock moves on: the pixels are only comparable within a minute)
if [ "$(date +%H%M)" = "$PLAIN_AT" ]; then
  d=$(magick compare -metric AE "$PLAIN" "$OUT/shots/off2.png" null: 2>&1 | cut -d' ' -f1)
  [ "${d%.*}" -lt 40 ] || fail "off is not as it was ($d px)"
  echo "off again: as it was ($d px)"
else
  echo "off again: the state is off (the minute changed, no pixel check)"
fi
"$SB" log 12 | grep -v 'host portal' | grep -iE 'TypeError|ReferenceError|FontLoader' && fail "the frontend complained"
echo "test-font-mix: OK"
