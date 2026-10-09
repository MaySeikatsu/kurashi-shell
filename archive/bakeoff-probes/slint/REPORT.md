# Probe slint
_(Written by the lead from the agent's hand-back — the agent's tools refused report files.)_

Versions: slint 1.18.1 (renderer-software + systemfonts), slint-interpreter 1.18.1, smithay-client-toolkit 0.21.1, wayland-client 0.31 (libwayland via `client_system`), wayland-protocols 0.32 (staging).
Run: `nix develop ./archive/bakeoff-probes/slint -c archive/bakeoff-probes/slint/target/release/kurashi-probe-slint` (build: `cd archive/bakeoff-probes/slint && nix develop -c cargo build --release`; `nix build` defined, untested).
Architecture: own platform backend = SCTK layer surfaces + wl_shm buffers (Abgr8888) + one MinimalSoftwareWindow per surface. Whole UI (bar, popup, mod widgets) loaded by slint-interpreter from a templated `.slint` string. Own poll loop, frame-callback pacing, no timers when idle.

## Capability checklist
- layer-shell any edge + exclusive zone: ✔ SCTK; bar TOP|LEFT|RIGHT, zone = bar.height
- multi-output + hotplug: ✔ output-add → 2nd bar; removal not exercised
- popup on layer surface: partial — separate layer surface (TOP anchor, margin = bar.height), centred under the island
- first-frame-gated reveal: ✔ first buffer committed with shown=false; `shown` set in the frame callback
- session lock: API exists in SCTK, not built
- screencopy: no SCTK helper; raw protocol needed, not built
- blur ext-background-effect: partial — raw protocol bound for bar + popup; unverified (no global in headless sway)
- custom shader: ✘/partial — no shader API in the software renderer; 200×80 CPU plasma → Image per frame, only while the popup is shown
- IME text-input-v3: ✘ custom platform gets no IME; TextInput via wl_keyboard utf8, no key repeat
- fractional scale: ✘ scale fixed at 1
- runtime-loaded mod UI: ✔ via slint-interpreter (generated `.slint`; whole source recompiled on tree change, state changes are property sets)
- theme tokens at runtime: ✔ Theme global; partial — cubic-bezier easing must be a literal → easing-token change recompiles

## Developer workload
clean build ~255 s (3 jobs, contended) | incremental (UI string) ~100–125 s (include_str + thin LTO; 0 s if loaded from disk, not wired) |
hot reload ✘ (feasible, recompile path exists) | probe LOC ~1150 Rust + 261 .slint | binary 27 MB | deps 291 |
compile-fix iterations 1 | docs 3/5 (thin for custom platform + interpreter)

## Bench summary (agent run, noisy)
pass_a: idle CPU 0.0 %, wakeups 0.0/s, PSS 21.6 MiB (1 out) / 22.6 (popup) / 22.8 (2 out), hotplug survived.
pass_b: startup 64 ms, idle commits 0.0/s, popup latency 2.0 ms, morph 23 commits (p50 16.4, p99 ~17 ms).
Clock-face width quantised to 8 px so a minute tick doesn't morph the island.

## Pain points / surprises
- No layer-shell in Slint; own backend ~400 lines (MinimalSoftwareWindow makes it cheap).
- Interpreter = mod UI for free, but 27 MB binary, slow builds, string-keyed unchecked Rust↔UI contract.
- Unverified (no input devices): slider drag/origin, island click/scroll, typing, Escape.

## Incident
First helper run had sway off PATH → `sandbox.sh start` silently failed → probe + mock ran ~1 min on the user's live session (one bar, `/run/user/1000/kurashi/ipc.sock`, one grim of the live desktop — not stored). Agent killed only its PIDs and removed the socket. Root cause fixed in `tools/bench/sandbox.sh` (fails closed since 61d76fa).
