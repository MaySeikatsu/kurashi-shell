#!/usr/bin/env bash
# covers: crates/kurashi-mods crates/kurashi-launcher/src/commands.rs crates/kurashid/src/actions.rs
# The mod contract on the real daemon (K154, docs/MODS.md "Integration contract"), on nested niri: a declared action
# lists its typed arguments and its `>` command; the launcher's `>` mode offers it with the rest of the line as its
# argument and launching the row runs it; a bad argument is refused by name before the handler; the `mods` document
# carries a mod's icon and menu rows; a mod's own strings are in the `i18n` document.
#   nix develop -c frontend/test-mod-contract.sh
set -uo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
export KURASHI_NIRI_SB_NAME=${KURASHI_SB_PREFIX:-}modcontract
export KURASHI_NIRI_SB_OUT=${MODCONTRACT_OUT:-$ROOT/frontend/shots/mod-contract}
OUT=$KURASHI_NIRI_SB_OUT
SB="$ROOT/tools/bench/niri-sandbox.sh"
mkdir -p "$OUT"
fail() { echo "test-mod-contract: FAIL: $*" >&2; "$SB" stop >/dev/null 2>&1; exit 1; }
ok() { echo "test-mod-contract: ok: $*"; }
trap '"$SB" stop >/dev/null 2>&1' EXIT
. "$ROOT/frontend/test-lib.sh"

CFG=$OUT/config.toml
printf '[idle]\nenabled = false\n\n[mods]\nloaded = ["timer", "tasks"]\nenabled = ["timer", "tasks"]\n' > "$CFG"
"$SB" start "$CFG" > /dev/null || fail "the sandbox did not start"
K() { "$SB" act "$@"; }
raw() { K raw "$1" 2>&1 | head -1; }
doc() { raw "{\"t\":\"sub\",\"id\":\"s\",\"doc\":\"$1\"}"; }
has() { case "$1" in *"$2"*) return 0 ;; *) return 1 ;; esac; }

enabled() { has "$(doc mods)" '"id":"timer"' && has "$(raw '{"t":"query","id":"a","kind":"actions","q":"timer.start"}')" '"timer.start"'; }
wait_until 15 enabled || fail "the timer mod did not come up: $(doc mods | cut -c1-300)"

a=$(raw '{"t":"query","id":"a","kind":"actions","q":"timer.start"}')
has "$a" '"command":"timer"' && has "$a" '"schema"' && has "$a" '"mod":"timer"' && has "$a" '"args":"{minutes?, seconds?, label?}"' \
  || fail "the actions query does not carry timer.start's declaration: $a"
ok "a declared action lists its typed arguments, icon, command and mod"

q=$(raw '{"t":"query","id":"q","kind":"launcher","q":"> timer 5"}')
has "$q" 'cmd:timer.start' && has "$q" 'minutes' || fail "> timer 5 offers no row: $q"
has "$(raw '{"t":"query","id":"q","kind":"launcher","q":"> timer soon"}')" 'cmd:timer.start' && fail "> timer soon is offered though the words do not fit"
has "$(raw '{"t":"query","id":"q","kind":"launcher","q":"> pomodoro"}')" 'cmd:timer.pomodoro.start' || fail "> pomodoro offers no row"
ok "the launcher's > mode offers the declared commands, the rest of the line as the argument"

K act launcher.launch '{"id":"cmd:timer.start\t{\"minutes\":5}"}' > /dev/null 2>&1 || fail "launching the timer's row failed"
running() { has "$(doc mod.timer)" '"state":"running"'; }
wait_until 5 running || fail "no timer runs after > timer 5: $(doc mod.timer | cut -c1-300)"
ok "launching the row runs the action with its argument"

e=$(K act timer.start '{"minutes":0}' 2>&1)
has "$e" 'error.args.invalid: minutes' || fail "an argument out of range is not refused by name: $e"
ok "a bad argument is refused by name before the handler"

K act launcher.launch '{"id":"cmd:tasks.add\t{\"text\":\"buy milk\"}"}' > /dev/null 2>&1 || fail "launching the task's row failed"
task() { has "$(doc mod.tasks)" 'buy milk'; }
wait_until 5 task || fail "no task after > task buy milk: $(doc mod.tasks | cut -c1-300)"
ok "> task buy milk adds the task"

m=$(doc mods)
has "$m" '"icon":"timer"' && has "$m" '"at":"module"' || fail "the mods document lacks the timer's icon or menu rows: $(echo "$m" | cut -c1-400)"
ok "the mods document carries a mod's icon and its menu rows"

w=$( ( . "$OUT/niri-env.sh" 2>/dev/null; grep -E "is registered and not declared" "$XDG_RUNTIME_DIR/kurashid.log" 2>/dev/null | head -3 ) )
[ -z "$w" ] || fail "an action is registered and not declared: $w"
ok "every action the enabled mods register is declared"
echo "test-mod-contract: PASS"
