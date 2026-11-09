#!/usr/bin/env bash
# A crowded bar never overlaps (B48, docs/ux/bar-fit.md), headless (sway sandbox), against the real kurashid and a fake
# MPRIS player with a long title (the user's case, session 26: start volume, the island's media title, sysmon; centre the
# window list, the timer, the weather; end the rest):
#   - roomy (1920 px): nothing compact, nothing in the overflow, the centre's middle within 1 px of the bar's;
#   - tight (1280 px): no two modules' boxes intersect; the centre in the middle, or moved the least amount (it then
#     stands one zone gap from the crowded side);
#   - overflowing (960 px, more windows): no intersection, a "…" button with the hidden modules; its card opens with
#     them (and the keyboard), Esc closes it;
#   - the default bar at 1920 px: nothing collapses;
#   - no binding loop and no QML error in the frontend's log.
# Each module's box from the bar's own log (KURASHI_BAR_GEOMETRY: BARZONE / BARWIN / BARFIT lines). Motion off (W55).
# Shots: frontend/shots/bar-fit/.
#   KURASHI_BIN_DIR=<dir with kurashid, kurashi, examples/fake_mpris_art> timeout 900 nix develop -c frontend/test-bar-fit.sh
# (`cargo build -p kurashid -p kurashi` and `cargo build -p kurashi-mock --example fake_mpris_art` first.)
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
NAME=${1:-${KURASHI_SB_PREFIX:-}w66-bar-fit}
BIN=${KURASHI_BIN_DIR:-${CARGO_TARGET_DIR:-$ROOT/target}/debug}
PLAYER_BIN=${KURASHI_FAKE_MPRIS_ART:-$BIN/examples/fake_mpris_art}
OUT=$ROOT/frontend/shots/bar-fit
FAILS=0
fail() { echo "test-bar-fit: FAIL $*" >&2; FAILS=$((FAILS + 1)); }
die() { echo "test-bar-fit: $*" >&2; exit 1; }
say() { echo "test-bar-fit: $*"; }
for b in "$BIN/kurashid" "$BIN/kurashi" "$PLAYER_BIN"; do [ -x "$b" ] || die "no $b (KURASHI_BIN_DIR; see the header)"; done

eval "$("$ROOT/tools/bench/sandbox.sh" start "$NAME")"
. "$ROOT/frontend/test-lib.sh"
R=$XDG_RUNTIME_DIR
W=$R/work
mkdir -p "$W" "$R/kurashi" "$OUT"
cp "$BIN/kurashid" "$BIN/kurashi" "$PLAYER_BIN" "$W/"
SRV=""; QS=""; WIN=""; PLAY=""
stop_one() { local p=${!1}; [ -n "$p" ] && { kill "$p" 2>/dev/null || true; wait "$p" 2>/dev/null || true; }; eval "$1="; }
cleanup() {
  stop_one WIN; stop_one QS; stop_one SRV
  [ -n "$PLAY" ] && { exec 7>&- 2>/dev/null || true; stop_one PLAY; }
  "$ROOT/tools/bench/sandbox.sh" stop "$NAME" >/dev/null || true
}
trap cleanup EXIT
trap 'echo "test-bar-fit: stopped at line $LINENO: $BASH_COMMAND" >&2' ERR

export XDG_CONFIG_HOME=$R/xdg/config XDG_STATE_HOME=$R/xdg/state \
       XDG_DATA_HOME=$R/xdg/data XDG_CACHE_HOME=$R/xdg/cache KURASHI_DATA_DIR=$ROOT LC_ALL=C.UTF-8
K() { timeout 10 "$W/kurashi" "$@"; }
swaymsg output '*' bg '#8fb8c8' solid_color >/dev/null
swaymsg 'default_border none' >/dev/null
: > "$R/qs.log"
size() { timeout 20 swaymsg output HEADLESS-1 resolution "$1x$2" >/dev/null || die "the output did not take $1x$2"; }
size 1920 1080

# ---- the daemon (idle lock off: I241; motion off: W55), the player, the windows, the frontend ----
rm -rf "$R/xdg"; mkdir -p "$XDG_CONFIG_HOME/kurashi" "$XDG_STATE_HOME" "$XDG_DATA_HOME" "$XDG_CACHE_HOME"
cat > "$XDG_CONFIG_HOME/kurashi/config.toml" <<'TOML'
idle.enabled = false
theme.style = "washi"
theme.motion.profile = "none"

[mods]
loaded = ["sysmon", "timer", "weather", "tasks"]
enabled = ["sysmon", "timer", "weather", "tasks"]

[mods.sysmon]
show = ["cpu", "mem", "temp", "load"]
TOML
rm -f "$KURASHI_SOCKET"
env DBUS_SYSTEM_BUS_ADDRESS="unix:path=$R/no-system-bus" PULSE_SERVER="unix:$R/no-pulse/native" \
    PULSE_RUNTIME_PATH="$R/no-pulse" "$W/kurashid" >> "$R/kurashid.log" 2>&1 &
SRV=$!
for _ in $(seq 100); do [ -S "$KURASHI_SOCKET" ] && K ping >/dev/null 2>&1 && break; sleep 0.1; done
K ping >/dev/null 2>&1 || die "kurashid did not come up (see $R/kurashid.log)"

rm -f "$R/player.in"; mkfifo "$R/player.in"
"$W/fake_mpris_art" "Zelda Ocarina of Time — Just Sent A Message (Full Playthrough, Part 3)" "Some Channel" "" 3600 "" \
  < "$R/player.in" >> "$R/player.log" 2>&1 &
PLAY=$!
exec 7> "$R/player.in"
# (a subscriber starts the media service: the snapshot comes first, the player's state in a patch after it)
wait_until 12 bash -c "timeout 4 '$W/kurashi' sub svc.media --count 4 --json 2>/dev/null | grep -q Ocarina" \
  || fail "the player's title never reached svc.media"

# Windows for the window list (one client, many toplevels).
windows() { # windows <n>
  stop_one WIN
  { echo 'import QtQuick'; echo 'import Quickshell'; echo 'ShellRoot {'
    for i in $(seq "$1"); do echo "  FloatingWindow { title: \"win $i\"; color: \"#c03030\"; implicitWidth: 200; implicitHeight: 150 }"; done
    echo '}'; } > "$W/wins.qml"
  env -u KURASHI_SOCKET qs -p "$W/wins.qml" >> "$R/win.log" 2>&1 &
  WIN=$!
  wait_until 10 sh -c "[ \$(swaymsg -t get_tree -r | jq '[.. | select(.pid? == $WIN)] | length') -ge $1 ]" \
    || fail "the $1 test windows did not map"
}
windows 6

env -u KURASHI_SOCKET KURASHI_BAR_GEOMETRY=1 qs -p "$ROOT/frontend" >> "$R/qs.log" 2>&1 &
QS=$!
wait_frontend "$R/qs.log" 0 8 0.6 || die "the frontend did not load (see $R/qs.log)"

apply() { K set "$@" >/dev/null || fail "kurashi set $* was refused"; wait_settled 3 0.6; }
mark() { echo "BARMARK $1" >> "$R/qs.log"; }
# The last logged layout of the top bar since mark <name>: the BARWIN line and the module lines after it.
block() { # block <mark>
  local m; m=$(grep -n "^BARMARK $1\$" "$R/qs.log" | tail -1 | cut -d: -f1)
  tail -n +"$((${m:-0} + 1))" "$R/qs.log" | grep -oE "BAR(WIN|ZONE|FIT) HEADLESS-1 top .*" \
    | awk '/^BARWIN/ { n = 0; delete b } { b[n++] = $0 } END { for (i = 0; i < n; i++) print b[i] }' || true
}
# Wait for a block whose BARFIT line has this width.
wait_block() { # wait_block <mark> <bar width>
  wait_until 8 bash -c "$(declare -f block); R='$R'; block '$1' | grep -q '^BARFIT HEADLESS-1 top width $2 '"
}
# check <mark> <what> <want: roomy|tight|overflow>
check() {
  local b; b=$(block "$1")
  [ -n "$b" ] || { fail "$2: no layout logged"; return; }
  local fit; fit=$(grep '^BARFIT' <<< "$b" | tail -1)
  say "$2: ${fit#BARFIT HEADLESS-1 top }"
  # No two boxes intersect (the modules and the overflow buttons; one row, so along x with their y spans).
  local over
  over=$(grep '^BARZONE' <<< "$b" | awk '{ id[NR] = $5; x0[NR] = $6; y0[NR] = $7; x1[NR] = $8; y1[NR] = $9 }
    END { for (i = 1; i <= NR; i++) for (j = i + 1; j <= NR; j++)
      if (x0[i] < x1[j] && x0[j] < x1[i] && y0[i] < y1[j] && y0[j] < y1[i]) printf "%s(%d-%d)x%s(%d-%d) ", id[i], x0[i], x1[i], id[j], x0[j], x1[j] }')
  [ -z "$over" ] && say "$2: no two modules intersect ($(grep -c '^BARZONE' <<< "$b") boxes)" || fail "$2: modules intersect: $over"
  # The centre: in the middle (1 px), or one zone gap from a side it was moved away from.
  local wd gap cmid c0 c1 s1 e0
  wd=$(awk '{ for (i = 1; i < NF; i++) if ($i == "width") print $(i + 1) }' <<< "$fit")
  gap=$(awk '{ for (i = 1; i < NF; i++) if ($i == "gap") print $(i + 1) }' <<< "$fit")
  read -r c0 c1 < <(grep '^BARZONE HEADLESS-1 top center ' <<< "$b" | awk 'NR == 1 { a = $6; z = $8 } { if ($6 < a) a = $6; if ($8 > z) z = $8 } END { print a + 0, z + 0 }')
  s1=$(grep '^BARZONE HEADLESS-1 top start ' <<< "$b" | awk 'BEGIN { z = 0 } { if ($8 > z) z = $8 } END { print z }')
  e0=$(grep '^BARZONE HEADLESS-1 top end ' <<< "$b" | awk -v w="$wd" 'BEGIN { a = w } { if ($6 < a) a = $6 } END { print a }')
  if [ "$c1" -gt 0 ]; then
    cmid=$(( c0 + c1 ))   # twice the middle
    if [ $(( cmid - wd )) -le 2 ] && [ $(( wd - cmid )) -le 2 ]; then say "$2: the centre stands in the middle ($c0-$c1 of $wd)"
    elif [ "$3" = roomy ]; then fail "$2: the centre ($c0-$c1) is not in the middle of $wd"
    # (a module's width is counted rounded up: a zone may draw a few px narrower than the fit counted, never wider)
    elif [ $(( c0 - s1 - gap )) -le 4 ] && [ $(( c0 - s1 - gap )) -ge -1 ]; then say "$2: the centre moved the least amount, away from the start ($s1 | $c0)"
    elif [ $(( e0 - c1 - gap )) -le 4 ] && [ $(( e0 - c1 - gap )) -ge -1 ]; then say "$2: the centre moved the least amount, away from the end ($c1 | $e0)"
    else fail "$2: the centre ($c0-$c1) is neither in the middle of $wd nor one gap ($gap) from a side ($s1, $e0)"; fi
  fi
  local comp park
  comp=$(awk '{ for (i = 1; i < NF; i++) if ($i == "compact") print $(i + 1) }' <<< "$fit")
  park=$(awk '{ for (i = 1; i < NF; i++) if ($i == "parked") print $(i + 1) }' <<< "$fit")
  case $3 in
    roomy|full) [ "$comp" = - ] && [ "$park" = - ] && say "$2: nothing collapsed" || fail "$2: collapsed at full width (compact $comp, parked $park)" ;;
    overflow)
      [ "$park" != - ] || fail "$2: nothing went into the overflow"
      grep -q '^BARZONE HEADLESS-1 top [a-z]* overflow ' <<< "$b" && say "$2: the overflow button stands ($park)" \
        || fail "$2: modules are parked ($park) but no overflow button is drawn" ;;
  esac
}
shoot() { grim -g "0,0 $1x48" "$OUT/$2.png"; }

LAYOUT=('edges.top.start=["volume","island","mod:sysmon:sysmon"]'
        'edges.top.center=["windows","mod:timer:timer","mod:weather:weather"]'
        'edges.top.end=["mod:tasks:tasks","recorder","keyboard","tray","quick","clock","sidebar_right"]')

# ---- the default bar, roomy ----
# (its end zone holds every mod widget and the island the media title: the centre may stand off the middle there)
mark default; wait_block default 1920 || true
check default "default bar 1920" full
shoot 1920 default-1920
# At rest the fit writes nothing (Ma): no run for two seconds once the bar stands.
before=$(log_size "$R/qs.log")
wait_settled 2 2
runs=$(tail -c +"$((before + 1))" "$R/qs.log" | grep -c 'BARFITRUN' || true)
[ "$runs" = 0 ] && say "idle: the fit wrote nothing for 2 s" || fail "idle: the fit wrote $runs time(s) in 2 s at rest"

# ---- the user's kind of bar ----
mark user1920; apply "${LAYOUT[@]}"; wait_block user1920 1920 || true
grep -q 'BARZONE HEADLESS-1 top start island' <(block user1920) || fail "user 1920: the island is not in the start zone"
check user1920 "user bar 1920" roomy
shoot 1920 user-1920

mark user1280; size 1280 800; wait_settled 3 0.6; wait_block user1280 1280 || true
check user1280 "user bar 1280" tight
shoot 1280 user-1280

mark user960; size 800 600; windows 12; wait_settled 3 0.6; wait_block user960 800 || true
check user960 "user bar 800, 12 windows" overflow
shoot 800 user-800

# ---- the overflow's card: opens with the hidden modules, takes the keyboard, Esc closes it ----
ob=$(block user960 | grep -oE '^BARZONE HEADLESS-1 top [a-z]+ overflow .*' | tail -1 | awk '{ print int(($6 + $8) / 2), int(($7 + $9) / 2) }')
if [ -n "$ob" ]; then
  before=$(log_size "$R/qs.log")
  # shellcheck disable=SC2086
  timeout 30 python3 -I "$ROOT/tools/bench/wl_pointer.py" click $ob left >/dev/null 2>&1 || true
  if wait_for "$R/qs.log" 'BAROVERFLOW open HEADLESS-1 top ' 5 "$before"; then
    line=$(tail -c +"$((before + 1))" "$R/qs.log" | grep -oE 'BAROVERFLOW open .*' | tail -1)
    say "overflow card: ${line#BAROVERFLOW open HEADLESS-1 top }"
    park=$(block user960 | grep '^BARFIT' | tail -1 | awk '{ for (i = 1; i < NF; i++) if ($i == "parked") print $(i + 1) }')
    for k in ${park//,/ }; do
      id=${k#*/}
      [[ " $(awk '{ print $5 }' <<< "$line" | tr ',' ' ') " == *" $id "* ]] || fail "overflow card: $id is parked but not in the card"
    done
    grim -g "0,0 800x160" "$OUT/overflow-card.png"
    # The keyboard: Tab reaches a module of the card.
    before=$(log_size "$R/qs.log")
    timeout 10 python3 -I "$ROOT/tools/bench/wl_keys.py" tab >/dev/null 2>&1 || true
    if wait_for "$R/qs.log" 'BAROVERFLOW focus (volume|mod:)' 5 "$before"; then
      say "overflow card: Tab reaches $(tail -c +"$((before + 1))" "$R/qs.log" | grep -oE 'BAROVERFLOW focus (volume|mod:)[^ ]*' | head -1 | cut -d' ' -f3)"
    else fail "overflow card: Tab reached no module ($(tail -c +"$((before + 1))" "$R/qs.log" | grep -oE 'BAROVERFLOW focus .*' | tail -1))"; fi
    before=$(log_size "$R/qs.log")
    timeout 10 python3 -I "$ROOT/tools/bench/wl_keys.py" escape >/dev/null 2>&1 || true
    wait_for "$R/qs.log" 'BAROVERFLOW closed' 5 "$before" && say "overflow card: Esc closed it" || fail "overflow card: Esc did not close it"
  else
    fail "overflow card: a click on the button opened nothing"
  fi
fi

# ---- back to roomy: everything returns ----
mark back; size 1920 1080; wait_settled 3 0.6; wait_block back 1920 || true
check back "user bar back at 1920, 12 windows" tight

# ---- the log ----
if grep -E 'Binding loop|binding loop' "$R/qs.log" | grep -qE 'bar|Bar|modules|Island|Widget'; then
  fail "a binding loop: $(grep -E 'inding loop' "$R/qs.log" | head -3)"
else say "no binding loop"; fi
errs=$(grep -E '(qml|QML|\.qml:[0-9]+).*(Error|TypeError|ReferenceError|Unable to assign|is not a type)' "$R/qs.log" | grep -vE 'BAR(ZONE|WIN|FIT)' | head -5 || true)
[ -z "$errs" ] && say "no QML error" || fail "QML errors: $errs"

if [ "$FAILS" -gt 0 ]; then echo "test-bar-fit: $FAILS failure(s); log $R/qs.log" >&2; exit 1; fi
echo "test-bar-fit: OK"
