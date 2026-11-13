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
# W85 (the polish, docs/ux/terminal.md "As built (W85)"):
#  10. the tab row's menu (⌄): it is the shell's menu (TrayMenu, `kurashi-terminal-menu`), it takes the keyboard from the
#      terminal (`held`; the host's window lets go) — Down, Down, Enter opens a tab in the favourite — and gives it back;
#      the bar field's Tab on an empty field lists the favourites the same way, Enter opens one;
#  11. a refused folder is said in the notice strip (shot), `terminal.dismiss` puts it away; the last tab closed says the
#      shell exited (shot), a new one starts;
#  12. the looks (TERM_LOOKS: washi kami material by default, light and dark): the drop-down with the ANSI colours (the
#      theme's `term.*`), its menu, the notice, the card — shots `<what>-<look>-<scheme>`; with each look's own motion, a
#      burst of the drop-down going out and coming in: every frame in which the sheet stands at rest shows the text (the
#      still the place draws through the slide; no pop-in), bursts `burst-{in,out}-<look>-<scheme>`.
#   nix develop -c mods/terminal/test/test-terminal.sh   (TERM_PASSES="light dark looks" by default)
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
# 10. the tab row's menu: ⌄ at the row's end, left of the pin (the row stands 2 × 4 px under the well, keys 30 px).
read -r WX WY WW WH < <(doc "' '.join(str(d['rests']['dropdown'][k]) for k in ('x', 'y', 'width', 'height'))")
"$SB" click $((WX + WW - 49)) $((WY + WH + 23))
wait_until 5 has_layer kurashi-terminal-menu || { shot "nomenu-$S"; fail "the tab row's ⌄ opened no menu"; }
layers | grep -A1 '"kurashi-terminal-menu"' | grep -q exclusive || fail "the menu does not hold the keyboard"
wait_until 5 doc_is "d.get('held') == True" || fail "the terminal did not let go of the keyboard for its menu"
wait_until 5 bash -c "\"$SB\" niri layers 2>/dev/null | grep -A1 '\"kurashi-terminal\"' | grep -q none" \
  || fail "the host's window still holds the keyboard under the menu"
sleep 0.3
shot "menu-$S"
"$SB" spawn wtype -k Down -k Down -k Return
wait_until 5 doc_is "len(d['tabs']) == 2 and d['tabs'][1]['dir'] == '$FAV' and d['active'] == d['tabs'][1]['id']" \
  || fail "Down, Down, Enter in the menu opened no tab in the favourite ($(doc "d['tabs']"))"
wait_until 5 bash -c "! (\"$SB\" niri layers 2>/dev/null | grep -q kurashi-terminal-menu)" || fail "the menu stayed after a choice"
wait_until 5 doc_is "not d.get('held')" || fail "the menu did not give the keyboard back"
sleep 1
type_line "pwd > $OUT/menu.txt"
wait_until 10 file_has "$OUT/menu.txt" "$FAV" || fail "after the menu the keys did not reach the new tab ($(cat "$OUT/menu.txt" 2>/dev/null))"
"$SB" spawn wtype -M ctrl -M shift -k w -m shift -m ctrl
wait_until 5 doc_is "len(d['tabs']) == 1 and d['active'] == '$TAB'" || fail "Ctrl+Shift+W did not close the menu's tab"
ok "$S: the tab row's menu: keys walk it, Enter opens the favourite, the keyboard comes back to the terminal"
# A double click on the tab renames it in place (the row takes the keyboard: `held`), Return keeps the name.
# (one pointer for both presses: two `click` runs are too far apart for a double click)
(. "$OUT/sway-env.sh"; printf 'click %s %s left\nclick %s %s left\n' $((WX + 30)) $((WY + WH + 23)) $((WX + 30)) $((WY + WH + 23)) \
  | python3 -I "$ROOT/tools/bench/wl_pointer.py" --serve)
wait_until 5 doc_is "d.get('held') == True" || fail "a double click on the tab did not start its rename"
sleep 0.3
"$SB" spawn wtype -k BackSpace "w85name" -k Return
wait_until 5 doc_is "d['tabs'][0]['title'] == 'w85name' and d['tabs'][0].get('renamed') and not d.get('held')" \
  || fail "the rename did not stick or kept the keyboard ($(doc "d['tabs'], d.get('held')"))"
sleep 0.5
type_line "echo renamed > $OUT/rename.txt"
wait_until 10 file_has "$OUT/rename.txt" renamed || fail "after the rename the keys did not reach the terminal"
ok "$S: a double click renames the tab; the keyboard comes back"
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
# Tab on the empty field lists the favourite folders (TrayMenu under the field); Enter opens a tab in the first.
N0=$(doc "len(d['tabs'])")
K act terminal.hide > /dev/null
wait_until 10 bash -c "! (\"$SB\" niri layers 2>/dev/null | grep -q kurashi-terminal-away)" || fail "the drop-down did not go"
sleep 1
"$SB" click "$FX" 16
wait_until 5 has_layer kurashi-terminal-field || fail "the field did not open again"
sleep 0.3
"$SB" spawn wtype -k Tab
sleep 0.4
[ "$S" = light ] && shot "field-favourites-$S" "1300,0 620x200" 1
"$SB" spawn wtype -k Return
wait_until 10 doc_is "len(d['tabs']) == $N0 + 1 and d['tabs'][-1]['dir'] == '$FAV'" \
  || fail "Tab, Enter in the field opened no tab in the favourite ($(doc "d['tabs']"))"
wait_until 5 bash -c "! (\"$SB\" niri layers 2>/dev/null | grep -q kurashi-terminal-field)" || fail "the field stayed after a folder was chosen"
K act terminal.close_tab "{\"tab\":\"$(doc "d['tabs'][-1]['id']")\"}" > /dev/null
wait_until 5 doc_is "len(d['tabs']) == $N0" || fail "the field's folder tab did not close"
ok "$S: Tab on the empty field lists the favourites; Enter opens one"
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
sleep 0.4
shot "dropdown-tabs-$S"
K act terminal.dismiss > /dev/null || fail "terminal.dismiss refused"
wait_until 5 doc_is "'notice' not in d" || fail "the notice stayed after its dismissal"
ok "$S: the favourite opened a tab there (pwd), a missing folder is said in the strip and put away"

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

# 11b. the last shell exited: said in the well; a new one starts.
K set mods.terminal.place '"bar"' > /dev/null
wait_until 10 doc_is "'dropdown' in d.get('rests', {})" || fail "the drop-down did not come back to the bar"
for t in $(doc "' '.join(t['id'] for t in d['tabs'])"); do K act terminal.close_tab "{\"tab\":\"$t\"}" > /dev/null; done
wait_until 10 doc_is "len(d['tabs']) == 0" || fail "the tabs did not close ($(doc "d['tabs']"))"
sleep 0.5
shot "exited-$S"
K act terminal.new_tab > /dev/null
wait_until 10 doc_is "len(d['tabs']) == 1 and d['host']['state'] == 'ready'" || fail "a new shell did not start after the last exited"
ok "$S: the last shell exited is said; a new one starts"

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

# ---- 12. the looks: shots and bursts ----
# A frame's crop `geom` (WxH+X+Y) against the same crop of `ref`: RMSE (0 = the same).
rmse() { magick compare -metric RMSE <(magick "$1" -crop "$3" +repage png:-) <(magick "$2" -crop "$3" +repage png:-) null: 2>&1 \
  | sed -E 's/.*\(([0-9.e-]+)\).*/\1/'; }
# frames <prefix> <x,y wxh> <n> <gap> -- <cmd…>: n shots at scale 1, `gap` s apart, while cmd runs.
frames() {
  local p=$1 g=$2 n=$3 gap=$4; shift 5
  ( "$@" ) > /dev/null 2>&1 &
  for i in $(seq -w 1 "$n"); do sleep "$gap"; (. "$OUT/sway-env.sh"; timeout 5 grim -s 1 -g "$g" "$OUT/$p-$i.png"); done
  wait
}
lt() { python3 -c "import sys; sys.exit(0 if float(sys.argv[1]) < float(sys.argv[2]) else 1)" "$1" "$2"; }
# Every frame in which the sheet stands at rest (its tab row as in `ref`) shows the text (its first line as in `ref`).
at_rest_has_text() { # <prefix> <ref.png> <n> <row crop> <text crop>
  local p=$1 ref=$2 n=$3 rowc=$4 txtc=$5 bad=0 rest=0 f
  for f in "$OUT/$p"-*.png; do
    if lt "$(rmse "$f" "$ref" "$rowc")" 0.03; then
      rest=$((rest + 1))
      lt "$(rmse "$f" "$ref" "$txtc")" 0.06 || { bad=$((bad + 1)); echo "  $f: at rest, no text"; }
    fi
  done
  echo "  $p: $rest of $n frames at rest, $bad without the text"
  [ "$bad" -eq 0 ] && [ "$rest" -gt 0 ]
}
burst_strip() { # <prefix> <name>: the frames side by side into the shots
  local p=${1:?}
  magick "$OUT/$p"-*.png -resize 40% -background red -splice 3x0 +append "$SHOTS/$2.png"
  rm -f "${OUT:?}/$p"-*.png
}

looks() {
rm -f "$OUT"/*.txt
conf light bar icon
# (each look's own motion: the bursts need the slides)
sed -i '/^\[theme.motion\]$/,/^profile/d' "$CONF"
"$SB" start "$CONF" "$OUT/wall.png" > /dev/null || fail "the sandbox did not start"
wait_until 20 doc_is "d.get('available') == True" || fail "mod.terminal never came"
for L in ${TERM_LOOKS:-washi kami material}; do
  for S in light dark; do
    K set theme.style="$L" > /dev/null || fail "theme.style $L refused"
    K set theme.colors.scheme="$S" > /dev/null
    wait_until 10 doc_is "d.get('tokens', {}).get('term.color1') is not None" theme || fail "$L $S: the theme has no term.* tokens"
    sleep 1.5
    K act terminal.show > /dev/null
    wait_until 20 doc_is "'dropdown' in d.get('rests', {}) and d['host']['state'] == 'ready' and d['host'].get('shows') == 'dropdown'" \
      || fail "$L $S: the drop-down did not rest with its text"
    sleep 0.5
    type_line "clear; printf 'kurashi \\e[31mred \\e[32mgreen \\e[33myellow \\e[34mblue \\e[35mmagenta \\e[36mcyan \\e[90mgrey \\e[37msilver \\e[97mwhite \\e[30;47mblack\\e[0m $L $S\\n'; ls -la /"
    sleep 1.5
    shot "look-$L-$S"
    read -r WX WY WW WH < <(doc "' '.join(str(d['rests']['dropdown'][k]) for k in ('x', 'y', 'width', 'height'))")
    # the menu
    "$SB" click $((WX + WW - 49)) $((WY + WH + 23))
    wait_until 5 has_layer kurashi-terminal-menu || fail "$L $S: no menu"
    sleep 0.4
    shot "menu-$L-$S" "$((WX + WW - 420)),$((WY + WH - 40)) 440x320" 1
    "$SB" spawn wtype -k Escape
    wait_until 5 bash -c "! (\"$SB\" niri layers 2>/dev/null | grep -q kurashi-terminal-menu)" || fail "$L $S: Esc left the menu open"
    wait_until 5 doc_is "not d.get('held')" || fail "$L $S: Esc did not give the keyboard back"
    # the notice strip
    K act terminal.open_dir '{"path":"~/does-not-exist-w85"}' > /dev/null 2>&1
    sleep 0.5
    shot "notice-$L-$S" "$WX,$((WY + WH - 20)) ${WW}x70" 1
    K act terminal.dismiss > /dev/null
    # the bursts (the sheet's box: the well and the tab row under it)
    G="$WX,$WY ${WW}x$((WH + 40))"
    ROWC="120x24+0+$((WH + 10))"; TXTC="300x16+0+1"
    sleep 1
    (. "$OUT/sway-env.sh"; timeout 5 grim -s 1 -g "$G" "$OUT/ref-out.png")
    frames bo "$G" 10 0.02 -- "$SB" act act terminal.hide
    at_rest_has_text bo "$OUT/ref-out.png" 10 "$ROWC" "$TXTC" || { burst_strip bo "burst-out-$L-$S"; fail "$L $S: the text left before its sheet"; }
    burst_strip bo "burst-out-$L-$S"
    sleep 1
    frames bi "$G" 14 0.02 -- "$SB" act act terminal.show
    wait_until 10 doc_is "d['host'].get('shows') == 'dropdown'" || fail "$L $S: the text did not come back"
    sleep 0.5
    (. "$OUT/sway-env.sh"; timeout 5 grim -s 1 -g "$G" "$OUT/ref-in.png")
    at_rest_has_text bi "$OUT/ref-in.png" 14 "$ROWC" "$TXTC" || { burst_strip bi "burst-in-$L-$S"; fail "$L $S: the sheet came to rest before its text (pop-in)"; }
    burst_strip bi "burst-in-$L-$S"
    # the card
    K act terminal.hide > /dev/null
    sleep 1
    K act mod.panel.open '{"id":"terminal","panel":"terminal"}' > /dev/null
    wait_until 10 doc_is "d.get('host', {}).get('shows') == 'card'" || fail "$L $S: the card did not show the text"
    sleep 0.5
    shot "card-$L-$S" "960,0 960x560" 1
    read -r CX CY CW CH < <(doc "' '.join(str(d['rests']['card'][k]) for k in ('x', 'y', 'width', 'height'))")
    K act ui.close > /dev/null
    wait_until 10 doc_is "d.get('shown_in') != 'card'" || fail "$L $S: the card's place stayed"
    # the card again, in a burst (its still is there now): at rest, the text is there (its tab row 40 px over the well)
    sleep 1
    GC="$CX,$((CY - 40)) ${CW}x$((CH + 40))"
    frames ci "$GC" 14 0.02 -- "$SB" act act mod.panel.open '{"id":"terminal","panel":"terminal"}'
    wait_until 10 doc_is "d.get('host', {}).get('shows') == 'card'" || fail "$L $S: the card did not show the text again"
    sleep 0.5
    (. "$OUT/sway-env.sh"; timeout 5 grim -s 1 -g "$GC" "$OUT/ref-card.png")
    at_rest_has_text ci "$OUT/ref-card.png" 14 "100x22+0+4" "200x16+0+41" || { burst_strip ci "burst-card-$L-$S"; fail "$L $S: the card came to rest before its text"; }
    burst_strip ci "burst-card-$L-$S"
    K act ui.close > /dev/null
    wait_until 10 doc_is "d.get('shown_in') != 'card'" || fail "$L $S: the card's place stayed"
    ok "$L $S: shots, the menu, the notice, the card; the text comes and goes with its sheet"
  done
done
"$SB" stop > /dev/null
}

for P in ${TERM_PASSES:-${TERM_SCHEME:-light dark} looks}; do
  case "$P" in
    looks) looks ;;
    both) pass light; pass dark ;;
    *) pass "$P" ;;
  esac
done
echo "test-terminal: PASS (shots in mods/terminal/shots/)"
