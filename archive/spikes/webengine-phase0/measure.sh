#!/usr/bin/env bash
# MODE=qtwe|qtbase|webkit|gtkbase: one panel with the page (or a baseline window), type, sum PSS of the client's processes.
set -uo pipefail
D=$(cd "$(dirname "$0")" && pwd); ROOT=/home/maike/Projects/kurashi-shell; NAME=webcmp-$MODE
W=/nix/store/fwlxhzls6qrnqn63q6n2lzmy5gidrn1j-qtwebengine-6.11.2
WC=$(nix-store -q --references $W | grep qtwebchannel); WP=$(nix-store -q --references $W | grep qtpositioning)
WTYPE=/nix/store/1npk1bl9fsmmx8nfr474f5n68wixw31w-wtype-0.4/bin/wtype
OUT=$D/cmp-$MODE; rm -rf "$OUT" "$D/store"; mkdir -p "$OUT" "$D/store"
eval "$("$ROOT/tools/bench/sandbox.sh" start "$NAME" 2>/dev/null)"
trap '"$ROOT/tools/bench/sandbox.sh" stop "$NAME" >/dev/null 2>&1 || true' EXIT
export SPIKE_URL=${SPIKE_URL_OVERRIDE:-file://$D/page.html} SPIKE_STORE=$D/store
case $MODE in
  qtwe)   export NIXPKGS_QT6_QML_IMPORT_PATH=$W/lib/qt-6/qml:$WC/lib/qt-6/qml:$WP/lib/qt-6/qml
          "$D/qs-patched/bin/quickshell" -p "$D/qs-share/shell.qml" >"$OUT/log" 2>&1 & ;;
  qtbase) quickshell -p "$D/qs-base/shell.qml" >"$OUT/log" 2>&1 & ;;
  webkit|gtkbase) [ $MODE = gtkbase ] && export SPIKE_BASE=1
          export LD_PRELOAD="$LD_PRELOAD:$GTK4_LAYER_SHELL_LIB"
          python3 "$D/wk/spike.py" >"$OUT/log" 2>&1 & ;;
esac
C=$!
for _ in $(seq 1 60); do grep -q "SPIKE LOAD 2" "$OUT/log" && break; sleep 0.5; done
sleep 2; "$WTYPE" "hello kurashi"; sleep "${SPIKE_IDLE:-3}"
grim -o HEADLESS-1 "$OUT/shot.png" 2>/dev/null
total=0; : > "$OUT/procs"
# The client and every descendant (Chromium's sandboxed children live in their own namespaces: walk the ppid tree).
desc() { echo "$1"; for c in $(awk -v p="$1" '$4==p{print $1}' /proc/[0-9]*/stat 2>/dev/null); do desc "$c"; done; }
for p in $(desc "$C"); do
  pss=$(awk '/^Pss:/{print $2}' /proc/$p/smaps_rollup 2>&1) || { echo "unreadable $p: $pss" >> "$OUT/procs"; continue; }
  total=$((total + pss)); echo "$pss kB  $(tr '\0' ' ' </proc/$p/cmdline | grep -oE -- '--type=[a-z-]+|WebKit[A-Za-z]+|quickshell|spike.py|bwrap|xdg-dbus-proxy' | head -1)" >> "$OUT/procs"
done
echo "$MODE total_pss_kB=$total typed=$(grep -c 'SPIKE TITLE typed' "$OUT/log")" | tee "$OUT/total"
kill $C 2>/dev/null; wait $C 2>/dev/null
