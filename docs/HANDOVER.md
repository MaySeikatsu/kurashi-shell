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

## 2026-11-16 — session 35 (machine A): the integration branch — memory, mods that read and call, host programs; 0.4.0, PR open
**State.** `main` = 0.3.0, tagged `v0.3.0` and pushed (the user: tag now, fix in 0.4.0). Everything else is on
**`feat/s35-integration`** = 0.4.0, **one PR to `main`, not merged** (the user's rule for this session: the lead merges
nothing into `main` and no PR; the user merges; then `git tag v0.4.0` on `main`, push the tag, K151). Gate: see "Verified".
Each card was built on its own branch and merged `--no-ff` into the integration branch with its acceptance in the merge
message. Work trees and build dirs left: see the end of this entry.
**Merged into the integration branch.**
1. **W89** the suites' kit (`tools/testkit/{ipc.py,px.py}`); sh clones 1999 → 1573.
2. **W90** what grows in a day (K157, B147, B150–B152): `just soak` (`tools/bench/soak.py`, budgets "Soak growth per hour"
   in BENCH), the daemon on jemalloc with two arenas and a one-second decay (`.cargo/config.toml`, `kurashid::alloc`),
   bounded texture caches (`kurashid::cache::keep_newest`: four tiles in memory, 48 on disk, two sets of swatches), the
   closed notification centre holds no card and its list is a list view, `just bench-gate` builds what it measures,
   `just sweep` takes stale sandboxes. **Acceptance: the daemon met its budget (63–70 MiB flat; 0.3.0: 66 → 260 in two
   minutes); the frontend did not** — the per-notification growth is gone, but opening and closing the island's card and
   quick settings still adds about 200 MiB an hour (**B156**, narrowed, cause not found); the re-read of the user's
   session a day after a rebuild is not done.
3. **W91** mods read services and call each other from Rust (K158): `ModCtx::follow` / `calls`, a mod that waits for a
   missing required use, lyrics follows `svc.media`, sessions calls the terminal itself, a host's scope from the
   contract, `mod check` reads the crates' literals. Acceptance met (crates' tests; `mod-contract`, lyrics, sessions on
   niri). Breaking: `lyrics.track`, `sessions.handed`, `sessions.undelivered`, `mod.sessions.handoff` are gone.
4. **W93** a mod's own program (K155): `[[host]]`, the protocol's `pub` / `serve` / `call` with fixtures, the daemon's
   `ProgramMod` and `native/served.rs`, `kurashi mod new --host python`, MODDING.md 7a, the sentence at the mod's switch,
   `frontend/test-mod-host.sh` (nested niri, in the merge set). Acceptance met; from the design not built: I593.
5. **W97** the Nix dependency derivation carries no version (K156): 657 s from nothing, 280 s after a bump, no dependency
   compiled; the flake's `tests` check passes on it. Acceptance met.
6. **W96, part**: `launcher`, `media` and the lyrics suite green three times and in the merge set; the runner's
   `# needs:` lines. **Acceptance not met as a whole** (I594: `modqml` and `mods-live` still fail at the mod's panel
   card; the timer's, sysmon's, the calendar's, the terminal's, the web dock's suites and B154, B155, I584 not looked at).
7. **W95.1, .3, .6, .7** `Label` in `components/quick`, `components/expanded`, `settings/components`, `settings/pages` and
   `settings/shell.qml` (one Haiku agent at a time, each reviewed: every converted block set its own size, colour and
   family; suites and niri shots equal before and after). Open: W95.2, .4, .5 (they share files with W92) and the
   per-mod cards; I589.
**Not merged.**
- **W94** `feat/s35-w94-mod-editor` (pushed): the four messages with fixtures and PROTOCOL §6, the daemon's side
  (`query points`, `mod.check`, `mod.new`, `mod.rescan`) and the mock's, both over `kurashi_mods::editor`, tested; the
  copy in en and ja. **The page itself is not built** (the prototype on the mock, the niri shots, the Mods page's rows,
  `> new mod`, the suite).
- **W98**: its UX brief only (`docs/ux/mod-catalogue.md`, on the integration branch). **W92**: not started.
**The user this session.** One subagent at a time. May read the live session and restart it if needed (it was read,
not restarted). CLAUDE.md: the maintainer owns the design; finish without stopping. Asked whether sidebars and cards
merge their corners the same way: two builders over one smoothing routine (I588). New inbox lines → I595–I600.
**What the lead chose without asking** (each can be changed): jemalloc over glibc's tunables (they are environment
variables that every started app would inherit; `unsafe` is forbidden) and over mimalloc (K157's table); `follow`
returns a handle whose `watch()` subscribes, and `calls` is per action and checked at enable (K158); a waiting mod stays
switched on; a host program's `start` defaults to `subscribed` with ten seconds of linger; a file in the mod's `bin/`
needs no `exec:` capability; `kurashi-mod-handwriting` follows the workspace's version; W90 was merged with the
frontend over budget and the cause filed, rather than held back; the bench gate's red rows that predate 0.2.0 were not
taken up (B153); every work tree has its own cargo build dir (a shared one handed W93 a stale `kurashi-ipc`).
**One thing to know.** A first run of W93's new test let its test program say a scoped hello to the *running* shell's
socket (the daemon handed hosts the default socket path); it was answered with `goodbye` and nothing else happened.
`HostEnv.socket` gives a test daemon its own path now.
**Verified.** See the PR's body for the gate's line on the head it ran on. The bench gate is red on rows that were red
at 0.2.0 (B153). Seen on nested niri, light and dark: the notification centre's list, quick settings and the expanded
views after `Label`, Settings' pages after `Label`, the host program's sentence at its mod's switch.
**Next steps (in order).**
0. The user merges the PR; `git tag v0.4.0` on `main`, push. A day after the rebuild: read the running session again
   (`/proc`, as BENCH "Soak" did) and note it there — W90's last acceptance line.
1. **B156**, the frontend's remaining growth: a Quickshell with debug symbols under heaptrack, or bisecting the Stage's
   view Loader on `just soak --only island`. Then `just soak 60` on a quiet machine until both budgets hold.
2. **W94**, the page: the QML prototype on `just mock` (the mock answers the four with the real generator), niri shots
   in two looks for the user, then wired; `settings/test-mod-editor.sh`.
3. **W92** the core names no mod, row by row (`svc.location` first), then W95.2, .4, .5.
4. **W98** from its brief: the index, `kurashi mod add`, Browse, the Home-Manager option.
5. **W96**, the rest (I594), and I593 (the ask-once before a host program's first enable).
6. B153: the bench gate's three red rows — a performance pass, or new budgets with the user.
**Left on this machine.** Work trees under `.claude/worktrees/` and build dirs under `~/.cache/kurashi-agents-target/`:
named at the end of the session in the PR's body and removed where their branch is merged.

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

## 2026-11-13 — session 32 (machine A): B128, the travelling workspace mark, Local mode, groups round two, the user's live bugs
**State.** One branch `feat/s32-combined` = #58 (W77) + #59 (session 31 handover) + this session; **PR #60 is open, not merged**
(the user merges; it closes #58 and #59). After the merge remove #58's worktree `.claude/worktrees/agent-ac748735f1e82a580`
(branch `feat/s31-settings-dock`), `~/.cache/kurashi-agents-target/w77`, and W80's worktree
`.claude/worktrees/agent-ae7eda47dcd83e6c3` (locked by its agent's process: `git worktree remove -f -f`). W78, W79, W81's
worktrees and build dirs are gone. Disk: ~180 GB free.
**Done** (K148, K149; CONTRACT-CHANGE 760, 764 decided; 766/767 deferred):
1. B128: the web dock's bar card kept open followed the focus (`bar.popups_follow`); a kept card stays, one not kept follows.
2. I507 / K148: the focused workspace is one travelling mark — `modules.workspaces.motion` goo (default) / stretch / slide /
   off; the wobble from the motion profile; `test-ws-motion` (merge set).
3. The user's live bugs: B132 a hover-opened sidebar holds while the pointer is on the web dock's page (`webdock.side_page`,
   `sidebar.hover`); B133 a pinned sidebar's page was one column off (placed on the output now, zones ignored);
   B134 the pins scroll with the wheel; B135 scroll edges on every scrolling view (ScrollEdge takes no room now).
4. B127 / K149: the docked Settings holds a hover-opened sidebar (`settings.dock_hover`, `runtime.settings.hover`); W79:
   one Settings process per start, a crash clears the dock, doctor and mock.
5. W80 (I508, partly): groups in Settings' list and a bar preview (drag/keys), "Group with…"/"Leave group" in the module
   menu; one `frontend/components/groups.js` (linked into settings/components). Open ends in I508.
6. W78: Local mode; Online lists sites only (the user); the desktop-apps evaluation (I510).
7. W81: B119/B120 measured, no fix: B119 is Qt's threaded render loop (BENCH.md, the rows).
**The user's answers this session.** #58/#59: build on top, one PR. B128: unpinned follows; it was the bar card. Workspace
motion default: goo. W78: Local mode, apps evaluated. Groups: both the list and a bar preview. B129: no key handover, click
only. Online: sites only. Apps spike: yes, next session. "Fix all bugs, then tests and builds; don't waste time on long
compiles before."
**Verified.** `just check` green; `just suites` (44): 43 pass, `quick-modules` red — the same on `main` (B92, checked in a
worktree of origin/main); `nix build .#kurashi` green. Seen on nested niri: the workspace mark (washi keys, dots, Material),
Settings' page edges and the notifications' edge, groups on the bar and the module menu, the docked Settings' hover hold.
On sway only: the web dock sidebar (pinned, hover), B128 (two outputs). Live on the user's session: frontend 0.0 % CPU at
rest (music paused); nothing visual yet.
**Next steps (in order; ask the user where a step says so — batched, one AskUserQuestion):**
1. Check PR #60's state; after the merge clean the worktrees above.
2. Live read with the user (read-only): `top -H` with music playing; ask them to look at the PR's "check live" list. File
   what they report.
3. Ask: try `QSG_RENDER_LOOP=basic` as an experiment card on the real session (B119)?
4. The desktop-apps spike (I510): a script on nested niri with `foot` and `chromium --app` — the user said yes.
5. I508's open ends (empty group drawn, states shot, motion, cross-zone drops, the `rect` hook with screen coordinates).
6. B123/B131 (`test-dock`'s mock bar has no web dock widget), B92 (`quick-modules`: a click past the output), B130, B120.
7. Older: B113, B112/B100, B114, B115, B116, B121, I483, I509's rest, the workspace mark in a side bar's column.
**Risks.** The scroll edge now on Settings' pages turns each page's layer on while it overflows (a layer per page; 0 frames
at rest, but memory). The web dock sidebar's place changed meaning (on the output, zones ignored): a compositor that counts
zones differently would misplace it — seen on sway and in the pinned case only.
