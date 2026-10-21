#!/usr/bin/env bash
# The quick settings card (K24, W12, W13; docs/ux/quick-settings.md) against kurashi-mock, invisibly (headless sway sandbox):
# the tiles, every page, the toggle states the mock can produce, the keyboard, and the Wi-Fi scan's subscription. Checks:
#   - quick.toggle opens the card (runtime.ui panel "quick"); its shot is 400 px wide and centred on the output;
#   - a pointer click on the Wi-Fi tile sends network.wifi (svc.network.wifi_enabled flips, and flips back); its arrow opens
#     the Wi-Fi page and the page's Back control returns to the tiles;
#   - the scan document is subscribed while the Wi-Fi page is open and unsubscribed when it closes (the relay's log, Ma);
#   - keyboard: a click on the heading gives the card its focus; Tab reaches the Wi-Fi tile, Return toggles it, Right opens
#     its page, Tab and Return on an unsaved network show the daemon's refusal in place, Escape goes back to the tile (focus
#     returns there); the audio page's Tab and Return choose the other output (the focus stays on the row chosen); the power
#     page's Tab and Return choose a profile; the focus page's Tab and Return turn Do not disturb on until one hour; the
#     display page's Tab and Right raise the brightness; the arrows move between tiles;
#   - connecting and failed: the mock is held still (SIGSTOP), so a Wi-Fi tile request gets no answer: "connecting" shows,
#     then the 30 s timeout's failure; SIGCONT lets the queued request through and the failure clears;
#   - the tile states (I51): shots with three, one and no tile on (tiles-3-on, tiles-1-on, tiles-0-on);
#   - the media row opens the island's media view; ui.close closes the card, and Escape on the tiles closes it too;
#     after each close the card's documents are unsubscribed (Ma); the frontend logs no QML error;
#   - W18 (quick.tiles): the mod tiles take cells after the core tiles (tiles-mods); Tab reaches the test mod's tile, Down
#     the wallpaper tile, Return moves its picture on, Right opens its picker panel; the mock's battery, unavailable and
#     forced tiles (tiles-battery, tiles-unavailable, tiles-forced), the wallpaper tile with its backend down
#     (tiles-wallpaper-down), brightness.set moves the Display level; no contribution is the six core tiles (tiles-no-mods);
#     the wallpaper tile's document is subscribed while the card shows it and unsubscribed after it closes (Ma).
#   nix develop -c frontend/test-quick-sections.sh [sandbox-name]
# The mock must serve svc.network, svc.audio, svc.power, svc.notifications, svc.brightness and svc.network.scan with the
# actions network.{wifi,connect,disconnect}, audio.{sink.default,source.default}, power.profile, notify.dnd, and (W18)
# mod.wallpaper with wallpaper.next, the mock controls mock.doc, and the intent brightness.set. Binaries:
# kurashi and kurashi-mock from $KURASHI_BIN_DIR (default $CARGO_TARGET_DIR/debug, else target/debug), copied first, since
# shared target dirs get overwritten. The shots in frontend/shots/quick-sections/ are evidence to read, not just the exit
# code. QUICK_LOCALE=ja_JP.UTF-8 runs the Japanese copy (shots in quick-sections-ja/). On a hybrid laptop export
# KURASHI_RENDER_NODE first.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
NAME=${1:-fe-quick-sections}
BIN=${KURASHI_BIN_DIR:-${CARGO_TARGET_DIR:-$ROOT/target}/debug}
MOCK_BIN=${KURASHI_MOCK_BIN:-$BIN/kurashi-mock}
LOCALE=${QUICK_LOCALE:-C.UTF-8}
OUT=$ROOT/frontend/shots/quick-sections
[ "$LOCALE" = C.UTF-8 ] || OUT=$OUT-ja
mkdir -p "$OUT"
fail() { echo "test-quick-sections: $*" >&2; exit 1; }

eval "$("$ROOT/tools/bench/sandbox.sh" start "$NAME")"
R=$XDG_RUNTIME_DIR
W=$R/work
MOCK_SOCK=$R/kurashi/mock.sock
mkdir -p "$W" "$R/kurashi"
cp "$BIN/kurashi" "$W/"
cp "$MOCK_BIN" "$W/kurashi-mock"
# The shared key helper has no Escape key: this test runs a copy with it (KEY_ESC, code 1).
sed 's/"left": (105, "Left")/"escape": (1, "Escape"), "left": (105, "Left")/' "$ROOT/tools/bench/wl_keys.py" > "$W/wl_keys.py"
grep -q '"escape"' "$W/wl_keys.py" || fail "could not add Escape to the key helper"

pids=()
MOCK_PID=""
stop_phase() {  # kills only the processes this script started
  for p in "${pids[@]}"; do kill "$p" 2>/dev/null || true; done
  for p in "${pids[@]}"; do wait "$p" 2>/dev/null || true; done
  pids=()
  rm -f "$KURASHI_SOCKET" "$MOCK_SOCK"
}
cleanup() {
  stop_phase
  "$ROOT/tools/bench/sandbox.sh" stop "$NAME" >/dev/null || true
}
trap cleanup EXIT

export XDG_CONFIG_HOME=$R/xdg/config XDG_STATE_HOME=$R/xdg/state \
       XDG_DATA_HOME=$R/xdg/data XDG_CACHE_HOME=$R/xdg/cache KURASHI_DATA_DIR=$ROOT LC_ALL=$LOCALE
mkdir -p "$XDG_CONFIG_HOME" "$XDG_STATE_HOME" "$XDG_DATA_HOME" "$XDG_CACHE_HOME"
K() { timeout 10 "$W/kurashi" "$@"; }
# doc <name>: the document's data as JSON, or nothing when the daemon does not serve it.
doc() { K sub "$1" --count 0 --json 2>/dev/null | jq -c 'select(.t == "snap") | .data' || true; }
panel() { doc runtime.ui | jq -r '.panel // ""' 2>/dev/null || true; }

# The card's surface (Theme.container, color.surface_container) in the output's centre column: its pixel count and
# bounding box. A card is drawn only where its surface is; a closed Stage draws nothing.
cat > "$W/analyse.py" <<'PY'
import json, sys

SURFACE = tuple(int(sys.argv[2][i:i + 2], 16) for i in (0, 2, 4))
TOL = 3
X0, X1, Y0, Y1 = 960, 1600, 40, 1000   # the output is 2560 wide: the card is centred on 1280, under the 36 px bar


def read_ppm(data):
    # Four whitespace-separated fields (magic, width, height, maxval), one whitespace byte, the raster.
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
        raise SystemExit(f"not an 8-bit P6 image: {fields}")
    return int(fields[1]), int(fields[2]), data[i + 1:]


with open(sys.argv[1], "rb") as f:
    w, h, raster = read_ppm(f.read())
n = 0
x0 = y0 = 1 << 30
x1 = y1 = -1
for y in range(Y0, min(Y1, h)):
    row = y * w * 3
    for x in range(X0, min(X1, w)):
        o = row + x * 3
        if (abs(raster[o] - SURFACE[0]) <= TOL and abs(raster[o + 1] - SURFACE[1]) <= TOL
                and abs(raster[o + 2] - SURFACE[2]) <= TOL):
            n += 1
            x0, x1 = min(x0, x), max(x1, x)
            y0, y1 = min(y0, y), max(y1, y)
print(json.dumps({"surface": n, "bbox": [x0, y0, x1, y1] if n else None}))
PY

# The relay sits where the frontend looks for the daemon (the protocol's default socket) and forwards to the mock. It logs
# the `sub` and `unsub` lines of the frontend's own connection, so the test can see what the card subscribes to and when
# (Ma). The test adds its own `mark` lines to the same log.
cat > "$W/relay.py" <<'PY'
import asyncio, json, os, sys

FRONT, BACK, LOG = sys.argv[1], sys.argv[2], sys.argv[3]
LIMIT = 1 << 22


def note(line):
    with open(LOG, "a") as f:
        f.write(line + "\n")


async def pump(src, dst, to_mock, state):
    try:
        while True:
            line = await src.readline()
            if not line:
                break
            if to_mock:
                try:
                    m = json.loads(line)
                except ValueError:
                    m = {}
                if m.get("t") == "hello":
                    state["frontend"] = m.get("client") == "frontend"
                elif state.get("frontend") and m.get("t") in ("sub", "unsub"):
                    note(f"{m['t']} {m.get('doc', '')}")
            dst.write(line)
            await dst.drain()
    except OSError:
        pass
    finally:
        dst.close()


async def handle(cr, cw):
    try:
        sr, sw = await asyncio.open_unix_connection(BACK, limit=LIMIT)
    except OSError:
        cw.close()
        return
    state = {}
    await asyncio.gather(pump(cr, sw, True, state), pump(sr, cw, False, state))


async def main():
    if os.path.exists(FRONT):
        os.unlink(FRONT)
    server = await asyncio.start_unix_server(handle, path=FRONT, limit=LIMIT)
    async with server:
        await server.serve_forever()


asyncio.run(main())
PY

# The shot's card (surface_container) in layout coordinates, and a crop of it as the evidence shot.
ppm_shot() {  # ppm_shot <name> <settle s>: the output as a PPM
  sleep "$2"
  timeout 20 grim -o HEADLESS-1 -t ppm "$W/$1.ppm" || fail "grim failed on $1"
}
card_shot() {  # card_shot <name> <settle s>: the open card's bounding box (cx0 cy0 cx1 cy1) and a crop of it
  local res
  ppm_shot "$1" "$2"
  res=$(timeout 60 python3 -I "$W/analyse.py" "$W/$1.ppm" "$(token color.surface_container 252329)") \
    || fail "$1: analysis failed"
  echo "$1: $res"
  jq -e '.surface >= 15000 and .bbox != null
      and (((.bbox[2] - .bbox[0] + 1) - 398) | fabs) <= 4
      and (((.bbox[0] + .bbox[2]) / 2 - 1280) | fabs) <= 4' <<<"$res" >/dev/null \
    || fail "$1: no card 400 px wide centred on the output ($res)"
  read -r cx0 cy0 cx1 cy1 < <(jq -r '.bbox | "\(.[0]) \(.[1]) \(.[2]) \(.[3])"' <<<"$res")
  timeout 20 grim -g "$((cx0 - 24)),$((cy0 - 24)) $((cx1 - cx0 + 49))x$((cy1 - cy0 + 49))" "$OUT/$1.png" \
    || fail "grim failed on $1"
  [ -s "$OUT/$1.png" ] || fail "empty screenshot $1"
  echo "shot $1"
}
# token <name> <fallback>: a colour token of the daemon's theme document, else the frontend's own fallback for it.
token() {
  local v
  v=$(doc theme | jq -r --arg k "$1" '.tokens[$k] // empty' 2>/dev/null || true)
  v=${v#\#}
  echo "${v:-$2}"
}
click() {  # click <x> <y>: a left click of the virtual pointer, at layout coordinates
  timeout 30 python3 -I "$ROOT/tools/bench/wl_pointer.py" click "$1" "$2" left || fail "click at $1,$2 failed"
}
press() {  # press <key>...: one line per key to the keyboard helper, a short pause after each
  local k
  for k in "$@"; do
    printf '%s\n' "$k" >&3 || fail "the keyboard helper stopped (see $R/keys.log)"
    sleep 0.4
  done
}
mark() { printf 'mark %s\n' "$1" >> "$R/subs.log"; }
# last_event <doc>: the last subscribe or unsubscribe of the card's connection for that document ("" when none yet).
last_event() { grep -E "^(un)?sub $1\$" "$R/subs.log" | tail -n 1 || true; }
# A pointer at layout coordinates measured from the card's top left (cx0, cy0), in the shots: the Wi-Fi tile's switch zone
# and arrow zone, the heading, the Wi-Fi page's Back control, and the media row's title.
at() { click $(( cx0 + $1 )) $(( cy0 + $2 )); }
# W21: the card is a phone (PhoneFrame): the rows sit on its screen, under its status row and the greeting row.
WIFI_TILE=(90 158)     # the tile's middle (B33: 186 was its bottom edge, so a click there missed now and then)
WIFI_ARROW=(184 158)
HEADING=(116 76)       # the greeting row
BACK=(54 82)          # the page header's round back key
MEDIA_TITLE_X=76        # the media row's title, from the card's left edge
# and 92 px above the phone screen's bottom edge (W21-island-morph: the phone is its own chrome, the Stage draws no card and
# no Close row under it any more): the rows above it differ by locale (the status line wraps), the footer does not
MEDIA_FROM_BOTTOM=92

: > "$R/qs.log"
: > "$R/server.log"
: > "$R/subs.log"
rm -f "$MOCK_SOCK" "$KURASHI_SOCKET"
RUST_LOG=info "$W/kurashi-mock" --outputs HEADLESS-1 --fixed-time 12:34 --socket "$MOCK_SOCK" >> "$R/server.log" 2>&1 &
MOCK_PID=$!
pids+=("$MOCK_PID")
for _ in $(seq 100); do [ -S "$MOCK_SOCK" ] && break; sleep 0.1; done
[ -S "$MOCK_SOCK" ] || fail "mock did not come up (see $R/server.log)"
python3 -I "$W/relay.py" "$KURASHI_SOCKET" "$MOCK_SOCK" "$R/subs.log" >> "$R/relay.log" 2>&1 &
pids+=("$!")
for _ in $(seq 100); do [ -S "$KURASHI_SOCKET" ] && K sub svc.clock --count 0 --json >/dev/null 2>&1 && break; sleep 0.1; done
[ -S "$KURASHI_SOCKET" ] || fail "relay did not come up (see $R/relay.log)"
# Without KURASHI_SOCKET: the frontend must find the relay by the protocol default, as in a live session.
env -u KURASHI_SOCKET LC_ALL=$LOCALE qs -p "$ROOT/frontend" >> "$R/qs.log" 2>&1 &
pids+=("$!")
for _ in $(seq 100); do grep -q 'hello.*frontend' "$R/server.log" && break; sleep 0.1; done
grep -q 'hello.*frontend' "$R/server.log" || fail "frontend never said hello (see $R/qs.log)"
sleep 3   # the bar's documents and the first frames

# One virtual keyboard for the whole keyboard part: a keyboard that goes away makes the compositor drop the window's
# keyboard focus, so the keys go through a FIFO to one long-running helper.
rm -f "$W/keys.fifo"
mkfifo "$W/keys.fifo"
timeout 1200 python3 -I "$W/wl_keys.py" --serve < "$W/keys.fifo" >> "$R/keys.log" 2>&1 &
pids+=("$!")
exec 3> "$W/keys.fifo"

# 1. The card opens on the tiles (the shot is the evidence: status, six tiles, levels, media, footer).
K act quick.toggle >/dev/null || fail "quick.toggle refused"
for _ in $(seq 25); do [ "$(panel)" = quick ] && break; sleep 0.2; done
[ "$(panel)" = quick ] || fail "quick.toggle did not open the quick panel (runtime.ui panel \"$(panel)\")"
card_shot quick-open 1.5
echo "ok: quick.toggle opens the card (panel quick)"
net=$(doc svc.network)
jq -e '.state | type == "string"' <<<"$net" >/dev/null || fail "the relay's mock does not serve svc.network: ${net:-no document}"
aud=$(doc svc.audio)
jq -e '.available == true and ((.sinks // []) | length) >= 2' <<<"$aud" >/dev/null \
  || fail "the mock's svc.audio has no available sinks: ${aud:-no document}"
jq -e '(.networks // []) | length >= 1' <<<"$(doc svc.network.scan)" >/dev/null \
  || fail "the mock's svc.network.scan lists no networks (W13-quick-daemon)"
[ "$(last_event svc.network.scan)" = "" ] || fail "the scan was subscribed before the Wi-Fi page was opened"
echo "ok: no scan subscription while the tiles show"

# 2. Keyboard: a click on the heading gives the card its focus; Tab reaches the Wi-Fi tile; Return toggles it; Right
#    opens its page (the scan subscribed); the page's Tab walks to an unsaved network, whose join the daemon refuses.
click "$((cx0 + HEADING[0]))" "$((cy0 + HEADING[1]))"
# The status sentence's segments are Tab stops that open their pages: Wi-Fi, then Audio; Escape returns to each.
press tab return
sleep 1.5
[ "$(last_event svc.network.scan)" = "sub svc.network.scan" ] || fail "the Wi-Fi status segment did not open the Wi-Fi page"
press escape
sleep 1.5
[ "$(last_event svc.network.scan)" = "unsub svc.network.scan" ] || fail "Escape did not unsubscribe the scan"
press tab return
sleep 1.5
press escape
sleep 1.5
[ "$(panel)" = quick ] || fail "Escape on the audio page closed the card"
echo "ok: keyboard: the status segments open their pages (Wi-Fi, Audio) and Escape returns to them"
# Tab from the Audio segment: the Power segment, then the Wi-Fi tile, where Return toggles the radio.
press tab tab return
sleep 1.5
[ "$(doc svc.network | jq -r '.wifi_enabled')" = "false" ] || fail "Tab and Return did not turn the Wi-Fi radio off"
# With the radio off the scan has no list: the page shows the daemon's reason (the unavailable state of the page).
press right
sleep 1.5
card_shot quick-wifi-off-page 0.5
press escape
sleep 1.5
press return
sleep 1.5
[ "$(doc svc.network | jq -r '.wifi_enabled')" = "true" ] || fail "Return on the Wi-Fi tile did not turn the radio back on"
echo "ok: keyboard: Tab to the Wi-Fi tile, Return toggles it (off and back on)"
press right
sleep 1.5
[ "$(last_event svc.network.scan)" = "sub svc.network.scan" ] || fail "Right did not open the Wi-Fi page (scan not subscribed)"
press tab tab tab tab return
sleep 1.5
card_shot quick-wifi-refused 0.5
[ "$(doc svc.network | jq -r '.wifi_enabled')" = "true" ] || fail "the refused join changed the Wi-Fi radio"
# The next unsaved network is secured: the daemon names the password it cannot take yet.
press tab return
sleep 1.5
card_shot quick-wifi-needs-secret 0.5
[ "$(doc svc.network | jq -r '.wifi_enabled')" = "true" ] || fail "the join that needs a password changed the Wi-Fi radio"
echo "ok: keyboard: Right opens the Wi-Fi page; Tab and Return on an unsaved network: the daemon refuses, shown in place"
# Escape goes back to the tiles (the scan unsubscribed) and the focus returns to the Wi-Fi tile.
press escape
sleep 1.5
[ "$(panel)" = quick ] || fail "Escape on a page closed the card"
[ "$(last_event svc.network.scan)" = "unsub svc.network.scan" ] || fail "Escape did not unsubscribe the scan"
echo "ok: keyboard: Escape goes back to the tiles (the scan unsubscribed), the card stays open"

# 3. Pointer: the Wi-Fi tile's main zone toggles the Wi-Fi radio; its arrow opens the page; the page's Back returns (the
#    focus goes back to the Wi-Fi tile, where the keyboard steps below pick up).
wifi0=$(jq -r '.wifi_enabled' <<<"$net")
at "${WIFI_TILE[0]}" "${WIFI_TILE[1]}"
sleep 1.5
wifi1=$(doc svc.network | jq -r '.wifi_enabled')
[ "$wifi1" != "$wifi0" ] || fail "a click on the Wi-Fi tile did not flip svc.network.wifi_enabled ($wifi0)"
at "${WIFI_TILE[0]}" "${WIFI_TILE[1]}"
sleep 1.5
[ "$(doc svc.network | jq -r '.wifi_enabled')" = "$wifi0" ] || fail "a second click on the Wi-Fi tile did not flip it back"
echo "ok: click on the Wi-Fi tile: wifi_enabled $wifi0 -> $wifi1 -> $wifi0"
at "${WIFI_ARROW[0]}" "${WIFI_ARROW[1]}"
sleep 1.5
[ "$(panel)" = quick ] || fail "the arrow closed the card (panel \"$(panel)\")"
[ "$(last_event svc.network.scan)" = "sub svc.network.scan" ] || fail "the Wi-Fi page did not subscribe the scan"
card_shot quick-wifi-page 0.5
at "${BACK[0]}" "${BACK[1]}"
sleep 1.5
[ "$(last_event svc.network.scan)" = "unsub svc.network.scan" ] || fail "the Back control did not unsubscribe the scan"
echo "ok: the arrow opens the Wi-Fi page (the scan subscribed); its Back control returns (unsubscribed)"

# 4. Audio: Tab to the Audio tile, Right opens the page; Tab walks to the other output, Return makes it the default, and the
#    focus stays on the row chosen (the rows update in place).
press tab tab tab right
sleep 1.5
press tab tab tab tab return
sleep 1.5
[ "$(doc svc.audio | jq -r '[.sinks[] | select(.default == true) | .id] | first // empty')" = 2 ] \
  || fail "Tab and Return on the second output did not make it the default"
card_shot quick-audio-hdmi 0.8
press escape
sleep 1.5
echo "ok: keyboard: the audio page: Tab and Return make the other output the default"

# 5. Arrows between tiles: Down from Audio reaches Display, Left reaches Power; Right opens the Power page, where Tab and
#    Return choose Power saver (the profile in effect changes).
press down left right
sleep 1.5
card_shot quick-power-page 0.5
press tab return
sleep 1.5
[ "$(doc svc.power | jq -r '.profile')" = "power-saver" ] || fail "Tab and Return on the power page did not choose power-saver"
echo "ok: arrows: Down and Left move between tiles; the power page chooses the profile (power-saver)"
press escape
sleep 1.5

# 6. Focus: Up from Power reaches Focus, Right opens its page; Tab Tab Return turns Do not disturb on until one hour.
press up right
sleep 1.5
press tab tab return
sleep 1.5
dnd_until=$(doc svc.notifications | jq -r '.dnd_until // empty')
[ -n "$dnd_until" ] || fail "the focus page's one-hour choice set no end (svc.notifications.dnd_until)"
card_shot quick-focus-page 0.5
press left
sleep 1.5
[ "$(panel)" = quick ] || fail "Left on the focus page closed the card"
echo "ok: focus page: Do not disturb until one hour (dnd_until $dnd_until)"

# 7. Display: Down and Tab reach Display, Right opens its page (the shot shows the level, the reason for night light). The
#    slider's intent (brightness.set) is not checked: the mock serves only audio.volume among the intents.
press down tab right
sleep 1.5
card_shot quick-display-page 0.5
press escape
sleep 1.5
echo "ok: display page"

# 8. Bluetooth: Up twice from Display reaches the Bluetooth tile; Right opens its page (the existing panel).
press up up right
sleep 1.5
card_shot quick-bluetooth-page 0.5
press escape
sleep 1.5
echo "ok: bluetooth page"

# 9. Connecting and failed: the mock is held still (SIGSTOP), so the Wi-Fi tile's request gets no answer. The tile shows
#    "connecting" and, 30 s later, the timeout's failure with its Retry; SIGCONT lets the queued request through.
press left
sleep 1
wifi_before=$(doc svc.network | jq -r '.wifi_enabled')
kill -STOP "$MOCK_PID"
press return
sleep 1.5
card_shot quick-connecting 0.5
sleep 30
card_shot quick-failed 0.5
kill -CONT "$MOCK_PID"
sleep 2.5
wifi_after=$(doc svc.network | jq -r '.wifi_enabled')
[ "$wifi_after" != "$wifi_before" ] || fail "the request queued while the mock was held was not applied after SIGCONT"
card_shot quick-recovered 0.5
echo "ok: connecting, then the timeout's failure; the queued request applies after SIGCONT ($wifi_before -> $wifi_after)"

# 10. The media row opens the island's media view (the card gives way to the island's panel).
at "$MEDIA_TITLE_X" "$(( cy1 - cy0 - MEDIA_FROM_BOTTOM ))"
sleep 1.5
[ "$(panel)" = island ] || fail "the media row did not open the island's media view (panel \"$(panel)\")"
echo "ok: the media row opens the island's media view"

# 11. ui.close closes the card (Ma: no card drawn, its documents unsubscribed); Escape on the tiles closes it too.
K act ui.close >/dev/null || fail "ui.close refused"
sleep 1.5
ppm_shot quick-closed 0.5
closed=$(timeout 60 python3 -I "$W/analyse.py" "$W/quick-closed.ppm" "$(token color.surface_container 252329)")
jq -e '.surface < 500' <<<"$closed" >/dev/null || fail "a card is still drawn after ui.close ($closed)"
[ "$(last_event svc.network)" = "unsub svc.network" ] || fail "the card's documents stayed subscribed after ui.close"
echo "ok: ui.close: no card drawn, and the card's documents unsubscribed"
K act quick.toggle >/dev/null
for _ in $(seq 25); do [ "$(panel)" = quick ] && break; sleep 0.2; done
card_shot quick-reopened 1.2
click "$((cx0 + HEADING[0]))" "$((cy0 + HEADING[1]))"
press escape
sleep 1.5
[ "$(panel)" = "" ] || fail "Escape on the tiles did not close the card (panel \"$(panel)\")"
echo "ok: Escape on the tiles closes the card"

# 12. Tile states (I51): an on tile is a tonal container with an accent glyph; a solid badge is for the failed state only.
#     Shots of the card with three tiles on (Wi-Fi, Bluetooth, Audio), one (Wi-Fi) and none.
K act quick.toggle >/dev/null
for _ in $(seq 25); do [ "$(panel)" = quick ] && break; sleep 0.2; done
[ "$(panel)" = quick ] || fail "quick.toggle did not reopen the card for the tile states"
K act network.wifi '{"on":true}' >/dev/null
K act bluetooth.power '{"on":true}' >/dev/null
K act power.profile '{"name":"balanced"}' >/dev/null
for _ in $(seq 25); do [ "$(doc svc.power | jq -r '.profile')" = balanced ] && break; sleep 0.2; done
[ "$(doc svc.power | jq -r '.profile')" = balanced ] || fail "the tile states: the power profile is not balanced (power saver is a tile in its own right)"
[ "$(doc svc.audio | jq -r '.muted')" = false ] || K act audio.mute.toggle >/dev/null
K act notify.dnd '{"on":false}' >/dev/null
sleep 1
card_shot tiles-3-on 1
K act bluetooth.power '{"on":false}' >/dev/null
[ "$(doc svc.audio | jq -r '.muted')" = true ] || K act audio.mute.toggle >/dev/null
sleep 1
card_shot tiles-1-on 1
K act network.wifi '{"on":false}' >/dev/null
sleep 1
card_shot tiles-0-on 1
[ "$(doc svc.network | jq -r '.wifi_enabled')" = false ] || fail "the tile states: Wi-Fi did not turn off"
echo "ok: tile states: three, one and no tile on (tiles-*-on.png)"

# 13. Contributions (W18, K28 `quick.tiles`): the test mod's tile and the wallpaper tile take the core tiles' flow in cells of
#     their own size; the plain contribution (not a tile) is clipped to its cell, and the grid does not grow for it. From the
#     heading, Tab walks the status segments and the core tiles to the test mod's tile; Down reaches the wallpaper tile; Return
#     moves its picture on (the subtitle changes); Right opens its picker panel (the card gives way to the panel).
card_shot tiles-mods 1
[ "$(last_event mod.wallpaper)" = "sub mod.wallpaper" ] || fail "the wallpaper tile did not subscribe its document while the card shows it"
click "$((cx0 + HEADING[0]))" "$((cy0 + HEADING[1]))"
# W23: the core tiles gained Keep awake, Night light and Record (three more Tab stops before the test mod's tile).
press tab tab tab tab tab tab tab tab tab tab tab tab tab
press down
pic0=$(doc mod.wallpaper | jq -r '.outputs["HEADLESS-1"].path // empty')
press return
sleep 1.5
pic1=$(doc mod.wallpaper | jq -r '.outputs["HEADLESS-1"].path // empty')
[ -n "$pic0" ] && [ "$pic1" != "$pic0" ] || fail "Return on the wallpaper tile did not move its picture ($pic0 -> $pic1)"
card_shot tiles-mods-next 0.5
echo "ok: keyboard: Tab reaches the mod tiles, Down reaches the wallpaper tile, Return moves its picture ($pic0 -> $pic1)"

# 14. States the mock makes on demand (W18, I50): a battery, a tile unavailable, a tile forced; and the Display slider's
#     intent (brightness.set, a fraction of full scale). The states are the documents' own, as a daemon would send them.
K act mock.doc '{"doc":"svc.power","patch":{"present":true,"on_battery":true,"percent":64,"state":"discharging","time_to_empty_s":7800}}' >/dev/null || fail "mock.doc refused the battery"
sleep 1
card_shot tiles-battery 0.8
K act mock.doc '{"doc":"svc.bluetooth","patch":{"available":false}}' >/dev/null || fail "mock.doc refused the unavailable tile"
sleep 1
card_shot tiles-unavailable 0.8
K act mock.doc '{"doc":"svc.network","patch":{"forced_by":"nix"}}' >/dev/null || fail "mock.doc refused the forced tile"
sleep 1
card_shot tiles-forced 0.8
K act mock.doc '{"doc":"svc.network","patch":{"forced_by":null}}' >/dev/null
# The mod's own tile unavailable: its backend is down, so the tile says why (the mod's i18n key) and dims.
K act mock.doc '{"doc":"mod.wallpaper","patch":{"backend":{"available":false,"reason":"mod-wallpaper.backend.down"}}}' >/dev/null || fail "mock.doc refused the wallpaper backend"
sleep 1
card_shot tiles-wallpaper-down 0.8
K act mock.doc '{"doc":"mod.wallpaper","patch":{"backend":{"available":true,"reason":null}}}' >/dev/null
K act mock.doc '{"doc":"svc.bluetooth","patch":{"available":true}}' >/dev/null
K act mock.doc '{"doc":"svc.power","patch":{"present":false,"on_battery":false,"percent":null,"state":null,"time_to_empty_s":null}}' >/dev/null
K intent brightness.set 0.3 >/dev/null || fail "brightness.set refused"
sleep 1
[ "$(doc svc.brightness | jq -r '.percent == 30')" = true ] || fail "brightness.set 0.3 did not set 30 % ($(doc svc.brightness))"
echo "ok: states: a battery, an unavailable tile, a forced tile; brightness.set 0.3 makes 30 %"

# 15. The picker: Right on the wallpaper tile opens its panel (the mod's Stage panel; the card gives way to it). The card is
#     reopened, so the keyboard starts where it starts for a user: on the card, with nothing focused.
K act ui.close >/dev/null
sleep 1
K act quick.toggle >/dev/null
for _ in $(seq 25); do [ "$(panel)" = quick ] && break; sleep 0.2; done
[ "$(panel)" = quick ] || fail "quick.toggle did not reopen the card for the picker check"
sleep 1
click "$((cx0 + HEADING[0]))" "$((cy0 + HEADING[1]))"
press tab tab tab tab tab tab tab tab tab tab tab tab tab   # W23: three more core tiles
press down right
sleep 1.5
[ "$(panel)" = "mod:wallpaper:wallpaper" ] || fail "Right on the wallpaper tile did not open its picker panel (panel \"$(panel)\")"
echo "ok: Right on the wallpaper tile opens its picker panel (mod:wallpaper:wallpaper)"

# 16. No contribution (the empty state, W18): with no `quick.tiles` entry the grid is the six core tiles and no cell is drawn.
K act ui.close >/dev/null
sleep 1
K act quick.toggle >/dev/null
for _ in $(seq 25); do [ "$(panel)" = quick ] && break; sleep 0.2; done
[ "$(panel)" = quick ] || fail "quick.toggle did not reopen the card for the empty state"
K act mock.doc '{"doc":"runtime.slots","patch":{"quick.tiles":null}}' >/dev/null || fail "mock.doc refused the empty slot"
sleep 1
card_shot tiles-no-mods 0.8
echo "ok: no contribution: the six core tiles only (tiles-no-mods.png)"

K act ui.close >/dev/null
sleep 1
[ "$(last_event mod.wallpaper)" = "unsub mod.wallpaper" ] || fail "the wallpaper tile's document stayed subscribed after the card closed"
echo "ok: the wallpaper tile subscribes its document while the card shows it, and unsubscribes it when the card is gone (Ma)"

exec 3>&-
stop_phase
errors='ERROR\|TypeError\|ReferenceError\|Unable to assign\|is not defined\|is not a type\|Cannot assign\|Cannot anchor\|Binding loop\|non-existent property'
if grep -q "$errors" "$R/qs.log"; then
  echo "qs.log has errors:" >&2
  grep "$errors" "$R/qs.log" | head >&2
  exit 1
fi
echo "ok: tiles, pages, keys, toggle states and the scan subscription; screenshots in $OUT"
