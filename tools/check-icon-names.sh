#!/bin/sh
# The icon names the shell draws are all in the icon subset (W41, row 446): nix/icon-names.txt must be what
# nix/icon-names.py finds in frontend/, settings/, mods/ and crates/ against the Material Symbols font. A name missing
# from the list is drawn from the full family at run time (Icon.qml's fallback) instead of the subset, which is the
# cost the subset exists to avoid. Needs `nix develop` (python3 with fontTools; the font is under XDG_DATA_DIRS).
# `just check` runs it.
set -eu
root=$(cd "$(dirname "$0")/.." && pwd)

font=
for d in $(printf '%s' "${XDG_DATA_DIRS:-}" | tr ':' ' '); do
    font=$(find "$d" -name 'MaterialSymbolsRounded*.ttf' 2>/dev/null | head -n 1)
    [ -n "$font" ] && break
done
[ -n "$font" ] || { echo "check-icon-names: no MaterialSymbolsRounded font under XDG_DATA_DIRS (run in nix develop)" >&2; exit 1; }

tmp=$(mktemp "${TMPDIR:-/tmp}/check-icon-names.XXXXXX")
trap 'rm -f "$tmp"' EXIT
python3 -I "$root/nix/icon-names.py" "$font" "$root" > "$tmp"
if ! diff -u "$root/nix/icon-names.txt" "$tmp"; then
    echo "check-icon-names: nix/icon-names.txt is stale; regenerate it with nix/icon-names.py (its header has the command)" >&2
    exit 1
fi
echo "check-icon-names: nix/icon-names.txt is current ($(grep -cv '^#' "$tmp") names)"
