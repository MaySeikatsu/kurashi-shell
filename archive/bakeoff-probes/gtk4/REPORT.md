# Probe gtk4
_(Written by the lead from the agent's hand-back — the agent's tools refused report files.)_

Versions: GTK 4.22.4 (nixpkgs unstable 2026-10-08), gtk4-rs 0.10.3, gtk4-layer-shell 0.7.1 (C lib 1.3.0), gdk4-wayland 0.10.3, wayland-client 0.31.15 + wayland-protocols 0.32.13 (blur only), glow 0.16 (shader), serde_json, async-channel. No relm4 (plain gtk4-rs was enough).
Run: `archive/bakeoff-probes/gtk4/result/bin/probe-gtk4` (build: `nix build ./archive/bakeoff-probes/gtk4 -o archive/bakeoff-probes/gtk4/result`). Forces `GSK_RENDERER=gl`, `GTK_A11Y=none`; app flag NON_UNIQUE (no D-Bus name).

## Capability checklist
- layer-shell any edge + exclusive zone: ✔ LayerShell trait, auto_exclusive_zone_enable(), top/left/right anchors
- multi-output + hotplug: ✔ display.monitors() items-changed; two bars verified (shots/two-outputs.png); survived hotplug
- popup on layer surface: separate Overlay layer-shell window anchored top (centred under the island); NOT a GtkPopover
- first-frame-gated reveal: partial — t0 = frame-clock time of the first tick after map (frame 0 painted at opacity 0 / scale .96); not tied to wl_surface.frame
- session lock: ✘ no GTK API (would need ext-session-lock via raw wayland-client)
- screencopy: ✘ no GTK API (raw protocol only)
- blur ext-background-effect: partial — raw protocol via gdk4-wayland wl_display/wl_surface + own event queue on the same connection, set_blur_region; logs "unavailable" on headless sway; untested against a compositor with the global
- custom shader: ✔ GtkGLArea + glow (GLES 3.0, 200×80), ticks only while mapped. GskGLShader is dead in 4.22 (magenta fallback, verified)
- IME text-input-v3: ✔ by construction (GtkEntry); not testable headless
- fractional scale: ✔ GTK4 native wp-fractional-scale; not exercised
- runtime-loaded mod UI: ✔ widgets built from the JSON tree (row/column/text+bind/icon), no interpreter
- theme tokens at runtime: ✔ tokens → generated CSS → CssProvider::load_from_string on every theme patch

## Developer workload
clean build ~200 s nix build (125 crates, 3 jobs, contended); cold cargo ~110 s | incremental (one UI string) 10.4 s |
hot reload ✘ (GTK Inspector live-edits CSS only) | probe LOC 939 Rust | binary 1.0 MB stripped (+ GTK closure) |
deps 125 | compile-fix iterations 4 + 2 runtime pivots (GskGLShader → GLArea; GLSL 150 → ES 300) |
docs 3/5 (gtk-rs book decent; subclassing, GLArea, layer-shell Rust docs thin; GLShader deprecation rotted silently)

## Bench summary (agent run, noisy)
pass_a: idle CPU 0.03 %, 1.4 wakeups/s, PSS 59 MiB (1 out) / 99 (popup) / 101 (2 out), GPU 6 MiB, hotplug survived.
pass_b: startup 556 ms, popup latency 2.0 ms median, morph 20 commits (p50 16.5, p99 19.6 ms), idle commits 0.7/s (minute clock patch in window).
pass_c: 0.8 syscalls/s idle.

## Pain points / surprises
- GTK 4.22 renderer is `gl` (renamed from ngl). Default Vulkan renderer on this NVIDIA box: ~110 wakeups/s and 0.7 commits/s idle + swapchain warnings on hotplug. Forcing gl makes idle silent.
- GskGLShader non-functional in 4.22 → GtkGLArea needs a GL loader (eglGetProcAddress via libloading; fragile).
- Custom widgets (animated-width Island) need GObject subclass boilerplate; add_tick_callback runs only while animating.
- Popup scale needs GtkFixed::set_child_transform.

## Requests
none
