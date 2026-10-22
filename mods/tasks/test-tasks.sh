#!/usr/bin/env bash
# The tasks mod in the REAL shell (W22-tasks, K46), invisibly: the real kurashid and the real Quickshell frontend in the
# headless sway sandbox, with `desktop.enabled = true`, the mod on and its two files in a vault folder of the sandbox.
# Per decor (sekai, none): the missing file (desk), two tasks added with `kurashi act tasks.add`, one ticked, then the
# file and the note edited on disk behind the daemon's back (the watch must publish it), the desk, the panel, and an
# empty file. Checks: each step's document says what it should; the file on disk is what the actions wrote; no QML error
# or warning from the mod in qs.log; no panic in kurashid's log.
# Screenshots (mods/tasks/shots/): {missing,desk,panel,panel-note,empty}-{sekai,none}.png (the desk column, or the
# panel's card).
#   KURASHI_RENDER_NODE=/dev/dri/renderD129 KURASHI_BIN_DIR=<dir with kurashid and kurashi> \
#     timeout 900 nix develop -c mods/tasks/test-tasks.sh [sandbox-name]
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
NAME=${1:-w22-tsk-live}   # unique per run: other runs stop any sandbox that shares a name
BIN=${KURASHI_BIN_DIR:-${CARGO_TARGET_DIR:-$ROOT/target}/debug}
OUT=$ROOT/mods/tasks/shots
DECORS=${DECORS:-sekai none}
# Machine B's iGPU when it exists; elsewhere sandbox.sh picks the display GPU (boot_vga).
[ -e /dev/dri/renderD129 ] && export KURASHI_RENDER_NODE=${KURASHI_RENDER_NODE:-/dev/dri/renderD129}
# The desk column (layout px of the 2560 x 1440 output): 300 px wide, 32 px from the right edge, under the bar.
DESK_GEOM=${DESK_GEOM:-"2200,30 360x1180"}
# The Stage card of a mod panel sits under the bar, centred.
PANEL_GEOM=${PANEL_GEOM:-"1020,30 520x900"}
# The header's "Note" tab in that card (layout px).
NOTE_TAB_X=${NOTE_TAB_X:-1442}
NOTE_TAB_Y=${NOTE_TAB_Y:-69}
mkdir -p "$OUT"
FAILS=0
CHECKS=0
fail() { echo "test-tasks: $*" >&2; exit 1; }
check() { # check <0|1> <label>
  CHECKS=$((CHECKS + 1))
  if [ "$1" = 1 ]; then echo "ok: $2"; else echo "FAIL: $2"; FAILS=$((FAILS + 1)); fi
}

eval "$("$ROOT/tools/bench/sandbox.sh" start "$NAME")"
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

# Hermetic: no config, state or cache from an earlier run; the system bus is not reachable.
export XDG_CONFIG_HOME=$R/xdg/config XDG_STATE_HOME=$R/xdg/state XDG_DATA_HOME=$R/xdg/data XDG_CACHE_HOME=$R/xdg/cache
export KURASHI_DATA_DIR=$ROOT LC_ALL=C.UTF-8
VAULT=$R/vault
TASKS=$VAULT/Tasks.md
NOTE=$VAULT/Note.md
K() { timeout 10 "$W/kurashi" "$@"; }

# `ipc.py <doc>` prints the first snapshot's data of a document (stdlib only, as in mods/weather/test-states.sh).
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
# doc_is <python condition on d>: 0 when it holds for mod.tasks now.
doc_is() { ipc mod.tasks | python3 -c "import json,sys; d = json.load(sys.stdin) or {}; sys.exit(0 if ($1) else 1)" 2>/dev/null; }
wait_doc() { local i; for i in $(seq "$2"); do doc_is "$1" && return 0; sleep 0.5; done; return 0; }
# id_of <text>: the id of the listed task with that text.
id_of() { ipc mod.tasks | python3 -c "import json,sys; d = json.load(sys.stdin); print(next(t['id'] for t in d['tasks'] if t['text'] == sys.argv[1]))" "$1"; }
shot() { # shot <name> <geometry>
  sleep "${WAIT:-2}"
  grim -g "$2" "$OUT/$1.png"
  [ -s "$OUT/$1.png" ] || fail "empty screenshot $1"
  echo "shot $1"
}

start_all() { # start_all <decor>
  stop_shell
  stop_daemon
  rm -rf "$R/xdg" "$VAULT"
  mkdir -p "$XDG_CONFIG_HOME/kurashi" "$XDG_STATE_HOME" "$XDG_DATA_HOME" "$XDG_CACHE_HOME"
  cat > "$XDG_CONFIG_HOME/kurashi/config.toml" <<TOML
theme.style = "$1"
desktop.enabled = true

[mods.tasks]
file = "$TASKS"
notes_file = "$NOTE"
TOML
  rm -f "$KURASHI_SOCKET"
  env DBUS_SYSTEM_BUS_ADDRESS="unix:path=$R/no-system-bus" PULSE_SERVER="unix:$R/no-pulse/native" \
    PULSE_RUNTIME_PATH="$R/no-pulse" "$W/kurashid" >> "$R/kurashid.log" 2>&1 &
  DPID=$!
  for _ in $(seq 100); do [ -S "$KURASHI_SOCKET" ] && K ping >/dev/null 2>&1 && break; sleep 0.1; done
  K ping >/dev/null 2>&1 || fail "kurashid did not come up (see $R/kurashid.log)"
  K act mod.enable '{"id": "tasks"}' >/dev/null || fail "mod.enable tasks failed"
  swaymsg output '*' bg '#8fb8c8' solid_color >/dev/null 2>&1 || true
  env -u KURASHI_SOCKET qs -p "$ROOT/frontend" >> "$R/qs.log" 2>&1 &
  SHPID=$!
  sleep "${SHELL_WAIT:-5}"
}

for DECOR in $DECORS; do
  echo "== $DECOR: missing file"
  start_all "$DECOR"
  wait_doc 'd.get("state") == "missing"' 20
  check "$(doc_is 'd.get("state") == "missing" and d.get("reason") == "mod-tasks.missing" and d.get("open") == 0' && echo 1 || echo 0)" "$DECOR missing: the document says the file is missing"
  shot "missing-$DECOR" "$DESK_GEOM"

  echo "== $DECOR: two tasks added, one ticked"
  K act tasks.add '{"text": "Buy milk"}' >/dev/null || fail "tasks.add failed"
  K act tasks.add '{"text": "Call the dentist"}' >/dev/null || fail "tasks.add failed"
  wait_doc 'd.get("open") == 2' 20
  check "$(doc_is 'd.get("state") == "ready" and d.get("open") == 2 and [t["text"] for t in d["tasks"]] == ["Buy milk", "Call the dentist"]' && echo 1 || echo 0)" "$DECOR add: two open tasks"
  check "$([ "$(cat "$TASKS" 2>/dev/null)" = "$(printf -- '- [ ] Buy milk\n- [ ] Call the dentist')" ] && echo 1 || echo 0)" "$DECOR add: the file holds the two lines"
  K act tasks.toggle "{\"id\": \"$(id_of 'Buy milk')\"}" >/dev/null || fail "tasks.toggle failed"
  wait_doc 'd.get("done") == 1' 20
  check "$(doc_is 'd.get("done") == 1 and d["tasks"][0]["done"] is True' && echo 1 || echo 0)" "$DECOR toggle: one done, still listed (today)"
  check "$(grep -q -- '- \[x\] Buy milk ✅ ' "$TASKS" && echo 1 || echo 0)" "$DECOR toggle: the file carries the done date"

  echo "== $DECOR: the file and the note edited behind the daemon's back"
  {
    cat "$TASKS"
    printf '\n# Today\n- [ ] Pay the rent ⏫ 📅 %s\n- [ ] Water the plants 🔼 📅 %s\n- [ ] Send the parcel 🔽\n' \
      "$(date +%F)" "$(date -d tomorrow +%F)"
    printf '\n# Later\n- [ ] Book the train for the weekend trip to Kyoto 📅 %s\n- [ ] Read chapter 3\n' "$(date -d '-2 days' +%F)"
  } > "$TASKS.new"
  mv "$TASKS.new" "$TASKS"
  printf '# Groceries\nmilk, eggs, miso\n\nAsk about the 金曜日 dinner.\n' > "$NOTE"
  wait_doc 'd.get("open") == 6 and d["notes"].get("state") == "ready"' 20
  check "$(doc_is 'd.get("open") == 6 and any(t.get("priority") == 1 and t.get("section") == "Today" and t.get("due") for t in d["tasks"]) and d["notes"]["text"].startswith("# Groceries")' && echo 1 || echo 0)" "$DECOR external edit: the watch published the new lines, markers and note"
  shot "desk-$DECOR" "$DESK_GEOM"

  echo "== $DECOR: the panel"
  K act mod.panel.open '{"id": "tasks", "panel": "tasks"}' >/dev/null || fail "mod.panel.open tasks failed"
  shot "panel-$DECOR" "$PANEL_GEOM"
  # The note tab: a click on its label in the panel's header.
  timeout 30 python3 -I "$ROOT/tools/bench/wl_pointer.py" click "$NOTE_TAB_X" "$NOTE_TAB_Y" left >> "$R/keys.log" 2>&1 || true
  shot "panel-note-$DECOR" "$PANEL_GEOM"
  K act ui.close '{}' >/dev/null 2>&1 || true

  echo "== $DECOR: an empty file"
  : > "$TASKS"
  rm -f "$NOTE"
  wait_doc 'd.get("state") == "ready" and d.get("open") == 0 and d["notes"].get("state") == "missing"' 20
  check "$(doc_is 'd.get("state") == "ready" and d.get("open") == 0 and d.get("tasks") == []' && echo 1 || echo 0)" "$DECOR empty: ready with nothing to do"
  shot "empty-$DECOR" "$DESK_GEOM"
done
stop_shell
stop_daemon

if grep -Eq 'ReferenceError|TypeError|binding loop|is not a function|is not defined|is not a type' "$R/qs.log" 2>/dev/null; then
  echo "QML errors in qs.log: $(grep -E 'ReferenceError|TypeError|binding loop|is not a function|is not defined|is not a type' "$R/qs.log" | head -5)" >&2
  FAILS=$((FAILS + 1))
fi
if grep -Ei 'mods/tasks|Desktop.qml' "$R/qs.log" 2>/dev/null | grep -Eiq 'warn|error'; then
  echo "QML warnings from the tasks mod or the desk: $(grep -Ei 'mods/tasks|Desktop.qml' "$R/qs.log" | grep -Ei 'warn|error' | head -5)" >&2
  FAILS=$((FAILS + 1))
fi
if grep -q panicked "$R/kurashid.log" 2>/dev/null; then
  echo "kurashid panicked (see $R/kurashid.log)" >&2
  FAILS=$((FAILS + 1))
fi
echo "checks: $((CHECKS - FAILS < 0 ? 0 : CHECKS - FAILS)) of $CHECKS"
[ "$FAILS" -eq 0 ] || fail "$FAILS failure(s); logs in $R, screenshots in $OUT"
echo "ok: screenshots in $OUT"
