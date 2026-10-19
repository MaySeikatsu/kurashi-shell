# Phase 0 spike: QtWebEngine in a Quickshell PanelWindow (2026-10-19, K38, K39)

Evidence for K39, kept as it ran (store paths of that day; not part of any test).
- `shell.qml`: one `WebEngineView` with a disk `WebEngineProfile` in a layer-shell `PanelWindow` (`keyboardFocus:
  OnDemand`). `//@ pragma Env LD_PRELOAD =` clears the sandbox's netjoin preload for Chromium's children (they inherit
  the namespace; K37 refuses the sandboxed zygote otherwise); `//@ pragma ShareOpenGLContexts` needs the patched build.
- `page.html`: an autofocused input that mirrors typed text into the title and the console; a visit counter in
  `localStorage` (profile persistence).
- `run.sh`: starts a sandbox, runs Quickshell (`QS_BIN` = the patched build: `nix build --impure` of
  `pkgs.quickshell.overrideAttrs` with `nix/patches/quickshell-webengine.patch`), types with `wtype`, takes grim
  shots, lists the engine processes' memory. Hard-coded store paths: qtwebengine-6.11.2 `fwlxhzls…`, wtype `1npk1bl9…`.

Results: stock Quickshell 0.3.1 aborts ("Argument list is empty"); patched: page loads, typed text arrives (the first
key was lost both times), `VISITS 1` stored; Quickshell PSS 255–262 MiB with one view; two zygotes ~79 MB RSS each.

## Engine comparison (same day, same sandbox, same page; `measure.sh`, `webkit-spike.py`, `webkit-shell.nix`)
Total PSS of the client's whole process tree after load + typing "hello kurashi":

| Client | Total PSS | Engine's share | Typed text |
|---|---|---|---|
| Quickshell, plain PanelWindow (`baseline-shell.qml`) | 97 MiB | — | — |
| Patched Quickshell + QtWebEngine 6.11 (Chromium 140) | 390 MiB (host 256, renderer 74, zygotes 60) | ≈ 293 MiB | first key lost |
| Python + GTK 4 layer-shell window, plain label | 114 MiB | — | — |
| Python + GTK 4 + WebKitGTK 2.54 (bwrap sandbox on) | 294 MiB (UI 140, web 116, network 36) | ≈ 180 MiB | all keys |

One tiny local page on machine B's iGPU, headless sway, a shared machine: real web apps cost much more in both.

## Privacy check (K38 "ungoogled by configuration")
`QTWEBENGINE_CHROMIUM_FLAGS="--log-net-log=<file> --net-log-capture-mode=Everything" SPIKE_IDLE=45 MODE=qtwe
measure.sh`: with the local page open and typed into for 45 s the net log has **0 events** (no request of the engine's
own, no Google endpoint). Positive control, `SPIKE_URL_OVERRIDE=http://example.com/`: the log records the page's
request (`http://example.com/`, host `example.com`). The library still contains Google URLs as strings (component
updater, FCM push, account endpoints); they are code paths the host keeps off, not traffic. Flags need `argc > 0`,
which the Quickshell patch provides (QTBUG-110157: ignored with `argc = 0`).
