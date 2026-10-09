#!/usr/bin/env bash
# Rebuild the archived bake-off probes exactly as their READMEs say (no source changes), in parallel.
# Compile phase only — measure afterwards with tools/bench/rerun-probes.sh on a quiet machine.
#   tools/bench/build-probes.sh        (from anywhere inside the repo; needs nix with flakes)
set -uo pipefail
R=$(git -C "$(dirname "$0")" rev-parse --show-toplevel)
P=$R/archive/bakeoff-probes
L=$R/tools/bench/results/logs
mkdir -p "$L"
unset CARGO_TARGET_DIR
export CARGO_INCREMENTAL=0
J=${JOBS:-4}
( cd "$P/iced"  && timeout 3600 nix develop -c cargo build --release -j"$J" > "$L/build-iced.log" 2>&1; echo "iced rc=$?" ) &
( cd "$P/slint" && timeout 3600 nix develop -c cargo build --release -j"$J" > "$L/build-slint.log" 2>&1; echo "slint rc=$?" ) &
( cd "$R" && timeout 3600 nix build "$P/gtk4" -o "$P/gtk4/result" > "$L/build-gtk4.log" 2>&1; echo "gtk4 rc=$?" ) &
( cd "$R" && timeout 3600 nix develop "$P/gpui" -c cargo build --release -j"$J" --manifest-path "$P/gpui/Cargo.toml" > "$L/build-gpui.log" 2>&1; echo "gpui rc=$?" ) &
wait
# gpui's run.sh caches its devshell env on first run; create it now so no nix runs mid-measurement.
( cd "$P/gpui" && [ -s .env.cache ] || nix develop . -c bash -c 'echo "export FONTCONFIG_FILE=$FONTCONFIG_FILE"; echo "export LD_LIBRARY_PATH=$LD_LIBRARY_PATH"' > .env.cache 2>/dev/null )
echo "logs: $L"
