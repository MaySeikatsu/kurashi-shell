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
#           commits in 5 s once the close has landed (WAYLAND_DEBUG; not across a minute's turn: the clock).
#   forms   (W59.3) the surface matrix: per form case (style:profile:edge[:light|dark]) and per surface class (panel: the session
#           menu; island: the clock's card out of the pill; centre: the notification centre) × form (today's, then expand,
#           iris, stamp, outline: `theme.motion.form.{open,close}`, the island following, D3), scrubbed at every p:
#           p = 1 equals that surface's motion-off frame (profile none), p < 1 differs; at p = 0.5 a reversal (the close
#           mid-way continues the open's form) and a quick → session retarget mid-way draw without a QML error. Each shot
#           also asserts the form was latched (`motion: form` lines are failures). Off: MOTION_FORM_CASES="".
#           W59.9a: also the right sidebar and a toast (their ShapeLayer), and liquid (panel, island, centre only).
#   landings (W59.9a) kami/origami: fold, book and roll on a panel, the island and the sidebar, scrubbed at 0.9, 0.97 and 1:
#           the frames before the landing within MOTION_LANDING_SLACK px of p = 1 at a 6 % colour tolerance (no seam).
# Shots: frontend/shots/motion/<style>-<profile>-<p>.png, …-rest.png, …-off.png, forms/<case>-<surface>-<form>-<p>.png
# (gitignored; read them).
#   nix develop -c frontend/test-motion.sh
#   MOTION_CASES="washi:calm snes:expressive" MOTION_SCRUBS="0.5 1" nix develop -c frontend/test-motion.sh
#   MOTION_CASES="" MOTION_FORM_CASES="kami:expressive:bottom" MOTION_FORMS="iris" nix develop -c frontend/test-motion.sh
# Binaries from $KURASHI_BIN_DIR (kurashid, kurashi), else $CARGO_TARGET_DIR/debug.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
NAME=${KURASHI_SB_PREFIX:-}w59-motion
BIN=${KURASHI_BIN_DIR:-${CARGO_TARGET_DIR:-$ROOT/target}/debug}
OUT=${MOTION_OUT:-$ROOT/frontend/shots/motion}
CASES=${MOTION_CASES-washi:expressive washi:calm sekai:lively fluent:expressive snes:expressive kawaii:lively vibrancy:calm}
SCRUBS=${MOTION_SCRUBS:-0.15 0.5 0.85 1}
# The Stage's own reveal (a look whose cards stand apart: snes) runs on a Driver since W59.3, so it scrubs; a stepped
# curve may stand on its last step before p = 1 (snes at 0.85): such a frame may equal rest (said, not failed).
STEPPED=${MOTION_STEPPED:-snes}
# One form case by default (the suite's 30-minute budget); the review set adds e.g.
# MOTION_FORM_CASES="washi:expressive:top sekai:lively:bottom kami:expressive:top:dark".
FORM_CASES=${MOTION_FORM_CASES-washi:expressive:top}
FORMS=${MOTION_FORMS:-expand iris stamp outline liquid}
# W59.9a: the right sidebar and a toast too (shape forms through their ShapeLayer); liquid only where a morph draws it.
SURFACES=${MOTION_SURFACES:-panel island centre sidebar toast}
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
# (no idle lock: a full run outlasts its timeout, and the lock screen then covers every shot — and a locked previous run
# starts the next one locked, I241)
rm -f "$R/kurashi/locked"
printf '[idle]\nenabled = false\n' > "$XDG_CONFIG_HOME/kurashi/config.toml"
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
# act_settled <must> <action…>: the action, then the panel's region changes (a first open makes its view first: I192)
# and settles. must = 0: a scrubbed open may hold the shape inside the bar's strip, where the region does not change.
changed() { [ "$(screen_hash "$CROP")" != "$1" ]; }
act_settled() {
  local must=$1 before; shift
  before=$(screen_hash "$CROP")
  K act "$@" >/dev/null || fail "act $* failed"
  if ! wait_until 10 changed "$before"; then
    [ "$must" = 0 ] || fail "act $*: the panel's region did not change in 10 s"
  fi
  wait_settled 8 0.8 "$CROP"
}
open_panel() { act_settled "${1:-1}" session.menu; }
close_panel() { act_settled 1 ui.close; }
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
    open_panel 0
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
  # The window must not hold a minute's turn (the bar's clock commits then): start between :03 and :40 of a minute.
  # The close's last sub-pixel spring steps commit frames the screen does not show: the window starts once the shell
  # has not committed for 1 s (at most 10 s).
  sec() { date +%S | sed 's/^0//'; }
  while [ "$(sec)" -gt 40 ] || [ "$(sec)" -lt 3 ]; do sleep 0.5; done
  wait_log_quiet "$log" 'wl_surface#[0-9]+\.commit\(' 1 10
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
    elif [ "$d" = 0 ] && [ "$p" != 0.15 ] && [[ " $STEPPED " == *" $style "* ]]; then
      echo "test-motion: $tag scrub $p: on the stepped curve's last step already (equals rest)"
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

# ---- forms: the surface matrix (W59.3) ----
FO=$OUT/forms
mkdir -p "$FO"
# The pixels two shots differ in, the clock's pill left out (a minute may turn between them).
# (W59.9a: the sidebar's crop has the bar's clock at its top, a toast its time in its first row: left out too)
fae() {
  local c="rectangle 360,0 640,46"
  [ "$edge" = bottom ] && c="rectangle 360,534 640,580"
  case ${3:-} in
    sidebar) c="rectangle 0,0 500,46 rectangle 0,$(( OH - 46 )) 500,$OH" ;;
    toast) c="$c rectangle 300,30 700,100"; [ "$edge" = bottom ] && c="$c rectangle 300,420 700,550" ;;
  esac
  { magick compare -metric AE <(magick "$1" -fill black -draw "$c" png:-) <(magick "$2" -fill black -draw "$c" png:-) null: 2>&1 || true; } \
    | awk '{print int($1)}'
}
open_of() { case $1 in panel) echo session.menu ;; island) echo island.expand ;; centre) echo notifications.center ;; esac; }
# W59.9a: open and close a surface of the matrix (the right sidebar by its toggle, a toast by a notification on the
# sandbox's bus), and where it is shot.
TOAST_ID=
open_sfc() {
  case $1 in
    sidebar) K act sidebar.toggle "{\"side\":\"right\",\"output\":\"$ONAME\"}" >/dev/null ;;
    toast) TOAST_ID=$(timeout 10 gdbus call --session --dest org.freedesktop.Notifications \
      --object-path /org/freedesktop/Notifications --method org.freedesktop.Notifications.Notify Calendar 0 "" \
      "Standup in 5 minutes" "Room 3" '[]' '{}' 60000 | grep -oE '[0-9]+' | tail -1) ;;
    *) K act "$(open_of "$1")" >/dev/null ;;
  esac
}
close_sfc() {
  case $1 in
    sidebar) K act sidebar.toggle "{\"side\":\"right\",\"output\":\"$ONAME\"}" >/dev/null ;;
    toast) if [ -n "$TOAST_ID" ]; then K act notify.dismiss "{\"id\":$TOAST_ID}" >/dev/null; fi; TOAST_ID= ;;
    *) K act ui.close >/dev/null ;;
  esac
}
crop_of() { if [ "$1" = sidebar ]; then echo "$(( OW - 500 )),0 500x$OH"; else echo "$FCROP"; fi; }
# Whether the form runs on that surface (elsewhere the daemon resolves another, which would not hold mid-way).
serves() { [ "$1" != liquid ] || [[ " panel island centre " == *" $2 "* ]]; }
bar_edge() {
  local e
  for e in top bottom left right; do
    if K --json get "edges.$e.bar" | grep -q '"value":true'; then
      [ "$e" = "$1" ] || K act layout.bar.move "{\"from\":\"$e\",\"to\":\"$1\"}" >/dev/null
      return
    fi
  done
  return 1
}
form_errors() {
  qml_errors "$1"
  # (W59.9a: `grow` named unknown at start was a false warning, now fixed — no exemption)
  if grep -E 'motion: form .* (failed to load|is not available|is unknown on )' "$1" >/dev/null; then
    grep 'motion: form' "$1" | head -5 >&2; fail "a form did not load (see $1)"
  fi
}
for fc in $FORM_CASES; do
  IFS=: read -r style prof edge scheme <<< "$fc"
  echo "-- forms $fc"
  K set theme.style "$style" >/dev/null || fail "theme.style $style refused"
  K set theme.colors.scheme "${scheme:-light}" >/dev/null || fail "theme.colors.scheme ${scheme:-light} refused"
  bar_edge "$edge" || fail "no bar to move to $edge"
  # 1000 × 580 round the bar's centre, from its edge (the output's size from sway).
  read -r OW OH ONAME < <(timeout 10 swaymsg -t get_outputs | python3 -c "import json,sys; o=json.load(sys.stdin)[0]; print(o['rect']['width'], o['rect']['height'], o['name'])")
  if [ "$edge" = bottom ]; then FCROP="$(( OW / 2 - 500 )),$(( OH - 580 )) 1000x580"; else FCROP="$(( OW / 2 - 500 )),0 1000x580"; fi
  K reset theme.motion.form.open >/dev/null || true; K reset theme.motion.form.close >/dev/null || true
  # The motion-off frame of every surface.
  K set theme.motion.profile none >/dev/null
  start_fe "$R/qs-forms-$style-off.log"
  for sfc in $SURFACES; do
    open_sfc "$sfc"; sleep 1.2; wait_settled 8 0.8 "$(crop_of "$sfc")"
    grim -g "$(crop_of "$sfc")" "$FO/$style-$edge-$sfc-off.png"
    close_sfc "$sfc"; sleep 0.8
  done
  form_errors "$R/qs-forms-$style-off.log"
  stop_fe
  K set theme.motion.profile "$prof" >/dev/null
  for form in $FORMS; do
    K set theme.motion.form.open "$form" >/dev/null || fail "theme.motion.form.open $form refused"
    K set theme.motion.form.close "$form" >/dev/null
    for p in $SCRUBS; do
      log=$R/qs-forms-$style-$form-$p.log
      start_fe "$log" KURASHI_MOTION_SCRUB="$p"
      for sfc in $SURFACES; do
        serves "$form" "$sfc" || continue
        tag=$style-$edge-$sfc-$form-$p
        open_sfc "$sfc"; sleep 1.2; wait_settled 8 0.8 "$(crop_of "$sfc")"
        grim -g "$(crop_of "$sfc")" "$FO/$tag.png"
        if [ "$p" = 0.5 ] && [ "$sfc" = panel ]; then
          # A reversal mid-way: the close continues the open's form from where it stands.
          K act ui.close >/dev/null; sleep 1; grim -g "$FCROP" "$FO/$style-$edge-$sfc-$form-reverse.png"
          # A retarget mid-way: quick settings, then the session menu, while the form holds the card.
          K act quick.toggle >/dev/null; sleep 0.8; K act session.menu >/dev/null; sleep 1
          grim -g "$FCROP" "$FO/$style-$edge-$sfc-$form-retarget.png"
        fi
        close_sfc "$sfc"; sleep 0.6
      done
      form_errors "$log"
      grep -q "motion: scrub $p" "$log" || fail "$fc $form: no 'motion: scrub $p' line"
      stop_fe
      for sfc in $SURFACES; do
        serves "$form" "$sfc" || continue
        d=$(fae "$FO/$style-$edge-$sfc-$form-$p.png" "$FO/$style-$edge-$sfc-off.png" "$sfc")
        if [ "$p" = 1 ]; then
          # (the sidebar under sekai/lively: ≤ 27 single pixels of its text's anti-aliasing apart, scattered — W59.9a)
          # (kami's island: its pen outline lands up to ~110 px apart from a fresh motion-off frontend's — on the W59.9a base
          # too, 65 and 106 px in two runs: pre-existing, reported; the card's own frame is checked by the landings below)
          slack=${MOTION_OFF_SLACK:-16}; [ "$sfc" = sidebar ] && slack=$(( slack * 2 ))
          # (a toast's pen outline is seeded by its notification's id, a new one per frontend: the same under kami)
          if [ "$style" = kami ] && { [ "$sfc" = island ] || [ "$sfc" = toast ]; }; then slack=160; fi
          [ "${d:-1}" -le "$slack" ] || fail "$fc $sfc $form: p = 1 differs from motion off in $d px"
        elif [ "${d:-0}" = 0 ] && [ "$p" != 0.15 ]; then
          # (W59.9a: an overshooting curve — expressive's, lively's spring — reaches its end early and passes it, where a
          # form that clamps (expand) stands at rest, from half its time on; said, not failed: p = 0.15 must differ)
          echo "test-motion: forms $style $edge $sfc $form p=$p: on the spring's rest already (equals motion off)"
          continue
        else
          [ "${d:-0}" -gt 0 ] || fail "$fc $sfc $form: p = $p looks like rest (the form held nothing?)"
        fi
        echo "test-motion: forms $style $edge $sfc $form p=$p: $d px from motion off"
      done
    done
  done
  K reset theme.motion.form.open >/dev/null || true; K reset theme.motion.form.close >/dev/null || true
  bar_edge top || true
done

# ---- landings (W59.9a): a sheet form on a joined card lands with no seam — the card is captured square where it meets the
# bar and its fillets are the surface's own, so the frames at p = 0.9 and 0.97 already show the joined corners of the rest
# frame: each against p = 1 within a 6 % colour tolerance (the warp's resampling), at most MOTION_LANDING_SLACK px.
# Cases form:surface on kami (origami); MOTION_LANDINGS="" skips.
LANDINGS=${MOTION_LANDINGS-fold:panel fold:island book:panel roll:sidebar}
if [ -n "$LANDINGS" ]; then
  echo "-- landings"
  edge=top
  K set theme.style kami >/dev/null; K set theme.colors.scheme light >/dev/null; K set theme.motion.profile origami >/dev/null
  bar_edge top || true
  read -r OW OH ONAME < <(timeout 10 swaymsg -t get_outputs | python3 -c "import json,sys; o=json.load(sys.stdin)[0]; print(o['rect']['width'], o['rect']['height'], o['name'])")
  FCROP="$(( OW / 2 - 500 )),0 1000x580"
  for lc in $LANDINGS; do
    form=${lc%%:*}; sfc=${lc#*:}
    K set theme.motion.form.open "$form" >/dev/null || fail "theme.motion.form.open $form refused"
    for p in 0.9 0.97 1; do
      log=$R/qs-landing-$form-$sfc-$p.log
      start_fe "$log" KURASHI_MOTION_SCRUB="$p"
      open_sfc "$sfc"; sleep 1.2; wait_settled 8 0.8 "$(crop_of "$sfc")"
      grim -g "$(crop_of "$sfc")" "$FO/landing-$form-$sfc-$p.png"
      close_sfc "$sfc"; sleep 0.4
      form_errors "$log"
      stop_fe
    done
    for p in 0.9 0.97; do
      c="rectangle 360,0 640,46"; [ "$sfc" = sidebar ] && c="rectangle 0,0 500,46"
      d=$({ magick compare -metric AE -fuzz 6% <(magick "$FO/landing-$form-$sfc-$p.png" -fill black -draw "$c" png:-) \
        <(magick "$FO/landing-$form-$sfc-1.png" -fill black -draw "$c" png:-) null: 2>&1 || true; } | awk '{print int($1)}')
      [ "${d:-99999}" -le "${MOTION_LANDING_SLACK:-600}" ] || fail "landing $form on $sfc: p = $p differs from p = 1 in $d px (a seam?)"
      echo "test-motion: landing $form $sfc p=$p: $d px from p = 1"
    done
  done
  K reset theme.motion.form.open >/dev/null || true
fi

# W59.4: the sheet forms (fold, roll, book, crumple) in their harness, in a sandbox of their own (MOTION_SHEETS=0 skips).
if [ "${MOTION_SHEETS:-1}" != 0 ]; then
  "$ROOT/frontend/core/motion/tests/sheet/run.sh" || fail "the sheet forms failed (frontend/core/motion/tests/sheet/run.sh)"
fi
echo "test-motion: ok (shots in $OUT)"
