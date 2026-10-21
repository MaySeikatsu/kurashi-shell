#!/usr/bin/env bash
# The AI mod in the REAL shell (card W28-ai), invisibly: the real kurashid and the real Quickshell frontend in the
# headless sway sandbox, the mod on, its Ollama address pointing at a FAKE Ollama (a stdlib HTTP server on localhost,
# started here). Nothing is ever sent to a real model server or a cloud API; no API key is set or read.
# Per decor (sekai, none): the panel empty (and no request sent by opening it), an answer with a code block, an answer
# while it streams (the patch rate measured: ≤ 10 a second), stopped, then the fake server gone (the error).
# Checks: each step's document says what it should; the conversation is saved as JSON; no QML error or warning from the
# mod in qs.log; no panic in kurashid's log.
# Screenshots (mods/ai/shots/): {empty,code,streaming,error}-{sekai,none}.png (the panel's card).
#   KURASHI_RENDER_NODE=/dev/dri/renderD129 KURASHI_BIN_DIR=<dir with kurashid and kurashi> \
#     timeout 900 nix develop -c mods/ai/test-ai.sh [sandbox-name]
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
NAME=${1:-w28-ai-live}   # unique per run: other runs stop any sandbox that shares a name
BIN=${KURASHI_BIN_DIR:-${CARGO_TARGET_DIR:-$ROOT/target}/debug}
OUT=$ROOT/mods/ai/shots
DECORS=${DECORS:-sekai none}
export KURASHI_RENDER_NODE=${KURASHI_RENDER_NODE:-/dev/dri/renderD129}
# The Stage card of a 560 px mod panel sits under the bar, centred on the 2560 px output.
PANEL_GEOM=${PANEL_GEOM:-"980,30 600x760"}
mkdir -p "$OUT"
FAILS=0
CHECKS=0
fail() { echo "test-ai: $*" >&2; exit 1; }
check() { # check <0|1> <label>
  CHECKS=$((CHECKS + 1))
  if [ "$1" = 1 ]; then echo "ok: $2"; else echo "FAIL: $2"; FAILS=$((FAILS + 1)); fi
}

eval "$("$ROOT/tools/bench/sandbox.sh" start "$NAME")"
R=$XDG_RUNTIME_DIR
W=$R/work
mkdir -p "$W" "$R/kurashi"
cp "$BIN/kurashid" "$BIN/kurashi" "$W/"
rm -f "$R/qs.log" "$R/kurashid.log" "$R/fake-ollama.log"
for _ in $(seq 150); do timeout 5 swaymsg -t get_outputs >/dev/null 2>&1 && break; sleep 0.2; done
timeout 5 swaymsg -t get_outputs >/dev/null 2>&1 || fail "the headless compositor does not answer (see $R/sway.log)"

DPID=""
SHPID=""
FPID=""
stop_daemon() { if [ -n "$DPID" ]; then kill "$DPID" 2>/dev/null || true; wait "$DPID" 2>/dev/null || true; fi; DPID=""; }
stop_shell() { if [ -n "$SHPID" ]; then kill "$SHPID" 2>/dev/null || true; wait "$SHPID" 2>/dev/null || true; fi; SHPID=""; }
stop_fake() { if [ -n "$FPID" ]; then kill "$FPID" 2>/dev/null || true; wait "$FPID" 2>/dev/null || true; fi; FPID=""; }
cleanup() {
  stop_shell
  stop_daemon
  stop_fake
  "$ROOT/tools/bench/sandbox.sh" stop "$NAME" >/dev/null || true
}
trap cleanup EXIT

# Hermetic: no config, state, data or cache from an earlier run; no key in the environment; the system bus is not
# reachable.
export XDG_CONFIG_HOME=$R/xdg/config XDG_STATE_HOME=$R/xdg/state XDG_DATA_HOME=$R/xdg/data XDG_CACHE_HOME=$R/xdg/cache
export KURASHI_DATA_DIR=$ROOT LC_ALL=C.UTF-8
unset OPENAI_API_KEY ANTHROPIC_API_KEY OLLAMA_HOST
K() { timeout 10 "$W/kurashi" "$@"; }

# The fake Ollama: /api/tags lists two models; /api/chat streams NDJSON. The question decides the answer: "code" → a
# short answer with a code block, "slow" → 120 tokens 50 ms apart (six seconds), else a short sentence. Every request is
# logged (method and path) to $R/fake-ollama.log.
cat > "$W/fake_ollama.py" <<'PY'
import json, sys, time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

LOG = sys.argv[2]


def log(line):
    with open(LOG, "a") as f:
        f.write(line + "\n")


class H(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def log_message(self, *a):
        pass

    def send_json(self, obj, code=200):
        body = json.dumps(obj).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        log("GET " + self.path)
        if self.path == "/api/tags":
            self.send_json({"models": [
                {"name": "llama3.2:latest", "details": {"parameter_size": "3.2B", "quantization_level": "Q4_K_M"}},
                {"name": "qwen3:8b", "details": {"parameter_size": "8.2B", "quantization_level": "Q4_K_M"}}]})
        else:
            self.send_json({"error": "not found"}, 404)

    def do_POST(self):
        n = int(self.headers.get("Content-Length") or 0)
        req = json.loads(self.rfile.read(n) or b"{}")
        log("POST " + self.path + " " + req.get("model", "") + " auth=" + ("yes" if self.headers.get("Authorization") else "no"))
        if self.path != "/api/chat":
            return self.send_json({"error": "not found"}, 404)
        q = req["messages"][-1]["content"]
        if "code" in q:
            tokens = ["Use ", "`ls`", " with ", "`-la`", ":\n\n", "```sh\n", "ls -la ~/Documents\n", "```\n\n",
                      "It lists **every** file, hidden ones too, with sizes and dates."]
            gap = 0.02
        elif "slow" in q:
            words = ("Once upon a time, in a small house by the sea, there lived a cat who watched the boats "
                     "every morning and counted the gulls ").split(" ")
            tokens = [w + " " for w in (words * 6)[:120]]
            gap = 0.05
        else:
            tokens = ["Hello", "!", " How can I help?"]
            gap = 0.02
        self.send_response(200)
        self.send_header("Content-Type", "application/x-ndjson")
        self.send_header("Transfer-Encoding", "chunked")
        self.end_headers()

        def chunk(obj):
            data = (json.dumps(obj) + "\n").encode()
            self.wfile.write(b"%x\r\n%s\r\n" % (len(data), data))
            self.wfile.flush()

        try:
            for t in tokens:
                time.sleep(gap)
                chunk({"model": req["model"], "message": {"role": "assistant", "content": t}, "done": False})
            chunk({"model": req["model"], "message": {"role": "assistant", "content": ""}, "done": True,
                   "done_reason": "stop"})
            self.wfile.write(b"0\r\n\r\n")
            self.wfile.flush()
        except (BrokenPipeError, ConnectionResetError):
            log("closed by the client")


ThreadingHTTPServer(("127.0.0.1", int(sys.argv[1])), H).serve_forever()
PY
PORT=${FAKE_PORT:-$((20000 + RANDOM % 20000))}
start_fake() {
  stop_fake
  python3 -I "$W/fake_ollama.py" "$PORT" "$R/fake-ollama.log" >> "$R/fake-ollama.err" 2>&1 &
  FPID=$!
  for _ in $(seq 50); do python3 -I -c "import socket,sys; socket.create_connection(('127.0.0.1', int(sys.argv[1])), 0.2)" "$PORT" 2>/dev/null && return 0; sleep 0.1; done
  fail "the fake Ollama did not start (see $R/fake-ollama.err)"
}

# `ipc.py <doc>` prints the first snapshot's data of a document; `ipc.py <doc> count <seconds>` counts its patches.
cat > "$W/ipc.py" <<'PY'
import json, os, socket, sys, time

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
counting = len(sys.argv) > 3 and sys.argv[2] == "count"
end = None
patches = 0
while True:
    try:
        line = f.readline()
    except socket.timeout:
        line = b""
        if counting:
            break
    if not line:
        if counting:
            break
        sys.exit("ipc: connection closed")
    m = json.loads(line)
    if m.get("t") == "err":
        sys.exit("ipc: " + json.dumps(m))
    if not counting:
        if m.get("id") == "s" and m["t"] == "snap":
            print(json.dumps(m.get("data")))
            sys.exit(0)
        continue
    if m["t"] == "snap" and end is None:
        end = time.monotonic() + float(sys.argv[3])
        sock.settimeout(max(0.05, end - time.monotonic()))
    elif m["t"] == "patch" and m.get("doc") == sys.argv[1]:
        patches += 1
    if end is not None:
        left = end - time.monotonic()
        if left <= 0:
            break
        sock.settimeout(left)
print(patches)
PY
ipc() { timeout 15 python3 -I "$W/ipc.py" "$@"; }
# doc_is <python condition on d>: 0 when it holds for mod.ai now.
doc_is() { ipc mod.ai | python3 -c "import json,sys; d = json.load(sys.stdin) or {}; m = (d.get('current') or {}).get('messages') or []; sys.exit(0 if ($1) else 1)" 2>/dev/null; }
wait_doc() { local i; for i in $(seq "$2"); do doc_is "$1" && return 0; sleep 0.25; done; return 0; }
shot() { # shot <name>
  sleep "${WAIT:-1.5}"
  grim -g "$PANEL_GEOM" "$OUT/$1.png"
  [ -s "$OUT/$1.png" ] || fail "empty screenshot $1"
  echo "shot $1"
}

start_all() { # start_all <decor>
  stop_shell
  stop_daemon
  rm -rf "$R/xdg"
  mkdir -p "$XDG_CONFIG_HOME/kurashi" "$XDG_STATE_HOME" "$XDG_DATA_HOME" "$XDG_CACHE_HOME"
  cat > "$XDG_CONFIG_HOME/kurashi/config.toml" <<TOML
theme.style = "$1"

[mods.ai]
ollama_url = "http://127.0.0.1:$PORT"
TOML
  rm -f "$KURASHI_SOCKET"
  env DBUS_SYSTEM_BUS_ADDRESS="unix:path=$R/no-system-bus" PULSE_SERVER="unix:$R/no-pulse/native" \
    PULSE_RUNTIME_PATH="$R/no-pulse" "$W/kurashid" >> "$R/kurashid.log" 2>&1 &
  DPID=$!
  for _ in $(seq 100); do [ -S "$KURASHI_SOCKET" ] && K ping >/dev/null 2>&1 && break; sleep 0.1; done
  K ping >/dev/null 2>&1 || fail "kurashid did not come up (see $R/kurashid.log)"
  K act mod.enable '{"id": "ai"}' >/dev/null || fail "mod.enable ai failed"
  swaymsg output '*' bg '#8fb8c8' solid_color >/dev/null 2>&1 || true
  env -u KURASHI_SOCKET qs -p "$ROOT/frontend" >> "$R/qs.log" 2>&1 &
  SHPID=$!
  sleep "${SHELL_WAIT:-5}"
}

for DECOR in $DECORS; do
  echo "== $DECOR: the empty panel"
  start_fake
  : > "$R/fake-ollama.log"
  start_all "$DECOR"
  K act mod.panel.open '{"id": "ai", "panel": "ai"}' >/dev/null || fail "mod.panel.open ai failed"
  wait_doc 'd.get("provider", {}).get("id") == "ollama"' 20
  check "$(doc_is 'd["provider"]["state"] == "unknown" and d["provider"]["local"] is True and m == [] and d["busy"] is False' && echo 1 || echo 0)" "$DECOR empty: nothing known, nothing asked"
  shot "empty-$DECOR"
  check "$([ ! -s "$R/fake-ollama.log" ] && echo 1 || echo 0)" "$DECOR empty: opening the panel sent no request (Ma)"

  echo "== $DECOR: an answer with a code block"
  K act ai.ask '{"text": "code: how do I list all files in Documents?"}' >/dev/null || fail "ai.ask failed"
  wait_doc 'd["busy"] is False and len(m) == 2' 40
  check "$(doc_is 'len(m) == 2 and [b["kind"] for b in m[1]["blocks"]] == ["text", "code", "text"] and m[1]["blocks"][1].get("lang") == "sh" and m[1]["model"] == "llama3.2:latest"' && echo 1 || echo 0)" "$DECOR code: text, a sh code block, text, from the first installed model"
  check "$(doc_is 'd["provider"]["state"] == "ready" and d["provider"].get("auto") is True and len(d["conversations"]) == 1' && echo 1 || echo 0)" "$DECOR code: the provider answered, the conversation is listed"
  check "$([ "$(head -2 "$R/fake-ollama.log" | tr '\n' '|')" = "GET /api/tags|POST /api/chat llama3.2:latest auth=no|" ] && echo 1 || echo 0)" "$DECOR code: the tags once, then the chat (no key sent)"
  check "$(ls "$XDG_DATA_HOME/kurashi/ai/conversations/"*.json >/dev/null 2>&1 && grep -q 'ls -la' "$XDG_DATA_HOME"/kurashi/ai/conversations/*.json && echo 1 || echo 0)" "$DECOR code: saved as JSON in the mod's data folder"
  shot "code-$DECOR"
  if command -v wl-paste >/dev/null 2>&1 && command -v wl-copy >/dev/null 2>&1; then
    K act ai.copy '{"message": 1, "block": 1}' >/dev/null || true
    check "$([ "$(timeout 5 wl-paste -n 2>/dev/null)" = "ls -la ~/Documents" ] && echo 1 || echo 0)" "$DECOR copy: the code block is on the clipboard"
  fi

  echo "== $DECOR: an answer while it streams"
  K act ai.ask '{"text": "slow: tell me a story"}' >/dev/null || fail "ai.ask failed"
  wait_doc 'd["busy"] is True and len(((d.get("reply") or {}).get("blocks") or [{}])[0].get("text", "")) > 0' 40
  RATE=$(ipc mod.ai count 2 || echo 999)
  check "$([ "$RATE" -le 21 ] && [ "$RATE" -ge 4 ] && echo 1 || echo 0)" "$DECOR streaming: $RATE patches in 2 s (coarse chunks, ≤ 10 a second)"
  WAIT=0.3 shot "streaming-$DECOR"
  check "$(doc_is 'd["busy"] is True and "reply" in d and len(m) == 3' && echo 1 || echo 0)" "$DECOR streaming: the reply grows beside the saved messages"
  K act ai.stop '{}' >/dev/null || fail "ai.stop failed"
  wait_doc 'd["busy"] is False and len(m) == 4' 20
  check "$(doc_is 'len(m) == 4 and m[3].get("stopped") is True and m[3]["blocks"][0]["text"].startswith("Once upon a time")' && echo 1 || echo 0)" "$DECOR stop: the partial answer is kept, marked stopped"

  echo "== $DECOR: Ollama gone"
  stop_fake
  K act ai.new '{}' >/dev/null || fail "ai.new failed"
  K act ai.ask '{"text": "hello?"}' >/dev/null || fail "ai.ask failed"
  wait_doc 'd["busy"] is False and len(m) == 2' 40
  check "$(doc_is 'm[1].get("error") == "mod-ai.error.ollama_unreachable" and d["provider"]["state"] == "error" and d["provider"]["url"].startswith("http://127.0.0.1:")' && echo 1 || echo 0)" "$DECOR error: Ollama is said to be unreachable at its address"
  shot "error-$DECOR"
  K act ui.close '{}' >/dev/null 2>&1 || true
done
stop_shell
stop_daemon

if grep -Eq 'ReferenceError|TypeError|binding loop|is not a function|is not defined|is not a type' "$R/qs.log" 2>/dev/null; then
  echo "QML errors in qs.log: $(grep -E 'ReferenceError|TypeError|binding loop|is not a function|is not defined|is not a type' "$R/qs.log" | head -5)" >&2
  FAILS=$((FAILS + 1))
fi
if grep -Ei 'mods/ai' "$R/qs.log" 2>/dev/null | grep -Eiq 'warn|error'; then
  echo "QML warnings from the AI mod: $(grep -Ei 'mods/ai' "$R/qs.log" | grep -Ei 'warn|error' | head -5)" >&2
  FAILS=$((FAILS + 1))
fi
if grep -q panicked "$R/kurashid.log" 2>/dev/null; then
  echo "kurashid panicked (see $R/kurashid.log)" >&2
  FAILS=$((FAILS + 1))
fi
echo "checks: $((CHECKS - FAILS < 0 ? 0 : CHECKS - FAILS)) of $CHECKS"
[ "$FAILS" -eq 0 ] || fail "$FAILS failure(s); logs in $R, screenshots in $OUT"
echo "ok: screenshots in $OUT"
