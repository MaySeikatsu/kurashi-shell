#!/usr/bin/env bash
# Bars on every edge (K71, K72; docs/ux/layout.md), headless (sway sandbox), against the real kurashid (its layout step
# computes `runtime.layout` from the config this test sets, as the user's Settings would):
#   - zones and bars: the default top bar; bars on top + bottom (image 6) with modules on both; a module moved to another
#     zone and bar; one left bar (`layout.bar.move`, vertical zones); bars on all four edges, the side bars between the
#     horizontal ones — each module's place from the bar's own log (KURASHI_BAR_GEOMETRY: BARZONE / BARWIN lines);
#   - draw: the mode table's bar row (dynamic, connected, floating; floating on each edge), with the frame off and on;
#   - visibility: hover (the pointer rests on the edge: not out before the dwell, out after it, gone after it left),
#     empty desktop (out with no window, gone with one), hidden (`kurashi act layout.toggle '{"target":"bar:bottom"}'`);
#   - reserve: a test window's place (sway's tree) for always + auto / off and hover + on / auto;
#   - idle: no Wayland commit in 10 s (default bar; frame on with the paper material);
#   - row 492 (b): the frontend's PSS with the frame off and on, toggled live, this frontend against a reference one
#     (BARS_REF=<frontend dir>, e.g. `git archive main frontend`), back-to-back pairs; and the texture seam at 8× under
#     `theme.texture.sheet` carried and fixed (row 490);
#   - the window kept unmapped while hidden against none (KURASHI_BAR_DROP=1), PSS after a reveal;
#   - no QML error in the frontend's log.
# Shots: frontend/shots/bars/<decor>/.
#   KURASHI_BIN_DIR=<dir with kurashid, kurashi> timeout 2400 nix develop -c frontend/test-bars.sh [sandbox]
#   BARS_DECORS="washi sekai" picks decors; BARS_PARTS="zones draw reveal reserve idle pss" the parts; BARS_PAIRS=<n>.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
NAME=${1:-w44-bar-test}
BIN=${KURASHI_BIN_DIR:-${CARGO_TARGET_DIR:-$ROOT/target}/debug}
OUT=$ROOT/frontend/shots/bars
DECORS=${BARS_DECORS:-washi sekai}
PARTS=${BARS_PARTS:-zones draw reveal reserve idle pss}
PAIRS=${BARS_PAIRS:-3}
FAILS=0
fail() { echo "test-bars: FAIL $*" >&2; FAILS=$((FAILS + 1)); }
die() { echo "test-bars: $*" >&2; exit 1; }
say() { echo "test-bars: $*"; }
want() { [[ " $PARTS " == *" $1 "* ]]; }
for b in kurashid kurashi; do [ -x "$BIN/$b" ] || die "no $b in $BIN (KURASHI_BIN_DIR)"; done

eval "$("$ROOT/tools/bench/sandbox.sh" start "$NAME")"
R=$XDG_RUNTIME_DIR
W=$R/work
mkdir -p "$W" "$R/kurashi"
cp "$BIN/kurashid" "$BIN/kurashi" "$W/"
SRV=""; QS=""; WIN=""; PTR=""
stop_qs() { [ -n "$QS" ] && { kill "$QS" 2>/dev/null || true; wait "$QS" 2>/dev/null || true; }; QS=""; }
stop() {
  for pv in WIN QS SRV; do p=${!pv}; [ -n "$p" ] && { kill "$p" 2>/dev/null || true; wait "$p" 2>/dev/null || true; }; eval "$pv="; done
}
cleanup() {
  stop
  [ -n "$PTR" ] && { exec 7>&-; wait "$PTR" 2>/dev/null || true; }
  "$ROOT/tools/bench/sandbox.sh" stop "$NAME" >/dev/null || true
}
trap cleanup EXIT

export XDG_CONFIG_HOME=$R/xdg/config XDG_STATE_HOME=$R/xdg/state \
       XDG_DATA_HOME=$R/xdg/data XDG_CACHE_HOME=$R/xdg/cache KURASHI_DATA_DIR=$ROOT LC_ALL=C.UTF-8
K() { timeout 10 "$W/kurashi" "$@"; }
SW=1920; SH=1080
timeout 20 swaymsg output HEADLESS-1 resolution "${SW}x${SH}" >/dev/null || die "the output did not take ${SW}x${SH}"
swaymsg output '*' bg '#8fb8c8' solid_color >/dev/null
swaymsg 'default_border none' >/dev/null
swaymsg 'default_floating_border none' >/dev/null
: > "$R/qs.log"

# ---- the daemon (one per decor; idle lock off: I241) and the frontend ----
start_daemon() { # start_daemon <decor>: washi, sekai, kanso; -paper adds the paper material
  stop
  local d=$1 style=${1%%-*}
  rm -rf "$R/xdg"; mkdir -p "$XDG_CONFIG_HOME/kurashi" "$XDG_STATE_HOME" "$XDG_DATA_HOME" "$XDG_CACHE_HOME"
  { echo 'idle.enabled = false'; printf 'theme.style = "%s"\n' "$style"; echo 'theme.motion.profile = "calm"'
    [[ "$d" == *-paper* ]] && printf 'theme.texture.kind = "paper"\ntheme.texture.strength = 1.5\n'; true; } > "$XDG_CONFIG_HOME/kurashi/config.toml"
  rm -f "$KURASHI_SOCKET"
  env DBUS_SYSTEM_BUS_ADDRESS="unix:path=$R/no-system-bus" PULSE_SERVER="unix:$R/no-pulse/native" \
      PULSE_RUNTIME_PATH="$R/no-pulse" "$W/kurashid" >> "$R/kurashid.log" 2>&1 &
  SRV=$!
  for _ in $(seq 100); do [ -S "$KURASHI_SOCKET" ] && K ping >/dev/null 2>&1 && break; sleep 0.1; done
  K ping >/dev/null 2>&1 || die "kurashid did not come up for $d (see $R/kurashid.log)"
  if [[ "$d" == *-paper* ]]; then
    for _ in $(seq 100); do [ -n "$(K sub theme --count 0 --json | jq -r '.data.tokens["texture.map"] // ""')" ] && break; sleep 0.2; done
  fi
  BARH=$(K sub theme --count 0 --json | jq -r '.data.tokens["bar.height"] // 36')
}
start_qs() { # start_qs [frontend dir] (env QS_ENV)
  stop_qs
  env -u KURASHI_SOCKET KURASHI_BAR_GEOMETRY=1 ${QS_ENV:-} qs -p "${1:-$ROOT/frontend}" >> "$R/qs.log" 2>&1 &
  QS=$!
  sleep 5
}
# A config change, then the time the bars need to follow (the springs at the calm profile).
apply() { K set "$@" >/dev/null || fail "kurashi set $* was refused"; sleep 2.5; }
reset_layout() { K reset edges >/dev/null 2>&1 || true; K reset layout >/dev/null 2>&1 || true; sleep 2; }
shoot() { # shoot <decor> <name>: the screen (half size), and each bar's edge at full size
  mkdir -p "$OUT/$1"
  grim -s 0.5 "$OUT/$1/$2.png"
}
pixel() { grim -t ppm -g "$1,$2 1x1" - | tail -c 3 | od -An -tu1 | xargs; }
BG="143 184 200"
# The last logged place of module `id`: "<edge> <zone> x0 y0 x1 y1", or "" when no bar shows it.
zone_of() {
  sleep 0.8
  local mark; mark=$(grep -n "BARMARK" "$R/qs.log" | tail -1 | cut -d: -f1); mark=${mark:-0}
  tail -n +"$((mark + 1))" "$R/qs.log" | grep -o "BARZONE HEADLESS-1 [a-z]* [a-z]* $1 .*" | tail -1 | cut -d' ' -f3,4,6- || true
}
# The bar windows logged since the last mark: "<edge> x y w h shown|hidden" per edge (the last line per edge).
bar_win() {
  local mark; mark=$(grep -n "BARMARK" "$R/qs.log" | tail -1 | cut -d: -f1); mark=${mark:-0}
  tail -n +"$((mark + 1))" "$R/qs.log" | grep -o "BARWIN HEADLESS-1 $1 .*" | tail -1 | cut -d' ' -f4- || true
}
mark() { echo "BARMARK $1" >> "$R/qs.log"; }
expect_zone() { # expect_zone <id> <edge> <zone> <what>
  local z; z=$(zone_of "$1")
  case "$z" in "$2 $3 "*) say "$4: $1 on $2/$3 (${z#* * })" ;; *) fail "$4: $1 is at '${z:-nowhere}', not $2/$3" ;; esac
}
expect_none() { local z; z=$(zone_of "$1"); [ -z "$z" ] || fail "$2: $1 is still drawn ($z)"; }

# The test window (an xdg toplevel sway tiles); its rect "x y w h".
cat > "$W/win.qml" <<'QML'
import QtQuick
import Quickshell
ShellRoot { FloatingWindow { color: "#c03030"; implicitWidth: 400; implicitHeight: 300 } }
QML
window_rect() {
  env -u KURASHI_SOCKET qs -p "$W/win.qml" >> "$R/win.log" 2>&1 &
  WIN=$!
  rect=""
  for _ in $(seq 50); do
    rect=$(swaymsg -t get_tree -r | jq -r --argjson p "$WIN" '.. | select(.pid? == $p) | .rect | "\(.x) \(.y) \(.width) \(.height)"' | head -1)
    [ -n "$rect" ] && break; sleep 0.1
  done
  sleep 1.5
  rect=$(swaymsg -t get_tree -r | jq -r --argjson p "$WIN" '.. | select(.pid? == $p) | .rect | "\(.x) \(.y) \(.width) \(.height)"' | head -1)
  return 0
}
close_window() { [ -n "$WIN" ] && { kill "$WIN" 2>/dev/null || true; wait "$WIN" 2>/dev/null || true; }; WIN=""; sleep 1; }
# One virtual pointer for the whole run (tools/bench/wl_pointer.py --serve).
pointer() {
  if [ -z "$PTR" ]; then
    coproc PTRP { python3 -I "$ROOT/tools/bench/wl_pointer.py" --serve; }
    PTR=$PTRP_PID; exec 7>&"${PTRP[1]}"
  fi
  echo "$*" >&7
}
commits() { tail -c +"$(( $1 + 1 ))" "$R/qs.log" | grep -c 'wl_surface#[0-9]*\.commit(' || true; }
pss_mib() { awk '/^Pss:/{s+=$2} END{printf "%.2f", s/1024}' "/proc/$1/smaps_rollup"; }

# ======================================== zones and bars ========================================
if want zones; then
  for d in $DECORS; do
    start_daemon "$d"; mark default; start_qs
    shoot "$d" default
    expect_zone island top center "$d default"
    expect_zone clock top end "$d default"
    expect_zone workspaces top start "$d default"

    # Image 6: a bar on top and one at the bottom, the modules on both.
    mark top-bottom
    apply edges.bottom.bar=true 'edges.top.start=["sidebar_left","workspaces","windows"]' 'edges.top.center=["island"]' \
      'edges.top.end=["clock","quick","tray","sidebar_right"]' 'edges.bottom.start=["volume"]' 'edges.bottom.center=[]' \
      'edges.bottom.end=["mods","recorder","keyboard"]'
    shoot "$d" top-bottom
    expect_zone clock top end "$d top+bottom"
    expect_zone volume bottom start "$d top+bottom"
    w=$(bar_win bottom); say "$d top+bottom: bottom bar window $w"
    case "$w" in "0 $((SH - BARH)) $SW $BARH shown") ;; *) fail "$d top+bottom: the bottom bar's window is '$w'" ;; esac

    # A module moved to another zone of another bar: the clock from the top's end to the bottom's center.
    mark moved
    apply 'edges.top.end=["quick","tray","sidebar_right"]' 'edges.bottom.center=["clock"]'
    shoot "$d" moved
    expect_zone clock bottom center "$d moved"
    z=$(zone_of clock); set -- $z
    cx=$(( ($3 + $5) / 2 )); [ "$cx" -ge $((SW / 2 - 40)) ] && [ "$cx" -le $((SW / 2 + 40)) ] || fail "$d moved: the clock is not centred ($z)"

    # One bar on the left (the move takes its zones along: `layout.bar.move`).
    reset_layout
    mark left
    K act layout.bar.move '{"from":"top","to":"left"}' >/dev/null || fail "layout.bar.move top → left was refused"
    sleep 3
    shoot "$d" left
    expect_zone island left center "$d left"
    expect_zone clock left end "$d left"
    w=$(bar_win left); say "$d left: window $w"
    case "$w" in "0 0 $BARH $SH shown") ;; *) fail "$d left: the bar's window is '$w', not 0 0 $BARH $SH" ;; esac

    # Three edges: top, bottom and a right bar between them.
    reset_layout
    mark three
    apply edges.bottom.bar=true edges.right.bar=true 'edges.top.end=["clock","quick"]' 'edges.bottom.start=[]' \
      'edges.bottom.center=["windows"]' 'edges.bottom.end=["volume"]' 'edges.right.start=[]' 'edges.right.center=[]' \
      'edges.right.end=["tray","recorder","keyboard","sidebar_right"]'
    shoot "$d" three
    w=$(bar_win right); say "$d three: right window $w"
    case "$w" in "$((SW - BARH)) $BARH $BARH $((SH - 2 * BARH)) shown") ;; *) fail "$d three: the right bar's window is '$w'" ;; esac
    expect_zone volume bottom end "$d three"

    # All four edges: the horizontal bars own the corners, the side bars run between them.
    reset_layout
    mark four
    apply edges.bottom.bar=true edges.left.bar=true edges.right.bar=true \
      'edges.top.end=["clock","quick"]' 'edges.bottom.start=[]' 'edges.bottom.center=["windows"]' 'edges.bottom.end=[]' \
      'edges.left.start=[]' 'edges.left.center=[]' 'edges.left.end=["volume"]' \
      'edges.right.start=[]' 'edges.right.center=[]' 'edges.right.end=["tray","recorder","keyboard","sidebar_right"]'
    shoot "$d" four
    for e in left right; do
      w=$(bar_win $e); say "$d four: $e window $w"
      x=$([ $e = left ] && echo 0 || echo $((SW - BARH)))
      case "$w" in "$x $BARH $BARH $((SH - 2 * BARH)) shown") ;; *) fail "$d four: the $e bar's window is '$w', not $x $BARH $BARH $((SH - 2 * BARH))" ;; esac
    done
    expect_zone volume left end "$d four"
    window_rect; say "$d four: test window at $rect"
    set -- $rect
    [ "${1:-x}" = "$BARH" ] && [ "${2:-x}" = "$BARH" ] && [ "${3:-0}" = $((SW - 2 * BARH)) ] && [ "${4:-0}" = $((SH - 2 * BARH)) ] \
      || fail "$d four: the window is at $rect, not inside the four bars"
    close_window
    reset_layout
  done
fi

# ======================================== draw ========================================
if want draw; then
  for d in $DECORS; do
    start_daemon "$d"; start_qs
    for fr in off on; do
      [ $fr = on ] && apply layout.frame.enabled=true
      for mode in dynamic connected floating; do
        mark "draw-$mode-$fr"
        apply layout.draw="$mode"
        shoot "$d" "draw-$mode-frame-$fr"
        w=$(bar_win top); say "$d $mode, frame $fr: top window $w"
        if [ $mode = floating ]; then
          # A pill `inset` from its edge: the screen's top rows and its first columns show what is under the bar.
          [ $fr = off ] && { [ "$(pixel $((SW / 2)) 2)" = "$BG" ] || fail "$d floating: the bar reaches the screen's edge"; }
          band=0; [ $fr = on ] && band=8
          [ "$(pixel $((SW / 2)) $((8 + band + BARH / 2)))" != "$BG" ] || fail "$d floating, frame $fr: no bar where the pill stands"
        elif [ "$d" != sekai ] || [ $fr = on ]; then
          # (sekai's groups float as keys on a clear strip, unless the bar is the frame's band.)
          [ "$(pixel 3 $((BARH / 2)))" != "$BG" ] || fail "$d $mode, frame $fr: the docked bar does not reach the screen's end"
        fi
      done
      [ $fr = on ] && apply layout.frame.enabled=false
    done
    # Floating on every edge (the bar moved there with its zones).
    apply layout.draw=floating
    from=top
    for e in bottom left right top; do
      K act layout.bar.move "{\"from\":\"$from\",\"to\":\"$e\"}" >/dev/null || fail "layout.bar.move $from → $e was refused"
      from=$e
      sleep 3
      shoot "$d" "floating-$e"
    done
    # The connected corners with the frame on, 4× (the bar's end over the fillet).
    apply layout.frame.enabled=true layout.draw=dynamic
    mkdir -p "$OUT/$d"; grim -s 4 -g "0,0 120x90" "$OUT/$d/frame-dynamic-corner.png"
    reset_layout
  done
fi

# ======================================== visibility ========================================
if want reveal; then
  d=${DECORS%% *}
  start_daemon "$d"; start_qs
  pointer move $((SW / 2)) 600
  # Hover: hidden at rest, out after the dwell, gone 400 ms after the pointer left.
  apply edges.top.visibility=hover
  sleep 1
  [ "$(pixel $((SW / 2)) 10)" = "$BG" ] || fail "hover: the bar is out at rest"
  shoot "$d" hover-rest
  pointer move $((SW / 2)) 0
  # (move settles 0.5 s; the dwell is 250 ms: it is out by now, and was not before the pointer came.)
  sleep 0.8
  [ "$(pixel $((SW / 2)) 10)" != "$BG" ] || fail "hover: the bar did not come out after the dwell"
  shoot "$d" hover-out
  pointer move $((SW / 2)) 20
  sleep 1
  [ "$(pixel $((SW / 2)) 10)" != "$BG" ] || fail "hover: the bar went while the pointer was on it"
  pointer move $((SW / 2)) 600
  sleep 1.5
  [ "$(pixel $((SW / 2)) 10)" = "$BG" ] || fail "hover: the bar stayed after the pointer left"
  say "hover: hidden at rest, out after the dwell, stays under the pointer, gone after it left"
  # Empty desktop: out with no window, gone with one.
  apply edges.top.visibility=empty_desktop
  sleep 1
  [ "$(pixel $((SW / 2)) 10)" != "$BG" ] || fail "empty desktop: the bar is not out on an empty desktop"
  shoot "$d" empty-desktop
  window_rect
  sleep 1
  [ "$(pixel 4 10)" != "143 184 200" ] && [ "$(pixel 4 10)" != "192 48 48" ] && fail "empty desktop: the bar stayed out over a window" || true
  shoot "$d" empty-desktop-window
  close_window
  sleep 1.5
  [ "$(pixel $((SW / 2)) 10)" != "$BG" ] || fail "empty desktop: the bar did not come back when the window went"
  # Hidden: out only while `layout.toggle` brought it out (runtime.ui.shown).
  apply edges.top.visibility=always edges.bottom.bar=true edges.bottom.visibility=hidden 'edges.bottom.center=["clock"]'
  sleep 1
  [ "$(pixel $((SW / 2)) $((SH - 10)))" = "$BG" ] || fail "hidden: the bottom bar is out"
  K act layout.toggle '{"target":"bar:bottom"}' >/dev/null || fail "layout.toggle bar:bottom was refused"
  sleep 1.5
  [ "$(pixel $((SW / 2)) $((SH - 10)))" != "$BG" ] || fail "hidden: layout.toggle did not bring the bar out"
  shoot "$d" hidden-toggled
  K act layout.toggle '{"target":"bar:bottom"}' >/dev/null || fail "layout.toggle bar:bottom (back) was refused"
  sleep 1.5
  [ "$(pixel $((SW / 2)) $((SH - 10)))" = "$BG" ] || fail "hidden: the second layout.toggle did not put the bar away"
  # Brought out by key, it takes the keyboard on a click (OnDemand) and Esc puts it away.
  K act layout.toggle '{"target":"bar:bottom"}' >/dev/null || fail "layout.toggle bar:bottom was refused"
  sleep 1.5
  pointer click $((SW / 2 - 300)) $((SH - 10)) left
  sleep 0.5
  timeout 10 python3 -I "$ROOT/tools/bench/wl_keys.py" escape || fail "wl_keys escape failed"
  sleep 1.5
  [ "$(pixel $((SW / 2)) $((SH - 10)))" = "$BG" ] || fail "hidden: Esc did not put the bar away"
  [ "$(K sub runtime.ui --count 0 --json 2>/dev/null | jq -r '.data.shown // [] | length')" = 0 ] || fail "hidden: runtime.ui.shown still lists the bar after Esc"
  say "empty desktop and hidden: done"
  # Hover on the bottom bar, the pointer at the bottom edge.
  apply edges.bottom.visibility=hover
  pointer move $((SW / 2)) $((SH - 1))
  sleep 0.8
  [ "$(pixel $((SW / 2)) $((SH - 10)))" != "$BG" ] || fail "hover (bottom): the bar did not come out"
  pointer move $((SW / 2)) 600
  sleep 1.5
  reset_layout
fi

# ======================================== reserve ========================================
if want reserve; then
  d=${DECORS%% *}
  start_daemon "$d"; start_qs
  for c in "always auto $BARH" "always off 0" "hover on $BARH" "hover auto 0" "hover off 0"; do
    set -- $c
    apply edges.top.visibility="$1" edges.top.reserve="$2"
    window_rect; say "reserve: $1 + $2: test window at $rect"
    set -- $c $rect
    [ "${5:-x}" = "$3" ] || fail "reserve $1 + $2: the window starts at y ${5:-?}, not $3"
    close_window
  done
  reset_layout
fi

# ======================================== idle ========================================
if want idle; then
  for ds in washi:off washi-paper:on; do
    d=${ds%:*}; fr=${ds#*:}
    start_daemon "$d"; QS_ENV=WAYLAND_DEBUG=client start_qs
    [ $fr = on ] && apply layout.frame.enabled=true
    # The bar clock's minute flip is the one idle commit the budget allows (K68): measure between two minutes.
    sleep 3; while [ "$(date +%-S)" -gt 40 ] || [ "$(date +%-S)" -lt 2 ]; do sleep 1; done
    s=$(stat -c %s "$R/qs.log"); sleep 10; c=$(commits "$s")
    say "idle ($d, frame $fr): $c commits in 10 s"
    [ "$c" = 0 ] || fail "idle ($d, frame $fr): $c commits"
  done
fi

# ======================================== PSS (row 492 b) and the seam ========================================
if want pss; then
  REF=${BARS_REF:-}
  for d in kanso washi-paper; do
    start_daemon "$d"
    for fe in ${REF:+ref} new; do
      dir=$ROOT/frontend; [ $fe = ref ] && dir=$REF
      start_qs "$dir"; sleep 4
      for i in $(seq "$PAIRS"); do
        K set layout.frame.enabled=false >/dev/null; sleep 5; a=$(pss_mib "$QS")
        K set layout.frame.enabled=true >/dev/null; sleep 5; b=$(pss_mib "$QS")
        say "PSS $d $fe pair $i: frame off $a MiB, on $b MiB (+$(awk -v a="$a" -v b="$b" 'BEGIN{printf "%.2f", b - a}') MiB)"
      done
      K set layout.frame.enabled=false >/dev/null
    done
  done
  # The seam (rows 490, 492 b): the docked bar's end and the band's fillet at 8×, the sheet carried and fixed.
  start_daemon washi-paper; start_qs
  apply layout.frame.enabled=true
  for sh in carried fixed; do
    apply theme.texture.sheet="$sh"
    mkdir -p "$OUT/washi-paper"; grim -s 8 -g "0,$((BARH - 12)) 40x40" "$OUT/washi-paper/seam-$sh.png"
  done
  # A hover bar's window, kept unmapped after a reveal against none (KURASHI_BAR_DROP=1): PSS at rest after one reveal.
  for v in keep drop; do
    start_daemon kanso
    env=""; [ $v = drop ] && env=KURASHI_BAR_DROP=1
    QS_ENV=$env start_qs
    apply edges.top.visibility=hover
    pointer move $((SW / 2)) 600; sleep 3; a=$(pss_mib "$QS")
    pointer move $((SW / 2)) 0; sleep 1.5; pointer move $((SW / 2)) 600; sleep 5
    b=$(pss_mib "$QS")
    say "PSS hidden bar ($v): before the first reveal $a MiB, after one reveal and hide $b MiB"
  done
fi

stop
if grep -E 'ERROR|qml:.*(Error|error)|TypeError|ReferenceError|is not a type|Cannot assign|Unable to assign|Binding loop' "$R/qs.log" \
    | grep -v 'Unable to assign \[undefined\]' >/dev/null; then
  grep -E 'Error|error|Cannot assign|Unable to assign|Binding loop' "$R/qs.log" | sort | uniq -c | head -20 >&2
  fail "QML errors (see $R/qs.log)"
fi
[ "$FAILS" = 0 ] || die "$FAILS checks failed"
say "ok ($OUT)"
