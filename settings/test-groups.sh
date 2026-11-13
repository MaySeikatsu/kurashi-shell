#!/usr/bin/env bash
# Groups round two on nested niri (W80, I502, I508; docs/ux/groups.md "Round two"): the shell's side of the Settings list.
# `SETTINGS_PART=groups-niri settings/test.sh` runs this, or `nix develop -c settings/test-groups.sh`. Binaries from
# KURASHI_BIN_DIR, else $CARGO_TARGET_DIR/debug.
#   N1 a group written as Settings writes it (one apply: the record and the zone list) is drawn by the bar: the layout
#      document's zone names the group and its members are consecutive;
#   N2 the clock's module menu, by keyboard: "Group with…" → Volume groups the two (one apply);
#      undo puts it back (one step); N3 "Leave group" takes it out again (a group of one stays), undo returns it;
#   shots light and dark of the bar with the group and of the menu.
# Shots: $GROUPS_OUT/shots (default /tmp/kurashi-settings-groups/shots).
set -uo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
if ! command -v qs >/dev/null || ! command -v niri >/dev/null || ! command -v sway >/dev/null; then
  exec nix develop "$ROOT" -c "$0" "$@"
fi
BIN=${KURASHI_BIN_DIR:-${CARGO_TARGET_DIR:-$ROOT/target}/debug}
for b in kurashid kurashi; do [ -x "$BIN/$b" ] || { echo "test-groups: no $b in $BIN" >&2; exit 1; }; done
export KURASHI_BIN_DIR=$BIN
export KURASHI_NIRI_SB_NAME=${KURASHI_SB_PREFIX:-}settings-groups
export KURASHI_NIRI_SB_OUT=${GROUPS_OUT:-/tmp/kurashi-settings-groups}
OUT=$KURASHI_NIRI_SB_OUT
SB="$ROOT/tools/bench/niri-sandbox.sh"
. "$ROOT/frontend/test-lib.sh"
FAILS=0
ok() { echo "test-groups: ok: $*"; }
fail() { echo "test-groups: FAIL: $*" >&2; FAILS=$((FAILS + 1)); }
die() { echo "test-groups: FAIL: $*" >&2; exit 1; }
cleanup() { "$SB" stop >/dev/null 2>&1 || true; }
trap cleanup EXIT
rm -rf "$OUT"; mkdir -p "$OUT/shots"

cat > "$OUT/config.toml" <<'TOML'
[idle]
enabled = false
[theme.colors]
scheme = "light"
[theme.motion]
profile = "none"
[edges.top]
start = ["workspaces"]
center = ["island"]
end = ["volume", "clock"]
TOML
"$SB" start "$OUT/config.toml" >/dev/null || die "the niri sandbox did not start"
NENV=$OUT/niri-env.sh
K() { ( . "$NENV"; timeout 10 "$BIN/kurashi" "$@" ); }
keys() { ( . "$OUT/sway-env.sh"; python3 -I "$ROOT/tools/bench/wl_keys.py" "$@" ); }
doc() { K sub "$1" --count 0 2>/dev/null | head -1; }
ui_is() { doc runtime.ui | grep -q "$1"; }
val() { K raw "{\"t\":\"cfg.get\",\"id\":\"v\",\"key\":\"$1\"}" | python3 -I -c 'import json,sys; m=json.loads(sys.stdin.readline()); print(json.dumps(m["v"]["value"], separators=(",", ":")))'; }
val_is() { [ "$(val "$1")" = "$2" ]; }
# The top edge's end zone as the layout document has it: the ids in order, a group's members marked `<id>@<group>`.
zone_end() { doc runtime.layout | python3 -I -c '
import json, sys
d = json.loads(sys.stdin.readline()); d = d.get("data") or d.get("v") or d
outs = d.get("outputs", {})
o = next(iter(v for k, v in outs.items() if k != "*"), outs.get("*", {}))
for e in o.get("edges", []) if isinstance(o.get("edges"), list) else [dict(o.get("edges", {}).get("top", {}), edge="top")]:
    if e.get("edge", "top") != "top": continue
    z = e.get("zones", {}).get("end", e.get("end", []))
    print(",".join(m.get("id", "?") + ("@" + m["group"] if m.get("group") else "") for m in z))
' 2>/dev/null; }

wait_until 20 K ping || die "the daemon did not answer"
wait_for "$(. "$NENV"; echo "$XDG_RUNTIME_DIR")/qs.log" 'Configuration Loaded' 20 || die "the shell did not load"
sleep 1

# N1: the bar draws a group Settings wrote.
K raw '{"t":"apply","id":"n1","ops":[{"set":"layout.groups","value":[{"id":"g1","name":"time","members":"volume,clock","accordion":false}]},{"set":"edges.top.end","value":["group:g1"]}]}' \
  | grep -q applied || fail "N1: the group was refused"
if wait_until 5 sh -c "true" && z=$(zone_end) && [ "$z" = "volume@g1,clock@g1" ]; then ok "N1: the bar's end zone draws the group ($z)"
else fail "N1: the layout's end zone is '$(zone_end)', not volume@g1,clock@g1 (raw: $(doc runtime.layout | head -c 600))"; fi
sleep 0.5; "$SB" shot bar-group-light "1400,0 520x60" 1 >/dev/null
K raw '{"t":"apply","id":"n1d","ops":[{"set":"theme.colors.scheme","value":"dark"}]}' >/dev/null
sleep 1; "$SB" shot bar-group-dark "1400,0 520x60" 1 >/dev/null
K raw '{"t":"apply","id":"n1l","ops":[{"set":"theme.colors.scheme","value":"light"}]}' >/dev/null
# Back to two plain modules.
K raw '{"t":"apply","id":"n1r","ops":[{"set":"layout.groups","value":[]},{"set":"edges.top.end","value":["volume","clock"]}]}' \
  | grep -q applied || fail "N1: the reset was refused"

# N2: the clock's menu, by keyboard: Up (Settings), Up (Group with…), Right (open), Down (Volume), Return.
K act tray.menu.open '{"id":"module:clock"}' >/dev/null
wait_until 5 ui_is '"tray":"module:clock"' || fail "N2: the clock's menu did not open: $(doc runtime.ui)"
sleep 0.6
"$SB" click 1585 63 >/dev/null   # the card takes the keyboard on demand: a click on its title first
sleep 0.3
keys up up right
sleep 0.5; "$SB" shot menu-group-with-light "1300,0 620x700" 1 >/dev/null
keys down return
if wait_until 5 val_is layout.groups '[{"accordion":false,"id":"g1","members":"volume,clock","name":""}]' \
   && val_is edges.top.end '["group:g1"]'; then ok "N2: Group with… → Volume grouped the clock with it"
else fail "N2: Group with… did not group (groups $(val layout.groups), end $(val edges.top.end))"; fi
# N3: the menu again: Up (Settings), Up (Leave group: Group with… has nothing left to offer), Return. A group of one stays.
keys escape
wait_until 5 ui_is '"tray":""' || fail "N3: Escape did not close the menu"
K act tray.menu.open '{"id":"module:clock"}' >/dev/null
wait_until 5 ui_is '"tray":"module:clock"' || fail "N3: the clock's menu did not open again"
sleep 0.6
"$SB" click 1585 63 >/dev/null
sleep 0.3
keys up up
sleep 0.5; "$SB" shot menu-leave-light "1300,0 620x700" 1 >/dev/null
keys return
if wait_until 5 val_is layout.groups '[{"accordion":false,"id":"g1","members":"volume","name":""}]' \
   && val_is edges.top.end '["group:g1","clock"]'; then ok "N3: Leave group took the clock out (the group of one stays)"
else fail "N3: Leave group did not (groups $(val layout.groups), end $(val edges.top.end))"; fi
K raw '{"t":"undo","id":"u0"}' >/dev/null
wait_until 5 val_is edges.top.end '["group:g1"]' || fail "N3: undo did not put the clock back in the group"
K raw '{"t":"apply","id":"n2d","ops":[{"set":"theme.colors.scheme","value":"dark"}]}' >/dev/null
sleep 1; "$SB" shot menu-dark "1300,0 620x700" 1 >/dev/null
K raw '{"t":"apply","id":"n2l","ops":[{"set":"theme.colors.scheme","value":"light"}]}' >/dev/null
K raw '{"t":"undo","id":"u1"}' >/dev/null; K raw '{"t":"undo","id":"u2"}' >/dev/null; K raw '{"t":"undo","id":"u3"}' >/dev/null
if wait_until 5 val_is edges.top.end '["volume","clock"]'; then ok "N2: undo took the group back"
else fail "N2: undo did not restore the zone ($(val edges.top.end), groups $(val layout.groups))"; fi
keys escape 2>/dev/null || true

echo "test-groups: shots in $OUT/shots"; ls "$OUT/shots"
[ "$FAILS" -eq 0 ] || { echo "test-groups: $FAILS failure(s)"; exit 1; }
echo "test-groups: ok"
