#!/usr/bin/env bash
# Drop shadows you can set, and shadows that follow the light (K67, docs/ux/shadows.md). Invisibly (headless sway
# sandbox), the REAL kurashid with an empty config, `kurashi set` between shots, no restart:
#   tokens   the theme's `shadow.dx/dy/alpha_scale` against the vector math (today's shadow at the defaults; the angle and
#            strength; away from the light while following, longer when it is low; `shadow_angle` inert while following;
#            following inert without a material);
#   matrix   keycap (sekai) and soft (glass) chrome × angle 180/135/225 × strength 0.5/1/2: the bar's groups and the
#            island's card at rest;
#   follow   sekai with a paper material, the light at 315° and at 45°, high (70°) and low (15°);
#   press    a bar key held down (sinks along the vector, here down to the right);
#   surfaces a Stage card (quick settings) and the right sidebar with a sideways shadow;
#   settings the Look/material rows with the preview, static and following (the direction inert);
#   ma       follow on with the pointer's lamp: the pointer sweeping the desktop for 3 s commits no frame of any shell
#            surface, and a light change (a new direction) repaints and settles again.
#   surfaces2 (W39, I206) the surfaces that cast their own hard shadow, at 135° strength 2 under sekai (keycap) and glass
#            (soft): the floating sidebar's column, a toast under the bar and beside it (the bar on the right), the
#            notification centre, the polkit dialog's field (a harness copy of the frontend), Settings' section cards and
#            sheet, the lock screen's field (kurashi-mock serves the tokens: the real daemon refuses to lock without PAM).
#   surfaces3 (W42, K67, I206) the surfaces that cast a hard or a soft shadow of their own, at rest, one shot per look and
#            angle: the session keys, the key clock, the quick settings' phone frame, the dock's phone card, the web host's
#            key and Settings' button — the real files, loaded by path beside a copy of the shell (a harness with fixed
#            content, so no clock minute moves a shot). At 135 and 225 the shadow of each falls to its side (the centroid
#            of the shadow's pixels off the face lies right of or left of the face's centre, and below it); at 180 it falls
#            straight down. Held (keycap, 135°): the web host's key sinks by the vector, Settings' button keeps its face and
#            shows 1 px along it. At the defaults every crop matches the reference frontend (SHADOW_REF) with no strong pixel.
#            Not covered: the web host's card (WebCard.qml, its pill still casts straight down until CONTRACT row 465 lands).
#            Settings' button is checked under keycap only: it has no soft shadow, as SectionCard has none (W39).
#   inert    (W42, row 423) Settings' three shadow rows under flat and line chrome: inert, with the reason, in en and ja. The
#            words name the first `requires` on theme.chrome, so under line they say "not flat", which holds there (CONTRACT
#            row 467); the test checks the reason key, and the shots (frontend/shots/shadows/w42-inert-*) show the words.
# Files: frontend/shots/shadows/*.png and sheet.png (a contact sheet, with ImageMagick). Fails on a server or frontend
# that does not come up, a token that disagrees with the math, a frame committed while the pointer moves, a QML error.
# SHADOW_REF=<a frontend dir from before the change, with its settings/ and mods/ beside it> (e.g. `git archive HEAD frontend
# settings mods i18n` into a scratch dir): the defaults must draw pixel for pixel what that frontend draws, for bar, card,
# quick, every surfaces2 surface and every surfaces3 crop (the harnesses' surfaces at 180, with no strong pixel).
#   nix develop -c frontend/test-shadows.sh
#   SHADOW_PARTS="tokens matrix" nix develop -c frontend/test-shadows.sh
# Binaries from $KURASHI_BIN_DIR (kurashid, kurashi, kurashi-mock), else $CARGO_TARGET_DIR/debug.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
NAME=${SHADOW_SANDBOX:-w42-shadows3-shadows}
BIN=${KURASHI_BIN_DIR:-${CARGO_TARGET_DIR:-$ROOT/target}/debug}
OUT=${SHADOW_OUT:-$ROOT/frontend/shots/shadows}
PARTS=${SHADOW_PARTS:-tokens matrix follow press surfaces settings ma surfaces2 surfaces3 inert}
mkdir -p "$OUT"
fail() { echo "test-shadows: FAIL: $*" >&2; exit 1; }
say() { echo "test-shadows: $*"; }
want() { [[ " $PARTS " == *" $1 "* ]]; }

eval "$("$ROOT/tools/bench/sandbox.sh" start "$NAME")"
R=$XDG_RUNTIME_DIR
W=$R/work
mkdir -p "$W" "$R/kurashi"
cp "$BIN/kurashid" "$BIN/kurashi" "$BIN/kurashi-mock" "$W/"
pids=()
QS_PID=
DPID=
cleanup() {
  for p in "${pids[@]}"; do kill "$p" 2>/dev/null || true; done
  for p in "${pids[@]}"; do wait "$p" 2>/dev/null || true; done
  "$ROOT/tools/bench/sandbox.sh" stop "$NAME" >/dev/null || true
}
trap cleanup EXIT

export XDG_CONFIG_HOME=$R/xdg/config XDG_STATE_HOME=$R/xdg/state \
       XDG_DATA_HOME=$R/xdg/data XDG_CACHE_HOME=$R/xdg/cache KURASHI_DATA_DIR=$ROOT LC_ALL=C.UTF-8
rm -rf "$R/xdg"; mkdir -p "$XDG_CONFIG_HOME/kurashi" "$XDG_STATE_HOME" "$XDG_DATA_HOME" "$XDG_CACHE_HOME"
: > "$XDG_CONFIG_HOME/kurashi/config.toml"
K() { timeout 10 "$W/kurashi" "$@"; }
set_() { K set "$@" >/dev/null || fail "kurashi set $* refused"; }

# The theme document's tokens (and a config key's provenance), over the socket.
cat > "$W/ipc.py" <<'PY'
import json, os, socket, sys
sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
sock.settimeout(5)
sock.connect(os.environ["KURASHI_SOCKET"])
f = sock.makefile("rwb")
def send(msg):
    f.write((json.dumps(msg) + "\n").encode()); f.flush()
send({"t": "hello", "v": 1, "client": "test", "caps": ["intents", "resync"]})
if json.loads(f.readline())["t"] != "welcome":
    sys.exit("ipc: no welcome")
send({"t": "sub", "id": "s", "doc": "theme"})
while True:
    m = json.loads(f.readline())
    if m.get("id") == "s" and m["t"] in ("snap", "err"):
        t = (m.get("data") or {}).get("tokens", {})
        print(json.dumps([t.get(k) for k in sys.argv[1:]]))
        break
PY
toks() { timeout 10 python3 -I "$W/ipc.py" "$@"; }
# expect <label> <dx> <dy> [alpha]: the tokens within 0.02 px.
expect() {
  local got
  got=$(toks shadow.dx shadow.dy shadow.alpha_scale)
  python3 -I -c '
import json, sys
dx, dy, a = json.loads(sys.argv[1])
want = [float(v) for v in sys.argv[3:]]
ok = abs(dx - want[0]) < 0.02 and abs(dy - want[1]) < 0.02 and (len(want) < 3 or abs(a - want[2]) < 0.02)
print(("ok   " if ok else "FAIL ") + sys.argv[2] + ": dx %.2f dy %.2f alpha %.2f" % (dx, dy, a))
sys.exit(0 if ok else 1)' "$got" "$@" || fail "tokens for $1"
}
# The vector the math gives: vec <length> <angle> <strength> → "dx dy".
vec() { python3 -I -c 'import math,sys; l,a,s=map(float,sys.argv[1:]); r=math.radians(a); print("%.4f %.4f" % (math.sin(r)*l*s, -math.cos(r)*l*s))' "$@"; }
# The followed vector: away from a light at <angle>, <elevation>; length × tan 40° / tan e within 0.5…2.
fvec() { python3 -I -c '
import math, sys
l, a, e, s = map(float, sys.argv[1:])
k = min(2.0, max(0.5, math.tan(math.radians(40)) / math.tan(math.radians(e))))
r = math.radians(a + 180)
print("%.4f %.4f" % (math.sin(r) * l * k * s, -math.cos(r) * l * k * s))' "$@"; }
reason() { K --json get "$1" | python3 -I -c 'import json,sys; print(json.load(sys.stdin).get("reason") or "")'; }

start_daemon() {  # the real kurashid on the sandbox's socket; its config is whatever `kurashi set` has written so far
  env DBUS_SYSTEM_BUS_ADDRESS="unix:path=$R/no-system-bus" \
    PULSE_SERVER="unix:$R/no-pulse/native" PULSE_RUNTIME_PATH="$R/no-pulse" \
    "$W/kurashid" >> "$R/server.log" 2>&1 &
  DPID=$!
  pids+=("$DPID")
  for _ in $(seq 100); do [ -S "$KURASHI_SOCKET" ] && K ping >/dev/null 2>&1 && break; sleep 0.1; done
  K ping >/dev/null 2>&1 || fail "kurashid did not come up (see $R/server.log)"
}
stop_daemon() { kill "$DPID" 2>/dev/null || true; wait "$DPID" 2>/dev/null || true; rm -f "$KURASHI_SOCKET"; }
: > "$R/server.log"
start_daemon
swaymsg output '*' bg '#8fb8c8' solid_color >/dev/null 2>&1 || true

# start_frontend_dir <frontend dir> [ENV=VALUE …]: the shell from that directory, once its hello is in the daemon's log.
start_frontend_dir() {
  local dir=$1 n0
  shift
  if [ -n "$QS_PID" ]; then kill "$QS_PID" 2>/dev/null || true; wait "$QS_PID" 2>/dev/null || true; fi
  : > "$R/qs.log"
  n0=$(grep -c 'hello.*frontend' "$R/server.log" || true)
  env -u KURASHI_SOCKET "$@" qs -p "$dir" >> "$R/qs.log" 2>&1 &
  QS_PID=$!
  pids+=("$QS_PID")
  for _ in $(seq 100); do [ "$(grep -c 'hello.*frontend' "$R/server.log" || true)" -gt "$n0" ] && break; sleep 0.1; done
  [ "$(grep -c 'hello.*frontend' "$R/server.log" || true)" -gt "$n0" ] || fail "frontend never said hello from $dir (see $R/qs.log)"
  sleep 3
}
start_frontend() { start_frontend_dir "$ROOT/frontend" "$@"; }  # start_frontend [ENV=VALUE …]
qml_errors() {
  grep -E "TypeError|ReferenceError|is not a type|Cannot assign|is not defined|Unable to assign|Cannot read property" "$R/qs.log" \
    | grep -v "^\s*$" || true
}
shot() { grim -g "$2" "$OUT/$1.png"; say "$OUT/$1.png"; }
# The bar's right half (its groups) and the island's card at rest (crops at 2560×1440, top bar).
BAR="1280,0 1280x52"
CARD="860,0 840x560"
look() {  # look <style>: the style, calm motion, shadows back to the defaults
  set_ theme.style "$1"
  set_ theme.motion.profile calm
  K reset theme.material >/dev/null 2>&1 || true
  K reset theme.texture >/dev/null 2>&1 || true
  K reset theme.light >/dev/null 2>&1 || true
  sleep 2
}
card() {  # card <name>: the island's card at rest, then closed
  K act island.expand >/dev/null || fail "island.expand"
  sleep 1.6
  shot "$1" "$CARD"
  K act ui.close >/dev/null || true
  sleep 1.2
}

# notify <app> <summary> <body> [ms]: one notification on the sandbox's own bus (the daemon serves it).
notify() {
  case "${DBUS_SESSION_BUS_ADDRESS:-}" in *"$R"*) ;; *) fail "no sandbox session bus: a notification would reach the real one" ;; esac
  timeout 10 gdbus call --session --dest org.freedesktop.Notifications --object-path /org/freedesktop/Notifications \
    --method org.freedesktop.Notifications.Notify "$1" 0 "" "$2" "$3" '[]' '{}' "${4:-8000}" >/dev/null
}
# sq <name> [settings dir] [file]: Settings opened on the shadow rows (its section cards and sheet), the whole output.
sq() {
  local dir=${2:-$ROOT/settings} file=${3:-$OUT/settings-$1.png} sp e
  env -u KURASHI_SOCKET KURASHI_SETTINGS_KEY=theme.material.shadow qs -p "$dir" > "$R/settings-$1.log" 2>&1 &
  sp=$!
  pids+=("$sp")
  for _ in $(seq 100); do qs -p "$dir" ipc call settings current >/dev/null 2>&1 && break; sleep 0.2; done
  sleep 2
  grim -o HEADLESS-1 "$file"; say "$file"
  kill "$sp" 2>/dev/null || true; wait "$sp" 2>/dev/null || true
  e=$(grep -E "TypeError|ReferenceError|is not a type|Cannot assign|is not defined|Unable to assign" "$R/settings-$1.log" || true)
  [ -z "$e" ] || { echo "$e"; fail "QML errors in Settings ($1)"; }
}
# same_px <a.png> <b.png> <label>: ok when the two draw the same pixels, or differ only inside clock-sized boxes (the clocks
# may turn their minute between two runs). A strong difference (a channel off by more than 64) outside those fails.
same_px() {
  python3 -I -c '
import subprocess, sys
def px(p):
    d = subprocess.run(["magick", p, "rgb:-"], capture_output=True, check=True).stdout
    w, h = map(int, subprocess.run(["magick", "identify", "-format", "%w %h", p], capture_output=True, check=True).stdout.split())
    return d, w, h
a, w, h = px(sys.argv[1]); b, _, _ = px(sys.argv[2])
diff = [i // 3 for i in range(0, len(a), 3) if a[i:i+3] != b[i:i+3]]
if not diff:
    print("ok   identical: " + sys.argv[3]); sys.exit(0)
# Two runs of one frontend differ in a few hundred scattered, faint px (text and blur rasterisation): what counts is a
# strong difference (a channel off by more than 64), which a moved shadow edge makes along its whole length.
strong = [i for i in diff if max(abs(a[3*i+c] - b[3*i+c]) for c in range(3)) > 64]
# Strong px are grouped into blobs (strong px within 3 px of each other, chains included). A clock digit, a glyph or a clock
# layout shift is a small blob or a few; a moved shadow edge or card is one long one. Every blob longer side must be at most
# 48 px (W42, I210): the clock and text churn between two runs measures up to 35×10 (the bar clock group at a minute change,
# 19×16 beside it) and 3×14 for a digit stroke. The old 80×30 let an 80×2 sliver pass; so does an edge up to 48 px long, which
# is why the small blocks (keys, the web host key, the Settings button) are checked strictly by surfaces3 instead.
pts = sorted((i % w, i // w) for i in strong)
cells = {}
for p in pts:
    cells.setdefault((p[0] // 4, p[1] // 4), []).append(p)
parent = {p: p for p in pts}
def find(p):
    while parent[p] != p:
        parent[p] = parent[parent[p]]
        p = parent[p]
    return p
for p in pts:
    for dx in (-1, 0, 1):
        for dy in (-1, 0, 1):
            for q in cells.get((p[0] // 4 + dx, p[1] // 4 + dy), []):
                if max(abs(q[0] - p[0]), abs(q[1] - p[1])) <= 3 and find(p) != find(q):
                    parent[find(p)] = find(q)
blobs = {}
for p in pts:
    blobs.setdefault(find(p), []).append(p)
sizes = [(max(x for x, _ in g) - min(x for x, _ in g) + 1, max(y for _, y in g) - min(y for _, y in g) + 1, min(x for x, _ in g), min(y for _, y in g)) for g in blobs.values()]
ok = all(max(bw, bh) <= 48 for bw, bh, _, _ in sizes)
big = sorted(sizes, key=lambda s: -(s[0] * s[1]))[:4]
print(("ok   " if ok else "FAIL ") + "%s: %d px differ, %d strongly in %d blobs, largest %s" % (sys.argv[3], len(diff), len(strong),
      len(sizes), " ".join("%dx%d@%d,%d" % s for s in big)))
sys.exit(0 if ok else 1)' "$1" "$2" "$3"
}
# lock_shot <frontend dir> <file>: the lock screen with the tokens in effect. kurashi-mock serves them (the real daemon
# refuses to lock without its PAM service); the real daemon is started again afterwards, with the same config.
lock_shot() {
  local dir=$1 file=$2 mp e
  K sub theme --count 0 --json | jq -c '{doc: "theme", patch: {tokens: .data.tokens}}' > "$W/lock-theme.json" \
    || fail "lock: no theme tokens"
  stop_daemon
  "$W/kurashi-mock" --outputs HEADLESS-1 --socket "$KURASHI_SOCKET" >> "$R/server.log" 2>&1 &
  mp=$!
  pids+=("$mp")
  for _ in $(seq 100); do [ -S "$KURASHI_SOCKET" ] && K ping >/dev/null 2>&1 && break; sleep 0.1; done
  K act mock.doc "$(cat "$W/lock-theme.json")" >/dev/null || fail "lock: mock.doc theme"
  if [ -n "$QS_PID" ]; then kill "$QS_PID" 2>/dev/null || true; wait "$QS_PID" 2>/dev/null || true; fi
  env -u KURASHI_SOCKET qs -p "$dir" > "$R/qs-lock.log" 2>&1 &
  QS_PID=$!
  pids+=("$QS_PID")
  sleep 4
  K act mock.doc '{"doc":"runtime.lock","patch":{"locked":true}}' >/dev/null || fail "lock: mock.doc runtime.lock"
  sleep 2
  # The field and its shadow (the clock is larger and changes every minute, so it is outside the crop).
  grim -g "${SHADOW_LOCK_CROP:-1060,740 440x120}" "$file"; say "$file"
  # Unlock through the daemon before the lock client goes: a session whose lock client dies stays locked (sway paints it
  # red), and every later shot of the run would be red.
  K act mock.doc '{"doc":"runtime.lock","patch":{"locked":false}}' >/dev/null || fail "lock: mock.doc unlock"
  sleep 2
  kill "$QS_PID" 2>/dev/null || true; wait "$QS_PID" 2>/dev/null || true; QS_PID=
  kill "$mp" 2>/dev/null || true; wait "$mp" 2>/dev/null || true
  e=$(grep -E "TypeError|ReferenceError|is not a type|Cannot assign|is not defined|Unable to assign" "$R/qs-lock.log" || true)
  [ -z "$e" ] || { echo "$e"; fail "QML errors in the lock screen"; }
  start_daemon
}
# surf2 <frontend dir> <file prefix> <look> [angle strength]: the surfaces that cast their own hard shadow (I206), one shot
# each under the look, with the shadow at that angle and strength (none: the defaults). The bar goes to the right for the
# toasts and the centre, so their own cards (not the bar's shape) cast there.
surf2() {
  local dir=$1 pre=$2 lk=$3 pf pp e
  look "$lk"
  if [ -n "${4:-}" ]; then set_ theme.material.shadow "$5"; set_ theme.material.shadow_angle "$4"; fi
  sleep 1
  set_ sidebar.style floating
  start_frontend_dir "$dir"
  K act sidebar.toggle '{"side":"right","output":"HEADLESS-1"}' >/dev/null || fail "sidebar.toggle"
  sleep 1.8
  grim -g "2000,0 560x1440" "$pre-sidebar.png"
  K act sidebar.toggle '{"side":"right","output":"HEADLESS-1"}' >/dev/null || true
  sleep 1.4
  K reset sidebar.style >/dev/null 2>&1 || true
  notify Calendar "Standup in 5 minutes" "Room 3 · bring the notes from Monday" 20000
  sleep 2.2
  grim -g "880,0 800x720" "$pre-toast-drip.png"
  K act notify.dismiss '{}' >/dev/null || true
  sleep 1.5
  set_ bar.edge right
  sleep 2
  notify Mail "Aiko Tanaka" "The photos from Saturday are in the shared folder." 20000
  sleep 2.2
  grim -g "1960,0 600x640" "$pre-toast-slide.png"
  K act notifications.center >/dev/null || fail "notifications.center"
  sleep 2
  grim -g "1960,0 600x900" "$pre-centre.png"
  K act ui.close >/dev/null || true
  sleep 1.2
  K act notify.dismiss '{}' >/dev/null || true
  sleep 1
  set_ bar.edge top
  sleep 2
  e=$(qml_errors)
  [ -z "$e" ] || { echo "$e" | head -20; fail "QML errors (see $R/qs.log)"; }
  kill "$QS_PID" 2>/dev/null || true; wait "$QS_PID" 2>/dev/null || true; QS_PID=
  # The polkit dialog: a copy of this frontend whose root is the dialog with a fake flow (test-polkit.sh's harness). Its
  # system bus does not exist, so it never registers an agent.
  pf=$W/fe-$(basename "$pre")
  rm -rf "$pf"
  cp -r "$dir" "$pf"
  cat > "$pf/polkit-harness.qml" <<'QML'
import QtQuick
import Quickshell
import "core"
import "surfaces"

ShellRoot {
    Watch { doc: "theme" }
    Watch { doc: "i18n" }
    Watch { doc: "svc.workspaces" }
    QtObject {
        id: fake
        property string message: "Authentication is needed to run the test program as the super user."
        property string actionId: "org.freedesktop.policykit.exec"
        property var identities: [{ id: 0, string: "root", displayName: "root", isGroup: false }]
        property var selectedIdentity: identities[0]
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
  env -u KURASHI_SOCKET DBUS_SYSTEM_BUS_ADDRESS="unix:path=$R/no-system-bus" qs -p "$pf/polkit-harness.qml" \
    > "$R/qs-polkit.log" 2>&1 &
  pp=$!
  pids+=("$pp")
  sleep 4.5
  grim -g "980,420 600x600" "$pre-polkit.png"; say "$pre-polkit.png"
  kill "$pp" 2>/dev/null || true; wait "$pp" 2>/dev/null || true
  e=$(grep -E "TypeError|ReferenceError|is not a type|Cannot assign|is not defined|Unable to assign" "$R/qs-polkit.log" || true)
  [ -z "$e" ] || { echo "$e"; fail "QML errors in the polkit dialog"; }
  sq surf2 "$(dirname "$dir")/settings" "$pre-settings.png"
  lock_shot "$dir" "$pre-lock.png"
}

# ---- surfaces3 and inert (W42) ----
# The harnesses: the real components loaded by path (Loader), at fixed places, with fixed content (no clock). A tree is a copy
# of the shell's files the harnesses load; tar keeps the links (the host's core and PhoneFrame resolve inside the copy).
cat > "$W/harness-frontend.qml" <<'QML'
import QtQuick
import Quickshell
import Quickshell.Wayland
import "core"

// Surfaces that cast a shadow at rest, placed where the test's crops are (frontend/test-shadows.sh, surfaces3).
ShellRoot {
    Watch { doc: "theme" }
    Watch { doc: "i18n" }
    PanelWindow {
        anchors { left: true; top: true; right: true; bottom: true }
        color: "transparent"
        WlrLayershell.namespace: "kurashi-shadows3"
        Loader { x: 80; y: 80; source: "surfaces/SessionMenu.qml" }
        Loader {
            x: 80; y: 380; source: "components/KeyClock.qml"
            onLoaded: { item.hh = "10"; item.mm = "24" }
        }
        Loader {
            x: 800; y: 80; source: "components/phone/PhoneFrame.qml"
            onLoaded: { item.theme = Theme; item.width = 260; item.contentHeight = 240 }
        }
        Loader {
            x: 1200; y: 80; source: "harness/Card.qml"
            onLoaded: { item.title = "Mail"; item.width = 280; item.height = 380 }
        }
        Loader {
            x: 80; y: 900; source: "harness/HostButton.qml"
            onLoaded: { item.keyed = true; item.glyph = "⏻" }
        }
    }
}
QML
cat > "$W/harness-settings.qml" <<'QML'
import QtQuick
import Quickshell
import Quickshell.Wayland
import "components"

// Settings' button (keycap: its hard shadow), placed where the test's crop is.
ShellRoot {
    PanelWindow {
        anchors { left: true; top: true; right: true; bottom: true }
        color: "transparent"
        WlrLayershell.namespace: "kurashi-shadows3-settings"
        Button { x: 80; y: 80; label: "Reset" }
    }
}
QML
# The analysis (python, -I): `side` checks a shadow's side against the face; `strict` counts strong px between two shots.
cat > "$W/px.py" <<'PY'
import subprocess, sys
from collections import Counter

def load(path, x, y, w, h):
    d = subprocess.run(["magick", path, "-crop", "%dx%d+%d+%d" % (w, h, x, y), "+repage", "rgb:-"],
                       capture_output=True, check=True).stdout
    return [d[i:i + 3] for i in range(0, len(d), 3)]

def dif(p, q):
    return max(abs(p[c] - q[c]) for c in range(3))

def side(base, shot, angle, x, y, w, h, label):
    # The face: what differs from the crop's background (the mode of its edge) in the strength-0 shot. The shadow: what
    # differs from that shot off the face. Its centroid, against the face's centre, says where the shadow falls.
    b = load(base, x, y, w, h)
    s = load(shot, x, y, w, h)
    edge = [b[i] for i in range(w * h) if i < w or i >= (h - 1) * w or i % w in (0, w - 1)]
    bg = Counter(edge).most_common(1)[0][0]
    face = [dif(p, bg) > 10 for p in b]
    fx = [i % w for i in range(w * h) if face[i]]
    fy = [i // w for i in range(w * h) if face[i]]
    if not fx:
        return False, "%s: no face in the crop" % label
    cx = (min(fx) + max(fx)) / 2.0
    cy = (min(fy) + max(fy)) / 2.0
    n = sx = sy = 0
    for i in range(w * h):
        if not face[i] and dif(s[i], b[i]) > 8:
            n += 1
            sx += i % w
            sy += i // w
    if n < 40:
        return False, "%s %d: no shadow off the face (%d px changed): the shadow does not follow the setting" % (label, angle, n)
    dx = sx / float(n) - cx
    dy = sy / float(n) - cy
    still = max(1.0, 0.05 * (max(fx) - min(fx)))
    ok = dy > 1 and ((angle == 135 and dx > 1) or (angle == 225 and dx < -1) or (angle == 180 and abs(dx) <= still))
    return ok, "%s %d: shadow centroid %+.1f,%+.1f px from the face centre (%d px off the face)" % (label, angle, dx, dy, n)

def strict(a, b, x, y, w, h, label):
    pa = load(a, x, y, w, h)
    pb = load(b, x, y, w, h)
    differ = sum(1 for p, q in zip(pa, pb) if p != q)
    strong = sum(1 for p, q in zip(pa, pb) if dif(p, q) > 64)
    return strong == 0, "%s: %d px differ, %d strong (> 64)" % (label, differ, strong)

def face_box(path, x, y, w, h):
    b = load(path, x, y, w, h)
    edge = [b[i] for i in range(w * h) if i < w or i >= (h - 1) * w or i % w in (0, w - 1)]
    bg = Counter(edge).most_common(1)[0][0]
    pts = [i for i in range(w * h) if dif(b[i], bg) > 10]
    if not pts:
        return None
    return min(i % w for i in pts), min(i // w for i in pts), max(i % w for i in pts), max(i // w for i in pts)

def shift(base, held, x, y, w, h, label, ex, ey):
    # A held key: its face (the corner of what differs from the background) moves by the shadow vector, whole px.
    a = face_box(base, x, y, w, h)
    b = face_box(held, x, y, w, h)
    if a is None or b is None:
        return False, "%s: no face in the crop" % label
    sx, sy = b[0] - a[0], b[1] - a[1]
    ok = abs(sx - ex) <= 1 and abs(sy - ey) <= 1
    return ok, "%s: the face moved %+d,%+d px while held (the shadow vector %+d,%+d)" % (label, sx, sy, ex, ey)

if __name__ == "__main__":
    if sys.argv[1] == "side":
        ok, msg = side(sys.argv[2], sys.argv[3], int(sys.argv[4]), *[int(v) for v in sys.argv[5:9]], sys.argv[9])
    elif sys.argv[1] == "shift":
        ok, msg = shift(sys.argv[2], sys.argv[3], *[int(v) for v in sys.argv[4:8]], sys.argv[8], int(sys.argv[9]), int(sys.argv[10]))
    else:
        ok, msg = strict(sys.argv[2], sys.argv[3], *[int(v) for v in sys.argv[4:8]], sys.argv[8])
    print(("ok   " if ok else "FAIL ") + msg)
    sys.exit(0 if ok else 1)
PY
# A tree of the shell's files for the harnesses: <frontend dir> → <tree dir>/{frontend,settings}, shots left out. Quickshell
# loads only what sits under the config root (frontend/), so the two webdock files the harness shows (the dock's card and the
# host's key) are copied into frontend/harness/. The copies import the root's core (`qs.core`, the harness's own Theme and
# Store): a second `core` beside them would have a Store that never gets the theme.
harness_tree() {
  local root
  root=$(dirname "$(cd "$1" && pwd)")
  rm -rf "$2"
  mkdir -p "$2"
  tar -C "$root" --exclude=shots -cf - frontend settings/core settings/components | tar -C "$2" -xf -
  mkdir -p "$2/frontend/harness"
  # The dock card's status row reads the live clock: its text is fixed in the copy, so a minute cannot move a shot.
  sed 's|text: card.clock.hh !== undefined ? card.clock.hh + ":" + card.clock.mm : ""|text: "10:24"|' "$root/mods/webdock/qml/Card.qml" > "$2/frontend/harness/Card.qml"
  grep -q 'text: "10:24"' "$2/frontend/harness/Card.qml" || fail "the dock card's clock line changed: update harness_tree"
  sed 's|^import "core"$|import qs.core|' "$root/mods/webdock/host/HostButton.qml" > "$2/frontend/harness/HostButton.qml"
  cp "$W/harness-frontend.qml" "$2/frontend/shadow-harness.qml"
  cp "$W/harness-settings.qml" "$2/settings/shadow-harness.qml"
}
full() { grim -o HEADLESS-1 "$1"; }
# start_qs_file <file>: a shell from one file (a harness; Settings' store needs no hello from the frontend).
start_qs_file() {
  if [ -n "$QS_PID" ]; then kill "$QS_PID" 2>/dev/null || true; wait "$QS_PID" 2>/dev/null || true; QS_PID=; fi
  env -u KURASHI_SOCKET qs -p "$1" > "$R/qs-file.log" 2>&1 &
  QS_PID=$!
  pids+=("$QS_PID")
  sleep 4
}
# The current look, four full shots: the defaults (180), 135 and 225 at strength 2, and strength 0 (no shadow).
s3_look_shots() {  # s3_look_shots <prefix>
  set_ theme.material.shadow 1; set_ theme.material.shadow_angle 180; sleep 1
  full "$1-180.png"
  set_ theme.material.shadow 2; set_ theme.material.shadow_angle 135; sleep 1
  full "$1-135.png"
  set_ theme.material.shadow_angle 225; sleep 1
  full "$1-225.png"
  set_ theme.material.shadow 0; sleep 1
  full "$1-base.png"
}
# s3_press <prefix> <x> <y>: the pointer holds (x,y) for 2.5 s; the shot at 135° strength 2 is taken while it is down. The
# vector the daemon gives for that setting goes to <prefix>-held.vec (whole px: a held key sinks by it).
s3_press() {
  set_ theme.material.shadow 2; set_ theme.material.shadow_angle 135; sleep 1
  toks shadow.dx shadow.dy | python3 -I -c 'import json,sys; v = json.load(sys.stdin); print(int(round(v[0])), int(round(v[1])))' > "$1-held.vec"
  timeout 20 python3 -I "$W/hold.py" "$ROOT/tools/bench/wl_pointer.py" "$2" "$3" 2.5 &
  local hp=$!
  sleep 1.6
  full "$1-held.png"
  wait "$hp" || fail "the held press at $2,$3 failed"
}
# s3_run <tree dir> <tag>: both harnesses, sekai (keycap) and glass (soft), into $W/s3-<tag>-<look>-<front|settings>-*.png.
s3_run() {
  local tree=$1 tag=$2 lk
  start_frontend_dir "$tree/frontend/shadow-harness.qml"
  for lk in sekai glass; do
    look "$lk"
    s3_look_shots "$W/s3-$tag-$lk-front"
    s3_press "$W/s3-$tag-$lk-front" 96 916
  done
  start_qs_file "$tree/settings/shadow-harness.qml"
  for lk in sekai glass; do
    look "$lk"
    s3_look_shots "$W/s3-$tag-$lk-settings"
    s3_press "$W/s3-$tag-$lk-settings" 110 96
  done
  kill "$QS_PID" 2>/dev/null || true; wait "$QS_PID" 2>/dev/null || true; QS_PID=
}
# The crops (name x y w h, output px): each surface's place in its harness with 40 px to spare for its shadow.
S3_FRONT="session 40 40 540 240
keyclock 40 340 320 140
phone 760 40 380 400
dockcard 1160 40 380 420
hostkey 40 860 120 120"
S3_SETTINGS="settingsbutton 40 40 240 120"
S3_FAIL=0
s3_side() {  # s3_side <prefix> <angle> <crops>: each crop's shadow falls to the side the angle names
  local name x y w h
  while read -r name x y w h; do
    python3 -I "$W/px.py" side "$1-base.png" "$1-$2.png" "$2" "$x" "$y" "$w" "$h" "$name" || S3_FAIL=1
  done <<< "$3"
}
s3_same() {  # s3_same <ref prefix> <new prefix> <crops>: the defaults, pixel for pixel (no strong px) in each crop
  local name x y w h
  while read -r name x y w h; do
    python3 -I "$W/px.py" strict "$1-180.png" "$2-180.png" "$x" "$y" "$w" "$h" "$name" || S3_FAIL=1
  done <<< "$3"
}

s3_sheet() {  # s3_sheet <prefix> <out> <crops> <angle>: the crops of one shot side by side, for the eye
  local name x y w h tiles=()
  while read -r name x y w h; do
    magick "$1-$4.png" -crop "${w}x${h}+${x}+${y}" +repage "$W/tile-$name-$4.png"
    tiles+=("$W/tile-$name-$4.png")
  done <<< "$3"
  magick "${tiles[@]}" -background '#202020' -gravity center +append "$2"
}

start_frontend

if want tokens; then
  say "== tokens"
  look sekai
  expect "keycap default" 0 4 1
  look glass
  expect "soft default" 0 6 1
  look none
  expect "flat default" 0 0 1
  look sekai
  for a in 135 225 90 0; do
    for s in 0.5 2; do
      set_ theme.material.shadow "$s"; set_ theme.material.shadow_angle "$a"; sleep 0.6
      # shellcheck disable=SC2046
      expect "keycap $a° × $s" $(vec 4 "$a" "$s")
    done
  done
  set_ theme.material.shadow 0; sleep 0.6
  expect "keycap strength 0" 0 0 0
  look glass
  set_ theme.material.shadow 2; sleep 0.6
  expect "soft × 2 (alpha twice, under 0.9)" 0 12 2
  look sekai
  # Following without a material is inert (and says so); the static direction stays.
  set_ theme.material.shadow_angle 90; set_ theme.material.shadow_follow true; sleep 0.6
  [ "$(reason theme.material.shadow_follow)" = settings.inert.requires ] || fail "shadow_follow without a material is not inert"
  expect "follow without a material: the angle" 4 0
  set_ theme.texture.kind paper; sleep 1.5
  [ "$(reason theme.material.shadow_angle)" = settings.inert.requires ] || fail "shadow_angle is not inert while following"
  for le in "315 40" "45 40" "315 15" "45 70" "0 40"; do
    # shellcheck disable=SC2086
    set -- $le
    set_ theme.light.angle "$1"; set_ theme.light.elevation "$2"; sleep 0.8
    # shellcheck disable=SC2046
    expect "follow light $1° at $2°" $(fvec 4 "$1" "$2" 1)
  done
  # The pointer's lamp casts from where it rests (the static angle): the same vector.
  set_ theme.light.mode pointer; sleep 0.8
  # shellcheck disable=SC2046
  expect "follow the pointer's lamp at rest" $(fvec 4 0 40 1)
fi

if want matrix; then
  say "== matrix"
  for st in sekai glass; do
    look "$st"
    for a in 180 135 225; do
      for s in 0.5 1 2; do
        set_ theme.material.shadow "$s"; set_ theme.material.shadow_angle "$a"; sleep 1
        shot "$st-a$a-s$s-bar" "$BAR"
        card "$st-a$a-s$s-card"
      done
    done
  done
  look sekai
  set_ theme.material.shadow 0; sleep 1
  shot "sekai-s0-bar" "$BAR"
  card "sekai-s0-card"
fi

if want follow; then
  say "== follow"
  for st in sekai glass; do
    look "$st"
    set_ theme.texture.kind paper; set_ theme.material.shadow_follow true
    for le in "315 70" "315 15" "45 70" "45 15"; do
      # shellcheck disable=SC2086
      set -- $le
      set_ theme.light.angle "$1"; set_ theme.light.elevation "$2"; sleep 1.5
      shot "$st-follow-l$1-e$2-bar" "$BAR"
      card "$st-follow-l$1-e$2-card"
    done
  done
fi

# A bar key held down: a virtual pointer presses and holds it (tools/bench/wl_pointer.py's protocol, its press without
# the release), the shot is taken while it is down.
cat > "$W/hold.py" <<'PY'
import importlib.util, struct, sys, time
spec = importlib.util.spec_from_file_location("wl_pointer", sys.argv[1])
wp = importlib.util.module_from_spec(spec); spec.loader.exec_module(wp)
x, y, secs = int(sys.argv[2]), int(sys.argv[3]), float(sys.argv[4])
p = wp.Pointer()
p.motion(x, y); p.roundtrip(); time.sleep(0.3)
p.send(p.pointer, 2, struct.pack("<III", wp.ms(), wp.BUTTONS["left"], 1)); p.send(p.pointer, 4); p.roundtrip()
time.sleep(secs)
p.send(p.pointer, 2, struct.pack("<III", wp.ms(), wp.BUTTONS["left"], 0)); p.send(p.pointer, 4); p.settle()
PY
if want press; then
  say "== press"
  look sekai
  set_ theme.material.shadow 2; set_ theme.material.shadow_angle 135; sleep 1
  # The island card's Close key (a Block button); its release closes the card.
  PX=${SHADOW_PRESS_X:-1125}; PY_=${SHADOW_PRESS_Y:-425}
  K act island.expand >/dev/null || fail "island.expand"
  sleep 1.6
  KEY="$((PX - 50)),$((PY_ - 30)) 110x64"
  shot "sekai-a135-s2-key-up" "$KEY"
  timeout 20 python3 -I "$W/hold.py" "$ROOT/tools/bench/wl_pointer.py" "$PX" "$PY_" 2.5 &
  hp=$!
  sleep 1.6
  shot "sekai-a135-s2-key-down" "$KEY"
  wait "$hp" || fail "the held press failed"
  sleep 1.5
  K act ui.close >/dev/null 2>&1 || true
  sleep 1.2
fi

if want surfaces; then
  say "== surfaces"
  for st in sekai glass; do
    look "$st"
    set_ theme.material.shadow 2; set_ theme.material.shadow_angle 135; sleep 1
    K act quick.toggle >/dev/null || fail "quick.toggle"
    sleep 1.8
    shot "$st-a135-s2-quick" "1040,0 1520x900"
    K act ui.close >/dev/null || true; sleep 1.2
    K act sidebar.toggle '{"side":"right","output":"HEADLESS-1"}' >/dev/null || fail "sidebar.toggle"
    sleep 1.8
    shot "$st-a135-s2-sidebar-right" "1860,0 700x900"
    K act sidebar.toggle '{"side":"right","output":"HEADLESS-1"}' >/dev/null || true; sleep 1.4
  done
fi

if want settings; then
  say "== settings"
  look sekai
  set_ theme.material.shadow 1.5; set_ theme.material.shadow_angle 135; sleep 1
  sq static
  set_ theme.texture.kind paper; set_ theme.material.shadow_follow true; set_ theme.light.angle 45; sleep 1.5
  sq follow
fi

if want ma; then
  say "== ma"
  look sekai
  set_ theme.texture.kind paper; set_ theme.material.shadow_follow true; set_ theme.light.mode pointer; sleep 1.5
  start_frontend WAYLAND_DEBUG=1
  sleep 2
  commits() { grep -c 'wl_surface#[0-9]*\.commit(' "$R/qs.log" || true; }
  # Which surfaces committed after byte offset $1, with their layer namespaces.
  who() {
    tail -c +"$(( $1 + 1 ))" "$R/qs.log" | grep -oE 'wl_surface#[0-9]+\.commit\(' | sort | uniq -c | while read -r n s; do
      id=${s%.commit(}
      ns=$(grep -oE "get_layer_surface\(new id zwlr_layer_surface_v1#[0-9]+, $id, [^\"]*\"[^\"]*\"" "$R/qs.log" | tail -1 | grep -oE '"[^"]*"$' || true)
      echo "    $n × $id ${ns:-?}"
    done
  }
  # The pointer sweeps the desktop (below the bar) for 3 s; the frames committed meanwhile.
  sweep() {
    local b0 c0
    b0=$(stat -c %s "$R/qs.log"); c0=$(commits)
    timeout 20 python3 -I "$ROOT/tools/bench/wl_pointer.py" sweep 300 700 2200 1200 3 || fail "sweep"
    sleep 0.5
    SWEPT=$(( $(commits) - c0 ))
    [ "$SWEPT" = 0 ] || who "$b0"
  }
  # A static light: following adds nothing to draw while the pointer moves.
  set_ theme.light.mode static; sleep 1.5
  sweep
  [ "$SWEPT" = 0 ] && say "ok   static light, following on, the pointer moving for 3 s: 0 frames" \
    || fail "static light, following on: the pointer moving committed $SWEPT frames"
  # The pointer's lamp (K61) moves the relief over the surfaces under the pointer by itself; following must add
  # nothing to that (the shadows cast from where the lamp rests).
  set_ theme.material.shadow_follow false; set_ theme.light.mode pointer; sleep 1.5
  sweep; base=$SWEPT
  set_ theme.material.shadow_follow true; sleep 1.5
  sweep
  [ "$SWEPT" -le "$base" ] && say "ok   the pointer's lamp: $SWEPT frames with following on, $base without (the lamp's own)" \
    || fail "following on the pointer's lamp added frames ($SWEPT with, $base without)"
  # A light change (the daytime sun moving, here a new angle) repaints once and then the shell is still again.
  set_ theme.light.mode static; sleep 1.5
  c2=$(commits)
  set_ theme.light.angle 45; sleep 1.5
  c3=$(commits)
  [ "$c3" -gt "$c2" ] || fail "a new light direction did not repaint the shadows"
  sleep 2
  c4=$(commits); sleep 3; c5=$(commits)
  [ "$c5" = "$c4" ] && say "ok   a light change repainted ($((c3 - c2)) commits) and settled (0 in 3 s)" \
    || fail "after a light change the shell kept committing ($((c5 - c4)) in 3 s)"
fi

e=$(qml_errors)
[ -z "$e" ] || { echo "$e" | head -20; fail "QML errors (see $R/qs.log)"; }

if want surfaces3; then
  say "== surfaces3"
  harness_tree "$ROOT/frontend" "$W/tree-new"
  s3_run "$W/tree-new" new
  e=$(qml_errors)
  [ -z "$e" ] || { echo "$e" | head -20; fail "QML errors in the surfaces3 harness (see $R/qs.log)"; }
  e=$(grep -E "TypeError|ReferenceError|is not a type|Cannot assign|is not defined|Unable to assign|Cannot read property" "$R/qs-file.log" || true)
  [ -z "$e" ] || { echo "$e" | head -20; fail "QML errors in the Settings harness (see $R/qs-file.log)"; }
  # Settings' button has a hard shadow only (as SectionCard does): under soft chrome it casts none, so only keycap is checked.
  for a in 135 225 180; do
    s3_side "$W/s3-new-sekai-front" "$a" "$S3_FRONT"
    s3_side "$W/s3-new-glass-front" "$a" "$S3_FRONT"
    s3_side "$W/s3-new-sekai-settings" "$a" "$S3_SETTINGS"
  done
  for lk in sekai glass; do
    for a in 135 225; do
      s3_sheet "$W/s3-new-$lk-front" "$OUT/surfaces3-$lk-$a.png" "$S3_FRONT" "$a"
    done
  done
  # Held (keycap, 135°, strength 2): the web host's key sinks onto its shadow, so its face moves by the vector; Settings'
  # button keeps its face and shows a 1 px shadow, still down and to the right.
  read -r ex ey < "$W/s3-new-sekai-front-held.vec"
  python3 -I "$W/px.py" shift "$W/s3-new-sekai-front-base.png" "$W/s3-new-sekai-front-held.png" 40 860 120 120 hostkey-held "$ex" "$ey" || S3_FAIL=1
  python3 -I "$W/px.py" side "$W/s3-new-sekai-settings-base.png" "$W/s3-new-sekai-settings-held.png" 135 40 40 240 120 settingsbutton-held || S3_FAIL=1
  [ "$S3_FAIL" = 0 ] || fail "surfaces3: a shadow is not on the side its angle names, or a held key does not sink (see above)"
  say "ok   surfaces3: every surface's shadow falls to its side at 135 and 225, straight down at 180 ($OUT/surfaces3-*.png)"
fi

if want inert; then
  say "== inert"
  # Flat (none) and line (kami) chrome: the three shadow rows are inert, and say why (K67 amendment, row 423).
  for lk in none kami; do
    look "$lk"
    for row in shadow shadow_angle shadow_follow; do
      [ "$(reason theme.material.$row)" = settings.inert.requires ] || fail "theme.material.$row is not inert under $lk"
    done
    sq "inert-$lk-en" "$ROOT/settings" "$OUT/settings-inert-$lk-en.png"
  done
  # Japanese: the daemon reads its locale from the environment (LC_ALL first, kurashid i18n.rs); the same two looks.
  stop_daemon
  export LC_ALL=ja_JP.UTF-8
  start_daemon
  for lk in none kami; do
    look "$lk"
    sq "inert-$lk-ja" "$ROOT/settings" "$OUT/settings-inert-$lk-ja.png"
  done
  stop_daemon
  export LC_ALL=C.UTF-8
  start_daemon
fi

if want surfaces2; then
  say "== surfaces2"
  for lk in sekai glass; do
    surf2 "$ROOT/frontend" "$OUT/surf2-$lk-a135-s2" "$lk" 135 2
    say "ok   $lk: the surfaces at 135 strength 2 (surf2-$lk-a135-s2-*.png)"
  done
  # The left and the upward reach (the windows take the slack there too): sekai at 225 and at 0, strength 2.
  for ang in 225 0; do
    surf2 "$ROOT/frontend" "$OUT/surf2-sekai-a$ang-s2" sekai "$ang" 2
    say "ok   sekai: the surfaces at $ang strength 2 (surf2-sekai-a$ang-s2-*.png)"
  done
fi

# identity (SHADOW_REF, see the header): at the defaults every look draws pixel for pixel what the reference draws — the
# bar, the island's card and quick settings (keycap, soft, flat, line), and the surfaces2 shots under sekai and glass.
if [ -n "${SHADOW_REF:-}" ]; then
  say "== identity against $SHADOW_REF"
  idshots() {  # idshots <frontend dir> <tag>
    start_frontend_dir "$1"
    for st in sekai glass washi terminal; do
      look "$st"
      grim -g "0,0 2560x52" "$W/id-$2-$st-bar.png"
      K act island.expand >/dev/null; sleep 1.6; grim -g "$CARD" "$W/id-$2-$st-card.png"
      K act ui.close >/dev/null; sleep 1.2
      K act quick.toggle >/dev/null; sleep 1.8; grim -g "1040,0 1520x900" "$W/id-$2-$st-quick.png"
      K act ui.close >/dev/null; sleep 1.2
    done
  }
  K reset theme >/dev/null 2>&1 || true
  idshots "$SHADOW_REF" ref
  # SHADOW_NEW=<the same ref dir>: the noise floor (two runs of one frontend).
  idshots "${SHADOW_NEW:-$ROOT/frontend}" new
  bad=0
  for st in sekai glass washi terminal; do
    for part in bar card quick; do
      same_px "$W/id-ref-$st-$part.png" "$W/id-new-$st-$part.png" "$st $part" || bad=1
    done
  done
  # The surfaces at the defaults (I206): the same shots from the reference frontend and from this one, under two looks.
  for st in sekai glass; do
    mkdir -p "$W/id2-ref-$st" "$W/id2-new-$st"
    surf2 "$SHADOW_REF" "$W/id2-ref-$st/surf2" "$st"
    surf2 "${SHADOW_NEW:-$ROOT/frontend}" "$W/id2-new-$st/surf2" "$st"
    for part in sidebar toast-drip toast-slide centre polkit settings lock; do
      same_px "$W/id2-ref-$st/surf2-$part.png" "$W/id2-new-$st/surf2-$part.png" "$st $part" || bad=1
    done
  done
  # The surfaces3 harnesses at the defaults (W42): the reference's crops against this shell's, pixel for pixel (0 strong px).
  harness_tree "$SHADOW_REF" "$W/tree-ref"
  s3_run "$W/tree-ref" ref
  [ -f "$W/s3-new-sekai-front-180.png" ] || { harness_tree "${SHADOW_NEW:-$ROOT/frontend}" "$W/tree-new"; s3_run "$W/tree-new" new; }
  S3_FAIL=0
  for lk in sekai glass; do
    s3_same "$W/s3-ref-$lk-front" "$W/s3-new-$lk-front" "$S3_FRONT"
    s3_same "$W/s3-ref-$lk-settings" "$W/s3-new-$lk-settings" "$S3_SETTINGS"
  done
  [ "$S3_FAIL" = 0 ] || bad=1
  [ "$bad" = 0 ] || fail "the defaults do not draw what they drew before W39 (shots in $W/id-*.png, $W/id2-*/)"
fi

if command -v magick >/dev/null && [ -f "$OUT/sekai-a180-s1-card.png" ]; then
  # The contact sheet: per chrome, rows of angle, columns of strength (the card with the bar's groups above it).
  tiles=()
  # ImageMagick's default font may not exist here: the labels use fontconfig's sans file.
  FONT=$(fc-match -f '%{file}' sans 2>/dev/null || true)
  [ -n "$FONT" ] || FONT=DejaVu-Sans
  for st in sekai glass; do
    for a in 180 135 225; do
      for s in 0.5 1 2; do
        [ -f "$OUT/$st-a$a-s$s-card.png" ] || continue
        magick "$OUT/$st-a$a-s$s-bar.png" -resize 840x "$OUT/$st-a$a-s$s-card.png" -append \
          -gravity north -background '#202020' -splice 0x44 -fill white -font "$FONT" -pointsize 34 \
          -annotate +0+4 "$st  angle $a  strength $s" "$W/t-$st-$a-$s.png"
        tiles+=("$W/t-$st-$a-$s.png")
      done
    done
  done
  for st in sekai glass; do
    for le in "315 70" "315 15" "45 70" "45 15"; do
      # shellcheck disable=SC2086
      set -- $le
      f="$OUT/$st-follow-l$1-e$2-card.png"
      [ -f "$f" ] || continue
      magick "$OUT/$st-follow-l$1-e$2-bar.png" -resize 840x "$f" -append \
        -gravity north -background '#202020' -splice 0x44 -fill white -font "$FONT" -pointsize 34 \
        -annotate +0+4 "$st  follow: light $1°  height $2°" "$W/f-$st-$1-$2.png"
      tiles+=("$W/f-$st-$1-$2.png")
    done
  done
  magick montage "${tiles[@]}" -tile 3x -geometry 420x+6+6 -background '#202020' "$OUT/sheet.png"
  say "$OUT/sheet.png"
  if [ -f "$OUT/sekai-a135-s2-key-down.png" ]; then
    # The held key, up and down, four times as large: the face sinks onto its shadow, down to the right.
    magick "$OUT/sekai-a135-s2-key-up.png" "$OUT/sekai-a135-s2-key-down.png" +append -scale 400% "$OUT/sheet-press.png"
    say "$OUT/sheet-press.png"
  fi
fi
say "ok"
