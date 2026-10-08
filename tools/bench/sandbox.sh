#!/usr/bin/env bash
# Headless sway sandbox for invisible frontend tests (never touches the user's session).
#   sandbox.sh start [name] [renderer]  → prints `export ...` lines (eval them)
#   sandbox.sh env   [name]             → prints the export lines again
#   sandbox.sh stop  [name]             → kills ONLY processes whose environ has this runtime dir
#   sandbox.sh output-add [name]        → hotplug a second output (HEADLESS-2)
# Renderer: gles2 (default; needed for dmabuf → clients render on the GPU, and for screencopy)
#           or pixman (software).
set -euo pipefail
action=${1:-start}; name=${2:-dev}; renderer=${3:-gles2}
R=/tmp/kurashi-sb-$name
SWAY=${KURASHI_SWAY:-$(command -v sway)}

env_lines() {
  local wl; wl=$(ls "$R" 2>/dev/null | grep -m1 -E '^wayland-[0-9]+$' || true)
  echo "export XDG_RUNTIME_DIR=$R"
  echo "export WAYLAND_DISPLAY=${wl:-wayland-1}"
  echo "export SWAYSOCK=$(ls "$R"/sway-ipc.*.sock 2>/dev/null | head -1)"
  [ -f "$R/dbus.addr" ] && echo "export DBUS_SESSION_BUS_ADDRESS=$(cat "$R/dbus.addr")"
  echo "export KURASHI_SOCKET=$R/kurashi/ipc.sock"
  echo "unset DISPLAY NIRI_SOCKET HYPRLAND_INSTANCE_SIGNATURE"
}

case $action in
  start)
    mkdir -p "$R" && chmod 700 "$R"
    printf 'output HEADLESS-1 resolution 2560x1440\noutput * bg #101014 solid_color\n' > "$R/sway.conf"
    renderer_env=(WLR_RENDERER="$renderer")
    [ "$renderer" = gles2 ] && renderer_env+=(WLR_RENDER_DRM_DEVICE=/dev/dri/renderD128)
    env -i HOME="$HOME" PATH="$PATH" XDG_RUNTIME_DIR="$R" WLR_BACKENDS=headless \
      WLR_LIBINPUT_NO_DEVICES=1 "${renderer_env[@]}" "$SWAY" -c "$R/sway.conf" > "$R/sway.log" 2>&1 &
    echo $! > "$R/sway.pid"
    dbus-daemon --session --fork --print-address=1 --print-pid=1 \
      --address="unix:path=$R/bus" > "$R/dbus.out" 2>/dev/null || true
    head -1 "$R/dbus.out" > "$R/dbus.addr" 2>/dev/null || true
    for _ in $(seq 50); do ls "$R" | grep -qE '^wayland-[0-9]+$' && break; sleep 0.1; done
    env_lines
    ;;
  env) env_lines ;;
  output-add)
    SWAYSOCK=$(ls "$R"/sway-ipc.*.sock | head -1) swaymsg create_output >/dev/null
    SWAYSOCK=$(ls "$R"/sway-ipc.*.sock | head -1) swaymsg output HEADLESS-2 resolution 2560x1440 >/dev/null || true
    ;;
  stop)
    pids=()
    for p in $(pgrep -u "$(id -u)" . || true); do
      if tr '\0' '\n' < "/proc/$p/environ" 2>/dev/null | grep -qx "XDG_RUNTIME_DIR=$R"; then pids+=("$p"); fi
    done
    [ -f "$R/dbus.out" ] && pids+=("$(sed -n 2p "$R/dbus.out")")
    [ ${#pids[@]} -gt 0 ] && kill "${pids[@]}" 2>/dev/null || true
    echo "stopped ${#pids[@]} process(es) in $R"
    ;;
  *) echo "usage: $0 start|env|stop|output-add [name] [gles2|pixman]" >&2; exit 2 ;;
esac
