#!/usr/bin/env bash
# Golden screenshots of the core surfaces (M3 exit criterion): a visual regression check.
#   tools/golden/run.sh            render the states, compare with tools/golden/ref (exit 1 on fail)
#   tools/golden/run.sh --update   render the states and overwrite tools/golden/ref (Read them first)
# Everything runs in the headless sway sandbox `golden`, never on the user's display:
#   - sway with the pixman renderer, output HEADLESS-1 at 1920x1080 scale 1, set before qs starts
#   - real kurashid with isolated XDG dirs, the fixed config (config.toml: wa-iro, reduce_motion) and
#     its launcher index pinned to fixtures/share (XDG_DATA_DIRS for kurashid only, not for qs)
#   - the frontend via frontend/launch.sh with QT_QUICK_BACKEND=software: Qt has no working EGL under
#     pixman, and QSG_RHI_BACKEND has no software value in this Qt
#   - LC_ALL=C.UTF-8, so i18n falls back to en whatever the host locale is
# Each state is opened with `kurashi act`, captured with grim, then closed before the next one.
# compare.py holds the tolerance and the clock masks.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
G=$ROOT/tools/golden
OUT=$G/out
UPDATE=0
case "${1:-}" in
  "") ;;
  --update) UPDATE=1 ;;
  *) echo "usage: tools/golden/run.sh [--update]" >&2; exit 2 ;;
esac
NAME=${KURASHI_GOLDEN_SANDBOX:-golden}
SETTLE=${KURASHI_GOLDEN_SETTLE:-1.5}  # seconds between an action and its capture
fail() { echo "golden: $*" >&2; exit 1; }

# 1. Build, then copy the binaries in the same step: shared target dirs are overwritten by other
#    worktrees (docs/tasks/README.md rule 3). KURASHI_BIN_DIR overrides, as in frontend/test-real.sh.
export CARGO_TARGET_DIR=${CARGO_TARGET_DIR:-$ROOT/target}
if [ -z "${KURASHI_BIN_DIR:-}" ]; then
  (cd "$ROOT" && timeout 600 cargo build -q -p kurashid -p kurashi) || fail "cargo build failed"
  BIN=$CARGO_TARGET_DIR/debug
else
  BIN=$KURASHI_BIN_DIR
fi

pids=()
cleanup() {
  for p in "${pids[@]}"; do kill "$p" 2>/dev/null || true; done
  "$ROOT/tools/bench/sandbox.sh" stop "$NAME" >/dev/null || true
}
trap cleanup EXIT

# 2. Sandbox (fails closed, see tools/bench/sandbox.sh), then the fixed output geometry.
eval "$("$ROOT/tools/bench/sandbox.sh" start "$NAME" pixman)"
R=$XDG_RUNTIME_DIR
W=$R/work
mkdir -p "$W" "$R/kurashi" "$OUT"
rm -f "$OUT"/*.png
cp "$BIN/kurashid" "$BIN/kurashi" "$W/"
out=$(timeout 20 swaymsg output HEADLESS-1 resolution 1920x1080 scale 1) || fail "swaymsg failed"
case $out in
  *'"success": true'*) ;;
  *) fail "could not set HEADLESS-1 to 1920x1080 scale 1: $out" ;;
esac

export XDG_CONFIG_HOME=$R/xdg/config XDG_STATE_HOME=$R/xdg/state \
       XDG_DATA_HOME=$R/xdg/data XDG_CACHE_HOME=$R/xdg/cache \
       KURASHI_DATA_DIR=$ROOT LC_ALL=C.UTF-8
mkdir -p "$XDG_CONFIG_HOME/kurashi" "$XDG_STATE_HOME" "$XDG_DATA_HOME" "$XDG_CACHE_HOME"
cp "$G/config.toml" "$XDG_CONFIG_HOME/kurashi/config.toml"
K() { timeout 10 "$W/kurashi" "$@"; }

# 3. Real daemon. XDG_DATA_DIRS is set for kurashid alone: the launcher then indexes only the
#    fixtures, while qs keeps the host's font and icon paths.
rm -f "$KURASHI_SOCKET"
env XDG_DATA_DIRS="$G/fixtures/share" "$W/kurashid" >> "$R/kurashid.log" 2>&1 &
pids+=("$!")
for _ in $(seq 100); do
  [ -S "$KURASHI_SOCKET" ] && K ping >/dev/null 2>&1 && break
  sleep 0.1
done
K ping >/dev/null 2>&1 || fail "kurashid did not come up (see $R/kurashid.log)"

# The harness has to show what it claims: the fixed config must be in effect, or the frames are
# not the golden ones (Shojiki applied to the test itself).
got=$(K get a11y.reduce_motion) || true
case $got in *"= true"*"(user)"*) ;; *) fail "a11y.reduce_motion is not on from the user config: $got" ;; esac
got=$(K get theme.colors.palette) || true
case $got in *'= "wa-iro"'*"(user)"*) ;; *) fail "theme.colors.palette is not wa-iro from the user config: $got" ;; esac

# 4. Frontend.
env QT_QUICK_BACKEND=software "$ROOT/frontend/launch.sh" >> "$R/qs.log" 2>&1 &
pids+=("$!")
sleep 4

captured=()
shot() { # <state>: grab the output and check its geometry
  sleep "$SETTLE"
  timeout 20 grim -o HEADLESS-1 "$OUT/$1.png" || fail "grim failed on $1"
  python3 "$G/compare.py" --size "$OUT/$1.png" 1920 1080 || fail "$1: unexpected capture size"
  captured+=("$1")
  echo "shot $1"
}

# 5. States, each closed again before the next one (launcher.toggle does not close the centre).
shot bar-idle
K act island.expand >/dev/null
shot island-expanded
K act island.expand >/dev/null
K act notifications.center >/dev/null
shot notification-center
K act notifications.center >/dev/null
K act launcher.toggle >/dev/null
shot launcher-open
K act launcher.toggle >/dev/null
if [ -f "$ROOT/frontend/surfaces/SessionMenu.qml" ]; then
  K act session.menu >/dev/null
  shot session-menu
  K act session.menu >/dev/null
else
  echo "skip session-menu: frontend/surfaces/SessionMenu.qml is not on this branch yet (M5-ui-session)"
fi

errors='ERROR\|TypeError\|ReferenceError\|Unable to assign\|is not defined'
if grep -q "$errors" "$R/qs.log"; then
  grep "$errors" "$R/qs.log" | head >&2
  fail "frontend log has errors (see $R/qs.log)"
fi

# 6. Compare with the references, or replace them with this run's captures.
if [ "$UPDATE" = 1 ]; then
  mkdir -p "$G/ref"
  for s in "${captured[@]}"; do cp "$OUT/$s.png" "$G/ref/$s.png"; done
  echo "golden: updated ${captured[*]} in tools/golden/ref (Read each before committing)"
else
  python3 "$G/compare.py" --check "$G/ref" "$OUT" "${captured[@]}" || fail "FAILED"
  echo "golden: ok (${captured[*]})"
fi
