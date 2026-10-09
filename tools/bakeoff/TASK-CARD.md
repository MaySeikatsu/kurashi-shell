# Bake-off task card — frontend probe `<NAME>` (M0.6)

You build ONE frontend probe with framework `<NAME>` so it can be compared against four other
frameworks building the exact same probe. Correct, honest measurements matter more than polish.
Read this card fully, then `docs/PROTOCOL.md` (§1–§4 and §8) and `crates/kurashi-ipc/src/lib.rs`
(message shapes). Do not read other docs unless stuck.

## Ownership (hard rule)
- You may create/edit files **only under `archive/bakeoff-probes/<NAME>/`** (your own `flake.nix`, sources,
  `README.md`, `REPORT.md`, screenshots in `archive/bakeoff-probes/<NAME>/shots/`).
- Everything else is read-only. Missing something outside? Write it in `REPORT.md` → "Requests".
- Never touch the user's session: run only inside the sandbox (below). Kill only PIDs you started
  (`tools/bench/sandbox.sh stop <name>` does this safely). Never `pkill -f`.
- Commit on your worktree branch (`probe(<NAME>): …`), no AI attribution lines.

## Environment
- `nix develop` (repo root) gives Rust, quickshell, sway, grim, strace, python, just.
- Your probe gets its own `archive/bakeoff-probes/<NAME>/flake.nix` (inputs: `nixpkgs` =
  `github:NixOS/nixpkgs/nixos-unstable`). Its devShell must provide every system library your
  framework needs (wayland, libxkbcommon, vulkan-loader, libGL, fontconfig, gtk4, …) and its
  package/app must produce ONE run command. Document build + run in `archive/bakeoff-probes/<NAME>/README.md`.
- Data source: `kurashi-mock` (fake daemon). Build once at the repo root:
  `cargo build --release -p kurashi-mock -p kurashi`.
- Sandbox (invisible headless sway, GPU renderer):
  ```sh
  eval "$(tools/bench/sandbox.sh start <NAME>)"      # exports XDG_RUNTIME_DIR, WAYLAND_DISPLAY, KURASHI_SOCKET
  mkdir -p "$(dirname "$KURASHI_SOCKET")"; target/release/kurashi-mock &   # in the same env
  <your run command> &
  grim archive/bakeoff-probes/<NAME>/shots/bar.png                     # screenshot, then Read it to check
  target/release/kurashi act probe.popup.toggle        # open/close popup
  target/release/kurashi mock face media               # island → media face
  target/release/kurashi act island.next               # what scroll on the island does
  tools/bench/sandbox.sh output-add <NAME>             # hotplug a 2nd output
  tools/bench/sandbox.sh stop <NAME>                   # ALWAYS clean up
  ```
  The sandbox has no input devices: test interactions via the CLI actions above (they are the
  same actions your UI sends). Blur (ext-background-effect-v1) and IME are NOT available in
  headless sway — implement them if the framework allows and report honestly.

## The probe (identical for all frameworks)
Connect to `$KURASHI_SOCKET` (NDJSON, `hello` → `welcome`), subscribe to: `theme`, `svc.clock`,
`svc.workspaces`, `svc.audio`, `svc.media`, `runtime.island.main`, `runtime.ui`, `mods.probe`.
Apply `patch` messages as JSON merge-patches; on a revision gap send `resync`. On disconnect,
retry with backoff (250 ms → 4 s) and keep showing the last state.

1. **Bar on every output** — top edge, height `bar.height`, exclusive zone, background
   `color.surface` with alpha `color.surface_alpha`. New outputs (hotplug) get a bar; removed ones
   lose it. Layout: left = workspaces of that output (`svc.workspaces.outputs[<output name>]`,
   fallback `"*"`; focused = accent pill, occupied = dot); center = **Island**; right = volume
   slider, mod widget, clock `HH:MM`.
2. **Volume slider** — optimistic: moves locally while dragging, sends
   `{"t":"intent","key":"audio.volume","value":v,"origin":"<unique>","coalesce":true}` at most
   once per frame, ignores patches carrying its own `origin` while dragging, settles on the
   daemon value after release.
3. **Island** — shows the face named in `runtime.island.main.face`: `clock` = `HH:MM · Fri`,
   `media` = `title — artist` (from `svc.media`). Face change = **morph**: width animates to the
   new content width (`motion.emphasized_ms`, cubic-bezier `motion.easing.enter`) and content
   crossfades. Scroll up/down → `act island.prev` / `island.next`; left click →
   `act probe.popup.toggle`; right click → `act island.pin`. Must be interruptible.
4. **Popup** — visible while `runtime.ui.popup` is true: 360×220, anchored under the Island
   (popup on the layer surface, or a separate layer surface positioned under it — note which).
   **Reveal starts on the first presented frame** of the popup surface (opacity 0→1, scale
   0.96→1, `motion.standard_ms`); hide reverses then unmaps. Contents: a text field (IME-capable
   if the framework supports text-input-v3), and a 200×80 **custom shader** area (animated
   gradient/noise; it animates ONLY while the popup is visible). Escape → `act probe.popup.toggle`.
5. **Blur** — request ext-background-effect-v1 blur for bar and popup if the framework lets you
   bind it (raw protocol access counts). Report how (or why not).
6. **Theme** — every colour, size, radius, font and duration comes from `theme.tokens`
   (fallbacks only if a token is missing). Font: `font.family`, Japanese text uses
   `font.family_jp`.
7. **Runtime mod widget** — render `mods.probe.widgets[*]` generically from its `ui` tree at
   runtime (node types `row`, `column`, `text` with `bind` into `state`, `icon` by name — a
   glyph or text fallback is fine). It must work for trees your code has never seen (no
   recompilation). If the framework can only do this through an interpreter (e.g. Slint
   interpreter, QML Loader) use it and say so.
8. **Idle discipline (Ma)** — with nothing changing, the probe commits **0 frames** and wakes up
   ~never: no timers, no continuous animations, the clock redraws only on `svc.clock` patches,
   the shader only runs while the popup is visible.

## Self-verification (required before reporting)
1. Screenshots (`grim`) of: bar idle, island media face, popup open, 2 outputs — check them.
2. Run the bench at the repo root (it starts its own sandboxes and the mock):
   `python3 tools/bench/measure.py --name <NAME> --warmup 10 --idle 30 -- <your run command>`
   Acceptance: `pass_a.error` absent; `pass_b.popup_latency_ms_median` and
   `pass_b.morph_commits` not null/zero (proves popup + morph work); `idle_commits_per_s` ≈ 0.
   Copy `tools/bench/results/<NAME>.json` to `archive/bakeoff-probes/<NAME>/bench.json`.

## REPORT.md (required, concise)
```
# Probe <NAME>
Versions: <framework + key crates/libs with exact versions>
Run: <command>
## Capability checklist (✔ / ✘ / partial — one line of evidence each)
layer-shell any edge + exclusive zone | multi-output + hotplug | popup on layer surface |
first-frame-gated reveal | session lock (API exists? don't build) | screencopy (API exists?) |
blur ext-background-effect | custom shader | IME text-input-v3 | fractional scale |
runtime-loaded mod UI | theme tokens at runtime
## Developer workload
clean build (s) | incremental rebuild after changing one UI string (s) |
hot reload / live preview (✔/✘ + latency) | probe LOC (excluding generated) | binary size |
dependency count (`cargo tree --prefix none | sort -u | wc -l`, or n/a) |
compile-fix iterations you needed (honest count) | docs quality 1–5 + note
## Bench summary
(key numbers from bench.json)
## Pain points / surprises
## Requests (anything you needed outside archive/bakeoff-probes/<NAME>/)
```
Time-box: if a requirement is impossible in this framework, stop trying after a reasonable effort,
mark it ✘ with the reason, and move on. Token thrift: read only what you need; keep the report terse.
