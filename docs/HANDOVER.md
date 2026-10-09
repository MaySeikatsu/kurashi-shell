# Handover

Updated at the **end of every session** (K14). Newest entry on top; keep the last 5 entries.

## Pickup prompt (paste into a fresh Claude Code session started in `~/Projects/kurashi-shell`)
> Read `CLAUDE.md`, then the latest entry of `docs/HANDOVER.md`, and continue with its "Next
> steps" in order. Use subagents as described there (parallel, isolated git worktrees, disjoint
> ownership, the task cards in `tools/bakeoff/`), keep the lead role yourself (review, measure,
> merge, decide). Follow the feature-branch workflow, keep `docs/PROGRESS.md` current, and write
> a new handover entry before ending the session.

---

## 2026-10-09 — session 2: bake-off probes built (cut short by usage limit)
**State:** branch `feat/m0-bakeoff` (NOT merged to main). All 5 probes merged into it (`probes/*`,
REPORT.md for gtk4/iced/slint/gpui written by the lead from agent hand-backs — subagent tools refuse
report files). Bench harness fixes committed: `sandbox.sh` now fails closed (61d76fa).

**Agent efficiency (Sonnet, same card):** quickshell 103k tok / 42 tools / 7.2 min / 4 fix iters ·
gtk4 173k / 69 / 29.9 min / 4 (+2 pivots) · iced 190k / 79 / 29.9 min / 3 (+1) ·
slint 191k / 81 / 32.0 min / 1 · gpui 176k / 84 / 32.9 min / 2.

**Agent-run numbers (noisy, contended):** PSS 1-out: slint 21.6 · gtk4 59 · iced 94.5 · gpui 110 ·
quickshell 164 MiB. Idle commits/s: 0 everywhere except gpui 61/surface (gpui_linux re-arms frame
callback forever → fails Ma). Wakeups/s: quickshell 0, slint 0, gtk4 1.4 (gl renderer; Vulkan ~110),
iced 118 (futex, undiagnosed), gpui 178. Popup latency ~2 ms all, gpui 26 ms.
Gates: blur bound in quickshell/gtk4/slint (raw), ✘ iced (not done), ✘ gpui (KDE only).
xdg_popup on layer surface: quickshell, iced; others separate layer surface. Real GPU shader:
quickshell, iced, gtk4 (GLArea); slint/gpui CPU only. IME: ✘ slint (custom platform).
Session lock API: quickshell, iced, slint(SCTK); ✘ gtk4/gpui (raw only). Hot reload: only quickshell.
Lead's provisional read: **QML/Quickshell stays default** (passes all gates, only hot-reload option,
4× cheaper agent workload); best native contender = slint (memory) but fails IME + shader gates.

### Next steps (in order)
1. Finish M0.7: quiet re-bench was started via `scratchpad/bench-all.sh` (runs from worktree binaries
   under `.claude/worktrees/agent-*`; results in `tools/bench/results/<name>.json`). If missing, rerun:
   `nix develop -c python3 tools/bench/measure.py --name <n> --warmup 10 --idle 30 -- <cmd>` with cmds
   from `probes/*/bench.json` (iced/slint need their devshell LD_LIBRARY_PATH via `env`).
2. Fill `docs/BAKEOFF.md` matrix + `docs/BENCH.md`, call advisor, decide **K3** in DECISIONS (note:
   user wants it re-evaluable later; target feel = quick, smooth, polished, snappy). Merge
   `feat/m0-bakeoff` → main (`--no-ff`), then remove the 5 worktrees + branches.
3. User request: after evaluation, start M1+ with ≤5 parallel subagents on disjoint subsystems,
   staggering compiles (e.g. `flock /tmp/kurashi-build.lock cargo …`) — M1 contracts first.

### Open issues / risks
- **Two safety incidents:** slint + gpui agents ran their probe briefly on the user's LIVE session
  (sandbox.sh silently failed outside nix develop). They killed their own PIDs; socket removed. Fixed.
- 12 leaked sandbox dbus-daemons (addresses `/tmp/kurashi-sb-{slint,iced}/bus`) — lead's kill was
  denied by the permission classifier; user should kill them (`pgrep -af kurashi-sb-.*/bus`).
- Bench commit counting needs libwayland (WAYLAND_DEBUG) — Rust-only wayland backends read 0.

---

## 2026-10-09 — session 1: plan, charter, M0 foundations
**Merged on `main`:** charter + docs (`CLAUDE.md`, `docs/*`), M0.1–M0.5:
- Nix flake: `packages.kurashi` (kurashid, kurashi, kurashi-mock), devShell (Rust, just, quickshell,
  sway, grim, strace, perf, hyperfine…), `nixosModules.default`, `homeManagerModules.default`
  (settings → `managed.toml` provenance layer `nix`, K15). Verified: `nix build .#kurashi`,
  `nix develop -c just check` (fmt + clippy -D warnings + tests) green.
- Crates: `kurashi-core` (Source/Provenanced/Rev), `kurashi-ipc` (protocol v1 draft types, NDJSON
  codec, merge-patch, golden fixtures in `fixtures/ipc/`), `kurashid` (handshake skeleton),
  `kurashi-mock` (probe subset: theme/clock/workspaces/audio/media/island/ui/mods docs, intents
  with origin echo, actions, `mock.*` control), `kurashi` CLI (act/sub/intent/mock/raw/ping).
- Bench harness `tools/bench/` (sandbox.sh + measure.py, 3 passes) — self-tested: a trivial
  Quickshell bar = **110 MiB PSS**, 0 idle CPU/commits/syscalls (docs/BENCH.md).
- Bake-off task card + per-framework hints: `tools/bakeoff/TASK-CARD.md`, `CANDIDATES.md`.

**Key decisions so far:** K1–K15 in `docs/DECISIONS.md` (daemon-first, provenance, one schema,
profiles, decor slots+recipe, Island arbitration, universal input slots, NDJSON, Nix-first,
GPL-3+, i18n en/ja, handovers, nix provenance layer). K3 (renderer) is 🟡 pending the bake-off.

### Next steps (in order)
1. **M0.6 — run the frontend bake-off with 5 parallel subagents.**
   - Branch for the lead: `feat/m0-bakeoff` (create from `main`).
   - Spawn **5 Sonnet subagents in one message**, each with `isolation: "worktree"`,
     `run_in_background: true`, `model: "sonnet"` — same model for all, so agent-efficiency
     numbers are comparable. Names: `quickshell`, `iced`, `slint`, `gpui`, `gtk4`.
   - Prompt per agent = "Read `tools/bakeoff/TASK-CARD.md` and the `<name>` section of
     `tools/bakeoff/CANDIDATES.md`; `<NAME>` = `<name>`. Build the probe under `probes/<name>/`
     only, self-verify, write `probes/<name>/REPORT.md` + `bench.json`, commit on your branch."
     Add: "Before building Rust, export `CARGO_BUILD_JOBS=3`" (5 parallel builds on 12 cores /
     31 GB RAM; GPUI/iced/Slint are heavy). If memory pressure shows, run 3 + 2 in waves.
   - Each worktree must build the mock itself (`cargo build --release -p kurashi-mock -p kurashi`)
     — `target/` is not shared between worktrees.
   - **Record agent efficiency** from each task notification's usage block (`subagent_tokens`,
     `tool_uses`, `duration_ms`) into `docs/BAKEOFF.md` — it is one of the scored metrics.
2. **M0.7 — measure & decide (lead).**
   - Merge each probe branch into `feat/m0-bakeoff` (probes are disjoint dirs → no conflicts).
   - Re-run every probe's bench yourself from the repo root for consistent conditions:
     `nix develop -c python3 tools/bench/measure.py --name <name> -- <run cmd from its README>`.
   - Verify capability claims by reading code (blur binding, popup type, runtime mod UI,
     shader), not just REPORT.md. Spot-check screenshots in `probes/*/shots/`.
   - Fill `docs/BAKEOFF.md` (matrix, weights runtime 35 / capability 30 with hard gates
     blur+popups+lock+IME / dev workload 25 / ecosystem 10) and `docs/BENCH.md`.
   - Decide **K3** in `docs/DECISIONS.md` (QML stays default unless a candidate passes all gates
     and wins overall). Note: IME and blur can't be exercised in headless sway; if a native
     candidate is close to winning, ask the user for a short live test on niri (their session —
     never start anything there without asking).
   - Merge `feat/m0-bakeoff` → `main`. Present the matrix + recommendation to the user.
3. **M1 — state core (lead/Opus, after K3):** branch `feat/m1-protocol`: protocol v1 complete
   (revisions, resync, transactions/undo, intents coalescing), `kurashi-schema` + `-derive`
   (`#[kurashi(...)]` → defaults, validation, SettingsMeta, example config, docs), resolution
   with provenance per output, sparse TOML + migrations, profiles (section-level partial load,
   diff, undo), Action registry, CLI `get/set/why/reset/undo/profile`, mock v1. Property tests.
   Freeze contracts (fixtures) at the end of M1 — only then fan out Sonnet agents (M2–M4) with
   task cards (see `CLAUDE.md` "Subagent task cards").

### Gotchas learned this session
- The Bash tool runs **zsh**: `$VAR` holding a command line is NOT word-split — use env vars
  (e.g. `KURASHI_SOCKET`) or arrays. The safety checker blocks `rm -rf` and `bash -c` scripts.
- Flakes only see git-tracked files: `git add` before `nix build`/`nix develop` on new files.
- Headless sway must use the **gles2** renderer (default in `sandbox.sh`) or clients fall back to
  software rendering and every memory/CPU number is wrong; screencopy also needs gles2.
- `ptrace_scope=1`: strace only works on children → `measure.py` launches the frontend itself.
- The user's live session currently runs **shellseikatsu** (`quickshell -p ./` in
  `~/Documents/projects/quickshell/shellseikatsu`) — never kill or restart it; it is the
  fallback until Kurashi M7 and the feature reference (all its features return as mods).

### Open decisions / risks
- K3 renderer (bake-off). GPUI/Slint may fail hard gates (shaders, popups on layer surfaces).
- Mod tier details (Luau host API) are v0.2 — don't design them in M1 beyond the manifest shape.
- The Island arbitration rules (K9) need concrete relevance signals per face in M5.

### Context links
- Approved plan (archive): `~/.claude/plans/i-think-this-shell-glimmering-otter.md`.
- Predecessors: `~/Documents/projects/quickshell/shellseikatsu` (Quickshell; features, lessons in
  its `docs/BUGS.md`, `agent_docs/APPLY.md`), `~/Projects/quickshell/WormShell` (design study,
  `docs/DECISIONS.md` D1–D93).
- Reference shells: `~/Documents/projects/github-forks/quickshell/` (noctalia-shell,
  DankMaterialShell with its Go backend in `core/`, caelestia, ii); noctalia v5 (C++/Luau) is the
  model for the mod system: https://docs.noctalia.dev/noctalia/plugins/development/
