# probe gtk4 — gtk4-rs 0.10 + gtk4-layer-shell 0.7 (GTK 4.22.4)

Build: `nix build probes/gtk4 -o probes/gtk4/result`  (or `nix develop` + `cargo build --release`)
Run:   `probes/gtk4/result/bin/probe-gtk4`   (needs `$KURASHI_SOCKET`, a Wayland session with layer-shell)

Dev helpers (inside `nix develop`): `dev/up.sh` starts sandbox `gtk4` + mock + probe;
`dev/smoke.sh [bin]` takes the screenshots in `shots/`; `dev/sh.sh <cmd>` runs in the sandbox env.
Layout: `src/main.rs` (app, IPC, bars, popup), `src/widgets.rs` (Island, GLArea shader), `src/blur.rs`.
