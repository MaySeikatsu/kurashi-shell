#!/usr/bin/env bash
# The lead platform for visual checks (session 17): niri nested (winit) inside the invisible headless sway sandbox. The
# shell runs on that niri — niri's own blur (ext-background-effect), layer stacking and animations — and nothing reaches
# the user's display, socket or bus. sway only hosts the niri window; grim and the pointer go through sway.
#
#   niri-sandbox.sh start <config.toml> [wallpaper.png]   start sway + niri + kurashid + the frontend
#   niri-sandbox.sh config <config.toml>                  replace the shell's config (the daemon reloads it)
#   niri-sandbox.sh shot <name> [x,y wxh] [scale]         screenshot (whole screen at 0.5, or a region at `scale`)
#   niri-sandbox.sh burst <name> <x,y wxh> <scale> <n> <gap> -- <cmd…>   n shots `gap` s apart while cmd runs, side by side
#   niri-sandbox.sh act <kurashi args…>                   the CLI against the sandbox's daemon (`act act island.expand`)
#   niri-sandbox.sh niri <msg args…>                      `niri msg` against the nested niri
#   niri-sandbox.sh spawn <cmd…>                          start a client on the nested niri (a terminal, swaybg …)
#   niri-sandbox.sh move|click <x> <y>                    the pointer (screen px of the 1920×1080 output)
#   niri-sandbox.sh log [n] | nlog [n]                    the frontend's warnings / niri's log
#   niri-sandbox.sh stop                                  kill only this sandbox's processes
#
# Run inside `nix develop` (sway, niri, qs, grim, imagemagick). Binaries from $KURASHI_BIN_DIR, else
# $CARGO_TARGET_DIR/debug, else target/debug. Shots and env files go to $KURASHI_NIRI_SB_OUT (/tmp/kurashi-niri-sb-out).
# Blur shows only over something: pass a patterned wallpaper (swaybg from nixpkgs is spawned with it).
# Known: the idle lock and a locked previous run are cleared on
# start (`idle.enabled = false` in the config keeps it from locking mid-test, I241).
set -uo pipefail
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
OUT=${KURASHI_NIRI_SB_OUT:-/tmp/kurashi-niri-sb-out}
NAME=${KURASHI_NIRI_SB_NAME:-niri}
BIN=${KURASHI_BIN_DIR:-${CARGO_TARGET_DIR:-$ROOT/target}/debug}
mkdir -p "$OUT/shots"
SWAYENV=$OUT/sway-env.sh
NIRIENV=$OUT/niri-env.sh
case "${1:-}" in
start)
  eval "$("$ROOT/tools/bench/sandbox.sh" start "$NAME")"
  "$ROOT/tools/bench/sandbox.sh" env "$NAME" > "$SWAYENV"
  R=$XDG_RUNTIME_DIR
  # (sandbox.sh may return before sway answers on its IPC socket)
  for _ in $(seq 50); do swaymsg -t get_version >/dev/null 2>&1 && break; sleep 0.2; done
  swaymsg output HEADLESS-1 resolution 1920x1080 >/dev/null
  swaymsg 'default_border none' >/dev/null
  cat > "$R/niri.kdl" <<'KDL'
blur {
  on
  passes 3
  offset 3
  noise 0.02
  saturation 1.5
}
prefer-no-csd
hotkey-overlay { skip-at-startup; }
layout { gaps 0; background-color "#5f8f6a"; }
cursor { xcursor-size 24; }
KDL
  rm -rf "$R/xdg/state" "$R/locked"
  mkdir -p "$R/xdg/config/kurashi" "$R/xdg/state" "$R/xdg/data" "$R/xdg/cache"
  setsid niri -c "$R/niri.kdl" > "$R/niri.log" 2>&1 < /dev/null &
  for _ in $(seq 50); do ls "$R"/niri.*.sock >/dev/null 2>&1 && break; sleep 0.2; done
  NS=$(ls "$R"/niri.*.sock 2>/dev/null | head -1)
  [ -n "$NS" ] || { echo "niri-sandbox: niri did not start (see $R/niri.log)" >&2; exit 1; }
  WD=$(basename "$NS" | sed -E 's/^niri\.(wayland-[0-9]+)\..*/\1/')
  {
    echo "export XDG_RUNTIME_DIR=$R NIRI_SOCKET=$NS WAYLAND_DISPLAY=$WD"
    echo "export XDG_CONFIG_HOME=$R/xdg/config XDG_STATE_HOME=$R/xdg/state XDG_DATA_HOME=$R/xdg/data XDG_CACHE_HOME=$R/xdg/cache"
    echo "export KURASHI_DATA_DIR=$ROOT LC_ALL=C.UTF-8 KURASHI_SOCKET=$R/kurashi.sock"
    grep -E "DBUS_SESSION|POLKIT|NETNS|LD_PRELOAD" "$SWAYENV" || true
    echo "unset SWAYSOCK"
  } > "$NIRIENV"
  sleep 1
  swaymsg '[app_id="niri"] fullscreen enable' >/dev/null 2>&1 || true
  . "$NIRIENV"
  cp "$2" "$XDG_CONFIG_HOME/kurashi/config.toml"
  env DBUS_SYSTEM_BUS_ADDRESS="unix:path=$R/no-system-bus" PULSE_SERVER="unix:$R/no-pulse/native" \
    PULSE_RUNTIME_PATH="$R/no-pulse" setsid "$BIN/kurashid" >> "$R/kurashid.log" 2>&1 < /dev/null &
  sleep 2
  setsid qs -p "$ROOT/frontend" >> "$R/qs.log" 2>&1 < /dev/null &
  if [ -n "${3:-}" ]; then
    SB=$(nix build nixpkgs#swaybg --no-link --print-out-paths 2>/dev/null | head -1)
    setsid "$SB/bin/swaybg" -i "$3" -m fill > /dev/null 2>&1 < /dev/null &
  fi
  sleep 6
  echo "started (niri on $WAYLAND_DISPLAY; logs in $R)" ;;
config) . "$NIRIENV"; cp "$2" "$XDG_CONFIG_HOME/kurashi/config.toml"; sleep 2 ;;
shot) . "$SWAYENV"
  if [ -n "${3:-}" ]; then timeout 10 grim -s "${4:-2}" -g "$3" "$OUT/shots/$2.png"
  else timeout 10 grim -s 0.5 "$OUT/shots/$2.png"; fi
  echo "$OUT/shots/$2.png" ;;
burst) . "$SWAYENV"; n=$2; g=$3; sc=$4; cnt=$5; gap=$6; shift 7; ( "$@" ) &
  for i in $(seq -w 1 "$cnt"); do sleep "$gap"; timeout 5 grim -s "$sc" -g "$g" "$OUT/shots/$n-$i.png"; done; wait
  magick "$OUT"/shots/"$n"-*.png -background red -splice 3x0 +append "$OUT/shots/$n.png"; rm "$OUT"/shots/"$n"-*.png
  echo "$OUT/shots/$n.png" ;;
act) . "$NIRIENV"; shift; timeout 10 "$BIN/kurashi" "$@" ;;
niri) . "$NIRIENV"; shift; timeout 10 niri msg "$@" ;;
spawn) . "$NIRIENV"; shift; setsid "$@" > /dev/null 2>&1 < /dev/null & ;;
move) . "$SWAYENV"; python3 -I "$ROOT/tools/bench/wl_pointer.py" move "$2" "$3" ;;
click) . "$SWAYENV"; python3 -I "$ROOT/tools/bench/wl_pointer.py" click "$2" "$3" left ;;
log) . "$NIRIENV"; grep -E 'WARN|ERROR|TypeError|ReferenceError|Unable' "$XDG_RUNTIME_DIR/qs.log" | sort | uniq -c | sort -rn | head -"${2:-20}" ;;
nlog) . "$NIRIENV"; tail -"${2:-20}" "$XDG_RUNTIME_DIR/niri.log" ;;
stop) "$ROOT/tools/bench/sandbox.sh" stop "$NAME" ;;
*) sed -n '2,22p' "$0"; exit 2 ;;
esac
