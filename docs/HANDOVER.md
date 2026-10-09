# Handover

Updated at the **end of every session** (K14). Newest entry on top; keep the last 5 entries.

## Pickup prompt (paste into a fresh Claude Code session started in `~/Projects/kurashi-shell`)
> Read `CLAUDE.md`, then the latest entry of `docs/HANDOVER.md` and `docs/BACKLOG.md`, and continue
> with the handover's "Next steps" in order. You have no memory of earlier sessions — everything you
> need is in this repo. Use subagents as described there (parallel, isolated git worktrees, disjoint
> ownership, task cards in `docs/tasks/`; push `main` before spawning them) and keep the lead role
> yourself (review, measure, merge, decide). Ask me the open design decisions the handover lists
> before building them. Follow the feature-branch workflow, keep `docs/PROGRESS.md` current, file
> every new bug or idea in `docs/BACKLOG.md`, and write a new handover entry before ending the session.
>
> Machines: both have a quiet baseline in `docs/BENCH.md` (A = desktop with a GTX 1060; B = hybrid
> laptop, measure on its iGPU with `KURASHI_RENDER_NODE=/dev/dri/renderD129`). Benchmarks only on a
> quiet machine; K3 = Quickshell stays fixed; never modify `archive/bakeoff-probes/`.

---

## 2026-10-09 — session 5 (machine B): waves 9–13, native mods, K24–K28, UX bar
**State:** `main` green and pushed (b53d79f: `just check` 384 tests, golden B ok, `nix build .#kurashi` ok). Usage limit hit
mid-wave: agents were stopped; their **unmerged branches/worktrees remain** (see Half-done).

**Merged:** wave 9 fixes (B2 volume honesty, B3 brightness session, row 20 `item_is_menu`, rows 21–22 config history +
live profiles, B5/B6/B8, I6 test helpers, I8 niri binds); wave 10 (K24 island expanded views + quick settings card +
◐ bar button; K25 mods as config lists `mods.loaded/enabled` — persisted, B11; Settings mod pages, dropdown, pick list;
I9 `choices_from`); K26 native mods (`kurashi-mod-api`, ledger); K28 slots/mod faces/choice sources/`mod.panel.open`
(daemon); quick settings sections (Wi-Fi, power, audio out, BT); B7 lazy island faces + bench mean-of-two-hotplugs.
Decisions K24–K28 in DECISIONS.md (user answered K24/K25/K26 this session).

**User rules added this session (keep):** (1) implementation by parallel Haiku max-effort agents, lead reviews/merges;
(2) **UX bar** (CLAUDE.md): every user-facing feature gets a researched brief in `docs/ux/` and is "done" only against
it; think what a feature *can become* and what it combines with (`docs/ux/COMPOSITION.md`), not the minimum.

**Half-done (later in session 5):** merged since the reset: quick daemon pages (K29), island daemon (K30), mod loading
(W11-mod-qml), weather, sysmon, wallpaper mods, media position (K31), mod import fix (B16/B17: mods import `qs.core`).
Running as agents at the time of writing: W13-settings-ux, W13-quick-ux, W13-island-views, W14-mod-runtime, W14-mods-live,
W14-wallpaper-ux; queued: W14-sysmon-ux, W14-weather-ux (after W14-mod-runtime). If the session ends with agents running:
commit WIP in each worktree (`git worktree list`), rename the branch `wip/<card>`, and re-spawn with "merge branch X first".

**Next steps (ordered):** 1. (done) 2. For each running/stopped card: review, finish (SendMessage
won't resume across sessions — re-spawn the card with "continue from branch X"), merge with the gate. 3. W13-quick-ux and
W13-island-views (cards ready; need W11-mod-qml merged). 4. Lead UX review of every merged user-facing feature against
its brief; PROGRESS "UX ✅" only then. 5. B7: quiet-machine repro of the +29.8 MiB cycle spike (main vs lazy faces, 3
outputs); I10 basic render loop on machine A. 6. BACKLOG B13 (profile load clears user keys — ask the user), B14 (quick
settings multi-output re-pick binding loop).

**Gotchas:** shared CARGO_TARGET_DIR hands worktrees stale path-crate rlibs (agents: touch + rebuild; lead: always gate
in the private target dir). Test runs regenerate tracked shots (`frontend/shots/*`, `settings/shots`) — restore them
unless the UI changed. Machine A golden refs need `just golden --update` there (bar changed). The user's live kurashi
qs shares Qt pages, so absolute @1-out PSS is lower than baseline (per-output deltas unaffected).

---

## 2026-10-09 — session 4 close: handover to the next agent (user feedback from the first live run)
**State:** `main` green and pushed (`just check` 330 tests + `test-launch.sh`, golden 5/5). No agents, no
extra worktrees. The user ran `nix run .#` live on niri for the first time: the bar showed
"disconnected" → fixed (M7.5: QML clients now use the protocol's default socket). Everything the user
said about the island, mods in Settings and wallpapers is in **`docs/BACKLOG.md`** (rows B1–B10, I1–I8,
D1, plus design notes). Read that file before planning; add new findings there (CLAUDE.md rule).

**User feedback to act on (summary; details in BACKLOG):**
- Island click must open the **expanded card of the face it shows** (media → controls, notifications →
  list, …), not a generic card with Bluetooth (B1; DESIGN-SYSTEM §8 already says so). Bluetooth moves to
  a quick-settings card (I2).
- Island model (I1): placements (bar module | standalone surface), faces as submodules (core + mod,
  user-ordered), the island optional like a mod. Lead view: agree, but the arbiter stays daemon core.
- Settings (I3, user's preferred option): loaded mods get pages **in the normal sidebar** with a state
  indicator (loaded-off / on / in use); the Mods page stays core; detected-only mods have no page.
- Wallpaper management (I7) as the first native mod. Animations/look & feel: user is not commenting yet.

**Next steps (ordered; each a card unless marked lead)**
1. **Per-output PSS** (B7, lead): A/B 6b13d56 vs main on machine B iGPU (≥ 3 quiet runs each,
   `KURASHI_RENDER_NODE=/dev/dri/renderD129 just bench-gate`), attribute, cut per-bar cost. Must be green
   before any new per-output surface (standalone island, wallpaper background).
2. **Fix wave** (parallel cards, disjoint files): B2 volume slider honesty (Bar), B3 brightness session
   resolver (kurashi-services brightness.rs), B4 tray waits for NameOwnerChanged (kurashi-tray), B5+B6
   profile error codes + list refresh (kurashid config.rs + settings ProfilesPage), I6 test helpers →
   `tools/bench/`, I8 niri keybinding snippet (README + optional HM option), B10 sandbox default GPU.
   Plus **I9 dropdowns for option sets** (schema `choices_from` resolved by the daemon + a Select control in
   Settings; palette, island default face, faces pick-list) — a prerequisite for the wallpaper backend choice.
   Lead first: contract rows 20 (`item_is_menu`) + 21 (`config.history`), then the settings card drops
   its reply-derived undo flags.
3. **K24 Island model** (lead decides *with the user*, then cards): `island.expand` opens the current
   face's expanded view (latched); each face = compact + expanded component; first expanded views:
   media, notifications, clock, volume/brightness; Bluetooth → quick-settings card (bar widget → Stage
   panel). Standalone placement + multiple islands after step 1 frees budget.
4. **K25 Mods in Settings + mod state model** (lead: contract change to the `mods` doc — detected /
   loaded-off / on / in_use, per-mod on/off key under K22; then a settings card: sidebar pages with a
   token-coloured, shape-coded indicator; `color.status.*` roles in kurashi-theme).
5. **K26 Native mod mechanism, driven by the wallpaper mod** (lead design → cards): how an enabled native
   mod registers its Rust service/actions/settings and ships QML loaded on demand (MODS.md "Lifecycle").
   Wallpaper mod: per-output state, library folders, `wallpaper.set/next/prev`, optional rotation timer,
   theme source `wallpaper` (DESIGN-SYSTEM §2), picker panel in the Stage. **Rendering decided by the
   user:** external daemon **awww / swww**, selected in Settings from a dropdown (BACKLOG I7, I9); awww/swww
   is the default if only one is supported at first. Needs I9 (dynamic choices → dropdown) first or with it.
6. M6 mods after that (media + lyrics, sysmon, weather), each a card on the K26 mechanism; keep the live
   test loop with the user (collect findings into BACKLOG).

**Decisions to ask the user:** K24 (arbiter stays core? standalone island placement priority), K25
(indicator semantics/colours), K26 (Wallhaven now or later; backend is decided: awww/swww).

**How to work (unchanged):** lead = review/verify/merge/decide; agents (Haiku, max effort) get cards in
`docs/tasks/`, isolated worktrees, disjoint ownership. **Push `main` before spawning agents** (their
worktrees may branch from `origin/main`). Gate every merge with `unset CARGO_TARGET_DIR;
CARGO_INCREMENTAL=0 just check`; UI merges also `frontend/test-real.sh` (now asserts the frontend
connects), `just golden` (`KURASHI_GOLDEN_REF=tools/golden/ref-machine-b` on machine B), Read screenshots.
On machine B export `KURASHI_RENDER_NODE=/dev/dri/renderD129` for every sandbox run.

---

## 2026-10-09 — session 4 (machine B): baseline, wave 8 merged
**Machine B** = hybrid laptop (Ryzen 7 6800H, Radeon 680M iGPU — niri renders on it — + RTX 3070 Laptop
dGPU with runtime PM). Its baseline is in `docs/BENCH.md`; the runbook is done (don't repeat it).
Everything below is on `main` and pushed to origin; `just check` green (330 tests, 0 ignored,
+ `frontend/test-launch.sh`), `just golden` 5/5 unchanged, `nix flake check --no-build` ✔.

**Merged this session**
- B.2 machine-B baseline: iGPU gate 0 violations; dGPU idle-CPU "failures" = NVIDIA runtime-PM resume
  (~1.7 s driver CPU on qs's main thread, UI blocked ~2 s) — never render the shell on a hybrid's dGPU.
  Probes re-measured (K3 unchanged). Raw JSON in `tools/bench/baselines/` — **`archive/` stays untouched**
  (user rule; the runbook now says so). Golden refs `tools/golden/ref-machine-b` = pixel-identical to A's.
  `tools/bench/sandbox.sh`: `KURASHI_RENDER_NODE` picks the GPU.
- K23 (lead): tray menus are a Stage panel (`tray.menu.open`, `runtime.ui.tray`), daemon + mock.
- Wave 8 (6 Haiku agents, all merged after review + private-dir gate + sandbox/golden + screenshots):
  S-settings-polish (keyboard/focus ring, AA, 32 px hits, translated errors, headers), B-tray-bluetooth
  (tray widget, tray menu, Bluetooth in the island panel, island hit area = bar thickness, mock docs),
  C-services (one `ServiceProvider<C,H>`, restart with backoff after bus loss), L-logind (explicit
  graphical session: XDG_SESSION_ID → user Display → Sessions → auto), C-mod-sections (`mods.<id>`
  profile sections, K22 addendum), K-hybrid-egl (`launch.sh` pins the EGL vendor of the compositor's
  dmabuf main device; −10 MiB here; HM + `nix run` pass `KURASHI_WAYLAND_INFO`).
- Lead fixes: `frontend/test-real.sh` and golden point kurashid at a missing system bus (no host BlueZ
  from tests); CONTRACT-CHANGE deduped/renumbered (rows 19–21 decided); MODS.md/PROTOCOL §5 K22 text.

**Numbers (machine B iGPU, after wave 8):** 114.3–115.5 MiB @1 out, idle 0 fps / 0 % CPU, popup 3.3–3.6 ms,
cycles ≤ +1.3 MiB — but **per extra output +4.7…+6.7 (mean ≈ 5.95, 2 of 4 runs over ≤ +6)**.

**Next steps (ordered)**
1. **Per-output PSS headroom (budget at its limit on A and B).** A/B on machine B iGPU: 6b13d56 vs 451347d,
   ≥ 3 quiet runs each (`KURASHI_RENDER_NODE=/dev/dri/renderD129 just bench-gate`), to attribute wave 8;
   then cut per-bar cost (candidates: per-bar Watches/Loaders, Island wrapper, tray Repeater, the unused
   `mods.probe` watch + ModNode repeater in Bar). Don't change the budget without the user.
2. Contract rows 20 + 21 (accepted, lead): `item_is_menu` in kurashi-tray (SNI `ItemIsMenu`; frontend reads
   it), and `config.history {can_undo, can_redo}` in kurashid + fixture + PROTOCOL §5; then settings
   `Store.qml` drops its reply-derived `canUndo/canRedo`.
3. Small fixes from reviews: brightness `SetBrightness` still on `session/auto` (same systemd --user gap as
   L-logind — reuse its resolver); tray start failure (watcher name taken by another shell) retries every
   30 s while a bar is visible → wait for NameOwnerChanged instead; profile actions should send error codes
   (settings shows "(code: invalid)"); move `settings/keys.py` + test-bindings' virtual pointer into
   `tools/bench/` (CONTRACT #6); profile list refresh when files appear.
4. **Live test with the user** (M7): `nix run .#` on niri was never run on a real display before this
   session — collect the user's findings, then fix (tray with real SNI items, menu-only items, scroll
   sign, side bars, keyboard paths are untested against real apps).
5. M6 first native mods (media + lyrics, wallpaper, sysmon, weather): needs a lead design first — how a
   native mod contributes QML components + Rust services when enabled (`docs/MODS.md` "Lifecycle").
6. Idea (user, not planned): Bevy as a candidate in the next framework re-test (`docs/BAKEOFF.md`).

**Process lessons (keep)**
- Tests must not hand clients what a live session doesn't: the frontend read only `KURASHI_SOCKET`, every
  sandbox test exported it, and `test-real.sh` passed with a disconnected bar (it took screenshots,
  asserted nothing). Found in the user's first live run; fixed (M7.5) + a hello assertion.
- Agent worktrees may be created from `origin/main`, not local `main`: **push (or fast-forward) before
  spawning**, or tell agents to `git merge --ff-only main` first (4 of 6 started on a stale base).
- A restarted Claude process restarts its background agents; check `ListAgents` before touching worktrees
  (the classifier rightly blocked removing live ones).
- Agents running in parallel append the same CONTRACT-CHANGE row number — renumber at merge (again).
- zsh: `git show $B:crates/...` breaks (`:c` modifier) — quote as `"$B:path"`.
- Hybrid GPUs: export `KURASHI_RENDER_NODE=/dev/dri/renderD129` for every sandbox test on machine B.

**Half-done / risks:** none half-done; no agents running, no extra worktrees. Per-output PSS (step 1) is the
open risk. `frontend/shots/tray-bt/` is generated, untracked.

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
