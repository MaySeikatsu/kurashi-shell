#!/usr/bin/env python3
"""W33 summary (tools/bench/w33.sh): the median of each scenario's runs, written as results/w33-<scenario>.json (the
shape of a measure.py result, so budget.py reads it), and a markdown table (metric × scenario) on stdout.

  python3 tools/bench/w33-summary.py [scenario ...]
"""
from __future__ import annotations

import json, statistics, subprocess, sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
RESULTS = HERE / "results"
SCENARIOS = ["none", "kami", "paint-shadows", "spotlight", "pen-text", "controls", "carried", "fixed", "everything"]
RUNS = (1, 2, 3)

# (row label, dotted path into a median result, format)
ROWS = [
    ("idle frames, 10 s (commits/s, all surfaces)", "pass_b.idle_commits_per_s", "{:g}"),
    ("idle CPU, frontend (%)", "pass_a.idle_cpu_pct", "{:.3f}"),
    ("idle CPU, daemon (%)", "pass_a.daemon_idle_cpu_pct", "{:.3f}"),
    ("idle CPU, daemon + frontend (%)", "pass_a.idle_cpu_pct_total", "{:.3f}"),
    ("wakeups/s, frontend", "pass_a.wakeups_per_s", "{:g}"),
    ("wakeups/s, daemon", "pass_a.daemon_wakeups_per_s", "{:g}"),
    ("PSS frontend @1 output (MiB; GPU device mappings left out, I93)", "pass_a.pss_mib_1out", "{:.1f}"),
    ("USS frontend @1 output (MiB)", "pass_a.uss_mib_1out", "{:.1f}"),
    ("PSS frontend after the popup was open once (MiB)", "pass_a.pss_mib_popup_closed", "{:.1f}"),
    ("PSS per extra output (MiB, vs popup closed)", "pass_a.pss_per_output_mib", "{:+.2f}"),
    ("USS per extra output (MiB, vs popup closed)", "pass_a.uss_per_output_mib", "{:+.2f}"),
    ("PSS daemon (MiB)", "pass_a.daemon_pss_mib", "{:.1f}"),
    ("popup input to first commit (ms; from rest, the Stage's own commit, W35)", "pass_b.popup_latency_ms_median", "{:.1f}"),
    ("mapped layer surfaces, idle, 1 output", "pass_b.mapped_layer_surfaces_idle", "{:g}"),
    ("motion window (s)", "pass_m.motion_window_s", "{:.1f}"),
    ("motion frames (commits/s, all surfaces)", "pass_b.motion_commits_per_s", "{:.1f}"),
    ("motion CPU, frontend (%)", "pass_m.motion_cpu_pct", "{:.2f}"),
    ("motion CPU, daemon (%)", "pass_m.daemon_motion_cpu_pct", "{:.2f}"),
    ("motion wakeups/s, frontend", "pass_m.motion_wakeups_per_s", "{:g}"),
    ("PSS frontend after motion (MiB)", "pass_m.pss_mib_motion_end", "{:.1f}"),
]


def is_num(v) -> bool:
    return isinstance(v, (int, float)) and not isinstance(v, bool)


def median_tree(vals: list):
    """Medians of the numbers (nested dicts recursively); anything else takes the first run's value."""
    first = vals[0]
    if isinstance(first, dict):
        return {k: median_tree([v[k] for v in vals]) for k in first if all(isinstance(v, dict) and k in v for v in vals)}
    nums = [v for v in vals if is_num(v)]
    if nums and len(nums) == len(vals):
        return round(statistics.median(nums), 3)
    return first


def with_derived(r: dict) -> dict:
    a = r.get("pass_a", {})
    if "pss_mib_3out" in a and "pss_mib_popup_closed" in a:
        # The mean of the two hotplugged outputs, against the popup-closed reading (budget.py takes the same delta).
        a["pss_per_output_mib"] = round((a["pss_mib_3out"] - a["pss_mib_popup_closed"]) / 2, 3)
    if "uss_mib_3out" in a and "uss_mib_popup_closed" in a:
        a["uss_per_output_mib"] = round((a["uss_mib_3out"] - a["uss_mib_popup_closed"]) / 2, 3)
    return r


def get(d: dict, path: str):
    for key in path.split("."):
        if not isinstance(d, dict) or key not in d:
            return None
        d = d[key]
    return d


def main(argv: list[str]) -> int:
    scenarios = argv or SCENARIOS
    medians: dict[str, dict] = {}
    notes: list[str] = []
    for s in scenarios:
        runs = []
        for k in RUNS:
            f = RESULTS / f"w33-{s}-r{k}.json"
            if not f.is_file():
                notes.append(f"{s} run {k}: no result")
                continue
            r = with_derived(json.loads(f.read_text()))
            if "error" in r.get("pass_a", {}) or "error" in r.get("pass_b", {}) or "error" in r.get("pass_m", {}):
                notes.append(f"{s} run {k}: measurement error {r.get('pass_a', {}) or r.get('pass_m', {})}")
                continue
            runs.append(r)
        if not runs:
            continue
        m = median_tree(runs)
        m.update(name=f"w33-{s}", runs=len(runs), runs_quiet=sum(1 for r in runs if r.get("quiet", {}).get("quiet", True)),
                 load1_go=[r.get("quiet", {}).get("load1_go") for r in runs])
        (RESULTS / f"w33-{s}.json").write_text(json.dumps(m, indent=2, ensure_ascii=False))
        medians[s] = m
        if m["runs_quiet"] < len(runs):
            notes.append(f"{s}: {len(runs) - m['runs_quiet']} of {len(runs)} runs went ahead over the load limit")
        tokens = runs[0].get("pass_a", {}).get("tokens")
        if tokens:
            shown = {k: v for k, v in tokens.items() if v not in (None, "", 0.0, False)}
            notes.append(f"{s} tokens in effect (run 1): {json.dumps(shown, ensure_ascii=False)}")

    cols = list(medians)
    print("| metric | " + " | ".join(cols) + " |")
    print("|---|" + "|".join("---" for _ in cols) + "|")
    for label, path, fmt in ROWS:
        cells = []
        for s in cols:
            v = get(medians[s], path)
            if v is None:
                cells.append("–")
            else:
                cells.append(fmt.format(v) if is_num(v) else str(v))
        print(f"| {label} | " + " | ".join(cells) + " |")

    print()
    for s in cols:
        out = subprocess.run([sys.executable, str(HERE / "budget.py"), str(RESULTS / f"w33-{s}.json")],
                             capture_output=True, text=True)
        lines = out.stdout.strip().splitlines()
        verdict = lines[-1] if lines else f"budget.py exit {out.returncode}"
        fails = [ln.split("  ")[0] for ln in lines if " FAIL" in ln]
        print(f"budget {s}: {verdict}" + (f"; FAIL: {'; '.join(f.strip() for f in fails)}" if fails else ""))
    for n in notes:
        print("note:", n)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
