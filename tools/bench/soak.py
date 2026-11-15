#!/usr/bin/env python3
"""Soak: what the real stack holds after an hour of ordinary use (W90, B147). The budgets are measured seconds after a
start; this drives the shell through the same round of use over and over in the headless sandbox and reads each
process's memory once a minute.

  python3 tools/bench/soak.py --name soak [--minutes 60] [--warmup-min 10] [--interval 60] -- frontend/launch.sh

The sandbox, the daemon's start and the /proc readers are measure.py's. What the sandbox lacks is stood in for: a fake
MPRIS player with covers (kurashi-mock's example `fake_mpris_art`, when built), the wallpaper backend
(tools/testkit/fakebin), pictures made here, notifications sent on the sandbox's bus. One round (about 20 s):

  the launcher, quick settings, the notification centre, the island's card and a mod's panel opened and closed · the
  next island face · a workspace switch · a notification · every 3rd round the player's next cover · every 5th the
  wallpaper's next (a 4K picture: the theme is extracted again) · every 7th another material (`theme.texture.kind`) ·
  every 10th Settings' material swatches watched (`theme.previews`) for a few seconds.

An action the daemon does not have is left out and named in the result (`skipped`), never silently.

Result: tools/bench/results/soak-<name>.json — every sample, and per process the growth in MiB per hour after the
warm-up (least squares over the samples; first and last beside it). The budget rows "Soak growth …" in docs/BENCH.md
are checked (budget.py's table reader); exit 1 when a process grows faster than its row.

  --daemon-wrap 'heaptrack -o /tmp/kd'   start kurashid under a profiler (the figures then include its overhead)
  --skip a,b / --only a,b                leave steps out of the round, to find the one that grows
  --round-pause S                        seconds between a round's steps (default 0.4)
"""
from __future__ import annotations

import argparse, json, os, shlex, shutil, subprocess, sys, tempfile, threading, time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import measure as m          # noqa: E402  (the sandbox, start_daemon, the /proc readers)
import budget                # noqa: E402  (the budget table's reader)

ROOT = m.ROOT
FAKEBIN = ROOT / "tools/testkit/fakebin"
MATERIALS = ("paper", "fabric", "stone", "wood", "leather", "metal", "canvas", "wool")
STEPS = ("launcher", "quick", "center", "island", "panel", "face", "workspace", "notify", "cover", "wallpaper",
         "material", "previews")
BUDGET_ROWS = {"daemon": "Soak growth per hour, daemon", "frontend": "Soak growth per hour, frontend"}


def make_pictures(folder: Path, n: int, size: str) -> list[Path]:
    """`n` pictures of `size` that differ in colour and do not compress to nothing (ImageMagick's plasma, seeded)."""
    folder.mkdir(parents=True, exist_ok=True)
    if not shutil.which("magick"):
        sys.exit("soak: magick is not on PATH (run inside `nix develop`)")
    out = []
    for i in range(n):
        p = folder / f"soak-{i:02d}.png"
        hue = (i * 360 // n + 20) % 360
        m.sh("magick", "-size", size, "-seed", str(i + 1), "plasma:fractal", "-modulate", f"100,120,{100 + hue // 2}",
             "-fill", f"hsl({hue},60%,45%)", "-colorize", "35", str(p))
        out.append(p)
    return out


def write_config(env, pics: Path, mods: list[str]):
    cfg = Path(env["XDG_RUNTIME_DIR"]) / "xdg/config/kurashi"
    cfg.mkdir(parents=True, exist_ok=True)
    (cfg / "config.toml").write_text(
        f"[mods]\nloaded = {json.dumps(mods)}\nenabled = {json.dumps(mods)}\n\n"
        f"[mods.wallpaper]\nfolders = \"{pics}\"\nbackend = \"awww\"\n\n"
        f"[theme.texture]\nkind = \"{MATERIALS[0]}\"\n")


class Use:
    """One round of ordinary use, against the actions the daemon really has."""

    def __init__(self, env, pause, covers, player, skip=()):
        self.env, self.pause, self.covers, self.player = env, pause, covers, player
        self.skip = set(skip)
        self.round_min = 5.0
        self.round = 0
        listed = m.kurashi(env, "--json", "act", "--list").stdout
        try:
            self.have = {a["id"] for a in json.loads(listed)}
        except (ValueError, TypeError, KeyError):
            self.have = set()
        self.skipped: set[str] = set()
        self.failed: dict[str, int] = {}
        self.sway = env.get("SWAYSOCK") and shutil.which("swaymsg")

    def act(self, action, args=None):
        if self.have and action not in self.have:
            self.skipped.add(action)
            return
        r = m.kurashi(self.env, "act", action, json.dumps(args or {}))
        if r.returncode != 0:
            self.failed[action] = self.failed.get(action, 0) + 1
        time.sleep(self.pause)

    def open_close(self, action, args=None):
        self.act(action, args)
        self.act("ui.close")

    def notify(self, n):
        m.sh("gdbus", "call", "--session", "--dest", "org.freedesktop.Notifications", "--object-path",
             "/org/freedesktop/Notifications", "--method", "org.freedesktop.Notifications.Notify", "Soak", "0", "",
             f"Message {n}", f"The {n}th of the soak, with a body of a line or so.", "[]", "{}", "4000",
             env=self.env, check=False)

    def previews(self, seconds):
        """Settings' material cards: a subscriber of `theme.previews` for a few seconds (the swatches are made)."""
        try:
            subprocess.run([m.binary("kurashi"), "sub", "theme.previews"], env=self.env, timeout=seconds,
                           stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        except subprocess.TimeoutExpired:
            pass

    def one(self):
        self.round += 1
        n = self.round
        started = time.monotonic()
        on = lambda step: step not in self.skip   # noqa: E731
        if on("launcher"):
            self.open_close("launcher.toggle")
        if on("quick"):
            self.open_close("quick.toggle")
        if on("center"):
            self.open_close("notifications.center")
        if on("island"):
            self.open_close("island.expand")
        if on("panel"):
            self.open_close("mod.panel.open", {"id": "timer", "panel": "timer"})
        if on("face"):
            self.act("island.next")
        if on("workspace"):
            if self.sway:
                m.sh("swaymsg", "workspace", "number", str(1 + n % 4), env=self.env, check=False)
            else:
                self.act("workspace.focus", {"idx": 1 + n % 4})
        if on("notify"):
            self.notify(n)
        if on("cover") and n % 3 == 0 and self.player and self.covers:
            try:
                self.player.stdin.write(f"art file://{self.covers[(n // 3) % len(self.covers)]}\n")
                self.player.stdin.flush()
            except OSError:
                self.failed["player"] = self.failed.get("player", 0) + 1
        if on("wallpaper") and n % 5 == 0:
            self.act("wallpaper.next")
        if on("material") and n % 7 == 0:
            r = m.kurashi(self.env, "set", "theme.texture.kind", MATERIALS[(n // 7) % len(MATERIALS)])
            if r.returncode != 0:
                self.failed["set theme.texture.kind"] = self.failed.get("set theme.texture.kind", 0) + 1
        if on("previews") and n % 10 == 0:
            self.previews(4)
        # Ordinary use, not a flood: a round with few steps left in it still takes its time.
        spent = time.monotonic() - started
        if spent < self.round_min:
            time.sleep(self.round_min - spent)


def slope_per_hour(samples, key, group, after_s):
    """Least-squares growth of `group`'s `key` in MiB per hour over the samples taken after `after_s`."""
    pts = [(s["t"], s[group][key]) for s in samples if s["t"] >= after_s and group in s]
    if len(pts) < 3:
        return None
    n = len(pts)
    mx, my = sum(p[0] for p in pts) / n, sum(p[1] for p in pts) / n
    den = sum((p[0] - mx) ** 2 for p in pts)
    return round(3600 * sum((p[0] - mx) * (p[1] - my) for p in pts) / den, 2) if den else None


def read(pids):
    r = m.mem_kib(pids)
    return {"pss": round(r["pss"] / 1024, 1), "uss": round(r["uss"] / 1024, 1),
            "anon": round(r["by"].get("anon", 0) / 1024, 1), "procs": len(pids)}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--name", default="soak")
    ap.add_argument("--minutes", type=float, default=60)
    ap.add_argument("--warmup-min", type=float, default=10, help="samples before this do not count toward the growth")
    ap.add_argument("--interval", type=float, default=60, help="seconds between samples")
    ap.add_argument("--round-pause", type=float, default=0.4)
    ap.add_argument("--pictures", type=int, default=8)
    ap.add_argument("--picture-size", default="3840x2160")
    ap.add_argument("--mods", default="timer,wallpaper,media,sysmon,calendar")
    ap.add_argument("--skip", default="", help=f"steps left out of the round, comma separated: {', '.join(STEPS)}")
    ap.add_argument("--only", default="", help="the steps of the round, the rest left out (`--only none`: at rest)")
    ap.add_argument("--daemon-wrap", help="a command kurashid is started under, e.g. 'heaptrack -o /tmp/kd'")
    ap.add_argument("--max-load", type=float)
    ap.add_argument("--load-wait", type=float, default=600)
    ap.add_argument("--keep", action="store_true", help="leave the sandbox dir (logs) after the run")
    ap.add_argument("cmd", nargs=argparse.REMAINDER)
    a = ap.parse_args()
    cmd = a.cmd[1:] if a.cmd[:1] == ["--"] else a.cmd
    if not cmd:
        sys.exit("missing frontend command after --")
    m.DAEMON = "real"
    result = {"name": a.name, "cmd": cmd, "date": time.strftime("%Y-%m-%d %H:%M"), "minutes": a.minutes,
              "warmup_min": a.warmup_min, "interval_s": a.interval,
              "commit": m.sh("git", "-C", str(ROOT), "rev-parse", "--short", "HEAD", check=False).stdout.strip()}
    if a.max_load is not None:
        result["quiet"] = m.wait_quiet(a.max_load, a.load_wait)

    wrap_dir = None
    if a.daemon_wrap:
        # measure.binary() looks in $KURASHI_BIN_DIR first: a folder whose `kurashid` starts the real one under the wrap.
        real = m.binary("kurashid")
        wrap_dir = Path(tempfile.mkdtemp(prefix="soak-wrap-"))
        for b in ("kurashi", "kurashi-mock"):
            os.symlink(m.binary(b), wrap_dir / b)
        (wrap_dir / "kurashid").write_text(f"#!/bin/sh\nexec {a.daemon_wrap} {shlex.quote(real)} \"$@\"\n")
        (wrap_dir / "kurashid").chmod(0o755)
        os.environ["KURASHI_BIN_DIR"] = str(wrap_dir)
        result["daemon_wrap"] = a.daemon_wrap

    sb = m.Sandbox(f"soak-{a.name}-{os.getpid()}")
    run = Path(sb.env["XDG_RUNTIME_DIR"])
    env = sb.env
    env["PATH"] = f"{FAKEBIN}:{env['PATH']}"
    env["WP_LOG"], env["WP_STATE"] = str(run / "awww.log"), str(run / "wpstate")
    (run / "wpstate").mkdir(exist_ok=True)
    pics = make_pictures(run / "pics", a.pictures, a.picture_size)
    covers = make_pictures(run / "covers", 6, "640x640")
    write_config(env, run / "pics", [x for x in a.mods.split(",") if x])
    daemon = app = player = None
    samples, stop_flag = [], threading.Event()
    try:
        daemon = m.start_daemon(env)
        app = subprocess.Popen(cmd, env=env, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        fake = Path(m.binary("kurashid")).parent / "examples/fake_mpris_art"
        if a.daemon_wrap:
            fake = Path(real).parent / "examples/fake_mpris_art"
        if fake.exists():
            player = subprocess.Popen([str(fake), "Soak", "Kurashi", "Hours", "240", f"file://{covers[0]}"], env=env,
                                      stdin=subprocess.PIPE, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                                      text=True)
        else:
            result["no_player"] = f"{fake} is not built (cargo build -p kurashi-mock --example fake_mpris_art)"
        time.sleep(8)
        if app.poll() is not None or daemon.poll() is not None:
            sys.exit(f"soak: the stack did not stay up (see {run}/daemon.log)")
        skip = {x for x in a.skip.split(",") if x}
        if a.only:
            skip = set(STEPS) - {x for x in a.only.split(",") if x}
        if skip - set(STEPS):
            sys.exit(f"soak: unknown step(s) {sorted(skip - set(STEPS))}; the steps are {', '.join(STEPS)}")
        result["steps"] = [x for x in STEPS if x not in skip]
        use = Use(env, a.round_pause, covers, player, skip)
        t0 = time.monotonic()

        def sampler():
            while not stop_flag.is_set():
                dpids = m.tree(daemon.pid)
                # under a wrap the daemon is the wrapper's child: the daemon is the process named kurashid
                own = [p for p in dpids if _comm(p) == "kurashid"] or dpids[:1]
                s = {"t": round(time.monotonic() - t0, 1), "round": use.round, "daemon": read(own),
                     "hosts": read([p for p in dpids if p not in own]), "frontend": read(m.tree(app.pid))}
                samples.append(s)
                print(f"[soak] {s['t'] / 60:5.1f} min · round {s['round']:4d} · daemon {s['daemon']['pss']:7.1f} MiB "
                      f"(anon {s['daemon']['anon']:.1f}) · frontend {s['frontend']['pss']:7.1f} MiB "
                      f"(anon {s['frontend']['anon']:.1f}) · hosts {s['hosts']['pss']:.1f}", file=sys.stderr, flush=True)
                stop_flag.wait(a.interval)

        th = threading.Thread(target=sampler, daemon=True)
        th.start()
        end = t0 + a.minutes * 60
        while time.monotonic() < end:
            use.one()
            if app.poll() is not None or daemon.poll() is not None:
                result["error"] = "a process exited during the soak"
                break
        stop_flag.set()
        th.join(timeout=10)
        result.update(rounds=use.round, skipped=sorted(use.skipped), failed=use.failed, samples=samples)
        after = a.warmup_min * 60
        result["growth_mib_per_h"] = {g: {k: slope_per_hour(samples, k, g, after) for k in ("pss", "uss", "anon")}
                                      for g in ("daemon", "frontend", "hosts")}
        counted = [s for s in samples if s["t"] >= after]
        if counted:
            result["first_last"] = {g: [counted[0][g]["pss"], counted[-1][g]["pss"]]
                                    for g in ("daemon", "frontend", "hosts")}
        cache = run / "xdg/cache/kurashi"
        if cache.is_dir():
            result["cache_mib"] = round(sum(f.stat().st_size for f in cache.rglob("*") if f.is_file()) / 2**20, 1)
            result["cache_files"] = sum(1 for f in cache.rglob("*") if f.is_file())
    finally:
        stop_flag.set()
        for p in (player, app, daemon):
            if p is not None:
                m.stop(p)
        if a.keep:
            print(f"[soak] sandbox kept: {run}", file=sys.stderr)
            m.sh(str(m.SANDBOX), "stop", sb.name, check=False)
        else:
            sb.stop()
            shutil.rmtree(run, ignore_errors=True)
        if wrap_dir:
            shutil.rmtree(wrap_dir, ignore_errors=True)
    if a.max_load is not None:
        result["quiet"]["load1_end"] = round(m.load1(), 2)

    rows = budget.parse_budgets(ROOT / "docs/BENCH.md")
    verdict, bad = {}, 0
    for g, row in BUDGET_ROWS.items():
        got = (result.get("growth_mib_per_h") or {}).get(g, {}).get("pss")
        limit = next((budget.numbers(b)[0] for metric, b in rows if metric.startswith(row)), None)
        ok = None if got is None or limit is None else got <= limit
        verdict[g] = {"growth_mib_per_h": got, "limit": limit, "ok": ok}
        bad += ok is False
    result["budget"] = verdict
    m.RESULTS.mkdir(parents=True, exist_ok=True)
    out = m.RESULTS / f"soak-{a.name}.json"
    out.write_text(json.dumps(result, indent=1, ensure_ascii=False))
    print(json.dumps({k: v for k, v in result.items() if k != "samples"}, indent=1, ensure_ascii=False))
    print(f"[soak] {out}", file=sys.stderr)
    sys.exit(1 if bad or "error" in result else 0)


def _comm(pid):
    try:
        return Path(f"/proc/{pid}/comm").read_text().strip()
    except OSError:
        return ""


if __name__ == "__main__":
    main()
