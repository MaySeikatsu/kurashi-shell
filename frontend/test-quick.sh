#!/usr/bin/env bash
# The bar's quick-settings button (K24), invisibly (headless sway sandbox), by virtual-pointer clicks:
#   - top bar, kurashi-mock: a click on the button makes runtime.ui.panel "quick", a second click closes
#     it; while open the button is drawn pressed (the primary fill), where the row puts it (before the tray);
#   - the REAL kurashid, the same on its top bar (its own theme) and then on the left bar (the vertical
#     layout: the button is in the bottom column, before the tray; the mock has no config to move the bar with);
#   - the frontend logs no QML error.
#   nix develop -c frontend/test-quick.sh [sandbox-name]
# Binaries: kurashid, kurashi and kurashi-mock from $KURASHI_BIN_DIR (default $CARGO_TARGET_DIR/debug or
# target/debug); they are copied first, since shared target dirs get overwritten. The screenshots in
# frontend/shots/quick/ are evidence to look at, not just the exit code. On a hybrid laptop export
# KURASHI_RENDER_NODE first.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
NAME=${1:-${KURASHI_SB_PREFIX:-}fe-quick}
BIN=${KURASHI_BIN_DIR:-${CARGO_TARGET_DIR:-$ROOT/target}/debug}
MOCK_BIN=${KURASHI_MOCK_BIN:-$BIN/kurashi-mock}
OUT=$ROOT/frontend/shots/quick
mkdir -p "$OUT"
fail() { echo "test-quick: $*" >&2; exit 1; }

eval "$("$ROOT/tools/bench/sandbox.sh" start "$NAME")"
. "$ROOT/frontend/test-lib.sh"
R=$XDG_RUNTIME_DIR
W=$R/work
mkdir -p "$W" "$R/kurashi"
cp "$BIN/kurashid" "$BIN/kurashi" "$W/"
cp "$MOCK_BIN" "$W/kurashi-mock"

pids=()
stop_phase() {  # kills only the processes this script started
  for p in "${pids[@]}"; do kill "$p" 2>/dev/null || true; done
  for p in "${pids[@]}"; do wait "$p" 2>/dev/null || true; done
  pids=()
  rm -f "$KURASHI_SOCKET"
}
cleanup() {
  stop_phase
  "$ROOT/tools/bench/sandbox.sh" stop "$NAME" >/dev/null || true
}
trap cleanup EXIT

rm -rf "$R/xdg"   # hermetic: the sandbox dir outlives a run, and a bar moved by one run would skew the next
export XDG_CONFIG_HOME=$R/xdg/config XDG_STATE_HOME=$R/xdg/state \
       XDG_DATA_HOME=$R/xdg/data XDG_CACHE_HOME=$R/xdg/cache KURASHI_DATA_DIR=$ROOT LC_ALL=C.UTF-8
mkdir -p "$XDG_CONFIG_HOME" "$XDG_STATE_HOME" "$XDG_DATA_HOME" "$XDG_CACHE_HOME"
# Pixel checks of the plain look (K53: a fresh install wears the style washi; this test reads layout and fills).
mkdir -p "$XDG_CONFIG_HOME/kurashi"
printf 'theme.style = "none"\n[theme.colors]\nscheme = "dark"\n' > "$XDG_CONFIG_HOME/kurashi/config.toml"
K() { timeout 10 "$W/kurashi" "$@"; }
# K71: the bar moves with its modules in one change (`layout.bar.move`), from the edge it stands on now.
bar_edge() {
  local e
  for e in top bottom left right; do
    if K --json get "edges.$e.bar" | grep -q '"value":true'; then
      [ "$e" = "$1" ] || K act layout.bar.move "{\"from\":\"$e\",\"to\":\"$1\"}" >/dev/null
      return
    fi
  done
  return 1
}

# The pressed button's fill in a P6 PPM crop: the primary button's colours (rest, hover, pressed; the pointer
# may still be over the button). The fill is a rounded square of the bar's thickness less 6 px; the glyph cuts
# its runs, not its span, so a column belongs to the fill when its colour spans nearly the whole square. The
# volume fill is 6 rows thick, its knob 12, a focused workspace mark 10 (24 on the vertical bar, outside the
# crop). Exit 0 when the check holds for <open|closed>.
cat > "$W/pill.py" <<'PY'
import json, sys

ppm, colours, mode = sys.argv[1], sys.argv[2], sys.argv[3]
ex, ey = int(sys.argv[4]), int(sys.argv[5])   # the centre the layout gives, in crop pixels
PH = int(sys.argv[6])                          # the drawn square's height
FILLS = [tuple(int(c.lstrip("#")[i:i + 2], 16) for i in (0, 2, 4)) for c in colours.split(",")]
MIN_SPAN = PH - 6                              # a column of the square spans nearly all of its rows
MIN_COLS = PH - 10                             # the rounded corners drop a column or two at each side

with open(ppm, "rb") as f:
    data = f.read()
fields, i = [], 0
while len(fields) < 4:
    while data[i:i + 1].isspace():
        i += 1
    j = i
    while not data[j:j + 1].isspace():
        j += 1
    fields.append(data[i:j])
    i = j
if fields[0] != b"P6" or fields[3] != b"255":
    sys.exit(f"not an 8-bit P6 image: {fields}")
w, h, raster = int(fields[1]), int(fields[2]), data[i + 1:]


def filled(x, y):
    o = (y * w + x) * 3
    return any(all(abs(raster[o + k] - f[k]) <= 10 for k in range(3)) for f in FILLS)


cols = []   # (x, top, bottom): the first and last filled row of each column that spans enough rows
for x in range(w):
    rows = [y for y in range(h) if filled(x, y)]
    if rows and rows[-1] - rows[0] + 1 >= MIN_SPAN:
        cols.append((x, rows[0], rows[-1]))

result = {"mode": mode, "fill_columns": len(cols)}
if cols:
    xs = [c[0] for c in cols]
    tops = sorted(c[1] for c in cols)
    bottoms = sorted(c[2] for c in cols)
    cx = (min(xs) + max(xs)) / 2
    cy = (tops[len(tops) // 2] + bottoms[len(bottoms) // 2]) / 2
    result.update(x0=min(xs), x1=max(xs), cx=cx, cy=cy)
if mode == "closed":
    ok = not cols
else:
    ok = len(cols) >= MIN_COLS and abs(cx - ex) <= 3 and abs(cy - ey) <= 3
result["ok"] = ok
print(json.dumps(result))
sys.exit(0 if ok else 1)
PY

wait_socket() {  # wait_socket <what>: the server answers on the socket
  for _ in $(seq 100); do [ -S "$KURASHI_SOCKET" ] && K ping >/dev/null 2>&1 && return 0; sleep 0.1; done
  fail "$1 did not come up (see $R/server.log)"
}
start_mock() {
  rm -f "$KURASHI_SOCKET"
  RUST_LOG=info "$W/kurashi-mock" --outputs HEADLESS-1 --fixed-time 14:07 --socket "$KURASHI_SOCKET" \
    >> "$R/server.log" 2>&1 &
  pids+=("$!")
  wait_socket mock
}
start_kurashid() {  # no system bus and no audio server: nothing of the host is reached
  rm -f "$KURASHI_SOCKET"
  env DBUS_SYSTEM_BUS_ADDRESS="unix:path=$R/no-system-bus" \
      PULSE_SERVER="unix:$R/no-pulse/native" PULSE_RUNTIME_PATH="$R/no-pulse" \
      "$W/kurashid" >> "$R/server.log" 2>&1 &
  pids+=("$!")
  wait_socket kurashid
}
start_frontend() {
  # Without KURASHI_SOCKET: the frontend must find the socket by the protocol default, as in a live session.
  QS_OFF=$(log_size "$R/qs.log"); QS_BARE=$(screen_hash)
  env -u KURASHI_SOCKET qs -p "$ROOT/frontend" >> "$R/qs.log" 2>&1 &
  pids+=("$!")
  for _ in $(seq 100); do grep -q 'hello.*frontend' "$R/server.log" && break; sleep 0.1; done
  grep -q 'hello.*frontend' "$R/server.log" || fail "frontend never said hello (see $R/qs.log)"
  # The bar's documents and the first frames (was a fixed 3 s: drawn and still, at most 3 s).
  wait_frontend "$R/qs.log" "$QS_OFF" 3 0.6 "$QS_BARE" || fail "the frontend did not load (see $R/qs.log)"
}

# Layout facts. The button sits in the row (or column) after the clock and before the tray, so its place
# follows from the bar thickness and the spacings: Theme.pad = space.md (row spacing and the right margin),
# Theme.gap = space.sm (column spacing). The tray count is the frontend's own filter: available, not Passive.
token() { K sub theme --count 0 --json | jq -r --arg k "$1" '.data.tokens[$k]'; }
num() { [[ "$1" =~ ^[0-9]+$ ]] || fail "not a number: '$1'"; echo "$1"; }
output_size() { swaymsg -t get_outputs -r | jq -r --arg k "$1" '.[] | select(.name == "HEADLESS-1") | .rect[$k]'; }
tray_items() {
  K sub svc.tray --count 0 --json \
    | jq -r 'if .data.available == true then [.data.items[] | select(.status != "Passive")] | length else 0 end'
}
panel() { K sub runtime.ui --count 0 --json | jq -r '.data.panel'; }
expect_panel() {  # expect_panel <panel|""> <what>: the daemon acts asynchronously, so poll (bounded)
  local got=""
  for _ in $(seq 25); do
    got=$(panel 2>/dev/null || true)
    if [ "$got" = "$1" ]; then echo "ok: $2 (panel \"$1\")"; return 0; fi
    sleep 0.2
  done
  fail "$2: expected panel \"$1\", got \"$got\""
}
click() {  # click <x> <y>: a left click of the virtual pointer, in layout coordinates
  timeout 30 python3 -I "$ROOT/tools/bench/wl_pointer.py" click "$1" "$2" left
}
grab() {  # grab <name> <x> <y> <w> <h>: a PNG to look at, and a PPM of the same region for the pixel check
  timeout 20 grim -g "$2,$3 ${4}x${5}" "$OUT/$1.png" || fail "grim failed on $1"
  timeout 20 grim -g "$2,$3 ${4}x${5}" -t ppm "$W/$1.ppm" || fail "grim failed on $1"
  [ -s "$OUT/$1.png" ] || fail "empty screenshot $1"
  echo "shot $1"
}
fills() {  # the primary button's colours (rest, hover, pressed): the daemon's tokens, else the frontend's fallbacks
  local kv k v out=""
  for kv in button.primary.bg:#c9404b button.primary.bg.hover:#b93b45 button.primary.bg.pressed:#ad3741; do
    k=${kv%%:*}
    v=$(token "$k")
    [ "$v" = null ] && v=${kv#*:}   # the fixture theme of kurashi-mock has no component tokens
    out+="${out:+,}$v"
  done
  echo "$out"
}
check_pill() {  # check_pill <name> <open|closed> <expect-x> <expect-y> (crop coordinates; PH: the square's height)
  local res
  res=$(timeout 20 python3 -I "$W/pill.py" "$W/$1.ppm" "$(fills)" "$2" "$3" "$4" "$PH") \
    || { echo "$res" >&2; fail "$1: the pressed fill is not where the layout puts the button"; }
  echo "$1: $res"
}

: > "$R/server.log"; : > "$R/qs.log"

# 1. Top bar on the mock: the tray has its two items at the row's end (the mock's svc.tray).
start_mock
start_frontend
BARH=$(num "$(token bar.height)")
PH=$(( BARH - 6 ))
PAD=$(num "$(token space.md)")
SCREEN_W=$(num "$(output_size width)")
N=$(num "$(tray_items)")
[ "$N" = 2 ] || fail "precondition: the mock's tray has 2 items (got $N)"
# Row, right to left: margin PAD, the right sidebar's button (BARH, I154), PAD, the N items (BARH each, PAD apart), PAD,
# the button (BARH wide).
X=$(( SCREEN_W - PAD * (N + 2) - BARH * (N + 1) - BARH / 2 ))
Y=$(( BARH / 2 ))
CROP_X=$(( SCREEN_W - 400 ))
expect_panel "" "closed at start"
click "$X" "$Y"
expect_panel quick "a click on the button opens the quick panel"
sleep 1
grab quick-open "$CROP_X" 0 400 "$BARH"
check_pill quick-open open "$(( X - CROP_X ))" "$(( BARH / 2 ))"
click "$X" "$Y"
expect_panel "" "a second click closes it"
sleep 1
grab quick-closed "$CROP_X" 0 400 "$BARH"
check_pill quick-closed closed 0 0
stop_phase

# 2. The REAL kurashid (its own theme: on this machine the bar is 32 px, and the sandbox has no tray host).
#    The top bar first, then the left bar: the column's bottom holds the tray items, the button above them.
: > "$R/server.log"
start_kurashid
start_frontend
# The accessible name comes from the daemon's i18n document (I18n.tr returns the bare key when it is missing).
[ "$(K sub i18n --count 0 --json | jq -r '.data.strings["frontend.quick.open"]')" = "Quick settings" ] \
  || fail "the daemon's i18n document lacks frontend.quick.open"
# K66 (row 104): the daemon's theme carries the quick tile's on-state tokens (kurashi-theme tokens.rs), as hex colours.
for k in quick.tile.on.bg quick.tile.on.badge quick.tile.on.fg; do
  v=$(token "$k")
  [[ "$v" =~ ^#[0-9a-f]{6}$ ]] || fail "the daemon's theme has no $k (got \"$v\")"
done
echo "ok: the daemon's theme carries quick.tile.on.{bg,badge,fg}"
BARH=$(num "$(token bar.height)")
PH=$(( BARH - 6 ))
PAD=$(num "$(token space.md)")
GAP=$(num "$(token space.sm)")
SCREEN_W=$(num "$(output_size width)")
SCREEN_H=$(num "$(output_size height)")
N=$(num "$(tray_items)")
X=$(( SCREEN_W - PAD * (N + 2) - BARH * (N + 1) - BARH / 2 ))
Y=$(( BARH / 2 ))
CROP_X=$(( SCREEN_W - 400 ))
expect_panel "" "closed at start (real top bar)"
click "$X" "$Y"
expect_panel quick "real top bar: a click on the button opens the quick panel"
sleep 1
grab quick-real-open "$CROP_X" 0 400 "$BARH"
check_pill quick-real-open open "$(( X - CROP_X ))" "$(( BARH / 2 ))"
click "$X" "$Y"
expect_panel "" "real top bar: a second click closes it"
sleep 1
grab quick-real-closed "$CROP_X" 0 400 "$BARH"
check_pill quick-real-closed closed 0 0

bar_edge left || fail "the bar did not move to the left"
sleep 3   # the bar re-lays out on the left edge
BARH=$(num "$(token bar.height)")
PH=$(( BARH - 6 ))
N=$(num "$(tray_items)")
# Column, bottom up: margin PAD, the N items (BARH each, GAP apart), GAP, the button (BARH tall).
X=$(( BARH / 2 ))
Y=$(( SCREEN_H - PAD - (BARH + PAD) - N * BARH - N * GAP - BARH / 2 ))   # under the column: the right sidebar's button (I154)
CROP_Y=$(( SCREEN_H - 300 ))
expect_panel "" "closed at start (left bar)"
click "$X" "$Y"
expect_panel quick "left bar: a click on the button opens the quick panel"
sleep 1
grab quick-left-open 0 "$CROP_Y" 200 300
check_pill quick-left-open open "$X" "$(( Y - CROP_Y ))"
click "$X" "$Y"
expect_panel "" "left bar: a second click closes it"
sleep 1
grab quick-left-closed 0 "$CROP_Y" 200 300
check_pill quick-left-closed closed 0 0
stop_phase

if grep -q "ERROR\|TypeError\|ReferenceError\|Unable to assign\|is not defined" "$R/qs.log"; then
  echo "qs.log has errors:" >&2
  grep "ERROR\|TypeError\|ReferenceError\|Unable to assign\|is not defined" "$R/qs.log" | head >&2
  exit 1
fi
echo "ok: quick button clicks (mock top bar; real kurashid top and left bars); screenshots in $OUT"
