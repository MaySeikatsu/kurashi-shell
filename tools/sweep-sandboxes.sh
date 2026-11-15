#!/usr/bin/env bash
# Sandboxes a run left behind (rule 11; session 35 found 42 dirs and 14 sway, niri and kurashid processes hours and days
# old). `sandbox.sh stop` keeps a sandbox's dir for its logs, and a suite that dies leaves its processes.
#   tools/sweep-sandboxes.sh [minutes]   (default 120)
# A dir /tmp/kurashi-sb-* goes when nothing runs in it and it has not been written for `minutes`. A process goes only
# when its environment carries that dir as XDG_RUNTIME_DIR (never anything else: CLAUDE.md "Testing"), it is older than
# `minutes`, and no process of that sandbox has a living parent outside it (its run is gone; the processes were handed to
# init or the user's manager): a run in progress is never touched.
set -uo pipefail
MIN=${1:-120}
now=$(date +%s)
killed=0; removed=0; kept=0
manager=$(pgrep -u "$(id -u)" -x systemd | head -1)
for d in /tmp/kurashi-sb-*; do
  [ -d "$d" ] || continue
  live=()
  for e in /proc/[0-9]*/environ; do
    if { tr '\0' '\n' < "$e"; } 2>/dev/null | grep -qx "XDG_RUNTIME_DIR=$d"; then live+=("$(basename "$(dirname "$e")")"); fi
  done
  # Owned: a process in it has a living parent outside it that is not init or the user's manager (the run that made it).
  owned=0; young=0
  for p in "${live[@]}"; do
    ppid=$(awk '{print $4}' "/proc/$p/stat" 2>/dev/null) || continue
    [ "$ppid" = 1 ] || [ "$ppid" = "$manager" ] || printf '%s\n' "${live[@]}" | grep -qx "$ppid" || owned=1
    [ $(( $(ps -o etimes= -p "$p" 2>/dev/null || echo 0) / 60 )) -ge "$MIN" ] || young=1
  done
  left=${#live[@]}
  if [ "$left" -gt 0 ] && [ "$owned" -eq 0 ] && [ "$young" -eq 0 ]; then
    kill "${live[@]}" 2>/dev/null && killed=$((killed + left)) && left=0
    sleep 0.5
  fi
  if [ "$left" -eq 0 ] && [ $(( (now - $(stat -c %Y "$d")) / 60 )) -ge "$MIN" ]; then
    rm -rf --one-file-system "$d" && removed=$((removed + 1))
  else
    kept=$((kept + 1))
  fi
done
echo "sweep: sandboxes: $removed dir(s) removed, $killed stale process(es) ended, $kept kept"
