#!/usr/bin/env bash
# Run command for the probe: sets fonts + library path from the nix devShell (cached), execs binary.
here=$(cd "$(dirname "$0")" && pwd)
cache=$here/.env.cache
if [ ! -s "$cache" ]; then
  nix develop "$here" -c bash -c 'echo "export FONTCONFIG_FILE=$FONTCONFIG_FILE"; echo "export LD_LIBRARY_PATH=$LD_LIBRARY_PATH"' > "$cache"
fi
. "$cache"
exec "$here/target/release/probe-gpui" "$@"
