#!/usr/bin/env bash
# The web dock's Local mode on nested niri (W78, docs/ux/webdock.md "Local mode"; the lead platform:
# tools/bench/niri-sandbox.sh), for review against the brief: the real kurashid and frontend, the timer and tasks mods on,
# two file:// sites (no network). For each scheme (light, dark):
#   local-online   the strip online: the sites, the switch showing `travel_explore`
#   local-strip    the switch pressed: Local, no view pinned yet — the strip's controls only
#   local-chooser  "+" in Local: the mods' views (timer, tasks, notes)
#   local-view     the timer's view pinned and open in the card
#   local-pinned   "+" again: the timer's row marked pinned
# Evidence to look at; it fails only when a step's document never comes or a log shows a QML problem.
# Shots in mods/webdock/shots/local/.   nix develop -c mods/webdock/test/shots-local.sh
set -uo pipefail
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
export KURASHI_NIRI_SB_NAME=${KURASHI_NIRI_SB_NAME:-${KURASHI_SB_PREFIX:-}webdock-local-niri}
OUT=${KURASHI_NIRI_SB_OUT:-${CARGO_TARGET_DIR:-$ROOT/target}/webdock-local}
export KURASHI_NIRI_SB_OUT=$OUT
SHOTS=$ROOT/mods/webdock/shots/local
PAGES=file://$ROOT/mods/webdock/test/pages
SB="$ROOT/tools/bench/niri-sandbox.sh"
mkdir -p "$OUT" "$SHOTS"
fail() { echo "shots-local: FAIL: $*" >&2; exit 1; }
trap '"$SB" stop > /dev/null 2>&1' EXIT
export KURASHI_WEBDOCK_DEBUG=1
magick -size 1920x1080 gradient:'#9cb7c9-#d9c7a3' "$OUT/wall.png"

conf() { # conf <scheme>
  cat > "$OUT/config.toml" <<T
[idle]
enabled = false
[theme.colors]
scheme = "$1"
[theme.motion]
profile = "none"
[edges.top]
bar = false
start = []
center = []
end = []
[edges.bottom]
bar = true
start = ["workspaces"]
center = ["island"]
end = ["clock", "quick"]
[mods]
enabled = ["webdock", "timer", "tasks"]
[mods.webdock]
pins = [
  { id = "site", title = "Site", target = "$PAGES/still.html#card" },
  { id = "other", title = "Other", target = "$PAGES/other.html" },
]
T
}
K() { "$SB" act "$@"; }
doc() { K --json sub mod.webdock --count 0 | python3 -c "import json,sys; d=json.loads(sys.stdin.readline()); d=d.get('data', d); print($1)"; }
wait_doc() { local i; for i in $(seq $(($2 * 2))); do [ "$(doc "$1" 2>/dev/null)" = True ] && return 0; sleep 0.5; done; return 1; }
logs() { (. "$OUT/niri-env.sh"; cat "$XDG_RUNTIME_DIR/qs.log"); }
last() { logs | grep -F "webdock-debug $1 " | tail -1 | sed "s/.*webdock-debug $1 //"; }
wait_log() { local i; for i in $(seq $(($2 * 4))); do [ -n "$(last "$1")" ] && return 0; sleep 0.25; done; return 1; }
# Controls and rows log their centre in the dock's window (right edge, from the top: the bar is at the bottom):
# <x> <y> <win w> <win h>; on screen that is (1920 - w + x, y).
shot() { "$SB" shot "$1" "$2" 1 > /dev/null; cp "$OUT/shots/$1.png" "$SHOTS/$1.png"; echo "shots-local: $SHOTS/$1.png"; }
EDGE="1340,0 580x1080"
qml_ok() {
  logs | grep -E 'TypeError|ReferenceError|is not a type|is not defined|Cannot assign|Binding loop' \
    | grep -v 'Unable to assign \[undefined\]' && fail "QML problems ($1)"
  return 0
}

for scheme in ${SCHEMES:-light dark}; do
  conf "$scheme"
  "$SB" start "$OUT/config.toml" "$OUT/wall.png" > /dev/null || fail "the sandbox did not start"
  sleep 2
  K set mods.webdock.content '"online"' > /dev/null
  K act webdock.pin '{"on":true}' > /dev/null
  K act webdock.toggle '{"output":"winit"}' > /dev/null
  wait_log "strip ctl:content" 10 || fail "the strip logged no switch ($scheme)"
  sleep 0.5; shot "local-online-$scheme" "$EDGE"
  read -r x y w h <<< "$(last "strip ctl:content")"
  "$SB" click $(( 1920 - w + x )) "$y" > /dev/null
  wait_doc "d.get('content') == 'local'" 5 || fail "the switch did not go local ($scheme)"
  sleep 0.8; shot "local-strip-$scheme" "$EDGE"
  read -r x y w h <<< "$(last "strip ctl:add")"
  "$SB" click $(( 1920 - w + x )) "$y" > /dev/null
  wait_log "local mod:timer:timer" 5 || fail "the chooser did not list the timer ($scheme)"
  sleep 0.5; shot "local-chooser-$scheme" "$EDGE"
  read -r _ lx ly w h <<< "$(last "local mod:timer:timer")"
  "$SB" click $(( 1920 - w + lx )) "$ly" > /dev/null
  wait_doc "d.get('shown') == 'timer' and d['mode'] == 'extended'" 5 || fail "the timer's view did not open ($scheme)"
  sleep 1; shot "local-view-$scheme" "$EDGE"
  read -r x y w h <<< "$(last "strip ctl:add")"
  "$SB" click $(( 1920 - w + x )) "$y" > /dev/null
  sleep 1; shot "local-pinned-$scheme" "$EDGE"
  qml_ok "$scheme"
  "$SB" stop > /dev/null
done
echo "shots-local: done"
