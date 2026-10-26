# Bench

Measured numbers per milestone. Method: `just bench …` (see `tools/bench/README.md`).
Always record: date, commit, machine, compositor, renderer, outputs, profile.

Machine A: 12 cores, 31 GiB RAM, NVIDIA GTX 1060 6 GB (driver 580.178), NixOS, niri 26.04.
Machine B: laptop, AMD Ryzen 7 6800H (8 cores / 16 threads), 38 GiB RAM, **hybrid GPU**: Radeon 680M iGPU
(Mesa 26.2.2, boot GPU — niri renders on it) + NVIDIA RTX 3070 Laptop 8 GB (open kernel module 595.99.02,
runtime PM), NixOS 26.11, niri 26.04. Procedure: `docs/RUNBOOK-MACHINE-B.md`. The sandbox picks the first
render node (renderD128 = the NVIDIA dGPU here); `KURASHI_RENDER_NODE=/dev/dri/renderD129` measures on the
iGPU, the GPU this machine's session actually uses.

**Per-machine baselines.** Budgets apply on every target machine; numbers are only comparable
within one machine (GPU driver floor differs: NVIDIA vs Mesa). Take each machine's baseline
**quiet**: no other compile jobs or agent sessions running (check `uptime` load ≈ idle), one
`just bench-gate` at a time. A result taken under load is labelled as such and never used as a
baseline.

## Budgets (v0.1)
| Metric | Budget |
|---|---|
| Idle frames, all windows, 30 s | ≤ 1 fps total; the only idle commits allowed are the bar clock's minute flip (≤ 300 ms, once a minute; K68) |
| Idle CPU, daemon + frontend, 10 min | < 0.5 % |
| PSS frontend, core profile | ≤ 150 MiB @1 output, ≤ +6 MiB per extra output, measured vs. popup-closed (K16, K19; was ≤ 50 % of shellseikatsu) |
| PSS allowance, material on (K68) | + ≤ 55 MiB @1 output, + ≤ 12 MiB per extra output (per-window tile sheets, K59); scope `everything` (the overlay) + ≤ 35 MiB more |
| USS allowance, web dock on and hidden (K68) | + ≤ 10 MiB @1 output, + ≤ 4 MiB per extra output (its `qs-webengine` host is a separate process, measured on its own) |
| Popup input → first frame | ≤ 1 frame after map |
| PSS growth over 20 panel open/close cycles (island, notification center, launcher; after 20 warm-up rounds) | ≤ 2 MiB |
| Mapped surfaces per output at idle | ≤ 4 |

## Baseline — shellseikatsu (2026-10-08, Quickshell 0.3.1, Qt 6.11.2, niri, 1 output)
| Metric | Value |
|---|---|
| RSS | 272–275 MB |
| PSS | 216 MB |
| Anonymous | 173 MB (QML JS heap 34 MB) |
| Avg CPU (1 h) | 3.5 % |
| Idle frames (after 2026-10-08 fixes, headless) | ~0.8 fps |

## Results

### 2026-10-26 — W43 frame: four strips per output, PSS with the frame off and on, idle (machine A; K71, docs/ux/frame.md)
`frontend/test-frame.sh` (sandbox `w43-frame-test`, headless sway gles2, one 1920×1080 output), kurashi-mock serving a staged
`runtime.layout` (frame on: thickness 8, radius 16, reserve on, a docked top bar; off: the fixture's unframed output) and wearing
kurashid's theme tokens for the look. Frontend `qs -p` directly (not launch.sh). PSS of the frontend process, MiB.

| Look | Pairs | Frame off | Frame on | Δ |
|---|---|---|---|---|
| kanso (no material), one frontend, frame toggled by the layout | 3 + 3 (two runs) | 186.4 / 188.6 / 188.0 · 164.7 / 169.3 / 170.5 | 191.4 / 190.8 / 190.6 · 170.0 / 173.1 / 173.4 | **+5.0 / +2.1 / +2.7 · +5.2 / +3.8 / +2.9** |
| washi + paper material, one frontend, toggled | 3 + 3 | 241.1 / 239.9 / 242.6 · 212.2 / 209.5 / 213.6 | 250.8 / 251.8 / 263.0 · 225.7 / 222.3 / 236.1 | **+9.7 / +11.9 / +20.4 · +13.5 / +12.8 / +22.5** |
| kanso, two frontends (each started off or on) | 3 | 186.9 / 172.3 / 172.3 | 201.1 / 187.5 / 187.3 | +14.2 / +15.2 / +15.0 |
| washi + paper, two frontends | 3 | 220.6 / 219.1 / 215.7 | 256.4 / 250.3 / 250.5 | +35.8 / +31.2 / +34.8 |

- **Untextured, live: +2…5 MiB per output** for four layer windows (top 1920×48 with the bar's part transparent, bottom
  1920×24, sides 8×1008). The brief's ≤ +2 MiB is just missed; I11's ~3.5 MiB per window does not hold for windows this small.
- **With the material: +10…23 MiB** — each strip makes its own TileSheet (normal, ink, height render targets) and reliefs; the
  material's per-output allowance (K68: ≤ +12) is missed in two of six pairs.
- Two frontends differ by +14…36 MiB: a frontend started with the frame on keeps more than one that turns it on later (start-up
  arenas); the spread between runs elsewhere in BENCH is of that order (I211), so the toggled pairs are the frame's own cost.
- The acceptance run after the last change (pieces that notify only on change): kanso toggled +5.6 / +2.8 / +1.9, washi +
  paper toggled +11.5 / +9.5 / +13.4.
- Earlier runs of the same test: kanso toggled +3.8, −5.8, +1.0, +1.6 (noise of ± 6); two-frontend pairs from −24.8 to +39.6.
- **Idle: 0 commits in 10 s** for the four strips and every other surface (washi + paper and kami with its pen, frame on; kami
  frame off), also while two documents nothing on the output shows are patched in the window (another output's layout and
  workspaces: every patch re-reads the layout; the strips' pieces and the bar's rule notify only when their values change).
  The mock's clock is pinned (`--fixed-time`): with a ticking clock the bar's own surface (namespace `quickshell`, not the
  strips) committed 14–27 times in 10 s in 2 of 5 runs although the window lay between two minutes — not isolated further.
  The strips are static: drawn once, a pen line painted once per change. The frame adds 4 mapped surfaces per output (budget "≤ 4 mapped
  surfaces per output" — row 492).

### 2026-10-25 — W42 memory: the image plugins the shell draws, two jemalloc arenas; the launcher window stays (machine A; K68, I194, I11)
"Before" is `8598d57b`'s frontend (`git archive`), "after" this branch; both against one real `kurashid` (release, this branch,
from the card's own target dir via the new `KURASHI_BIN_DIR`), headless sway gles2, one 2560×1440 output, sandboxes
`w42-memory-*`. Every table is interleaved runs in one invocation (variant by variant, round by round); the 1-minute load was
4–20 (the user's session), so no `--max-load`. **Absolute PSS is lower today than in W41** (before reads 123–139 MiB @1 output
against W41's 152–158): which other processes map the same Qt and driver files moves PSS by tens of MiB (I211); compare the pairs,
and files by RSS (`*_rss_by`).

**What was found.** (1) Qt maps every image format plugin it can find (most likely when it probes an image by its content — a
`data:` URL or a name without a suffix; inferred, not isolated), and a NixOS session hands it the system profile's: kimageformats with libheif, x265, libde265, OpenEXR, libraw, libjxl, libavif, libaom, dav1d,
and qtimageformats (tiff, jasper, mng, …) — 9.9 MiB resident. They come **two ways**: `QT_PLUGIN_PATH` and nixpkgs' Qt patch that
adds `<entry>/../lib/qt-6/plugins` for every `PATH` entry (`/run/current-system/sw/bin` → `/run/current-system/sw/lib/qt-6/plugins`;
`QT_DEBUG_PLUGINS=1` shows the dir searched after `QT_PLUGIN_PATH` no longer names it). Putting a filtered dir first would not
help — Qt merges every dir it is given — so `frontend/launch.sh` *replaces* each such dir by a copy made of symlinks under
`$XDG_RUNTIME_DIR/kurashi/qt-plugins-<pid>` whose `imageformats/` keeps svg, jpeg, webp and gif (png, bmp, xpm are built into Qt;
quickshell's own plugin dirs keep ico); a `PATH` entry becomes `<farm>/b<n>/bin`, a link to the same dir, so commands still resolve
and the patch's lexical `../lib/qt-6/plugins` lands in the copy. Wallpapers: kurashi-mod-wallpaper lists png jpg jpeg webp gif bmp
(`library.rs` EXTENSIONS, `wallhaven.rs`), so AVIF/HEIF/JXL are never offered and are dropped; `KURASHI_IMAGE_FORMATS` adds formats
back (`… avif` keeps `kimg_avif.so`), `all` turns the filter off. (2) Quickshell links **jemalloc** (`MALLOC_CONF=stats_print:true`):
48 arenas on 12 cores, no background thread, 10 s dirty decay. `MALLOC_CONF=narenas:2` (set by launch.sh unless the user sets their
own) is the larger cut. Why it pays is inferred, not isolated: many arenas each holding partly used extents and freed pages that a
quiet thread's arena does not purge — but a 1 s decay on top of two arenas added nothing, so fragmentation across arenas, not decay,
looks like most of it.

**Each option on its own (pass a, `--idle 10 --cycles 0`, three interleaved rounds, @1 output; MiB).**

| variant | PSS | USS | RSS lib | RSS anon |
|---|---|---|---|---|
| before | 136.3 / 138.6 / 123.4 | 108.8 / 107.1 / 96.5 | 115.3 / 115.5 / 115.5 | 83.5 / 92.3 / 72.5 |
| image plugins filtered | 124.4 / 126.8 / 126.0 | 97.8 / 100.1 / 99.3 | **105.5 / 105.6 / 105.6** | 84.9 / 82.8 / 84.8 |
| launcher window made on first open, kept | 124.8 / 137.1 / 130.3 | 93.9 / 110.3 / 103.7 | 115.3 / 115.5 / 115.5 | 80.5 / 87.1 / 80.5 |
| `MALLOC_CONF=narenas:2` | 115.1 / 118.4 / 111.4 | 88.3 / 92.1 / 91.9 | 115.2 / 115.4 / 115.5 | **64.4 / 67.0 / 68.2** |
| `narenas:2,dirty_decay_ms:1000` | 118.8 / 116.5 / 98.5 | 92.0 / 90.4 / 78.5 | 115.4 / 115.4 / 115.6 | 63.9 / 64.5 / 68.1 |

The plugin filter is −9.9 MiB RSS of libraries, the same in every run; two arenas −15…−20 MiB anonymous; a faster decay adds
nothing over two arenas (not kept). The lazy launcher saves ~3 MiB anonymous, inside the spread.

**Launcher first open** (`measure.py --passes b --popup-action launcher.toggle --popup-window kurashi-launcher`: action → the
launcher window's first commit; the first round is the shell's first launcher open; ms, three interleaved rounds).

| variant | first open | median of 5 |
|---|---|---|
| before | 7.9 / 7.9 / 6.0 | 5.3 / 5.3 / 4.6 |
| plugins + two arenas | 7.6 / 7.5 / 8.1 | 4.7 / 6.0 / 5.4 |
| plugins + two arenas + launcher made on first open | **13.8 / 17.0 / 24.3** | 4.6 / 6.4 / 6.2 |

Making the window on first open costs its first open +6…+17 ms (QML instantiation, a new layer surface and GL context before the
first commit); the card's bar is "no worse", so the launcher window **stays persistent** (K16) and its ~3 MiB was not taken.
test-launcher.sh's cold-open check (`bar-morph frame` gaps from the open) would not have seen this: its clock starts once the
window exists. The Stage cannot be made lazily either: it also carries the hover peeks and the island's first frame (≤ 16.7 ms).

**K16's leak re-measured** (the launcher made per open and released once folded back, against the kept window; both with plugins +
two arenas; pass a with the 20 + 20 cycle test, three interleaved rounds): growth +16.9 / −28.6 / +7.3 MiB per open-made window
against −6.8 / +1.8 / +2.2 kept. The per-open window scatters three to four times wider; with the row's own scatter (W35, W41)
this neither proves nor clears a leak, and nothing here argues for re-made windows. "One window for Launcher and Stage" was not
built: the launcher's exclusive keyboard focus against the Stage's, two morph owners in one window — a large change for at most the
~3.5 MiB of one window (W39), which the budget no longer needs.

**Acceptance: the gate (`measure.py --daemon real`, default passes abc and the 20-cycle test, `budget.py`), two interleaved pairs.**

| metric | before r1 / r2 | after r1 / r2 | budget |
|---|---|---|---|
| PSS frontend @1 output (MiB; USS) | 126.3 (102.3) / 123.8 (98.9) | **110.4 (84.6) / 107.1 (80.1)** | ≤ 150 ✔ (card: ≤ 148) |
| RSS lib / anon @1 output (MiB) | 115.6 / 86.6, 115.9 / 84.1 | 105.8 / 67.5, 105.9 / 63.5 | — |
| PSS per extra output (MiB, mean of 2) | +1.0 / +0.2 | −0.8 / +2.5 | ≤ +6 ✔ |
| popup input → first commit (ms, median of 5) | 18.6 / 16.8 | 17.3 / 16.1 | ≤ 16.7 (both sides at the line under load) |
| popup daemon patch → first commit (ms) | 14.0 / 14.4 | 14.4 / 13.5 | — |
| island morph: commits, frame p50 / p99 (ms) | 38, 16.6 / 22.4 · 40, 16.3 / 18.2 | 40, 16.4 / 18.6 · 40, 16.3 / 18.4 | — |
| PSS growth, 20 cycles (MiB) | +7.96 / −0.76 | +9.64 / −0.22 | ≤ 2 (scatters both sides, W35) |
| idle frames, 30 s (fps) | 0 / 0.67 (the minute flip at 16:52:00) | 0 / 0 | ≤ 1 ✔ |
| idle CPU, daemon + frontend (%) | 0 / 0.1 | 0.53 / 0 (load 10 in r1) | < 0.5 |
| mapped surfaces, idle | 3 / 3 | 3 / 3 | ≤ 4 ✔ |

Pair for pair the bare shell is **−16 MiB PSS / −18 MiB USS** at one output. **Attribution caveat:** in these two pairs the
libraries' *PSS* did not fall (29.9 / 29.7 → 31.5 / 31.1) while their RSS fell 9.9 — some other process was mapping the same
kimageformats/libheif pages then, so dropping them freed little PSS; in the option runs an hour earlier (40.3 / 35.4 / 40.1 →
29.9 / 31.4 / 30.5) and in a last pair with `--smaps-dump` (31.1 → 22.7) it did. The plugin filter saves 9.9 MiB RSS; its PSS share
depends on who else maps those libraries (a KDE session does). The −16 here is the arenas'; they alone would take W41's 152.4 to
~137. The last pair's per-path diff: only image plugins and their libraries (x265, libheif, OpenEXR, libraw, libjxl, libaom, libde265,
libmng, libavif, libyuv, libvmaf, libtiff, jasper, KF6Archive, lcms2, …) and libQt6PrintSupport left the map — 59 files; fcitx5's
input context, qt6ct and the wayland shell integration plugins are mapped on both sides. **Quick card** (`quick-open.sh`, washi, each
frontend through its own launch.sh, two interleaved runs): first 31 / 30 → 32 / 31 ms, warm median 22.0 / 22.0 → 22.0 / 22.0 ms —
the arenas cost nothing measurable on the most allocation-heavy open. The popup and morph rows do not move (the popup's first commit sits at the 16.7 ms line on both sides at load 5–10; W41 read 14.9–15.9 quieter).
`frontend/test-morph.sh` (washi, sekai, washi-bottom, sekai-bottom; real + mock phases; the frontend started through launch.sh by a
scratch `qs` shim, since the test runs `qs -p` itself — row 462): ok, 270 shots, 45 spring runs. **Start-up:** launch.sh takes 60–66 ms before the exec instead of 10 (a few `mkdir`/`ln` per plugin dir; a first version with one
`ln` per entry took 520–640 ms and was rewritten), once per session.

**Large and not shell-owned (per-path `--smaps-dump`, before, @1 output):** the NVIDIA driver (libnvidia-gpucomp 10.3 MiB,
eglcore 5.3), Qt (Qml 4.8, Quick 4.3, Gui 2.3, Widgets 2.2 — quickshell links Widgets), the QML GC heap 3.0, Inter.ttc 3.0, and
fontconfig's serif fallbacks NotoSerif 0.8 and FreeSerif 0.7 (some text asks for a family fontconfig resolves to a serif); the
user's qt6ct platform theme and fcitx5 input context ~0.5. Not changed.
||||||| 8598d57b
### 2026-10-25 — W42 tiles: one hit area, the Snes frame builds its own part, a tile bench, the bench windows get the tile sheet (machine A, loaded; I211, I199, I192; rows 475–478)
"HEAD" is `8598d57b` (this branch's start: the daemon, the frontend copied with `git archive`); "W42" the branch's frontend, the same daemon binary (no Rust changed). Release binaries in `$CARGO_TARGET_DIR/release`, sandboxes `w42-tiles-*`. The machine ran at load 5–16 (the user's session and other agents): wall-clock medians moved by ±10–20 % between runs of the same frontend, so every comparison below is a pair or an ABBA run in one invocation. **CPU** per tile or Block (the process's utime + stime over the rounds, `tile.sh` and `block.sh`) moved far less than the wall clock and is the figure to read first.

**Quick card (`quick-open.sh`, HEAD → W42, 9 warm opens, one run per look; first open in brackets).** The final run:

| look | HEAD | W42 | first open |
|---|---|---|---|
| washi (default) | 22.0 | 21.0 | 30 → 31 |
| sekai | 12.0 | 12.0 | 19 → 20 |
| kami | 25.0 | 23.0 | 32 → 32 |
| snes | 30.0 | 23.0 | 39 → 32 |
| kanso | 13.0 | 20.0 (reversed order: 11.0 vs 11.0) | 18 → 19 |

An earlier run (before the pageless strip was restored, higher load): washi 24 → 22, sekai 12 → 13, kami 26 → 26, snes 37 → 33, kanso 17 → 16. **Target washi ≤ 18 ms: not met** (21–22 ms). The washi card is the Blocks: see the tile bench (the paper frame is about 0.5 ms CPU per Block; contract row 475).

**Tile bench (`tile.sh`, 120 QuickTiles × 31 rounds per look, CPU per tile, mean of two frontend runs, ABBA order; kami 41 rounds).**

| look | HEAD CPU µs | W42 CPU µs | Δ CPU | Δ wall |
|---|---|---|---|---|
| washi | 2252 | 2210 | −2 % | −3 % |
| sekai | 1058 | 961 | −9 % | −10 % |
| kami | 4238 | 4028 | −5 % | −5 % |
| snes | 3852 | 2594 | −33 % | −35 % |
| kanso | 978 | 849 | −13 % | −9 % |
| terminal | 1300 | 1278 | −2 % | −13 % (noisy) |

Attribution of a washi tile (one run, CPU per tile, 31 rounds, the variants of HEAD): the two Blocks with the paper frame 2159–2339; the same Blocks with the frame drawing nothing 1191; the Blocks alone 2339 (both Blocks with paper), with a badge Icon 2718 (+379), with the two Texts 2761 (+422); no visuals at all 137. So a washi tile is mostly its two Blocks (the frame about 0.5 ms per Block), then the Texts and the badge Icon (about 0.4 ms each); QuickTile's own tree is small, and the W42 changes take 30–60 µs off it.

**Block bench (`block.sh`, 100 pairs × 15 rounds per look, per Block; the bench window holds a tile sheet as the Stage does).** The first Sketch runs of this session had no tile sheet in the window, so every Relief made its own pair: kami's relief read about 3 ms CPU per Block there. With the sheet, the same relief is about 0.5 ms CPU:

| look | build | wall µs | CPU µs | anon KiB |
|---|---|---|---|---|
| snes | HEAD | 922 | 1227 | 176 |
| snes | W42 | **605** | **770** | **118** |
| kami | HEAD | 665 | 1533 | 226 |
| kami | W42 | 670 | 1513 | 233 |

kami attribution (HEAD variants, the same method): relief off (`Block.qml`) 338 / 970 / 193; frame host off, relief on 428 / 707 / 137; Sketch's paint skipped 558 / 977 / 230; the paint's arithmetic without any canvas call 525 / 1090 / 229, against HEAD's 525–530 / 1187–1263 / 231 in the same runs. The Canvas item itself costs about 75 KiB anon per block (HEAD without it: 160 KiB against 217–235). snes attribution: frame host off 110 / 173 / 41, so the frame host plus the Snes frame cost about 0.5 ms wall per small snes block after W42 (contract row 476).

**Sketch (kami): no change, and why.** The outline's per-block cost is the canvas (75 KiB anon) and the stroke calls (about 0.2 ms CPU); the arithmetic (the random walk, the field) is about 0.1 ms CPU per block and no wall time. A geometry memo (`papercache`-style) would save at most that, so it was not built. The variants below were measured in the first block runs, whose window had no tile sheet (the relief is the same in all of them, so the comparison between them holds): an SVG Image per key (`sketchcache`-style) was worse, +97 KiB anon per block and +18 % CPU; a framebuffer canvas (`renderTarget: FramebufferObject`) and a threaded one (`renderStrategy: Threaded`) showed no gain.

**Snes frame (the W42 change):** a `visible` tree was built for every block (a small block built about 30 hidden items); each part is now a `Loader` on its block kind. Snes tiles: −33 % CPU per tile (above); snes Blocks: −34 % wall, −37 % CPU (above).

**Pixel identity (`block-identity.sh`, HEAD vs W42, 11 scenarios × bar, card, quick, launcher, session, held):** every pair identical within the noise rule, 0 strongly different pixels (a channel off by more than 64) in all 66 comparisons; faint differences 1–140 px per shot. The same tool with HEAD against itself (kami) gives faint counts of the same size (card 132, quick 115, launcher 67, session 8, held 51, bar 1): the faint ones are the noise floor. The snes frame's ground (the lock's and the polkit dialog's backdrop) is none of these scenes: a scratch check (not committed) drew the snes frame's three kinds, ground, card and small, in one shot each, HEAD against W42: 0 differing pixels (the shot holds 112 colours, so the frames drew). The tile states have no scene either: a scratch check (not committed) drew a focused tile, a failed tile and a pageless tile, HEAD against W42, twice (focus set, and not set): 0 differing pixels in both; the focused and the unfocused W42 shots differ by 89 px, so the focus ring is drawn. The failed ring is in `quick-failed` of the keyboard run (the Wi-Fi tile's red ring, "No answer in 30 s").

**Keyboard and pointer (`frontend/test-quick-sections.sh`, release binaries, `kurashi-mock`):** exit 0; every check ok, including the arrows, Tab and Return on the tiles, Right and Escape, the Menu key, a right click on a tile (no toggle), the mod tiles, focus across contribution changes, the forced, connecting and failed tiles, and the scan subscription. The test rewrites tracked PNGs under `frontend/shots/quick-sections`; they are restored after the run.

**Not done / not met**
- washi ≤ 18 ms: not met (21–22 ms). The card's cost is its Blocks (the paper frame, the frame host and the Block base) and its Texts and icons: contract rows 475, 476, 477.
- kami per-Block: not reduced. Its relief (about 0.33 ms wall) and its frame (about 0.24 ms wall: the frame host, Sketch and its canvas) are in `Block.qml` and `FrameHost.qml`: row 476.
- Sketch memo: not built (see above). The Canvas per block is the cost, and a shared outline sheet would be the next step (a design change).
- The pageless tile's right 22 px stay dead, as before (row 478; kept by the MouseArea's width, by construction: no test clicks there). A right click on the arrow zone shares the left-click branch; no test exercises it either.
- The sidebar's toggles (`TogglesSection.qml`) use QuickTile too; the identity run covers the quick card, not the sidebar, and no sidebar test was run for this change.
- quick-open at this load is noisy (±2 ms over 9 opens; the kanso pair flipped between runs).

**Backlog-worthy:** the pageless strip (row 478); the badge Icon and the Texts (row 477); FrameHost's frame load for kinds a frame does not draw (row 476); the Sketch canvas per block (75 KiB anon); the bench windows now carry a tile sheet, so block and tile numbers from before this entry are not comparable with it.

### 2026-10-25 — W41 icons: the subset installed and preferred, a per-name fallback, the grain memoised (machine A; I194, I199, rows 445–447)
"Before" is `caa335c8` (this branch's start: its daemon and frontend), "after" this branch. Real `kurashid` (release) and the frontend
in a headless sway sandbox (gles2, one 2560×1440 output, sandboxes `w41-icons-*`); paired runs back to back.

**Quick settings card (`tools/bench/quick-open.sh`, washi, the default style; first open | median of 7 warm, ms). Card target: warm ≤ 25 ms.**

| daemon (icon fonts it sees) | frontend | first | warm median (range) |
|---|---|---|---|
| before (Material Symbols) | before | 57 | 50.0 (48–54) |
| after (Material Symbols) | after | 29 | **22.0** (20–22) |
| after (subset installed) | before | 61 | 48.0 (43–49) |
| after (subset installed) | after | 29 | **22.0** (21–25) |

The grain memo (row 447) does the work: in a first pass with the memo alone the same method gave 48 → 26 ms.

**Pixel identity (`tools/bench/block-identity.sh`: kanso, sekai, glass, terminal, washi × bar, card, quick, launcher, session, held; 30 pairs per run).**

| run | compared | strong px | faint px (largest channel step) |
|---|---|---|---|
| C (one invocation, the W39 method) | before's frontend with Material Symbols vs after's frontend with the subset under the Material Symbols family names; the daemon sees only Material Symbols | 0 | 975 (1) |
| control | before vs before, same daemon | 0 | 824 (2) |
| A | before's daemon: before vs after frontend (both Material Symbols) | 0 | up to 114 px in one shot |
| B | after's daemon (subset installed): before vs after frontend | 0 | up to 94 px in one shot |

Run C is the test of the subset itself: `fc-match` resolved the renamed file for both names, the frontend draws only it, and the glyphs
match the full family pixel for pixel but for ±1 rounding. Run A tests the QML changes (Icon.qml, the memo), run B the shipped
configuration. Comparing shots across separate runs (before with Material Symbols against after with the subset) was not usable: the
minute turned between them, and the only differences were the clock digits (checked on crops: 13:34 against 13:40).

**PSS (`tools/bench/measure.py --daemon real` with the bench gate's flags and `budget.py`; @1 output; pairs back to back).**

| run | PSS frontend, core (MiB) | per extra output | popup commit (ms) | 20-cycle growth (MiB) |
|---|---|---|---|---|
| before 1 | 157.5 | +2.8 | 15.1 | +16.7 ✘ |
| after 1 | 152.3 | +0.5 | 14.9 | +1.1 |
| before 2 | 158.2 | +1.5 | 15.2 | −1.6 |
| after 2 | 152.4 | +0.6 | 15.9 | +0.4 |

Budget (≤ 150 MiB @1 output, ≤ +6 MiB per extra output): **not met** before (157.9 mean) and after (152.4 mean). The −5.5 MiB is in both
pairs. Where the −5.8 MiB of pair 2 went (per-path PSS of the 1-output reading, `--smaps-dump`): anonymous memory −4.0 MiB, the JS GC
heap −0.9 MiB, the icon font −0.9 MiB (Material Symbols Sharp 1342 KiB → Kurashi Symbols Sharp 411 KiB). The icon font's PSS saving is
small because the sandbox shares the Material Symbols pages with another process (PSS splits a shared page); a user without that sharing
sees the RSS saving (W39: 22.5 → 13.9 MiB). The anonymous drop is most likely the grain memo: each block's Image held its own copy of the
grain strings; the memo shares one. That is inferred, not isolated.

**Not improved, not met:** PSS @1 output is 152.4 MiB against 150 (budget not met; this card gives 5.5 MiB of it). The 20-cycle growth row
is noisy (+16.7 in one run, −1.6 in the next; W39 saw −12…+26) and this card does not touch it. The quick card was measured for washi
only; the other looks were not re-measured. The icon font's RSS was not measured here (W39's number stands).

**`tools/bench/budget.py`:** the PSS checker matched the K68 material and web-dock allowance rows (`PSS allowance…`) and crashed on their
`+ ≤ N MiB` text, so `just bench-gate` failed on HEAD too. It now matches `pss frontend` only; the allowance rows show n/a.

### 2026-10-25 — W39 block: a lighter Block, the quick card's build, idle windows, the icon font (machine A; I199, I204, I194)
Real `kurashid` (release, built from `2b2e682a`), headless sway gles2 on renderD128, one 2560×1440 output, sandboxes
`w39-block-*`. "Before" is the frontend of `2b2e682a` (`git archive`), "after" this branch, run in the same invocation
(ref and new interleaved where the tool allows), so both see the same load and the same other processes. **PSS across
days is not comparable here:** pages a file shares with another process (a Quickshell in the user's session, another
agent's sandbox: Qt's libraries, Material Symbols) split their PSS, so one frontend read 124–171 MiB PSS @1 output today
depending on what else ran (USS 99–144); before/after pairs below always ran back to back. New tools (tools/bench/README):
`block.sh`, `block-identity.sh`, `quick-open.sh`, and `*_rss_by` in measure.py's readings.

**Block (`tools/bench/block.sh`: 100 quick-tile pairs — a pill Block with a badge Block in it — made 15 times per look,
median of the warm rounds; anonymous memory with 500 pairs held minus none, rough).** Where the 135 µs went (HEAD, sekai /
glass, a piece removed each): the five Behaviors 17 / 20 µs, the four Loaders and FrameHost 34 / 35 µs, the `layer.*` lines
0, an inactive SoftShadow 7 µs (an active one, glass: 40 µs). The new Block keeps the stacking order and makes what only
some looks draw in two Loaders — under the content (the line chrome's press flash, the relief) and over it (the relief
with `texture.text`, the pen's outline, the decor frame) — and has two Behaviors (one eased press value for the sink and
the shrink, one colour animation for the fill).

| look (chrome) | before µs / Block | after µs / Block | anon KiB / Block before → after |
|---|---|---|---|
| sekai (keycap) | 135 | **95** | 86 → 67 |
| glass (soft) | 165–168 | **130** | 91 → 70 |
| kanso (flat) | 130–135 | **95–98** | 70 → 50 |
| terminal (line) | 135 | **125** | 58 → 50 |
| kami (line + sketch frame) | 775–810 | 828–835 (+3–7 %) | 418–458 → 461–470 |
| washi (line + paper frame, the default style) | 1342–1352 | 1375–1435 (+2–6 %) | 334–337 → 343–348 |
| snes (keycap + frame) | 750 | 765 (+2 %) | 179 → 177 |

**Not improved:** in a look with a decor frame the frame costs 5–10× the Block itself (washi's Paper frame builds its grain
SVG in JS once per block: ~1.2 ms), and the extra Loader level adds 2–7 % there. (Two runs; the second interleaves the frontends per look.) Row 447 asks for the grain to be memoised.

**Pixel identity (`tools/bench/block-identity.sh`, HEAD vs this branch):** 11 scenarios — kanso, sekai, glass, terminal,
washi, kami, snes, sekai with a 2× shadow at 135°, sekai on paper, glass on paper with `texture.text`, terminal with a
rough pen and a text modifier — × the bar, the island card (the month grid), quick settings, the launcher, the session
menu and the card's Close key held down (the sink, the shrink, the flash): **0 strongly different pixels in all 66 pairs**;
up to 122 faint ones per shot (text and blur rasterisation; the same frontend against itself with only the icon font
changed reads up to 94). The first run failed only where the minute turned between the two frontends (the clock's width
moves the bar groups): the tool now shoots both inside one wall-clock minute and retries.

**Quick settings card (`tools/bench/quick-open.sh`, W37's method: a synchronous view Loader on sandbox copies, runtime.ui
patch → view made; first open | median of 7 warm).**

| | before | after |
|---|---|---|
| default style (washi, Paper frame) | 60 \| 48 ms | 60–61 \| 48–50 ms |
| … with the Paper grain memoised (row 447, scratch variant) | — | 44 \| **21 ms** |
| sekai (W37's 14 ms) | 21 \| 14 ms | 19 \| **12 ms** |

Attribution (sekai, after): without the ten tiles 10 | 5 ms, without their badge Blocks 17 | 11, with the icon font off
26 | 13 — the tiles are ~0.7 ms each and the two Blocks are ~0.2 of it; the rest is QuickTile's own tree (texts, icons, two
MouseAreas, the focus ring, bindings), not QuickPanel's. Washi (before): without the tiles 19 | 10, without the badges
40 | 34. **Not met:** the card's ≤ 8 ms warm target — 12 ms in sekai, 48–50 in the default style (21 with row 447). Nothing in
QuickPanel.qml itself was worth cutting; a lighter QuickTile (one hit area, the chevron and focus ring made lazily) is the
next step, outside this card's paths.

**Idle windows (pass a only, PSS @1 output, two runs each, this branch's frontend with one part left out).** All of it: 170.7 /
168.8; without the peek's shape and shadow 169.2 / 171.3; without the island's shape, relief and head face 169.1 / 169.3;
without the tray column 171.2 / 171.2; without the Stage window 162.9 / 162.0 (−7.3); without the Launcher window 163.2 /
163.1 (−6.6). The anonymous class moves in 2.0 MiB steps between runs, so a hidden part under ~2 MiB does not show: the
Stage's and the Launcher's hidden trees are not where their cost is — it is the windows themselves (W35: ~3.5 MiB each)
and their first-use state. A Loader for the peek's shape (self-contained, made only while a peek morphs) was built and
measured, gained nothing visible, and was **reverted**; the island shape (on every popup's first frame, ≤ 16.7 ms gated)
and the launcher card (its field and list referenced by the window's handlers; W37-daemon's ≤ 40 ms cold-open gap) were
left as they are. K16's persistent Stage window stays.

**Icon font (I194).** Material Symbols keeps ~4300 ligatures; the shell's sources name 411 (`nix/icon-names.txt`, from
`nix/icon-names.py`). `nix/icon-font.nix` builds "Kurashi Symbols Rounded/Sharp" from them with every axis and the
FILL alternates (`settings.fill`): Sharp 8.9 MB → 0.68 MB, Rounded 15.2 → 1.18 MB. Measured with the same subset under the
original family name (fontconfig pointed at it; pass a, two runs each, the ref frontend):

| | font RSS @1 out | font RSS after the popup | PSS @1 out |
|---|---|---|---|
| Material Symbols (today) | 22.5 MiB | 24.5 | 129.1 / 129.7 |
| subset, every axis (the derivation) | **13.9** | **13.9** | 125.9 / 128.1 |
| subset, GRAD 0 and opsz 24 pinned | 12.8 | 12.8 | 124.0 / 127.7 |

The PSS saving here is smaller than the RSS saving because another process mapped the same Material Symbols file during
these runs (its pages were split); with the shell the only one mapping it, PSS falls by about the RSS amount (I194's
8.2 MiB). A static instance was not pursued: Icon.qml sets FILL and wght per icon (`filled`, `icon.weight` 300/400/600),
so it would need several instances and an Icon.qml change; the pinned variant saves 1 MiB more but rounds outlines, the
every-axis subset draws pixel for pixel (identity run: kanso, sekai, glass, terminal, 0 strong pixels). Not wired yet:
kurashi-theme must prefer the new families and the modules install the package (row 445); a name the subset lacks would
draw as letters (third-party mods' icons): row 446.

**`just bench-gate` (measure.py + budget.py, `--max-load 2.5`, load 0.6–1.1, before/after interleaved, two runs each).**

| metric (gate) | before r1 / r2 | after r1 / r2 | budget |
|---|---|---|---|
| idle frames, 30 s (fps) | 1.2 / 0.67 (the minute flip) | 0 / 0 | ≤ 1 |
| idle CPU, daemon + frontend (%) | 0.067 / 0.033 | 0 / 0 | < 0.5 ✔ |
| PSS frontend @1 output (MiB; USS) | 167.3 (140.7) / 169.0 (142.4) | 167.3 (140.9) / 170.5 (143.9) | ≤ 150 ✘ |
| PSS per extra output (MiB, mean of 2) | +0.7 / +2.2 | +2.3 / +0.5 | ≤ +6 ✔ |
| popup input → first commit (ms) | 14.8 / 14.8 | 15.1 / 15.4 | ≤ 16.7 ✔ |
| PSS growth over 20 cycles (MiB) | +4.00 / +5.28 | +0.37 / +0.75 | ≤ 2 (scatters, W35) |
| mapped surfaces, idle | 3 / 3 | 3 / 3 | ≤ 4 ✔ |

The idle frame and cycle rows differ by chance (the bar's minute flip fell into the before runs' windows; the cycle row
scatters as W35 described). **PSS @1 output did not move** (167.3 → 167.3, 169.0 → 170.5): the idle shell holds a few dozen
Blocks (~18 KiB less each is ~0.5 MiB, inside the run-to-run spread). What would move it: the icon font subset (row 445,
up to ~8–9 MiB where the shell is the font's only user), not the Block. The badge token (I204) changed only colours.

### 2026-10-25 — W35 perf: popup latency, idle frames, memory (machine A; B37, B34, B35/B7, I93)
Real stack (`kurashid` release build of `2bbc8f7`, no crate changed since), headless sway gles2 on renderD128, one
2560×1440 output, `frontend/launch.sh`. **Load:** the user's live session runs an installed `kurashid` that burns ~1 core
around the clock (cputime 8 h 45 min over 2 d 7 h; most likely the B36 config-watch loop, fixed on main but not deployed;
observed read-only), so the 1-minute load never fell below 1.5 and every W35 run used `--max-load 2.5` (W33: 1.5); the
load at the start of each run is in its JSON (1.5–2.5). "Before" is the frontend of `2bbc8f7` (main), "after" this
branch, both measured by this branch's `measure.py`; gate passes `abc`, 30 s idle, 20 cycles, plus `--latency 10`.

**Method changes (tools/bench, see README).** (1) I93: PSS is summed from `smaps` without the GPU driver's device
mappings (`/dev/nvidia*`, `/dev/dri/*`); USS (private clean + dirty) and a per-class breakdown are reported beside it. Here
the left-out part is `/dev/nvidiactl`: 8.1 MiB at one output, 15.1 once the popup has been open — add it to compare with
earlier rows (before: 174.8 + 8.1 = 182.9 the old way; W33's gate read 174.8 the old way on `191fd68`, before the W34
morphs). (2) B37: a popup round starts only once the Stage has committed nothing for
0.3 s and counts only the Stage's own first commit. Before, a round could start while the previous close still folded
(the fold outlasts the 0.6 s gap), and then "the first commit after the input" was its next frame: W33's 45–118 ms mixed
such ~1 ms readings with the real ~80 ms ones. (3) `--latency` sends the same action through one open IPC connection and
timestamps the daemon's `runtime.ui` patch, so the time splits into parts.

| metric (gate) | before | after | budget |
|---|---|---|---|
| idle frames, 30 s (fps) | 0.80 | 0.67 | ≤ 1 ✔ |
| idle CPU, daemon + frontend (%) | 0.033 | 0.033 | < 0.5 ✔ |
| PSS frontend @1 output (MiB; USS) | 174.8 (148.4) | **154.2** (132.4) | ≤ 150 ✘ |
| PSS after the popup was open once (MiB) | 194.8 | 175.8 | — |
| PSS per extra output (MiB, mean of 2) | +9.0 | **+0.4** | ≤ +6 ✔ |
| popup input → first commit (ms, CLI path, median of 5) | 88.9 | **13.7** | ≤ 16.7 ✔ |
| — CLI start + handshake → daemon patch (ms) | 2.1 | 2.2 | |
| — daemon: act → done / patch (ms) | 0.14 | 0.14 | |
| — frontend: patch → first Stage commit (ms, 10 IPC rounds) | 84.7 | 8.5 | |
| PSS growth over 20 cycles (MiB) | +4.63 | −0.56 | ≤ 2 (scatters, see below) |
| mapped surfaces, idle | 3 | 3 | ≤ 4 ✔ |
| violations | 3 | **1** (PSS @1 output) | |

**The plain `just bench-gate` at the end** (no load gate; load 1.7–1.9): idle frames 0 fps, idle CPU 0 %, PSS 151.7 MiB
with −0.0 per extra output, popup 13.3 ms, mapped 3 — and the cycle row +16.48 MiB (fail): two violations. **The cycle
row is noise on this branch, no leak shown:** eleven 20-cycle runs read −12.0 to +25.7 MiB (this branch: −0.6, +16.5,
−3.2, +10.1, +3.0, −7.7, +9.4, +25.7; with the old, synchronous clock grid put back: −12.0, −2.4, +16.3 — so not the
async grid), while main's frontend read −2.6 to +4.6 at a ~45 MiB higher level (274–281). Each reading stays flat for
12 s after its phase (sampled every 2 s in three of the runs), so it is not memory still on its way back to the system.
The reading after 40 rounds spans 217.7–231.6 MiB across runs; after 80 rounds one run read 231.7, after 200 one read
234.3 — inside that spread, so no trend shows, though a slow leak under ~2 MiB per 100 rounds is not ruled out.
A hypothesis, not measured: the QML engine collects the destroyed views on allocation, not on time, so a reading lands
before or after a collection by chance; main's extra resident objects may make collections more frequent. The gate needs a steadier reading before this row means anything (a forced
collection before each reading through a bench-only hook, or the median of several cycle blocks).

**B37 popup latency — cause and fix.** CLI start-up is 2 ms and the daemon answers in 0.14 ms: the time was the
frontend's. Timestamps logged in `Store.handle` and the Stage's view Loader (temporary, removed) show it: patch in at
19.0297 s → clock view made at 19.0999 s → first `set_size` at 19.1009 s. The island card's view is made synchronously
when the card opens, inside the patch handler, and the clock view took 73–84 ms, ~65–70 of them for the month grid's 42
day cells (a Block each, W21; with the cells' Repeater at 0 the view took ~11 ms and the popup 12.4 ms). Fix
(`ClockView.qml`): the cells are made asynchronously in a box of their final size (the grid always has 7 × 6 cells), so the
card has its height at once and the shape grows straight to it; the cells are there before the view fades in
(test-stage, test-morph, test-desk and test-texture pass; their shots differ from the committed ones by anti-aliasing
noise only, as do views this branch does not touch, so they were not re-committed). The open also makes the generic view
first and then the clock view (`onOpenChanged` reads `wantedKind` before it follows `runtime.ui`): ~1 ms, left as is.
**Not fixed:** the quick settings card (`quick.toggle`, not in the gate) takes 67 ms (QuickPanel made in 62–65 ms, the
phone's whole tree), same cause. A general fix belongs in the Stage: make the view Loader asynchronous and let the shape
grow to the card size the view had last time (per kind), holding the growth only on a view's very first open.

**B34 idle frames — cause.** Every idle commit in the gate and in `none`/`kami` (65 s windows) is the bar
(`quickshell#34`, the Bar has no namespace of its own) at hh:mm:00: the clock face's minute flip (FlipText, W21) — 20
commits over 305 ms in the default theme, 40 over 657 ms in kami (its longer motion), 0 commits outside it. W33's 10 s
windows made that 2.0 and 3.1 commits/s when they held a minute turn and 0 when not; over the budget's 30 s it is
0.67 fps (pass), and in kami 1.33 fps (over) for a window that holds the flip. Not changed (a designed animation, the
lead's and the user's call): the options are a shorter flip (≤ 300 ms ≈ ≤ 20 frames), no flip at idle, or a budget that
names the minute. Acceptance "0 idle frames in every scenario" is not met for that reason only.

**B35/B7 memory — attribution (A/B: copies of the frontend with parts of `shell.qml` left out; pass a, 5 s idle, no
cycles; medians of three).**

| variant | PSS @1 out | per extra output | Δ @1 out |
|---|---|---|---|
| main (before) | 175.4 | +11.15 | |
| without the hidden Desktop and TextureOverlay windows | 159.5 | +0.55 | −15.9 |
| after the lazy windows (this branch's first cut) | 159.9 | +0.75 | |
| … without the Stage window | 144.5 | +7.65 * | −15.4 |
| … without the Launcher window | 152.4 | +0.75 | −7.5 |
| … without Lock / Toasts / Sidebars / mod surfaces, Dock, corners | 159.2–160.3 | +0.35–1.45 | ≤ 0.7 |
| … session keys made only while the menu shows (second cut) | 152.3 (USS −3.0) | +1.25 | −7.5 |
| bar only (main, nothing else) | 127.1 | +7.4 * | |
| Quickshell floor (one PanelWindow + Text per output) | 88.5 | +2.7 | |
\* without the Stage there is no popup before the hotplug, so first-use costs land on the outputs.

The per-output cost was almost all the Desktop and TextureOverlay windows: both were made per output and kept hidden
(`visible: false` makes no surface, but the window and its whole item tree exist). Cut 1 (`shell.qml`): each is made by a
LazyLoader only while `desktop.enabled` (per output) or the everything scope is on. Cut 2 (`SessionMenu.qml`): the five
session keys exist only while the menu is on screen; their glyphs had pulled Kochi Mincho, Adwaita Mono and Symbola in
as fallback fonts (−3.2, −0.4, −0.2 MiB of file pages). By class after both: anon 82.2, libs 51.5 (floor 40.4), fonts
11.6 — Material Symbols Sharp alone 8.2 MiB (the variable font is resident almost whole, 8.9 MB file), Inter 1.6,
fallbacks ~2 — shm/QML heap 4.1, files 4.6. The first popup leaves +21 MiB resident (anon +18.3, JS heap +3.1); further
opens add nothing beyond the cycle row's scatter.

**What remains over budget, with numbers:** PSS @1 output 151.7–154.2 against 150 (USS 132.4); the quick card's open,
67 ms against 16.7 (not gated). Candidates, not done (each
touches W34's surfaces or the font setup, so they are the lead's to schedule): the Stage window's idle cost (~8 MiB after
cut 2, ~3.5 of it the window itself, I11; the rest its hidden tree — peek shape, tray column, close key — which could be
made only while shown, at a cost to the first frame), the Launcher window (7.5 MiB idle, ~3.5 the window, the rest its
hidden card), a subset or static instance of the icon font (up to ~7 MiB), the image
plugins Qt loads (kimageformats, libheif, OpenEXR, libraw, x265: ~3 MiB of libraries).

**`just bench-texture` after (W33's nine scenarios × three runs, `W33_MAX_LOAD=2.5`, sandboxes `w35-perf-w33-*`; medians;
W33's values of 2026-10-22 in brackets — older tree, GPU mappings counted, popup rounds not from rest):**

| metric | none | kami | paint-shadows | spotlight | pen-text | controls | carried | fixed | everything |
|---|---|---|---|---|---|---|---|---|---|
| idle frames, 10 s (commits/s) | 0 (2) | 0 (3.1) | 0 | 0 | 0 | 0 | 2 * (0) | 0 | 0 |
| idle CPU, daemon + frontend (%) | 0 (8.3) | 0 (8.7) | 0 (8.4) | 0 (8.5) | 0 (8.8) | 0 (8.5) | 0 (8.3) | 0 (8.4) | 0.199 † (8.3) |
| PSS @1 output (MiB) | 152.3 (177.6) | 174.5 (201.0) | 186.6 (227.8) | 186.6 (221.9) | 177.5 (203.8) | 170.6 (211.9) | 184.5 (225.8) | 184.6 (225.8) | 205.1 (249.9) |
| USS @1 output (MiB) | 130.4 | 153.3 | 164.7 | 164.7 | 156.2 | 148.7 | 162.6 | 162.7 | 183.2 |
| PSS after the popup was open once | 173.9 | 206.2 | 206.0 | 206.2 | 212.1 | 192.1 | 204.1 | 203.9 | 221.9 |
| PSS per extra output (MiB) | +0.25 (+10.5) | +4.05 (+10.6) | +10.70 (+19.8) | +11.30 (+20.05) | +5.15 (+10.6) | +9.75 (+18.9) | +10.05 (+17.85) | +10.10 (+19.05) | +30.55 (+42.4) |
| popup → first commit (ms) | 12.8 (85.1) | 11.0 (45.0) | 13.7 (104.1) | 12.9 (101.7) | 11.5 (48.4) | 15.2 (104.3) | 13.4 (102.4) | 13.7 (102.6) | 11.9 (81.8) |
| mapped surfaces | 3 | 3 | 3 | 3 | 3 | 3 | 3 | 3 | 4 |
| motion frames (commits/s) | – | – | – | 135.7 (140.1) | 9.4 (3.6) | – | 27.1 (30.5) | 27.5 (30.5) | – |
| motion CPU, frontend (%) | – | – | – | 14.45 (7.64) | 4.22 (1.24) | – | 12.09 (13.94) | 12.35 (13.08) | – |
| PSS after motion (MiB) | – | – | – | 183.6 (223.0) | 211.6 (219.2) | – | 233.8 (278.4) | 234.1 (275.1) | – |

\* `carried`: two of three runs held the minute flip (20 bar commits at hh:mm:00); the third read 0. † Four of the 27
runs (none r3, kami r2, everything r2 and r3) read 0.2–0.4 % frontend CPU and 20–39 wakeups/s with 0 commits; the other
23 read 0 and 0.1. Not attributed: in four interleaved idle runs each of main's and this branch's frontend (`none`) all
eight read 0 and 0.1, and an strace pass of the same tree saw 0.1 syscalls/s. The daemon's idle 8 % of W33 is gone (B36,
fixed on main). Every scenario still fails PSS @1 output (152–205 MiB against 150); the textures add +18 to +53 MiB at one
output and +4 to +11 per extra output (per window tile sheets, K59), the overlay +30. Motion CPU: `spotlight`'s 14.5 % (13.2–14.4 in all three
runs) did not reproduce — four later runs, main's and this branch's frontend interleaved, read 7.4–7.8 % (main) and
7.4–7.6 % (branch), W33's level; not attributed (the machine's state during the set is the suspect). `pen-text` reads
4.0–4.5 % on main's frontend and 4.6–5.6 % on this branch's in the same interleaved runs (9.3 and 9.6 frames/s), against
W33's 1.2 % and 3.6 frames/s: the held quick card commits ~8 frames/s on main too (W34), so the rise is not this
branch's; the branch's extra ~0.5 % over main in two runs is within their scatter.


`just bench-texture` = `tools/bench/w33.sh` on the real stack: nine scenarios × three interleaved runs (`measure.py --daemon real --config <scenario> --passes abm --idle 10 --warmup 10 --cycles 0 --max-load 1.5`, `frontend/launch.sh`), medians by `w33-summary.py` (`tools/bench/results/w33-<scenario>.json`, raw runs `-r1` to `-r3`; results are gitignored). Measured tree: `191fd68` (the driver's pass selection is the only change after `72db4d6`, which the first run of the set recorded; the measuring code is the same). Binaries: release build of `8cbce81` (no crate changed). Machine A: 12 cores, GTX 1060 (driver 580.178), headless sway on renderD128 (gles2), one 2560×1440 output. Load (1 min) at the start of each run was 0.36–1.10: all 27 runs quiet, none waited. The idle window is 10 s, not the budgets' windows (idle CPU is a 10 min budget, frames 30 s), so those rows are screens.

| scenario | theme in effect (checked in each run) | motion, after the rest measurements |
|---|---|---|
| none | no texture | – |
| kami | style kami: paper dots 0.55, shadows on, pen 0.35 | – |
| paint-shadows | oil paint, shadows on, depth 2 | – |
| spotlight | oil paint, `light.mode` spotlight | pointer swept across the bar for 5 s |
| pen-text | kami + `pen.text_*` 0.6 | quick card opened and held |
| controls | leather, `texture.controls` on | – |
| carried | squared paper, sheet carried | right sidebar opened and closed five times |
| fixed | squared paper, sheet fixed | as carried |
| everything | squared paper, scope everything (overlay) | – |

Medians of three runs; PSS and CPU of the frontend unless marked; `–` = not measured in that scenario.

| metric | none | kami | paint-shadows | spotlight | pen-text | controls | carried | fixed | everything |
|---|---|---|---|---|---|---|---|---|---|
| idle frames, 10 s (commits/s) | 2 | 3.1 | 0 | 0 | 0 | 0 | 0 | 0 | 0 |
| idle CPU, frontend (%) | 0.000 | 0.000 | 0.000 | 0.000 | 0.000 | 0.000 | 0.000 | 0.000 | 0.000 |
| idle CPU, daemon (%) | 8.348 | 8.746 | 8.445 | 8.545 | 8.844 | 8.546 | 8.348 | 8.447 | 8.349 |
| wakeups/s, frontend | 0.1 | 0.1 | 0.1 | 0.1 | 0.1 | 0.1 | 0.1 | 0.1 | 0.1 |
| wakeups/s, daemon | 34.1 | 32 | 31.9 | 38 | 32.9 | 33 | 33 | 32.7 | 33.1 |
| PSS frontend @1 output (MiB) | 177.6 | 201.0 | 227.8 | 221.9 | 203.8 | 211.9 | 225.8 | 225.8 | 249.9 |
| PSS per extra output (MiB, vs popup closed) | +10.50 | +10.60 | +19.80 | +20.05 | +10.60 | +18.90 | +17.85 | +19.05 | +42.40 |
| PSS daemon (MiB) | 27.3 | 29.8 | 33.4 | 32.8 | 30.6 | 29.7 | 30.9 | 31.4 | 30.5 |
| popup input → first commit (ms) | 85.1 | 45.0 | 104.1 | 101.7 | 48.4 | 104.3 | 102.4 | 102.6 | 81.8 |
| mapped layer surfaces, idle, 1 output | 3 | 3 | 3 | 3 | 3 | 3 | 3 | 3 | 4 |
| motion window (s) | – | – | – | 7.1 | 8.1 | – | 15.1 | 15.1 | – |
| motion frames (commits/s, all surfaces) | – | – | – | 140.1 | 3.6 | – | 30.5 | 30.5 | – |
| motion CPU, frontend (%) | – | – | – | 7.64 | 1.24 | – | 13.94 | 13.08 | – |
| motion CPU, daemon (%) | – | – | – | 8.63 | 9.05 | – | 8.70 | 8.70 | – |
| motion wakeups/s, frontend | – | – | – | 1020.8 | 22.1 | – | 332.8 | 341.1 | – |
| PSS frontend after motion (MiB) | – | – | – | 223.0 | 219.2 | – | 278.4 | 275.1 | – |

**Against the budgets** (`budget.py` on the medians). Passing: mapped surfaces (3; 4 with `everything`, at the limit) and idle frames in the six scenarios with the texture on (0 fps). Failing in every scenario: PSS at one output (178–250 MiB against 150), PSS per extra output (+10.5 to +42.4 MiB against +6), popup → first commit (45–104 ms against 16.7 ms) and idle CPU of daemon + frontend (8.3–8.8 % against 0.5 %). Also failing: idle frames in `none` (2.0 fps) and `kami` (3.1 fps). Not run: the open/close cycle row (`--cycles 0`).

**Deltas against `none`.** PSS at one output: +23 MiB kami (the look), +26 pen-text, +34 controls, +44 spotlight, +48 carried and fixed, +50 paint-shadows, +72 everything. Per extra output the texture adds +7 to +10 MiB (paint +9.3, spotlight +9.6, controls +8.4, carried +7.4, fixed +8.6), the overlay adds +32 (`everything`), and kami and pen-text add +0.1. The daemon's PSS grows by +2 to +6 MiB. Idle CPU and wakeups differ from `none` by nothing beyond the loop below. Popup: no texture effect (85 ms in `none`, 82 in `everything`, 102–104 ms in paint, spotlight, controls, carried and fixed); the kami look is lower (45–48 ms), not explained.

**Motion.** `spotlight`: 140 commits/s during the 7.1 s sweep (about 60 pointer events/s), frontend CPU 7.6 %, about 1,020 wakeups/s. `carried` and `fixed`: 30.5 frames/s over the 15 s of ten toggles, frontend CPU 13.9 % and 13.1 %, about 340 wakeups/s; the sheet mode changes what is drawn, not how often. `pen-text`: the quick card's own animation, 3.6 frames/s over 8.1 s, frontend CPU 1.2 %. The daemon stays at its idle level during every motion (8.6–9.1 %).

**Finding: the daemon's 8 % idle load is a config-watch loop, not the texture.** The daemon alone, with no frontend, idles at 8.2 % CPU and 37 wakeups/s when its config.toml exists, and at 0.00 % and 0 wakeups/s without one (diagnostic runs in the sandbox, not in the table). The default gate, which has no config file, measured 0.166 %. strace shows the loop: each read of config.toml by the daemon raises an inotify `IN_OPEN` (mask 0x20) on that file. The watcher in `crates/kurashid/src/config.rs` (`watch()`, notify 8.2.0, whose inotify backend subscribes to OPEN; its callback does not filter `EventKind::Access`) takes that for an edit, waits 150 ms and calls `store.reload()`, which reads config.toml, managed.toml, styles/, looks/ and profiles/ again. That is about 5.5 reloads a second and about 3,600 `statx` a second, with the frontend absent. Any config.toml triggers it. Not changed here (kurashid is outside this card's paths): ignore `Access` events in the callback, or drop `IN_OPEN` from the mask, then measure again. Check the other notify watchers of directories the daemon reads (`crates/kurashi-mod-tasks/src/service.rs`) for the same loop.

**Not resolved.** (1) Popup → first commit: 118 ms in the default gate with no texture (the 2026-10-09 gate measured 2.6–7.3 ms). The gate has no config file, so it is not the loop; the cause is not identified. (2) Idle frames of 2.0 to 3.1 fps in `none` and `kami` but 0 in the other seven scenarios: one diagnostic run of `none` saw no commits in 10 s, so the cause is unknown and may be transient.

**Default gate on this tree** (`just bench-gate`, no texture, default passes, 30 s idle): idle frames 0.67 fps (pass), idle CPU 0.166 % (pass), PSS 174.8 MiB with +9.3 per output (fail; limits 150 and +6), popup 118.2 ms (fail), +2.32 MiB over 20 panel cycles (fail; limit 2), mapped 3 (pass). Three violations; the gate exits 1 as designed.

### 2026-10-19 — web dock host (W17, machine B iGPU, headless sway, shared machine; `mods/webdock/test/test-host.sh` phase 4)
Total PSS of the web host's process tree (patched Quickshell + QtWebEngine 6.11 / Chromium 140: host, zygotes,
renderers) with local fixture pages: **1 kept site 389–393 MiB, 5 kept sites 403–420 MiB** (two runs). The host is its
own process (K38): it is not counted in the frontend budget (K16) and is gone after `unload_after` (0 MiB). Hidden: 0
Wayland requests and commits in 10 s. Phase 0 for comparison: plain Quickshell window 97 MiB, WebKitGTK window 294 MiB
(`archive/spikes/webengine-phase0/README.md`). Real web apps cost more; re-measure on a quiet machine.

### 2026-10-09 — harness self-test / Quickshell floor (commit eca978f)
Trivial Quickshell bar (one `PanelWindow` per screen, one `Text`), headless sway gles2,
NVIDIA GTX 1060. Not a probe — a lower bound for "anything on Quickshell".
| Metric | Value |
|---|---|
| PSS @1 output | **110.1 MiB** |
| PSS @2 outputs | 112.8 MiB (+2.7 per output) |
| GPU memory | 4 MiB |
| Idle CPU / wakeups / commits / syscalls | 0 / 0 / 0 / 0 |
| Startup (launch → first commit) | 172 ms |
→ ~40 % of shellseikatsu's 272 MB RSS is Quickshell/Qt baseline before any feature exists.

### 2026-10-09 — M0 bake-off, lead quiet re-measure (branch feat/m0-bakeoff)
One probe at a time, headless sway gles2, GTX 1060, `--warmup 10 --idle 30`. Full matrix: `BAKEOFF.md`.
| | quickshell | iced | slint (CPU) | gpui | gtk4 |
|---|---|---|---|---|---|
| PSS 1 out / popup / 2 out (MiB) | 144.0 / 148.7 / 155.1 | 154.7 / 160.1 / 160.1 | 25.2 / 27.6 / 27.8 | 148.5 / 151.1 / 153.5 | 156.1 / 233.5 / 234.2 |
| idle wakeups/s · syscalls/s · commits/s | 0 · 3.1 · 0.03 | 118 · 233 · 0 | 1.6 · 0 · 0 | 178 · 725 · 61.8 | 0 · 46 · 0.7 |
| startup ms · popup ms | 143 · 2.0 | 356 · 2.2 | 54 · 1.8 | 339 · 22.8 | 489 · 1.9 |
Quickshell probe vs budget: idle frames ✔, idle CPU ✔, popup ✔, PSS 144 ✔ under K16 (✘ under old 108).

### 2026-10-09 — bench gate, real stack (M7.2, `just bench-gate`)
Real `kurashid` (isolated dirs, sandbox bus) + `frontend/` (main 3f40f8b), headless sway gles2, 30 s idle.
| Metric | Value | Budget |
|---|---|---|
| idle frames | 0 fps | ≤ 1 ✔ |
| idle CPU daemon + frontend | 0 % | < 0.5 % ✔ (30 s window; `--idle 600` for 10 min) |
| PSS frontend @1 output | 95.0–119.7 MiB | ≤ 150 ✔ |
| PSS per extra output (vs popup-closed) | +0.8 MiB | ≤ +6 ✔ |
| popup input → first frame | 7.3 ms | ≤ 16.7 ✔ |
| mapped layer surfaces idle (1 output) | 1 | ≤ 4 ✔ |
| daemon PSS / CPU / wakeups | 8.5 MiB / 0 % / 0 | — |

### 2026-10-09 13:25 — bench gate after wave 7 (0470378), quiet machine A
Real `kurashid` + full UI via `frontend/launch.sh` (NVIDIA EGL pin), release binaries from main,
no other compile jobs (the first quiet baseline for machine A).
| idle fps | idle CPU | PSS @1 out | per extra output | popup → frame | 20-cycle growth | mapped surfaces | result |
|---|---|---|---|---|---|---|---|
| 0.03 | 0 % | 104.3 MiB | **+6.0** | 2.6 ms | +0.63 MiB | 3 | **0 violations** |
Headroom: 46 MiB at 1 output (was 12 before M3.2). The per-output row sits exactly at its limit
(+6.0 vs ≤ +6): watch it — the next surface added per output must pay for itself.
Same frontend against the mock: 118.8 MiB @1 out, 0 wakeups/s (`docs/BAKEOFF.md` re-measure).

### 2026-10-09 15:15–15:35 — bench gate after wave 8, quiet machine B iGPU (313f094)
Tray widget + tray menu + Bluetooth panel, hybrid EGL pin (Mesa on the Radeon), release binaries from main,
`KURASHI_RENDER_NODE=/dev/dri/renderD129`, load < 1, 4 runs.
| run | idle fps | idle CPU | PSS @1 out | per extra output | popup → frame | 20-cycle growth | result |
|---|---|---|---|---|---|---|---|
| 1 | 0 | 0 % | 115.5 MiB | **+6.5** ✘ | 3.6 ms | +1.30 MiB | 1 violation |
| 2 | 0.03 | 0 % | 114.5 MiB | +5.9 | 3.3 ms | +0.50 MiB | 0 violations |
| 3 | — | — | 114.3 MiB | **+6.7** ✘ | — | — | 1 violation |
| 4 | — | — | 114.9 MiB | +4.7 | — | — | 0 violations |
@1 output dropped ~10 MiB (123.5–126.9 → 114.3–115.5) as the Mesa-pin experiment predicted. **Per extra
output sits on its limit: mean ≈ +5.95, 2 of 4 runs over by ≤ 0.7 MiB** (before the wave: +4.5–5.6, so
within the ±1 MiB run-to-run spread — not yet attributable to wave 8). Budget unchanged (lead/user
decision); next step: attribute (A/B 6b13d56 vs 313f094, ≥ 3 runs each) and cut per-output cost.

### 2026-10-09 14:09–14:40 — bench gate, quiet machine B (e72690f)
Real `kurashid` + full UI via `frontend/launch.sh`, release binaries from main, no compile jobs (load < 1).
| GPU (render node) | idle fps | idle CPU | PSS @1 out | per extra output | popup → frame | 20-cycle growth | mapped surfaces | result |
|---|---|---|---|---|---|---|---|---|
| RTX 3070 dGPU (D128), run 1 | 0.03 | **5.80 %** ✘ | 106.1 MiB | +2.1 | 3.4 ms | +0.12 MiB | 3 | 1 violation |
| RTX 3070 dGPU (D128), run 2 | 0.03 | **5.73 %** ✘ | 106.2 MiB | +2.3 | 3.2 ms | +0.30 MiB | 3 | 1 violation |
| RTX 3070 dGPU (D128), run 3 | — | 0 % | — | — | — | — | — | 0 violations |
| Radeon 680M iGPU (D129), run 1 | 0.03 | 0.07 % | 126.9 MiB | +5.6 | 3.1 ms | −0.14 MiB | 3 | **0 violations** |
| Radeon 680M iGPU (D129), run 2 | 0 | 0 % | 123.5 MiB | +4.5 | 3.4 ms | +0.32 MiB | 3 | **0 violations** |
| iGPU, Mesa EGL pinned (experiment) | 0 | 0 % | 114.4 MiB | +5.1 | 3.0 ms | +1.80 MiB | 3 | 0 violations |

**The dGPU idle-CPU failures are a runtime-PM artefact, not a frontend loop:** a per-second timeline shows
0 ticks for ~45 s, then ~1.7 s of CPU on qs's *main thread* (inside the NVIDIA driver) exactly while the
RTX 3070 is `resuming` from runtime suspend (`/sys/bus/pci/devices/0000:01:00.0/power/runtime_status`),
then 0 again. A 30 s window that catches a resume fails; one that doesn't reads 0 %. Two consequences: on
the dGPU a resume also blocks the UI thread for ~2 s, and a hybrid laptop should never render the shell on
the dGPU (it also keeps the dGPU in use). niri renders on the iGPU here, so the **iGPU rows are machine B's
baseline**. Raw JSON: `tools/bench/baselines/machine-b-2026-10-09/` (dGPU gate JSON not kept).
Headroom on the iGPU: 23–27 MiB at 1 output; per extra output **+4.5–5.6 of ≤ +6** — as tight as machine
A. glvnd loads both EGL vendors on a hybrid (`launch.sh` pins only with one render node): pinning Mesa on
the iGPU saves ~10 MiB (114.4 MiB) → Kaizen card (pin the vendor of the GPU the session renders on).
Golden screenshots on machine B are pixel-identical to machine A's refs (same Nix fonts, pixman).

### 2026-10-09 — bench gate after wave 5 (b39974d): full UI on the real stack
Bar + Stage + island faces + toasts/center + launcher + lock, real `kurashid`, serial run.
| idle fps | idle CPU | PSS @1 out | per extra output | popup → frame | mapped surfaces | result |
|---|---|---|---|---|---|---|
| 0.03 | 0 % | 137.9 MiB | +4.0 | 3.9 ms | 3 | **0 violations** (headroom 12 MiB) |
Earlier "exited early / 6.4 fps" readings came from parallel agents sharing sandbox names — fixed
(sandbox names carry the pid).

Lead check after the merge (Icon retries when the theme family changes; `Theme.iconFamilyFallback`): quick card, washi,
9 warm opens each, one run — merged 29.0 / 28.0 ms, the agent's frontend 28.0 ms. Machine load average 6–10 during the
run (the agent's 22.0 ms was measured quieter); the edit costs nothing measurable.

## Mods (K41: an enabled mod's own cost, mod on vs off)
| Mod | Machine / renderer | Idle frames | Per output | Once | 20-cycle growth | Note |
|---|---|---|---|---|---|---|
| webdock (shell side, W20) | B, gles2 renderD129 | 0 commits / 10 s hidden | +6.2 MiB USS (median of 3; runs swing ~40 MiB) | +3.8 MiB USS (shared dock window, first reveal) | −0.9 MiB | PSS unusable on 2 outputs under gles2 (a ~1.9 TiB mapping, I93); bar widget +0.8 MiB PSS. Web host process: not yet measured (I79/BENCH) |
| webdock (web host process tree, W20) | B, sandbox | 0 commits / 10 s | — | 405–417 MiB PSS with 1 site kept; 409–434 MiB with 5 (two runs each); 0 sites: not measured | — | Own process (K38), gone after `unload_after`; Phase 0 was 255–262 MiB for one view in the hosting process alone |
| app dock (core, opt-in `dock.enabled`, W25-dock, K51) | B, gles2 renderD129, 1 output | 0 commits / 10 s hidden (autohide), 0 / 10 s shown | +6.9 MiB USS hidden (dock on vs off, medians of three: 152.5 vs 145.7; one output, so this includes the once-per-shell component load; the 4 px edge window is the only surface) | +2.2 MiB USS on the first show (the dock window, made then kept) | not measured | `DOCK_MEASURE=1 frontend/test-dock.sh`; absolute USS swung ~50 MiB between sessions on this shared machine (106 vs 152 MiB), deltas held |

### 2026-10-25 — web dock follow-ups (W38-webdock; I191's measure numbers, re-measured once)
The webdock mod's shell side, mod on and off, from the dock test's measure phase (`mods/webdock/test/test-dock.sh`,
`DOCK_PHASES=measure`; I191 quoted W35's run of the same phase). Machine A (session 13, its only GPU is `renderD128`,
gles2). The re-measure is one run of the phase: its own numbers, not a replacement for the quoted row.
| Measure | Machine / renderer | Idle frames | Per output | Once | 20-cycle growth | Note |
|---|---|---|---|---|---|---|
| I191, as quoted (W35 measure phase) | A (session 13); renderer not restated in I191 | 0 commits / 10 s hidden | +2.86 MiB USS | +2.89 MiB USS (first reveal) | — | +5.08 MiB USS mod on, one output (quoted, not re-run here) |
| W38 re-measure (this run) | A, gles2 renderD128 | 0 commits / 10 s hidden | +8.0 MiB USS (median of 3 at two outputs; off 146–175, on 153–178 MiB) | +4.89 MiB USS (first reveal; +16.8 MiB PSS) | −0.46 MiB USS | one run each at one output: mod on 246.4, off 154.1 MiB PSS (delta 92.2; the bar widget alone 9.7). Not medians, not repeated: open. Run-to-run spread is ±15 MiB, so the per-output figure is not a trend |

PSS is unusable with two outputs under gles2 (a ~1.9 TiB mapping, I93), as in the W20 row. The phase's checks pass:
per-output USS at most 10 MiB, and 20 reveal/hide cycles add at most 1 MiB of USS. The W38 changes (the forced tip, a
`PopupWindow` made only while shown, and the notes' shots) add no window while the dock is hidden; the idle check is 0 commits.

### 2026-10-26 — timer mod: idle frames and daemon wakeups (W43-timer, K73; row 500)
The timer mod on the real `kurashid` (a release build of `228168c2`, thin LTO) under headless sway (gles2, renderD128) with
the frontend: `tools/bench/measure.py --daemon real`, sandbox prefix `w43-timer-`, warm-up 10 s, idle 30 s. Pass B counts the
commits of each layer surface over the idle window; pass A reads the daemon's CPU and wakeups over the same window.
| Scenario | Idle commits (30 s) | Daemon CPU | Daemon wakeups/s | Note |
|---|---|---|---|---|
| Mod on, no timer, bar shown | 20 in one burst at the bar's minute flip (14:37:00, 309 ms); 0 otherwise | not measured | not measured | the bar's own clock (quickshell#34) |
| Mod on, a 10 min countdown running; bar and desk off; island faces = clock only (no view shows the timer) | 0; no bursts | 0.0 % | 0.0 | daemon PSS 27.6 MiB; the frontend's wakeups 0.1/s |
- Idle frames: 0 with the mod on and no timer, apart from the bar's minute flip; 0 with a running countdown that no view shows.
- The daemon holds no timer while the countdown runs: its one deadline is ten minutes away, so no wakeup falls in the window.
- Not measured: a countdown that a view shows (the glance, the panel, the desk card or the island face). Its own tick is one
  frame a second while it is visible (Ma), and it stops when the view closes.
- Configs for the second row: `mods.enabled = ["timer"]`, `bar.enabled = false`, `desktop.enabled = false`,
  `island.main.faces = ["clock"]`; the countdown starts from the measured command (`timer.start`, 600 s) before the frontend runs.
