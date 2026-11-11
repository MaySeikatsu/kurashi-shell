#!/usr/bin/env bash
# The web dock's page in the bar's card on nested niri (W72, I482; the lead platform: tools/bench/niri-sandbox.sh), for
# review against docs/ux/webdock.md "In the bar's card": the real kurashid and frontend, the web host as the daemon starts
# it, file:// pages (no network). For each scheme (light, dark): the card from a bottom bar's right corner (the user's
# layout) with a page, the same card on a load error, the card in each `card_size` (W73: card-{phone,tablet,wide}; W74:
# card-dock, the default, its size key's tip, and card-pressed after one press of the key), the card from a top bar, and
# the card with no pin. Evidence to look
# at; it fails only when the host never gets ready or a log shows a QML problem. Shots in mods/webdock/shots/card/.
#   nix develop -c mods/webdock/test/shots-card.sh
# One sandbox at a time (its name: ${KURASHI_NIRI_SB_NAME:-${KURASHI_SB_PREFIX}webdock-card-niri}).
set -uo pipefail
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
export KURASHI_NIRI_SB_NAME=${KURASHI_NIRI_SB_NAME:-${KURASHI_SB_PREFIX:-}webdock-card-niri}
OUT=${KURASHI_NIRI_SB_OUT:-${CARGO_TARGET_DIR:-$ROOT/target}/webdock-card}
export KURASHI_NIRI_SB_OUT=$OUT
SHOTS=$ROOT/mods/webdock/shots/card
PAGES=file://$ROOT/mods/webdock/test/pages
SB="$ROOT/tools/bench/niri-sandbox.sh"
mkdir -p "$OUT" "$SHOTS"
fail() { echo "shots-card: FAIL: $*" >&2; exit 1; }
trap '"$SB" stop > /dev/null 2>&1' EXIT
export KURASHI_WEBDOCK_DEBUG=1
magick -size 1920x1080 gradient:'#9cb7c9-#d9c7a3' "$OUT/wall.png"

conf() { # conf <scheme> <bar edge> <pins: yes|no> [card size]
  local bars pins="" size=""
  [ -n "${4:-}" ] && size="card_size = \"$4\""
  if [ "$2" = bottom ]; then
    bars='[edges.top]
bar = false
start = []
center = []
end = []
[edges.bottom]
bar = true
start = ["workspaces"]
center = ["island"]
end = ["mod:webdock:webdock", "clock", "quick"]'
  else
    bars='[edges.top]
start = ["workspaces"]
center = ["island"]
end = ["mod:webdock:webdock", "clock", "quick"]'
  fi
  [ "$3" = yes ] && pins="pins = [
  { id = \"site\", title = \"Site\", target = \"$PAGES/still.html#card\" },
  { id = \"bad\", title = \"Broken\", target = \"file:///nonexistent/page.html\" },
]"
  cat > "$OUT/config.toml" <<T
[idle]
enabled = false
[theme.colors]
scheme = "$1"
$bars
[mods]
enabled = ["webdock"]
[mods.webdock]
$size
$pins
T
}
# The card's region from the panel's last report (W73: the card's size varies): 40 px round the panel, down to the bar.
card_region() {
  local line px py pw
  line=$(logs | grep -F 'webdock-panel card ' | grep -v 'webdock-panel card off' | tail -1 | sed 's/.* panel //')
  read -r px py pw _ <<< "$line"
  [ -n "$px" ] || { echo "1380,240 540x840"; return; }
  echo "$(( px - 40 < 0 ? 0 : px - 40 )),$(( py - 60 < 0 ? 0 : py - 60 )) $(( pw + 80 > 1920 - px + 40 ? 1920 - px + 40 : pw + 80 ))x$(( 1080 - (py - 60 < 0 ? 0 : py - 60) ))"
}
K() { "$SB" act "$@"; }
doc() { K --json sub mod.webdock --count 0 | python3 -c "import json,sys; d=json.loads(sys.stdin.readline()); d=d.get('data', d); print($1)"; }
wait_doc() { local i; for i in $(seq $(($2 * 2))); do [ "$(doc "$1" 2>/dev/null)" = True ] && return 0; sleep 0.5; done; return 1; }
logs() { (. "$OUT/niri-env.sh"; cat "$XDG_STATE_HOME/kurashi/webdock/host-web.log" 2>/dev/null; echo; cat "$XDG_RUNTIME_DIR/qs.log"); }
open_card() {
  K act ui.close > /dev/null; sleep 0.8
  K act mod.panel.open '{"id":"webdock","panel":"webdock"}' > /dev/null
}
# The bar card's region: the right part of the output, from the bar's side.
shot() { "$SB" shot "$1" "$2" 1 > /dev/null; cp "$OUT/shots/$1.png" "$SHOTS/$1.png"; echo "shots-card: $SHOTS/$1.png"; }

for scheme in ${SCHEMES:-light dark}; do
  conf "$scheme" bottom yes
  "$SB" start "$OUT/config.toml" "$OUT/wall.png" > /dev/null || fail "the sandbox did not start"
  sleep 2
  open_card
  wait_doc "d['host']['state'] == 'ready' and [p for p in d['pins'] if p['id'] == 'site'][0].get('loaded') == True" 60 \
    || fail "the host never got ready ($scheme)"
  wait_doc "'place' in d.get('card', {})" 10 || fail "the card never placed its page ($scheme)"
  sleep 2
  shot "card-bottom-$scheme" "$(card_region)"
  K act webdock.card_select '{"pin":"bad"}' > /dev/null
  sleep 3
  shot "card-error-$scheme" "$(card_region)"
  K act webdock.card_select '{"pin":"site"}' > /dev/null
  # W73 (docs/ux/webdock.md "The card's size"): the sizes from the bottom bar, each fully on screen; W74: the default
  # (`dock`, the edge card's size) first, then one press of the card's size key on screen (card-pressed: phone).
  for size in ${SIZES:-dock phone tablet wide}; do
    conf "$scheme" bottom yes "$size"
    "$SB" config "$OUT/config.toml"
    sleep 2
    open_card
    wait_doc "'place' in d.get('card', {}) and d.get('card_size', 'dock') == '$size'" 10 \
      || fail "the card never placed its page in the $size size ($scheme)"
    sleep 2.5
    shot "card-$size-$scheme" "$(card_region)"
    if [ "$size" = dock ]; then
      read -r kx ky _ <<< "$(logs | grep -F 'webdock-panel sizekey ' | tail -1 | sed 's/.*webdock-panel sizekey //')"
      [ -n "${kx:-}" ] || fail "the card logged no size key ($scheme)"
      "$SB" move "$kx" "$ky"; sleep 0.6
      shot "card-key-tip-$scheme" "$(card_region)"
      "$SB" click "$kx" "$ky"
      wait_doc "d.get('card_size') == 'phone' and 'place' in d.get('card', {})" 10 \
        || fail "a press of the size key did not step to phone ($scheme)"
      sleep 2.5
      shot "card-pressed-$scheme" "$(card_region)"
      "$SB" move 600 400
    fi
  done
  conf "$scheme" bottom yes
  conf "$scheme" top yes
  "$SB" config "$OUT/config.toml"
  sleep 2
  open_card
  wait_doc "'place' in d.get('card', {})" 10 || fail "the card never placed its page on a top bar ($scheme)"
  sleep 2
  shot "card-top-$scheme" "$(card_region)"
  conf "$scheme" bottom no
  "$SB" config "$OUT/config.toml"
  sleep 2
  open_card
  sleep 2.5
  shot "card-empty-$scheme" "$(card_region)"
  logs > "$OUT/logs-$scheme.txt"
  "$SB" stop > /dev/null 2>&1
  if grep -E 'WARN.{0,12}(scene|qml)|TypeError|ReferenceError|is not a type|is not defined|Binding loop|failed to transition' \
      "$OUT/logs-$scheme.txt" | grep -v "refused: unavailable disconnected\|refused this scope\|refused this host\|host.unloaded refused"; then
    fail "QML problems ($OUT/logs-$scheme.txt)"
  fi
done
echo "shots-card: done"
