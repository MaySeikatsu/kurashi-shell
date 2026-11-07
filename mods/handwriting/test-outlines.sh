#!/usr/bin/env bash
# No drawing takes the shell down (docs/ux/handwriting.md "Outlines"): against the REAL kurashid, a font of the worst a pen can do (back
# on itself, tight zigzags, round and round on one spot, along its own line, and a real digit that once crashed Qt) is made through the mod's actions and drawn by
# Qt as the shell draws text, in a process of its own. A crash there fails. A font from older outlines is made again at the daemon's start.
#   nix develop -c mods/handwriting/test-outlines.sh
#   OUTLINES_DATA=<dir with a font's .json>: that font instead of the scribbles.
set -uo pipefail
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
NAME=${KURASHI_SB_PREFIX:-}outlines
BIN=${KURASHI_BIN_DIR:-${CARGO_TARGET_DIR:-$ROOT/target}/debug}
fail() { echo "test-outlines: FAIL: $*" >&2; exit 1; }
eval "$("$ROOT/tools/bench/sandbox.sh" start "$NAME")"
R=$XDG_RUNTIME_DIR; W=$R/work; mkdir -p "$W" "$R/kurashi"
cp "$BIN/kurashid" "$BIN/kurashi" "$W/"
pids=()
cleanup() {
  for p in "${pids[@]}"; do kill "$p" 2>/dev/null || true; done
  for p in "${pids[@]}"; do wait "$p" 2>/dev/null || true; done
  "$ROOT/tools/bench/sandbox.sh" stop "$NAME" > /dev/null || true
}
trap cleanup EXIT
rm -rf "$R/xdg"
export XDG_CONFIG_HOME=$R/xdg/config XDG_STATE_HOME=$R/xdg/state XDG_DATA_HOME=$R/xdg/data XDG_CACHE_HOME=$R/xdg/cache KURASHI_DATA_DIR=$ROOT LC_ALL=C.UTF-8
mkdir -p "$XDG_CONFIG_HOME/kurashi" "$XDG_STATE_HOME" "$XDG_DATA_HOME/kurashi/handwriting" "$XDG_DATA_HOME/fonts" "$XDG_CACHE_HOME"
printf '[idle]\nenabled = false\n\n[mods]\nenabled = ["handwriting"]\n' > "$XDG_CONFIG_HOME/kurashi/config.toml"
if [ -n "${OUTLINES_DATA:-}" ]; then cp "$OUTLINES_DATA"/*.json "$XDG_DATA_HOME/kurashi/handwriting/"; fi
# A font from before simple outlines: its file on disk, no mark in its drawing.
if [ -z "${OUTLINES_DATA:-}" ]; then
  printf '{"name":"Old","pen":56.0,"versions":1,"glyphs":{"1:A":[[[0,0],[100,700],[200,0]]]}}' > "$XDG_DATA_HOME/kurashi/handwriting/old.json"
  printf 'an old font' > "$XDG_DATA_HOME/fonts/kurashi-hand-old-1.ttf"
fi
K() { timeout 15 "$W/kurashi" "$@"; }
: > "$R/server.log"
env DBUS_SYSTEM_BUS_ADDRESS="unix:path=$R/no-system-bus" PULSE_SERVER="unix:$R/no-pulse/native" PULSE_RUNTIME_PATH="$R/no-pulse" \
  "$W/kurashid" >> "$R/server.log" 2>&1 &
pids+=("$!")
for _ in $(seq 100); do [ -S "$KURASHI_SOCKET" ] && K ping > /dev/null 2>&1 && break; sleep 0.1; done
K ping > /dev/null 2>&1 || fail "kurashid did not come up"
"$W/kurashi" sub mod.handwriting > /dev/null 2>&1 &
pids+=("$!")
sleep 1

# draw <font file> <chars>: 0 when Qt draws them all and stands.
draw() {
  : > "$R/qs.log"
  GLYPHS_FONT=$1 GLYPHS_CHARS=$2 timeout 8 qs -p "$ROOT/mods/handwriting/test/glyphs" > "$R/qs.log" 2>&1 &
  local p=$!
  for _ in $(seq 12); do sleep 0.4; kill -0 "$p" 2>/dev/null || break; done
  kill "$p" 2>/dev/null; wait "$p" 2>/dev/null
  ! grep -q "has crashed" "$R/qs.log"
}

if [ -n "${OUTLINES_DATA:-}" ]; then
  id=$(basename "$(ls "$OUTLINES_DATA"/*.json | head -1)" .json)
  K act handwriting.font.make "{\"id\":\"$id\"}" > /dev/null || fail "make"
else
  old_font() { [ "$(head -c 11 "$XDG_DATA_HOME/fonts/kurashi-hand-old-1.ttf" | tr -d '\0')" = "an old font" ]; }
  for _ in $(seq 50); do old_font || break; sleep 0.2; done
  if [ -z "${OUTLINES_NO_REFRESH:-}" ]; then
    old_font && fail "the font from older outlines was not made again"
    echo "test-outlines: a font from older outlines made again at the start"
  fi
  id=scribbles
  K act handwriting.font.create '{"name":"scribbles"}' > /dev/null || fail "create"
  python3 -I - "$ROOT/mods/handwriting/test/crash-three.json" > "$R/saves.json" <<'PY'
import json, math, random, sys
random.seed(7)
def hairpin():
    x, y = random.uniform(50, 400), random.uniform(50, 500)
    return [[x, y], [x + 200, y], [x + 204, y + 1], [x, y + 2], [x + 200, y + 4], [x + 3, y + 1]]
def zigzag():
    n = random.randint(8, 40)
    return [[100 + i * random.uniform(1, 6), 100 + (i % 2) * random.uniform(50, 500)] for i in range(n)]
def spiral():
    r0 = random.uniform(5, 60)
    return [[300 + (r0 + i * .4) * math.cos(i * .4), 300 + (r0 + i * .4) * math.sin(i * .4)] for i in range(random.randint(30, 150))]
def again():
    x, y = random.uniform(50, 500), random.uniform(50, 500)
    return [[x + (i % 2) * random.uniform(1, 30), y + (i % 3)] for i in range(random.randint(6, 40))]
def tail():
    x, y = random.uniform(100, 400), random.uniform(80, 500)
    p = [[x - i * 12, y + i * 2 + random.uniform(-1, 1)] for i in range(12)]
    return p + [[p[-1][0] + 4, p[-1][1]], [p[-1][0] + 60, p[-1][1] - 7]]
def noise():
    return [[random.uniform(0, 700), random.uniform(-200, 800)] for _ in range(random.randint(3, 60))]
kinds = [hairpin, zigzag, spiral, again, tail, noise]
chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789"
for c in chars:
    if c == "3":
        continue
    print(json.dumps({"id": "scribbles", "version": 1, "char": c, "strokes": [random.choice(kinds)() for _ in range(random.randint(1, 5))]}))
print(json.dumps({"id": "scribbles", "version": 1, "char": "3", "strokes": json.load(open(sys.argv[1]))["strokes"]}))
PY
  while IFS= read -r args; do K act handwriting.glyph.save "$args" > /dev/null || fail "save: ${args:0:60}"; done < "$R/saves.json"
  K act handwriting.font.make '{"id":"scribbles"}' > /dev/null || fail "make"
fi
FILE=$XDG_DATA_HOME/fonts/kurashi-hand-$id-1.ttf
[ -s "$FILE" ] || fail "no font file $FILE"
ALL='ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789.,:;!?()&/+=@#%*-'
draw "$FILE" "$ALL" || { tail -3 "$R/qs.log" | cut -c1-150 >&2; fail "Qt crashed drawing the font"; }
grep -q "Configuration Loaded" "$R/qs.log" || fail "the drawing never ran: $(tail -2 "$R/qs.log" | cut -c1-150)"
echo "test-outlines: every letter drawn, Qt stands"
echo "test-outlines: ok"
