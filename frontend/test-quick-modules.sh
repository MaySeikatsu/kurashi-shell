#!/usr/bin/env bash
# The control centre's controls as modules of their own (W70, I469, docs/ux/control-centre-modules.md) against kurashi-mock,
# invisibly (headless sway sandbox), by one persistent virtual pointer:
#   1. a top bar listing the eleven control modules shows each of them (the bar's own log, KURASHI_BAR_GEOMETRY);
#   2. a click does the control's obvious thing, read back from the service document: Focus turns do not disturb on and
#      off, sound output mutes, the microphone mutes, airplane mode, keep awake and night light switch; dark mode writes
#      theme.colors.scheme (the relay logs the `apply`; the mock refuses it, so the bar shows the module's error state);
#      the wheel steps sound output (two notches: 10 %) and brightness; busy: with the mock held still (SIGSTOP) Focus
#      waits dimmed (shot), and its request goes through after SIGCONT;
#   3. a click on Wi-Fi opens the control centre on its page (the scan is subscribed: the relay's log), a second click
#      closes it; Bluetooth's click while the Wi-Fi page is up turns the open card to its page (it stays open); with
#      `bar.hover_card` a rest on Wi-Fi opens its card, Bluetooth turns it, leaving both closes it (K113);
#   4. unavailable (mock.doc): keep awake with the idle service's reason (no page: a click sends nothing and opens
#      nothing), Bluetooth without an adapter (a click changes nothing and opens its card, which says why; shot); a right
#      click opens a module's menu (runtime.ui.tray = module:<id>);
#   6. the centre as a container (stage c): it shows `quick.tiles` (the default: the ten tiles of before, in order);
#      its edit key starts the edit mode (shot); Alt+Right and Alt+Down move a tile, Delete takes one out, the add key
#      adds the microphone at the end, a tile's remove key (−) takes one out; Done writes the edit's list as one apply
#      (the relay's log); the mock refuses it, so the edit stays and says so (shot), Escape puts the setting back; the
#      centre follows the setting when it changes elsewhere (mock.doc, as Settings' list would write it; shot);
#   5. idle: with the pointer away and nothing open, the shell commits no frame for 3 s (Ma; WAYLAND_DEBUG commits);
#      the frontend logs no QML error.
# Shots (evidence to read) in frontend/shots/quick-modules/.
#   nix develop -c frontend/test-quick-modules.sh [sandbox-name]
# Binaries kurashi and kurashi-mock from $KURASHI_BIN_DIR (default $CARGO_TARGET_DIR/debug, else target/debug), copied.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
NAME=${1:-${KURASHI_SB_PREFIX:-}fe-quick-modules}
BIN=${KURASHI_BIN_DIR:-${CARGO_TARGET_DIR:-$ROOT/target}/debug}
OUT=$ROOT/frontend/shots/quick-modules
mkdir -p "$OUT"
fail() { echo "test-quick-modules: FAIL: $*" >&2; exit 1; }

eval "$("$ROOT/tools/bench/sandbox.sh" start "$NAME")"
. "$ROOT/frontend/test-lib.sh"
R=$XDG_RUNTIME_DIR
W=$R/work
MOCK_SOCK=$R/kurashi/mock.sock
mkdir -p "$W" "$R/kurashi"
cp "$BIN/kurashi" "$BIN/kurashi-mock" "$W/"
pids=()
cleanup() {
  exec 9>&- 2>/dev/null || true
  for p in "${pids[@]}"; do kill "$p" 2>/dev/null || true; done
  for p in "${pids[@]}"; do wait "$p" 2>/dev/null || true; done
  "$ROOT/tools/bench/sandbox.sh" stop "$NAME" >/dev/null || true
}
trap cleanup EXIT

export XDG_CONFIG_HOME=$R/xdg/config XDG_STATE_HOME=$R/xdg/state XDG_DATA_HOME=$R/xdg/data XDG_CACHE_HOME=$R/xdg/cache \
       KURASHI_DATA_DIR=$ROOT LC_ALL=C.UTF-8
mkdir -p "$XDG_CONFIG_HOME" "$XDG_STATE_HOME" "$XDG_DATA_HOME" "$XDG_CACHE_HOME"
K() { timeout 10 "$W/kurashi" "$@"; }
doc() { K sub "$1" --count 0 --json 2>/dev/null | jq -c 'select(.t == "snap") | .data' || true; }
ui() { doc runtime.ui; }
ui_is() { ui | jq -e "$1" >/dev/null 2>&1; }
closed() { ui_is '(.panel // "") == "" and (.tray // "") == ""'; }
close_all() { K act ui.close >/dev/null || true; wait_until 3 closed || fail "ui.close did not close: $(ui)"; }

# The relay sits where the frontend looks for the daemon and logs its connection's `sub`, `unsub` and `act` lines (Ma, and
# what a press sent), as test-quick-sections.sh does.
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
                elif state.get("frontend") and m.get("t") == "act":
                    note(f"act {m.get('action', '')} {json.dumps(m.get('args', {}), sort_keys=True)}")
                elif state.get("frontend") and m.get("t") == "intent":
                    note(f"intent {m.get('key', '')} {json.dumps(m.get('value'))}")
                elif state.get("frontend") and m.get("t") == "apply":
                    note(f"apply {json.dumps(m.get('ops', []), sort_keys=True)}")
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

: > "$R/qs.log"; : > "$R/server.log"; : > "$R/subs.log"
RUST_LOG=info "$W/kurashi-mock" --outputs HEADLESS-1 --fixed-time 12:34 --socket "$MOCK_SOCK" >> "$R/server.log" 2>&1 &
MOCK_PID=$!
pids+=($MOCK_PID)
wait_until 10 test -S "$MOCK_SOCK" || fail "the mock did not come up (see $R/server.log)"
python3 -I "$W/relay.py" "$KURASHI_SOCKET" "$MOCK_SOCK" "$R/subs.log" >> "$R/relay.log" 2>&1 &
pids+=($!)
wait_until 10 K ping || fail "the relay did not come up (see $R/relay.log)"
MODS='["wifi","bluetooth","audio","mic","power","brightness","focus","caffeine","nightlight","darkmode","airplane","clock"]'
# (the mock answers no `apply`: its config document is patched, and it lays the bars out again from it; motion off is the
# theme document's tokens)
K act mock.doc "{\"doc\":\"config\",\"patch\":{\"values\":{\"edges.top.end\":{\"value\":$MODS}}}}" >/dev/null \
  || fail "the mock refused the bar's modules"
K act mock.doc '{"doc":"theme","patch":{"tokens":{"motion.spring.on":false,"motion.kind":"none"}}}' >/dev/null \
  || fail "the mock refused motion off"
wait_until 5 sh -c "\"$W/kurashi\" sub runtime.layout --count 0 --json | grep -q '\"darkmode\"'" \
  || fail "the mock's layout does not list the control modules"
QS_BARE=$(screen_hash)
env -u KURASHI_SOCKET KURASHI_BAR_GEOMETRY=1 KURASHI_QUICK_LOG=1 WAYLAND_DEBUG=1 qs -p "$ROOT/frontend" >> "$R/qs.log" 2>&1 &
pids+=($!)
wait_frontend "$R/qs.log" 0 15 0.6 "$QS_BARE" || fail "the frontend did not load (see $R/qs.log)"

# One pointer for the whole run (`--serve`): a pointer made per move is gone when its tool exits, and the bar then hears a
# leave half a second later.
rm -f "$R/ptr.fifo"
mkfifo "$R/ptr.fifo"
python3 -I "$ROOT/tools/bench/wl_pointer.py" --serve < "$R/ptr.fifo" &
pids+=($!)
exec 9> "$R/ptr.fifo"
mv_to() { echo "move $1 $2" >&9; sleep 0.15; }
ptr() { echo "click $1 $2 ${3:-left}" >&9; sleep 0.25; }
W_OUT=$(swaymsg -t get_outputs | python3 -c 'import json,sys; print(json.load(sys.stdin)[0]["rect"]["width"])')
H_OUT=$(swaymsg -t get_outputs | python3 -c 'import json,sys; print(json.load(sys.stdin)[0]["rect"]["height"])')
AWAY_X=$(( W_OUT / 2 )); AWAY_Y=$(( H_OUT - 200 ))
mv_to "$AWAY_X" "$AWAY_Y"

# ---- 1. each module on the bar ----
# where <id> → "cx cy": the middle of the module's last logged box on the top bar.
where() {
  grep -o "BARZONE HEADLESS-1 top end $1 .*" "$R/qs.log" | tail -1 | awk '{ printf "%d %d\n", ($6 + $8) / 2, ($7 + $9) / 2 }'
}
for id in wifi bluetooth audio mic power brightness focus caffeine nightlight darkmode airplane; do
  wait_until 5 sh -c "grep -q 'BARZONE HEADLESS-1 top end $id ' '$R/qs.log'" || fail "the bar does not show module $id"
done
echo "ok: the bar shows the eleven control modules"
read -r BX0 BY0 < <(grep -o "BARZONE HEADLESS-1 top end wifi .*" "$R/qs.log" | tail -1 | awk '{ print $6, $7 }')
timeout 20 grim -g "$(( BX0 - 16 )),0 $(( W_OUT - BX0 + 16 ))x48" "$OUT/bar.png" || fail "grim failed on the bar"
click_mod() { local x y; read -r x y < <(where "$1"); [ -n "$x" ] || fail "no place for $1"; ptr "$x" "$y" "${2:-left}"; }

# ---- 2. a click does the obvious thing ----
flip() { # flip <module> <doc> <jq of the value> <what>: a click changes the value, a second one changes it back
  local before after
  before=$(doc "$2" | jq -c "$3")
  click_mod "$1"
  wait_until 5 sh -c "[ \"\$(\"$W/kurashi\" sub $2 --count 0 --json | jq -c 'select(.t == \"snap\") | .data | $3')\" != '$before' ]" \
    || fail "a click on $1 did not change $4 (still $before)"
  after=$(doc "$2" | jq -c "$3")
  closed || fail "a click on $1 opened something: $(ui)"
  click_mod "$1"
  wait_until 5 sh -c "[ \"\$(\"$W/kurashi\" sub $2 --count 0 --json | jq -c 'select(.t == \"snap\") | .data | $3')\" = '$before' ]" \
    || fail "a second click on $1 did not change $4 back (still $after)"
  echo "ok: a click on $1 switches $4 ($before → $after → $before)"
}
flip focus svc.notifications '.dnd == true' "do not disturb"
flip audio svc.audio '.muted == true' "the output's mute"
flip mic svc.audio '.source.muted == true' "the microphone's mute"
flip airplane svc.network '.airplane == true' "airplane mode"
flip caffeine svc.idle '.caffeine == true' "keep awake"
flip nightlight svc.nightlight '.enabled == true' "night light"
# Busy: the mock held still (SIGSTOP), a click on Focus waits for its answer — the mark dims and its name says so (shot);
# SIGCONT lets the request through and the switch follows the document.
d0=$(doc svc.notifications | jq -c '.dnd == true')
printf 'mark busy\n' >> "$R/subs.log"
kill -STOP "$MOCK_PID"
click_mod focus
wait_until 3 sh -c "sed -n '/^mark busy\$/,\$p' '$R/subs.log' | grep -q '^act notify.dnd'" \
  || { kill -CONT "$MOCK_PID"; fail "busy: the click on Focus sent nothing"; }
sleep 0.8
timeout 20 grim -g "$(( BX0 - 16 )),0 $(( W_OUT - BX0 + 16 ))x48" "$OUT/bar-busy.png" || { kill -CONT "$MOCK_PID"; fail "grim failed"; }
kill -CONT "$MOCK_PID"
wait_until 5 sh -c "[ \"\$(\"$W/kurashi\" sub svc.notifications --count 0 --json | jq -c 'select(.t == \"snap\") | .data.dnd == true')\" != '$d0' ]" \
  || fail "busy: the held request did not go through after SIGCONT"
click_mod focus
wait_until 5 sh -c "[ \"\$(\"$W/kurashi\" sub svc.notifications --count 0 --json | jq -c 'select(.t == \"snap\") | .data.dnd == true')\" = '$d0' ]" \
  || fail "busy: Focus did not switch back"
echo "ok: busy: while the daemon does not answer, Focus waits dimmed (bar-busy); the request goes through after it"
# The wheel steps a level (5 % a notch) on sound output and brightness.
level() { doc "$1" | jq -r "$2"; }
wheel_mod() { local x y; read -r x y < <(where "$1"); echo "wheel $x $y $2 0.08" >&9; sleep 0.6; }
v0=$(level svc.audio '.volume')
# (down from a high level, up from a low one)
n=$(awk -v a="$v0" 'BEGIN { print (a > 0.5 ? -2 : 2) }')
wheel_mod audio "$n"
wait_until 5 sh -c "[ \"\$(\"$W/kurashi\" sub svc.audio --count 0 --json | jq -r 'select(.t == \"snap\") | .data.volume')\" != '$v0' ]" \
  || fail "the wheel on sound output did not step the level (still $v0)"
sleep 0.5
v1=$(level svc.audio '.volume')
awk -v a="$v0" -v b="$v1" -v n="$n" 'BEGIN { d = (b - a) * (n > 0 ? 1 : -1); exit !(d > 0.05 && d < 0.15) }' \
  || fail "two notches ($n) on sound output: $v0 → $v1, not a 10 % step"
b0=$(level svc.brightness '.percent')
n=$(awk -v a="$b0" 'BEGIN { print (a > 50 ? -2 : 2) }')
wheel_mod brightness "$n"
wait_until 5 sh -c "[ \"\$(\"$W/kurashi\" sub svc.brightness --count 0 --json | jq -r 'select(.t == \"snap\") | .data.percent')\" != '$b0' ]" \
  || fail "the wheel on brightness did not step the level (still $b0)"
echo "ok: the wheel steps sound output ($v0 → $v1) and brightness ($b0 → $(level svc.brightness '.percent'))"
# Dark mode writes the setting (an `apply`, which the mock refuses: the module then shows the refusal, its error state).
printf 'mark dark\n' >> "$R/subs.log"
click_mod darkmode
wait_until 5 sh -c "sed -n '/^mark dark\$/,\$p' '$R/subs.log' | grep -q '^apply .*\"theme.colors.scheme\"'" \
  || fail "a click on dark mode did not write theme.colors.scheme"
grep '^apply .*theme.colors.scheme' "$R/subs.log" | tail -1 | grep -qE '"value": "(dark|light)"' \
  || fail "dark mode wrote no scheme: $(grep '^apply' "$R/subs.log" | tail -1)"
wait_settled 1.5 0.4
read -r BX0 BY0 < <(grep -o "BARZONE HEADLESS-1 top end wifi .*" "$R/qs.log" | tail -1 | awk '{ print $6, $7 }')
timeout 20 grim -g "$(( BX0 - 16 )),0 $(( W_OUT - BX0 + 16 ))x48" "$OUT/bar-darkmode-refused.png" || fail "grim failed on the bar"
echo "ok: a click on dark mode writes theme.colors.scheme ($(grep '^apply' "$R/subs.log" | tail -1 | grep -oE '"value": "[a-z]+"'); the mock's refusal shows: bar-darkmode-refused)"

# ---- 3. a card on its page ----
mark() { printf 'mark %s\n' "$1" >> "$R/subs.log"; }
since() { sed -n "/^mark $1\$/,\$p" "$R/subs.log"; }
mark wifi-card
click_mod wifi
wait_until 5 ui_is '.panel == "quick"' || fail "a click on Wi-Fi opened no card: $(ui)"
wait_until 5 sh -c "sed -n '/^mark wifi-card\$/,\$p' '$R/subs.log' | grep -q '^sub svc.network.scan\$'" \
  || fail "the Wi-Fi card did not open on its page (no scan subscribed)"
since wifi-card | grep -q '^act network.wifi' && fail "a click on Wi-Fi switched the radio"
wait_settled 2 0.4
timeout 20 grim "$OUT/card-wifi.png" || fail "grim failed on the Wi-Fi card"
echo "ok: a click on Wi-Fi opens the control centre on its page"
click_mod bluetooth
sleep 0.6
ui_is '.panel == "quick"' || fail "Bluetooth's click while the Wi-Fi card was up closed it: $(ui)"
wait_until 5 sh -c "sed -n '/^mark wifi-card\$/,\$p' '$R/subs.log' | grep -q '^unsub svc.network.scan\$'" \
  || fail "Bluetooth's click did not turn the card from the Wi-Fi page"
wait_settled 2 0.4
timeout 20 grim "$OUT/card-bluetooth.png" || fail "grim failed on the Bluetooth card"
click_mod bluetooth
wait_until 5 closed || fail "a second click on Bluetooth did not close its card: $(ui)"
echo "ok: Bluetooth's click turns the open card to its page; a second click closes it"
mark power-card
click_mod power
wait_until 5 ui_is '.panel == "quick"' || fail "a click on power opened no card"
since power-card | grep -q '^act power.profile' && fail "a click on power changed the profile"
wait_settled 2 0.4
timeout 20 grim "$OUT/card-power.png" || fail "grim failed on the power card"
close_all
echo "ok: a click on power opens its card and changes no profile"

# Open on hover (K113, `bar.hover_card`): resting on Wi-Fi opens its card, moving on to Bluetooth turns it to that page,
# leaving both closes it.
K act mock.doc '{"doc":"config","patch":{"values":{"bar.hover_card":{"value":["wifi","bluetooth"]}}}}' >/dev/null \
  || fail "the mock refused bar.hover_card"
sleep 0.5
mark hover
read -r hx hy < <(where wifi)
mv_to "$hx" "$hy"
wait_until 3 ui_is '.panel == "quick"' || fail "hover: resting on Wi-Fi opened no card: $(ui)"
wait_until 3 sh -c "sed -n '/^mark hover\$/,\$p' '$R/subs.log' | grep -q '^sub svc.network.scan\$'" \
  || fail "hover: the card did not open on the Wi-Fi page"
read -r hx hy < <(where bluetooth)
mv_to "$hx" "$hy"
wait_until 3 sh -c "sed -n '/^mark hover\$/,\$p' '$R/subs.log' | grep -q '^unsub svc.network.scan\$'" \
  || fail "hover: moving on to Bluetooth did not turn the card to its page"
ui_is '.panel == "quick"' || fail "hover: the card closed on the way to Bluetooth: $(ui)"
mv_to "$AWAY_X" "$AWAY_Y"
wait_until 3 closed || fail "hover: the card stayed after the pointer left: $(ui)"
K act mock.doc '{"doc":"config","patch":{"values":{"bar.hover_card":{"value":[]}}}}' >/dev/null || true
echo "ok: bar.hover_card: resting on Wi-Fi opens its card, Bluetooth turns it, leaving closes it"

# ---- 4. unavailable: inert, and it says why ----
K act mock.doc '{"doc":"svc.idle","patch":{"reason":"power.idle.reason.no_protocol"}}' >/dev/null || fail "mock.doc refused svc.idle"
mark inert
click_mod caffeine
sleep 0.8
since inert | grep -q '^act idle.caffeine' && fail "a click on keep awake that cannot work sent idle.caffeine"
closed || fail "a click on keep awake that cannot work opened something: $(ui)"
echo "ok: keep awake that cannot work (the compositor reports no idle time) is inert"
K act mock.doc '{"doc":"svc.bluetooth","patch":{"available":false}}' >/dev/null || fail "mock.doc refused svc.bluetooth"
bt0=$(doc svc.bluetooth | jq -c '.powered')
mark bt-inert
click_mod bluetooth
wait_until 5 ui_is '.panel == "quick"' || fail "a click on an unavailable Bluetooth opened no card to say why"
since bt-inert | grep -q '^act bluetooth.power' && fail "a click on an unavailable Bluetooth switched it"
[ "$(doc svc.bluetooth | jq -c '.powered')" = "$bt0" ] || fail "a click on an unavailable Bluetooth changed it"
wait_settled 2 0.4
timeout 20 grim "$OUT/card-bluetooth-unavailable.png" || fail "grim failed"
close_all
echo "ok: an unavailable Bluetooth is inert; its card says why (shot card-bluetooth-unavailable)"
timeout 20 grim -g "$(( BX0 - 16 )),0 $(( W_OUT - BX0 + 16 ))x48" "$OUT/bar-unavailable.png" || fail "grim failed on the bar"
for id in wifi focus caffeine power; do
  click_mod "$id" right
  wait_until 3 ui_is ".tray == \"module:$id\"" || fail "a right click on $id opened no menu: $(ui)"
  close_all
done
echo "ok: a right click opens the module's menu (wifi, focus, caffeine, power)"

# ---- 6. the centre as a container: `quick.tiles` and its edit mode (W70 stage c) ----
# The keys stand where the card logs them (KURASHI_QUICK_LOG: `quick-at <name> x y w h`, output px).
at_of() { grep -o "quick-at $1 .*" "$R/qs.log" | tail -1 | awk '{ printf "%d %d\n", $3 + $5 / 2, $4 + $6 / 2 }'; }
tiles_now() { grep -o 'quick-tiles .*' "$R/qs.log" | tail -1 | cut -d' ' -f2; }
press() { local k; for k in "$@"; do printf '%s\n' "$k" >&3 || fail "the keyboard helper stopped"; sleep 0.35; done; }
sed 's/"left": (105, "Left")/"escape": (1, "Escape"), "left": (105, "Left")/' "$ROOT/tools/bench/wl_keys.py" > "$W/wl_keys.py"
rm -f "$W/keys.fifo"; mkfifo "$W/keys.fifo"
python3 -I "$W/wl_keys.py" --serve < "$W/keys.fifo" >> "$R/keys.log" 2>&1 &
pids+=($!)
exec 3> "$W/keys.fifo"
DEFAULT=wifi,bluetooth,focus,audio,power,brightness,caffeine,nightlight,recorder,darkmode
K act quick.toggle >/dev/null || fail "quick.toggle refused"
wait_until 5 ui_is '.panel == "quick"' || fail "quick.toggle opened no card"
wait_until 5 sh -c "[ \"\$(grep -o 'quick-tiles .*' '$R/qs.log' | tail -1 | cut -d' ' -f2)\" = '$DEFAULT' ]" \
  || fail "the centre does not show the default tiles in order: $(tiles_now)"
echo "ok: the centre shows quick.tiles' default, the ten tiles of before, in order"
wait_until 3 sh -c "grep -q 'quick-at edit ' '$R/qs.log'" || fail "the card logged no edit key"
read -r ex ey < <(at_of edit)
ptr "$ex" "$ey"
wait_until 3 sh -c "grep -q 'quick-edit on' '$R/qs.log'" || fail "the edit key did not start the edit mode"
wait_settled 1.5 0.4
timeout 20 grim "$OUT/edit-mode.png" || fail "grim failed on the edit mode"
# The focus is on the first tile: Alt+Right moves it one place on, Delete takes it out, Alt+Down moves the next a row down.
press alt+right
wait_until 3 sh -c "grep -o 'quick-tiles .*' '$R/qs.log' | tail -1 | grep -q ' bluetooth,wifi,focus'" \
  || fail "Alt+Right did not move Wi-Fi one place on: $(tiles_now)"
press delete
wait_until 3 sh -c "grep -o 'quick-tiles .*' '$R/qs.log' | tail -1 | grep -q ' bluetooth,focus,audio'" \
  || fail "Delete did not take Wi-Fi out: $(tiles_now)"
press alt+down
wait_until 3 sh -c "grep -o 'quick-tiles .*' '$R/qs.log' | tail -1 | grep -q ' bluetooth,audio,power,focus'" \
  || fail "Alt+Down did not move Focus a row down: $(tiles_now)"
echo "ok: edit mode by keys: Alt+Right and Alt+Down move a tile, Delete takes it out ($(tiles_now))"
sleep 0.8
read -r axx axy < <(at_of add:mic)
[ -n "${axx:-}" ] || fail "the edit mode offers no key to add the microphone"
ptr "$axx" "$axy"
wait_until 3 sh -c "grep -o 'quick-tiles .*' '$R/qs.log' | tail -1 | grep -q ',mic\$'" \
  || fail "the add key did not add the microphone at the end: $(tiles_now)"
read -r rx ry rw rh < <(grep -o "quick-at tile:power .*" "$R/qs.log" | tail -1 | awk '{ print $3, $4, $5, $6 }')
# the tile's remove key (−): on its top-right corner
ptr "$(( rx + rw - 5 ))" "$(( ry + 5 ))"
wait_until 3 sh -c "! grep -o 'quick-tiles .*' '$R/qs.log' | tail -1 | grep -q 'power'" \
  || fail "the remove key did not take power out: $(tiles_now)"
WANT=$(tiles_now)
echo "ok: edit mode by pointer: + adds a control at the end, − takes one out ($WANT)"
sleep 0.8
read -r dx dy < <(at_of done)
printf 'mark save\n' >> "$R/subs.log"
ptr "$dx" "$dy"
wait_until 3 sh -c "sed -n '/^mark save\$/,\$p' '$R/subs.log' | grep -q '^apply .*\"quick.tiles\"'" \
  || fail "Done wrote no quick.tiles"
got=$(sed -n '/^mark save$/,$p' "$R/subs.log" | grep '^apply' | tail -1 | sed 's/^apply //' | jq -r '.[0].value | join(",")')
[ "$got" = "$WANT" ] || fail "Done wrote $got, not the edit's $WANT"
# The mock answers no apply: the edit stays, with the refusal; Escape drops it and the tiles are the setting's again.
sleep 0.8
grep -q 'quick-edit off' "$R/qs.log" && fail "a refused save left the edit mode"
wait_settled 1.5 0.4
timeout 20 grim "$OUT/edit-refused.png" || fail "grim failed"
press escape
wait_until 3 sh -c "grep -q 'quick-edit off' '$R/qs.log'" || fail "Escape did not leave the edit mode"
wait_until 3 sh -c "[ \"\$(grep -o 'quick-tiles .*' '$R/qs.log' | tail -1 | cut -d' ' -f2)\" = '$DEFAULT' ]" \
  || fail "after the refused save and Escape the centre does not show the setting's tiles: $(tiles_now)"
echo "ok: Done writes the edit's list ($got) as one apply; refused, the edit stays and says so; Escape puts the setting back"
# The setting changed elsewhere (Settings, the daemon): the centre follows it.
K act mock.doc "{\"doc\":\"config\",\"patch\":{\"values\":{\"quick.tiles\":{\"value\":$(jq -cn --arg l "$WANT" '$l | split(",")')}}}}" >/dev/null \
  || fail "mock.doc refused quick.tiles"
wait_until 3 sh -c "[ \"\$(grep -o 'quick-tiles .*' '$R/qs.log' | tail -1 | cut -d' ' -f2)\" = '$WANT' ]" \
  || fail "the centre did not follow quick.tiles: $(tiles_now)"
wait_settled 1.5 0.4
timeout 20 grim "$OUT/edited.png" || fail "grim failed"
close_all
echo "ok: the centre follows quick.tiles as the daemon has it ($WANT)"

# ---- 5. idle ----
mv_to "$AWAY_X" "$AWAY_Y"
wait_settled 3 0.6
commits() { grep -c 'wl_surface#[0-9]*\.commit(' "$R/qs.log" || true; }
c0=$(commits)
sleep 3
idle=$(( $(commits) - c0 ))
[ "$idle" = 0 ] || fail "idle: the shell committed $idle frames in 3 s with the control modules on the bar"
echo "ok: idle, the bar with the control modules commits 0 frames in 3 s"
if grep -E "qml|QML" "$R/qs.log" | grep -iE "error|TypeError|ReferenceError|Binding loop" | grep -v desktopentry | head -3 | grep -q .; then
  grep -E "qml|QML" "$R/qs.log" | grep -iE "error|TypeError|ReferenceError|Binding loop" | head -5 >&2
  fail "the frontend logged a QML error"
fi
echo "ok: the frontend logs no QML error"
echo "test-quick-modules: all checks passed"
