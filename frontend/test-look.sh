#!/usr/bin/env bash
# The look of the shell, invisibly (headless sway sandbox), against the REAL kurashid (K42 design pass):
# starts kurashid with a theme (default: decor `sekai`), the frontend, then opens each surface by its action and
# takes a screenshot of it — bar, island card, quick settings, notification centre, launcher, session menu — into
# frontend/shots/look/<tag>/. Evidence to look at, not a pass/fail test; it fails only on a QML error or a server
# that does not come up.
#   nix develop -c frontend/test-look.sh [tag] [config-toml-line ...]
#   e.g. frontend/test-look.sh wa-iro 'theme.decor = "none"'
#        frontend/test-look.sh sekai-dark 'theme.decor = "sekai"' 'theme.colors.scheme = "dark"'
# LOOK_STEPS="bar island quick notif launcher session" picks steps; LOOK_LOCK=1 adds lock.png (the real daemon refuses
# to lock without its PAM service, so the lock is shown by kurashi-mock wearing the real daemon's theme tokens); LOOK_EXTRA="<cmd>" runs a command (e.g.
# `kurashi act webdock.open`) before a last screenshot named extra.png. Machine B: KURASHI_RENDER_NODE first.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
TAG=${1:-sekai}
shift || true
LINES=("$@")
[ ${#LINES[@]} -eq 0 ] && LINES=('theme.decor = "sekai"')
NAME=fe-look-$TAG
BIN=${KURASHI_BIN_DIR:-${CARGO_TARGET_DIR:-$ROOT/target}/debug}
OUT=$ROOT/frontend/shots/look/$TAG
STEPS=${LOOK_STEPS:-bar island quick notif launcher session}
mkdir -p "$OUT"
fail() { echo "test-look: $*" >&2; exit 1; }

eval "$("$ROOT/tools/bench/sandbox.sh" start "$NAME")"
R=$XDG_RUNTIME_DIR
W=$R/work
mkdir -p "$W" "$R/kurashi"
cp "$BIN/kurashid" "$BIN/kurashi" "$W/"
[ -x "$BIN/kurashi-mock" ] && cp "$BIN/kurashi-mock" "$W/"
pids=()
cleanup() {
  for p in "${pids[@]}"; do kill "$p" 2>/dev/null || true; done
  for p in "${pids[@]}"; do wait "$p" 2>/dev/null || true; done
  "$ROOT/tools/bench/sandbox.sh" stop "$NAME" >/dev/null || true
}
trap cleanup EXIT

rm -rf "$R/xdg"
export XDG_CONFIG_HOME=$R/xdg/config XDG_STATE_HOME=$R/xdg/state \
       XDG_DATA_HOME=$R/xdg/data XDG_CACHE_HOME=$R/xdg/cache KURASHI_DATA_DIR=$ROOT LC_ALL=C.UTF-8
mkdir -p "$XDG_CONFIG_HOME/kurashi" "$XDG_STATE_HOME" "$XDG_DATA_HOME" "$XDG_CACHE_HOME"
printf '%s\n' "${LINES[@]}" > "$XDG_CONFIG_HOME/kurashi/config.toml"
K() { timeout 10 "$W/kurashi" "$@"; }

: > "$R/server.log"; : > "$R/qs.log"
env DBUS_SYSTEM_BUS_ADDRESS="unix:path=$R/no-system-bus" \
    PULSE_SERVER="unix:$R/no-pulse/native" PULSE_RUNTIME_PATH="$R/no-pulse" \
    "$W/kurashid" >> "$R/server.log" 2>&1 &
pids+=("$!")
for _ in $(seq 100); do [ -S "$KURASHI_SOCKET" ] && K ping >/dev/null 2>&1 && break; sleep 0.1; done
K ping >/dev/null 2>&1 || fail "kurashid did not come up (see $R/server.log)"
# A desk to look at: the wallpaper test picture when there is one, else a neutral fill.
swaymsg output '*' bg '#8fb8c8' solid_color >/dev/null 2>&1 || true
env -u KURASHI_SOCKET qs -p "$ROOT/frontend" >> "$R/qs.log" 2>&1 &
pids+=("$!")
for _ in $(seq 100); do grep -q 'hello.*frontend' "$R/server.log" && break; sleep 0.1; done
grep -q 'hello.*frontend' "$R/server.log" || fail "frontend never said hello (see $R/qs.log)"
sleep 3

shot() { sleep "${2:-1.2}"; grim "$OUT/$1.png"; echo "test-look: $OUT/$1.png"; }
close() { K act "$1" >/dev/null 2>&1 || true; sleep 0.8; }
for s in $STEPS; do
  case $s in
    bar) shot bar 0.2 ;;
    island) K act island.expand >/dev/null; shot island; close island.expand ;;
    quick) K act quick.toggle >/dev/null; shot quick; close quick.toggle ;;
    notif) K act notifications.center >/dev/null; shot notif; close notifications.center ;;
    launcher) K act launcher.toggle >/dev/null; shot launcher; close launcher.toggle ;;
    session) K act session.menu >/dev/null; shot session; close session.menu ;;
  esac
done
if [ -n "${LOOK_EXTRA:-}" ]; then
  KURASHI=$W/kurashi bash -c "$LOOK_EXTRA" || true
  shot extra 2
fi
if [ "${LOOK_LOCK:-0}" = 1 ]; then
  K sub theme --count 0 --json | jq -c '{doc: "theme", patch: {tokens: .data.tokens}}' > "$W/theme-patch.json"
  for p in "${pids[@]}"; do kill "$p" 2>/dev/null || true; done
  for p in "${pids[@]}"; do wait "$p" 2>/dev/null || true; done
  pids=()
  rm -f "$KURASHI_SOCKET"
  "$W/kurashi-mock" --outputs HEADLESS-1 --socket "$KURASHI_SOCKET" >> "$R/server.log" 2>&1 &
  pids+=("$!")
  for _ in $(seq 100); do [ -S "$KURASHI_SOCKET" ] && K ping >/dev/null 2>&1 && break; sleep 0.1; done
  K act mock.doc "$(cat "$W/theme-patch.json")" >/dev/null
  : > "$R/server.log.lock"
  env -u KURASHI_SOCKET qs -p "$ROOT/frontend" >> "$R/qs.log" 2>&1 &
  pids+=("$!")
  sleep 3
  K act mock.doc '{"doc":"runtime.lock","patch":{"locked":true}}' >/dev/null
  shot lock 2
fi
if grep -E 'qml:.*(Error|error)|TypeError|ReferenceError|is not a type' "$R/qs.log" | grep -v 'Unable to assign \[undefined\]' >/dev/null; then
  grep -E 'Error|error' "$R/qs.log" | head -20 >&2
  fail "QML errors (see $R/qs.log)"
fi
echo "test-look: ok ($OUT)"
