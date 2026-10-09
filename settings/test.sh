#!/usr/bin/env bash
# Settings app test and screenshots (cards M5-settings, S-settings-polish, W9-config-profiles, W10-settings, W13-settings-ux).
# Runs ONLY in a headless sway sandbox with an isolated kurashid (own XDG dirs); never touches the real session or ~/.config.
#   settings/test.sh                        → exit 0 and settings/shots/*.png (English, then Japanese copy)
#   KURASHI_BIN_DIR=<dir> settings/test.sh  → take kurashid + kurashi from <dir>; no cargo build
# Needs: nix develop (qs, grim, sway, python3); kurashid + kurashi from KURASHI_BIN_DIR, or built with
# `cargo build -p kurashid -p kurashi`. KURASHI_RENDER_NODE picks the GPU (tools/bench/sandbox.sh).
#
# Coverage (UX brief docs/ux/settings.md, States and Definition of done). Shots: default, user, profile (after a profile
# load), Nix-forced and its chip's stack (managed.toml), inert (requires, overridden, mods off, restart pending, choice
# unavailable), invalid input (the refusal under the row), preview (palette, scheme, radius, font), undo after a CLI change,
# empty search, search landing on a row (flashed), mod states (available, loaded-off, on, refused, invalid, removed while
# on), the Changed view and its reset plan, profiles with their differ count, the Japanese copy of the main pages.
# Keyboard only (K1-K15): the sidebar and every page, a switch, a dropdown (type-ahead, Return, Up), the scheme, radius and
# font previews, search typed and landed on, the pick list's move buttons (focus follows the moved row), the Changed view's
# reset plan with Cancel and confirm, a mod switch that keeps its focus, invalid input refused.
# Not key-tested: Alt+Up/Down on the pick list and Escape. tools/bench/wl_keys.py has neither modifiers nor Escape, so Esc
# runs through the IPC hook `putBack` (the same path). Not shown: a mod's "running" line (no native mod with a service is
# built in), greyed dropdown offers (no offer is unavailable in this sandbox), export and import (CONTRACT-CHANGE 35).
set -euo pipefail
cd "$(dirname "$0")/.."
ROOT=$PWD
if ! command -v qs >/dev/null || ! command -v sway >/dev/null; then
  exec nix develop -c "$0" "$@"
fi
BIN=$(mktemp -d)
if [ -n "${KURASHI_BIN_DIR:-}" ]; then
  cp "$KURASHI_BIN_DIR/kurashid" "$KURASHI_BIN_DIR/kurashi" "$BIN/"
else
  export CARGO_TARGET_DIR=${CARGO_TARGET_DIR:-$HOME/.cache/kurashi-agents-target}
  # The target dir is shared with other agents' worktrees, so always rebuild (a no-op when current)
  # and snapshot the binaries right away; a bare `debug/kurashi` may belong to another branch.
  cargo build -q -p kurashid -p kurashi
  cp "$CARGO_TARGET_DIR/debug/kurashid" "$CARGO_TARGET_DIR/debug/kurashi" "$BIN/"
fi

NAME=${KURASHI_SB_NAME:-settings-$$}   # unique: concurrent runs must not stop each other's sway
envfile=$(mktemp)
tools/bench/sandbox.sh start "$NAME" > "$envfile"
# shellcheck disable=SC1090
. "$envfile"; rm -f "$envfile"
R=$XDG_RUNTIME_DIR                      # /tmp/kurashi-sb-<name>, the sandbox's own runtime dir
pids=()
kbd_pid=""
cleanup() {
  for p in "${pids[@]}"; do kill "$p" 2>/dev/null || true; done   # only PIDs started here
  tools/bench/sandbox.sh stop "$NAME" >/dev/null || true
  rm -rf "$BIN"
}
trap cleanup EXIT
fail() { echo "FAIL: $*"; exit 1; }

# --- isolated daemon state -------------------------------------------------------------------------
mkdir -p "$R/cfg/kurashi/profiles" "$R/state" "$R/data" "$R/cache" "$R/root/i18n/en" "$R/root/i18n/ja"
export XDG_CONFIG_HOME=$R/cfg XDG_STATE_HOME=$R/state XDG_DATA_HOME=$R/data XDG_CACHE_HOME=$R/cache
cat > "$R/cfg/kurashi/config.toml" <<'T'
schema_version = 1
[bar]
height = 40
[outputs."HEADLESS-1".bar]
height = 48
T
# Enforced nix layer (managed.toml, _managed.enforce): density is forced by Nix with no coupling, so its chip reads
# "Nix: programs.kurashi.settings.theme.density"; blur is also forced, by the compositor capability.
cat > "$R/cfg/kurashi/managed.toml" <<'T'
[_managed]
enforce = true
[theme]
density = "airy"
[theme.material]
blur = false
T
# A profile that sets density too: loading it shows "not applied: set by Nix" for density.
cat > "$R/cfg/kurashi/profiles/roomy.toml" <<'T'
[theme]
density = "compact"
[theme.shape]
radius_scale = 1.5
[a11y]
large_text = true
T
# Mods (docs/MODS.md): user mods live in $XDG_DATA_HOME/kurashi/mods/<id>/. A minimal mod, and a folder without
# mod.toml (shown as invalid).
mkdir -p "$R/data/kurashi/mods/demo-blur" "$R/data/kurashi/mods/broken-demo"
cat > "$R/data/kurashi/mods/demo-blur/mod.toml" <<'T'
id = "demo-blur"
name = "Demo blur"
version = "0.1.0"
tier = "native"
kurashi = ">=0.0.1"
provides = ["widget:demo-blur"]
capabilities = []
cost = "low"
T
# Data dir = the repo itself: i18n/ (incl. the generated schema catalog) and palettes/, exactly what the package installs.
export KURASHI_DATA_DIR=$ROOT

# The daemon's locale comes from LANG (kurashid i18n.rs); the Japanese pass starts it with ja_JP.UTF-8.
start_daemon() {
  LANG=${1:-C} "$BIN/kurashid" > "$R/kurashid.log" 2>&1 & daemon_pid=$!; pids+=("$daemon_pid")
  for _ in $(seq 50); do [ -S "$KURASHI_SOCKET" ] && break; sleep 0.1; done
  [ -S "$KURASHI_SOCKET" ] || { echo "kurashid did not start"; cat "$R/kurashid.log"; exit 1; }
}
start_daemon C
K() { "$BIN/kurashi" raw "$1"; }
# The value and the layer of a key, as the daemon says them (cfg.get).
val() { K "{\"t\":\"cfg.get\",\"id\":\"v\",\"key\":\"$1\"}" | python3 -c 'import json,sys; m=json.loads(sys.stdin.readline()); print(json.dumps(m["v"]["value"], ensure_ascii=False, separators=(",", ":")))'; }
src() { K "{\"t\":\"cfg.get\",\"id\":\"s\",\"key\":\"$1\"}" | python3 -c 'import json,sys; m=json.loads(sys.stdin.readline()); print(m["v"]["source"]["kind"])'; }

# History (K27): one change before Settings starts, so the daemon already has something to undo. The seed is an
# advanced, harmless key that no shot shows.
"$BIN/kurashi" set notifications.history_max 210 | grep '^applied' >/dev/null || fail "seed: kurashi set was not applied"

# Without KURASHI_SOCKET, as in a live session: the protocol default must be found. The deep link (UX brief, settings 4):
# KURASHI_SETTINGS_KEY opens that row at start.
start_qs() {
  env -u KURASHI_SOCKET KURASHI_SETTINGS_KEY="${1:-}" qs -p settings > "$R/settings.log" 2>&1 & qs_pid=$!; pids+=("$qs_pid")
}
Q() { qs -p settings ipc call settings "$@"; }
start_qs theme.colors.palette
for _ in $(seq 100); do Q current >/dev/null 2>&1 && break; sleep 0.2; done
Q current >/dev/null 2>&1 || { echo "settings app did not start"; cat "$R/settings.log"; exit 1; }
sleep 1.5

mkdir -p settings/shots
shot() { sleep 1; grim -o HEADLESS-1 "settings/shots/$1.png"; [ -s "settings/shots/$1.png" ]; }
# No settle delay: a search flash or a tooltip is only on screen for a moment.
shot_now() { grim -o HEADLESS-1 "settings/shots/$1.png"; [ -s "settings/shots/$1.png" ]; }

# 0. the deep link: the palette row's page opens by itself once the schema is in (the check is the page, the shot shows
#    the row in place; its flash is over after a second).
for _ in $(seq 50); do [ "$(Q current)" = appearance ] && break; sleep 0.2; done
[ "$(Q current)" = appearance ] || fail "deep link: KURASHI_SETTINGS_KEY did not open the palette's page ($(Q current); $(Q dbg))"
echo "deep link: KURASHI_SETTINGS_KEY=theme.colors.palette opened page appearance"
Q goto bar

# 0b. history (K27): the daemon's history is pushed with the config, so Undo is on as soon as Settings opens (the seed
#     above is the only change this daemon has seen). Redo is off: nothing was undone.
for _ in $(seq 50); do [ "$(Q undoState)" = "undo=on,redo=off" ] && break; sleep 0.2; done
[ "$(Q undoState)" = "undo=on,redo=off" ] || fail "history: Undo not on after opening ($(Q undoState))"
shot 0-undo-on-open

# 1. a user value: chip "you", with Reset on the same line (bar.height = 40 from config.toml)
shot 1-user-value

# 2. inert rows with reasons and their links: a11y override + the enforced (forced) blur value (Advanced on)
K '{"t":"apply","id":"a1","ops":[{"set":"a11y.reduce_transparency","value":true}]}' | grep -q applied || fail "a11y override not applied"
Q goto appearance
Q advanced true
shot 2-inert-reasons

# 2b. Nix-forced rows (managed.toml): search names the Nix option path in the chip, and the row says it is set by Nix
Q find density
shot 2b-nix-forced
[ "$(src theme.density)" = forced ] || [ "$(src theme.density)" = nix ] || fail "theme.density is not forced by Nix: $(src theme.density)"

# 2c. the search with nothing found names what it searched
Q find zzzz
shot 2c-empty-search
Q find ""
Q goto bar

# 3. a rejected value, shown inline under its row (goes through the same path as the controls)
Q set bar.height 500
shot 3-rejected

# 4. profiles: the header of the selected profile counts the differences (Show / Save / Revert), and the diff lists what
#    Nix holds (density): "not applied: set by Nix"
Q preview roomy
shot 4-profiles-preview

# 5. search: "blur" matches keys, labels and help on every page; each hit shows page › section › label
Q find blur
shot 5-search
Q find ""

# 6. Mods page: available (detected only, Load), then loaded and off, then on; the folder without mod.toml is refused
Q goto @mods
shot 6-mods-available
Q modLoad demo-blur
for _ in $(seq 20); do [ "$(Q navOrder | tr ',' '\n' | grep -c demo-blur)" -ge 1 ] && break; sleep 0.2; done
shot 6a-mods-loaded-off
Q mod demo-blur true
Q mod broken-demo true
shot 6-mods
[ -n "$(Q modRefusal broken-demo)" ] || fail "mods: the refusal under broken-demo is not shown"

# 7. a mod's page (K25, UX brief settings 5): on/off first, running line, capabilities and cost, "Adds" with its link
Q mod media true
Q goto mods.media
shot 7-mod-page
# 7b. B8: a change that went through elsewhere (the Media enable above) takes broken-demo's refusal line away
Q goto @mods
for _ in $(seq 15); do [ -z "$(Q modRefusal broken-demo)" ] && break; sleep 0.2; done
[ -z "$(Q modRefusal broken-demo)" ] || fail "mods: refusal survived a change elsewhere: $(Q modRefusal broken-demo)"
shot 7b-mods-after-change

# --- keyboard only from here: one virtual keyboard for the whole run (a keyboard that goes away drops focus) ----
mkfifo "$R/keys.fifo"
python3 -I tools/bench/wl_keys.py --serve < "$R/keys.fifo" & kbd_pid=$!; pids+=("$kbd_pid")
exec 3> "$R/keys.fifo"
kp() { for k in "$@"; do echo "$k" >&3; sleep 0.3; done; }
# Tab until the focused control is the name given (objectName, else accessible name), at most $2 presses (default 80).
tab_to() {
  local want=$1 max=${2:-80}
  for _ in $(seq "$max"); do
    [ "$(Q focused)" = "$want" ] && return 0
    echo tab >&3; sleep 0.25
  done
  fail "keyboard: Tab never reached $want ($(Q focused))"
}

# K1. Tab walks the window's focus order to the bar's "show bar" switch; Space flips it. The daemon confirms the flip,
#     and the shot shows the focus ring on that switch (outside the track, not on the ON fill).
Q goto bar
Q focusList >/dev/null
tab_to "toggle:bar.enabled"
[ "$(val bar.enabled)" = true ] || fail "keyboard: bar.enabled not on before the test"
kp space
[ "$(val bar.enabled)" = false ] || fail "keyboard: Space did not flip bar.enabled"
shot 8-keyboard-focus
echo "keyboard K1: Tab to toggle:bar.enabled, Space flipped it (inert rows of the bar now show their reason)"

# K2. the sidebar, keyboard only: Tab to the first entry, then Return opens each page in turn (every page, mods included)
Q goto bar
Q focusList >/dev/null
tab_to "Bar"
IFS=, read -ra nav <<< "$(Q navOrder)"
for id in "${nav[@]}"; do
  kp return
  [ "$(Q current)" = "$id" ] || fail "keyboard K2: Return on the sidebar did not open $id ($(Q current))"
  kp tab
done
echo "keyboard K2: every sidebar page opened with Tab and Return (${#nav[@]} entries)"
Q goto bar

# K3. the palette dropdown: Return opens it, Down previews the next palette, Return picks it (kept, one change)
Q goto appearance
Q focusList >/dev/null
tab_to "select:theme.colors.palette"
kp return down
[ "$(Q previewState)" = 'theme.colors.palette="kanso"' ] || fail "dropdown: Down did not preview kanso ($(Q previewState))"
kp return
[ "$(val theme.colors.palette)" = '"kanso"' ] || fail "dropdown: Return did not keep kanso ($(val theme.colors.palette))"
[ "$(Q previewState)" = none ] || fail "dropdown: the preview is still open after Return"
shot 14-palette-keyboard
echo "keyboard K3: palette Return, Down (preview), Return (kept): kanso"

# K4. the scheme switch: Right previews light (shot: Keep and Put back shown), then Esc (the same path as the IPC hook
#     putBack) puts dark back, and Redo stays off: the cancelled preview is not a redo step.
tab_to "switch:theme.colors.scheme"
kp right
[ "$(Q previewState)" = 'theme.colors.scheme="light"' ] || fail "preview: Right did not preview light ($(Q previewState))"
[ "$(val theme.colors.scheme)" = '"light"' ] || fail "preview: the shell does not show the previewed scheme"
shot 20-preview-scheme
Q putBack
[ "$(Q previewState)" = none ] || fail "preview: Put back did not end the preview"
[ "$(val theme.colors.scheme)" = '"dark"' ] || fail "preview: Put back did not restore dark ($(val theme.colors.scheme))"
[ "$(Q undoState)" = "undo=on,redo=off" ] || fail "preview: after Put back, Redo must be off ($(Q undoState))"
echo "keyboard K4: Right previewed light; Put back restored dark; Redo stayed off"

# K5. a preview moved several times and kept is ONE undo step: Undo takes back the scheme only, and the step before
#     (the bar switched off in K1) stays.
kp right left right return
[ "$(val theme.colors.scheme)" = '"light"' ] || fail "preview: the kept scheme is not light ($(val theme.colors.scheme))"
Q undo
[ "$(val theme.colors.scheme)" = '"dark"' ] || fail "preview: one Undo did not take back the whole preview ($(val theme.colors.scheme))"
[ "$(val bar.enabled)" = false ] || fail "preview: Undo took back more than the preview (bar.enabled)"
echo "keyboard K5: a moved-and-kept preview is one undo step"

# K6. the dropdown without preview: a letter opens it on the matching offer (type-ahead), nothing changes until Return
Q goto island
Q focusList >/dev/null
tab_to "select:island.main.default"
kp m
[ "$(val island.main.default)" = '"clock"' ] || fail "dropdown: type-ahead changed the value before Return"
kp return
[ "$(val island.main.default)" = '"media"' ] || fail "dropdown: Return did not pick the type-ahead offer ($(val island.main.default))"
kp return up return
[ "$(val island.main.default)" = '"clock"' ] || fail "dropdown: Up and Return did not restore clock ($(val island.main.default))"
echo "keyboard K6: type-ahead highlights, Return picks"

# K7. the pick list (vertical, UX brief settings 6): Tab into the first row, Tab to its move-down button, Return moves
#     it; focus follows the moved row, so Tab and Return move it back up.
Q goto island
Q focusList >/dev/null
tab_to "pickrow:clock"
kp tab return
[ "$(val island.main.faces)" = '["media","clock","notifications"]' ] || fail "pick list: move down did not reorder ($(val island.main.faces))"
kp tab return
[ "$(val island.main.faces)" = '["clock","media","notifications"]' ] || fail "pick list: moving back up did not reorder ($(val island.main.faces))"
echo "keyboard K7: pick list moved a row down and back up with its buttons"
shot 16-island-pick-list

# K8. Reset with its diff (UX brief settings 2): on the palette row (kanso, set by K3), Reset plans the change and lists
#     it; focus lands on Confirm reset; Return makes it one change.
Q goto appearance
Q focusList >/dev/null
tab_to "reset:theme.colors.palette"
kp return
shot 17b-reset-confirm
kp return
[ "$(src theme.colors.palette)" = default ] || fail "reset: confirming did not reset the palette ($(src theme.colors.palette))"
echo "keyboard K8: Reset showed the diff, Confirm reset went back to default"

# K9. invalid input (UX brief settings, States): an action binding typed as "foo" is refused; the text stays as typed
#     and the refusal shows under the row.
Q advanced true
Q goto island
Q focusList >/dev/null
tab_to "Left click"
# The field holds the binding it had: clear it with Backspace, then type text the daemon refuses. An action id is lowercase
# segments joined by dots (docs/ux/settings.md; registry.rs), so a space is refused; "foo" alone is a valid id.
for _ in $(seq 30); do echo backspace >&3; sleep 0.1; done
kp f o o space b a r
# Leaving the field commits what is typed (Enter does too; the harness lost an Enter that followed a space, so Tab is used).
kp tab
sleep 0.5
[ "$(val island.main.input.left)" = '"island.expand"' ] || fail "invalid input: the daemon kept a refused binding ($(val island.main.input.left))"
[ -n "$(Q rowError island.main.input.left)" ] || fail "invalid input: the row shows no refusal"
shot 22-invalid-input
echo "keyboard K9: 'foo bar' typed into Left click was refused and stays as typed"
Q advanced false

# K10. a slider previews too (UX brief, settings 3): Right moves the radius one step, shown but not kept; Put back
#      returns the value the preview started from.
Q goto appearance
Q advanced true
Q focusList >/dev/null
tab_to "slider:theme.shape.radius_scale"
radius0=$(val theme.shape.radius_scale)
kp right
[[ "$(Q previewState)" == theme.shape.radius_scale=* ]] || fail "radius: Right did not preview ($(Q previewState))"
shot_now 20b-preview-radius
Q putBack
[ "$(val theme.shape.radius_scale)" = "$radius0" ] || fail "radius: Put back did not restore $radius0 ($(val theme.shape.radius_scale))"
echo "keyboard K10: Right previewed the radius scale; Put back restored $radius0"

# K11. the font chain previews too: Delete on a family is a preview (Keep or Put back); Put back restores the chain.
fonts0=$(val theme.typography.family)
first=$(printf '%s' "$fonts0" | python3 -c 'import json,sys; print(json.load(sys.stdin)[0])')
Q goto appearance
Q focusList >/dev/null
tab_to "Remove $first" 120
kp delete
[[ "$(Q previewState)" == theme.typography.family=* ]] || fail "font: Delete did not preview ($(Q previewState))"
shot_now 20c-preview-font
Q putBack
[ "$(val theme.typography.family)" = "$fonts0" ] || fail "font: Put back did not restore the chain ($(val theme.typography.family))"
echo "keyboard K11: Delete on a font family previewed the chain; Put back restored it"

# K12. search by keyboard (UX brief, settings 4): typing starts the search, Return lands on the first hit, and the row
#      flashes; the shot is taken at once, inside the flash.
Q goto bar
Q focusList >/dev/null
kp p a l e t t e return
[ "$(Q current)" = appearance ] || fail "search: Return on 'palette' did not land on its page ($(Q current))"
[ "$(Q focused)" = "select:theme.colors.palette" ] || fail "search: the keyboard focus did not land on the row's control ($(Q focused))"
shot_now 5b-search-lands
echo "keyboard K12: typed 'palette', Return landed on the row (appearance)"

# K13. a provenance chip with focus shows every layer that sets its key (cfg.why); the Nix layer names its option path
#      (UX brief, settings 1). theme.density is forced by Nix (managed.toml).
Q goto appearance
Q focusList >/dev/null
tab_to "chip:theme.density" 120
shot 23-chip-stack
echo "keyboard K13: the Nix chip of theme.density shows its layers on focus"

# K14. Reset with its diff in the Changed view (UX brief, settings 2): the plan lists what would change; Cancel drops it
#      and changes nothing; a second plan and its confirm make the one change.
Q goto @changed
Q focusList >/dev/null
tab_to "reset:a11y.reduce_transparency" 120
kp return
tab_to "confirm:a11y.reduce_transparency" 4
shot 17d-changed-reset-plan
tab_to "cancel:a11y.reduce_transparency" 4
kp return
[ "$(val a11y.reduce_transparency)" = true ] || fail "changed: Cancel changed the value ($(val a11y.reduce_transparency))"
tab_to "reset:a11y.reduce_transparency" 4
kp return
tab_to "confirm:a11y.reduce_transparency" 4
kp return
[ "$(src a11y.reduce_transparency)" = default ] || fail "changed: confirm did not reset ($(src a11y.reduce_transparency))"
echo "keyboard K14: Changed view: Reset showed the diff, Cancel changed nothing, the confirm reset the key"

# K15. a switch that the daemon answers keeps the keyboard focus: the mods document changes, the row is updated in place.
Q goto @mods
Q focusList >/dev/null
tab_to "mod:demo-blur" 120
before=$(K '{"t":"cfg.get","id":"m2","key":"mods.enabled"}')
kp space
sleep 1
[ "$(Q focused)" = "mod:demo-blur" ] || fail "mods: focus left the switch after Space ($(Q focused))"
[[ "$(K '{"t":"cfg.get","id":"m2","key":"mods.enabled"}')" != "$before" ]] || fail "mods: Space did not change mods.enabled"
kp space
echo "keyboard K15: Space on the demo-blur switch changed it and the focus stayed on the switch"

# --- states by IPC (the same paths as the controls) ------------------------------------------------------------------
# 10. undo from the header (the same click as the button): the step is undone and Redo turns on
Q undo
for _ in $(seq 50); do [ "$(Q undoState)" = "undo=on,redo=on" ] && break; sleep 0.2; done
[ "$(Q undoState)" = "undo=on,redo=on" ] || fail "history: after Undo, expected undo=on,redo=on ($(Q undoState))"
shot 10-undo-redo

# 10b. undo after a change made from the CLI: the header's Undo follows config.history at once
"$BIN/kurashi" set bar.height 44 | grep -q '^applied' || fail "cli: set bar.height was not applied"
for _ in $(seq 50); do [ "$(Q undoState)" = "undo=on,redo=off" ] && break; sleep 0.2; done
[ "$(Q undoState)" = "undo=on,redo=off" ] || fail "history: CLI change not followed ($(Q undoState))"
Q goto bar
shot 10b-cli-change

# 11. mod pages (K25): media is loaded and off (nothing is on by default — K33 —, demo-blur on from step 6). The sidebar
#     places each mod page among the core pages by name; navOrder lists the entries the window built.
Q mod media false
for _ in $(seq 50); do [[ "$(K '{"t":"cfg.get","id":"m1","key":"mods.enabled"}')" != *media* ]] && break; sleep 0.2; done
[[ "$(K '{"t":"cfg.get","id":"m1","key":"mods.enabled"}')" != *media* ]] || fail "mods: media is still on after mod.disable"
want="bar,appearance,accessibility,mods.demo-blur,island,mods.media,notifications,launcher,@changed,@mods,@profiles"
for _ in $(seq 50); do [ "$(Q navOrder)" = "$want" ] && break; sleep 0.2; done
[ "$(Q navOrder)" = "$want" ] || fail "sidebar: order is $(Q navOrder), expected $want"
Q goto bar
shot 11-sidebar-mods

# 12. a mod's page (K25): its switch (off), the running line, and its settings, each with the reason they are not in effect
Q goto mods.media
shot 12-media-page

# 13. the Mods page: Load on the available rows, Remove from Settings and the switch on the loaded ones, the refusal and the
#     errors of the invalid one.
Q goto @mods
shot 13-mods-page

# 13b. the Changed view (UX brief settings 2): what differs from the defaults, by page, with the layer named
Q goto @changed
shot 17-changed-view

# 13c. a profile load: the profile names its settings (chip "roomy profile"), and Nix holds density
K '{"t":"act","id":"pl","action":"profile.load","args":{"name":"roomy"}}' | grep -q '"done"' || fail "profile.load failed"
for _ in $(seq 50); do [ "$(src a11y.large_text)" = "forced" ] || [ "$(src a11y.large_text)" = "profile" ] && break; sleep 0.2; done
Q goto @changed
shot 17c-profile-source

# 14b. a value the daemon keeps but no offer names (I9, K21): the dropdown shows the value as it is, the row says it has
#      no effect, and the row stays editable. Set through the same path as the controls.
Q goto appearance
Q set theme.colors.palette '"from-a-mod"'
for _ in $(seq 50); do
  case "$(K '{"t":"cfg.get","id":"k3","key":"theme.colors.palette"}')" in *from-a-mod*) break ;; esac
  sleep 0.2
done
case "$(K '{"t":"cfg.get","id":"k3","key":"theme.colors.palette"}')" in *from-a-mod*) ;; *) fail "dropdown: from-a-mod was not kept";; esac
shot 18-palette-unavailable
Q set theme.colors.palette '"wa-iro"'

# 15. the palette dropdown open (opened the way Enter opens it): the offers, the chosen one ticked and highlighted.
Q goto appearance
Q openChoice theme.colors.palette
shot 15-palette-dropdown
kp return

# 15c. an offer that is not available now: the island's default face offers the Media face while its mod is off, greyed
#      with its reason (the daemon says which). Return picks the highlighted offer, the value in effect: nothing changes.
Q goto island
Q openChoice island.main.default
shot 15c-dropdown-greyed-offer
kp return
[ "$(val island.main.default)" = '"clock"' ] || fail "dropdown: Return on the highlighted offer changed the default face ($(val island.main.default))"

# 15b. the restart line (UX brief, States: "restart pending"): a restart-flagged key saved, not in effect until the shell
#      restarts; the value goes back afterwards.
Q goto notifications
Q set notifications.server false
shot 21-restart-pending
Q set notifications.server true

# 15c. the empty and the searched-by-value states are above; the search that lands on the row and flashes it (step 5)
#      is the blur shot. Done with search.

# 19. a mod without settings (demo-blur, loaded and on): its page has the switch and the running line, and says there is
#     nothing to configure instead of "No settings match".
Q goto mods.demo-blur
shot 19-mod-no-settings

# 19b. a mod removed from disk while it is on (UX brief, States: "removed while on"): the page shows what the daemon
#      now reports, and nothing stays on screen that the daemon no longer has.
Q goto mods.demo-blur
rm -rf "$R/data/kurashi/mods/demo-blur"
sleep 2
shot 19b-mod-removed-while-on

# 9. profiles (K27): a profile file that appears while the Profiles page is open is listed by the same Settings process,
#    with no reconnect (the daemon pushes the list when the file appears).
Q goto @profiles
t0=$(date +%s%N)
printf '[bar]\nheight = 44\n' > "$R/cfg/kurashi/profiles/late.toml"
while [[ "$(Q profileNames)" != *late* ]]; do
  elapsed=$(( ($(date +%s%N) - t0) / 1000000 ))
  [ "$elapsed" -lt 5000 ] || fail "profiles: late.toml not listed within 5 s ($(Q profileNames))"
  sleep 0.1
done
echo "profiles: late.toml listed after $(( ($(date +%s%N) - t0) / 1000000 )) ms (IPC round trips included)"
shot 9-profiles-live
exec 3>&-
kbd_pid=""

# Japanese copy (UX brief: "ja copy lengths"): the same shell with the daemon's locale set to ja_JP.UTF-8.
kill "$qs_pid" "$daemon_pid" 2>/dev/null || true
sleep 0.5
start_daemon ja_JP.UTF-8
start_qs ""
for _ in $(seq 100); do Q goto appearance >/dev/null 2>&1 && break; sleep 0.2; done
sleep 1.5
Q goto appearance
shot ja-appearance
Q goto @changed
shot ja-changed
Q goto @profiles
Q preview roomy
shot ja-profiles
Q goto mods.media
shot ja-mod-page
Q goto @mods
shot ja-mods
Q find zzzz
shot ja-empty-search
Q find ""

# The QML log: no errors and no warnings from the settings process (the compositor's own notes are not ours).
if grep -aE 'ReferenceError|TypeError|is not a function|Cannot assign|Unable to assign|SyntaxError|Expected token|anchors' \
    "$R/settings.log" | sed 's/\x1b\[[0-9;]*m//g' | grep -q .; then
  grep -aE 'ReferenceError|TypeError|is not a function|Cannot assign|Unable to assign|SyntaxError|Expected token|anchors' \
    "$R/settings.log" | sed 's/\x1b\[[0-9;]*m//g' | head -20
  fail "QML errors in the settings log"
fi

echo "ok: settings/shots/"; ls settings/shots
