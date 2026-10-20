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
NAME=${1:-wp-real}
BIN=${KURASHI_BIN_DIR:-${CARGO_TARGET_DIR:-$ROOT/target}/debug}
OUT=$ROOT/mods/wallpaper/shots
PIXMAPS=/run/current-system/sw/share/pixmaps
mkdir -p "$OUT"
export KURASHI_RENDER_NODE=${KURASHI_RENDER_NODE:-/dev/dri/renderD129}

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

# ---- the fake backend: awww and awww-daemon, logging their argv -------------------------------------
cat > "$R/fakebin/awww" <<'EOF'
#!/bin/sh
echo "awww $*" >> "$WP_LOG"
case "$1" in
  --version) echo "awww 0.12.1" ;;
  query)
    if [ -f "$WP_STATE/daemon" ]; then
      printf '%s\n' '{"": [{"name": "HEADLESS-1", "width": 2560, "height": 1440, "scale": 1, "displaying": {"color": "000000"}}, {"name": "HEADLESS-2", "width": 2560, "height": 1440, "scale": 1, "displaying": {"color": "000000"}}]}'
    else
      echo "Failed to connect to the awww-daemon socket" >&2
      exit 1
    fi ;;
  img) exit 0 ;;
  kill) rm -f "$WP_STATE/daemon" ;;
esac
exit 0
EOF
cat > "$R/fakebin/awww-daemon" <<'EOF'
#!/bin/sh
echo "awww-daemon $*" >> "$WP_LOG"
[ -n "${WP_NODAEMON:-}" ] || touch "$WP_STATE/daemon"
EOF
chmod +x "$R/fakebin/awww" "$R/fakebin/awww-daemon"

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
expect() {  # description command...: the check passes when the command succeeds
  local what=$1; shift
  if "$@"; then echo "ok: $what"; else echo "FAIL: $what"; FAILS=$((FAILS + 1)); fi
}
# What the backend was last asked for: the fake logs `awww img <path> [--outputs <name>] …` (no --outputs = every output).
backend_last() { grep "awww img" "$WP_LOG" | tail -n 1; }
backend_last_is() { backend_last | grep -q "/$1 "; }
backend_last_has() { backend_last | grep -q -- "--outputs $1"; }
backend_last_no_output() { backend_last | grep -q "awww img" && ! backend_last | grep -q -- "--outputs"; }
# The theme follows this picture: the state file's theme_image ends with it.
state_theme_is() { grep -q "\"theme_image\": *\"[^\"]*/$1\"" "$R/xdg/state/kurashi/wallpaper.json" 2>/dev/null; }

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

# The keyboard run, in the order the picker's focus moves. Coordinates are physical px on the 2560 x 1440 output:
# the HEADLESS-1 chip (1082, 131), All outputs (975, 131), the row-2 tile of the first column (1021, 396), Apply look
# (1466, 634), the header's overflow (1609, 65).
scenario grid "$R/pics" awww
start_keys
press down right                        # 06-wall-light
shot preview
press t
shot theme-off
press t
press f                                 # keep it as a look
WAIT=2 shot kept-look
# Apply look (the preview's row, its last button): the look's picture with its theme. Clicked: the grid keeps the focus.
click_at 1466 634
sleep 2
expect "Apply look puts its picture in effect" backend_last_is 06-wall-light.png
expect "Apply look makes the theme follow its picture" state_theme_is 06-wall-light.png
click_at 1021 396                       # 05-wall-dark: the grid takes the focus and the selection
# Tab from the grid goes to the preview's actions (the theme switch first), not out of the picker (I32).
press tab                               # the theme switch takes the focus
press space                             # Space presses it: the switch reads Theme: off in the shot
WAIT=1 shot tab-from-grid
press space                             # on again
click_at 1021 396                       # the grid again; 05 stays selected
# Ctrl+Return: the picture alone; the theme keeps the picture it had.
press ctrl+return
sleep 2
expect "Ctrl+Return sets the picture" backend_last_is 05-wall-dark.png
expect "Ctrl+Return keeps the theme's picture" state_theme_is 06-wall-light.png
# Return: the picture with its theme.
press return
sleep 2
expect "Return sets the picture and its theme" state_theme_is 05-wall-dark.png
# One output chosen: Return sets that output; Shift+Return sets every output (the call names no output).
click_at 1082 131                        # HEADLESS-1
click_at 1021 396                       # 05-wall-dark: the grid takes the focus and the selection
press return
sleep 2
expect "Return with one output chosen sets that output" backend_last_has HEADLESS-1
press shift+return
sleep 2
expect "Shift+Return sets every output" backend_last_no_output
click_at 975 131                         # All outputs again
click_at 1021 396                       # the grid again
press r                                 # shuffle
WAIT=2 shot shuffled
press down
WAIT=2 shot grid-moved
press up                                # back to the first row (the folder row is reached from it)
# `/` from the grid focuses the search field; typing filters the library (07-sunset, in the sub folder); Escape clears it.
# It runs before the folder row, while the library is unfiltered.
press slash s u n
WAIT=2 shot search
press escape
sleep 1
# The folder row, from the keyboard: from the first grid row Up goes to the chips; Right moves to the library's folder and
# Return opens it. The subfolder's chip is opened by a click (its place in the row is the chips' order, not a key walk).
press left left left left left left left left left left up
press right
press return
WAIT=2 shot folder-root
click_at 1056 161                       # sub 1
WAIT=2 shot folder-sub
press backspace                         # Backspace goes back up to the library's folder
WAIT=2 shot after-backspace
# The overflow in the header: the thumbnail cache and what a clear frees. Escape closes it.
click_at 1609 65
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
