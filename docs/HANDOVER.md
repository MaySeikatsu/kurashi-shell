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

## 2026-10-22…25 — session 13 (machine A): textures, the pen, one motion language, shortcuts, apps follow, perf, shadows, terminal material, icon subset — K61–K69, waves 32–42
**State:** `main` green (`just check`), pushed. Wave 42 is running (four agents: W42-memory opus, W42-shadows3, W42-faces2,
W42-tiles haiku; cards in `docs/tasks/`, CONTRACT-CHANGE rows 460–479). If this session ended before their merge, their
branches `worktree-agent-*` live under `.claude/worktrees/` — review each against its card, merge `--no-ff`, union the
CONTRACT-CHANGE rows. Lead build dir `~/.cache/kurashi-agents-target/lead` is kept. The user's live session still runs an
old installed `kurashid` that burns ~1 core (B36, fixed on main) — suggest reinstalling (`nix build .#kurashi`).

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
1. Merge wave 42 (W42-memory: core PSS ≤ 148 with pairs; W42-shadows3: last straight-down shadows; W42-faces2: I212 incl.
   `save_profile` keeping user-set defaults; W42-tiles: lighter QuickTile, Sketch/Snes frame memo).
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

---

## 2026-10-21 — session 11 (machine B): Style · Look · Palette, light/dark everywhere, sidebars — K53, K54, wave 29
**State:** `main` green, pushed. Two agent cards (W29-sidebar, W29-appearance) merged through the integration branch
`feat/k53-appearance`; no agent worktrees left. `target/` deleted at the end (disk at 94 %). Nothing is half-done.

**User decisions (session 11):** washi is the default on a fresh install; the greeter stays off in the user's NixOS
config (the feature stays); AI defaults to Ollama with the **last used model** (else the first installed); MangoWM after
most of the shell is done (I143); "isekai" may be "mirai" or both — **ask again** (I117); sidebar gets style options and
an edge-to-edge panel like ii (stops at a bar on that side), the phone style stays, a paper-notebook sidebar is an idea
(I144); appearance split into **Style** (a fixed preset that resets and sets everything), **Look** (shape, chrome,
material, motion, type, frame), **Palette** (colours only), sorted into categories Modern / Inspired / Retro / Fiction;
every palette has light **and** dark.

**Built and merged:**
- **K53 appearance:** `looks/*.toml` (17) and `styles/*.toml` (19) replace `decors/`; user packs in
  `~/.config/kurashi/{looks,styles}/`; `theme.style` (default washi) + `theme.look` (default kanso); schema v2 with a
  v1→v2 migration (`theme.decor` → `theme.style`); per-entry theme layer sources `look:<n>`/`style:<n>`; actions
  `theme.style.apply` / `theme.look.apply` reset their keys and set the pack in one undoable transaction; document
  `theme.previews`; the theme document carries `appearance`; offers carry `group`. Light/dark is the **user's mode**:
  never reset by a style (a style only recommends one). Dark mode tile in quick settings and the sidebar toggles.
- **Settings:** Style / Look / Palette blocks with category chips and preview cards, "N settings differ from Washi ·
  Reset", light/dark switch with the style's recommendation; washi paper frame (`frames/Paper.qml`).
- **Palettes:** the missing scheme added to yorha, win95, luna, aero, kawaii, snes (dark) and hallownest, ps2, souls
  (light); a test requires both.
- **K54 sidebars:** `surfaces/Sidebar.qml`, `sidebar.{style panel|floating, width, right, left, from_bar}`, actions
  `sidebar.toggle/open/close`, Mod+Shift+N (right) and Mod+A (left); left column = mod panel tabs (AI, …), mod panels
  may fill the offered height (`fillHeight`, MODS.md).
- **AI:** empty Ollama model = the last used one from saved conversations, if still installed.

**Verification (end of session):** `just check`; `nix build .#kurashi`; hm-eval; all 24 sandbox suites (real, stage,
quick, quick-sections, volume, modqml, mods-live, sidebars, sidebar-panel, power, desk, dock, launcher, media, polkit,
island-morph, sway-adapter, settings, greeter, ai, tasks, lyrics, calendar, webdock); look washi and sekai — green.

**Next steps (ordered):**
1. Ask the user: isekai and/or mirai inspiration (I117); should the web dock become a sidebar tab (I116); keep
   light/dark as the user's mode, or let a style set it on apply (K53 amendment)?
2. Show the session's work live when the user asks: Settings › Appearance categories, Reset to Washi, Dark tile,
   both sidebars in panel and floating styles.
3. Sidebar follow-ups I148–I152; appearance follow-ups I145 (mod `decor:` provide → `look:`/`style:`), I146 (profile
   layer vs style apply), I147 (palette categories), I153 (Settings display maps; the mock lacks `schema.settings`).
4. Then session 10's remaining steps: I134 secret setting type, I127, I141, I139; backlog sweep I118–I142; bench.

**Open decisions (ask):** see step 1. MangoWM stays deferred.

**Gotchas (new):** frontend pixel tests pin `theme.style = "none"` (washi is the default now). `cargo test` replaces the
`--features kurashid/test-mods` binary: rebuild with the feature before the sandbox suites. A new quick tile adds a Tab
stop (quick-sections counts them). Data URLs: use `encodeURIComponent`, not `Qt.btoa(string)` (deprecated, logs a
warning that fails the QML-warning checks). Sandbox dirs may survive a run: remove fifos before `mkfifo`.

---

## 2026-10-21 — session 10 (machine B): looks, daily-driver services, identity packs, adapters — K45–K52, waves 22–28
**State:** `main` green (see "Verification" below), pushed. 13 Opus agent cards merged in waves of ≤ 2; no agent worktrees
left. **Disk:** the machine ran full once (`target/` dirs grew to 70 GB across worktrees) — delete `target/` and agent
worktrees' `target/` after merges; `~/.cache/kurashi-agents-target` is gone. Nothing is half-done.

**User decisions (session 10):** `sekai` stays an option; every decor is a whole, distinct look and **never** a layout —
layout lives in profiles (K45); the keycap island card joins its bar group (done); sidebar details to be discussed
(I116); "isekai" cyberpunk decor only after the user sends inspiration (I117 — Cyberpunk presets were left out on
purpose); first look / first-run profile offer deferred. Then: "as complete and usable as possible", copy from
Caelestia, Noctalia, DMS, ii, shellseikatsu, WormShell where they solved it.

**Built and merged:**
- **Looks:** chrome flat/keycap/soft/line from tokens (K45); decors are files `decors/*.toml` + user packs (K50); 18
  packs incl. 14 ports from shellseikatsu with frames and lock backdrops; Settings decor preview cards; bundled
  look+layout profiles (`profiles/`); **app theme export** (K49: matugen-syntax templates for GTK, Qt, foot, kitty,
  alacritty, ghostty, niri; HM `programs.kurashi.themeExport` adds the include lines).
- **Daily driver (K47):** idle (ext-idle-notify: dim → lock → screens off → suspend) + keep-awake + media inhibit,
  night light (wlsunset), keyboard layouts, recorder (gpu-screen-recorder/wf-recorder), screenshots, polkit dialog
  (Quickshell PolkitAgent; never in sandboxes), rounded screen corners, power page in Settings.
- **Mods:** tasks + notes over Markdown (K46, Obsidian Tasks syntax), lyrics (LRCLIB), calendar (ICS/vdirsyncer/feeds/
  khal, RRULE, time zones), AI chat (Ollama first, OpenAI-compatible, Anthropic; keys from secret-tool/env only),
  Wallhaven in the wallpaper picker; `desk:` provide for mod desk cards.
- **Shell:** app dock (K51), desk edit mode + `desktop.order`, Settings section cards + theme-export status, launcher
  `>` commands / web search / unit conversions / clipboard with images and pins / emoji grid / `?` keybind cheat
  sheet, live audio levels (cava) + cover colours, greetd greeter (NixOS `services.kurashi.greeter`).
- **Compositors (K52):** Sway and Hyprland adapters beside niri, `AnyCompositor` chosen from env; the sway sandbox now
  runs the real adapter path.
- **Fixed:** B31 and B33 (stale tests), the polkit agent can never run inside a sandbox, `Store.apply` (+ err path),
  theme-export test independent of the install prefix (nix build checks).

**Verification (end of session):** `just check`; `nix build .#kurashi`; `nix/tests/hm-eval.nix`; `greeter/nixos-eval.nix`;
every frontend suite incl. new ones (power, media, desk, dock, launcher, polkit, sway adapter, greeter, ai, tasks,
lyrics, calendar, settings, webdock, mods-live, peek, sidebars, look for 8 decors) — all green; the last full run after
the W28 merges: check, nix build, hm-eval, greeter-eval, greeter, ai, real, look, mods-live green.

**Next steps (ordered):**
1. Show the user the session's work live (the shell on their display only when they ask): `theme.decor` packs,
   Settings › Appearance cards, `theme.export`, quick tiles (keep awake, night light, record), dock (`dock.enabled`),
   desk edit mode, launcher `>`/`;`/`:`/`?`, AI panel against their Ollama, calendar/tasks pointed at their files.
2. Sidebar discussion (I116), then the isekai decor when inspiration arrives (I117).
3. Contract follow-ups: I134 secret setting type (Wallhaven key, AI keys, calendar feeds), I127 mods following core
   documents, I141 mods adding launcher rows (AI `!` mode), I139 capabilities published per adapter.
4. Backlog sweep of the session's rows I118–I142 (polish), then bench: dock (+6.9 MiB hidden), desk with mod cards,
   spectrum bars, idle service.

**Open decisions (ask):** default look for new installs; should the greeter be on in the user's NixOS config; which AI
provider/model by default; MangoWM adapter priority.

**Gotchas (new):** agents' CONTRACT-CHANGE rows collide — give each card its own row range (this session: 120–223 in
blocks). Resolving those conflicts with a regex left a `|||||||` line once: grep for markers after every merge. A
`cd` into a worktree moves the lead's cwd. Nix builds run tests with an empty data dir: tests must read repository
files by `CARGO_MANIFEST_DIR`. Quick-settings and web dock tests click fixed coordinates: new tiles or bar chips move
them (update the offsets, B33).
