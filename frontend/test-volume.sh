#!/usr/bin/env bash
# The bar's volume slider (B2), invisibly (headless sway sandbox). Checks, by screenshot and pixel:
#   - no audio server (the REAL kurashid, svc.audio available:false): no accent fill or knob at the bar's
#     end, a dim "⊘" in their place (unavailable.png); the same with the bar on the left edge, the
#     vertical layout (unavailable-left.png);
#   - the MOCK (volume 0.5, available): the accent fill and knob are drawn (available.png);
#   - the mock, muted: the level is drawn in the dim token, no accent (muted.png);
#   - the mock, unmuted, with the daemon's device line (detail.volume, I45): the volume face says that line (volume-device.png);
#   - the frontend logs no QML error.
#   nix develop -c frontend/test-volume.sh [sandbox-name]
# Binaries: kurashid and kurashi from $KURASHI_BIN_DIR (default $CARGO_TARGET_DIR/debug or target/debug),
# the mock from $KURASHI_MOCK_BIN (default: kurashi-mock in the same dir). They are copied first, since
# shared target dirs get overwritten. The screenshots in frontend/shots/volume/ are evidence to read, not
# just the exit code. On a hybrid laptop export KURASHI_RENDER_NODE first.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
NAME=${1:-fe-volume}
BIN=${KURASHI_BIN_DIR:-${CARGO_TARGET_DIR:-$ROOT/target}/debug}
MOCK_BIN=${KURASHI_MOCK_BIN:-$BIN/kurashi-mock}
OUT=$ROOT/frontend/shots/volume
STRIP=420   # px of the bar's end that holds the slider and the clock (the slider sits one pad from the clock)
# No level: no accent, the clock's run, and before it one run no wider than a glyph (the dim mark).
UNAVAILABLE='.accent == 0 and .light >= 20 and (.ink_groups | length) >= 2 and (.ink_groups[0][1] - .ink_groups[0][0]) <= 20'
mkdir -p "$OUT"
fail() { echo "test-volume: $*" >&2; exit 1; }

eval "$("$ROOT/tools/bench/sandbox.sh" start "$NAME")"
R=$XDG_RUNTIME_DIR
W=$R/work
mkdir -p "$W" "$R/kurashi"
cp "$BIN/kurashid" "$BIN/kurashi" "$W/"
cp "$MOCK_BIN" "$W/kurashi-mock"

pids=()
stop_phase() {  # kills only the processes this script started
  for p in "${pids[@]}"; do kill "$p" 2>/dev/null || true; done
  for p in "${pids[@]}"; do wait "$p" 2>/dev/null || true; done
  pids=()
  rm -f "$KURASHI_SOCKET"
}
cleanup() {
  stop_phase
  "$ROOT/tools/bench/sandbox.sh" stop "$NAME" >/dev/null || true
}
trap cleanup EXIT

rm -rf "$R/xdg"   # hermetic: the left-edge phase moves the bar, which a rerun would otherwise start with
export XDG_CONFIG_HOME=$R/xdg/config XDG_STATE_HOME=$R/xdg/state \
       XDG_DATA_HOME=$R/xdg/data XDG_CACHE_HOME=$R/xdg/cache KURASHI_DATA_DIR=$ROOT LC_ALL=C.UTF-8
mkdir -p "$XDG_CONFIG_HOME" "$XDG_STATE_HOME" "$XDG_DATA_HOME" "$XDG_CACHE_HOME"
# Pixel checks of the plain look (K53: a fresh install wears the style washi; this test reads layout and fills).
mkdir -p "$XDG_CONFIG_HOME/kurashi"
printf 'theme.style = "none"\n[theme.colors]\nscheme = "dark"\n' > "$XDG_CONFIG_HOME/kurashi/config.toml"

# One protocol exchange with the socket: `ipc sub <doc>` prints the first snapshot's data, `ipc act
# <action> [args-json]` prints the reply (exit 1 on err). Plain stdlib, as in test-tray-bt.sh.
cat > "$W/ipc.py" <<'PY'
import json, os, socket, sys

sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
sock.settimeout(5)
sock.connect(os.environ["KURASHI_SOCKET"])
f = sock.makefile("rwb")


def send(msg):
    f.write((json.dumps(msg) + "\n").encode())
    f.flush()


def reply(rid):
    while True:
        line = f.readline()
        if not line:
            sys.exit("ipc: connection closed")
        m = json.loads(line)
        if m.get("id") == rid and m["t"] in ("done", "err", "snap"):
            return m


send({"t": "hello", "v": 1, "client": "test", "caps": ["intents", "resync"]})
if json.loads(f.readline())["t"] != "welcome":
    sys.exit("ipc: no welcome")
if sys.argv[1] == "act":
    args = json.loads(sys.argv[3]) if len(sys.argv) > 3 else {}
    send({"t": "act", "id": "a", "action": sys.argv[2], "args": args})
    m = reply("a")
    print(json.dumps(m))
    sys.exit(0 if m["t"] == "done" else 1)
send({"t": "sub", "id": "s", "doc": sys.argv[2]})
print(json.dumps(reply("s").get("data")))
PY
ipc() { timeout 10 python3 -I "$W/ipc.py" "$@"; }
tok() { ipc sub theme | jq -r --arg k "$1" '.tokens[$k]'; }
K() { timeout 10 "$W/kurashi" "$@"; }
# K71: the bar moves with its modules in one change (`layout.bar.move`), from the edge it stands on now.
bar_edge() {
  local e
  for e in top bottom left right; do
    if K --json get "edges.$e.bar" | grep -q '"value":true'; then
      [ "$e" = "$1" ] || K act layout.bar.move "{\"from\":\"$e\",\"to\":\"$1\"}" >/dev/null
      return
    fi
  done
  return 1
}

# Pixel counts in the bar's end of one capture (P6 PPM): accent (fill and knob), dim (muted level or the
# unavailable mark) and light (the clock, which proves the region is the bar). JSON on stdout.
cat > "$W/analyse.py" <<'PY'
import json, sys


def rgb(hex_color):
    h = hex_color.lstrip("#")
    return tuple(int(h[i:i + 2], 16) for i in (0, 2, 4))


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


path, edge = sys.argv[1], sys.argv[2]
accent, dim = rgb(sys.argv[3]), rgb(sys.argv[4])
bar, strip = int(float(sys.argv[5])), int(sys.argv[6])
with open(path, "rb") as f:
    w, h, raster = read_ppm(f.read())


def pix(a, b):
    # a runs along the bar's end (x on a top bar, y on a left bar), b across the bar.
    x, y = (a, b) if edge == "top" else (b, a)
    o = (y * w + x) * 3
    return (raster[o], raster[o + 1], raster[o + 2])


def near(c, ref, tol):
    return all(abs(c[k] - ref[k]) <= tol for k in range(3))


# The bar's end: the right end of a top bar, the bottom end of a left bar.
along = range(w - strip, w) if edge == "top" else range(h - strip, h)
across = range(0, bar)
acc = dim_n = light = 0
hits, groups = [], []
for a in along:
    ink = False
    for b in across:
        c = pix(a, b)
        if near(c, accent, 10):
            acc += 1
            hits.append((a, b))
        elif near(c, dim, 6):
            dim_n += 1
        if sum(c) > 360:
            light += 1
        if sum(c) > 180:   # clearly above the bar's background (about 26 per channel)
            ink = True
    if ink:
        # Runs of ink along the bar, split by gaps over 4 px: the slider comes before the clock on
        # both layouts, so the first run is the slider (or its mark) and the last one the clock.
        if groups and a - groups[-1][1] <= 4:
            groups[-1][1] = a
        else:
            groups.append([a, a])
bbox = None
if hits:
    xy = [(a, b) if edge == "top" else (b, a) for a, b in hits]
    xs, ys = [p[0] for p in xy], [p[1] for p in xy]
    bbox = [min(xs), min(ys), max(xs), max(ys)]
print(json.dumps({"accent": acc, "dim": dim_n, "light": light, "accent_bbox": bbox, "ink_groups": groups}))
PY

analyse() {  # analyse <shot> <top|left>; the colours are the running daemon's tokens
  timeout 20 python3 -I "$W/analyse.py" "$W/$1.ppm" "$2" "$(tok color.accent)" \
    "$(tok color.on_surface_variant)" "$(tok bar.height)" "$STRIP"
}
check() {  # check <shot> <top|left> <jq condition on the counts> <what fails>
  local res
  res=$(analyse "$1" "$2") || fail "$1: analysis failed"
  echo "$1: $res"
  jq -e "$3" <<<"$res" >/dev/null || fail "$1: $4 ($res)"
}
shot() {  # shot <name> [settle seconds]: PPM for the pixel check, PNG to look at
  sleep "${2:-2}"
  timeout 20 grim -o HEADLESS-1 -t ppm "$W/$1.ppm" || fail "grim failed on $1"
  timeout 20 grim -o HEADLESS-1 "$OUT/$1.png" || fail "grim failed on $1"
  [ -s "$OUT/$1.png" ] || fail "empty screenshot $1"
  echo "shot $1"
}

wait_socket() {  # wait_socket <what>: the server answers on the socket
  for _ in $(seq 100); do [ -S "$KURASHI_SOCKET" ] && ipc sub svc.clock >/dev/null 2>&1 && return 0; sleep 0.1; done
  fail "$1 did not come up (see $R/server.log)"
}
start_kurashid() {  # no audio server: PULSE_SERVER names a socket that does not exist
  rm -f "$KURASHI_SOCKET"
  env DBUS_SYSTEM_BUS_ADDRESS="unix:path=$R/no-system-bus" \
      PULSE_SERVER="unix:$R/no-pulse/native" PULSE_RUNTIME_PATH="$R/no-pulse" \
      "$W/kurashid" >> "$R/server.log" 2>&1 &
  pids+=("$!")
  wait_socket kurashid
}
start_mock() {  # the fixture audio: volume 0.5, available (the mock's svc.audio has no `available` key)
  rm -f "$KURASHI_SOCKET"
  RUST_LOG=info "$W/kurashi-mock" --outputs HEADLESS-1 --fixed-time 14:07 --socket "$KURASHI_SOCKET" \
    >> "$R/server.log" 2>&1 &
  pids+=("$!")
  wait_socket mock
}
start_frontend() {
  # Without KURASHI_SOCKET: the frontend must find the socket by the protocol default, as in a live session.
  env -u KURASHI_SOCKET qs -p "$ROOT/frontend" >> "$R/qs.log" 2>&1 &
  pids+=("$!")
  for _ in $(seq 100); do grep -q 'hello.*frontend' "$R/server.log" && break; sleep 0.1; done
  grep -q 'hello.*frontend' "$R/server.log" || fail "frontend never said hello (see $R/qs.log)"
  sleep 3   # the bar's documents and the first frames
}

: > "$R/qs.log"

# 1. No audio server, the real kurashid. Its svc.audio answer is the precondition of this check.
: > "$R/server.log"
start_kurashid
[ "$(ipc sub svc.audio | jq -r '.available')" = false ] \
  || fail "precondition: svc.audio must be available:false (no audio server in the sandbox)"
start_frontend
shot unavailable 1
check unavailable top "$UNAVAILABLE" "a fill or knob is drawn with no audio, or no mark stands in for it"
bar_edge left || fail "the bar did not move to the left"
shot unavailable-left 3
check unavailable-left left "$UNAVAILABLE" "a fill or knob is drawn with no audio (vertical), or no mark"
stop_phase

# 2. The mock: audio available at 50 %, then muted (the mock's own action).
: > "$R/server.log"
start_mock
[ "$(ipc sub svc.audio | jq -r '.volume')" = 0.5 ] || fail "precondition: the mock's svc.audio volume is not 0.5"
start_frontend
shot available 1
check available top '.accent >= 150 and (.ink_groups[0][1] - .ink_groups[0][0]) >= 100' \
  "no accent fill and knob in the slider's run with the mock's audio available"
ipc act audio.mute.toggle >/dev/null || fail "audio.mute.toggle failed on the mock"
shot muted 2
check muted top '.accent == 0 and .dim >= 150 and (.ink_groups[0][1] - .ink_groups[0][0]) >= 100' \
  "the muted level is not drawn dim in the slider's run (or still accent)"
# 3. The volume face names the output when the daemon does (I45): unmuted, the pill says the daemon's line, not the percent.
ipc act audio.mute.toggle >/dev/null || fail "audio.mute.toggle (unmute) failed on the mock"
ipc act mock.island '{"face":"volume","reason":"default","detail":{"volume":"Headphones · 40 %"}}' >/dev/null \
  || fail "mock.island (the volume face with a device line) failed"
shot volume-device 2.5
stop_phase

if grep -q "ERROR\|TypeError\|ReferenceError\|Unable to assign\|is not defined" "$R/qs.log"; then
  echo "qs.log has errors:" >&2
  grep "ERROR\|TypeError\|ReferenceError\|Unable to assign\|is not defined" "$R/qs.log" | head >&2
  exit 1
fi
echo "ok: screenshots in $OUT"
