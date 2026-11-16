#!/usr/bin/env python3
"""The mod catalogue's index (K155, W98; docs/ux/mod-catalogue.md "The index").

An index repository holds one file per mod, `mods/<id>.toml`. This script is its CI:

  build.py check <index dir> [--fetch]   every entry is well-formed; with --fetch, each version's source is fetched,
                                         its hash compared (`kurashi mod hash`) and `kurashi mod check` run on it
  build.py summary <index dir> <id>      fetch the newest version and print its `[version.summary]`
                                         (`kurashi mod check --summary`) for the entry's file
  build.py build <index dir> [-o FILE]   write index.json (default: <index dir>/index.json) from every entry

A pull request is the review: `check --fetch` must pass before a merge, `build` runs after it. `kurashi` must be on
PATH (or KURASHI=<binary>); `git` and `tar` fetch the sources. Nothing here runs a mod's code.
"""
import json
import os
import re
import subprocess
import sys
import tempfile
import tomllib
import urllib.request
from pathlib import Path

KURASHI = os.environ.get("KURASHI", "kurashi")
ID = re.compile(r"^[a-z][a-z0-9-]{0,31}$")
HASH = re.compile(r"^sha256-[A-Za-z0-9+/]{43}=$")
REV = re.compile(r"^[0-9a-f]{40}$")


def fail(msg):
    print(f"mod-index: {msg}", file=sys.stderr)
    sys.exit(1)


def entries(root):
    out = []
    for path in sorted((Path(root) / "mods").glob("*.toml")):
        with open(path, "rb") as f:
            e = tomllib.load(f)
        problems = lint(path, e)
        if problems:
            fail("; ".join(problems))
        out.append(e)
    return out


def lint(path, e):
    """The same rules as kurashi_mods::index::Entry::validate, so a broken entry never reaches index.json."""
    p = []
    name = path.name
    if not ID.match(str(e.get("id", ""))) or e.get("id") != path.stem:
        p.append(f"{name}: id must be the file's name: lowercase letters, digits, hyphens")
    if not str((e.get("name") or {}).get("en", "")).strip():
        p.append(f"{name}: name.en is missing")
    versions = e.get("version") or []
    if not versions:
        p.append(f"{name}: no [[version]]")
    seen = set()
    for v in versions:
        n = v.get("version", "?")
        if n in seen:
            p.append(f"{name}: version {n} twice")
        seen.add(n)
        if not HASH.match(str(v.get("hash", ""))):
            p.append(f"{name} {n}: hash is not sha256-<base64>")
        src = v.get("source") or {}
        url = src.get("git") or src.get("archive") or ""
        if not url.startswith("https://") or ("git" in src and not REV.match(str(src.get("rev", "")))):
            p.append(f"{name} {n}: source must be https, a git source with a full revision")
        if not v.get("shell"):
            p.append(f"{name} {n}: shell (the version range) is missing")
    return p


def fetch(src, into):
    """The version's tree at <into>/<id>, without VCS files; returns that folder."""
    if "git" in src:
        subprocess.run(["git", "init", "-q", into], check=True)
        subprocess.run(["git", "-C", into, "fetch", "-q", "--depth", "1", src["git"], src["rev"]], check=True)
        subprocess.run(["git", "-C", into, "checkout", "-q", "FETCH_HEAD"], check=True)
        subprocess.run(["rm", "-rf", os.path.join(into, ".git")], check=True)
    else:
        archive = os.path.join(into, ".archive")
        with urllib.request.urlopen(src["archive"], timeout=60) as r, open(archive, "wb") as f:
            f.write(r.read())
        subprocess.run(["tar", "-xf", archive, "-C", into, "--strip-components=1", "--no-same-owner"], check=True)
        os.remove(archive)
    return into


def verified(e, v):
    """Fetches version `v` of entry `e`, compares the hash and runs the check; returns the tree's folder."""
    tmp = tempfile.mkdtemp(prefix="kurashi-index-")
    tree = os.path.join(tmp, e["id"])
    os.mkdir(tree)
    fetch(v["source"], tree)
    got = subprocess.run([KURASHI, "mod", "hash", tree], capture_output=True, text=True, check=True).stdout.strip()
    if got != v["hash"]:
        fail(f"{e['id']} {v['version']}: the source hashes to {got}, the entry says {v['hash']}")
    check = subprocess.run([KURASHI, "mod", "check", tree], capture_output=True, text=True)
    if check.returncode != 0:
        fail(f"{e['id']} {v['version']}: kurashi mod check fails:\n{check.stdout}")
    return tree


def summary_toml(tree):
    """`[version.summary]` for the tree, from `kurashi mod check --summary` (the mod's own manifest, never the author)."""
    out = subprocess.run([KURASHI, "--json", "mod", "check", "--summary", tree], capture_output=True, text=True, check=True)
    s = json.loads(out.stdout)
    q = json.dumps  # a JSON string is a TOML basic string
    lines = ["[version.summary]"]
    for key in ("provides", "uses", "capabilities"):
        lines.append(f"{key} = [{', '.join(q(x) for x in s.get(key, []))}]")
    hosts = s.get("hosts") or []
    if hosts:
        rows = ", ".join("{ " + ", ".join(f"{k} = {q(h[k])}" for k in ("name", "exec", "start")) + " }" for h in hosts)
        lines.append(f"hosts = [{rows}]")
    return "\n".join(lines)


def main(argv):
    if len(argv) < 3 or argv[1] not in ("check", "summary", "build"):
        print(__doc__)
        return 2
    cmd, root = argv[1], argv[2]
    all_entries = entries(root)
    if cmd == "check":
        if "--fetch" in argv:
            for e in all_entries:
                for v in e["version"]:
                    verified(e, v)
        print(f"mod-index: {len(all_entries)} entr{'y' if len(all_entries) == 1 else 'ies'} ok")
        return 0
    if cmd == "summary":
        e = next((x for x in all_entries if x["id"] == argv[3]), None) if len(argv) > 3 else None
        if e is None:
            fail("summary: name an entry's id")
        v = e["version"][-1]
        tree = verified(e, v)
        print(summary_toml(tree))
        return 0
    out = Path(argv[argv.index("-o") + 1]) if "-o" in argv else Path(root) / "index.json"
    out.write_text(json.dumps({"mods": all_entries}, ensure_ascii=False, separators=(",", ":")) + "\n")
    print(f"mod-index: wrote {out} ({len(all_entries)} mods)")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
