#!/usr/bin/env bash
# Zen and Firefox (I422, K100, docs/ux/browsers.md), the daemon against profiles in a HOME of the suite's own, never the real one:
#   profiles  svc.theme_export lists Zen's from its profiles.ini, the one it opens first, and Firefox's; none is hardcoded
#   link      the action writes the import first in a profile's userChrome.css and the prefs in a marked block of its user.js,
#             keeping what was there; a toggle moves the prefs; Unlink takes back exactly that
#   css       Zen's layers, not :root variables, carry the colour and the tile; translucent drops the tile and asks for its pref
#   nix develop -c frontend/test-browsers.sh
# Binaries from $KURASHI_BIN_DIR, else $CARGO_TARGET_DIR/debug.
set -uo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
export KURASHI_NIRI_SB_NAME=${KURASHI_SB_PREFIX:-}browsers
export KURASHI_NIRI_SB_OUT=${BROWSERS_OUT:-$ROOT/frontend/shots/browsers}
OUT=$KURASHI_NIRI_SB_OUT
SB="$ROOT/tools/bench/niri-sandbox.sh"
mkdir -p "$OUT"
fail() { echo "test-browsers: $*" >&2; "$SB" stop >/dev/null 2>&1; exit 1; }
trap '"$SB" stop >/dev/null 2>&1' EXIT
# The daemon's HOME: the action writes under it.
FAKE=$OUT/home
rm -rf "$FAKE"
mkdir -p "$FAKE/.zen/aaa.default/chrome" "$FAKE/.zen/bbb.work" "$FAKE/.mozilla/firefox/ccc.me"
printf '[General]\nVersion=2\n\n[Profile0]\nName=work\nIsRelative=1\nPath=bbb.work\n\n[Profile1]\nName=default\nIsRelative=1\nPath=aaa.default\nDefault=1\n' > "$FAKE/.zen/profiles.ini"
printf '[Install123]\nDefault=ccc.me\nLocked=1\n\n[Profile0]\nName=me\nIsRelative=1\nPath=ccc.me\n' > "$FAKE/.mozilla/firefox/profiles.ini"
printf '/* mine */\n#foo { color: red }\n' > "$FAKE/.zen/aaa.default/chrome/userChrome.css"
printf 'user_pref("mine", 1);\n' > "$FAKE/.zen/aaa.default/user.js"
CFG=$OUT/config.toml
conf() { # conf <translucent true|false> <pages true|false>
  printf '[idle]\nenabled = false\n\n[theme]\nstyle = "washi"\nexport = ["zen","firefox"]\nbrowser_translucent = %s\nbrowser_translucent_pages = %s\n\n[theme.texture]\nkind = "paper"\nscope = "shell"\n\n[desktop]\nenabled = false\n\n[modules.windows]\npreviews = false\n[modules.workspaces]\npreviews = false\n' "$1" "$2" > "$CFG"
}
conf false false
HOME="$FAKE" "$SB" start "$CFG" > /dev/null || fail "the sandbox did not start"
. "$OUT/niri-env.sh"
C=$XDG_CONFIG_HOME
doc() { "$SB" act --json sub svc.theme_export --count 0 2>/dev/null | head -1; }
list() { doc | jq -r ".data.targets[] | select(.name==\"$1\") | .profiles.list | map(.name + (if .default then \"*\" else \"\" end) + (if .linked then \"+\" else \"\" end)) | join(\" \")"; }
until_list() { local got=; for _ in $(seq 100); do got=$(list "$1"); [ "$got" = "$2" ] && return 0; sleep 0.2; done; fail "$1's profiles: '$got', not '$2'"; }
until_list zen "default* work"
until_list firefox "me*"
echo "profiles: from each browser's own ini, the one it opens first"

ZCSS=$FAKE/.zen/aaa.default/chrome/userChrome.css
ZJS=$FAKE/.zen/aaa.default/user.js
"$SB" act act theme.export.link '{"target":"nobody","profile":"default"}' > /dev/null 2>&1 && fail "linked a target that is no browser"
"$SB" act act theme.export.link '{"target":"zen","profile":"nobody"}' > /dev/null 2>&1 && fail "linked a profile that is not in the ini"
"$SB" act act theme.export.link '{"target":"zen","profile":"default","on":true}' > /dev/null || fail "the link action"
until_list zen "default*+ work"
sed -n 1p "$ZCSS" | grep -q "^@import url(\"file://$C/kurashi/apps/zen.css\");" || fail "the import is not first: $(sed -n 1p "$ZCSS")"
grep -q '#foo { color: red }' "$ZCSS" || fail "the user's rule went"
grep -q 'user_pref("mine", 1);' "$ZJS" || fail "the user's pref went"
grep -q 'legacyUserProfileCustomizations.stylesheets", true' "$ZJS" || fail "no stylesheets pref"
[ ! -e "$FAKE/.zen/bbb.work/chrome/userChrome.css" ] || fail "the other profile was touched"
echo "link: the import first, the prefs marked, the rest kept, the other profile alone"

Z=$C/kurashi/apps/zen.css
for _ in $(seq 100); do [ -s "$C/kurashi/apps/zen-tile.png" ] && grep -q 'zen-tile.png' "$Z" && break; sleep 0.2; done
grep -q 'zen-tile.png' "$Z" || fail "no tile in zen.css"
grep -q '.zen-browser-generic-background::after' "$Z" || fail "not on Zen's layers"
grep -q -- '--zen-border-radius: 9px' "$Z" || fail "no corners: $(grep -n radius "$Z" | head -3)"
conf true true; "$SB" config "$CFG"
for _ in $(seq 100); do grep -q 'zen.widget.linux.transparency", true' "$ZJS" && break; sleep 0.2; done
grep -q 'zen.widget.linux.transparency", true' "$ZJS" || fail "a linked profile did not get the transparency pref"
grep -q 'allow_transparent_browser", true' "$ZJS" || fail "no pages pref"
grep -q 'zen-tile.png' "$Z" && fail "the tile would close what translucency opens"
grep -q 'browser\[type="content"\]' "$Z" || fail "no translucent pages"
[ "$(grep -c 'kurashi: begin' "$ZJS")" = 1 ] || fail "the block piled up"
conf false false; "$SB" config "$CFG"
for _ in $(seq 100); do grep -q 'zen.widget.linux.transparency' "$ZJS" || break; sleep 0.2; done
grep -q 'zen.widget.linux.transparency' "$ZJS" && fail "the pref stayed after the toggle"
echo "css: Zen's layers, corners, a tile; translucent drops it and asks for the pref; a toggle moves it"

"$SB" act act theme.export.link '{"target":"zen","profile":"default","on":false}' > /dev/null || fail "the unlink action"
until_list zen "default* work"
[ "$(cat "$ZCSS")" = "$(printf '/* mine */\n#foo { color: red }')" ] || fail "Unlink left the css otherwise: $(cat "$ZCSS")"
[ "$(cat "$ZJS")" = 'user_pref("mine", 1);' ] || fail "Unlink left user.js otherwise: $(cat "$ZJS")"
echo "unlink: back to what the user had, byte for byte"
echo "test-browsers: OK"
