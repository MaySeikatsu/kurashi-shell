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

## 2026-11-06 — session 23, the font mix (machine A): I176, K93
**State.** `feat/s23-font-mix`, stacked on `feat/s23-niri-motion` (PR #6). Not pushed: the user decides. The worktree it was built in lived in the session's scratchpad and goes with it.
**Built.** `theme.typography.mix.{preset,count,fonts}`. kurashid builds one font holding the chosen fonts' letters (`kurashi_theme::font_mix`, cache `kurashi/fonts/mix-<hash>.ttf`), `calt` moves on a font per letter and starts over per word, and `Theme.families` takes it through a `FontLoader`: no text component changed. New page Fonts, with the comparison card on top. Patrick Hand, Handlee, Gochi Hand in `nix/handwriting-fonts.nix`. Brief `docs/ux/fonts.md`. The plugin idea is I415.
**Verified.** Nested niri on kami; `frontend/test-font-mix.sh`; builder tests shape text through `harfrust`.
**Not verified.** The user's own desktop; fonts with CFF outlines or variable axes beyond what the preset uses (the code handles them, no test font does); the greeter (I416).
**Next steps.** 1. The user reviews the look and says whether `kami` turns the mix on by default (left off). 2. PR after #6. 3. I415, the plugin.

## 2026-11-06 — session 23, last (machine A): forms on niri's windows (K91), hover previews (K92), the island's menu
**State.** `main` has session 23's earlier work (merged at 6d751b0f, the user waived `island-join`, I406). This entry's work is on `feat/s23-niri-motion`, in a PR the user merges.
**Built.**
- `theme.motion.windows = forms` (default stays off): every shell form as a generated niri custom shader on window open and close, `crates/kurashi-theme/src/niri_forms/`. `window` is a thirteenth surface class. Brief `docs/ux/niri-motion.md`. The three repos the user sent proved the hook; no code taken from them.
- The island's right click opens its menu: the pinned face and a check to take it back, "Pin a face", its faces and options. The pin moved to the middle click (`island.main.input.middle`). `island.pin {face}`. A user config that binds `right` keeps its own.
- Hover previews, last-seen stills: `svc.previews`, `crates/kurashi-compositor/src/{capture,locate}.rs`, `crates/kurashid/src/previews.rs`, `frontend/components/PreviewPeek.qml`. On by default per module (`modules.{windows,workspaces}.previews`). Brief `docs/ux/hover-previews.md`.
**Found.** niri does not say where a tiled window stands (`tile_pos_in_workspace_view` is floating only), so `locate` reads the scroll and the gap from the still's edges and gives no crop when unsure. `ext_image_copy_capture` is not on this niri: `wlr-screencopy` is (a new crate, `wayland-protocols-wlr`). Nested niri's output is `Flipped180`, so a capture must honour the output's transform. Nested niri compiles shaders with the real NVIDIA compiler: its messages say so. **Nested niri stops redrawing after any screencopy until something damages it** (plain `grim` with previews off does the same; a close animation froze for about 20 s): `src/backend/winit.rs` redraws through the host window's frame callback, `tty.rs` from its vblank, so a TTY session should not do this, but that rests on reading the source. Visual checks on nested niri with animations want previews off or a redraw; `test-niri-motion` turns them off.
A `svc.previews` patch made every surface draw a frame, since any patch reassigns `Store.docs`: it lives in `Store.quiet` now; the wider cost is I417.
**Verified.** Nested niri on the GTX 1060: contact sheets of all 24 forms at four progress values; `frontend/test-niri-motion.sh`, `frontend/test-previews.sh`, `frontend/test-module-menu.sh`, both new suites in the merge set. `just check` green. `just suites`: 18 of 18; `sidebars` failed under load (a timing and a memory check) and passed alone.
**Not verified.** No real session: the user's niri has not run these. Crops on a real desktop with their wallpaper and window frames, on two outputs and at a fractional scale; only unit tests cover several outputs' logic and 90° transforms. A round's cost on the GPU (I414). Seen once on the user's live session (kami's fold at a slow pace, 2026-11-06): it runs on through captures, and showed a bug the sandbox could not: with a window shadow in the layout the fold painted that shadow over the whole shader area, now fixed and in `test-niri-motion`. Close animations were compiled and one was drawn (iris); the sheets show the open direction, which the close runs backwards. Every form's feel at speed, since only stills were judged.
**Next steps.**
1. The user merges `feat/s23-niri-motion` and rebuilds, then sets Settings › Motion › Window animations to "Follow the profile, with its animations". Their config has `windows = "follow"`, so nothing changes until then.
2. Tune forms on the real session: durations on big windows; yorha's `glitch`.
3. I412 (genie toward a bottom dock), I413 (crops on sway and Hyprland), I414 (default and GPU cost), I409, I411, I387, I389.

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
