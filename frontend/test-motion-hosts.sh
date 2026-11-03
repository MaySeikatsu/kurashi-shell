#!/usr/bin/env bash
# W64 (K83; docs/ux/motion-engine.md §5–§7, §11): the forms on the three hosts that ignored them — the dock (Dock.qml's
# FormHost and SheetRest), the bar's hover / empty-desktop reveal (Bar.qml, `surface: "bar"`, role fast) and the web dock's
# card (mods/webdock/qml/DockWindow.qml, `surface: "panel"`). Invisibly (headless sway; the visual review runs on niri):
#   landings  per host × sheet form (fold, genie) under kami: the frontend scrubbed (KURASHI_MOTION_SCRUB) at 0.9, 0.97 and
#             1, the host brought out; p = 1 equals the host at rest without scrub (≤ MH_REST_SLACK px), and 0.9 / 0.97 lie
#             within MH_LANDING_SLACK px of p = 1 at a 6 % colour tolerance (no corner pop, no shadow jump); 0.9 differs
#             from rest (the form is drawn);
#   reversal  the dock opening in fold, put away mid-way with genie as its close form: the fold refolds (the only sheet
#             layer of that transition is fold's) and the layer is released once it has landed;
#   ma        per host 20 open/close cycles in its sheet form: every `motion: sheet layer up` has its `released`, no QML
#             error, and the frontend's USS after the cycles within MH_USS_SLACK MiB of before (the sidebar's 11-MiB leak
#             of W59.9a is what this catches); the numbers are printed;
#   idle      per host one open and close in its sheet form, then 0 surface commits in 5 s (WAYLAND_DEBUG).
# The bar is brought out by `layout.toggle` (visibility `hidden`: the same `wantShown` as a hover's, without the dwell).
# Shots: frontend/shots/motion-hosts/ (gitignored; read them).
#   nix develop -c frontend/test-motion-hosts.sh
#   MH_PHASES="landings ma" MH_HOSTS="dock bar" nix develop -c frontend/test-motion-hosts.sh
# Binaries from $KURASHI_BIN_DIR (kurashid, kurashi), else $CARGO_TARGET_DIR/debug.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
NAME=${KURASHI_SB_PREFIX:-}w64-motion-hosts
BIN=${KURASHI_BIN_DIR:-${CARGO_TARGET_DIR:-$ROOT/target}/debug}
OUT=${MH_OUT:-$ROOT/frontend/shots/motion-hosts}
HOSTS=${MH_HOSTS:-dock bar webdock}
FORMS=${MH_FORMS:-fold genie}
CYCLES=${MH_CYCLES:-20}
mkdir -p "$OUT"
fail() { echo "test-motion-hosts: $*" >&2; exit 1; }
want() { [ -z "${MH_PHASES:-}" ] || [[ " $MH_PHASES " == *" $1 "* ]]; }

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
rm -f "$R/kurashi/locked"
# kami's paper (its origami pack); the dock and the top bar brought out by `layout.toggle`; the bar without its clocks (a
# minute's turn between two shots is not a seam); one view pin on the web dock (its card is the shell's, not the host's).
cat > "$XDG_CONFIG_HOME/kurashi/config.toml" <<'EOF'
[idle]
enabled = false
[theme]
style = "kami"
[dock]
enabled = true
visibility = "hidden"
pinned = ["firefox", "org.gnome.Nautilus", "foot"]
[edges.top]
visibility = "hidden"
center = []
end = []
EOF
: > "$R/server.log"
env DBUS_SYSTEM_BUS_ADDRESS="unix:path=$R/no-system-bus" \
    PULSE_SERVER="unix:$R/no-pulse/native" PULSE_RUNTIME_PATH="$R/no-pulse" \
    "$W/kurashid" >> "$R/server.log" 2>&1 &
pids+=("$!")
wait_until 10 K ping || fail "kurashid did not come up (see $R/server.log)"
swaymsg output '*' bg '#8fb8c8' solid_color >/dev/null 2>&1 || true
K act mod.enable '{"id":"webdock"}' >/dev/null || fail "mod.enable webdock was refused"
K set mods.webdock.pins '[{"id":"weather","title":"Weather","target":"mod:weather:weather"}]' >/dev/null \
  || fail "the web dock's pin was refused"
read -r OW OH < <(timeout 10 swaymsg -t get_outputs | python3 -c "import json,sys; o=json.load(sys.stdin)[0]; print(o['rect']['width'], o['rect']['height'])")

said_hello() { [ "$(grep -c 'hello.*frontend' "$R/server.log" || true)" -gt "$1" ]; }
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
  if grep -E 'qml:.*(Error|error)|TypeError|ReferenceError|is not a type|Binding loop|is not defined|failed to load' "$1" \
      | grep -v 'Unable to assign \[undefined\]' >/dev/null; then
    grep -E 'Error|error|Binding loop|not defined|failed to load' "$1" | head -20 >&2
    fail "QML errors (see $1)"
  fi
}
# Per host: its crop (the web dock's card without the strip, which a scrub holds mid-way too), and how it comes and goes.
crop_of() {
  case $1 in
    dock) echo "$(( OW / 2 - 300 )),$(( OH - 220 )) 600x220" ;;
    bar) echo "0,0 ${OW}x72" ;;
    webdock) echo "$(( OW - 520 )),0 462x$OH" ;;
  esac
}
surface_of() { case $1 in webdock) echo panel ;; *) echo "$1" ;; esac; }
bring() {   # bring <host> on|off
  case $1 in
    dock) K act layout.toggle '{"target":"dock"}' >/dev/null ;;
    bar) K act layout.toggle '{"target":"bar:top"}' >/dev/null ;;
    webdock) if [ "$2" = on ]; then K act webdock.open '{"pin":"weather"}' >/dev/null; else K act webdock.hide '{}' >/dev/null; fi ;;
  esac
}
# The daemon remembers a toggled host for the next frontend: put it away (a scrubbed close never lands; no wait).
put_away() { bring "$1" off || true; }
set_form() {   # set_form <surface> <open> [close]
  K set "theme.motion.form.$1.open" "\"$2\"" >/dev/null || fail "theme.motion.form.$1.open $2 refused"
  K set "theme.motion.form.$1.close" "\"${3:-$2}\"" >/dev/null || fail "theme.motion.form.$1.close ${3:-$2} refused"
}
reset_forms() { for s in dock bar panel; do K reset "theme.motion.form.$s.open" >/dev/null 2>&1 || true; K reset "theme.motion.form.$s.close" >/dev/null 2>&1 || true; done; }
ae() { { magick compare -metric AE -fuzz "${3:-0}%" "$OUT/$1.png" "$OUT/$2.png" null: 2>&1 || true; } | awk '{print int($1)}'; }
uss_mib() { awk '/^Private_(Clean|Dirty):/{s+=$2} END{printf "%.2f", s/1024}' "/proc/$1/smaps_rollup"; }

# ---- landings ----
if want landings; then
  echo "== landings"
  for h in $HOSTS; do
    sfc=$(surface_of "$h"); crop=$(crop_of "$h")
    # The host at rest, without scrub (its form: the slide).
    reset_forms
    start_fe "$R/qs-$h-rest.log"
    bring "$h" on; sleep 1; wait_settled 8 0.8 "$crop"
    grim -g "$crop" "$OUT/$h-rest.png"
    bring "$h" off; wait_settled 8 0.8 "$crop"
    qml_errors "$R/qs-$h-rest.log"
    stop_fe
    for f in $FORMS; do
      set_form "$sfc" "$f"
      for p in 0.9 0.97 1; do
        log=$R/qs-$h-$f-$p.log
        start_fe "$log" KURASHI_MOTION_SCRUB="$p"
        wait_for "$log" "motion: scrub $p" 5 || fail "$h $f: no 'motion: scrub $p' line"
        bring "$h" on; sleep 1.2; wait_settled 8 0.8 "$crop"
        grim -g "$crop" "$OUT/$h-$f-$p.png"
        if [ "$p" != 1 ]; then
          grep -q "motion: sheet layer up $sfc $f" "$log" || fail "$h $f p=$p: no sheet layer came up (the form was not drawn)"
        fi
        qml_errors "$log"
        put_away "$h"
        stop_fe
      done
      # (the web dock's phone card shows the time in its status row: a minute may turn between the two shots)
      slack=${MH_REST_SLACK:-0}; [ "$h" = webdock ] && slack=${MH_REST_SLACK:-300}
      d=$(ae "$h-$f-1" "$h-rest")
      [ "$d" -le "$slack" ] || fail "$h $f: p = 1 differs from the host at rest in $d px"
      for p in 0.9 0.97; do
        d=$(ae "$h-$f-$p" "$h-$f-1" 6)
        [ "$d" -le "${MH_LANDING_SLACK:-600}" ] || fail "$h $f: p = $p differs from p = 1 in $d px (a seam?)"
        echo "test-motion-hosts: landing $h $f p=$p: $d px from p = 1"
      done
      d=$(ae "$h-$f-0.9" "$h-rest")
      [ "$d" -gt 0 ] || fail "$h $f: p = 0.9 looks like the host at rest (the form was not drawn?)"
    done
  done
  reset_forms
fi

# ---- reversal: a fold put away mid-way refolds (the form in flight), whatever the close form ----
if want reversal && [[ " $HOSTS " == *" dock "* ]]; then
  echo "== reversal"
  K set theme.motion.speed 0.25 >/dev/null
  set_form dock fold genie
  log=$R/qs-reversal.log
  start_fe "$log"
  off=$(log_size "$log")
  # (the first open makes the dock's window: wait for the fold to be drawn, then put it away a moment into it)
  bring dock on
  wait_for "$log" 'motion: sheet layer up dock fold' 10 "$off" || fail "reversal: the fold never started"
  sleep 0.3
  grep -q 'sheet layer dock fold released' < <(tail -c +"$(( off + 1 ))" "$log") && fail "reversal: the fold landed in 0.3 s (speed not applied?)"
  bring dock off
  wait_for "$log" 'motion: sheet layer dock fold released' 10 "$off" || fail "reversal: the fold never landed"
  wait_settled 8 0.8 "$(crop_of dock)"
  # The fold refolds to its rest (its release is the landing at 0). FormHost then clears its latch, and its Loader makes and
  # drops the close form's sheet in the same turn (no frame drawn; reported to the lead, W64): a genie line may follow the
  # fold's release, never come before it.
  seq=$(tail -c +"$(( off + 1 ))" "$log" | grep -oE 'sheet layer (up )?dock [a-z]+( released)?' | tr '\n' '|')
  case $seq in
    "sheet layer up dock fold|sheet layer dock fold released|"*) ;;
    *) fail "reversal: the close mid-way did not continue the fold ($seq)" ;;
  esac
  qml_errors "$log"
  stop_fe
  K reset theme.motion.speed >/dev/null 2>&1 || true
  reset_forms
  echo "test-motion-hosts: reversal: the fold refolded and was released"
fi

# ---- ma: 20 cycles per host, USS before and after, every layer released ----
if want ma; then
  echo "== ma"
  for h in $HOSTS; do
    sfc=$(surface_of "$h"); crop=$(crop_of "$h")
    f=$( [ "$h" = dock ] && echo genie || echo fold )
    set_form "$sfc" "$f"
    log=$R/qs-ma-$h.log
    start_fe "$log"
    # (one cycle first: what the first open makes once — the window, its loaders — is not a leak)
    bring "$h" on; wait_for "$log" "sheet layer $sfc $f released" 10 || fail "ma $h: the first open never landed"
    wait_settled 8 0.8 "$crop"
    bring "$h" off; sleep 0.3; wait_settled 8 0.8 "$crop"; sleep 3
    u0=$(uss_mib "$QS_PID")
    for i in $(seq "$CYCLES"); do
      bring "$h" on; sleep 0.25; wait_settled 6 0.4 "$crop"
      bring "$h" off; sleep 0.25; wait_settled 6 0.4 "$crop"
    done
    sleep 3
    u1=$(uss_mib "$QS_PID")
    ups=$(grep -c "motion: sheet layer up $sfc" "$log" || true)
    downs=$(grep -c "motion: sheet layer $sfc .* released" "$log" || true)
    [ "$ups" = "$downs" ] || fail "ma $h: a sheet layer is still up at rest ($ups up, $downs released)"
    [ "$ups" -ge "$CYCLES" ] || fail "ma $h: only $ups sheet layers in $CYCLES cycles (the form did not run)"
    qml_errors "$log"
    echo "test-motion-hosts: USS $h ($f, $CYCLES cycles): $u0 → $u1 MiB ($ups layers up and released)"
    awk -v a="$u0" -v b="$u1" -v s="${MH_USS_SLACK:-4}" 'BEGIN { exit !(b - a <= s) }' \
      || fail "ma $h: USS grew from $u0 to $u1 MiB over $CYCLES cycles (more than ${MH_USS_SLACK:-4} MiB)"
    put_away "$h"
    stop_fe
  done
  reset_forms
fi

# ---- idle: after each host's form has closed, the shell commits nothing (Ma: 0 frames at rest) ----
if want idle; then
  echo "== idle"
  commits() { tail -c +"$(( $1 + 1 ))" "$2" | grep -cE 'wl_surface#[0-9]+\.commit\(' || true; }
  set_form dock genie; set_form bar fold; set_form panel fold
  log=$R/qs-idle.log
  start_fe "$log" WAYLAND_DEBUG=1
  for h in $HOSTS; do
    sfc=$(surface_of "$h")
    off=$(log_size "$log")
    bring "$h" on; wait_for "$log" "sheet layer $sfc [a-z]+ released" 10 "$off" || fail "idle $h: the open never landed"
    off=$(log_size "$log")
    bring "$h" off; wait_for "$log" "sheet layer $sfc [a-z]+ released" 10 "$off" || fail "idle $h: the close never landed"
    wait_log_quiet "$log" 'wl_surface#[0-9]+\.commit\(' 1 10
    off=$(log_size "$log"); sleep 5
    n=$(commits "$off" "$log")
    [ "$n" = 0 ] || fail "idle $h: $n surface commits in 5 s after the close (idle must be 0 frames)"
    echo "test-motion-hosts: idle $h: 0 commits in 5 s after its form closed"
  done
  qml_errors "$log"
  stop_fe
  reset_forms
fi
echo "test-motion-hosts: ok (shots in $OUT)"
