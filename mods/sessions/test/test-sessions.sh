#!/usr/bin/env bash
# The sessions mod on nested niri (W86, docs/ux/sessions.md "Definition of done"), invisibly (tools/bench/niri-sandbox.sh),
# with a stub noren (fixed `list` lines; every other call logged) and a stub terminal (`kitty`: logs its argv). The user's
# own noren is never run: `mods.sessions.command` names the stub by its absolute path.
#   1. the launcher lists the sessions (a name query, the state's icon, the folder as the second line);
#   2. Enter (launching the row) shows "Open in…" with In Kurashi, Terminal window and the stub terminal; shot;
#   3. the key 1 (In Kurashi) opens the drop-down with a new tab running `noren connect kurashi`;
#   4. the stub terminal gets `noren connect kurashi` as its argv; "Remember" stores the choice, the next open asks not;
#   5. save desk → the test window moved away and resized → restore puts it back (workspace, width); a closed one is
#      launched again from its command line; nothing is closed;
#   6. the sidebar section and the bar module (shots);
#   7. without noren: the mod is on, says why (document, launcher row, section; shot).
# Light and dark (SESSIONS_SCHEME=light|dark runs one).
#   nix develop -c mods/sessions/test/test-sessions.sh
set -uo pipefail
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
export KURASHI_NIRI_SB_NAME=${KURASHI_SB_PREFIX:-}w86sess
OUT=${SESSIONS_TEST_OUT:-${CARGO_TARGET_DIR:-$ROOT/target}/sessions-test}
export KURASHI_NIRI_SB_OUT=$OUT
SHOTS=$ROOT/mods/sessions/shots
mkdir -p "$OUT" "$SHOTS"
SB="$ROOT/tools/bench/niri-sandbox.sh"
fail() { echo "test-sessions: FAIL: $*" >&2; "$SB" log 30 >&2; exit 1; }
ok() { echo "test-sessions: ok: $*"; }
trap '"$SB" stop > /dev/null 2>&1' EXIT
command -v qs-terminal > /dev/null || fail "qs-terminal is not on PATH (nix develop provides it)"
command -v foot > /dev/null || fail "foot is needed for the test window"

K() { "$SB" act "$@"; }
doc() { K --json sub "${2:-mod.sessions}" --count 0 | tail -1 | python3 -c "import json,sys; d=json.loads(sys.stdin.readline()); d=d.get('data', d); print($1)"; }
doc_is() { [ "$(doc "$1" "${2:-mod.sessions}" 2>/dev/null)" = True ]; }
wait_until() { local n=$1; shift; for _ in $(seq $((n * 4))); do "$@" && return 0; sleep 0.25; done; return 1; }
has_layer() { "$SB" niri layers 2>/dev/null | grep -q "$1"; }
no_layer() { ! has_layer "$1"; }
file_has() { [ -f "$1" ] && grep -q -- "$2" "$1"; }
win() { "$SB" niri --json windows | python3 -c "import json,sys; w=[x for x in json.load(sys.stdin) if x.get('app_id') == 'kstest-desk']; print($1)"; }
win_is() { [ "$(win "$1" 2>/dev/null)" = True ]; }
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
row_id() { rows "$1" | python3 -c "import json,sys; r=[json.loads(l) for l in sys.stdin]; print(json.dumps({'id': next(x['id'] for x in r if x.get('mod') == 'sessions' and x.get('key') == '$2')}))"; }
shot() { cp "$("$SB" shot "$1" ${2:+"$2"} ${3:+"$3"})" "$SHOTS/$1.png"; }

# The stubs: noren and a terminal, on PATH for the daemon (the terminal) and named by path (noren).
BIN=$OUT/bin
LOG=$OUT/calls.log
PROJ=$OUT/proj/kurashi-shell
rm -rf "$BIN" "$OUT/proj"
mkdir -p "$BIN" "$PROJ" "$OUT/proj/docs"
cat > "$BIN/noren-stub" <<EOF
#!/bin/sh
echo "noren \$*" >> "$LOG"
case "\$1" in
list) printf 'zoxide\tdocs\t%s\tdir\t📁 docs\n' "$OUT/proj/docs"
      printf 'zellij\told\t%s\texited\t⊗ old\n' "$OUT/proj/gone"
      printf 'zellij\tkurashi\t%s\tlive\t▢ kurashi\n' "$PROJ" ;;
connect) echo "connected \$2"; sleep 2 ;;
esac
EOF
cat > "$BIN/kitty" <<EOF
#!/bin/sh
echo "kitty \$*" >> "$LOG"
EOF
chmod +x "$BIN/noren-stub" "$BIN/kitty"
export PATH="$BIN:$PATH"

magick -size 1920x1080 pattern:checkerboard -fill '#6a8caf' -colorize 40 "$OUT/wall.png"
CONF=$OUT/config.toml
conf() { # conf <scheme> <noren command>
cat > "$CONF" <<T
[idle]
enabled = false
[theme.colors]
scheme = "$1"
[theme.motion]
profile = "none"
[mods]
enabled = ["terminal", "sessions"]
[mods.terminal]
shell = "bash --norc --noprofile"
[mods.sessions]
command = "$2"
[edges.top]
start = ["workspaces"]
center = ["island"]
end = ["mod:sessions:sessions", "clock"]
[sidebar.right]
sections = ["mod:sessions:sessions"]
T
}

pass() { # pass <scheme>
local S=$1
rm -f "$LOG"
conf "$S" "$BIN/noren-stub"
"$SB" start "$CONF" "$OUT/wall.png" > /dev/null || fail "the sandbox did not start"
wait_until 20 doc_is "d.get('available') == True" || fail "mod.sessions never became available ($(doc 'd.get("noren")'))"
file_has "$LOG" "noren list all" || fail "noren list was not asked"

# 1. the launcher
R=$(rows kura) || fail "no launcher answer"
echo "$R" | python3 -c "
import json,sys
r=[json.loads(l) for l in sys.stdin if l.strip()]
k=[x for x in r if x.get('mod') == 'sessions']
assert k and k[0]['name'] == 'kurashi' and k[0]['generic'].endswith('proj/kurashi-shell') and k[0]['icon'] == 'play_arrow', k
" || fail "the launcher does not offer kurashi as the sessions' row ($R)"
rows old | grep -q '"generic": "Folder not found"' || fail "a missing folder's row does not say so ($(rows old))"
ok "$S: the launcher lists the sessions (name, folder, state icon); a missing folder says so"

# 2. Enter: the step
K act launcher.launch "$(row_id kura s:kurashi)" > /dev/null || fail "launching the row was refused"
wait_until 10 doc_is "d.get('choosing', {}).get('name') == 'kurashi'" || fail "no Open in… step"
wait_until 10 has_layer kurashi-sessions-chooser || fail "the step's card is not mapped"
[ "$(doc "[t['id'] for t in d['targets']][:2] + [t['id'] for t in d['targets'] if t['id'] == 'kitty']")" = "['kurashi', 'window', 'kitty']" ] \
  || fail "the targets are not In Kurashi, Terminal window and the stub terminal ($(doc "d['targets']"))"
sleep 0.6
shot "step-$S" "640,300 640x480" 1
ok "$S: Enter shows Open in… with In Kurashi, the window and the stub terminal"

# 3. In Kurashi (key 1)
"$SB" spawn wtype 1
wait_until 15 file_has "$LOG" "noren connect kurashi" || fail "the in-shell terminal did not run noren connect kurashi ($(cat "$LOG"))"
doc_is "d.get('dropdown', {}).get('open') == True" mod.terminal || fail "the drop-down is not out"
wait_until 5 no_layer kurashi-sessions-chooser || fail "the step stayed mapped"
doc_is "d.get('current', {}).get('name') == 'kurashi'" || fail "kurashi is not the current project"
sleep 1
shot "kurashi-$S"
ok "$S: In Kurashi: the drop-down came out, its new tab ran noren connect kurashi"
K act terminal.hide > /dev/null

# 4. the stub terminal, remembered
K act sessions.open '{"key":"s:kurashi"}' > /dev/null
wait_until 5 doc_is "'choosing' in d" || fail "no step the second time"
K act sessions.choose '{"via":"kitty","remember":true}' > /dev/null || fail "choosing kitty was refused"
wait_until 10 file_has "$LOG" "kitty $BIN/noren-stub connect kurashi" || fail "the stub terminal did not get noren connect kurashi ($(cat "$LOG"))"
wait_until 10 doc_is "any(e.get('open_in') == 'kitty' for e in d['entries'])" || fail "the choice was not remembered"
: > "$LOG.k"; grep -c '^kitty' "$LOG" > "$LOG.k"
K act sessions.open '{"key":"s:kurashi"}' > /dev/null
wait_until 10 [ "$(grep -c '^kitty' "$LOG")" -gt "$(cat "$LOG.k")" ] || fail "the remembered project still asked"
doc_is "'choosing' not in d" || fail "a remembered project showed the step"
K act sessions.forget "{\"project\":\"$PROJ\"}" > /dev/null
ok "$S: the stub terminal ran noren connect kurashi; Remember opened it there without asking"

# 4b. In Kurashi with the terminal mod off: never a silent nothing — the step comes back, In Kurashi grey with its reason
K act mod.disable '{"id":"terminal"}' > /dev/null || fail "the terminal mod did not turn off"
wait_until 10 doc_is "any(m['id'] == 'terminal' and m['state'] != 'enabled' for m in d['mods'])" mods || fail "the mods list still has the terminal on"
sleep 0.5
K act sessions.open '{"key":"s:kurashi","via":"kurashi"}' > /dev/null
wait_until 10 doc_is "d.get('choosing', {}).get('name') == 'kurashi' and d.get('notice', {}).get('key') == 'sessions.notice.mod_off'" \
  || fail "In Kurashi with the terminal off did not bring the step back ($(doc 'd.get("notice"), d.get("handoff"), d.get("choosing")'))"
wait_until 10 has_layer kurashi-sessions-chooser || fail "the step's card is not mapped (terminal off)"
sleep 0.6
shot "step-terminal-off-$S" "640,300 640x480" 1
K act sessions.cancel > /dev/null
K act mod.enable '{"id":"terminal"}' > /dev/null
ok "$S: In Kurashi with the terminal off brings the step back, the target grey with its reason"

# 5. the desk
"$SB" spawn foot -a kstest-desk sh -c 'sleep 300'
wait_until 10 win_is "len(w) == 1" || fail "the test window did not map"
WID=$(win "w[0]['id']"); WS=$(win "w[0]['workspace_id']"); WW=$(win "w[0]['layout']['window_size'][0]")
R=$(K act sessions.desk.save) || fail "save desk was refused"
wait_until 5 doc_is "d.get('desks', {}).get('$PROJ', {}).get('windows', 0) >= 1" || fail "the desk was not saved ($R)"
"$SB" niri action set-window-width --id "$WID" 400 > /dev/null
"$SB" niri action move-window-to-workspace --window-id "$WID" --focus false 3 > /dev/null
wait_until 5 win_is "w[0]['workspace_id'] != $WS" || fail "the test window did not move away"
K act sessions.desk.restore > /dev/null || fail "restore was refused"
wait_until 15 win_is "len(w) == 1 and w[0]['id'] == $WID and w[0]['workspace_id'] == $WS and abs(w[0]['layout']['window_size'][0] - $WW) <= 2" \
  || fail "restore did not put the window back (now $(win "[(x['workspace_id'], x['layout']['window_size']) for x in w]"), saved ws $WS width $WW)"
ok "$S: save desk, the window moved and resized, restore put it back"
"$SB" niri action close-window --id "$WID" > /dev/null
wait_until 5 win_is "len(w) == 0" || fail "the test window did not close"
K act sessions.desk.restore > /dev/null || fail "the second restore was refused"
wait_until 15 win_is "len(w) == 1 and w[0]['workspace_id'] == $WS" || fail "the missing window was not launched again"
wait_until 15 doc_is "d.get('notice', {}).get('key') == 'sessions.notice.restored'" || fail "the restore did not say it was done ($(doc 'd.get("notice")'))"
ok "$S: a closed window is launched again from its command line"

# 6. the glances
K act sidebar.toggle '{"side":"right"}' > /dev/null
sleep 1.5
shot "sidebar-$S" "1500,70 420x280" 2
K act sidebar.close > /dev/null
shot "bar-$S" "1400,0 520x40" 2
"$SB" stop > /dev/null

# 7. without noren (the user's own on PATH must not count: the setting names a path that is not there)
conf "$S" "/nonexistent/noren"
"$SB" start "$CONF" "$OUT/wall.png" > /dev/null || fail "the sandbox did not start (no noren)"
wait_until 20 doc_is "d.get('noren', {}).get('state') == 'missing'" || fail "without noren the document does not say so ($(doc 'd.get("noren")'))"
doc_is "d['available'] == False and d['noren']['reason'] == 'sessions.state.missing'" || fail "without noren: no reason"
rows noren | grep -q '"generic": "Sessions need noren' || fail "the launcher does not say noren is needed ($(rows noren))"
K act sidebar.toggle '{"side":"right"}' > /dev/null
sleep 1.5
shot "missing-$S" "1500,70 420x160" 2
ok "$S: without noren the mod is on and says why (document, launcher, section)"
"$SB" stop > /dev/null
}

case "${SESSIONS_SCHEME:-both}" in
  both) pass light; pass dark ;;
  *) pass "$SESSIONS_SCHEME" ;;
esac
echo "test-sessions: PASS (shots in mods/sessions/shots/)"
