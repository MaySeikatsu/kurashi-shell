#!/usr/bin/env bash
# The web dock end to end against the REAL kurashid (K38): the mod enabled, pins set through the config (records),
# `webdock.open` → the daemon starts `qs-webengine` (host:web) with a scoped token → the host connects, loads the
# file:// page and reports `loaded`; the view toggle writes the pin through the settings writer (undoable); a forged
# scope is refused; disabling the mod stops the host. Headless sway sandbox, no network (K37), isolated XDG dirs.
#   nix develop -c mods/webdock/test/test-real.sh [sandbox-name]
#   KURASHI_BIN_DIR=<dir with kurashid + kurashi> (default: ${CARGO_TARGET_DIR:-target}/debug)
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
NAME=${1:-webdock-real}
BIN=${KURASHI_BIN_DIR:-${CARGO_TARGET_DIR:-$ROOT/target}/debug}
SHOTS=$ROOT/mods/webdock/shots
PAGES=file://$ROOT/mods/webdock/test/pages

fail() { echo "test-real: FAIL: $*" >&2; exit 1; }
ok() { echo "test-real: ok: $*"; }

eval "$("$ROOT/tools/bench/sandbox.sh" start "$NAME")"
R=$XDG_RUNTIME_DIR
W=$R/work
mkdir -p "$W" "$R/kurashi"
cp "$BIN/kurashid" "$BIN/kurashi" "$W/"
DPID=
cleanup() {
  [ -n "$DPID" ] && kill "$DPID" 2>/dev/null || true
  "$ROOT/tools/bench/sandbox.sh" stop "$NAME" >/dev/null || true
}
trap cleanup EXIT
export XDG_CONFIG_HOME=$R/xdg/config XDG_STATE_HOME=$R/xdg/state \
       XDG_DATA_HOME=$R/xdg/data XDG_CACHE_HOME=$R/xdg/cache KURASHI_DATA_DIR=$ROOT
mkdir -p "$XDG_CONFIG_HOME" "$XDG_STATE_HOME" "$XDG_DATA_HOME" "$XDG_CACHE_HOME"
K() { "$W/kurashi" "$@"; }
# One field of mod.webdock: doc <python expression over d>.
doc() { K --json sub mod.webdock --count 0 | python3 -c "import json,sys; d=json.loads(sys.stdin.readline()); d=d.get('data', d); print($1)"; }
wait_doc() {
  local i
  for i in $(seq $(($2 * 2))); do [ "$(doc "$1" 2>/dev/null)" = True ] && return 0; sleep 0.5; done
  return 1
}
# Host processes of this sandbox: qs-webengine's Quickshell with the scope in its environment.
hosts() {
  local p
  for p in $(pgrep -u "$USER" -f 'webdock/host/shell.qml' || true); do
    grep -qs "KURASHI_SCOPE_MOD=webdock" /proc/$p/environ && grep -qs "$R" /proc/$p/environ && echo "$p"
  done
}

command -v qs-webengine >/dev/null || fail "qs-webengine not on PATH (nix develop)"
DBUS_SYSTEM_BUS_ADDRESS="unix:path=$R/no-system-bus" "$W/kurashid" >> "$R/kurashid.log" 2>&1 &
DPID=$!
for _ in $(seq 100); do [ -S "$KURASHI_SOCKET" ] && K ping >/dev/null 2>&1 && break; sleep 0.1; done
K ping >/dev/null 2>&1 || fail "kurashid did not come up ($R/kurashid.log)"

K act mod.enable '{"id":"webdock"}' >/dev/null || fail "mod.enable webdock"
K set mods.webdock.pins "[{\"id\":\"page\",\"title\":\"Page\",\"target\":\"$PAGES/site.html#page\"},{\"id\":\"weather\",\"title\":\"Weather\",\"target\":\"mod:weather:weather\"}]" >/dev/null \
  || fail "the pins were refused"
K set mods.webdock.pins '[{"id":"Bad Id","title":"x","target":"ftp://x"}]' >/dev/null 2>&1 && fail "a bad pin was accepted"
ok "pins set through the config; a bad pin refused"
wait_doc "[p['kind'] for p in d['pins']] == ['web', 'view']" 5 || fail "pin kinds: $(doc "d['pins']")"
[ "$(doc "d['host']['state']")" = off ] || fail "the host runs before any site is shown"
[ -z "$(hosts)" ] || fail "a host process before any site is shown"

K act webdock.open '{"pin":"weather"}' >/dev/null
sleep 1
[ -z "$(hosts)" ] || fail "a view pin started the host"
ok "a view pin does not start the web engine"

K act webdock.open '{"pin":"page"}' >/dev/null
wait_doc "d['host']['state'] == 'ready'" 60 || fail "the host never got ready: $(doc "d['host']") ($R/xdg/state/kurashi/webdock/host-web.log)"
wait_doc "[p for p in d['pins'] if p['id'] == 'page'][0].get('loaded') == True" 60 || fail "the page never reported loaded"
[ "$(hosts | wc -l)" = 1 ] || fail "expected one host process, found: $(hosts | tr '\n' ' ')"
sleep 2
grim -o HEADLESS-1 "$SHOTS/real-open.png" || fail "grim"
ok "webdock.open → the daemon started the host, it connected with its scope and loaded the page (shots/real-open.png)"

K act webdock.view '{"pin":"page","view":"desktop"}' >/dev/null || fail "webdock.view"
K --json get mods.webdock.pins | grep -q '"view":"desktop"' || fail "the view was not written to the pin: $(K --json get mods.webdock.pins)"
wait_doc "[p for p in d['pins'] if p['id'] == 'page'][0]['view'] == 'desktop'" 5 || fail "the document did not follow the view"
K undo >/dev/null || fail "undo"
wait_doc "[p for p in d['pins'] if p['id'] == 'page'][0]['view'] == 'mobile'" 5 || fail "undo did not bring the view back"
ok "the view toggle writes the pin (settings writer) and undoes"

# A first hello with a token the daemon never issued (the CLI's `raw` greets first, so a socket of our own).
reply=$(python3 -I -c '
import json, os, socket
s = socket.socket(socket.AF_UNIX); s.connect(os.environ["KURASHI_SOCKET"])
s.sendall(b"{\"t\":\"hello\",\"v\":1,\"client\":\"forged\",\"scope\":{\"mod\":\"webdock\",\"token\":\"0000\"}}\n")
print(s.makefile().readline().strip())' 2>&1 || true)
echo "$reply" | grep -q '"reason":"scope"' || fail "a forged scope was not refused: $reply"
ok "a forged scope is refused (goodbye scope)"

K act mod.disable '{"id":"webdock"}' >/dev/null || fail "mod.disable"
for _ in $(seq 50); do [ -z "$(hosts)" ] && break; sleep 0.1; done
[ -z "$(hosts)" ] || fail "the host outlived the mod: $(hosts | tr '\n' ' ')"
ok "disabling the mod stops the host"
echo "test-real: PASS"
