#!/usr/bin/env bash
# Edge modules (K71, K72; docs/ux/edge-modules.md), headless (sway sandbox). Two groups on bar-less edges — the fixture's
# bottom-centre timer glance and a right-start group (clock, volume) — against the real kurashid (its layout step computes
# `runtime.layout` from the config this test sets, as Settings would), and the standalone island against kurashi-mock
# (its transient faces come from `mock.island`) wearing kurashid's theme tokens:
#   - states: every visibility (always, hover, empty desktop, hidden) × draw (dynamic, connected, floating) × frame off/on,
#     at rest and revealed, each group's place from its own log (KURASHI_EDGE_GEOMETRY: EDGEGROUP / EDGEMOD lines): the body
#     stands on the band (or the screen edge) at the layout's inset; hover — nothing at rest, out after the dwell on the
#     zone's span, gone after the pointer left; empty desktop — out with no window, gone with one, out again on hover;
#     hidden — out only while `layout.toggle {target: "module:<edge>:<zone>"}` lists it;
#   - span: two groups on one edge; the dwell on one zone's span reveals that group only; a touch shorter than the dwell
#     reveals nothing; the group goes ~400 ms after the pointer left (EDGEREVEAL timestamps);
#   - peek and expanded: hover on the timer glance asks its peek from the group's edge and place (row 514); a click on the
#     glance opens its panel; a click on the clock opens the island's clock card (K72);
#   - keys: a hidden group brought out by `layout.toggle` takes the keyboard — the first module has it, Enter opens the
#     clock card, Tab walks on, Esc puts the group away;
#   - reserve: a test window's place (sway's tree) for always + auto (the group holds the zone, holder module) and + off, and
#     hover + on;
#   - idle: no Wayland commit in 10 s at rest (an always group, a hover group), between two minutes of the clock;
#   - pss: the frontend's PSS without a group and with one always group, toggled live (pairs; budget ≤ +3 MiB, BENCH);
#   - island: the standalone island (top bar off, `island` in the top centre, hover) — nothing at rest, a transient volume
#     face grows it out (`island.main.system_events`), a click opens the island's card, the end of the face folds it;
#   - no QML error in the frontend's log.
# Shots: frontend/shots/edge-modules/<decor>/ (each group's region at full size); the timer's edge shots also go to
# mods/timer/shots/ (docs/ux/timer.md).
#   KURASHI_BIN_DIR=<dir with kurashid, kurashi, kurashi-mock> timeout 3600 nix develop -c frontend/test-edge-modules.sh [sandbox]
#   EDGE_DECORS="washi sekai" picks decors; EDGE_PARTS="states span peek keys reserve idle pss island" the parts;
#   EDGE_PAIRS=<n> the PSS pairs.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
NAME=${1:-w45-edge-test}
BIN=${KURASHI_BIN_DIR:-${CARGO_TARGET_DIR:-$ROOT/target}/debug}
OUT=$ROOT/frontend/shots/edge-modules
TIMER_OUT=$ROOT/mods/timer/shots
DECORS=${EDGE_DECORS:-washi sekai}
PARTS=${EDGE_PARTS:-states span peek keys reserve idle pss island}
PAIRS=${EDGE_PAIRS:-3}
FAILS=0
fail() { echo "test-edge: FAIL $*" >&2; FAILS=$((FAILS + 1)); }
die() { echo "test-edge: $*" >&2; exit 1; }
say() { echo "test-edge: $*"; }
want() { [[ " $PARTS " == *" $1 "* ]]; }
for b in kurashid kurashi kurashi-mock; do [ -x "$BIN/$b" ] || die "no $b in $BIN (KURASHI_BIN_DIR)"; done

eval "$("$ROOT/tools/bench/sandbox.sh" start "$NAME")"
R=$XDG_RUNTIME_DIR
W=$R/work
mkdir -p "$W" "$R/kurashi"
cp "$BIN/kurashid" "$BIN/kurashi" "$BIN/kurashi-mock" "$W/"
SRV=""; QS=""; WIN=""; PTR=""; KEY=""
stop_qs() { [ -n "$QS" ] && { kill "$QS" 2>/dev/null || true; wait "$QS" 2>/dev/null || true; }; QS=""; }
stop() {
  for pv in WIN QS SRV; do p=${!pv}; [ -n "$p" ] && { kill "$p" 2>/dev/null || true; wait "$p" 2>/dev/null || true; }; eval "$pv="; done
}
cleanup() {
  set +e
  stop
  # The second coprocess holds a copy of the first one's pipe: close both ends first, then make sure both are gone.
  [ -n "$PTR" ] && exec 7>&-
  [ -n "$KEY" ] && exec 8>&-
  for p in $PTR $KEY; do kill "$p" 2>/dev/null || true; wait "$p" 2>/dev/null || true; done
  # The removal is forked first, in a clean environment: the stop ends every process whose environment names the sandbox,
  # this script's children included, before a line after it runs (measured).
  setsid -f env -i PATH="$PATH" /bin/sh -c "sleep 4; rm -rf '/tmp/kurashi-sb-$NAME'" >/dev/null 2>&1 < /dev/null
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

# ---- the daemon (idle lock off: I241), the mock, the frontend ----
# The two groups every state shows: the fixture's bottom-centre timer and a right-start group.
GROUPS_CFG='edges.bottom.center = ["mod:timer:timer"]
edges.right.start = ["clock", "volume"]'
start_daemon() { # start_daemon <decor> [locale]
  stop
  local d=$1 loc=${2:-C}
  rm -rf "$R/xdg"; mkdir -p "$XDG_CONFIG_HOME/kurashi" "$XDG_STATE_HOME" "$XDG_DATA_HOME" "$XDG_CACHE_HOME"
  { echo 'idle.enabled = false'; printf 'theme.style = "%s"\n' "$d"; echo 'theme.motion.profile = "calm"'
    echo "$GROUPS_CFG"; } > "$XDG_CONFIG_HOME/kurashi/config.toml"
  rm -f "$KURASHI_SOCKET"
  env LC_ALL="$loc.UTF-8" LANG="$loc.UTF-8" DBUS_SYSTEM_BUS_ADDRESS="unix:path=$R/no-system-bus" \
      PULSE_SERVER="unix:$R/no-pulse/native" PULSE_RUNTIME_PATH="$R/no-pulse" "$W/kurashid" >> "$R/kurashid.log" 2>&1 &
  SRV=$!
  for _ in $(seq 100); do [ -S "$KURASHI_SOCKET" ] && K ping >/dev/null 2>&1 && break; sleep 0.1; done
  K ping >/dev/null 2>&1 || die "kurashid did not come up for $d (see $R/kurashid.log)"
  K act mod.enable '{"id": "timer"}' >/dev/null || fail "mod.enable timer was refused"
  BARH=$(K sub theme --count 0 --json | jq -r '.data.tokens["bar.height"] // 32')
  K sub theme --count 0 --json | jq -c '{doc: "theme", patch: {tokens: .data.tokens}}' > "$W/theme-$d.json"
}
start_mock() { # start_mock <decor>: kurashi-mock wearing kurashid's tokens for the decor
  stop
  rm -f "$KURASHI_SOCKET"
  "$W/kurashi-mock" --outputs HEADLESS-1 --socket "$KURASHI_SOCKET" >> "$R/mock.log" 2>&1 &
  SRV=$!
  for _ in $(seq 100); do [ -S "$KURASHI_SOCKET" ] && K ping >/dev/null 2>&1 && break; sleep 0.1; done
  K ping >/dev/null 2>&1 || die "kurashi-mock did not come up (see $R/mock.log)"
  K act mock.doc "$(cat "$W/theme-$1.json")" >/dev/null
}
mset() { # mset <key> <json value>: a config value on the mock (its layout step follows the config document)
  K act mock.doc "$(jq -cn --arg k "$1" --argjson v "$2" '{doc: "config", patch: {values: {($k): {value: $v, source: {kind: "user"}}}}}')" >/dev/null
}
start_qs() { # start_qs (env QS_ENV, QS_LANG)
  stop_qs
  env -u KURASHI_SOCKET KURASHI_EDGE_GEOMETRY=1 ${QS_LANG:+LC_ALL=$QS_LANG.UTF-8 LANG=$QS_LANG.UTF-8} ${QS_ENV:-} \
      qs -p "$ROOT/frontend" >> "$R/qs.log" 2>&1 &
  QS=$!
  sleep 5
}
apply() { K set "$@" >/dev/null || fail "kurashi set $* was refused"; }
settle() { sleep "${1:-2.5}"; }
mark() { echo "EDGEMARK $1" >> "$R/qs.log"; }
since_mark() { local m; m=$(grep -n "EDGEMARK" "$R/qs.log" | tail -1 | cut -d: -f1); tail -n +"$(( ${m:-0} + 1 ))" "$R/qs.log"; }
# The group's last logged state since the mark: "out …", "in …", "none", or "" (nothing logged).
group_of() { # since the mark, else the last one logged
  local l; l=$(since_mark | grep -o "EDGEGROUP HEADLESS-1 $1 $2 .*" | tail -1 || true)
  [ -n "$l" ] || l=$(grep -o "EDGEGROUP HEADLESS-1 $1 $2 .*" "$R/qs.log" | tail -1 || true)
  echo "$l" | cut -d' ' -f7-
}
state_of() { local s; s=$(group_of "$1" "$2"); s=${s%% *}; echo "${s:-none}"; }
wait_state() { # wait_state <edge> <zone> <out|none> <tries of 0.25 s>
  local i; for i in $(seq "${4:-20}"); do [ "$(state_of "$1" "$2")" = "$3" ] && return 0; sleep 0.25; done; return 1
}
expect_state() { # expect_state <edge> <zone> <out|none> <what>
  if wait_state "$1" "$2" "$3" 24; then say "$4: $1/$2 $3"; else fail "$4: $1/$2 is '$(group_of "$1" "$2")', not $3"; fi
}
# The module's box "x0 y0 x1 y1" from the last EDGEMOD line.
mod_of() { grep -o "EDGEMOD HEADLESS-1 [a-z]* [a-z]* $1 .*" "$R/qs.log" | tail -1 | cut -d' ' -f6- || true; }
inset_of() { K sub runtime.layout --count 0 --json | jq -r --arg e "$1" '(.data.outputs["HEADLESS-1"] // .data.outputs["*"]).edges[$e].inset'; }
ui() { K sub runtime.ui --count 0 --json | jq -c "${1:-.data}"; }
crop() { # crop <decor> <name>: each group's region at full size
  mkdir -p "$OUT/$1"
  grim -g "$((SW / 2 - 240)),$((SH - 80)) 480x80" "$OUT/$1/$2-bottom.png"
  grim -g "$((SW - 110)),0 110x420" "$OUT/$1/$2-right.png"
}
# The test window (an xdg toplevel sway tiles); its rect "x y w h".
cat > "$W/win.qml" <<'QML'
import QtQuick
import Quickshell
ShellRoot { FloatingWindow { color: "#c03030"; implicitWidth: 400; implicitHeight: 300 } }
QML
open_window() {
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
# One virtual pointer and one keyboard for the whole run (a device that goes away drops the window's focus).
pointer() {
  if [ -z "$PTR" ]; then
    coproc PTRP { python3 -I "$ROOT/tools/bench/wl_pointer.py" --serve; }
    PTR=$PTRP_PID; exec 7>&"${PTRP[1]}"
  fi
  echo "$*" >&7
}
keys() {
  if [ -z "$KEY" ]; then
    coproc KEYP { python3 -I "$ROOT/tools/bench/wl_keys.py" --serve; }
    KEY=$KEYP_PID; exec 8>&"${KEYP[1]}"
  fi
  echo "$*" >&8
}
away() { pointer move 700 500; }
commits() { tail -c +"$(( $1 + 1 ))" "$R/qs.log" | grep -c 'wl_surface#[0-9]*\.commit(' || true; }
pss_mib() { awk '/^Pss:/{s+=$2} END{printf "%.2f", s/1024}' "/proc/$1/smaps_rollup"; }
# Waits for a second of the minute where 10 s do not cross the next one (the clock's flip, K68).
between_minutes() { while :; do s=$((10#$(date +%S))); [ "$s" -ge 2 ] && [ "$s" -le 40 ] && return; sleep 1; done; }
# The body's outer edge stands at the edge's inset (from the screen edge); a floating pill's too (band + gap).
check_place() { # check_place <what>
  local b r ib ir; b=$(group_of bottom center); r=$(group_of right start)
  ib=$(inset_of bottom); ir=$(inset_of right)
  read -r _ _ bx by bw bh _ <<< "$b"; read -r _ _ rx ry rw rh _ <<< "$r"
  [ $((by + bh)) -eq $((SH - ib)) ] || fail "$1: the bottom group ends at $((by + bh)), not $((SH - ib)) (inset $ib)"
  [ $((rx + rw)) -eq $((SW - ir)) ] || fail "$1: the right group ends at $((rx + rw)), not $((SW - ir)) (inset $ir)"
  [ "$((bx + bw / 2))" -ge $((SW / 2 - 2)) ] && [ "$((bx + bw / 2))" -le $((SW / 2 + 2)) ] || fail "$1: the bottom group is not centred ($bx +$bw)"
  [ "$bh" -eq "$BARH" ] && [ "$rw" -eq "$BARH" ] || fail "$1: a group is not a bar thick ($bh, $rw; bar $BARH)"
}

# ---- states: visibility × draw × frame -------------------------------------------------------------------------------
states() { # states <decor>
  local d=$1 fr dr vis tag
  for fr in off on; do
    apply layout.frame.enabled "$([ $fr = on ] && echo true || echo false)"
    for dr in dynamic connected floating; do
      apply edges.bottom.draw "$dr"; apply edges.right.draw "$dr"
      for vis in always hover empty_desktop hidden; do
        tag="frame-$fr-$dr-$vis"
        away; mark "$tag"
        apply edges.bottom.visibility "$vis"; apply edges.right.visibility "$vis"
        settle
        case $vis in
          always)
            expect_state bottom center out "$d $tag"; expect_state right start out "$d $tag"
            check_place "$d $tag"
            crop "$d" "$tag" ;;
          hover)
            expect_state bottom center none "$d $tag rest"; expect_state right start none "$d $tag rest"
            crop "$d" "$tag-rest"
            mark "$tag-dwell"; pointer move "$((SW / 2))" "$((SH - 1))"; sleep 1.6
            expect_state bottom center out "$d $tag dwell"
            [ "$(state_of right start)" = none ] || fail "$d $tag: the dwell on the bottom edge brought the right group out too"
            crop "$d" "$tag-out"
            mark "$tag-leave"; away; sleep 1.8
            expect_state bottom center none "$d $tag left" ;;
          empty_desktop)
            expect_state bottom center out "$d $tag empty"; expect_state right start out "$d $tag empty"
            crop "$d" "$tag-empty"
            mark "$tag-window"; open_window; sleep 1
            expect_state bottom center none "$d $tag window"; expect_state right start none "$d $tag window"
            crop "$d" "$tag-window"
            mark "$tag-window-dwell"; pointer move "$((SW - 1))" 150; sleep 1.6
            expect_state right start out "$d $tag window dwell"
            crop "$d" "$tag-window-out"
            away; close_window ;;
          hidden)
            expect_state bottom center none "$d $tag rest"
            crop "$d" "$tag-rest"
            mark "$tag-toggle"; K act layout.toggle '{"target": "module:bottom:center"}' >/dev/null || fail "$d $tag: layout.toggle refused"
            sleep 1.6
            expect_state bottom center out "$d $tag toggled"
            [ "$(state_of right start)" = none ] || fail "$d $tag: toggling the bottom group brought the right one out"
            crop "$d" "$tag-toggled"
            mark "$tag-untoggle"; K act layout.toggle '{"target": "module:bottom:center"}' >/dev/null; sleep 1.6
            expect_state bottom center none "$d $tag toggled back" ;;
        esac
        # The timer's edge shots (docs/ux/timer.md): the dynamic draw, frame on.
        if [ "$fr" = on ] && [ "$dr" = dynamic ]; then
          for f in "$OUT/$d/$tag"*-bottom.png; do cp "$f" "$TIMER_OUT/edge-$(basename "${f%-bottom.png}" | sed 's/^frame-on-dynamic-//')-$d.png"; done
        fi
      done
    done
  done
  apply edges.bottom.visibility always; apply edges.right.visibility always
  apply edges.bottom.draw dynamic; apply edges.right.draw dynamic; apply layout.frame.enabled false
}

# ---- span: the zone's span reveals its group only; the dwell; the hide delay ---------------------------------------
span() { # span <decor>
  local d=$1
  apply edges.bottom.start '["clock"]'; apply edges.bottom.visibility hover; apply edges.right.visibility hover
  settle; away
  mark span-touch; pointer move "$((SW / 2))" "$((SH - 1))"; sleep 0.1; away; sleep 1
  [ "$(state_of bottom center)" = none ] || fail "$d span: a touch shorter than the dwell brought the group out"
  mark span-dwell; pointer move "$((SW / 2))" "$((SH - 1))"; sleep 1.6
  expect_state bottom center out "$d span centre dwell"
  [ "$(state_of bottom start)" = none ] || fail "$d span: the centre's dwell brought the start group out"
  crop "$d" span-centre
  mark span-leave; local t0; t0=$(date +%s%3N); away; sleep 1.8
  local t1; t1=$(since_mark | grep -o "EDGEREVEAL HEADLESS-1 bottom center false t=[0-9]*" | tail -1 | sed 's/.*t=//' || true)
  if [ -n "$t1" ]; then
    local dt=$((t1 - t0)); say "$d span: the group goes $dt ms after the pointer left"
    [ "$dt" -ge 300 ] && [ "$dt" -le 900 ] || fail "$d span: hidden $dt ms after leaving (want ~400)"
  else fail "$d span: no hide logged"; fi
  mark span-start; pointer move 200 "$((SH - 1))"; sleep 1.6
  expect_state bottom start out "$d span start dwell"
  [ "$(state_of bottom center)" = none ] || fail "$d span: the start's dwell brought the centre group out"
  away; sleep 1.5
  apply edges.bottom.start '[]'; apply edges.bottom.visibility always; apply edges.right.visibility always; settle
}

# ---- peek and expanded from an edge module ------------------------------------------------------------------------
peek() { # peek <decor>
  local d=$1 box x0 y0 x1 y1 cx cy
  mark peek; settle 1
  box=$(mod_of "mod:timer:timer"); [ -n "$box" ] || { K act layout.toggle '{}' >/dev/null 2>&1 || true; box=$(mod_of "mod:timer:timer"); }
  read -r x0 y0 x1 y1 <<< "$box"
  cx=$(((x0 + x1) / 2)); cy=$(((y0 + y1) / 2))
  pointer move "$cx" "$cy"; sleep 1.2
  local pk; pk=$(ui '.data.peek // {}')
  say "$d peek: $pk"
  [ "$(jq -r .source <<< "$pk")" = "mod:timer:timer" ] || fail "$d peek: the timer's peek was not asked ($pk)"
  [ "$(jq -r .edge <<< "$pk")" = bottom ] || fail "$d peek: the peek hangs off '$(jq -r .edge <<< "$pk")', not the group's bottom edge"
  local px; px=$(jq -r '.x // 0 | floor' <<< "$pk")
  [ "$px" -ge $((x0 - 2)) ] && [ "$px" -le $((x0 + 2)) ] || fail "$d peek: x $px is not the glance's $x0 (row 514: the window's place)"
  mkdir -p "$OUT/$d"; grim -g "$((SW / 2 - 300)),$((SH - 200)) 600x200" "$OUT/$d/peek-timer.png"
  pointer click "$cx" "$cy" left; sleep 1
  pointer click "$cx" "$cy" left; sleep 1.5
  [ "$(ui '.data.panel')" = '"mod:timer:timer"' ] || fail "$d expanded: a click on the running glance did not open its panel ($(ui '.data.panel'))"
  [ "$(state_of bottom center)" = out ] || fail "$d expanded: the group went while its card was open"
  grim -s 0.5 "$OUT/$d/expanded-timer.png"
  K act ui.close '{}' >/dev/null 2>&1 || true; K act timer.stop_all '{}' >/dev/null 2>&1 || true; sleep 1
  box=$(mod_of clock); read -r x0 y0 x1 y1 <<< "$box"
  pointer click "$(((x0 + x1) / 2))" "$(((y0 + y1) / 2))" left; sleep 1.5
  local u; u=$(ui '{panel: .data.panel, face: .data.face}')
  [ "$u" = '{"panel":"island","face":"clock"}' ] || fail "$d expanded: a click on the clock did not open the island's clock card ($u)"
  grim -s 0.5 "$OUT/$d/expanded-clock.png"
  K act ui.close '{}' >/dev/null 2>&1 || true; away; sleep 1
}

# ---- keys: brought out by key, Tab walks, Enter opens, Esc puts it away ------------------------------------------
keyboard() { # keyboard <decor>
  local d=$1
  apply edges.right.visibility hidden; settle; away
  mark keys; K act layout.toggle '{"target": "module:right:start"}' >/dev/null || fail "$d keys: layout.toggle refused"
  sleep 1.8
  expect_state right start out "$d keys toggled"
  mkdir -p "$OUT/$d"; grim -g "$((SW - 110)),0 110x420" "$OUT/$d/keys-first.png"
  keys return; sleep 1.5
  local u; u=$(ui '{panel: .data.panel, face: .data.face}')
  [ "$u" = '{"panel":"island","face":"clock"}' ] || fail "$d keys: Enter on the first module (the clock) did not open its card ($u)"
  [ "$(state_of right start)" = out ] || fail "$d keys: the group went while the card it opened was up"
  K act ui.close '{}' >/dev/null; sleep 1.5
  [ "$(ui '.data.shown // []' | jq -r 'index("module:right:start@HEADLESS-1")')" = null ] \
    || fail "$d keys: the group stayed out after the card it opened closed"
  mark keys-tab; K act layout.toggle '{"target": "module:right:start"}' >/dev/null; sleep 1.8
  keys tab; sleep 0.8
  grim -g "$((SW - 110)),0 110x420" "$OUT/$d/keys-tab.png"
  keys escape; sleep 1.5
  [ "$(ui '.data.shown // []')" = '[]' ] || fail "$d keys: Esc did not put the group away ($(ui '.data.shown'))"
  expect_state right start none "$d keys escape"
  apply edges.right.visibility always; settle
}

# ---- reserve: who holds the bottom edge's zone ----------------------------------------------------------------------
reserve() { # reserve <decor>
  local d=$1
  apply edges.right.start '[]'; apply edges.bottom.visibility always; apply edges.bottom.reserve auto; settle
  local h; h=$(K sub runtime.layout --count 0 --json | jq -r '(.data.outputs["HEADLESS-1"] // .data.outputs["*"]).edges.bottom | "\(.holder) \(.reserve)"')
  [ "$h" = "module $BARH" ] || fail "$d reserve: always + auto names '$h', not 'module $BARH'"
  open_window; read -r _ y _ hh <<< "$rect"
  [ $((y + hh)) -le $((SH - BARH)) ] || fail "$d reserve: always + auto — the window reaches $((y + hh)), past the group's zone ($((SH - BARH)))"
  say "$d reserve always+auto: window $rect"
  close_window
  apply edges.bottom.reserve off; settle; open_window; read -r _ y _ hh <<< "$rect"
  [ $((y + hh)) -eq "$SH" ] || fail "$d reserve: always + off — the window ends at $((y + hh)), not the screen's edge"
  say "$d reserve always+off: window $rect"
  close_window
  apply edges.bottom.visibility hover; apply edges.bottom.reserve on; settle; open_window; read -r _ y _ hh <<< "$rect"
  [ $((y + hh)) -le $((SH - BARH)) ] || fail "$d reserve: hover + on — the window reaches $((y + hh))"
  say "$d reserve hover+on: window $rect"
  close_window
  apply edges.bottom.reserve auto; apply edges.bottom.visibility always; apply edges.right.start '["clock", "volume"]'; settle
}

# ---- idle: no commit at rest ------------------------------------------------------------------------------------------
idle() { # idle <decor>
  local d=$1 s c
  QS_ENV=WAYLAND_DEBUG=client start_qs
  for vis in always hover; do
    apply edges.bottom.visibility "$vis"; apply edges.right.visibility "$vis"; away; settle 3
    between_minutes
    s=$(stat -c %s "$R/qs.log"); sleep 10; c=$(commits "$s")
    say "idle ($d, $vis): $c commits in 10 s"
    [ "$c" = 0 ] || fail "idle ($d, $vis): $c commits at rest"
  done
  apply edges.bottom.visibility always; apply edges.right.visibility always
  start_qs
}

# ---- pss: one shown group --------------------------------------------------------------------------------------------
pss() { # pss <decor>
  local d=$1 i a b
  apply edges.right.start '[]'; apply edges.bottom.center '[]'; apply edges.bottom.visibility always; settle 3
  # Toggled live, one frontend (its heap's history is in every number), …
  for i in $(seq "$PAIRS"); do
    apply edges.bottom.center '[]'; settle 6; a=$(pss_mib "$QS")
    apply edges.bottom.center '["mod:timer:timer"]'; settle 6; b=$(pss_mib "$QS")
    say "pss ($d) live pair $i: no group $a MiB → one always group $b MiB (Δ $(awk -v a="$a" -v b="$b" 'BEGIN{printf "%+.2f", b - a}'))"
  done
  # … and fresh frontends, each started with the layout in place (no history), 10 s after start.
  for i in $(seq "$PAIRS"); do
    apply edges.bottom.center '[]'; start_qs; sleep 5; a=$(pss_mib "$QS")
    apply edges.bottom.center '["mod:timer:timer"]'; start_qs; sleep 5; b=$(pss_mib "$QS")
    say "pss ($d) fresh pair $i: no group $a MiB → one always group $b MiB (Δ $(awk -v a="$a" -v b="$b" 'BEGIN{printf "%+.2f", b - a}'))"
  done
  apply edges.right.start '["clock", "volume"]'; settle
}

# ---- island: the standalone island on the top band (mock) -----------------------------------------------------------
island() { # island <decor>
  local d=$1 box x0 y0 x1 y1
  start_mock "$d"
  mset edges.top.bar false; mset edges.top.visibility '"hover"'; mset layout.frame.enabled true
  mset edges.bottom.center '[]'; mset edges.right.start '[]'
  start_qs; away; mark island
  settle 1
  local il; il=$(K sub runtime.layout --count 0 --json | jq -c '(.data.outputs["HEADLESS-1"] // .data.outputs["*"]).island')
  [ "$(jq -r .host <<< "$il")" = module ] || fail "$d island: the layout does not name the island an edge module ($il)"
  expect_state top center none "$d island rest"
  mkdir -p "$OUT/$d"; grim -g "$((SW / 2 - 300)),0 600x80" "$OUT/$d/island-rest.png"
  mark island-face; K act mock.island '{"face": "volume", "reason": "event"}' >/dev/null; sleep 1.6
  expect_state top center out "$d island transient face"
  for z in start end; do [ "$(state_of top $z)" = none ] || fail "$d island: the transient face brought the top $z group out"; done
  grim -g "$((SW / 2 - 300)),0 600x80" "$OUT/$d/island-transient.png"
  box=$(mod_of island); read -r x0 y0 x1 y1 <<< "$box"
  pointer click "$(((x0 + x1) / 2))" "$(((y0 + y1) / 2))" left; sleep 1.5
  [ "$(ui '.data.panel')" = '"island"' ] || fail "$d island: a click on the standalone island did not open its card ($(ui '.data.panel'))"
  grim -s 0.5 "$OUT/$d/island-card.png"
  K act ui.close '{}' >/dev/null 2>&1 || true; away
  mark island-fold; K act mock.island '{"face": "clock", "reason": "default"}' >/dev/null; sleep 2
  expect_state top center none "$d island folds back after the face"
  # The top start and end groups (the bar's zones, now edge modules) come out on hover of their span.
  mark island-start; pointer move 100 0; sleep 1.6
  expect_state top start out "$d island: the top start group on hover"
  grim -g "0,0 600x80" "$OUT/$d/top-start-out.png"
  away; sleep 1.5
}

for d in $DECORS; do
  say "== $d"
  start_daemon "$d"; start_qs
  want states && states "$d"
  want span && span "$d"
  want peek && peek "$d"
  want keys && keyboard "$d"
  want reserve && reserve "$d"
  want idle && idle "$d"
  want pss && pss "$d"
  want island && island "$d"
done

errs=$(grep -E "\.qml:[0-9]+:.*(Error|TypeError|ReferenceError)|Unable to assign|is not defined|Cannot read property|Binding loop" "$R/qs.log" | sort -u || true)
if [ -n "$errs" ]; then fail "QML errors in the frontend's log:"; echo "$errs" | head -30 >&2; fi
if [ "$FAILS" -gt 0 ]; then echo "test-edge: $FAILS failure(s)"; exit 1; fi
echo "test-edge: OK"
