#!/usr/bin/env bash
# Live audio levels, cover colours and the Wallhaven tab in the REAL shell (W24-media, K48), invisibly: the real kurashid
# and the real Quickshell frontend in the headless sway sandbox, `desktop.enabled = true`, the wallpaper mod on with a
# fake awww; a FAKE cava first on PATH (prints a fixed frame, logs when it starts and stops), a fake MPRIS player with a
# cover (crates/kurashi-mock/examples/fake_mpris_art.rs) on the sandbox's session bus, and a fixture Wallhaven API on the
# sandbox's loopback (`KURASHI_WALLHAVEN_API`; crates/kurashi-mod-wallpaper/tests/fixtures). Per decor (sekai, none):
#   1. playing: svc.media carries `art_colors` (AA contrast between bg and fg), svc.audio.spectrum the fake frame;
#      shots of the island pill, the island's media card and the desk card (bars + cover colours);
#   2. paused: the views stop watching the spectrum, so cava is stopped (Ma);
#   3. the wallpaper picker's Wallhaven tab: results with thumbnails (from the fixture), Download and set (the fake awww
#      gets the downloaded file), then the fixture server gone (offline state).
# Checks print ok / FAIL; any FAIL, QML error or kurashid panic makes the run exit 1.
# Shots: frontend/shots/media/{pill,card,desk,wallhaven,wallhaven-set,wallhaven-offline}-{sekai,none}.png.
#   KURASHI_RENDER_NODE=/dev/dri/renderD129 KURASHI_BIN_DIR=<dir with kurashid, kurashi, examples/fake_mpris_art> \
#     timeout 900 nix develop -c frontend/test-media.sh [sandbox-name]
# (`cargo build -p kurashid -p kurashi` and `cargo build -p kurashi-mock --example fake_mpris_art` first.)
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
NAME=${1:-w24-med-1}   # unique per run: other runs stop any sandbox that shares a name
BIN=${KURASHI_BIN_DIR:-${CARGO_TARGET_DIR:-$ROOT/target}/debug}
PLAYER_BIN=${KURASHI_FAKE_MPRIS_ART:-$BIN/examples/fake_mpris_art}
OUT=$ROOT/frontend/shots/media
DECORS=${DECORS:-sekai none}
FIX=$ROOT/crates/kurashi-mod-wallpaper/tests/fixtures
export KURASHI_RENDER_NODE=${KURASHI_RENDER_NODE:-/dev/dri/renderD129}
# Layout px of the 2560 x 1440 output: the bar's middle (the island pill), the Stage's card, the desk column.
PILL_GEOM=${PILL_GEOM:-"980,0 600x48"}
CARD_GEOM=${CARD_GEOM:-"860,30 840x760"}
DESK_GEOM=${DESK_GEOM:-"2200,30 360x700"}
PICK_GEOM=${PICK_GEOM:-"860,30 840x760"}
PORT=8766
mkdir -p "$OUT"
FAILS=0
CHECKS=0
fail() { echo "test-media: $*" >&2; exit 1; }
check() { # check <0|1> <label>
  CHECKS=$((CHECKS + 1))
  if [ "$1" = 1 ]; then echo "ok: $2"; else echo "FAIL: $2"; FAILS=$((FAILS + 1)); fi
}
[ -x "$PLAYER_BIN" ] || fail "no fake MPRIS player at $PLAYER_BIN (cargo build -p kurashi-mock --example fake_mpris_art)"

eval "$("$ROOT/tools/bench/sandbox.sh" start "$NAME")"
R=$XDG_RUNTIME_DIR
W=$R/work
rm -rf "$R/fakebin" "$R/covers"
mkdir -p "$W" "$R/kurashi" "$R/fakebin" "$R/covers" "$R/wpstate"
cp "$BIN/kurashid" "$BIN/kurashi" "$PLAYER_BIN" "$W/"
rm -f "$R/qs.log" "$R/kurashid.log" "$R/wallhaven.log" "$R/cava.log" "$R/awww.log"
for _ in $(seq 150); do timeout 5 swaymsg -t get_outputs >/dev/null 2>&1 && break; sleep 0.2; done
timeout 5 swaymsg -t get_outputs >/dev/null 2>&1 || fail "the headless compositor does not answer (see $R/sway.log)"

DPID=""
SHPID=""
PPID_=""
SPID=""
stop_daemon() { if [ -n "$DPID" ]; then kill "$DPID" 2>/dev/null || true; wait "$DPID" 2>/dev/null || true; fi; DPID=""; }
stop_shell() { if [ -n "$SHPID" ]; then kill "$SHPID" 2>/dev/null || true; wait "$SHPID" 2>/dev/null || true; fi; SHPID=""; }
stop_player() { if [ -n "$PPID_" ]; then exec 7>&- 2>/dev/null || true; kill "$PPID_" 2>/dev/null || true; wait "$PPID_" 2>/dev/null || true; fi; PPID_=""; }
stop_server() { if [ -n "$SPID" ]; then kill "$SPID" 2>/dev/null || true; wait "$SPID" 2>/dev/null || true; fi; SPID=""; }
cleanup() {
  stop_shell
  stop_player
  stop_daemon
  stop_server
  # A fake cava left by a killed daemon: only ours (its environ carries this sandbox's runtime dir).
  for p in $(pgrep -f "$R/fakebin/cava" 2>/dev/null || true); do
    grep -qz "XDG_RUNTIME_DIR=$R" "/proc/$p/environ" 2>/dev/null && kill "$p" 2>/dev/null || true
  done
  "$ROOT/tools/bench/sandbox.sh" stop "$NAME" >/dev/null || true
}
trap cleanup EXIT

export XDG_CONFIG_HOME=$R/xdg/config XDG_STATE_HOME=$R/xdg/state XDG_DATA_HOME=$R/xdg/data XDG_CACHE_HOME=$R/xdg/cache
export KURASHI_DATA_DIR=$ROOT LC_ALL=C.UTF-8 WP_LOG=$R/awww.log WP_STATE=$R/wpstate CAVA_LOG=$R/cava.log
K() { timeout 10 "$W/kurashi" "$@"; }

# ---- covers and pictures: PNGs with known colours (stdlib only) ----------------------------------------------------
cat > "$W/png.py" <<'PY'
import struct, sys, zlib

def png(path, w, h, px):
    rows = bytearray()
    for y in range(h):
        rows.append(0)
        for x in range(w):
            rows.extend(px(x, y))
    def chunk(t, d):
        c = struct.pack(">I", len(d)) + t + d
        return c + struct.pack(">I", zlib.crc32(t + d) & 0xFFFFFFFF)
    data = b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0))
    data += chunk(b"IDAT", zlib.compress(bytes(rows), 9)) + chunk(b"IEND", b"")
    open(path, "wb").write(data)

def hexrgb(s):
    s = s.lstrip("#")
    return bytes(int(s[i:i + 2], 16) for i in (0, 2, 4))

if __name__ == "__main__":
    out = sys.argv[1]
    # A crimson cover with a dark title band, and a deep blue one.
    png(out + "/red.png", 240, 240, lambda x, y: bytes([30, 18, 22]) if y > 190 else bytes([196 - x // 6, 30 + y // 12, 48]))
    png(out + "/blue.png", 240, 240, lambda x, y: bytes([24, 52 + x // 5, 170 + y // 6]))
PY
python3 -I "$W/png.py" "$R/covers"

# ---- the fake cava: the config from stdin, one fixed frame thirty times a second, its life in a log -----------------
cat > "$R/fakebin/cava" <<'PY'
#!/usr/bin/env python3
import os, signal, sys, time
log = open(os.environ["CAVA_LOG"], "a", buffering=1)
log.write("start %d\n" % os.getpid())
conf = sys.stdin.read()
log.write("config " + ("ok" if "bars=16" in conf and "data_format=ascii" in conf else "bad") + "\n")
def bye(*_):
    log.write("stop %d\n" % os.getpid())
    sys.exit(0)
signal.signal(signal.SIGTERM, bye)
frame = "92;100;84;70;76;61;48;55;40;33;38;26;18;12;7;3;"
try:
    while True:
        sys.stdout.write(frame + "\n")
        sys.stdout.flush()
        time.sleep(1 / 30)
except BrokenPipeError:
    bye()
PY
# ---- the fake backend: awww and awww-daemon, logging their argv (as mods/wallpaper/test/real-shell.sh) --------------
cat > "$R/fakebin/awww" <<'EOF'
#!/bin/sh
echo "awww $*" >> "$WP_LOG"
case "$1" in
  --version) echo "awww 0.12.1" ;;
  query)
    if [ -f "$WP_STATE/daemon" ]; then
      printf '%s\n' '{"": [{"name": "HEADLESS-1", "width": 2560, "height": 1440, "scale": 1, "displaying": {"color": "000000"}}]}'
    else
      echo "Failed to connect to the awww-daemon socket" >&2; exit 1
    fi ;;
  kill) rm -f "$WP_STATE/daemon" ;;
esac
exit 0
EOF
cat > "$R/fakebin/awww-daemon" <<'EOF'
#!/bin/sh
echo "awww-daemon $*" >> "$WP_LOG"
touch "$WP_STATE/daemon"
EOF
chmod +x "$R/fakebin/cava" "$R/fakebin/awww" "$R/fakebin/awww-daemon"

# ---- the fixture Wallhaven: the search and info fixtures with their URLs pointed here, PNG thumbs and pictures -------
cat > "$W/wallhaven.py" <<'PY'
import http.server, json, os, sys, urllib.parse
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import png as pngmod, io, struct, zlib

port, fixdir, logp = int(sys.argv[1]), sys.argv[2], sys.argv[3]
me = "http://127.0.0.1:%d" % port
def local(text):
    return text.replace("https://th.wallhaven.cc", me + "/th").replace("https://w.wallhaven.cc", me + "/w")
search = json.loads(local(open(fixdir + "/wallhaven-search.json").read()))
info = json.loads(local(open(fixdir + "/wallhaven-info.json").read()))
by_id = {h["id"]: h for h in search["data"]}
log = open(logp, "a", buffering=1)

def png_bytes(w, h, rgb):
    path = "/tmp/_unused"
    rows = bytearray()
    for y in range(h):
        rows.append(0)
        for x in range(w):
            rows.extend(bytes([max(0, min(255, rgb[0] + (x - w // 2) // 4)), rgb[1], max(0, min(255, rgb[2] + (y - h // 2) // 4))]))
    def chunk(t, d):
        c = struct.pack(">I", len(d)) + t + d
        return c + struct.pack(">I", zlib.crc32(t + d) & 0xFFFFFFFF)
    return b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0)) + chunk(b"IDAT", zlib.compress(bytes(rows), 6)) + chunk(b"IEND", b"")

def colour_of(i):
    h = by_id.get(i)
    c = (h or {}).get("colors") or ["#5577aa"]
    c = [x for x in c if len(x) == 7 and x != "#000000"] or ["#5577aa"]
    return pngmod.hexrgb(c[-1])

class H(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        u = urllib.parse.urlparse(self.path)
        log.write(u.path + " " + u.query + " key=" + (self.headers.get("X-API-Key") or "-") + "\n")
        if u.path == "/api/v1/search":
            return self.send(200, "application/json", json.dumps(search).encode())
        if u.path.startswith("/api/v1/w/"):
            i = u.path.rsplit("/", 1)[1]
            if i == info["data"]["id"]:
                return self.send(200, "application/json", json.dumps(info).encode())
            if i in by_id:
                return self.send(200, "application/json", json.dumps({"data": by_id[i]}).encode())
            return self.send(404, "application/json", b'{"error":"Nothing here"}')
        if u.path.startswith("/th/"):
            i = u.path.rsplit("/", 1)[1].split(".")[0]
            return self.send(200, "image/png", png_bytes(300, 200, colour_of(i)))
        if u.path.startswith("/w/"):
            i = u.path.rsplit("/", 1)[1].split(".")[0].replace("wallhaven-", "")
            return self.send(200, "image/png", png_bytes(640, 360, colour_of(i)))
        self.send(404, "text/plain", b"no")

    def send(self, code, ctype, body):
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, *a):
        pass

http.server.ThreadingHTTPServer(("127.0.0.1", port), H).serve_forever()
PY
start_server() {
  stop_server
  python3 "$W/wallhaven.py" "$PORT" "$FIX" "$R/wallhaven.log" >> "$R/wallhaven.err" 2>&1 &
  SPID=$!
  for _ in $(seq 50); do python3 -c "import socket; socket.create_connection(('127.0.0.1', $PORT), 0.2)" 2>/dev/null && return 0; sleep 0.1; done
  fail "the fixture Wallhaven did not start (see $R/wallhaven.err)"
}

# `ipc.py <doc>` prints the first snapshot's data of a document (stdlib only, as in mods/lyrics/test-lyrics.sh).
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
# AA contrast of art_colors (WCAG 2.x), in Python: exit 0 when fg on bg >= 4.5 and accent on bg >= 3.
cat > "$W/aa.py" <<'PY'
import json, sys
d = json.load(sys.stdin) or {}
c = d.get("art_colors") or {}
def lum(h):
    h = h.lstrip("#")
    v = [int(h[i:i + 2], 16) / 255 for i in (0, 2, 4)]
    v = [x / 12.92 if x <= 0.03928 else ((x + 0.055) / 1.055) ** 2.4 for x in v]
    return 0.2126 * v[0] + 0.7152 * v[1] + 0.0722 * v[2]
def ratio(a, b):
    la, lb = sorted([lum(a), lum(b)], reverse=True)
    return (la + 0.05) / (lb + 0.05)
try:
    ok = ratio(c["fg"], c["bg"]) >= 4.5 and ratio(c["accent"], c["bg"]) >= 3.0
except Exception:
    ok = False
print(json.dumps(c))
sys.exit(0 if ok else 1)
PY
ipc() { timeout 10 python3 -I "$W/ipc.py" "$@"; }
doc_is() { ipc "$1" | python3 -c "import json,sys; d = json.load(sys.stdin) or {}; sys.exit(0 if ($2) else 1)" 2>/dev/null; }
wait_doc() { local i; for i in $(seq "$3"); do doc_is "$1" "$2" && return 0; sleep 0.5; done; return 0; }
cava_running() { pgrep -f "$R/fakebin/cava" >/dev/null 2>&1; }
wait_cava() { local i; for i in $(seq 40); do if cava_running; then [ "$1" = up ] && return 0; else [ "$1" = down ] && return 0; fi; sleep 0.25; done; return 0; }
shot() { # shot <name> <geometry>
  sleep "${WAIT:-2}"
  grim -g "$2" "$OUT/$1.png"
  [ -s "$OUT/$1.png" ] || fail "empty screenshot $1"
  echo "shot $1"
}
click_at() { timeout 30 python3 -I "$ROOT/tools/bench/wl_pointer.py" click "$1" "$2" left || true; sleep 0.4; }

start_player() { # start_player <title> <artist> <album> <length_s> <art_url>
  stop_player
  rm -f "$R/player.in"
  mkfifo "$R/player.in"
  "$W/fake_mpris_art" "$@" < "$R/player.in" >> "$R/player.log" 2>&1 &
  PPID_=$!
  exec 7> "$R/player.in"
}
player() { printf '%s\n' "$1" >&7; }

start_all() { # start_all <decor>
  stop_shell
  stop_player
  stop_daemon
  rm -rf "$R/xdg" "$WP_STATE"
  mkdir -p "$XDG_CONFIG_HOME/kurashi" "$XDG_STATE_HOME" "$XDG_DATA_HOME" "$XDG_CACHE_HOME" "$WP_STATE" "$R/pics"
  cp "$R/covers/blue.png" "$R/pics/library-blue.png"
  cat > "$XDG_CONFIG_HOME/kurashi/config.toml" <<TOML
theme.style = "$1"
desktop.enabled = true

[mods]
loaded = ["wallpaper"]

[mods.wallpaper]
folders = "$R/pics"
backend = "awww"
TOML
  : > "$R/cava.log"
  : > "$R/awww.log"
  : > "$R/wallhaven.log"
  start_server
  start_player "夜に駆ける" "YOASOBI" "THE BOOK" 261 "file://$R/covers/red.png"
  rm -f "$KURASHI_SOCKET"
  env PATH="$R/fakebin:$PATH" DBUS_SYSTEM_BUS_ADDRESS="unix:path=$R/no-system-bus" PULSE_SERVER="unix:$R/no-pulse/native" \
    PULSE_RUNTIME_PATH="$R/no-pulse" KURASHI_WALLHAVEN_API="http://127.0.0.1:$PORT" "$W/kurashid" >> "$R/kurashid.log" 2>&1 &
  DPID=$!
  for _ in $(seq 100); do [ -S "$KURASHI_SOCKET" ] && K ping >/dev/null 2>&1 && break; sleep 0.1; done
  K ping >/dev/null 2>&1 || fail "kurashid did not come up (see $R/kurashid.log)"
  swaymsg output '*' bg '#8fb8c8' solid_color >/dev/null 2>&1 || true
  env -u KURASHI_SOCKET DBUS_SYSTEM_BUS_ADDRESS="unix:path=$R/no-system-bus" qs -p "$ROOT/frontend" >> "$R/qs.log" 2>&1 &
  SHPID=$!
  sleep "${SHELL_WAIT:-5}"
}

for DECOR in $DECORS; do
  echo "== $DECOR: playing, a crimson cover"
  start_all "$DECOR"
  wait_doc svc.media 'd.get("title") == "夜に駆ける" and "art_colors" in d' 30
  check "$(doc_is svc.media 'd.get("playing") is True and d.get("art_url", "").endswith("red.png")' && echo 1 || echo 0)" "$DECOR media: the fake player and its cover are shown"
  AA=$(ipc svc.media | python3 -I "$W/aa.py" && echo ok || echo bad)
  check "$([ "${AA##*$'\n'}" = ok ] && echo 1 || echo 0)" "$DECOR art_colors: fg on bg >= 4.5:1, accent >= 3:1 ($(echo "$AA" | head -1))"
  check "$(ls "$XDG_CACHE_HOME/kurashi/media/art/"*.json >/dev/null 2>&1 && echo 1 || echo 0)" "$DECOR the cover's answer is cached under the daemon's cache dir"
  wait_cava up
  check "$(cava_running && echo 1 || echo 0)" "$DECOR cava runs while the pill's bars show a playing track"
  check "$(grep -q '^config ok' "$R/cava.log" && echo 1 || echo 0)" "$DECOR cava got the 16-bar ascii config on stdin"
  wait_doc svc.audio.spectrum 'd.get("bars", [0])[1] == 1.0' 20
  check "$(doc_is svc.audio.spectrum 'd.get("available") is True and len(d["bars"]) == 16 and d["bars"][0] == 0.92 and d["bars"][15] == 0.03' && echo 1 || echo 0)" "$DECOR spectrum: the fake frame as 16 levels"
  shot "pill-$DECOR" "$PILL_GEOM"
  shot "desk-$DECOR" "$DESK_GEOM"
  K act island.expand '{}' >/dev/null || fail "island.expand failed"
  check "$(doc_is runtime.ui 'd.get("panel") == "island" and d.get("face") == "media"' && echo 1 || echo 0)" "$DECOR the island opens on the media card"
  shot "card-$DECOR" "$CARD_GEOM"
  K act ui.close '{}' >/dev/null 2>&1 || true

  echo "== $DECOR: a blue cover, then paused"
  player "art file://$R/covers/blue.png"
  wait_doc svc.media 'd.get("art_url", "").endswith("blue.png") and "art_colors" in d' 30
  check "$(ipc svc.media | python3 -I "$W/aa.py" >/dev/null && echo 1 || echo 0)" "$DECOR a new cover gets its own readable colours"
  WAIT=2 shot "desk-blue-$DECOR" "$DESK_GEOM"
  player pause
  wait_doc svc.media 'd.get("playing") is False' 20
  wait_cava down
  check "$(cava_running && echo 0 || echo 1)" "$DECOR paused: nothing watches the spectrum, cava is stopped (Ma)"
  WAIT=1 shot "pill-paused-$DECOR" "$PILL_GEOM"

  echo "== $DECOR: the Wallhaven tab"
  K act mod.enable '{"id": "wallpaper"}' >/dev/null 2>&1 || true
  K act mod.panel.open '{"id": "wallpaper", "panel": "wallpaper"}' >/dev/null || fail "mod.panel.open wallpaper failed"
  sleep 2
  check "$([ "$(grep -c '^/api/v1/search' "$R/wallhaven.log" || true)" = 0 ] && echo 1 || echo 0)" "$DECOR nothing is fetched while the library tab is shown"
  WAIT=1 shot "picker-library-$DECOR" "$PICK_GEOM"
  click_at "${TAB_X:-1043}" "${TAB_Y:-95}"
  sleep 3
  check "$([ "$(grep -c '^/api/v1/search' "$R/wallhaven.log" || true)" = 1 ] && echo 1 || echo 0)" "$DECOR opening the tab runs one search (SFW: $(grep -o 'purity=[0-9]*' "$R/wallhaven.log" | head -1))"
  check "$(grep -q 'purity=100' "$R/wallhaven.log" && echo 1 || echo 0)" "$DECOR the search is SFW only by default"
  check "$(ls "$XDG_CACHE_HOME/kurashi/wallpaper/wallhaven/"*.jpg >/dev/null 2>&1 && echo 1 || echo 0)" "$DECOR the page's thumbnails are in the cache"
  shot "wallhaven-$DECOR" "$PICK_GEOM"
  # The first tile, then Download and set.
  click_at "${TILE_X:-1020}" "${TILE_Y:-288}"
  click_at "${SET_X:-1515}" "${SET_Y:-625}"
  sleep 3
  check "$(ls "$XDG_DATA_HOME/kurashi/wallpaper/wallhaven/wallhaven-94x38z."* >/dev/null 2>&1 && echo 1 || echo 0)" "$DECOR the picture is saved in the mod's data folder"
  check "$(grep -q 'awww img .*wallhaven-94x38z\.' "$R/awww.log" && echo 1 || echo 0)" "$DECOR the backend was asked to show it"
  shot "wallhaven-set-$DECOR" "$PICK_GEOM"
  stop_server
  click_at "${TOP_X:-1467}" "${TOP_Y:-167}"
  sleep 3
  shot "wallhaven-offline-$DECOR" "$PICK_GEOM"
  K act ui.close '{}' >/dev/null 2>&1 || true
done
stop_shell
stop_player
stop_daemon

if grep -Eq 'ReferenceError|TypeError|binding loop|is not a function|is not defined|is not a type' "$R/qs.log" 2>/dev/null; then
  echo "QML errors in qs.log: $(grep -E 'ReferenceError|TypeError|binding loop|is not a function|is not defined|is not a type' "$R/qs.log" | head -5)" >&2
  FAILS=$((FAILS + 1))
fi
if grep -Ei 'LevelBars|MediaView|Desktop.qml|Wallhaven.qml|wallpaper/qml/Panel' "$R/qs.log" 2>/dev/null | grep -Eiq 'warn|error'; then
  echo "QML warnings: $(grep -Ei 'LevelBars|MediaView|Desktop.qml|Wallhaven.qml|wallpaper/qml/Panel' "$R/qs.log" | head -5)" >&2
  FAILS=$((FAILS + 1))
fi
if grep -q panicked "$R/kurashid.log" 2>/dev/null; then
  echo "kurashid panicked (see $R/kurashid.log)" >&2
  FAILS=$((FAILS + 1))
fi
echo "checks: $((CHECKS - FAILS < 0 ? 0 : CHECKS - FAILS)) of $CHECKS"
[ "$FAILS" -eq 0 ] || fail "$FAILS failure(s); logs in $R, screenshots in $OUT"
echo "ok: screenshots in $OUT"
