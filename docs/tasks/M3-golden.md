# Card M3-golden — golden screenshots of the core surfaces (M3 exit criterion)

**Goal.** A visual regression check: render the core surfaces in a deterministic sandbox state and
compare against committed reference images with a tolerance.

**Owned paths:** new `tools/golden/` only (+ one `golden` recipe line in `justfile`).
Common rules: `docs/tasks/README.md`.

**Read:** `tools/bench/sandbox.sh`, `frontend/test-real.sh`, `frontend/README.md`, `justfile`.

**Build:**
1. `tools/golden/run.sh [--update]`: sandbox (pixman renderer for determinism, fixed output size
   1920x1080, scale 1), real kurashid with isolated XDG dirs and a fixed config (wa-iro palette,
   reduce_motion on so no frame is mid-animation), the frontend via `frontend/launch.sh`. States:
   bar idle, island expanded, notification center (empty), launcher open, session menu — each opened
   via `kurashi act …`, then `grim`. The clock changes every minute: mask the clock regions in the
   comparison (document the mask rectangles) rather than editing other crates.
2. `tools/golden/compare.py`: stdlib-only PNG decode (zlib) + per-pixel diff; pass if ≤ 0.5 % of
   unmasked pixels differ by more than 16/255 in any channel; on fail write a diff image to
   `tools/golden/out/` (gitignored) and print the failing state.
3. References in `tools/golden/ref/*.png` generated with `--update` (Read each before committing:
   they must look right). `just golden` runs the check.
4. If the session menu is not on main yet, skip that state with a clear message (it lands in
   parallel).

**Acceptance:** `nix develop -c just golden` exits 0 twice in a row (deterministic); an intentional
1-line change to a theme token (local, not committed) makes it fail with a diff image.
