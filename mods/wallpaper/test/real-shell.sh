#!/usr/bin/env bash
# The wallpaper picker in the REAL shell (frontend/shell.qml, Stage card) against the REAL kurashid, invisibly
# (headless sway sandbox). Replaces the old harness host: a mod component imports `qs.core`, which only the shell's
# own root resolves. Steps: a library of real pictures (a subfolder, a light/dark pair, a monochrome picture, a broken
# file); a FAKE awww / awww-daemon first on PATH, logging its argv (the real backend is never run); `mod.enable
# wallpaper`; `mod.panel.open` shows the picker in the Stage card; screenshots of each state and the keyboard run
# (tools/bench/wl_keys.py, with its modifiers: Shift+Return, Ctrl+Return). Each keyboard path is also a
# check (ok / FAIL on the fake backend's log and the state file); a FAIL makes the run exit 1.
# Screenshots: mods/wallpaper/shots/real-<state>.png.
#   KURASHI_RENDER_NODE=/dev/dri/renderD129 KURASHI_BIN_DIR=<dir with kurashid, kurashi>  \
#     nix develop -c mods/wallpaper/test/real-shell.sh [sandbox-name]
# Binaries are copied first (shared target dirs are overwritten by other builds).
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
NAME=${1:-${KURASHI_SB_PREFIX:-}wp-real}
BIN=${KURASHI_BIN_DIR:-${CARGO_TARGET_DIR:-$ROOT/target}/debug}
OUT=$ROOT/mods/wallpaper/shots
PIXMAPS=/run/current-system/sw/share/pixmaps
mkdir -p "$OUT"
# Machine B's iGPU when it exists; elsewhere sandbox.sh picks the display GPU (boot_vga).
[ -e /dev/dri/renderD129 ] && export KURASHI_RENDER_NODE=${KURASHI_RENDER_NODE:-/dev/dri/renderD129}

eval "$("$ROOT/tools/bench/sandbox.sh" start "$NAME")"
R=$XDG_RUNTIME_DIR
W=$R/work
rm -rf "$R/pics" "$R/empty" "$R/fakebin" "$R/wpstate" "$R/xdg" "$R/nope"
: > "$R/qs.log"; : > "$R/kurashid.log"
mkdir -p "$W" "$R/kurashi" "$R/fakebin" "$R/pics/sub" "$R/empty" "$R/xdg/config" "$R/xdg/state" "$R/xdg/data" "$R/xdg/cache"
cp "$BIN/kurashid" "$BIN/kurashi" "$W/"

DPID=""
SHPID=""
KEYPID=""
cleanup() {
  exec 3>&- 2>/dev/null || true
  [ -n "$KEYPID" ] && kill "$KEYPID" 2>/dev/null || true
  [ -n "$SHPID" ] && kill "$SHPID" 2>/dev/null || true
  [ -n "$DPID" ] && kill "$DPID" 2>/dev/null || true
  "$ROOT/tools/bench/sandbox.sh" stop "$NAME" >/dev/null || true
}
trap cleanup EXIT

export XDG_CONFIG_HOME=$R/xdg/config XDG_STATE_HOME=$R/xdg/state \
       XDG_DATA_HOME=$R/xdg/data XDG_CACHE_HOME=$R/xdg/cache KURASHI_DATA_DIR=$ROOT
export WP_LOG=$R/awww.log WP_STATE=$R/wpstate
mkdir -p "$WP_STATE"
K() { "$W/kurashi" "$@"; }

# ---- the library: real pictures, one monochrome, a light/dark pair, a subfolder, one broken file ----
python3 "$ROOT/mods/wallpaper/test/make-pictures.py" "$R/pics"

# ---- the fake backend: awww and awww-daemon, logging their argv (the kit's: tools/testkit/fakebin) ----
cp "$ROOT/tools/testkit/fakebin/awww" "$ROOT/tools/testkit/fakebin/awww-daemon" "$R/fakebin/"

# ---- helpers ------------------------------------------------------------------------------------------
write_config() {  # folders backend
  mkdir -p "$XDG_CONFIG_HOME/kurashi"
  cat > "$XDG_CONFIG_HOME/kurashi/config.toml" <<EOF2
[mods]
loaded = ["wallpaper"]

[mods.wallpaper]
folders = "$1"
backend = "$2"
EOF2
}

start_daemon() {  # WP_NODAEMON (optional) is passed through
  rm -f "$KURASHI_SOCKET" "$WP_STATE/daemon"
  env PATH="$R/fakebin:$PATH" DBUS_SYSTEM_BUS_ADDRESS="unix:path=$R/no-system-bus" \
    "$W/kurashid" >> "$R/kurashid.log" 2>&1 &
  DPID=$!
  for _ in $(seq 100); do [ -S "$KURASHI_SOCKET" ] && K ping >/dev/null 2>&1 && return 0; sleep 0.1; done
  echo "kurashid did not come up (see $R/kurashid.log)" >&2
  exit 1
}

stop_daemon() {
  kill "$DPID" 2>/dev/null || true
  wait "$DPID" 2>/dev/null || true
  DPID=""
}

# The real shell, as a session starts it: no KURASHI_SOCKET, the protocol default.
start_shell() {
  env -u KURASHI_SOCKET qs -p "$ROOT/frontend" >> "$R/qs.log" 2>&1 &
  SHPID=$!
  sleep "${SHELL_WAIT:-4}"
}

stop_shell() {
  kill "$SHPID" 2>/dev/null || true
  wait "$SHPID" 2>/dev/null || true
  SHPID=""
}

# Keys go through one virtual keyboard for the whole run: a FIFO feeds wl_keys.py --serve.
start_keys() {
  rm -f "$R/keys.fifo"
  mkfifo "$R/keys.fifo"
  python3 "$ROOT/tools/bench/wl_keys.py" --serve < "$R/keys.fifo" >> "$R/keys.log" 2>&1 &
  KEYPID=$!
  exec 3> "$R/keys.fifo"
}
press() {  # one key per argument (chords as shift+return), with a short pause so each lands before the next
  local k
  for k in "$@"; do
    printf '%s\n' "$k" >&3
    sleep 0.35
  done
}

shot() {  # name: give the picker time to page its thumbnails, then grab the output
  sleep "${WAIT:-3}"
  grim -o HEADLESS-1 "$OUT/real-$1.png"
  [ -s "$OUT/real-$1.png" ] || { echo "empty screenshot $1" >&2; exit 1; }
  echo "shot real-$1"
}

# The checks: each prints ok or FAIL; a FAIL makes the run exit 1 (the acceptance is a green run).
FAILS=0
expect() {  # description command...: the check passes when the command succeeds within 20 s (it waits for the condition)
  local what=$1 i; shift
  for i in $(seq 40); do "$@" && { echo "ok: $what"; return 0; }; sleep 0.5; done
  echo "FAIL: $what (outputs and theme picture: $(wp_state))"
  FAILS=$((FAILS + 1))
}
# What is in effect, from the mod's document (W99: the backend is shown the picture filter's baked copy — K59, K88 —, so
# its argv does not name the picture; the document does): `<output>=<file> … theme=<file>`.
wp_state() {
  timeout 10 "$W/kurashi" sub mod.wallpaper --count 0 2>/dev/null | head -1 | python3 -c '
import json, sys, os
j = json.load(sys.stdin); d = j.get("data", j)
outs = d.get("outputs") or {}
names = [n + "=" + os.path.basename(o.get("path", "")) for n, o in sorted(outs.items())]
print(" ".join(names + ["theme=" + os.path.basename((d.get("theme") or {}).get("image", ""))]))' 2>/dev/null
}
# Every output shows this picture (or the one output named).
shows() { local s; s=$(wp_state); [ -n "$s" ] && ! echo "$s" | tr ' ' '\n' | grep -v '^theme=' | grep -vq "=$1\$"; }
output_shows() { wp_state | tr ' ' '\n' | grep -qx "$1=$2"; }
# The theme follows this picture (the document's theme.image).
theme_is() { wp_state | tr ' ' '\n' | grep -qx "theme=$1"; }
# A config value in effect (I135: the picker writes the theme's palette; it once sent an intent nothing handled).
cfg_is() {
  [ "$(timeout 10 "$W/kurashi" sub config --count 0 2>/dev/null | head -1 \
    | python3 -c "import json,sys; v=json.load(sys.stdin)['data']['values'].get('$1'); print(v['value'] if v else '')" 2>/dev/null)" = "$2" ]
}

open_picker() {
  K act mod.enable '{"id": "wallpaper"}' >/dev/null
  K act mod.panel.open '{"id": "wallpaper", "panel": "wallpaper"}' >/dev/null
}

close_picker() { K act ui.close >/dev/null 2>&1 || true; sleep 0.5; }
# A click on the card's title: the card is top-centre under the bar (physical px on the 2560 x 1440 sandbox output).
focus_card() { timeout 30 python3 -I "$ROOT/tools/bench/wl_pointer.py" click 1130 64 left || true; sleep 0.5; }
click_at() { timeout 30 python3 -I "$ROOT/tools/bench/wl_pointer.py" click "$1" "$2" left || true; }
stop_keys() {
  exec 3>&- 2>/dev/null || true
  [ -n "$KEYPID" ] && kill "$KEYPID" 2>/dev/null || true
  [ -n "$KEYPID" ] && wait "$KEYPID" 2>/dev/null || true
  KEYPID=""
}

# The proportional set size of the shell process: what the picker costs while it is open.
pss() {  # name: three samples a second apart (the shell's PSS moves with the thumbnails), MiB
  local i total samples=""
  for i in 1 2 3; do
    total=$(pgrep -f "$ROOT/frontend" 2>/dev/null | while read -r p; do awk '/^Pss:/ {print $2}' "/proc/$p/smaps_rollup" 2>/dev/null; done \
      | awk '{s += $1} END {printf "%.1f", s / 1024}') || true
    samples="$samples ${total:-?}"
    sleep 1
  done
  echo "pss $1:$samples MiB"
}

# A scenario: fresh daemon and shell with the given folders and backend, the picker opened, then `body`.
scenario() {  # name folders backend [WP_NODAEMON]
  local name=$1 folders=$2 backend=$3
  echo "== $name"
  stop_shell
  [ -n "$DPID" ] && stop_daemon
  write_config "$folders" "$backend"
  rm -rf "$WP_STATE" && mkdir -p "$WP_STATE" && : > "$WP_LOG"
  if [ "$name" = backend-down ]; then WP_NODAEMON=1 start_daemon; else start_daemon; fi
  start_shell
  open_picker
  # The Stage's surface takes keys on demand: a click on its title (no control) gives it the keyboard, as in test-stage.sh.
  sleep 1
  focus_card
  if [ "$name" = backend-down ]; then WAIT=8 shot "$name"; else shot "$name"; fi
}

# ---- scenarios ---------------------------------------------------------------------------------------
# Memory: a fresh shell with the picker closed, then the picker open on the same library (the difference is the
# picker's own cost while it is open; the shell's PSS is sampled three times each).
write_config "$R/pics" awww
rm -rf "$WP_STATE" && mkdir -p "$WP_STATE" && : > "$WP_LOG"
start_daemon
start_shell
sleep 2
pss "memory shell, picker closed"
open_picker
sleep 6
pss "memory shell, picker open"
close_picker
stop_shell
stop_daemon

# The keyboard run, in the order the picker's focus moves. Every control is reached by keys (W99: the card is large and
# its columns follow its width, so a picture is found by searching for it, not by its place in the grid); the one click
# is the header's overflow at the card's top-right corner (physical px on the 2560 x 1440 output: the large card is 60 %
# of its width, centred).
scenario grid "$R/pics" awww
start_keys
find_picture() {  # name: `/` from the grid (the field's text is selected: typing replaces it), the name, Down to the grid
  local c
  press slash
  for c in $(echo "$1" | grep -o .); do press "$c"; done
  sleep 1
  press down
}
find_picture light                      # 06-wall-light
shot preview
press t
shot theme-off
press t
press f                                 # keep it as a look
WAIT=2 shot kept-look
# Apply look (the actions' last button): Tab from the grid reaches the actions (the theme switch first, I32), then Dark,
# Light, Apply, Wallpaper only, ★, Apply look; Space presses it.
press tab tab tab tab tab tab tab space
expect "Apply look puts its picture in effect" shows 06-wall-light.png
expect "Apply look makes the theme follow its picture" theme_is 06-wall-light.png
expect "... and the theme's palette is the picture's (I135)" cfg_is theme.colors.palette wallpaper
press shift+tab shift+tab shift+tab shift+tab shift+tab shift+tab shift+tab   # back to the grid
find_picture dark                       # 05-wall-dark
# Tab from the grid goes to the preview's actions (the theme switch first), not out of the picker (I32).
press tab                               # the theme switch takes the focus
press space                             # Space presses it: the switch reads Theme: off in the shot
WAIT=1 shot tab-from-grid
press space                             # on again
press shift+tab                         # the grid again; 05 stays selected
# Ctrl+Return: the picture alone; the theme keeps the picture it had.
press ctrl+return
expect "Ctrl+Return sets the picture" shows 05-wall-dark.png
expect "Ctrl+Return keeps the theme's picture" theme_is 06-wall-light.png
# Return: the picture with its theme.
press return
expect "Return sets the picture and its theme" theme_is 05-wall-dark.png
# One output chosen (another picture, 01-teal): Up from the grid's first row reaches the folder row, Shift+Tab the
# targets (their last output), Left the first output; Return chooses it, Down goes back to the grid. Return sets that
# output alone; Shift+Return every output.
find_picture teal
press up shift+tab left return down
WAIT=1 shot target-one
press return
expect "Return with one output chosen sets that output" output_shows HEADLESS-1 01-teal.png
expect "... and only that output" output_shows HEADLESS-2 05-wall-dark.png
press shift+return
expect "Shift+Return sets every output" shows 01-teal.png
press up shift+tab left left return down   # All outputs again
press r                                 # shuffle
WAIT=2 shot shuffled
press down
WAIT=2 shot grid-moved
press up                                # back to the first row
# `/` from the grid focuses the search field; typing filters the library (07-sunset, in the sub folder); Escape clears it.
press slash s u n
WAIT=2 shot search
press escape
sleep 1
# The folders, from the keyboard: from the first grid row Up goes to the folder's chip, Return browses it; Down to the
# grid, Up again reaches the breadcrumb row (the folder under it: sub), Return opens it.
press up return
WAIT=2 shot folder-root
press down up return
WAIT=2 shot folder-sub
press backspace                         # Backspace goes back up to the library's folder
WAIT=2 shot after-backspace
# The overflow in the header: the thumbnail cache, what a clear frees, the Settings page. Escape closes it.
click_at 2017 66
WAIT=2 shot cache-menu
press escape
WAIT=1 shot menu-closed
stop_keys
close_picker
# The quick-settings tile the mod contributes (slot quick.tiles), with the picker closed.
K act quick.toggle >/dev/null 2>&1 || true
WAIT=2 shot quick-tile
K act ui.close >/dev/null 2>&1 || true

# The states the brief lists: an empty folder, no folder yet, a missing folder, a backend that is not installed,
# and a backend whose daemon does not answer (the picker says so and offers the restart). `scenario` shoots each.
scenario empty "$R/empty" awww
scenario onboarding "" awww
scenario folder-missing "$R/nope" awww
scenario backend-missing "$R/pics" swww
scenario backend-down "$R/pics" awww
stop_shell
[ -n "$DPID" ] && stop_daemon
echo "done: $OUT"
[ "$FAILS" -eq 0 ] || { echo "$FAILS check(s) failed"; exit 1; }
