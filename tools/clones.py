#!/usr/bin/env python3
"""Cross-file clone check (K153, CLAUDE.md rule 10): the same block in two files is one shared pattern not yet written.

Every source line is normalised (indentation, blank lines, comments, imports and lone brackets dropped); each run of
WINDOW such lines is hashed; a window found in two or more files is a clone. Per language the number of cloned window
starts is compared with tools/clones-baseline.json: it may fall, never rise. Linked files (settings/ and the web dock's
host link the shell's components) count once.

  tools/clones.py              the report: totals, the file pairs sharing most, the files with most cloned lines
  tools/clones.py --check      the ratchet (`just check`): exit 1 when a language's count rose, naming the files
  tools/clones.py --update     rewrite the baseline after a count fell (refuses a rise without --force)
  tools/clones.py --lang qml   one language only (rs, qml, sh)
"""
import collections
import hashlib
import json
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
BASELINE = os.path.join(ROOT, "tools", "clones-baseline.json")
LANGS = {
    "rs": {"ext": ".rs", "window": 6, "roots": ["crates"]},
    "qml": {"ext": ".qml", "window": 6, "roots": ["frontend", "mods", "settings", "greeter"]},
    "sh": {"ext": ".sh", "window": 5, "roots": ["frontend", "mods", "settings", "greeter", "tools"]},
}
SKIP = ("/target/", "/archive/", "/.claude/", "/result/", "/fixtures/", "/golden/", "/tools/bench/results/", "/shots/")
LONE = {"{", "}", "});", ")", "};", "],", "]", "),", "},", "else {", "} else {", "fi", "done", "then", "do", "esac", ";;"}
PREFIXES = ("//", "#", "///", "/*", "*", "use ", "import ", "pragma ")


def norm(line):
    s = line.strip()
    if not s or s in LONE or s.startswith(PREFIXES):
        return None
    return re.sub(r"\s+", " ", s)


def scan(lang):
    cfg = LANGS[lang]
    win = cfg["window"]
    files = {}
    for root in cfg["roots"]:
        for dp, _dn, fn in os.walk(os.path.join(ROOT, root)):
            # Judged inside the checkout: an agent's worktree lives under .claude/worktrees and is a checkout too.
            if any(k in "/" + os.path.relpath(dp, ROOT) + "/" for k in SKIP):
                continue
            for f in fn:
                p = os.path.join(dp, f)
                if not f.endswith(cfg["ext"]) or os.path.islink(p):
                    continue
                try:
                    raw = open(p, errors="ignore").read().split("\n")
                except OSError:
                    continue
                files[os.path.relpath(p, ROOT)] = [(i + 1, n) for i, l in enumerate(raw) if (n := norm(l))]
    index = collections.defaultdict(list)
    for p, lines in files.items():
        for i in range(len(lines) - win + 1):
            chunk = "\n".join(n for _, n in lines[i:i + win])
            if len(chunk) < win * 14:   # six one-word lines are not a pattern
                continue
            index[hashlib.md5(chunk.encode()).hexdigest()].append((p, lines[i][0]))
    cloned = collections.defaultdict(set)
    pairs = collections.Counter()
    for occ in index.values():
        fs = sorted({p for p, _ in occ})
        if len(fs) < 2:
            continue
        for p, ln in occ:
            cloned[p].add(ln)
        if len(fs) <= 6:
            for a in range(len(fs)):
                for b in range(a + 1, len(fs)):
                    pairs[(fs[a], fs[b])] += 1
    per_file = {p: len(s) for p, s in cloned.items()}
    return {
        "lines": sum(len(l) for l in files.values()),
        "windows": sum(per_file.values()),
        "files": dict(sorted(per_file.items())),
        "pairs": pairs,
    }


def main():
    args = sys.argv[1:]
    langs = list(LANGS)
    if "--lang" in args:
        langs = [args[args.index("--lang") + 1]]
    found = {l: scan(l) for l in langs}
    if "--check" in args or "--update" in args:
        try:
            base = json.load(open(BASELINE))
        except OSError:
            base = {}
        bad = False
        for l in langs:
            was = base.get(l, {"windows": 0, "files": {}})
            now = found[l]
            if now["windows"] > was["windows"]:
                bad = True
                print(f"clones: {l}: {now['windows']} cloned windows, the baseline has {was['windows']}. Risen in:")
                rose = [(n - was["files"].get(p, 0), p) for p, n in now["files"].items() if n > was["files"].get(p, 0)]
                for d, p in sorted(rose, reverse=True)[:12]:
                    print(f"  +{d:4d}  {p}")
                print("  Put the block in one shared place and use it from both (`tools/clones.py --lang " + l
                      + "` lists the pairs).")
            else:
                print(f"clones: {l}: {now['windows']} cloned windows (baseline {was['windows']})")
        if "--update" in args:
            if bad and "--force" not in args:
                print("clones: not updated: a count rose (--force writes it anyway; say why in the commit)")
                return 1
            for l in langs:
                base[l] = {"windows": found[l]["windows"], "files": found[l]["files"]}
            json.dump(base, open(BASELINE, "w"), indent=1, sort_keys=True)
            open(BASELINE, "a").write("\n")
            print(f"clones: wrote {os.path.relpath(BASELINE, ROOT)}")
            return 0
        return 1 if bad else 0
    for l in langs:
        r = found[l]
        pct = 100 * r["windows"] / max(r["lines"], 1)
        print(f"== {l}: {len(r['files'])} files with clones, {r['lines']} code lines, {r['windows']} cloned windows ({pct:.1f} %)")
        print("-- file pairs sharing most")
        for (a, b), n in r["pairs"].most_common(15):
            print(f"{n:5d}  {a}  <->  {b}")
        print("-- files with most cloned lines")
        for p, n in sorted(r["files"].items(), key=lambda x: -x[1])[:12]:
            print(f"{n:5d}  {p}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
