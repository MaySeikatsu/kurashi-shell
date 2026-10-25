#!/usr/bin/env python3
"""Kurashi frontend bench (docs/BAKEOFF.md). Runs a frontend command against kurashi-mock in a
fresh headless-sway sandbox per pass and writes tools/bench/results/<name>.json (+ .md row).

  python3 tools/bench/measure.py --name quickshell -- qs -p archive/bakeoff-probes/quickshell
  python3 tools/bench/measure.py --name frontend-real --daemon real -- qs -p frontend

Pass A (clean)          : idle CPU %, wakeups/s (ctx switches), PSS @1 output, PSS popup open,
                          PSS @2 and @3 outputs (hotplug), GPU memory (nvidia-smi), surviving after hotplug
                          (real daemon: + PSS growth over --cycles open/close cycles of each panel)
Pass B (WAYLAND_DEBUG)  : startup ms (launch → first commit), idle commits/s per surface,
                          popup input→commit latency (median of 5), island morph frame pacing
Pass C (strace -f -ttt) : idle syscalls/s + top syscalls
--daemon mock (default) runs kurashi-mock; --daemon real runs the built kurashid (isolated XDG
dirs, the sandbox's D-Bus, no NIRI_SOCKET) and reports its CPU/PSS/wakeups separately.
--config FILE (real daemon) starts kurashid with FILE as the user config.toml (a copy in the sandbox).
--script FILE (real daemon) adds a motion window (see load_script): pass m (opt-in, --passes abm) measures the
                          frontend's and the daemon's CPU and wakeups while it plays, pass b the commits in it.
--max-load F waits (up to --load-wait s) for the 1-minute load average to fall below F, and records it.
Line arrival on the stderr pipe is timestamped by us (libwayland writes unbuffered), so the
numbers are comparable across toolkits without parsing toolkit-specific timestamp formats.
"""
from __future__ import annotations

import argparse, json, os, re, select, shlex, shutil, signal, statistics, subprocess, sys, threading, time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SANDBOX = ROOT / "tools/bench/sandbox.sh"
RESULTS = ROOT / "tools/bench/results"
CLK_TCK = os.sysconf("SC_CLK_TCK")
COMMIT = re.compile(r"wl_surface#?@?(\d+)\.commit\(")
# libwayland prefixes lines with "[sec.usec]" or "[HH:MM:SS.usec] {queue}" depending on version.
WL_DEBUG = re.compile(r"^\[[\d:. ]+\].*?\w+[#@]\d+\.\w+\(")
ATTACH = re.compile(r"wl_surface#?@?(\d+)\.attach\((nil|wl_buffer)")
LAYER = re.compile(r"get_layer_surface\(.*?wl_surface#?@?(\d+)(?:.*?\"([^\"]*)\")?")
# Set by main(): sandbox name prefix, the real daemon's user config, the motion script (--config, --script).
SANDBOX_PREFIX, CONFIG, SCRIPT = "bench-", None, None
# --latency N: popup rounds through our own open IPC connection (pass b, real daemon); --wl-log FILE: pass b's
# WAYLAND_DEBUG lines with their arrival time (seconds since launch), for attributing commits to windows and items.
LATENCY, WL_LOG = 0, None
SMAPS_DUMP = None   # --smaps-dump DIR: each PSS reading's mappings, PSS per path in KiB (B35 attribution)
SETTLE_S, SETTLE_CAP_S = 0.3, 3.0   # a popup round starts once the popup's window has been still this long (B37)


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


SMAPS_HEAD = re.compile(r"^[0-9a-f]+-[0-9a-f]+ ")
# I93: mappings of the GPU driver's device files. Under gles2 the NVIDIA driver maps its device (and the DRM node) into
# the client, and on two outputs one such mapping reads ~1.9 TiB in the PSS sum (W20): device memory, not the process's
# RAM. They are left out of PSS and USS, and reported on their own (`gpu_map`).
GPU_MAP = re.compile(r"^/dev/(dri/|nvidia|kfd)")


def map_class(path: str) -> str:
    """The class of one mapping, for the breakdown (B35): gpu_map, heap/anon, stack, a shared library, a font, or other
    files."""
    if GPU_MAP.search(path):
        return "gpu_map"
    if path.startswith("/memfd:"):
        return "shm"   # wl_shm pools and Qt's shared buffers: RAM, counted
    if path in ("", "[heap]") or path.startswith("[anon"):
        return "anon"
    if path.startswith("[stack"):
        return "stack"
    if path.startswith("["):
        return "special"
    if ".so" in path:
        return "lib"
    if path.endswith((".ttf", ".otf", ".ttc", ".otc", ".pcf", ".pcf.gz", ".woff", ".woff2")) or "/fonts/" in path:
        return "font"
    if path.endswith(".qmlc") or "/qmlcache" in path or path.endswith(".qml"):
        return "qml"
    return "file"


def mem_kib(pids, per_path=None):
    """PSS and USS of the processes, the GPU driver's mappings left out (I93), and a PSS breakdown by mapping class
    (all in KiB). USS = private clean + private dirty: what goes away with the process. `per_path` (a dict), when given,
    collects PSS per mapped path (anonymous mappings as "[anon]")."""
    pss = uss = 0
    by: dict[str, int] = {}
    path = ""
    for p in pids:
        try:
            text = Path(f"/proc/{p}/smaps").read_text(errors="replace")
        except OSError:
            continue
        cls = "anon"
        for line in text.splitlines():
            if SMAPS_HEAD.match(line):
                parts = line.split(None, 5)
                path = parts[5].strip() if len(parts) > 5 else ""
                cls = map_class(path)
            elif line.startswith("Pss:"):
                v = int(line.split()[1])
                by[cls] = by.get(cls, 0) + v
                if per_path is not None:
                    key = path or "[anon]"
                    per_path[key] = per_path.get(key, 0) + v
                if cls != "gpu_map":
                    pss += v
            elif line.startswith(("Private_Clean:", "Private_Dirty:")) and cls != "gpu_map":
                uss += int(line.split()[1])
    return {"pss": pss, "uss": uss, "by": by}


def pss_kib(pids):
    """PSS without the GPU driver's mappings (I93; was smaps_rollup's Pss, which counts them)."""
    return mem_kib(pids)["pss"]


def mem_fields(prefix, pids):
    """`<prefix>` PSS in MiB plus its USS and breakdown beside it (I93, B35)."""
    paths = {} if SMAPS_DUMP else None
    m = mem_kib(pids, paths)
    if SMAPS_DUMP:
        SMAPS_DUMP.mkdir(parents=True, exist_ok=True)
        top = sorted(paths.items(), key=lambda kv: -kv[1])
        (SMAPS_DUMP / f"{prefix}.txt").write_text("".join(f"{v:9d} {k}\n" for k, v in top))
    return {prefix: round(m["pss"] / 1024, 1), prefix.replace("pss", "uss"): round(m["uss"] / 1024, 1),
            prefix + "_by": {k: round(v / 1024, 1) for k, v in sorted(m["by"].items(), key=lambda kv: -kv[1])}}


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


def binary(name: str) -> str:
    """tools/bench/bin/<name> (copied right after building: the shared target dir is overwritten
    by other worktrees), else target/release."""
    for d in (ROOT / "tools/bench/bin", ROOT / "target/release"):
        if (d / name).exists():
            return str(d / name)
    sys.exit(f"{name} not found: build it and copy it to tools/bench/bin/")


# The real daemon has no mock.* controls: popup and Island morph go through registered actions.
DAEMON = "mock"
POPUP_ACTION = {"mock": ["act", "probe.popup.toggle"], "real": ["act", "island.expand"]}
MORPH_ACTION = {"mock": ["mock", "face", "media"], "real": ["act", "island.next"]}


def kurashi(env, *args):
    return sh(binary("kurashi"), *args, env=env, check=False)


def popup(env):
    return kurashi(env, *POPUP_ACTION[DAEMON])


class IpcProbe:
    """One IPC connection of our own (PROTOCOL v1, NDJSON), opened once (B37): an action sent through it does not pay the
    `kurashi` CLI's start-up and handshake, and every line that arrives is timestamped on arrival. It subscribes to
    `runtime.ui`, so the moment the daemon publishes the change an action made is seen too (the frontend receives the
    same patch on its own connection at about the same time)."""

    def __init__(self, env, docs=("runtime.ui",)):
        import socket
        self.sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        self.sock.connect(env["KURASHI_SOCKET"])
        self.lines: list[tuple[float, dict]] = []
        self.cv = threading.Condition()
        self.seq = 0
        threading.Thread(target=self._reader, daemon=True).start()
        self.send({"t": "hello", "v": 1, "client": "bench-probe", "caps": []})
        self.wait(lambda m: m.get("t") == "welcome", 5)
        for d in docs:
            self.send({"t": "sub", "id": "s:" + d, "doc": d})
            self.wait(lambda m, d=d: m.get("t") == "snap" and m.get("doc") == d, 5)

    def _reader(self):
        buf = b""
        while True:
            try:
                chunk = self.sock.recv(65536)
            except OSError:
                return
            if not chunk:
                return
            now = time.monotonic()
            buf += chunk
            *full, buf = buf.split(b"\n")
            with self.cv:
                for raw in full:
                    try:
                        m = json.loads(raw)
                    except ValueError:
                        continue
                    if m.get("t") == "ping":
                        self.send({"t": "pong"})
                    self.lines.append((now, m))
                self.cv.notify_all()

    def send(self, m):
        self.sock.sendall((json.dumps(m) + "\n").encode())

    def wait(self, pred, timeout, since=0.0):
        """The arrival time of the first line since `since` that matches, or None after `timeout` s."""
        end = time.monotonic() + timeout
        with self.cv:
            while True:
                for t, m in self.lines:
                    if t >= since and pred(m):
                        return t
                left = end - time.monotonic()
                if left <= 0:
                    return None
                self.cv.wait(left)

    def act(self, action, args=None):
        """Sends the action; returns (send time, its id)."""
        self.seq += 1
        aid = f"p{self.seq}"
        t = time.monotonic()
        self.send({"t": "act", "id": aid, "action": action, "args": args or {}})
        return t, aid

    def close(self):
        try:
            self.sock.close()
        except OSError:
            pass


def morph(env):
    return kurashi(env, *MORPH_ACTION[DAEMON])


def start_daemon(env):
    """kurashi-mock or kurashid. The real daemon gets isolated XDG dirs under the sandbox runtime
    dir, the sandbox's own D-Bus (it exports a notification server), no compositor socket, and this
    checkout as data dir (not the path baked in at build time)."""
    run = Path(env["XDG_RUNTIME_DIR"])
    log = open(run / "daemon.log", "w")
    denv = env
    if DAEMON == "mock":
        argv = [binary("kurashi-mock"), "--outputs", "HEADLESS-1,HEADLESS-2"]
    else:
        argv = [binary("kurashid")]
        denv = dict(env, KURASHI_DATA_DIR=str(ROOT))
        for k in ("config", "state", "data", "cache"):
            (run / "xdg" / k).mkdir(parents=True, exist_ok=True)
            denv[f"XDG_{k.upper()}_HOME"] = str(run / "xdg" / k)
        for k in ("NIRI_SOCKET", "HYPRLAND_INSTANCE_SIGNATURE", "DISPLAY"):
            denv.pop(k, None)
        if not denv.get("DBUS_SESSION_BUS_ADDRESS", "").startswith(f"unix:path={run}"):
            sys.exit("refusing to run kurashid without the sandbox's own D-Bus")
        if CONFIG is not None:
            # The daemon reads $XDG_CONFIG_HOME/kurashi/config.toml; the sandbox gets a copy, the source stays as it is.
            (run / "xdg" / "config" / "kurashi").mkdir(parents=True, exist_ok=True)
            shutil.copyfile(CONFIG, run / "xdg" / "config" / "kurashi" / "config.toml")
    p = subprocess.Popen(argv, env=denv, stdout=log, stderr=log)
    for _ in range(100):
        if Path(env["KURASHI_SOCKET"]).exists():
            return p
        time.sleep(0.05)
    stop(p)
    sys.exit(f"{argv[0]} did not create {env['KURASHI_SOCKET']} (see {run}/daemon.log)")


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


# Panels the cycle test opens/closes. Only real-daemon actions exist for them (no mock.*).
CYCLE_OPEN = [["act", "island.expand"], ["act", "notifications.center"], ["act", "launcher.toggle"]]
CYCLE_CLOSE = ["act", "ui.close"]


def cycle_test(env, app, n):
    """Leak gate: n warm-up rounds, then n measured rounds of open/close for every panel; reports
    the PSS growth over the measured rounds. Warm-up is as long as the measurement because
    first-use allocations (glyph/texture/driver caches) keep landing for ~20 opens of a panel and
    then saturate (measured: +5.8 MiB in rounds 1-20, +0.2 MiB per further 20), which is not a
    leak; a real leak keeps growing and shows up in the measured window."""
    def one_round():
        for opener in CYCLE_OPEN:
            kurashi(env, *opener)
            time.sleep(0.25)
            kurashi(env, *CYCLE_CLOSE)
            time.sleep(0.25)

    # W35: on a frontend without the hidden per-output windows these two readings scatter by up to ±15 MiB from run to
    # run (each stays flat for 12 s after its phase, so it is not memory on its way back to the system; docs/BENCH.md).
    for _ in range(n):
        one_round()
    time.sleep(2)
    before = pss_kib(tree(app.pid))
    for _ in range(n):
        one_round()
    time.sleep(2)
    after = pss_kib(tree(app.pid))
    return {"cycle_count": n, "pss_mib_cycle_before": round(before / 1024, 2),
            "pss_mib_cycle_after": round(after / 1024, 2),
            "pss_mib_cycle_growth": round((after - before) / 1024, 2)}


# ---- motion (--script) and the textured shell (--config) -------------------------------------------------------
BUTTONS_OK = ("left", "middle", "right")
POINTER_ARGS = {"move": 2, "click": 3, "sweep": 5}   # arguments after the verb (wl_pointer.py)
# Theme tokens recorded per run, so a report can show the config took effect (Shōjiki: what is in effect).
TOKENS = ("light.mode", "texture.map", "texture.ink_map", "texture.shell", "texture.overlay", "texture.depth",
          "texture.shadow", "texture.controls", "texture.sheet", "texture.amp", "pen.pressure", "pen.text_pressure",
          "pen.text_breaks", "pen.text_fade", "pen.text_wobble")
MOTION_TAIL = 1.5   # seconds the window runs on after the last action, when the script gives no `window`


def load1():
    return float(Path("/proc/loadavg").read_text().split()[0])


def wait_quiet(limit, timeout):
    """A quiet machine (docs/BENCH.md): waits until the 1-minute load average is below `limit`, for `timeout` s at
    most. A run that goes ahead over the limit says so (quiet: false), so its numbers are labelled, not hidden."""
    start, t0 = load1(), time.monotonic()
    while load1() >= limit and time.monotonic() - t0 < timeout:
        time.sleep(5)
    now = load1()
    return {"load1_start": start, "load1_go": now, "waited_s": round(time.monotonic() - t0, 1),
            "limit": limit, "quiet": now < limit}


def action_seconds(body):
    """Checks one action (its argv, without the time) and returns how long it runs: a sweep's seconds, else 0."""
    verb, args = body[0], body[1:]
    if verb == "act":
        if len(args) not in (1, 2):
            raise ValueError("act takes an action name and optional JSON")
        return 0.0
    if verb not in POINTER_ARGS or len(args) != POINTER_ARGS[verb]:
        raise ValueError(f"not an action: {' '.join(body)}")
    if verb == "click" and args[2] not in BUTTONS_OK:
        raise ValueError("click takes left, middle or right")
    for n in (args[:4] if verb == "sweep" else args[:2]):
        int(n)
    return float(args[4]) if verb == "sweep" else 0.0


def load_script(path):
    """A motion script. `pre <action>` runs before the warm-up ends (the pointer is created and parked there);
    `<t> <action>` runs t seconds into the motion window; `window <s>` sets the window's length (default: the last
    action's end plus 1.5 s). Actions: `act <name> [json]` (kurashi act), `move x y`, `click x y <button>`,
    `sweep x0 y0 x1 y1 <s>` (wl_pointer.py). Quote JSON with single quotes. `#` starts a comment line."""
    pre, steps, window = [], [], None
    for n, raw in enumerate(Path(path).read_text().splitlines(), 1):
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        try:
            parts = shlex.split(line)
            if parts[0] == "window":
                if len(parts) != 2:
                    raise ValueError("window takes one number of seconds")
                window = float(parts[1])
            elif parts[0] == "pre":
                action_seconds(parts[1:])
                pre.append(parts[1:])
            else:
                steps.append((float(parts[0]), parts[1:], action_seconds(parts[1:])))
        except (ValueError, IndexError) as e:
            sys.exit(f"{path}:{n}: {e}")
    steps.sort(key=lambda s: s[0])
    end = max([t + d for t, _, d in steps] or [0.0])
    if window is None:
        window = end + MOTION_TAIL
    elif window < end:
        sys.exit(f"{path}: window {window} s ends before its last action ({end} s)")
    return {"pre": pre, "steps": [(t, body) for t, body, _ in steps], "window": window}


class Motion:
    """A script's actions in one sandbox: one virtual pointer (wl_pointer.py --serve, created by the first pointer
    action, its log in the sandbox's runtime dir) and the timed actions."""

    def __init__(self, env, script):
        self.env, self.script, self.pointer = env, script, None
        self.errors: list[str] = []   # refused actions (kurashi act exits 1 on an error reply): reported, not hidden

    def do(self, body):
        if body[0] == "act":
            r = kurashi(self.env, "act", *body[1:])
            if r.returncode != 0:
                self.errors.append(f"{' '.join(body)}: {(r.stdout or r.stderr or '').strip()[:200]}")
            return
        if self.pointer is None:
            log = open(Path(self.env["XDG_RUNTIME_DIR"]) / "pointer.log", "w")
            self.pointer = subprocess.Popen([sys.executable, str(ROOT / "tools/bench/wl_pointer.py"), "--serve"],
                                            env=self.env, stdin=subprocess.PIPE, stdout=subprocess.DEVNULL,
                                            stderr=log, text=True)
            time.sleep(1.0)   # the virtual pointer exists ~0.5 s after its creation (wl_pointer.Pointer)
        self.pointer.stdin.write(" ".join(body) + "\n")
        self.pointer.stdin.flush()

    def pre(self):
        for body in self.script["pre"]:
            self.do(body)

    def play(self, start, end):
        """Runs the timed actions over the window; start() and end() run at its two ends (the caller samples there)."""
        start()
        t0 = time.monotonic()
        for at, body in self.script["steps"]:
            wait = t0 + at - time.monotonic()
            if wait > 0:
                time.sleep(wait)
            self.do(body)
        wait = t0 + self.script["window"] - time.monotonic()
        if wait > 0:
            time.sleep(wait)
        end()

    def close(self):
        if self.pointer is not None:
            self.pointer.stdin.close()   # EOF ends the serve loop; the virtual pointer goes with its socket
            try:
                self.pointer.wait(timeout=5)
            except subprocess.TimeoutExpired:
                self.pointer.kill()
            self.pointer = None


def theme_doc(env):
    """The theme document as the daemon has it now (the first snapshot of `kurashi sub theme`), or None."""
    p = subprocess.Popen([binary("kurashi"), "sub", "theme", "--count", "0", "--json"], env=env,
                         stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True)
    try:
        line = p.stdout.readline() if select.select([p.stdout], [], [], 5)[0] else ""
    finally:
        p.kill()
        p.wait()
    try:
        doc = json.loads(line)
    except ValueError:   # no snapshot yet (an empty or non-JSON line): the caller treats it as "not ready"
        return None
    return doc.get("data", doc) if isinstance(doc, dict) else None


def wait_texture(env, limit=60.0):
    """The daemon makes a material's relief tile in the background on first use, so a window that starts before it
    is ready would measure the generation. Waits while the theme says 'texture: generating' (for `limit` s at most).
    Returns (seconds waited, the TOKENS in effect, the theme's notes)."""
    t0 = time.monotonic()
    while True:
        doc = theme_doc(env) or {}
        notes = doc.get("notes", [])
        if not any("generating" in json.dumps(n) for n in notes) or time.monotonic() - t0 > limit:
            break
        time.sleep(0.5)
    tokens = doc.get("tokens", {})
    return round(time.monotonic() - t0, 2), {k: tokens.get(k) for k in TOKENS}, notes


def pass_a(name, cmd, warmup, idle, cycles=20):
    sb = Sandbox(f"{SANDBOX_PREFIX}{name}-a-{os.getpid()}")  # pid: parallel runs never share (and kill) a sandbox
    mock = start_daemon(sb.env)
    motion = Motion(sb.env, SCRIPT) if SCRIPT else None
    try:
        app = subprocess.Popen(cmd, env=sb.env, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        if motion:
            motion.pre()
        time.sleep(warmup)
        if app.poll() is not None:
            return {"error": f"exited early with {app.returncode}"}
        if mock.poll() is not None:
            return {"error": f"daemon exited early with {mock.returncode} (see daemon.log in the sandbox)"}
        texture = wait_texture(sb.env) if CONFIG else None
        pids = tree(app.pid)
        dpids = tree(mock.pid)
        t0, c0, s0 = time.monotonic(), cpu_ticks(pids), ctx_switches(pids)
        dc0, ds0 = cpu_ticks(dpids), ctx_switches(dpids)
        time.sleep(idle)
        pids = tree(app.pid)
        dpids = tree(mock.pid)
        dt = time.monotonic() - t0
        r = {
            "idle_cpu_pct": round(100 * (cpu_ticks(pids) - c0) / CLK_TCK / dt, 3),
            "wakeups_per_s": max(0.0, round((ctx_switches(pids) - s0) / dt, 1)),
            "gpu_mib": gpu_mib(set(pids)),
            "processes": len(pids),
            "idle_window_s": round(dt, 1),
            **mem_fields("pss_mib_1out", pids),
        }
        if DAEMON == "real":
            # Reported separately; the "daemon + frontend" CPU budget uses the sum.
            r["daemon_idle_cpu_pct"] = round(100 * (cpu_ticks(dpids) - dc0) / CLK_TCK / dt, 3)
            r["daemon_wakeups_per_s"] = max(0.0, round((ctx_switches(dpids) - ds0) / dt, 1))
            r["daemon_pss_mib"] = round(pss_kib(dpids) / 1024, 1)
            r["idle_cpu_pct_total"] = round(r["idle_cpu_pct"] + r["daemon_idle_cpu_pct"], 3)
        popup(sb.env)
        time.sleep(2)
        r.update(mem_fields("pss_mib_popup", tree(app.pid)))
        popup(sb.env)
        time.sleep(2)
        # Baseline for the per-output delta: popup memory that stays resident after closing must
        # not be charged to the second output.
        r.update(mem_fields("pss_mib_popup_closed", tree(app.pid)))
        sb.add_output()
        time.sleep(4)
        r.update(mem_fields("pss_mib_2out", tree(app.pid)))
        # A third output: one hotplug delta scatters by about ±1 MiB (heap growth that is not
        # per output), so the gate takes the mean of two (budget.py, B7).
        sb.add_output()
        time.sleep(4)
        r.update(mem_fields("pss_mib_3out", tree(app.pid)))
        r["survived_hotplug"] = app.poll() is None
        if DAEMON == "real" and cycles > 0:
            r.update(cycle_test(sb.env, app, cycles))
        if DAEMON == "real":
            r["daemon_pss_mib_end"] = round(pss_kib(tree(mock.pid)) / 1024, 1)
        if texture:
            r.update(texture_wait_s=texture[0], tokens=texture[1], theme_notes=texture[2])
        stop(app)
        return r
    finally:
        if motion:
            motion.close()
        stop(mock)
        sb.stop()


def pass_b(name, cmd, warmup, idle):
    sb = Sandbox(f"{SANDBOX_PREFIX}{name}-b-{os.getpid()}")  # pid: parallel runs never share (and kill) a sandbox
    env = dict(sb.env, WAYLAND_DEBUG="client")
    mock = start_daemon(sb.env)
    motion = Motion(sb.env, SCRIPT) if SCRIPT else None
    events: list[tuple[float, int]] = []
    debug_lines = [0]          # any libwayland debug line at all
    mapped: dict[int, bool] = {}   # layer-shell wl_surface id -> last attach had a buffer
    layer_surfaces: set[int] = set()
    names: dict[int, str] = {}     # layer-shell wl_surface id -> its namespace (which window commits)
    lock = threading.Lock()
    try:
        t_launch = time.monotonic()
        # With --wl-log the frontend's stdout (its log lines) joins the stderr pipe, so they are timestamped alike.
        app = subprocess.Popen(["sh", "-c", 'exec "$@" 1>&2', "sh", *cmd] if WL_LOG else cmd, env=env, stdout=subprocess.DEVNULL, stderr=subprocess.PIPE,
                               text=True, errors="replace", bufsize=1)

        wl_log = open(WL_LOG, "w") if WL_LOG else None

        def reader():
            for line in app.stderr:
                now = time.monotonic()
                if wl_log:
                    wl_log.write(f"{now - t_launch:.4f} {line}")
                with lock:
                    if WL_DEBUG.match(line):
                        debug_lines[0] += 1
                    m = COMMIT.search(line)
                    if m:
                        events.append((now, int(m.group(1))))
                        continue
                    m = LAYER.search(line)
                    if m:
                        layer_surfaces.add(int(m.group(1)))
                        names[int(m.group(1))] = m.group(2) or "?"
                        continue
                    m = ATTACH.search(line)
                    if m:
                        mapped[int(m.group(1))] = m.group(2) != "nil"
        threading.Thread(target=reader, daemon=True).start()
        if motion:
            motion.pre()   # after the reader: the frontend's debug output must keep draining while the pointer appears

        def commits_since(t):
            with lock:
                return [e for e in events if e[0] >= t]

        time.sleep(warmup)
        if app.poll() is not None:
            return {"error": f"exited early with {app.returncode}"}
        if mock.poll() is not None:
            return {"error": f"daemon exited early with {mock.returncode}"}
        if CONFIG:
            wait_texture(sb.env)   # the relief tile is generated before the idle window (see wait_texture)
        with lock:
            startup_ms = round((events[0][0] - t_launch) * 1000) if events else None
            measurable = debug_lines[0] > 0
        if not measurable:
            # A client that prints no WAYLAND_DEBUG (not libwayland, or a stripped build) would
            # read as 0 commits: say so instead (Shōjiki).
            stop(app)
            return {"commits": "unmeasurable", "startup_ms": None,
                    "note": "no WAYLAND_DEBUG=client output from the frontend"}
        t0 = time.monotonic()
        time.sleep(idle)
        idle_events = commits_since(t0)
        with lock:
            mapped_now = sorted(i for i in layer_surfaces if mapped.get(i))
        per_surface: dict[int, int] = {}
        for _, sid in idle_events:
            per_surface[sid] = per_surface.get(sid, 0) + 1
        # B34: which window commits at idle, and when (wall clock): a burst at hh:mm:00 is the bar clock's minute flip.
        wall = time.time() - time.monotonic()
        bursts, open_burst = [], {}
        with lock:
            idle_named = {f"{names.get(s, '?')}#{s}": n for s, n in per_surface.items()}
            for t, sid in idle_events:
                b = open_burst.get(sid)
                if b is None or t - b["_last"] > 0.2:
                    b = {"surface": f"{names.get(sid, '?')}#{sid}", "_first": t, "_last": t, "commits": 0}
                    bursts.append(b)
                    open_burst[sid] = b
                b["_last"], b["commits"] = t, b["commits"] + 1
        idle_bursts = [{"surface": b["surface"], "commits": b["commits"],
                        "at": time.strftime("%H:%M:%S", time.localtime(wall + b["_first"]))
                        + f".{int((wall + b['_first']) % 1 * 1000):03d}",
                        "span_ms": round((b["_last"] - b["_first"]) * 1000)} for b in bursts]

        # B37 (W35): popup input → first commit of the popup's own window (kurashi-stage; any window for a frontend that has
        # none, e.g. the bake-off probes), each round from rest: the Stage must have committed nothing for SETTLE_S first,
        # else "the first commit after the input" is the next frame of the previous close still folding (W33 measured
        # those). The gated number stays the CLI path (`kurashi act`: process start, handshake, daemon, frontend), as
        # before; our own connection (IpcProbe) timestamps the daemon's runtime.ui patch in the same rounds, and --latency
        # adds rounds sent through that open connection, so the parts can be told apart: CLI → patch, patch → commit.
        probe = None
        try:
            probe = IpcProbe(sb.env) if DAEMON == "real" else None
        except OSError:
            probe = None

        def is_ui_patch(m):
            return m.get("t") in ("patch", "snap") and m.get("doc") == "runtime.ui"

        def stage_ids():
            with lock:
                ids = {i for i, n in names.items() if n == "kurashi-stage"}
            return ids or None   # None: count every window

        def settle():
            """Waits until the popup's window has been still for SETTLE_S (at most SETTLE_CAP_S); True if it was."""
            end = time.monotonic() + SETTLE_CAP_S
            while True:
                ids = stage_ids()
                with lock:
                    last = max([t for t, sid in events if ids is None or sid in ids] or [0.0])
                now = time.monotonic()
                if now - last >= SETTLE_S:
                    return True
                if now >= end:
                    return False
                time.sleep(0.05)

        def first_commit(since):
            ids = stage_ids()
            return next(((t, sid) for t, sid in commits_since(since) if ids is None or sid in ids), None)

        latencies, cli_patch, patch_commit, unsettled = [], [], [], 0
        for _ in range(5):
            unsettled += not settle()
            t = time.monotonic()
            popup(sb.env)
            time.sleep(0.6)
            fc = first_commit(t)
            if fc:
                latencies.append((fc[0] - t) * 1000)
            tp = probe.wait(is_ui_patch, 0, since=t) if probe else None
            if tp is not None:
                cli_patch.append((tp - t) * 1000)
                if fc and fc[0] >= tp:
                    patch_commit.append((fc[0] - tp) * 1000)
            popup(sb.env)
        settle()

        def med(xs, nd=1):
            return round(statistics.median(xs), nd) if xs else None
        ipc = {"popup_rounds_unsettled": unsettled}
        if probe and LATENCY > 0:
            send_commit, send_done, send_patch, ipc_patch_commit, sent_at, ipc_unsettled = [], [], [], [], [], 0
            action = POPUP_ACTION[DAEMON][1]
            for _ in range(LATENCY):
                ipc_unsettled += not settle()
                t, aid = probe.act(action)
                sent_at.append(round(t - t_launch, 4))
                time.sleep(0.6)
                fc = first_commit(t)
                td = probe.wait(lambda m, aid=aid: m.get("id") == aid and m.get("t") in ("done", "err"), 0, since=t)
                tp = probe.wait(is_ui_patch, 0, since=t)
                if fc:
                    send_commit.append((fc[0] - t) * 1000)
                if td is not None:
                    send_done.append((td - t) * 1000)
                if tp is not None:
                    send_patch.append((tp - t) * 1000)
                    if fc and fc[0] >= tp:
                        ipc_patch_commit.append((fc[0] - tp) * 1000)
                probe.act(action)
            settle()
            ipc.update({"latency_rounds": LATENCY, "latency_rounds_unsettled": ipc_unsettled,
                        "ipc_send_to_commit_ms_median": med(send_commit, 2),
                        "ipc_send_to_commit_ms_all": [round(x, 1) for x in send_commit],
                        "ipc_send_to_done_ms_median": med(send_done, 2),
                        "ipc_send_to_patch_ms_median": med(send_patch, 2),
                        "ipc_patch_to_commit_ms_median": med(ipc_patch_commit, 2),
                        "ipc_patch_to_commit_ms_all": [round(x, 1) for x in ipc_patch_commit],
                        "ipc_sent_at_s": sent_at})   # since launch, as the --wl-log timestamps
        if probe:
            ipc["cli_to_patch_ms_median"] = med(cli_patch)
            ipc["cli_to_patch_ms_all"] = [round(x, 1) for x in cli_patch]
            ipc["cli_patch_to_commit_ms_median"] = med(patch_commit)
            probe.close()

        t = time.monotonic()
        morph(sb.env)
        time.sleep(1.5)
        morph_t = [e[0] for e in commits_since(t)]
        gaps = sorted((b - a) * 1000 for a, b in zip(morph_t, morph_t[1:]))
        motion_fields = {}
        if motion:
            # Frames while the script plays, after the idle and popup measurements (the state they left is the rest).
            marks = {}
            motion.play(lambda: marks.update(t0=time.monotonic()), lambda: marks.update(t1=time.monotonic()))
            with lock:
                inside = [e for e in events if marks["t0"] <= e[0] <= marks["t1"]]
            by_surface: dict[int, int] = {}
            for _, sid in inside:
                by_surface[sid] = by_surface.get(sid, 0) + 1
            span = marks["t1"] - marks["t0"]
            motion_fields = {"motion_window_s": round(span, 2), "motion_commits": len(inside),
                             "motion_commits_per_s": round(len(inside) / span, 2),
                             "motion_commits_by_surface": by_surface, "motion_act_errors": motion.errors}
        stop(app)
        return {
            "startup_ms": startup_ms,
            "idle_commits_per_s": round(len(idle_events) / idle, 2),
            "idle_commits_by_surface": per_surface,
            "idle_commits_by_layer": idle_named,
            "idle_bursts": idle_bursts,
            "popup_latency_ms_median": round(statistics.median(latencies), 1) if latencies else None,
            "popup_latency_ms_all": [round(x, 1) for x in latencies],
            **ipc,
            "mapped_layer_surfaces_idle": len(mapped_now),   # 1 sandbox output
            "morph_commits": len(morph_t),
            "morph_frame_ms_p50": round(gaps[len(gaps) // 2], 1) if gaps else None,
            "morph_frame_ms_p99": round(gaps[min(len(gaps) - 1, int(len(gaps) * 0.99))], 1) if gaps else None,
            **motion_fields,
        }
    finally:
        if motion:
            motion.close()
        stop(mock)
        sb.stop()


def pass_c(name, cmd, warmup, idle):
    if not shutil.which("strace"):
        return {"error": "strace missing"}
    sb = Sandbox(f"{SANDBOX_PREFIX}{name}-c-{os.getpid()}")  # pid: parallel runs never share (and kill) a sandbox
    mock = start_daemon(sb.env)
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


def pass_m(name, cmd, warmup):
    """Motion, clean (no WAYLAND_DEBUG): the frontend's and the daemon's CPU and wakeups while the script plays, and
    their PSS after it. Its own sandbox; the same daemon and config as the other passes."""
    sb = Sandbox(f"{SANDBOX_PREFIX}{name}-m-{os.getpid()}")  # pid: parallel runs never share (and kill) a sandbox
    mock = start_daemon(sb.env)
    motion = Motion(sb.env, SCRIPT)
    try:
        app = subprocess.Popen(cmd, env=sb.env, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        motion.pre()
        time.sleep(warmup)
        if app.poll() is not None:
            return {"error": f"exited early with {app.returncode}"}
        if mock.poll() is not None:
            return {"error": f"daemon exited early with {mock.returncode}"}
        if CONFIG:
            wait_texture(sb.env)
        marks: dict = {}

        def start():
            marks["t0"] = time.monotonic()
            marks["p0"], marks["d0"] = tree(app.pid), tree(mock.pid)
            marks["c0"], marks["dc0"] = cpu_ticks(marks["p0"]), cpu_ticks(marks["d0"])
            marks["s0"], marks["ds0"] = ctx_switches(marks["p0"]), ctx_switches(marks["d0"])

        def end():
            marks["t1"] = time.monotonic()
            pids, dpids = tree(app.pid), tree(mock.pid)
            marks["c1"], marks["dc1"] = cpu_ticks(pids), cpu_ticks(dpids)
            marks["s1"], marks["ds1"] = ctx_switches(pids), ctx_switches(dpids)
            marks["pss"], marks["dpss"] = pss_kib(pids), pss_kib(dpids)

        motion.play(start, end)
        dt = marks["t1"] - marks["t0"]
        r = {
            "motion_window_s": round(dt, 2),
            "motion_cpu_pct": round(100 * (marks["c1"] - marks["c0"]) / CLK_TCK / dt, 3),
            "motion_wakeups_per_s": max(0.0, round((marks["s1"] - marks["s0"]) / dt, 1)),
            "pss_mib_motion_end": round(marks["pss"] / 1024, 1),
            "motion_act_errors": motion.errors,
        }
        if DAEMON == "real":
            r["daemon_motion_cpu_pct"] = round(100 * (marks["dc1"] - marks["dc0"]) / CLK_TCK / dt, 3)
            r["daemon_motion_wakeups_per_s"] = max(0.0, round((marks["ds1"] - marks["ds0"]) / dt, 1))
            r["motion_cpu_pct_total"] = round(r["motion_cpu_pct"] + r["daemon_motion_cpu_pct"], 3)
            r["daemon_pss_mib_motion_end"] = round(marks["dpss"] / 1024, 1)
        stop(app)
        return r
    finally:
        motion.close()
        stop(mock)
        sb.stop()


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--name", required=True)
    ap.add_argument("--warmup", type=float, default=10)
    ap.add_argument("--idle", type=float, default=30)
    ap.add_argument("--passes", default="abc",
                    help="a clean, b WAYLAND_DEBUG (frames), c strace, m motion (clean; needs --script)")
    ap.add_argument("--cycles", type=int, default=20,
                    help="open/close cycles per panel for the leak row (real daemon, pass A; 0 = skip)")
    ap.add_argument("--daemon", choices=("mock", "real"), default="mock",
                    help="kurashi-mock (default) or the built kurashid")
    ap.add_argument("--config", type=Path,
                    help="real daemon: this config.toml is the user config (a copy goes into the sandbox)")
    ap.add_argument("--script", type=Path,
                    help="real daemon: a motion script (load_script); pass m, and the end of pass b, play it")
    ap.add_argument("--max-load", type=float,
                    help="wait until the 1-minute load average is below this before the run (recorded)")
    ap.add_argument("--load-wait", type=float, default=600,
                    help="seconds --max-load may wait; the run goes ahead after that, marked quiet: false")
    ap.add_argument("--sandbox-prefix", default="bench-",
                    help="sandbox names are <prefix><name>-<pass>-<pid> (default bench-)")
    ap.add_argument("--latency", type=int, default=0,
                    help="pass b, real daemon: N more popup rounds sent through one open IPC connection (B37)")
    ap.add_argument("--wl-log", type=Path, help="pass b: write the frontend's WAYLAND_DEBUG lines, timestamped, here")
    ap.add_argument("--smaps-dump", type=Path, help="pass a: write each PSS reading's mappings (KiB per path) to DIR")
    ap.add_argument("--popup-action", help="real daemon: the action that toggles the popup (default island.expand)")
    ap.add_argument("cmd", nargs=argparse.REMAINDER)
    a = ap.parse_args()
    global DAEMON, SANDBOX_PREFIX, CONFIG, SCRIPT, LATENCY, WL_LOG, SMAPS_DUMP
    DAEMON = a.daemon
    LATENCY, WL_LOG, SMAPS_DUMP = a.latency, a.wl_log, a.smaps_dump
    if a.popup_action:
        POPUP_ACTION["real"] = ["act", a.popup_action]
    SANDBOX_PREFIX = a.sandbox_prefix
    if (a.config or a.script) and DAEMON != "real":
        sys.exit("--config and --script need --daemon real (the mock has no such actions)")
    if a.config is not None and not a.config.is_file():
        sys.exit(f"--config: {a.config} is not a file")
    CONFIG = a.config
    SCRIPT = load_script(a.script) if a.script else None
    if "m" in a.passes and SCRIPT is None:
        sys.exit("--passes m needs --script")
    cmd = a.cmd[1:] if a.cmd[:1] == ["--"] else a.cmd
    if not cmd:
        sys.exit("missing frontend command after --")
    RESULTS.mkdir(parents=True, exist_ok=True)
    result = {"name": a.name, "cmd": cmd, "daemon": a.daemon, "date": time.strftime("%Y-%m-%d %H:%M"),
              "commit": sh("git", "-C", str(ROOT), "rev-parse", "--short", "HEAD", check=False).stdout.strip()}
    if CONFIG is not None:
        result["config"] = str(a.config)
    if SCRIPT is not None:
        result["script"] = str(a.script)
    if a.max_load is not None:
        result["quiet"] = wait_quiet(a.max_load, a.load_wait)
        print(f"[{a.name}] load1 {result['quiet']['load1_go']} (limit {a.max_load}, waited "
              f"{result['quiet']['waited_s']} s)", file=sys.stderr)
    for p, fn in (("a", pass_a), ("b", pass_b), ("c", pass_c), ("m", pass_m)):
        if p in a.passes:
            print(f"[{a.name}] pass {p} …", file=sys.stderr)
            result[f"pass_{p}"] = (fn(a.name, cmd, a.warmup, a.idle, a.cycles) if p == "a"
                                   else fn(a.name, cmd, a.warmup) if p == "m"
                                   else fn(a.name, cmd, a.warmup, a.idle))
    if a.max_load is not None:
        result["quiet"]["load1_end"] = round(load1(), 2)
    out = RESULTS / f"{a.name}.json"
    out.write_text(json.dumps(result, indent=2, ensure_ascii=False))
    print(json.dumps(result, indent=2, ensure_ascii=False))


if __name__ == "__main__":
    main()
