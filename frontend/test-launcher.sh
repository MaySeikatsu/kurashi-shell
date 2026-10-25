#!/usr/bin/env bash
# The launcher's clipboard, emoji grid and keybind cheat sheet in the REAL shell (W26, docs/ux/launcher.md), invisibly:
# the real kurashid and the real Quickshell frontend in the headless sway sandbox. A FAKE cliphist and a FAKE wl-copy
# come first on the daemon's PATH, so no clipboard history and no clipboard (not even the sandbox's) is ever touched:
# the fake history is a folder of files, the fake wl-copy writes what it was given to a log. niri's binds come from a
# fixture config with includes (docs/niri-binds.kdl among them). Per decor (sekai, none):
#   1. `;`: text rows show two lines, the visible image rows get a thumbnail (decoded once into the cache), an image far
#      down the list is NOT decoded (Ma); Ctrl+P pins the newest entry (listed first), Shift+Delete removes one (cliphist
#      delete reads its line), Enter on an image copies it as image/png; the clear row asks first, Enter again wipes;
#   2. `:`: the grid, arrows move in two dimensions, Enter copies; the copied emoji comes first next time (recent);
#   3. `?` via action launcher.keys: the cheat sheet, grouped, kurashi's own binds labelled; launcher.keys again closes.
#   4. W34 (docs/ux/motion.md): the launcher grows out of the island pill and folds back into it. Per look x profile x bar
#      edge (MORPH_CASES), three grims at MORPH_AT ms (40 120 250) after `launcher.toggle`, the card at rest, and two
#      grims after the close; the motion profile in effect is checked first (the theme document's `motion.profile`).
# Checks print ok / FAIL; any FAIL, QML error or kurashid panic makes the run exit 1.
# Shots: frontend/shots/launcher/w26/{clip,clip-confirm,emoji,keys}-{sekai,none}.png (the launcher card);
#   frontend/shots/morph/launcher-<look>-<profile>-<edge>-{open-40,open-120,open-250,rest,close-40,close-120}.png.
# LAUNCHER_PHASES=modes|morph|"modes morph" picks the phases (both by default).
#   KURASHI_RENDER_NODE=/dev/dri/renderD129 KURASHI_BIN_DIR=<dir with kurashid and kurashi> \
#     timeout 900 nix develop -c frontend/test-launcher.sh [sandbox-name]
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
NAME=${1:-w26-lch-1}   # unique per run: other runs stop any sandbox that shares a name
BIN=${KURASHI_BIN_DIR:-${CARGO_TARGET_DIR:-$ROOT/target}/debug}
OUT=$ROOT/frontend/shots/launcher/w26
DECORS=${DECORS:-sekai none}
# Machine B's iGPU when it exists; elsewhere sandbox.sh picks the display GPU (boot_vga).
[ -e /dev/dri/renderD129 ] && export KURASHI_RENDER_NODE=${KURASHI_RENDER_NODE:-/dev/dri/renderD129}
# The launcher card, hanging from the top bar under the island (W34) on the 2560 x 1440 output.
CARD_GEOM=${CARD_GEOM:-"930,0 700x720"}
PHASES=${LAUNCHER_PHASES:-modes morph}
MOUT=$ROOT/frontend/shots/morph
AT=${MORPH_AT:-40 120 250}
# <look>:<profile>:<edge>; each look in its own profile on both edges and in the other one on top; `none` cuts.
MORPH_CASES=${MORPH_CASES:-washi:calm:top washi:calm:bottom washi:lively:top sekai:lively:top sekai:lively:bottom sekai:calm:top kami:calm:top kami:calm:bottom kami:lively:top sekai:none:top}
mkdir -p "$OUT" "$MOUT"
FAILS=0
CHECKS=0
fail() { echo "test-launcher: $*" >&2; exit 1; }
check() { # check <0|1> <label>
  CHECKS=$((CHECKS + 1))
  if [ "$1" = 1 ]; then echo "ok: $2"; else echo "FAIL: $2"; FAILS=$((FAILS + 1)); fi
}

eval "$("$ROOT/tools/bench/sandbox.sh" start "$NAME")"
R=$XDG_RUNTIME_DIR
W=$R/work
mkdir -p "$W" "$R/kurashi"
cp "$BIN/kurashid" "$BIN/kurashi" "$W/"
rm -f "$R/qs.log" "$R/kurashid.log" "$R/keys.log"
for _ in $(seq 150); do timeout 5 swaymsg -t get_outputs >/dev/null 2>&1 && break; sleep 0.2; done
timeout 5 swaymsg -t get_outputs >/dev/null 2>&1 || fail "the headless compositor does not answer (see $R/sway.log)"

DPID=""
SHPID=""
KPID=""
stop_daemon() { if [ -n "$DPID" ]; then kill "$DPID" 2>/dev/null || true; wait "$DPID" 2>/dev/null || true; fi; DPID=""; }
stop_shell() { if [ -n "$SHPID" ]; then kill "$SHPID" 2>/dev/null || true; wait "$SHPID" 2>/dev/null || true; fi; SHPID=""; }
stop_keys() { if [ -n "$KPID" ]; then exec 3>&- 2>/dev/null || true; kill "$KPID" 2>/dev/null || true; wait "$KPID" 2>/dev/null || true; fi; KPID=""; }
cleanup() {
  stop_keys
  stop_shell
  stop_daemon
  # MORPH_LOG=<file> keeps the frontend's log (KURASHI_MORPH_DEBUG=1 adds the morph's lines).
  if [ -n "${MORPH_LOG:-}" ]; then cp "$R/qs.log" "$MORPH_LOG" 2>/dev/null || true; fi
  "$ROOT/tools/bench/sandbox.sh" stop "$NAME" >/dev/null || true
}
trap cleanup EXIT

# Hermetic: no config, state or cache from an earlier run; the system bus is not reachable.
export XDG_CONFIG_HOME=$R/xdg/config XDG_STATE_HOME=$R/xdg/state XDG_DATA_HOME=$R/xdg/data XDG_CACHE_HOME=$R/xdg/cache
export KURASHI_DATA_DIR=$ROOT LC_ALL=C.UTF-8
unset NIRI_CONFIG
FAKE=$R/fakebin
DB=$R/cliphist-db
CLIP_CACHE=$XDG_CACHE_HOME/kurashi/clip
PINS=$XDG_STATE_HOME/kurashi/clip-pins/pins.json
K() { timeout 10 "$W/kurashi" "$@"; }
# The launcher's rows for a query, as JSON lines (one request on the socket).
rows() {
  python3 -I - "$1" <<'PY'
import json, os, socket, sys
s = socket.socket(socket.AF_UNIX); s.settimeout(10); s.connect(os.environ["KURASHI_SOCKET"]); f = s.makefile("rwb")
def send(m): f.write((json.dumps(m) + "\n").encode()); f.flush()
send({"t": "hello", "v": 1, "client": "test", "caps": []}); f.readline()
send({"t": "query", "id": "q", "kind": "launcher", "q": sys.argv[1]})
while True:
    m = json.loads(f.readline())
    if m.get("id") == "q":
        for r in m.get("items", []): print(json.dumps(r, ensure_ascii=False))
        break
PY
}
shot() { # shot <name>
  sleep "${WAIT:-1.5}"
  grim -g "$CARD_GEOM" "$OUT/$1.png"
  [ -s "$OUT/$1.png" ] || fail "empty screenshot $1"
  echo "shot $1"
}
kp() { for k in "$@"; do echo "$k" >&3; sleep 0.3; done; }

# The fake cliphist: entries are files `<id>` (content) and `<id>.preview` (the list line) in $DB; every call is logged.
mkdir -p "$FAKE"
cat > "$FAKE/cliphist" <<SH
#!/bin/sh
d=$DB
echo "\$*" >> $R/cliphist.log
case "\$1" in
  list) for f in \$(ls "\$d" | grep -v preview | sort -rn); do printf '%s\t%s\n' "\$f" "\$(cat "\$d/\$f.preview")"; done ;;
  decode) cat "\$d/\$2" ;;
  delete) read -r line; id=\${line%%	*}; echo "deleted \$id" >> $R/cliphist.log; rm -f "\$d/\$id" "\$d/\$id.preview" ;;
  wipe) rm -f "\$d"/* ;;
esac
SH
cat > "$FAKE/wl-copy" <<SH
#!/bin/sh
bytes=\$(cat | wc -c)
echo "\$* \$bytes" >> $R/copied.log
SH
chmod +x "$FAKE/cliphist" "$FAKE/wl-copy"
put() { # put <id> <file|text> <preview>
  if [ -f "$2" ]; then cp "$2" "$DB/$1"; else printf '%s' "$2" > "$DB/$1"; fi
  printf '%s' "$3" > "$DB/$1.preview"
}
fill_history() {
  rm -rf "$DB"; mkdir -p "$DB"
  # Oldest first; the list is newest first. Id 1 is an image far down the list: never on screen, never decoded.
  put 1 "$ROOT/frontend/shots/look/sekai/island.png" "[[ binary data 61 KiB png 2560x1440 ]]"
  for i in $(seq 2 11); do put "$i" "note $i" "note $i"; done
  put 12 "$ROOT/frontend/shots/look/glass/launcher.png" "[[ binary data 87 KiB png 2560x1440 ]]"
  put 13 "a long entry that wraps: the quick brown fox jumps over the lazy dog, again and again, until the row runs out of room and has to end" \
    "a long entry that wraps: the quick brown fox jumps over the lazy dog, again and again, until the row runs out of room and has to end"
  put 14 "$ROOT/frontend/shots/look/sekai/quick.png" "[[ binary data 84 KiB png 2560x1440 ]]"
  put 15 "https://kurashi.example/暮らし" "https://kurashi.example/暮らし"
}
# niri's config: binds of its own, the kurashi snippet, a nested include.
niri_fixture() {
  mkdir -p "$XDG_CONFIG_HOME/niri/more"
  cp "$ROOT/docs/niri-binds.kdl" "$XDG_CONFIG_HOME/niri/kurashi-binds.kdl"
  cat > "$XDG_CONFIG_HOME/niri/config.kdl" <<'KDL'
input { mod-key "Super"; }
binds {
    Mod+T hotkey-overlay-title="Open a Terminal: foot" { spawn "foot"; }
    Mod+Q repeat=false { close-window; }
    Mod+Left  { focus-column-left; }
    Mod+Right { focus-column-right; }
    Mod+F { maximize-column; }
    Mod+O repeat=false { toggle-overview; }
    Mod+Shift+Slash { show-hotkey-overlay; }
    Print { screenshot; }
    /-Mod+X { quit; }
}
include "more/workspaces.kdl"
include "kurashi-binds.kdl"
KDL
  cat > "$XDG_CONFIG_HOME/niri/more/workspaces.kdl" <<'KDL'
binds {
    Mod+1 { focus-workspace 1; }
    Mod+2 { focus-workspace 2; }
    Mod+Ctrl+1 { move-column-to-workspace 1; }
    Mod+Page_Down { focus-workspace-down; }
    Mod+Shift+Left { move-column-to-monitor-left; }
}
KDL
}

start_all() { # start_all <decor> [config line ...]
  stop_keys
  stop_shell
  stop_daemon
  rm -rf "$R/xdg" "$R/cliphist.log" "$R/copied.log"
  mkdir -p "$XDG_CONFIG_HOME/kurashi" "$XDG_STATE_HOME" "$XDG_DATA_HOME" "$XDG_CACHE_HOME"
  fill_history
  niri_fixture
  { printf 'theme.style = "%s"\n' "$1"; shift; printf '%s\n' "$@"; } > "$XDG_CONFIG_HOME/kurashi/config.toml"
  rm -f "$KURASHI_SOCKET"
  env PATH="$FAKE:$PATH" DBUS_SYSTEM_BUS_ADDRESS="unix:path=$R/no-system-bus" PULSE_SERVER="unix:$R/no-pulse/native" \
    PULSE_RUNTIME_PATH="$R/no-pulse" "$W/kurashid" >> "$R/kurashid.log" 2>&1 &
  DPID=$!
  for _ in $(seq 100); do [ -S "$KURASHI_SOCKET" ] && K ping >/dev/null 2>&1 && break; sleep 0.1; done
  K ping >/dev/null 2>&1 || fail "kurashid did not come up (see $R/kurashid.log)"
  swaymsg output '*' bg '#8fb8c8' solid_color >/dev/null 2>&1 || true
  env -u KURASHI_SOCKET qs -p "$ROOT/frontend" >> "$R/qs.log" 2>&1 &
  SHPID=$!
  sleep "${SHELL_WAIT:-5}"
  rm -f "$R/keys.fifo"
  mkfifo "$R/keys.fifo"
  python3 -I "$ROOT/tools/bench/wl_keys.py" --serve < "$R/keys.fifo" >> "$R/keys.log" 2>&1 &
  KPID=$!
  exec 3> "$R/keys.fifo"
}
has() { grep -q -- "$2" "$1" 2>/dev/null && echo 1 || echo 0; }

for DECOR in $DECORS; do
  [[ " $PHASES " == *" modes "* ]] || break
  echo "== $DECOR: clipboard"
  start_all "$DECOR"
  K act launcher.toggle >/dev/null
  sleep 1
  kp semicolon
  sleep 2.5
  check "$([ -s "$CLIP_CACHE/14.png" ] && [ -s "$CLIP_CACHE/12.png" ] && echo 1 || echo 0)" "$DECOR the visible images got thumbnails"
  check "$([ ! -e "$CLIP_CACHE/1.png" ] && echo 1 || echo 0)" "$DECOR the image far down was not decoded"
  # Ctrl+P pins the newest entry (the URL); it is listed first and its history row is not listed twice.
  kp ctrl+p
  sleep 1
  check "$(python3 -c 'import json,sys; p=json.load(open(sys.argv[1]))["pins"]; sys.exit(0 if len(p)==1 and p[0]["src"]=="15" else 1)' "$PINS" && echo 1 || echo 0)" "$DECOR Ctrl+P pinned entry 15"
  first=$(rows ';' | head -1)
  check "$(echo "$first" | grep -q '"pinned": true' && echo 1 || echo 0)" "$DECOR the pin is listed first"
  # Down to the image (14), shot: thumbnails, two-line text, the pin.
  kp down
  shot "clip-$DECOR"
  kp return
  sleep 1
  check "$(has "$R/copied.log" '--type image/png')" "$DECOR Enter on an image copied it as image/png ($(tail -1 "$R/copied.log" 2>/dev/null))"
  check "$(K raw '{"t":"sub","id":"s","doc":"runtime.ui"}' | head -1 | grep -q '"launcher":false' && echo 1 || echo 0)" "$DECOR the launcher closed after copying"
  # Shift+Delete removes the selected entry (the long text, 13).
  K act launcher.toggle >/dev/null
  sleep 1
  kp semicolon
  sleep 1
  kp down down
  kp shift+delete
  sleep 1
  check "$(has "$R/cliphist.log" 'deleted 13')" "$DECOR Shift+Delete deleted entry 13 through cliphist"
  # The clear row is last: down to it, Enter asks, Enter again wipes (the pin stays).
  for _ in $(seq 16); do echo down >&3; sleep 0.12; done
  kp return
  shot "clip-confirm-$DECOR"
  check "$([ -s "$CLIP_CACHE/1.png" ] && echo 1 || echo 0)" "$DECOR the old image was decoded once its row came into view"
  check "$([ "$(has "$R/cliphist.log" '^wipe')" = 0 ] && echo 1 || echo 0)" "$DECOR the first Enter only asked"
  kp return
  sleep 1
  check "$(has "$R/cliphist.log" '^wipe')" "$DECOR the second Enter wiped the history"
  check "$(rows ';' | grep -c '"pinned": true' | grep -qx 1 && echo 1 || echo 0)" "$DECOR the pin survived the wipe"
  check "$(ls "$CLIP_CACHE" 2>/dev/null | wc -l | grep -qx 0 && echo 1 || echo 0)" "$DECOR the wipe removed the thumbnails"
  kp escape
  sleep 0.8

  echo "== $DECOR: emoji"
  K act launcher.toggle >/dev/null
  sleep 1
  kp colon
  sleep 1.5
  kp right right down
  shot "emoji-$DECOR"
  copies=$(grep -c '' "$R/copied.log" || true)
  want=$(rows ':' | sed -n 11p | python3 -c 'import json,sys; print(json.loads(sys.stdin.readline())["glyph"])')
  kp return
  sleep 1
  check "$([ "$(grep -c '' "$R/copied.log")" -gt "$copies" ] && echo 1 || echo 0)" "$DECOR Enter copied the emoji"
  got=$(rows ':' | head -1 | python3 -c 'import json,sys; r=json.loads(sys.stdin.readline()); print(r["glyph"], r.get("recent", False))')
  check "$([ "$got" = "$want True" ] && echo 1 || echo 0)" "$DECOR the copied emoji ($want) comes first and is recent ($got)"

  echo "== $DECOR: keys"
  K act launcher.keys >/dev/null
  sleep 2
  shot "keys-$DECOR"
  keys=$(rows '?')
  check "$(echo "$keys" | grep -q '"kind": "keygroup", "name": "Shell"\|"name": "Shell"' && echo 1 || echo 0)" "$DECOR the cheat sheet has a Shell group"
  check "$(echo "$keys" | grep '"name": "Launcher"' | grep -q '"Super", "Space"' && echo 1 || echo 0)" "$DECOR Mod+Space reads Launcher, Super Space"
  check "$(echo "$keys" | grep -q 'Open a Terminal: foot' && echo 1 || echo 0)" "$DECOR hotkey-overlay-title labels a bind"
  check "$(echo "$keys" | grep -q '"generic": "quit"' && echo 0 || echo 1)" "$DECOR a slashdashed bind is not listed"
  check "$(echo "$keys" | grep -q 'Workspace 2' && echo 1 || echo 0)" "$DECOR the nested include's binds are listed"
  check "$(rows '?workspace' | grep -c '"kind": "key"' | grep -qx 4 && echo 1 || echo 0)" "$DECOR ?workspace filters to the four workspace binds"
  K act launcher.keys >/dev/null
  sleep 0.8
  check "$(K raw '{"t":"sub","id":"s","doc":"runtime.ui"}' | head -1 | grep -q '"launcher":false' && echo 1 || echo 0)" "$DECOR launcher.keys again closed the cheat sheet"
  K act launcher.toggle >/dev/null
  sleep 1
  check "$(K raw '{"t":"sub","id":"s","doc":"runtime.ui"}' | head -1 | grep -q 'launcher_query' && echo 0 || echo 1)" "$DECOR a plain open carries no launcher_query"
  K act ui.close >/dev/null
  sleep 0.5
done
# burst <file prefix> <action> <crop>: the action, and one grim per MORPH_AT offset, each started on its own clock.
burst() {
  local gp=() t t0 ap
  t0=$(date +%s%N)
  K act "$2" >/dev/null &
  ap=$!
  for t in $AT; do
    ( now=$(date +%s%N); w=$(( t - (now - t0) / 1000000 )); [ "$w" -gt 0 ] && sleep "$(printf '%d.%03d' $((w / 1000)) $((w % 1000)))"
      grim -g "$3" "$1-$t.png" ) &
    gp+=("$!")
  done
  for p in "${gp[@]}"; do wait "$p" || fail "grim failed ($1)"; done
  wait "$ap" || fail "act $2 failed"
}
if [[ " $PHASES " == *" morph "* ]]; then
  for CASE in $MORPH_CASES; do
    IFS=: read -r LOOK PROFILE EDGE <<< "$CASE"
    echo "== morph: $LOOK $PROFILE $EDGE"
    start_all "$LOOK" "theme.motion.profile = \"$PROFILE\"" "bar.edge = \"$EDGE\""
    got=$(K sub theme --count 0 --json | jq -r '.data.tokens["motion.profile"]')
    check "$([ "$got" = "$PROFILE" ] && echo 1 || echo 0)" "$LOOK the motion profile in effect is $PROFILE ($got)"
    # The card under the bar's centre: 800 x 720 from the bar's edge of the 2560 x 1440 output.
    crop="880,0 800x720"
    [ "$EDGE" = bottom ] && crop="880,720 800x720"
    base=$MOUT/launcher-$LOOK-$PROFILE-$EDGE
    # One open and close first: the first open of a fresh shell also loads the app icons.
    K act launcher.toggle >/dev/null; sleep 1.5; K act ui.close >/dev/null; sleep 1.2
    burst "$base-open" launcher.toggle "$crop"
    sleep 1.5
    grim -g "$crop" "$base-rest.png"
    AT="40 120" burst "$base-close" ui.close "$crop"
    sleep 1
    check "$(K raw '{"t":"sub","id":"s","doc":"runtime.ui"}' | head -1 | grep -q '"launcher":false' && echo 1 || echo 0)" "$LOOK $PROFILE $EDGE: the launcher closed"
    echo "shots $base-*.png"
  done
fi
stop_keys
stop_shell
stop_daemon

if grep -Eq 'ReferenceError|TypeError|binding loop|is not a function|is not defined|is not a type' "$R/qs.log" 2>/dev/null; then
  echo "QML errors in qs.log: $(grep -E 'ReferenceError|TypeError|binding loop|is not a function|is not defined|is not a type' "$R/qs.log" | head -5)" >&2
  FAILS=$((FAILS + 1))
fi
if grep -Ei 'Launcher.qml|ClipRow.qml|KeyRow.qml' "$R/qs.log" 2>/dev/null | grep -Eiq 'warn|error'; then
  echo "QML warnings from the launcher: $(grep -Ei 'Launcher.qml|ClipRow.qml|KeyRow.qml' "$R/qs.log" | head -5)" >&2
  FAILS=$((FAILS + 1))
fi
if grep -q panicked "$R/kurashid.log" 2>/dev/null; then
  echo "kurashid panicked (see $R/kurashid.log)" >&2
  FAILS=$((FAILS + 1))
fi
echo "checks: $((CHECKS - FAILS < 0 ? 0 : CHECKS - FAILS)) of $CHECKS"
[ "$FAILS" -eq 0 ] || fail "$FAILS failure(s); logs in $R, screenshots in $OUT"
echo "ok: screenshots in $OUT"
