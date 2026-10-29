#!/usr/bin/env bash
# One motion language (W34, docs/ux/motion.md): every Stage panel grows out of its bar widget and folds back into it, as
# the island's views do. Invisibly (headless sway sandbox), frames grabbed at MORPH_AT ms (default 40 120 250) after each
# action, then the panel at rest:
#   real   the REAL kurashid, per case (a look, a motion profile, the bar's edge; `kurashi set`, no restart): the island's
#          view (island.expand), quick settings (quick.toggle; the phone), the session menu (session.menu), a mod's panel
#          (sysmon: mod.panel.open), the sysmon peek (ui.peek with the widget's box), a retarget quick → session → sysmon
#          → quick without a close (mid shots), and the island's view → quick; W36: the launcher (launcher.toggle) and the
#          notification centre (notifications.center), out of the pill on the same springs; a toast budding off the bar
#          (a Notify on the sandbox's own session bus) and drifting away (notify.dismiss); the right and the left sidebar
#          out of their bar buttons (sidebar.toggle);
#   mock   kurashi-mock (its tray has two items): a tray item's menu out of its icon, and quick → session → tray.
# Files: frontend/shots/morph/<case>-<surface>-{open,close}-<ms>.png, <case>-<surface>-rest.png, retarget shots
# <case>-retarget-<step>-<ms>.png. Fails on a server or frontend that does not come up, a panel the daemon did not open,
# a panel still drawn after its close (the Stage must be empty: a stuck morph, B32), or a QML error. The Stage logs its
# springs (KURASHI_STAGE_DEBUG=1): `morph-springs settled frames=N stepMs=T` per run; the summary prints frames and the
# frontend's CPU per morph frame (utime+stime of qs over the real phase's morphs).
#   nix develop -c frontend/test-morph.sh
#   MORPH_CASES="washi sekai" MORPH_SURFACES="quick session" MORPH_PHASES=real nix develop -c frontend/test-morph.sh
# Cases: washi, sekai, kami (their own profiles: calm, lively, calm), washi-lively, sekai-calm, washi-bottom,
# sekai-bottom, washi-none (motion off: cuts), plain (no style: translucent flat strip, the I160 head), glass (soft: I122). Binaries from $KURASHI_BIN_DIR (kurashid, kurashi, kurashi-mock).
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
NAME=${MORPH_SANDBOX:-${KURASHI_SB_PREFIX:-}w34-stage-morph}
BIN=${KURASHI_BIN_DIR:-${CARGO_TARGET_DIR:-$ROOT/target}/debug}
OUT=${MORPH_OUT:-$ROOT/frontend/shots/morph}
AT=${MORPH_AT:-40 120 250}
CASES=${MORPH_CASES:-washi sekai kami washi-lively sekai-calm washi-bottom sekai-bottom washi-none plain glass}
ALL_SURFACES="island quick session mod peek retarget launcher centre toast sidebars"
PHASES=${MORPH_PHASES:-real mock}
mkdir -p "$OUT"
fail() { echo "test-morph: $*" >&2; exit 1; }
want() { [[ " $2 " == *" $1 "* ]]; }

eval "$("$ROOT/tools/bench/sandbox.sh" start "$NAME")"
. "$ROOT/frontend/test-lib.sh"
R=$XDG_RUNTIME_DIR
W=$R/work
mkdir -p "$W" "$R/kurashi"
cp "$BIN/kurashid" "$BIN/kurashi" "$BIN/kurashi-mock" "$W/"
pids=()
stop_phase() {
  for p in "${pids[@]}"; do kill "$p" 2>/dev/null || true; done
  for p in "${pids[@]}"; do wait "$p" 2>/dev/null || true; done
  pids=()
  rm -f "$KURASHI_SOCKET"
}
cleanup() {
  stop_phase
  "$ROOT/tools/bench/sandbox.sh" stop "$NAME" >/dev/null || true
}
trap cleanup EXIT

export XDG_CONFIG_HOME=$R/xdg/config XDG_STATE_HOME=$R/xdg/state \
       XDG_DATA_HOME=$R/xdg/data XDG_CACHE_HOME=$R/xdg/cache KURASHI_DATA_DIR=$ROOT LC_ALL=C.UTF-8
K() { timeout 10 "$W/kurashi" "$@"; }
# K71: the bar moves with its modules in one change (`layout.bar.move`), from the edge it stands on now.
bar_edge() {
  local e
  for e in top bottom left right; do
    if K --json get "edges.$e.bar" | grep -q '"value":true'; then
      [ "$e" = "$1" ] || K act layout.bar.move "{\"from\":\"$e\",\"to\":\"$1\"}" >/dev/null
      return
    fi
  done
  return 1
}
cat > "$W/ipc.py" <<'PY'
import json, os, socket, sys
sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
sock.settimeout(5)
sock.connect(os.environ["KURASHI_SOCKET"])
f = sock.makefile("rwb")
def send(msg):
    f.write((json.dumps(msg) + "\n").encode()); f.flush()
send({"t": "hello", "v": 1, "client": "test", "caps": ["intents", "resync"]})
if json.loads(f.readline())["t"] != "welcome":
    sys.exit("ipc: no welcome")
send({"t": "sub", "id": "s", "doc": sys.argv[1]})
while True:
    line = f.readline()
    if not line:
        sys.exit("ipc: connection closed")
    m = json.loads(line)
    if m.get("id") == "s" and m["t"] in ("snap", "err"):
        print(json.dumps(m.get("data")) if m["t"] == "snap" else "null")
        break
PY
ipc() { timeout 10 python3 -I "$W/ipc.py" "$@"; }
panel() { ipc runtime.ui | python3 -I -c 'import json,sys; d=json.load(sys.stdin) or {}; print(d.get("panel") or "")'; }
OUTPUT=HEADLESS-1

start_frontend() {
  : > "$R/qs.log"
  local bare; bare=$(screen_hash)
  env -u KURASHI_SOCKET KURASHI_STAGE_DEBUG=1 qs -p "$ROOT/frontend" >> "$R/qs.log" 2>&1 &
  QS_PID=$!
  pids+=("$QS_PID")
  for _ in $(seq 100); do grep -q 'hello.*frontend' "$R/server.log" && break; sleep 0.1; done
  grep -q 'hello.*frontend' "$R/server.log" || fail "frontend never said hello (see $R/qs.log)"
  # Was a fixed 3 s: the frontend loaded, drew and stands still (at most 3 s for that).
  wait_frontend "$R/qs.log" 0 3 0.6 "$bare" || fail "the frontend did not load (see $R/qs.log)"
}
cpu_ticks() { awk '{print $14 + $15}' "/proc/$QS_PID/stat"; }

# burst <file-prefix> <crop> <act args...>: the action, and one grim per MORPH_AT offset, each on its own clock.
burst() {
  local pre=$1 crop=$2; shift 2
  local gp=() t t0 ap
  t0=$(date +%s%N)
  # BURST_CMD names a function that does the action instead of `kurashi act` (a toast: a Notify call).
  if [ -n "${BURST_CMD:-}" ]; then "$BURST_CMD" "$@" >/dev/null & else K act "$@" >/dev/null & fi
  ap=$!
  for t in $AT; do
    ( now=$(date +%s%N); wait_ms=$(( t - (now - t0) / 1000000 )); [ "$wait_ms" -gt 0 ] && sleep "$(printf '%d.%03d' $((wait_ms / 1000)) $((wait_ms % 1000)))"
      grim -g "$crop" "$OUT/$pre-$t.png" ) &
    gp+=("$!")
  done
  for p in "${gp[@]}"; do wait "$p" || fail "grim failed ($pre)"; done
  wait "$ap" || fail "act $* failed"
}
rest() { grim -g "$2" "$OUT/$1.png"; echo "test-morph: $OUT/$1.png"; }
# The Stage holds nothing after a close: no layer surface named kurashi-stage is drawn with content. Checked on pixels: the
# card's region against the same region before the open (the frontend may tint nothing else there).
empty_check() {  # empty_check <tag> <crop> <baseline ppm>
  grim -t ppm -g "$2" "$W/after.ppm"
  # The bar's own strip (its first BAR_SKIP rows from the bar's edge) is left out: the clock's minute may turn between
  # the two grabs (W36: a false "stuck morph" at hh:mm:00). A stuck shape always reaches below the bar.
  python3 -I -c '
import sys
def rows(p):
    d = open(p, "rb").read()
    parts = d.split(b"\n", 3)  # P6, "w h", maxval, pixels (grim writes no comments)
    w, h = map(int, parts[1].split())
    px = parts[3]
    return [px[i * w * 3:(i + 1) * w * 3] for i in range(h)]
a, b = rows(sys.argv[1]), rows(sys.argv[2])
if len(a) != len(b): sys.exit(1)
skip = int(sys.argv[3])
keep = range(len(a) - skip) if sys.argv[4] == "bottom" else range(skip, len(a))
a = b"".join(a[i] for i in keep); b = b"".join(b[i] for i in keep)
n = sum(1 for x, y in zip(a, b) if abs(x - y) > 24)
sys.exit(0 if n < max(1, len(a)) // 600 else 1)' "$3" "$W/after.ppm" "${BAR_SKIP:-44}" "${EDGE:-top}" \
    || fail "$1: a panel is still drawn after its close (stuck morph?)"
}

# One surface: open, rest, close, then the Stage must be empty again.
surface() {  # surface <case> <name> <crop> <open act...> -- <close act...>
  local cs=$1 nm=$2 crop=$3; shift 3
  local op=() cl=()
  while [ "$1" != "--" ]; do op+=("$1"); shift; done; shift
  cl=("$@")
  grim -t ppm -g "$crop" "$W/base.ppm"
  BURST_CMD=${OPEN_CMD:-} burst "$cs-$nm-open" "$crop" "${op[@]}"
  sleep 1.4
  rest "$cs-$nm-rest" "$crop"
  BURST_CMD= burst "$cs-$nm-close" "$crop" "${cl[@]}"
  sleep 1.4
  empty_check "$cs-$nm" "$crop" "$W/base.ppm"
}

# The case's config: look, profile, edge.
apply_case() {
  local cs=$1 style=${1%%-*} prof="" edge=top
  # plain: no style (the shell's own default: wa-iro, flat, translucent — the I160 head).
  [ "$style" = plain ] && style=none
  case "$cs" in
    *-lively) prof=lively ;; *-calm) prof=calm ;; *-none) prof=none ;;
    *-bottom) edge=bottom ;;
  esac
  # -slow anywhere in the name: springs at a quarter speed, to look at the mid-morph frames (MORPH_AT spread wider).
  local speed=1.0
  [[ "$cs" == *-slow* ]] && speed=0.25
  K set theme.motion.speed "$speed" >/dev/null || fail "theme.motion.speed $speed refused"
  K set theme.style "$style" >/dev/null || fail "theme.style $style refused"
  # Each look's own profile unless the case names one (washi and kami calm, sekai lively).
  [ -n "$prof" ] || { [ "$style" = sekai ] && prof=lively || prof=calm; }
  K set theme.motion.profile "$prof" >/dev/null || fail "profile $prof refused"
  bar_edge "$edge" || fail "the bar did not move to $edge"
  sleep 2.5
  EDGE=$edge
}
# A crop in the top bar's frame (x y w h from the screen edge the bar is on).
crop() { if [ "$EDGE" = bottom ]; then echo "$1,$((1440 - $2 - $4)) ${3}x$4"; else echo "$1,$2 ${3}x$4"; fi; }

frames_total=0; morph_cpu=0
if want real "$PHASES"; then
  echo "== phase real: kurashid"
  rm -rf "$R/xdg"; mkdir -p "$XDG_CONFIG_HOME/kurashi" "$XDG_STATE_HOME" "$XDG_DATA_HOME" "$XDG_CACHE_HOME"
  : > "$XDG_CONFIG_HOME/kurashi/config.toml"
  : > "$R/server.log"
  env DBUS_SYSTEM_BUS_ADDRESS="unix:path=$R/no-system-bus" \
      PULSE_SERVER="unix:$R/no-pulse/native" PULSE_RUNTIME_PATH="$R/no-pulse" \
      "$W/kurashid" >> "$R/server.log" 2>&1 &
  pids+=("$!")
  for _ in $(seq 100); do [ -S "$KURASHI_SOCKET" ] && K ping >/dev/null 2>&1 && break; sleep 0.1; done
  K ping >/dev/null 2>&1 || fail "kurashid did not come up (see $R/server.log)"
  swaymsg output '*' bg '#8fb8c8' solid_color >/dev/null 2>&1 || true
  start_frontend
  K act mod.enable '{"id":"sysmon"}' >/dev/null || fail "mod.enable sysmon failed"
  sleep 2
  cpu0=$(cpu_ticks)
  for cs in $CASES; do
    echo "-- case $cs"
    apply_case "$cs"
    # Every surface for the looks themselves; the variants (another profile, the bottom bar, no style) a few, to keep the
    # shots reviewable. MORPH_SURFACES picks them for every case.
    if [ -n "${MORPH_SURFACES:-}" ]; then SURFACES=$MORPH_SURFACES
    else case "$cs" in
      washi|sekai|kami) SURFACES=$ALL_SURFACES ;;
      *-bottom) SURFACES="island quick session peek launcher toast" ;;
      plain) SURFACES="island quick" ;;
      *-none) SURFACES="island quick session launcher centre" ;;
      *) SURFACES="island quick session" ;;
    esac; fi
    if want island "$SURFACES"; then
      surface "$cs" island "$(crop 860 0 840 560)" island.expand -- ui.close
    fi
    if want quick "$SURFACES"; then
      surface "$cs" quick "$(crop 1040 0 1520 900)" quick.toggle -- ui.close
    fi
    if want session "$SURFACES"; then
      surface "$cs" session "$(crop 860 0 840 360)" session.menu -- ui.close
    fi
    if want mod "$SURFACES"; then
      surface "$cs" mod "$(crop 760 0 1800 720)" mod.panel.open '{"id":"sysmon","panel":"sysmon"}' -- ui.close
    fi
    if want peek "$SURFACES"; then
      # The sysmon widget's box: the Stage logs the origin it opened the panel from.
      K act mod.panel.open '{"id":"sysmon","panel":"sysmon"}' >/dev/null; sleep 1.2; K act ui.close >/dev/null; sleep 1.2
      o=$(grep -o 'stage-morph open mod origin=[0-9]*,[0-9]*,widget' "$R/qs.log" | tail -1 | sed 's/.*origin=//' || true)
      [ -n "$o" ] || fail "$cs: the sysmon widget's origin is not logged"
      ox=${o%%,*}; ow=${o#*,}; ow=${ow%%,*}
      px=$((ox - 3)); pw=$((ow + 6))
      surface "$cs" peek "$(crop $((px - 300 > 0 ? px - 300 : 0)) 0 760 360)" \
        ui.peek "{\"source\":\"mod:sysmon:sysmon\",\"output\":\"$OUTPUT\",\"x\":$px,\"w\":$pw,\"edge\":\"$EDGE\"}" -- ui.peek '{}'
    fi
    if want launcher "$SURFACES"; then
      surface "$cs" launcher "$(crop 900 0 760 560)" launcher.toggle -- ui.close
    fi
    if want centre "$SURFACES"; then
      surface "$cs" centre "$(crop 980 0 600 640)" notifications.center -- ui.close
    fi
    if want toast "$SURFACES"; then
      # Sent on the sandbox's own session bus only (kurashid's notification server there); dismissed by the daemon: it
      # drifts and fades away, never back into the bar.
      notify_one() { timeout 10 gdbus call --session --dest org.freedesktop.Notifications \
        --object-path /org/freedesktop/Notifications --method org.freedesktop.Notifications.Notify \
        "Calendar" 0 "" "Standup in 5 minutes" "Room 3 · bring the notes from Monday" '[]' '{}' 30000; }
      OPEN_CMD=notify_one surface "$cs" toast "$(crop 980 0 600 360)" toast -- notify.dismiss '{}'
    fi
    if want sidebars "$SURFACES"; then
      surface "$cs" sidebar-right "$(crop 1860 0 700 900)" sidebar.toggle "{\"side\":\"right\",\"output\":\"$OUTPUT\"}" \
        -- sidebar.toggle "{\"side\":\"right\",\"output\":\"$OUTPUT\"}"
      surface "$cs" sidebar-left "$(crop 0 0 700 900)" sidebar.toggle "{\"side\":\"left\",\"output\":\"$OUTPUT\"}" \
        -- sidebar.toggle "{\"side\":\"left\",\"output\":\"$OUTPUT\"}"
    fi
    if want retarget "$SURFACES"; then
      c=$(crop 760 0 1800 900)
      grim -t ppm -g "$c" "$W/base.ppm"
      K act quick.toggle >/dev/null; sleep 1.4
      rest "$cs-retarget-0-quick" "$c"
      burst "$cs-retarget-1-session" "$c" session.menu; sleep 1.4
      rest "$cs-retarget-1-session-rest" "$c"
      burst "$cs-retarget-2-mod" "$c" mod.panel.open '{"id":"sysmon","panel":"sysmon"}'; sleep 1.4
      rest "$cs-retarget-2-mod-rest" "$c"
      burst "$cs-retarget-3-quick" "$c" quick.toggle; sleep 1.4
      [ "$(panel)" = quick ] || fail "$cs: the retarget to quick did not open quick ($(panel))"
      K act ui.close >/dev/null; sleep 1.4
      # A face's view, then quick over it.
      K act island.expand >/dev/null; sleep 1.4
      burst "$cs-retarget-4-island-quick" "$c" quick.toggle; sleep 1.4
      rest "$cs-retarget-4-quick-rest" "$c"
      K act ui.close >/dev/null; sleep 1.4
      empty_check "$cs-retarget" "$c" "$W/base.ppm"
    fi
  done
  cpu1=$(cpu_ticks)
  frames_total=$(grep -o 'morph-springs settled frames=[0-9]*' "$R/qs.log" | sed 's/.*=//' | awk '{s += $1} END {print s + 0}')
  runs=$(grep -c 'morph-springs settled' "$R/qs.log" || true)
  hz=$(getconf CLK_TCK)
  echo "test-morph: real phase: $runs spring runs, $frames_total frames; qs CPU over the phase $(( (cpu1 - cpu0) * 1000 / hz )) ms"
  if [ "${frames_total:-0}" -gt 0 ]; then
    echo "test-morph: qs CPU per morph frame (upper bound: the phase's whole CPU over its morph frames): $(( (cpu1 - cpu0) * 1000000 / hz / frames_total )) us"
  fi
  if grep -E 'qml:.*(Error|error)|TypeError|ReferenceError|is not a type|Binding loop' "$R/qs.log" | grep -v 'Unable to assign \[undefined\]' >/dev/null; then
    grep -E 'Error|error|TypeError|ReferenceError|Binding loop' "$R/qs.log" | head -20 >&2
    fail "QML errors (see $R/qs.log)"
  fi
  cp "$R/qs.log" "$R/qs-real.log"
  stop_phase
fi

if want mock "$PHASES"; then
  echo "== phase mock: kurashi-mock (tray)"
  EDGE=top
  : > "$R/server.log"
  "$W/kurashi-mock" --fixed-time 12:34 >> "$R/server.log" 2>&1 &
  pids+=("$!")
  for _ in $(seq 100); do [ -S "$KURASHI_SOCKET" ] && K ping >/dev/null 2>&1 && break; sleep 0.1; done
  K ping >/dev/null 2>&1 || fail "mock did not come up (see $R/server.log)"
  start_frontend
  mapfile -t TIDS < <(ipc svc.tray | python3 -I -c 'import json,sys; [print(i["id"]) for i in (json.load(sys.stdin) or {}).get("items", [])]')
  [ "${#TIDS[@]}" -ge 2 ] || fail "mock: the tray has fewer than two items"
  surface mock tray "$(crop 1900 0 660 520)" tray.menu.open "{\"id\":\"${TIDS[0]}\"}" -- ui.close
  c=$(crop 760 0 1800 900)
  grim -t ppm -g "$c" "$W/base.ppm"
  K act quick.toggle >/dev/null; sleep 1.4
  burst "mock-retarget-1-session" "$c" session.menu; sleep 1.4
  burst "mock-retarget-2-tray" "$c" tray.menu.open "{\"id\":\"${TIDS[1]}\"}"; sleep 1.4
  rest "mock-retarget-2-tray-rest" "$c"
  [ "$(panel)" = tray ] || fail "mock: the retarget to the tray did not open it ($(panel))"
  K act ui.close >/dev/null; sleep 1.4
  empty_check mock-retarget "$c" "$W/base.ppm"
  if grep -E 'qml:.*(Error|error)|TypeError|ReferenceError|is not a type|Binding loop' "$R/qs.log" | grep -v 'Unable to assign \[undefined\]' >/dev/null; then
    grep -E 'Error|error|TypeError|ReferenceError|Binding loop' "$R/qs.log" | head -20 >&2
    fail "QML errors (see $R/qs.log)"
  fi
  stop_phase
fi
echo "test-morph: ok ($(ls "$OUT" | wc -l) shots in $OUT)"
