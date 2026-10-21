#!/usr/bin/env bash
# The web dock as a phone (W21, K42), against the REAL kurashid and frontend with a theme (frontend/test-look.sh):
# the mod on, three pins (two file:// sites, a view), the first site opened — the strip's keycap app icons and the phone
# with the page on its screen — then the view pin (the shell's own phone card). Evidence to look at, not pass/fail: it
# fails on a QML error in the frontend or the host, or a host that never gets ready. Shots: mods/webdock/shots/
# phone-<tag>.png and phone-view-<tag>.png.
#   nix develop -c mods/webdock/test/test-phone.sh [tag] [config-toml-line ...]
#   e.g. mods/webdock/test/test-phone.sh sekai 'theme.style = "sekai"'
#        mods/webdock/test/test-phone.sh wa-iro 'theme.style = "none"'
# Machine B: KURASHI_RENDER_NODE first.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
TAG=${1:-sekai}
shift || true
[ $# -eq 0 ] && set -- 'theme.style = "sekai"'
PAGES=file://$ROOT/mods/webdock/test/pages
SHOTS=$ROOT/mods/webdock/shots
LOOK=$ROOT/frontend/shots/look/w21-phone-$TAG
fail() { echo "test-phone: FAIL: $*" >&2; exit 1; }

# The steps run inside test-look's sandbox, after its own (none here), with $KURASHI the sandbox's CLI.
EXTRA=$(cat <<EOF
set -e
K() { timeout 10 "\$KURASHI" "\$@"; }
doc() { K --json sub mod.webdock --count 0 | python3 -c "import json,sys; d=json.loads(sys.stdin.readline()); d=d.get('data', d); print(\$1)"; }
K act mod.enable '{"id":"webdock"}' >/dev/null
K act mod.enable '{"id":"weather"}' >/dev/null || true
K set mods.webdock.pins '[{"id":"page","title":"Page","target":"$PAGES/site.html#page"},{"id":"notes","title":"Notes","target":"$PAGES/other.html"},{"id":"weather","title":"Weather","target":"mod:weather:weather"}]' >/dev/null
sleep 1
K act webdock.open '{"pin":"page"}' >/dev/null
for i in \$(seq 120); do [ "\$(doc "d['host']['state'] == 'ready' and [p for p in d['pins'] if p['id'] == 'page'][0].get('loaded') == True")" = True ] && break; sleep 0.5; done
[ "\$(doc "d['host']['state']")" = ready ] || { echo "test-phone: the host never got ready" >&2; exit 1; }
sleep 3
grim "$LOOK/phone.png"
K act webdock.open '{"pin":"weather"}' >/dev/null
sleep 2
grim "$LOOK/phone-view.png"
cp "\$XDG_STATE_HOME/kurashi/webdock/host-web.log" "$LOOK/host-web.log" 2>/dev/null || true
EOF
)
mkdir -p "$LOOK"
rm -f "$LOOK/phone.png" "$LOOK/phone-view.png" "$LOOK/host-web.log"
LOOK_STEPS="none" LOOK_EXTRA="$EXTRA" "$ROOT/frontend/test-look.sh" "w21-phone-$TAG" "$@"
[ -s "$LOOK/phone.png" ] || fail "no phone shot (the host did not get ready?)"
if [ -f "$LOOK/host-web.log" ] && grep -E 'qml:.*(Error|error)|TypeError|ReferenceError|is not a type' "$LOOK/host-web.log" >/dev/null; then
  grep -E 'Error|error' "$LOOK/host-web.log" | head -20 >&2
  fail "QML errors in the host (see $LOOK/host-web.log)"
fi
cp "$LOOK/phone.png" "$SHOTS/phone-$TAG.png"
cp "$LOOK/phone-view.png" "$SHOTS/phone-view-$TAG.png"
echo "test-phone: ok: $SHOTS/phone-$TAG.png, $SHOTS/phone-view-$TAG.png"
