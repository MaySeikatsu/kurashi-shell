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
# on), the Changed view and its reset plan, profiles with their differ count, the profile overlay (B13: your change
# replaced, the changes kept, Nix holds back), a profile line whose value stays (I64: "Now from this profile"), a user value
# that a forced layer holds back (I64: "Not in effect"), export and import with their review and refusal (keyboard), the
# Japanese copy of the main pages, and the records list of the test mod `records` (K38, W17, I81): empty, two entries, the
# add form, a refusal at its field (an empty id, sent by keyboard), the add form filled in by keyboard (an address with `:`
# and `/`) and saved, a reorder by Alt+Down and Alt+Up and one with the row's buttons, Down and Up between the entries, Enter
# to edit and Escape back to the entry, Delete, a removal with the row's buttons, the edit form opened and closed by keyboard,
# a list pinned by Nix (read-only), and its Japanese page. W24 (K48 (5), K49): the pages' sections as cards in order
# (power, desktop, a search), and the theme export status under its row: foot's file, its missing include line, Copy by
# keyboard (the clipboard holds the line, or the row says it could not copy without wl-copy).
# W29 (K53): the Appearance page's Style, Look and Palette blocks, their categories (each opened once, shots in
# settings/shots/appearance/), the "differs from the style" line and its Reset (undo, redo), style cards that reset the
# user's appearance values and keep the rest, a look over the style (the palette stays), dark kept by a style, None.
# Keyboard only (K1-K15): the sidebar and every page, a switch, a dropdown (type-ahead, Return, Up), the scheme, radius and
# font previews, search typed and landed on, the pick list's move buttons (focus follows the moved row) and Alt+Down/Alt+Up,
# the Changed view's reset plan with Cancel and confirm, a mod switch that keeps its focus, invalid input refused.
# K4 puts a preview back through the IPC hook `putBack`; P3 presses Escape on the import review. Not shown: a mod's "running"
# line (no native mod with a service is built in), greyed dropdown offers (no offer is unavailable in this sandbox), the
# loading line of a profile read (too quick for a shot).
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
  rm -rf "$BIN"   # before the sandbox stops: its netjoin preload refuses every later external command (exit 111)
  for p in "${pids[@]}"; do kill "$p" 2>/dev/null || true; done   # only PIDs started here
  tools/bench/sandbox.sh stop "$NAME" >/dev/null || true
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
# A records list pinned by Nix (K38, W17): forced, read-only, its chip names this layer; the test mod `records` shows it.
[mods.records]
locked = [{ id = "nix", title = "Set by Nix", target = "https://nix.example" }]
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
# The records test mod (K38, W17): the repo's test data, copied in so the daemon discovers it like a user mod.
mkdir -p "$R/data/kurashi/mods/records"
cp "$ROOT/crates/kurashid/tests/data/mods/records/mod.toml" "$R/data/kurashi/mods/records/mod.toml"
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

# A. Appearance as Style · Look · Palette (W29, K53; docs/ux/looks.md "Settings"). A fresh config: the style is washi.
mkdir -p settings/shots/appearance
ashot() { sleep 1; grim -o HEADLESS-1 "settings/shots/appearance/$1.png"; [ -s "settings/shots/appearance/$1.png" ]; }
ap() { Q appearance | python3 -c 'import json,sys; a=json.loads(sys.stdin.read()); print(a[sys.argv[1]] if isinstance(a[sys.argv[1]], str) else ",".join(a[sys.argv[1]]))' "$1"; }
wait_ap() { for _ in $(seq 50); do [ "$(ap "$1")" = "$2" ] && return 0; sleep 0.2; done; fail "appearance: $1 is $(ap "$1"), expected $2"; }
wait_differs() {   # "" = hidden, else a substring of the line
  for _ in $(seq 50); do
    if [ -z "$1" ]; then [ -z "$(Q differs)" ] && return 0; else [[ "$(Q differs)" == *"$1"* ]] && return 0; fi
    sleep 0.2
  done
  fail "appearance: the differs line is '$(Q differs)', expected '${1:-hidden}'"
}
Q goto appearance
wait_ap style washi
[ "$(ap look)" = washi ] && [ "$(ap palette)" = wa-iro ] || fail "appearance: washi's look and palette are not in effect ($(Q appearance))"
# A1. three blocks in order — Style, Look, Palette — before the detail sections; the light/dark switch sits with the palette.
for _ in $(seq 25); do [[ "$(Q sections)" == block:theme.style,block:theme.look,block:theme.colors.palette,appearance.* ]] && break; sleep 0.2; done
[[ "$(Q sections)" == block:theme.style,block:theme.look,block:theme.colors.palette,appearance.* ]] || fail "appearance: the page does not open with the three blocks ($(Q sections))"
wait_differs ""
[ "$(src theme.colors.palette)" = theme ] || fail "appearance: the palette is not the style's ($(src theme.colors.palette))"
Q scrollTo block:theme.style
ashot washi-page
# A2. categories: only those with packs, the current pack's open; each opened once (style and look).
[ "$(Q categories theme.style)" = "modern,inspired,retro,fiction" ] || fail "appearance: style categories $(Q categories theme.style)"
[ "$(Q openCategory theme.style)" = inspired ] || fail "appearance: washi's category is not open ($(Q openCategory theme.style))"
for row in theme.style theme.look; do
  IFS=, read -ra cats <<< "$(Q categories $row)"
  for c in "${cats[@]}"; do
    Q category "$row" "$c"
    [ "$(Q openCategory $row)" = "$c" ] || fail "appearance: $row did not open $c"
    Q scrollTo "block:$row"
    ashot "${row#theme.}-$c"
  done
done
echo "appearance A1-A2: Style, Look, Palette blocks; categories $(Q categories theme.style) each opened"
# A3. changed from the style: two appearance values of yours (and a contrast, which is not the style's) → the line names
#     them; Reset to Washi takes them away (one undo step: Undo brings them back, Redo removes them again).
K '{"t":"apply","id":"ap1","ops":[{"set":"theme.chrome","value":"keycap"},{"set":"theme.shape.corners","value":"none"},{"set":"theme.colors.contrast","value":"medium"}]}' | grep -q applied || fail "appearance: the user's values were refused"
wait_differs "2 settings differ from Washi: Chrome, Corners"
Q scrollTo block:theme.style
ashot differs
Q resetToStyle
wait_differs ""
[ "$(src theme.chrome)" = theme ] || fail "appearance: Reset to Washi kept the user's chrome ($(src theme.chrome))"
[ "$(val theme.colors.contrast)" = '"medium"' ] || fail "appearance: Reset to Washi took the contrast too"
Q undo
wait_differs "Chrome"
K '{"t":"redo","id":"rd"}' | grep -q applied || fail "appearance: redo of the reset was refused"
wait_differs ""
echo "appearance A3: the differs line came with chrome and corners, Reset to Washi took it away (undo, redo)"
# A4. a style card: earlier appearance values of yours are gone, the contrast stays; its category opens.
K '{"t":"apply","id":"ap2","ops":[{"set":"theme.chrome","value":"soft"}]}' | grep -q applied || fail "appearance: chrome refused"
wait_differs "Chrome"
Q pick theme.style '"sekai"'
wait_ap style sekai
[ "$(src theme.chrome)" != user ] || fail "appearance: applying sekai kept the user's chrome"
[ "$(val theme.colors.contrast)" = '"medium"' ] || fail "appearance: applying sekai reset the contrast"
wait_differs ""
Q scrollTo block:theme.style
ashot sekai-page
Q pick theme.style '"win95"'
wait_ap style win95
[ "$(Q openCategory theme.style)" = retro ] || fail "appearance: win95's category is not open ($(Q openCategory theme.style))"
Q scrollTo block:theme.style
ashot win95-page
# A5. a look over the style: theme.look is yours, the style's palette stays; the line names the look.
Q pick theme.look '"sekai"'
wait_ap look sekai
[ "$(src theme.look)" = user ] || fail "appearance: the look picked is not the user's ($(src theme.look))"
[ "$(ap palette)" = win95 ] && [ "$(src theme.colors.palette)" = theme ] || fail "appearance: the style's palette did not stay ($(ap palette), $(src theme.colors.palette))"
wait_differs "1 setting differs from Win95: Look"
Q scrollTo block:theme.style
ashot look-over-style
# A6. light or dark follows a style (K55): dark set by you, applying the style again sets the style's light.
K '{"t":"apply","id":"ap3","ops":[{"set":"theme.colors.scheme","value":"dark"}]}' | grep -q applied || fail "appearance: dark refused"
Q resetToStyle
wait_differs ""
[ "$(val theme.colors.scheme)" = '"light"' ] && [ "$(src theme.colors.scheme)" = theme ] || fail "appearance: the style did not take light or dark over ($(val theme.colors.scheme), $(src theme.colors.scheme))"
Q scrollTo block:theme.colors.palette
ashot palette-dark
echo "appearance A4-A6: sekai and win95 applied by card (chrome reset, contrast kept), a look over the style, the style's light"
# A7. None (your own): only the style changes. Back to the baseline the steps below expect (no style, defaults).
Q pick theme.style '"none"'
wait_ap style none
K '{"t":"apply","id":"ap4","ops":[{"reset":"theme.colors.scheme"},{"reset":"theme.colors.contrast"}]}' | grep -q applied || fail "appearance: baseline reset refused"
wait_ap look kanso
Q goto bar

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
# The enable is answered once the mod runs; any change that goes through clears the refusal lines (B8), so the refused
# enable is sent after that answer, not raced against it.
for _ in $(seq 25); do [[ "$(K '{"t":"cfg.get","id":"m0","key":"mods.enabled"}')" == *demo-blur* ]] && break; sleep 0.2; done
sleep 0.5
Q mod broken-demo true
for _ in $(seq 25); do [ -n "$(Q modRefusal broken-demo)" ] && break; sleep 0.2; done
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
# Waits (up to 5 s) for the focus to land on the name given: a move or a save changes the rows first, and the focus follows
# that change a moment later.
focus_on() {
  local want=$1
  for _ in $(seq 25); do [ "$(Q focused)" = "$want" ] && return 0; sleep 0.2; done
  return 1
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

# K3. the palette as preview cards (K45, I104; it was a dropdown): one Tab stop, the chosen card; Down previews the next
#     palette, Return keeps it (one change)
Q goto appearance
Q focusList >/dev/null
tab_to "cards:theme.colors.palette"
kp down
[ "$(Q previewState)" = 'theme.colors.palette="kanso"' ] || fail "palette cards: Down did not preview kanso ($(Q previewState))"
kp return
[ "$(val theme.colors.palette)" = '"kanso"' ] || fail "palette cards: Return did not keep kanso ($(val theme.colors.palette))"
[ "$(Q previewState)" = none ] || fail "palette cards: the preview is still open after Return"
shot 14-palette-keyboard
echo "keyboard K3: palette cards Down (preview), Return (kept): kanso"

# K3b. the category chips (W29): one Tab stop (the open chip), Right moves to the next, Return opens it, Tab goes on into
#      its cards; an arrow in the style cards moves the focus only (applying a style resets settings: it is never a preview).
Q goto appearance
Q focusList >/dev/null
tab_to "category:modern"
kp right return
[ "$(Q openCategory theme.style)" = inspired ] || fail "chips: Right and Return did not open inspired ($(Q openCategory theme.style))"
kp tab
[ "$(Q focused)" = "cards:theme.style" ] || fail "chips: Tab did not go into the cards ($(Q focused))"
kp right
[ "$(val theme.style)" = '"none"' ] || fail "chips: an arrow in the style cards applied a style ($(val theme.style))"
[ "$(Q previewState)" = none ] || fail "chips: an arrow in the style cards opened a preview"
echo "keyboard K3b: chips Right+Return opened inspired, Tab into its cards, an arrow there changed nothing"

# K4. the scheme's pills (K55: auto, wallpaper, dark, light): Right previews wallpaper (shot: Keep and Put back shown),
#     then Esc (the same path as the IPC hook putBack) puts auto back, and Redo stays off: the cancelled preview is not a
#     redo step.
tab_to "Follow the system"   # the first pill (auto), named by its label
kp right
[ "$(Q previewState)" = 'theme.colors.scheme="wallpaper"' ] || fail "preview: Right did not preview wallpaper ($(Q previewState))"
[ "$(val theme.colors.scheme)" = '"wallpaper"' ] || fail "preview: the shell does not show the previewed scheme"
shot 20-preview-scheme
Q putBack
[ "$(Q previewState)" = none ] || fail "preview: Put back did not end the preview"
[ "$(val theme.colors.scheme)" = '"auto"' ] || fail "preview: Put back did not restore auto ($(val theme.colors.scheme))"
[ "$(Q undoState)" = "undo=on,redo=off" ] || fail "preview: after Put back, Redo must be off ($(Q undoState))"
echo "keyboard K4: Right previewed wallpaper; Put back restored auto; Redo stayed off"

# K5. a preview moved several times and kept is ONE undo step: Undo takes back the scheme only, and the step before
#     (the bar switched off in K1) stays.
kp right left right return
[ "$(val theme.colors.scheme)" = '"dark"' ] || fail "preview: the kept scheme is not dark ($(val theme.colors.scheme))"
Q undo
[ "$(val theme.colors.scheme)" = '"auto"' ] || fail "preview: one Undo did not take back the whole preview ($(val theme.colors.scheme))"
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

# K7b. the same pick list by the keyboard's move keys (W18, I81): Alt+Down moves the focused row below the next one, and
#      Alt+Up moves it back. The focus stays on the row.
Q goto island
Q focusList >/dev/null
tab_to "pickrow:clock"
kp alt+down
for _ in $(seq 20); do [ "$(val island.main.faces)" = '["media","clock","notifications"]' ] && break; sleep 0.2; done
[ "$(val island.main.faces)" = '["media","clock","notifications"]' ] || fail "pick list: Alt+Down did not move the row ($(val island.main.faces))"
focus_on "pickrow:clock" || fail "pick list: the focus did not follow the moved row ($(Q focused))"
kp alt+up
for _ in $(seq 20); do [ "$(val island.main.faces)" = '["clock","media","notifications"]' ] && break; sleep 0.2; done
[ "$(val island.main.faces)" = '["clock","media","notifications"]' ] || fail "pick list: Alt+Up did not move the row back ($(val island.main.faces))"
echo "keyboard K7b: Alt+Down and Alt+Up moved the first pick-list row down and back up"

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
[ "$(Q focused)" = "cards:theme.colors.palette" ] || fail "search: the keyboard focus did not land on the row's control ($(Q focused))"
shot_now 5b-search-lands
echo "keyboard K12: typed 'palette' (the Style and Look name palettes in their help: the row named so wins), Return landed on the row (appearance)"

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
want="bar,appearance,accessibility,mods.demo-blur,island,mods.media,notifications,launcher,desktop,power,dock,sidebar,@changed,@mods,@profiles"
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

# 13c. a profile load: the profile names its settings (chip "roomy profile"), and Nix holds density. Before the load the user
#      sets density too: Nix enforces it, so the value is inert, and the load keeps it (K36); the Changed view lists it as held
#      back, with "Not in effect" and the value in effect (I64 (3)).
K '{"t":"apply","id":"hb1","ops":[{"set":"theme.density","value":"compact"}]}' | grep -q applied || fail "held: the user's density was refused"
K '{"t":"act","id":"pl","action":"profile.load","args":{"name":"roomy"}}' | grep -q '"done"' || fail "profile.load failed"
for _ in $(seq 50); do [ "$(src a11y.large_text)" = "forced" ] || [ "$(src a11y.large_text)" = "profile" ] && break; sleep 0.2; done
# The overlay (B13, UX brief settings 6): roomy does not name the history size, so the user's 210 survives the load.
[ "$(val notifications.history_max)" = 210 ] || fail "overlay: the user's history size did not survive a profile that does not set it ($(val notifications.history_max))"
[ "$(src theme.density)" = forced ] || [ "$(src theme.density)" = nix ] || fail "held: Nix does not hold density ($(src theme.density))"
for _ in $(seq 50); do [ "$(Q held theme.density)" = '"compact"' ] && break; sleep 0.2; done
[ "$(Q held theme.density)" = '"compact"' ] || fail "held: the Changed view does not hold the user's compact back ($(Q held theme.density))"
Q goto @changed
shot 17c-profile-source

# 13d. the review of a load after the user changed a key the profile sets: the user's value is replaced ("your change
#      replaced"), the changes the profile does not name stay (kept), and Nix holds density back (not applied).
Q set theme.shape.radius_scale 0.8
Q preview roomy
pv=$(K '{"t":"act","id":"pv","action":"profile.preview","args":{"name":"roomy"}}')
echo "$pv" | python3 -c 'import json,sys
m = json.loads(sys.stdin.readline()); d = m["data"]
r = [e for e in d["diff"] if e["key"] == "theme.shape.radius_scale"]
assert r and r[0]["before"]["source"]["kind"] == "user", r
assert d["kept_user"] >= 2, d
assert any(h["key"] == "theme.density" for h in d["not_applied"]), d' || fail "overlay: the review does not replace the user value or keep the others: $pv"
shot 4b-profile-overlay
echo "overlay B13: the review replaces radius_scale (your change), keeps the other changes, and holds density back"

# 13d2. I64 (2): a value of yours that the profile sets to the same value (large_text: roomy turns it on). The review marks it
#       as the same value, listed under "Same value, now set by this profile" with the neutral "Now from this profile" chip,
#       and not as a change that replaces yours.
K '{"t":"apply","id":"sv1","ops":[{"set":"a11y.large_text","value":true}]}' | grep -q applied || fail "same value: large_text was not set by the user"
Q preview roomy
pv2=$(K '{"t":"act","id":"pv2","action":"profile.preview","args":{"name":"roomy"}}')
echo "$pv2" | python3 -c 'import json,sys
m = json.loads(sys.stdin.readline()); d = m["data"]
r = [e for e in d["diff"] if e["key"] == "a11y.large_text"]
assert r and r[0].get("same_value") is True and r[0]["before"]["source"]["kind"] == "user", r' || fail "same value: the review does not mark large_text as the same value: $pv2"
shot 4c-profile-same-value
K '{"t":"apply","id":"sv2","ops":[{"reset":"a11y.large_text"}]}' | grep -q applied || fail "same value: the user's large_text was not removed"
echo "I64 (2): the review marks the user's large_text as the same value, shown with Now from this profile"

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

# 15. the palette's offers (preview cards now, K45/I104; the dropdown they replaced has no open state): every offer, the
#     chosen one ticked and framed. The dropdown's open state is 15c's.
Q jump theme.colors.palette
shot 15-palette-dropdown

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

# P0. a profile of this machine to export: "mine" saves the current settings, so it holds this output's bar height, which
#     export leaves out (per output, UX brief settings 6). Saved through the same action as the Save button.
K '{"t":"act","id":"sv","action":"profile.save","args":{"name":"mine"}}' | grep -q '"done"' || fail "profile.save mine failed"
for _ in $(seq 50); do [[ "$(Q profileNames)" == *mine* ]] && break; sleep 0.2; done
[[ "$(Q profileNames)" == *mine* ]] || fail "profiles: mine is not listed ($(Q profileNames))"

# P1. export, by keyboard: Tab to Export and Return writes mine.toml to the export folder, and the result lists what
#     stayed on this machine and why.
Q goto @profiles
Q preview mine
Q focusList >/dev/null
tab_to "profile-export" 120
kp return
for _ in $(seq 50); do [ -s "$R/data/kurashi/exports/mine.toml" ] && break; sleep 0.2; done
[ -s "$R/data/kurashi/exports/mine.toml" ] || fail "export: no mine.toml in the export folder"
grep -q 'height' "$R/data/kurashi/exports/mine.toml" || fail "export: the file holds no settings"
shot 24-export-result
echo "keyboard P1: Tab to Export and Return wrote the export folder's mine.toml"

# P2. import error (UX brief, settings: error states), by keyboard: from Export, Tab reaches the import field. A name the
#     export folder does not hold is refused in place with its code; no review opens and the field keeps its text.
kp tab
kp n o p e
kp return
sleep 1
[ "$(Q focused)" = "Import file" ] || fail "import: focus left the field after a refused name ($(Q focused))"
shot 25-import-error
echo "keyboard P2: a file name the export folder does not hold is refused in place"

# P3. import review, by keyboard: a file name the folder holds opens the review with Apply focused; Esc cancels it, nothing
#     changes, and the field takes the focus back. The export is imported under another name: a file named like a saved
#     profile is refused (row 101, `profile_name_taken`) — B31 was this test importing mine.toml back as "mine".
cp "$R/data/kurashi/exports/mine.toml" "$R/data/kurashi/exports/theirs.toml"
for _ in $(seq 8); do echo backspace >&3; sleep 0.1; done
kp t h e i r s
kp return
sleep 1
[ "$(Q focused)" = "profile-apply" ] || fail "import review: Apply does not hold the focus ($(Q focused))"
shot 26-import-review
kp escape
sleep 0.5
[ "$(Q focused)" = "Import file" ] || fail "import review: Esc did not cancel back to the field ($(Q focused))"
echo "keyboard P3: Return reviewed theirs.toml with Apply focused; Esc cancelled the review"

# P4. Apply, by keyboard: Return on the field reviews again, Return on Apply loads the file as one undoable change. Its
#     profile names history size, so the user's 210 is replaced by its value (source: profile).
kp return
sleep 1
[ "$(Q focused)" = "profile-apply" ] || fail "import review: the second review does not hold Apply ($(Q focused))"
kp return
for _ in $(seq 30); do [ "$(Q focused)" = "Import file" ] && break; sleep 0.2; done
[ "$(Q focused)" = "Import file" ] || fail "import: focus did not return to the field after Apply ($(Q focused))"
[ "$(src notifications.history_max)" = profile ] || fail "import: Apply did not load theirs ($(src notifications.history_max))"
shot 27-import-applied
echo "keyboard P4: Apply loaded theirs.toml as one change; the focus is back on the field"

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

# 10. records (K38, W17): a list of records, one row each, named by its title. The test mod `records` has `pins` (the user's
#     list: the rows are set here, the add form is typed into by keyboard) and `locked` (pinned by Nix, forced). It is turned
#     on as any mod is (Mods page, K15).
Q modLoad records
for _ in $(seq 20); do [ "$(Q navOrder | tr ',' '\n' | grep -c records)" -ge 1 ] && break; sleep 0.2; done
Q mod records true
Q goto mods.records
shot records-empty
"$BIN/kurashi" set mods.records.pins '[{"id":"home","title":"Home","target":"https://example.org"},{"id":"docs","title":"Docs","target":"mod:webdock:docs","view":"mobile"}]' | grep '^applied' >/dev/null || fail "records: the two entries were not applied"
for _ in $(seq 20); do [[ "$(val mods.records.pins)" == *Docs* ]] && break; sleep 0.2; done
[[ "$(val mods.records.pins)" == *'"keep":false'* ]] || fail "records: the absent fields were not filled in ($(val mods.records.pins))"
shot records-two
echo "records: two entries in effect, every declared field present (absent ones took their defaults)"
# R1. the add form by keyboard: Tab to "Add entry" (the pins list's), Return opens it with the focus in its first field.
#     Return with the id empty is refused at that field (the first problem of the new entry); the form stays open.
Q goto mods.records
Q focusList >/dev/null
tab_to "recordadd" 150
kp return
sleep 1
shot records-add
kp return
sleep 1
shot records-field-error
[ "$(python3 -I -c 'import json,sys; print(len(json.loads(sys.argv[1])))' "$(val mods.records.pins)")" = 2 ] || fail "records: a refused entry was stored"
echo "keyboard R1: Tab to Add entry, Return opened the form, the empty id was refused at its field"
kp escape
sleep 0.5
# R5. the add form, end to end by keyboard (I81): an id, a title and an address typed key by key (":" and "/" are keys of
#     their own in wl_keys.py). Enter saves the form; the new entry is the last one, and the focus goes to it.
Q goto mods.records
Q focusList >/dev/null
tab_to "recordadd" 150
kp return
for _ in $(seq 20); do [ "$(Q focused)" = "Id" ] && break; sleep 0.2; done
[ "$(Q focused)" = "Id" ] || fail "records: Add entry did not open the form in its first field ($(Q focused))"
kp e x a m p l e tab e x a m p l e tab h t t p s : / / e x a m p l e . o r g /
kp return
for _ in $(seq 30); do [[ "$(val mods.records.pins)" == *'"id":"example"'* ]] && break; sleep 0.2; done
[ "$(python3 -I -c 'import json,sys; p=json.loads(sys.argv[1]); print(len(p), p[-1]["id"], p[-1]["target"])' "$(val mods.records.pins)")" = "3 example https://example.org/" ] || fail "records: the add form did not store the typed entry ($(val mods.records.pins))"
for _ in $(seq 20); do [ "$(Q focused)" = "recordrow:2" ] && break; sleep 0.2; done
[ "$(Q focused)" = "recordrow:2" ] || fail "records: the focus did not go to the saved entry ($(Q focused))"
shot records-added
echo "keyboard R5: Add entry, the id, title and address typed by keyboard, Enter stored it as the last entry and focused it"
# R6. reorder by the move keys (I81): Alt+Down moves the focused entry below the next one and the focus follows it; Alt+Up
#     moves it back. Each move is one change of the list.
Q goto mods.records
Q focusList >/dev/null
tab_to "recordrow:0" 150
kp alt+down
for _ in $(seq 20); do [[ "$(val mods.records.pins)" == '[{"id":"docs"'* ]] && break; sleep 0.2; done
[[ "$(val mods.records.pins)" == '[{"id":"docs"'* ]] || fail "records: Alt+Down did not move the focused entry down ($(val mods.records.pins))"
focus_on "recordrow:1" || fail "records: the focus did not follow the entry moved down ($(Q focused))"
shot records-reordered
kp alt+up
for _ in $(seq 20); do [[ "$(val mods.records.pins)" == '[{"id":"home"'* ]] && break; sleep 0.2; done
[[ "$(val mods.records.pins)" == '[{"id":"home"'* ]] || fail "records: Alt+Up did not move the entry back up ($(val mods.records.pins))"
focus_on "recordrow:0" || fail "records: the focus did not follow the entry moved up ($(Q focused))"
echo "keyboard R6: Alt+Down moved the first entry below the second and Alt+Up moved it back; the focus followed each"
# R7. Down and Up move between the entries; Enter opens the focused entry's form, and Escape closes it: the focus goes back to
#     that entry.
kp down
focus_on "recordrow:1" || fail "records: Down did not move to the next entry ($(Q focused))"
kp up
focus_on "recordrow:0" || fail "records: Up did not move back to the entry above ($(Q focused))"
kp down return
for _ in $(seq 20); do [ "$(Q focused)" = "Id" ] && break; sleep 0.2; done
[ "$(Q focused)" = "Id" ] || fail "records: Enter on an entry did not open its form ($(Q focused))"
kp escape
sleep 0.5
focus_on "recordrow:1" || fail "records: Escape did not give the focus back to the entry it closed ($(Q focused))"
[[ "$(val mods.records.pins)" == '[{"id":"home"'* ]] || fail "records: Escape changed the list ($(val mods.records.pins))"
echo "keyboard R7: Down and Up moved between the entries, Enter opened the second entry's form, Escape closed it and the focus went back"
# R8. Delete removes the focused entry; the focus moves to the entry above it (the last one is removed here).
kp down
focus_on "recordrow:2" || fail "records: Down did not reach the last entry ($(Q focused))"
kp delete
for _ in $(seq 20); do [ "$(python3 -I -c 'import json,sys; print(len(json.loads(sys.argv[1])))' "$(val mods.records.pins)")" = 2 ] && break; sleep 0.2; done
[ "$(python3 -I -c 'import json,sys; print(len(json.loads(sys.argv[1])))' "$(val mods.records.pins)")" = 2 ] || fail "records: Delete did not remove the focused entry ($(val mods.records.pins))"
focus_on "recordrow:1" || fail "records: the focus did not move to the entry above the removed one ($(Q focused))"
echo "keyboard R8: Delete removed the last entry, and the focus moved to the one above it"
# R3. reorder by the row's buttons: Tab to the down button of the first entry and Return moves it below the second; the focus
#     follows the moved entry, Tab reaches its up button, and Return moves it back. Each move is one change of the list.
Q goto mods.records
Q focusList >/dev/null
tab_to "recorddown:0" 150
kp return
for _ in $(seq 20); do [[ "$(val mods.records.pins)" == '[{"id":"docs"'* ]] && break; sleep 0.2; done
[[ "$(val mods.records.pins)" == '[{"id":"docs"'* ]] || fail "records: the down button did not move the first entry ($(val mods.records.pins))"
tab_to "recordup:1" 20
kp return
for _ in $(seq 20); do [[ "$(val mods.records.pins)" == '[{"id":"home"'* ]] && break; sleep 0.2; done
[[ "$(val mods.records.pins)" == '[{"id":"home"'* ]] || fail "records: the up button did not move the entry back ($(val mods.records.pins))"
echo "keyboard R3: the down button moved the first entry, the focus followed it to its up button, and Return moved it back"
# R2. the Nix list: forced and read-only; its chip names the managed layer, and its value is the pinned one.
Q goto mods.records
shot records-forced
[[ "$(val mods.records.locked)" == *'"nix"'* ]] || fail "records: the Nix list is not in effect ($(val mods.records.locked))"
echo "records: the Nix-pinned list is in effect"
# R4. remove and edit by keyboard: Tab to the remove button of the second entry and Return removes it (one change of the list);
#     the list is then set back as it was, for the Japanese page. Tab to the edit button of the first entry and Return opens
#     its form with the entry's id in the first field; Escape closes it and changes nothing.
Q goto mods.records
Q focusList >/dev/null
tab_to "recordremove:1" 150
kp return
for _ in $(seq 20); do [ "$(python3 -I -c 'import json,sys; print(len(json.loads(sys.argv[1])))' "$(val mods.records.pins)")" = 1 ] && break; sleep 0.2; done
[ "$(python3 -I -c 'import json,sys; print(len(json.loads(sys.argv[1])))' "$(val mods.records.pins)")" = 1 ] || fail "records: the remove button did not remove the second entry ($(val mods.records.pins))"
"$BIN/kurashi" set mods.records.pins '[{"id":"home","title":"Home","target":"https://example.org"},{"id":"docs","title":"Docs","target":"mod:webdock:docs","view":"mobile"}]' | grep '^applied' >/dev/null || fail "records: the two entries were not set back"
for _ in $(seq 20); do [[ "$(val mods.records.pins)" == *Docs* ]] && break; sleep 0.2; done
tab_to "recordedit:0" 150
kp return
for _ in $(seq 20); do [ "$(Q focused)" = "Id" ] && break; sleep 0.2; done
[ "$(Q focused)" = "Id" ] || fail "records: the edit button did not open the form with the focus in its first field ($(Q focused))"
kp escape
sleep 0.5
[[ "$(val mods.records.pins)" == '[{"id":"home"'* ]] || fail "records: the edit form changed the list on Escape ($(val mods.records.pins))"
echo "keyboard R4: the remove button removed the second entry and was set back; the edit button opened the form, Escape closed it"

# S1. section cards (K48 (5), I104): each section of a page is a card with its icon and title, in the schema's order.
Q goto power
for _ in $(seq 20); do [ "$(Q sections)" = "power.idle,power.night_light,power.recorder" ] && break; sleep 0.2; done
[ "$(Q sections)" = "power.idle,power.night_light,power.recorder" ] || fail "cards: the power page's sections are not cards in order ($(Q sections))"
shot 28-cards-power
Q advanced true
Q goto desktop
[ "$(Q sections)" = "desktop.widgets" ] || fail "cards: the desktop page shows $(Q sections)"
shot 29-cards-desktop
# A search keeps its breadcrumbs, one card per section found (no card title: the crumb names it).
Q find blur
[ -n "$(Q sections)" ] || fail "cards: the search shows no cards"
Q find ""
Q advanced false
echo "cards S1: the power page shows its three sections as cards; desktop one; a search keeps its crumbs"
# S2. theme export (K49): foot chosen; its file is written under this sandbox's config, foot.ini does not include it yet, so
#     the status under the row names the file, the line to add, and Copy. Copy by keyboard puts the line on the clipboard
#     (wl-copy), or says it could not.
K '{"t":"apply","id":"te1","ops":[{"set":"theme.export","value":["foot"]}]}' | grep -q applied || fail "export: theme.export was refused"
Q jump theme.export
for _ in $(seq 50); do [ "$(Q exportState)" = "foot:missing" ] && break; sleep 0.2; done
[ "$(Q exportState)" = "foot:missing" ] || fail "export: the status does not list foot's missing include ($(Q exportState))"
ls "$R/cfg/foot/"* >/dev/null 2>&1 || fail "export: no foot colours file under the sandbox's config"
shot 30-theme-export
Q focusList >/dev/null
tab_to "copy:foot" 150
kp return
for _ in $(seq 25); do [ "$(Q exportCopied foot)" != none ] && break; sleep 0.2; done
if command -v wl-copy >/dev/null; then
  [ "$(Q exportCopied foot)" = copied ] || fail "export: Copy did not copy ($(Q exportCopied foot))"
  case "$(timeout 5 wl-paste -n 2>/dev/null)" in include=*) ;; *) fail "export: the clipboard does not hold the include line";; esac
  echo "export S2: foot's include line listed with its file; Copy put it on the clipboard"
else
  [[ "$(Q exportCopied foot)" == error* ]] || fail "export: without wl-copy, Copy must say it could not ($(Q exportCopied foot))"
  echo "export S2: foot's include line listed with its file; without wl-copy, Copy says it could not"
fi
shot 31-theme-export-copied
K '{"t":"apply","id":"te2","ops":[{"reset":"theme.export"}]}' | grep -q applied || fail "export: theme.export reset was refused"

# Japanese copy (UX brief: "ja copy lengths"): the same shell with the daemon's locale set to ja_JP.UTF-8.
kill "$qs_pid" "$daemon_pid" 2>/dev/null || true
sleep 0.5
start_daemon ja_JP.UTF-8
start_qs ""
for _ in $(seq 100); do Q goto appearance >/dev/null 2>&1 && break; sleep 0.2; done
sleep 1.5
Q goto appearance
shot ja-appearance
Q goto power
shot ja-cards-power
Q goto @changed
shot ja-changed
Q goto @profiles
Q preview roomy
shot ja-profiles
# The same-value line in Japanese (I64 (2)): the user's large_text is on, as roomy sets it.
K '{"t":"apply","id":"sv3","ops":[{"set":"a11y.large_text","value":true}]}' | grep -q applied || fail "ja: same value was not set by the user"
Q preview roomy
shot ja-profiles-same
K '{"t":"apply","id":"sv4","ops":[{"reset":"a11y.large_text"}]}' | grep -q applied || fail "ja: the user's large_text was not removed"
Q preview roomy
# The export and the refused import, in Japanese (the virtual keyboard stayed open through the restart).
Q focusList >/dev/null
Q preview mine
tab_to "profile-export" 120
kp return
sleep 1
shot ja-profile-export
kp tab
kp n o p e
kp return
sleep 1
shot ja-import-error
exec 3>&-
kbd_pid=""
Q goto mods.media
shot ja-mod-page
Q goto @mods
shot ja-mods
Q find zzzz
shot ja-empty-search
Q find ""
# The records page in Japanese: the two entries and the Nix-pinned list (K38, W17).
Q goto mods.records
shot ja-records

# The QML log: no errors and no warnings from the settings process (the compositor's own notes are not ours).
if grep -aE 'ReferenceError|TypeError|is not a function|Cannot assign|Unable to assign|SyntaxError|Expected token|anchors' \
    "$R/settings.log" | sed 's/\x1b\[[0-9;]*m//g' | grep -q .; then
  grep -aE 'ReferenceError|TypeError|is not a function|Cannot assign|Unable to assign|SyntaxError|Expected token|anchors' \
    "$R/settings.log" | sed 's/\x1b\[[0-9;]*m//g' | head -20
  fail "QML errors in the settings log"
fi

echo "ok: settings/shots/"; ls settings/shots
