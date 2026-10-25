#!/usr/bin/env bash
# The quick settings card's build time (W37-quick's method, W39-block): on a copy of each frontend the Stage's view Loader
# is made synchronous and two log lines are added (the runtime.ui patch arriving in Store, the view made in the Stage), so
# "patch → view made" is the card's whole build inside the patch handler. Per frontend: the first open, then QUICK_WARM
# warm opens (default 7), each from rest; medians of the warm ones. Invisibly, the real kurashid, an empty config.
#   nix develop -c tools/bench/quick-open.sh <frontend dir> [<frontend dir> …]
# QUICK_LOOK (kurashi set theme.style=…, default: none, the empty config's look), QUICK_ACTION (default quick.toggle),
# QUICK_KIND (the Stage's content kind it makes, default quick). Binaries from $KURASHI_BIN_DIR, else
# $CARGO_TARGET_DIR/release. Nothing of this is committed into the frontend: the copies live in the sandbox.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
NAME=${QUICK_SANDBOX:-w39-block-quick}
BIN=${KURASHI_BIN_DIR:-${CARGO_TARGET_DIR:-$ROOT/target}/release}
WARM=${QUICK_WARM:-7}
ACTION=${QUICK_ACTION:-quick.toggle}
KIND=${QUICK_KIND:-quick}
[ $# -gt 0 ] || set -- "$ROOT/frontend"
fail() { echo "quick-open: FAIL: $*" >&2; exit 1; }

eval "$("$ROOT/tools/bench/sandbox.sh" start "$NAME")"
R=$XDG_RUNTIME_DIR
W=$R/work
mkdir -p "$W" "$R/kurashi"
cp "$BIN/kurashid" "$BIN/kurashi" "$W/"
pids=()
cleanup() {
  for p in "${pids[@]}"; do kill "$p" 2>/dev/null || true; done
  for p in "${pids[@]}"; do wait "$p" 2>/dev/null || true; done
  "$ROOT/tools/bench/sandbox.sh" stop "$NAME" >/dev/null || true
}
trap cleanup EXIT
export XDG_CONFIG_HOME=$R/xdg/config XDG_STATE_HOME=$R/xdg/state \
       XDG_DATA_HOME=$R/xdg/data XDG_CACHE_HOME=$R/xdg/cache KURASHI_DATA_DIR=$ROOT LC_ALL=C.UTF-8
rm -rf "$R/xdg"; mkdir -p "$XDG_CONFIG_HOME/kurashi" "$XDG_STATE_HOME" "$XDG_DATA_HOME" "$XDG_CACHE_HOME"
: > "$XDG_CONFIG_HOME/kurashi/config.toml"
K() { timeout 10 "$W/kurashi" "$@"; }
env DBUS_SYSTEM_BUS_ADDRESS="unix:path=$R/no-system-bus" PULSE_SERVER="unix:$R/no-pulse/native" \
    PULSE_RUNTIME_PATH="$R/no-pulse" "$W/kurashid" > "$R/server.log" 2>&1 &
pids+=("$!")
for _ in $(seq 100); do [ -S "$KURASHI_SOCKET" ] && K ping >/dev/null 2>&1 && break; sleep 0.1; done
K ping >/dev/null 2>&1 || fail "kurashid did not come up (see $R/server.log)"
[ -z "${QUICK_LOOK:-}" ] || K set theme.style="$QUICK_LOOK" >/dev/null || fail "theme.style=$QUICK_LOOK refused"

i=0
for fe in "$@"; do
  i=$((i + 1))
  C=$W/fe$i
  rm -rf "$C"; cp -r "$fe" "$C"
  python3 -I - "$C" <<'PY'
import sys
c = sys.argv[1]
def patch(path, old, new):
    s = open(path).read()
    if s.count(old) != 1:
        sys.exit("quick-open: cannot patch %s (%r)" % (path, old))
    open(path, "w").write(s.replace(old, new))
patch(c + "/core/Store.qml", '} else if (m.t === "patch") {',
      '} else if (m.t === "patch") {\n            if (m.doc === "runtime.ui") console.log("QPBENCH patch t=" + Date.now())')
patch(c + "/surfaces/Stage.qml", "asynchronous: true", "asynchronous: false")
patch(c + "/surfaces/Stage.qml", 'onLoaded: if (stage.debugLog) console.log("stage-view made "',
      'onLoaded: console.log("QPBENCH made "')
PY
  log=$W/qs$i.log
  n0=$(grep -c 'hello.*frontend' "$R/server.log" || true)
  env -u KURASHI_SOCKET qs -p "$C" > "$log" 2>&1 &
  qs=$!; pids+=("$qs")
  for _ in $(seq 100); do [ "$(grep -c 'hello.*frontend' "$R/server.log" || true)" -gt "$n0" ] && break; sleep 0.1; done
  sleep 4
  for _ in $(seq $((WARM + 1))); do
    K act "$ACTION" >/dev/null || fail "act $ACTION"
    sleep 1.6
    K act ui.close >/dev/null || true
    sleep 1.4
  done
  kill "$qs" 2>/dev/null || true; wait "$qs" 2>/dev/null || true
  python3 -I - "$log" "$fe" "$KIND" <<'PY'
import re, statistics, sys
log, fe, kind = sys.argv[1:]
last, ms = None, []
for line in open(log, errors="ignore"):
    m = re.search(r"QPBENCH patch t=(\d+)", line)
    if m: last = int(m.group(1)); continue
    m = re.search(r"QPBENCH made (\S+) t=(\d+)", line)
    if m and m.group(1) == kind and last is not None:
        ms.append(int(m.group(2)) - last); last = None
if not ms:
    sys.exit("quick-open: no %s view made (see %s)" % (kind, log))
warm = ms[1:]
print("%-60s first %d ms | warm %s → median %.1f ms" % (fe[-60:], ms[0], warm, statistics.median(warm) if warm else float("nan")))
PY
done
