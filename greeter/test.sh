#!/usr/bin/env bash
# The greeter (W28, docs/ux/greeter.md), invisibly, in the headless sway sandbox against a fake greetd
# (greeter/fake_greetd.py) — never a real greetd, never /etc. Users come from a fake passwd, sessions from a fake
# wayland-sessions folder, the power command is a script that only logs. The look is the real kurashid's greeter cache:
# per decor (sekai, none) kurashid runs once with USER=tester and the shared slots the NixOS module would make
# (KURASHI_GREETER_DIR), and must fill them.
# Per decor: the greeter as it opens; a wrong password → greetd's auth error, the message, the field shakes and
# clears; sekai: the user list open, the suspend key (logged by the fake command); none: the session chip set to Sway
# by keyboard; then the right password → start_session with the chosen session's command, the memory file written,
# the greeter quits.
# Screenshots (greeter/shots/): greeter-{open,wrong}-{sekai,none}.png, greeter-users-sekai.png,
# greeter-sessions-none.png.
#   KURASHI_RENDER_NODE=/dev/dri/renderD129 KURASHI_BIN_DIR=<dir with kurashid> \
#     timeout 900 nix develop -c greeter/test.sh [sandbox-name]
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
NAME=${1:-w28-grt-test}
BIN=${KURASHI_BIN_DIR:-${CARGO_TARGET_DIR:-$ROOT/target}/debug}
OUT=$ROOT/greeter/shots
DECORS=${DECORS:-sekai none}
PASS=kurashi-test-pass
export KURASHI_RENDER_NODE=${KURASHI_RENDER_NODE:-/dev/dri/renderD129}
mkdir -p "$OUT"
FAILS=0
CHECKS=0
fail() { echo "greeter/test.sh: $*" >&2; exit 1; }
check() { # check <0|1> <label>
  CHECKS=$((CHECKS + 1))
  if [ "$1" = 1 ]; then echo "ok: $2"; else echo "FAIL: $2"; FAILS=$((FAILS + 1)); fi
}
[ -x "$BIN/kurashid" ] || fail "no kurashid in $BIN (cargo build -p kurashid, or set KURASHI_BIN_DIR)"

eval "$("$ROOT/tools/bench/sandbox.sh" start "$NAME")"
R=$XDG_RUNTIME_DIR
W=$R/work
rm -rf "$W"
mkdir -p "$W"
cp "$BIN/kurashid" "$W/"
for _ in $(seq 150); do timeout 5 swaymsg -t get_outputs >/dev/null 2>&1 && break; sleep 0.2; done
timeout 5 swaymsg -t get_outputs >/dev/null 2>&1 || fail "the headless compositor does not answer (see $R/sway.log)"

FPID=""
QPID=""
DPID=""
stop() { if [ -n "${!1}" ]; then kill "${!1}" 2>/dev/null || true; wait "${!1}" 2>/dev/null || true; fi; printf -v "$1" ''; }
cleanup() {
  stop QPID
  stop FPID
  stop DPID
  "$ROOT/tools/bench/sandbox.sh" stop "$NAME" >/dev/null || true
}
trap cleanup EXIT

export XDG_CONFIG_HOME=$R/xdg/config XDG_STATE_HOME=$R/xdg/state XDG_DATA_HOME=$R/xdg/data XDG_CACHE_HOME=$R/xdg/cache
export KURASHI_DATA_DIR=$ROOT LC_ALL=C.UTF-8
keys() { timeout 30 python3 -I "$ROOT/tools/bench/wl_keys.py" "$@" >> "$R/keys.log" 2>&1 || true; }
shot() { sleep "${WAIT:-1.2}"; grim "$OUT/$1.png"; [ -s "$OUT/$1.png" ] || fail "empty screenshot $1"; echo "shot $1"; }

# The system the greeter sees: two people, a service account and a nologin account (both hidden), two sessions and a
# hidden one.
cat > "$W/passwd" <<'EOF'
root:x:0:0:System administrator:/root:/bin/sh
greeter:x:999:999::/var/empty:/bin/sh
tester:x:1000:100:Tess Tester:/home/tester:/run/current-system/sw/bin/bash
guest:x:1001:100::/home/guest:/bin/sh
nixbld1:x:30001:30000:Nix build user 1:/var/empty:/run/current-system/sw/bin/nologin
EOF
mkdir -p "$W/sessions"
printf '[Desktop Entry]\nName=Niri\nExec=niri-session\nDesktopNames=niri\nType=Application\n' > "$W/sessions/niri.desktop"
printf '[Desktop Entry]\nName=Sway\nExec=sway --unsupported-gpu %%U\nDesktopNames=sway\n' > "$W/sessions/sway.desktop"
printf '[Desktop Entry]\nName=Hidden\nExec=hidden\nHidden=true\n' > "$W/sessions/hidden.desktop"
printf '#!/bin/sh\necho "$@" >> %s/power.log\n' "$W" > "$W/power"
chmod +x "$W/power"

# log_has <python expression over e (one log entry)>: some entry of the fake greetd's log matches.
log_has() {
  python3 -I -c "
import json, sys
for line in open('$W/greetd.log'):
    e = json.loads(line)
    if $1:
        sys.exit(0)
sys.exit(1)" 2>/dev/null
}
wait_for() { local i; for i in $(seq "$2"); do eval "$1" && return 0; sleep 0.25; done; return 1; }

cache_for() { # cache_for <decor>: the real kurashid fills the greeter slots for user tester
  stop DPID
  rm -rf "$R/xdg" "$W/gdir"
  mkdir -p "$XDG_CONFIG_HOME/kurashi" "$XDG_STATE_HOME" "$W/gdir"
  : > "$W/gdir/tester.json"
  printf 'theme.style = "%s"\n' "$1" > "$XDG_CONFIG_HOME/kurashi/config.toml"
  env USER=tester KURASHI_GREETER_DIR="$W/gdir" KURASHI_SOCKET="$R/kurashi-cache.sock" \
    DBUS_SYSTEM_BUS_ADDRESS="unix:path=$R/no-system-bus" PULSE_SERVER="unix:$R/no-pulse/native" \
    "$W/kurashid" >> "$R/kurashid.log" 2>&1 &
  DPID=$!
  wait_for '[ -s "$W/gdir/tester.json" ]' 60 || true
  stop DPID
  check "$( [ -s "$W/gdir/tester.json" ] && python3 -I -c "
import json, sys
d = json.load(open('$W/gdir/tester.json'))
sys.exit(0 if d['user'] == 'tester' and d['tokens'].get('color.accent') and d['locale'] else 1)" && echo 1 || echo 0)" \
    "$1 kurashid filled the greeter slot (tokens, user, locale)"
  check "$( [ -s "$XDG_STATE_HOME/kurashi/greeter-theme.json" ] && echo 1 || echo 0)" "$1 kurashid wrote its own copy in XDG_STATE_HOME"
}

start_greeter() {
  stop QPID
  stop FPID
  rm -f "$W/greetd.log" "$W/greetd.sock"
  python3 -I "$ROOT/greeter/fake_greetd.py" "$W/greetd.sock" "$W/greetd.log" "$PASS" tester,guest &
  FPID=$!
  wait_for '[ -S "$W/greetd.sock" ]' 40 || fail "the fake greetd did not start"
  env GREETD_SOCK="$W/greetd.sock" KURASHI_GREETER_DIR="$W/gdir" KURASHI_GREETER_PASSWD="$W/passwd" \
    KURASHI_GREETER_SESSIONS="$W/sessions:$W/no-such-dir" KURASHI_GREETER_POWER="$W/power" KURASHI_GREETER_TIME=09:41 \
    KURASHI_SOCKET="$R/no-daemon.sock" qs -p "$ROOT/greeter/shell.qml" >> "$R/qs.log" 2>&1 &
  QPID=$!
  sleep "${GREETER_WAIT:-4}"
  kill -0 "$QPID" 2>/dev/null || fail "the greeter exited at start (see $R/qs.log)"
}
type_secret() { local s=$1 t=(); for ((i = 0; i < ${#s}; i++)); do c=${s:i:1}; [ "$c" = - ] && c=minus; t+=("$c"); done; keys "${t[@]}" return; }

for DECOR in $DECORS; do
  echo "== $DECOR"
  cache_for "$DECOR"
  rm -f "$W/gdir/memory.json" "$W/power.log"
  start_greeter
  shot "greeter-open-$DECOR"
  type_secret wrong
  wait_for 'log_has "e[\"type\"] == \"post_auth_message_response\" and e[\"ok\"] is False"' 40 || true
  check "$(log_has 'e["type"] == "create_session" and e["username"] == "tester"' && echo 1 || echo 0)" "$DECOR the remembered-or-first user (tester) opens a greetd session"
  check "$(log_has 'e["type"] == "post_auth_message_response" and e["ok"] is False' && echo 1 || echo 0)" "$DECOR a wrong password reaches greetd and fails"
  wait_for 'log_has "e[\"type\"] == \"cancel_session\""' 20 || true
  check "$(log_has 'e["type"] == "cancel_session"' && echo 1 || echo 0)" "$DECOR the failed session is cancelled"
  shot "greeter-wrong-$DECOR"
  if [ "$DECOR" = sekai ]; then
    keys tab return
    shot "greeter-users-sekai"
    keys escape escape
    # Tab: field → user → session → suspend.
    keys tab tab tab return
    wait_for '[ -s "$W/power.log" ]' 20 || true
    check "$(grep -qx suspend "$W/power.log" 2>/dev/null && echo 1 || echo 0)" "sekai the suspend key runs the power command (suspend)"
    keys escape
    WANT='["niri-session"]'
  else
    # The session chip by keyboard: Tab Tab, open, down to Sway, pick.
    keys tab tab return
    shot "greeter-sessions-none"
    keys down return
    WANT='["sway", "--unsupported-gpu"]'
  fi
  type_secret "$PASS"
  wait_for 'log_has "e[\"type\"] == \"start_session\""' 40 || true
  check "$(log_has 'e["type"] == "post_auth_message_response" and e["ok"] is True' && echo 1 || echo 0)" "$DECOR the right password authenticates"
  check "$(log_has "e['type'] == 'start_session' and e['authed'] and e['cmd'] == $WANT" && echo 1 || echo 0)" "$DECOR start_session runs the chosen session's command $WANT"
  check "$(log_has "e['type'] == 'start_session' and 'XDG_SESSION_TYPE=wayland' in e['env']" && echo 1 || echo 0)" "$DECOR the session gets XDG_SESSION_TYPE=wayland"
  wait_for '! kill -0 "$QPID" 2>/dev/null' 40 || true
  check "$(kill -0 "$QPID" 2>/dev/null && echo 0 || echo 1)" "$DECOR the greeter quits once the session starts"
  QPID=""
  check "$(python3 -I -c "
import json, sys
d = json.load(open('$W/gdir/memory.json'))
sys.exit(0 if d['user'] == 'tester' and d['session'] == ('niri' if '$DECOR' == 'sekai' else 'sway') else 1)" 2>/dev/null && echo 1 || echo 0)" \
    "$DECOR the memory keeps the user and session that started"
  cp "$W/greetd.log" "$R/greetd-$DECOR.log"
done

if grep -Eq 'ReferenceError|TypeError|binding loop|is not a function|is not defined|is not a type|Cannot assign' "$R/qs.log" 2>/dev/null; then
  echo "QML errors in qs.log: $(grep -E 'ReferenceError|TypeError|binding loop|is not a function|is not defined|is not a type|Cannot assign' "$R/qs.log" | head -5)" >&2
  FAILS=$((FAILS + 1))
fi
if grep -q panicked "$R/kurashid.log" 2>/dev/null; then
  echo "kurashid panicked (see $R/kurashid.log)" >&2
  FAILS=$((FAILS + 1))
fi
echo "checks: $((CHECKS - FAILS < 0 ? 0 : CHECKS - FAILS)) of $CHECKS"
[ "$FAILS" -eq 0 ] || fail "$FAILS failure(s); logs in $R, screenshots in $OUT"
echo "ok: screenshots in $OUT"
