# Handover

Updated at the **end of every session** (K14). Newest entry on top; keep the last 5 entries.

## Pickup prompt (paste into a fresh Claude Code session started in `~/Projects/kurashi-shell`)
> Read `CLAUDE.md`, then the latest entry of `docs/HANDOVER.md`, `docs/INBOX.md` and `docs/BACKLOG.md`, and continue
> with the handover's "Next steps" in order. You have no memory of earlier sessions — everything you
> need is in this repo. Use subagents as described there (parallel, isolated git worktrees, disjoint
> ownership, task cards in `docs/tasks/`; push `main` before spawning them) and keep the lead role
> yourself (review, measure, merge, decide). Ask me the open design decisions the handover lists
> before building them, and ask whenever you are unsure (batched, in the selection view). Follow the feature-branch workflow, keep `docs/PROGRESS.md` current, file
> every new bug or idea in `docs/BACKLOG.md`, and write a new handover entry before ending the session.
>
> Machines: both have a quiet baseline in `docs/BENCH.md` (A = desktop with a GTX 1060; B = hybrid
> laptop, measure on its iGPU with `KURASHI_RENDER_NODE=/dev/dri/renderD129`). Benchmarks only on a
> quiet machine; K3 = Quickshell stays fixed; never modify `archive/bakeoff-probes/`.

---

## 2026-11-17 — session 36 (machine A): quick polish — 0.5.0, one PR open
**State.** `main` = 0.4.0 (`v0.4.0` tagged and pushed, PR #63 merged). Everything of this session is on
**`feat/s36-polish`** = 0.5.0, **one PR to `main`, not merged** (the user merges; then `git tag v0.5.0` on `main` and
push the tag, K151). The gate's line, on the last code commit (the commits after it are docs):
`gate: passed on 0035643f at 2026-11-17T09:54Z: check, suites (merge set; 1 known failing as on main), hm-eval, nix build`.
The session ran in two parts: the first stopped on the usage limit with three branches unmerged, the second (a pickup
from that state) finished them and closed the run. Task: the "Quick polish" section of `docs/BACKLOG-BATCHES.md`
(8 batches, 50 rows) and sidebars on the top and bottom edges (I607).
**The user's rules of this session** (each is in the memory too): one subagent at a time; a new tuning knob goes under
Advanced; a feature that does not extend an existing one is a first-party mod; vertical bars must work like horizontal
ones; rows are described by what they are, ids in brackets.
**Merged into the integration branch.**
- Launcher (K162): a prefix whose mod is off says so, a `>` command waiting for its words is listed, `> note`,
  `launcher.open {query}`, mod rows draw their icon.
- Frontend polish (K163–K165): the user's picture and name, the large card at the bar's centre, sidebars on the top
  and bottom edges (brief `docs/ux/edge-sidebars.md`), the Now Playing card's colour option, glyph sizes.
- Settings fixes: search, reconnect, reset on inert rows, Location; the components' text on `Label` (I589).
- Web dock: a site's menu in the bar card and the sidebar, sites on the bar as icons (K166), the suite's bar-widget
  row (the mock takes a `mods` document from a test now).
- Side bars: every card comes out of the bar at its module; the volume and brightness sliders stand upright in the
  look's own upright face (`Slider.vertical`).
- The colour wheel on the GPU (B89), tray pictures trimmed (B61), the power menu and the quick footer inert with the
  reason without a session service (I204).
- Mods: a mod's folder and "Open the folder", a views-only mod reports the use it waits for and the Mods row names it
  (I592), the row says which program a mod runs and its switch asks first (I593 parts 1 and 3), covers from the web
  can be switched off (I133).
- W99 the wallpaper pickers (an Opus agent, stopped once and finished by a second one): one `PickerCore`, both pickers
  use the room, the appearance menu's picker has the card's features, "theme follows the picture" takes effect (I135).
**Not done, and why** (each has its row).
- I593: the mod's own Settings page lists no `uses` and its switch does not ask (the `mods` document carries no
  `uses`: a contract change); rust and go host templates; bubblewrap.
- I484: only the sliders. Keycap chrome, material on controls, more faces, the hover preview are open.
- B62: the tint is seen in the window list and the launcher; a toast drew the bell glyph in the sandbox, the dock was
  not looked at.
- I352 (the sheet's sidebar spill): probably ended by the scrolling sidebar of 2026-11-10; not seen, because
  `settings/test-sheet.sh` fails at its first check (**B158**, fails before this session's Settings changes too).
- **B159**: `frontend/test-controls.sh` fails 6 relief checks, the same on the branch before the upright sliders.
- B123: the web dock suite's growth check is still noise (+6.5 MiB this time).
- B88 (the wallpaper lags a colour change): cause found, in Rust (bake every output first; the shell's fade
  duration); not fixed.
- I138 (launcher grab-bag), I69, I73 (web dock ideas), I214, I83's "Clear thumbnails" (CONTRACT-CHANGE row 821),
  I32's drag-and-drop / lock wallpaper / `look:` provider.
- I611: at the default large-card height a 1080p screen shows under two rows of pictures; the appearance card's side
  column scrolls. A decision for the user: a taller card for pickers, or a smaller preview.
**What the lead chose without asking** (each can be changed): the question before a program mod goes on is asked every
time, not remembered ("asks once" read as one confirm step, as Delete does); the Mods-page hook `mod` stays the direct
path and `modWish` is the switch's; the upright slider is the same component with `vertical`, not a second one;
`mock.doc` may create the mock's `mods` document; `frontend/test-media.sh` got new click coordinates for the large
card (outside W99's owned paths, needed).
**Verified.** Seen on nested niri: the parts sheet's upright sliders in eight looks; the Mods page with a waiting mod
and the question, light and dark; Palettes and Bar in the snes look after `Label`; the icon tint in the window list;
the wallpaper card, the launcher's pane and the appearance card, light, dark and sekai (W99's shots, read by the
lead). Suites: the merge set in the gate (56 suites; `test-quick-modules` known, B92; `test-card` and
`test-previews` failed under load and passed alone). `mods/webdock/test/test-dock.sh` outside it: every row but the
growth check. The first gate runs stopped in `just check` on the mod index's example entry, whose hash moves with the
version (I612).
**Left in the workspace.** Nothing of this session: its worktrees, branches (`feat/s36-*` but the integration
branch) and agent build dirs are removed, `just sweep` ran (target 120 G, 62 older sandboxes kept by the sweep's own
rule); 332 G free.
**Next steps (in order).**
1. The user merges the PR; then `git tag v0.5.0` on `main`, push the tag.
2. The parked structure session, unchanged and still first when the user asks for it: **B156** (the frontend's memory
   growth), **W92 rows 4–6**, **W95 .2, .4, .5** and the per-mod `Label` cards, **W96** (the red suites: I603, I594 —
   and now B158, B159).
3. Only if the user asks for features: I593's contract change (`uses` in the `mods` document), B88's fix, I611's
   decision, the rest of the quick-polish rows above.
**Open decisions for the user.** I611 (picker height or preview size). Whether the program question should be
remembered per mod. The brief `docs/ux/mod-catalogue.md` is still unread (from session 35).

## 2026-11-16 — session 35 (machine A): the integration branch — 0.4.0, one PR open
**State.** `main` = 0.3.0, tagged `v0.3.0` and pushed. Everything else is on **`feat/s35-integration`** = 0.4.0, **one
PR to `main`, not merged** (the user's rule: the lead merges nothing into `main`; the user merges; then `git tag v0.4.0`
on `main`, push the tag, K151). The gate's line is in the PR's body. Each card was built on its own branch and merged
`--no-ff` with its acceptance in the merge message.
**The user at the end of the session:** "the task was mainly about project optimisation/structure, not reinventing the
wheel" — the session spent too long on the feature cards (W91, W93, W94, W98) and W90's hunt, and stopped twice without
working (the usage limit, an expired login). **Next session: structure first** (W92's rows, W95, W96, B156), features
only when the user asks for them.
**Merged, acceptance met.** W89 (the suites' kit) · W91 (mods read and call from Rust, K158) · W93 (host programs,
K155) · W97 (the Nix dependency derivation without the version, K156: 657 s → 280 s) · W95.1, .3, .6, .7 (`Label` in
quick, expanded, Settings' components and pages).
**Merged, acceptance not met (each merge message says what is missing).**
- **W90** (K157): the daemon within budget (63–70 MiB flat; 0.3.0: 66 → 260 in two minutes), bounded caches, the
  notification centre, `just soak`. The frontend still grows about 200 MiB an hour under continuous card use (**B156**,
  cause not found); the re-read of the user's session a day after a rebuild is not done.
- **W92** rows 1–3: `svc.location` (K159: a place set by hand under Settings › Power, or offered by a mod with
  `location:<name>`), the desk's weather card as the weather mod's `desk:weather` (K160, **config schema 8**,
  `v7_to_v8`), the clock's peek names no mod (I602). Open: row 4 (binds, I571), row 5 (the wallpaper's three:
  `theme.rs`, `Wash.qml`, `AppearanceMenu.qml`), row 6 (the sidebar's hold over the web dock's page).
- **W94** the Mod Editor: the four messages (PROTOCOL §6, `spec.skips`, `rules`), the daemon's and the mock's side over
  `kurashi_mods::editor`, the page (Settings › Mods › New mod…, `> new mod`), `settings/test-mod-editor.sh` in the merge
  set; Mods › Check per mod with the same report (`settings/components/CheckReport.qml`). Not done: the shell's icon
  picker in the page, "Open the folder" (the `mods` document carries no path, I605), the skip error names no variant
  (I604), a made mod placed in the bar and its panel opened in a suite, the states other than fresh / id taken / skip
  edited / passed / created on niri.
- **W96**: `launcher`, `media`, the lyrics suite in the merge set; `test-modqml` green once; `test-mods-live` to its
  second phase (I603); the timer's, sysmon's, the calendar's, the terminal's, the web dock's suites and B154, B155, I584
  untouched (I594).
- **W98** step 1 (K161): the Nix-compatible tree hash, index entries, the reach summary, `.source`, `kurashi mod hash`,
  `mod check --summary`, `tools/mod-index/`. Not built: fetching, `mod.add` / `update` / `remove`, Browse, the
  Home-Manager option. **The brief `docs/ux/mod-catalogue.md` has not been read by the user.**
**Not started.** W95.2, .4, .5 and the per-mod `Label` cards (I589).
**What the lead chose without asking** (each can be changed): jemalloc with two arenas over glibc's tunables and
mimalloc (K157); `follow` / `calls` handles and a waiting mod that stays switched on (K158); a host program starts
`subscribed` with ten seconds of linger; the place in effect lives in the config store and a place set by hand wins
(K159); the weather card stands among the mods' cards in mod order, and `desktop.weather` became an entry in
`desktop.hidden` (K160); the catalogue's hash is Nix's NAR hash, its summary is written by CI (K161); W90 was merged
with the frontend over budget; the bench gate's rows that were red at 0.2.0 were not taken up (B153); `v0.3.0` was
tagged with the gate red (the user chose that).
**One thing to know.** A first run of W93's new test let its test program say a scoped hello to the *running* shell's
socket; it was answered with `goodbye` and nothing else happened. `HostEnv.socket` gives a test daemon its own path now.
**Verified.** The PR's body carries `just gate`'s line. Seen on nested niri, light and dark: the notification centre's
list, quick settings and the expanded views after `Label`, Settings' pages after `Label`, a host program's sentence at
its mod's switch, Settings › Power › Location, the weather mod's desk card, the Mod Editor in two looks. The bench gate
is red on rows that were red at 0.2.0 (B153).
**Next steps (in order).**
0. The user merges the PR; `git tag v0.4.0` on `main`, push. A day later: read the running session again (`/proc`, as
   BENCH "Soak" did) — W90's last acceptance line.
1. **B156**, the frontend's remaining growth (a Quickshell with debug symbols under heaptrack, or bisecting the Stage's
   view Loader on `just soak --only island`; the kept view of I493 is one thing to switch off first).
2. **W92** rows 4–6, then the card's grep as a test (exclude `kurashi_mod_api`).
3. **W95.2, .4, .5** and the per-mod cards; then the check's notes become errors.
4. **W96**: I603 (`test-mods-live` phase 2), I594's list.
5. Only on the user's word: W94's leftovers, W98 steps 2–7 (after the user read the brief), I593.
**Left on this machine.** Nothing was removed (the removal was refused by a safety check; the user's to do): the work
trees `.claude/worktrees/{s35-soak,s35-v020,s35-w93,s35-w97,s35-w98,s35-w92,s35-lead,s35-w94,agent-a9d677188cf796ebc}`,
their merged branches, the build dirs `~/.cache/kurashi-agents-target/{s35-lead,s35-w92,s35-w93,s35-w94,s35-w98,W94page}`
and stale `/tmp/kurashi-sb-bench-*`. The PR's body repeats this.

---

## 2026-11-15 — session 34 (machine A): the loop and the mod contract — 0.3.0, PR open
**State.** `main` = 0.2.0 (untouched). Branch `feat/s34-loop-and-mods` = 0.3.0, **PR #62 open, not merged** (the user merges;
then `git tag v0.3.0` on `main` and push the tag, K151). Gate: see "Verified" (the last code commit is 274f04e3).
One agent worktree is left: **W89, finished, not merged** (`.claude/worktrees/agent-add20fbd7bf4e0b6d`, branch
`worktree-agent-add20fbd7bf4e0b6d` at 0ab8a3ab, made from ce6218b6; build dir `~/.cache/kurashi-agents-target/W89`): the
suites' kit, 23 suites on it; kept out of PR #62 because the lead had not re-run the merge set on it and `test-peek`
stayed on its own client (I580). Disk: 204 GB free when last read; `target/` about 230 GB, all younger than seven days (the
new dev profile rebuilt everything once; I569 asks the user about a size cap).
`~/.cache/kurashi-agents-target/debug` (3.8 GB, no card's name, older than this session) was left alone: ask the user.
**Done** (K153, K154; BACKLOG I540–I576, B142–B144; the review that started it is in those rows).
1. *The loop (K153).* `just gate` (check, suites, hm-eval, nix build → the commit it passed on), `just sweep` (131 GiB taken
   out of `target/`), `just timings`, `just clones`; `just check` on nextest (tests 9 min → 3 min) with a clone ratchet
   (`tools/clones.py`, `tools/clones-baseline.json`); the dev shell links with mold, dev profile `line-tables-only`
   (a rebuild after an edit 16.5 s → 4.2 s; BENCH "Build loop"); `just suites --changed` runs one mod's suites for a
   change inside that mod, reads `# covers:` lines, has `--list`, reaches all suites. CLAUDE.md rules 10–12, "The loop",
   "QML first", session start with `git fetch` and `just sweep`; the lead's rules that lived in one machine's memory.
2. *Bugs.* B143 documents never carry `null` (the hub strips it); B142 sysmon declares `exec:systemd-run`; B144 a racing
   brightness test.
3. *The mod contract (K154, docs/MODS.md "Integration contract").* `kurashi-mods`: `points` (the registry of where a mod
   can stand), `contract` (`uses` doc/action/intent, `points`, `[[action]]` with typed arguments, `[[menu]]`, `[skips]`,
   `icon`), `check` (the ruleset), `scaffold` (templates that pass it). The twelve bundled manifests declare; a test
   holds them. `kurashid`: declared arguments checked before the handler, the `actions` query with `schema`, `icon`,
   `command`, `mod`; `>` commands from manifests (`> timer 5`, `> task buy milk`); the `mods` document with `icon` and
   `menus`; a mod's own strings in `i18n`. Frontend: the desktop's and a module's menu draw the mods' rows; `qs.kit`
   (`frontend/kit/qmldir`) and `components/Label.qml`; a mod's icon on its Settings page. CLI: `kurashi mod
   check|points|reach|new`. Docs: `docs/MODDING.md` (the community's guide), `docs/ux/mod-editor.md` (brief).
   New suite `frontend/test-mod-contract.sh` (nested niri, in the merge set).
4. *Dedup.* W88 merged: `crates/kurashi-testkit` (one D-Bus test bus; rs clones 1077 → 810).
**The user's answers this session.** Dedup and cleanup: rules plus tooling. Mod tooling: ruleset, scaffolder, check, and
the editor started now. Languages: Rust in the tree, Luau for portable mods, any language as a host process. Console:
typed actions plus the variant check. Later, in passing: mods bring their own menu rows; templates must guarantee a
native feel, with icon and settings; a community document on making mods (done: MODDING.md); and two questions to
discuss next — how a Rust mod is distributed (it is linked into the daemon today; nothing is compiled or loaded on a
user's machine) and how to organise a catalogue (I570). "If I don't answer, pick the best and show what you chose."
**What the lead chose without asking** (each can be changed): one PR for everything (one gate) instead of two; mold
and `line-tables-only` after measuring; a mod names another mod's point as `slot:<mod>:<point>`; `uses` has a third
kind, `intent:`; the views are held to `uses` by a static check, not a run-time facade (the mods import the global
Store; no cost at run time); an action without a declaration still works and is logged; `easter-eggs` is exempt from
the check until it has code (I286); the check's native-feel lints are notes, not errors, until the bundled mods are
clean (I574); the kit is a `qmldir` naming the shell's own files (same types, nothing compiled twice); a user-made mod
is views only today (a host process needs a crate: I576) and the guide says so; a list of suites that fail on `main`
with their rows (`tools/suites-known-failing.txt`) so the gate can pass while B92 is open; this file trimmed to its
five newest entries (its own rule); the argument error is the plain key `error.args.invalid` (views translate it) and
the daemon's log names the argument; rule 12 is written as the rule though its roll-out is not finished (MODS.md
"Roll-out" says what is built); W89 kept out of this PR; the branch pushed and the PR opened.
**Verified.** `just gate --no-suites` passed on 274f04e3, the last code commit (check: 1539 tests, clippy, the clone ratchet at rs 810, qml 1512, sh 1999; hm-eval; `nix build .#kurashi`, 0.3.0). The merge set (51 suites) ran on 82a2578d: 50 pass — three only alone, a second runner
shared the machine (I578) — and `quick-modules` fails as on `main` (B92, now in `tools/suites-known-failing.txt`); the suites
the later commits touch were run again on the head (the web dock's four, `mod-contract`, `context-menus`, `module-menu`).
The flake's `tests` check: green (142 test binaries; it was red on `main`, B146). `frontend/test-mod-contract.sh` on nested
niri with all twelve mods on: every registered action is declared. A scaffolded mod through the daemon
(`kurashid/tests/native_mods.rs`) and the kit in Quickshell (a sandbox). Outside the merge set, run on the head and on
`main` (862f5375): `launcher`, `timer`, `sysmon`, `calendar`, `terminal`, the web dock's `test-dock` fail on both, alone
(B145); `test-dock`'s cost check reads 10.4 MiB against 8.4–9.5 on `main` because the mod-off baseline is lighter here, the
mod-on figure is the same (I582); `ai`, `lyrics`, `tasks`, `weather` pass. **Not run:** the bench gate (the hub's write
path changed: `strip_nulls` on every write) — run `just bench-gate` on a quiet machine before the tag. Not seen on niri by
eye: the module menu's own rows, the launcher's command rows, a scaffolded mod's views. Nothing was run on the user's
screen; the user's running session was read through `/proc` only (B147: it holds 1.9 GiB after 42 h).
**The user's decisions at the end of the session** (K155, K156; each staged as a card): code mods outside the tree are
host programs; the catalogue is an index repository with Nix beside it; the Nix dependency cache is keyed without the
version; the next session starts with the memory growth; then the consuming side, the core's reads of mods, host
programs, the Mod Editor (the full brief), the catalogue; `Label` and the kit by a card per folder; the six red suites
are fixed and join the merge set; `just sweep` caps `target/` at 60 GB (run: 133 GiB more taken out; `du` still says
102 GB — cargo-sweep does not count `incremental/`, I569); the unnamed agent build dir is deleted (done). **The inbox**
(the user): `docs/INBOX.md`, bugs and ideas by area, read before work on an area starts (CLAUDE.md "Workflow").
**Next steps (in order; every card is in `docs/tasks/` and ready to start).**
0. Housekeeping, before anything: `git fetch`; the user merges PR #62 (if not yet); `just bench-gate` on a quiet machine
   (the hub strips `null` on every write: not measured yet), then `git tag v0.3.0`, push the tag. W89: review its diff,
   merge it on a branch of its own, `python3 tools/clones.py --update` (expect sh 1573), `just gate`, PR; remove its
   worktree, branch and build dir.
1. **W90** — what grows in a day (B147): read the user's running session first (ask; read-only), `just soak`, find and
   fix the growth in the daemon and the frontend, a growth budget in BENCH.
2. **W91** — `ModCtx::follow` / `call`, inert on a missing use, a host's scope from `uses`; lyrics and sessions lose
   their QML workarounds.
3. **W92** — the core names no mod: `svc.location`, the desk's weather card, `clock.peek.lines`, binds from
   declarations, the wallpaper's three, the sidebar's hold; its grep becomes a test.
4. **W93** — host programs (K155): the protocol's `pub`, `serve`, `call` designed and fixtured first, then built; the
   host templates.
5. **W94** — the Mod Editor, the full brief: daemon queries and actions, the mock, the QML prototype on niri for the
   user's look, then wired.
6. **W98** — the catalogue: its UX brief first, then the index, `kurashi mod add`, the Mods page, the Home-Manager
   option.
Beside them, whenever two agents are free or between steps: **W95** (`Label` and the kit, a card per folder, Haiku),
**W96** (the six red suites, then into the merge set), **W97** (the Nix dependency cache, K156).
7. A look on niri at what session 34 built and no one has seen: the timer's module menu with its rows, `> timer 5` and
   `> task …` in the launcher, a `kurashi mod new` mod turned on and placed; I573 (a mod's icon in the Settings sidebar).
8. Then: the suites' floor (I544), typed documents (I548), `qmllint` (I549), the two `honesty` tests (I542), the mock's
   `mods` document (I581), a BACKLOG triage with the user (I568); and session 33's list (the live read with the user,
   B119, the terminal's and sessions' open ends, I517–I537).
**Risks.** The dev shell's mold applies to `cargo` in `nix develop` only; a build outside it relinks everything with
the default linker. `line-tables-only` drops variable info from debug builds (`CARGO_PROFILE_DEV_DEBUG=full` for a
debugger session). A declared action's arguments are now checked: a caller that sent a wrong type to a declared action
(only the fifteen with a schema) is refused where it was tolerated before. The `>` list lost its "web" row.

---

## 2026-11-13 — session 33, part two (machine A): 0.2.0 merged straight to `main` (the user's call)
**State.** `main` = 0.2.0 (tag `v0.2.0`; `v0.1.0` = PR #61). No open branch, PR or worktree. Merged directly to `main`
(no PR) at the user's word, after `just check` (green) and the touched suites on nested niri (`test-osd`, the terminal's
light/washi pass, `hm-eval`); the full merge set was not run for 0.2.0.
**Done.** The attached OSD (`osd.place = edge`, `osd.edge`, Caelestia's style); the terminal's way out (a Put away key, the
last shell's exit puts it away, `hide_on_blur` on by default — B141); the frontend unit `Wants` kurashid instead of
`Requires`, so a rebuild that restarts the daemon no longer leaves the shell down (B140 — what the user hit after enabling
the terminal); backlog I538 (more room for wallpapers in the Wallpaper & Theming menu), I539 (`!` with the terminal off
should say so). The user's keyboard: English first, German or Japanese sometimes (niri binds go by the first layout:
`Mod+Grave` should hold — confirm with the user).
**Next steps.** As session 33's list below (1 is done: tagged), plus: the full merge set once on `main`; I538, I539.

---

## 2026-11-13 — session 33 (machine A): 0.1.0 — terminal, work sessions, Wallpaper & Theming, OSD, menus, launcher
**State.** `main` = #60 (session 32). **PR #61 (branch `feat/s33-context-menus`) is open, not merged** — the user merges;
after the merge tag `v0.1.0` on `main` and push the tag (K151). No worktree or agent build dir is left (all removed).
Disk ~145 GB free.
**Done** (K150–K152; CONTRACT-CHANGE 764, 782–819 decided or deferred with BACKLOG rows):
1. Dark/light for web pages (the host on Qt's portal theme; a stand-in portal `tools/bench/fake_portal.py`, sandbox
   `KURASHI_SB_FAKE_PORTAL=1`); the docked Settings holds a hover-opened sidebar on its drawer and menus too (B136).
2. W82 right-click menus everywhere (one system on TrayMenu; desktop, bar background, web page; I512).
3. K150 launcher providers for mods; the web dock's `/`; the launcher's clipboard in two columns (I514, I515).
4. W83 + W85 the terminal mod (`qs-terminal`, QMLTermWidget Qt 6, packaged in nix/), Yakuake-like, every place (I516).
5. W84 the Wallpaper & Theming menu (icon rail; launcher or card, `appearance.open`) — the user chose prototype C.
6. K152 the OSD (`runtime.osd`, `Osd.qml`, `osd.*`, `osd.show`) (I527).
7. W86 the `sessions` mod over noren, HM option off by default (I517).
8. K151 versioning (0.1.0, CHANGELOG, `kurashi --version`); `config.toml.example` generated and tested.
9. Fixes found on the way: mods sharing `i18n` / launcher provides refused each other (B137); `hm-eval` had been red on
   `main` (B138); ScrollEdge takes no room and is on every scrolling view (B135).
**The user's answers this session.** No key handover into docked Settings (B129, click only). Online lists sites only.
The apps spike in the web dock: yes, later (I510). Groups: both list and bar preview (built in #60's W80). Terminal:
native QML, everywhere, Yakuake-like, places as a setting, bar module modes, favourite folders, `!` in the launcher.
Versioning: SemVer 0.x. Wallpaper & Theming: prototype C, the preview a switchable section, the wallpaper pane about
choosing. Work sessions: a first-party plugin, "Open in…" after choosing, HM ships noren only when enabled. OSD next
after the core. Ideas I517–I537 in BACKLOG (the user liked them).
**Verified.** `just check` green; `just suites` (50): 48 pass, `bar-fit` only under load, `quick-modules` as on `main` (B92); `nix build .#kurashi` green (0.1.0); HM evals (hm, terminal, webdock, sessions) pass. Each feature seen on nested niri with shots, light and dark, in several looks; nothing seen on the user's screen yet (they rebuilt #60 earlier; read-only CPU at rest 0 %).
**Next steps (in order; ask the user where a step says so):**
1. Check PR #61; after the merge: `git tag v0.1.0` on `main`, push the tag (the user said to start versioning).
2. Live read with the user: their on-screen list in the PR; the CPU reading with music (postponed: they were in a call).
3. Ask: B119 (Qt's basic render loop as an experiment on their session).
4. The backlog's open ends of this session: terminal 801/802 (module-menu rows from mods; OSC 133 patch), sessions
   810–816, appearance 792 (a bar module/quick tile), OSD caps lock and media, B139.
5. The user's picks among I517–I537 (one search for everything, I518, was the lead's next suggestion).
6. Older: B120, B123/B131, B92, I508's open ends, I509, I510 (the web dock apps spike, approved).
**Risks.** The terminal and sessions add two Nix packages (qmltermwidget from upstream master, noren as a flake input):
check `nix flake update` keeps building them. The appearance menu's preview applies real config values while previewing
(put back on Esc/close): a crash mid-preview leaves the previewed value — undo restores it.

---
