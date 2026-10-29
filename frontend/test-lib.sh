# Shared waits for the frontend suites (card W55): conditions instead of fixed sleeps. Source it after the sandbox's
# env lines are in effect (grim talks to $WAYLAND_DISPLAY):  . "$ROOT/frontend/test-lib.sh"
# Every wait returns as soon as its condition holds; its timeout is the old fixed sleep or longer, so a suite is never
# slower than before, only faster. A fixed sleep stays where a suite measures time itself (an idle window, a dwell, a
# reveal's duration).

# _tl_ms <seconds>: whole milliseconds (decimals allowed).
_tl_ms() { awk -v s="$1" 'BEGIN { printf "%d", s * 1000 }'; }
_tl_now() { echo $(( $(date +%s%N) / 1000000 )); }

# now_ms: the clock in milliseconds. sleep_rest <t0 ms> <seconds>: sleeps until `seconds` after t0 — for a measurement
# (PSS) that was taken a fixed time after a start, while the start's own wait got shorter.
now_ms() { _tl_now; }
sleep_rest() {
  local left; left=$(( $1 + $(_tl_ms "$2") - $(_tl_now) ))
  [ "$left" -gt 0 ] && sleep "$(awk -v l="$left" 'BEGIN { printf "%.3f", l / 1000 }')"
  return 0
}

# log_size <file>: its size in bytes now (an offset for wait_for's "since").
log_size() { stat -c %s "$1" 2>/dev/null || echo 0; }

# wait_for <file> <ERE> [timeout s=10] [since byte=0]: 0 once a line of the file (after byte `since`) matches,
# 1 after the timeout.
wait_for() {
  local f=$1 pat=$2 end since=${4:-0}
  end=$(( $(_tl_now) + $(_tl_ms "${3:-10}") ))
  while :; do
    # (Not a pipe: grep -q leaves early and a big log's tail would die of SIGPIPE under pipefail.)
    grep -qE -- "$pat" < <(tail -c +"$(( since + 1 ))" "$f" 2>/dev/null) && return 0
    [ "$(_tl_now)" -ge "$end" ] && return 1
    sleep 0.05
  done
}

# wait_until <timeout s> <command …>: 0 once the command succeeds, 1 after the timeout.
wait_until() {
  local end; end=$(( $(_tl_now) + $(_tl_ms "$1") )); shift
  while :; do
    "$@" >/dev/null 2>&1 && return 0
    [ "$(_tl_now)" -ge "$end" ] && return 1
    sleep 0.05
  done
}

# _tl_trace <what> <max s> <ms>: each wait's length, for tuning, in the sandbox's test-lib.log.
_tl_trace() { echo "$1 max=${2:-} ${3}ms" >> "${XDG_RUNTIME_DIR:-/tmp}/test-lib.log" 2>/dev/null || true; }

# _tl_screen [geometry]: a hash of the screen (all outputs, or the region "x,y wxh"), at half size.
_tl_screen() {
  if [ -n "${1:-}" ]; then timeout 10 grim -t ppm -g "$1" - 2>/dev/null | md5sum
  else timeout 10 grim -t ppm -s 0.5 - 2>/dev/null | md5sum; fi
}

# wait_settled [max s=10] [quiet s=0.6] [geometry]: returns once the screen (or the region) has not changed for `quiet`
# seconds — the surfaces stand and their motion ended — or after `max` (then it says so on stderr). Always 0: it is the
# wait that replaced a fixed sleep of `max`, and the checks after it judge what is on screen.
# A change that starts later than `quiet` after the call (a hover dwell, a timer) is not waited for: use wait_for there.
wait_settled() {
  local max quiet g=${3:-} t0 now last="" h since
  max=$(_tl_ms "${1:-10}"); quiet=$(_tl_ms "${2:-0.6}")
  t0=$(_tl_now); since=$t0
  while :; do
    h=$(_tl_screen "$g")
    now=$(_tl_now)
    if [ "$h" != "$last" ]; then last=$h; since=$now
    elif [ $(( now - since )) -ge "$quiet" ]; then _tl_trace settled "$1" $(( now - t0 )); return 0; fi
    if [ $(( now - t0 )) -ge "$max" ]; then
      echo "test-lib: the screen did not settle in ${1:-10} s${g:+ ($g)}" >&2
      _tl_trace "not-settled" "$1" $(( now - t0 ))
      return 0
    fi
    sleep 0.1
  done
}

# screen_hash [geometry]: the screen now, for wait_frontend's "changed from" (take it before starting the frontend).
screen_hash() { _tl_screen "${1:-}"; }

# wait_frontend <qs log> [since byte=0] [max s=15] [quiet s=0.6] [hash before]: the frontend loaded its configuration
# (Quickshell's "Configuration Loaded" after byte `since`), drew (the screen is no longer `hash before`, when given:
# an unchanged empty screen is not a settled one) and the screen settled after it. 1 when it never loaded.
wait_frontend() {
  local log=$1 since=${2:-0} max=${3:-15} quiet=${4:-0.6} bare=${5:-} end t0
  t0=$(_tl_now)
  wait_for "$log" 'Configuration Loaded' 15 "$since" || return 1
  _tl_trace loaded "$max" $(( $(_tl_now) - t0 ))
  if [ -n "$bare" ]; then
    end=$(( $(_tl_now) + $(_tl_ms "$max") ))
    while [ "$(_tl_screen)" = "$bare" ] && [ "$(_tl_now)" -lt "$end" ]; do sleep 0.05; done
  fi
  wait_settled "$max" "$quiet"
}

# wait_log_quiet <file> <ERE> <quiet s> [max s=10]: returns once no new line matching the ERE (say a WAYLAND_DEBUG
# commit) was written for `quiet` seconds, or after `max`. Always 0 (a start-up wait before an idle window).
wait_log_quiet() {
  local f=$1 pat=$2 quiet max t0 off size n since now
  quiet=$(_tl_ms "$3"); max=$(_tl_ms "${4:-10}")
  t0=$(_tl_now); since=$t0; off=$(log_size "$f")
  while :; do
    size=$(log_size "$f")
    n=0
    # Only the bytes written since the last look (a WAYLAND_DEBUG log grows by megabytes).
    [ "$size" -gt "$off" ] && n=$(tail -c +"$(( off + 1 ))" "$f" | head -c "$(( size - off ))" | grep -cE -- "$pat" || true)
    off=$size
    now=$(_tl_now)
    if [ "${n:-0}" -gt 0 ]; then since=$now
    elif [ $(( now - since )) -ge "$quiet" ]; then return 0; fi
    [ $(( now - t0 )) -ge "$max" ] && return 0
    sleep 0.1
  done
}
