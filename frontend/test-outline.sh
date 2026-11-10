#!/usr/bin/env bash
# The line round a surface (session 28, Theme.surfaceLineW; docs/ux/frame.md "Surfaces without a line"): under a chrome
# that draws no outline of its own (flat), `theme.frame_outline` decides whether cards carry a hairline — Automatic and
# Off draw none, On draws one. Headless sway against the real kurashid; the quick card under the bar's end, read as
# pixels: Automatic and Off are the same picture, and On differs from them.
#   nix develop -c frontend/test-outline.sh
set -uo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
NAME=${KURASHI_SB_PREFIX:-}outline
BIN=${KURASHI_BIN_DIR:-${CARGO_TARGET_DIR:-$ROOT/target}/debug}
fail() { echo "test-outline: FAIL: $*" >&2; exit 1; }
ok() { echo "test-outline: ok: $*"; }
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
swaymsg output '*' bg '#8fb8c8' solid_color > /dev/null 2>&1 || true
SW=$(swaymsg -t get_outputs -r | jq '.[0].rect.width')
# (a home of this run's own inside the sandbox's fresh runtime dir)
X=$R/xdg-outline
export XDG_CONFIG_HOME=$X/config XDG_STATE_HOME=$X/state XDG_DATA_HOME=$X/data XDG_CACHE_HOME=$X/cache KURASHI_DATA_DIR=$ROOT LC_ALL=C.UTF-8
mkdir -p "$XDG_CONFIG_HOME/kurashi" "$XDG_STATE_HOME" "$XDG_DATA_HOME" "$XDG_CACHE_HOME"
cat > "$XDG_CONFIG_HOME/kurashi/config.toml" <<T
[idle]
enabled = false
[theme]
style = "kanso"
chrome = "flat"
frame_outline = "auto"
[theme.colors]
scheme = "dark"
[theme.material]
kind = "solid"
[theme.motion]
profile = "none"
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
CROP="$(( SW - 520 )),0 520x420"
K act quick.toggle > /dev/null || fail "quick.toggle"
wait_until 6 eval '[ "$(K sub runtime.ui --count 0 --json | jq -r .data.panel)" = quick ]' || fail "the quick card did not open"
shot() { wait_settled 6 0.6 "$CROP"; grim -g "$CROP" "$R/$1.png"; }
differ() { magick compare -metric AE "$R/$1.png" "$R/$2.png" null: 2>&1 | cut -d' ' -f1 | cut -d. -f1; }
shot auto
K set theme.frame_outline off > /dev/null; sleep 0.4; shot off
K set theme.frame_outline on > /dev/null; sleep 0.4; shot on
mkdir -p "$ROOT/frontend/shots/outline"; cp "$R/auto.png" "$R/off.png" "$R/on.png" "$ROOT/frontend/shots/outline/" 2>/dev/null || true
d=$(differ auto off); [ "$d" = 0 ] || fail "flat chrome: Automatic and Off differ by $d px (Automatic must draw no line)"
ok "flat chrome: Automatic draws what Off draws"
d=$(differ off on); [ "$d" -gt 150 ] || fail "flat chrome: On draws no line ($d px differ from Off)"
ok "flat chrome: On draws the hairline ($d px differ from Off)"
K act ui.close > /dev/null
if grep -E 'ERROR|qml:.*(Error|error)|TypeError|ReferenceError|is not a type|Cannot assign|Binding loop' "$R/qs.log" | grep -v 'Unable to assign \[undefined\]' > /dev/null; then
  grep -E 'Error|error|Cannot assign|Binding loop' "$R/qs.log" | sort | uniq -c | head -10 >&2
  fail "QML errors (see $R/qs.log)"
fi
echo "test-outline: PASS"
