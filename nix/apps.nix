# Apps behind `nix run .#<app>` (flake.nix wires them per system). Each is a writeShellApplication:
# runtime tools come from runtimeInputs and shellcheck runs at build time. The scripts are Nix
# indented strings, so a shell `${var}` is written `''${var}`; a bare `$var` needs no escape.
{ pkgs, kurashi }:
let
  inherit (pkgs) lib;
  # Frontend, settings and i18n trees of this package. kurashid finds this prefix itself (i18n.rs).
  data = "${kurashi}/share/kurashi";

  scripts = {
    # Live session on the real display. Unless a daemon already answers on the socket, start
    # kurashid and stop it again on exit; the frontend runs in the foreground (no exec, so the
    # EXIT trap still runs).
    default = pkgs.writeShellApplication {
      name = "kurashi-app-default";
      runtimeInputs = [
        kurashi
        pkgs.quickshell
        pkgs.coreutils
      ];
      meta.description = "Live session: kurashid (unless one answers) and the frontend";
      text = ''
        state="''${XDG_STATE_HOME:-$HOME/.local/state}/kurashi"
        mkdir -p "$state"
        export KURASHI_QS=${lib.getExe' pkgs.quickshell "qs"}
        # launch.sh asks it for the compositor's main GPU to pin the right EGL vendor (K-hybrid-egl).
        export KURASHI_WAYLAND_INFO=${lib.getExe' pkgs.wayland-utils "wayland-info"}

        daemon=
        cleanup() {
          if [ -n "$daemon" ]; then
            kill "$daemon" 2>/dev/null || true
            wait "$daemon" 2>/dev/null || true
          fi
        }
        trap cleanup EXIT
        trap 'exit 129' HUP
        trap 'exit 130' INT
        trap 'exit 143' TERM

        if kurashi ping >/dev/null 2>&1; then
          echo "kurashi: kurashid already answers on the socket, attaching to it" >&2
        else
          kurashid >> "$state/kurashid.log" 2>&1 &
          daemon=$!
          up=0
          for _ in $(seq 100); do
            if kurashi ping >/dev/null 2>&1; then
              up=1
              break
            fi
            sleep 0.1
          done
          if [ "$up" -ne 1 ]; then
            echo "kurashi: kurashid did not come up; last lines of $state/kurashid.log:" >&2
            tail -n 20 "$state/kurashid.log" >&2 || true
            exit 1
          fi
        fi

        ${data}/frontend/launch.sh "$@"
      '';
    };

    # Settings talks to the running daemon and starts none (the default app does that).
    settings = pkgs.writeShellApplication {
      name = "kurashi-app-settings";
      runtimeInputs = [
        kurashi
        pkgs.quickshell
        pkgs.coreutils
      ];
      meta.description = "Settings app against the running kurashid";
      text = ''
        if ! kurashi ping >/dev/null 2>&1; then
          echo "kurashi: no kurashid answers on the socket; settings will show a disconnected state" >&2
        fi
        exec qs -p ${data}/settings "$@"
      '';
    };

    mock = pkgs.writeShellApplication {
      name = "kurashi-app-mock";
      runtimeInputs = [ kurashi ];
      meta.description = "Fake kurashid for frontend work (kurashi-mock)";
      text = ''
        exec kurashi-mock "$@"
      '';
    };

    # frontend/test-real.sh with this package's binaries. Everything the daemon and the frontend
    # could reach on the user's session is replaced: a headless sway, a private session bus, a
    # dead system bus and isolated XDG dirs and socket.
    sandbox = pkgs.writeShellApplication {
      name = "kurashi-app-sandbox";
      runtimeInputs = [
        kurashi
        pkgs.quickshell
        pkgs.sway
        pkgs.grim
        pkgs.dbus
        pkgs.coreutils
        pkgs.gnugrep
        pkgs.gnused
      ];
      meta.description = "Invisible real-stack smoke test in a headless sway (writes ./shots-sandbox)";
      text = ''
        out="$PWD/shots-sandbox"
        mkdir -p "$out"
        R=$(mktemp -d /tmp/kurashi-sandbox.XXXXXX)
        mkdir -p "$R/kurashi" "$R/xdg/config" "$R/xdg/state" "$R/xdg/data" "$R/xdg/cache"
        pids=()
        dpid=

        cleanup() {
          status=$?
          for p in "''${pids[@]}"; do
            kill "$p" 2>/dev/null || true
          done
          # Stragglers of this run: only processes whose environment carries this runtime dir.
          for d in /proc/[0-9]*; do
            p=''${d#/proc/}
            if [ "$p" = "$$" ]; then
              continue
            fi
            if grep -zqxF -- "XDG_RUNTIME_DIR=$R" "$d/environ" 2>/dev/null; then
              kill "$p" 2>/dev/null || true
            fi
          done
          if [ "$status" -eq 0 ]; then
            rm -rf "$R"
          else
            echo "sandbox: failed; logs kept in $R" >&2
          fi
        }
        trap cleanup EXIT
        trap 'exit 129' HUP
        trap 'exit 130' INT
        trap 'exit 143' TERM

        # Headless sway on its own runtime dir. LIBSEAT_BACKEND=builtin keeps it away from logind,
        # so it never asks for the user's seat. gles2 on the first render node (screencopy needs
        # it), pixman where there is none.
        printf 'output HEADLESS-1 resolution 2560x1440\noutput * bg #101014 solid_color\n' > "$R/sway.conf"
        node=
        for n in /dev/dri/renderD*; do
          [ -e "$n" ] || continue
          node=$n
          break
        done
        if [ -n "$node" ]; then
          renderer=(WLR_RENDERER=gles2 "WLR_RENDER_DRM_DEVICE=$node")
        else
          renderer=(WLR_RENDERER=pixman)
        fi
        env -i HOME="$HOME" PATH="$PATH" XDG_RUNTIME_DIR="$R" LIBSEAT_BACKEND=builtin \
          WLR_BACKENDS=headless WLR_LIBINPUT_NO_DEVICES=1 "''${renderer[@]}" \
          sway -c "$R/sway.conf" > "$R/sway.log" 2>&1 &
        pids+=("$!")

        # Private session bus: the daemon exports a notification server on the session bus.
        XDG_RUNTIME_DIR="$R" dbus-daemon --session --fork --print-address=1 --print-pid=1 \
          --address="unix:path=$R/bus" > "$R/dbus.out"
        bus=$(head -n 1 "$R/dbus.out")
        pids+=("$(sed -n 2p "$R/dbus.out")")

        wl=
        sock=
        for _ in $(seq 50); do
          for f in "$R"/wayland-* "$R"/sway-ipc.*.sock; do
            if [ -S "$f" ]; then
              case ''${f##*/} in
                sway-ipc.*) sock=$f ;;
                *) wl=''${f##*/} ;;
              esac
            fi
          done
          if [ -n "$wl" ] && [ -n "$sock" ]; then
            break
          fi
          sleep 0.1
        done
        if [ -z "$wl" ] || [ -z "$sock" ]; then
          echo "sandbox: headless sway did not start (see $R/sway.log)" >&2
          exit 1
        fi

        # Environment of every client: nothing of the user's session survives (no DISPLAY, niri or
        # Hyprland socket), and the daemon and frontend see only this sandbox's compositor and bus.
        sbenv=(
          env -u DISPLAY -u NIRI_SOCKET -u HYPRLAND_INSTANCE_SIGNATURE
          "XDG_RUNTIME_DIR=$R" "WAYLAND_DISPLAY=$wl" "SWAYSOCK=$sock"
          "DBUS_SESSION_BUS_ADDRESS=$bus" "DBUS_SYSTEM_BUS_ADDRESS=unix:path=$R/no-system-bus"
          "XDG_CONFIG_HOME=$R/xdg/config" "XDG_STATE_HOME=$R/xdg/state"
          "XDG_DATA_HOME=$R/xdg/data" "XDG_CACHE_HOME=$R/xdg/cache"
          "KURASHI_SOCKET=$R/kurashi/ipc.sock" "KURASHI_DATA_DIR=${data}"
        )
        in_sb() { "''${sbenv[@]}" "$@"; }
        K() { in_sb kurashi "$@"; }
        shot() {
          sleep "''${2:-1.5}"
          in_sb grim "$out/$1.png"
          if [ ! -s "$out/$1.png" ]; then
            echo "sandbox: empty screenshot $1" >&2
            exit 1
          fi
          echo "shot $1"
        }
        start_daemon() {
          rm -f "$R/kurashi/ipc.sock"
          "''${sbenv[@]}" kurashid >> "$R/kurashid.log" 2>&1 &
          dpid=$!
          pids+=("$dpid")
          for _ in $(seq 100); do
            if [ -S "$R/kurashi/ipc.sock" ] && in_sb kurashi ping >/dev/null 2>&1; then
              return 0
            fi
            sleep 0.1
          done
          echo "sandbox: kurashid did not come up (see $R/kurashid.log)" >&2
          exit 1
        }

        : > "$R/qs.log"
        start_daemon
        "''${sbenv[@]}" qs -p "${data}/frontend" >> "$R/qs.log" 2>&1 &
        pids+=("$!")
        sleep 3

        shot bar-idle
        K act island.next >/dev/null
        shot island-next
        K act island.expand >/dev/null
        shot popup-expand
        K act island.expand >/dev/null   # toggle the popup closed again

        # Daemon gone: the frontend must veil and keep rendering, then recover on restart.
        kill "$dpid" 2>/dev/null || true
        wait "$dpid" 2>/dev/null || true
        shot veil-disconnected 2.5
        start_daemon
        shot reconnected 2.5

        errors='ERROR|TypeError|ReferenceError|Unable to assign|is not defined'
        if grep -qE "$errors" "$R/qs.log"; then
          echo "sandbox: qs.log has errors:" >&2
          grep -E "$errors" "$R/qs.log" | head >&2
          exit 1
        fi
        echo "ok: screenshots in $out"
      '';
    };
  };
in
{
  inherit scripts;
  apps = lib.mapAttrs (_: drv: {
    type = "app";
    program = "${drv}/bin/${drv.name}";
  }) scripts;
}
