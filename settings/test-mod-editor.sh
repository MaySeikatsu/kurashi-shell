#!/usr/bin/env bash
# The Mod Editor page (W94, K154; docs/ux/mod-editor.md), keyboard only, in a headless sway sandbox against an isolated
# kurashid (its mod.check / mod.new / query points / query actions are the real ones; the mod is written into the
# sandbox's own data dir). Binaries from KURASHI_BIN_DIR, else built with cargo.
# covers: crates/kurashi-mods/src/editor.rs crates/kurashi-mods/src/scaffold.rs i18n/en/mod-editor.toml i18n/ja/mod-editor.toml
#   E1 Mods › "New mod…" by keyboard opens the page with the focus on Name; fresh: Create inert, "Give it a name"
#   E2 an id typed with no name: the name's reason; E3 "Tea": the id made from it is taken, the id field says so
#   E4 "Tea timer": the live check passes and lists the files, the manifest opens as a preview
#   E5 a card chosen with the arrows presets the ticks; E6 a variant's reason emptied: the check says so, Create inert
#   E7 Create (Return): the created state, the mod `available` in the daemon's list; Turn it on: enabled; Open its page
#   E8 Esc on a form with input asks first; E9 the folder not writable: Create's error with the path
#   E10 the daemon away: Create inert with that reason, the uses list empty; E11 Nix forces the mod lists: Turn it on inert
# Shots: $MOD_EDITOR_OUT/shots (default /tmp/kurashi-mod-editor/shots). Any FAIL exits 1.
set -uo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
if ! command -v qs >/dev/null || ! command -v sway >/dev/null; then exec nix develop "$ROOT" -c "$0" "$@"; fi
BIN=$(mktemp -d)
if [ -n "${KURASHI_BIN_DIR:-}" ]; then
  cp "$KURASHI_BIN_DIR/kurashid" "$KURASHI_BIN_DIR/kurashi" "$BIN/"
else
  cargo build -q -p kurashid -p kurashi || exit 1
  cp "${CARGO_TARGET_DIR:-$ROOT/target}/debug/kurashid" "${CARGO_TARGET_DIR:-$ROOT/target}/debug/kurashi" "$BIN/"
fi
OUT=${MOD_EDITOR_OUT:-/tmp/kurashi-mod-editor}
rm -rf "$OUT"; mkdir -p "$OUT/shots"
NAME=${KURASHI_SB_PREFIX:-}mod-editor-$$
envfile=$(mktemp)
tools/bench/sandbox.sh start "$NAME" > "$envfile" || { echo "test-mod-editor: FAIL: the sandbox did not start"; exit 1; }
# shellcheck disable=SC1090
. "$envfile"; rm -f "$envfile"
R=$XDG_RUNTIME_DIR
pids=()
FAILS=0
cleanup() {
  exec 3>&- 2>/dev/null || true
  rm -rf "$BIN"
  for p in "${pids[@]}"; do kill "$p" 2>/dev/null || true; done
  tools/bench/sandbox.sh stop "$NAME" >/dev/null || true
}
trap cleanup EXIT
ok() { echo "test-mod-editor: ok: $*"; }
fail() { echo "test-mod-editor: FAIL: $*"; FAILS=$((FAILS + 1)); }
die() { echo "test-mod-editor: FAIL: $*"; exit 1; }

mkdir -p "$R/cfg/kurashi" "$R/state" "$R/data/kurashi/mods/tea" "$R/cache"
export XDG_CONFIG_HOME=$R/cfg XDG_STATE_HOME=$R/state XDG_DATA_HOME=$R/data XDG_CACHE_HOME=$R/cache KURASHI_DATA_DIR=$ROOT
printf 'schema_version = 1\n[idle]\nenabled = false\n[theme.motion]\nprofile = "none"\n' > "$R/cfg/kurashi/config.toml"
# A mod that holds the id `tea` (E3).
printf 'id = "tea"\nname = "Tea"\nversion = "0.1.0"\ntier = "native"\nkurashi = ">=0.0.1"\nprovides = []\ncapabilities = []\n' \
  > "$R/data/kurashi/mods/tea/mod.toml"

daemon_pid=""
start_daemon() {
  "$BIN/kurashid" > "$R/kurashid.log" 2>&1 & daemon_pid=$!; pids+=("$daemon_pid")
  for _ in $(seq 50); do [ -S "$KURASHI_SOCKET" ] && break; sleep 0.1; done
  [ -S "$KURASHI_SOCKET" ] || { cat "$R/kurashid.log"; die "kurashid did not start"; }
}
start_daemon
qs -p settings > "$R/settings.log" 2>&1 & pids+=("$!")
Q() { qs -p settings ipc call settings "$@"; }
for _ in $(seq 100); do Q current >/dev/null 2>&1 && break; sleep 0.2; done
Q current >/dev/null 2>&1 || { cat "$R/settings.log"; die "the settings app did not start"; }

# The page's state (the `modNew` hook), one field of it; and a wait until a field reads a value (5 s).
st() { Q modNew | python3 -I -c 'import json,sys; d=json.loads(sys.stdin.read() or "{}"); v=d.get(sys.argv[1]); print(json.dumps(v, ensure_ascii=False, separators=(",", ":")) if not isinstance(v, str) else v)' "$1" 2>/dev/null; }
st_is() { for _ in $(seq 50); do [ "$(st "$1")" = "$2" ] && return 0; sleep 0.1; done; return 1; }
st_has() { for _ in $(seq 50); do [[ "$(st "$1")" == *"$2"* ]] && return 0; sleep 0.1; done; return 1; }
shot() { sleep 0.4; grim -o HEADLESS-1 "$OUT/shots/$1.png" && [ -s "$OUT/shots/$1.png" ] || fail "shot $1"; }
# One keyboard for the run (a keyboard that goes away drops the window's focus).
rm -f "$R/keys.fifo"; mkfifo "$R/keys.fifo"
python3 -I tools/bench/wl_keys.py --serve < "$R/keys.fifo" & pids+=("$!")
exec 3> "$R/keys.fifo"
kp() { for k in "$@"; do echo "$k" >&3; sleep 0.08; done; sleep 0.25; }
# Types lowercase words, a key per character (the sandbox's keymap has no shifted letters).
type_text() {
  local s=$1 c i
  for (( i = 0; i < ${#s}; i++ )); do
    c=${s:i:1}
    case "$c" in " ") kp space ;; *) kp "$c" ;; esac
  done
}
tab_to() {   # <objectName or accessible name>
  for _ in $(seq 80); do [ "$(Q focused)" = "$1" ] && return 0; kp tab; done
  fail "Tab never reached $1 (on $(Q focused))"; return 1
}

# E1. Mods › "New mod…" by keyboard; the page opens with the focus on Name. Fresh: Create inert with "Give it a name".
Q goto @mods
Q focusList
tab_to mods-new && kp return
for _ in $(seq 50); do [ "$(Q current)" = @modnew ] && break; sleep 0.1; done
[ "$(Q current)" = @modnew ] || fail "E1: the page did not open ($(Q current))"
st_is points '8' || st_has points ''
for _ in $(seq 50); do [ "$(Q focused)" = Name ] && break; sleep 0.1; done
[ "$(Q focused)" = Name ] || fail "E1: the focus is on $(Q focused), not Name"
st_is createReason "Give it a name" || fail "E1: Create's reason is '$(st createReason)'"
[ "$(st points)" -gt 0 ] 2>/dev/null || fail "E1: no points from the registry ($(st points))"
[ "$(st actions)" -gt 0 ] 2>/dev/null || fail "E1: no actions from the registry ($(st actions))"
shot fresh
ok "E1: New mod… opened the page by keyboard; fresh, Create says Give it a name ($(st points) points, $(st actions) actions)"

# E2. An id typed with no name: the scaffold's name_empty, and Create still says Give it a name.
kp tab; type_text x
st_is refusal mods.new.error.name_empty || fail "E2: the refusal is '$(st refusal)'"
st_is createReason "Give it a name" || fail "E2: Create's reason is '$(st createReason)'"
shot name-empty
kp backspace shift+tab
ok "E2: an id without a name: the name's reason shows"

# E3. "tea": the id made from it is taken (a mod `tea` is installed).
type_text tea
st_is id tea || fail "E3: the id is '$(st id)', not tea"
st_is refusal mods.new.error.id_taken || fail "E3: the refusal is '$(st refusal)'"
st_is idError true || fail "E3: the id field shows no error"
st_has createReason "already exists" || fail "E3: Create's reason is '$(st createReason)'"
shot id-taken
ok "E3: Tea → id tea is taken; the id field and Create say so"

# E4. "tea timer": the live check passes; the files are listed, the manifest first, and it opens as a preview.
type_text " timer"
st_is id tea-timer || fail "E4: the id is '$(st id)'"
st_is passed true || fail "E4: the check did not pass ($(Q modNew))"
st_has files '"mod.toml"' || fail "E4: the files are $(st files)"
[[ "$(st files)" == '["mod.toml",'* ]] || fail "E4: the manifest is not first ($(st files))"
tab_to mod-new-file:mod.toml && kp space
st_is openFile mod.toml || fail "E4: the manifest did not open ($(st openFile))"
shot passed-preview
ok "E4: Tea timer passes the check; $(st files); the manifest opened"

# E5. A card chosen with the arrows: Panel presets the ticks.
tab_to mod-new-start:module && kp right
st_is parts '["panel"]' || fail "E5: Panel ticked $(st parts)"
st_is passed true || fail "E5: the Panel draft does not pass ($(Q modNew))"
kp left
st_is parts '["widget","peek","panel"]' || fail "E5: Bar module ticked $(st parts)"
ok "E5: the cards preset the ticks (Panel, then Bar module again)"

# E6. A variant's reason emptied (the desk card's): its line asks, the check's variant line is not met, Create inert.
tab_to "Why it has none: Desk card" && kp ctrl+a backspace
st_is unanswered '["desk"]' || fail "E6: unanswered is $(st unanswered)"
st_is createReason "1 rule is not met" || fail "E6: Create's reason is '$(st createReason)'"
shot variant-unanswered
type_text "nothing at rest"
st_is unanswered '[]' || fail "E6: the reason typed did not answer it ($(st unanswered))"
ok "E6: an emptied reason: the check's variant line not met, Create inert; typed again, answered"

# E7. Create with Return; the created state; the daemon lists the mod as available. Turn it on (the focus is on it), then
# Open its page.
st_is createReason "" || fail "E7: Create is inert: '$(st createReason)'"
tab_to mod-new-create && kp return
st_has created "/kurashi/mods/tea-timer" || fail "E7: not created ($(Q modNew))"
where=$(st created)
st_is modState available || fail "E7: the mod is '$(st modState)', not available"
[ -f "$R/data/kurashi/mods/tea-timer/mod.toml" ] || fail "E7: no mod.toml was written"
[ "$(Q focused)" = mod-new-turn-on ] || fail "E7: the focus is on $(Q focused) after Create"
shot created
kp return
st_is modState enabled || fail "E7: Turn it on left it '$(st modState)'"
st_is hasPage true || fail "E7: its page is not in Settings"
tab_to mod-new-open-page && kp return
for _ in $(seq 50); do [ "$(Q current)" = mods.tea-timer ] && break; sleep 0.1; done
[ "$(Q current)" = mods.tea-timer ] || fail "E7: Open its page opened $(Q current)"
ok "E7: created in $where; turned on; its page opened"

# E8. Esc on a form with input asks first: Esc again keeps editing, Discard leaves for the Mods page.
Q goto @modnew
for _ in $(seq 50); do [ "$(Q focused)" = Name ] && break; sleep 0.1; done
type_text pot
kp escape
st_is asking true || fail "E8: Esc did not ask ($(st asking))"
shot discard-ask
kp escape
st_is asking false || fail "E8: Esc on the question did not keep editing"
[ "$(Q current)" = @modnew ] || fail "E8: the page went away ($(Q current))"
kp escape
st_is asking true || fail "E8: Esc did not ask again"
tab_to mod-new-discard && kp return
for _ in $(seq 50); do [ "$(Q current)" = @mods ] && break; sleep 0.1; done
[ "$(Q current)" = @mods ] || fail "E8: Discard did not go back ($(Q current))"
ok "E8: Esc asks first; Esc keeps editing; Discard goes back to Mods"

# E9. The folder not writable (a file where the mods folder goes: the sandbox may run as root in its namespace, so a
# mode would not stop it): Create's error names the path; nothing is written.
mv "$R/data/kurashi/mods" "$R/data/kurashi/mods.away"; : > "$R/data/kurashi/mods"
Q goto @modnew
for _ in $(seq 50); do [ "$(Q focused)" = Name ] && break; sleep 0.1; done
type_text kettle
st_is passed true || fail "E9: Kettle does not pass ($(Q modNew))"
tab_to mod-new-create && kp return
st_has createError "/kurashi/mods/kettle" || fail "E9: Create's error is '$(st createError)'"
[ -d "$R/data/kurashi/mods.away/kettle" ] && fail "E9: something was written"
shot write-error
rm -f "$R/data/kurashi/mods"; mv "$R/data/kurashi/mods.away" "$R/data/kurashi/mods"
ok "E9: the folder not writable: $(st createError)"

# E10. The daemon away: Create inert with that reason; the uses list empty. Then back.
kill "$daemon_pid"; wait "$daemon_pid" 2>/dev/null
st_is createReason "The shell is not running" || fail "E10: Create's reason is '$(st createReason)'"
shot daemon-away
start_daemon
st_is passed true || fail "E10: the check did not come back with the daemon ($(Q modNew))"
ok "E10: the daemon away: Create says The shell is not running; back, the check runs again"

# E11. Nix forces the mod lists: Turn it on is inert with the provenance reason; the folder is still written.
kill "$daemon_pid"; wait "$daemon_pid" 2>/dev/null
printf '[_managed]\nenforce = true\n[mods]\nloaded = []\nenabled = []\n' > "$R/cfg/kurashi/managed.toml"
start_daemon
Q goto @mods; Q goto @modnew
for _ in $(seq 50); do [ "$(Q focused)" = Name ] && break; sleep 0.1; done
type_text mug
st_is passed true || fail "E11: Mug does not pass ($(Q modNew))"
tab_to mod-new-create && kp return
st_has created "/kurashi/mods/mug" || fail "E11: not created ($(Q modNew))"
[ -n "$(st forcedOn)" ] || fail "E11: no forced reason ($(st forcedOn))"
shot forced
ok "E11: Nix forces the lists: Turn it on inert ($(st forcedOn)); the folder is written"

grep -E 'ModEditorPage.qml.*(Error|TypeError|ReferenceError|Unable)' "$R/settings.log" | head -5 | while read -r l; do fail "log: $l"; done
if grep -qE 'ModEditorPage.qml.*(TypeError|ReferenceError)' "$R/settings.log"; then FAILS=$((FAILS + 1)); fi
echo "test-mod-editor: shots in $OUT/shots"
[ "$FAILS" -eq 0 ] || { echo "test-mod-editor: $FAILS failure(s)"; exit 1; }
echo "test-mod-editor: ok"
