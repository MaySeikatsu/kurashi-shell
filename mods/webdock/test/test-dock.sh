#!/usr/bin/env bash
# The web dock's shell side (W20-webdock-shell; K40; docs/ux/webdock.md) in the headless sandbox, against kurashi-mock:
#   states     the edge surface, the strip, the card of a view pin and the empty, cold, missing and pinned states, 30 pins,
#              and every edge (right, left, top, bottom); the shots are mods/webdock/shots/dock-*.png (read them);
#   intents    the pointer and the keys reach the dock, and each intent the frontend sends is logged (hover, engage, select,
#              pin, add, move, remove, size, collapse, back, toggle); the menu and the add form take the keyboard;
#   ja         the Japanese copy (the mock's i18n document follows LC_ALL);
#   measure    idle cost: no commit of a dock surface in 10 s while hidden; PSS with the mod on and off, one and two outputs.
# The daemon's state machine is not here (W20-webdock-daemon): `mod.webdock` is set with `mock.webdock`. A relay in front of
# the mock serves the `mods` document (the mock serves none) and logs every act and intent the frontend sends; the mock
# refuses the actions it does not know, and the logged intent is what is asserted.
#   timeout 900 bash mods/webdock/test/test-dock.sh [sandbox-name]
#   DOCK_PHASES="states intents" selects phases; KURASHI_SB_RENDERER=pixman on a machine without a render node.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
NAME=${1:-w20-shell-dock-$$}   # unique per run: other agents' runs stop any sandbox that shares a name
BIN=${KURASHI_BIN_DIR:-${CARGO_TARGET_DIR:-$ROOT/target}/debug}
OUT=$ROOT/mods/webdock/shots
mkdir -p "$OUT"
fail() { echo "test-dock: $*" >&2; exit 1; }
want() { [ -z "${DOCK_PHASES:-}" ] || [[ " $DOCK_PHASES " == *" $1 "* ]]; }

eval "$("$ROOT/tools/bench/sandbox.sh" start "$NAME" "${KURASHI_SB_RENDERER:-gles2}")"
R=$XDG_RUNTIME_DIR
W=$R/work
MOCK_SOCK=$R/kurashi/mock.sock
INTENTS=$R/intents.jsonl
FIFO=$R/pointer.fifo
KFIFO=$R/keys.fifo
mkdir -p "$W" "$R/kurashi"
# Hermetic frontend and mock: isolated XDG dirs, the repo as the data dir (the i18n files), C locale unless a phase says otherwise.
export XDG_CONFIG_HOME=$R/xdg/config XDG_STATE_HOME=$R/xdg/state XDG_DATA_HOME=$R/xdg/data XDG_CACHE_HOME=$R/xdg/cache \
       KURASHI_DATA_DIR=$ROOT LC_ALL=C.UTF-8
mkdir -p "$XDG_CONFIG_HOME" "$XDG_STATE_HOME" "$XDG_DATA_HOME" "$XDG_CACHE_HOME"
export MOCK_SOCKET=$MOCK_SOCK INTENTS_LOG=$INTENTS

# The helpers the test writes into the sandbox (stdlib Python, as the other frontend tests).
cat > "$W/relay.py" <<'PY'
import json, os, socket, sys, threading

# A relay in front of kurashi-mock: the frontend's socket. Lines go to the mock unchanged, except that `sub`/`resync` of
# `mods` are answered with the snapshot in the file given, and `unsub mods` is dropped. Every act and intent is logged.
LISTEN = os.environ["KURASHI_SOCKET"]
MOCK = sys.argv[1]
MODS = json.load(open(sys.argv[2]))
LOG = sys.argv[3]
log_lock = threading.Lock()


def record(rec):
    with log_lock, open(LOG, "a") as f:
        f.write(json.dumps(rec) + "\n")


def handle(client):
    mock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    mock.connect(MOCK)
    lock = threading.Lock()

    def send(msg):
        with lock:
            client.sendall((json.dumps(msg) + "\n").encode())

    def from_mock():
        try:
            while True:
                data = mock.recv(65536)
                if not data:
                    break
                with lock:
                    client.sendall(data)
        except OSError:
            pass
        finally:
            try:
                client.shutdown(socket.SHUT_RDWR)
            except OSError:
                pass

    threading.Thread(target=from_mock, daemon=True).start()
    buf = b""
    try:
        while True:
            data = client.recv(65536)
            if not data:
                break
            buf += data
            while b"\n" in buf:
                line, buf = buf.split(b"\n", 1)
                if not line:
                    continue
                try:
                    m = json.loads(line)
                except ValueError:
                    mock.sendall(line + b"\n")
                    continue
                t = m.get("t")
                if t in ("sub", "resync") and m.get("doc") == "mods":
                    send({"t": "snap", "id": m.get("id", "s:mods"), "doc": "mods", "rev": 1, "data": MODS})
                    continue
                if t == "unsub" and m.get("doc") == "mods":
                    continue
                if t in ("act", "intent"):
                    record({"t": t, "id": m.get("id"), "action": m.get("action"), "key": m.get("key"),
                            "args": m.get("args", m.get("value"))})
                mock.sendall(line + b"\n")
    except OSError:
        pass
    finally:
        mock.close()
        client.close()


if os.path.exists(LISTEN):
    os.unlink(LISTEN)
srv = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
srv.bind(LISTEN)
srv.listen(8)
while True:
    conn, _ = srv.accept()
    threading.Thread(target=handle, args=(conn,), daemon=True).start()
PY
cat > "$W/drive.py" <<'PY'
import json, os, socket, sys

# `drive.py act <action> [json args]` runs one action on the mock (exit 1 on an error reply); `drive.py doc <doc>` prints one
# document's data. The test talks to the mock directly, not through the relay.
sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
sock.settimeout(5)
sock.connect(os.environ["MOCK_SOCKET"])
f = sock.makefile("rwb")


def send(msg):
    f.write((json.dumps(msg) + "\n").encode())
    f.flush()


def recv():
    line = f.readline()
    if not line:
        sys.exit("drive: the socket closed")
    return json.loads(line)


send({"t": "hello", "v": 1, "client": "webdock-test", "caps": ["intents", "resync"]})
if recv()["t"] != "welcome":
    sys.exit("drive: no welcome")
if sys.argv[1] == "act":
    send({"t": "act", "id": "d1", "action": sys.argv[2], "args": json.loads(sys.argv[3]) if len(sys.argv) > 3 else {}})
    while True:
        m = recv()
        if m.get("id") == "d1" and m["t"] in ("done", "err"):
            break
    print(json.dumps(m))
    sys.exit(0 if m["t"] == "done" else 1)
send({"t": "sub", "id": "d2", "doc": sys.argv[2]})
while True:
    m = recv()
    if m.get("id") == "d2" and m["t"] in ("snap", "err"):
        break
if m["t"] == "err":
    sys.exit("drive: " + json.dumps(m))
print(json.dumps(m["data"]))
PY
cat > "$W/seen.py" <<'PY'
import json, os, sys

# `seen.py <condition>`: exit 0 when an intent in the log satisfies the condition (`i` is the intent record).
path = os.environ["INTENTS_LOG"]
recs = [json.loads(line) for line in open(path)] if os.path.exists(path) else []


def holds(i):
    try:
        return bool(eval(sys.argv[1], {}, {"i": i}))
    except (KeyError, TypeError):
        return False


sys.exit(0 if any(holds(i) for i in recs) else 1)
PY
cat > "$W/count.py" <<'PY'
import json, os, sys

# `count.py <condition>`: how many intents in the log satisfy the condition.
path = os.environ["INTENTS_LOG"]
recs = [json.loads(line) for line in open(path)] if os.path.exists(path) else []


def holds(i):
    try:
        return bool(eval(sys.argv[1], {}, {"i": i}))
    except (KeyError, TypeError):
        return False


print(sum(1 for i in recs if holds(i)))
PY
# diff.py <a.ppm> <b.ppm> x0 y0 x1 y1: pixels of the rectangle (x1, y1 exclusive) that differ by more than 24 in some channel.
cat > "$W/diff.py" <<'PY'
import sys


def read(path):
    with open(path, "rb") as f:
        data = f.read()
    toks, i = [], 0
    while len(toks) < 4:
        while data[i:i + 1].isspace():
            i += 1
        j = i
        while not data[j:j + 1].isspace():
            j += 1
        toks.append(data[i:j])
        i = j
    return int(toks[1]), data[i + 1:]


aw, a = read(sys.argv[1])
bw, b = read(sys.argv[2])
x0, y0, x1, y1 = map(int, sys.argv[3:7])
n = 0
for y in range(y0, y1):
    s, e = (y * aw + x0) * 3, (y * aw + x1) * 3
    ra, rb = a[s:e], b[s:e]
    for k in range(0, len(ra), 3):
        if abs(ra[k] - rb[k]) > 24 or abs(ra[k + 1] - rb[k + 1]) > 24 or abs(ra[k + 2] - rb[k + 2]) > 24:
            n += 1
print(n)
PY
# mods_json <file> <on|off>: the `mods` document the relay serves: the dock's surface and widget (on), and the weather panel.
mods_json() {
  python3 -I - "$1" "$2" "$ROOT" <<'PY'
import json, sys

path, on, root = sys.argv[1], sys.argv[2], sys.argv[3]
mods = [{"id": "weather", "qml": {"panel:weather": f"file://{root}/mods/weather/qml/Panel.qml"}}]
if on in ("on", "widget"):
    qml = {"widget:webdock": f"file://{root}/mods/webdock/qml/Widget.qml"}
    if on == "on":
        qml["surface:dock"] = f"file://{root}/mods/webdock/qml/surfaces/dock.qml"
    mods.insert(0, {"id": "webdock", "qml": qml})
json.dump({"mods": mods}, open(path, "w"))
PY
}

pids=()
QS_PID=""
stop_phase() {
  { exec 3>&-; } 2>/dev/null || true   # the pointer's fifo
  { exec 4>&-; } 2>/dev/null || true   # the keys' fifo
  for p in ${pids[@]+"${pids[@]}"}; do kill "$p" 2>/dev/null || true; done
  for p in ${pids[@]+"${pids[@]}"}; do wait "$p" 2>/dev/null || true; done
  pids=()
  rm -f "$MOCK_SOCK" "$KURASHI_SOCKET" "$FIFO" "$KFIFO"
}
cleanup() {
  stop_phase
  "$ROOT/tools/bench/sandbox.sh" stop "$NAME" >/dev/null || true
}
trap cleanup EXIT

start_mock() { # start_mock <outputs> [locale]: kurashi-mock serves the socket, its first output is the dock's
  rm -f "$MOCK_SOCK"
  LC_ALL=${2:-C.UTF-8} "$BIN/kurashi-mock" --outputs "$1" --fixed-time 12:34 --socket "$MOCK_SOCK" >> "$R/mock.log" 2>&1 &
  pids+=("$!")
  for _ in $(seq 100); do [ -S "$MOCK_SOCK" ] && return 0; sleep 0.1; done
  fail "mock did not come up (see $R/mock.log)"
}
start_relay() { # start_relay <mods json>: the frontend's socket; the intents go to $INTENTS
  rm -f "$KURASHI_SOCKET" "$INTENTS"
  python3 -I "$W/relay.py" "$MOCK_SOCK" "$1" "$INTENTS" >> "$R/relay.log" 2>&1 &
  pids+=("$!")
  for _ in $(seq 100); do [ -S "$KURASHI_SOCKET" ] && return 0; sleep 0.1; done
  fail "relay did not come up (see $R/relay.log)"
}
start_frontend() { # start_frontend [VAR=value ...]: qs on the relay, with the given environment
  env "$@" qs -p "$ROOT/frontend" >> "$R/qs.log" 2>&1 &
  QS_PID=$!
  pids+=("$QS_PID")
  sleep 4
}
start_input() { # one virtual pointer and one virtual keyboard for the phase, after the output they point at exists
  rm -f "$FIFO" "$KFIFO"
  mkfifo "$FIFO" "$KFIFO"
  timeout 900 python3 -I "$ROOT/tools/bench/wl_pointer.py" --serve < "$FIFO" > "$R/pointer.log" 2>&1 &
  pids+=("$!")
  timeout 900 python3 -I "$ROOT/tools/bench/wl_keys.py" --serve < "$KFIFO" > "$R/keys.log" 2>&1 &
  pids+=("$!")
  exec 3> "$FIFO"
  exec 4> "$KFIFO"
  sleep 1
}
move() { echo "move $1 $2" >&3; sleep 0.7; }
click() { echo "click $1 $2 ${3:-left}" >&3; sleep 0.9; }
# press <key tokens...>: tab, return, escape, down, space, or a character token. The virtual keyboard takes about 0.3 s a key,
# so the pause grows with the tokens: a later pointer click or key must not overtake them.
press() { echo "$*" >&4; sleep "$(awk -v n="$#" 'BEGIN { print 0.5 + 0.3 * n }')"; }
drv() { timeout 10 python3 -I "$W/drive.py" "$@"; }
setdoc() { drv act mock.webdock "$1" > /dev/null || fail "mock.webdock refused: $1"; }
seen() { timeout 10 python3 -I "$W/seen.py" "$1"; }
count() { timeout 10 python3 -I "$W/count.py" "$1"; }
docq() { drv doc mod.webdock | python3 -c "import json,sys; d=json.load(sys.stdin); sys.exit(0 if ($1) else 1)"; }
check() { # check <0|1> <label>
  if [ "$1" = 1 ]; then echo "ok: $2"; else echo "FAIL: $2"; FAILS=$((FAILS + 1)); fi
}
grab() { timeout 20 grim -o HEADLESS-1 -t ppm "$W/$1.ppm" || fail "grim failed on $1"; }
shot() { timeout 20 grim -o HEADLESS-1 "$OUT/dock-$1.png" || fail "grim failed on $1"; grab "dock-$1"; }
changed() { timeout 30 python3 -I "$W/diff.py" "$@"; }   # changed <ppm> <baseline ppm> x0 y0 x1 y1
size() { stat -c %s "$R/qs.log"; }
pss_mib() { awk '/^Pss:/{s+=$2} END{printf "%.2f", s/1024}' "/proc/$1/smaps_rollup"; }
# dock_commits <start byte>: commits of the dock's layer surfaces (namespace kurashi-webdock-shell) since that offset
dock_commits() {
  local ids
  ids=$(grep -oE 'wl_surface#[0-9]+, wl_output#[0-9]+, [0-9]+, "kurashi-webdock-(shell|edge)"' "$R/qs.log" | grep -oE 'wl_surface#[0-9]+' \
    | grep -oE '[0-9]+$' | paste -sd'|' - || true)
  [ -n "$ids" ] || { echo 0; return 0; }
  tail -c +"$(( $1 + 1 ))" "$R/qs.log" | grep -cE "wl_surface#($ids)\.commit\(" || true
}

# The base document: two pins and a view, on the right edge, hidden, the host ready. A phase sets what it needs on top.
MAIL='{"id":"mail","kind":"web","title":"Mail","target":"https://mail.example.org/","view":"mobile","profile":"mail","loaded":true}'
CHAT='{"id":"chat","kind":"web","title":"Chat","target":"https://chat.example.org/","view":"desktop","profile":"work","loaded":false,"audible":true,"blocked":["camera"],"error":"webdock.error.crashed"}'
WEATHER='{"id":"weather","kind":"view","title":"Weather","target":"mod:weather:weather"}'
PINS3="[$MAIL,$CHAT,$WEATHER]"
PINS2="[$MAIL,$WEATHER]"
BASE='{"available":true,"mode":"hidden","size":"phone","edge":"right","output":"HEADLESS-1","pinned":false,"engaged":false,"hover":true,"reserve":false,"indicator":false,"new_tabs":"dock","geometry":{"strip":56,"width":412,"large":90,"grace":24},"keep":[],"host":{"state":"ready"},"dirs":{"profiles":"/p","icons":"/i"}}'
FAILS=0

# ---- states: the drawing of each state, on the right edge, then each edge ----
phase_states() {
  echo "== phase states: the surface, strip and card; the empty, cold, missing and pinned states; 30 pins; every edge"
  start_mock HEADLESS-1
  mods_json "$W/mods-on.json" on
  start_relay "$W/mods-on.json"
  start_frontend
  setdoc "$(python3 -I -c "import json,sys; d=json.loads(sys.argv[1]); d['pins']=json.loads(sys.argv[2]); print(json.dumps(d))" "$BASE" "$PINS3")"
  sleep 2
  grab bare
  setdoc '{"indicator":true}'; sleep 1
  shot hidden-indicator
  check "$([ "$(changed "$W/dock-hidden-indicator.ppm" "$W/bare.ppm" 2544 660 2560 780)" -gt 100 ] && echo 1 || echo 0)" \
    "hidden: the edge indicator is drawn (4 x 48 px on the edge)"
  setdoc '{"mode":"compact","shown":null}'; sleep 1.2
  shot compact
  check "$([ "$(changed "$W/dock-compact.ppm" "$W/bare.ppm" 2500 500 2560 900)" -gt 1000 ] && echo 1 || echo 0)" \
    "compact: the strip is drawn with its pins and controls"
  setdoc '{"mode":"extended","shown":"weather","size":"phone"}'; sleep 1.5
  shot view-phone
  check "$([ "$(changed "$W/dock-view-phone.ppm" "$W/bare.ppm" 2092 340 2504 1170)" -gt 3000 ] && echo 1 || echo 0)" \
    "extended: the view card (phone, 412 px) is drawn beside the strip"
  setdoc '{"size":"large"}'; sleep 1.5
  shot view-large
  check "$([ "$(changed "$W/dock-view-large.ppm" "$W/bare.ppm" 200 300 2500 1100)" -gt 20000 ] && echo 1 || echo 0)" \
    "large: the card is 90 % of the output's width"
  setdoc '{"size":"phone","pins":[],"shown":null,"mode":"extended"}'; sleep 1.5
  shot empty
  check "$([ "$(changed "$W/dock-empty.ppm" "$W/bare.ppm" 2092 340 2504 1170)" -gt 1500 ] && echo 1 || echo 0)" \
    "empty: the card says so and offers to add a site"
  setdoc "$(python3 -I -c "import json,sys; print(json.dumps({'pins': json.loads(sys.argv[1]), 'shown': 'mail', 'mode': 'extended', 'host': {'state': 'starting'}}))" "$PINS3")"
  sleep 1.5
  shot cold
  check "$([ "$(changed "$W/dock-cold.ppm" "$W/bare.ppm" 2092 340 2504 1170)" -gt 1500 ] && echo 1 || echo 0)" \
    "cold engine: the card frame with the starting text, while the host is not up"
  setdoc '{"host":{"state":"missing","reason":"webdock.host.missing"}}'; sleep 1.5
  shot missing
  check "$([ "$(changed "$W/dock-missing.ppm" "$W/bare.ppm" 2092 340 2504 1170)" -gt 1500 ] && echo 1 || echo 0)" \
    "host missing: the card says the engine is not installed, and the strip still works"
  setdoc '{"host":{"state":"ready"},"shown":"weather","pinned":true}'; sleep 1.5
  shot pinned
  check "$([ "$(changed "$W/dock-pinned.ppm" "$W/dock-view-phone.ppm" 2506 752 2558 808)" -gt 100 ] && echo 1 || echo 0)" \
    "pinned: the dock's pin control is lit (the strip differs from the unpinned shot)"
  local many
  many=$(python3 -I -c "import json; print(json.dumps([{'id': 'p%02d' % i, 'kind': 'web', 'title': 'Site %d' % i, 'target': 'https://s%d.example.org/' % i} for i in range(30)] + [json.loads('$WEATHER')]))")
  setdoc "$(python3 -I -c "import json,sys; print(json.dumps({'pins': json.loads(sys.argv[1]), 'shown': 'weather', 'mode': 'extended', 'pinned': False, 'host': {'state': 'ready'}}))" "$many")"
  sleep 1.5
  shot 30-pins
  check "$([ "$(changed "$W/dock-30-pins.ppm" "$W/bare.ppm" 2500 0 2560 1440)" -gt 1500 ] && echo 1 || echo 0)" \
    "30 pins: the strip is drawn and scrolls (the output is shorter than the strip)"
  setdoc "$(python3 -I -c "import json,sys; print(json.dumps({'pins': json.loads(sys.argv[1]), 'shown': 'weather', 'mode': 'extended', 'edge': 'left'}))" "$PINS3")"
  sleep 1.5
  shot edge-left
  check "$([ "$(changed "$W/dock-edge-left.ppm" "$W/bare.ppm" 0 300 500 1170)" -gt 3000 ] && echo 1 || echo 0)" \
    "edge left: the strip and the card are on the left edge"
  setdoc '{"edge":"top"}'; sleep 1.5
  shot edge-top
  check "$([ "$(changed "$W/dock-edge-top.ppm" "$W/bare.ppm" 1000 40 1560 940)" -gt 3000 ] && echo 1 || echo 0)" \
    "edge top: the strip is horizontal and the card hangs under it"
  setdoc '{"edge":"bottom"}'; sleep 1.5
  shot edge-bottom
  check "$([ "$(changed "$W/dock-edge-bottom.ppm" "$W/bare.ppm" 1000 500 1560 1440)" -gt 3000 ] && echo 1 || echo 0)" \
    "edge bottom: the strip is horizontal and the card stands above it"
  setdoc '{"edge":"right","mode":"hidden","shown":null,"pinned":false,"pins":[]}'; sleep 1
  stop_phase
}

# ---- intents: the pointer and the keys reach the dock; the intents reach the mock, which answers them ----
# The mock answers each intent (hover and engage at once, select, back, pin, add, move, remove, size, collapse, toggle),
# so a check reads the document after the act (docq), and the intent the frontend sent (seen).
phase_intents() {
  echo "== phase intents: hover, engage, select, back, pin, move, size, collapse, add, remove, toggle"
  start_mock HEADLESS-1
  mods_json "$W/mods-on.json" on
  start_relay "$W/mods-on.json"
  start_frontend
  setdoc "$(python3 -I -c "import json,sys; d=json.loads(sys.argv[1]); d['pins']=json.loads(sys.argv[2]); d['indicator']=True; print(json.dumps(d))" "$BASE" "$PINS2")"
  start_input
  sleep 1
  move 1500 400; move 2559 400
  seen "i['action']=='webdock.hover' and i['args']['part']=='edge' and i['args']['inside'] is True and i['args']['output']=='HEADLESS-1'" && r=1 || r=0
  check "$r" "hover: the pointer on the edge zone reports part edge, inside, with the output"
  move 1500 400
  seen "i['action']=='webdock.hover' and i['args']['part']=='edge' and i['args']['inside'] is False" && r=1 || r=0
  check "$r" "hover: the pointer leaving the zone reports it outside"
  setdoc '{"mode":"compact","shown":null}'; sleep 1.2
  grab icompact
  move 2531 701
  seen "i['action']=='webdock.hover' and i['args']['part']=='strip' and i['args']['inside'] is True" && r=1 || r=0
  check "$r" "hover: the strip reports part strip, inside"
  move 1500 701
  seen "i['action']=='webdock.hover' and i['args']['part']=='strip' and i['args']['inside'] is False" && r=1 || r=0
  check "$r" "hover: leaving the strip reports it outside"
  setdoc '{"mode":"compact","shown":null}'; sleep 1
  click 2531 637
  seen "i['action']=='webdock.select' and i['args']['pin']=='mail' and i['args']['output']=='HEADLESS-1'" && r=1 || r=0
  check "$r" "click: a pin sends webdock.select with its id and the output"
  seen "i['action']=='webdock.engage' and i['args']['on'] is True" && r=1 || r=0
  check "$r" "focus: a click into the dock sends webdock.engage on"
  docq "d['mode']=='extended' and d.get('shown')=='mail'" && r=1 || r=0
  check "$r" "select: the mock shows the pin (extended, shown: mail)"
  press escape
  seen "i['action']=='webdock.back'" && r=1 || r=0
  check "$r" "keys: Escape on the strip sends webdock.back"
  docq "d['mode']=='compact' and d.get('shown') is None" && r=1 || r=0
  check "$r" "back: extended goes to compact, the card away"
  click 2531 768
  seen "i['action']=='webdock.pin' and i['args']['on'] is True" && r=1 || r=0
  check "$r" "click: the dock's pin control sends webdock.pin with the new value"
  docq "d.get('pinned') is True" && r=1 || r=0
  check "$r" "pin: the mock keeps the dock open (pinned)"
  press down return
  seen "i['action']=='webdock.select' and i['args']['pin']=='weather'" && r=1 || r=0
  check "$r" "keys: Down moves to the next pin and Return selects it"
  press space
  docq "d.get('pinned') is False" && r=1 || r=0
  check "$r" "keys: Space toggles the dock's pin (the mock unpins)"
  press up
  click 2531 637 right
  shot menu
  press return
  seen "i['action']=='webdock.move' and i['args']['pin']=='mail' and i['args']['to']==1" && r=1 || r=0
  check "$r" "menu: a right click opens the pin's menu, which takes the keyboard (Move down)"
  docq "[p['id'] for p in d['pins']]==['weather','mail']" && r=1 || r=0
  check "$r" "move: the mock reorders the pins"
  click 2531 701 right
  press return
  docq "[p['id'] for p in d['pins']]==['mail','weather']" && r=1 || r=0
  check "$r" "menu: Move up (the first enabled) restores the order"
  setdoc '{"mode":"compact","shown":null,"size":"phone"}'; sleep 1.2
  click 2531 701
  press tab tab return
  seen "i['action']=='webdock.size' and i['args']['size']=='large'" && r=1 || r=0
  check "$r" "card: Tab reaches the size button, Return sends webdock.size large"
  docq "d.get('size')=='large'" && r=1 || r=0
  check "$r" "size: the mock makes the card large"
  press tab return
  seen "i['action']=='webdock.collapse'" && r=1 || r=0
  check "$r" "card: Tab reaches the collapse button, Return sends webdock.collapse"
  docq "d['mode']=='compact' and d.get('shown') is None" && r=1 || r=0
  check "$r" "collapse: the mock puts the card away"
  click 2531 701 right
  press tab return
  docq "[p['id'] for p in d['pins']]==['mail']" && r=1 || r=0
  check "$r" "menu: Tab skips the disabled move and Return removes the pin (the mock drops it)"
  click 2531 754
  shot add
  check "$([ "$(changed "$W/dock-add.ppm" "$W/icompact.ppm" 2000 560 2500 900)" -gt 1000 ] && echo 1 || echo 0)" \
    "add: the add form takes the card's place beside the strip"
  click 2350 659
  press h t t p s colon slash slash e x a m p l e period t e s t slash return
  seen "i['action']=='webdock.add' and i['args']['url']=='https://example.test/'" && r=1 || r=0
  check "$r" "add: the typed address goes to webdock.add"
  docq "[p['id'] for p in d['pins']]==['mail','example-test']" && r=1 || r=0
  check "$r" "add: the mock adds the pin, and the form closes with the keyboard back on the add control"
  click 2256 17   # W23: the keyboard layout chip sits right of the widget (was 2338); K58: the sidebar button too (was 2304)
  seen "i['action']=='webdock.toggle' and i['args'].get('output')=='HEADLESS-1'" && r=1 || r=0
  check "$r" "bar widget: a click sends webdock.toggle for the output the bar is on"
  stop_phase
}

# ---- ja: the Japanese copy, the view card, on the right edge ----
phase_ja() {
  echo "== phase ja: the copy in Japanese"
  start_mock HEADLESS-1 ja_JP.UTF-8
  mods_json "$W/mods-on.json" on
  start_relay "$W/mods-on.json"
  start_frontend
  setdoc "$(python3 -I -c "import json,sys; d=json.loads(sys.argv[1]); d['pins']=json.loads(sys.argv[2]); d['mode']='extended'; d['shown']='weather'; print(json.dumps(d))" "$BASE" "$PINS3")"
  sleep 2
  shot ja
  stop_phase
}

# ---- measure: idle cost of the dock with the mod on and off, one and two outputs ----
uss_mib() { awk '/^Private_(Clean|Dirty):/{s+=$2} END{printf "%.2f", s/1024}' "/proc/$1/smaps_rollup"; }
median() { python3 -I -c 'import statistics,sys; print(round(statistics.median([float(x) for x in sys.argv[1:]]), 2))' "$@"; }

phase_measure() {
  echo "== phase measure: the dock's cost with the mod on and off (medians of three runs), the first reveal, 20 reveal cycles"
  echo "renderer: ${KURASHI_SB_RENDERER:-gles2} (render node ${KURASHI_RENDER_NODE:-default}); render nodes here: $(ls /dev/dri 2>/dev/null | tr '\n' ' ')"
  local pss_on1 pss_off1 pss_widget1 c0 commits pss_before pss_rev1 pss_rev20 uss_rev1 rep run p u
  local on_p="" on_u="" off_p="" off_u=""
  # One output, the dock never revealed: idle commits (10 s), and PSS with the mod on, off, and the bar widget alone.
  for run in on off widget; do
    start_mock HEADLESS-1
    mods_json "$W/mods-$run.json" "$run"
    start_relay "$W/mods-$run.json"
    start_frontend WAYLAND_DEBUG=1
    setdoc "$(python3 -I -c "import json,sys; d=json.loads(sys.argv[1]); d['pins']=json.loads(sys.argv[2]); d['indicator']=True; print(json.dumps(d))" "$BASE" "$PINS2")"
    sleep 5
    c0=$(size)
    sleep 10
    commits=$(dock_commits "$c0")
    if [ "$run" = on ]; then
      check "$([ "$commits" -eq 0 ] && echo 1 || echo 0)" "idle: 0 commits of the dock's windows in 10 s while hidden (got $commits)"
      pss_on1=$(pss_mib "$QS_PID")
    elif [ "$run" = off ]; then
      pss_off1=$(pss_mib "$QS_PID")
    else
      pss_widget1=$(pss_mib "$QS_PID")
    fi
    stop_phase
  done
  "$ROOT/tools/bench/sandbox.sh" output-add "$NAME" > /dev/null 2>&1 || fail "could not add the second output"
  sleep 2
  # Two outputs, the dock never revealed: three runs of each, alternating; the cost per output is half the difference of the medians.
  for rep in 1 2 3; do
    for run in on off; do
      start_mock HEADLESS-1
      mods_json "$W/mods-$run.json" "$run"
      start_relay "$W/mods-$run.json"
      start_frontend
      setdoc "$(python3 -I -c "import json,sys; d=json.loads(sys.argv[1]); d['pins']=json.loads(sys.argv[2]); d['indicator']=True; print(json.dumps(d))" "$BASE" "$PINS2")"
      sleep 10
      p=$(pss_mib "$QS_PID"); u=$(uss_mib "$QS_PID")
      stop_phase
      if [ "$run" = on ]; then on_p="$on_p $p"; on_u="$on_u $u"; else off_p="$off_p $p"; off_u="$off_u $u"; fi
    done
  done
  # The first reveal, then 20 reveal/hide cycles (mod on, two outputs): one run; the window is made once and kept.
  start_mock HEADLESS-1
  mods_json "$W/mods-on.json" on
  start_relay "$W/mods-on.json"
  start_frontend
  setdoc "$(python3 -I -c "import json,sys; d=json.loads(sys.argv[1]); d['pins']=json.loads(sys.argv[2]); d['indicator']=True; print(json.dumps(d))" "$BASE" "$PINS2")"
  sleep 8
  pss_before=$(pss_mib "$QS_PID"); uss_before=$(uss_mib "$QS_PID")
  setdoc '{"mode":"compact","shown":null}'; sleep 2
  setdoc '{"mode":"hidden"}'; sleep 2
  pss_rev1=$(pss_mib "$QS_PID"); uss_rev1=$(uss_mib "$QS_PID")
  for _ in $(seq 20); do
    setdoc '{"mode":"compact","shown":null}'; sleep 0.8
    setdoc '{"mode":"hidden"}'; sleep 0.8
  done
  pss_rev20=$(pss_mib "$QS_PID"); uss_rev20=$(uss_mib "$QS_PID")
  stop_phase
  local med_on_p med_off_p med_on_u med_off_u per_p per_u one_time growth uss_one_time growth_u
  med_on_p=$(median $on_p); med_off_p=$(median $off_p); med_on_u=$(median $on_u); med_off_u=$(median $off_u)
  per_p=$(python3 -I -c "print(round((${med_on_p} - ${med_off_p}) / 2, 2))")
  per_u=$(python3 -I -c "print(round((${med_on_u} - ${med_off_u}) / 2, 2))")
  one_time=$(python3 -c "print(round(${pss_rev1} - ${pss_before}, 2))")
  growth=$(python3 -c "print(round(${pss_rev20} - ${pss_rev1}, 2))")
  uss_one_time=$(python3 -c "print(round(${uss_rev1} - ${uss_before}, 2))")
  growth_u=$(python3 -c "print(round(${uss_rev20} - ${uss_rev1}, 2))")
  echo "measure: never revealed, one output (one run each): mod on ${pss_on1} MiB, off ${pss_off1} MiB (delta $(python3 -c "print(round(${pss_on1} - ${pss_off1}, 2))") MiB); the bar widget alone delta $(python3 -c "print(round(${pss_widget1} - ${pss_off1}, 2))") MiB"
  echo "measure: never revealed, two outputs, medians of three: USS mod on ${med_on_u} MiB, off ${med_off_u} MiB; per output ${per_u} MiB USS (USS runs on:${on_u} off:${off_u})"
  echo "measure: PSS of the two-output runs is not usable (runs on:${on_p} off:${off_p}: a ~1.9 TiB mapping under gles2); per output PSS as computed: ${per_p} MiB"
  echo "measure: the first reveal, once for the shell (its window is made, then kept): +${uss_one_time} MiB USS (${uss_before} -> ${uss_rev1}), +${one_time} MiB PSS (${pss_before} -> ${pss_rev1})"
  echo "measure: 20 reveal/hide cycles after the first: growth ${growth_u} MiB USS (${uss_rev1} -> ${uss_rev20}), ${growth} MiB PSS (${pss_rev1} -> ${pss_rev20})"
  # K41: an opt-in mod carries its own recorded cost (BENCH "Mods": 6.2 MiB USS per output, runs swing widely), so
  # this guards against a regression rather than holding the core budget.
  check "$(python3 -c "print(1 if ${per_u} <= 10.0 else 0)")" "cost: the dock's USS per output, never revealed, stays at most 10 MiB (K41; recorded 6.2)"
  check "$(python3 -c "print(1 if ${growth_u} <= 1.0 else 0)")" "growth: 20 reveal/hide cycles add at most 1 MiB of USS"
}

want states && phase_states
want intents && phase_intents
want ja && phase_ja
want measure && phase_measure
echo "test-dock: $FAILS failed"
[ "$FAILS" -eq 0 ] || exit 1
echo "ok: screenshots in $OUT"
