# Card W42-memory — the bare shell inside 150 MiB PSS at one output (K68; I194, I11)

**Why:** K68 keeps the core budget at ≤ 150 MiB PSS @1 output (+6 per extra output) for the bare shell (no material, no web
dock). After W41 it measures 152.3 / 152.4 (BENCH "2026-10-25 — W41 icons"). The remaining candidates are measured in BENCH
"W39-block" (Idle windows): the Stage window −7.3 and the Launcher window −6.6 when left out (each ~3.5 MiB is the window
itself, I11: one GL context, render thread and glyph cache per layer surface); Qt's image format plugins ~3 MiB of libraries
(kimageformats, libheif, OpenEXR, libraw, x265) that the shell never needs.

**Read first:** `CLAUDE.md`; `docs/tasks/README.md`; DECISIONS K16 (one persistent Stage; re-creating it per open leaked ~5 MiB per
cycle, measured then), K68; BENCH "W39-block" and "W41 icons" (method: back-to-back before/after pairs, the same day, the same
shared libraries — absolute PSS is not comparable across days, I211); `tools/bench/README.md`; `frontend/shell.qml`,
`frontend/surfaces/Launcher.qml`, `frontend/surfaces/Stage.qml`, `frontend/launch.sh`, `nix/package.nix` (the frontend wrapper).

**Task:** get the bare shell's PSS @1 output to ≤ 150 MiB with margin, without giving back latency or motion. Measure each
option on its own (pairs), then keep what pays:
1. **Image plugins:** the shell loads only svg, png, jpeg, webp, gif (check what the sources and icon themes need: tray and
   launcher icons, wallpapers, mod images — list them) — e.g. a filtered `imageformats` plugin dir in the wrapper / launch.sh
   (`QT_PLUGIN_PATH` order) so Qt never maps the rest. Wallpapers in AVIF/HEIF/JXL: decide with evidence (the wallpaper mod
   may draw them; if so keep those, report).
2. **One window for Launcher and Stage**, or a Launcher window made on first open and kept, or released after a linger: weigh
   each against K16's leak finding (re-measure it: 20 open/close cycles, the growth row, three runs) and the launcher's first
   open (W37-daemon: ≤ 40 ms cold; popup budget ≤ 16.7 ms first frame from rest). The merge-into-bar morph (BarMorph, W34/W36)
   must look the same — `frontend/test-morph.sh` (or the morph cases in `tools/bench`) passes on washi/sekai left/right.
3. Anything else the per-path `--smaps-dump` shows as large and shell-owned (report it; fix it only inside owned paths).
Record each option's pair in BENCH (a new entry at the top of Results), and the kept ones' effect on: PSS @1 and per extra
output, popup first frame, launcher first open, the 20-cycle growth row, idle frames (must stay 0).

**Owned paths:** `frontend/shell.qml`, `frontend/surfaces/Launcher.qml`, `frontend/surfaces/Stage.qml` (window lifetime only —
no visual change), `frontend/launch.sh`, `frontend/test-launch.sh`, `nix/package.nix` (wrapper env / plugin dir only),
`tools/bench/**`, `docs/BENCH.md` (your entry). Anything else → CONTRACT-CHANGE.

**Acceptance:** back-to-back pairs (two each) PSS @1 output ≤ 148 MiB after; per extra output ≤ +6; idle frames 0; popup first
frame and launcher first open no worse than before (numbers in the report); 20-cycle growth within the budget row; morph test
passes; `nix build .#kurashi --no-link`; `just check` green.

**Contract rows:** CONTRACT-CHANGE rows 460–464 only.

**Env:** `CARGO_TARGET_DIR=$HOME/.cache/kurashi-agents-target/w42-memory CARGO_BUILD_JOBS=4`; sandbox names `w42-memory-…`;
bench binaries from your target dir (`KURASHI_BIN_DIR`, or copy into `tools/bench/bin` and delete after — I213). The machine is
loaded (load average 6–10 from the user's session): always pairs, never one number against an old one. Model: opus.
