# Card K-hybrid-egl — pin the EGL vendor of the GPU the session renders on (hybrid laptops)

**Read first:** `frontend/launch.sh`, `docs/BENCH.md` "quiet machine B" section (the measurements behind
this card), `tools/bench/sandbox.sh` (`KURASHI_RENDER_NODE`), `nix/hm-module.nix` (how the service runs
`launch.sh`, `KURASHI_QS`), `nix/package.nix` (runtime inputs).

**Problem:** with more than one DRM render node `launch.sh` pins nothing, so glvnd loads both the NVIDIA
and the Mesa EGL vendor. Measured on machine B (Radeon 680M + RTX 3070, niri on the Radeon): pinning Mesa
saves ~10 MiB PSS (114.4 vs 123.5–126.9 MiB). Rendering the shell on an NVIDIA dGPU with runtime PM also
stalls the UI thread ~2 s per dGPU resume, so the right vendor matters beyond memory.

**Owned paths:** `frontend/launch.sh`, new `frontend/test-launch.sh`, `nix/package.nix` (runtime deps
only, e.g. `wayland-utils`), `nix/hm-module.nix` (only if the service needs a dep on PATH).
NOT anything else under `frontend/`. Common rules: `docs/tasks/README.md`.

**Do:** keep the single-node rule as is. With several render nodes, find the compositor's main device:
first from `wayland-info` (linux-dmabuf feedback "main device", a dev_t → `/dev/dri/renderD*` via
`/sys/dev/char/<maj>:<min>`), else the render node of the card with `boot_vga=1`; then pin the vendor that
drives it (`nvidia` driver → `10_nvidia.json`; `amdgpu`/`i915`/`xe`/other → `50_mesa.json`), looked up in
the same glvnd dirs as today. Pin nothing when unsure. A user's `__EGL_VENDOR_LIBRARY_FILENAMES` or
`__NV_PRIME_RENDER_OFFLOAD` always wins. POSIX sh, no bashisms, no extra process left running, < 50 ms.
Comment the why (cite this card's numbers / K16).

**Acceptance:** `frontend/test-launch.sh` runs `launch.sh` with `KURASHI_QS` pointing at a stub that dumps
its env, against fake inputs (a temp sysfs-like tree passed via an env override you add for tests, e.g.
`KURASHI_SYSFS`): one node → NVIDIA pin (unchanged); AMD main + NVIDIA → Mesa; NVIDIA main + AMD → NVIDIA;
user override → untouched; unknown → no pin. Then, on this machine in the sandbox:
`KURASHI_RENDER_NODE=/dev/dri/renderD129` → qs maps no `libnvidia-eglcore` (`/proc/<pid>/maps`);
`…renderD128` → no `libgallium`. Never on the user's display. The lead measures `just bench-gate`.
