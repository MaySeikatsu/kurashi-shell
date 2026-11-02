#!/usr/bin/env bash
# The sheet forms (W59.4, K83; docs/ux/motion-engine.md §5, §10, §11) in their harness (shell.qml beside this file), on
# the real kurashid, invisibly (headless sway sandbox; the visual review runs the same harness on nested niri). Per
# form × scene (kami, origami): the harness card at rest, then held at p (a close: the rest it leaves is 1) and checked —
#   the form resolved from the tokens and FormHost loaded it ("motion: sheet layer up <surface> <form>");
#   p < 1 differs from the rest (the sheet is warped mid-way), p = 1 equals the rest pixel for pixel (the layer is gone);
#   a reversal (0.3 → 0.6 → 0.4) keeps the form latched and lands on the rest frame;
#   a real run on the theme's curves (play 0, then 1 before it lands) ends on the rest frame;
#   every layer made was released, no QML errors.
# W59.5: a case is form:scene[:style[:scheme]] — the style's motion profile with it (kami origami, terminal phosphor,
# washi sumi, aqua aqua, glass liquid; W59.8b: yorha glitch, souls and hallownest ember, snes and ps2 their own), the scheme
# light or dark (else the style's). crt and glitch cases also sweep p in 0.05 steps both ways and hold the photosensitivity
# rule (brief §11): the region's mean luminance moves ≤ 0.2 a step, and at most one rise-and-fall of ≥ 0.1 per transition.
# The open of pixelate, glitch and dissolve is shot too (W59.8b: each is a function of p, so it runs as the close does).
# SHEET_SCALE=1.5 runs the output at 1.5× (2880×1620 px, the same 1920×1080 layout).
# Shots: frontend/shots/motion/sheet/<form>-<scene>[-<style>[-<scheme>]]-<p>.png (gitignored; read them).
#   nix develop -c frontend/core/motion/tests/sheet/run.sh
#   SHEET_CASES="fold:panel roll:sidebar" SHEET_PS="0.3 0.7" nix develop -c frontend/core/motion/tests/sheet/run.sh
#   SHEET_CASES="genie:dock:aqua:dark crt:panel:terminal" nix develop -c frontend/core/motion/tests/sheet/run.sh
#   a look, a scheme and a scale (W59.8: the variants are shot into their own folders with SHEET_OUT):
#   SHEET_STYLE=washi SHEET_SCHEME=dark SHEET_SCALE=1.5 SHEET_OUT=$PWD/frontend/shots/motion/sheet-washi-dark-1.5 …
# Binaries from $KURASHI_BIN_DIR (kurashid, kurashi), else $CARGO_TARGET_DIR/debug.
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/../../../../.." && pwd)
NAME=${KURASHI_SB_PREFIX:-}w59-sheet
BIN=${KURASHI_BIN_DIR:-${CARGO_TARGET_DIR:-$ROOT/target}/debug}
OUT=${SHEET_OUT:-$ROOT/frontend/shots/motion/sheet}
CASES=${SHEET_CASES:-fold:panel fold:bottom fold:launcher roll:sidebar roll:right book:panel crumple:launcher crumple:toast \
genie:module:aqua genie:dock:aqua:dark genie:toast:aqua crt:panel:terminal crt:launcher:terminal:light drop:toast:washi \
drop:panel:washi:dark drop:module:washi fan:panel fan:bottom fan:launcher fan:leftpanel noren:panel noren:sidebar noren:toast \
pixelate:panel:snes:light pixelate:launcher:ps2:dark glitch:panel:yorha:light glitch:launcher:yorha:dark \
dissolve:panel:souls:dark dissolve:module:souls:light dissolve:launcher:hallownest:dark}
PS=${SHEET_PS:-0.15 0.5 0.85}
# The look (theme.style), the scheme (light | dark | empty = the config's) and the output's scale (1 or 1.5, the 1.5 output
# being 2880×1620 at scale 1.5 — the same 1920×1080 logical screen the regions are written in).
STYLE=${SHEET_STYLE:-kami}
SCHEME=${SHEET_SCHEME:-}
SCALE=${SHEET_SCALE:-1}
mkdir -p "$OUT"
fail() { echo "sheet: $*" >&2; exit 1; }

eval "$("$ROOT/tools/bench/sandbox.sh" start "$NAME")"
. "$ROOT/frontend/test-lib.sh"
R=$XDG_RUNTIME_DIR
W=$R/work
H=$W/harness
mkdir -p "$W" "$H"
cp "$BIN/kurashid" "$BIN/kurashi" "$W/"
cp "$HERE/shell.qml" "$H/"
ln -sfn "$ROOT/frontend" "$H/frontend"
pids=()
QS_PID=
stop_h() {
  [ -n "$QS_PID" ] || return 0
  kill "$QS_PID" 2>/dev/null || true; wait "$QS_PID" 2>/dev/null || true
  QS_PID=
}
cleanup() {
  stop_h
  for p in "${pids[@]}"; do kill "$p" 2>/dev/null || true; done
  for p in "${pids[@]}"; do wait "$p" 2>/dev/null || true; done
  "$ROOT/tools/bench/sandbox.sh" stop "$NAME" >/dev/null || true
}
trap cleanup EXIT

export XDG_CONFIG_HOME=$R/xdg/config XDG_STATE_HOME=$R/xdg/state \
       XDG_DATA_HOME=$R/xdg/data XDG_CACHE_HOME=$R/xdg/cache KURASHI_DATA_DIR=$ROOT LC_ALL=C.UTF-8
K() { timeout 10 "$W/kurashi" "$@"; }
rm -rf "$R/xdg"; mkdir -p "$XDG_CONFIG_HOME/kurashi" "$XDG_STATE_HOME" "$XDG_DATA_HOME" "$XDG_CACHE_HOME"
printf '[theme]\nstyle = "kami"\n\n[theme.motion]\nprofile = "origami"\n\n[idle]\nenabled = false\n' \
  > "$XDG_CONFIG_HOME/kurashi/config.toml"
env DBUS_SYSTEM_BUS_ADDRESS="unix:path=$R/no-system-bus" \
    PULSE_SERVER="unix:$R/no-pulse/native" PULSE_RUNTIME_PATH="$R/no-pulse" \
    "$W/kurashid" > "$R/server.log" 2>&1 &
pids+=("$!")
wait_until 10 K ping || fail "kurashid did not come up (see $R/server.log)"
# (the scenes' regions are on a 1920×1080 output)
if [ "$SCALE" = 1 ]; then
  swaymsg output '*' resolution 1920x1080 >/dev/null 2>&1 || true
else
  swaymsg output '*' resolution "$(awk -v s="$SCALE" 'BEGIN { printf "%dx%d", 1920 * s, 1080 * s }')" scale "$SCALE" \
    >/dev/null 2>&1 || true
fi
swaymsg output '*' bg '#8fb8c8' solid_color >/dev/null 2>&1 || true

ipc() { timeout 10 qs ipc -p "$H" call sheet "$@"; }
# The scenes' regions (the harness's card rects, with room for what a form draws past them).
region() {
  case $1 in
    panel|bottom) echo "200,0 1320x1080" ;;
    launcher) echo "300,0 1320x800" ;;
    sidebar) echo "0,0 420x1080" ;;
    right) echo "1500,0 420x1080" ;;
    toast) echo "1300,0 620x200" ;;
    module) echo "540,0 680x520" ;;
    dock) echo "640,580 640x500" ;;
    leftpanel) echo "0,0 700x1080" ;;
  esac
}
# A style's motion profile (W59.5's cases name a style; W59.4's run on kami's origami).
profile_of() {
  case $1 in
    terminal) echo phosphor ;; washi) echo sumi ;; aqua|vibrancy) echo aqua ;; glass) echo liquid ;;
    yorha) echo glitch ;; souls|hallownest) echo ember ;; snes) echo snes ;; ps2) echo ps2 ;; *) echo origami ;;
  esac
}
# The region's mean luminance (Rec. 709, 0 … 1).
luma() { magick "$OUT/$1.png" -colorspace Gray -format '%[fx:mean]' info:; }
# crt's photosensitivity rule over one sweep of shots: no step moves the mean by more than 0.2, and the mean rises and
# falls by ≥ 0.1 at most once (a flash is a pair of opposing changes, WCAG 2.3.1). Prints the largest step.
flash_safe() {
  local tag=$1; shift
  printf '%s\n' "$@" | awk -v tag="$tag" '
    { v[NR] = $1 }
    END {
      max = 0; flashes = 0; lo = v[1]; hi = v[1]; dir = 0
      for (i = 2; i <= NR; i++) {
        d = v[i] - v[i - 1]; if (d < 0) d = -d; if (d > max) max = d
        if (v[i] > hi) hi = v[i]; if (v[i] < lo) lo = v[i]
        # a swing of ≥ 0.1 one way, then ≥ 0.1 back: one flash
        if (dir >= 0 && hi - v[i] >= 0.1) { if (dir > 0) flashes++; dir = -1; lo = v[i] }
        else if (dir <= 0 && v[i] - lo >= 0.1) { if (dir < 0) flashes++; dir = 1; hi = v[i] }
      }
      printf "sheet: %s flash check: largest step %.3f, %d opposing swings ≥ 0.1\n", tag, max, flashes
      if (max > 0.2 || flashes > 1) exit 1
    }'
}
shot() { grim -g "$1" "$OUT/$2.png"; }
ae() { { magick compare -metric AE "$OUT/$1.png" "$OUT/$2.png" null: 2>&1 || true; } | awk '{print int($1)}'; }
qml_errors() {
  if grep -E 'qml:.*(Error|error)|TypeError|ReferenceError|is not a type|Binding loop|is not defined|failed to load' "$1" \
      | grep -v 'Unable to assign \[undefined\]' >/dev/null; then
    grep -E 'Error|error|Binding loop|not defined|failed' "$1" | head -20 >&2
    fail "QML errors (see $1)"
  fi
}
surface_of() {
  case $1 in sidebar|right) echo sidebar ;; toast) echo toast ;; launcher) echo launcher ;; dock) echo dock ;; *) echo panel ;; esac
}

for cs in $CASES; do
  IFS=: read -r form scene style scheme <<< "$cs"
  surf=$(surface_of "$scene"); g=$(region "$scene")
  tag=$form-$scene${style:+-$style}${scheme:+-$scheme}
  echo "-- $tag"
  style=${style:-$STYLE}; scheme=${scheme:-$SCHEME}
  K set theme.style "$style" >/dev/null || fail "$tag: theme.style $style refused"
  K set theme.motion.profile "$(profile_of "$style")" >/dev/null || fail "$tag: the profile was refused"
  if [ -n "$scheme" ]; then
    K set theme.colors.scheme "$scheme" >/dev/null || fail "$tag: theme.colors.scheme $scheme refused"
  else
    K reset theme.colors.scheme >/dev/null || true
  fi
  K set "theme.motion.form.$surf.open" "$form" >/dev/null || fail "$tag: theme.motion.form.$surf.open refused"
  K set "theme.motion.form.$surf.close" "$form" >/dev/null || fail "$tag: theme.motion.form.$surf.close refused"
  log=$R/h-$tag.log
  : > "$log"
  env -u KURASHI_SOCKET KURASHI_SOCKET="$KURASHI_SOCKET" SHEET_SCENE="$scene" qs -p "$H" >> "$log" 2>&1 &
  QS_PID=$!
  wait_for "$log" 'SHEETHARNESS up' 15 || fail "$tag: the harness did not start (see $log)"
  wait_until 10 sh -c "timeout 5 qs ipc -p '$H' call sheet info | grep -q 'form=$form family=sheet'" \
    || fail "$tag: the form never resolved ($(ipc info))"
  wait_settled 8 0.6 "$g"
  shot "$g" "$tag-rest"
  for p in $PS; do
    ipc at "$p" >/dev/null
    wait_settled 4 0.3 "$g"
    shot "$g" "$tag-$p"
    d=$(ae "$tag-$p" "$tag-rest")
    [ "$d" -gt 0 ] || fail "$tag: p = $p looks like the rest (no sheet drawn?)"
    echo "sheet: $tag p=$p: $d px from rest"
  done
  grep -q "motion: sheet layer up $surf $form" "$log" || fail "$tag: no 'motion: sheet layer up $surf $form' line"
  # W59.5's forms draw an open differently from a close (crt's afterglow, drop's evaporation), and W59.8b's dissolve condenses
  # from embers, glitch and pixelate run their frames forwards: the open too, from rest 0.
  case $form in genie|crt|drop|dissolve|glitch|pixelate)
    ipc at 0 >/dev/null
    wait_settled 4 0.3 "$g"
    for p in $PS; do
      ipc at "$p" >/dev/null
      wait_settled 4 0.3 "$g"
      shot "$g" "$tag-open-$p"
      ipc info | grep -q "form=$form .*dir=open busy=true" || fail "$tag: the open did not run ($(ipc info))"
      echo "sheet: $tag open p=$p: $(ae "$tag-open-$p" "$tag-rest") px from rest"
    done
    ipc at 1 >/dev/null
    wait_settled 4 0.3 "$g" ;;
  esac
  # crt and glitch: the photosensitivity rule over a sweep each way (0.05 steps: about a frame each at phosphor's timing)
  if [ "$form" = crt ] || [ "$form" = glitch ]; then
    ipc at 0 >/dev/null
    for dir in open close; do
      ls=()
      # (p = 0.01, not 0: the harness draws its card at rest 0 — a real surface is gone there)
      for i in $(seq 0 20); do
        if [ "$dir" = open ]; then p=$(awk -v i="$i" 'BEGIN { printf "%.2f", i ? i / 20 : 0.01 }')
        else p=$(awk -v i="$i" 'BEGIN { printf "%.2f", i < 20 ? 1 - i / 20 : 0.01 }'); fi
        ipc at "$p" >/dev/null
        wait_settled 4 0.2 "$g"
        shot "$g" "$tag-sweep-$dir-$i"
        ls+=("$(luma "$tag-sweep-$dir-$i")")
      done
      flash_safe "$tag $dir" "${ls[@]}" || fail "$tag: the $dir sweep breaks the photosensitivity rule (brief §11)"
    done
    ipc at 1 >/dev/null
    wait_settled 4 0.3 "$g"
  fi
  # reversal mid-way: the form stays latched, the rest frame comes back
  ipc at 0.3 >/dev/null; ipc at 0.6 >/dev/null; ipc at 0.4 >/dev/null
  ipc info | grep -q "form=$form .*dir=close busy=true" || fail "$tag: the reversal lost the form ($(ipc info))"
  ipc at 1 >/dev/null
  wait_settled 4 0.3 "$g"
  shot "$g" "$tag-1"
  d=$(ae "$tag-1" "$tag-rest")
  [ "$d" = 0 ] || fail "$tag: p = 1 differs from the rest in $d px"
  # a real run on the theme's curves, reversed before it lands
  ipc play 0 >/dev/null; sleep 0.15; ipc play 1 >/dev/null
  wait_until 5 sh -c "timeout 5 qs ipc -p '$H' call sheet info | grep -q 'busy=false'" || fail "$tag: the run never landed"
  wait_settled 4 0.3 "$g"
  shot "$g" "$tag-played"
  d=$(ae "$tag-played" "$tag-rest")
  [ "$d" = 0 ] || fail "$tag: the reversed run landed $d px from the rest"
  ups=$(grep -c 'motion: sheet layer up' "$log" || true); downs=$(grep -c 'motion: sheet layer .* released' "$log" || true)
  [ "$ups" = "$downs" ] || fail "$tag: a sheet layer is still up at rest ($ups up, $downs released)"
  qml_errors "$log"
  stop_h
  echo "sheet: $tag ok ($ups layers made and released)"
done
echo "sheet: ok (shots in $OUT)"
