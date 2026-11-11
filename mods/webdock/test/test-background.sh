#!/usr/bin/env bash
# Pages that keep playing (W73, docs/ux/webdock.md "Background pages"), invisibly (headless sway sandbox), with the REAL
# kurashid and the real web host (qs-webengine; the edge card, no shell needed), `file://` pages, no network (K37), no
# sound device (PULSE_SERVER points nowhere: Chromium falls back to its fake output, which still reports the sound). The
# page `pages/tone.html` stands in for a music player: a click plays track 1, a `setTimeout` plays track 2 after a silent
# gap, with no gesture, as a player's next track. A frozen page never runs that timer.
#   gap         the page is hidden in the silence after track 1 (the gap between tracks, a pause): track 2 starts while
#               it is hidden; the engine never froze it
#   cap         `max_loaded = 1`: the player plays hidden past the cap; the gap's "not audible" report keeps it (the
#               grace), so its page is not destroyed and track 2 starts
#   background  a pin with `background = true`: hidden and silent, its timer keeps running, it is kept past the cap, and
#               its document says `awake`
#   nix develop -c mods/webdock/test/test-background.sh [sandbox-name]
#   STEPS="gap cap background" (the default) picks steps; KURASHI_BIN_DIR: kurashid and kurashi (default
#   $CARGO_TARGET_DIR/debug or target/debug)
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
NAME=${1:-${KURASHI_SB_PREFIX:-}w73-webdock-bg}
BIN=${KURASHI_BIN_DIR:-${CARGO_TARGET_DIR:-$ROOT/target}/debug}
STEPS=${STEPS:-gap cap background}
PAGES=file://$ROOT/mods/webdock/test/pages
GAP=8
fail() { echo "test-background: FAIL: $*" >&2; exit 1; }
ok() { echo "test-background: ok: $*"; }
step() { case " $STEPS " in *" $1 "*) return 0 ;; esac; return 1; }
command -v qs-webengine >/dev/null || fail "qs-webengine not on PATH (nix develop)"

eval "$("$ROOT/tools/bench/sandbox.sh" start "$NAME")"
. "$ROOT/frontend/test-lib.sh"
R=$XDG_RUNTIME_DIR
W=$R/work
mkdir -p "$W" "$R/kurashi"
cp "$BIN/kurashid" "$BIN/kurashi" "$W/"
pids=()
cleanup() {
  exec 9>&- 2>/dev/null || true
  for p in "${pids[@]}"; do kill "$p" 2>/dev/null || true; done
  for p in "${pids[@]}"; do wait "$p" 2>/dev/null || true; done
  "$ROOT/tools/bench/sandbox.sh" stop "$NAME" >/dev/null || true
}
trap cleanup EXIT

rm -rf "$R/xdg"
export XDG_CONFIG_HOME=$R/xdg/config XDG_STATE_HOME=$R/xdg/state XDG_DATA_HOME=$R/xdg/data XDG_CACHE_HOME=$R/xdg/cache \
       KURASHI_DATA_DIR=$ROOT LC_ALL=C.UTF-8 KURASHI_WEBDOCK_DEBUG=1
mkdir -p "$XDG_CONFIG_HOME/kurashi" "$XDG_STATE_HOME" "$XDG_DATA_HOME" "$XDG_CACHE_HOME"
CONF=$XDG_CONFIG_HOME/kurashi/config.toml
HOSTLOG=$XDG_STATE_HOME/kurashi/webdock/host-web.log
K() { timeout 10 "$W/kurashi" "$@"; }
W_OUT=$(swaymsg -t get_outputs -r | jq -r '.[0].rect.width')
H_OUT=$(swaymsg -t get_outputs -r | jq -r '.[0].rect.height')

# The pins: two players (one per step, each its own profile), a quiet page, and with the background step a ticking pin.
tone="$PAGES/tone.html#gap=$GAP&len=2&mode=element"
pins="[[mods.webdock.pins]]
id = \"tone\"
title = \"Tone\"
target = \"$tone\"
[[mods.webdock.pins]]
id = \"tone2\"
title = \"Tone 2\"
target = \"$tone\"
[[mods.webdock.pins]]
id = \"other\"
title = \"Other\"
target = \"$PAGES/other.html\""
step background && pins="$pins
[[mods.webdock.pins]]
id = \"bg\"
title = \"Ticks\"
target = \"$PAGES/tone.html#tick=1\"
background = true"
cat > "$CONF" <<T
[idle]
enabled = false
[theme.motion]
profile = "none"
[mods]
enabled = ["webdock"]
[mods.webdock]
pinned = true
max_loaded = 1
$pins
T

doc() { K --json sub "${2:-mod.webdock}" --count 0 | python3 -c "import json,sys; d=json.loads(sys.stdin.readline()); d=d.get('data', d); print($1)"; }
doc_is() { [ "$(doc "$1" "${2:-mod.webdock}" 2>/dev/null)" = True ]; }
pin_is() { doc_is "[p for p in d['pins'] if p['id'] == '$1'][0].get($2) == True"; }
count() { grep -c -F -- "$1" "$2" 2>/dev/null || true; }
has() { grep -qF -- "$1" "$HOSTLOG" 2>/dev/null; }
# The engine stopped hearing <pin> after its track 1 ended (its own hold after the last sound has passed).
silent() {
  awk -v a="webdock-debug $1 TRACK 1 end" -v b="webdock-debug life $1 audible: state Active recommended Active audible false" \
    'index($0, a) { e = 1 } e && index($0, b) { f = 1 } END { exit !f }' "$HOSTLOG" 2>/dev/null
}
rm -f "$R/ptr.fifo"; mkfifo "$R/ptr.fifo"
python3 -I "$ROOT/tools/bench/wl_pointer.py" --serve < "$R/ptr.fifo" >> "$W/ptr.log" 2>&1 &
pids+=($!)
exec 9> "$R/ptr.fifo"
ptr() { echo "click $1 $2 left" >&9; sleep 0.25; }

env DBUS_SYSTEM_BUS_ADDRESS="unix:path=$R/no-system-bus" PULSE_SERVER="unix:$R/no-pulse/native" \
    PULSE_RUNTIME_PATH="$R/no-pulse" "$W/kurashid" >> "$R/server.log" 2>&1 &
pids+=("$!")
wait_until 15 K ping || fail "kurashid did not come up ($R/server.log)"
wait_until 10 doc_is "'tone' in [p['id'] for p in d.get('pins', [])]" || fail "the dock's pins never came ($(K get mods.webdock.pins 2>&1 | head -3))"

# play <pin>: the edge card shows the player; a click on its page (the right edge's phone, no bar) starts track 1.
play() {
  K act webdock.open "{\"pin\":\"$1\"}" >/dev/null || fail "webdock.open $1 refused"
  wait_until 60 has "webdock-debug $1 TRACK ready" || fail "the $1 page never loaded ($HOSTLOG)"
  sleep 1
  local i
  for i in 1 2 3; do
    ptr $(( W_OUT - 56 - 206 )) $(( H_OUT / 2 + 40 ))
    wait_until 3 has "webdock-debug $1 TRACK 1 start" && break
  done
  has "webdock-debug $1 TRACK 1 start" || fail "a click on the $1 page did not start track 1 ($HOSTLOG)"
  wait_until 5 has "webdock-debug life $1 audible: state Active recommended Active audible true" \
    || fail "the engine never heard track 1 of $1 (no recentlyAudible in the sandbox?)"
}
# track2 <pin>: track 2 starts (after the gap) while the page is hidden; the log line's own visibility says so.
track2() {
  wait_until $(( GAP + 20 )) has "webdock-debug $1 TRACK 2 start" \
    || fail "track 2 of $1 never started while hidden: $(grep -E "webdock-debug (life )?$1 " "$HOSTLOG" | tail -6)"
  grep -F "webdock-debug $1 TRACK 2 start" "$HOSTLOG" | grep -qF 'visibility=hidden' || fail "track 2 of $1 started, but not hidden"
}

# ---- gap: hidden in the silence between two tracks ----
if step gap; then
  play tone
  wait_until 10 has "webdock-debug tone TRACK 1 end" || fail "track 1 never ended"
  # the engine's own hold after the last sound passes: the page is silent now
  wait_until 10 silent tone || fail "the engine kept hearing tone"
  t_end=$(date +%s.%N)
  K act webdock.hide >/dev/null
  wait_until 5 has "webdock-debug page tone frozen" || fail "the page was not hidden"
  track2 tone
  t_two=$(date +%s.%N)
  ! grep -E "webdock-debug life tone .*state Frozen" "$HOSTLOG" || fail "the engine froze the hidden player"
  ok "gap: hidden in the silence after track 1, the page stayed Active and track 2 started hidden ($(python3 -c "print(round($t_two - $t_end, 1))") s after the hide)"
fi

# ---- cap: past max_loaded, the silent gap does not drop the player ----
if step cap; then
  play tone2
  K act webdock.open '{"pin":"other"}' >/dev/null || fail "webdock.open other refused"
  wait_until 5 doc_is "d.get('shown') == 'other'" || fail "the edge did not show the other pin"
  doc_is "'tone2' in d['keep']" || fail "the playing tone2 is not kept past the cap: $(doc "d['keep']")"
  wait_until 10 has "webdock-debug tone2 TRACK 1 end" || fail "track 1 of tone2 never ended"
  wait_until 10 silent tone2 || fail "the engine kept hearing tone2"
  sleep 1
  ! has 'webdock.host.unloaded {"pin":"tone2"}' || fail "the gap's silence unloaded the player past the cap (keep $(doc "d['keep']"))"
  doc_is "'tone2' in d['keep']" || fail "the silent player left keep in its grace: $(doc "d['keep']")"
  pin_is tone2 "'awake'" || fail "the player in its grace is not marked awake: $(doc "[p for p in d['pins'] if p['id'] == 'tone2'][0]")"
  track2 tone2
  ! has 'webdock.host.unloaded {"pin":"tone2"}' || fail "the player was unloaded"
  ok "cap: past max_loaded = 1 the player is kept and awake through the gap, and track 2 starts"
fi

# ---- background: a pin that keeps running ----
if step background; then
  K act webdock.open '{"pin":"bg"}' >/dev/null || fail "webdock.open bg refused"
  wait_until 60 has "webdock-debug bg TICK 2" || fail "the bg page never ticked ($HOSTLOG)"
  pin_is bg "'background'" || fail "the document does not say bg keeps running"
  K act webdock.open '{"pin":"other"}' >/dev/null
  wait_until 5 has "webdock-debug page bg frozen" || fail "the bg page was not hidden"
  t0=$(count "webdock-debug bg TICK" "$HOSTLOG")
  sleep 6
  t1=$(count "webdock-debug bg TICK" "$HOSTLOG")
  [ $(( t1 - t0 )) -ge 4 ] || fail "the hidden background page ticked $(( t1 - t0 )) times in 6 s (frozen?)"
  doc_is "'bg' in d['keep']" || fail "the background pin is not kept past the cap: $(doc "d['keep']")"
  pin_is bg "'awake'" || fail "the loaded background pin is not marked awake"
  ! grep -E "webdock-debug life bg .*state Frozen" "$HOSTLOG" || fail "the engine froze the background page"
  ok "background: hidden and silent, the page keeps running ($(( t1 - t0 )) ticks in 6 s), kept past the cap, awake"
fi

bad=$(grep -E 'TypeError|ReferenceError|is not a type|is not defined|Cannot assign|Binding loop|Parameter "[a-zA-Z]+" is not declared' "$HOSTLOG" || true)
[ -z "$bad" ] || fail "QML problems in the host log:
$bad"
echo "test-background: PASS"
