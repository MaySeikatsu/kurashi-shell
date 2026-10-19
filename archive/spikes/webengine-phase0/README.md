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
