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

## 2026-10-21 — session 12, part 2 (machine B): material textures and their light, 紙 kami, text colour — K59, K60, wave 31
**State:** `main` green, pushed (merge of `feat/k59-texture-light`). Four agent cards merged (W31-texture-gen,
W31-texture-polish, W31-relief, W31-paint); no agent worktrees left; their build dirs deleted. Nothing is half-done.

**User decisions (session 12, part 2):** textures are colourless reliefs lit like a normal map, an appearance option
of their own; scopes shell (default) / wallpaper / shell + wallpaper / everything (apps too); rulings and dots as faint
ink in the palette's colours with a switch to no colour; a continuous sheet by default; light modes static (direction
configurable), pointer, daytime and — added later — the wallpaper's own light (its brightest place); text untextured by
default with an option to texture it; screen filters (CRT, pixelate, scanlines) are a separate idea (I165), Hyprland's
`screen_shader` a later adapter detail (I164); a polished 紙 (kami) style with a handwritten font in blue ink; a general
text colour option; a brushed oil-paint material.

**Built and merged:**
- **K59 textures:** `crates/kurashi-texture` — twelve seamless, deterministic materials (paper, dotted/lined/squared
  paper, fabric, wool, stone, halftone, metal, leather, wood, paint), wrinkles, tint/plain; the shading formula
  (DESIGN-SYSTEM "Texture and light") mirrored by `frontend/shaders/relief.frag` (qsb, `just shaders`); tiles as an opaque
  relief map + a white ink map (rows 280–281, Qt premultiplies). Daemon `kurashid/src/texture.rs`: tokens `texture.*`,
  `light.*` (legibility cap so text keeps 4.5:1), tile cache on a blocking thread, daytime sun (NOAA, 5-minute tick only in
  that mode), the wallpaper light (`light_spot`: a lamp at the picture's brightest region, `light.lamp`), the wallpaper
  bake through the mod API's new `PictureFilter`, Settings swatches only while Settings watches `theme.previews`.
  `theme.texture.restore` brings the user's material back after a look/style took it (as K55).
- **Frontend:** `Relief` on blocks, bar strip, grounds, Stage card and the island's shape, notifications, lock;
  continuous sheet (gl_FragCoord + window origin, `Light.originOf`); `TextureOverlay` (scope everything, click-through);
  pointer lamp (`core/Light.qml`, `LightSense.qml`); `texture.text` lays the relief over content.
- **K60:** `theme.colors.ink` (palette | blue | black | sepia | red | green | violet | custom) as a palette stage before
  wcag; `theme.typography.family_jp`; style/look/palette `kami` (paper_dots, sketch frame, Kalam + Klee One — in the dev
  shell and the HM/NixOS font defaults via `google-fonts.override`), light and dark.
- **Settings:** material cards (daemon swatches), light dial, ink swatches (`settings/test-texture.sh`).

**Verification (end of session):** `just check`; `nix build .#kurashi`; hm-eval; 30 sandbox suites incl. the new
`frontend/test-texture.sh` (relief = formula within 0.6/255, ink included; continuity; text on/off; overlay
click-through; four static angles, pointer, daytime) and `settings/test-texture.sh`; looks washi and kami — all green.
Fixed on the way: `mods/webdock/test/test-dock.sh` clicked where the K58 sidebar button now sits; the calendar test's feed
event fell into tomorrow in an evening run.

**Next steps (ordered):**
1. Show the user live when they ask: 紙 in light and dark, a few materials under each light mode (incl. the wallpaper's
   light with a real wallpaper, never shot in the sandbox yet), the everything overlay.
2. Kami polish: I172 (the phone card's ground), I168 (relief clipped to the island's path), I169 (fibres busy on dark
   paper), I167 (media cover opt-out).
3. BENCH row for scope shell (idle 0 frames measured by W31-relief; PSS with one tile pair per window ≈ 1.8 MiB at
   scale 1) and the everything overlay; I171 (generation time at scale 2), I170 (finer normals), I166 (greeter tile).
4. Then session 12's earlier list: I156 time-of-day fallback for `auto`, I158–I162, I148–I153, I145–I147; session 10's
   I134, I127, I141, I139; backlog sweep I118–I142.

**Open decisions (ask):** none pending. MangoWM and isekai/mirai stay deferred until the user raises them.

**Gotchas (new):** Qt Quick premultiplies texture alpha — never keep data in the RGB of alpha-0 texels. A sandbox name
reused across runs keeps its cache (`/tmp/kurashi-sb-<name>`): read the file the tokens name, not the first match. Tests
that place events "hours from now" break in evening runs.

---

## 2026-10-21 — session 12 (machine B): light/dark modes, web dock in the sidebar, island join — K55, K56, wave 30
**State:** `main` green, pushed. Two agent cards (W30-webdock-sidebar, W30-island-line) merged through the integration
branch `feat/k55-scheme-modes`; no agent worktrees left. `target/` deleted at the end. Nothing is half-done.

**User decisions (session 12):** isekai/mirai stays deferred (I117 — don't ask again until the user brings it up); the
web dock can be used in the sidebar and fills it there, not phone shaped (K56); light/dark has modes Follow system /
Follow wallpaper / Dark / Light, a style takes it over when applied and "reset" goes back to the user's own (K55).
Reported: the sidebar could not be opened (I154) and the open island's outline did not meet the bar under line chrome
(I155) — both fixed.

**Built and merged:**
- **K55:** `theme.colors.scheme` = `auto` (default; xdg-desktop-portal `org.freedesktop.appearance color-scheme`,
  `kurashid/src/os_scheme.rs`, watched only while chosen) | `wallpaper` (mean CIE L* of the wallpaper mod's applied
  picture, light from 55) | `dark` | `light`. The scheme is in `STYLE_KEYS` again: applying a style resets it; the
  user's mode before is kept in `$XDG_STATE_HOME/kurashi/scheme-before`, `theme.scheme.restore {}` brings it back.
  Theme document `appearance.scheme_effective / scheme_detail / scheme_before`. Settings: four pills + a reason line +
  "Back to …" (`SchemeStatus.qml`); Dark tiles show the scheme in effect; the wallpaper picker keeps a follow mode.
- **I154 / K58:** the sidebars open without a key — a button at each end of the bar (`sidebar.bar_buttons`, on by
  default), launcher `>` "Right sidebar" / "Left sidebar" (`sidebar.{right,left}.toggle`), Settings › Sidebar "Open
  now" with the keys. HM default binds now include `Mod+Shift+N` (right sidebar) and `Mod+A` (left); bind entries may carry JSON
  arguments (`"sidebar.toggle {\"side\":\"left\"}"`). The user's niri config does not include `kurashi-binds.kdl`
  yet (`programs.kurashi.niri.binds.enable` + `include "kurashi-binds.kdl"`) — tell them, don't edit it.
- **W30-island-line:** under line chrome the card hangs from the bar's rule: one continuous outline (fillets with
  constant width), the rule opened under the card; `frontend/test-island-join.sh` pixel-checks 10 cases.
- **W30-webdock-sidebar (K56):** `panel:webdock` for `sidebar.left`/`sidebar.right`; pins as a key row, the page fills
  the pane; the host maps a second window `kurashi-webdock-side` and moves the pin's page (no reload); same pin in
  both places → live in the sidebar, "shown in the sidebar" at the edge. Panel property `placement` (MODS "Panels"),
  `mod.webdock.sidebar {pin?, place?}` (fixture variant `snap_mod_webdock_sidebar.json`).

**Verification (end of session):** `just check` (fmt, clippy -D warnings, all tests); `nix build .#kurashi`; hm-eval
(incl. the sidebar binds with JSON args, `niri validate`); 31 sandbox suites — real, stage, quick, quick-sections, volume,
modqml, mods-live, sidebars, sidebar-panel, power, desk, dock, launcher, media, polkit, island-morph, sway-adapter,
**island-join (12 cases incl. mid-morph)**, settings, greeter, ai, tasks, lyrics, calendar, webdock dock, **webdock
sidebar**, webdock host; looks washi and sekai — all green.

**Next steps (ordered):**
1. Show the user live when they ask: the four light/dark modes and "Back to …", both sidebars via the new keys, the
   web dock as a left tab (`sidebar.left = ["mod:webdock:webdock", "mod:ai:ai"]`), the island under washi.
2. I156 time-of-day fallback for `auto` without a portal. (I154 is done: K58 — bar end buttons, launcher commands,
   Settings "Open now".)
3. Follow-ups I158 (host memory with the sidebar window, BENCH), I159 (web dock in the sidebar polish), I160 (island
   polish), I148–I153 (sidebar/appearance), I145–I147.
4. Then session 10's remaining steps: I134 secret setting type, I127, I141, I139; backlog sweep I118–I142; bench.

**Open decisions (ask):** none pending. MangoWM and isekai/mirai stay deferred until the user raises them.

**Also fixed (session 12):** Settings' preview moved across several choices stacked undo steps (K57: the config
document publishes `history.rev`); the sandbox's D-Bus no longer activates a real desktop portal (`tools/bench/sandbox.sh`
denies `org.freedesktop.portal.Desktop`); the washi grain no longer uses deprecated `Qt.btoa`.

**Gotchas (new):** never run `just check` while sandbox suites run — `cargo test` and the `--features
kurashid/test-mods` build share `target/`. The lyrics test needs `cargo build -p kurashi-mod-lyrics --example fake_mpris`.
Settings' focus hook names a Segmented pill by its label (e.g. "Follow the system"), not `segment:<key>`. `pkill -f` with a pattern that also matches your own shell's command line kills the tool call
(exit 144) — kill by PID. A private `dbus-daemon` for tests needs `<allow receive_sender="*"/>` or replies are
dropped and the test hangs; bound such tests with `tokio::time::timeout`. With two agents building, a lead `cargo
test` can wait 10+ minutes on the build lock — run it in the background.
