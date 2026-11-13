#!/usr/bin/env bash
# Music plays, nothing is open (W75, B118): the shell draws only what changes visibly (Ma), on nested niri (the lead
# platform: niri's blur re-runs on every commit of a blurred surface).
#   The user's setup (profile red-wood-splatting, session 29): washi, chrome `line`, colour flow while music plays at speed
#   0.25 (drift, tones), the paper material, text spawn `kana`, the sketch outline, the frame, a bottom bar with the island
#   (faces clock, media …) and the lyrics line, the desk with its media and lyrics cards, the web dock, both sidebars pinned (the user's sections); scheme from the
#   wallpaper, palette wa-iro, `mods.media.show_art`.
#   Music: a fake MPRIS player with a cover (crates/kurashi-mock/examples/fake_mpris_art.rs) on the sandbox's bus, a fake
#   cava on the daemon's PATH (16 levels, 30 a second: svc.audio.spectrum as on a real session), synced lyrics in the
#   lyrics mod's cache (a line every 3 s; no network).
#   Measured: every layer surface's Wayland commits (WAYLAND_DEBUG) over MEDIA_IDLE_SECS (default 12) once the start has
#   settled, against the budgets below; the frontend's CPU over the same window is printed (inflated by the debug log).
#   Motion stays on (the user's profile): under the motion profile None the daemon stops the colour flow and the level
#   bars, which are what this suite is about. Nothing opens or closes in the window, so no surface's form runs.
#
#   KURASHI_BIN_DIR=<dir with kurashid, kurashi, examples/fake_mpris_art> timeout 900 nix develop -c frontend/test-media-idle.sh
#   MEDIA_IDLE_OFF="flow gradient line art lyrics spectrum outline fx desk island sidebars" turns parts off (bisecting; no budget check then);
#   MEDIA_IDLE_CPU=1 also measures the CPU with no debug log (the frontend restarted without it).
set -uo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
export KURASHI_NIRI_SB_NAME=${KURASHI_SB_PREFIX:-}media-idle
export KURASHI_NIRI_SB_OUT=${MEDIA_IDLE_OUT:-/tmp/kurashi-media-idle-$KURASHI_NIRI_SB_NAME}
OUT=$KURASHI_NIRI_SB_OUT
SB="$ROOT/tools/bench/niri-sandbox.sh"
BIN=${KURASHI_BIN_DIR:-${CARGO_TARGET_DIR:-$ROOT/target}/debug}
export KURASHI_BIN_DIR=$BIN
SECS=${MEDIA_IDLE_SECS:-12}
OFF=" ${MEDIA_IDLE_OFF:-} "
FAILS=0
say() { echo "test-media-idle: $*"; }
fail() { echo "test-media-idle: FAIL $*" >&2; FAILS=$((FAILS + 1)); }
die() { echo "test-media-idle: $*" >&2; exit 1; }
off() { [[ "$OFF" == *" $1 "* ]]; }
# (the fake player is an example: tools/test-suites.sh builds only the binaries, so it is built here when missing)
[ -x "$BIN/examples/fake_mpris_art" ] || [ "$BIN" != "${CARGO_TARGET_DIR:-$ROOT/target}/debug" ] \
  || (cd "$ROOT" && cargo build -q -p kurashi-mock --example fake_mpris_art) || die "the fake player did not build"
for b in kurashid kurashi examples/fake_mpris_art; do [ -x "$BIN/$b" ] || die "no $b in $BIN (KURASHI_BIN_DIR)"; done
PIDS=()
cleanup() { for p in "${PIDS[@]}"; do kill "$p" 2>/dev/null || true; done; "$SB" stop >/dev/null 2>&1 || true; }
trap cleanup EXIT

# Budgets while music plays and nothing is open (what changes visibly, at the rate the eye needs; W75). Measured on
# origin/main before W75: 30 a second for the bars' windows, 15 for every flowing one (the closed launcher too), a frame
# of every window at each lyric line, 170–230 in all.
#   bars   commits a second of a window with the level bars in it (the bar's window with the island's media face, the
#          desk's with its media card): the bars at 15 a second with the flow's 7.5 steps taken in the same frames, a
#          lyric line's move and spawn
#   flow   a window that shows the colour flow and nothing else that moves (the frame's strips, the dock, the pinned
#          sidebars): its 7.5 steps a second (speed 0.25)
#   still  commits in the whole window of a surface that shows nothing that moves (the closed launcher and Stage, the
#          screen corners, the edge strips): none — one is let through for a minute's turn of a clock
#   total  commits a second of all of them
BUDGET_BARS=${MEDIA_IDLE_BUDGET_BARS:-24}
BUDGET_FLOW=${MEDIA_IDLE_BUDGET_FLOW:-9}
BUDGET_STILL=${MEDIA_IDLE_BUDGET_STILL:-1}
BUDGET_TOTAL=${MEDIA_IDLE_BUDGET_TOTAL:-100}

rm -rf "$OUT"; mkdir -p "$OUT/cava"
# ---- a stand-in cava (stdin: its config; stdout: 16 levels 30 times a second, never silent) ----
cat > "$OUT/cava/cava" <<'PY'
#!/usr/bin/env python3
import math, sys, time
sys.stdin.read()
t = 0
while True:
    t += 1
    sys.stdout.write(";".join(str(int(50 + 45 * math.sin(t * 0.37 + i * 0.9))) for i in range(16)) + ";\n")
    sys.stdout.flush()
    time.sleep(1 / 30)
PY
chmod +x "$OUT/cava/cava"
off spectrum && rm -f "$OUT/cava/cava"

# ---- the user's profile (red-wood-splatting with the user's config over it), what the suite needs of it ----
CFG=$OUT/config.toml
FLOW_ON=true; off flow && FLOW_ON=false
FLOW_GRAD=true; off gradient && FLOW_GRAD=false
FLOW_LINE=true; off line && FLOW_LINE=false
ART=true; off art && ART=false
STROKE=sketch; off outline && STROKE=pen
SPAWN=kana; off fx && SPAWN=none
DESK=true; off desk && DESK=false
LYR='"mod:lyrics:lyrics"'; off lyrics && LYR=''
ISL='"island"'; off island && ISL=''
# The user pins both sidebars on one output (HDMI-A-1): here, on the one output.
PIN=true; off sidebars && PIN=false
cat > "$CFG" <<TOML
[idle]
enabled = false

[bar]
height = 26
hover = "card"

[desktop]
enabled = $DESK
calendar = true
clock = true
media = true
weather = false
left = ["mod:lyrics:lyrics", "mod:timer:timer"]
right = ["clock", "calendar", "media"]
side = "left"

[dock]
enabled = true
edge = "bottom"
visibility = "empty_desktop"

[edges.bottom]
bar = true
center = [$ISL]
draw = "auto"
end = ["recorder", "tray", "audio", "clock", "quick", "mod:webdock:webdock"]
start = ["launcher", "workspaces", $LYR]
visibility = "always"

[edges.top]
bar = false
start = []
center = []
end = []
visibility = "empty_desktop"

[edges.left]
bar = false
start = []
center = []
end = []
visibility = "empty_desktop"

[edges.right]
bar = false
start = []
center = []
end = []
visibility = "hidden"

[island.main]
draw = "auto"
faces = ["clock", "media", "notifications"]

[launcher]
button_logo = "os"

[layout]
draw = "dynamic"

[layout.frame]
enabled = true
reserve = true
thickness = 10

[mods]
enabled = ["sysmon", "media", "calendar", "lyrics", "webdock", "timer", "wallpaper", "handwriting"]

[mods.media]
show_art = $ART

[mods.webdock]
edge = "right"
reserve = true

[sidebar.left]
mode = "pages"
pinned = $PIN
sections = ["mod:webdock:webdock", "mod:wallpaper:wallpaper", "sliders", "mod:sysmon:sysmon", "mod:timer:timer", "mod:handwriting:handwriting"]
visibility = "hover"
width = 390

[sidebar.right]
mode = "stack"
pinned = $PIN
sections = ["header", "toggles", "notifications", "calendar"]
visibility = "hover"
width = 390

[mods.sysmon]
show = ["cpu", "mem", "temp"]
watch = true

[theme]
style = "washi"
look = "washi"
chrome = "line"
frame_outline = "auto"
frame_outline_ink = "text"
frame_outline_stroke = "$STROKE"
outline_ink = "outline"
join = "auto"
join_corner = "round"
window_frame = true

[theme.colors]
palette = "wa-iro"
scheme = "wallpaper"
strong_chrome = true
app_icons = "tones"
chrome_fill = "neutral"

[theme.colors.flow]
on = $FLOW_ON
when = "media"
speed = 0.25
pattern = "drift"
colours = "tones"
gradient = $FLOW_GRAD
outline = $FLOW_LINE

[theme.colors.gradient]
on = true
colours = "tones"
pattern = "watercolour"
span_outputs = true

[theme.colors.media]
apps = true
blend = "wheel_closest"
follow = false
tone = "cover"

[theme.material]
kind = "solid"
shadow = 1.1
sheet_shadow = "inward"

[theme.motion]
profile = "washi"
layout_move = "follow"
content = "profile"

[theme.motion.form]
open = "splat"
close = "splat"

[theme.shape]
corners = "rounded"
radius = 31
screen_corners = 26

[theme.texture]
kind = "paper"
scope = "shell_wallpaper"
strength = 0.35
text = true
controls = true

[theme.typography]
scale = 1.25

[theme.typography.fx]
scope = "all"
spawn = "$SPAWN"
TOML

# ---- the sandbox: niri nested in the invisible sway; kurashid finds the fake cava on its PATH ----
PATH="$OUT/cava:$PATH" "$SB" start "$CFG" > "$OUT/start.log" 2>&1 || die "the sandbox did not start ($(tail -3 "$OUT/start.log"))"
. "$OUT/niri-env.sh"
R=$XDG_RUNTIME_DIR
K() { timeout 10 "$BIN/kurashi" "$@"; }

# ---- the lyrics, cached for the track (crates/kurashi-mod-lyrics/src/cache.rs: FNV-1a of artist, title, seconds) ----
TITLE="Yoru ni Kakeru"; ARTIST="Kurashi Test"; ALBUM="Idle"; LEN=600
python3 -I - "$XDG_CACHE_HOME/kurashi/lyrics" "$ARTIST" "$TITLE" "$LEN" <<'PY'
import json, os, sys, time
d, artist, title, secs = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]
norm = lambda s: " ".join(s.split()).lower()
h = 0xcbf29ce484222325
for b in f"{norm(artist)}\x1f{norm(title)}\x1f{secs}".encode():
    h = ((h ^ b) * 0x100000001b3) & 0xFFFFFFFFFFFFFFFF
lrc = "\n".join(f"[{t // 60:02d}:{t % 60:02d}.00]line {t // 3} of the song" for t in range(0, int(secs), 3))
os.makedirs(d, exist_ok=True)
json.dump({"v": 1, "found": True, "at": int(time.time()), "instrumental": False, "synced": lrc}, open(f"{d}/{h:016x}.json", "w"))
PY

# ---- the music ----
magick -size 96x96 gradient:'#8c1c3a-#e8b04a' "$R/cover.png"
mkfifo "$R/player.in"
"$BIN/examples/fake_mpris_art" "$TITLE" "$ARTIST" "$ALBUM" "$LEN" "file://$R/cover.png" < "$R/player.in" > "$R/player.log" 2>&1 &
PIDS+=("$!")
exec 7> "$R/player.in"
for _ in $(seq 100); do
  [ "$(K sub svc.media --count 0 --json 2>/dev/null | jq -r '.data.playing // false')" = true ] && break; sleep 0.2
done
[ "$(K sub svc.media --count 0 --json | jq -r '.data.playing // false')" = true ] || die "svc.media never played the fake player"
# MEDIA_IDLE_PAUSE=1 (W81): the player paused before the window — the shell at rest with everything mapped (no budget
# check then: every window's budget is `still`'s).
if [ -n "${MEDIA_IDLE_PAUSE:-}" ]; then
  echo pause >&7
  for _ in $(seq 50); do
    [ "$(K sub svc.media --count 0 --json 2>/dev/null | jq -r '.data.playing // false')" = false ] && break; sleep 0.2
  done
  MEDIA_IDLE_OFF=${MEDIA_IDLE_OFF:-paused}
fi

# ---- the frontend again, with the Wayland debug log (niri-sandbox started one without) ----
qs_pids() {
  local p
  for p in $(pgrep -u "$(id -u)" -f -- "-p $ROOT/frontend\$"); do
    tr '\0' '\n' < "/proc/$p/environ" 2>/dev/null | grep -qx "XDG_RUNTIME_DIR=$R" && echo "$p"
  done
}
restart_qs() { # restart_qs <log> [env…]
  local p log=$1; shift
  for p in $(qs_pids); do kill "$p" 2>/dev/null || true; done
  for _ in $(seq 50); do [ -z "$(qs_pids)" ] && break; sleep 0.1; done
  env "$@" setsid qs -p "$ROOT/frontend" > "$log" 2>&1 < /dev/null &
  QS=$!
  for _ in $(seq 100); do grep -q 'get_layer_surface\|Configuration Loaded' "$log" 2>/dev/null && break; sleep 0.1; done
}
LOG=$R/qs-debug.log
# (MEDIA_IDLE_QS_ENV: more environment for the frontend while hunting, e.g. QT_LOGGING_RULES=qt.scenegraph.time.renderloop=true)
# shellcheck disable=SC2086
restart_qs "$LOG" WAYLAND_DEBUG=client ${MEDIA_IDLE_QS_ENV:-}
# The start: the cover, the theme from it, the first spawn of every text, the lyrics' first line. Long enough for the
# shell's own start-up animations to end.
sleep "${MEDIA_IDLE_SETTLE:-12}"
cpu() { awk '{print $14 + $15}' "/proc/$1/stat"; }
TICK=$(getconf CLK_TCK)
s=$(stat -c %s "$LOG"); c0=$(cpu "$QS")
# MEDIA_IDLE_POKE="<kurashi args>" (W81, B119): that CLI call every 3 s of the window (e.g. `act island.next`: the island's
# morph, an animation in the bar's window alone) — do the other windows draw for it?
if [ -n "${MEDIA_IDLE_POKE:-}" ]; then
  # shellcheck disable=SC2086
  ( for _ in $(seq $((SECS / 3))); do sleep 1.5; K $MEDIA_IDLE_POKE > /dev/null 2>&1; sleep 1.5; done ) &
fi
sleep "$SECS"
c1=$(cpu "$QS")
tail -c +"$((s + 1))" "$LOG" > "$OUT/window.log"
# Which surfaces committed, by layer namespace (the last get_layer_surface for that wl_surface id before the window).
grep -o 'get_layer_surface(new id [^,]*, wl_surface#[0-9]*, [^)]*)' "$LOG" \
  | sed -E 's/.*(wl_surface#[0-9]+), [^,]*, [^,]*, "([^"]*)"\)$/\1 \2/' > "$OUT/names.txt"
grep -o 'wl_surface#[0-9]*\.commit(' "$OUT/window.log" | sed 's/\.commit(//' | sort | uniq -c | sort -rn > "$OUT/per.txt"
TOTAL=0
while read -r n sid; do
  ns=$(awk -v s="$sid" '$1 == s {v = $2} END {print v}' "$OUT/names.txt")
  ns=${ns:-$sid}
  rate=$(awk -v n="$n" -v t="$SECS" 'BEGIN {printf "%.1f", n / t}')
  TOTAL=$((TOTAL + n))
  say "  $ns ($sid): $n commits, $rate/s"
  [ -n "${MEDIA_IDLE_OFF:-}" ] && continue
  case "$ns" in
    # (the bar's window has no namespace of its own: "quickshell")
    quickshell|kurashi-desktop|kurashi-edge-module) b=$BUDGET_BARS ;;
    kurashi-launcher|kurashi-stage|kurashi-corners|kurashi-edge|kurashi-webdock-edge)
      [ "$n" -le "$BUDGET_STILL" ] || fail "$ns ($sid): $n commits in $SECS s, and it shows nothing that moves (budget $BUDGET_STILL)"
      continue ;;
    *) b=$BUDGET_FLOW ;;
  esac
  awk -v r="$rate" -v b="$b" 'BEGIN {exit !(r > b)}' && fail "$ns ($sid): $rate commits/s (budget $b)"
done < "$OUT/per.txt"
trate=$(awk -v n="$TOTAL" -v t="$SECS" 'BEGIN {printf "%.1f", n / t}')
pct=$(awk -v a="$c0" -v b="$c1" -v t="$SECS" -v k="$TICK" 'BEGIN {printf "%.0f", (b - a) / k / t * 100}')
say "off: [${MEDIA_IDLE_OFF:-none}] total $TOTAL commits in $SECS s ($trate/s); frontend CPU ${pct}% (with the debug log)"
[ -z "${MEDIA_IDLE_OFF:-}" ] && awk -v r="$trate" -v b="$BUDGET_TOTAL" 'BEGIN {exit !(r > b)}' && fail "all windows: $trate commits/s (budget $BUDGET_TOTAL)"
if [ -n "${MEDIA_IDLE_CPU:-}" ]; then
  # shellcheck disable=SC2086
  restart_qs "$R/qs.log" ${MEDIA_IDLE_QS_ENV:-}
  sleep "${MEDIA_IDLE_SETTLE:-12}"
  # (and by thread name: the GUI thread, the render threads, the rest — top -H's view)
  threads() { for t in /proc/"$QS"/task/*; do echo "$(cat "$t/comm" 2>/dev/null)|$(awk '{print $14 + $15}' "$t/stat" 2>/dev/null)"; done; }
  # (and the nested niri's: every commit is composited, and re-blurred under a blurred surface — W81)
  NIRI=$(for p in $(pgrep -u "$(id -u)" niri); do
    tr '\0' '\n' < "/proc/$p/environ" 2>/dev/null | grep -qx "XDG_RUNTIME_DIR=$R" && echo "$p"; done | head -1)
  threads > "$OUT/t0"; c0=$(cpu "$QS"); n0=$(cpu "${NIRI:-self}"); sleep "$SECS"
  c1=$(cpu "$QS"); n1=$(cpu "${NIRI:-self}"); threads > "$OUT/t1"
  say "niri CPU $(awk -v a="$n0" -v b="$n1" -v t="$SECS" -v k="$TICK" 'BEGIN {printf "%.0f", (b - a) / k / t * 100}')%"
  pct=$(awk -v a="$c0" -v b="$c1" -v t="$SECS" -v k="$TICK" 'BEGIN {printf "%.0f", (b - a) / k / t * 100}')
  by=$(python3 -I -c '
import collections, sys
def read(p):
    d = collections.Counter()
    for line in open(p):
        name, _, v = line.strip().rpartition("|")
        if v: d[name or "?"] += int(v)
    return d
a, b, secs, tick = read(sys.argv[1]), read(sys.argv[2]), float(sys.argv[3]), float(sys.argv[4])
diff = {k: (b[k] - a.get(k, 0)) / tick / secs * 100 for k in b}
print(", ".join("%s %.0f%%" % (k, v) for k, v in sorted(diff.items(), key=lambda x: -x[1]) if v >= 1))
' "$OUT/t0" "$OUT/t1" "$SECS" "$TICK")
  say "off: [${MEDIA_IDLE_OFF:-none}] frontend CPU ${pct}% (no debug log; by thread: $by)"
fi
# MEDIA_IDLE_SHOTS=<dir> (W81): the bar and both pinned sidebars into <dir> (before/after shots of a change; pass
# MEDIA_IDLE_OFF=flow as well, or the flow's phase differs between runs).
if [ -n "${MEDIA_IDLE_SHOTS:-}" ]; then
  mkdir -p "$MEDIA_IDLE_SHOTS"
  for s in "bar 0,1030 1920x50" "sidebar-left 0,0 420x1080" "sidebar-right 1500,0 420x1080"; do
    set -- $s
    cp "$("$SB" shot "w81-$1" "$2 $3" 1)" "$MEDIA_IDLE_SHOTS/$1.png" || fail "no shot of $1"
  done
fi
errs=$(grep -E 'TypeError|ReferenceError|Cannot read|is not a function' "$LOG" | sort -u | head -5)
[ -z "$errs" ] || fail "QML errors: $errs"
[ "$FAILS" = 0 ] || die "$FAILS checks failed"
say ok
