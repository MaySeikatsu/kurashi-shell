# Probe gpui
_(Written by the lead from the agent's hand-back — the agent's tools refused report files.)_

Versions: gpui + gpui_platform from zed git rev b5e03c7 (crates.io gpui 0.2.2 has no layer-shell), feature `wayland`; wayland-client 0.31.15 (second connection for hotplug); rustc 1.98; wgpu renderer.
Run: `archive/bakeoff-probes/gpui/run.sh` (build: `nix develop ./archive/bakeoff-probes/gpui -c cargo build --release --manifest-path archive/bakeoff-probes/gpui/Cargo.toml`).

## Capability checklist
- layer-shell any edge + exclusive zone: ✔ `WindowKind::LayerShell(LayerShellOptions{..})`
- multi-output + hotplug: partial — only via a second raw wayland-client connection: no display-change callback, `global_remove` ignored (TODO in gpui_linux), no output names (matched via uuid v5 of the name); removal untested
- popup on layer surface: partial — separate Overlay layer surface (no xdg_popup for layer surfaces in gpui), 4 px below the bar
- first-frame-gated reveal: partial — first `render` of the popup, no presentation hook
- session lock: ✘ not in gpui
- screencopy: partial — `screen_capture_sources` behind `screen-capture` feature
- blur ext-background-effect: ✘ only `org_kde_kwin_blur` bound
- custom shader: ✘ no public API; CPU gradient + 160 paint_quad tiles while the popup is visible
- IME text-input-v3: ✔ binding exists, `EntityInputHandler` implemented; untestable headless
- fractional scale: ✔ wp_fractional_scale bound
- runtime-loaded mod UI: ✔ recursive `serde_json::Value → AnyElement`, no interpreter
- theme tokens at runtime: ✔
- **idle discipline: ✘** — `WaylandWindowStatePtr::frame()` re-arms `wl_surface.frame` and commits on every callback even when nothing is dirty (4 renders vs 932 commits in 8 s on 2 bars). Not fixable without patching gpui_linux.

## Developer workload
clean build 569 s (release, thin LTO, 3 jobs, contended) | incremental ~156 s (`cargo check` ~5 s) | hot reload ✘ |
probe LOC 1443 (~290 text input) | binary 26.2 MB | deps 594 | compile-fix iterations 2 |
docs 2/5 (no guide; examples + gpui-shell; API churns on main)

## Bench summary (agent run, noisy)
startup 351 ms; **idle commits 61/s per surface**; idle CPU 0.47 %; wakeups 178/s; PSS 110 MiB (1 out) / 96 (2 out); popup latency 26.2 ms; morph 93 commits (inflated by the always-on frame chain; p50 16.3, p99 17.6 ms).

## Pain points / surprises
- Wayland frame loop never stops.
- Layer surfaces can't be resized/repositioned via public API; reveal scale simulated on an inner box.
- Fonts via fontconfig (flake sets FONTCONFIG_FILE with Inter + Noto CJK).
- Popup uses KeyboardInteractivity::OnDemand → Escape needs click focus first on sway.

## Incident
First launch ran with the sandbox down (`sandbox.sh start` failure swallowed) → bar appeared briefly on the user's live session and a grim captured the live desktop (not committed). Agent killed its PID and added guards. Root cause fixed in `tools/bench/sandbox.sh` (fails closed since 61d76fa).
