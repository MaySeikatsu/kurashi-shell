#!/usr/bin/env bash
# Recipes (W59.7, K83; docs/ux/motion-engine.md §5 "Recipes"): a user's motion pack with the brief's three recipes and a
# broken one, in the invisible headless sway sandbox (the visual review runs on niri, tools/bench/niri-sandbox.sh):
#   tokens  the daemon publishes `motion.recipe.<id>` for each (the broken one with its reasons and no tracks), lists the
#           valid ones in the forms meta (`recipe: true`, pop-tilt flagged vestibular) and offers them in `motion.forms`;
#           profile `mine` (the pack) resolves its forms to its recipes; reduce motion never names pop-tilt;
#   shell   the notification centre on ps2 (no join: its content moves through FormHost) opened under profile `mine`
#           (panel opens with pop-tilt): its FormHost logs `motion: recipe pop-tilt on panel` and a frame mid-way differs
#           from rest, no QML errors; at rest
#           the centre equals the motion-off frame (profile none) pixel for pixel; after the close 0 surface commits in 5 s.
# Scrubbed frames by progress are Settings' recipe preview's (its scrubber; the same forms/Recipe.qml) — the centre's
# fallback reveal is a NumberAnimation until W59.3 puts it on a Driver.
#   nix develop -c frontend/test-recipes.sh
# Binaries from $KURASHI_BIN_DIR (kurashid, kurashi), else $CARGO_TARGET_DIR/debug. Shots: frontend/shots/recipes/.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
NAME=${KURASHI_SB_PREFIX:-}w59-recipes
BIN=${KURASHI_BIN_DIR:-${CARGO_TARGET_DIR:-$ROOT/target}/debug}
OUT=${RECIPES_OUT:-$ROOT/frontend/shots/recipes}
mkdir -p "$OUT"
fail() { echo "test-recipes: $*" >&2; exit 1; }

eval "$("$ROOT/tools/bench/sandbox.sh" start "$NAME")"
. "$ROOT/frontend/test-lib.sh"
R=$XDG_RUNTIME_DIR
W=$R/work
mkdir -p "$W"
cp "$BIN/kurashid" "$BIN/kurashi" "$W/"
pids=()
QS_PID=
stop_fe() {
  [ -n "$QS_PID" ] || return 0
  kill "$QS_PID" 2>/dev/null || true; wait "$QS_PID" 2>/dev/null || true
  QS_PID=
}
cleanup() {
  stop_fe
  for p in "${pids[@]}"; do kill "$p" 2>/dev/null || true; done
  for p in "${pids[@]}"; do wait "$p" 2>/dev/null || true; done
  "$ROOT/tools/bench/sandbox.sh" stop "$NAME" >/dev/null || true
}
trap cleanup EXIT

export XDG_CONFIG_HOME=$R/xdg/config XDG_STATE_HOME=$R/xdg/state \
       XDG_DATA_HOME=$R/xdg/data XDG_CACHE_HOME=$R/xdg/cache KURASHI_DATA_DIR=$ROOT LC_ALL=C.UTF-8
K() { timeout 10 "$W/kurashi" "$@"; }
rm -rf "$R/xdg"; mkdir -p "$XDG_CONFIG_HOME/kurashi/motion" "$XDG_STATE_HOME" "$XDG_DATA_HOME" "$XDG_CACHE_HOME"
printf '[idle]\nenabled = false\n\n[theme]\nstyle = "ps2"\n' > "$XDG_CONFIG_HOME/kurashi/config.toml"
# The brief's pack, byte for byte (the crate's tests parse the same file), and a broken one.
cp "$ROOT/crates/kurashi-motion/tests/recipes-brief.toml" "$XDG_CONFIG_HOME/kurashi/motion/mine.toml"
printf '[recipes.wobbly]\n[[recipes.wobbly.track]]\nprop = "wobble"\nkeys = [[0, 1]]\n' \
  > "$XDG_CONFIG_HOME/kurashi/motion/broken.toml"
: > "$R/server.log"
env DBUS_SYSTEM_BUS_ADDRESS="unix:path=$R/no-system-bus" \
    PULSE_SERVER="unix:$R/no-pulse/native" PULSE_RUNTIME_PATH="$R/no-pulse" \
    "$W/kurashid" >> "$R/server.log" 2>&1 &
pids+=("$!")
wait_until 10 K ping || fail "kurashid did not come up (see $R/server.log)"
swaymsg output '*' bg '#8fb8c8' solid_color >/dev/null 2>&1 || true

# A document's data as JSON (the snapshot `kurashi sub` prints first).
doc() { K sub "$1" --count 0 | grep -m1 '^{' ; }
tokens_check() {
  python3 -I -c '
import json, sys
d = json.loads(sys.stdin.read())["data"]["tokens"]
want = sys.argv[1]
def ok(c, m):
    if not c: print("test-recipes: " + m, file=sys.stderr); sys.exit(1)
r = {k[14:]: v for k, v in d.items() if k.startswith("motion.recipe.")}
ok(sorted(r) == ["drop-squash", "pop-tilt", "slide-blur", "wobbly"], "recipe tokens: %s" % sorted(r))
ok(all(r[i]["ok"] for i in ["drop-squash", "pop-tilt", "slide-blur"]), "a brief recipe is skipped")
ok(r["wobbly"]["ok"] is False and r["wobbly"]["tracks"] == [] and r["wobbly"]["diags"][0]["key"] == "config.diag.recipe.prop",
   "the broken recipe: %s" % r["wobbly"])
ok(r["pop-tilt"]["path"].endswith("/kurashi/motion/mine.toml"), "pack path: %s" % r["pop-tilt"]["path"])
m = d["motion.forms"]
ok(all(m.get(i, {}).get("recipe") is True for i in ["drop-squash", "pop-tilt", "slide-blur"]), "forms meta lacks a recipe")
ok("wobbly" not in m, "a skipped recipe is in the forms meta")
ok(m["pop-tilt"]["flags"] == ["vestibular"] and m["drop-squash"]["flags"] == [], "vestibular flags")
if want == "mine":
    ok(d["motion.form.panel.open"] == "pop-tilt" and d["motion.form.toast.open"] == "drop-squash"
       and d["motion.form.sidebar.open"] == "slide-blur", "profile mine: its forms are its recipes")
elif want == "reduced":
    ok(all(v != "pop-tilt" for k, v in d.items() if k.startswith("motion.form.")), "reduce motion names pop-tilt")
print("test-recipes: tokens ok (" + want + ")")
' "$1"
}

echo "== tokens"
K set theme.motion.profile mine >/dev/null || fail "theme.motion.profile mine refused (is the user pack offered?)"
sleep 0.5
doc theme | tokens_check mine
K set a11y.reduce_motion true >/dev/null || fail "a11y.reduce_motion refused"
sleep 0.5
doc theme | tokens_check reduced
K set a11y.reduce_motion false >/dev/null
# The pickers' offers: the valid recipes, by their labels; not the broken one.
doc schema.settings > "$W/settings.json"
grep -q '"pop-tilt"' "$W/settings.json" && grep -q '"Pop and tilt"' "$W/settings.json" \
  || fail "motion.forms offers lack the recipes (see $W/settings.json)"
grep -q '"wobbly"' "$W/settings.json" && fail "a skipped recipe is offered" || true
K set theme.motion.form.toast.close slide-blur >/dev/null || fail "a recipe refused as a surface's form"
K reset theme.motion.form.toast.close >/dev/null
echo "test-recipes: offers ok"

echo "== shell"
said_hello() { [ "$(grep -c 'hello.*frontend' "$R/server.log" || true)" -gt "$1" ]; }
start_fe() {
  local log=$1; shift
  local hellos
  hellos=$(grep -c 'hello.*frontend' "$R/server.log" || true)
  : > "$log"
  env -u KURASHI_SOCKET "$@" qs -p "$ROOT/frontend" >> "$log" 2>&1 &
  QS_PID=$!
  wait_until 15 said_hello "$hellos" || fail "the frontend never said hello (see $log)"
  wait_frontend "$log" 0 15 0.6 || fail "the frontend did not load (see $log)"
}
qml_errors() {
  if grep -E 'qml:.*(Error|error)|TypeError|ReferenceError|is not a type|Binding loop|is not defined' "$1" \
      | grep -v 'Unable to assign \[undefined\]' >/dev/null; then
    grep -E 'Error|error|Binding loop|not defined' "$1" | head -20 >&2
    fail "QML errors (see $1)"
  fi
}
# The centre hangs from the bar's middle (ps2: a card apart from the bar).
CROP="980,40 600x260"
shot() { grim -g "$CROP" "$OUT/$1.png"; }
ae() { { magick compare -metric AE "$OUT/$1.png" "$OUT/$2.png" null: 2>&1 || true; } | awk '{print int($1)}'; }
commits() { tail -c +"$(( $1 + 1 ))" "$2" | grep -cE 'wl_surface#[0-9]+\.commit\(' || true; }

# Slowed down, so a frame mid-way is there to catch.
K set theme.motion.speed 0.25 >/dev/null
log=$R/qs-mine.log
start_fe "$log" WAYLAND_DEBUG=1
K act notifications.center >/dev/null
sleep 0.25
shot mine-mid
wait_settled 8 0.8 "$CROP"
shot mine-rest
grep -q "motion: recipe pop-tilt on panel" "$log" || fail "no FormHost took the recipe pop-tilt (see $log)"
d=$(ae mine-mid mine-rest)
[ "$d" -gt 0 ] || fail "the centre mid-way looks like the centre at rest: the recipe did not run"
echo "test-recipes: centre mid-way differs from rest in $d px"
K act notifications.center >/dev/null
sleep 3
sec() { date +%S | sed 's/^0//'; }
while [ "$(sec)" -gt 40 ] || [ "$(sec)" -lt 3 ]; do sleep 0.5; done
wait_log_quiet "$log" 'wl_surface#[0-9]+\.commit\(' 1 10
off=$(log_size "$log"); sleep 5
n=$(commits "$off" "$log")
[ "$n" = 0 ] || fail "$n surface commits in 5 s after the close (idle must be 0 frames)"
qml_errors "$log"
stop_fe

K set theme.motion.profile none >/dev/null
start_fe "$R/qs-off.log"
K act notifications.center >/dev/null
wait_settled 8 0.8 "$CROP"
shot off-rest
qml_errors "$R/qs-off.log"
K act notifications.center >/dev/null
stop_fe
d=$(ae mine-rest off-rest)
[ "$d" = 0 ] || fail "the centre at rest under the recipe differs from motion off in $d px"
echo "test-recipes: rest equals motion off; idle 0 commits in 5 s"
echo "test-recipes: ok (shots in $OUT)"
