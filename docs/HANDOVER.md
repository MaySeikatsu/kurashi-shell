# Handover

Updated at the **end of every session** (K14). Newest entry on top; keep the last 5 entries.

## Pickup prompt (paste into a fresh Claude Code session started in `~/Projects/kurashi-shell`)
> Read `CLAUDE.md`, then the latest entry of `docs/HANDOVER.md`, and continue with its "Next
> steps" in order. Use subagents as described there (parallel, isolated git worktrees, disjoint
> ownership, the task cards in `docs/tasks/`), keep the lead role yourself (review, measure,
> merge, decide). Follow the feature-branch workflow, keep `docs/PROGRESS.md` current, and write
> a new handover entry before ending the session.
>
> **On a different machine than the one with the GTX 1060** (or if you are unsure): you have no
> memory of earlier sessions — everything you need is in this repo. If machine B has no baseline in
> `docs/BENCH.md` yet, do `docs/RUNBOOK-MACHINE-B.md` first (benchmarks only, on a quiet machine;
> K3 = Quickshell stays fixed; never modify `archive/bakeoff-probes/`), then the next steps below.

---

## 2026-10-09 — session 3 close: handover for any machine (no prior context assumed)
**Read this whole entry; it does not assume you remember anything.** The repo is the only memory:
`CLAUDE.md` (rules), `docs/VISION.md` (why), `docs/ARCHITECTURE.md` (what talks to what),
`docs/PROTOCOL.md` (IPC v1, frozen + additive), `docs/DECISIONS.md` (K1–K22), `docs/PROGRESS.md`
(every step), `docs/tasks/` (agent cards + README rules), `docs/reviews/` (review findings).

**What exists (main, green):** Rust daemon `kurashid` owns all state and serves NDJSON over a unix
socket; the Quickshell frontend (`frontend/`) and the settings app (`settings/`) are thin views;
`kurashi` CLI; `kurashi-mock` fake daemon. Features: bar (per-output, any edge), Island with faces
(clock, media, notifications, volume/brightness OSD), notification server + toasts + centre, launcher,
session menu, lock screen (PAM; refuses without the `kurashi` PAM service), settings app with
provenance, search, profiles, Mods page and per-mod settings pages, theming (palettes, a11y
couplings), input bindings, tray + Bluetooth services (no UI yet), `nix run` apps, NixOS +
Home-Manager modules. Run/test instructions: `README.md` "Running".

**How to verify anything** (inside `nix develop`):
- `just check` — fmt + clippy -D warnings + all tests. For merges use a private target dir:
  `unset CARGO_TARGET_DIR; CARGO_INCREMENTAL=0 just check`.
- `frontend/test-real.sh`, `settings/test.sh`, `frontend/test-bindings.sh` — headless sandbox smoke
  tests with screenshots (Read them). `just golden` — visual regression (per-machine refs via
  `KURASHI_GOLDEN_REF`). `just bench-gate` — budgets on the real stack (quiet machine only).
- Never run the shell on the user's display; never kill processes you didn't start.

**How the work is organised (if you use subagents):** you are the lead (review, verify, merge,
decide); agents get one card each in `docs/tasks/` (goal, owned paths, frozen contracts, one
acceptance test) and work in isolated git worktrees. This session used Haiku agents at max effort,
up to ~10 in parallel — that worked well when each card owned disjoint files; the user may set a
different limit. Agents share `CARGO_TARGET_DIR=$HOME/.cache/kurashi-agents-target` (builds take
turns via cargo's lock). Lead checklist per returned branch: (1) diff only touches the card's owned
paths, (2) merge with `--no-ff --no-commit`, (3) full gate with a private target dir, (4) for UI:
run the sandbox test and Read screenshots, (5) renumber `docs/CONTRACT-CHANGE.md` rows if two
agents appended the same number, (6) commit, remove the worktree, update `docs/PROGRESS.md`.

**Next steps (ordered, each a card-sized task):**
1. Machine B baseline if not done (`docs/RUNBOOK-MACHINE-B.md`).
2. Settings polish from `docs/reviews/2026-10-09-ux-review.md`: #3 (settings focus/keys, focus ring),
   #4/#5 (use `Theme.fgOnAccent`, titles in `Theme.fg`), #7, #8, #9, #11 (settings hit targets ≥ 32 px),
   #13 (daemon error codes → catalog keys), #17, #18, #23. Owns `settings/` + `i18n/*/settings.toml`.
3. Island hit target is 26 px (< 32, review #11): enlarge the bar's island hit area without changing
   visuals (`frontend/surfaces/Bar.qml` + `components/Island.qml`); decide with the golden refs.
4. Tray + Bluetooth UI: a bar tray widget and a Stage panel, against the shapes in
   `fixtures/ipc/server/snap_{tray,bluetooth}.json` and the actions in `docs/PROTOCOL.md` §7.
   Mind the per-output PSS budget (+6.0 of +6 used on machine A): measure with `just bench-gate`.
5. logind session for a `systemd --user` daemon: resolve the user's graphical session explicitly
   (session hints may report `available:false` today) — `crates/kurashi-services/src/session.rs`.
6. Cleanups: fold `RefcountedService` into `ServiceProvider` (CONTRACT-CHANGE row 16); per-mod profile
   sections (K22 note: all mod keys share the `mods` section); D-Bus connection-level reconnect
   (services stay unavailable after a bus loss); mock `available` fields.
7. M6 first native mods (media + lyrics, wallpaper, sysmon, weather) per `docs/MODS.md`; then M7
   hardening towards v0.1 (`docs/ROADMAP.md`), including a live niri test **with the user present**.

**Known numbers (machine A, quiet, 2026-10-09):** real stack 104.3 MiB @1 output, +6.0/output,
popup 2.6 ms, 0.03 idle fps, 0 % CPU, +0.63 MiB over 20 panel cycles — 0 violations. Archived probes:
`docs/BAKEOFF.md` "Quiet re-measure".

**Gotchas learned (keep):** shared target dirs hand worktrees each other's crates/embedded files —
gate merges with a private target dir; always `timeout` + `set -o pipefail`; never name a QML
property `on<Capital>…`; frontend agents can use prebuilt daemon binaries (`KURASHI_BIN_DIR`) to
avoid compiling; prune `~/.cache/kurashi-agents-target/debug/incremental` between waves (disk).

**Remote:** `origin = git@github.com:MaySeikatsu/kurashi-shell.git` (configured 2026-10-09; first push
by the user). Local-only files stay untracked (`.claude/settings.local.json`, worktrees, results).

---

## 2026-10-09 — session 3: wave 7 with Haiku agents (M3–M7 depth, review-driven fixes)
**Update 13:30:** U-components and U-surfaces merged (ed847b0, 0470378), golden refs re-recorded; quiet
benchmarks done (probes re-measured unchanged + real-stack gate: 104.3 MiB, +6.0/output at the limit,
0 violations). No agents running. Next steps 1 → settings polish card; 2 → machine B baseline only.

**State:** `main` green at handover (`just check` in a **private** target dir: fmt, clippy -D warnings,
all workspace tests, **0 ignored**; `just golden` 5/5; `nix flake check --no-build` ✔). Lead = Opus,
agents = Haiku at max effort, up to 10 in parallel, task cards in `docs/tasks/` (README = rules).
**Two agents may still be running or have finished unmerged** (see "Half-done"). The user paused new
work until 12:50.

**Merged this session (all with tests; details in PROGRESS "Wave 7")**
- Memory branch M3.2: `frontend/launch.sh` pins the NVIDIA EGL vendor only with exactly one render
  node; HM frontend service runs it (`KURASHI_QS`); BENCH 20-cycle growth budget. Bench re-run pending.
- Launcher watcher `Drop` hang fixed (a test hung 4.5 h; real daemon bug); bake-off probes moved to
  `archive/bakeoff-probes/` (unused, K3 re-run baseline).
- Features: `session.menu` + session menu UI (2-press destructive confirm); brightness/volume key
  actions with island OSD faces; `session.lock` refuses without PAM service `kurashi`; input via
  `bindings`/`input.dispatch`; settings search + Mods page + mod descriptions; **mod settings as config
  keys** `mods.<id>.<key>` with pages (K22); tray (SNI) + BlueZ crates **wired** (`svc.tray`,
  `svc.bluetooth`, refcounted, actions never auto-start); `nix run .#{default,settings,mock,sandbox}`
  + README "Running"; mock parity (panels, bindings, brightness, session, notifications, launcher,
  instance, `--fixed-time`); golden screenshots `just golden` (pixman, masks for clock/caret);
  weekday localised (`i18n/*/clock.toml`); `available` flags on svc.session/media/power.
- Honesty: test over all 39 keys (M5.17) → **K21**: daemon reports `reason` + `inert_by` for
  requires-inert keys and `settings.pending.restart`; settings app stopped evaluating couplings.
- Review R.1 (daemon concurrency) → fixed: island timer spawned off-runtime (HIGH: first volume
  change killed the audio worker), hub subscribe/unsubscribe race + orphaned tasks, atomic
  `Hub::update`, lag re-snapshot, bounded reply queue + `bye overflow`, accept backoff, quadratic
  notify sanitiser (184 s → 0.1 s) + caps, watcher spawn/debounce, services report unavailable,
  shutdown grace 2 s (PAM 2FA hang), PAM lockout doctor check.
- Review R.2 (UX) → `docs/reviews/2026-10-09-ux-review.md` (25 findings); #14 fixed by the lead; the
  rest is in cards U-components / U-surfaces (running) and the next steps below.
- Decisions: K21 (inert/pending reasons), K22 (mod settings). CONTRACT-CHANGE rows 5–19 decided
  (16 deferred: fold `RefcountedService` into `ServiceProvider`).

**Half-done / where it lives**
- `U-components` (theme tokens, AA contrast, focus/keys, hit targets, motion, provenance chip) and
  `U-surfaces` (bar.enabled/edge honoured, Stage sample chips removed, launcher errors, sizing) ran as
  Haiku agents in worktrees `.claude/worktrees/agent-*` on branches `worktree-agent-<id>`
  (`git branch | grep worktree-agent`). If their reports were not merged: for each branch, check the
  diff stays in the card's owned paths, run the gate (below) + `frontend/test-real.sh` + `just golden`,
  Read the screenshots, then `git merge --no-ff`. If a branch has no commits, re-run the card.
- Island hit target still 26 px (< 32): decide in Bar (U.1 note). Per-output PSS is at its limit.

**Next steps (ordered)**
1. (U-components / U-surfaces landed.) Settings polish from the UX review (#3 settings
   focus/keys, #7, #8, #9, #11 settings, #13 error codes→keys, #17, #18, #23) as one card owning `settings/`.
2. (Machine A quiet benchmarks done.) A first baseline on the user's second machine (Machine B, `docs/BENCH.md`), plus `just golden --update` there (refs are per machine).
3. Frontend for tray + Bluetooth (bar widget + stage panel) against `fixtures/ipc/server/snap_{tray,bluetooth}.json`.
4. logind session for a `systemd --user` daemon (resolve the user's graphical session explicitly;
   today session hints may stay `available:false`).
5. Fold `RefcountedService` into `ServiceProvider` (row 16); per-mod profile sections (K22 note);
   connection-level reconnect for D-Bus services (they stay unavailable after a bus loss).
6. M6 first native mods (media + lyrics, wallpaper, sysmon, weather), live niri test with the user present.

**Process lessons (keep)**
- **Gate every merge with `just check` in the repo's own target dir** (`unset CARGO_TARGET_DIR`,
  `CARGO_INCREMENTAL=0`): the shared agent dir hands worktrees each other's path-crate artifacts and
  embedded files (seen 5×: missing fields/modules, a test palette baked into a binary). Crate-only
  checks let a cross-crate break through once (theme test read the mock's moved source).
- Always `timeout` + `set -o pipefail` (a piped failure got committed once; a deadlock ran 4.5 h).
- CONTRACT-CHANGE rows collide when agents append in parallel: renumber at merge.
- Frontend agents can use prebuilt daemon binaries (`KURASHI_BIN_DIR`) to avoid compiling.

**Risks / open**
- Disk: the user cleaned up (138 GB free at 12:27). The shared agent dir grows ~1–2 GB per agent;
  prune its stale `debug/incremental` dirs between waves (ask the user if the tool is denied).
- 13 leaked bake-off `dbus-daemon`s (`/tmp/kurashi-sb-{slint,iced,gpui}`), harmless; user may
  `pkill -f 'address=unix:path=/tmp/kurashi-sb-'`.
- Volume keys need a standing `svc.audio` subscriber (the bar has one). Lock with stale marker but no
  PAM service starts locked (doctor reports it).

---

## 2026-10-09 — session 2: M0 decided, M1 complete, M2–M7 foundations + first full UI (parallel waves)
**State:** everything is on `main`, green (`just check` ~200 tests; `just bench-gate` 0 violations on
the real stack; `nix build .#kurashi` ✔). Work ran in waves of ≤5 subagents with task cards in
`docs/tasks/` (README = common rules), each in its own worktree; builds serialised through one shared
`CARGO_TARGET_DIR=~/.cache/kurashi-agents-target`. No agents running at handover.

**Decided / merged this session**
- K3 = Quickshell/QML (bake-off, `BAKEOFF.md`); K16 PSS budget ≤150 MiB @1 out, ≤+6/out (measured
  vs popup-closed); K17 protocol v1 **frozen**; K18 profile loads clear section pins; K19 Stage =
  one content-sized, permanently mapped, transparent surface on the focused output; K20 a locked
  session survives daemon restarts.
- Daemon `kurashid`: hub (revisions, merge-patch diffs, refcounted providers), actions, intent
  coalescing, config store (`config`, `schema.settings`, cfg.*, apply/dry-run/undo/redo, profiles,
  file watcher, a11y → `forced:accessibility`), `theme` (kurashi-theme), `i18n`, `svc.clock`,
  `svc.workspaces` (niri), `svc.media/power/session/network/brightness` (D-Bus), `svc.audio`
  (libpulse, origin echo), island arbiter (`runtime.island.main`: clock/media/notifications/volume
  faces; volume = transient OSD; notifications = unread relevance), `runtime.ui` (panel/launcher),
  launcher queries + launch, notification server (non-stealing), mods registry, `runtime.lock` (PAM),
  `doctor` query.
- CLI: get/set/why/reset/undo/redo/profile/doctor/act/sub/intent/raw.
- Frontend (`frontend/`, real daemon or mock): Store core API (watch/unwatch refcounted, act, query),
  Bar, Stage, Island faces, toasts + notification center, launcher, lock screen. Settings app
  (`settings/`, schema-generated). i18n en+ja for every domain (schema catalog generated + test).
- Nix: package ships data dirs, libpulse + PAM inputs; HM module runs kurashid + frontend
  (`just nix-eval-test`); NixOS module installs PAM service `kurashi`.
- Bench: `just bench-gate` (real stack) — 0.03 fps idle, 0 % CPU, 137.9 MiB, +4.0/output, popup 3.9 ms.

### Next steps (in order)
1. **Memory headroom (risk):** real stack 137.9 MiB, mock 150.5 with popup — each new surface costs
   ~3–5 MiB. Kaizen task: lazy-create rarely used surfaces' *content* (Launcher list, Lock content,
   NotificationCenter) via Loaders without unmapping (K19 leak), drop the unused probe props from Bar
   (`clockText/mediaText`, `mods.probe` watch), find Quickshell's per-surface baseline.
2. Blur honesty: report ext-background-effect availability (frontend sees the global) → daemon
   `forced:capability` for `theme.material.blur` with reason (schema coupling already declared).
3. Session menu (lock/suspend/reboot/poweroff via `svc.session` commands, confirm step) + OSD for
   brightness (island transient like volume).
4. Island config from schema (`island.main.faces/default/ttl` → IslandConfig), input-slot bindings
   resolved by the daemon (schema `input_slots`) instead of hardcoded actions in the frontend.
5. Mods: register contributions on enable (island faces, services, settings pages) — M6; first native
   mods (media+lyrics, wallpaper, sysmon, weather, clipboard) as cards.
6. Launcher watcher refcounted per launcher open; `doctor` async facts (buses, notification name).
7. M7: live test on niri **with the user present** (never start the shell on their session unasked);
   golden screenshots for the component kit; `--idle 600` CPU budget run.

### Open decisions / risks
- Memory headroom (above). Mod widget documents: real `mods` is a registry; the probe's `mods.probe`
  widget-list shape needs a successor (M6).
- Notification server owns the name for the daemon's lifetime (deliberate Ma exception).
- `volume` face is cyclable via scroll (registered face, not in config order) — decide whether
  transient-only faces should be excluded from cycling (arbiter change).

### Gotchas learned this session
- Subagent tools refuse report files → reports come back as text; the lead saves/acts on them.
- `sandbox.sh start` once failed silently outside `nix develop` and two agents drew on the live
  session — fixed (fails closed). Bench sandboxes now carry the pid (parallel runs killed each other).
- Shared target dir: `debug/<bin>` is overwritten by other worktrees — copy right after building.
- Never chain `merge` after a check with `;` — use `&&` (one broken merge, fixed in 186066d).
- Exporting `XDG_CONFIG_HOME` for a smoke test in the same shell breaks `git commit`.
- zsh: `"$B:path"` triggers a history modifier — write `"${B}:path"`.
- PAM: without `/etc/pam.d/kurashi` PAM falls back to `other` (deny); tests never use real credentials.

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
