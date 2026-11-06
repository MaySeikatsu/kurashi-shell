#!/usr/bin/env bash
# The colour round the focused window (I423, docs/ux/window-frame.md), on nested niri under kami, whose accent is red and whose
# outline ink is the text's: Accent writes the accent into niri's config and draws it; Shell outline writes the ink, the setting
# changes the border live, no restart; a role writes that role.
#   nix develop -c frontend/test-window-frame.sh
# Binaries from $KURASHI_BIN_DIR, else $CARGO_TARGET_DIR/debug. Shots: frontend/shots/window-frame/.
set -uo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
export KURASHI_NIRI_SB_NAME=${KURASHI_SB_PREFIX:-}window-frame
export KURASHI_NIRI_SB_OUT=${WINDOW_FRAME_OUT:-$ROOT/frontend/shots/window-frame}
OUT=$KURASHI_NIRI_SB_OUT
SB="$ROOT/tools/bench/niri-sandbox.sh"
mkdir -p "$OUT"
fail() { echo "test-window-frame: $*" >&2; "$SB" stop >/dev/null 2>&1; exit 1; }
trap '"$SB" stop >/dev/null 2>&1' EXIT

CFG=$OUT/config.toml
conf() { # conf <colour>
  printf '[idle]\nenabled = false\n\n[theme]\nstyle = "kami"\nexport = ["niri"]\nwindow_frame = true\nwindow_frame_color = "%s"\n\n[modules.windows]\npreviews = false\n[modules.workspaces]\npreviews = false\n' "$1" > "$CFG"
}
conf accent
"$SB" start "$CFG" > /dev/null || fail "the sandbox did not start"
. "$OUT/niri-env.sh"
KDL=$XDG_CONFIG_HOME/niri/kurashi.kdl
cat > "$XDG_RUNTIME_DIR/niri.kdl" <<KDL
prefer-no-csd
hotkey-overlay {
    skip-at-startup
}
layout {
    gaps 16
    background-color "#808080"
    center-focused-column "always"
    default-column-width {
        proportion 0.5
    }
    border {
        width 6
    }
}
include "xdg/config/niri/kurashi.kdl"
KDL
active() { sed -n '/^    border {/,/^    }/p' "$KDL" | sed -n 's/.*active-color *"\(#[0-9a-fA-F]*\)".*/\1/p' | head -1; }
role() { # role <name>: from the theme's token
  "$KURASHI_BIN/kurashi" --json sub theme --count 0 2>/dev/null | head -1 | jq -r ".data.tokens[\"color.$1\"]"
}
wait_active() { # wait_active <hex> <what>
  for _ in $(seq 100); do [ "$(active)" = "$1" ] && return 0; sleep 0.1; done
  fail "$2: the border's active colour is $(active), not $1"
}
KURASHI_BIN=${KURASHI_BIN_DIR:-${CARGO_TARGET_DIR:-$ROOT/target}/debug}
export KURASHI_SOCKET=${KURASHI_SOCKET:-$XDG_RUNTIME_DIR/kurashi/ipc.sock}
for _ in $(seq 100); do [ -n "$(active)" ] && break; sleep 0.1; done
ACCENT=$(active)
INK=$(role on_surface)
[ -n "$ACCENT" ] && [ "$INK" != null ] && [ -n "$INK" ] || fail "no accent ($ACCENT) or ink ($INK)"
[ "$ACCENT" != "$INK" ] || fail "kami's accent and ink should differ here"
echo "accent: $ACCENT, ink: $INK"

"$SB" spawn foot -a kstest sh -c 'sleep 60'
sleep 2
shot() { (. "$OUT/sway-env.sh"; timeout 8 grim "$OUT/$1.png"); }
# Reads the left border of the one window: the first pixel across the middle row that is not the background.
border() {
  magick "$OUT/$1.png" -crop "1920x1+0+540" +repage txt:- 2>/dev/null | awk -F'#' 'NR>1 { c=tolower(substr($2,1,6)); if (c != "808080") { print "#" c; exit } }'
}
shot accent
got=$(border accent)
[ "$got" = "$(printf '%s' "$ACCENT" | tr 'A-F' 'a-f')" ] || fail "drawn under Accent: $got, not $ACCENT"

conf shell_outline; "$SB" config "$CFG"
wait_active "$INK" "Shell outline"
sleep 1
shot outline
got=$(border outline)
[ "$got" = "$(printf '%s' "$INK" | tr 'A-F' 'a-f')" ] || fail "drawn under Shell outline: $got, not $INK"
echo "drawn: the accent, then the shell's ink, live"

conf secondary; "$SB" config "$CFG"
SECONDARY=$(role secondary)
wait_active "$SECONDARY" "Secondary"
echo "role: secondary is written"
conf accent; "$SB" config "$CFG"
wait_active "$ACCENT" "back to Accent"
echo "test-window-frame: OK"
