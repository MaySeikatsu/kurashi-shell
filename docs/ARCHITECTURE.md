# Architecture

## 1. Process model (K2)
```
                 ┌──────────────────────────── kurashid (Rust, systemd user unit) ─────────────┐
 niri IPC ──────▶│ compositor adapter ─┐                                                       │
 D-Bus (zbus) ──▶│ services (refcounted): audio(PipeWire) net(NM) bt(BlueZ) power(UPower)     │
 PipeWire ──────▶│   mpris notifications(server) tray(SNI host) logind brightness             │
 fs/inotify ────▶│ config: schema → resolution(provenance) → stores(config|profile|runtime)   │
                 │ theme pipeline → token map        actions registry      island arbiter     │
                 │ mods (manifests, Luau VMs)        launcher scoring      undo / transactions│
                 └──────────────▲──────────────────────────────▲────────────────────────────────┘
                                │ IPC v1 (unix socket, NDJSON) │
                   ┌────────────┴──────────┐        ┌──────────┴──────────┐     ┌──────────────┐
                   │ frontend (shell view) │        │ kurashi-settings     │     │ kurashi (CLI)│
                   │ bars, stage, lock,    │        │ (separate process,   │     │ get/set/why, │
                   │ island, background    │        │  on demand)          │     │ actions, keys│
                   └───────────────────────┘        └─────────────────────┘     └──────────────┘
```
- **kurashid** is the only process that touches the system (D-Bus, PipeWire, compositor socket,
  files). Crash → systemd restarts it; frontends show a "reconnecting" veil after 2 s and resync.
- **Frontend** renders state documents and sends intents. It owns *presentation state only*
  (hover, drag position, text buffers, animation progress). Renderer chosen by the M0 bake-off
  (K3); the contract is renderer-agnostic.
- **kurashi-settings** is a separate on-demand process (zero cost when closed).
- **kurashi** CLI: `get/set/explain(why)/reset`, `action <id>`, `profile save|load|diff|list`,
  `doctor`; compositor keybinds call `kurashi action …` via `spawn`.

## 2. Crates
| Crate | Responsibility | Depends on |
|---|---|---|
| `kurashi-core` | ids, errors, shared value types (`Value`, `Source`, `Rev`) | — |
| `kurashi-ipc` | protocol types, NDJSON codec, golden fixtures | core |
| `kurashi-schema` (+`-derive`) | `#[kurashi(...)]` derive, key registry, validation, generators (settings meta, example TOML, docs) | core |
| `kurashi-config` | layered resolution with provenance, sparse TOML (`toml_edit`), migrations, profiles, transactions/undo (schema-agnostic via `SchemaView`) | core |
| `kurashi-theme` | palette pipeline, roles, component tokens, WCAG, fonts (`ThemeInput` → `TokenMap`; exporters later) | — |
| `kurashi-services` | system services behind a refcounted `Service` trait | core |
| `kurashi-compositor` | `Compositor` trait + capabilities + niri adapter | core |
| `kurashi-mods` | manifests, discovery, enable/disable registry, `mods` catalog (Luau host API v0.2) | — |
| `kurashi-island` | Island arbitration (K9): pure, time as input, one deadline | — |
| `kurashi-notify` | `org.freedesktop.Notifications` server, history, `svc.notifications` | services (`DocSink`) |
| `kurashi-launcher` | desktop-entry index (inotify), fuzzy + frecency ranking, launch | — |
| `kurashi-audio` | `svc.audio` from PipeWire/Pulse (wave 3) | services |
| `kurashi-auth` | PAM + lock state machine, `runtime.lock` (wave 4) | services |
| `kurashid` | daemon: hub (docs, revs, refcounted providers), IPC server, actions, intents, config store, theme, providers, wiring | all |
| `kurashi` | CLI: get/set/why/reset/undo/redo/profile, act/sub/intent/raw/mock | ipc |
| `kurashi-mock` | fake daemon (scripted/recorded state) for frontend work and the bake-off | ipc |

## 3. State model
Three stores, never mixed, each with a monotonic **revision**:
- `config` — persisted user intent (sparse TOML `~/.config/kurashi/config.toml`).
- `profiles` — persisted snapshots (`~/.config/kurashi/profiles/*.toml` + bundled).
- `runtime` — ephemeral state (DND, volume, open panels, island current face).

**Resolution** (per key, optionally per output):
`schema default → nix (managed.toml, K15) → theme:<recipe> → profile:<name> → user → forced:<reason>`.
The result carries `{value, source, forced_by?, reason?}`. Removing a user key recomputes the
resolution (it never "sticks"). Couplings (`requires`, `capability`, `overridden_by`) are schema
data, evaluated in the daemon — never `&&` chains in renderers.

**Services and absent buses** (I17, I200): a stock service follows its bus name itself (`NameOwnerChanged`), so a
missing BlueZ/UPower never fails it; a service whose bus *socket* is absent waits for the file (inotify on the deepest
existing directory, safety cap 30 min, no wakeups), and a socket nobody answers on backs off to 10 min.

**Transactions**: every mutation is `apply(batch)`; validated atomically; recorded on a global
undo stack (bounded); profile loads are a single transaction with a diff preview.

## 4. Surfaces (frontend, any renderer)
Per output, at most: bar(s) (one per configured bar, any edge) · **stage** (one overlay surface
holding popups, OSD, toasts, island expansions — content-sized, on the focused output; kept mapped
but transparent, input-less and at 0 frames while hidden, because remapping leaked memory, K19) ·
background (wallpaper-layer decor, optional) · lock (session lock, only while locked).
Budget: ≤ 4 mapped at idle. Corner ownership between bars is computed in the daemon's layout
step and delivered as geometry (renderers never re-derive it).

Every reveal starts on the **first presented frame** of its surface (no dropped intro frames).
Keyboard focus: surfaces declare interactivity (`none|on_demand|exclusive`); Escape is owned by
the topmost interactive layer; grabs are released on close.

## 5. Island (島) arbitration
Daemon-side, per island instance. Inputs: face registry (core + mod faces), face signals
(priority, conditions, TTL triggers), user pin state, config (faces, order, default, which
triggers may interrupt, TTLs). Output: `runtime.island.<id> = {face, reason, until?}`.
Precedence: **pinned > transient (TTL) > live relevance > default**. Deterministic and unit
tested; the frontend only animates between faces.

## 6. Input bindings
Every placeable component declares slots `left|right|middle|hover|scroll_up|scroll_down|
shift_scroll_up|shift_scroll_down` with default **Action** ids in its schema. Users override per
component type or per instance (`[bars.<id>.widgets.<n>.input]`). Bindings resolve with
provenance like any other value; the frontend dispatches `invoke_action`.

## 7. Compositor adapter
`trait Compositor { snapshot(); events() -> Stream; actions(); capabilities() }` with optional
capability-gated features (scroll position, overview, window previews, blur hints). Emits
`Resync` on reconnect (subscribers discard state and await a snapshot). niri first; Hyprland,
MangoWM, Sway later — adapters only, no core changes.

**Adapters (W26).** `kurashi_compositor::any` picks one at startup: `KURASHI_COMPOSITOR`
(`niri|hyprland|sway|none|auto`) overrides, else `NIRI_SOCKET` → niri, `HYPRLAND_INSTANCE_SIGNATURE` →
Hyprland, `SWAYSOCK` → Sway, else none (the daemon runs; `svc.workspaces` stays empty, compositor actions are
refused as unavailable). `AnyCompositor` implements the trait by delegation (an enum, no `dyn`); a `Target`
(kind + socket path) is the clonable factory and also serves the one-shot actions (screens off, screenshots,
layouts) and the recorder's focused output. `kurashi doctor`'s compositor row names the adapter and what it
offers and lacks.

| | niri | Sway (i3-IPC, hand-framed) | Hyprland (`.socket.sock` / `.socket2.sock`) |
|---|---|---|---|
| state | event stream, incremental | events → re-read only the touched domain (workspaces+tree, tree, outputs, inputs); titles in place | events → re-read monitors+workspaces / clients / devices; focus, urgency, titles in place |
| workspaces | per output | per output; `idx` = `num` | global, shown on their monitor; `idx` = number; named ids 2³²+\|id\|; special ones hidden |
| window id | niri id | container id | client address |
| layouts | `KeyboardLayoutsChanged` | `get_inputs` (first keyboard naming its layouts) | `devices` main keyboard (codes → XKB names) |
| screens off | `power-off-monitors` (niri wakes) | `output * power off`, then `on` at the next input | `dpms off`, then `on` at the next input |
| screenshots | niri's own | `grim`/`slurp` (+`wl-copy`), if installed | same |
| overview | yes | no | no |

"At the next input" is kurashid's wake guard: an `ext-idle-notify` notification of 1 s proves the protocol works
and the seat is idle, then the screens go off; its `resumed` turns them on (swayidle's `resume`, hypridle's
`on-resume`). Without the protocol the screens stay on. A burst of events is read whole before anything is
re-read, so a workspace switch costs one round of requests; nothing polls.

## 8. Mods
See `MODS.md`. Native-tier (first-party, renderer components + daemon logic) in v0.2; portable
tier (declarative UI vocabulary + Luau) in v0.3. Enable/disable is live.

## 9. Files & paths
| Path | Content |
|---|---|
| `~/.config/kurashi/config.toml` | sparse user overrides (versioned) |
| `~/.config/kurashi/profiles/` | user profiles |
| `~/.local/state/kurashi/` | runtime persistence (undo journal, island pins, last profile) |
| `$XDG_RUNTIME_DIR/kurashi/ipc.sock` | IPC socket (0600) |
| `~/.local/share/kurashi/mods/` | user mods |
