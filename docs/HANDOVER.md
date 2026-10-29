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

## 2026-10-29 — session 17, part 3 (machine A): outlines in general, Settings on the shell's Theme, cards for corners, shadows, the light
**State:** branch `feat/s17-frame-ink` (on top of `main` 0e0f3adb+) is **not merged** — its check run was still going at
handover: 12 of 15 suites green under load; `frontend/test-sidebars.sh` (kami: "the fillet (231) is the bar strip's
colour (247)", calm and lively) and `settings/test-sheet.sh` ("the spotlight does not follow the pointer over the sheet")
failed under load and were re-running alone; `settings/test.sh` and `just check` after them. Logs:
`/tmp/kurashi-suites/s17-settings/` (summary.txt once done), `/tmp/kurashi-lead-logs/check-settings.log`. A package of the
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
1. Finish the branch: read the alone re-runs. If `test-sidebars` kami fillet is real, it comes from kami's sketched ink on
   the joined column (ColumnShape `penOn`/`oc` with `pen.line = sketch`) — compare on niri (`niri-sandbox.sh`, look kami,
   chrome line, right sidebar top fillet) against `main`; if `test-sheet`'s spotlight check is real, it comes from the
   sheet's content now sitting in a clipped, offset slot (SheetHost: `slot` inside the grow clip; Relief registers by
   window pixel — check `Light` still gets the sheet's pointer). Fix, `just suites --changed main settings/test-sheet.sh`,
   `just check`, merge `--no-ff`, `nix build .#kurashi`, ask the user to push.
2. Bugs found today: I309 (kami: the island card's head shows the wallpaper across the bar — main too), I305 (keycap
   frame outline under grouped bars looks heavy), re-check on the user's niri I296 (sidebar band with blur) and I298
   (dock texture after a Sheet change: a guess is in), I304 (layer stacking by map order), I306 (mock tokens), I308 (pen
   idle flake; W55 should settle it).
3. W56 corners (I288 squircle on every visible shape incl. relief.frag's box; I269 concentric rest) — `docs/tasks/W56-corners.md`.
4. W57 elevation shadows (I310; the user wants them smooth: layered ambient + key, no banding) — UX brief first,
   `docs/tasks/W57-elevation-shadows.md` (static via niri layer-rule shadows vs client-drawn for follow-light).
5. W58 the pointer light across the screen (I311) — `docs/tasks/W58-pointer-light.md`: a click-through overlay cannot see
   the cursor (Wayland); niri 26.04 has no ext-image-copy-capture cursor sessions and no cursor IPC → routes: cursor
   sessions in kurashid where supported, a niri patch (ask the user first), an honest fallback. The effects sheet (I312:
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

---

## 2026-10-28 — session 16, part 2 (machine A, the user away for 3 h): squircles, nested corners, the top dock, sidebar layouts, palettes, the style-rework card — K75
**State:** branches `feat/w49-squircle` → `w50-dock-top` → `w51-sidebar-mode` → `w52-palettes` (stacked) merged into
`main` locally (`--no-ff`), **not pushed** — push when the user agrees. `nix build .#default` run on the merged `main`
afterwards so `nix run .` starts without a compile (until a tracked file changes; see I290–I293 for making rebuilds
cheap). No subagents (user's rule). Scratch: `/tmp/kurashi-lead-logs/` (dev.sh sandbox with the user's config, bursts).

**Built (K75 addenda):** real squircle corners (`core/corner.js`, `Corner.squircled`, `SquircleRect`; radius ×1.3 under
squircle; leftovers I288) · `Theme.nested(outer, inset)` — Settings navigation and the sidebar's section plates are
concentric (rest of I269 open) · `dock.edge = top`, and a dock joined to a sliding bar rides its edge (I282) ·
`sidebar.<side>.mode` stack / pages, core sections as pages, wrapping tabs (I283) · catppuccin, rose-pine, tokyo-night
are palettes, not styles (schema v6, `v5_to_v6` keeps a config's look) · I242 empty output names refused · I259 empty
peeks draw nothing · I244 mod pages' names translated and sorted · stale rows I148, I205 (dnd) closed.
**Written, not built:** `docs/tasks/W53-styles.md` (I289) — the user's style rework (Windows 95…11, macOS, consoles;
new decor components; a lock screen per style; shellseikatsu's LockStyle*.qml as inspiration). I290–I293: build-time
proposals.

**Next steps (ordered):**
1. The user's review of today's work on niri (blur at corners, the sidebar band while sliding, popups' sheet, click-away,
   squircle looks — aqua/glass —, the top dock, the sidebar layouts).
2. W53 (I289): UX brief `docs/ux/styles.md` first, then the system card, then one card per family (the card says how).
3. I290–I293 if the user wants faster builds (they asked for ideas; nothing changed in `nix/package.nix` yet).
4. The rest of I269 (Stage views, desk tiles), I288 (squircle leftovers), I280 (style vs profile look), I284/I285 previews.

---

## 2026-10-28 — session 16 (machine A): screen corners follow the radius; the user's live check (blur, popups, motion, click-away, mods, seasons) — K74 addendum, K75
**State:** `feat/w47-screen-corners` and `feat/w48-polish` merged into `main` (`--no-ff`); `main` pushed after the first
merge (user's go) — push the second when the user agrees. `nix build .` run on the merged `main` so `nix run .` starts
without a compile (until a tracked file changes). No subagents (user's rule, session 15–16). The old `/tmp/kurashi-sb-*`
leftovers were deleted (user's go). Lead build dirs `~/.cache/kurashi-agents-target/{lead,lead-mods}` kept; scratch
logs in `/tmp/kurashi-lead-logs/` (dev.sh: a sandbox with the user's own config, bursts of frames).

**User decisions (session 16):** screen corners follow the radius by default, with a toggle (done: schema v5); nested
concentric controls are next (I269); seasonal tint — make it visible and say what it does (done); squircle — implement
real superellipse corners (**open, next**); the Media mod's dead page — gone; blur — must follow its switch (done); click
popups need no Close button, a click elsewhere or Esc closes (done); popups must share their origin's colour and texture
(done); don't dig into "styles broken" now (I280 holds the finding: applying a style clears the user's look, and the
active profile's look shows through).

**Merged:**
- K74 addendum (schema v5): `theme.shape.screen_corners_follow` (default on) → `runtime.layout.screen_radius` = R, else
  `screen_corners`; migration `v4_to_v5` keeps a chosen size. Probes in test-dock/stage/modqml/mods-live skip the corners.
- K75: blur gated on glass + switch + compositor, regions follow the drawn corners (bar, frame, sidebar, dock, edge groups,
  cards, toasts); popups (Stage cards, launcher, notification centre, peek, dock tooltip/menu, the phone views) are the
  bar's sheet (surface colour + relief); sidebar/dock rule openings every frame, the dock starts on its first presented
  frame; `ClickAway` (one top-layer catcher per output while something is open) and no Close button; native mods whose
  code is not linked are not offered (media manifest removed, easter-eggs hidden, I286); the seasons have hues.

**Suites (session 16, on the branch):** `just check` ✅; stage, quick-sections, dock, sidebars, bars, edge-modules, frame,
polkit, island-join, settings ✅. test-tray-bt ❌ at its Bluetooth step — fails on main too (I287). test-modqml's
mod-panel step and test-morph fail on main too (I274).

**Next steps (ordered):**
1. Ask the user to check on niri: glass blur at rounded corners and joins, the sidebar's band while it slides (image 6 of
   session 16 was not reproduced on sway), the dock's reveal, popups' colour/texture, click-away.
2. Squircle (I281): real superellipse corners for `corners = squircle` — the shared shapes (Block, ColumnShape,
   MorphShape, BarMorph, FramePieces' arcs, Rectangle-based controls via a shape path), concentric with K74's radii.
3. I269: concentric radii for nested controls (buttons, toggles, tiles, the Settings navigation).
4. I282 dock on the top edge (grows out of the bar, stays aligned while either spawns); I283 a per-side sidebar mode
   setting (pages with tabs / one column of sections).
5. I284/I285 window and workspace previews on hover — UX brief first; niri 26.04 offers no per-window capture to clients
   (stills through niri's IPC are the route).
6. I280 styles (low priority per the user), I287 tray-bt, I274 mod panel gate, I286 easter-eggs.

**Open decisions / risks:** blur shapes and the sidebar band could only be verified by loading and logging (sway has no
`ext_background_effect`); the fillets' wedges are not blurred under glass (small, noted in K75). Washi's R 9 still gives a
1 px hole radius (session 15's open point).

---

## 2026-10-28 — session 15 (machine A): the frame under a hover bar, one corner radius, the expressive motion — K74
**State:** `feat/w46-frame-morph` merged into `main` locally (`--no-ff`), **not pushed** (push when the user agrees). No subagents this session (user's rule).
Lead build dirs `~/.cache/kurashi-agents-target/lead` and `lead-mods` kept. Leftovers the lead could not remove (denied):
`/tmp/kurashi-sb-{dev,lead-sbars,lead-w44-int,w44-*,lead-frame}` (≈ 3.5 GB, no processes but `dev`), and the handover's
sandbox `dev` still runs (sway pid 2347498) — stop it with `tools/bench/sandbox.sh stop dev`, then delete the dirs.

**User decisions (session 15):** the frame must connect to the screen edge under a hover bar; its outline must run on
smoothly into the bar and every emerging component; morphs in dynamic should look and feel like Caelestia's (grow out of
the border, fillets that track the motion, Caelestia's curves), the springs staying as a setting of their own; **one
radius setting** that drives the frame, the joins, buttons, toggles and other controls, with related radii (inner =
outer − the distance between them; a square look squares the frame too); the screen's black corners are the shell's
topmost layer. Ideas noted: pixelated and straight-line joins (I270).

**Built (branch):**
- Frame: a docked hover bar keeps the band; the frame's fillets/arcs/rules follow a sliding bar on all four edges
  (`IslandGeom.lifts`, FramePieces `lift*`, `cover`/`coverRule`); bands run the full width (corner hole above a docked
  side bar fixed); a side bar's rule ends where its fillet does; columns joined to a hover bar follow it to the band;
  rules opened and arcs hidden where a joined neighbour reaches; screen corners on the overlay layer; Stage cards keep
  clear of bands/fillets/side bars; joined edge-module groups open the band's rule (I258 row 556) and take the hole radius.
- K74 / schema v4: `theme.shape.radius` (px) replaces `radius_scale` (migration + test); `layout.frame.radius` derived
  (R − thickness on a framed output) for frame, dock, sidebars; expressive motion profile (default; calm looks moved)
  with Caelestia's curves: `core/Glide.qml`, `core/ease.js`, MorphSprings and Sidebar timed paths; bar/column overshoot
  widens inward. test-frame gained a `hover` scene.

**Next steps (in order):**
1. Push `main` (the user's go), then Live check on the user's niri (I219) — now including a hover bar with the frame, R 18/24, and the expressive feel.
3. I269 (concentric nested controls, Settings nav; screen corners following R: ask the user), I273 (island/fades on the
   curves if the user wants), I271 (side bar under a top edge's module zone), I268 (acrossMade loop).
4. The rest of session 14's list (I256–I267, I245, budgets I246/I261/I254/I272).

**Open decisions:** should `theme.shape.screen_corners` follow R by default? Washi's R 9 makes its frame's inner corners
1 px (R − 8): fine by the rule, or should washi's R go up?
**Suites (session 15):** `just check` ✅; test-frame (washi, terminal, incl. niri) ✅; test-sidebars ✅;
test-stage ✅; test-dock ✅ (fillet check follows the layout radius); test-bars ✅; test-edge-modules ✅; settings/test.sh ✅;
test-island-join ✅; test-morph ❌ at the sysmon peek — same on main's frontend, I274. A regression found and fixed on the
way: Glide's spring path started a SpringAnimation by hand, which ignores a new target while running (groups and bars
stayed out); it is a Behavior now.

---

## 2026-10-26 — session 14 (machine A): the layout system — screen frame, draw modes, bars on every edge, edge modules, the timer — K71–K73, waves 43–45
**State:** `main` green (`just check`), pushed, no agent running, no worktree left. Lead build dirs
`~/.cache/kurashi-agents-target/lead` (52 GB) and `lead-mods` (a `--features test-mods` build) are kept. The disk filled to
100 % mid-session (old `/tmp/kurashi-sb-*` sandboxes ≈ 51 GB, agent target dirs ≈ 20 GB each): delete each card's target
dir and its sandboxes right after its merge, and start cards with `CARGO_INCREMENTAL=0`. Nix GC'd the nixpkgs source
while the disk was full; `nix develop --option eval-cache false` refetched it. A sandbox `dev` (sway pid 2347498,
`/tmp/kurashi-sb-dev`) a W45 agent started by mistake may still run — the user was asked to stop it
(`tools/bench/sandbox.sh stop dev`). The user's NixOS/HM config needs no change for schema v3 (it sets only
`idle.enabled = false`).

**User decisions (session 14):** draw preset **dynamic**; the frame reserves space by default and can be set not to;
sidebars **slide in from their screen edge in every mode** (replaces W34's grow-from-the-button); **one bar per edge**
(several per edge later, I221); I218 option (a) (small blocks share the window's paper grain), the rest of I216/I218 a
refinement round; the live-session check deferred (I219); **I253 (a)**: a sidebar under a floating bar starts a gap below
it in every draw mode (option (b), the bar shortening, only as an optional setting if cheap: I255).

**Built and merged:**
- Wave 43 (contracts K71–K73): schema v3 + `v2_to_v3` migration; `crates/kurashi-layout` computes `runtime.layout`
  (frame bands, per-edge bars/zones/insets/holders/reserve, dock, sidebars, island, `unplaced`, `problems`) for kurashid
  and the mock; actions `layout.toggle`, `layout.bar.move`, the `actions` query, `kurashi act --list`; the screen frame
  (`surfaces/Frame.qml`); the timer/pomodoro mod with every K72 variant (row 500: ungated background jobs).
- Wave 44: shared edge strips (`EdgeStrips`/`EdgeReveal`/`EdgeStripHost`); bars on every edge from the zones with every
  bar item a module component (`components/modules/**`, `ModuleHost`), floating pill, always/hover/empty-desktop/hidden,
  the docked bar carrying its frame strip; dock and sidebars in every draw mode, sidebars slide/hover/pin/drag-resize
  (Ctrl+Left/Right), desk on both sides; Settings › Layout (screen diagram, zone lists, Move bar to, honest
  "Automatic (…)", inert reasons, empty-bar warning).
- Lead (rows 510/511/513/520/522/523/530/531): `layout.bar.move` keeps the destination's modules; `holder: bar` on a
  framed edge a docked bar carries; a hidden bar is not the band; side bars get `span`; the mock answers `layout.toggle`;
  `keys.bar_<edge>` / `keys.dock` (empty by default); `"*"` documented as an alias; I253 (a) (`joins: none`).
- Wave 45: W44-follow (the Stage grows from its own bar under any bar; one reveal model — EdgeHold folded into
  EdgeReveal, no more out/in loop on a resting pointer; frame strips stay `Ignore`; openings per side; the joined dock's
  paper) and W45-edge (edge module groups on bar-less edges in every visibility × draw, the standalone island with
  transient faces, peeks from the host's place, keyboard path, the clock's K72 row; a click on the bar's clock now opens
  the island clock card).

**Next steps (in order):**
1. Rerun the deferred suites on main (I267) on a quiet machine; fix what fails first. `SIDEBARS_PARTS=bars
   frontend/test-sidebars.sh` failed on the W44-follow branch (end column stacking) but **passed on main** after the
   merge (lead rerun, all checks) — treat it as a load-timing flake unless it recurs.
2. The live-session check on the user's niri (I219): bar, frame, a hover dock, a sidebar pinned, Settings › Layout.
3. Stage work (I256): cards grow out of an edge module and out of the standalone island (rows 553, 557); then the
   clock peek served (row 550, I257) and the edge-module overlaps (I258: peek clearance row 552, dock × group row 554,
   frame rule under joined groups row 556).
4. Smaller follow-ups: I259 (blank timer peek), I260, I265, I266, I245 (inner fillets where bars meet), I242–I244,
   I250–I252, I262–I264; fullscreen (I237) before hover edges ship as a default.
5. Budgets: reveal first frame ≤ 16.7 ms (I246); the first edge group's PSS (I261); frame + paper (I254).
6. The refinement round the user asked for (I216, I218 rest) and the deferred features: several bars per edge (I221),
   the redesign edit mode (I220), free desk placement (I222), I255.

**Open decisions / risks:** none pending from the user. Risk: much of wave 45's suite coverage ran on branches only
(I267). Contract rows still open: 540–543, 550–557 (see CONTRACT-CHANGE; their BACKLOG rows above).

## 2026-10-22…25 — session 13 (machine A): textures, the pen, one motion language, shortcuts, apps follow, perf, shadows, terminal material, icon subset — K61–K69, waves 32–42 (K70)
**State:** `main` green (`just check`), pushed, no agent running, no worktree left. Lead build dir
`~/.cache/kurashi-agents-target/lead` is kept. The user's NixOS config (`~/.config/nixos`, uncommitted there) now runs
kurashi as the niri shell: the NixOS and HM modules from the `kurashi-shell` input (`git+file`, not `path:` — a path
input copies cargo's 47 GB target/), `modules/home-manager/desktop/kurashi.nix` (user services, HM niri binds with the
user's Mod+N/Mod+Shift+N/Mod+A kept, idle off), `include "kurashi-binds.kdl"` in niri/config.kdl, noctalia and
plasma-polkit-agent no longer spawned from niri/init.kdl. Its flake.lock was empty; restored from git with nixpkgs pinned
to the running system's 6510408. After the user's first rebuild into kurashi, check the live session (bar, notifications,
polkit, lock) and pick up anything that breaks first.

**User decisions (session 13):** spotlight over a steered direction; Settings as a modal sheet (window stays default);
carried sheet by default; relief shadows on for kami/paint; everything that comes out of the bar morphs like the island
(calm and lively stay); apps follow the shell incl. icons and fonts. K68: split memory budgets (core 150 MiB @1; material
and web dock have allowances); the minute flip ≤ 300 ms is the one idle commit; `island.main.faces` restricts (system
transients exempt; default users keep every face); toasts/centre under the island and panels under their widget stay.

**Built and merged:** waves 32–35 (texture depth/relief shadows/spotlight/light colour/controls/sheet/cracks/brush/wallpaper
material, the pen K62, Settings sheet, morph everywhere, apps follow, K64 shortcuts, web dock polish; see PROGRESS) and:
- W35-perf: popup 88.9 → 13.7 ms (ClockView cells async), PSS reader without GPU mappings (I93), lazy desktop/overlay
  windows and session keys (per output +9.0 → +0.4 MiB; one output 174.8 → 154.2 MiB).
- Wave 36 (K65): one spring family for every surface, async Stage views with a size cache (quick 14.6 ms), panels rest
  under their widget, polkit steps aside; window list in both bar layouts (middle-click close, drag to workspace, title
  peek, urgent), dock pin reorder; Settings by page, island system events switch, free string lists; desk hide/titles/order.
- Wave 37 (K66): ghostty custom shader with the material (background pixels only; glslang in the devShell); island face
  switch, forced services overlay (`Hub::set_overlay`), polkit refusals, daemon icon paths, `kurashi settings --page`,
  no-bus wait; calendar event details + agenda day; quick tile tokens, right-click → page, focus across changes.
- Wave 38 (K67): drop shadows (strength, direction, follow the light; defaults pixel-identical); keys for Sway/Hyprland +
  niri overlay titles; web dock forced tip + the daemon's forced feed for native mods (lead); clock grid centred and
  five-week months, Return saves desk edits, side-bar toast tests, DND follows the config live.
- Wave 39: shadows on notifications/lock/polkit/toasts/centre/Settings; a lighter Block (−20–40 µs, pixel-identical);
  badge contrast ≥ 3:1; minute flip capped at 300 ms and split budgets (lead, K68).
- Wave 40 (K68): island faces restrict; the faces a list leaves out are offered back in Settings (lead fix, row 450).
- Wave 41 (K69): the package installs the icon subset (Kurashi Symbols); `font.icons_fallback` + Icon.qml tiers (a name the
  subset lacks draws from Material Symbols, else glyph/bullet); `tools/check-icon-names.sh` in `just check`; washi grain
  memo (quick card 48–50 → 22 ms warm); PSS @1 157.5/158.2 → 152.3/152.4 MiB (budget 150 still ✗); `nix build .#kurashi`
  (CLAUDE.md fixed); the nix check phase reads i18n from the source tree.
- Wave 42 contracts (lead): the three shadow rows are inert under flat and line chrome (row 423, K67 amendment).

**Next steps (ordered):**
1. Wave 42 merged (K70 memory: PSS @1 ~110 in pairs; last shadows; faces follow-ups; lighter QuickTile). Next: the
   user's live session on kurashi (see State); I216 first-launcher-open burst; I218 quick card ≤ 18 ms (paper frame on small
   blocks is a design call); I217 tests through launch.sh.
2. Follow-ups by area: I197 (window list), I202 (ghostty tokens/BENCH), I205/I208 (daemon, keys), I207 (web dock on niri),
   I213 (bench tooling), I214 (icon fallback edge cases), I195 (mods' own i18n), I134 (secret settings), I140 rest (CalDAV).
3. Ideas: I176 mixed fonts (try `calt` first), I173 rays/bloom, I174 kitty/WezTerm baked background.

**Open decisions:** none pending from the user. If W42-memory cannot reach 150 without latency cost, ask the user again
(raise to ~155 or accept the latency).

**Gotchas (new):** a `&& grep` chain hides a failing cargo test — use `set -o pipefail`; tests must not read the user's
real `~/.local/state`; Quickshell hot-reloads the config while a suite runs; machine A has one GPU (`renderD128`);
CONTRACT-CHANGE.md conflicts on every merge — give each card a row range up front and union both sides; a card whose
API needs a daemon half must own that half (W38-webdock didn't); agent worktrees are locked — `git worktree remove -f -f`
after checking the branch is merged and clean; the auto-mode classifier can drop out for minutes — agents then stop
mid-commit, so check `git status` in their worktree. Run `just check` before merging a lead fix into main, not after
(W40). `target/release` goes stale — rebuild before a bench (`cargo build --release -p kurashid -p kurashi`). The machine's
load average sits at 6–10 from the user's session: only same-run pairs are comparable. The shared agents target dir grew
to 52 GB once — delete per-card dirs after each merge.

---
