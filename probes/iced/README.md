# probe: iced 0.14 + iced_layershell 0.19.1

Build: `cd probes/iced && nix develop -c cargo build --release`  (or `nix build ./probes/iced`, untested)
Run (inside the sandbox env, mock running): `probes/iced/target/release/kurashi-probe-iced`
Bench/sandbox tooling needs the probe shell: `nix develop ./probes/iced -c <cmd>` (same nixpkgs rev as root).

`Cargo.lock` pins winit-common/winit-core to 0.31.0-beta.2: iced_exdevtools 0.19.1 does not compile
against beta.3 (`cargo update -p winit-common --precise 0.31.0-beta.2`, same for winit-core).
`wayland-backend` has `client_system` so `WAYLAND_DEBUG=client` works (needed by the bench).
