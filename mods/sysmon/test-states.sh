#!/usr/bin/env bash
# The system monitor's states drawn in the REAL shell (I56, W15-sysmon-fixes), invisibly: the real kurashid and the real
# Quickshell frontend in the headless sway sandbox, with the daemon reading a FIXTURE /proc and /sys (KURASHI_SYSMON_ROOT,
# read once at start; the shell never sets it). Nothing is signalled: the daemon records the signals it is asked for in the
# fixture (signals.log), so End and Force quit can be pressed on a fixture process without touching a real one.
#
# The states (screenshots in mods/sysmon/shots/states-<name>.png): the bar at normal, activity, critical and paused, with no
# sensor, and with the sparkline on; the panel at card widths 360, 440 and 720 px (a copy of the checkout with the one
# constant changed, so the Stage clamps the width exactly as it does for the shipped panel); the End and Force quit
# confirmations; the shell's own processes with their reasons; the GPU tile with the sleeping dGPU listed as asleep; the
# trouble face after a sustained critical load, and its expanded view. And the states of the fixes (I65): a virtual
# machine's host line; 24 cores (the strip collapsed to the average); a process the system refuses (EPERM) and its row;
# the counters going backwards after a suspend (no spike); the Japanese copy with the Japanese desktop names and a
# versioned program (`2.1.302` shown as `claude`).
# Checks: no QML error in qs.log, no panic in the daemon's log, the End on the culprit is recorded as SIGTERM, and no part
# of the shell is ever recorded as signalled (B24), not even by a request made straight to the daemon.
#   KURASHI_RENDER_NODE=/dev/dri/renderD129 KURASHI_BIN_DIR=<dir with kurashid and kurashi> \
#     timeout 900 nix develop -c mods/sysmon/test-states.sh [sandbox-name]
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
NAME=${1:-sysmon-states}   # unique per run: other agents' runs stop any sandbox that shares a name
BIN=${KURASHI_BIN_DIR:-${CARGO_TARGET_DIR:-$ROOT/target}/debug}
OUT=$ROOT/mods/sysmon/shots
export KURASHI_RENDER_NODE=${KURASHI_RENDER_NODE:-/dev/dri/renderD129}
# Where the pointer clicks to give the card the keyboard: the panel's title, left of its Pause control (layout px).
FOCUS_X=${FOCUS_X:-1090}
FOCUS_Y=${FOCUS_Y:-88}
# The fixture's CPU count (the writer and the /proc/stat lines follow it); set for one state, then back to 4.
CORES=4
mkdir -p "$OUT"
FINDINGS=()
finding() { FINDINGS+=("$*"); echo "finding: $*" >&2; }
fail() { echo "test-states: $*" >&2; exit 1; }

eval "$("$ROOT/tools/bench/sandbox.sh" start "$NAME")"
R=$XDG_RUNTIME_DIR
W=$R/work
DATA=$R/data
FIX=$R/fixture
# The runtime dir is reused by a later run of the same sandbox: nothing of an earlier run is kept.
rm -rf "$DATA" "$FIX" "$R/xdg" "$R/qs.log" "$R/kurashid.log" "$R/keys.log"
mkdir -p "$W" "$R/kurashi" "$DATA" "$R/xdg/config" "$R/xdg/state" "$R/xdg/data" "$R/xdg/cache"
cp "$BIN/kurashid" "$BIN/kurashi" "$W/"
for _ in $(seq 150); do timeout 5 swaymsg -t get_outputs >/dev/null 2>&1 && break; sleep 0.2; done
timeout 5 swaymsg -t get_outputs >/dev/null 2>&1 || fail "the headless compositor does not answer (see $R/sway.log)"

DPID=""
SHPID=""
WRITER=""
DSID=""
cleanup() {
  for pid in "$WRITER" "$SHPID" "$DPID"; do
    if [ -n "$pid" ]; then kill "$pid" 2>/dev/null || true; wait "$pid" 2>/dev/null || true; fi
  done
  "$ROOT/tools/bench/sandbox.sh" stop "$NAME" >/dev/null || true
}
trap cleanup EXIT

# Hermetic: no config, state or cache from an earlier run; the system bus is not reachable.
export XDG_CONFIG_HOME=$R/xdg/config XDG_STATE_HOME=$R/xdg/state XDG_DATA_HOME=$R/xdg/data XDG_CACHE_HOME=$R/xdg/cache
export KURASHI_DATA_DIR=$DATA LC_ALL=C.UTF-8
UIDV=$(id -u)
K() { "$W/kurashi" "$@"; }

# The checkout's frontend, mods, i18n and palettes, copied: the daemon and the shell both read the copy. A width other
# than the shipped 440 px changes the one constant the panel asks for (its `cardWidth`) in the copy.
prep_data() {  # width
  rm -rf "$DATA"
  mkdir -p "$DATA"
  tar -C "$ROOT" --exclude=frontend/shots --exclude=settings/shots --exclude=mods/sysmon/shots \
    -cf - frontend i18n mods palettes | tar -C "$DATA" -xf -
  if [ "$1" != 440 ]; then
    sed -i "s/property int cardWidth: 440/property int cardWidth: $1/" "$DATA/mods/sysmon/qml/Panel.qml"
    grep -q "property int cardWidth: $1" "$DATA/mods/sysmon/qml/Panel.qml" || fail "the card width of the copy did not change"
  fi
}

# ---- the fixture machine ---------------------------------------------------------------------------
# Four CPUs at 100 ticks a second each. The load (a percentage, in $FIX/load) is applied every second by the writer.
fixture_static() {
  mkdir -p "$FIX/proc/net" "$FIX/proc/pressure" "$FIX/proc/1" "$FIX/share/applications" \
    "$FIX/sys/class/drm/card1/device/power" "$FIX/sys/class/drm/card2/device/power" \
    "$FIX/sys/class/drm/card2/device/hwmon/hwmon3"
  {
    printf 'cpu 0 0 0 %d 0 0 0 0\n' $((CORES * 1000))
    for c in $(seq 0 $((CORES - 1))); do printf 'cpu%d 0 0 0 1000 0 0 0 0\n' "$c"; done
  } > "$FIX/proc/stat"
  printf 'MemTotal:       16777216 kB\nMemAvailable:   10066329 kB\nSwapTotal:             0 kB\nSwapFree:              0 kB\n' \
    > "$FIX/proc/meminfo"
  printf '0.52 0.40 0.30 1/200 999\n' > "$FIX/proc/loadavg"
  printf 'Inter-|   Receive\n face |bytes\n  wlan0: 123456 0 0 0 0 0 0 0 98765 0 0 0 0 0 0 0\n' > "$FIX/proc/net/dev"
  printf 'some avg10=4.20 avg60=3.10 avg300=2.00 total=123456\n' > "$FIX/proc/pressure/cpu"
  printf 'some avg10=12.00 avg60=8.00 avg300=4.00 total=99999\nfull avg10=2.00 avg60=1.00 avg300=0.50 total=1234\n' \
    > "$FIX/proc/pressure/memory"
  printf 'some avg10=0.00 avg60=0.00 avg300=0.00 total=0\n' > "$FIX/proc/pressure/io"
  # HYPERVISOR=1: a guest, whose flags carry the hypervisor bit (the panel's host line).
  printf 'flags\t\t: fpu vme sse4_2 aes avx2%s\n' "${HYPERVISOR:+ hypervisor}" > "$FIX/proc/cpuinfo"
  printf '0::/init.scope\n' > "$FIX/proc/1/cgroup"
  # A hybrid laptop: the dGPU (card1) runtime-suspended, the iGPU (card2) awake, and the firmware's display GPU.
  printf 'suspended\n' > "$FIX/sys/class/drm/card1/device/power/runtime_status"
  printf '0x10de\n' > "$FIX/sys/class/drm/card1/device/vendor"
  printf 'active\n' > "$FIX/sys/class/drm/card2/device/power/runtime_status"
  printf '0x1002\n' > "$FIX/sys/class/drm/card2/device/vendor"
  printf '37\n' > "$FIX/sys/class/drm/card2/device/gpu_busy_percent"
  printf '1288490188\n' > "$FIX/sys/class/drm/card2/device/mem_info_vram_used"
  printf '4294967296\n' > "$FIX/sys/class/drm/card2/device/mem_info_vram_total"
  printf '1\n' > "$FIX/sys/class/drm/card2/device/boot_vga"
  printf '54000\n' > "$FIX/sys/class/drm/card2/device/hwmon/hwmon3/temp1_input"
  # Both GPUs' outputs: the panel is lit from the iGPU (card2-eDP-1). The dGPU's own output reads connected too, but
  # the dGPU sleeps, so its outputs are never read (I65).
  mkdir -p "$FIX/sys/class/drm/card1-DP-1" "$FIX/sys/class/drm/card2-eDP-1"
  printf 'connected\n' > "$FIX/sys/class/drm/card2-eDP-1/status"
  printf 'connected\n' > "$FIX/sys/class/drm/card1-DP-1/status"
  # The desktop entry that names the Firefox programs (I61), in English and in Japanese (I65).
  printf '[Desktop Entry]\nName=Firefox\nName[ja]=Firefox ウェブブラウザー\nExec=firefox %%u\n' \
    > "$FIX/share/applications/firefox.desktop"
}

# One process of the fixture: pid, command name, session, executable ("" for none), command line, start time, CPU ticks.
fixture_proc() {
  local pid=$1 comm=$2 session=$3 exe=$4 cmd=$5 start=$6 ticks=${7:-0} uid=${8:-$UIDV}
  local d=$FIX/proc/$pid
  mkdir -p "$d"
  printf '%s (%s) S 1 %s %s 0 -1 4194560 0 0 0 0 %s 0 0 0 20 0 1 0 %s 1000 50\n' \
    "$pid" "$comm" "$pid" "$session" "$ticks" "$start" > "$d/stat"
  printf 'Name:\tx\nUid:\t%s\t%s\t%s\t%s\n' "$uid" "$uid" "$uid" "$uid" > "$d/status"
  if [ -n "$exe" ]; then ln -sfn "$exe" "$d/exe"; fi
  printf '%s' "$cmd" | tr ' ' '\0' > "$d/cmdline"
}

# The culprit (firefox, the first row), its content process, a Quickshell config that is not the shell's, the shell's own
# frontend, Settings window and daemon in this session, another session's kurashid, and a versioned install of Claude
# Code: the kernel names it by its version (2.1.302), the list by its program (I61, I65).
fixture_procs() {
  local ff=/nix/store/xa1-firefox-130/lib/firefox/firefox
  local qs=/nix/store/xc3-quickshell/bin/.quickshell-wrapped
  local kd=/nix/store/xd4-kurashid/bin/kurashid
  fixture_proc 4101 firefox 1 "$ff" "$ff" 101 0
  fixture_proc 4102 "Isolated Web Co" 1 /nix/store/xa1-firefox-130/lib/firefox/.firefox-wrapped \
    "/nix/store/xa1-firefox-130/lib/firefox/firefox -contentproc" 102
  fixture_proc 4103 ".zen-twilight-w" 1 /nix/store/xb2-zen/bin/.zen-twilight-wrapped "zen-twilight" 103
  fixture_proc 4104 ".quickshell-wra" "$DSID" "$qs" "qs -p $DATA/frontend" 104
  fixture_proc 4105 kurashid 1 "$kd" "kurashid" 105
  fixture_proc 4106 ".quickshell-wra" "$DSID" "$qs" "qs -p $DATA/settings" 106
  # Another user's process (uid 0): listed with the program's name, its End and Force quit disabled with the reason.
  fixture_proc 4107 2.1.302 1 /home/fixture/.local/share/claude/versions/2.1.302 "claude --resume" 107 0 0
  fixture_proc 4108 kurashid "$DSID" "$kd" "kurashid" 108
}

set_load() { echo "$1" > "$FIX/load.tmp" && mv "$FIX/load.tmp" "$FIX/load"; }

# Advances the counters every second: the busy share of the CPUs is the load, and the culprit takes all of it. A file
# $FIX/suspend makes the counters start again from zero once, as a machine that slept does (the sample that sees them go
# backwards is dropped, and the next one is measured from the reset values).
start_writer() {
  (
    busy=0
    idle=0
    hog=0
    while :; do
      pct=$(cat "$FIX/load" 2>/dev/null || true)
      pct=${pct:-0}
      if [ -e "$FIX/suspend" ]; then busy=0; idle=0; hog=0; rm -f "$FIX/suspend"; fi
      total=$((CORES * 100))
      d=$((total * pct / 100))
      busy=$((busy + d))
      idle=$((idle + total - d))
      hog=$((hog + d))
      {
        printf 'cpu %d 0 0 %d 0 0 0 0\n' "$busy" "$idle"
        for c in $(seq 0 $((CORES - 1))); do printf 'cpu%d %d 0 0 %d 0 0 0 0\n' "$c" $((busy / CORES)) $((idle / CORES)); done
      } > "$FIX/proc/stat.tmp" && mv "$FIX/proc/stat.tmp" "$FIX/proc/stat"
      printf '4101 (firefox) S 1 4101 1 0 -1 4194560 0 0 0 0 %d 0 0 0 20 0 1 0 101 1000 50\n' "$hog" \
        > "$FIX/proc/4101/stat.tmp" && mv "$FIX/proc/4101/stat.tmp" "$FIX/proc/4101/stat"
      sleep 1
    done
  ) &
  WRITER=$!
}

# ---- the daemon and the shell -------------------------------------------------------------------------
write_config() {  # the [mods.sysmon] settings, one line each
  mkdir -p "$XDG_CONFIG_HOME/kurashi"
  {
    echo "[mods.sysmon]"
    for line in "$@"; do echo "$line"; done
  } > "$XDG_CONFIG_HOME/kurashi/config.toml"
}

start_daemon() {
  rm -f "$KURASHI_SOCKET"
  # DAEMON_LOCALE (the session's language, I65): the daemon's i18n and the desktop names follow it.
  env PATH="$PATH" LC_ALL="${DAEMON_LOCALE:-C.UTF-8}" DBUS_SYSTEM_BUS_ADDRESS="unix:path=$R/no-system-bus" \
    KURASHI_SYSMON_ROOT="$FIX" "$W/kurashid" >> "$R/kurashid.log" 2>&1 &
  DPID=$!
  for _ in $(seq 100); do [ -S "$KURASHI_SOCKET" ] && K ping >/dev/null 2>&1 && break; sleep 0.1; done
  K ping >/dev/null 2>&1 || fail "kurashid did not come up (see $R/kurashid.log)"
  # This session's login session: the daemon's own, which this session's shell processes of the fixture share.
  DSID=$(awk '{print $6}' "/proc/$DPID/stat")
}

start_shell() {
  env -u KURASHI_SOCKET qs -p "$DATA/frontend" >> "$R/qs.log" 2>&1 &
  SHPID=$!
  sleep "${SHELL_WAIT:-5}"
}

stop_all() {
  for pid in "$WRITER" "$SHPID" "$DPID"; do
    if [ -n "$pid" ]; then kill "$pid" 2>/dev/null || true; wait "$pid" 2>/dev/null || true; fi
  done
  WRITER=""
  SHPID=""
  DPID=""
}

# A fresh copy, fixture, daemon and shell for one state: the card width, the load, the sysmon settings, the mod enabled.
start_all() {  # width load settings...
  local width=$1 load=$2
  shift 2
  stop_all
  prep_data "$width"
  rm -rf "$FIX"
  mkdir -p "$FIX"
  set_load 0
  fixture_static
  write_config "$@"
  start_daemon
  fixture_procs
  set_load "$load"
  start_writer
  start_shell
  K act mod.enable '{"id": "sysmon"}' >/dev/null
  sleep 2
}

# ---- the screen, the keys, the pointer ----------------------------------------------------------------
shot() {  # name: give the frames time to settle, then grab the output
  sleep "${WAIT:-2}"
  grim -o HEADLESS-1 "$OUT/states-$1.png"
  [ -s "$OUT/states-$1.png" ] || fail "empty screenshot $1"
  echo "shot states-$1"
}

# Keys go one at a time through the sandbox's virtual keyboard.
press() {
  local k
  for k in "$@"; do
    timeout 20 python3 "$ROOT/tools/bench/wl_keys.py" "$k" >> "$R/keys.log" 2>&1 || true
    sleep 0.35
  done
}

# The card takes keys on demand: a click on its title (no control) gives it the keyboard.
focus_card() {
  timeout 30 python3 -I "$ROOT/tools/bench/wl_pointer.py" click "$FOCUS_X" "$FOCUS_Y" left >> "$R/keys.log" 2>&1 || true
  sleep 0.5
}

open_panel() {
  K act mod.panel.open '{"id": "sysmon", "panel": "sysmon"}' >/dev/null
  sleep 3
  focus_card
}

close_panel() {
  K act ui.close >/dev/null 2>&1 || true
  sleep 1
}

# What the fixture recorded as signalled: "pid SIG" per line.
signals() { cat "$FIX/signals.log" 2>/dev/null || true; }

# ---- the states ---------------------------------------------------------------------------------------
echo "== bar: normal"
start_all 440 0 'show = ["cpu", "mem"]' 'bar_spark = false' 'sustain = 600'
sleep 4
shot bar-normal
stop_all

echo "== bar: activity (CPU 60 %, the activity level is 50 %)"
start_all 440 60 'show = ["cpu", "mem"]' 'bar_spark = false' 'sustain = 600'
sleep 4
shot bar-activity
stop_all

echo "== bar: critical (CPU 95 %; a long sustain, so the face waits)"
start_all 440 95 'show = ["cpu", "mem"]' 'bar_spark = false' 'sustain = 600'
sleep 4
shot bar-critical
stop_all

echo "== bar: paused from the panel's action"
start_all 440 60 'show = ["cpu", "mem"]' 'bar_spark = false' 'sustain = 600'
sleep 4
K act sysmon.pause '{"paused": true}' >/dev/null
sleep 2
shot bar-paused
stop_all

echo "== bar: no sensor (temperature shown, no hwmon sensor on this machine)"
start_all 440 60 'show = ["cpu", "mem", "temp"]' 'bar_spark = false' 'sustain = 600'
sleep 4
shot bar-no-sensor
stop_all

echo "== bar: sparkline on (the last 30 samples)"
start_all 440 40 'show = ["cpu", "mem"]' 'bar_spark = true' 'sustain = 600' 'interval = 1'
sleep 25
shot bar-sparkline
stop_all

echo "== panel at 440 px: tiles, the GPU tile with the dGPU asleep, the processes, End and Force quit"
start_all 440 60 'show = ["cpu", "mem"]' 'bar_spark = false' 'sustain = 600'
open_panel
sleep 2
shot panel-440
# The card's focus order: Pause, Show cores, By CPU, By memory, then the first row (the culprit): its End, then its Force.
press tab tab tab tab tab
press return
sleep 1
shot panel-440-end-confirm
press tab return
sleep 1
shot panel-440-force-confirm
# End on the culprit, then Confirm (the End question's Confirm comes after Force): SIGTERM is what the list offered.
close_panel
open_panel
press tab tab tab tab tab return tab tab return
sleep 2
if signals | grep -q '^4101 TERM$'; then
  echo "signal: 4101 TERM recorded (End on the culprit)"
else
  finding "End on the culprit recorded no TERM: $(signals | tr '\n' ' ')"
fi
close_panel
stop_all

echo "== panel at 360 px"
start_all 360 60 'show = ["cpu", "mem"]' 'bar_spark = false' 'sustain = 600'
open_panel
sleep 2
shot panel-360
stop_all

echo "== panel at 720 px, the per-core strip open"
start_all 720 60 'show = ["cpu", "mem"]' 'bar_spark = false' 'sustain = 600'
open_panel
press tab tab return
sleep 1
shot panel-720-cores
stop_all

echo "== trouble face: CPU 95 % past the sustain window, then its expanded view"
start_all 440 95 'show = ["cpu", "mem"]' 'bar_spark = false' 'sustain = 5'
sleep 20
shot trouble-face
K act island.expand '{}' >/dev/null
sleep 2
shot trouble-face-expanded
stop_all

echo "== counters that went backwards after a suspend: the sparkline has no spike, the figures return at once"
start_all 440 40 'show = ["cpu", "mem"]' 'bar_spark = true' 'sustain = 600' 'interval = 1'
sleep 12
touch "$FIX/suspend"
sleep 8
shot bar-counters-reset
# The daemon's history of the CPU figure (what the sparkline draws): the load is 40 %, so no sample above 60 % is a spike.
highest=$(K --json sub mod.sysmon --count 0 2>/dev/null | python3 -I -c '
import json, sys
values = []
for line in sys.stdin:
    m = json.loads(line)
    values += (m.get("data", m).get("cpu") or {}).get("history", [])
print(max(values) if values else -1)
' || echo -1)
if awk -v h="$highest" 'BEGIN { exit !(h >= 0 && h < 60) }'; then
  echo "ok: the highest CPU sample is $highest % (the load is 40 %)"
else
  finding "a spike in the CPU history after the counters went backwards: highest $highest %"
fi
stop_all

echo "== a virtual machine: the host line says the figures and the sensors are the hypervisor's"
HYPERVISOR=1
start_all 440 60 'show = ["cpu", "mem"]' 'bar_spark = false' 'sustain = 600'
unset HYPERVISOR
open_panel
sleep 2
shot panel-440-vm
stop_all

echo "== 24 cores: the per-core strip is collapsed to the average above 16 cores"
CORES=24
start_all 440 60 'show = ["cpu", "mem"]' 'bar_spark = false' 'sustain = 600'
open_panel
press tab tab return
sleep 1
shot panel-440-cores-24
stop_all
CORES=4

echo "== a process the system refuses (EPERM): the row says so, and nothing is recorded as ended"
start_all 440 60 'show = ["cpu", "mem"]' 'bar_spark = false' 'sustain = 600'
echo 4101 > "$FIX/refuse"
open_panel
press tab tab tab tab tab return
sleep 1
press tab tab return
sleep 2
shot panel-440-refused
if signals | grep -q '^4101 TERM refused$'; then
  echo "signal: 4101 TERM refused by the system, as the fixture says, and nothing was ended"
else
  finding "the refused End was not shown as refused: $(signals | tr '\n' ' ')"
fi
close_panel
stop_all

echo "== the Japanese copy: the panel and an End in Japanese, the Japanese desktop name, the versioned program as claude"
DAEMON_LOCALE=ja_JP.UTF-8
start_all 440 60 'show = ["cpu", "mem"]' 'bar_spark = false' 'sustain = 600'
unset DAEMON_LOCALE
open_panel
sleep 2
shot panel-440-ja
press tab tab tab tab tab return
sleep 1
shot panel-440-ja-end-confirm
close_panel
stop_all

# ---- B24, live: the shell's own processes are refused by the daemon, whatever a request names --------------
start_all 440 60 'show = ["cpu", "mem"]' 'bar_spark = false' 'sustain = 600'
sleep 3
while read -r pid start; do
  K act sysmon.process.kill "{\"pid\": $pid, \"start\": $start}" >/dev/null 2>&1 || true
  K act sysmon.process.term "{\"pid\": $pid, \"start\": $start}" >/dev/null 2>&1 || true
done <<< $'4104 104\n4105 105\n4106 106\n4108 108'
if signals | grep -Eq '^(4104|4105|4106|4108) '; then
  finding "a part of the shell was recorded as signalled: $(signals | tr '\n' ' ')"
else
  echo "signal: no part of the shell was recorded as signalled"
fi
stop_all

# ---- the checks of the whole run ----------------------------------------------------------------------
if grep -Eq 'ReferenceError|TypeError|binding loop|is not a function' "$R/qs.log" 2>/dev/null; then
  finding "QML errors in qs.log: $(grep -E 'ReferenceError|TypeError|binding loop|is not a function' "$R/qs.log" | head -3 | tr '\n' ' ')"
fi
if grep -q panicked "$R/kurashid.log" 2>/dev/null; then
  finding "kurashid panicked (see $R/kurashid.log)"
fi
if [ "${#FINDINGS[@]}" -gt 0 ]; then
  printf 'finding: %s\n' "${FINDINGS[@]}" >&2
  fail "${#FINDINGS[@]} finding(s); screenshots in $OUT"
fi
echo "ok: screenshots in $OUT"
