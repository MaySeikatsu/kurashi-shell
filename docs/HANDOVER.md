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

## 2026-11-07 — session 24, after the merge (machine A): the web dock, strong shadows, the light across monitors, Zen's other stylesheet, handwriting
**State.** #11 to #17 and #19 are merged. Five stacked PRs wait, each on the one before: `fix/s25-hand-outlines` → `fix/s25-sheet-artifacts` → `feat/s25-light-outputs` → `fix/s25-zen-other-imports` → `feat/s25-handwriting`. Worktrees `../kurashi-wt-radii` and `../kurashi-wt-hand` hold them, with `CARGO_TARGET_DIR` `~/.cache/kurashi-agents-target/radii` and `.../hand`: remove all four after the merges.
**Built.** The web dock's host starts again (#19). I439 K103: a handwritten font crash-looped the shell (a `3` whose pen doubled back segfaulted Qt's distance fields); outlines are simple polygons now (`i_overlay`), old fonts are made again at start, and the user's `Emmi 1` is out of their mix until the fix is in (put it back after the rebuild). I435: a blur region follows its strip (`FillRegion`), one light vector per output for the sheet, windows keep `Theme.elevReach` as room, `CardJoin` opens the rule and cuts the sheet's shadow under a translucent card. I436 K101: `theme.light.outputs`. I437: Settings names other stylesheets in a linked profile and turns them off. I438 K102: handwriting's settings, `panel_place` for any mod, Open in Settings and a launcher row for any mod's panel, a widget. A race in `LayoutProvider::start`: the output list was read after the document was written, so an output arriving between them was never named.
**Learned.** `Region { item: … }` does not follow an item that moves. grim can catch the cursor where it crosses into a neighbouring output's crop. A sandbox with no subscriber on a service document shows the last document, so a suite keeps a subscriber while it reads. A session locked by idle stays locked through a daemon restart (K20, the `locked` marker), so a swap of the live shell can come up on the lock page: check `$XDG_RUNTIME_DIR/kurashi/locked` first. A stylesheet left in a browser profile by another shell looks like a failed link: read the computed styles over Marionette (`MOZ_REMOTE_ALLOW_SYSTEM_ACCESS=1`, `--marionette`), never guess.
**Not verified.** `theme.light.outputs` with the user's real pointer (the virtual pointer tool refuses a real session; the two-output suite covers it). Zen on the user's profile after Turn it off. Settings' Open buttons were seen on nested niri, not on the live session, and were not clicked there. `test-dock` still fails three checks from before session 24 (I434). Pen pressure and kerning are not built (I419).
**Open for the user.** Turn it off in Settings › Apps that follow, and restart Zen. Inward on desktop widgets, after their test. I424: the launcher's rows moving, confirmed, waits for their go. Leftover sandbox processes (I432): the permission check refused killing them, the user decides.
**Later the same night.** #20 to #24 merged. `feat/s25-terminal-fonts` (K104, I441) went to `main` directly, as the user asked: `theme.typography.mono` (kami: Monaspace Radon, now among the shipped fonts) and the opt-in for the terminals and the desktop's monospaced font, widened after to `theme.export_fonts` (K105: every app that can take the shell's font; Websites too forces it on pages; Spotify and Zed keep theirs). The browser tile got its own strength (I445). The mix for GTK/Qt apps is an idea only (I442). Zen still waits on the user's Turn it off (Appearance › Colors › Apps that follow, then restart Zen).
**Next steps, in order.** 1. The user merges the stack and rebuilds; Emmi 1 back into the mix. 2. I424 on their go. 3. I440 (a safe mode after a font crash loop), I432, `test-dock` (I434). 4. The earlier entry's steps.

## 2026-11-07 — session 24 (machine A): recipes on windows, frame colour, matching corners, the sheet's shadow, corner merges, terminals, Zen
**State.** Seven stacked PRs, each on the one before, none merged; merge bottom up: #11 `feat/s24-recipe-shaders` → #12 `feat/s24-frame-colour` → #13 `feat/s24-surface-radii` → #14 `feat/s24-sheet-shadows` → #15 `feat/s24-popover-joins` → #16 `feat/s24-terminals` → #17 `feat/s24-zen`. `just check` is green on each; the merge set ran on the tip only, and every suite passes alone. If a lower one changes, rebase the rest with `git rebase --update-refs`. Worktree `../kurashi-wt-radii` holds the tip, with `CARGO_TARGET_DIR=~/.cache/kurashi-agents-target/radii`: remove both after the merges. `.git/info/attributes` sets union merges for DECISIONS, BACKLOG, PROGRESS and PROTOCOL: union keeps both sides of a status change in BACKLOG, so check for a doubled row after a rebase.
**Built.** I418 K95 (a recipe's shader from its tracks). I423 (`theme.window_frame_color`). I426 K96: the hole's radius is the radius you set, the outer corner it plus the band; `radius.{frame,join,window,widget,dock}`, `theme.shape.radius_*`; K74 gave the frame's corner 0 under washi with a 10 px band. I427 K97 (`theme.material.sheet_shadow`). I428 K98 (Stage cards and the launcher at a button merge near a corner in dynamic: `MorphShape.edgeL/edgeR`, `components/JoinedCard.qml`). I420 K99 (`theme.texture.terminals`, targets wezterm, rio, ratty, `targets[].material`). I422 K100 (`browsers.rs`, `theme.export.link`, Zen's layers). Six new suites joined the merge set: corners, sheet-shadow, popover-joins, window-frame, terminals, browsers.
**Learned.** Zen sets its background variable inline on `.zen-browser-generic-background`, so `:root` can never win. An extension's `browser.theme.update` runs unsigned in Zen with the pref and does not reach its chrome. Rio 0.5.28's `background-image` draws over text. Foot 1.28 refuses `[colors]`, so the shell's foot theme had been refused. On nested niri a config with modules on a bar-less edge makes them edge modules, and a module's menu then opens elsewhere: keep those zones empty in suites. Run `just check` per branch before a stack goes up: on the tip alone it hid a stale `nix/icon-names.txt` and a formatting miss that lower branches would have merged with. The sheet's shadow darkens the desk beside a band, so a pixel check for "desk" there sees ink: that check turns it off.
**Not verified.** Anything on the live session; translucent pages; Firefox's toolbox tile; Hyprland, MangoWM and sway running the frame colour file; Alacritty running its file; PSS of the wider frame strips (BENCH); a recipe with a real long translate on a tall window beyond the contact sheet.
**Open for the user.** (1) Their Zen profile: `Link` in Settings › Apps that follow, once they say so; nothing has been written to it. (2) Whether "Inward" means what K97 took: even, no direction, into the hole, as Caelestia's offset 0. (3) Should kami turn the Handwriting mix on by default: ask once they have seen it. (4) I430: 914 `config.tmp.*` in `~/.config/ghostty/` from a tool of theirs, left alone.
**Next steps, in order.**
1. The user merges the stack; fix what review finds; rebase with `--update-refs`.
2. Ask (1) and (2) above.
3. I424: the launcher's rows moving while typing as Caelestia's (confirm what they mean first: it reads `modules/launcher/AppList.qml`'s transitions); I425 idea.
4. I419: handwriting after the prototype. I421 stays an idea.
5. The quick panel's phone frame under dynamic (I428's note); I429 when Rio changes.

## 2026-11-06 — session 23, end (machine A): handwriting prototype (I415, K94), and what is next
**State.** Three stacked branches. `feat/s23-niri-motion` is PR #6. `feat/s23-font-mix` sits on it, `feat/s23-handwriting-mod` on that; each is its own PR, and the user merges. If a lower one changes, rebase the ones above.
**Built here.** `mods/handwriting`, `crates/kurashi-mod-handwriting`, `docs/ux/handwriting.md`, `mods/handwriting/test-handwriting.sh`. Off by default; enable it on the Mods page. Open with `kurashi act mod.panel.open '{"id":"handwriting","panel":"handwriting"}'`.
**Not verified.** A real pen; a whole alphabet drawn by a person; the panel on the user's session.
**Next steps, in order.**
1. I418: shaders generated from a user's recipes for niri's windows (`crates/kurashi-motion/src/recipe.rs` has the tracks; `crates/kurashi-theme/src/niri_forms.rs` the frame). The user wants it if it is quick.
2. I423: the window frame colour setting.
3. I420: terminals, with the `theme.texture.terminals` switch.
4. I422: Zen. Ask the user about their profile once it is ready to test; never hardcode one.
5. I421, I419 afterwards.
6. Sandboxes: delete `/tmp/kurashi-sb-*` with no live process (the user agreed), and the build dirs under `~/.cache/kurashi-agents-target/`.
**Risks.** Do not edit `frontend/` or `settings/` in a tree whose suites are running: the frontend reloads itself on a change and a suite fails for no reason. Nested niri stops redrawing after a screencopy: turn previews off in a visual check with animations.

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
