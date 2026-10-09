#!/usr/bin/env bash
# Mod QML in the bar, the Island and the Stage (K26, K28), invisibly (headless sway sandbox). The test mod `hello`
# (crates/kurashid/tests/data/mods/hello/qml, or $KURASHI_MOD_HELLO) logs `MODQML <what> created|destroyed` for every
# component it instantiates, so the test counts what loads and when it goes. Two daemons:
#   1. the prebuilt kurashid ($KURASHI_BIN_DIR): `hello` is not linked into it (native::linked() is empty), so it is
#      listed with no qml map, and `mod.enable hello` is refused: the disabled path, against the real daemon;
#   2. a stand-in in front of kurashi-mock (embedded below, frontend tests only): it serves `mods`, `runtime.slots`
#      and `mod.enable`/`mod.disable` as kurashid does for a linked `hello`, and refuses `mod.panel.open` while the
#      mod is off. Everything else goes to the mock. Retire it once a kurashid that links `hello` is built for tests.
# Steps (stand-in): mod off, nothing; mod.enable, the bar widget and the clock card's footer and aside (the day
# contribution is not ready: never loads); mod.panel.open, the Stage card shows the panel and the clock's slots are
# gone; ui.close; panel open then mod.disable, the panel and the widget go and no panel is named; the mod's island face
# and its expanded card; media slots (backdrop, below); the notification header; the quick tile.
# The frontend logs no QML warning: no qml/scene WARN or ERROR, no binding loop, no reference or type error.
# Screenshots: frontend/shots/modqml/. Usage:
#   KURASHI_RENDER_NODE=/dev/dri/renderD129 KURASHI_BIN_DIR=<dir with kurashi, kurashid, kurashi-mock> \
#     timeout 900 nix develop -c frontend/test-modqml.sh [sandbox-name]
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
NAME=${1:-fe-modqml}
BIN=${KURASHI_BIN_DIR:-${CARGO_TARGET_DIR:-$ROOT/target}/debug}
MOCK_BIN=${KURASHI_MOCK_BIN:-$BIN/kurashi-mock}
HELLO=${KURASHI_MOD_HELLO:-$ROOT/crates/kurashid/tests/data/mods/hello}
OUT=$ROOT/frontend/shots/modqml
mkdir -p "$OUT"
fail() { echo "test-modqml: $*" >&2; exit 1; }

eval "$("$ROOT/tools/bench/sandbox.sh" start "$NAME")"
R=$XDG_RUNTIME_DIR
W=$R/work
mkdir -p "$W" "$R/kurashi"
cp "$BIN/kurashi" "$BIN/kurashid" "$W/"
cp "$MOCK_BIN" "$W/kurashi-mock"

pids=()
stop_phase() {  # kills only the processes this script started
  for p in "${pids[@]}"; do kill "$p" 2>/dev/null || true; done
  for p in "${pids[@]}"; do wait "$p" 2>/dev/null || true; done
  pids=()
  rm -f "$KURASHI_SOCKET" "$KURASHI_SOCKET.mock"
}
cleanup() {
  stop_phase
  "$ROOT/tools/bench/sandbox.sh" stop "$NAME" >/dev/null || true
}
trap cleanup EXIT

rm -rf "$R/xdg"   # hermetic: a config left by an earlier run would leave `hello` enabled
export XDG_CONFIG_HOME=$R/xdg/config XDG_STATE_HOME=$R/xdg/state \
       XDG_DATA_HOME=$R/xdg/data XDG_CACHE_HOME=$R/xdg/cache KURASHI_DATA_DIR=$ROOT LC_ALL=C.UTF-8
mkdir -p "$XDG_CONFIG_HOME" "$XDG_STATE_HOME" "$XDG_DATA_HOME" "$XDG_CACHE_HOME"
# The real kurashid discovers the test mod in its data dir (kurashid/src/main.rs roots); it is not linked, so it is off.
mkdir -p "$XDG_DATA_HOME/kurashi/mods"
ln -sfn "$HELLO" "$XDG_DATA_HOME/kurashi/mods/hello"

# `ipc.py <doc>` prints the first snapshot's data of a document (plain stdlib, as in test-stage.sh).
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
ipc() { timeout 10 python3 -I "$W/ipc.py" "$@"; }
K() { timeout 10 "$W/kurashi" "$@"; }

# The stand-in: kurashi-mock behind a proxy that serves `hello` the way kurashid does for a linked mod.
cat > "$W/standin.py" <<'PY'
import asyncio
import json
import os
import signal
import subprocess
import sys

SOCK = os.environ["KURASHI_SOCKET"]
MOCK_SOCK = SOCK + ".mock"
MOCK_BIN, HELLO_DIR, MOCK_ARGS = sys.argv[1], sys.argv[2], sys.argv[3:]
mock = subprocess.Popen([MOCK_BIN, *MOCK_ARGS, "--socket", MOCK_SOCK])


def stop(*_):
    mock.terminate()
    os._exit(0)


signal.signal(signal.SIGTERM, stop)
signal.signal(signal.SIGINT, stop)

NAME = "hello"
# The provides kurashid would list for hello: its manifest (mod.toml) plus the widget and slots the frontend needs.
# The manifest is not this card's file (docs/CONTRACT-CHANGE.md asks for these provides).
PROVIDES = [
    "service:hello", "action:hello.*", "island-face:hello", "panel:hello", "widget:hello",
    "slot:clock.expanded.footer", "slot:clock.expanded.aside", "slot:clock.expanded.day",
    "slot:media.expanded.below", "slot:media.expanded.backdrop", "slot:notifications.expanded.header",
    "slot:quick.tiles", "choices:hello.greetings",
]
NOT_READY = {"clock.expanded.day"}   # kurashid lists a contribution whose primary document is not available
state = {"state": "disabled"}        # loaded and off, as the mod starts


def files():
    # The `qml` map kurashid builds for an enabled native mod: only the files that exist (native.rs qml_of).
    d = os.path.join(HELLO_DIR, "qml")
    out = {}

    def add(key, rel):
        p = os.path.join(d, rel)
        if os.path.isfile(p):
            out[key] = "file://" + os.path.abspath(p)

    for p in PROVIDES:
        kind, _, rest = p.partition(":")
        if kind == "widget":
            add(p, "Widget.qml")
        elif kind == "panel":
            add(p, "Panel.qml")
        elif kind == "island-face":
            add(p, "Face.qml")
            add(p + ":expanded", "FaceExpanded.qml")
        elif kind == "slot":
            add(p, "slots/%s.qml" % rest)
    return out


def mods_data():
    e = {"id": NAME, "name": "Hello", "version": "0.1.0", "tier": "native", "state": state["state"],
         "running": False, "capabilities": [], "cost": "low", "provides": PROVIDES, "errors": [],
         "shadows_bundled": False}
    if state["state"] == "enabled":
        e["qml"] = files()
    return {"mods": [e]}


def slots_data():
    if state["state"] != "enabled":
        return {}
    out = {}
    q = files()
    for p in PROVIDES:
        if p.startswith("slot:") and p in q:
            slot = p[len("slot:"):]
            out.setdefault(slot, []).append({"mod": NAME, "qml": q[p], "ready": slot not in NOT_READY})
    return out


OWNED = {"mods": mods_data, "runtime.slots": slots_data}
clients = set()


class Client:
    def __init__(self, w):
        self.w = w
        self.subs = set()
        self.rev = {}

    def send(self, obj):
        self.w.write((json.dumps(obj) + "\n").encode())

    def snap(self, doc, rid=None):
        self.rev[doc] = self.rev.get(doc, 0) + 1
        m = {"t": "snap", "doc": doc, "rev": self.rev[doc], "data": OWNED[doc]()}
        if rid is not None:
            m["id"] = rid
        self.send(m)


def set_state(new):
    state["state"] = new
    for c in list(clients):
        for doc in OWNED:
            if doc in c.subs:
                c.snap(doc)


async def upstream(c, r):
    while True:
        line = await r.readline()
        if not line:
            return
        try:
            m = json.loads(line)
        except ValueError:
            c.w.write(line)
            continue
        if m.get("doc") in OWNED or m.get("id") == "standin-close":
            continue
        c.w.write(line)


async def downstream(c, r, uw):
    while True:
        line = await r.readline()
        if not line:
            return
        try:
            m = json.loads(line)
        except ValueError:
            uw.write(line)
            await uw.drain()
            continue
        t, doc, rid = m.get("t"), m.get("doc"), m.get("id")
        if t == "sub" and doc in OWNED:
            c.subs.add(doc)
            c.snap(doc, rid)
            continue
        if t == "resync" and doc in OWNED:
            if doc in c.subs:
                c.snap(doc, rid)
            continue
        if t == "unsub" and doc in OWNED:
            c.subs.discard(doc)
            continue
        if t == "act":
            action, args = m.get("action"), m.get("args") or {}
            if action in ("mod.enable", "mod.disable"):
                if args.get("id") != NAME:
                    c.send({"t": "err", "id": rid, "kind": "not_found", "msg": "mods.error.not_declared"})
                    continue
                if action == "mod.enable":
                    set_state("enabled")
                else:
                    if state["state"] == "enabled":
                        # kurashid closes a mod's panel when the mod goes off (the Stage card would be stale).
                        uw.write((json.dumps({"t": "act", "id": "standin-close", "action": "ui.close",
                                              "args": {}}) + "\n").encode())
                        await uw.drain()
                    set_state("disabled")
                c.send({"t": "done", "id": rid})
                continue
            if action == "mod.panel.open" and args.get("id") == NAME and state["state"] != "enabled":
                c.send({"t": "err", "id": rid, "kind": "invalid", "msg": "mods.error.panel_unavailable"})
                continue
        uw.write(line)
        await uw.drain()


async def handle(r, w):
    ur, uw = await asyncio.open_unix_connection(MOCK_SOCK)
    c = Client(w)
    clients.add(c)
    up = asyncio.ensure_future(upstream(c, ur))
    try:
        await downstream(c, r, uw)
    except (ConnectionError, asyncio.IncompleteReadError):
        pass
    finally:
        clients.discard(c)
        up.cancel()
        uw.close()
        w.close()


async def main():
    while not os.path.exists(MOCK_SOCK):
        await asyncio.sleep(0.05)
    if os.path.exists(SOCK):
        os.unlink(SOCK)
    server = await asyncio.start_unix_server(handle, path=SOCK)
    async with server:
        await server.serve_forever()


asyncio.run(main())
PY

# Card geometry from a screenshot (PPM): the card's surface colour in the output's centre column.
cat > "$W/analyse.py" <<'PY'
import json, sys

SURFACE = (0x25, 0x23, 0x29)   # color.surface_container in the mock's theme
TOL = 3
X0, X1, Y0, Y1 = 960, 1600, 40, 900   # the output is 2560 wide: a card is centred on 1280, under the 36 px bar


def read_ppm(data):
    # Four whitespace-separated fields (magic, width, height, maxval), one whitespace byte, the raster.
    fields, i = [], 0
    while len(fields) < 4:
        while data[i:i + 1].isspace():
            i += 1
        j = i
        while not data[j:j + 1].isspace():
            j += 1
        fields.append(data[i:j])
        i = j
    if fields[0] != b"P6" or fields[3] != b"255":
        raise SystemExit(f"not an 8-bit P6 image: {fields}")
    return int(fields[1]), int(fields[2]), data[i + 1:]


with open(sys.argv[1], "rb") as f:
    w, h, raster = read_ppm(f.read())
n = 0
x0 = y0 = 1 << 30
x1 = y1 = -1
for y in range(Y0, min(Y1, h)):
    row = y * w * 3
    for x in range(X0, min(X1, w)):
        o = row + x * 3
        if (abs(raster[o] - SURFACE[0]) <= TOL and abs(raster[o + 1] - SURFACE[1]) <= TOL
                and abs(raster[o + 2] - SURFACE[2]) <= TOL):
            n += 1
            x0, x1 = min(x0, x), max(x1, x)
            y0, y1 = min(y0, y), max(y1, y)
print(json.dumps({"surface": n, "bbox": [x0, y0, x1, y1] if n else None}))
PY
analyse() { timeout 60 python3 -I "$W/analyse.py" "$W/$1.ppm"; }

ppm_shot() {  # ppm_shot <name> <seconds>: waits, then takes the whole output as a PPM for the analysis
  sleep "$2"
  timeout 20 grim -o HEADLESS-1 -t ppm "$W/$1.ppm" || fail "grim failed on $1"
}
# card <name> <width>: the card is drawn at the width asked for, centred on the output; the crop is the evidence shot.
card() {
  local res x0 y0 x1 y1 cx cy
  ppm_shot "$1" 2.5
  res=$(analyse "$1") || fail "$1: analysis failed"
  echo "$1: $res"
  jq -e --argjson w "$2" '.surface >= 15000 and .bbox != null
      and (((.bbox[2] - .bbox[0] + 1) - ($w - 2)) | fabs) <= 4
      and (((.bbox[0] + .bbox[2]) / 2 - 1280) | fabs) <= 4' <<<"$res" >/dev/null \
    || fail "$1: no card of width $2 centred on the output ($res)"
  read -r x0 y0 x1 y1 < <(jq -r '.bbox | "\(.[0]) \(.[1]) \(.[2]) \(.[3])"' <<<"$res")
  cx=$((x0 - 24)); cy=$((y0 - 24))
  ((cx < 0)) && cx=0
  ((cy < 0)) && cy=0
  timeout 20 grim -g "$cx,$cy $((x1 - x0 + 49))x$((y1 - y0 + 49))" "$OUT/$1.png" || fail "grim failed on $1"
}
# closed <name>: no card is drawn (Ma: the Stage is empty once closed).
closed() {
  local res
  ppm_shot "$1" 1.5
  res=$(analyse "$1") || fail "$1: analysis failed"
  echo "$1: $res"
  jq -e '.surface < 500' <<<"$res" >/dev/null || fail "$1: a card is still drawn ($res)"
}
# bar <name>: the whole top bar (the Island's face and the mod's widget), as evidence.
bar() { timeout 20 grim -g "0,0 2560x36" "$OUT/$1.png" || fail "grim failed on $1"; }
shot() { timeout 20 grim -o HEADLESS-1 "$OUT/$1.png" || fail "grim failed on $1"; }

# Log counts: the test mod's lifetime lines in this phase's qs.log (one frontend per phase).
mq() { grep -c -F "MODQML $1" "$R/qs.log" || true; }
expect() {  # expect <what> <label> <count>
  local got
  got=$(mq "$1")
  [ "$got" -eq "$3" ] || fail "$2: MODQML '$1' seen $got times, want $3"
  echo "log: $2 ($1 x$got)"
}
# The frontend's QML warnings: any qml or scene WARN/ERROR (quickshell's socket and compositor notices are not QML),
# binding loops, reference and type errors.
qml_warnings() {
  grep -E '(WARN|ERROR)[^:]*(qml|scene)|Binding loop|ReferenceError|TypeError|is not a function|Unable to assign|Expected a qualified' "$R/qs.log" || true
}
no_qml_warnings() {  # no_qml_warnings <label>
  local w
  w=$(qml_warnings)
  if [ -n "$w" ]; then
    echo "$w" | head -20 >&2
    fail "$1: $(echo "$w" | wc -l) QML warning line(s) in qs.log"
  fi
  echo "log: $1: no QML warnings"
}

start_frontend() {
  : > "$R/qs.log"
  # Without KURASHI_SOCKET: the frontend must find the socket by the protocol default, as in a live session.
  env -u KURASHI_SOCKET qs -p "$ROOT/frontend" >> "$R/qs.log" 2>&1 &
  pids+=("$!")
  sleep 3   # the bar's documents and the first frames
}
wait_socket() {  # wait_socket <what>: the daemon serves svc.clock
  for _ in $(seq 100); do [ -S "$KURASHI_SOCKET" ] && ipc svc.clock >/dev/null 2>&1 && return 0; sleep 0.1; done
  fail "$1 did not come up (see $R/server.log)"
}

# ---- Phase 1: the prebuilt kurashid. It links no native mod, so `hello` has no runtime side. Its answers to
# `mod.enable` and to the panel are recorded (PROTOCOL §5/§8); the frontend must load what the daemon's `qml` map names
# and drop it when the mod goes off.
: > "$R/server.log"
RUST_LOG=info "$W/kurashid" >> "$R/server.log" 2>&1 &
pids+=("$!")
wait_socket kurashid
start_frontend
ipc mods | jq -c '.mods[] | select(.id == "hello")' | tee "$R/real-off.json"
ipc runtime.slots | jq -e '. == {}' >/dev/null || fail "real kurashid: runtime.slots lists something while hello is off"
K act mod.enable '{"id":"hello"}' >/dev/null || true
sleep 1
ipc mods | jq -c '.mods[] | select(.id == "hello")' | tee "$R/real-on.json"
ipc runtime.slots | tee "$R/real-slots-on.json"
if jq -e '.state == "enabled" and (.qml["panel:hello"] != null)' "$R/real-on.json" >/dev/null; then
  K act mod.panel.open '{"id":"hello","panel":"hello"}' || true
  sleep 2
  ipc runtime.ui | tee "$R/real-ui-panel.json"
  shot real-panel
  expect "panel created" "real kurashid: the panel loads from the daemon's qml map" 1
  K act mod.disable '{"id":"hello"}' >/dev/null || true
  sleep 2
  expect "panel destroyed" "real kurashid: disabling the mod destroys the panel" 1
  ipc mods | jq -e '[.mods[] | select(.id == "hello") | has("qml")] == [false]' >/dev/null \
    || fail "real kurashid: hello still has a qml map after mod.disable"
else
  echo "real kurashid: the enable did not take (see $R/real-on.json); nothing of the mod loads"
  expect "" "real kurashid: no MODQML line" 0
fi
no_qml_warnings "real kurashid"
stop_phase

# ---- Phase 2: the stand-in (kurashi-mock behind a proxy that serves `hello` as a linked kurashid would).
: > "$R/server.log"
RUST_LOG=info python3 -I "$W/standin.py" "$W/kurashi-mock" "$HELLO" --outputs HEADLESS-1 --fixed-time 12:34 \
  >> "$R/server.log" 2>&1 &
pids+=("$!")
wait_socket "stand-in"
start_frontend

# 1. mod off: the bar and the clock card instantiate nothing of the mod.
ipc mods | jq -e '[.mods[] | select(.id == "hello") | has("qml")] == [false]' >/dev/null \
  || fail "mods: hello has a qml map while it is off"
K act island.expand >/dev/null
card clock-mod-off 400
K act ui.close >/dev/null
closed closed-mod-off
bar bar-mod-off
expect "" "mod off: no MODQML line" 0

# 2. mod.enable: the bar widget, and the clock card's footer and aside (the day contribution is not ready).
K act mod.enable '{"id":"hello"}' >/dev/null
sleep 1.5
expect "widget created" "enabled: bar widget loaded" 1
ipc runtime.slots | jq -e '(."clock.expanded.footer" | length) == 1 and ."clock.expanded.footer"[0].ready == true
    and ((."clock.expanded.day" // []) | map(select(.ready == true)) | length) == 0' >/dev/null \
  || fail "runtime.slots does not list the ready footer and no ready day contribution"
bar bar-widget
K act island.expand >/dev/null
card clock-slots 400
expect "slot clock.expanded.footer created" "enabled: footer in the clock card" 1
expect "slot clock.expanded.aside created" "enabled: aside in the clock card" 1
expect "slot clock.expanded.day created" "not ready: the day contribution never loads" 0

# 3. mod.panel.open: the panel replaces the clock card; its slots are destroyed (no stale component).
K act mod.panel.open '{"id":"hello","panel":"hello"}' >/dev/null
ipc runtime.ui | jq -e '.panel == "mod:hello:hello"' >/dev/null || fail "runtime.ui does not name the mod panel"
card mod-panel 360
expect "panel created" "panel open: the hello panel loads" 1
expect "slot clock.expanded.footer destroyed" "panel open: the footer is gone" 1
expect "slot clock.expanded.aside destroyed" "panel open: the aside is gone" 1

# 4. ui.close: the panel is destroyed; nothing is drawn.
K act ui.close >/dev/null
closed closed-panel
expect "panel destroyed" "closed: the panel is destroyed" 1

# 5. the panel open, then mod.disable: the panel and the widget go; the card closes; no panel is named.
K act mod.panel.open '{"id":"hello","panel":"hello"}' >/dev/null
sleep 2
expect "panel created" "panel open again" 2
K act mod.disable '{"id":"hello"}' >/dev/null
sleep 2
expect "panel destroyed" "disabled with the panel open: the panel is destroyed" 2
expect "widget destroyed" "disabled: the widget is destroyed" 1
ipc runtime.ui | jq -e '(.panel // "") == ""' >/dev/null || fail "runtime.ui still names a panel after mod.disable"
closed closed-disabled
bar bar-widget-gone

# 6. the island face of the mod: drawn with the mod on, the clock stands in with it off.
K act mod.enable '{"id":"hello"}' >/dev/null
sleep 1.5
expect "widget created" "re-enabled: the widget loads again" 2
K mock face hello >/dev/null
sleep 2
expect "face created" "enabled: the island draws the mod face" 1
bar bar-face-hello
K act island.expand >/dev/null
card face-expanded 360
expect "face-expanded created" "the expanded face loads in the card" 1
K act ui.close >/dev/null
closed closed-face
expect "face-expanded destroyed" "closed: the expanded face is destroyed" 1
K act mod.disable '{"id":"hello"}' >/dev/null
sleep 2
expect "face destroyed" "disabled: the mod face is destroyed" 1
bar bar-face-fallback

# 7. media: the card's aside-less slots, backdrop and the line under the transport.
K act mod.enable '{"id":"hello"}' >/dev/null
sleep 1.5
K mock face media >/dev/null
sleep 1
K act island.expand >/dev/null
card media-slots 400
expect "slot media.expanded.backdrop created" "media card: the backdrop loads" 1
expect "slot media.expanded.below created" "media card: the line under the transport loads" 1
K act ui.close >/dev/null
closed closed-media

# 8. notifications: the header row in the notifications face's expanded card (the centre is its own surface);
# 9. quick settings: the tile.
K mock face notifications >/dev/null
sleep 1
K act island.expand >/dev/null
card notifications-header 360
expect "slot notifications.expanded.header created" "notifications: the header loads" 1
K act ui.close >/dev/null
closed closed-notifications
K act quick.toggle >/dev/null
card quick-tiles 360
expect "slot quick.tiles created" "quick settings: the tile loads" 1
K act ui.close >/dev/null
closed closed-quick

# 10. mod.disable with everything closed: every component of the mod is gone. The widget was enabled three times (steps
# 2, 6 and 7) and the island face shown twice (step 6, and again on the re-enable in step 7, before the media face).
K act mod.disable '{"id":"hello"}' >/dev/null
sleep 2
expect "widget created" "the widget loaded once per enable" 3
expect "widget destroyed" "disabled: the widget is gone" 3
expect "face created" "the island showed the mod face twice" 2
expect "panel created" "the panel opened twice" 2
expect "slot clock.expanded.day created" "the not-ready day never loaded" 0
# Every component the mod loaded has been destroyed: nothing of a disabled mod stays instantiated.
for what in "widget" "face" "face-expanded" "panel" "slot clock.expanded.footer" "slot clock.expanded.aside" \
    "slot media.expanded.backdrop" "slot media.expanded.below" "slot notifications.expanded.header" "slot quick.tiles"; do
  c=$(mq "$what created"); d=$(mq "$what destroyed")
  [ "$c" -eq "$d" ] || fail "'$what': $c created, $d destroyed after mod.disable"
done
echo "log: every component created was destroyed"
no_qml_warnings "stand-in"
stop_phase

echo "ok: screenshots in $OUT"
