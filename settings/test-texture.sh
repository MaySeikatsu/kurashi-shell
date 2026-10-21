#!/usr/bin/env bash
# K59/K60 in Settings: the material cards (the daemon's swatches), the light dial and the ink swatches, under the style
# kami in light and dark. Headless sway sandbox, isolated kurashid; never touches the real session.
#   settings/test-texture.sh   → exit 0 and settings/shots/appearance/texture-*.png
set -euo pipefail
cd "$(dirname "$0")/.."
ROOT=$PWD
if ! command -v qs >/dev/null || ! command -v sway >/dev/null; then
  exec nix develop -c "$0" "$@"
fi
BIN=$(mktemp -d)
if [ -n "${KURASHI_BIN_DIR:-}" ]; then
  cp "$KURASHI_BIN_DIR/kurashid" "$KURASHI_BIN_DIR/kurashi" "$BIN/"
else
  export CARGO_TARGET_DIR=${CARGO_TARGET_DIR:-$HOME/.cache/kurashi-agents-target}
  cargo build -q -p kurashid -p kurashi
  cp "$CARGO_TARGET_DIR/debug/kurashid" "$CARGO_TARGET_DIR/debug/kurashi" "$BIN/"
fi
NAME=${KURASHI_SB_NAME:-settex-$$}
envfile=$(mktemp)
tools/bench/sandbox.sh start "$NAME" > "$envfile"
# shellcheck disable=SC1090
. "$envfile"; rm -f "$envfile"
R=$XDG_RUNTIME_DIR
pids=()
cleanup() {
  rm -rf "$BIN"
  for p in "${pids[@]}"; do kill "$p" 2>/dev/null || true; done
  tools/bench/sandbox.sh stop "$NAME" >/dev/null || true
}
trap cleanup EXIT
fail() { echo "FAIL: $*"; exit 1; }

mkdir -p "$R/cfg/kurashi" "$R/state" "$R/data" "$R/cache" settings/shots/appearance
export XDG_CONFIG_HOME=$R/cfg XDG_STATE_HOME=$R/state XDG_DATA_HOME=$R/data XDG_CACHE_HOME=$R/cache
export KURASHI_DATA_DIR=$ROOT
cat > "$R/cfg/kurashi/config.toml" <<'T'
schema_version = 2
[theme]
style = "kami"
look = "kami"
[theme.colors]
palette = "kami"
scheme = "light"
ink = "blue"
[theme.texture]
kind = "paper_dots"
strength = 0.55
T
"$BIN/kurashid" > "$R/kurashid.log" 2>&1 & pids+=("$!")
for _ in $(seq 50); do [ -S "$KURASHI_SOCKET" ] && break; sleep 0.1; done
[ -S "$KURASHI_SOCKET" ] || { cat "$R/kurashid.log"; fail "kurashid did not start"; }
K() { "$BIN/kurashi" "$@"; }
Q() { qs -p settings ipc call settings "$@"; }
start_qs() {
  env -u KURASHI_SOCKET KURASHI_SETTINGS_KEY="$1" qs -p settings > "$R/settings-$2.log" 2>&1 & qs_pid=$!; pids+=("$qs_pid")
  for _ in $(seq 100); do Q current >/dev/null 2>&1 && break; sleep 0.2; done
  Q current >/dev/null 2>&1 || { cat "$R/settings-$2.log"; fail "settings did not start"; }
}
stop_qs() { kill "$qs_pid" 2>/dev/null || true; wait "$qs_pid" 2>/dev/null || true; }
shot() { sleep 1.2; grim -o HEADLESS-1 "settings/shots/appearance/$1.png"; [ -s "settings/shots/appearance/$1.png" ]; }
errors() { grep -E "TypeError|ReferenceError|is not a type|Cannot assign|is not defined|Unable to assign" "$1" | grep -v "^\s*$" || true; }

start_qs theme.texture.kind light
# The swatches are made once Settings watches the previews: eleven, then the cards show them.
for _ in $(seq 150); do [ "$(ls "$R/cache/kurashi/texture/swatch" 2>/dev/null | grep -c '\.png$')" -ge 11 ] && break; sleep 0.2; done
[ "$(ls "$R/cache/kurashi/texture/swatch" | grep -c '\.png$')" -ge 11 ] || fail "swatches were not made"
shot texture-cards-light
stop_qs
start_qs theme.light.mode light2
shot texture-light-dial
stop_qs
start_qs theme.colors.ink light3
shot texture-ink-light
stop_qs
K set theme.colors.scheme '"dark"' | grep -q '^applied' || fail "dark"
start_qs theme.texture.kind dark
for _ in $(seq 150); do [ "$(ls "$R/cache/kurashi/texture/swatch" | grep -c '\.png$')" -ge 22 ] && break; sleep 0.2; done
shot texture-cards-dark
stop_qs
for f in "$R"/settings-*.log; do
  e=$(errors "$f"); [ -z "$e" ] || { echo "$e"; fail "QML errors in $(basename "$f")"; }
done
echo "settings texture: ok"
