# W89 — The suites' shared kit: the IPC client and the pixel reader (session 34, I547; Haiku)

Rule 10 (K153). Sixteen suites write the same Python IPC client into their sandbox with a heredoc (`cat > "$W/ipc.py"
<<'PY'`: connect to `$KURASHI_SOCKET`, `hello`, then act / sub / intent / raw), and fourteen carry the same PPM reader
(`while len(fields) < 4: …`). Common rules: `docs/tasks/README.md`. Build dir:
`CARGO_TARGET_DIR=$HOME/.cache/kurashi-agents-target/W89` (the suites read `$CARGO_TARGET_DIR/debug`).

## Goal
1. `tools/testkit/ipc.py`: the union of what the heredoc copies do (read three of them first:
   `frontend/test-volume.sh`, `frontend/test-polkit.sh`, `frontend/test-peek.sh`; `grep -l 'cat > .*ipc\.py'` lists all),
   as a module **and** a command with the same arguments the copies take, so a suite's calls change only in the path.
   A suite whose copy has a command the others lack keeps that command in the kit, not in the suite.
2. `tools/testkit/px.py`: the PPM reader (`read_ppm(path) -> (w, h, pixels)`) and the small helpers the copies share
   (a pixel at x,y; a crop's mean); the suites' own checks stay in the suites and import it
   (`PYTHONPATH="$ROOT/tools/testkit"`, set once in `frontend/test-lib.sh`).
3. `frontend/test-lib.sh`: `tk_ipc` (runs the kit's client) and `KIT=$ROOT/tools/testkit`. Each suite that had a copy
   sources `test-lib.sh` (some do not yet) and loses its heredoc.
4. Every check a suite makes stays exactly as it is: the diff of `fail`/`say`/`ok` lines is empty.

## Owned paths
`tools/testkit/**` (new), `frontend/test-lib.sh`, and in `frontend/test-*.sh`, `settings/test*.sh`, `mods/*/test/*.sh`,
`mods/*/test-*.sh` only the heredocs named above and the lines that call them; `tools/clones-baseline.json` (rewritten by
`python3 tools/clones.py --update` once the count fell). Not: QML, Rust, `tools/test-suites.sh`.

## Acceptance
Before changing anything: `nix develop -c tools/test-suites.sh -j 4 <the suites you will touch>` and keep its summary
(`$KURASHI_SUITES_OUT/summary.txt`) — some suites fail on the base for their own reasons. After: the same command gives the
same result per suite (a suite green before is green after), `bash -n` passes on every touched script, and
`python3 tools/clones.py --check` passes with the `sh` count lower. Report both summaries and the count before and
after. Never run a suite outside its sandbox; never edit a tree whose suites are running — run them, then edit, then run.
