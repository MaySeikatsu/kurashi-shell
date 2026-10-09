#!/usr/bin/env bash
# The wallpaper picker and quick tile against the REAL kurashid, invisibly (headless sway sandbox).
#   nix develop -c mods/wallpaper/test/picker.sh [sandbox-name]
# The daemon runs with isolated XDG dirs, the sandbox's bus, and a FAKE awww / awww-daemon first on its
# PATH that logs its argv and answers like awww's query (two outputs). The real awww is never run.
# Until W11-mod-qml loads mod components in the shell, test/harness/shell.qml hosts Panel.qml or the tile
# in a window (WP_COMPONENT). Screenshots: mods/wallpaper/shots/<scenario>.png.
# Binaries: $KURASHI_BIN_DIR (default: $CARGO_TARGET_DIR/debug or target/debug) must hold kurashid and
# kurashi; they are copied first, since shared target dirs get overwritten.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
NAME=${1:-wp-picker}
BIN=${KURASHI_BIN_DIR:-${CARGO_TARGET_DIR:-$ROOT/target}/debug}
OUT=$ROOT/mods/wallpaper/shots
HARNESS=$ROOT/mods/wallpaper/test/harness
PIXMAPS=/run/current-system/sw/share/pixmaps
mkdir -p "$OUT"
export KURASHI_RENDER_NODE=${KURASHI_RENDER_NODE:-/dev/dri/renderD129}

eval "$("$ROOT/tools/bench/sandbox.sh" start "$NAME")"
R=$XDG_RUNTIME_DIR
W=$R/work
rm -rf "$R/pics" "$R/empty" "$R/fakebin" "$R/harness" "$R/wpstate" "$R/xdg"
: > "$R/qs.log"; : > "$R/kurashid.log"
mkdir -p "$W" "$R/kurashi" "$R/fakebin" "$R/pics/sub" "$R/empty" "$R/xdg/config" "$R/xdg/state" "$R/xdg/data" "$R/xdg/cache"
cp "$BIN/kurashid" "$BIN/kurashi" "$W/"

DPID=""
HPID=""
cleanup() {
  [ -n "$HPID" ] && kill "$HPID" 2>/dev/null || true
  [ -n "$DPID" ] && kill "$DPID" 2>/dev/null || true
  "$ROOT/tools/bench/sandbox.sh" stop "$NAME" >/dev/null || true
}
trap cleanup EXIT

export XDG_CONFIG_HOME=$R/xdg/config XDG_STATE_HOME=$R/xdg/state \
       XDG_DATA_HOME=$R/xdg/data XDG_CACHE_HOME=$R/xdg/cache KURASHI_DATA_DIR=$ROOT
export WP_LOG=$R/awww.log WP_STATE=$R/wpstate
mkdir -p "$WP_STATE"
K() { "$W/kurashi" "$@"; }

# ---- the library: real pictures (pixmaps are small, but decode), one broken file, a subfolder ----
i=0
for f in steam flycast proton-mail proton-pass legion_logo legion_logo_dark legion_logo_light steam_tray_mono; do
  i=$((i + 1))
  install -m 644 "$PIXMAPS/$f.png" "$R/pics/$(printf '%02d' "$i")-$f.png"
done
install -m 644 "$PIXMAPS/steam.png" "$R/pics/sub/inner-steam.png"
echo "this is not a picture" > "$R/pics/zz-broken.png"

# ---- the fake backend: awww and awww-daemon, logging their argv -------------------------------
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

# ---- helpers -----------------------------------------------------------------------------------
write_config() {  # folders backend
  mkdir -p "$XDG_CONFIG_HOME/kurashi"
  cat > "$XDG_CONFIG_HOME/kurashi/config.toml" <<EOF2
[mods]
loaded = ["wallpaper"]
enabled = ["wallpaper"]

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

start_harness() {  # component file
  mkdir -p "$R/harness"
  sed "s|@ROOT@|$ROOT|g" "$HARNESS/shell.qml" > "$R/harness/shell.qml"
  WP_COMPONENT=$1 qs -p "$R/harness" >> "$R/qs.log" 2>&1 &
  HPID=$!
}

stop_harness() {
  kill "$HPID" 2>/dev/null || true
  wait "$HPID" 2>/dev/null || true
  HPID=""
}

shot() {  # name: give the picker time to page its thumbnails, then grab the output
  sleep "${WAIT:-4}"
  grim -o HEADLESS-1 "$OUT/$1.png"
  [ -s "$OUT/$1.png" ] || { echo "empty screenshot $1" >&2; exit 1; }
  echo "shot $1"
}

doc() {  # the wallpaper document as the daemon serves it now (first snapshot)
  timeout 3 "$W/kurashi" sub mod.wallpaper 2>/dev/null | head -n 1 | cut -c1-600 || true
  echo
}

scenario() {  # name folders backend component-file [WP_NODAEMON]
  local name=$1 folders=$2 backend=$3 component=$4
  echo "== $name"
  stop_harness
  [ -n "$DPID" ] && stop_daemon
  write_config "$folders" "$backend"
  rm -rf "$WP_STATE" && mkdir -p "$WP_STATE" && : > "$WP_LOG"
  if [ "$name" = picker-backend-down ]; then WP_NODAEMON=1 start_daemon; else start_daemon; fi
  start_harness "$component"
  # A daemon that never answers is only reported down after the start polls (about 5 s).
  if [ "$name" = picker-backend-down ]; then WAIT=8 shot "$name"; else shot "$name"; fi
  pss "$name"
  doc
}

# The proportional set size of the harness process(es): what the component costs while it is open.
pss() {
  local total
  total=$(pgrep -f "$R/harness" | while read -r p; do awk '/^Pss:/ {print $2}' "/proc/$p/smaps_rollup" 2>/dev/null; done \
    | awk '{s += $1} END {printf "%.1f", s / 1024}')
  echo "pss $1: ${total:-?} MiB"
}

PANEL=$ROOT/mods/wallpaper/qml/Panel.qml
TILE=$ROOT/mods/wallpaper/qml/slots/quick.tiles.qml

# ---- the scenarios ----------------------------------------------------------------------------
# The same host with an empty component: the baseline the picker's memory is measured against.
printf 'import QtQuick\n\nItem {\n    implicitWidth: 1\n    implicitHeight: 1\n}\n' > "$R/empty.qml"
scenario baseline-empty "$R/pics" awww "$R/empty.qml"
scenario picker-grid "$R/pics" awww "$PANEL"
K act wallpaper.set "{\"path\": \"$R/pics/02-flycast.png\", \"output\": \"HEADLESS-1\"}" >/dev/null
echo "the backend was asked (the fake logs its argv):"
grep "awww img" "$WP_LOG" | tail -n 1
WAIT=2 shot picker-applied
scenario tile "$R/pics" awww "$TILE"
scenario picker-empty "$R/empty" awww "$PANEL"
scenario picker-onboarding "" awww "$PANEL"
scenario picker-folder-missing "$R/nope" awww "$PANEL"
scenario picker-backend-missing "$R/pics" swww "$PANEL"
scenario picker-backend-down "$R/pics" awww "$PANEL"
stop_harness
echo "done: $OUT"
