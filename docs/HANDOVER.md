# Handover

Updated at the **end of every session** (K14). Newest entry on top; keep the last 5 entries.

## Pickup prompt (paste into a fresh Claude Code session started in `~/Projects/kurashi-shell`)
> Read `CLAUDE.md`, then the latest entry of `docs/HANDOVER.md` and `docs/BACKLOG.md`, and continue
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

## 2026-11-15 — session 34 (machine A): the loop and the mod contract — 0.3.0, PR open
**State.** `main` = 0.2.0 (untouched). Branch `feat/s34-loop-and-mods` = 0.3.0, **PR #62 open, not merged** (the user merges;
then `git tag v0.3.0` on `main` and push the tag, K151). Gate: `just gate --no-suites` passed on 7b431efb (check, hm-eval, nix build); the merge set ran on 82a2578d (the commit before; only the runner's known-failing list changed since): 50 of 51 pass, `quick-modules` fails as on `main` (B92, now listed in `tools/suites-known-failing.txt`).
One agent worktree may be left: W89 (`.claude/worktrees/agent-add20fbd7bf4e0b6d`, branch
`worktree-agent-add20fbd7bf4e0b6d`, build dir `~/.cache/kurashi-agents-target/W89`) — its agent was still editing and running suites when this was written (29 files changed, nothing committed); merge it when it reports (re-measure `python3 tools/clones.py --check`, then `--update`), or drop it. Disk: 204 GB free; `target/` 228 GB, all younger than seven days (the new dev profile rebuilt everything once; I569 asks the user about a size cap).
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
is views only today (a host process needs a crate: I576) and the guide says so.
**Verified.** `just check` green (1538 tests, 167 s; clippy; the clone ratchet at rs 810, qml 1512, sh 1999); the merge set 50/51 with three suites green only alone (`webdock/test-card`, `settings/test-dock`, `bar-fit`: I578 — a second runner, W89's, shared the machine); hm-eval and `nix build .#kurashi` green (0.3.0; all 341 dependencies rebuilt for the version bump, I577); `frontend/test-mod-contract.sh` green on nested niri. Not seen on niri by eye: the module menu's own rows, the launcher's command rows, a scaffolded
mod's views in the shell (its kit import loads in Quickshell: checked in a sandbox). Nothing was run on the user's screen.
**Next steps (in order; ask the user where a step says so).**
1. The user checks and merges the PR; then tag `v0.3.0`, push the tag. Remove W89's worktree, branch and build dir once
   it is merged or dropped.
2. Discuss with the user: I570 (distribution of Rust mods, the catalogue), I576 (a mod's own program without a crate:
   manifest-declared hosts and a publishing scoped connection), I569 (a size cap for `target/`), I573 (a mod's icon in
   the Settings sidebar), `~/.cache/kurashi-agents-target/debug`.
3. Look on niri (shots, light and dark, two looks): the timer's module menu with its rows, `> timer 5` and `> task …` in
   the launcher, a `kurashi mod new` mod turned on and placed. Fix what the look finds.
4. The Mod Editor page (docs/ux/mod-editor.md): `query points`, `mod.new`, `mod.check`, a registry rescan without a
   restart; QML prototype on the mock first, niri shots, then the page.
5. K154 step 5: `ModCtx::follow` / `call` (I127, I552) — lyrics follows `svc.media` itself, sessions calls
   `terminal.run` itself (its QML relay goes); a host's scope from `uses`.
6. I555's rest: a core `location` the weather mod feeds (the night light reads it), binds from declarations (I571),
   `ClockPeek`, `Desktop.qml`'s weather card as the mod's `desk:weather`, `AppearanceMenu`, `Wash`, `Sidebar.qml`.
7. Dedup cards: W89 if not merged; `Label` in the 481 places (a card per folder, goldens and the idle budget checked);
   the bundled mods on `qs.kit` (I557, I574); the lock faces' model; `Rec`/`assert_no_null` into the testkit.
8. The suites' floor (I544: `settings/test.sh` split, the motion scrub as a run-time intent, then `-j 6`), typed documents
   (I548), `qmllint` (I549), the two `honesty` tests (I542), a BACKLOG triage with the user (I568).
9. Older, from session 33's list: the live read with the user, B119, the terminal's and sessions' open ends, I517–I537.
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

---

## 2026-11-13 — session 31 (machine A): live fixes on the user's session, Settings in a sidebar
**State.** `main` = #57 (live fixes). **PR #58 (Settings docked in a sidebar, W77, K146) is open, not merged** — the user
merges; its worktree `.claude/worktrees/agent-ac748735f1e82a580` (branch `feat/s31-settings-dock`) and build dir
`~/.cache/kurashi-agents-target/w77` go after the merge. #56 (session 30) is merged; its worktrees are gone. Disk: ~270 GB
free after removing 154 GB of suite sandboxes and build dirs (B124).
**Done** (K147):
1. B125: read-only `top -H` on the user's session with music: ~115 % of a core, ~6 % with the desktop's media card hidden
   (the colour flow off changed it by a few percent). The card's level bars stand still unless `desktop.media_bars`.
   Not yet re-measured on the user's session after the rebuild.
2. B126: a card opens on the screen whose bar was pressed (IslandGeom's last press), mod cards count as cards, a card
   asked for on another screen while one is open moves there. `test-follow` green; not yet seen on the user's monitors.
3. `ui.keep {on}` / runtime.ui `kept`: the web dock's bar card has a keep-open key (the user's choice: the card itself
   stays; a click elsewhere passes through; Esc, the module, `ui.close` close it).
4. Web dock icons: none was ever saved (K38's privacy setting stopped the engine fetching them).
   `mods.webdock.site_icons` (on) lets it; the grab is retried while shown; `test-host`'s net-log proof runs with it off.
5. B124: the nested-niri sandbox refuses an empty env file or one naming no sandbox, and refuses to start under 2 GB
   free; `sandbox.sh` under 1 GB; `tools/test-suites.sh` under 20 GB (`KURASHI_SUITES_MIN_GB`).
6. W77 (#58, open): the full Settings docked in a sidebar section, a third host `dock`, `runtime.settings` +
   `settings.dock`; gaps in B127.
**The user's answers this session.** Bar card keep-open: the card itself stays open. Colour flow while music plays: leave
as is (I506 closed). Live checks: read-only only — read `top`/documents on their session, they look at the visual things
and tell you; never open anything on their display.
**Next steps — session 32 is time-boxed: the user reviews at 13:00.** Plan backwards from it: a review-ready PR with
a summary by 12:45; the merge set and `just check` on the combined branch from ~12:00; nothing new started after 11:45.
1. **First 10 minutes:** fetch; check #58 and #59 are merged (if not, ask). Then ask the user ALL of these at once
   (one AskUserQuestion, recommended option first) so no step waits later:
   - B128: when the edge web dock is *not* pinned, does it still follow the focus to the other monitor?
   - W78: the desktop-apps experiment's scope (which apps; what "done" means for an experiment), or leave W78 for later?
   - Groups round two (I502): where the drag happens (the bar preview in Settings, or the list) and what a drop on
     another group does — or leave it for later?
2. **Right after the questions, start at most two subagents** (worktrees, cards in `docs/tasks/`, own target dirs):
   - B127 mechanical parts (Haiku, max effort): `runtime.settings` in doctor's KNOWN_DOCS and the mock, the double-start
     race, a crash clearing `dock`, `settings/test-dock.sh` in the merge set. Not the hover hold (a contract change).
   - W78 (Opus) only if the user said yes and gave a scope; otherwise the hover hold of B127 (Opus; contract change
     authorised by the lead: row + K-id).
3. **Meanwhile, yourself — B128:** a pinned edge dock stays on its output (`crates/kurashi-mod-webdock/src/dock.rs`, the
   paths that set `output`; the dock's window follows `mod.webdock.output`, `mods/webdock/qml/surfaces/dock.qml`).
   A unit test plus a two-output step in a web dock suite. Then the keyboard path from a sidebar into the docked
   Settings (B127; `SideWindow`'s `focusAsks` is the pattern).
4. **~12:00:** merge the agents' branches into one session branch; `just check` and `just suites` (the merge set; only
   a failure alone counts; `quick-modules` is red on `main`, B92); `nix build .#kurashi`.
5. **By 12:45:** push, open ONE PR. Its body is the review: what changed, by the user's points; what was seen on niri
   (shot paths); what the user should look at live after the rebuild (cards on the clicked monitor, site icons, the
   kept bar card, docked Settings, CPU with music); what is not done and why. Update this handover.
Not in this time box (leave in BACKLOG unless time is left): B119/B120 performance, B122/B123/B117/B110 web dock rough
edges, B92, B113, B112/B100, B114, B115, B116, B121, I483.
**Efficiency.** While iterating use `just suites --changed` (never suites one by one); batch builds; Haiku for clear
mechanical cards, Opus only for judgement; do small things yourself; terse agent reports; no idle waiting — review or
fix something while suites run; check `df -h /` before a merge set. Live checks on the user's session are read-only.
**Risks.** B126's fix keys on a press within 1.5 s; a card opened by key still uses the compositor's focused output.
`mods.webdock.site_icons` on means one request per site the page did not make itself (the user asked for the images;
off restores K38's strict proof). Two subagents at most; check `df -h /` before a merge set.
