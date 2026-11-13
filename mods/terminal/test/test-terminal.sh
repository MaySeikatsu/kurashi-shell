#!/usr/bin/env bash
# The terminal mod on nested niri (W83, docs/ux/terminal.md "Definition of done"), invisibly (tools/bench/niri-sandbox.sh):
#   1. `terminal.toggle` drops it out of the top bar's centre, joined to the bar; the host lays a prompt over the well;
#      typed `echo kurashi` runs (a file it writes, and the shot); shot dropdown-bar-<scheme>;
#   2. a second toggle hides it: the host's window is gone (no `kurashi-terminal` layer), the sheet too; a third brings
#      the same session back (the same tab, the same shell: its pid);
#   3. the bar's field (`bar_mode = input`): a click on it, `echo kurashi` + Enter → it runs in the session; the launcher's
#      run (`terminal.run`, what its `$` prefix sends) the same;
#   4. a favourite opens a tab there (`pwd` shows it); a missing folder is refused and said;
#   5. hovering the bar module opens its card at the module (`runtime.ui.panel`), the card shows the same session; closing
#      it keeps the session;
#   6. the sidebar section shows the same session; closing the sidebar keeps it;
#   7. `place = center` floats it; shot dropdown-center-<scheme>;
#   8. the host killed → the place says so (`host.crashed`), a press (`terminal.restart`) starts it again with a shell;
#   9. light and dark (TERM_SCHEME=dark runs the dark pass; both by default).
#   nix develop -c mods/terminal/test/test-terminal.sh
set -uo pipefail
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
export KURASHI_NIRI_SB_NAME=${KURASHI_SB_PREFIX:-}w83term
OUT=${TERMINAL_TEST_OUT:-${CARGO_TARGET_DIR:-$ROOT/target}/terminal-test}
export KURASHI_NIRI_SB_OUT=$OUT
SHOTS=$ROOT/mods/terminal/shots
mkdir -p "$OUT" "$SHOTS"
SB="$ROOT/tools/bench/niri-sandbox.sh"
R=/tmp/kurashi-sb-$KURASHI_NIRI_SB_NAME
fail() { echo "test-terminal: FAIL: $*" >&2; "$SB" log 30 >&2; exit 1; }
ok() { echo "test-terminal: ok: $*"; }
trap '"$SB" stop > /dev/null 2>&1' EXIT
command -v qs-terminal > /dev/null || fail "qs-terminal is not on PATH (nix develop provides it)"

K() { "$SB" act "$@"; }
doc() { K --json sub "${2:-mod.terminal}" --count 0 | tail -1 | python3 -c "import json,sys; d=json.loads(sys.stdin.readline()); d=d.get('data', d); print($1)"; }
doc_is() { [ "$(doc "$1" "${2:-mod.terminal}" 2>/dev/null)" = True ]; }
wait_until() { local n=$1; shift; for _ in $(seq $((n * 4))); do "$@" && return 0; sleep 0.25; done; return 1; }
layers() { "$SB" niri layers 2>/dev/null; }
has_layer() { layers | grep -q "$1"; }
type_line() { "$SB" spawn wtype "$1" -k Return; }
file_has() { [ -f "$1" ] && grep -q "$2" "$1"; }
# The launcher's rows for a query, as JSON lines (one request on the sandbox daemon's socket).
rows() {
  ( . "$OUT/niri-env.sh"; python3 -I -c '
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
' "$1" )
}
shot() { cp "$("$SB" shot "$1" ${2:+"$2"} ${3:+"$3"})" "$SHOTS/$1.png"; }

FAV=$OUT/fav
rm -rf "$FAV" "$OUT"/*.txt
mkdir -p "$FAV"
magick -size 1920x1080 pattern:checkerboard -fill '#6a8caf' -colorize 40 "$OUT/wall.png"
CONF=$OUT/config.toml
conf() { # conf <scheme> <place> <bar_mode>
cat > "$CONF" <<T
[idle]
enabled = false
[theme.colors]
scheme = "$1"
[theme.motion]
profile = "none"
[mods]
enabled = ["terminal"]
[mods.terminal]
shell = "bash --norc --noprofile"
place = "$2"
bar_mode = "$3"
favourites = [{ path = "$FAV", label = "fav" }]
[bar]
hover_card = ["mod:terminal:terminal"]
[edges.top]
start = ["workspaces"]
center = ["island"]
end = ["mod:terminal:terminal", "clock"]
[sidebar.right]
sections = ["mod:terminal:terminal"]
T
}

pass() { # pass <scheme>
local S=$1
rm -f "$OUT"/*.txt
conf "$S" bar icon
"$SB" start "$CONF" "$OUT/wall.png" > /dev/null || fail "the sandbox did not start"
wait_until 20 doc_is "d.get('available') == True" || fail "mod.terminal never came (is the mod linked?)"

# 1. out of the bar, a prompt, a typed line runs
K act terminal.toggle > /dev/null
wait_until 20 doc_is "d.get('shown_in') == 'dropdown' and 'dropdown' in d.get('rests', {}) and d['host']['state'] == 'ready'" \
  || fail "the drop-down never rested with the host ready ($(doc 'd.get(\"host\"), d.get(\"rests\")'))"
wait_until 10 has_layer kurashi-terminal-dropdown || fail "no drop-down sheet on niri"
wait_until 10 has_layer "kurashi-terminal\b" || fail "the host's window is not mapped"
TAB=$(doc "d['active']")
sleep 1
type_line "echo kurashi > $OUT/echo.txt; echo kurashi; echo \$\$ > $OUT/pid1.txt"
wait_until 10 file_has "$OUT/echo.txt" kurashi || fail "typed 'echo kurashi' did not run (the keyboard is not the terminal's)"
ok "$S: out of the bar, typed echo kurashi ran"
# The host's own variables never reach the shell (the scope token above all).
type_line "env | grep -c -E 'KURASHI_SCOPE|COLORSCHEMES_DIR|KB_LAYOUT_DIR|NIXPKGS_QT6_QML' > $OUT/scope.txt"
wait_until 10 file_has "$OUT/scope.txt" . || fail "the env check did not run"
[ "$(cat "$OUT/scope.txt")" = 0 ] || fail "the host's variables reached the shell ($(cat "$OUT/scope.txt") of them)"
ok "$S: the scope token and the host's paths are not in the shell's environment"
# Tabs by Yakuake's keys: Ctrl+Shift+T a new one, Ctrl+PgDown the next, Ctrl+Shift+W closes.
"$SB" spawn wtype -M ctrl -M shift -k t -m shift -m ctrl
wait_until 5 doc_is "len(d['tabs']) == 2 and d['active'] != '$TAB'" || fail "Ctrl+Shift+T made no tab ($(doc "d['tabs']"))"
sleep 0.5
"$SB" spawn wtype -M ctrl -k Next -m ctrl
wait_until 5 doc_is "d['active'] == '$TAB'" || fail "Ctrl+PgDown did not switch to the next tab"
"$SB" spawn wtype -M ctrl -k Next -m ctrl
wait_until 5 doc_is "d['active'] != '$TAB'" || fail "Ctrl+PgDown did not wrap"
"$SB" spawn wtype -M ctrl -M shift -k w -m shift -m ctrl
wait_until 5 doc_is "len(d['tabs']) == 1 and d['active'] == '$TAB'" || fail "Ctrl+Shift+W did not close the tab"
ok "$S: Ctrl+Shift+T, Ctrl+PgDown, Ctrl+Shift+W"
sleep 0.5
shot "dropdown-bar-$S"
# Kept out (hide_on_blur off): a click elsewhere gives the keyboard back, the terminal stays; on: it hides.
"$SB" click 960 900
wait_until 5 doc_is "d['dropdown']['open'] == True and not d.get('keys')" || fail "a click elsewhere did not give the keyboard back"
"$SB" niri layers | grep -A1 '"kurashi-terminal"' | grep -q on-demand || fail "the host still holds the keyboard exclusively"
K set mods.terminal.hide_on_blur true > /dev/null
K act terminal.toggle > /dev/null; K act terminal.toggle > /dev/null
wait_until 10 doc_is "d.get('keys') == True and 'dropdown' in d.get('rests', {})" || fail "the drop-down did not take the keyboard again"
"$SB" click 960 900
wait_until 5 doc_is "d['dropdown']['open'] == False" || fail "hide_on_blur: a click elsewhere did not hide it"
K act terminal.pin '{"on":true}' > /dev/null
K act terminal.toggle > /dev/null
wait_until 10 doc_is "d['settings']['pinned'] == True and d.get('keys') == True" || fail "terminal.pin did not keep it"
"$SB" click 960 900
wait_until 5 doc_is "d['dropdown']['open'] == True and not d.get('keys')" || fail "kept open, a click elsewhere hid it"
K act terminal.pin '{"on":false}' > /dev/null
K set mods.terminal.hide_on_blur false > /dev/null
ok "$S: a click elsewhere gives the keyboard back; hide_on_blur hides; kept open stays"
# The height per output (the grip's write).
OUTN=$(doc "d['rests']['dropdown']['output']")
H0=$(doc "d['rests']['dropdown']['height']")
K act terminal.resize "{\"output\":\"$OUTN\",\"height\":30}" > /dev/null
wait_until 10 doc_is "d['settings']['sizes'].get('$OUTN') == 30 and d['rests']['dropdown']['height'] < $H0" || fail "terminal.resize did not shrink it"
K act terminal.resize "{\"output\":\"$OUTN\"}" > /dev/null
ok "$S: the height per output"
K act terminal.toggle > /dev/null; K act terminal.toggle > /dev/null
wait_until 10 doc_is "d.get('keys') == True and 'dropdown' in d.get('rests', {})" || fail "the drop-down did not come back"

# 2. hidden: no window; shown again: the same session
K act terminal.toggle > /dev/null
wait_until 10 doc_is "d['dropdown']['open'] == False and 'dropdown' not in d.get('rests', {})" || fail "the toggle did not hide it"
wait_until 10 bash -c "! (\"$SB\" niri layers 2>/dev/null | grep -q kurashi-terminal)" || fail "a terminal window is still mapped while hidden"
K act terminal.toggle > /dev/null
wait_until 10 doc_is "d.get('shown_in') == 'dropdown' and 'dropdown' in d.get('rests', {})" || fail "the third toggle did not show it"
[ "$(doc "d['active']")" = "$TAB" ] || fail "the session changed across a hide ($TAB → $(doc "d['active']"))"
sleep 1
# The screen is still there (a window shrunk while hidden once came back blank): the well's first line has ink, its foot not.
read -r WX WY WW WH < <(doc "' '.join(str(d['rests']['dropdown'][k]) for k in ('x', 'y', 'width', 'height'))")
sd() { (. "$OUT/sway-env.sh"; timeout 8 grim -g "$1" -t png - | magick - -colorspace gray -format "%[fx:standard_deviation]" info:); }
TOP=$(sd "$WX,$((WY + 2)) ${WW}x22"); FOOT=$(sd "$WX,$((WY + WH - 40)) ${WW}x22")
python3 -c "import sys; sys.exit(0 if $TOP > 1.5 * $FOOT + 0.01 else 1)" || fail "the terminal came back blank after a hide (ink $TOP vs $FOOT)"
type_line "echo \$\$ > $OUT/pid2.txt"
wait_until 10 file_has "$OUT/pid2.txt" . || fail "the shown-again terminal does not take keys"
[ "$(cat "$OUT/pid1.txt")" = "$(cat "$OUT/pid2.txt")" ] || fail "a new shell after a hide ($(cat "$OUT/pid1.txt") → $(cat "$OUT/pid2.txt"))"
ok "$S: hidden = no window; the same shell after it"

# 3. the bar's field and the launcher's run
K set mods.terminal.bar_mode '"input"' > /dev/null || fail "bar_mode input refused"
K act terminal.hide > /dev/null
sleep 1.5
FX=$(python3 -c "print(1920 - 64 - 160)")
"$SB" click "$FX" 16
wait_until 5 has_layer kurashi-terminal-field || fail "a click on the bar's field opened no field"
sleep 0.3
type_line "echo kurashi > $OUT/field.txt"
wait_until 10 file_has "$OUT/field.txt" kurashi || fail "the bar's field did not run echo kurashi"
wait_until 10 doc_is "d['dropdown']['open'] == True" || fail "the field's run did not show the terminal (input_target = show)"
ok "$S: the bar's field ran echo kurashi and showed the terminal"
K act terminal.run "{\"text\":\"echo launcher > $OUT/launcher.txt\"}" > /dev/null || fail "terminal.run refused"
wait_until 10 file_has "$OUT/launcher.txt" launcher || fail "terminal.run (the launcher's prefix) did not run"
ok "$S: terminal.run (the launcher's prefix) ran"
K set mods.terminal.bar_mode '"icon"' > /dev/null
# The launcher (K150): `! echo kurashi` is the run prefix's row; launching it runs the line. "term" offers the terminal,
# "fav" the favourite folder.
ROW=$(rows "! echo kurashi > $OUT/prefix.txt" | python3 -c "import json,sys; r=[json.loads(l) for l in sys.stdin]; print(json.dumps({'id': next(x['id'] for x in r if x.get('key') == 'run')}))") \
  || fail "the launcher offers no run row for '! echo kurashi' ($(rows '! echo kurashi'))"
K act launcher.launch "$ROW" > /dev/null || fail "launching the run row was refused"
wait_until 10 file_has "$OUT/prefix.txt" kurashi || fail "the launcher's ! echo kurashi did not run"
rows term | grep -q '"modact:' || fail "the launcher offers no Terminal row for 'term'"
rows fav | grep -q '"key": "dir:' || fail "the launcher offers no favourite row for 'fav'"
ok "$S: the launcher's ! echo kurashi ran; term and fav offer the terminal and the folder"

# 4. a favourite, a missing folder
K act terminal.open_dir "{\"path\":\"$FAV\"}" > /dev/null || fail "open_dir refused"
wait_until 10 doc_is "len(d['tabs']) == 2 and d['tabs'][1]['dir'] == '$FAV'" || fail "the favourite opened no tab there"
sleep 1
type_line "pwd > $OUT/pwd.txt"
wait_until 10 file_has "$OUT/pwd.txt" "$FAV" || fail "pwd in the favourite's tab is not $FAV ($(cat "$OUT/pwd.txt" 2>/dev/null))"
K act terminal.open_dir '{"path":"~/does-not-exist-w83"}' > /dev/null 2>&1 && fail "a missing folder was accepted"
doc_is "d.get('notice', {}).get('key') == 'terminal.error.no_dir'" || fail "the missing folder is not said"
shot "dropdown-tabs-$S"
ok "$S: the favourite opened a tab there (pwd), a missing folder is said"

# 4b. the bar module's status: the program in the foreground of the active tab
K set mods.terminal.bar_mode '"status"' > /dev/null || fail "bar_mode status refused"
K act terminal.run '{"text":"sleep 6"}' > /dev/null
wait_until 8 doc_is "[t for t in d['tabs'] if t['id'] == d['active']][0].get('program') == 'sleep'" \
  || fail "the status does not name the running program ($(doc "d['tabs']"))"
shot "bar-status-$S" "1500,0 420x40" 2
K set mods.terminal.bar_mode '"icon"' > /dev/null
ok "$S: the bar's status names the running program"

# 5. the bar card on hover, the same session
K act terminal.hide > /dev/null
sleep 1
TABS=$(doc "[t['id'] for t in d['tabs']]")
# (the module stands left of the clock: its symbol at about 1816 on a 1920 px output)
MX=1816
"$SB" move 960 540; "$SB" move "$MX" 16
wait_until 10 doc_is "d.get('panel') == 'mod:terminal:terminal'" runtime.ui || { "$SB" shot nocard; fail "hovering the module opened no card"; }
wait_until 10 doc_is "d.get('shown_in') == 'card' and 'card' in d.get('rests', {})" || fail "the card did not show the terminal"
[ "$(doc "[t['id'] for t in d['tabs']]")" = "$TABS" ] || fail "the card has other sessions"
R0=$(doc "d['rests']['card']['x']")
[ "$R0" -gt 900 ] || fail "the card is not at the module (its well starts at x $R0)"
sleep 0.5
shot "card-$S"
K act ui.close > /dev/null
"$SB" move 960 540
wait_until 10 doc_is "d.get('shown_in') != 'card'" || fail "the card's place is still open after it closed"
[ "$(doc "[t['id'] for t in d['tabs']]")" = "$TABS" ] || fail "closing the card ended a session"
ok "$S: the card opens at the module on hover with the same sessions; closing it keeps them"

# 6. the sidebar section
K act sidebar.toggle '{"side":"right"}' > /dev/null
wait_until 10 doc_is "d.get('shown_in') == 'sidebar' and 'sidebar' in d.get('rests', {})" || fail "the sidebar section did not show the terminal"
sleep 0.5
shot "sidebar-$S"
K act sidebar.close > /dev/null
wait_until 10 doc_is "d.get('shown_in') != 'sidebar'" || fail "the sidebar's place is still open after it closed"
[ "$(doc "[t['id'] for t in d['tabs']]")" = "$TABS" ] || fail "closing the sidebar ended a session"
ok "$S: the sidebar section shows the same session; closing it keeps it"

# 7. floating in the centre
K set mods.terminal.place '"center"' > /dev/null
K act terminal.show > /dev/null
wait_until 10 doc_is "d.get('shown_in') == 'dropdown' and 'dropdown' in d.get('rests', {})" || fail "the centred drop-down did not rest"
RX=$(doc "d['rests']['dropdown']['y']")
[ "$RX" -gt 150 ] || fail "the centred drop-down is not floating (its well at y $RX)"
sleep 0.5
shot "dropdown-center-$S"
ok "$S: place = center floats it"
# A screen edge (Yakuake): the bottom one; and a position (bottom-right).
K set mods.terminal.place '"edge"' > /dev/null
K set mods.terminal.edge '"bottom"' > /dev/null
wait_until 10 doc_is "'dropdown' in d.get('rests', {}) and d['rests']['dropdown']['y'] > 400" || fail "place = edge (bottom) did not rest at the bottom"
sleep 0.5
shot "dropdown-edge-$S"
K set mods.terminal.place '"position"' > /dev/null
K set mods.terminal.anchor '"bottom-right"' > /dev/null
wait_until 10 doc_is "'dropdown' in d.get('rests', {}) and d['rests']['dropdown']['x'] > 600 and d['rests']['dropdown']['y'] > 400" \
  || fail "place = position (bottom-right) did not rest there ($(doc "d.get('rests')"))"
shot "dropdown-position-$S"
K set mods.terminal.place '"center"' > /dev/null
ok "$S: place = edge and position"

# 8. the host killed
HP=""
for p in $(pgrep -f "terminal/host/shell.qml"); do
  tr '\0' '\n' < "/proc/$p/environ" 2>/dev/null | grep -qx "XDG_RUNTIME_DIR=$R" && HP=$p
done
[ -n "$HP" ] || fail "no host process of this sandbox"
kill "$HP"
wait_until 20 doc_is "d['host'].get('crashed') == True" || fail "the host's death is not said ($(doc 'd[\"host\"]'))"
sleep 0.5
shot "crashed-$S"
K act terminal.restart > /dev/null
wait_until 20 doc_is "d['host']['state'] == 'ready' and len(d['tabs']) == 1 and not d['host'].get('crashed')" || fail "a restart did not bring a shell back"
ok "$S: the host killed is said, a press restarts it"
"$SB" stop > /dev/null
}

case "${TERM_SCHEME:-both}" in
  both) pass light; pass dark ;;
  *) pass "$TERM_SCHEME" ;;
esac
echo "test-terminal: PASS (shots in mods/terminal/shots/)"
