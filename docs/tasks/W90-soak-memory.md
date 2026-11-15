# W90 — What grows in a day: a soak measurement, then the leaks (session 34, B147; lead)

**First card of the next session (the user's choice).** The user's running 0.2.0 session after 42 h, two outputs, read
through `/proc`: `kurashid` 641 MiB PSS, 637 MiB of it anonymous, its high-water mark equal to its current size; the
frontend 597 MiB PSS (budget: 150 MiB at one output, +6 per further output); the web dock's host 549 MiB + 63 MiB of
engine processes; the terminal's host 69 MiB. A fresh start in the sandbox: daemon 72 MiB, frontend 382 MiB (nested niri;
the bench's headless figure is ~152). The budgets are measured for seconds after a start; nothing measures a day.

## Steps
1. **Read the live session first, read-only** (ask the user before anything else touches it): `/proc/<pid>/smaps` of
   `kurashid` grouped by mapping (heap, anonymous by size class), `kurashi sub` of every document with its size
   (`runtime.*`, `svc.previews`, `svc.notifications`, `mods`, `theme.previews`, `i18n`), the state and cache dirs' sizes
   (`$XDG_CACHE_HOME/kurashi`, previews, thumbnails, texture, font mix). What is 600 MiB made of?
2. **`tools/bench/soak.py`** (new; rule 10: on `measure.py`'s sandbox and readers, not a copy): starts the real stack in
   the headless sandbox, drives a script of ordinary use in a loop (open and close the launcher, quick settings, the
   notification centre, a mod's panel; workspace switches; notifications arriving; a track change with a cover; the
   wallpaper's next; the clock's minute), reads PSS, USS and the heap's size of each process every minute, writes
   `tools/bench/results/soak-<name>.json` and a growth figure (MiB per hour after the first ten minutes). `just soak
   [minutes]` (default 60). Deterministic: the same script, the mock's services for what the sandbox lacks.
3. **Find what grows**, per process: for the daemon `heaptrack` or `bytehound` from nix on a soak run (suspects: the
   previews' stills and their history, notification history, launcher index and frecency, thumbnails held in memory,
   the texture and font-mix caches, a broadcast ring or a per-subscriber queue that only grows, `tokio` tasks never
   ended); for the frontend Quickshell's `QML` object counts over the loop (Loaders not released, images with
   `cache: true`, a `Repeater` model growing, ShaderEffect sources), `QSG_INFO`, and the same loop with each surface left
   out in turn.
4. **Fix** each cause with a test that holds its bound (a cache has a size and an eviction; a history has a length), and a
   budget: growth per hour after warm-up ≤ 1 MiB for the daemon and ≤ 2 MiB for the frontend (propose the numbers to the
   user with the first soak's result; rule 9). BENCH gains a "Soak" section; the bench gate does not get slower — the soak
   is its own recipe, run before a release.

## Owned paths
`tools/bench/soak.py`, `tools/bench/README.md`, `justfile` (`soak`), `docs/BENCH.md` ("Soak"), and the crates and QML the
causes are in (each fix its own commit, with its test).

## Acceptance
`just soak 60` on a quiet machine: the growth figures in BENCH, each process within its budget or the remaining cause named
with its row; the user's session, a day after they rebuild, read again and noted in BENCH.
