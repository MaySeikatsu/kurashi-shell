#!/usr/bin/env bash
# The polkit dialog and the rounded screen corners (W23-auth-media, K47 (5) (6)), invisibly, with the real kurashid in
# the headless sway sandbox.
# Polkit: the sandbox has no polkitd of its own, and its shell must never register an agent on the user's real system
# bus (it would answer the user's own requests with an invisible dialog), so the dialog is driven by a harness: a copy of
# frontend/ whose root file holds PolkitDialog with `fakeFlow` (the AuthFlow shape of Quickshell.Services.Polkit, any
# password fails). Per decor (sekai, none): the prompt; a wrong password typed through the sandbox's virtual keyboard
# (shake, message, field cleared); Escape cancels and the window goes away. runtime.ui.polkit follows (true while up,
# false after). One run with two identities. Then the real shell with KURASHI_POLKIT_AGENT=1 and a system bus that does
# not exist: the agent's registration result is logged ("polkit: agent not registered").
# Corners: the real shell with its own screen-corner size (screen_corners_follow = false, screen_corners = 24): black
# fillets at the output's corners, the background at 14 px in; set to 0 live: gone; following the radius again (K74,
# sekai's 23 px): back.
# I128 (W36), with the real shell: while runtime.ui.polkit is true no Stage panel opens (row 381: kurashid refuses
# quick.toggle and island.expand with ui.error.polkit, runtime.ui.panel stays empty, nothing drawn), an open quick card is
# closed by the daemon and folds away when it turns true, and does not come back when it turns false.
# Screenshots (frontend/shots/): polkit-{prompt,wrong}-{sekai,none}.png, polkit-identities-sekai.png,
# corners-24-{tl,br}.png, polkit-stage-aside.png.
#   KURASHI_RENDER_NODE=/dev/dri/renderD129 KURASHI_BIN_DIR=<dir with kurashid and kurashi> \
#     timeout 900 nix develop -c frontend/test-polkit.sh [sandbox-name]
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
NAME=${1:-${KURASHI_SB_PREFIX:-}w23-aut-polkit}
BIN=${KURASHI_BIN_DIR:-${CARGO_TARGET_DIR:-$ROOT/target}/debug}
OUT=$ROOT/frontend/shots
DECORS=${DECORS:-sekai none}
# Machine B's iGPU when it exists; elsewhere sandbox.sh picks the display GPU (boot_vga).
[ -e /dev/dri/renderD129 ] && export KURASHI_RENDER_NODE=${KURASHI_RENDER_NODE:-/dev/dri/renderD129}
CARD_GEOM=${CARD_GEOM:-"980,420 600x600"}
mkdir -p "$OUT"
FAILS=0
CHECKS=0
fail() { echo "test-polkit: $*" >&2; exit 1; }
check() { # check <0|1> <label>
  CHECKS=$((CHECKS + 1))
  if [ "$1" = 1 ]; then echo "ok: $2"; else echo "FAIL: $2"; FAILS=$((FAILS + 1)); fi
}

eval "$("$ROOT/tools/bench/sandbox.sh" start "$NAME")"
. "$ROOT/frontend/test-lib.sh"
R=$XDG_RUNTIME_DIR
W=$R/work
mkdir -p "$W" "$R/kurashi"
cp "$BIN/kurashid" "$BIN/kurashi" "$W/"
rm -f "$R/qs.log" "$R/kurashid.log"
for _ in $(seq 150); do timeout 5 swaymsg -t get_outputs >/dev/null 2>&1 && break; sleep 0.2; done
timeout 5 swaymsg -t get_outputs >/dev/null 2>&1 || fail "the headless compositor does not answer (see $R/sway.log)"

DPID=""
SHPID=""
stop_daemon() { if [ -n "$DPID" ]; then kill "$DPID" 2>/dev/null || true; wait "$DPID" 2>/dev/null || true; fi; DPID=""; }
stop_shell() { if [ -n "$SHPID" ]; then kill "$SHPID" 2>/dev/null || true; wait "$SHPID" 2>/dev/null || true; fi; SHPID=""; }
cleanup() {
  stop_shell
  stop_daemon
  "$ROOT/tools/bench/sandbox.sh" stop "$NAME" >/dev/null || true
}
trap cleanup EXIT

export XDG_CONFIG_HOME=$R/xdg/config XDG_STATE_HOME=$R/xdg/state XDG_DATA_HOME=$R/xdg/data XDG_CACHE_HOME=$R/xdg/cache
export KURASHI_DATA_DIR=$ROOT LC_ALL=C.UTF-8
NOBUS="unix:path=$R/no-system-bus"
K() { timeout 10 "$W/kurashi" "$@"; }
keys() { timeout 30 python3 -I "$ROOT/tools/bench/wl_keys.py" "$@" >> "$R/keys.log" 2>&1 || true; }
# `ipc.py <doc>` prints the first snapshot's data of a document (stdlib only, as in mods/tasks/test-tasks.sh).
cat > "$W/ipc.py" <<'PY'
import json, os, socket, sys

sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
sock.settimeout(5)
sock.connect(os.environ["KURASHI_SOCKET"])
f = sock.makefile("rwb")


def send(msg):
    f.write((json.dumps(msg) + "\n").encode())
    f.flush()


send({"t": "hello", "v": 1, "client": "test", "caps": ["intents", "resync"]})
if json.loads(f.readline())["t"] != "welcome":
    sys.exit("ipc: no welcome")
send({"t": "sub", "id": "s", "doc": sys.argv[1]})
while True:
    line = f.readline()
    if not line:
        sys.exit("ipc: connection closed")
    m = json.loads(line)
    if m.get("id") == "s" and m["t"] in ("snap", "err"):
        if m["t"] == "err":
            sys.exit("ipc: " + json.dumps(m))
        print(json.dumps(m.get("data")))
        break
PY
ui_is() { timeout 10 python3 -I "$W/ipc.py" runtime.ui | python3 -c "import json,sys; d = json.load(sys.stdin) or {}; sys.exit(0 if ($1) else 1)" 2>/dev/null; }
wait_ui() { local i; for i in $(seq "$2"); do ui_is "$1" && return 0; sleep 0.25; done; return 0; }
shot() { # shot <name> <geometry>
  sleep "${WAIT:-1.5}"
  grim -g "$2" "$OUT/$1.png"
  [ -s "$OUT/$1.png" ] || fail "empty screenshot $1"
  echo "shot $1"
}

# The harness: frontend/ copied (its imports stay inside one config root), with a root file that holds the dialog and a
# fake flow. The flow starts 1.5 s after the shell, so the window is created the way a real request creates it.
FE=$R/fe
rm -rf "$FE"
cp -r "$ROOT/frontend" "$FE"
cat > "$FE/polkit-harness.qml" <<'QML'
import QtQuick
import Quickshell
import "core"
import "surfaces"

ShellRoot {
    Watch { doc: "theme" }
    Watch { doc: "i18n" }
    Watch { doc: "svc.workspaces" }
    readonly property bool two: Quickshell.env("FAKE_IDENTITIES") === "2"
    // The AuthFlow shape (Quickshell.Services.Polkit) the dialog reads. Any password fails after 300 ms; the typed text
    // is dropped unread.
    QtObject {
        id: fake
        property string message: "Authentication is needed to run `/run/current-system/sw/bin/true' as the super user."
        property string actionId: "org.freedesktop.policykit.exec"
        property var identities: two
            ? [{ id: 1000, string: "maike", displayName: "maike", isGroup: false },
               { id: 0, string: "root", displayName: "root", isGroup: false }]
            : [{ id: 0, string: "root", displayName: "root", isGroup: false }]
        property var selectedIdentity: identities[identities.length - 1]
        property bool isResponseRequired: true
        property string inputPrompt: "Password: "
        property bool responseVisible: false
        property string supplementaryMessage: ""
        property bool supplementaryIsError: false
        property bool isCompleted: false
        signal authenticationFailed()
        signal authenticationRequestCancelled()
        function submit(value) { isResponseRequired = false; failLater.start() }
        function cancelAuthenticationRequest() { isCompleted = true; authenticationRequestCancelled(); dialog.fakeFlow = null }
    }
    Timer { id: failLater; interval: 300; onTriggered: { fake.authenticationFailed(); fake.isResponseRequired = true } }
    Timer { interval: 1500; running: true; onTriggered: dialog.fakeFlow = fake }
    PolkitDialog { id: dialog }
}
QML

start_daemon() { # start_daemon <decor> [extra config lines]
  stop_shell
  stop_daemon
  rm -rf "$R/xdg"
  mkdir -p "$XDG_CONFIG_HOME/kurashi" "$XDG_STATE_HOME" "$XDG_DATA_HOME" "$XDG_CACHE_HOME"
  printf 'theme.style = "%s"\n%s\n' "$1" "${2:-}" > "$XDG_CONFIG_HOME/kurashi/config.toml"
  rm -f "$KURASHI_SOCKET"
  env DBUS_SYSTEM_BUS_ADDRESS="$NOBUS" PULSE_SERVER="unix:$R/no-pulse/native" PULSE_RUNTIME_PATH="$R/no-pulse" \
    "$W/kurashid" >> "$R/kurashid.log" 2>&1 &
  DPID=$!
  for _ in $(seq 100); do [ -S "$KURASHI_SOCKET" ] && K ping >/dev/null 2>&1 && break; sleep 0.1; done
  K ping >/dev/null 2>&1 || fail "kurashid did not come up (see $R/kurashid.log)"
  swaymsg output '*' bg '#8fb8c8' solid_color >/dev/null 2>&1 || true
}
start_harness() {
  local off bare; off=$(log_size "$R/qs.log"); bare=$(screen_hash)
  env -u KURASHI_SOCKET DBUS_SYSTEM_BUS_ADDRESS="$NOBUS" FAKE_IDENTITIES="${1:-1}" qs -p "$FE/polkit-harness.qml" >> "$R/qs.log" 2>&1 &
  SHPID=$!
  # Was a fixed SHELL_WAIT (4 s): the harness loaded, drew and stands still, at most that long.
  wait_frontend "$R/qs.log" "$off" "${SHELL_WAIT:-4}" 0.6 "$bare" || fail "the harness did not load (see $R/qs.log)"
}

# `px.py <ppm> x,y,want ...`: each pixel of a full-output grab is `black`, `bg` (the sandbox's background #8fb8c8) or
# `dim` (the background under the dialog's scrim: darker, not black). Layer surfaces are not in sway's tree, so the
# pixels are the evidence that a surface is there or gone.
cat > "$W/px.py" <<'PY'
import sys
data = open(sys.argv[1], "rb").read()
fields, i = [], 0
while len(fields) < 4:
    while data[i:i + 1].isspace():
        i += 1
    j = i
    while not data[j:j + 1].isspace():
        j += 1
    fields.append(data[i:j]); i = j
w, h, raster = int(fields[1]), int(fields[2]), data[i + 1:]
BG = (0x8f, 0xb8, 0xc8)
ok = True
for arg in sys.argv[2:]:
    x, y, want = arg.split(",")
    x, y = int(x), int(y)
    o = (y * w + x) * 3
    p = tuple(raster[o:o + 3])
    black = max(p) < 16
    bg = all(abs(a - b) <= 8 for a, b in zip(p, BG))
    good = {"black": black, "bg": bg, "dim": not black and not bg and all(a < b for a, b in zip(p, BG)),
            "card": not bg}[want]
    print(f"({x},{y}) {p} {want}: {'ok' if good else 'FAIL'}")
    ok &= good
sys.exit(0 if ok else 1)
PY
pixels() { # pixels <label> x,y,want ...: one check
  local label=$1; shift
  grim -t ppm "$R/full.ppm"
  check "$(python3 -I "$W/px.py" "$R/full.ppm" "$@" > "$R/px.log" 2>&1 && echo 1 || echo 0)" "$label ($(tr '\n' ' ' < "$R/px.log"))"
}

for DECOR in $DECORS; do
  echo "== $DECOR: polkit dialog"
  start_daemon "$DECOR"
  start_harness 1
  wait_ui 'd.get("polkit") is True' 20
  check "$(ui_is 'd.get("polkit") is True' && echo 1 || echo 0)" "$DECOR the dialog tells the daemon it is up"
  shot "polkit-prompt-$DECOR" "$CARD_GEOM"
  pixels "$DECOR the scrim covers the output" 100,1300,dim 2400,200,dim
  keys w r o n g return
  shot "polkit-wrong-$DECOR" "$CARD_GEOM"
  keys escape
  wait_ui 'd.get("polkit") is False' 20
  check "$(ui_is 'd.get("polkit") is False' && echo 1 || echo 0)" "$DECOR Escape cancels; the daemon hears the dialog is gone"
  sleep 0.5
  pixels "$DECOR no dialog once cancelled" 100,1300,bg 2400,200,bg
done

echo "== sekai: two identities"
start_daemon sekai
start_harness 2
wait_ui 'd.get("polkit") is True' 20
shot "polkit-identities-sekai" "$CARD_GEOM"
stop_shell

echo "== the real shell: agent registration and screen corners at 24 px"
start_daemon sekai $'theme.shape.screen_corners_follow = false\ntheme.shape.screen_corners = 24'
env -u KURASHI_SOCKET DBUS_SYSTEM_BUS_ADDRESS="$NOBUS" KURASHI_POLKIT_AGENT=1 qs -p "$ROOT/frontend" >> "$R/qs-real.log" 2>&1 &
SHPID=$!
# Was a fixed 6 s: the agent's registration result logged, then the screen still (its corners drawn).
wait_for "$R/qs-real.log" 'polkit: agent (registered|not registered)' 6 || true
wait_settled 3 0.6
check "$(grep -q 'polkit: agent \(registered\|not registered\)' "$R/qs-real.log" && echo 1 || echo 0)" "the agent's registration result is logged: $(grep -m1 -o 'polkit: agent.*' "$R/qs-real.log" || echo none)"
pixels "corners at 24: black at the output's corners, the background 14 px in" \
  1,1438,black 2558,1438,black 2,2,black 2557,2,black 14,1425,bg 2545,1425,bg
grim -g "0,0 120x120" "$OUT/corners-24-tl.png"
grim -g "2440,1320 120x120" "$OUT/corners-24-br.png"
# (Each fixed 1.5 s after a set is now: until the screen stands still, at most 1.5 s.)
K set theme.shape.screen_corners=0 >/dev/null || fail "set screen_corners failed"
wait_settled 1.5 0.5
pixels "corners at 0: the background at the output's corners" 1,1438,bg 2558,1438,bg
K set theme.shape.screen_corners_follow=true >/dev/null || fail "set screen_corners_follow failed"
wait_settled 1.5 0.5
pixels "corners following sekai's radius (23): black at the output's corners, the background 14 px in" \
  1,1438,black 2558,1438,black 14,1425,bg 2545,1425,bg

# I128 (W36): while runtime.ui.polkit is true the Stage and the island step aside. The flag is set through the daemon's
# own action (the agent is not registered here). (2350,300) lies in the quick card at rest (under its button at the
# bar's right end), (1280,300) in an island card (centred under the pill).
panel_is() { ui_is "d.get('panel', '') == '$1'"; }
K act ui.polkit '{"active":true}' >/dev/null || fail "ui.polkit true refused"
wait_ui 'd.get("polkit") is True' 20
# Row 381: the daemon refuses the Stage's panel actions (kurashi act exits non-zero and names the key).
refused_by_polkit() { local out; if out=$(K act "$@" 2>&1); then return 1; fi; grep -q 'ui.error.polkit\|authentication dialog' <<<"$out"; }
check "$(refused_by_polkit quick.toggle && echo 1 || echo 0)" "polkit up: quick.toggle is refused with ui.error.polkit"
sleep 0.5
check "$(panel_is "" && echo 1 || echo 0)" "polkit up: quick settings stays closed (runtime.ui.panel empty)"
check "$(refused_by_polkit island.expand && echo 1 || echo 0)" "polkit up: island.expand is refused with ui.error.polkit"
sleep 0.5
check "$(panel_is "" && echo 1 || echo 0)" "polkit up: the island does not expand (runtime.ui.panel empty)"
sleep 1
pixels "polkit up: no card drawn" 2350,300,bg 1280,300,bg
K act ui.polkit '{"active":false}' >/dev/null || fail "ui.polkit false refused"
K act quick.toggle >/dev/null
sleep 1.5
check "$(panel_is quick && echo 1 || echo 0)" "polkit gone: quick settings opens again"
pixels "polkit gone: the quick card stands under its button" 2350,300,card
K act ui.polkit '{"active":true}' >/dev/null
sleep 0.5
wait_ui 'd.get("panel", "") == ""' 20
check "$(panel_is "" && echo 1 || echo 0)" "polkit comes up over an open quick card: the panel is closed"
sleep 1.5
pixels "polkit up: the quick card folded away" 2350,300,bg
grim -g "1040,0 1520x700" "$OUT/polkit-stage-aside.png"
K act ui.polkit '{"active":false}' >/dev/null
sleep 1.5
check "$(panel_is "" && echo 1 || echo 0)" "polkit gone: the folded panel does not come back by itself"
pixels "polkit gone: still no card" 2350,300,bg
stop_shell
stop_daemon
cat "$R/qs-real.log" >> "$R/qs.log"


if grep -Eq 'ReferenceError|TypeError|binding loop|is not a function|is not defined|is not a type' "$R/qs.log" 2>/dev/null; then
  echo "QML errors in qs.log: $(grep -E 'ReferenceError|TypeError|binding loop|is not a function|is not defined|is not a type' "$R/qs.log" | head -5)" >&2
  FAILS=$((FAILS + 1))
fi
if grep -Ei 'PolkitDialog|ScreenCorners' "$R/qs.log" 2>/dev/null | grep -Eiq 'warn|error'; then
  echo "QML warnings from the new surfaces: $(grep -Ei 'PolkitDialog|ScreenCorners' "$R/qs.log" | grep -Ei 'warn|error' | head -5)" >&2
  FAILS=$((FAILS + 1))
fi
if grep -q panicked "$R/kurashid.log" 2>/dev/null; then
  echo "kurashid panicked (see $R/kurashid.log)" >&2
  FAILS=$((FAILS + 1))
fi
echo "checks: $((CHECKS - FAILS < 0 ? 0 : CHECKS - FAILS)) of $CHECKS"
[ "$FAILS" -eq 0 ] || fail "$FAILS failure(s); logs in $R, screenshots in $OUT"
echo "ok: screenshots in $OUT"
