#!/usr/bin/env bash
# The shell's forms on niri's windows (K91, docs/ux/niri-motion.md), on nested niri, whose GPU compiler is the real one:
#   export   `theme.motion.windows = forms` writes the window's form into kurashi.kdl as custom shaders; follow writes none;
#            reduce motion has no window animation at all
#   compile  every form the shell offers, as open and as close, loads in niri with no shader error (niri only warns and falls
#            back, so the log is what tells)
#   style    a style's pack gives the windows its forms (origami folds)
#   drawn    a slow fold really is one: mid-way the window's top stands and its foot is still empty; a slow iris close has
#            emptied the corners while the middle stands; at rest the window is whole
#   nix develop -c frontend/test-niri-motion.sh
# Binaries from $KURASHI_BIN_DIR, else $CARGO_TARGET_DIR/debug. Shots: frontend/shots/niri-motion/.
set -uo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
export KURASHI_NIRI_SB_NAME=${KURASHI_SB_PREFIX:-}niri-motion
SBR=/tmp/kurashi-sb-$KURASHI_NIRI_SB_NAME
export KURASHI_NIRI_SB_OUT=${NIRI_MOTION_OUT:-$ROOT/frontend/shots/niri-motion}
OUT=$KURASHI_NIRI_SB_OUT
SB="$ROOT/tools/bench/niri-sandbox.sh"
mkdir -p "$OUT"
fail() { echo "test-niri-motion: $*" >&2; "$SB" stop >/dev/null 2>&1; exit 1; }
trap '"$SB" stop >/dev/null 2>&1' EXIT

CFG=$OUT/config.toml
conf() { # conf <windows> [profile] [open] [close] [extra toml]
  {
    printf '[idle]\nenabled = false\n\n[theme]\nexport = ["niri"]\n\n[theme.motion]\nwindows = "%s"\n' "$1"
    [ -n "${2:-}" ] && printf 'profile = "%s"\n' "$2"
    printf '\n[theme.motion.form.window]\nopen = "%s"\nclose = "%s"\n' "${3:-}" "${4:-}"
    printf '%b' "${5:-}"
    # (no previews here: niri nested in a window stops redrawing after any screencopy until something damages it, grim's too,
    # so a still mid-animation would freeze the animation under test. niri on a TTY redraws from its vblank.)
    printf '\n[modules.windows]\npreviews = false\n[modules.workspaces]\npreviews = false\n'
  } > "$CFG"
}
conf forms origami
"$SB" start "$CFG" > /dev/null || fail "the sandbox did not start"
. "$OUT/niri-env.sh"
KDL=$XDG_CONFIG_HOME/niri/kurashi.kdl
LOG=$XDG_RUNTIME_DIR/niri.log
# niri reads what the daemon writes, under a layout that puts a window where the pixels are read.
cat > "$XDG_RUNTIME_DIR/niri.kdl" <<KDL
prefer-no-csd
hotkey-overlay {
    skip-at-startup
}
layout {
    gaps 16
    background-color "#5f8f6a"
    center-focused-column "always"
    default-column-width {
        proportion 0.5
    }
    focus-ring {
        off
    }
}
cursor {
    xcursor-size 24
}
include "xdg/config/niri/kurashi.kdl"
KDL
until_kdl() { # until_kdl <grep -E pattern> <what>
  for _ in $(seq 100); do grep -qE "$1" "$KDL" 2>/dev/null && return 0; sleep 0.1; done
  fail "kurashi.kdl never had $2"
}
errs() { grep -a -c 'error compiling custom' "$LOG"; }
set_conf() { conf "$@"; "$SB" config "$CFG"; }

# --- export ---
until_kdl 'custom-shader r"' "a shader under forms"
grep -q 'vec4 open_color' "$KDL" || fail "no open shader"
grep -q 'vec4 close_color' "$KDL" || fail "no close shader"
niri validate -c "$XDG_RUNTIME_DIR/niri.kdl" > /dev/null 2>&1 || fail "niri refuses the written config"
echo "export: forms writes the shaders, niri validates them"
set_conf follow origami
for _ in $(seq 100); do grep -q 'custom-shader' "$KDL" || break; sleep 0.1; done
grep -q 'custom-shader' "$KDL" && fail "follow still has a shader"
set_conf forms origami '' '' '\n[a11y]\nreduce_motion = true\n'
for _ in $(seq 100); do grep -q 'custom-shader' "$KDL" || break; sleep 0.1; done
grep -q 'custom-shader' "$KDL" && fail "reduce motion still has a shader"
grep -A1 '^animations {' "$KDL" | grep -q 'off' || fail "reduce motion left the windows' animations on"
echo "export: follow has curves alone, reduce motion has none"

# --- compile: every form, both ways ---
: > "$LOG"
FORMS="grow slide rubber zoom fade flip bleed stepped expand iris stamp outline fold book roll crumple genie crt drop liquid fan noren pixelate glitch dissolve"
for f in $FORMS; do
  set_conf forms origami "$f" "$f"
  until_kdl "ks_form" "$f's shader"
  sleep 0.2
  e=$(errs); [ "$e" = 0 ] || { grep -a -B2 'error compiling custom' "$LOG" | cut -c1-200 | tail -6 >&2; fail "$f: niri could not compile it"; }
done
echo "compile: all $(echo "$FORMS" | wc -w) forms load in niri, open and close"

# --- a style's pack ---
set_conf forms origami
until_kdl 'ks_along' "origami's fold"
grep -q 'const float ks_axes = 2.00000;' "$KDL" || fail "origami's fold has not its two axes"
grep -A2 'window-open {' "$KDL" | grep -q 'duration-ms 728' || { grep -A2 'window-open {' "$KDL" >&2; fail "fold's pace (520 ms × 1.4) is not in the block"; }
echo "style: origami's pack gives the windows its fold, two axes, its pace"

# --- drawn ---
px() { # px <png> <x> <y> → "r g b"
  magick "$1" -format "%[fx:int(255*p{$2,$3}.r)] %[fx:int(255*p{$2,$3}.g)] %[fx:int(255*p{$2,$3}.b)]" info:
}
bg() { # is it the layout's background (#5f8f6a)?
  set -- $1; [ "$1" -ge 85 ] && [ "$1" -le 105 ] && [ "$2" -ge 133 ] && [ "$2" -le 153 ] && [ "$3" -ge 96 ] && [ "$3" -le 116 ]
}
shot() { (. "$OUT/sway-env.sh"; timeout 8 grim "$OUT/$1.png"); }
SLOW='\n[theme.motion.timing]\nopen = "linear"\nopen_ms = 3000\nclose = "linear"\nclose_ms = 3000\n'
set_conf forms origami fold iris "$SLOW"
until_kdl 'ks_along' "the slow fold"
until_kdl 'duration-ms 4200' "the slow fold's duration"
sleep 0.5
"$SB" spawn foot -a kstest sh -c 'printf "kurashi"; sleep 100'
# As soon as the window's top stands (it takes 4.2 s to land), its foot must still be empty: a fold's panels come down in turn.
stood=
for _ in $(seq 60); do
  shot fold-mid
  bg "$(px "$OUT/fold-mid.png" 960 60)" || { stood=1; break; }
  sleep 0.1
done
[ -n "$stood" ] || fail "fold: the window's top never came"
foot=$(px "$OUT/fold-mid.png" 960 950)
bg "$foot" || fail "fold mid-way: the window's foot is not empty ($foot)"
rest=
for _ in $(seq 100); do
  shot rest
  bg "$(px "$OUT/rest.png" 960 950)" || { rest=1; break; }
  sleep 0.2
done
[ -n "$rest" ] || fail "the fold never landed"
sleep 1
shot rest
corner=$(px "$OUT/rest.png" 500 60); bg "$corner" && fail "at rest the window has no corner ($corner)"
closed_at=$(date +%s%N)
"$SB" niri action close-window > /dev/null 2>&1
# The iris closes from the corners: when a corner has gone (3.6 s in all), the middle must still stand.
gone=
for _ in $(seq 60); do
  shot iris-mid
  bg "$(px "$OUT/iris-mid.png" 500 60)" && { gone=1; break; }
  sleep 0.1
done
[ -n "$gone" ] || fail "iris: the corner never went"
mid=$(px "$OUT/iris-mid.png" 960 540)
bg "$mid" && fail "iris mid-way: the middle is gone ($mid)"
left=
for _ in $(seq 150); do
  shot gone
  bg "$(px "$OUT/gone.png" 960 540)" && { left=1; break; }
  sleep 0.2
done
[ -n "$left" ] || fail "the window never left ($(px "$OUT/gone.png" 960 540); windows: $("$SB" niri --json windows | cut -c1-200))"
echo "drawn: fold's top before its foot, iris's middle after its corners, whole at rest"
echo "drawn: the close took $(( ($(date +%s%N) - closed_at) / 1000000 )) ms (the form's own 3600)"
[ "$(errs)" = 0 ] || fail "niri warned about a shader"
echo "test-niri-motion: OK"
