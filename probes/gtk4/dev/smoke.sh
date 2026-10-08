#!/usr/bin/env bash
# Dev helper: screenshots of bar, media face, popup, 2 outputs. Run inside `nix develop`.
ROOT=$(git rev-parse --show-toplevel)
S=$ROOT/probes/gtk4/shots
"$ROOT/tools/bench/sandbox.sh" stop gtk4
"$ROOT/probes/gtk4/dev/up.sh" "${1:-$ROOT/probes/gtk4/target/release/probe-gtk4}"
source <("$ROOT/tools/bench/sandbox.sh" env gtk4)
grim "$S/bar.png"
"$ROOT/target/release/kurashi" mock face media; sleep 1.2
grim "$S/island-media.png"
"$ROOT/target/release/kurashi" act probe.popup.toggle; sleep 1
grim "$S/popup.png"
"$ROOT/tools/bench/sandbox.sh" output-add gtk4; sleep 2
grim "$S/two-outputs.png"
"$ROOT/target/release/kurashi" act probe.popup.toggle; sleep 1
cat "$XDG_RUNTIME_DIR/probe.log" | head -20
