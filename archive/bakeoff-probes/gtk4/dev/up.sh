#!/usr/bin/env bash
# Dev helper: start sandbox "gtk4" + kurashi-mock + the probe binary (run inside `nix develop`).
# usage: dev/up.sh [probe-binary]
set -u
ROOT=$(git rev-parse --show-toplevel)
BIN=${1:-$ROOT/archive/bakeoff-probes/gtk4/target/release/probe-gtk4}
source <("$ROOT/tools/bench/sandbox.sh" start gtk4)
mkdir -p "$(dirname "$KURASHI_SOCKET")"
nohup "$ROOT/target/release/kurashi-mock" --outputs HEADLESS-1,HEADLESS-2 > "$XDG_RUNTIME_DIR/mock.log" 2>&1 &
sleep 0.5
nohup "$BIN" > "$XDG_RUNTIME_DIR/probe.log" 2>&1 &
sleep 3
head -20 "$XDG_RUNTIME_DIR/probe.log"
