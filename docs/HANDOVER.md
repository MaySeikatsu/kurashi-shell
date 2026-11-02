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
  forms keep the hinge joined; D3 the island takes every form and follows the default unless `theme.motion.island.follow`
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

## 2026-11-01 — session 18, part 3 (machine A, the user at their niri): depth across the shell, joins, popups — K82
**State:** branch `feat/s18-depth-and-joins` (merged into `main` with `--no-ff` once `just check` and `just suites`
pass on it; see the merge commit). `main` was pushed at a774738f at the start of this part (user's go-ahead); the work
below is **not pushed** — ask before pushing. No agents ran (user: none this time). The user's live session runs the
repo build: kurashid from `target/release` and the frontend from `frontend/` (started detached by the lead, the
session's env); a re-login or a Home-Manager rebuild returns it to their Nix build — they should rebuild from `main`
to keep these fixes and to get the niri layer rule (it rides in the HM-written `kurashi-binds.kdl`).

**Done (K82, BACKLOG I322, I324–I344 rows updated):**
- Elevation reaches the sheet: `SheetShadow` (frontend/shaders/sheet_shadow.frag, analytic inset shadow, dithered)
  in the frame strips and docked bars, each window grown by `Theme.sheetReach` on its inner side, one owner per hole
  pixel (`FG.hole`, `FG.shadowOwn`); floating bars and desk cards at level 2; blocks lift under flat/line/bevel
  (`elevation.blocks`), icons per look (`elevation.icons`).
- One light: under follow a held lamp (spotlight pin, wallpaper lamp) is a point light per surface (`Light.heldLamp`).
  The pointer lamp follows the pointer screen-wide only with niri main (I316); the user's niri 26.04 lacks it.
- Per-style depth: washi/kami follow, material static; STYLE_KEYS now holds every look key + `title_bar.buttons`;
  washi's paper covers shell + wallpaper (I339).
- Fixes the user reported: washi island card hangs from the strip (I337); floating sidebar concentric with the frame
  (I341); shadows clipped at a card's far sides (Elevation's Loader resized its clip box) and at mod tile cells.
- `bar.popups` / `bar.popups_other` (I340): cards come out under the pressed module or at the bar's centre.
- Blur: niri blurs layer surfaces in xray mode → layer rule `xray false` for `^kurashi-` top/overlay in the niri
  include (HM + kurashid writers; validated with niri 26.04); desk cards got a blur region (I322).
- Fluent: Windows 11 caption part; the fluent style ships `title_bar.buttons = off` (I325).
- Gaps: ScrollHost on every list, FrameHost on notification cards and sidebar sections, ProgressLine (M3 form),
  menu rows' `labelX/labelW` (kami underline, sekai key row), desk side, fluent flyout blur, dock hand cursor.
- Infra: the dev shell's `wtype` refuses outside `/tmp/kurashi-sb-*` (I331); test-styles settle points (I333);
  suites updated for the sheet's shadow (test-bars `bar_is`, test-frame shadow check, island-join elevation off).
- Bench (I330): `tools/bench/styles.sh`, BENCH 2026-11-01 — every style 131–133 MiB at one output, idle CPU ≈ 0.

**Next steps (ordered):**
1. The user's style-review session (I336): each family on their niri, verdicts, visual bugs fixed in the same run.
   Raise there: the strength/visibility of K82's shadows per style, `elevation.icons` on washi/kami, the popup setting.
2. Ma at rest (I344): the ~12 wakeups/s in six styles and ~1 commit/s in five; then K82's memory (I342).
3. The remaining family gaps (I324, I325, I327, I328, I332 — see their status columns), the Settings preview of the
   new depth (I343), Settings reconnecting to a restarted daemon (I334).
4. Scale 1.5, ja and high-contrast shots; listen to the sounds and see the cursors on niri (I330's rest).

**Open decisions:** none blocking. The user may overrule K82's per-style defaults (washi/kami follow, icons 0.5).

**Risks:** K82 grows every docked bar's and strip's window by ~25 px of click-through room; a user niri `layer-rule`
with its own shadow on `kurashi-*` would double it (Settings' help should say so — not yet). The HM-written binds file
now carries a layer rule: a user who includes it gets non-xray blur (costlier while windows move behind panels).

## 2026-11-01 — session 18, part 2 (machine A, the user away): every W53 style family merged — K81
**State:** `main` = 43614625 plus the handover fix-up. It is **not pushed**: everything after 4e6237e6 is local, and
pushing waits for the user. Verification on main (after the fixes below): `just suites` 11/11 green on the first try, `just check` green, `nix build .#kurashi` built (`result`), test-styles on niri for kanso/washi/sekai with no QML error.
No agents are running. Every W53 worktree, branch and `~/.cache/kurashi-agents-target/W53.*` build dir is deleted.

**Merged since the first session-18 entry:**
- 875eeecf, 0f0795d5/61b99e6d: W53.0a/0b, the visual system and the personality plumbing.
- d7ee9177: win95.
- 418a7691: the W53 integration (callers host every slot).
- 2d82aaeb: luna/aero.
- 421a28d8: fluent.
- b0978f4f: aqua/vibrancy, including Elevation's knock-out under translucent fills (row 608).
- 25d896ee: snes/ps2.
- bca78169: kawaii/yorha/souls/hallownest.
- 65153590: washi/kami/sekai and kanso/material/glass/terminal.
- 5c670bc8: Watch.qml teardown TypeError.
- 52fc7fad: settings/test.sh K7/K10 waits.
- 8339a722: the bundled packs are parsed once. Every apply had parsed all of them: release 35 → 50–65 ms, debug ~0.9 s.
- 2c559e00: sekai's Keycap scroll part loads in Settings (it used Block).
- 6104036e: the settings test's mods race.

Each family got its own personality, a layout preset (`<style>-desk`), a cursor and a cue set (both off by default).
The Windows styles got a start button. Each family was handed back once with specifics, then accepted on niri shots
(`frontend/shots/styles/<style>/`). CONTRACT-CHANGE rows 590–623 are accepted as K81. PROGRESS S18.5–S18.5f.

**Next steps (ordered):**
1. Ask the user to look at each family on their own niri and collect their verdicts. Two things to raise:
   - washi, the default style, now carries a paper grain (K81). One key undoes it: `theme.texture.kind = "none"`.
   - I322: blur on the user's niri. They will report on this build.
2. Push `main` once the user agrees.
3. Close the family gaps, one card per family (I324–I328 and I332).
4. Measure W53 (I330): `just bench` per style, scale 1.5, ja and high contrast for the Windows and macOS families, and
   listen to the sounds and see the cursors on niri.
5. Fix the test flakes (I333) and the test infra (I329), and guard wtype in `niri-sandbox.sh` (I331).

**Open decisions:**
- fluent's title slot is `""`, so the title-bar switch does nothing under fluent (I325). Draw Windows 11 caption buttons,
  or keep the switch inert with its reason?
- washi's grain on by default (K81): the user may overrule it.

**Risks:** the W53.3 wtype incident (I331). 7 key events may have reached the user's focused window on 2026-10-30.

---

## 2026-10-29 — session 18 (machine A): the kami fillet, today's bugs, corners, the pointer light, elevation, the styles wave started — K78–K80
**State (updated 2026-10-30 ~01:10):** `main` = 61b99e6d (pushed up to 4e6237e6; later merges **not pushed**): W53.0a
(visual system) + W53.0b (personality plumbing) + high contrast keeps a bevel (row 590) + cursor decor keys (row 593);
`just check` green (1284+). **Agents running:** row 591 (callers adopt the decor hosts, start-menu skin row 563, mock
parity row 565, effects-sheet bench) and **W53.1 win95** (the first family, 1:1 with Windows 95/98). When 591 lands on
main, tell the win95 agent (SendMessage) to merge main and verify end to end. Then the families in pairs: W53.2 luna+aero,
W53.3 fluent (new), W53.4 aqua+vibrancy (new), W53.5 snes+ps2, W53.6 fiction, W53.7 japanese, W53.8 modern — each
reviewed against its original on niri shots before merge. The user's standing order: finish the styles at their best,
prepare a build, write the summary, then suspend the PC (`systemctl suspend`).

**Merged this session:**
- s17 branch finished: kami's fillet ink came from the sketch's second pass drifting to one side (0.7–1.3 px) across
  the column's hidden edge segment, and open lines overshooting their ends; the light pass is now one path (the column's
  first frame stalled: sketch doubled every pen canvas). I315 = a residual later first frame under kami.
- I305 (user: a gap): the strip's rule breaks under groups floating with a shadow and under the island pill.
- I306: the mock's theme document = the real resolved token set under its Wa-iro colours.
- W56: `RoundBox` (+`RoundPen`) — squircle corners where visible boxes were Rectangles (Stage cards, phone, dock
  tooltip, notification/desk cards, Settings' SectionCard/navigation/Button/TextField/Select/Segmented/ChoiceSwitch;
  linked into `settings/components`); relief.frag's box is a superellipse through the cubic's midpoint; SquircleRect
  strokes its border on the centre line (no speck where a corner meets its side). I269: notification cards concentric in
  the sidebar and the centre; desk and media art nested.
- W58 (K79): niri main has cursor sessions (niri#4554) → no patch. `svc.pointer` (kurashid, `kurashi-compositor/src/
  pointer.rs`, refcounted, ≤ 1 patch/16 ms, nothing at rest; waits for a seat pointer); Light prefers it, its sensors
  stay the fallback; Settings' light dial says which. Flake input `niri-main` (849c576) used by
  `programs.kurashi.pointerLight.enable` (mkDefault `programs.niri.package`). Measured: niri main end to end, 26.04
  `pointer.no_protocol`, sway globals present (headless seat has no pointer).

**Decisions:** K78 (elevation: the shell draws all, light shell-wide, pointer-follow as an option, band casts key-only
onto windows, soft/keycap on by default, separate strengths), K79 (cursor sessions from niri main, fallback kept, back to
a release asap — I316), K80 (styles: lock faces follow the style, dress-only + opt-in layout preset per style, title bars
with configurable buttons — minimize may open the app's bar menu —, free font stand-ins, sound sets for every style,
high contrast keeps bevels, the design system grows per style incl. animation styles/curves, icons, materials, bloom;
a start button for Windows styles; cursor theme + trail per style, off by default — I317).

**Next steps (ordered):**
1. Ask the user to push `main`. I296 and I309 are fixed (reproduced on niri with blur: both were blur regions niri filled
   with the blurred wallpaper over a lower layer); **I298** still open (not reproduced; likely the user's GPU) — ask for
   steps or test on machine A's GPU.
2. W55: when the agent reports, re-run its suites alone (no other runner active, I319), diff its `fail`/`check` lines
   against main (nothing weakened), then merge. Fix I319 (a per-runner sandbox suffix) with or right after it.
3. W57 slices 1–2 are merged (sidebar, Stage card, notification centre, floating dock, launcher card, polkit, Settings
   preview). Next: toasts, the launcher's morph, the bars and the frame band (the hole's inset shadow in screen coordinates, key-only onto windows,
   window margins outside input/blur/exclusive zone); Settings' live preview + inert reasons; idle 0 frames with
   elevation on (frame idle check, bench); shots per mode × chrome on niri. Check `Elevation.centre` while a column slides
   with `elevation.pointer` on (it is re-evaluated only on Light changes).
4. W53: review and merge W53.0a + W53.0b (agents), then the family cards W53.1–8 (`docs/ux/styles.md` "Card split")
   in parallel worktrees — two agents at a time (the user's allowance this session).
5. Later: I312 effects sheet (cursor trails build on it), I313 lighting as a module, I304 layer order, I315, I318.

**Risks:** an unreleased niri for pointer-light users (check releases, I316); elevation's two RectangularShadows per
surface are unmeasured against BENCH; the W53 wave is large — keep the system card first.

---

## 2026-10-29 — session 17, part 3 (machine A): outlines in general, Settings on the shell's Theme, cards for corners, shadows, the light
**State:** branch `feat/s17-frame-ink` (on top of `main` 0e0f3adb+) is **not merged**. Its full check run finished:
`just check` green (1254 tests), 13 of 15 suites green (the merge set + pen, look, settings texture). Two failed alone too:
- `frontend/test-sidebars.sh` — **from this branch** (green on main): under kami, "the fillet (231, 231, 231) is the bar
  strip's colour (247, 244, 236)" for top-kami calm/lively left/right, plus "open 40 ms: p=1.003/1.096" in kami lively.
  Most likely kami's new sketched ink on the joined column (ColumnShape `penOn`/`oc` with `pen.line = sketch`, or the
  sketch's second pass/overshoot landing on the sampled fillet pixel). **Fix before merging.**
- `settings/test-sheet.sh` "the spotlight does not follow the pointer over the sheet" — **fails on main too** (I314),
  older; not a blocker.
Logs: `/tmp/kurashi-suites/s17-settings/` (summary.txt) and `/tmp/kurashi-lead-logs/main-{sidebars,sheet}.log` (main). A package of the
branch was built (`nix run .` from the checkout runs it); `main` and its package are part 2's. Nothing pushed.
The `nix run .` regression of part 1 (passthru `bin` → the app ran the unwrapped daemon) is fixed on `main` with a flake
check (`apps-wrapped`).

**On the branch:**
- Outlines in general (user): `theme.outline_ink` (outline | text | accent → token `outline.ink`; `Theme.outlineColor`
  honours it everywhere, kami's sketch decor too); `theme.pen.line` gains `sketch` (pen.js, kami's two light passes);
  kami's recipe: text + sketch. `theme.frame_outline` still decides whether the frame and the bars' inner edges get a line.
- Settings: `settings/core/Theme.qml` and `Glide.qml` are links to the shell's (one Theme: Settings follows every token);
  the sheet grows down from its top edge on the profile's motion (Caelestia's curves under expressive), the window's
  content fades/slides in; pages scroll kinetically (`KineticWheel`) with a grabbable `PageScrollBar`; the navigation is
  framed as the section cards. UX brief: `docs/ux/settings.md` "Opening, scrolling and the navigation's frame".
- Tools: `niri-sandbox.sh` starts from an empty sandbox dir and has `wheel`; `test-suites.sh` adds named suites to
  `--changed`.

**Next steps (ordered):**
1. Finish the branch: fix the kami fillet in `test-sidebars` (see State; compare on niri with `niri-sandbox.sh`, look kami,
   chrome line, the right sidebar's top fillet, against main), then `just suites sidebars` + `just suites --changed main`,
   `just check`, merge `--no-ff`, `nix build .#kurashi`, ask the user to push. The sheet spotlight (I314) is older.
2. Bugs found today: I309 (kami: the island card's head shows the wallpaper across the bar — main too), I305 (keycap
   frame outline under grouped bars looks heavy), re-check on the user's niri I296 (sidebar band with blur) and I298
   (dock texture after a Sheet change: a guess is in), I304 (layer stacking by map order), I306 (mock tokens), I308 (pen
   idle flake; W55 should settle it).
3. W56 corners (I288 squircle on every visible shape incl. relief.frag's box; I269 concentric rest) — `docs/tasks/W56-corners.md`.
4. W57 elevation shadows (I310; the user wants them smooth: layered ambient + key, no banding) — UX brief first,
   `docs/tasks/W57-elevation-shadows.md` (static via niri layer-rule shadows vs client-drawn for follow-light).
5. W58 the pointer light across the screen (I311) — `docs/tasks/W58-pointer-light.md`. **Decided (user):** the Wayland
   cursor protocol (ext-image-copy-capture cursor sessions) in kurashid; niri 26.04 lacks it → a patched niri through the
   flake, switched on by the modules only while the pointer light is on; lighting becomes a module later (I313). The effects sheet (I312:
   ripples, trails, waves) builds on it later.
6. W55 fast suites, W53 styles (I294 first if style edits pile up), I280, I284/I285.

**Rules in force (CLAUDE.md, memory):** niri is the lead platform for every visual check; suites via `just suites`
(`--changed` while iterating); no subagents unless the user allows one.

**Risks:** Settings now shares the shell's Theme file — a Theme change reaches both apps (Settings-only members are at
the end of it). Schema v7 keys were renamed on this branch before release (`frame_outline_ink/stroke` → `outline_ink`
and `pen.line = sketch`); a config that set the old keys on the branch reads them as unknown.

---
