#!/usr/bin/env bash
# Settings app smoke test + screenshots (cards M5-settings, S-settings-polish, W9-config-profiles: Undo from
# config.history, a profile file listed while the page is open, refusal lines of mods). Runs ONLY in a headless
# sway sandbox with an isolated kurashid (own XDG dirs); never touches the real session or ~/.config.
#   settings/test.sh                        → exit 0 and settings/shots/*.png
#   KURASHI_BIN_DIR=<dir> settings/test.sh  → take kurashid + kurashi from <dir>; no cargo build
# Needs: nix develop (qs, grim, sway, python3); kurashid + kurashi from KURASHI_BIN_DIR, or built with
# `cargo build -p kurashid -p kurashi`. KURASHI_RENDER_NODE picks the GPU (tools/bench/sandbox.sh).
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
R=$XDG_RUNTIME_DIR                      # /tmp/kurashi-sb-settings, the sandbox's own runtime dir
pids=()
cleanup() {
  for p in "${pids[@]}"; do kill "$p" 2>/dev/null || true; done   # only PIDs started here
  tools/bench/sandbox.sh stop "$NAME" >/dev/null || true
  rm -rf "$BIN"
}
trap cleanup EXIT

# --- isolated daemon state --------------------------------------------------------------------------
mkdir -p "$R/cfg/kurashi/profiles" "$R/state" "$R/data" "$R/cache" "$R/root/i18n/en" "$R/root/i18n/ja"
export XDG_CONFIG_HOME=$R/cfg XDG_STATE_HOME=$R/state XDG_DATA_HOME=$R/data XDG_CACHE_HOME=$R/cache
cat > "$R/cfg/kurashi/config.toml" <<'T'
schema_version = 1
[bar]
height = 40
[outputs."HEADLESS-1".bar]
height = 48
T
# Enforced nix layer: forced value with a reason (stands in for a compositor-capability force,
# which the daemon does not wire yet).
cat > "$R/cfg/kurashi/managed.toml" <<'T'
[_managed]
enforce = true
[theme.material]
blur = false
T
printf '[theme.shape]\nradius_scale = 1.5\n[a11y]\nlarge_text = true\n' > "$R/cfg/kurashi/profiles/roomy.toml"
# Mods (docs/MODS.md): user mods live in $XDG_DATA_HOME/kurashi/mods/<id>/ (xdg_dir adds the app dir),
# discovered at daemon start. A minimal mod, and a folder without mod.toml (shown as invalid).
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
# Data dir = the repo itself: i18n/ (incl. the generated schema catalog) and palettes/, exactly
# what the package installs.
export KURASHI_DATA_DIR=$ROOT

"$BIN/kurashid" > "$R/kurashid.log" 2>&1 & pids+=($!)
for _ in $(seq 50); do [ -S "$KURASHI_SOCKET" ] && break; sleep 0.1; done
[ -S "$KURASHI_SOCKET" ] || { echo "kurashid did not start"; cat "$R/kurashid.log"; exit 1; }
K() { "$BIN/kurashi" raw "$1"; }

# History (K27): one change before Settings starts, so the daemon already has something to undo. The
# seed is an advanced, harmless key that no shot shows.
"$BIN/kurashi" set notifications.history_max 210 | grep '^applied' >/dev/null || { echo "seed: kurashi set was not applied"; exit 1; }

# Without KURASHI_SOCKET, as in a live session: the protocol default must be found.
env -u KURASHI_SOCKET qs -p settings > "$R/settings.log" 2>&1 & pids+=($!)
Q() { qs -p settings ipc call settings "$@"; }
for _ in $(seq 100); do Q goto bar >/dev/null 2>&1 && break; sleep 0.2; done
Q goto bar >/dev/null 2>&1 || { echo "settings app did not start"; cat "$R/settings.log"; exit 1; }
sleep 1.5

mkdir -p settings/shots
shot() { sleep 1; grim -o HEADLESS-1 "settings/shots/$1.png"; [ -s "settings/shots/$1.png" ]; }

# 0. history (K27): the daemon's history is pushed with the config, so Undo is on as soon as Settings opens
#    (the seed above is the only change this daemon has seen). Redo is off: nothing was undone.
for _ in $(seq 50); do [ "$(Q undoState)" = "undo=on,redo=off" ] && break; sleep 0.2; done
[ "$(Q undoState)" = "undo=on,redo=off" ] || { echo "history: Undo not on after opening ($(Q undoState))"; exit 1; }
Q goto bar
shot 0-undo-on-open

# 1. a user value: chip "user" + reset button (bar.height = 40 from config.toml)
Q goto bar
shot 1-user-value

# 2. inert rows with reasons: a11y override + the enforced (forced) blur value
K '{"t":"apply","id":"a1","ops":[{"set":"a11y.reduce_transparency","value":true}]}' | grep -q applied
Q goto appearance
Q advanced true
shot 2-inert-reasons

# 3. a rejected value, shown inline under its row (goes through the same path as the controls)
Q advanced false
Q goto bar
Q set bar.height 500
shot 3-rejected

# 4. profiles: preview diff before loading
Q preview roomy
shot 4-profiles-preview

# 5. search: "blur" matches keys, labels and help on every page; each hit shows page › section › label
Q find blur
shot 5-search

# 6. Mods page: the demo mod turned on through the page's toggle path; the enable of the folder without
#    mod.toml is refused by the daemon and its message shows under that entry
Q goto @mods
Q mod demo-blur true
Q mod broken-demo true
shot 6-mods
[ -n "$(Q modRefusal broken-demo)" ] || { echo "mods: the refusal under broken-demo is not shown"; exit 1; }

# 7. a mod's settings page (K22): Media turned on; its page reads "Mods › Media" with the album-art
#    toggle and the seek step slider. The page exists only where the daemon calls sync_mods (wiring);
#    a daemon without that call serves no mod page, and this shot is then empty.
Q mod media true
Q goto mods.media
shot 7-mod-page
# 7b. B8: a change that went through elsewhere (the Media enable above) takes broken-demo's refusal line
#     away; the row keeps its one-sentence reason (shot 6 showed it before this change)
Q goto @mods
for _ in $(seq 15); do [ -z "$(Q modRefusal broken-demo)" ] && break; sleep 0.2; done
[ -z "$(Q modRefusal broken-demo)" ] || { echo "mods: refusal survived a change elsewhere: $(Q modRefusal broken-demo)"; exit 1; }
shot 7b-mods-after-change

# 8. keyboard only: Tab walks the window's focus order until the bar's "show bar" toggle has focus
#    (its objectName is toggle:<key>), then Space flips it. The daemon must confirm the flip, and the
#    shot shows the 1 px focus ring on that toggle. At most 60 Tabs; never a pointer event.
Q goto bar
Q focusList >/dev/null
# One virtual keyboard for the whole step (settings/keys.py --serve, fed through a FIFO): a keyboard
# that goes away makes the compositor drop the window's keyboard focus.
mkfifo "$R/keys.fifo"
python3 settings/keys.py --serve < "$R/keys.fifo" & pids+=($!)
exec 3> "$R/keys.fifo"
tabs=0
for _ in $(seq 60); do
  echo tab >&3
  tabs=$((tabs + 1))
  sleep 0.3
  [ "$(Q focused)" = "toggle:bar.enabled" ] && break
done
[ "$(Q focused)" = "toggle:bar.enabled" ] || { echo "keyboard: Tab never reached toggle:bar.enabled ($(Q focused))"; exit 1; }
before=$(K '{"t":"cfg.get","id":"k0","key":"bar.enabled"}')
case "$before" in *'"value":true'*) ;; *) echo "keyboard: bar.enabled not on before the test: $before"; exit 1;; esac
echo space >&3
sleep 0.5
after=$(K '{"t":"cfg.get","id":"k1","key":"bar.enabled"}')
case "$after" in *'"value":false'*) ;; *) echo "keyboard: Space did not flip bar.enabled: $after"; exit 1;; esac
shot 8-keyboard-focus   # while the keyboard is still there: its focus is what the ring shows
exec 3>&-
echo "keyboard: Tab x$tabs, Space flipped bar.enabled"

# 9. profiles (K27): a profile file that appears while the Profiles page is open is listed by the same
#    Settings process, with no reconnect (the daemon pushes the list when the file appears).
Q goto @profiles
t0=$(date +%s%N)
printf '[bar]\nheight = 44\n' > "$R/cfg/kurashi/profiles/late.toml"
while [[ "$(Q profileNames)" != *late* ]]; do
  elapsed=$(( ($(date +%s%N) - t0) / 1000000 ))
  [ "$elapsed" -lt 5000 ] || { echo "profiles: late.toml not listed within 5 s ($(Q profileNames))"; exit 1; }
  sleep 0.1
done
echo "profiles: late.toml listed after $(( ($(date +%s%N) - t0) / 1000000 )) ms (IPC round trips included)"
shot 9-profiles-live

# 10. undo from the header (the same click as the button): the step is undone and Redo turns on
Q undo
for _ in $(seq 50); do [ "$(Q undoState)" = "undo=on,redo=on" ] && break; sleep 0.2; done
[ "$(Q undoState)" = "undo=on,redo=on" ] || { echo "history: after Undo, expected undo=on,redo=on ($(Q undoState))"; exit 1; }
shot 10-undo-redo

echo "ok: settings/shots/"; ls settings/shots
