#!/usr/bin/env bash
# Headless sway sandbox for invisible frontend tests (never touches the user's session).
#   sandbox.sh start [name] [renderer]  → prints `export ...` lines (eval them)
#   sandbox.sh env   [name]             → prints the export lines again
#   sandbox.sh stop  [name]             → kills ONLY processes whose environ has this runtime dir
#   sandbox.sh output-add [name]        → hotplug one more output (HEADLESS-2, -3, …)
#   sandbox.sh netcheck [name]          → probes the sandbox's network from inside it; every probe must fail
# Renderer: gles2 (default; needed for dmabuf → clients render on the GPU, and for screencopy)
#           or pixman (software). KURASHI_RENDER_NODE=/dev/dri/renderD… overrides the GPU.
# Network (I58): sway and every process the env lines start share one network namespace that holds loopback only
# (netns-hold.py holds it; netjoin.c joins it before main(), through LD_PRELOAD), so a test cannot reach the host
# network or the internet, while the sandbox's unix sockets and its D-Bus work as before. `start` probes that and
# fails closed when the sandbox reaches a network. KURASHI_SANDBOX_NET=1 keeps the host network (no test uses it).
set -euo pipefail
action=${1:-start}; name=${2:-dev}; renderer=${3:-gles2}
HERE=$(cd "$(dirname "$0")" && pwd)
R=/tmp/kurashi-sb-$name
SWAY=${KURASHI_SWAY:-$(command -v sway || true)}   # may be empty for stop/env outside nix develop

# The namespace exists while the holder's id file and the join library do (start writes them, stop removes the id).
netns_on() { [ -s "$R/netns.id" ] && [ -f "$R/netjoin.so" ]; }

env_lines() {
  local wl; wl=$(ls "$R" 2>/dev/null | grep -m1 -E '^wayland-[0-9]+$' || true)
  echo "export XDG_RUNTIME_DIR=$R"
  echo "export WAYLAND_DISPLAY=${wl:-wayland-1}"
  echo "export SWAYSOCK=$(ls "$R"/sway-ipc.*.sock 2>/dev/null | head -1)"
  [ -f "$R/dbus.addr" ] && echo "export DBUS_SESSION_BUS_ADDRESS=$(cat "$R/dbus.addr")"
  echo "export KURASHI_SOCKET=$R/kurashi/ipc.sock"
  if netns_on; then
    preload=$R/netjoin.so
    # Keep whatever the caller preloads, unless this library is already in it.
    if [ -n "${LD_PRELOAD:-}" ] && [ "${LD_PRELOAD#*"$R/netjoin.so"}" = "$LD_PRELOAD" ]; then preload=$preload:$LD_PRELOAD; fi
    echo "export KURASHI_SANDBOX_NETNS_PID=$(cat "$R/sway.pid")"
    echo "export KURASHI_SANDBOX_NETNS_ID=$(cat "$R/netns.id")"
    echo "export LD_PRELOAD=$preload"
  else
    echo "unset KURASHI_SANDBOX_NETNS_PID KURASHI_SANDBOX_NETNS_ID"
  fi
  echo "unset DISPLAY NIRI_SOCKET HYPRLAND_INSTANCE_SIGNATURE"
}

# netcheck_run: the sandbox's probes, run joined to its namespace (the env lines do that). Every probe must fail.
# curl first when it is on PATH (the NixOS host has one; the dev shell does not), then tools/bench/netcheck.py.
netcheck_run() {
  local out
  netns_on || { echo "netcheck: no sandbox network namespace (KURASHI_SANDBOX_NET=1, or the sandbox is not started)" >&2; return 1; }
  if command -v curl >/dev/null 2>&1; then
    if out=$( (eval "$(env_lines)"; exec timeout 15 curl -sS --max-time 5 -o /dev/null https://example.com) 2>&1 ); then
      echo "netcheck: curl https://example.com SUCCEEDED inside the sandbox" >&2
      return 1
    fi
    echo "netcheck: curl https://example.com failed inside the sandbox: $(tail -n 1 <<<"$out")"
  fi
  (eval "$(env_lines)"; exec timeout 60 python3 -I "$HERE/netcheck.py")
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
    rm -f "$R/netns.id" "$R/netjoin.so" "$R/dbus.addr"
    net=1
    [ "${KURASHI_SANDBOX_NET:-0}" = 1 ] && net=0
    holder=()
    if [ "$net" = 1 ]; then
      command -v python3 >/dev/null || fail "python3 not on PATH (the sandbox network namespace needs it)"
      command -v cc >/dev/null || fail "cc not on PATH (builds the sandbox's network join, tools/bench/netjoin.c)"
      cc -shared -fPIC -O2 -Wall -Werror -o "$R/netjoin.so" "$HERE/netjoin.c" || fail "netjoin.c does not build"
      holder=(python3 -I "$HERE/netns-hold.py" "$R/netns.id")
    fi
    printf 'output HEADLESS-1 resolution 2560x1440\noutput * bg #101014 solid_color\n' > "$R/sway.conf"
    # The render node of the firmware's display GPU (boot_vga=1), else the first one; none → pixman.
    # On hybrid laptops the first node is often the dGPU, whose runtime-PM resumes stall tests (B10).
    # KURASHI_RENDER_NODE picks another one.
    node=${KURASHI_RENDER_NODE:-}
    if [ -z "$node" ]; then
      for r in /sys/class/drm/renderD*; do
        [ "$(cat "$r/device/boot_vga" 2>/dev/null)" = 1 ] && { node=/dev/dri/${r##*/}; break; }
      done
    fi
    node=${node:-$(ls /dev/dri/renderD* 2>/dev/null | head -n 1)}
    if [ "$renderer" = gles2 ] && [ -z "$node" ]; then
      echo "sandbox: no DRM render node, falling back to pixman" >&2
      renderer=pixman
    fi
    renderer_env=(WLR_RENDERER="$renderer")
    [ "$renderer" = gles2 ] && renderer_env+=(WLR_RENDER_DRM_DEVICE="$node")
    # With the network on, the holder unshares the namespace and then execs sway, so sway is the holder's pid.
    env -i HOME="$HOME" PATH="$PATH" XDG_RUNTIME_DIR="$R" WLR_BACKENDS=headless \
      WLR_LIBINPUT_NO_DEVICES=1 "${renderer_env[@]}" "${holder[@]}" "$SWAY" -c "$R/sway.conf" > "$R/sway.log" 2>&1 &
    echo $! > "$R/sway.pid"
    if [ "$net" = 1 ]; then
      for _ in $(seq 50); do [ -s "$R/netns.id" ] && break; sleep 0.1; done
      [ -s "$R/netns.id" ] || fail "the sandbox network namespace did not start (see $R/sway.log)"
    fi
    join=()
    if netns_on; then
      join=(LD_PRELOAD="$R/netjoin.so" KURASHI_SANDBOX_NETNS_PID="$(cat "$R/sway.pid")" KURASHI_SANDBOX_NETNS_ID="$(cat "$R/netns.id")")
    fi
    env XDG_RUNTIME_DIR="$R" "${join[@]}" dbus-daemon --session --fork --print-address=1 --print-pid=1 \
      --address="unix:path=$R/bus" > "$R/dbus.out" 2>/dev/null || true
    head -1 "$R/dbus.out" > "$R/dbus.addr" 2>/dev/null || true
    if netns_on && [ ! -s "$R/dbus.addr" ]; then fail "the sandbox's D-Bus did not start inside its network namespace"; fi
    for _ in $(seq 50); do ls "$R" | grep -qE '^wayland-[0-9]+$' && break; sleep 0.1; done
    ls "$R" | grep -qE '^wayland-[0-9]+$' || fail "headless sway did not start (see $R/sway.log)"
    if netns_on && ! netcheck_run >&2; then
      "$0" stop "$name" >/dev/null 2>&1 || true
      fail "the sandbox reaches a network (see the netcheck lines above)"
    fi
    env_lines
    ;;
  env) env_lines ;;
  netcheck) netcheck_run ;;
  output-add)
    sock=$(ls "$R"/sway-ipc.*.sock | head -1)
    SWAYSOCK=$sock swaymsg create_output >/dev/null
    # The new output is the highest HEADLESS-<n>; same mode as HEADLESS-1.
    out=$(SWAYSOCK=$sock swaymsg -t get_outputs -r | grep -o '"HEADLESS-[0-9]*"' | tr -d '"' | sort -t- -k2 -n | tail -1)
    SWAYSOCK=$sock swaymsg output "${out:-HEADLESS-2}" resolution 2560x1440 >/dev/null || true
    ;;
  stop)
    pids=()
    for p in $(pgrep -u "$(id -u)" . || true); do
      [ "$p" = $$ ] || [ "$p" = "$PPID" ] && continue   # never the caller's own shell
      if { tr "\0" "\n" < "/proc/$p/environ"; } 2>/dev/null | grep -qx "XDG_RUNTIME_DIR=$R"; then pids+=("$p"); fi
    done
    [ -f "$R/dbus.out" ] && pids+=("$(sed -n 2p "$R/dbus.out")")
    [ ${#pids[@]} -gt 0 ] && kill "${pids[@]}" 2>/dev/null || true
    rm -f "$R/netns.id"   # the env lines stop joining a namespace that is going away
    echo "stopped ${#pids[@]} process(es) in $R"
    ;;
  *) echo "usage: $0 start|env|stop|output-add|netcheck [name] [gles2|pixman]" >&2; exit 2 ;;
esac
