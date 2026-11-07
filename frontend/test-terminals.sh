#!/usr/bin/env bash
# The material in terminals (I420, K99, docs/ux/terminal-texture.md), by the daemon alone in the invisible sandbox, against the real files:
#   who     Ghostty a shader, Kitty and WezTerm a tile, the others colours, and the document says so
#   switch  theme.texture.terminals off: no shader line, no picture line, every terminal colours, why named
#   foot    the file passes `foot --check-config` (foot 1.28 refused [colors]); ghostty validates when it is here
#   ratty   the shell keeps a ratty.toml of its own; one of the user's stays and the document says so
#   nix develop -c frontend/test-terminals.sh
# Binaries from $KURASHI_BIN_DIR, else $CARGO_TARGET_DIR/debug.
set -uo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
export KURASHI_NIRI_SB_NAME=${KURASHI_SB_PREFIX:-}terminals
export KURASHI_NIRI_SB_OUT=${TERMINALS_OUT:-$ROOT/frontend/shots/terminals}
OUT=$KURASHI_NIRI_SB_OUT
SB="$ROOT/tools/bench/niri-sandbox.sh"
mkdir -p "$OUT"
fail() { echo "test-terminals: $*" >&2; "$SB" stop >/dev/null 2>&1; exit 1; }
trap '"$SB" stop >/dev/null 2>&1' EXIT
CFG=$OUT/config.toml
conf() { # conf <terminals true|false>
  printf '[idle]\nenabled = false\n\n[theme]\nstyle = "washi"\nexport = ["foot","kitty","alacritty","ghostty","wezterm","rio","ratty"]\n\n[theme.texture]\nkind = "paper"\nscope = "shell"\nterminals = %s\n\n[desktop]\nenabled = false\n\n[modules.windows]\npreviews = false\n[modules.workspaces]\npreviews = false\n' "$1" > "$CFG"
}
conf true
"$SB" start "$CFG" > /dev/null || fail "the sandbox did not start"
. "$OUT/niri-env.sh"
C=$XDG_CONFIG_HOME
how() { "$SB" act --json sub svc.theme_export --count 0 2>/dev/null | head -1 | jq -r ".data.targets[] | select(.name==\"$1\") | .material.how + \":\" + (.material.why // \"\")"; }
until_how() { # until_how <target> <how:why>
  local got=
  for _ in $(seq 150); do got=$(how "$1"); [ "$got" = "$2" ] && return 0; sleep 0.2; done
  fail "$1 takes $got, not $2"
}
until_how ghostty shader:
until_how kitty image:
until_how wezterm image:
for t in foot alacritty rio ratty; do until_how "$t" colours:; done
[ -s "$C/kitty/kurashi-tile.png" ] || fail "no tile for kitty"
grep -q 'background_image_layout tiled' "$C/kitty/kurashi-colors.conf" || fail "kitty's lines"
grep -q "repeat_x = 'Repeat'" "$C/wezterm/kurashi.lua" || fail "wezterm's table"
grep -q 'custom-shader' "$C/ghostty/themes/kurashi" || fail "ghostty's shader line"
echo "who: a shader, two tiles, colours for the rest"

foot --check-config --config="$C/foot/kurashi-colors.ini" 2>&1 | grep -q . && fail "foot refuses its file: $(foot --check-config --config="$C/foot/kurashi-colors.ini" 2>&1 | head -2)"
if command -v ghostty > /dev/null; then
  mkdir -p "$C/ghostty"; printf 'theme = kurashi\n' > "$C/ghostty/config"
  ghostty +validate-config 2>&1 | grep -iE 'error' && fail "ghostty refuses its theme"
fi
echo "foot: passes its own check"

conf false; "$SB" config "$CFG"
until_how ghostty off:switch
until_how kitty off:switch
until_how wezterm off:switch
grep -q 'background_image ' "$C/kitty/kurashi-colors.conf" && fail "kitty keeps its picture under the switch"
grep -q 'M.background = nil' "$C/wezterm/kurashi.lua" || fail "wezterm keeps its picture under the switch"
grep -q 'custom-shader =' "$C/ghostty/themes/kurashi" && fail "ghostty keeps its shader under the switch"
echo "switch: colours alone, and why"

grep -q '^\[theme\]' "$C/ratty/ratty.toml" || fail "no ratty.toml from the shell"
printf '[theme]\nbackground = "#000000"\n' > "$C/ratty/ratty.toml"
conf true; "$SB" config "$CFG"
for _ in $(seq 100); do
  own=$("$SB" act --json sub svc.theme_export --count 0 2>/dev/null | head -1 | jq -r '.data.targets[] | select(.name=="ratty") | .own_config.file // empty')
  [ -n "$own" ] && break; sleep 0.2
done
[ -n "${own:-}" ] || fail "the document does not say ratty.toml is the user's"
grep -q '#000000' "$C/ratty/ratty.toml" || fail "the user's ratty.toml was written over"
echo "ratty: its config is the shell's while it has none; the user's stays"
echo "test-terminals: OK"
