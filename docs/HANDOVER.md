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

## 2026-10-18 — session 6 (machine B): wave 14 close, K34–K36, wave 15, K35 daemon
**State:** `main` green and pushed (`just check` 682 tests, settings/test.sh, mods-live no QML warnings, stage/quick/volume tests, golden B ok). Wave 16 (W16-peek-frontend) is the next card; nothing half-done.

**Merged:** session-5 leftovers resumed and finished — W14-weather-ux, W14-sysmon-ux (PopupWindow peek removed at merge:
K19, row 75 rejected); lead: Stage `cardWidth` for mod panels (row 66, I53); **K34** palette `wallpaper` follows
`mod.wallpaper.theme.image` (daemon holds the mod's document while chosen; waiting note); **K35** (user decision) the
Stage hosts peeks — daemon/contract/mock side: `ui.peek`, `runtime.ui.peek`, `peek:<name>` → `qml/Peek.qml`;
**K36** (user decision, B13) profile load is an overlay. Wave 15 (4 Haiku cards): W15-profiles (K36 + Profiles page
review/export/import), W15-job-active (`JobCtx::set_active`, honest "Running now", I48), W15-quick-island-polish
(I51/I52/I45/I44/B14), W15-sysmon-fixes (B24 shell processes protected by identity, I61 names, I62 GPU tile, I56
`KURASHI_SYSMON_ROOT` + `mods/sysmon/test-states.sh`). Lead fixes: island secondary name, volume a11y (I12), 400 px
card for power/bluetooth. BACKLOG: B22–B25, I55–I65 filed; contract rows 70–82 decided.

**User decisions this session:** B13 → overlay (K36); K35 → Stage-hosted peeks. User added `INSPIRATION.md` (I60:
Vitreus, Capsule, pleamar, a Project-Sekai Quickshell rice) — use it in the next design pass.

**Next steps (ordered):**
1. Spawn **W16-peek-frontend** (`docs/tasks/W16-peek-frontend.md`, card ready; push main first). It owns Stage.qml,
   Bar.qml hover plumbing, tray/island peeks and the sysmon/weather/hello `Peek.qml`; it must report the K35
   measurements (idle 0 fps, peek PSS, retarget to a second output, 20 hover cycles).
2. Parallel cards with disjoint paths (write them): I52 host sizing of `quick.tiles` (SlotHost + wallpaper/hello tiles,
   row 76); I64 profiles follow-ups; I65/B25 mod follow-ups (wallpaper `null`, sysmon main device); I58 network-less
   sandboxes; row 80 mock focus model so B14 gets a two-output runtime check; I63 data colour roles (kurashi-theme).
3. Lead UX review against the briefs with screenshots: wallpaper (I32 open items), weather (I57), settings profiles.
   PROGRESS "UX ✅" only after that.
4. B7 quiet-machine repro (no agents running) and I10 render-loop check on machine A.
5. Design pass with the user using `INSPIRATION.md` (decor packs, motion; I60, I63).

**Gotchas (new):** agents now get **one build dir per card** (`~/.cache/kurashi-agents-target/<card>`, README rule 3;
B23) — the shared dir handed worktrees stale path crates and once let a sandbox daemon reach Open-Meteo. Delete a
card's dir after merging it (disk: 365 GB, keep ≥ 40 GB free; `./target` is the lead's gate dir). Parallel cards
still collide on CONTRACT-CHANGE row numbers and on the `i18n/*/settings.toml` tail — renumber/resolve at merge.
`git merge` here uses diff3 markers: strip the `|||||||` base block when resolving. One agent's sandbox commands were
refused by the permission guard (W15-job-active): the lead ran the UI checks. A finished agent's worktree stays
locked by this session's own pid — `git worktree remove -f -f` once its branch is merged.

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

**Half-done (end of session 5, usage limit):** main is green and pushed (622 tests; `just mods-live` green).
Merged since the reset: quick daemon (K29), island daemon (K30), mod loading, weather/sysmon/wallpaper mods, media position (K31),
settings UX + settings daemon (K32), mod runtime (K33), live all-mods test, island views, quick settings UX, wallpaper UX.
Open branches: `feat/k34-wallpaper-theme` (lead WIP: palette `wallpaper` → `Source::WallpaperFile(mod.wallpaper.theme.image)`,
hub-event listener, "From wallpaper" offer — NOT compiled yet; finish: build, add i18n `config.choice.palette.wallpaper` +
`theme.note.wallpaper_waiting` (en/ja), a kurashid test with a generated picture, DECISIONS K34, then merge). Agents stopped
at the limit: W14-sysmon-ux and W14-weather-ux — `git branch | grep worktree-agent`, review their commits, re-spawn with
"merge branch X first". The wallpaper-ux worktree is locked by a stale agent pid: `git worktree remove -f -f` it.

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
