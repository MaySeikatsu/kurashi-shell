#!/usr/bin/env bash
# Settings app smoke test + screenshots (card M5-settings). Runs ONLY in a headless sway sandbox
# with an isolated kurashid (own XDG dirs); never touches the real session or ~/.config.
#   settings/test.sh            → exit 0 and settings/shots/*.png
# Needs: nix develop (qs, grim, sway), kurashid + kurashi built (cargo build -p kurashid -p kurashi).
set -euo pipefail
cd "$(dirname "$0")/.."
ROOT=$PWD
if ! command -v qs >/dev/null || ! command -v sway >/dev/null; then
  exec nix develop -c "$0" "$@"
fi
export CARGO_TARGET_DIR=${CARGO_TARGET_DIR:-$HOME/.cache/kurashi-agents-target}
# The target dir is shared with other agents' worktrees, so always rebuild (a no-op when current)
# and snapshot the binaries right away; a bare `debug/kurashi` may belong to another branch.
cargo build -q -p kurashid -p kurashi
BIN=$(mktemp -d)
cp "$CARGO_TARGET_DIR/debug/kurashid" "$CARGO_TARGET_DIR/debug/kurashi" "$BIN/"

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

# --- isolated daemon state --------------------------------------------------------------------
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

qs -p settings > "$R/settings.log" 2>&1 & pids+=($!)
Q() { qs -p settings ipc call settings "$@"; }
for _ in $(seq 100); do Q goto bar >/dev/null 2>&1 && break; sleep 0.2; done
Q goto bar >/dev/null 2>&1 || { echo "settings app did not start"; cat "$R/settings.log"; exit 1; }
sleep 1.5

mkdir -p settings/shots
shot() { sleep 1; grim -o HEADLESS-1 "settings/shots/$1.png"; [ -s "settings/shots/$1.png" ]; }

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

# 7. a mod's settings page (K22): Media turned on; its page reads "Mods › Media" with the album-art
#    toggle and the seek step slider. The page exists only where the daemon calls sync_mods (wiring);
#    a daemon without that call serves no mod page, and this shot is then empty.
Q mod media true
Q goto mods.media
shot 7-mod-page

echo "ok: settings/shots/"; ls settings/shots
