#!/usr/bin/env bash
# The motion engine (W59.2, K83; docs/ux/motion-engine.md §9–§11): curves, Driver and FormHost under today's profiles.
# Invisibly (headless sway sandbox; the visual review runs on niri, tools/bench/niri-sandbox.sh):
#   unit    core/motion/tests (qmltestrunner, offscreen, a Quickshell stub): curves.js against ease.js and MorphSprings'
#           K42 loop, springs, steps, retarget; Driver (rest, landing, cuts, spring velocity through a retarget, cubic slope
#           matching, track/release); the Theme's motion readers with today's tokens and with W59.1's — skipped when
#           qmltestrunner is not on PATH;
#   scrub   per case (a style and a motion profile: expressive, calm, lively; fluent, snes, kawaii and vibrancy on their
#           own) the session menu (a Stage panel) opened with KURASHI_MOTION_SCRUB at 0.15, 0.5, 0.85 and 1 (one frontend per value: the variable
#           is read once): every Driver and morph holds there, so the shots are by progress, not by sleeping. Asserted:
#           the frontend logs `motion: scrub <p>`; p = 1 equals the panel at rest without scrub, pixel for pixel, and that
#           the motion-off frame (profile none; ≤ 16 px: lively's neck fillets differ at rest, on main too); p < 1 differs
#           from rest (the panel is mid-way);
#   rest    the same panel without scrub, opened and closed: after the close no `motion: sheet layer` line and 0 surface
#           commits in 5 s (WAYLAND_DEBUG; the window starts after a minute's turn so the clock does not count).
# Shots: frontend/shots/motion/<style>-<profile>-<p>.png, …-rest.png, …-off.png (gitignored; read them).
#   nix develop -c frontend/test-motion.sh
#   MOTION_CASES="washi:calm snes:expressive" MOTION_SCRUBS="0.5 1" nix develop -c frontend/test-motion.sh
# Binaries from $KURASHI_BIN_DIR (kurashid, kurashi), else $CARGO_TARGET_DIR/debug.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
NAME=${KURASHI_SB_PREFIX:-}w59-motion
BIN=${KURASHI_BIN_DIR:-${CARGO_TARGET_DIR:-$ROOT/target}/debug}
OUT=${MOTION_OUT:-$ROOT/frontend/shots/motion}
CASES=${MOTION_CASES:-washi:expressive washi:calm sekai:lively fluent:expressive snes:expressive kawaii:lively vibrancy:calm}
SCRUBS=${MOTION_SCRUBS:-0.15 0.5 0.85 1}
# Styles whose Stage card is not a morph (snes: no join) reveal on the Stage's own animation until W59.3 puts it on a
# Driver: their scrubbed frames may equal rest (said, not failed).
PENDING=${MOTION_PENDING:-snes}
mkdir -p "$OUT"
fail() { echo "test-motion: $*" >&2; exit 1; }

echo "== unit: core/motion/tests"
T=$ROOT/frontend/core/motion/tests
if command -v qmltestrunner >/dev/null 2>&1 && [ -d "$T" ]; then
  QT_QPA_PLATFORM=offscreen timeout 120 qmltestrunner -import "$T/stub" -input "$T" > "$OUT/unit.log" 2>&1 \
    || { tail -30 "$OUT/unit.log" >&2; fail "unit tests failed (see $OUT/unit.log)"; }
  grep -E '^Totals' "$OUT/unit.log"
  # The Theme's motion readers: core/Theme.qml beside a Store stand-in, today's tokens and W59.1's.
  TT=$(mktemp -d)
  cp "$ROOT/frontend/core/Theme.qml" "$T/theme/Store.qml" "$TT/"
  cp "$T/theme/theme_case.qml" "$TT/tst_theme.qml"
  printf 'singleton Store 1.0 Store.qml\nsingleton Theme 1.0 Theme.qml\n' > "$TT/qmldir"
  QT_QPA_PLATFORM=offscreen timeout 120 qmltestrunner -import "$T/stub" -input "$TT" > "$OUT/unit-theme.log" 2>&1 \
    || { tail -30 "$OUT/unit-theme.log" >&2; rm -rf "$TT"; fail "Theme reader tests failed (see $OUT/unit-theme.log)"; }
  rm -rf "$TT"
  grep -E '^Totals' "$OUT/unit-theme.log"
else
  echo "test-motion: qmltestrunner not on PATH: unit phase skipped"
fi

eval "$("$ROOT/tools/bench/sandbox.sh" start "$NAME")"
. "$ROOT/frontend/test-lib.sh"
R=$XDG_RUNTIME_DIR
W=$R/work
mkdir -p "$W"
cp "$BIN/kurashid" "$BIN/kurashi" "$W/"
pids=()
QS_PID=
stop_fe() {
  [ -n "$QS_PID" ] || return 0
  kill "$QS_PID" 2>/dev/null || true; wait "$QS_PID" 2>/dev/null || true
  QS_PID=
}
cleanup() {
  stop_fe
  for p in "${pids[@]}"; do kill "$p" 2>/dev/null || true; done
  for p in "${pids[@]}"; do wait "$p" 2>/dev/null || true; done
  "$ROOT/tools/bench/sandbox.sh" stop "$NAME" >/dev/null || true
}
trap cleanup EXIT

export XDG_CONFIG_HOME=$R/xdg/config XDG_STATE_HOME=$R/xdg/state \
       XDG_DATA_HOME=$R/xdg/data XDG_CACHE_HOME=$R/xdg/cache KURASHI_DATA_DIR=$ROOT LC_ALL=C.UTF-8
K() { timeout 10 "$W/kurashi" "$@"; }
rm -rf "$R/xdg"; mkdir -p "$XDG_CONFIG_HOME/kurashi" "$XDG_STATE_HOME" "$XDG_DATA_HOME" "$XDG_CACHE_HOME"
: > "$XDG_CONFIG_HOME/kurashi/config.toml"
: > "$R/server.log"
env DBUS_SYSTEM_BUS_ADDRESS="unix:path=$R/no-system-bus" \
    PULSE_SERVER="unix:$R/no-pulse/native" PULSE_RUNTIME_PATH="$R/no-pulse" \
    "$W/kurashid" >> "$R/server.log" 2>&1 &
pids+=("$!")
wait_until 10 K ping || fail "kurashid did not come up (see $R/server.log)"
swaymsg output '*' bg '#8fb8c8' solid_color >/dev/null 2>&1 || true

said_hello() { [ "$(grep -c 'hello.*frontend' "$R/server.log" || true)" -gt "$1" ]; }
# start_fe <log> [env…]: a frontend with that environment; returns once it said hello and the screen settled.
start_fe() {
  local log=$1; shift
  local hellos
  hellos=$(grep -c 'hello.*frontend' "$R/server.log" || true)
  : > "$log"
  env -u KURASHI_SOCKET "$@" qs -p "$ROOT/frontend" >> "$log" 2>&1 &
  QS_PID=$!
  wait_until 15 said_hello "$hellos" || fail "the frontend never said hello (see $log)"
  wait_frontend "$log" 0 15 0.6 || fail "the frontend did not load (see $log)"
}
qml_errors() {
  if grep -E 'qml:.*(Error|error)|TypeError|ReferenceError|is not a type|Binding loop|is not defined' "$1" \
      | grep -v 'Unable to assign \[undefined\]' >/dev/null; then
    grep -E 'Error|error|Binding loop|not defined' "$1" | head -20 >&2
    fail "QML errors (see $1)"
  fi
}
# The session menu under the pill, below the bar's strip (the clock may turn between two shots).
CROP="860,44 840x316"
# act_settled <action…>: the action, then the panel's region changes (a first open makes its view first: I192) and settles.
changed() { [ "$(screen_hash "$CROP")" != "$1" ]; }
act_settled() {
  local before; before=$(screen_hash "$CROP")
  K act "$@" >/dev/null || fail "act $* failed"
  wait_until 10 changed "$before" || fail "act $*: the panel's region did not change in 10 s"
  wait_settled 8 0.8 "$CROP"
}
open_panel() { act_settled session.menu; }
close_panel() { act_settled ui.close; }
shot() { grim -g "$CROP" "$OUT/$1.png"; }
ae() { { magick compare -metric AE "$OUT/$1.png" "$OUT/$2.png" null: 2>&1 || true; } | awk '{print int($1)}'; }
commits() { tail -c +"$(( $1 + 1 ))" "$2" | grep -cE 'wl_surface#[0-9]+\.commit\(' || true; }

for cs in $CASES; do
  style=${cs%%:*}; prof=${cs#*:}; tag=$style-$prof
  echo "-- case $tag"
  K set theme.style "$style" >/dev/null || fail "theme.style $style refused"
  K set theme.motion.profile "$prof" >/dev/null || fail "theme.motion.profile $prof refused"
  for p in $SCRUBS; do
    start_fe "$R/qs-$tag-$p.log" KURASHI_MOTION_SCRUB="$p"
    wait_for "$R/qs-$tag-$p.log" "motion: scrub $p" 5 || fail "$tag: no 'motion: scrub $p' line"
    open_panel
    shot "$tag-$p"
    qml_errors "$R/qs-$tag-$p.log"
    # (the daemon keeps the panel open for the next frontend otherwise; a scrubbed close never lands, so no wait)
    K act ui.close >/dev/null || true
    stop_fe
  done
  # At rest without scrub: open, close, then the shell is silent.
  log=$R/qs-$tag-rest.log
  start_fe "$log" WAYLAND_DEBUG=1
  open_panel
  shot "$tag-rest"
  close_panel
  # (a window that a minute's turn cannot cross: the bar's clock would commit)
  while [ "$(date +%S | sed 's/^0//')" -gt 50 ]; do sleep 0.5; done
  off=$(log_size "$log"); sleep 5
  n=$(commits "$off" "$log")
  [ "$n" = 0 ] || fail "$tag: $n surface commits in 5 s after the close (idle must be 0 frames)"
  ups=$(grep -c 'motion: sheet layer up' "$log" || true); downs=$(grep -c 'motion: sheet layer.*released' "$log" || true)
  [ "$ups" = "$downs" ] || fail "$tag: a sheet layer is still up after the close ($ups up, $downs released)"
  qml_errors "$log"
  stop_fe
  # Motion off: the frame p = 1 must equal.
  K set theme.motion.profile none >/dev/null || fail "theme.motion.profile none refused"
  start_fe "$R/qs-$tag-off.log"
  open_panel
  shot "$tag-off"
  qml_errors "$R/qs-$tag-off.log"
  K act ui.close >/dev/null || true
  stop_fe
  for p in $SCRUBS; do
    d=$(ae "$tag-$p" "$tag-rest")
    if [ "$p" = 1 ]; then
      [ "$d" = 0 ] || fail "$tag: scrub 1 differs from the panel at rest in $d px"
    elif [ "$d" = 0 ] && [[ " $PENDING " == *" $style "* ]]; then
      echo "test-motion: $tag scrub $p: not held — the Stage's own reveal (no join: a NumberAnimation) moves to Driver in W59.3"
      continue
    else
      [ "$d" -gt 0 ] || fail "$tag: scrub $p looks like the panel at rest (nothing held mid-way?)"
    fi
    echo "test-motion: $tag scrub $p: $d px from rest"
  done
  # At rest a profile draws as motion off does — but lively's neck fillets, 8 px apart on main too (reported, W59.2).
  d=$(ae "$tag-rest" "$tag-off")
  [ "$d" -le "${MOTION_OFF_SLACK:-16}" ] || fail "$tag: the panel at rest differs from the motion-off frame in $d px"
  echo "test-motion: $tag rest vs off: $d px; idle 0 commits in 5 s"
done
echo "test-motion: ok (shots in $OUT)"
