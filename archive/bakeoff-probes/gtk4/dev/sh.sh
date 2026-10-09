#!/usr/bin/env bash
# Dev helper: run a command inside sandbox "gtk4" env.  usage: dev/sh.sh grim x.png | dev/sh.sh kurashi act ...
ROOT=$(git rev-parse --show-toplevel)
source <("$ROOT/tools/bench/sandbox.sh" env gtk4)
cmd=$1; shift
[ "$cmd" = kurashi ] && cmd=$ROOT/target/release/kurashi
exec "$cmd" "$@"
