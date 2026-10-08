#!/usr/bin/env python3
"""Kurashi frontend bench (docs/BAKEOFF.md). Runs a frontend command against kurashi-mock in a
fresh headless-sway sandbox per pass and writes tools/bench/results/<name>.json (+ .md row).

  python3 tools/bench/measure.py --name quickshell -- qs -p probes/quickshell

Pass A (clean)          : idle CPU %, wakeups/s (ctx switches), PSS @1 output, PSS popup open,
                          PSS @2 outputs (hotplug), GPU memory (nvidia-smi), surviving after hotplug
Pass B (WAYLAND_DEBUG)  : startup ms (launch → first commit), idle commits/s per surface,
                          popup input→commit latency (median of 5), island morph frame pacing
Pass C (strace -f -ttt) : idle syscalls/s + top syscalls
Line arrival on the stderr pipe is timestamped by us (libwayland writes unbuffered), so the
numbers are comparable across toolkits without parsing toolkit-specific timestamp formats.
"""
from __future__ import annotations

import argparse, json, os, re, shutil, signal, statistics, subprocess, sys, threading, time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SANDBOX = ROOT / "tools/bench/sandbox.sh"
RESULTS = ROOT / "tools/bench/results"
CLK_TCK = os.sysconf("SC_CLK_TCK")
COMMIT = re.compile(r"wl_surface#?@?(\d+)\.commit\(")


def sh(*args, env=None, check=True, capture=True):
    return subprocess.run(args, env=env, check=check, text=True,
                          stdout=subprocess.PIPE if capture else None, stderr=subprocess.PIPE if capture else None)


class Sandbox:
    def __init__(self, name: str):
        self.name = name
        out = sh(str(SANDBOX), "start", name).stdout
        self.env = dict(os.environ)
        for line in out.splitlines():
            if line.startswith("export "):
                k, _, v = line[7:].partition("=")
                self.env[k] = v
            elif line.startswith("unset "):
                for k in line[6:].split():
                    self.env.pop(k, None)
        Path(self.env["KURASHI_SOCKET"]).parent.mkdir(parents=True, exist_ok=True)

    def add_output(self):
        sh(str(SANDBOX), "output-add", self.name, check=False)

    def stop(self):
        sh(str(SANDBOX), "stop", self.name, check=False)


def tree(pid: int) -> list[int]:
    children: dict[int, list[int]] = {}
    for p in Path("/proc").iterdir():
        if p.name.isdigit():
            try:
                ppid = int((p / "stat").read_text().rsplit(")", 1)[1].split()[1])
                children.setdefault(ppid, []).append(int(p.name))
            except (OSError, IndexError, ValueError):
                pass
    out, stack = [], [pid]
    while stack:
        q = stack.pop()
        out.append(q)
        stack.extend(children.get(q, []))
    return out


def cpu_ticks(pids):
    t = 0
    for p in pids:
        try:
            f = Path(f"/proc/{p}/stat").read_text().rsplit(")", 1)[1].split()
            t += int(f[11]) + int(f[12])
        except (OSError, IndexError):
            pass
    return t


def ctx_switches(pids):
    n = 0
    for p in pids:
        for task in Path(f"/proc/{p}/task").glob("*"):
            try:
                for line in (task / "status").read_text().splitlines():
                    if line.startswith(("voluntary_ctxt_switches", "nonvoluntary_ctxt_switches")):
                        n += int(line.split()[1])
            except OSError:
                pass
    return n


def pss_kib(pids):
    total = 0
    for p in pids:
        try:
            for line in Path(f"/proc/{p}/smaps_rollup").read_text().splitlines():
                if line.startswith("Pss:"):
                    total += int(line.split()[1])
        except OSError:
            pass
    return total


def gpu_mib(pids):
    if not shutil.which("nvidia-smi"):
        return None
    try:
        q = sh("nvidia-smi", "-q", "-d", "PIDS", check=False).stdout
    except OSError:
        return None
    total, cur = 0, None
    for line in q.splitlines():
        line = line.strip()
        if line.startswith("Process ID"):
            cur = int(line.split(":")[1])
        elif line.startswith("Used GPU Memory") and cur in pids:
            m = re.search(r"(\d+)\s*MiB", line)
            total += int(m.group(1)) if m else 0
    return total


def kurashi(env, *args):
    return sh(str(ROOT / "target/release/kurashi"), *args, env=env, check=False)


def start_mock(env):
    log = open(Path(env["XDG_RUNTIME_DIR"]) / "mock.log", "w")
    p = subprocess.Popen([str(ROOT / "target/release/kurashi-mock"), "--outputs", "HEADLESS-1,HEADLESS-2"],
                         env=env, stdout=log, stderr=log)
    for _ in range(50):
        if Path(env["KURASHI_SOCKET"]).exists():
            break
        time.sleep(0.05)
    return p


def stop(p: subprocess.Popen):
    for q in reversed(tree(p.pid)):
        try:
            os.kill(q, signal.SIGTERM)
        except ProcessLookupError:
            pass
    try:
        p.wait(timeout=5)
    except subprocess.TimeoutExpired:
        p.kill()


def pass_a(name, cmd, warmup, idle):
    sb = Sandbox(f"bench-{name}-a")
    mock = start_mock(sb.env)
    try:
        app = subprocess.Popen(cmd, env=sb.env, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        time.sleep(warmup)
        if app.poll() is not None:
            return {"error": f"exited early with {app.returncode}"}
        pids = tree(app.pid)
        t0, c0, s0 = time.monotonic(), cpu_ticks(pids), ctx_switches(pids)
        time.sleep(idle)
        pids = tree(app.pid)
        dt = time.monotonic() - t0
        r = {
            "idle_cpu_pct": round(100 * (cpu_ticks(pids) - c0) / CLK_TCK / dt, 3),
            "wakeups_per_s": round((ctx_switches(pids) - s0) / dt, 1),
            "pss_mib_1out": round(pss_kib(pids) / 1024, 1),
            "gpu_mib": gpu_mib(set(pids)),
            "processes": len(pids),
        }
        kurashi(sb.env, "act", "probe.popup.toggle")
        time.sleep(2)
        r["pss_mib_popup"] = round(pss_kib(tree(app.pid)) / 1024, 1)
        kurashi(sb.env, "act", "probe.popup.toggle")
        sb.add_output()
        time.sleep(4)
        r["pss_mib_2out"] = round(pss_kib(tree(app.pid)) / 1024, 1)
        r["survived_hotplug"] = app.poll() is None
        stop(app)
        return r
    finally:
        stop(mock)
        sb.stop()


def pass_b(name, cmd, warmup, idle):
    sb = Sandbox(f"bench-{name}-b")
    env = dict(sb.env, WAYLAND_DEBUG="client")
    mock = start_mock(sb.env)
    events: list[tuple[float, int]] = []
    lock = threading.Lock()
    try:
        t_launch = time.monotonic()
        app = subprocess.Popen(cmd, env=env, stdout=subprocess.DEVNULL, stderr=subprocess.PIPE,
                               text=True, errors="replace", bufsize=1)

        def reader():
            for line in app.stderr:
                m = COMMIT.search(line)
                if m:
                    with lock:
                        events.append((time.monotonic(), int(m.group(1))))
        threading.Thread(target=reader, daemon=True).start()

        def commits_since(t):
            with lock:
                return [e for e in events if e[0] >= t]

        time.sleep(warmup)
        if app.poll() is not None:
            return {"error": f"exited early with {app.returncode}"}
        with lock:
            startup_ms = round((events[0][0] - t_launch) * 1000) if events else None
        t0 = time.monotonic()
        time.sleep(idle)
        idle_events = commits_since(t0)
        per_surface: dict[int, int] = {}
        for _, sid in idle_events:
            per_surface[sid] = per_surface.get(sid, 0) + 1

        latencies = []
        for _ in range(5):
            t = time.monotonic()
            kurashi(sb.env, "act", "probe.popup.toggle")
            time.sleep(0.6)
            after = commits_since(t)
            if after:
                latencies.append((after[0][0] - t) * 1000)
            kurashi(sb.env, "act", "probe.popup.toggle")
            time.sleep(0.6)

        t = time.monotonic()
        kurashi(sb.env, "mock", "face", "media")
        time.sleep(1.5)
        morph = [e[0] for e in commits_since(t)]
        gaps = sorted((b - a) * 1000 for a, b in zip(morph, morph[1:]))
        stop(app)
        return {
            "startup_ms": startup_ms,
            "idle_commits_per_s": round(len(idle_events) / idle, 2),
            "idle_commits_by_surface": per_surface,
            "popup_latency_ms_median": round(statistics.median(latencies), 1) if latencies else None,
            "popup_latency_ms_all": [round(x, 1) for x in latencies],
            "morph_commits": len(morph),
            "morph_frame_ms_p50": round(gaps[len(gaps) // 2], 1) if gaps else None,
            "morph_frame_ms_p99": round(gaps[min(len(gaps) - 1, int(len(gaps) * 0.99))], 1) if gaps else None,
        }
    finally:
        stop(mock)
        sb.stop()


def pass_c(name, cmd, warmup, idle):
    if not shutil.which("strace"):
        return {"error": "strace missing"}
    sb = Sandbox(f"bench-{name}-c")
    mock = start_mock(sb.env)
    log = Path(sb.env["XDG_RUNTIME_DIR"]) / "strace.log"
    try:
        app = subprocess.Popen(["strace", "-f", "-ttt", "-qq", "-o", str(log), "--", *cmd], env=sb.env,
                               stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        time.sleep(warmup)
        t0 = time.time()
        time.sleep(idle)
        t1 = time.time()
        stop(app)
        counts: dict[str, int] = {}
        total = 0
        for line in log.read_text(errors="replace").splitlines():
            parts = line.split(None, 2)
            if len(parts) < 3:
                continue
            try:
                ts = float(parts[1])
            except ValueError:
                continue
            if t0 <= ts <= t1:
                call = parts[2].split("(", 1)[0]
                if call.startswith("<...") or call.startswith("---") or call.startswith("+++"):
                    continue
                counts[call] = counts.get(call, 0) + 1
                total += 1
        top = sorted(counts.items(), key=lambda kv: -kv[1])[:6]
        return {"idle_syscalls_per_s": round(total / idle, 1), "top_syscalls": dict(top)}
    finally:
        stop(mock)
        sb.stop()


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--name", required=True)
    ap.add_argument("--warmup", type=float, default=10)
    ap.add_argument("--idle", type=float, default=30)
    ap.add_argument("--passes", default="abc")
    ap.add_argument("cmd", nargs=argparse.REMAINDER)
    a = ap.parse_args()
    cmd = a.cmd[1:] if a.cmd[:1] == ["--"] else a.cmd
    if not cmd:
        sys.exit("missing frontend command after --")
    RESULTS.mkdir(parents=True, exist_ok=True)
    result = {"name": a.name, "cmd": cmd, "date": time.strftime("%Y-%m-%d %H:%M"),
              "commit": sh("git", "-C", str(ROOT), "rev-parse", "--short", "HEAD", check=False).stdout.strip()}
    for p, fn in (("a", pass_a), ("b", pass_b), ("c", pass_c)):
        if p in a.passes:
            print(f"[{a.name}] pass {p} …", file=sys.stderr)
            result[f"pass_{p}"] = fn(a.name, cmd, a.warmup, a.idle)
    out = RESULTS / f"{a.name}.json"
    out.write_text(json.dumps(result, indent=2, ensure_ascii=False))
    print(json.dumps(result, indent=2, ensure_ascii=False))


if __name__ == "__main__":
    main()
