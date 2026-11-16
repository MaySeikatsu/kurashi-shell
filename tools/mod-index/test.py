#!/usr/bin/env python3
"""The index script against a mod scaffolded on the spot (no network): `KURASHI=<binary> tools/mod-index/test.py`."""
import importlib.util
import json
import os
import shutil
import subprocess
import sys
import tarfile
import tempfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location("build", HERE / "build.py")
build = importlib.util.module_from_spec(spec)
spec.loader.exec_module(build)
K = build.KURASHI
fails = 0


def check(ok, what):
    global fails
    print(("ok: " if ok else "FAIL: ") + what)
    fails += 0 if ok else 1


tmp = Path(tempfile.mkdtemp(prefix="kurashi-index-test-"))
try:
    # The example entry is well-formed and builds into an index.json with its summary.
    index = tmp / "index"
    shutil.copytree(HERE / "example", index)
    out = subprocess.run([sys.executable, str(HERE / "build.py"), "build", str(index)], capture_output=True, text=True)
    built = json.loads((index / "index.json").read_text()) if out.returncode == 0 else {}
    tea = (built.get("mods") or [{}])[0]
    check(out.returncode == 0 and tea.get("id") == "tea" and tea["version"][0]["summary"]["hosts"][0]["exec"] == "tea-host",
          "the example index builds, the entry carries its summary")

    # The mod the example describes, made now: its hash is the entry's (the scaffold and the entry stay in step).
    src = tmp / "src"
    subprocess.run([K, "mod", "new", "tea", "--name", "Tea timer", "--icon", "emoji_food_beverage", "--description",
                    "Steeping times in the bar.", "--with", "widget,peek,panel", "--host", "python", "--dir", str(src)],
                   check=True, capture_output=True)
    got = subprocess.run([K, "mod", "hash", str(src / "tea")], capture_output=True, text=True).stdout.strip()
    check(got == tea["version"][0]["hash"], f"the scaffolded mod hashes to the entry's hash ({got})")
    check(build.summary_toml(str(src / "tea")).splitlines()[1:] ==
          [l for l in (HERE / "example/mods/tea.toml").read_text().split("[version.summary]\n")[1].splitlines() if l],
          "the summary CI writes is the entry's")

    # Fetched as an archive: the hash matches, the check passes; one changed byte is refused.
    archive = tmp / "tea.tar.gz"
    with tarfile.open(archive, "w:gz") as t:
        t.add(src / "tea", arcname="tea-0.1.0")
    v = dict(tea["version"][0], source={"archive": archive.as_uri()})
    tree = build.verified(tea, v)
    check(Path(tree, "mod.toml").is_file() and os.access(Path(tree, "bin/tea-host"), os.X_OK),
          "a fetched archive verifies and keeps the program executable")
    (src / "tea" / "README.md").write_text("changed\n")
    with tarfile.open(archive, "w:gz") as t:
        t.add(src / "tea", arcname="tea-0.1.0")
    try:
        build.verified(tea, v)
        check(False, "a changed tree is refused")
    except SystemExit:
        check(True, "a changed tree is refused")

    # A broken entry never reaches index.json.
    (index / "mods" / "bad.toml").write_text('id = "bad"\nname = { en = "Bad" }\n[[version]]\nversion = "1.0.0"\n'
                                            'shell = "*"\nsource = { git = "http://example.org/x", rev = "main" }\nhash = "sha256-x"\n')
    out = subprocess.run([sys.executable, str(HERE / "build.py"), "check", str(index)], capture_output=True, text=True)
    check(out.returncode == 1 and "hash" in out.stderr and "source" in out.stderr, "a broken entry fails the check, with what is wrong")
finally:
    shutil.rmtree(tmp, ignore_errors=True)
sys.exit(1 if fails else 0)
