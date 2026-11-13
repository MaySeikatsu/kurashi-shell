#!/usr/bin/env bash
# The OSD (session 33, I527; docs/ux/osd.md) on nested niri with the real daemon: `osd.show` draws each kind (the sandbox has
# no audio or backlight), a keyboard layout switch draws the layout's own; it goes after its timeout and leaves no layer
# surface; ten events in a row are one OSD; a kind switched off shows nothing; the places; shots light and dark, two looks.
#   nix develop -c frontend/test-osd.sh
set -uo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
export KURASHI_NIRI_SB_NAME=${KURASHI_SB_PREFIX:-}osd
export KURASHI_NIRI_SB_OUT=${OSD_OUT:-$ROOT/frontend/shots/osd}
OUT=$KURASHI_NIRI_SB_OUT
SB="$ROOT/tools/bench/niri-sandbox.sh"
mkdir -p "$OUT"
fail() { echo "test-osd: FAIL: $*" >&2; "$SB" stop >/dev/null 2>&1; exit 1; }
ok() { echo "test-osd: ok: $*"; }
trap '"$SB" stop >/dev/null 2>&1' EXIT
. "$ROOT/frontend/test-lib.sh"

CFG=$OUT/config.toml
printf '[idle]\nenabled = false\n\n[theme]\nlook = "washi"\n\n[osd]\ntimeout_ms = 1200\n' > "$CFG"
"$SB" start "$CFG" > /dev/null || fail "the sandbox did not start"
K() { "$SB" act "$@"; }
# The OSD's layer surfaces on the nested niri (its namespace).
osd_layers() { "$SB" niri layers 2>/dev/null | grep -c 'kurashi-osd' || true; }
show() { K act osd.show "$1" > /dev/null || fail "osd.show $1"; }
sleep 1.5
[ "$(osd_layers)" = 0 ] || fail "an OSD at start"
ok "nothing at start"

show '{"kind":"volume","label":"Speakers","icon":"volume_down","value":0.42}'
wait_until 4 sh -c "[ \"\$(\"$SB\" niri layers 2>/dev/null | grep -c kurashi-osd)\" = 1 ]" || fail "the volume OSD did not map"
sleep 0.5; "$SB" shot osd-volume "660,940 600x110" 1 > /dev/null
wait_until 5 sh -c "[ \"\$(\"$SB\" niri layers 2>/dev/null | grep -c kurashi-osd)\" = 0 ]" || fail "the OSD stayed after its timeout"
ok "volume: shown, then gone with no layer left"

for v in 0.1 0.2 0.3 0.4 0.5 0.6 0.7 0.8 0.9 1.0; do
  show "{\"kind\":\"volume\",\"label\":\"Speakers\",\"icon\":\"volume_up\",\"value\":$v}"; sleep 0.12
done
[ "$(osd_layers)" = 1 ] || fail "a held key made $(osd_layers) OSDs"
ok "ten events in a row: one OSD that follows"
wait_until 5 sh -c "[ \"\$(\"$SB\" niri layers 2>/dev/null | grep -c kurashi-osd)\" = 0 ]" || fail "the held OSD stayed"

show '{"kind":"volume","label":"Muted","sub":"Speakers","icon":"volume_off","value":0.5,"muted":true}'; sleep 0.6
"$SB" shot osd-muted "660,940 600x110" 1 > /dev/null; sleep 1.6
show '{"kind":"mic","label":"Microphone muted","sub":"Headset","icon":"mic_off","muted":true}'; sleep 0.6
"$SB" shot osd-mic "660,940 600x110" 1 > /dev/null; sleep 1.6
show '{"kind":"brightness","label":"Brightness","icon":"brightness_6","value":0.65}'; sleep 0.6
"$SB" shot osd-brightness "660,940 600x110" 1 > /dev/null; sleep 1.6
ok "muted, mic and brightness drawn (shots)"

# The keyboard layout, from the compositor (the sandbox's niri has two layouts, or gets them here).
"$SB" niri action switch-layout next > /dev/null
if wait_until 4 sh -c "[ \"\$(\"$SB\" niri layers 2>/dev/null | grep -c kurashi-osd)\" = 1 ]"; then
  sleep 0.4; "$SB" shot osd-layout "660,920 600x130" 1 > /dev/null
  ok "a layout switch shows the layout"
  sleep 1.8
  K set osd.layout=false > /dev/null; sleep 0.6
  "$SB" niri action switch-layout next > /dev/null; sleep 1
  [ "$(osd_layers)" = 0 ] || fail "osd.layout = false still showed the layout"
  ok "a kind switched off shows nothing"
else
  echo "test-osd: note: no layout OSD (the sandbox's niri has one layout)"
fi

K set osd.place='"top"' > /dev/null; sleep 0.6
show '{"kind":"volume","label":"Speakers","icon":"volume_up","value":0.7}'; sleep 0.6
"$SB" shot osd-top "660,0 600x140" 1 > /dev/null
d=$(magick "$OUT/shots/osd-top.png" -format '%[fx:standard_deviation]' info: 2>/dev/null || echo 0)
ok "place top (shot)"; sleep 1.6
# Session 33 (the user: "an attached mode, as Caelestia has"): joined to the right edge, upright; then the bottom edge.
K set osd.place='"edge"' osd.edge='"right"' > /dev/null; sleep 0.6
show '{"kind":"volume","label":"Speakers","icon":"volume_up","value":0.62}'; sleep 0.7
"$SB" shot osd-edge-right "1760,240 160x600" 1 > /dev/null
wait_until 5 sh -c "[ \"\$(\"$SB\" niri layers 2>/dev/null | grep -c kurashi-osd)\" = 0 ]" || fail "the attached OSD stayed"
K set osd.edge='"bottom"' > /dev/null; sleep 0.6
show '{"kind":"brightness","label":"Brightness","icon":"brightness_6","value":0.4}'; sleep 0.7
"$SB" shot osd-edge-bottom "640,960 640x120" 1 > /dev/null
ok "attached: right (upright) and bottom (shots), gone after its timeout"; sleep 1.6
K set osd.place='"bottom"' theme.colors.scheme='"dark"' > /dev/null; sleep 1
show '{"kind":"volume","label":"Speakers","icon":"volume_up","value":0.7}'; sleep 0.6
"$SB" shot osd-dark "660,940 600x110" 1 > /dev/null; sleep 1.6
K set theme.look='"kami"' > /dev/null; sleep 1.5
show '{"kind":"brightness","label":"Brightness","icon":"brightness_6","value":0.3}'; sleep 0.6
"$SB" shot osd-kami-dark "660,940 600x110" 1 > /dev/null
ok "dark and kami (shots)"

if "$SB" log 40 | grep -v -e portal | grep -E 'TypeError|ReferenceError|Binding loop|is not a type|Cannot assign' > /dev/null; then
  "$SB" log 40 >&2; fail "QML errors"
fi
echo "test-osd: PASS (shots in $OUT/shots)"
