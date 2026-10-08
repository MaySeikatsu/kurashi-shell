# Probe iced
_(Written by the lead from the agent's hand-back — the agent's tools refused report files.)_

Versions: iced 0.14.0 (wgpu), iced_layershell 0.19.1 (layershellev 0.19.1), wayland-client 0.31 (own wl_output watcher thread), tokio 1; winit-core/winit-common pinned to 0.31.0-beta.2 (beta.3 breaks iced_exdevtools); wayland-backend `client_system` enabled so WAYLAND_DEBUG works (needed by the bench's commit counter).
Run: `probes/iced/target/release/kurashi-probe-iced` (build: `cd probes/iced && nix develop -c cargo build --release`; run tooling via `nix develop ./probes/iced -c …`).

## Capability checklist
- layer-shell any edge + exclusive zone: ✔ NewLayerShellSettings{anchor, exclusive_zone}
- multi-output + hotplug: ✔ add verified. iced_layershell exposes no output name per window with AllScreens → own wl_output v4 watcher spawns one NewLayerShell per output (OutputOption::OutputName). Removal relies on compositor closing the surface (unverified)
- popup on layer surface: ✔ real xdg_popup via get_popup on the layer surface (IcedNewPopupSettings, anchor rect under the island)
- first-frame-gated reveal: partial — t0 = first RedrawRequested of the popup window, not presentation feedback
- session lock: API exists (iced_sessionlock), not built
- screencopy: ✘ no API in iced_layershell
- blur ext-background-effect: ✘ not implemented; possible via iced::window::run (raw wl_surface) + Settings.with_connection
- custom shader: ✔ iced::widget::shader, wgpu pipeline + WGSL noise; requests next frame only while in the popup tree
- IME text-input-v3: partial — ime_preedit + InputMethod exist; untestable headless
- fractional scale: ✔ wp_fractional_scale + viewporter objects created (WAYLAND_DEBUG)
- runtime-loaded mod UI: ✔ recursive serde Value → Element renderer, no interpreter
- theme tokens at runtime: ✔ colours, sizes, radii, durations, easings, fonts from theme.tokens
Emulation: no group opacity/transform in iced → reveal = alpha on every colour + panel size scaled in layout. Island width is a char-count estimate, not measured text.

## Developer workload
clean build ~6 min (3 jobs, contended) | incremental 13 s | hot reload ✘ | probe LOC 1169 (main 798, net 183, glow 188) |
binary 20 MB | deps 346 | compile-fix iterations 3 (+1 runtime: event::listen_with silently drops RedrawRequested → listen_raw) |
docs 2/5 (crate ships no examples; read layershellev/iced_layershell source)

## Bench summary (agent run, noisy)
idle commits/s 0.0; popup latency 2.5 ms; morph 23 commits (p50 16.5, p99 16.8 ms); startup 356 ms; PSS 94.5 MiB (1 out) / 100 (popup) / 100 (2 out); GPU 15 MiB; idle CPU 0.2 %; **wakeups 117.9/s, 230 futex syscalls/s** despite 0 commits (undiagnosed; executor or clipboard thread suspected).

## Pain points / surprises
- crates.io drift broke a fresh build (winit-core beta.3) → manual pin.
- Any Message redraws ALL windows. Animation = vsync-paced frame subscription that exists only while animating.
- No per-window output name exposed.
- `sandbox.sh stop` without pgrep (procps) in PATH silently kills nothing → stale sways accumulate.

## Requests
Bench needs libwayland (`client_system`) for commit counting; run through `nix develop ./probes/iced`.
