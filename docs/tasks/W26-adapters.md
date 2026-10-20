# Card W26-adapters — Hyprland and Sway adapters (roadmap v0.3; CLAUDE.md "designed for Hyprland / MangoWM / Sway")

**User (session 10):** "as complete and usable as possible … WormShell especially from a planning and optimisation and
modularity, concept perspective." The compositor abstraction exists for exactly this (ARCHITECTURE §7: "no core
changes per adapter"). Efficient: write the adapters against fake sockets first, compile/test a few times.

**References:** WormShell `~/Projects/quickshell/WormShell/docs/10-compositor-adapter.md` §§3–7 (data model,
capabilities, Hyprland global workspaces, Sway i3-IPC); WormShell's code if any under `~/Projects/quickshell/WormShell/crates`
(grep `hypr`, `sway`); Quickshell's own Hyprland integration and DMS `…/scratchpad/insp/DankMaterialShell/quickshell/Services/{HyprlandService,CompositorService,MangoService}.qml`,
Noctalia `~/Downloads/github/quickshell/noctalia-shell/Services/{CompositorService,WorkspaceService}.qml`, ii
`~/.config/quickshell/ii/services/HyprlandData.qml` (the events and `hyprctl -j` shapes they parse).
(`…/scratchpad` = `/tmp/claude-1000/-home-maike-Projects-kurashi-shell/dbcea378-a7d4-4c51-ac59-ac9689ce0b5f/scratchpad`.)

**Read first:** `CLAUDE.md`; ARCHITECTURE §7; `crates/kurashi-compositor/src/{lib,types,niri,fake,doc}.rs` (the trait,
domain events, `Capabilities`, how niri is translated and reconnects); `crates/kurashid/src/{main,workspaces}.rs` (how
the daemon picks and drives the adapter; the generic `Compositor` bound); `crates/kurashid/src/doctor.rs`.

**Owned paths:** new `crates/kurashi-compositor/src/{hyprland,sway,any}.rs` (+ `lib.rs` exports), the adapter choice
in `crates/kurashid/src/main.rs` (and `doctor.rs` facts), `crates/kurashid/src/workspaces.rs` only where a capability
gates something, `docs/ARCHITECTURE.md` §7 (append), `docs/DECISIONS.md` is the lead's — propose a K-entry text in your
report. Tests under the compositor crate; a sandbox script `frontend/test-sway-adapter.sh`. Contract rows ≥ 170.

**Do:**
1. **Sway** (i3-IPC binary protocol on `$SWAYSOCK`; `swayipc-async` if it fits the tokio version, else a small
   hand-written framing): outputs, workspaces (per output, `num`/`name`, focused, urgent), windows (tree walk:
   `app_id` or X11 `window_properties.class`, workspace, focused), keyboard layouts (`get_inputs` xkb), events
   (`workspace`, `window`, `output`, `input`), actions (focus workspace/window, close, layout switch, screenshot via
   `grim`/`slurp` when the compositor has none of its own — report as capability), power-off monitors (`output * power off`).
2. **Hyprland** (`.socket.sock` request `j/…` JSON, `.socket2.sock` line events): global workspaces shown per monitor
   (`per_output_workspaces: false` mapped as "shown on output X"), addresses as window ids, `dispatch` actions,
   `dpms off`, keyboard layouts (`devices` → main keyboard `active_keymap`, `switchxkblayout`).
3. **Choice** at startup: `KURASHI_COMPOSITOR` override, else `NIRI_SOCKET` → niri, `HYPRLAND_INSTANCE_SIGNATURE` →
   hyprland, `SWAYSOCK` → sway, else none (the daemon still runs; documents say unavailable). An `AnyCompositor` enum
   implements the trait by delegation (no dyn: the trait is not object-safe). `kurashi doctor` names the adapter and
   its capabilities.
4. Capabilities honest per adapter; a frontend feature a compositor lacks says so (reason) instead of failing.

**Acceptance:** compositor crate tests with fake Sway and Hyprland sockets (snapshot, events → domain events, actions →
wire requests, reconnect); clippy; `frontend/test-sway-adapter.sh`: real kurashid **in the headless sway sandbox with
the sway adapter** (no fake niri) — the bar shows sway's workspaces, `kurashi act workspace.focus` switches, a
`swaymsg exec foot`-like client window appears in `svc.workspaces.windows`; shots. Report (terse) with a proposed
K-entry.
