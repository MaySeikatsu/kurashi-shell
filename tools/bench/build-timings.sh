#!/usr/bin/env bash
# What the Rust loop costs on this machine (session 34, BACKLOG I541): a no-op build, then the three binaries after a
# touch of the daemon's `main.rs` (the link alone), of the daemon's library, of a leaf mod and of the schema, and
# `cargo check -p` after each. Touches change the files' times only; nothing is edited. A touch is the floor: an edit
# that changes a signature costs more. Run it before and after a change to the linker, a profile or the crate graph.
#
#   nix develop -c tools/bench/build-timings.sh            # the checkout's target dir
#   CARGO_TARGET_DIR=… nix develop -c tools/bench/build-timings.sh
# The lines go to stdout and to tools/bench/results/build-timings.txt.
set -uo pipefail
export LC_ALL=C
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
cd "$ROOT"
mkdir -p tools/bench/results
OUT=tools/bench/results/build-timings.txt
: > "$OUT"
run() {   # run <label> <command…>
  local label=$1 t0 rc; shift
  t0=$(date +%s%N)
  "$@" > /dev/null 2>&1; rc=$?
  printf '%7.1fs rc=%s  %s\n' "$(awk -v n=$(( ($(date +%s%N) - t0) / 1000000 )) 'BEGIN { print n / 1000 }')" "$rc" "$label" | tee -a "$OUT"
}
BINS=(-p kurashid -p kurashi -p kurashi-mock)
run "settle: the three binaries" cargo build "${BINS[@]}"
run "no-op: the three binaries" cargo build "${BINS[@]}"
touch crates/kurashid/src/main.rs
run "kurashid main.rs (the link): build -p kurashid" cargo build -p kurashid
touch crates/kurashid/src/wiring.rs
run "kurashid library: check -p kurashid" cargo check -p kurashid
run "kurashid library: build -p kurashid" cargo build -p kurashid
run "  then the mock and the CLI" cargo build "${BINS[@]}"
touch crates/kurashi-mod-timer/src/lib.rs
run "a leaf mod: check -p kurashi-mod-timer" cargo check -p kurashi-mod-timer
run "a leaf mod: the three binaries" cargo build "${BINS[@]}"
touch crates/kurashi-schema/src/v1.rs
run "the schema: the three binaries" cargo build "${BINS[@]}"
