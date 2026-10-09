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
SWAY=${KURASHI_SWAY:-$(command -v sway || true)}   # may be empty for stop/env outside nix develop

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
    # Fail closed: on any failure print env lines that point clients at a socket that does not
    # exist, so nothing ever falls back to the user's real session.
    fail() {
      echo "sandbox.sh: $*" >&2
      echo "export XDG_RUNTIME_DIR=$R WAYLAND_DISPLAY=kurashi-sandbox-FAILED KURASHI_SOCKET=$R/FAILED"
      echo "unset DISPLAY NIRI_SOCKET HYPRLAND_INSTANCE_SIGNATURE SWAYSOCK"
      echo "false"
      exit 1
    }
    [ -n "$SWAY" ] || fail "sway not on PATH (run inside 'nix develop')"
    command -v pgrep >/dev/null || fail "pgrep not on PATH"
    mkdir -p "$R" && chmod 700 "$R"
    # A stale sway from an earlier start of the same sandbox would add HEADLESS-2/3 confusion.
    if [ -f "$R/sway.pid" ] && kill -0 "$(cat "$R/sway.pid")" 2>/dev/null; then
      "$0" stop "$name" >/dev/null
    fi
    printf 'output HEADLESS-1 resolution 2560x1440\noutput * bg #101014 solid_color\n' > "$R/sway.conf"
    # First render node (renderD128 on single-GPU machines, may differ elsewhere); none → pixman.
    node=$(ls /dev/dri/renderD* 2>/dev/null | head -n 1)
    if [ "$renderer" = gles2 ] && [ -z "$node" ]; then
      echo "sandbox: no DRM render node, falling back to pixman" >&2
      renderer=pixman
    fi
    renderer_env=(WLR_RENDERER="$renderer")
    [ "$renderer" = gles2 ] && renderer_env+=(WLR_RENDER_DRM_DEVICE="$node")
    env -i HOME="$HOME" PATH="$PATH" XDG_RUNTIME_DIR="$R" WLR_BACKENDS=headless \
      WLR_LIBINPUT_NO_DEVICES=1 "${renderer_env[@]}" "$SWAY" -c "$R/sway.conf" > "$R/sway.log" 2>&1 &
    echo $! > "$R/sway.pid"
    XDG_RUNTIME_DIR="$R" dbus-daemon --session --fork --print-address=1 --print-pid=1 \
      --address="unix:path=$R/bus" > "$R/dbus.out" 2>/dev/null || true
    head -1 "$R/dbus.out" > "$R/dbus.addr" 2>/dev/null || true
    for _ in $(seq 50); do ls "$R" | grep -qE '^wayland-[0-9]+$' && break; sleep 0.1; done
    ls "$R" | grep -qE '^wayland-[0-9]+$' || fail "headless sway did not start (see $R/sway.log)"
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
      [ "$p" = $$ ] || [ "$p" = "$PPID" ] && continue   # never the caller's own shell
      if { tr "\0" "\n" < "/proc/$p/environ"; } 2>/dev/null | grep -qx "XDG_RUNTIME_DIR=$R"; then pids+=("$p"); fi
    done
    [ -f "$R/dbus.out" ] && pids+=("$(sed -n 2p "$R/dbus.out")")
    [ ${#pids[@]} -gt 0 ] && kill "${pids[@]}" 2>/dev/null || true
    echo "stopped ${#pids[@]} process(es) in $R"
    ;;
  *) echo "usage: $0 start|env|stop|output-add [name] [gles2|pixman]" >&2; exit 2 ;;
esac
