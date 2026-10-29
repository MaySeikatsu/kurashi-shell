#!/usr/bin/env bash
# Every style × the shell's surfaces on nested niri, the lead platform (W53.0a, K80; docs/ux/styles.md "Tests"): the bar,
# the island's card, the launcher, a sidebar, a toast, quick settings and the lock, shot into
# frontend/shots/styles/<style>/ with motion off (a11y.reduce_motion), for the lead's sheet review against the brief.
# Checks, besides the shots:
#   - no QML error while any style is shown;
#   - the bevel probe: a user look naming `chrome = "bevel"` (written into the sandbox: no renderer knows its name, rule 4)
#     draws its four lines in the theme's exact colours on the bar's first group, one device pixel each;
#   - STYLES_REF=<dir>: the shots of STYLES_IDENTICAL (default "kanso washi") equal <dir>/<style>/<surface>.png within
#     tools/bench/block-identity.sh's noise rule (faint px pass; strong ones only in clock-sized clusters — the minute).
#   nix develop -c frontend/test-styles.sh [style …]          (default: every bundled style)
# STYLES_ROOT=<tree>: another checkout's frontend and sandbox script with these binaries (`git archive main | tar -x`: a
# reference set); STYLES_OUT=<dir>: the shots go there. STYLES_SANDBOX names the sandbox (default styles),
# STYLES_WALLPAPER a picture behind the shell (blur shows only over one). Binaries: $KURASHI_BIN_DIR, else
# $CARGO_TARGET_DIR/debug, else target/debug.
set -uo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
TREE=${STYLES_ROOT:-$ROOT}
OUT=${STYLES_OUT:-$ROOT/frontend/shots/styles}
export KURASHI_BIN_DIR=${KURASHI_BIN_DIR:-${CARGO_TARGET_DIR:-$ROOT/target}/debug}
export KURASHI_NIRI_SB_NAME=${STYLES_SANDBOX:-styles}
export KURASHI_NIRI_SB_OUT=/tmp/kurashi-niri-sb-out-$KURASHI_NIRI_SB_NAME
R=/tmp/kurashi-sb-$KURASHI_NIRI_SB_NAME
SB=$TREE/tools/bench/niri-sandbox.sh
STYLES=("$@")
[ ${#STYLES[@]} -gt 0 ] || mapfile -t STYLES < <(ls "$ROOT"/styles/*.toml | xargs -n1 basename | sed 's/\.toml$//')
IDENTICAL=${STYLES_IDENTICAL:-kanso washi}
fail() { echo "test-styles: FAIL: $*" >&2; exit 1; }
say() { echo "test-styles: $*"; }
K() { "$SB" act "$@" >/dev/null 2>&1; }
cleanup() { "$SB" stop >/dev/null 2>&1 || true; }
trap cleanup EXIT

CONF=$(mktemp -d)/config.toml
printf '%s\n' 'theme.style = "kanso"' '[a11y]' 'reduce_motion = true' '[idle]' 'enabled = false' > "$CONF"
"$SB" start "$CONF" ${STYLES_WALLPAPER:-} >/dev/null || fail "the niri sandbox did not start"
for _ in $(seq 50); do K ping && break; sleep 0.2; done
K ping || fail "kurashid did not answer (see $R/kurashid.log)"
for _ in $(seq 100); do grep -q 'hello.*frontend' "$R/kurashid.log" 2>/dev/null && break; sleep 0.1; done

# Waits until the daemon has the style in effect, then a little for the frontend to paint it (motion is off).
apply() {
  K reset theme
  K set "theme.style=$1"
  for _ in $(seq 50); do "$SB" act get theme.style 2>/dev/null | grep -q "\"$1\"" && break; sleep 0.1; done
  sleep 1.2
}
shot() {   # shot <name> [region at scale 1] — without a region the whole screen at 0.5
  if [ -n "${2:-}" ]; then "$SB" shot "$1" "$2" 1 >/dev/null; else "$SB" shot "$1" >/dev/null; fi &&
    mv "$KURASHI_NIRI_SB_OUT/shots/$1.png" "$OUT/$STYLE/$1.png"
}
open_shot() {   # open_shot <name> <region> <action> [args]
  "$SB" act act "$3" ${4:+"$4"} >/dev/null 2>&1 || say "$STYLE: $3 refused"
  sleep 1.2; shot "$1" "$2"
  "$SB" act act ui.close >/dev/null 2>&1 || true; sleep 0.6
}

errs=""
for STYLE in "${STYLES[@]}"; do
  mkdir -p "$OUT/$STYLE"
  apply "$STYLE"
  shot bar "0,0 1920x64"
  open_shot card "440,0 1040x620" island.expand
  open_shot launcher "440,0 1040x520" launcher.toggle
  open_shot sidebar "1380,0 540x1080" sidebar.toggle '{"side":"right"}'
  open_shot quick "1380,0 540x700" quick.toggle
  "$SB" spawn notify-send -t 4000 "Standup" "14:00 room 3"
  sleep 1.2; shot toast
  sleep 3.5
  e=$(grep -E 'ReferenceError|TypeError|is not a type|Cannot assign|unavailable|not found' "$R/qs.log" 2>/dev/null | sort -u)
  [ -z "$e" ] || errs+="$STYLE: $e"$'\n'
  say "$STYLE: 6 surfaces"
done

# The bevel probe: a look of the user's (unknown to every renderer) names the bevel chrome; the bar's first group must
# show the theme's four lines (`bevel.light`, `light2` at its left edge, `dark2`, `dark` at its bottom), in the exact
# token colours, one device px each. (A look's recipe applies when the look in effect changes: kanso first.)
mkdir -p "$R/xdg/config/kurashi/looks"
printf '%s\n' 'name = "probe-bevel"' 'category = "custom"' '[recipe]' '"theme.chrome" = "bevel"' \
  '"theme.shape.corners" = "none"' '"theme.material.kind" = "solid"' > "$R/xdg/config/kurashi/looks/probe-bevel.toml"
K reset theme
K set theme.style=win95
K set theme.look=kanso
K set theme.look=probe-bevel
sleep 1.5
want=$("$SB" act get theme.chrome 2>/dev/null)
echo "$want" | grep -q '"bevel"' || errs+="probe: theme.chrome is not bevel ($want)"$'\n'
"$SB" shot probe "0,0 200x30" 1 >/dev/null
"$SB" act --json sub theme --count 0 > "$R/theme.json" 2>/dev/null
python3 -I - "$KURASHI_NIRI_SB_OUT/shots/probe.png" "$R/theme.json" <<'PY' || errs+="probe: the bevel's lines are not the theme's"$'\n'
import json, subprocess, sys
w, h = map(int, subprocess.run(["magick", "identify", "-format", "%w %h", sys.argv[1]], capture_output=True,
                                text=True, check=True).stdout.split())
raw = subprocess.run(["magick", sys.argv[1], "-depth", "8", "rgb:-"], capture_output=True, check=True).stdout
px = lambda x, y: "#%02x%02x%02x" % tuple(raw[3 * (y * w + x):3 * (y * w + x) + 3])
doc = json.loads(open(sys.argv[2]).readline())
doc = doc.get("data", doc.get("value", doc))
tok = doc["tokens"]
want = [tok["bevel." + n].lower() for n in ("light", "light2", "dark2", "dark")]
# The middle row from the left: the bar's ground, then the outer and the inner light line; down the group's face from
# there: the inner and the outer dark line.
y = h // 2
ground = px(0, y)
xs = [x for x in range(w) if px(x, y) != ground][:2]
assert len(xs) == 2 and xs[1] == xs[0] + 1, ("no 1 px pair at the group's left edge", xs)
face = px(xs[0] + 6, y)
down = [yy for yy in range(y, h) if px(xs[0] + 6, yy) != face][:2]
assert len(down) == 2 and down[1] == down[0] + 1, ("no 1 px pair at the group's bottom", down)
got = [px(xs[0], y), px(xs[1], y), px(xs[0] + 6, down[0]), px(xs[0] + 6, down[1])]
assert got == want, ("bevel lines", got, "tokens", want)
print("test-styles: bevel probe ok:", got)
PY

# The lock last, every style in one locked session (the real daemon locks in the sandbox; unlocking needs a password).
K act session.lock
sleep 1.5
for STYLE in "${STYLES[@]}"; do
  apply "$STYLE"
  shot lock
done
say "lock: ${#STYLES[@]} styles"

if [ -n "${STYLES_REF:-}" ]; then
  for STYLE in $IDENTICAL; do
    for f in "$OUT/$STYLE"/*.png; do
      s=$(basename "$f")
      [ -f "$STYLES_REF/$STYLE/$s" ] || { say "no reference for $STYLE/$s"; continue; }
      python3 -I - "$STYLES_REF/$STYLE/$s" "$f" "$STYLE/$s" <<'PY' || errs+="identity: $STYLE/$s"$'\n'
import subprocess, sys
def load(p):
    w, h = map(int, subprocess.run(["magick", "identify", "-format", "%w %h", p], capture_output=True, text=True,
                                    check=True).stdout.split())
    return w, h, subprocess.run(["magick", p, "-depth", "8", "rgb:-"], capture_output=True, check=True).stdout
wa, ha, a = load(sys.argv[1]); wb, hb, b = load(sys.argv[2])
if (wa, ha) != (wb, hb):
    print("FAIL " + sys.argv[3] + ": sizes differ"); sys.exit(1)
w = wa
diff = [i // 3 for i in range(0, len(a), 3) if a[i:i+3] != b[i:i+3]]
strong = [i for i in diff if max(abs(a[3*i+c] - b[3*i+c]) for c in range(3)) > 64]
pts = sorted((i % w, i // w) for i in strong)
boxes, cur = [], []
for p in pts:
    if cur and p[0] - cur[-1][0] > 100:
        boxes.append(cur); cur = []
    cur.append(p)
if cur: boxes.append(cur)
sizes = [(max(x for x, _ in b) - min(x for x, _ in b) + 1, max(y for _, y in b) - min(y for _, y in b) + 1) for b in boxes]
ok = all(bw <= 80 and bh <= 30 for bw, bh in sizes)
print(("ok   " if ok else "FAIL ") + "%s: %d px differ, %d strongly %s" % (sys.argv[3], len(diff), len(strong), sizes))
sys.exit(0 if ok else 1)
PY
    done
  done
fi

[ -z "$errs" ] || { printf '%s' "$errs" >&2; fail "see above (shots in $OUT, logs in $R)"; }
say "ok: ${#STYLES[@]} styles × 7 surfaces in $OUT"
