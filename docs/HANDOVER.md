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

## 2026-11-03 — session 20 (machine A): app templates, sidebars alike + pin, launcher logo, display texture; web dock ad blocking blocked
**State:** local `main` holds everything below, **not pushed** (ahead of `origin/main`; the user decides push/PR).
`just check` and `just suites --changed` green on the final tree. No agent is running; worktrees under
`.claude/worktrees/` (agent-a5bf…, agent-a1455…, lead-sync) can be removed.

**Lesson:** this session began on a stale local `main` (PR #1, W59, had been merged on GitHub). `git fetch` and compare
`main...origin/main` at session start; take new BACKLOG/K/CONTRACT-CHANGE ids from `origin/main` (I351–I365 clashed and
were renumbered).

**Done:**
- K49 amendment 2: theme export for Neovim, Helix, Zed, Firefox, Zen, Vesktop, Spicetify, Obsidian, zellij, fzf (noren's
  picker), Hyprland, MangoWM, sway; switches under "Apps that follow": window frame, see-through unfocused windows
  (+ opacity), window animations (default on), titlebars. Checked by niri validate, Hyprland --verify-config, mango -p,
  nvim and fzf in a test.
- K84: both sidebars offer every section; `sidebar.<side>.pinned` (pin in the header row, or its own row); "Quick
  settings opens the right sidebar" no longer hides a button, plus per-side "button in the bar" switches; desk columns
  `desktop.left/right` pickable (`desktop.cards`).
- K85: `launcher.button_logo` (look · os · own) + `launcher.button_icon`; `os.logo` token from os-release;
  `[decor] start.logo_tint`; PS2 look: original Towers mark, OS logo in four colours. (A Shape gradient draws nothing in
  the bar window: plain rectangles there.)
- W62 (Haiku): texture kind `display` (4 px pixel grid, ink capped for 4.5:1).
- W63 (Haiku): blocked — QtWebEngine 6.11 refuses uBO (MV2) and does not enforce uBO Lite's rules. Options in
  `docs/ux/webdock-engine.md` (I371): the user favours hosting a real browser (their own engine) in the dock, and
  shell-hosted app windows in general (I372).
- `/tmp` cleanup (79 GB of old sandboxes; W59's kept); I375 for removing sandboxes after a passing run.

**Next steps (ordered):**
1. The user: push / PR `main`.
2. W60 + I375 (sandbox isolation and cleanup), then upstream's I364/I365.
3. Prototype I371 option 1 / I372 (a browser or app window placed by niri in a shell surface) — UX brief first.
4. BACKLOG I366–I384 as prioritised (I379, I382 are small; I384 true pixelation later).

**Open decisions:** CONTRACT-CHANGE 693 (web dock ad blocking: interceptor, re-probe, or drop — superseded by I371);
I381 (a dark yorha variant taking `display`); upstream rows 690–692 (W59.6b).

---

## 2026-11-02 — session 19, part 3 (machine A): W59 finished — check + suites green, README previews, PR
**State:** branch `feat/w59-motion-engine` pushed to origin (112 commits over `main`); the PR to `main` is the user's
to merge. `just check` green (1339 tests) and `just suites` 13/13 green on 2026-11-02. No agent ran, no worktree is left.

**Done:**
- `nix/icon-names.txt` regenerated (W59.6b's "compare" string made `check-icon-names` fail).
- `test-sidebars.sh`'s slide part pins `theme.motion.form.sidebar.{open,close} = slide`. Since D4 kami opens the
  column with origami (a formed path, no freeze or rest hooks), all 8 kami cases and the following `none` case failed.
  kami's origami on the sidebar is test-motion's job.
- README previews: 18 forms on the session menu (`docs/media/motion/*.webp`, 1.4 MB total, each ≤ 148 KB). Every frame
  sheet was reviewed: only the session menu, the clock and the generated wallpaper. The 6 forms the README does not show
  (slide, zoom, fade, flip, bleed, stepped) are not committed.
- **Not committed:** the sidebar roll preview showed the login name in the sidebar header (I364, needs W60). The toast
  run filmed no toast (I365). roll/drop/crumple are on the session menu instead.

**Next steps (ordered):**
1. The user merges the PR (`--no-ff` is GitHub's merge commit); then `git switch main && git pull`.
2. W60 (sandbox isolation: own HOME and user), then I364/I365 (sidebar and toast previews).
3. The user's verdicts on origami, phosphor and genie (W59.9 acceptance, PROGRESS UX column); `tools/bench/motion.sh`
   rows on A and B's iGPU (W59.9, not done); then the W59.9 deferred list below and I346–I365.

**Open decisions:** rows 690–692 (W59.6b) still await the user.

---

## 2026-11-02 — session 19, part 2 (machine A): the motion engine built — W59.0–W59.8 merged; finish and open the PR
**State:** branch `feat/w59-motion-engine` (not pushed; `main` = e2bc7d68 on origin after the history rewrite). Merged
into it: W59.0 contract, W59.1 daemon/packs, W59.2 runtime, W59.3 surfaces, W59.4 paper forms, W59.5 genie/crt/drop,
W59.6 Settings page, W59.7 recipes, W59.8a/b fan/noren/pixelate/glitch/dissolve; lead: inert pass, profile_curve, D4
style defaults (kami origami, terminal phosphor, aqua/vibrancy genie), niri `theme.motion.windows = follow`,
`motion.pack.open` + pack-dir live reload, DESIGN-SYSTEM §9. Every form but `liquid` is available. Last full
`just suites` (before W59.3's follow-ups): 11/13 — recipes fixed since; **sidebars USS +11 MiB** (handed to W59.9a).
**User rules this session:** at most **two** agents at once (memory `max-two-agents`); screenshots stay local (I345).

W59.6b (Settings live preview, c8e5ff1c) and W59.9a (liquid; shape forms on toast/dock/sidebar; iris from the press
point; seamless sheet landings; **the sidebar USS leak and the false "grow is unknown" warnings fixed**; a2f43d6c) are
merged too — **every form is available, no agent is running, no worktree is left.** Rows 690–692 (W59.6b) await a
decision. Not yet re-run after the last merges: `just suites` (W59.9a ran it green except settings M10 and
edge-modules, both fixed in a2f43d6c).

**Next steps (short, in order):**
1. `nix develop -c just check` and `just suites` (merge set) — expect green; fix what is not.
2. README previews: `nix develop -c tools/motion-previews.sh` (session menu), plus `MOTION_SURFACE=sidebar … roll` and
   `MOTION_SURFACE=toast … drop crumple`; look at **every** frame sheet in `/tmp/kurashi-motion-previews/review/` for personal
   data (I345) before `git add docs/media/motion/`; README §Motion already points at those files.
3. PROGRESS row; push the branch (ask the user first) and
   `gh pr create --base main --head feat/w59-motion-engine` with a summary of K83 and the previews.

**Deferred (BACKLOG/W59.9 notes, not blocking the PR):** the dock has no FormHost yet (aqua's genie on the dock falls back to slide; toasts do genie), drop's bead ignores `pressAt`, kami's pen outline varies run to run, `tools/bench/motion.sh` (agents measured 1.2–1.6 ms CPU per
frame, idle 0), crumple's mid-frames read as cloth, drop wants ≥ 500 ms and genie ≥ 400 ms curves, fold PSS on kami
(+58 MiB once), I346–I363.

---

## 2026-11-02 — session 19 (machine A): the motion engine planned (K83, W59); screenshot privacy audit
**State:** `main` = the merge of `feat/s19-motion-engine` (docs: the plan; shots untracked). **History was rewritten**
(user's choice, I345): every `*/shots/` path is gone from all commits (`git filter-repo`), and `main` plus the remote
branches were force-pushed, so every SHA in older handover entries is now stale. The pre-rewrite backup is a bundle:
`~/Projects/kurashi-shell-backup-2026-11-02.bundle`. **Machine B and every other clone must re-clone** (or
`git fetch && git reset --hard origin/main` on a clean tree). One subagent ran (the user allowed one): the read-only
screenshot audit.

**Done:**
- Motion engine planned with the user: brief `docs/ux/motion-engine.md` (prior art incl. Hyprland, Compiz, KWin, niri,
  SwiftUI, M3 Expressive; five axes timing × form × choreography × accents × speed; motion packs; 25 forms in two
  families — shape and sheet; curve presets and the custom curve syntax; the Motion page and curve editor; engine
  architecture; budget), K83 with the user's answers (D1 reduce motion = short fades via a `reduced` profile; D2 sheet
  forms keep the hinge joined; D3 the island takes every form and follows the default unless `theme.motion.form.island.follow`
  is off; D4 kami → origami, terminal → phosphor (CRT), aqua/vibrancy → genie on dock and toasts, washi unchanged).
- Cards `docs/tasks/W59-motion-engine.md` (waves + **frozen contract**: schema keys, token shapes, pack format, frontend
  interfaces) and W59.0–W59.9. BACKLOG I346–I350. PROGRESS S19.1.
- Screenshots (I345): the audit found the user's prompt and hostname, the real sysmon process list, the wallpaper folder
  and the installed-app list in committed shots. They are now gitignored (`**/shots/`; `tools/golden/ref*/` and
  `archive/` stay tracked), purged from history and force-pushed. The shots stay on disk for reviews. Card W60 removes
  the root cause: the sandbox keeps the real HOME and XDG dirs.

**Next steps (ordered):**
1. W60 (sandbox isolation) before the next shot-heavy card. Until it lands, don't share sandbox shots outside this machine.
2. W59.0 (lead): the contract exactly as `W59-motion-engine.md` says; push `main`; then spawn W59.1 ∥ W59.2.
3. W59.3 ∥ W59.6, then W59.4 → W59.5, then W59.7 ∥ W59.8, then W59.9 (user verdicts on origami, phosphor, genie).
4. Implementation goes on `feat/w59-motion-engine` (the cards merge into it). When W59.9 passes, open **one PR** from
   it to `main` (the user asked for a PR once the feature is finished). PR body ends with the Claude Code line, and
   commits carry no AI attribution (CLAUDE.md).

**Open decisions:** none for W59.0–W59.6. Later: which offer packs (sumi, pop, liquid, glitch, ember, outline, pudding)
any style should recommend — in the style review (I336).

**Risks:** sheet forms capture a card into a layer while moving — PSS and GPU budget per form must be measured on B's iGPU
(brief §11); niri's grammar for `custom-shader` and `cubic-bezier` must be validated against the installed niri (W59.9).

---
