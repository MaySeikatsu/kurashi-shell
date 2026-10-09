#!/usr/bin/env bash
# The wallpaper picker in the REAL shell (frontend/shell.qml, Stage card) against the REAL kurashid, invisibly
# (headless sway sandbox). Replaces the old harness host: a mod component imports `qs.core`, which only the shell's
# own root resolves. Steps: a library of real pictures (a subfolder, a light/dark pair, a monochrome picture, a broken
# file); a FAKE awww / awww-daemon first on PATH, logging its argv (the real backend is never run); `mod.enable
# wallpaper`; `mod.panel.open` shows the picker in the Stage card; screenshots of each state and the keyboard run
# (tools/bench/wl_keys.py). Screenshots: mods/wallpaper/shots/real-<state>.png. Shift and Ctrl variants of the keys
# are not drivable by wl_keys.py (no modifiers); they are covered by reading the code, and reported as such.
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
press() {  # one key per argument, with a short pause so each lands before the next
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

open_picker() {
  K act mod.enable '{"id": "wallpaper"}' >/dev/null
  K act mod.panel.open '{"id": "wallpaper", "panel": "wallpaper"}' >/dev/null
}

close_picker() { K act ui.close >/dev/null 2>&1 || true; sleep 0.5; }
# A click on the card's title: the card is top-centre under the bar (physical px on the 2560 x 1440 sandbox output).
focus_card() { timeout 30 python3 -I "$ROOT/tools/bench/wl_pointer.py" click 1130 64 left || true; sleep 0.5; }
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
# The picker's normal state, then the keyboard run: the grid, the preview with its theme, the theme switch, a look,
# the shuffle, the apply, and the folder row (Up from the first row, Left/Right, Return, Backspace).
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

scenario grid "$R/pics" awww
start_keys
press down right
shot preview
press t
shot theme-off
press t
press f
WAIT=2 shot kept-look
press r
WAIT=2 shot shuffled
press down down
WAIT=2 shot grid-moved

# Return applies the selected picture with the theme, from its tile (the origin is the tile's centre).
press return
sleep 2
echo "the backend was asked (the fake logs its argv):"
grep "awww img" "$WP_LOG" | tail -n 1 || echo "NO awww img line"
echo "the state file (the theme follows the picture, the look is kept):"
grep -o '"theme_image": *"[^"]*"' "$R/xdg/state/kurashi/wallpaper.json" 2>/dev/null || echo "no theme_image in state"
sed -n '/"favourites"/,/]/p' "$R/xdg/state/kurashi/wallpaper.json" 2>/dev/null || echo "no favourites in state"

# The folder row: from the first grid row, Up goes to the chips; Right moves to the library's folder, Return opens it;
# Up again lands on its crumb, Right reaches its subfolder, Return opens that; Backspace goes back up.
press left left left left left left left left left left up
press right
press return
press up right
WAIT=2 shot folder-root
press up right return
WAIT=2 shot folder-sub
press backspace
WAIT=2 shot after-backspace
# Search through the keyboard: from the folder row, Right to the looks chip, Tab to the search field, then type.
press up right right right tab s u n
WAIT=2 shot search
press return
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
