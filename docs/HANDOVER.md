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

## 2026-11-06 — session 23, later (machine A): launcher placement (I407), module menus (I408, K90)
**State.** Merged to `main` with `feat/s23-quick-wins` (2026-11-06). The user waived `island-join` for this merge (I406: it fails under
load and passes alone). `just check` green on the merged tree.
**Built.** `launcher.place` (opened, centre, island, fixed; by key in the middle, by click at the button). Every module on a bar or
frame opens its own menu on a right click, from `#[kurashi(module = "<id>")]`, in the Stage's `tray` panel (`module:<id>`).
New options `modules.workspaces.{empty,marks,scroll}`, `modules.windows.{max,middle_close}`. Briefs `docs/ux/module-menu.md`,
`docs/ux/launcher.md` "Where it opens". New suite `frontend/test-module-menu.sh`, in the merge set.
**Verified.** Nested niri (kami, aqua; top, bottom, left bars). `just suites`: 16 of 16, `island-join` failing under load and passing
alone (I406). `just check` green but for the icon list, regenerated since and rechecked alone.
**Not verified.** The dock's launcher tile opener has not been clicked in a test. Keyboard in the menu: tested on sway after a click on
the card; a layer with on-demand focus takes no keys before that there, not checked on niri.
**Next steps.**
1. The user picks a route for the hover previews (I284, I285). The recorded route is out: niri's `screenshot-window` overwrites the
   clipboard. Candidates: last-seen stills cropped from whole-output screencopy (no clipboard; stale, and nothing for a window never
   seen); per-window PipeWire cast through niri's ScreenCast D-Bus (live, heavier, not tried); wait for toplevel capture in niri.
2. The user decides the island's right click (I408): keep pin, or the module menu with pin as a row.
3. I409 (launcher in a sidebar), I410 (the motion styles on niri's windows through custom shaders), I411.
4. `/tmp/kurashi-sb-*` still holds many old sandboxes: the user decides.

## 2026-11-05 — session 23 (machine A): the dock's texture (I298), dev shell on Qt 6.12, the user's list from session 22
**State:** `feat/s23-quick-wins`, pushed; the user merges the PR themselves (gh here is a work account: use the compare URL). Their live session runs the installed shell again, config back as it was; it needs a rebuild to get any of this.

**Done:**
- I298, the dock losing its texture: a window's scene graph starts anew on each map and a non-live copy is not drawn again (K89). Reproduced and fixed live on the user's GTX 1060, on kami and washi; `test-dock` fails without it. `StillCopy` replaces every other still copy.
- I397 lock bump (Qt 6.12, Quickshell 0.3.2). B43: a Hyprland that reads `-c` as Lua counts as no checker, so its keys file is written again; `hyprland.conf` at its default path still loads as hyprlang, so **Lua output is deferred** (user). mango 0.18's renamed keywords.
- I399 `theme.colors.media.apps`, I390 reduced motion fades (dock, bar), I386 maximize keeps the card, I392, I393, and three binding loops Qt 6.12 reports.
- I395: peek, pen, morph green, all stale tests.
- User's verdicts: Spotify and Wallpaper Color Grade work as intended; the updated animations are fine; the web dock's motion waits for an overhaul (I402, I391, I394).
- **Lost:** the `wallgrade-proto` worktree was removed with `--force` before looking at its uncommitted files; the prototype was never committed, so its code is gone (K88 is the shipped version).

**Next steps (ordered):**
1. The user merges and rebuilds, then judges the texture on their dock (hover it more than twice) and the new "Apps follow too" switch.
2. I404: Qt 6.12 budgets on a quiet machine; no BENCH numbers yet, and the web dock's reveal cycles are over their budget on main too.
3. I406 (flaky island-join case), I405 (one texture check), I403 (web dock's bar widget in its test).
4. I387 (shape forms on non-morph launcher and centre), I388 (needs a decision: where a start menu pours from), I389 (drop's 1 to 2 frame gap): looked at or left, not done.
5. Session 21's remaining list, then the unprioritised `new` rows.

**Checks:** `just check` green. `just suites`: 14 of 15 steady; island-join is flaky (I406): it failed alone in one full run and passed alone in the last. 11 of those last ran one small commit earlier (the size cache's write in `Stage.qml`); island-join, quick-sections, stage and motion ran on the final code. test-texture and webdock test-dock are outside the merge set and still red (I405; I403, I404).

**Open decisions/risks:** I404 is unexplained and stays red rather than loosened. I386 makes a titled card's window output-wide while it is open: within noise on software GL, not measured on a GPU. Rule from the user this session: prototype and debug in QML first, the proper implementation after verification; no subagents were used at their request.

---

## 2026-11-04 — session 22, later (machine A): Wallpaper Color Grade (K88), Spotify covers (B44)
**State:** `feat/s22-wallpaper-grade`; the user merges the PR themselves (gh here has only a read-only work account; use the compare URL).

**Live state on machine A:** `kurashi-wallgrade.service`, the prototype, runs from `.claude/worktrees/wallgrade-proto` (a process with a shader on the background layer; `wg stop` ends it). Stop it once the real one is installed, or the two stack. Then remove that worktree, `.claude/worktrees/wallpaper-grade` and `~/.cache/kurashi-agents-target/s22-grade`.

**Next steps (ordered):**
1. The user merges, rebuilds, runs `wg stop`, turns on Settings › Appearance › Wallpaper Color Grade and judges it (mode, fade) on their wallpaper, with Spotify too.
2. B43 still red in `just check` (Hyprland 0.57); I397 (dev shell on Qt 6.11); I399 (apps on a recolour per track).
3. Session 21's list below.

---

## 2026-11-04 — session 22 (machine A): kinetic wheel back under Qt 6.12 and on every scroller (B42, I396); Dynamic Media Color (K87)
**State:** `feat/s22-media-theme` (holds `feat/s22-kinetic-wheel`) is pushed; the user opens and merges the PR themselves (gh is logged in only as a work account with read access, so use the compare URL). The user waived B43 for this merge.

**Done:**
- B42: the rebuild of 2026-11-04 (generation 1178) moved the installed shell to Qt 6.12.0 / Quickshell 0.3.2, which report a `pixelDelta` with a wheel notch; `KineticWheel` took that for a touchpad (15 px, no glide). It now reads `ev.phase`. Measured on 6.12 and 6.11: 156 px per notch with a glide, 1:1 for simulated fingers.
- I396: `KineticWheel` moved to `frontend/components/`, on the launcher (which had no wheel scrolling), wallpaper, Wallhaven, sidebars, notification centre, tasks, AI, lyrics and Settings' dropdowns. Launcher checked on nested niri with Qt 6.12; the others only through the suites.
- `wl_pointer.py finger`; a wheel step in `settings/test.sh`.

- K87 Dynamic Media Color, on `feat/s22-media-theme` (holds the kinetic wheel too): `kurashi_theme::media_tint`, `theme.colors.media.*`, `frontend/core/ColorBlend.qml`, `frontend/test-dynamic-media.sh`. The Now Playing card keeps its behaviour (user).
- I375: 402 sandboxes (180 GB) filled the disk mid-session and were deleted with the user's yes. A green `just suites` now clears its own; `sandbox.sh start` clears those a day old.

**Live state on machine A:** the user's session may still run the prototype: `kurashi-proto.service` from `.claude/worktrees/media-theme-proto` instead of `kurashi-frontend.service`. `.claude/worktrees/media-theme-proto/mt revert` goes back. That worktree (`feat/s22-media-theme-proto`, uncommitted) and `media-theme` can go once the real one is installed.

**Next steps (ordered):**
1. The user merges the PR and rebuilds, then stops the prototype (`mt revert`). They feel the wheel on their real mouse; a real touchpad on machine B. They judge Dynamic Media Color on their apps (I399) and in `keep`.
2. B43: `just check` is red on two Hyprland tests, on code unchanged from main: the user's Hyprland 0.57 reads its config as Lua. Pin or skip in the tests, and the adapter needs Lua output; the merge rule needs this fixed or the user's waiver. I397: the dev shell is still Qt 6.11.2, so the suites do not run on what the user runs. Bump flake.lock and run the merge set.
3. Then session 21's list below: the user's motion verdicts, I390, I394, I391, I395, I386–I389, I392, I393.

**Checks:** `just suites` 14/14 on the commit before the last small fix (sidebars and island-join only under load; settings failed on the Tab limit its new rows raised, fixed, then green alone). The last fix (K87 stage before the material, a daemon-start check) reran only test-dynamic-media and `just check`; it acts only with the switch on.

**Open decisions/risks:** the installed shell needs a rebuild to get this. Any other Qt 6.12 regression would not show in the suites until I397.

---

## 2026-11-03 — session 21 (machine A): motion polish — every form everywhere, pace, three tiers, a style's own animation (K86, W64)
**State:** branch `feat/s21-motion-polish` (from `origin/main` after PR #1 and session 20), **not pushed**; the user decides
push/PR (gh is logged in only as a work account: last time the user opened the PR from the compare URL). `just check`
green, `just suites` (merge set, 13/13) green after the W64 merge; test-motion-hosts and webdock's test-dock run separately.
No agent running; the W64 worktree and its target dir are removed (agent-a5bf… from session 20 can go too).

**Done (the user's eight points, brief `docs/ux/motion-engine.md` §8/§12, K86):**
- Every form but liquid serves every surface (`forms.rs`); W64 made the dock (sheet forms, genie from its edge), the bar's
  hover/empty-desktop reveal and the web dock's overlay card/panels actually host them; host links in `mods/webdock/host/`.
- A form's `pace` (drop 1.9×, genie/noren 1.5×, fold/book/fan/crumple 1.4× …) stretches the profile's curves (`curves.js`
  `stretch`), in the shell and the preview.
- Stutter after a form lands: MorphSprings' `snap()` left a stale timed travel (the sysmon width jump); the launcher's
  first-frame flash (slide/fade under a sheet form, raw card at p = 0) fixed; maximize moves on the profile's curve.
- Motion page: nav icon; three tiers — Profiles (full packs; speed moved into the preview stage, replacing ½×/¼×),
  Animation style (forms table) + **Timing preset** (`theme.motion.timing.preset`, `motion.timings`), Advanced curves.
- Each style's own animation (yorha pixelate, souls dissolve, win95 outline, snes stepped pixelate, aqua genie, kawaii
  stamp, hallownest bleed, ps2 iris, luna slide, sekai pop, glass liquid, kanso new pack).
- Sheet closes keep their content to the end; genie's shadow/fillets follow the pour on joined surfaces; the raindrop's
  new story (gathers from the clicked module, bulges, falls accelerating, squashes, ripples).
- Tests: settings M1 section order, M8b on a user `still` pack (win95 moves now), M8c with liquid on the bar; the sidebar
  logs `sidebar-rest` when a form lands it.

**Next steps (ordered):**
1. Ask the user to push/open the PR for `feat/s21-motion-polish` (compare URL `main...feat/s21-motion-polish`).
2. User verdicts on niri: the raindrop's new story, the default paces, each style's animation (yorha, aqua, kawaii).
3. I390 (reduce motion fades on the dock and bar), I394 (web dock strip waits for the card), I391 (WebCard via FormHost).
4. I395: the suites outside the merge set that fail on main (peek, texture, morph, pen, webdock bar click) — alone, fix
   or retire. Consider test-motion-hosts in MERGE_SET (its USS slack is noisy under load).
5. I386 (morph maximize vanishes 2 frames), I387–I389, I392, I393.

**Open decisions/risks:** pace factors are the lead's taste, not the user's yet; timing presets are hidden under still
profiles (by design, the row says why). Shots stay local (I345: the sandbox shows the real login name).

---

