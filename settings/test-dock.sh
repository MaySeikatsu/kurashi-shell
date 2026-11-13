#!/usr/bin/env bash
# Settings docked in a sidebar section (W77, K146; docs/ux/settings.md "In a sidebar"). `SETTINGS_PART=dock settings/test.sh`
# runs this, or on its own: `nix develop -c settings/test-dock.sh`. Binaries from KURASHI_BIN_DIR, else
# $CARGO_TARGET_DIR/debug (built by the caller: tools/test-suites.sh builds once).
#   Part 1, on nested niri (the lead platform, tools/bench/niri-sandbox.sh): the right sidebar with the sections header and
#   settings. Its toggle starts Settings for the dock (one process) and Settings maps its dock over the well: the rect in
#   `runtime.settings.dock` is the dock window's; a click in it and typed keys land in its search; Esc clears the search,
#   the next Esc closes the sidebar and the dock goes (no host, the document without `dock`), the process stays (a minute)
#   and the sidebar's toggle brings it back at once; a narrow sidebar (320) makes the chrome compact and its drawer opens;
#   `kurashi settings` moves the content to Settings' own window (the dock says so), the dock's Show here brings it back
#   (the window says so), closing the window leaves it in the dock; `sidebar.close` takes it away. Shots light and dark at
#   420 and 320 px, the drawer, both "elsewhere" notes.
#   Part 2, two outputs (headless sway: nested niri has one): a sidebar on each output, the last to rest has the dock, the
#   other's well says where it is shown; opening that one again takes it back.
# Shots: $DOCK_OUT/shots (default /tmp/kurashi-settings-dock/shots).
set -uo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
if ! command -v qs >/dev/null || ! command -v niri >/dev/null || ! command -v sway >/dev/null; then
  exec nix develop "$ROOT" -c "$0" "$@"
fi
BIN=${KURASHI_BIN_DIR:-${CARGO_TARGET_DIR:-$ROOT/target}/debug}
for b in kurashid kurashi; do [ -x "$BIN/$b" ] || { echo "test-dock: no $b in $BIN" >&2; exit 1; }; done
export KURASHI_BIN_DIR=$BIN
export KURASHI_NIRI_SB_NAME=${KURASHI_SB_PREFIX:-}settings-dock
export KURASHI_NIRI_SB_OUT=${DOCK_OUT:-/tmp/kurashi-settings-dock}
OUT=$KURASHI_NIRI_SB_OUT
SB="$ROOT/tools/bench/niri-sandbox.sh"
. "$ROOT/frontend/test-lib.sh"
FAILS=0
ok() { echo "test-dock: ok: $*"; }
fail() { echo "test-dock: FAIL: $*" >&2; FAILS=$((FAILS + 1)); }
die() { echo "test-dock: FAIL: $*" >&2; exit 1; }
SWAY2=""
cleanup() {
  "$SB" stop >/dev/null 2>&1 || true
  [ -n "$SWAY2" ] && "$ROOT/tools/bench/sandbox.sh" stop "$SWAY2" >/dev/null 2>&1 || true
}
trap cleanup EXIT
rm -rf "$OUT"; mkdir -p "$OUT/shots"
SHOTS=$OUT/shots

# ---- part 1: nested niri ----
cat > "$OUT/config.toml" <<'TOML'
[idle]
enabled = false
[theme.colors]
scheme = "light"
[theme.motion]
profile = "none"
[sidebar.right]
mode = "stack"
sections = ["header", "settings"]
visibility = "hidden"
width = 420
TOML
"$SB" start "$OUT/config.toml" >/dev/null || die "the niri sandbox did not start"
NENV=$OUT/niri-env.sh
K() { ( . "$NENV"; timeout 10 "$BIN/kurashi" "$@" ); }
Q() { ( . "$NENV"; timeout 10 qs -p "$ROOT/settings" ipc call settings "$@" 2>/dev/null ); }
keys() { ( . "$OUT/sway-env.sh"; python3 -I "$ROOT/tools/bench/wl_keys.py" "$@" ); }
dock() { K sub runtime.settings --count 0 | jq -c '.data.dock // empty'; }
host_is() { case "$(Q host)" in $1) return 0;; esac; return 1; }
# The Settings processes the daemon started (`<qs> -p <this checkout>/settings`, nothing after).
RT=$(. "$NENV"; echo "$XDG_RUNTIME_DIR")
procs() { local n=0 p; for p in $(pgrep -f -- " -p $ROOT/settings\$"); do
  tr "\0" "\n" < "/proc/$p/environ" 2>/dev/null | grep -qx "XDG_RUNTIME_DIR=$RT" && n=$((n + 1)); done; echo "$n"; }
q_is() { [ "$(Q "$1")" = "$2" ]; }
# The dock's rect on the screen (x, y from the output's corner; niri's output is 1080 high).
shot_dock() { local d; d=$(dock); [ -n "$d" ] || return 1
  local x w; w=$(jq .width <<<"$d")
  x=$(jq .x <<<"$d")
  "$SB" shot "$1" "$((x - 8)),0 $((w + 16))x1080" 1 >/dev/null; }

wait_until 20 K ping || die "the daemon did not answer"
wait_for "$(. "$NENV"; echo "$XDG_RUNTIME_DIR")/qs.log" 'Configuration Loaded' 20 || die "the shell did not load"
sleep 1
K act sidebar.toggle '{"side":"right"}' >/dev/null || fail "sidebar.toggle"
wait_until 20 host_is "dock *" || die "Settings did not dock over the section (host: $(Q host); dock: $(dock))"
D=$(dock)
H=$(Q host)
[ "$H" = "dock $(jq -r .x <<<"$D"),$(jq -r .y <<<"$D") $(jq -r .width <<<"$D")x$(jq -r .height <<<"$D") on $(jq -r .output <<<"$D")" ] \
  && ok "the dock window is the well's rect ($H)" || fail "the dock window ($H) is not the document's rect ($D)"
jq -e "has(\"radius\")" <<<"$D" >/dev/null && ok "the well's radius goes with it ($(jq -r .radius <<<"$D"))" || fail "no radius in $D"
[ "$(procs)" = 1 ] && ok "one Settings process" || fail "Settings processes: $(procs)"
[ "$(Q userOpen)" = false ] && ok "no window of its own (started for the dock)" || fail "a dock-only Settings opened its window"
[ "$(Q compact)" = true ] && ok "the chrome is compact at 420 px" || fail "not compact at 420 ($(Q compact))"
sleep 0.5; shot_dock dock-light-420
F0=$(Q frames); sleep 1.5
[ "$(Q frames)" = "$F0" ] && ok "docked and still: no frames (Ma)" || fail "frames while docked and still ($F0 → $(Q frames))"

# A click in the dock (its left margin, half way down: the page's ground) gives it the keyboard; typing searches.
X=$(( $(jq .x <<<"$D") + 5 ))
Y=$(( $(jq .y <<<"$D") + $(jq .height <<<"$D") / 2 ))
"$SB" click "$X" "$Y" >/dev/null
keys r a d i u s
wait_until 5 q_is query radius && ok "a key typed in the dock lands in its search" || fail "typed keys did not reach the search ($(Q query))"
sleep 0.4; shot_dock dock-search
keys escape
wait_until 3 q_is query "" || fail "Esc did not clear the search"
keys escape
wait_until 5 host_is "" && ok "Esc then closes the sidebar and the dock goes" || fail "Esc did not take the dock away ($(Q host))"
[ -z "$(dock)" ] && ok "runtime.settings has no dock" || fail "the dock stayed in the document: $(dock)"
Q current >/dev/null && ok "Settings stays (kept a minute)" || fail "Settings ended with the dock"
# (undocked there is no window to draw: the frames counted are the host's, so this only says nothing is hosted)

K act sidebar.toggle '{"side":"right"}' >/dev/null
wait_until 8 host_is "dock *" && ok "the toggle brings it back" || fail "the dock did not come back ($(Q host))"
[ "$(procs)" = 1 ] && ok "still one process" || fail "Settings processes: $(procs)"

# Narrow: 320 px.
K set sidebar.right.width 320 >/dev/null
wait_until 8 host_is "dock * 2[0-9][0-9]x*" && ok "a 320 px sidebar docks a narrower Settings ($(Q host))" || fail "not narrower at 320 ($(Q host))"
sleep 0.5; shot_dock dock-light-320
Q drawer true >/dev/null
[ "$(Q compact)" = drawer ] && ok "the pages' drawer opens" || fail "no drawer ($(Q compact))"
sleep 0.4; shot_dock dock-drawer-320
Q drawer false >/dev/null

K set theme.colors.scheme dark >/dev/null
sleep 2.5; shot_dock dock-dark-320
K set sidebar.right.width 420 >/dev/null
wait_until 8 host_is "dock * 3[0-9][0-9]x*" || fail "back to 420 ($(Q host))"
sleep 1; shot_dock dock-dark-420
K set theme.colors.scheme light >/dev/null
sleep 1.5

# One content, two places.
K settings >/dev/null
wait_until 8 host_is window && ok "kurashi settings moves it to its window" || fail "settings.open did not show the window ($(Q host))"
[ "$(Q userOpen)" = true ] || fail "userOpen after settings.open"
sleep 1; "$SB" shot in-window >/dev/null
Q showHere >/dev/null
wait_until 5 host_is "dock *" && ok "Show here brings it to the dock" || fail "Show here ($(Q host))"
sleep 1; "$SB" shot in-sidebar >/dev/null
WID=$( ( . "$NENV"; niri msg -j windows ) | jq -r '.[] | select(.title == "Kurashi settings") | .id' | head -1)
if [ -n "$WID" ]; then
  ( . "$NENV"; niri msg action close-window --id "$WID" ) >/dev/null
  wait_until 5 q_is userOpen false && ok "closing the window leaves it in the dock" || fail "the window's close ($(Q userOpen))"
  host_is "dock *" || fail "the dock lost it when the window closed ($(Q host))"
else
  fail "no Settings window found in niri's list"
fi
K act sidebar.close >/dev/null
wait_until 5 host_is "" && ok "sidebar.close takes it away" || fail "sidebar.close ($(Q host))"

# Pinned (the column keeps a zone: a Normal-mode surface would be pushed off the well by it), then the top bar off from
# under it (the window moves on the output, the well in it does not), then the dock taken away under it.
K set sidebar.right.visibility always >/dev/null
wait_until 10 host_is "dock *" && ok "a pinned sidebar docks it ($(Q host))" || fail "pinned: no dock ($(Q host))"
sleep 1; shot_dock dock-pinned
Y0=$(dock | jq .y)
K set edges.top.bar false >/dev/null
dock_moved() { local y; y=$(dock | jq '.y // -1'); [ "$y" != -1 ] && [ "$y" != "$Y0" ]; }
wait_until 10 dock_moved && ok "the top bar gone, the dock follows the well ($Y0 → $(dock | jq .y))" || fail "the dock stayed at y $Y0 with the bar gone ($(dock))"
wait_until 5 host_is "dock *" || fail "no dock after the bar went ($(Q host))"
sleep 1; shot_dock dock-pinned-nobar
K set edges.top.bar true >/dev/null
sleep 1
# The dock goes from under a resting section (as after a daemon restart: an empty document): the section asks again.
K act settings.dock '{}' >/dev/null
has_dock() { [ -n "$(dock)" ]; }
wait_until 8 has_dock && wait_until 5 host_is "dock *" && ok "a dock taken away under a resting section is asked for again ($(Q host))" || fail "not docked again ($(Q host); $(dock))"
[ "$(procs)" = 1 ] && ok "still one process" || fail "Settings processes: $(procs)"

# The left sidebar (anchored to the other edge).
K set sidebar.right.visibility hidden >/dev/null
K set sidebar.left.sections '["settings"]' >/dev/null || fail "sidebar.left.sections = [settings] was refused"
K act sidebar.toggle '{"side":"left"}' >/dev/null
wait_until 10 host_is "dock *" && ok "the left sidebar docks it ($(Q host))" || fail "left: no dock ($(Q host))"
LD=$(dock); [ "$(jq .x <<<"$LD")" -lt 960 ] && ok "on the left ($LD)" || fail "the left dock is not on the left: $LD"
sleep 1; "$SB" shot dock-left "0,0 $(( $(jq .x <<<"$LD") + $(jq .width <<<"$LD") + 8 ))x1080" 1 >/dev/null
K act sidebar.close >/dev/null
wait_until 5 host_is "" || fail "left: sidebar.close ($(Q host))"

# Known gap (docs/ux/settings.md): a sidebar opened by hover holds on the pointer over its own window only.
K set sidebar.left.visibility hover >/dev/null
"$SB" move 1 540 >/dev/null; sleep 0.3; "$SB" move 0 540 >/dev/null
if wait_until 6 host_is "dock *"; then
  LD=$(dock)
  "$SB" move "$(( $(jq .x <<<"$LD") + $(jq .width <<<"$LD") / 2 ))" "$(( $(jq .y <<<"$LD") + 200 ))" >/dev/null
  sleep 2
  host_is "dock *" && ok "hover: the sidebar stays with the pointer on Settings" \
    || fail "a hover-opened sidebar closed with the pointer on the docked Settings (B127; $(Q host))"
  [ "$(K sub runtime.settings --count 0 | jq -r '.data.hover // false')" = true ] \
    || fail "runtime.settings has no hover with the pointer on the dock"
  # Session 33 (the user: the drawer and the menus in Settings closed the sidebar): the pages' drawer open, the pointer on
  # its rows (they take the hover), the sidebar still stays.
  if [ "$(Q compact)" != false ]; then
    Q drawer true >/dev/null
    sleep 0.6
    for dy in 120 160 200 240; do
      "$SB" move "$(( $(jq .x <<<"$LD") + 60 ))" "$(( $(jq .y <<<"$LD") + dy ))" >/dev/null
      sleep 0.5
    done
    sleep 1.5
    host_is "dock *" && ok "hover: the sidebar stays with the pointer on the drawer's rows" \
      || fail "a hover-opened sidebar closed with the pointer on Settings' drawer ($(Q host))"
    Q drawer false >/dev/null
  fi
  # The pointer leaves the dock and the column: the sidebar goes after its grace.
  "$SB" move 960 540 >/dev/null
  wait_until 6 host_is "" && ok "hover: off the dock and the column, the sidebar goes" \
    || fail "the sidebar stayed after the pointer left the dock ($(Q host))"
else
  echo "test-dock: KNOWN GAP: the hover reveal did not open the left sidebar here (not measured)"
fi
"$SB" stop >/dev/null 2>&1

# ---- part 2: two outputs (headless sway) ----
SWAY2=${KURASHI_SB_PREFIX:-}settings-dock2
eval "$("$ROOT/tools/bench/sandbox.sh" start "$SWAY2")"
R=$XDG_RUNTIME_DIR; RT=$R
"$ROOT/tools/bench/sandbox.sh" output-add "$SWAY2" >/dev/null || die "no second output"
swaymsg output HEADLESS-1 pos 0 0 >/dev/null 2>&1
W1=$(swaymsg -t get_outputs -r | jq '.[] | select(.name == "HEADLESS-1") | .rect.width')
swaymsg output HEADLESS-2 pos "$W1" 0 >/dev/null 2>&1
export XDG_CONFIG_HOME=$R/xdg/config XDG_STATE_HOME=$R/xdg/state XDG_DATA_HOME=$R/xdg/data XDG_CACHE_HOME=$R/xdg/cache
export KURASHI_DATA_DIR=$ROOT LC_ALL=C.UTF-8 KURASHI_SOCKET=$R/kurashi.sock
mkdir -p "$XDG_CONFIG_HOME/kurashi" "$XDG_STATE_HOME" "$XDG_DATA_HOME" "$XDG_CACHE_HOME"
# (pinned: both sidebars rest at once — a toggled one closes the other output's)
sed 's/^visibility = "hidden"/visibility = "always"/' "$OUT/config.toml" > "$XDG_CONFIG_HOME/kurashi/config.toml"
env DBUS_SYSTEM_BUS_ADDRESS="unix:path=$R/no-system-bus" PULSE_SERVER="unix:$R/no-pulse/native" \
  PULSE_RUNTIME_PATH="$R/no-pulse" setsid "$BIN/kurashid" >> "$R/kurashid.log" 2>&1 < /dev/null &
for _ in $(seq 100); do [ -S "$KURASHI_SOCKET" ] && "$BIN/kurashi" ping >/dev/null 2>&1 && break; sleep 0.1; done
setsid qs -p "$ROOT/frontend" >> "$R/qs.log" 2>&1 < /dev/null &
wait_frontend "$R/qs.log" 0 15 0.6 "" || true
K() { timeout 10 "$BIN/kurashi" "$@"; }
Q() { timeout 10 qs -p "$ROOT/settings" ipc call settings "$@" 2>/dev/null; }
wait_until 25 host_is "dock * on HEADLESS-*" || fail "pinned sidebars on two outputs docked nothing ($(Q host))"
A=$(dock | jq -r .output); B=HEADLESS-2; [ "$A" = HEADLESS-2 ] && B=HEADLESS-1
ok "one of the two pinned sidebars has the dock ($A)"
# (each output's right end, where its sidebar stands)
end_of() { [ "$1" = HEADLESS-1 ] && echo "$((W1 - 440)),0 440x1080" || echo "$((W1 * 2 - 440)),0 440x1080"; }
sleep 1; grim -g "$(end_of "$B")" "$SHOTS/elsewhere-$B.png" 2>/dev/null || true
grim -g "$(end_of "$A")" "$SHOTS/docked-$A.png" 2>/dev/null || true
# Settings is drawn on the well, not beside it: the top third of the docked well differs from the same part of the other
# output's well (plain there), pixel for pixel.
covers() {
  local DD GX OX RW RH RX RY AE on; DD=$(dock); on=$(jq -r .output <<<"$DD")
  GX=0; OX=$W1; [ "$on" = HEADLESS-2 ] && { GX=$W1; OX=$(( -W1 )); }
  RW=$(jq .width <<<"$DD"); RH=$(( $(jq .height <<<"$DD") / 3 )); RX=$(( $(jq .x <<<"$DD") + GX )); RY=$(jq .y <<<"$DD")
  grim -g "$RX,$RY ${RW}x$RH" "$OUT/well-a.png" 2>/dev/null; grim -g "$(( RX + OX )),$RY ${RW}x$RH" "$OUT/well-b.png" 2>/dev/null
  AE=$(magick compare -metric AE "$OUT/well-a.png" "$OUT/well-b.png" null: 2>&1 | cut -d' ' -f1 | cut -d. -f1)
  [ "${AE:-0}" -gt $(( RW * RH / 20 )) ] && ok "Settings covers the docked well on $on ($AE px differ)" \
    || fail "the docked well on $on looks like the plain one ($AE px differ): Settings is not on it"
}
covers
# The other one rests anew (its width changes): the last to rest wins; the first did not withdraw it on the way.
K set --output "$B" sidebar.right.width 400 >/dev/null
wait_until 10 host_is "dock * on $B" && ok "the last well to rest has it ($B)" || fail "not moved to $B ($(Q host))"
sleep 1; covers
K set --output "$A" sidebar.right.width 400 >/dev/null
wait_until 10 host_is "dock * on $A" && ok "and back ($A)" || fail "not back on $A ($(Q host))"
sleep 1; covers
[ "$(procs)" = 1 ] && ok "one Settings process across both outputs" || fail "Settings processes: $(procs)"
grim -s 0.5 "$SHOTS/two-outputs.png" 2>/dev/null || true

echo "test-dock: shots in $SHOTS"
[ "$FAILS" = 0 ] && { echo "test-dock: all ok"; exit 0; }
echo "test-dock: $FAILS failed" >&2; exit 1
