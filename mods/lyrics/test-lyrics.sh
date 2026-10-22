#!/usr/bin/env bash
# The lyrics mod in the REAL shell (W23-auth-media, K47), invisibly: the real kurashid and the real Quickshell frontend in
# the headless sway sandbox, `desktop.enabled = true`, the mod on, a fake MPRIS player on the sandbox's session bus
# (crates/kurashi-mod-lyrics/examples/fake_mpris.rs) and a fake LRCLIB on the sandbox's loopback
# (`KURASHI_LYRICS_API`). Per decor (sekai, none): a song with synced lyrics (the views send the track, the daemon asks
# once and caches it), the bar widget, the desk card and the media card's slot; then a song LRCLIB has nothing for, then
# the fake LRCLIB gone (offline) and a song from the cache. Checks: each document says what it should; one request per
# new song however many views send it; the cache file exists; no QML error or warning from the mod; no kurashid panic.
# Screenshots (mods/lyrics/shots/): {bar,desk,card}-{sekai,none}.png, card-offline-{sekai,none}.png.
#   KURASHI_RENDER_NODE=/dev/dri/renderD129 KURASHI_BIN_DIR=<dir with kurashid and kurashi> \
#     timeout 900 nix develop -c mods/lyrics/test-lyrics.sh [sandbox-name]
# (`cargo build -p kurashid -p kurashi` and `cargo build -p kurashi-mod-lyrics --example fake_mpris` first.)
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
NAME=${1:-w23-aut-lyrics}   # unique per run: other runs stop any sandbox that shares a name
BIN=${KURASHI_BIN_DIR:-${CARGO_TARGET_DIR:-$ROOT/target}/debug}
PLAYER_BIN=${KURASHI_FAKE_MPRIS:-$BIN/examples/fake_mpris}
OUT=$ROOT/mods/lyrics/shots
DECORS=${DECORS:-sekai none}
# Machine B's iGPU when it exists; elsewhere sandbox.sh picks the display GPU (boot_vga).
[ -e /dev/dri/renderD129 ] && export KURASHI_RENDER_NODE=${KURASHI_RENDER_NODE:-/dev/dri/renderD129}
# Layout px of the 2560 x 1440 output: the bar's right half, the desk column, the Stage's card under the bar.
BAR_GEOM=${BAR_GEOM:-"1600,0 960x48"}
DESK_GEOM=${DESK_GEOM:-"2200,30 360x1000"}
CARD_GEOM=${CARD_GEOM:-"860,30 840x760"}
PORT=8765
mkdir -p "$OUT"
FAILS=0
CHECKS=0
fail() { echo "test-lyrics: $*" >&2; exit 1; }
check() { # check <0|1> <label>
  CHECKS=$((CHECKS + 1))
  if [ "$1" = 1 ]; then echo "ok: $2"; else echo "FAIL: $2"; FAILS=$((FAILS + 1)); fi
}
[ -x "$PLAYER_BIN" ] || fail "no fake MPRIS player at $PLAYER_BIN (cargo build -p kurashi-mod-lyrics --example fake_mpris)"

eval "$("$ROOT/tools/bench/sandbox.sh" start "$NAME")"
R=$XDG_RUNTIME_DIR
W=$R/work
mkdir -p "$W" "$R/kurashi"
cp "$BIN/kurashid" "$BIN/kurashi" "$PLAYER_BIN" "$W/"
rm -f "$R/qs.log" "$R/kurashid.log" "$R/lrclib.log"
for _ in $(seq 150); do timeout 5 swaymsg -t get_outputs >/dev/null 2>&1 && break; sleep 0.2; done
timeout 5 swaymsg -t get_outputs >/dev/null 2>&1 || fail "the headless compositor does not answer (see $R/sway.log)"

DPID=""
SHPID=""
PPID_=""
LPID=""
stop_daemon() { if [ -n "$DPID" ]; then kill "$DPID" 2>/dev/null || true; wait "$DPID" 2>/dev/null || true; fi; DPID=""; }
stop_shell() { if [ -n "$SHPID" ]; then kill "$SHPID" 2>/dev/null || true; wait "$SHPID" 2>/dev/null || true; fi; SHPID=""; }
stop_player() { if [ -n "$PPID_" ]; then exec 7>&- 2>/dev/null || true; kill "$PPID_" 2>/dev/null || true; wait "$PPID_" 2>/dev/null || true; fi; PPID_=""; }
stop_lrclib() { if [ -n "$LPID" ]; then kill "$LPID" 2>/dev/null || true; wait "$LPID" 2>/dev/null || true; fi; LPID=""; }
cleanup() {
  stop_shell
  stop_player
  stop_daemon
  stop_lrclib
  "$ROOT/tools/bench/sandbox.sh" stop "$NAME" >/dev/null || true
}
trap cleanup EXIT

# Hermetic: no config, state or cache from an earlier run; the system bus is not reachable.
export XDG_CONFIG_HOME=$R/xdg/config XDG_STATE_HOME=$R/xdg/state XDG_DATA_HOME=$R/xdg/data XDG_CACHE_HOME=$R/xdg/cache
export KURASHI_DATA_DIR=$ROOT LC_ALL=C.UTF-8
K() { timeout 10 "$W/kurashi" "$@"; }

# The fake LRCLIB: /api/get knows 夜に駆ける (a line every 3 s), /api/search knows nothing; every request is logged.
cat > "$W/lrclib.py" <<'PY'
import http.server, json, sys, urllib.parse

WORDS = ["夜に駆ける", "沈むように溶けてゆくように", "二人だけの空が広がる夜に", "さよならだけだった", "", "騒がしい日々に笑えない君に", "思い付く限り眩しい明日を"]
# (every 7th line, from index 4, is a pause: the views show ♪)
rows = []
for i, s in enumerate(range(0, 300, 3)):
    text = WORDS[i % 7]
    rows.append(f"[{s // 60:02d}:{s % 60:02d}.00]" + (f"{text} {i}" if text else ""))
lrc = "[ar:YOASOBI]\n[ti:夜に駆ける]\n" + "\n".join(rows)
SONGS = {("YOASOBI", "夜に駆ける"): {"syncedLyrics": lrc, "plainLyrics": "…", "instrumental": False, "duration": 261}}
log = open(sys.argv[2], "a", buffering=1)


class H(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        u = urllib.parse.urlparse(self.path)
        q = dict(urllib.parse.parse_qsl(u.query))
        log.write(u.path + " " + json.dumps(q, ensure_ascii=False) + "\n")
        if u.path == "/api/get":
            rec = SONGS.get((q.get("artist_name"), q.get("track_name")))
            if rec is None:
                return self.answer(404, {"code": 404, "name": "TrackNotFound"})
            return self.answer(200, rec)
        if u.path == "/api/search":
            return self.answer(200, [])
        self.answer(404, {})

    def answer(self, code, body):
        data = json.dumps(body).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def log_message(self, *a):
        pass


http.server.ThreadingHTTPServer(("127.0.0.1", int(sys.argv[1])), H).serve_forever()
PY

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
ipc() { timeout 10 python3 -I "$W/ipc.py" "$@"; }
# doc_is <doc> <python condition on d>: 0 when it holds now.
doc_is() { ipc "$1" | python3 -c "import json,sys; d = json.load(sys.stdin) or {}; sys.exit(0 if ($2) else 1)" 2>/dev/null; }
wait_doc() { local i; for i in $(seq "$3"); do doc_is "$1" "$2" && return 0; sleep 0.5; done; return 0; }
gets() { grep -c "^/api/get " "$R/lrclib.log" 2>/dev/null || true; }
shot() { # shot <name> <geometry>
  sleep "${WAIT:-2}"
  grim -g "$2" "$OUT/$1.png"
  [ -s "$OUT/$1.png" ] || fail "empty screenshot $1"
  echo "shot $1"
}

start_lrclib() {
  stop_lrclib
  python3 -I "$W/lrclib.py" "$PORT" "$R/lrclib.log" >> "$R/lrclib.err" 2>&1 &
  LPID=$!
  for _ in $(seq 50); do python3 -c "import socket; socket.create_connection(('127.0.0.1', $PORT), 0.2)" 2>/dev/null && return 0; sleep 0.1; done
  fail "the fake LRCLIB did not start (see $R/lrclib.err)"
}
start_player() { # start_player <title> <artist> <album> <length_s> <start_s>
  stop_player
  rm -f "$R/player.in"
  mkfifo "$R/player.in"
  "$W/fake_mpris" "$@" < "$R/player.in" >> "$R/player.log" 2>&1 &
  PPID_=$!
  exec 7> "$R/player.in"
}
player() { printf '%s\n' "$1" >&7; }

start_all() { # start_all <decor>
  stop_shell
  stop_player
  stop_daemon
  rm -rf "$R/xdg"
  mkdir -p "$XDG_CONFIG_HOME/kurashi" "$XDG_STATE_HOME" "$XDG_DATA_HOME" "$XDG_CACHE_HOME"
  cat > "$XDG_CONFIG_HOME/kurashi/config.toml" <<TOML
theme.style = "$1"
desktop.enabled = true
TOML
  : > "$R/lrclib.log"
  start_lrclib
  start_player "夜に駆ける" "YOASOBI" "THE BOOK" 261 13
  rm -f "$KURASHI_SOCKET"
  env DBUS_SYSTEM_BUS_ADDRESS="unix:path=$R/no-system-bus" PULSE_SERVER="unix:$R/no-pulse/native" \
    PULSE_RUNTIME_PATH="$R/no-pulse" KURASHI_LYRICS_API="http://127.0.0.1:$PORT" "$W/kurashid" >> "$R/kurashid.log" 2>&1 &
  DPID=$!
  for _ in $(seq 100); do [ -S "$KURASHI_SOCKET" ] && K ping >/dev/null 2>&1 && break; sleep 0.1; done
  K ping >/dev/null 2>&1 || fail "kurashid did not come up (see $R/kurashid.log)"
  K act mod.enable '{"id": "lyrics"}' >/dev/null || fail "mod.enable lyrics failed"
  swaymsg output '*' bg '#8fb8c8' solid_color >/dev/null 2>&1 || true
  env -u KURASHI_SOCKET DBUS_SYSTEM_BUS_ADDRESS="unix:path=$R/no-system-bus" qs -p "$ROOT/frontend" >> "$R/qs.log" 2>&1 &
  SHPID=$!
  sleep "${SHELL_WAIT:-5}"
}

for DECOR in $DECORS; do
  echo "== $DECOR: a song with synced lyrics"
  start_all "$DECOR"
  wait_doc svc.media 'd.get("title") == "夜に駆ける"' 20
  check "$(doc_is svc.media 'd.get("title") == "夜に駆ける" and d.get("playing") is True' && echo 1 || echo 0)" "$DECOR media: the fake player is shown"
  wait_doc mod.lyrics 'd.get("state") == "ready"' 30
  check "$(doc_is mod.lyrics 'd.get("state") == "ready" and d.get("synced") is True and len(d["lines"]) == 100 and d["track"]["title"] == "夜に駆ける" and d["lines"][1] == {"t_ms": 3000, "text": "沈むように溶けてゆくように 1"}' && echo 1 || echo 0)" "$DECOR ready: the synced lines of the song"
  check "$([ "$(gets)" = 1 ] && echo 1 || echo 0)" "$DECOR one request for the song (got $(gets)), however many views send it"
  check "$(ls "$XDG_CACHE_HOME/kurashi/lyrics/"*.json >/dev/null 2>&1 && echo 1 || echo 0)" "$DECOR the answer is cached"
  shot "bar-$DECOR" "$BAR_GEOM"
  shot "desk-$DECOR" "$DESK_GEOM"
  K act island.expand '{}' >/dev/null || fail "island.expand failed"
  check "$(doc_is runtime.ui 'd.get("panel") == "island" and d.get("face") == "media"' && echo 1 || echo 0)" "$DECOR the island opens on the media card"
  shot "card-$DECOR" "$CARD_GEOM"
  K act ui.close '{}' >/dev/null 2>&1 || true

  echo "== $DECOR: a song LRCLIB has nothing for"
  player "$(printf 'track Unknown Song\tNobody\tNo Album\t200\t5')"
  wait_doc mod.lyrics 'd.get("track", {}).get("title") == "Unknown Song" and d.get("state") == "none"' 30
  check "$(doc_is mod.lyrics 'd.get("state") == "none" and d.get("reason") == "mod-lyrics.none" and d["track"]["title"] == "Unknown Song"' && echo 1 || echo 0)" "$DECOR none: no lyrics for the song"
  check "$(grep -c '^/api/search ' "$R/lrclib.log" | grep -qx 1 && echo 1 || echo 0)" "$DECOR none: the get missed, one search"

  echo "== $DECOR: LRCLIB gone, a new song, then the cached one"
  stop_lrclib
  player "$(printf 'track Offline Song\tNobody\t\t180\t5')"
  wait_doc mod.lyrics 'd.get("state") == "offline"' 40
  check "$(doc_is mod.lyrics 'd.get("state") == "offline" and d.get("reason") == "mod-lyrics.offline" and d["track"]["title"] == "Offline Song"' && echo 1 || echo 0)" "$DECOR offline: no answer"
  K act island.expand '{}' >/dev/null || true
  shot "card-offline-$DECOR" "$CARD_GEOM"
  K act ui.close '{}' >/dev/null 2>&1 || true
  player "$(printf 'track 夜に駆ける\tYOASOBI\tTHE BOOK\t261\t40')"
  wait_doc mod.lyrics 'd.get("state") == "ready" and d["track"]["title"] == "夜に駆ける"' 30
  check "$(doc_is mod.lyrics 'd.get("state") == "ready" and d["track"]["title"] == "夜に駆ける"' && echo 1 || echo 0)" "$DECOR cache: the song's lyrics without LRCLIB"
done
stop_shell
stop_player
stop_daemon

if grep -Eq 'ReferenceError|TypeError|binding loop|is not a function|is not defined|is not a type' "$R/qs.log" 2>/dev/null; then
  echo "QML errors in qs.log: $(grep -E 'ReferenceError|TypeError|binding loop|is not a function|is not defined|is not a type' "$R/qs.log" | head -5)" >&2
  FAILS=$((FAILS + 1))
fi
if grep -Ei 'mods/lyrics' "$R/qs.log" 2>/dev/null | grep -Eiq 'warn|error'; then
  echo "QML warnings from the lyrics mod: $(grep -Ei 'mods/lyrics' "$R/qs.log" | grep -Ei 'warn|error' | head -5)" >&2
  FAILS=$((FAILS + 1))
fi
if grep -q panicked "$R/kurashid.log" 2>/dev/null; then
  echo "kurashid panicked (see $R/kurashid.log)" >&2
  FAILS=$((FAILS + 1))
fi
grep -m1 "polkit:" "$R/qs.log" || true
echo "checks: $((CHECKS - FAILS < 0 ? 0 : CHECKS - FAILS)) of $CHECKS"
[ "$FAILS" -eq 0 ] || fail "$FAILS failure(s); logs in $R, screenshots in $OUT"
echo "ok: screenshots in $OUT"
