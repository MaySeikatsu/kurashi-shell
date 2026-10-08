# Probe quickshell
Versions: Quickshell 0.3.1 (nixpkgs), Qt 6.11.2, qsb from qtshadertools 6.11.2. QML only.
Run: `qs -p probes/quickshell` (or `nix run ./probes/quickshell`; `nix build` verified).

## Capability checklist
- layer-shell any edge + exclusive zone: ✔ PanelWindow anchors + auto exclusion.
- multi-output + hotplug: ✔ Variants over Quickshell.screens; survived_hotplug true, 2nd bar screenshot.
- popup on layer surface: ✔ PopupWindow (xdg_popup child of the layer surface), under Island.
- first-frame-gated reveal: ✔ Window.frameSwapped of first frame starts animation (Qt swap, not wl presentation feedback).
- session lock: ✔ API exists (WlSessionLock), not built.
- screencopy: ✔ API exists (ScreencopyView), not built.
- blur ext-background-effect: partial — BackgroundEffect.blurRegion on bar+popup; headless sway lacks protocol (qs warns, no-op), untested.
- custom shader: ✔ ShaderEffect + precompiled .qsb; animates only while popup visible.
- IME text-input-v3: partial — TextInput present, not testable headless.
- fractional scale: ✔ Qt6 native, untested headless.
- runtime-loaded mod UI: ✔ recursive Loader(source "Node.qml") + Repeater over JSON tree, no interpreter.
- theme tokens at runtime: ✔ everything via Store.tok(), fallbacks only if missing.

## Developer workload
clean build: n/a (no compile) | incremental: 0 s | hot reload: ✔ auto-reload on save, sub-second |
probe LOC: ~520 QML+GLSL | binary size: n/a | deps: n/a | compile-fix iterations: 4 |
docs quality: 3/5 (gaps on BackgroundEffect and QML pitfalls)

## Bench summary
idle 0.0 CPU%, 0 wakeups/s, 0 commits/s, 0 syscalls/s. PSS 163.6 MiB (1 out) / 166.7 (popup) / 164.6 (2 out). GPU 4 MiB.
startup 174 ms. popup latency median 2.4 ms. morph 21 commits, p50 16.3 / p99 18.1 ms. Noisy.

## Pain points / surprises
- font.families not available in QML Text; family chosen by script regex instead.
- qmldir must list every type; property names cannot start uppercase.
- Recursive component only via Loader.source.
- Slider drag and Escape/IME untested (no input devices headless).

## Requests
none
