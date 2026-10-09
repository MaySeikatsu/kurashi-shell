#!/usr/bin/env python3
"""Budget gate (CLAUDE.md rule 9): compare a measure.py result with the budget table in
docs/BENCH.md and exit non-zero on any violation.

  python3 tools/bench/budget.py tools/bench/results/frontend-real.json [--budgets docs/BENCH.md] [--strict]

The limits are read from the "## Budgets" table, never copied here; this file only knows which
measured field answers which row. A row whose value cannot be measured in this run (headless, no
GPU, client prints no WAYLAND_DEBUG, daemon not real) is n/a: shown, not passed. n/a does not fail
the gate unless --strict is given. A row with no checker is n/a too, so a new budget row is never
silently green.
"""
from __future__ import annotations

import argparse, json, re, sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
FRAME_MS = 1000 / 60   # "1 frame" at the sandbox's 60 Hz headless output


def numbers(text: str) -> list[float]:
    return [float(x) for x in re.findall(r"\d+(?:\.\d+)?", text)]


def parse_budgets(path: Path) -> list[tuple[str, str]]:
    rows, inside = [], False
    for line in path.read_text().splitlines():
        if line.startswith("## "):
            inside = line.startswith("## Budgets")
            continue
        if inside and line.startswith("|"):
            cells = [c.strip() for c in line.strip().strip("|").split("|")]
            if len(cells) >= 2 and cells[0] not in ("Metric",) and not set(cells[0]) <= set("-: "):
                rows.append((cells[0], cells[1]))
    return rows


def get(r: dict, pass_name: str, key: str):
    v = r.get(pass_name, {}).get(key)
    return None if v in (None, "unmeasurable") else v


# Each checker returns (measured text, limit text, ok | None for n/a, note).
def idle_frames(r, budget):
    limit = numbers(budget)[0]
    v = get(r, "pass_b", "idle_commits_per_s")
    if v is None:
        return "commits: unmeasurable", f"≤ {limit:g} fps", None, "client printed no WAYLAND_DEBUG"
    return f"{v:g} fps", f"≤ {limit:g} fps", v <= limit, ""


def idle_cpu(r, budget):
    limit = numbers(budget)[0]
    total = get(r, "pass_a", "idle_cpu_pct_total")
    note = f"{get(r, 'pass_a', 'idle_window_s') or '?'} s window"
    if total is None:
        v = get(r, "pass_a", "idle_cpu_pct")
        if v is None:
            return "-", f"< {limit:g} %", None, "no pass A"
        # The budget says daemon + frontend; frontend-only is not that (Shōjiki).
        return f"{v:g} % (frontend only)", f"< {limit:g} %", None, "daemon not measured (--daemon mock)"
    return f"{total:g} %", f"< {limit:g} %", total < limit, note


def pss(r, budget):
    base = float(re.search(r"≤\s*(\d+(?:\.\d+)?)\s*MiB", budget).group(1))
    extra = float(re.search(r"\+\s*(\d+(?:\.\d+)?)\s*MiB", budget).group(1))
    one, two = get(r, "pass_a", "pss_mib_1out"), get(r, "pass_a", "pss_mib_2out")
    three = get(r, "pass_a", "pss_mib_3out")
    if one is None:
        return "-", f"≤ {base:g} MiB", None, "no pass A"
    ok = one <= base
    text = f"{one:g} MiB"
    if two is not None:
        # Delta against the popup-closed reading when present (see measure.py pass A); the mean
        # over two hotplugged outputs when the run has a third one.
        start = get(r, "pass_a", "pss_mib_popup_closed") or one
        delta = (three - start) / 2 if three is not None else two - start
        ok = ok and delta <= extra
        text += f", +{delta:.1f}/output" + (" (mean of 2)" if three is not None else "")
    return text, f"≤ {base:g} MiB, ≤ +{extra:g}/output", ok, ""


def popup(r, budget):
    v = get(r, "pass_b", "popup_latency_ms_median")
    if v is None:
        return "-", f"≤ {FRAME_MS:.1f} ms", None, "no popup commit seen"
    return f"{v:g} ms", f"≤ {FRAME_MS:.1f} ms (1 frame @60 Hz)", v <= FRAME_MS, ""


def mapped(r, budget):
    limit = numbers(budget)[-1]
    v = get(r, "pass_b", "mapped_layer_surfaces_idle")
    if v is None:
        return "-", f"≤ {limit:g}", None, "unmeasurable"
    return f"{v}", f"≤ {limit:g}", v <= limit, "layer surfaces with a buffer, 1 output"


def cycles(r, budget):
    limit = numbers(budget)[0]
    v = get(r, "pass_a", "pss_mib_cycle_growth")
    if v is None:
        return "-", f"≤ {limit:g} MiB", None, "needs --daemon real (no panel actions on the mock)"
    n = get(r, "pass_a", "cycle_count")
    return f"{v:+.2f} MiB / {n} cycles", f"≤ {limit:g} MiB", v <= limit, "island + center + launcher"


CHECKS = [("open/close", cycles), ("idle frames", idle_frames), ("idle cpu", idle_cpu), ("pss", pss),
          ("popup", popup), ("mapped surfaces", mapped)]


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("result")
    ap.add_argument("--budgets", default=str(ROOT / "docs/BENCH.md"))
    ap.add_argument("--strict", action="store_true", help="n/a counts as a failure")
    a = ap.parse_args()
    r = json.loads(Path(a.result).read_text())
    rows = parse_budgets(Path(a.budgets))
    if not rows:
        print(f"no '## Budgets' table in {a.budgets}", file=sys.stderr)
        return 2
    if "error" in r.get("pass_a", {}) or "error" in r.get("pass_b", {}):
        print("measurement error:", r.get("pass_a", {}).get("error") or r["pass_b"]["error"], file=sys.stderr)
        return 2

    fails = nas = 0
    print(f"{r.get('name', '?')} · daemon {r.get('daemon', '?')} · {r.get('commit', '?')}")
    print(f"{'budget':<46} {'measured':<30} {'limit':<30} result")
    for metric, budget in rows:
        fn = next((f for k, f in CHECKS if k in metric.lower()), None)
        if fn is None:
            m, lim, ok, note = "-", budget, None, "no checker for this row"
        else:
            m, lim, ok, note = fn(r, budget)
        verdict = "n/a" if ok is None else "pass" if ok else "FAIL"
        fails += ok is False
        nas += ok is None
        print(f"{metric[:45]:<46} {m:<30} {lim:<30} {verdict}{'  (' + note + ')' if note else ''}")
    if a.strict:
        fails += nas
    print(f"{fails} violation(s), {nas} n/a")
    return 1 if fails else 0


if __name__ == "__main__":
    sys.exit(main())
