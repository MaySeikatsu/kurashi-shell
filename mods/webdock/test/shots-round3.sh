#!/usr/bin/env bash
# The web dock's round three on nested niri (W76, docs/ux/webdock.md "Round three"; the lead platform:
# tools/bench/niri-sandbox.sh), for review against the brief: the real kurashid and frontend, the web host as the daemon
# starts it, file:// pages (no network), a bottom bar. For each scheme (light, dark):
#   round3-resize   the edge card dragged wider (a remembered box), its grip lit under the pointer
#   round3-keep     the edge card's keep-open key lit (the dock pinned)
#   round3-field    "+" at the edge: the empty temporary page, its address field open in the title
#   round3-typed    a path typed in the field
#   round3-temp     the temporary page loaded, "Pin" beside the title
#   round3-menu     a pin's menu on the strip with Reload, Update pin to this page, Unpin but keep open
#   round3-card     "+" in the bar's card: the field in the card's navigation row, the keep-open key beside it
#   round3-cardgrip the bar card's grip lit at the well's top edge
# Evidence to look at; it fails only when the host never gets ready or a log shows a QML problem.
# Shots in mods/webdock/shots/round3/.   nix develop -c mods/webdock/test/shots-round3.sh
set -uo pipefail
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
export KURASHI_NIRI_SB_NAME=${KURASHI_NIRI_SB_NAME:-${KURASHI_SB_PREFIX:-}webdock-r3-niri}
OUT=${KURASHI_NIRI_SB_OUT:-${CARGO_TARGET_DIR:-$ROOT/target}/webdock-r3}
export KURASHI_NIRI_SB_OUT=$OUT
SHOTS=$ROOT/mods/webdock/shots/round3
PAGES=file://$ROOT/mods/webdock/test/pages
SB="$ROOT/tools/bench/niri-sandbox.sh"
mkdir -p "$OUT" "$SHOTS"
fail() { echo "shots-round3: FAIL: $*" >&2; exit 1; }
trap '"$SB" stop > /dev/null 2>&1' EXIT
export KURASHI_WEBDOCK_DEBUG=1
magick -size 1920x1080 gradient:'#9cb7c9-#d9c7a3' "$OUT/wall.png"

conf() { # conf <scheme>
  cat > "$OUT/config.toml" <<T
[idle]
enabled = false
[theme.colors]
scheme = "$1"
[edges.top]
bar = false
start = []
center = []
end = []
[edges.bottom]
bar = true
start = ["workspaces"]
center = ["island"]
end = ["mod:webdock:webdock", "clock", "quick"]
[mods]
enabled = ["webdock"]
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
logs() { (. "$OUT/niri-env.sh"; cat "$XDG_STATE_HOME/kurashi/webdock/host-web.log" 2>/dev/null; echo; cat "$XDG_RUNTIME_DIR/qs.log"); }
last() { logs | grep -F "$1" | tail -1 | sed "s/.*$1//"; }
keys() { (. "$OUT/sway-env.sh"; python3 -I "$ROOT/tools/bench/wl_keys.py" "$@"); }
rclick() { (. "$OUT/sway-env.sh"; python3 -I "$ROOT/tools/bench/wl_pointer.py" click "$1" "$2" right); }
shot() { "$SB" shot "$1" "$2" 1 > /dev/null; cp "$OUT/shots/$1.png" "$SHOTS/$1.png"; echo "shots-round3: $SHOTS/$1.png"; }
EDGE="1380,60 540x1000"
qml_ok() {
  logs | grep -E 'TypeError|ReferenceError|is not a type|is not defined|Cannot assign|Binding loop' \
    | grep -v 'Unable to assign \[undefined\]' && fail "QML problems ($1)"
  return 0
}

for scheme in ${SCHEMES:-light dark}; do
  conf "$scheme"
  "$SB" start "$OUT/config.toml" "$OUT/wall.png" > /dev/null || fail "the sandbox did not start"
  sleep 2
  cp "$ROOT/mods/webdock/test/pages/other.html" "$OUT/o.html"
  # ---- the edge card: a remembered box, its grip under the pointer; the keep-open key ----
  K act webdock.pin '{"on":true}' > /dev/null
  K act webdock.open '{"pin":"site"}' > /dev/null
  wait_doc "d['host']['state'] == 'ready' and [p for p in d['pins'] if p['id'] == 'site'][0].get('loaded') == True" 60 \
    || fail "the host never got ready ($scheme)"
  K act webdock.resize '{"output":"winit","width":480,"height":760}' > /dev/null
  wait_doc "d.get('sizes', {}).get('winit') == {'width': 480, 'height': 760}" 10 || fail "the box was not written ($scheme)"
  sleep 2
  read -r gx gy gw gh aw ah <<< "$(last 'webdock-debug grips winit ')"
  [ -n "${aw:-}" ] || fail "the edge card logged no grips ($scheme)"
  wx=$(( 1920 - 56 - aw ))
  "$SB" move $(( wx + gx )) $(( gy + gh / 2 )); sleep 0.8
  shot "round3-resize-$scheme" "$EDGE"
  "$SB" move 600 400; sleep 0.5
  shot "round3-keep-$scheme" "1380,760 540x200"
  # ---- "+" at the edge: the empty field, a typed path, the loaded temporary page with Pin ----
  K act webdock.browse '{"place":"edge","output":"winit"}' > /dev/null
  sleep 2
  shot "round3-field-$scheme" "$EDGE"
  keys $(python3 -I "$ROOT/mods/webdock/test/keytokens.py" "$OUT/o.html")
  sleep 0.6
  shot "round3-typed-$scheme" "$EDGE"
  keys return
  wait_doc "[p for p in d['pins'] if p.get('temporary') and p.get('loaded')] != []" 15 || fail "the + page never loaded ($scheme)"
  sleep 1.5
  shot "round3-temp-$scheme" "$EDGE"
  # ---- a pin's menu on the strip ----
  K act webdock.open '{"pin":"site"}' > /dev/null
  sleep 1.5
  read -r sx sy sww swh <<< "$(last 'webdock-debug strip site ')"
  [ -n "${swh:-}" ] || fail "the strip logged no tile ($scheme)"
  K act webdock.collapse > /dev/null
  sleep 1
  rclick $(( 1920 - sww + sx )) "$sy"            # (a bottom bar: the dock's window starts at the top)
  sleep 1.5
  shot "round3-menu-$scheme" "1300,60 620x1000"
  K act webdock.hide > /dev/null
  K act webdock.pin '{"on":false}' > /dev/null
  K act webdock.resize '{"output":"winit"}' > /dev/null
  "$SB" move 600 400
  sleep 1
  # ---- the bar's card: "+" (the field in the navigation row, the keep-open key), its grip ----
  K act mod.panel.open '{"id":"webdock","panel":"webdock"}' > /dev/null
  wait_doc "'place' in d.get('card', {})" 15 || fail "the card never placed its page ($scheme)"
  K act webdock.browse '{"place":"card"}' > /dev/null
  sleep 2.5
  read -r px py pw ph <<< "$(last 'webdock-panel card ' | sed 's/.* panel //' | cut -d' ' -f1-4)"
  [ -n "${ph:-}" ] || fail "the panel logged no place ($scheme)"
  region="$(( px - 40 )),$(( py - 60 )) $(( pw + 80 > 1920 - px + 40 ? 1920 - px + 40 : pw + 80 ))x$(( 1080 - py + 60 ))"
  shot "round3-card-$scheme" "$region"
  read -r _ wx wy ww wh _ <<< "$(last 'webdock-panel card ')"
  "$SB" move $(( wx + ww / 2 )) $(( wy + 3 )); sleep 0.8
  shot "round3-cardgrip-$scheme" "$region"
  qml_ok "$scheme"
  "$SB" stop > /dev/null
done
echo "shots-round3: done"
