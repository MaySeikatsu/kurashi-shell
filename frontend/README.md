# frontend (Quickshell / QML, K3)

Thin view over the kurashid IPC socket: subscribes, renders, sends intents/actions. No business
logic, polling or `Process` here (CLAUDE.md rules 1, 5).

## Run (sandbox only, never the real display)
```sh
nix develop
cargo build --release -p kurashi-mock -p kurashi
eval "$(tools/bench/sandbox.sh start dev)"
target/release/kurashi-mock --outputs HEADLESS-1 &
qs -p frontend &            # grim frontend/shots/x.png to look
tools/bench/sandbox.sh stop dev
```
Acceptance: `python3 tools/bench/measure.py --name frontend --warmup 10 --idle 30 -- qs -p frontend`.

## Layout
- `shell.qml` one `Bar` per output (Variants over `Quickshell.screens`, hotplug-safe) + ONE `Stage`
  retargeted to the focused output (focused workspace's output, latched while open).
- `core/` singletons: `Store` (IPC, merge-patch, revision-gap resync, 250 ms to 4 s reconnect,
  `connected`/`live`), `Theme` (the only reader of `theme.tokens`), `I18n` (`tr(key)`).
- `components/` Button, IconButton, Slider, Chip, ProvenanceChip, Island, ModNode (mod UI tree).
- `surfaces/` `Bar`; `Stage` (content-sized overlay layer, top-centred under the Island; permanently mapped but
  transparent with empty input/blur regions while hidden: map/unmap cycles leaked heap, K16;
  reveal = slide on first presented frame, no group opacity).
- Strings: `i18n/{en,ja}/frontend.toml`. Until the daemon serves them, `tr` returns the key.

## Conventions
- Style only from `Theme` tokens; never branch on theme/profile names.
- Components are presentational: signals out, props in; surfaces turn signals into `Store.act/intent`.
- Every animation/timer is gated on visibility or on an active interaction; idle = zero frames.
- New QML types must be added to the folder's `qmldir`. Never assign `anchor.item` dynamically.
- Reconnect veil: `Store.live` false keeps last state, dims content (`opacity.stale`), shows a glyph.

## Core API (`core/`)
- `Store.watch(doc)` / `unwatch(doc)` refcounted; declaratively `Watch { doc: "svc.media"; active: cond }`.
  Surfaces watch only what they render. `Store.docs[doc]` is reactive; docs the daemon does not
  serve (`unknown_doc`) stay absent, with no retry.
- `Store.act(action, args, cb)` -> `cb(done, err)` (`done.data` for results); `Store.query(kind, q, cb)`
  -> `cb(items, err)`, only the newest query per kind is answered; `Store.intent(...)` unchanged.
- Reconnect: fresh Socket per attempt (a reused one stayed silent after the first failure), all
  watched docs re-subscribed on welcome; `instance` change drops cached docs.
- `I18n.tr` reads the daemon's `i18n` doc. Island `reason` `manual` counts as `user` (`byUser`).
- Real-daemon smoke test: `nix develop -c frontend/test-real.sh` (screenshots in `shots/real/`).

## Memory (M3-memory, 2026-10-09)
Launch through `frontend/launch.sh` (not bare `qs -p frontend`): with the NVIDIA driver active it
pins glvnd to the NVIDIA EGL vendor, so Mesa's libgallium + libLLVM are not loaded for nothing
(**-13 MiB**, 135.6 -> 122.9 MiB mean of 3). It does nothing without NVIDIA or when
`__EGL_VENDOR_LIBRARY_FILENAMES` is already set. Tried with no effect: `MALLOC_ARENA_MAX=1`,
`QSG_RENDER_LOOP=basic`.

PSS @1 output, real daemon, headless sway gles2, GTX 1060, one surface removed per row, 3 runs
(mean [min-max] MiB; run-to-run spread is ~5 MiB, so deltas under that are noise):
| variant | PSS @1 out | popup |
|---|---|---|
| all surfaces | 135.6 [129.6-139.1] | 137.9 |
| no Bar | 130.1 [127.8-131.9] | 129.7 |
| no Stage | 132.6 [131.8-133.0] | 132.7 |
| no Island in Bar | 135.4 [134.2-136.9] | 135.9 |
| no Launcher | 135.5 [134.2-136.2] | 137.5 |
| no Toasts+Center | 138.7 [138.1-139.3] | 140.7 |
| no Lock | 139.2 [139.0-139.5] | 140.9 |
Composition of the full stack (smaps): anon heap 56, libnvidia-gpucomp 15.7, libLLVM 7.0,
libnvidia-eglcore 6.3, Qt Quick/Gui/Qml 14, libgallium 4.8, CJK font 4.3. Each surface costs
0-5 MiB: below the noise, nothing worth lazy-loading; the floor is driver + Qt.

Cycle gate: `measure.py` (real daemon) opens/closes island, notification center and launcher
`--cycles` (20) times each after an equally long warm-up. First-use allocations keep landing for
~20 opens (+5.8 MiB island, then +0.2 MiB per further 20), which is saturation, not a leak, hence
the warm-up. Result now +0.5 MiB / 20 cycles.
