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

## 2026-11-01 — session 18, part 2 (machine A, the user away): every W53 style family merged — K81
**State:** `main` = 65153590 plus this docs commit. It is **not pushed**: everything after 4e6237e6 is local, and
pushing waits for the user. Verification on main: VERIFY_LINE.
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

## 2026-10-29 — session 17, part 2 (machine A): the user's niri review, schema v7, the test workflow — K77
**State:** `feat/w54-schema-v7` (one subagent, card W54) and `feat/s17-review-fixes` merged into `main` (`--no-ff`), **not
pushed** (push when the user agrees; part 1 and session 16's merges are unpushed too). `nix build .#kurashi` run on the
merged `main` (306 s: Rust changed, deps cached). Config files migrate to schema v7 on the daemon's first start.

**User rules (new, in CLAUDE.md and memory):** niri is the lead platform for every visual check
(`tools/bench/niri-sandbox.sh`: niri nested in the invisible sway sandbox, real blur); suites run in parallel with
`just suites` (`--changed` while iterating; a failure re-runs alone, only that counts) — never one by one.

**Merged (K77):** blur regions from numbers following the drawn shape (morph cards, peeks, dock/sidebar slides, dock
tooltip/menu, task list popups) · the dock's overshoot keeps its foot on the band · the frame draws joined fillets' tails
on its rule row; a docked bar carries the frame's rule over its body · schema v7: Solid/Translucent (+ blur, default off),
`theme.shape.squircle` → `shape.squircle_k`, `theme.frame_outline` → `frame.outline` (auto: keycap, line), hover sidebars
keep space only while out (`reserve_open`) · idle fixes: zones as int properties, PenOutline repaints on content.
**Verified:** merge set via `just suites` (28 min wall vs ~81 serial), frame alone incl. idle, pen ×2, look, `just check`
(1254 tests); on nested niri: every fix above by screenshots/pixel dumps, old code reproducing each bug first; Settings
shows the new controls.

**Next steps (ordered):**
1. The user's live check on niri of K77 (blur on the real wallpaper, the sidebar band while sliding — I296 not
   reproduced after the region fix —, dock texture after a Sheet change — I298 not reproduced, mask re-grab is a guess —,
   keycap frame outline weight I305).
2. W55 (fast suites: condition waits, motion off, fewer restarts, idle window) — card ready.
3. W53 styles (UX brief first); I294 (looks/styles/palettes at run time) first if style edits pile up.
4. The rest of I269, I288, I280, I284/I285; I304 (layer stacking by map order), I306 (mock tokens), I308 (pen idle flake).

**Risks:** blur default changed to off (translucent looks without a blur key stay unblurred; a user file with
`blur = true`, no kind and a translucent look now blurs — see K77). Tracked screenshots were regenerated by the suites.

---

## 2026-10-29 — session 17 (machine A): faster builds — K76
**State:** `feat/i290-faster-builds` merged into `main` (`--no-ff`), **not pushed** (push when the user agrees; session
16 part 2's merges are unpushed too). `nix build .#kurashi` run on the merged `main`. No subagents (user's rule).

**Merged (K76, I290–I293):** crane flake input; `nix/package.nix` = deps (`buildDepsOnly`) → `bin` (our crates, from
Rust sources + `looks/ styles/ palettes/ i18n/*/doctor.toml`, which are `include_str!`'d) → the package (data copied,
`makeBinaryWrapper --set-default KURASHI_DATA_DIR $out/share/kurashi`). `option_env!("KURASHI_DATA_DIR")` removed
(kurashid `i18n.rs`, mod-timer `texts.rs`). Tests: `checks.<system>.tests` (`passthru.cargoTests`), no longer in
`nix build`. devShell lists `passthru.rust{Native,}BuildInputs` instead of `inputsFrom`. README "Iterating".
**Measured:** old package builds 34–78 min (nix log timestamps, 15 builds Oct 22–28, median ~44 min); now QML/string
edit ~5 s, Rust edit ~5 min, cold/Cargo.lock ~11 min. Verified: `just check` and `checks.tests` (1244 tests each),
hm/webdock/greeter evals, webdock-closure, `nix run .#sandbox`, wrapped kurashid without the variable (data found, ja
strings, process name `kurashid`).

**Next steps (ordered):**
1. The user's review of session 16's work on niri (see the entry below, step 1) — first live start on the new package.
2. W53 (I289): UX brief `docs/ux/styles.md` first, then the system card, then one card per family.
3. I294 if style work makes `looks/`/`styles/`/`palettes/` edits frequent (load them at run time; then they rebuild in
   seconds too). I293's binary cache: not wanted for now (user), kept as an idea.
4. The rest of I269, I288, I280, I284/I285.

**Risks:** the first `nix build` on machine B is a cold one (~11 min there or more). HM/NixOS installs keep the same
paths (`$out/share/kurashi/...`, `$out/bin/...`); the binaries in `$out/bin` are now small wrappers.
