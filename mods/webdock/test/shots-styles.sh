#!/usr/bin/env bash
# The web dock's page styles on nested niri (W69, I468; the lead platform: tools/bench/niri-sandbox.sh), for review
# against docs/ux/webdock.md "Page styles": the real kurashid and frontend, the web host as the daemon starts it, a still
# file:// page (no network). For each scheme (light, dark) and style (phone, notebook, plain): the card's opening held at
# three points of its motion and at rest (KURASHI_WEBDOCK_HOLD, a file the host watches: shots by progress, not by
# timing), the large size (the phone's tablet, held half-way and at rest), the shell's own card for a view pin and a
# page that fails to load.
# Evidence to look at; it fails only when the host never gets ready or logs a QML problem. Shots in
# mods/webdock/shots/styles/ (each a strip, left to right).
#   nix develop -c mods/webdock/test/shots-styles.sh [style ...]
# One sandbox at a time (its name: ${KURASHI_SB_PREFIX}webdock-styles-niri).
set -uo pipefail
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
export KURASHI_NIRI_SB_NAME=${KURASHI_SB_PREFIX:-}webdock-styles-niri
OUT=${STYLES_OUT:-${CARGO_TARGET_DIR:-$ROOT/target}/webdock-styles}
export KURASHI_NIRI_SB_OUT=$OUT
SHOTS=$ROOT/mods/webdock/shots/styles
PAGES=file://$ROOT/mods/webdock/test/pages
SB="$ROOT/tools/bench/niri-sandbox.sh"
STYLES=${*:-phone notebook plain}
mkdir -p "$OUT" "$SHOTS"
fail() { echo "shots-styles: FAIL: $*" >&2; exit 1; }
trap '"$SB" stop > /dev/null 2>&1' EXIT
HOLD=$OUT/hold
: > "$HOLD"
# The daemon hands its environment to the hosts it starts: the hold file and the test logs reach the web host.
export KURASHI_WEBDOCK_HOLD=$HOLD KURASHI_WEBDOCK_DEBUG=1
magick -size 1920x1080 gradient:'#9cb7c9-#d9c7a3' "$OUT/wall.png"

conf() { # conf <scheme> <style> <size>
cat > "$OUT/config.toml" <<T
[idle]
enabled = false
[theme.colors]
scheme = "$1"
[mods]
enabled = ["webdock", "weather"]
[mods.webdock]
page_style = "$2"
pinned = true
pins = [
  { id = "still", title = "Still", target = "$PAGES/still.html#still" },
  { id = "weather", title = "Weather", target = "mod:weather:weather" },
  { id = "bad", title = "Broken", target = "file:///nonexistent/page.html" },
]
T
}
K() { "$SB" act "$@"; }
doc() { K --json sub mod.webdock --count 0 | python3 -c "import json,sys; d=json.loads(sys.stdin.readline()); d=d.get('data', d); print($1)"; }
hostlog() { (. "$OUT/niri-env.sh"; cat "$XDG_STATE_HOME/kurashi/webdock/host-web.log" 2>/dev/null); }
hold() { echo "$*" > "$HOLD"; sleep 0.7; }
# The card's place on the 1920×1080 output, the strip (56) on the right: a phone 412 wide, as tall as 2 × 412 allows.
REGION="1400,90 520x900"
shot() { "$SB" shot "$1" "$REGION" 1 > /dev/null; }
strip() { # strip <out> <in ...>: side by side, a 3 px rule between
  local out=$1; shift
  magick "$@" -background '#d03030' -splice 3x0 +append "$SHOTS/$out.png" && rm -f "$@"
  echo "shots-styles: $SHOTS/$out.png"
}

for scheme in ${SCHEMES:-light dark}; do
  conf "$scheme" phone phone
  "$SB" start "$OUT/config.toml" "$OUT/wall.png" > /dev/null || fail "the sandbox did not start"
  for style in $STYLES; do
    conf "$scheme" "$style" phone
    "$SB" config "$OUT/config.toml"
    sleep 2
    K act webdock.open '{"pin":"still"}' > /dev/null
    for i in $(seq 120); do
      [ "$(doc "d['host']['state'] == 'ready' and [p for p in d['pins'] if p['id'] == 'still'][0].get('loaded') == True")" = True ] && break
      sleep 0.5
    done
    [ "$(doc "d['host']['state']")" = ready ] || fail "the host never got ready ($style, $scheme)"
    [ "$(doc "d.get('page_style', 'phone')")" = "$style" ] || fail "mod.webdock does not say page_style $style"
    sleep 2
    # The opening, held at three points, then at rest.
    for p in 0.3 0.55 0.8; do hold "open $p"; shot "$style-$scheme-$p"; done
    hold ""
    sleep 1
    shot "$style-$scheme-rest"
    strip "$style-$scheme-open" "$OUT"/shots/"$style-$scheme"-{0.3,0.55,0.8,rest}.png
    # The large size: held half-way, then at rest (the whole output).
    K act webdock.size '{"size":"large"}' > /dev/null
    sleep 2
    hold "wide 0.5"
    "$SB" shot "$style-$scheme-wide-half" "0,0 1920x1080" 0.5 > /dev/null
    hold ""
    sleep 1.5
    "$SB" shot "$style-$scheme-wide-rest" "0,0 1920x1080" 0.5 > /dev/null
    strip "$style-$scheme-large" "$OUT/shots/$style-$scheme-wide-half.png" "$OUT/shots/$style-$scheme-wide-rest.png"
    K act webdock.size '{"size":"phone"}' > /dev/null
    sleep 1.5
    # The states (brief "States (every style)"): the shell's own card for a view pin, then a page that fails to load.
    K act webdock.open '{"pin":"weather"}' > /dev/null
    sleep 2.5
    shot "$style-$scheme-view"
    K act webdock.open '{"pin":"bad"}' > /dev/null
    sleep 3
    shot "$style-$scheme-error"
    strip "$style-$scheme-states" "$OUT/shots/$style-$scheme-view.png" "$OUT/shots/$style-$scheme-error.png"
    K act webdock.collapse '{}' > /dev/null
    sleep 1
  done
  hostlog > "$OUT/host-$scheme.log"
  # Which panel form the profile gave plain (its open and close lines, test-only).
  grep -o "webdock-debug mapped [a-z]* plain [a-z]*:[a-z]*" "$OUT/host-$scheme.log" | sort | uniq -c || true
  "$SB" stop > /dev/null 2>&1
  if grep -E 'WARN.{0,12}(scene|qml)|TypeError|ReferenceError|is not a type|is not defined|Binding loop' "$OUT/host-$scheme.log"; then
    fail "QML problems in the host ($OUT/host-$scheme.log)"
  fi
done
echo "shots-styles: done"
