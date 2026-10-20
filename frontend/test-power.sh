#!/usr/bin/env bash
# K47 (W23-system, docs/ux/power.md): idle, keep awake, night light, keyboard layouts, the recorder and the quick tiles,
# against the REAL kurashid, invisibly (headless sway sandbox). Checks:
#   - svc.keyboard from a fake niri socket (the adapter's real event stream): two layouts; keyboard.next reaches the
#     compositor as SwitchLayout and the switch comes back as the document's `current`; the bar shows the short name;
#   - idle.caffeine toggles svc.idle.caffeine (and `inhibited`), and the quick card's Keep awake tile shows it lit;
#   - with idle.dim_after = 30 (the schema's step is 30 s, so the card's 2 s is refused: CONTRACT-CHANGE) and no input the
#     stage goes `dimmed` within ~35 s (headless sway has ext-idle-notify-v1; without it the document must carry the
#     reason); a pointer move brings it back to `active`;
#   - night light with a fake wlsunset on PATH (it records its argv): the manual schedule's flags, a restart with the new
#     warmth, and no process once it is turned off;
#   - the recorder with a fake wf-recorder: recording true with the file and the bar's REC dot; recorder.stop ends it
#     (SIGINT), the file is there and the document says recording false;
#   - shots of the quick card with the three tiles under theme.decor "sekai" and "none", and of the night light page.
#   nix develop -c frontend/test-power.sh [sandbox-name]
# Binaries: kurashid and kurashi from $KURASHI_BIN_DIR (default $CARGO_TARGET_DIR/debug, else target/debug), copied first.
# Shots in frontend/shots/power/. On a hybrid laptop export KURASHI_RENDER_NODE first.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
NAME=${1:-w23-sys-power}
BIN=${KURASHI_BIN_DIR:-${CARGO_TARGET_DIR:-$ROOT/target}/debug}
OUT=$ROOT/frontend/shots/power
mkdir -p "$OUT"
fail() { echo "test-power: FAIL: $*" >&2; exit 1; }
ok() { echo "test-power: ok: $*"; }

eval "$("$ROOT/tools/bench/sandbox.sh" start "$NAME")"
R=$XDG_RUNTIME_DIR
W=$R/work
FAKE=$W/fakebin
mkdir -p "$W" "$FAKE" "$R/kurashi"
cp "$BIN/kurashid" "$BIN/kurashi" "$W/"

pids=()
cleanup() {
  for p in "${pids[@]}"; do kill "$p" 2>/dev/null || true; done
  "$ROOT/tools/bench/sandbox.sh" stop "$NAME" >/dev/null || true
}
trap cleanup EXIT

export XDG_CONFIG_HOME=$R/xdg/config XDG_STATE_HOME=$R/xdg/state \
       XDG_DATA_HOME=$R/xdg/data XDG_CACHE_HOME=$R/xdg/cache KURASHI_DATA_DIR=$ROOT
# The daemon's own home: the recorder saves into its Videos folder.
KHOME=$R/home
mkdir -p "$XDG_CONFIG_HOME/kurashi" "$XDG_STATE_HOME" "$XDG_DATA_HOME" "$XDG_CACHE_HOME" "$KHOME"
cat > "$XDG_CONFIG_HOME/kurashi/config.toml" <<'TOML'
[idle]
dim_after = 30
lock_after = 0
screen_off_after = 0
TOML

# Fake programs: each records its argv and stays up until signalled, as the real ones do.
cat > "$FAKE/wlsunset" <<SH
#!/usr/bin/env bash
echo "\$*" >> "$W/wlsunset.argv"
trap 'echo stopped >> "$W/wlsunset.argv"; exit 0' TERM INT
while :; do sleep 0.2; done
SH
cat > "$FAKE/wf-recorder" <<SH
#!/usr/bin/env bash
echo "\$*" > "$W/wf-recorder.argv"
file=""
while [ \$# -gt 0 ]; do [ "\$1" = -f ] && file=\$2; shift; done
trap 'printf "fake mp4" > "\$file"; echo stopped >> "$W/wf-recorder.argv"; exit 0' INT
while :; do sleep 0.2; done
SH
chmod +x "$FAKE/wlsunset" "$FAKE/wf-recorder"

# A minimal niri: the event stream (no workspaces or windows, two layouts), Outputs, FocusedOutput and actions (logged).
# keyboard.next arrives as SwitchLayout and is answered with KeyboardLayoutSwitched on every open stream.
cat > "$W/fake_niri.py" <<'PY'
import asyncio, json, sys
SOCK, LOG = sys.argv[1], sys.argv[2]
NAMES = ["English (US)", "Japanese"]
state = {"cur": 0}
streams = []

def log(line):
    with open(LOG, "a") as f:
        f.write(line + "\n")

async def handle(r, w):
    line = await r.readline()
    try:
        req = json.loads(line)
    except ValueError:
        w.close(); return
    if req == "EventStream":
        w.write(b'{"Ok":"Handled"}\n')
        for ev in ({"WorkspacesChanged": {"workspaces": []}}, {"WindowsChanged": {"windows": []}},
                   {"KeyboardLayoutsChanged": {"keyboard_layouts": {"names": NAMES, "current_idx": state["cur"]}}}):
            w.write((json.dumps(ev) + "\n").encode())
        try:
            await w.drain()
        except ConnectionError:
            return
        streams.append(w)
        # The daemon shuts its write half after the request; the stream lives until it closes the connection.
        await w.wait_closed()
        streams.remove(w)
        return
    if req == "Outputs":
        reply = {"Ok": {"Outputs": {}}}
    elif req == "FocusedOutput":
        reply = {"Ok": {"FocusedOutput": None}}
    elif isinstance(req, dict) and "Action" in req:
        log("action " + json.dumps(req["Action"], sort_keys=True))
        act = req["Action"]
        if "SwitchLayout" in act:
            t = act["SwitchLayout"]["layout"]
            state["cur"] = (state["cur"] + 1) % len(NAMES) if t == "Next" else int(t.get("Index", 0))
            for s in list(streams):
                s.write((json.dumps({"KeyboardLayoutSwitched": {"idx": state["cur"]}}) + "\n").encode())
        reply = {"Ok": "Handled"}
    else:
        reply = {"Err": "unsupported"}
    w.write((json.dumps(reply) + "\n").encode())
    try:
        await w.drain()
    except ConnectionError:
        pass
    w.close()

async def main():
    srv = await asyncio.start_unix_server(handle, SOCK)
    async with srv:
        await srv.serve_forever()

asyncio.run(main())
PY

K() { timeout 15 "$W/kurashi" "$@"; }
doc() { K sub "$1" --count 0 --json 2>/dev/null | jq -c 'select(.t == "snap") | .data' || true; }
# wait_for <what> <jq filter on the doc> <doc> [tries of 0.1 s]
wait_for() {
  local what=$1 filter=$2 name=$3 n=${4:-80}
  for _ in $(seq "$n"); do
    [ "$(doc "$name" | jq -r "$filter" 2>/dev/null)" = true ] && return 0
    sleep 0.1
  done
  echo "last $name: $(doc "$name")" >&2
  fail "$what"
}
shot() { sleep "${2:-1.2}"; grim "$OUT/$1.png"; [ -s "$OUT/$1.png" ] || fail "empty screenshot $1"; echo "shot $1"; }

python3 -I "$W/fake_niri.py" "$R/niri.sock" "$W/niri.log" &
pids+=("$!")
for _ in $(seq 50); do [ -S "$R/niri.sock" ] && break; sleep 0.1; done
[ -S "$R/niri.sock" ] || fail "fake niri did not start"
export NIRI_SOCKET=$R/niri.sock

: > "$R/kurashid.log"; : > "$R/qs.log"
rm -f "$KURASHI_SOCKET"
HOME=$KHOME PATH="$FAKE:$PATH" DBUS_SYSTEM_BUS_ADDRESS="unix:path=$R/no-system-bus" "$W/kurashid" >> "$R/kurashid.log" 2>&1 &
pids+=("$!")
for _ in $(seq 100); do [ -S "$KURASHI_SOCKET" ] && K ping >/dev/null 2>&1 && break; sleep 0.1; done
K ping >/dev/null 2>&1 || fail "kurashid did not come up (see $R/kurashid.log)"

env -u KURASHI_SOCKET qs -p "$ROOT/frontend" >> "$R/qs.log" 2>&1 &
pids+=("$!")
for _ in $(seq 80); do grep -q 'hello.*frontend' "$R/kurashid.log" && break; sleep 0.1; done
grep -q 'hello.*frontend' "$R/kurashid.log" || fail "frontend never said hello (see $R/qs.log)"

# ---- keyboard layouts (the bar watches svc.keyboard, so its stream stays up) ----------------------------------------------
wait_for "svc.keyboard has two layouts" '(.layouts | length) == 2 and .current == 0 and .layouts[1].short == "jp"' svc.keyboard
ok "svc.keyboard from the compositor: $(doc svc.keyboard)"
shot bar-layout-us

K act keyboard.next >/dev/null || fail "keyboard.next refused"
grep -q '"SwitchLayout": {"layout": "Next"}' "$W/niri.log" || fail "keyboard.next did not reach the compositor: $(cat "$W/niri.log")"
wait_for "the switch comes back as current 1" '.current == 1' svc.keyboard
ok "keyboard.next → SwitchLayout → current 1"
shot bar-layout-jp

# ---- idle: dimmed with no input, active again on input ---------------------------------------------------------------
idle=$(doc svc.idle)
if echo "$idle" | jq -e '.reason' >/dev/null; then
  echo "$idle" | jq -e '.stage == "active"' >/dev/null || fail "unsupported idle must stay active: $idle"
  ok "no ext-idle-notify here: reason $(echo "$idle" | jq -r .reason)"
else
  # No input since the daemon armed the notification (the sandbox seat has no devices): 30 s plus slack.
  for _ in $(seq 45); do [ "$(doc svc.idle | jq -r .stage)" = dimmed ] && break; sleep 1; done
  wait_for "stage dimmed within ~35 s of no input" '.stage == "dimmed" and .next == null' svc.idle 5
  ok "dimmed with no input: $(doc svc.idle)"
  python3 -I "$ROOT/tools/bench/wl_pointer.py" move 1200 700 >/dev/null || fail "pointer move failed"
  wait_for "input brings the stage back" '.stage == "active"' svc.idle 40
  ok "active again after input"
fi

# ---- caffeine --------------------------------------------------------------------------------------------------------
K act idle.caffeine >/dev/null || fail "idle.caffeine refused"
wait_for "caffeine on" '.caffeine == true and .inhibited == true' svc.idle
ok "idle.caffeine on: $(doc svc.idle)"

# ---- night light -------------------------------------------------------------------------------------------------------
K act nightlight.toggle '{"on": true}' >/dev/null || fail "nightlight.toggle refused"
wait_for "night light enabled" '.enabled == true and .available == true' svc.nightlight
for _ in $(seq 30); do [ -s "$W/wlsunset.argv" ] && break; sleep 0.1; done
grep -qx -- "-t 4000 -T 6500 -S 07:00 -s 20:00 -d 900" "$W/wlsunset.argv" || fail "wlsunset argv: $(cat "$W/wlsunset.argv" 2>/dev/null)"
ok "wlsunset started with the manual schedule's flags"
K set night_light.temperature=3000 >/dev/null || fail "temperature not set"
for _ in $(seq 30); do grep -q -- "^-t 3000 " "$W/wlsunset.argv" && break; sleep 0.1; done
grep -q -- "^-t 3000 " "$W/wlsunset.argv" || fail "no restart with the new warmth: $(cat "$W/wlsunset.argv")"
grep -q '^stopped$' "$W/wlsunset.argv" || fail "the old wlsunset was not stopped first"
ok "restarted with -t 3000"

# ---- recorder -----------------------------------------------------------------------------------------------------
wait_for "recorder available (fake wf-recorder)" '.available == true and .backend == "wf-recorder"' svc.recorder
K act recorder.start >/dev/null || fail "recorder.start refused"
wait_for "recording" '.recording == true and (.file | test("kurashi-.*\\.mp4$"))' svc.recorder
for _ in $(seq 30); do [ -s "$W/wf-recorder.argv" ] && break; sleep 0.1; done
grep -q -- "-y -f $KHOME/Videos/kurashi-.*\.mp4 --audio" "$W/wf-recorder.argv" || fail "wf-recorder argv: $(cat "$W/wf-recorder.argv")"
ok "wf-recorder started: $(head -1 "$W/wf-recorder.argv")"

# ---- the quick card with the three tiles, two decors ---------------------------------------------------------------------
shot bar-recording
K act quick.toggle >/dev/null
for decor in sekai none; do
  K set theme.decor="$decor" >/dev/null || fail "theme.decor $decor"
  shot "quick-$decor" 2
done

# The night light page: a click on the night tile's arrow (sekai: the 8th tile, right column, at 1441,388).
K set theme.decor=sekai >/dev/null
K act ui.close >/dev/null
sleep 0.5
K act quick.toggle >/dev/null
sleep 1.5
python3 -I "$ROOT/tools/bench/wl_pointer.py" click 1441 388 left >/dev/null || fail "click on the night tile's arrow"
shot night-page 1.5
K act ui.close >/dev/null
sleep 0.5
K act quick.toggle >/dev/null
sleep 1
# ---- stop the recorder (the card shows Record lit until then) ----------------------------------------------------------
K act recorder.stop >/dev/null || fail "recorder.stop refused"
wait_for "recording ended" '.recording == false and (.file | test("\\.mp4$"))' svc.recorder
f=$(doc svc.recorder | jq -r .file)
[ -s "$f" ] || fail "no file after stop: $f"
grep -q '^stopped$' "$W/wf-recorder.argv" || fail "wf-recorder was not stopped with SIGINT"
ok "recorder.stop: file $f"
shot quick-after-stop
K act ui.close >/dev/null

# ---- night light off: no process ---------------------------------------------------------------------------------------
K act nightlight.toggle '{"on": false}' >/dev/null || fail "nightlight.toggle off refused"
wait_for "night light off" '.enabled == false' svc.nightlight
sleep 0.5
left=0
for p in $(pgrep -f "$FAKE/wlsunset" || true); do
  if tr '\0' '\n' < "/proc/$p/environ" 2>/dev/null | grep -qx "XDG_RUNTIME_DIR=$R"; then left=$((left + 1)); fi
done
[ "$left" = 0 ] || fail "wlsunset still runs after disable ($left)"
ok "no wlsunset after disable"

K act idle.caffeine '{"on": false}' >/dev/null
wait_for "caffeine off" '.caffeine == false' svc.idle
grep -E "QML|TypeError|ReferenceError" "$R/qs.log" | grep -v "^$" | head -5 > "$W/qml-errors" || true
if [ -s "$W/qml-errors" ]; then cat "$W/qml-errors" >&2; fail "the frontend logged QML errors"; fi
echo "test-power: all checks passed; shots in $OUT"
