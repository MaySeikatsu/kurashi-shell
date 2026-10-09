# Handover

Updated at the **end of every session** (K14). Newest entry on top; keep the last 5 entries.

## Pickup prompt (paste into a fresh Claude Code session started in `~/Projects/kurashi-shell`)
> Read `CLAUDE.md`, then the latest entry of `docs/HANDOVER.md`, and continue with its "Next
> steps" in order. Use subagents as described there (parallel, isolated git worktrees, disjoint
> ownership, the task cards in `tools/bakeoff/`), keep the lead role yourself (review, measure,
> merge, decide). Follow the feature-branch workflow, keep `docs/PROGRESS.md` current, and write
> a new handover entry before ending the session.

---

## 2026-10-09 — session 2: M0 decided, M1 complete, M2/M4/M5/M6/M7 foundations (parallel waves)
**State:** everything is on `main` (green: `just check`, ~180 tests). Work happened in waves of ≤5
Sonnet/Opus subagents with task cards in `docs/tasks/` (README = common rules), each in its own
worktree, builds serialised through one shared `CARGO_TARGET_DIR=~/.cache/kurashi-agents-target`.

**Decided / merged this session**
- **K3 = Quickshell/QML** (bake-off matrix in `BAKEOFF.md`, quiet re-bench in `probes/*/bench-lead.json`);
  K16 PSS budget revised to ≤150 MiB @1 output (+≤6/output); K17 protocol v1 **frozen**; K18 profile
  loads clear section pins.
- Daemon (`kurashid`): hub (revisions, merge-patch diffs, refcounted providers), action registry,
  intent coalescing, config store (`config` + `schema.settings` docs, cfg.get/explain, apply +
  dry-run preview, undo/redo, profile.* actions, file watcher, a11y couplings → `forced:accessibility`),
  `theme` doc from `kurashi-theme`, `i18n` doc, `svc.workspaces` (niri adapter), D-Bus services
  (`svc.media/power/session/network/brightness`, media feeds the island), island arbiter
  (`runtime.island.main`, island.next/prev/pin/expand), `runtime.ui`, launcher queries + launch,
  notification server (non-stealing name claim), mods registry (`mods` doc, mod.enable/disable).
- Crates: schema(+derive), config, theme, compositor, services, island, notify, launcher, mods, auth.
- CLI: `kurashi get/set/why/reset/undo/redo/profile` (exit codes 0/1/2/3), smoke-tested end to end.
- Frontend skeleton (`frontend/`, still on the mock) + Settings app (`settings/`, schema-generated pages,
  provenance chips, inert reasons, profiles; `settings/test.sh`). i18n en+ja for frontend, settings,
  config, schema (generated en catalog with staleness test), lock.
- Nix: package ships i18n/palettes/frontend/settings/mods; HM module runs kurashid + frontend as
  user services (`just nix-eval-test`, impure); `nix build .#kurashi` verified mid-session.

**Agent efficiency (bake-off, Sonnet, same card):** quickshell 103k tok/42 tools/7 min · gtk4 173k/69/30 ·
iced 190k/79/30 · slint 191k/81/32 · gpui 176k/84/33.

### Next steps (in order)
1. Merge the agents still running at handover time (see "half-done").
2. Switch `frontend/` from the mock to the real daemon: subscribe `i18n` (fill `I18n.strings`),
   `config`, `svc.audio` (once wired), `runtime.island.main` reason `manual`; keep the mock working.
3. Wire `kurashi-audio` (svc.audio + `audio.volume` intent coalesced) and `kurashi-auth`
   (`runtime.lock`, intent `lock.submit` — never log it; action `session.lock`) into kurashid; add
   `linux-pam` + `rustPlatform.bindgenHook` to `nix/package.nix` and enable `kurashi-auth/pam` (CONTRACT #4a).
4. Frontend UI cards (disjoint files under `frontend/surfaces/`): notification toasts + center,
   launcher, OSD (volume/brightness via island transient), lock screen (`WlSessionLock`), session menu.
5. Capability forcing for blur (`forced:capability`) once we can tell whether the compositor offers
   ext-background-effect (ask the frontend to report the global, or probe it in the daemon).
6. `kurashi doctor`, then M7 budgets via the bench gate (`tools/bench/budget.py`) on the real stack.

### Open decisions / risks
- Stage surface memory (K16) — card M3-stage measures and fixes; budget may need a decision.
- The notification server runs for the daemon's lifetime (deliberate Ma exception, documented in
  `crates/kurashid/src/wiring.rs`); it never steals the name from the user's running shell.
- Mod contributions (faces, services, settings pages) are not registered yet — only the catalog.
- `kurashi-launcher` watcher not started (refcount per launcher subscriber is TODO).
- Shared target dir: `debug/<bin>` is overwritten by other worktrees — copy right after building.

### Gotchas learned this session
- Subagents' tools refuse to write report files → reports come back as text; the lead saves them.
- Two agents briefly drew on the live session because `sandbox.sh start` failed silently outside
  `nix develop` — fixed (fails closed). Leaked sandbox dbus-daemons may remain (`pgrep -af kurashi-sb-`).
- Exporting `XDG_CONFIG_HOME` for a smoke test in the same shell breaks `git commit` (identity lives
  in ~/.config/git).
- zsh: `"$B:path"` triggers the `:p` modifier — write `"${B}:path"`.

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
