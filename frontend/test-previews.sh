#!/usr/bin/env bash
# Hover previews (I284, I285, K92; docs/ux/hover-previews.md), on nested niri:
#   crops    three windows of known colours: each picture is that window alone, its corners its own colour, no gap in it
#   quiet    the clipboard is what it was: the reason for this route (niri's own window screenshot overwrites it)
#   peeks    resting on a window's button and on another workspace asks the Stage for their previews; a click takes it away
#   gone     a closed window loses its picture, file and all
#   off      both modules' previews off: no subscriber, the service stops and the pictures are gone (Ma)
#   nix develop -c frontend/test-previews.sh
# Binaries from $KURASHI_BIN_DIR, else $CARGO_TARGET_DIR/debug. Shots: frontend/shots/previews/.
set -uo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
export KURASHI_NIRI_SB_NAME=${KURASHI_SB_PREFIX:-}previews
export KURASHI_NIRI_SB_OUT=${PREVIEWS_OUT:-$ROOT/frontend/shots/previews}
OUT=$KURASHI_NIRI_SB_OUT
SB="$ROOT/tools/bench/niri-sandbox.sh"
mkdir -p "$OUT"
fail() { echo "test-previews: $*" >&2; rm -rf "$OUT/failed"; cp -r "${PICS:-/nonexistent}" "$OUT/failed" 2>/dev/null; "$SB" stop >/dev/null 2>&1; exit 1; }
trap '"$SB" stop >/dev/null 2>&1' EXIT

CFG=$OUT/config.toml
conf() { # conf <previews true|false>
  cat > "$CFG" <<TOML
[idle]
enabled = false
[theme]
style = "kanso"
[theme.motion]
profile = "none"
[edges.top]
start = ["launcher", "workspaces", "windows"]
center = ["island"]
end = ["clock"]
[modules.windows]
previews = $1
[modules.workspaces]
previews = $1
TOML
}
conf true
WAYLAND_DEBUG=1 "$SB" start "$CFG" > /dev/null || fail "the sandbox did not start"
. "$OUT/niri-env.sh"
BIN=${KURASHI_BIN_DIR:-${CARGO_TARGET_DIR:-$ROOT/target}/debug}
K() { timeout 10 "$BIN/kurashi" "$@"; }
PICS=$XDG_RUNTIME_DIR/kurashi-previews
cat > "$XDG_RUNTIME_DIR/niri.kdl" <<KDL
prefer-no-csd
hotkey-overlay {
    skip-at-startup
}
layout {
    gaps 20
    background-color "#5f8f6a"
    default-column-width {
        proportion 0.3
    }
    focus-ring {
        off
    }
}
animations {
    off
}
KDL
sleep 1
doc() { K sub "$1" --count 0 2>/dev/null | head -1; }
win_ids() { "$SB" niri --json windows | python3 -c 'import json,sys; [print(w["id"], w["app_id"]) for w in json.load(sys.stdin)]'; }
pic_of() { # the picture's path for a window id, or nothing
  doc svc.previews | python3 -c "import json,sys; d=json.load(sys.stdin)['data']; print(d['windows'].get('$1',{}).get('path',''))"
}
until_() { local n=$1; shift; for _ in $(seq "$n"); do "$@" && return 0; sleep 0.2; done; return 1; }

wl-copy "kept by the test" || fail "wl-copy"
for c in red:cc2222 green:22aa33 blue:2233cc; do
  "$SB" spawn foot -a "kstest-${c%%:*}" -o "colors-dark.background=${c##*:}" sh -c 'printf "\033[?25l"; sleep 300'
  sleep 2.5
done
has_three() { [ "$(doc svc.previews | python3 -c "import json,sys; print(len(json.load(sys.stdin)['data']['windows']))")" -ge 2 ]; }
"$SB" niri action focus-column-left > /dev/null
sleep 2.5
"$SB" act act preview.refresh > /dev/null
until_ 40 has_three || fail "no pictures: $(doc svc.previews | cut -c1-300)"
sleep 1.8

# --- crops: every corner and the middle are the window's colour, within what PNG and the scaling keep ---
check_pic() { # <id> <r> <g> <b>
  local f; f=$(pic_of "$1")
  [ -n "$f" ] && [ -f "$f" ] || return 2
  local w h; read -r w h < <(magick "$f" -format '%w %h' info:)
  for at in "2,2" "$((w-3)),2" "2,$((h-3))" "$((w-3)),$((h-3))" "$((w/2)),$((h/2))"; do
    local px; px=$(magick "$f" -format "%[fx:int(255*p{$at}.r)] %[fx:int(255*p{$at}.g)] %[fx:int(255*p{$at}.b)]" info:)
    set -- "$1" "$2" "$3" "$4" $px
    for i in 0 1 2; do
      local want=${@:2+i:1} got=${@:5+i:1}
      [ "$(( want > got ? want - got : got - want ))" -le 12 ] || { echo "pic $1 at $at is $px"; return 1; }
    done
    set -- "$1" "$2" "$3" "$4"
  done
}
checked=0
while read -r id app; do
  case "$app" in
    kstest-red) rgb="204 34 34" ;;
    kstest-green) rgb="34 170 51" ;;
    kstest-blue) rgb="34 51 204" ;;
    *) continue ;;
  esac
  f=$(pic_of "$id")
  [ -n "$f" ] || continue   # (a column off screen has none yet: not a wrong one)
  # shellcheck disable=SC2086
  check_pic "$id" $rgb || fail "$app's picture is not that window alone"
  cp "$f" "$OUT/$app.png"
  checked=$((checked + 1))
done < <(win_ids)
[ "$checked" -ge 2 ] || fail "only $checked windows had a picture"
echo "crops: $checked windows, each its own picture"

# --- at rest: a round draws nothing of the shell's (the document stays out of Store.docs; K92) ---
"$SB" move 900 700 > /dev/null
sleep 2.5
qs_log=$XDG_RUNTIME_DIR/qs.log
mark=$(stat -c %s "$qs_log")
before=$(pic_of "$(win_ids | awk 'NR==1{print $1}')")
"$SB" act act preview.refresh > /dev/null
for _ in $(seq 40); do [ "$(pic_of "$(win_ids | awk 'NR==1{print $1}')")" != "$before" ] && break; sleep 0.2; done
[ "$(pic_of "$(win_ids | awk 'NR==1{print $1}')")" != "$before" ] || fail "preview.refresh made no new picture"
sleep 1
n=$(tail -c +"$((mark + 1))" "$qs_log" | grep -c 'wl_surface#[0-9]*\.commit(' || true)
[ "$n" = 0 ] || fail "a round made the shell draw: $n commits"
echo "at rest: a round makes the shell commit nothing"

# --- quiet ---
[ "$(wl-paste --no-newline 2>/dev/null)" = "kept by the test" ] || fail "the clipboard changed: $(wl-paste 2>&1 | head -c 80)"
echo "quiet: the clipboard is what it was"

# --- peeks ---
peek() { doc runtime.ui | python3 -c "import json,sys; print((json.load(sys.stdin)['data'].get('peek') or {}).get('source',''))"; }
"$SB" niri action focus-workspace-down > /dev/null
sleep 2
"$SB" spawn foot -a kstest-other sh -c 'sleep 300'
sleep 2
# Across the bar until something answers: the buttons' places are the look's.
find_peek() { # <prefix>
  local x
  for x in $(seq 40 12 300); do
    "$SB" move "$x" 15 > /dev/null; sleep 0.05; "$SB" move "$x" 16 > /dev/null; sleep 0.45
    case "$(peek)" in "$1"*) echo "$x"; return 0 ;; esac
  done
  return 1
}
wx=$(find_peek workspace:) || fail "no workspace's rest asked for its preview: $(doc runtime.ui | cut -c1-240)"
sleep 0.5
"$SB" shot workspace-peek 0,0\ 1000x420 1 > /dev/null
echo "peeks: a workspace at x=$wx: $(peek)"
tx=$(find_peek window:) || fail "no window's rest asked for its preview"
sleep 0.5
"$SB" shot window-peek 0,0\ 1000x420 1 > /dev/null
echo "peeks: a window at x=$tx: $(peek)"
"$SB" click "$tx" 16 > /dev/null
sleep 0.5
[ -z "$(peek)" ] || fail "a click left the peek: $(peek)"
echo "peeks: a click takes it away"
"$SB" move 900 700 > /dev/null
sleep 0.5

# --- gone ---
other=$(win_ids | awk '$2 == "kstest-other" {print $1}')
until_ 40 test -n "$(pic_of "$other")" || true
"$SB" act act preview.refresh > /dev/null
sleep 2.5
f=$(pic_of "$other")
[ -n "$f" ] || fail "the new window has no picture"
"$SB" niri action close-window > /dev/null
sleep 1
[ -z "$(pic_of "$other")" ] || fail "a closed window keeps its entry"
[ ! -e "$f" ] || fail "a closed window keeps its file"
echo "gone: a closed window has no picture left"

# --- off ---
conf false
"$SB" config "$CFG"
until_ 40 test ! -e "$PICS" || fail "previews off: the pictures are still there: $(ls "$PICS" | head -3)"
echo "off: nothing is kept"
"$SB" log 12 | grep -v 'host portal' | grep -iE 'preview|TypeError|ReferenceError' && fail "the frontend complained"
echo "test-previews: OK"
