#!/usr/bin/env bash
# Phase 0 spike: QtWebEngine view in a Quickshell PanelWindow, keyboard input, in the headless sandbox.
set -uo pipefail
D=$(cd "$(dirname "$0")" && pwd)
ROOT=/home/maike/Projects/kurashi-shell
NAME=${NAME:-webspike}
W=/nix/store/fwlxhzls6qrnqn63q6n2lzmy5gidrn1j-qtwebengine-6.11.2
WC=$(nix-store -q --references $W | grep qtwebchannel)
WP=$(nix-store -q --references $W | grep qtpositioning)
WTYPE=/nix/store/1npk1bl9fsmmx8nfr474f5n68wixw31w-wtype-0.4/bin/wtype
OUT=$D/${OUT_NAME:-out}; rm -rf "$OUT"; mkdir -p "$OUT"
eval "$("$ROOT/tools/bench/sandbox.sh" start "$NAME")"
trap '"$ROOT/tools/bench/sandbox.sh" stop "$NAME" >/dev/null 2>&1 || true' EXIT
export NIXPKGS_QT6_QML_IMPORT_PATH=$W/lib/qt-6/qml:$WC/lib/qt-6/qml:$WP/lib/qt-6/qml
export SPIKE_URL=file://$D/page.html SPIKE_STORE=$D/store
export QT_LOGGING_RULES="${SPIKE_LOG_RULES:-}"
[ -n "${SPIKE_EXTRA_ENV:-}" ] && export $SPIKE_EXTRA_ENV
"${QS_BIN:-quickshell}" -p "$D/${QS_DIR:-qs}/shell.qml" >"$OUT/qs.log" 2>&1 &
QS=$!
for _ in $(seq 1 60); do grep -q "SPIKE LOAD 2\|SPIKE LOAD 3" "$OUT/qs.log" && break; sleep 0.5; done
sleep 1
grim -o HEADLESS-1 "$OUT/1-loaded.png" 2>>"$OUT/grim.log"
"$WTYPE" "hello kurashi" 2>>"$OUT/wtype.log"
sleep 1.5
grim -o HEADLESS-1 "$OUT/2-typed.png" 2>>"$OUT/grim.log"
ps -o pid,rss,cmd --ppid $QS > "$OUT/children.txt" 2>/dev/null
pgrep -f QtWebEngineProcess | while read -r p; do grep -qs "$XDG_RUNTIME_DIR" /proc/$p/environ && echo "$p $(awk '/^Pss:/{print $2}' /proc/$p/smaps_rollup) kB $(tr '\0' ' ' </proc/$p/cmdline | grep -o -- '--type=[a-z-]*')"; done > "$OUT/webengine-procs.txt"
echo "qs pss $(awk '/^Pss:/{print $2}' /proc/$QS/smaps_rollup) kB" >> "$OUT/webengine-procs.txt"
kill $QS; wait $QS 2>/dev/null
echo "rc done"
