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

---

## 2026-10-19 — session 7 (machine B): web dock (I68) — K38/K39, Phase 0, waves 17 and 18
**State:** `main` green (`just check` 779 tests; `just webdock`, `just peek`, `just mods-live` 5/5 after the B29 fix,
test-stage, test-sidebars, test-quick(-sections), settings/test.sh, weather and wallpaper state tests). Waves 17–19
merged; no agents, no extra worktrees; nothing half-done.

**Wave 19 (user: "start the next wave, we handle the open decisions afterwards"):** lead contract — slot
`clock.expanded.daymark` (row 71), `runtime.slots` `reason` + `ModCtx::slot().set_reason` (row 72), schema
`clock.week_start`/`week_numbers`. Cards: W19-side-bars (vertical widget forms, hidden count; row 107, I85),
W19-weather (labelled hourly rain, week range, place preview forecast, no-place reason; I82), W19-wallpaper (720 px
picker, quiet choices, overflow menu, keyboard paths; rows 105–106, I83, I32), W19-calendar (day marks, week start and
numbers, the aside's "Set place"; row 108, I46). **B29:** my row-72 prep caused a lock-order deadlock in kurashid
(`slots()` under the hub's lock took a mod's state lock that a choice-source change holds across hub calls) — found by
the calendar agent's mods-live runs, fixed (own lock), 5/5. New rows I87–I89.

**Wave 18 (after the web dock, user: "continue with other parts of the shell"):** contract rows 98 (peek `edge`/`y`/`h`)
and 99 (diff `same_value`) by the lead; W18-quick-tiles (160×56 cells for `quick.tiles`, wallpaper/hello as
`QuickTile`, `mock.doc`; I52, I50), W18-peeks (peeks on every bar edge, fade-out, weather/sysmon peek states, `just
peek`, mods-live kinds from manifests; I67), W18-sysmon (GPU by connected output, names in the session language,
refusals on the row, counter reset, states; I65), W18-settings (same-value lines, held-back values in Changed,
records keyboard paths, `wl_keys` modifiers + URL characters; I64, I81). Lead: row 101 (an import named like a saved
profile is refused), two Settings editor fixes, the island peek crop. UX reviews filed: weather I82, wallpaper I83.

**Merged:** session-6 wave 16 (peeks, no-network sandboxes). Session 7 — the user's **web dock** request (an Edge/Floorp-
style edge dock with pinned sites, from a WormShell prompt adapted to kurashi): Phase 0 spike
(`archive/spikes/webengine-phase0/`: stock Quickshell aborts with QtWebEngine — `argc = 0`; a 2-line patch works;
engine comparison QtWebEngine 390 MiB vs WebKitGTK 294 MiB for one page; net log shows zero engine requests); UX brief
`docs/ux/webdock.md`; **K38** (web dock: own lazy host process, Chromium ungoogled by configuration, default browser as
the bridge), **K39** (patched Quickshell `qs-webengine` for the host only; the shell keeps stock Quickshell); contract
(scoped hello + `forbidden`, `host:` provide + `ModCtx::host`, `mod.webdock`, records type; rows 88–97); netjoin accepts
loopback-only namespaces (K37 amended, B26). Wave 17 (3 Haiku cards): W17-webdock-host (QML host: profiles per pin,
mobile/desktop UA + client hints, privacy switches, card states, sheets, blocked chips, freeze, mock parity),
W17-webdock-daemon (host facility: start/scoped token/one restart/Failed/stop, scope enforcement, settings writer, mod
`webdock`: actions, keep/max_loaded, idle unload), W17-records (records setting type: manifest, schema, kurashid,
Settings editor). Lead: pins setting, `mods/webdock/test/test-real.sh`, B28 sheet fix, `just webdock`.

**User decisions this session:** web dock = mod `webdock` "Web dock"; modes hidden/compact/extended (extended phone
format by default, up to ~full screen); edge configurable (default right), hover reveal, pin/unpin, keybind + bar
widget; kurashi pins first (sites and kurashi views); mobile/desktop toggle; lazy engine that unloads after 1 h;
Chromium via QtWebEngine on a patched Quickshell (Gecko is not embeddable); "ungoogled" by configuration + net-log test
(no ungoogled build, I76); the browser bridge is the **default browser**, never Zen by name; hybrid pins (I75) and
browser bookmarks (I70) later; a browse/search section later (I69).

**Open decision (ask before W17.4):** the eight interpretations in `docs/ux/webdock.md` "Modes and transitions" and
sizes — hover re-opens the last app and a click on its icon clears it; a click into the dock keeps it until focus leaves;
strip 56 px, phone 412 × ≤ 2× width, large 90 %; reveal 250 ms (500 ms on a shared edge), hide 400 ms + 24 px
hysteresis; pinned overlays (reserve space optional, strip only); keybind `Mod+B` via HM; sign-in popups as sheets,
new tabs to the browser, permissions/downloads refused with a chip; kurashi views = mod panels in v1.

**Design pass with the user (ask):** the accent colour (crimson in wa-iro) is used for selected states, data and
every primary button, so panels read as alarms — I51, I63, I78, I82, I83, I86 (row 104 tile tokens). Proposal: tonal
selected states, `color.data.*` roles, one primary action per panel; use `INSPIRATION.md` (I60).

**Next steps (ordered):**
1. Ask the user the open web-dock decision above and the design pass; then: **W17.4 shell side** (row 88 `surface:` provide: indicator,
   strip, card frame for view pins, `webdock.hover` state machine in the daemon, pin/unpin, add/remove/move, keyboard,
   bar widget, empty/cold/offline states), **I78** card polish (title first, quieter toggles, rounded bottom, keyboard
   path into the header, reduced motion), **I77** scope table and host registry into `Daemon`, **W17.6** Nix (a
   `kurashi-webdock` package apart from the base closure, HM/NixOS options, closure check).
2. **I80** web host on niri (nested niri in the sandbox; reveal by click).
3. Cards without a user decision: I86 (`forced_by` on service documents), I88 (weather: preview verification path,
   hourly overflow, ja review), I89 (calendar polish), I84 sysmon leftovers, the keyboard path into bar widgets (I67),
   I77 (scope table into `Daemon`), W17.6 (web dock Nix packaging), I87 (peek PSS check robust under load).
4. B7 quiet repro + quiet re-measure of K35, W18 peeks (second output +3…+34 MiB under load) and the web host (BENCH);
   no agents running. I10 on machine A.

**Gotchas (new):** parallel cards keep colliding on CONTRACT-CHANGE row numbers (renumber at merge) and on sandbox
names (give each card unique names, I84). `wtype` drops the first key of every call (looked like B27) — type with `tools/bench/wl_keys.py`,
which cannot type `:` (I81). `qs-webengine` (dev shell) is the patched Quickshell; Chromium needs `argc > 0` for
`QTWEBENGINE_CHROMIUM_FLAGS`. The host imports `frontend/core` through the link `mods/webdock/host/core` (Quickshell
refuses imports outside a config root). Card cross-talk: give the host card the daemon's i18n key list early (done by
SendMessage this time). The permission guard refused decompressing the user's Zen session file (it holds open tabs) —
don't read browser profiles without asking. Disk is at 90 % (38 GB free): clean caches before the next wave.

---

## 2026-10-18 — session 6 (machine B): wave 14 close, K34–K36, wave 15, K35 daemon
**State:** `main` green and pushed after W16 (`just check` 686 tests, test-peek/stage/real, settings/test.sh, mods-live no QML warnings, stage/quick/volume tests, golden B ok). Wave 16 (W16-peek-frontend) is the next card; nothing half-done.

**Merged:** session-5 leftovers resumed and finished — W14-weather-ux, W14-sysmon-ux (PopupWindow peek removed at merge:
K19, row 75 rejected); lead: Stage `cardWidth` for mod panels (row 66, I53); **K34** palette `wallpaper` follows
`mod.wallpaper.theme.image` (daemon holds the mod's document while chosen; waiting note); **K35** (user decision) the
Stage hosts peeks — daemon/contract/mock side: `ui.peek`, `runtime.ui.peek`, `peek:<name>` → `qml/Peek.qml`;
**K36** (user decision, B13) profile load is an overlay. Wave 15 (4 Haiku cards): W15-profiles (K36 + Profiles page
review/export/import), W15-job-active (`JobCtx::set_active`, honest "Running now", I48), W15-quick-island-polish
(I51/I52/I45/I44/B14), W15-sysmon-fixes (B24 shell processes protected by identity, I61 names, I62 GPU tile, I56
`KURASHI_SYSMON_ROOT` + `mods/sysmon/test-states.sh`). Lead fixes: island secondary name, volume a11y (I12), 400 px
card for power/bluetooth. BACKLOG: B22–B25, I55–I65 filed; contract rows 70–82 decided.

**User decisions this session:** B13 → overlay (K36); K35 → Stage-hosted peeks. User added `INSPIRATION.md` (I60:
Vitreus, Capsule, pleamar, a Project-Sekai Quickshell rice) — use it in the next design pass.

**Next steps (ordered):**
1. **Wave 16 merged:** W16-test-infra (K37 no-network sandboxes, mock focus + B14 two-output step, B25) and
   W16-peek-frontend (K35 frontend: Stage peeks for tray, island, sysmon, weather; measured). Follow-ups in I67
   (side bars, keyboard path, fade-out, peek state shots, quiet re-measure). Original card for reference: (`docs/tasks/W16-peek-frontend.md`, card ready; push main first). It owns Stage.qml,
   Bar.qml hover plumbing, tray/island peeks and the sysmon/weather/hello `Peek.qml`; it must report the K35
   measurements (idle 0 fps, peek PSS, retarget to a second output, 20 hover cycles).
2. Parallel cards with disjoint paths (write them): I52 host sizing of `quick.tiles` (SlotHost + wallpaper/hello tiles,
   row 76); I64 profiles follow-ups; I65/B25 mod follow-ups (wallpaper `null`, sysmon main device); I58 network-less
   sandboxes; row 80 mock focus model so B14 gets a two-output runtime check; I63 data colour roles (kurashi-theme).
3. Lead UX review against the briefs with screenshots: wallpaper (I32 open items), weather (I57), settings profiles.
   PROGRESS "UX ✅" only after that.
4. B7 quiet-machine repro (no agents running) and I10 render-loop check on machine A.
5. Design pass with the user using `INSPIRATION.md` (decor packs, motion; I60, I63).

**Gotchas (new):** agents now get **one build dir per card** (`~/.cache/kurashi-agents-target/<card>`, README rule 3;
B23) — the shared dir handed worktrees stale path crates and once let a sandbox daemon reach Open-Meteo. Delete a
card's dir after merging it (disk: 365 GB, keep ≥ 40 GB free; `./target` is the lead's gate dir). Parallel cards
still collide on CONTRACT-CHANGE row numbers and on the `i18n/*/settings.toml` tail — renumber/resolve at merge.
`git merge` here uses diff3 markers: strip the `|||||||` base block when resolving. One agent's sandbox commands were
refused by the permission guard (W15-job-active): the lead ran the UI checks. A finished agent's worktree stays
locked by this session's own pid — `git worktree remove -f -f` once its branch is merged.

---

## 2026-10-09 — session 5 (machine B): waves 9–13, native mods, K24–K28, UX bar
**State:** `main` green and pushed (b53d79f: `just check` 384 tests, golden B ok, `nix build .#kurashi` ok). Usage limit hit
mid-wave: agents were stopped; their **unmerged branches/worktrees remain** (see Half-done).

**Merged:** wave 9 fixes (B2 volume honesty, B3 brightness session, row 20 `item_is_menu`, rows 21–22 config history +
live profiles, B5/B6/B8, I6 test helpers, I8 niri binds); wave 10 (K24 island expanded views + quick settings card +
◐ bar button; K25 mods as config lists `mods.loaded/enabled` — persisted, B11; Settings mod pages, dropdown, pick list;
I9 `choices_from`); K26 native mods (`kurashi-mod-api`, ledger); K28 slots/mod faces/choice sources/`mod.panel.open`
(daemon); quick settings sections (Wi-Fi, power, audio out, BT); B7 lazy island faces + bench mean-of-two-hotplugs.
Decisions K24–K28 in DECISIONS.md (user answered K24/K25/K26 this session).

**User rules added this session (keep):** (1) implementation by parallel Haiku max-effort agents, lead reviews/merges;
(2) **UX bar** (CLAUDE.md): every user-facing feature gets a researched brief in `docs/ux/` and is "done" only against
it; think what a feature *can become* and what it combines with (`docs/ux/COMPOSITION.md`), not the minimum.

**Half-done (end of session 5, usage limit):** main is green and pushed (622 tests; `just mods-live` green).
Merged since the reset: quick daemon (K29), island daemon (K30), mod loading, weather/sysmon/wallpaper mods, media position (K31),
settings UX + settings daemon (K32), mod runtime (K33), live all-mods test, island views, quick settings UX, wallpaper UX.
Open branches: `feat/k34-wallpaper-theme` (lead WIP: palette `wallpaper` → `Source::WallpaperFile(mod.wallpaper.theme.image)`,
hub-event listener, "From wallpaper" offer — NOT compiled yet; finish: build, add i18n `config.choice.palette.wallpaper` +
`theme.note.wallpaper_waiting` (en/ja), a kurashid test with a generated picture, DECISIONS K34, then merge). Agents stopped
at the limit: W14-sysmon-ux and W14-weather-ux — `git branch | grep worktree-agent`, review their commits, re-spawn with
"merge branch X first". The wallpaper-ux worktree is locked by a stale agent pid: `git worktree remove -f -f` it.

**Next steps (ordered):** 1. (done) 2. For each running/stopped card: review, finish (SendMessage
won't resume across sessions — re-spawn the card with "continue from branch X"), merge with the gate. 3. W13-quick-ux and
W13-island-views (cards ready; need W11-mod-qml merged). 4. Lead UX review of every merged user-facing feature against
its brief; PROGRESS "UX ✅" only then. 5. B7: quiet-machine repro of the +29.8 MiB cycle spike (main vs lazy faces, 3
outputs); I10 basic render loop on machine A. 6. BACKLOG B13 (profile load clears user keys — ask the user), B14 (quick
settings multi-output re-pick binding loop).

**Gotchas:** shared CARGO_TARGET_DIR hands worktrees stale path-crate rlibs (agents: touch + rebuild; lead: always gate
in the private target dir). Test runs regenerate tracked shots (`frontend/shots/*`, `settings/shots`) — restore them
unless the UI changed. Machine A golden refs need `just golden --update` there (bar changed). The user's live kurashi
qs shares Qt pages, so absolute @1-out PSS is lower than baseline (per-output deltas unaffected).

---

## 2026-10-09 — session 4 close: handover to the next agent (user feedback from the first live run)
**State:** `main` green and pushed (`just check` 330 tests + `test-launch.sh`, golden 5/5). No agents, no
extra worktrees. The user ran `nix run .#` live on niri for the first time: the bar showed
"disconnected" → fixed (M7.5: QML clients now use the protocol's default socket). Everything the user
said about the island, mods in Settings and wallpapers is in **`docs/BACKLOG.md`** (rows B1–B10, I1–I8,
D1, plus design notes). Read that file before planning; add new findings there (CLAUDE.md rule).

**User feedback to act on (summary; details in BACKLOG):**
- Island click must open the **expanded card of the face it shows** (media → controls, notifications →
  list, …), not a generic card with Bluetooth (B1; DESIGN-SYSTEM §8 already says so). Bluetooth moves to
  a quick-settings card (I2).
- Island model (I1): placements (bar module | standalone surface), faces as submodules (core + mod,
  user-ordered), the island optional like a mod. Lead view: agree, but the arbiter stays daemon core.
- Settings (I3, user's preferred option): loaded mods get pages **in the normal sidebar** with a state
  indicator (loaded-off / on / in use); the Mods page stays core; detected-only mods have no page.
- Wallpaper management (I7) as the first native mod. Animations/look & feel: user is not commenting yet.

**Next steps (ordered; each a card unless marked lead)**
1. **Per-output PSS** (B7, lead): A/B 6b13d56 vs main on machine B iGPU (≥ 3 quiet runs each,
   `KURASHI_RENDER_NODE=/dev/dri/renderD129 just bench-gate`), attribute, cut per-bar cost. Must be green
   before any new per-output surface (standalone island, wallpaper background).
2. **Fix wave** (parallel cards, disjoint files): B2 volume slider honesty (Bar), B3 brightness session
   resolver (kurashi-services brightness.rs), B4 tray waits for NameOwnerChanged (kurashi-tray), B5+B6
   profile error codes + list refresh (kurashid config.rs + settings ProfilesPage), I6 test helpers →
   `tools/bench/`, I8 niri keybinding snippet (README + optional HM option), B10 sandbox default GPU.
   Plus **I9 dropdowns for option sets** (schema `choices_from` resolved by the daemon + a Select control in
   Settings; palette, island default face, faces pick-list) — a prerequisite for the wallpaper backend choice.
   Lead first: contract rows 20 (`item_is_menu`) + 21 (`config.history`), then the settings card drops
   its reply-derived undo flags.
3. **K24 Island model** (lead decides *with the user*, then cards): `island.expand` opens the current
   face's expanded view (latched); each face = compact + expanded component; first expanded views:
   media, notifications, clock, volume/brightness; Bluetooth → quick-settings card (bar widget → Stage
   panel). Standalone placement + multiple islands after step 1 frees budget.
4. **K25 Mods in Settings + mod state model** (lead: contract change to the `mods` doc — detected /
   loaded-off / on / in_use, per-mod on/off key under K22; then a settings card: sidebar pages with a
   token-coloured, shape-coded indicator; `color.status.*` roles in kurashi-theme).
5. **K26 Native mod mechanism, driven by the wallpaper mod** (lead design → cards): how an enabled native
   mod registers its Rust service/actions/settings and ships QML loaded on demand (MODS.md "Lifecycle").
   Wallpaper mod: per-output state, library folders, `wallpaper.set/next/prev`, optional rotation timer,
   theme source `wallpaper` (DESIGN-SYSTEM §2), picker panel in the Stage. **Rendering decided by the
   user:** external daemon **awww / swww**, selected in Settings from a dropdown (BACKLOG I7, I9); awww/swww
   is the default if only one is supported at first. Needs I9 (dynamic choices → dropdown) first or with it.
6. M6 mods after that (media + lyrics, sysmon, weather), each a card on the K26 mechanism; keep the live
   test loop with the user (collect findings into BACKLOG).

**Decisions to ask the user:** K24 (arbiter stays core? standalone island placement priority), K25
(indicator semantics/colours), K26 (Wallhaven now or later; backend is decided: awww/swww).

**How to work (unchanged):** lead = review/verify/merge/decide; agents (Haiku, max effort) get cards in
`docs/tasks/`, isolated worktrees, disjoint ownership. **Push `main` before spawning agents** (their
worktrees may branch from `origin/main`). Gate every merge with `unset CARGO_TARGET_DIR;
CARGO_INCREMENTAL=0 just check`; UI merges also `frontend/test-real.sh` (now asserts the frontend
connects), `just golden` (`KURASHI_GOLDEN_REF=tools/golden/ref-machine-b` on machine B), Read screenshots.
On machine B export `KURASHI_RENDER_NODE=/dev/dri/renderD129` for every sandbox run.

---
