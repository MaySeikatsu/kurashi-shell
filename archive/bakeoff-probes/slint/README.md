# Probe slint

Slint 1.18.1 (software renderer, UI compiled at runtime by slint-interpreter) + own
smithay-client-toolkit 0.21 layer-shell glue (Slint has no layer-shell support).

Build: `cd archive/bakeoff-probes/slint && nix develop -c cargo build --release`
Run (inside the sandbox env; dev-shell libs on LD_LIBRARY_PATH):
`nix develop ./archive/bakeoff-probes/slint -c archive/bakeoff-probes/slint/target/release/kurashi-probe-slint`
(`nix build ./archive/bakeoff-probes/slint` is defined in the flake but was NOT exercised.)
Env: `KURASHI_SOCKET`, `KURASHI_PROBE_DEBUG=1` (prints poll timeouts).
Layout: `ui/probe.slint` (UI + Theme global, templated), `src/ui.rs` (source gen, tokens, shader),
`src/ipc.rs` (NDJSON thread), `src/main.rs` (wayland + loop).
