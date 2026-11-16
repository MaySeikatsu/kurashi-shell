#!/usr/bin/env bash
# covers: crates/kurashid/src/native crates/kurashi-mods/src/scaffold.rs
# A mod whose code is a program of its own (K155, W93; MODS.md "Host programs"), on nested niri with the real daemon:
# `kurashi mod new --host python` writes it; enabled, its document appears once something watches it; `> tea` runs its
# action and the document changes; the mods document names its program and Settings says so at its switch (shots,
# light and dark); a killed program comes back; disabling the mod stops it.
#   nix develop -c frontend/test-mod-host.sh
set -uo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
export KURASHI_NIRI_SB_NAME=${KURASHI_SB_PREFIX:-}modhost
export KURASHI_NIRI_SB_OUT=${MODHOST_OUT:-$ROOT/frontend/shots/mod-host}
OUT=$KURASHI_NIRI_SB_OUT
SB="$ROOT/tools/bench/niri-sandbox.sh"
BIN=${KURASHI_BIN_DIR:-${CARGO_TARGET_DIR:-$ROOT/target}/debug}
rm -rf "$OUT"; mkdir -p "$OUT/seed/kurashi/mods"
fail() { echo "test-mod-host: FAIL: $*" >&2; "$SB" stop >/dev/null 2>&1; exit 1; }
ok() { echo "test-mod-host: ok: $*"; }
trap '"$SB" stop >/dev/null 2>&1' EXIT
. "$ROOT/frontend/test-lib.sh"

# ---- the mod, as its author would make it ----
"$BIN/kurashi" mod new tea --name "Tea" --icon emoji_food_beverage --with widget,panel --host python \
  --dir "$OUT/seed/kurashi/mods" > "$OUT/new.log" 2>&1 || fail "kurashi mod new --host python failed: $(cat "$OUT/new.log")"
[ -x "$OUT/seed/kurashi/mods/tea/bin/tea-host" ] || fail "the program was not written executable"
"$BIN/kurashi" mod check "$OUT/seed/kurashi/mods/tea" > "$OUT/check.log" 2>&1 || fail "the written mod does not pass the check: $(cat "$OUT/check.log")"
ok "kurashi mod new --host python writes a mod that passes the check"

CFG=$OUT/config.toml
printf '[idle]\nenabled = false\n\n[mods]\nloaded = ["tea"]\nenabled = ["tea"]\n' > "$CFG"
export KURASHI_NIRI_SB_SEED=$OUT/seed
"$SB" start "$CFG" > /dev/null || fail "the sandbox did not start"
R=$( . "$OUT/niri-env.sh"; echo "$XDG_RUNTIME_DIR" )
# The program's processes: those of this sandbox whose command line names the mod's file.
host_pids() {
  for p in $(pgrep -f 'kurashi/mods/tea/bin/tea-host' || true); do
    { tr '\0' '\n' < "/proc/$p/environ"; } 2>/dev/null | grep -qx "XDG_RUNTIME_DIR=$R" && echo "$p"
  done
}

on() { has "$(doc mods)" '"id":"tea"' && has "$(doc mods)" '"state":"enabled"'; }
wait_until 15 on || fail "the tea mod did not come up: $(doc mods | cut -c1-400)"
m=$(doc mods)
has "$m" '"hosts":[{' && has "$m" '"exec":"tea-host"' || fail "the mods document does not name the mod's program: $(echo "$m" | cut -c1-400)"
ok "a mod with no crate is enabled, and the mods document names its program"

# Watched, the program runs and the document is its own (each read is a subscriber; the program lingers between them).
served() { has "$(doc mod.tea)" '"available":true'; }
wait_until 15 served || fail "the program did not publish mod.tea: $(doc mod.tea) / $(tail -5 "$R/xdg/state/kurashi/tea/host-main.log" 2>/dev/null)"
has "$(doc mod.tea)" '"pokes":0' || fail "the document is not the program's: $(doc mod.tea)"
ok "its document appears once something watches it"

q=$(raw '{"t":"query","id":"q","kind":"launcher","q":"> tea"}')
has "$q" 'cmd:tea.poke' || fail "> tea offers no row: $q"
K act launcher.launch '{"id":"cmd:tea.poke"}' > /dev/null 2>&1 || fail "launching the row failed"
poked() { has "$(doc mod.tea)" '"pokes":1'; }
wait_until 5 poked || fail "the document did not change after > tea: $(doc mod.tea)"
ok "> tea runs the program's action and the document changes"

# Settings says so where the mod is switched on (looked at by the lead: shots, light and dark).
K act settings.open '{"page":"mod:tea"}' > /dev/null 2>&1 || fail "Settings did not open on the mod's page"
sleep 4
"$SB" shot settings-tea-light > /dev/null
K set theme.colors.scheme dark > /dev/null; sleep 2
"$SB" shot settings-tea-dark > /dev/null
K set theme.colors.scheme light > /dev/null
ok "shots: $OUT/shots/settings-tea-{light,dark}.png"

# Killed, it is started again (once) and serves again.
pid=$(host_pids | head -1)
[ -n "$pid" ] || fail "no program of the mod runs in the sandbox"
kill "$pid"
back() { p=$(host_pids | head -1); [ -n "$p" ] && [ "$p" != "$pid" ] && has "$(doc mod.tea)" '"available":true'; }
wait_until 15 back || fail "the program did not come back after it was killed: $(doc mod.tea)"
ok "a killed program is started again and publishes again"

K act mod.disable '{"id":"tea"}' > /dev/null 2>&1 || fail "mod.disable failed"
gone() { [ -z "$(host_pids)" ]; }
wait_until 10 gone || fail "the program still runs after the mod was switched off"
has "$(K act tea.poke 2>&1)" 'unknown_action' || fail "the action is still there after the mod was switched off"
ok "switching the mod off stops its program and takes its action away"
echo "test-mod-host: PASS"
