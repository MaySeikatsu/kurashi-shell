#!/usr/bin/env bash
# `bar.popups_follow` (session 28, docs/ux/layout.md "Cards follow the pointer"): two outputs (headless sway, against the
# real kurashid). A card opened on purpose (the command line here, as a key or a click) follows the focused output — the
# compositor's, which the pointer moves — and opens there; with the setting off it stays where it opened. Read from each
# output's pixels where the card stands (under the bar's end): nothing else draws there. A kept card (B128) stays.
#   nix develop -c frontend/test-follow.sh
set -uo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
NAME=${KURASHI_SB_PREFIX:-}follow
BIN=${KURASHI_BIN_DIR:-${CARGO_TARGET_DIR:-$ROOT/target}/debug}
fail() { echo "test-follow: FAIL: $*" >&2; exit 1; }
ok() { echo "test-follow: ok: $*"; }
eval "$("$ROOT/tools/bench/sandbox.sh" start "$NAME")"
. "$ROOT/frontend/test-lib.sh"
R=$XDG_RUNTIME_DIR; W=$R/work; mkdir -p "$W" "$R/kurashi"
cp "$BIN/kurashid" "$BIN/kurashi" "$W/"
pids=()
cleanup() {
  for p in "${pids[@]}"; do kill "$p" 2>/dev/null || true; done
  for p in "${pids[@]}"; do wait "$p" 2>/dev/null || true; done
  "$ROOT/tools/bench/sandbox.sh" stop "$NAME" > /dev/null || true
}
trap cleanup EXIT
"$ROOT/tools/bench/sandbox.sh" output-add "$NAME" > /dev/null || fail "no second output"
swaymsg output HEADLESS-1 pos 0 0 > /dev/null 2>&1
W1=$(swaymsg -t get_outputs -r | jq '.[] | select(.name == "HEADLESS-1") | .rect.width')
W2=$(swaymsg -t get_outputs -r | jq '.[] | select(.name == "HEADLESS-2") | .rect.width')
swaymsg output HEADLESS-2 pos "$W1" 0 > /dev/null 2>&1
swaymsg output '*' bg '#8fb8c8' solid_color > /dev/null 2>&1 || true
# Where the quick card stands on each output: under the bar's end.
C1="$(( W1 - 460 )),60 440x300"; C2="$(( W1 + W2 - 460 )),60 440x300"
rm -rf "$R/xdg"
export XDG_CONFIG_HOME=$R/xdg/config XDG_STATE_HOME=$R/xdg/state XDG_DATA_HOME=$R/xdg/data XDG_CACHE_HOME=$R/xdg/cache KURASHI_DATA_DIR=$ROOT LC_ALL=C.UTF-8
mkdir -p "$XDG_CONFIG_HOME/kurashi" "$XDG_STATE_HOME" "$XDG_DATA_HOME" "$XDG_CACHE_HOME"
cat > "$XDG_CONFIG_HOME/kurashi/config.toml" <<T
[idle]
enabled = false
[theme]
style = "kanso"
[theme.motion]
profile = "${FOLLOW_MOTION:-none}"
[edges.top]
bar = true
start = ["workspaces"]
center = []
end = ["quick"]
T
K() { timeout 10 "$W/kurashi" "$@"; }
: > "$R/server.log"; : > "$R/qs.log"
env DBUS_SYSTEM_BUS_ADDRESS="unix:path=$R/no-system-bus" PULSE_SERVER="unix:$R/no-pulse/native" PULSE_RUNTIME_PATH="$R/no-pulse" \
  "$W/kurashid" >> "$R/server.log" 2>&1 &
pids+=("$!")
for _ in $(seq 100); do [ -S "$KURASHI_SOCKET" ] && K ping > /dev/null 2>&1 && break; sleep 0.1; done
BARE=$(screen_hash)
env -u KURASHI_SOCKET qs -p "$ROOT/frontend" >> "$R/qs.log" 2>&1 &
pids+=("$!")
wait_frontend "$R/qs.log" 0 15 0.6 "$BARE" || fail "the frontend did not load"
[ "$(K --json get bar.popups_follow | jq -r .value)" = true ] || fail "cards do not follow by default"

swaymsg focus output HEADLESS-1 > /dev/null
wait_settled 6 0.6
grim -g "$C1" "$R/bare1.png"; grim -g "$C2" "$R/bare2.png"
# How many pixels of an output's card area differ from the bare screen.
diff_of() { grim -g "$2" "$R/now.png"; magick compare -metric AE "$R/bare$1.png" "$R/now.png" null: 2>&1 | cut -d' ' -f1 | cut -d. -f1; }
card_on() { [ "$(diff_of "$1" "$([ "$1" = 1 ] && echo "$C1" || echo "$C2")")" -gt 8000 ]; }
card_off() { [ "$(diff_of "$1" "$([ "$1" = 1 ] && echo "$C1" || echo "$C2")")" -lt 500 ]; }

K act quick.toggle > /dev/null || fail "quick.toggle"
wait_until 6 card_on 1 || fail "the quick card did not open on the focused output"
card_off 2 || fail "the card is on the other output too"
ok "the card opens on the focused output"

swaymsg focus output HEADLESS-2 > /dev/null
wait_until 6 card_on 2 || fail "the card did not follow the focus to the second output"
wait_until 6 card_off 1 || fail "the card stayed on the first output"
[ "$(K sub runtime.ui --count 0 --json | jq -r .data.panel)" = quick ] || fail "the hop closed the panel"
grim -g "$C2" "$R/shot-followed.png"
ok "the card follows the focus to the second output and leaves the first; the panel stays open"

swaymsg focus output HEADLESS-1 > /dev/null
wait_until 6 card_on 1 || fail "the card did not follow back"
wait_until 6 card_off 2 || fail "the card stayed on the second output"
ok "and back"

# B128 (session 32): a kept card (`ui.keep`, K147: the web dock's bar card pinned) stays where it was kept; the same card
# not kept follows again.
K act ui.keep '{"on":true}' > /dev/null || fail "ui.keep"
[ "$(K sub runtime.ui --count 0 --json | jq -r .data.kept)" = quick ] || fail "ui.keep did not keep the quick card"
swaymsg focus output HEADLESS-2 > /dev/null
sleep 1.5
card_on 1 || fail "the kept card left its output"
card_off 2 || fail "the kept card went to the other output"
ok "a kept card stays on its output when the focus moves"
K act ui.keep '{"on":false}' > /dev/null || fail "ui.keep off"
swaymsg focus output HEADLESS-1 > /dev/null
sleep 0.5
swaymsg focus output HEADLESS-2 > /dev/null
wait_until 6 card_on 2 || fail "the card no longer kept did not follow"
wait_until 6 card_off 1 || fail "the card no longer kept stayed on the first output"
swaymsg focus output HEADLESS-1 > /dev/null
wait_until 6 card_on 1 || fail "the card did not follow back after keep off"
ok "not kept, it follows again"

K set bar.popups_follow false > /dev/null || fail "set bar.popups_follow"
sleep 0.5
swaymsg focus output HEADLESS-2 > /dev/null
sleep 1.5
card_on 1 || fail "with the setting off the card left its output"
card_off 2 || fail "with the setting off the card went to the other output"
ok "off: the card stays where it opened"

K act ui.close > /dev/null
wait_until 6 card_off 1 || fail "the card did not close"
if grep -E 'ERROR|qml:.*(Error|error)|TypeError|ReferenceError|is not a type|Cannot assign|Binding loop' "$R/qs.log" | grep -v 'Unable to assign \[undefined\]' > /dev/null; then
  grep -E 'Error|error|Cannot assign|Binding loop' "$R/qs.log" | sort | uniq -c | head -10 >&2
  fail "QML errors (see $R/qs.log)"
fi
echo "test-follow: PASS"
