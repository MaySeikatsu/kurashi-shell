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
conf() { # conf <terminals true|false> [mono true|false]
  printf '[idle]\nenabled = false\n\n[theme]\nstyle = "washi"\nexport_fonts = %s\nexport = ["foot","kitty","alacritty","ghostty","wezterm","rio","ratty"]\n\n[theme.typography]\nmono = ["JetBrains Mono", "DejaVu Sans Mono", "monospace"]\n\n[theme.texture]\nkind = "paper"\nscope = "shell"\nterminals = %s\n\n[desktop]\nenabled = false\n\n[modules.windows]\npreviews = false\n[modules.workspaces]\npreviews = false\n' "${2:-false}" "$1" > "$CFG"
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

# ---- the monospaced font (K104): only while Monospaced font in apps is on, each terminal in its own syntax ----
printf '[main]\nfont=Some Font:size=13\ninclude=%s\n' "$C/foot/kurashi-colors.ini" > "$C/foot/foot.ini"
grep -q '^font-family' "$C/ghostty/themes/kurashi" && fail "a font in ghostty's theme while it is off"
grep -q 'M.font = nil' "$C/wezterm/kurashi.lua" || fail "wezterm names a font while it is off"
conf true true; "$SB" config "$CFG"
for _ in $(seq 100); do
  F=$("$SB" act --json sub svc.theme_export --count 0 2>/dev/null | head -1 | jq -r '.data.targets[] | select(.name=="kitty") | .font.family // empty')
  [ -n "$F" ] && break; sleep 0.2
done
[ -n "${F:-}" ] || fail "kitty does not say it takes the font"
for t in rio ratty; do
  why=$("$SB" act --json sub svc.theme_export --count 0 2>/dev/null | head -1 | jq -r ".data.targets[] | select(.name==\"$t\") | .font.why // empty")
  [ "$why" = unsupported ] || fail "$t: '$why', not unsupported"
done
for _ in $(seq 50); do grep -q "font_family $F" "$C/kitty/kurashi-colors.conf" && break; sleep 0.2; done
grep -q "font_family $F" "$C/kitty/kurashi-colors.conf" || fail "kitty's font line"
grep -q "^font-family = \"$F\"" "$C/ghostty/themes/kurashi" || fail "ghostty's font line"
grep -q "M.font = require('wezterm').font('$F')" "$C/wezterm/kurashi.lua" || fail "wezterm's font"
grep -q "^font=$F:size=13$" "$C/foot/kurashi-colors.ini" || fail "foot's font, at the user's size: $(grep -n font "$C/foot/kurashi-colors.ini")"
grep -A1 '^\[font.normal\]' "$C/alacritty/kurashi-colors.toml" | grep -q "family = \"$F\"" || fail "alacritty's font"
foot --check-config --config="$C/foot/kurashi-colors.ini" 2>&1 | grep -q . && fail "foot refuses its file with the font"
if command -v ghostty > /dev/null; then
  printf 'theme = kurashi\nfont-family = "Mine"\n' > "$C/ghostty/config"
  first=$(XDG_CONFIG_HOME=$C ghostty +show-config 2>/dev/null | grep -m1 '^font-family = ' | sed 's/^font-family = //')
  [ "$first" = "$F" ] || fail "ghostty's first font is '$first', not $F"
fi
echo "mono: $F in ghostty, kitty, wezterm, foot (at its own size), alacritty; rio and ratty say why not"
conf true false; "$SB" config "$CFG"
for _ in $(seq 100); do grep -q 'M.font = nil' "$C/wezterm/kurashi.lua" && break; sleep 0.2; done
grep -q "font_family" "$C/kitty/kurashi-colors.conf" && fail "kitty keeps the font when it is off"
grep -q 'font-family' "$C/ghostty/themes/kurashi" && fail "ghostty keeps the font when it is off"
echo "mono off: every terminal keeps its own"
echo "test-terminals: OK"
