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

---

## 2026-10-20 — session 9 (machine B): the sekai look, morphing island, phone, desk — K42–K44, wave 21
**State:** `main` at 781045a (not pushed). Green: cargo clippy -D warnings + cargo test --workspace, test-real, test-stage, test-peek, test-quick, test-quick-sections, test-volume (made hermetic), test-island-morph, test-look sekai/wa-iro, `just webdock`, test-sidebars, `just mods-live` (now classifies `surface:`). `just check` stops only at `cargo fmt --check` on the other session's uncommitted `crates/kurashid/tests/hosts.rs`. `settings/test.sh` stops at P3 (B31, pre-existing at 80640d6). Two Opus agents (W21-island-morph, W21-phone), both merged; their worktrees
are removed. Nothing is half-done.

**User request (session 9):** read `INSPIRATION.md` (Vitreus, Capsule, pleamar, the Project-Sekai rice = SekaiPop) and take
what works: a SekaiPop-style theme, the web dock themed as a front-view phone, a dynamic island "performed properly",
improve everything, "almost feature complete", ≤ 2 subagents.

**Built and merged:**
- **K42 chrome + decor:** `theme.chrome` flat|keycap (outline/ring/hard shadow/press sink via `Block.qml`), palette roles
  `line`/`ring`, palettes `sekai` + `sekai-night`, `theme.decor` none|sekai|glass as a recipe at the `theme:<pack>`
  layer (user values win), spring tokens, `Icon.qml` (Material Symbols, glyph fallback), tonal `color.selected` and
  `color.data.*`, `Theme.panel`. HM `programs.kurashi.fonts` (material-symbols, nunito, noto CJK); the dev shell exposes
  the fonts to sandboxes. **`Theme.fgOnSelected`** (an `on…` property reads back black, like onAccent).
- **Surfaces (lead):** keycap primitives; bar groups float as blocks, numbered workspace keys, **window list**
  (`svc.workspaces.tasks`, `window.focus`, K44); launcher card + **calculator**, **`:` emoji** (Vitreus data, MIT),
  **`;` clipboard** (cliphist, HM `clipboardHistory`); notification centre/cards; session menu as five keys; lock with a
  keycap clock + dot field; **desktop widgets** (K43, `desktop.*`, `docs/ux/desktop.md`); Settings app tonal/keycap.
- **W21-island-morph:** one Shapes path from the bar pill to the card and back (Capsule's asymmetric springs), liquid
  neck under flat chrome, keycap pill, flip clock, media level bars, OSD level meter, KeyButton views, `ownChrome`
  content (the phone) without card chrome; `frontend/test-island-morph.sh`.
- **W21-phone:** `frontend/components/phone/PhoneFrame.qml` (linked into the host), web dock phone card with status row,
  title pill, bottom bar; keycap pin icons; quick settings as a SekaiPop phone (greeting row, keycap tiles). Row 118:
  `svc.clock` joins every host scope.
- **Tools:** `frontend/test-look.sh <tag> [config lines]` (real kurashid; `LOOK_MOCK=1` fake windows, `LOOK_LOCK=1`
  lock via the mock wearing the real theme) → `frontend/shots/look/<tag>/`.

**Next steps (ordered):**
1. Look at the shell live with the user (`theme.decor = "sekai"`, also `glass` and `none`) and collect taste feedback;
   the screenshots in `frontend/shots/look/` and `frontend/shots/island/morph-*` are the review set.
2. Commit the other session's Nix-build fix (`nix/package.nix`, `crates/kurashid/tests/hosts.rs`,
   `crates/kurashi-mock/tests/wire.rs`, still uncommitted, not mine) with the user's OK, then `nix build .#kurashi`.
3. B31 (settings import-review focus, pre-existing — checks after P3 do not run), B32 (one-off morph stall), B30.
4. Follow-ups: I101 (desk v2: drag/resize, notes/todo service), I102 (window list on side bars), I104 (decor cards in
   Settings), I105 (launcher conversions), I106–I115 (phone + island leftovers), then the session-8 queue (I80 web dock on
   niri, I90–I100).
5. Bench: per-output cost of the desk (opt-in, K43) and the Stage while the island card is out (it covers the bar strip).

**Open decisions (ask):** keep `sekai` as a decor only or make it the default look? Desktop widgets on by default with
the sekai decor (now: yes via recipe)? Should the keycap island card get a neck to its bar group (I115)?

**Gotchas (new):** an `on…`-named QML property reads back black (use `fg…`). Merging append-only i18n files with diff3
markers: remove the `|||||||` base line too (main was broken once by it). `settings/test.sh` stops at P3 since before
this session (B31). The emoji data lives in `crates/kurashi-launcher/data/` (MIT note there).

---

## 2026-10-20 — session 8 (machine B): web dock shell side — K40, K41, wave 20
**State:** `main` green and pushed (80640d6): `just check`, `just webdock` (test-host incl. net-log privacy, test-real against
kurashid, test-dock all four phases), `nix build .#kurashi` + `checks.webdock-closure` (with the uncommitted fix below),
`nix flake check --no-build`. No agents, no extra worktrees; `w20-*` build dirs deleted.

**User decisions this session (K40):** the eight interpretations of `docs/ux/webdock.md` as proposed — hover reveals
the strip **and** re-opens the last page, a click on its icon puts it away, click-in keeps it until focus leaves;
250/500 ms reveal, 400 ms hide, 24 px grace; 56 px strip, 412 phone, 90 % large; pinned overlays, reserve optional;
`Mod+B`; kurashi views = mod panels. **Change:** new tabs stay in the dock (setting `new_tabs`, browser optional); the
header has back/forward, **home** once the page left the pin's address, and **"Replace pin with this page"**
(`webdock.retarget`). **K41:** opt-in mods carry their own measured cost (BENCH "Mods"), outside the core K16/K19 budget —
the dock's per-output edge window is ~6.2 MiB USS per output (+3.8 MiB once for the shared dock window). Accent design
pass: later, separately.

**Merged (wave 20, 4 Haiku cards):** lead contract (`surface:` provide row 88, `mod.webdock` fields row 109, seven
settings row 110, actions + hover machine row 111; mock `add` reply row 113); W20-webdock-daemon (pure hover/focus state
machine with deadlines in the supervisor, select/back/pin/add/remove/move/retarget as settings writes, mock parity —
the mock has no timers); W20-webdock-shell (per-output thin edge window + **one** shared dock window retargeted like the
Stage after a first design used one full window per output at 20–35 MiB each; strip panel, view card, add form, pin
menu, empty/cold/missing states, keyboard, bar widget `widget:webdock`); W20-webdock-host (new tabs in the dock,
home/forward, overflow menu, retarget, I78 polish, hover/engage reports, card centred in the usable area);
W20-webdock-nix (W17.6: `packages.kurashi-webdock` 1.7 GB apart from `kurashi` 160 MB, closure check,
`programs.kurashi.webdock.{enable,pins,keybind,…}`, NixOS parity, `Mod+B` bind). Rows 112–117 decided/deferred; new
backlog I90–I100.

**Not mine, left alone — ask the user:** uncommitted changes in `nix/package.nix`, `crates/kurashid/tests/hosts.rs`,
`crates/kurashi-mock/tests/wire.rs` (another session's: python3 + patchShebangs for the fake host, XDG dirs for the mock
under Nix). Verified: with them `nix build .#kurashi` passes; without them it fails in checkPhase. `hosts.rs` needs
`cargo fmt` before commit.

**Next steps (ordered):**
1. Commit the Nix-build fix above (user's OK), then `nix build .#checks.x86_64-linux.webdock-closure` on main.
2. **I80** the web dock on niri (nested niri in the sandbox, then the user's session on request): reveal by hover and
   by `Mod+B`, keyboard focus (I98 first keystroke), layer surfaces at each edge; then PROGRESS W17 "UX ✅".
3. Web dock follow-ups: I90 (view card Tab path + padding), I91 (provenance on `pinned`), I94 (CLI reveal and the hide),
   I97 (`online` on `mod.webdock`), I99/I100 (reduced motion, 26 px buttons, top/bottom edges), I92 (browser command),
   I95 (per-key enforce), I96 (mock `mods` document).
4. Earlier queue (session 7 step 3–4): I86, I88, I89, I84, I67 keyboard path, I77, I87; B7 quiet re-measure; I93 (PSS
   reader on two outputs under gles2) before trusting two-output PSS; I10 on machine A.
5. Design pass with the user (accent colour: I51, I63, I78 leftovers, I82, I83, I86; `INSPIRATION.md`).

**Gotchas (new):** a `cd` into an agent worktree moves the lead's session cwd — use `git -C`. `git commit -am` sweeps the
other session's dirty files into your commit (happened once, undone before push) — stage paths explicitly while that
diff exists. Parallel cards still collide on CONTRACT-CHANGE row numbers (renumbered 112→114, 114→115 at merge). The
zsh tool shell has no `PIPESTATUS` (use `$pipestatus` or `set -o pipefail`). PSS on two outputs under gles2 shows a
~1.9 TiB mapping: measure USS (I93).
