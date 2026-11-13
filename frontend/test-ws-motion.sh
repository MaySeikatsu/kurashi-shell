#!/usr/bin/env bash
# The focused workspace's mark travels (session 32, docs/ux/workspace-motion.md): on nested niri, three workspaces with a
# window each; a switch from the first to the third is shot mid-way and the mark's accent pixels are read along the keys'
# row. Liquid (the default) and stretch: mid-switch the mark spans more than one key; liquid pinches a neck between its
# ends; every style rests on the new key; motion off (`motion.spring.on = false`) is there at once.
#   nix develop -c frontend/test-ws-motion.sh
set -uo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
export KURASHI_NIRI_SB_NAME=${KURASHI_SB_PREFIX:-}ws-motion
export KURASHI_NIRI_SB_OUT=${WS_MOTION_OUT:-$ROOT/frontend/shots/ws-motion}
OUT=$KURASHI_NIRI_SB_OUT
SB="$ROOT/tools/bench/niri-sandbox.sh"
mkdir -p "$OUT"
fail() { echo "test-ws-motion: FAIL: $*" >&2; "$SB" stop >/dev/null 2>&1; exit 1; }
ok() { echo "test-ws-motion: ok: $*"; }
trap '"$SB" stop >/dev/null 2>&1' EXIT

# (previews off: niri nested in a window stops redrawing after a screencopy until something damages it)
CFG=$OUT/config.toml
printf '[idle]\nenabled = false\n\n[modules.workspaces]\npreviews = false\nmarks = "numbers"\n[modules.windows]\npreviews = false\n' > "$CFG"
"$SB" start "$CFG" > /dev/null || fail "the sandbox did not start"
for i in 1 2 3; do "$SB" niri action focus-workspace "$i" > /dev/null; "$SB" spawn foot; sleep 0.8; done
"$SB" niri action focus-workspace 1 > /dev/null
sleep 1.5
[ "$("$SB" act --json get modules.workspaces.motion | jq -r .value)" = goo ] || fail "liquid is not the default"

# The keys' row: the workspaces module at the bar's start (x 50..210, y 4..30 of the 1920x1080 output), shot at 4x.
GEO="50,4 160x26"
# measure <burst png> <frames>: per frame "left right mid_h end_h" of the accent run (the mark's red), as JSON lines.
measure() {
  magick "$1" ppm:- | python3 -I -c '
import sys, json
data = sys.stdin.buffer.read()
parts = data.split(b"\n", 3)
w, h = map(int, parts[1].split()); px = parts[3]
n = int(sys.argv[1]); fw = (w // n)
def red(x, y):
    i = (y * w + x) * 3
    r, g, b = px[i], px[i+1], px[i+2]
    return r > 140 and g < 90 and b < 100
for f in range(n):
    x0 = f * fw + 3
    cols = [sum(1 for y in range(h) if red(x0 + x, y)) for x in range(fw - 3)]
    on = [x for x, c in enumerate(cols) if c > h * 0.15]
    if not on: print(json.dumps(None)); continue
    l, r = on[0], on[-1]; mid = (l + r) // 2
    print(json.dumps({"l": l, "r": r, "mid": cols[mid], "ends": max(cols[l:l + (r - l) // 4 + 1] + [0])}))
' "$2"
}
switch_burst() { # switch_burst <name> <to>
  "$SB" burst "$1" "$GEO" 4 12 0.01 -- "$SB" niri action focus-workspace "$2" > /dev/null
}

# At rest: one key wide.
"$SB" shot rest "$GEO" 4 > /dev/null
REST=$(measure "$OUT/shots/rest.png" 1)
KEYW=$(echo "$REST" | jq '.r - .l')
[ "$KEYW" -gt 40 ] || fail "no mark at rest ($REST)"
ok "the mark rests on the focused key (${KEYW} px at 4x)"

check_style() { # check_style <style> <stretches 0|1> <neck 0|1>
  "$SB" act set "modules.workspaces.motion=$1" > /dev/null || fail "set $1"
  sleep 0.8
  switch_burst "$1" 3
  local rows; rows=$(measure "$OUT/shots/$1.png" 12)
  local widest; widest=$(echo "$rows" | jq -s '[.[] | select(. != null) | .r - .l] | max')
  local last; last=$(echo "$rows" | tail -1)
  [ "$last" != null ] || fail "$1: no mark after the switch"
  # rests on the third key: right of where it started, one key wide
  [ "$(echo "$last" | jq '.l')" -gt "$(echo "$REST" | jq '.l + 100')" ] || fail "$1: the mark did not land on the third key ($last)"
  [ "$(echo "$last" | jq '.r - .l')" -lt $(( KEYW * 13 / 10 )) ] || fail "$1: the mark did not settle to one key ($last)"
  if [ "$2" = 1 ]; then
    [ "$widest" -gt $(( KEYW * 3 / 2 )) ] || fail "$1: the mark never drew out (widest $widest, key $KEYW)"
  fi
  if [ "$3" = 1 ]; then
    echo "$rows" | jq -e -s '[.[] | select(. != null) | select(.r - .l > '"$(( KEYW * 3 / 2 ))"') | select(.mid < .ends * 0.85)] | length > 0' > /dev/null \
      || fail "$1: no neck while drawn out ($(echo "$rows" | jq -c -s .))"
  fi
  ok "$1: travels (widest ${widest} px) and rests on the third key"
  "$SB" niri action focus-workspace 1 > /dev/null
  sleep 1
}
check_style goo 1 1
check_style stretch 1 0
check_style slide 0 0

# Motion off (the a11y setting, which forces the profile to "reduced": no springs): there at once.
"$SB" act set modules.workspaces.motion=goo a11y.reduce_motion=true > /dev/null || fail "set a11y.reduce_motion"
sleep 1
switch_burst off 3
rows=$(measure "$OUT/shots/off.png" 12)
widest=$(echo "$rows" | jq -s '[.[] | select(. != null) | .r - .l] | max')
[ "$widest" -lt $(( KEYW * 13 / 10 )) ] || fail "reduced motion: the mark drew out ($widest)"
ok "reduced motion: the mark does not draw out"

if "$SB" log 40 | grep -v -e portal -e 'Unable to assign \[undefined\]' | grep -E 'TypeError|ReferenceError|Binding loop|is not a type' > /dev/null; then
  "$SB" log 40 >&2
  fail "QML errors"
fi
echo "test-ws-motion: PASS"
