#!/usr/bin/env bash
# Pixel identity of two frontends (W39-block: a lighter Block must draw what the old one drew). Invisibly (headless sway
# sandbox), the real kurashid with an empty config; for each scenario both frontends are shot at rest — the bar, the
# island's card (the month grid: 42 Blocks), quick settings, the launcher and the session menu — plus a held key, then
# compared pixel by pixel. Scenarios: every chrome (flat kanso, keycap sekai, soft glass, line terminal), the frames
# (washi, kami, snes), a long sideways hard shadow, the material's relief under and over the content, the pen's outline
# and its text layer.
#   nix develop -c tools/bench/block-identity.sh <ref frontend dir> [new frontend dir (default: this checkout's)]
# e.g. `git archive HEAD frontend | tar -x -C /tmp/ref` for the ref. Pass the ref twice for the noise floor.
# Fails on any shot that differs strongly (a channel off by > 64) outside clock-sized clusters (the minute may turn
# between the runs); faint scattered differences (text and blur rasterisation) are reported, not failed.
# IDENTITY_SCENARIOS limits the scenarios (names below); IDENTITY_OUT keeps the shots (default: the sandbox, removed).
# Binaries from $KURASHI_BIN_DIR, else $CARGO_TARGET_DIR/release.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
REF=${1:?usage: block-identity.sh <ref frontend dir> [new frontend dir]}
NEW=${2:-$ROOT/frontend}
NAME=${IDENTITY_SANDBOX:-w39-block-id}
BIN=${KURASHI_BIN_DIR:-${CARGO_TARGET_DIR:-$ROOT/target}/release}
fail() { echo "block-identity: FAIL: $*" >&2; exit 1; }
say() { echo "block-identity: $*"; }

# name|kurashi set arguments (after `reset theme`)
SCENARIOS=(
  "kanso|theme.style=kanso"
  "sekai|theme.style=sekai"
  "glass|theme.style=glass"
  "terminal|theme.style=terminal"
  "washi|theme.style=washi"
  "kami|theme.style=kami"
  "snes|theme.style=snes"
  "sekai-a135-s2|theme.style=sekai theme.material.shadow=2 theme.material.shadow_angle=135"
  "sekai-paper|theme.style=sekai theme.texture.kind=paper"
  "glass-paper-text|theme.style=glass theme.texture.kind=paper theme.texture.text=true"
  "terminal-pen|theme.style=terminal theme.pen.line=rough theme.pen.pressure=0.6 theme.pen.text_pressure=0.6"
)
WANT=${IDENTITY_SCENARIOS:-}

eval "$("$ROOT/tools/bench/sandbox.sh" start "$NAME")"
R=$XDG_RUNTIME_DIR
W=$R/work
OUT=${IDENTITY_OUT:-$W/shots}
mkdir -p "$W" "$OUT" "$R/kurashi"
cp "$BIN/kurashid" "$BIN/kurashi" "$W/"
pids=()
QS_PID=
cleanup() {
  for p in "${pids[@]}"; do kill "$p" 2>/dev/null || true; done
  for p in "${pids[@]}"; do wait "$p" 2>/dev/null || true; done
  "$ROOT/tools/bench/sandbox.sh" stop "$NAME" >/dev/null || true
}
trap cleanup EXIT

export XDG_CONFIG_HOME=$R/xdg/config XDG_STATE_HOME=$R/xdg/state \
       XDG_DATA_HOME=$R/xdg/data XDG_CACHE_HOME=$R/xdg/cache KURASHI_DATA_DIR=$ROOT LC_ALL=C.UTF-8
rm -rf "$R/xdg"; mkdir -p "$XDG_CONFIG_HOME/kurashi" "$XDG_STATE_HOME" "$XDG_DATA_HOME" "$XDG_CACHE_HOME"
: > "$XDG_CONFIG_HOME/kurashi/config.toml"
K() { timeout 10 "$W/kurashi" "$@"; }
: > "$R/server.log"
env DBUS_SYSTEM_BUS_ADDRESS="unix:path=$R/no-system-bus" PULSE_SERVER="unix:$R/no-pulse/native" \
    PULSE_RUNTIME_PATH="$R/no-pulse" "$W/kurashid" >> "$R/server.log" 2>&1 &
pids+=("$!")
for _ in $(seq 100); do [ -S "$KURASHI_SOCKET" ] && K ping >/dev/null 2>&1 && break; sleep 0.1; done
K ping >/dev/null 2>&1 || fail "kurashid did not come up (see $R/server.log)"
swaymsg output '*' bg '#8fb8c8' solid_color >/dev/null 2>&1 || true

# A key held down (tools/bench/wl_pointer.py's protocol: its press without the release).
cat > "$W/hold.py" <<'PY'
import importlib.util, struct, sys, time
spec = importlib.util.spec_from_file_location("wl_pointer", sys.argv[1])
wp = importlib.util.module_from_spec(spec); spec.loader.exec_module(wp)
x, y, secs = int(sys.argv[2]), int(sys.argv[3]), float(sys.argv[4])
p = wp.Pointer()
p.motion(x, y); p.roundtrip(); time.sleep(0.3)
p.send(p.pointer, 2, struct.pack("<III", wp.ms(), wp.BUTTONS["left"], 1)); p.send(p.pointer, 4); p.roundtrip()
time.sleep(secs)
p.send(p.pointer, 2, struct.pack("<III", wp.ms(), wp.BUTTONS["left"], 0)); p.send(p.pointer, 4); p.settle()
PY

start_frontend() {  # start_frontend <frontend dir>
  if [ -n "$QS_PID" ]; then kill "$QS_PID" 2>/dev/null || true; wait "$QS_PID" 2>/dev/null || true; fi
  local n0; n0=$(grep -c 'hello.*frontend' "$R/server.log" || true)
  env -u KURASHI_SOCKET qs -p "$1" >> "$R/qs.log" 2>&1 &
  QS_PID=$!; pids+=("$QS_PID")
  for _ in $(seq 100); do [ "$(grep -c 'hello.*frontend' "$R/server.log" || true)" -gt "$n0" ] && break; sleep 0.1; done
  [ "$(grep -c 'hello.*frontend' "$R/server.log" || true)" -gt "$n0" ] || fail "frontend $1 never said hello (see $R/qs.log)"
  sleep 3
}
open_shot() {  # open_shot <action> <geometry> <file> [settle]
  K act "$1" >/dev/null || fail "act $1"
  sleep "${4:-1.8}"
  grim -g "$2" "$3"
  K act ui.close >/dev/null 2>&1 || true
  sleep 1.2
}
shots() {  # shots <frontend dir> <tag>
  start_frontend "$1"
  for sc in "${SCENARIOS[@]}"; do
    local n=${sc%%|*} args=${sc#*|}
    [ -z "$WANT" ] || [[ " $WANT " == *" $n "* ]] || continue
    K reset theme >/dev/null 2>&1 || true
    # shellcheck disable=SC2086
    K set $args theme.motion.profile=calm >/dev/null || fail "kurashi set $args refused"
    sleep 2.5
    grim -g "0,0 2560x52" "$OUT/$2-$n-bar.png"
    open_shot island.expand "860,0 840x620" "$OUT/$2-$n-card.png"
    open_shot quick.toggle "1040,0 1520x900" "$OUT/$2-$n-quick.png"
    K act launcher.toggle >/dev/null || fail "act launcher.toggle"
    sleep 1.8; grim -g "560,0 1440x1000" "$OUT/$2-$n-launcher.png"
    K act launcher.toggle >/dev/null || true; sleep 1.2
    open_shot session.menu "780,200 1000x700" "$OUT/$2-$n-session.png"
    # The island card's Close key held down: the sink, the shrink or the flash at rest (its release closes the card).
    K act island.expand >/dev/null || fail "island.expand"
    sleep 1.8
    timeout 20 python3 -I "$W/hold.py" "$ROOT/tools/bench/wl_pointer.py" 1125 425 2.5 &
    local hp=$!
    sleep 1.8
    grim -g "860,300 840x320" "$OUT/$2-$n-held.png"
    wait "$hp" || fail "the held press failed"
    sleep 1.2
    K act ui.close >/dev/null 2>&1 || true
    sleep 1.2
  done
}

shots "$REF" ref
shots "$NEW" new

errs=$(grep -E "TypeError|ReferenceError|is not a type|Cannot assign|is not defined|Unable to assign|Cannot read property" "$R/qs.log" || true)

bad=0
for sc in "${SCENARIOS[@]}"; do
  n=${sc%%|*}
  [ -z "$WANT" ] || [[ " $WANT " == *" $n "* ]] || continue
  for part in bar card quick launcher session held; do
    python3 -I - "$OUT/ref-$n-$part.png" "$OUT/new-$n-$part.png" "$n $part" <<'PY' || bad=1
import subprocess, sys
def px(p):
    d = subprocess.run(["magick", p, "rgb:-"], capture_output=True, check=True).stdout
    w, h = map(int, subprocess.run(["magick", "identify", "-format", "%w %h", p], capture_output=True, check=True).stdout.split())
    return d, w, h
a, w, h = px(sys.argv[1]); b, _, _ = px(sys.argv[2])
diff = [i // 3 for i in range(0, len(a), 3) if a[i:i+3] != b[i:i+3]]
if not diff:
    print("ok   identical: " + sys.argv[3]); sys.exit(0)
# Faint scattered px are rasterisation noise; a moved or missing edge is strong (a channel off by > 64) along its length.
strong = [i for i in diff if max(abs(a[3*i+c] - b[3*i+c]) for c in range(3)) > 64]
# The clocks may turn their minute between the runs: strong px in clock-sized clusters (split at 100 px of empty x) pass.
pts = sorted((i % w, i // w) for i in strong)
boxes, cur = [], []
for p in pts:
    if cur and p[0] - cur[-1][0] > 100:
        boxes.append(cur); cur = []
    cur.append(p)
if cur: boxes.append(cur)
sizes = [(max(x for x, _ in b) - min(x for x, _ in b) + 1, max(y for _, y in b) - min(y for _, y in b) + 1,
          min(x for x, _ in b), min(y for _, y in b)) for b in boxes]
ok = all(bw <= 80 and bh <= 30 for bw, bh, _, _ in sizes)
print(("ok   " if ok else "FAIL ") + "%s: %d px differ, %d strongly %s" % (sys.argv[3], len(diff), len(strong),
      " ".join("%dx%d@%d,%d" % s for s in sizes)))
sys.exit(0 if ok else 1)
PY
  done
done
[ -z "$errs" ] || { echo "$errs" | sort | uniq -c | head -20; fail "QML errors (see $R/qs.log)"; }
[ "$bad" = 0 ] || fail "the frontends draw differently (shots in $OUT)"
say "identical within the noise rule: $REF vs $NEW"
