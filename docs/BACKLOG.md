# Backlog — bugs, improvements, ideas

The one place where everything not yet scheduled is written down, so nothing gets lost between
sessions. **Anyone (lead, agent, user) who finds a bug, has an idea or sees an improvement adds a row
here** — with date and source — instead of leaving it in a chat, a report or a handover only.
Scheduled work moves to `docs/ROADMAP.md` / `docs/PROGRESS.md` and gets a task card in `docs/tasks/`;
then the row's status points there. Rows are never deleted: done rows say where they landed.

Status: `new` (not looked at) · `accepted` (agreed, needs design or a card) · `designing` · `scheduled
<card/step>` · `done <step/commit>` · `rejected (why)`.

## Bugs
| # | Date | Source | What | Status |
|---|---|---|---|---|
| B1 | 2026-10-09 | user, first live run | **Island click opens a generic card** (title, Bluetooth, Close) instead of the expanded view of the face it shows. Contradicts DESIGN-SYSTEM §8 ("left click → expanded view"). See I1. | accepted — K24 (expanded view of the current face); wave 10 |
| B2 | 2026-10-09 | lead review | Bar volume slider shows 0 % when `svc.audio` is `available:false` (no audio server): a value that is not in effect (rule 2). Hide or mark the slider unavailable. | done c80c399 (W9-bar-volume) |
| B3 | 2026-10-09 | L-logind report | `brightness.rs` still calls `SetBrightness` on `session/auto`: fails for a `systemd --user` daemon. Reuse the session resolver of `session.rs`. | done fa478bc (W9-brightness-session) |
| B4 | 2026-10-09 | lead review (C-services) | A tray that cannot start (watcher name owned by another shell) retries every 30 s while a bar is visible: a small idle wakeup. Wait for `NameOwnerChanged` instead. | rejected (session 5): premise false — a foreign watcher is hosted (`become_host`, since 361276b); `start` never fails, no retry exists |
| B5 | 2026-10-09 | S-settings report | Profile actions answer `kind: invalid` + English text, so Settings can only show "(code: invalid)". Send i18n codes like the mods actions do. | done 89702da (W9-config-profiles) |
| B6 | 2026-10-09 | S-settings report | Profiles page: "No profiles found" stays after a profile file appears (refreshes only on reconnect). | done 89702da (W9-config-profiles, CONTRACT row 22) |
| B7 | 2026-10-09 | bench (BENCH "after wave 8") | Per extra output PSS +4.7…+6.7 MiB on machine B iGPU (budget ≤ +6): at the limit on both machines. Attribute (A/B runs), then cut per-bar cost. | designing — session 5: attributed (see BENCH "per-output attribution"); lazy island faces on feat/m7-per-output-pss |
| B8 | 2026-10-09 | lead review | Settings: an invalid mod reads "mod.toml is missing (mod.toml)"; a row's "Rejected" line stays after unrelated changes. Copy/lifetime polish. | done 89702da (W9-config-profiles) |
| B9 | 2026-10-09 | B-tray report | Tray tooltips are not shown on hover (a tooltip needs a surface outside the bar; K16/K19 forbid per-hover windows). Needs a design (Stage-hosted tooltip?). | new |
| B10 | 2026-10-09 | lead (machine B) | `sandbox.sh` defaults to the first render node, which is the dGPU on hybrids (runtime-PM stalls in tests). Default to the `boot_vga` GPU. | done (session 5, feat/m7-per-output-pss: sandbox.sh defaults to the boot_vga GPU) |
| B11 | 2026-10-09 | lead (K25 design) | Mod enablement is not persisted: only the startup policy (`easter-eggs`) is applied, so a mod switched on in Settings is off again after a daemon restart. | accepted — K25 addendum (`mods.loaded`/`mods.enabled` config lists), wave 10 |
| B12 | 2026-10-09 | W9-bar-volume report | `Slider` does not clamp its level: `svc.audio` volume can reach 1.5 (PulseBackend MAX_VOLUME), and fill + knob then draw past the track. | new |
| B13 | 2026-10-09 | W9-config-profiles report | Loading a profile without a section filter clears every user override, not only the profile's keys (seen: History size 210 user → 200 default). Documented engine behaviour, but surprising in Settings: decide (keep + say so in the preview, or keep user keys the profile does not set). | decided (user, session 6): **overlay** — a profile changes only the keys it sets; the preview lists what changes; "Reset to defaults" stays a separate action. Card next wave |
| B14 | 2026-10-09 | lead (W10-stage-panels merge) | Quick settings open on the output latched at the last island/session/tray open (shell.qml re-picks `stageScreen` only on `want`). Adding `quick` to `want` made Stage report a binding loop on `ui`/`wantedKind` (frontend/test-stage.sh keyboard step) — find the loop, then re-pick the output for quick too (CONTRACT row 25). Single output unaffected. | accepted — likely root cause found by W11-mod-qml (Store.unwatch wrote `docs` inside a binding chain; now deferred): retry adding `quick` to shell.qml `want` |
| B15 | 2026-10-09 | W11-mod-qml report | A native-tier mod whose daemon code is not linked into this build (bundled `media`, `easter-eggs`, the test mod `hello` in a release build) can be switched on: the registry says `enabled`, its QML map is served, but nothing registers — "on" that does nothing (rule 2). Decide: refuse with `mods.error.not_built` when the manifest provides daemon kinds (service/action/island-face/choices) and no `NativeMod` is linked, or show it on with an error line. | done (K33: refused as not built; default lists empty) |
| B22 | 2026-10-18 | W14-sysmon-ux report | Weather's hover peek is drawn above its widget inside the bar window: on the default top bar it lies outside the window and is clipped (suspected, not verified). Sysmon's PopupWindow peek was removed at merge (K19). Both wait for the Stage-hosted peek (I55). | new |
| B23 | 2026-10-18 | W14-weather-ux + W14-sysmon-ux reports | The shared agent `CARGO_TARGET_DIR` links another worktree's build of a path crate into kurashid (cargo's artifact names do not depend on the checkout path): two agents tested stale daemons; once a sandbox daemon without the `KURASHI_WEATHER_API` hook fetched the real Open-Meteo forecast. Fix: per-agent target dirs pruned after merge (disk is the limit: 56 GB shared dir, disk at 96 %), plus I58. | new |
| B24 | 2026-10-18 | lead (sysmon screenshot review) | Sysmon process list: the shell's own processes are killable from the shell — a second `kurashid` (another session's) and `.quickshell-wra` show enabled End / Force quit; only the serving daemon's pid is protected. Protect by identity (this session's kurashid, its frontend and settings processes) and show the reason. | new |
| B25 | 2026-10-18 | lead (K35 review of PROTOCOL §1) | `mod.wallpaper` carries `"theme": {"image": null}` (and maybe other nulls), but documents never contain `null` (PROTOCOL §1): a patched client then sees the key absent while a fresh snapshot shows null. Make the wallpaper mod omit the key. | new |

## Improvements
| # | Date | Source | What | Status |
|---|---|---|---|---|
| I1 | 2026-10-09 | user | **Island model, three levels** (see "Island" below): island *placements* (a bar module as today, or a standalone island surface), island *faces* as submodules the user scrolls through and the UI reacts to (core faces + mod faces, user-ordered), and the island itself optional like a mod. Click = expanded card of the current face. | decided K24 (arbiter core; expanded views first, standalone after B7); cards wave 10 |
| I2 | 2026-10-09 | lead (follows I1) | A home for Bluetooth (and later network, audio devices, power): a quick-settings card (bar widget → Stage panel), not the island. | decided K24 (quick-settings card); wave 10 |
| I3 | 2026-10-09 | user | **Mods in the Settings sidebar** (user's preferred option): each loaded mod gets its page in the normal sidebar next to Launcher, Notifications…, with a small state indicator; the Mods page stays a core page (install/load). See "Mods in Settings" below. | decided K25 (on/off dots, alphabetical, "running now" on the page); contract + cards wave 10 |
| I4 | 2026-10-09 | B-tray report | CONTRACT row 20: `item_is_menu` on `svc.tray` items (frontend already reads it). | done 5ad6f95 (W9-tray) |
| I5 | 2026-10-09 | S-settings report | CONTRACT row 21: `config.history {can_undo, can_redo}`; Settings drops its reply-derived flags. | done 89702da (W9-config-profiles) |
| I6 | 2026-10-09 | S-settings report | Move `settings/keys.py` and the virtual pointer of `frontend/test-bindings.sh` into `tools/bench/` (CONTRACT #6). | done 75ff0dc + 4248bc4 (W9-test-helpers) |
| I7 | 2026-10-09 | user | **Wallpaper management** as the first native mod (see "Wallpaper" below). Rendering decided by the user: an external daemon, **awww / swww**, chosen from a dropdown (I9). | decided K26 (awww/swww, Wallhaven later); mechanism design next (lead) |
| I8 | 2026-10-09 | lead (user's live test) | Compositor keybindings for kurashi actions (launcher, session menu, centre, volume/brightness keys): document a niri snippet (`spawn "kurashi" "act" "launcher.toggle"`) and/or let the HM module emit it. Without it the shell can only be driven by mouse and CLI. | done a82f957 (W9-niri-binds) |
| I9 | 2026-10-09 | user | **Choices instead of freeform text** in Settings: string keys with a known option set get a dropdown (Segmented stays for ≤ 4 fixed options). Today freeform: `theme.colors.palette`, `island.main.default`, `island.main.faces` (should be an ordered pick-list). Options are often dynamic (palettes incl. mod palettes, island faces incl. mod faces, installed wallpaper backends), so the daemon resolves them into `schema.settings` rows (one schema, rule 3: e.g. `#[kurashi(choices_from = "palettes")]`); an option that cannot work right now (backend not installed) is shown disabled with its reason (rule 2). | accepted |
| I10 | 2026-10-09 | lead (B7 attribution) | `QSG_RENDER_LOOP=basic` measured on machine B iGPU: −1.0 MiB per output (bare PanelWindow 3.6 → 2.6) and −5 MiB @1 out, popup latency and morph pacing unchanged (p50 16.0 vs 16.2 ms, p99 18.1 vs 17.1). An older note (frontend/README, machine A) says "no effect" @1 out. Verify on machine A (per output, pacing with 2–3 outputs animating), then decide (launch.sh default + K-entry). | new |
| I11 | 2026-10-09 | lead (B7 attribution) | Quickshell's own cost per layer surface is ~3.0–3.6 MiB anon (bare `PanelWindow` + Text, threaded loop), i.e. most of the ≤ +6 per-output budget before any content. Worth an upstream look (per-window render thread/context, glyph cache per context) or a budget discussion with the user if more per-output surfaces are wanted. | new |
| I12 | 2026-10-09 | W9-bar-volume report | The volume slider has no accessible name while audio is available (only the unavailable/muted states have one). | new |
| I13 | 2026-10-09 | W9-bar-volume report | No automated test that the unavailable slider ignores keyboard, pointer and wheel (now possible with `tools/bench/wl_{keys,pointer}.py`). | new |
| I14 | 2026-10-09 | W9-brightness-session report | kurashid's BrightnessWriter opens a new system-bus connection per key press (hold one while keys repeat); `Commands::set_percent` has no daemon caller. | new |
| I15 | 2026-10-09 | W9-niri-binds report | Unverified: `include "kurashi-binds.kdl"` relative to a `config.kdl` that is a store symlink (niri-flake / HM-managed niri config); the paste fallback for niri < 25.11. | new |
| I16 | 2026-10-09 | W9-tray report | kurashi-tray's NameOwnerChanged match rule is bus-wide (it filters in code); narrow it (arg0) to cut wakeups on busy buses. | new |
| I17 | 2026-10-09 | W13-island-daemon report | The service supervisor retries a start every ≤ 30 s while a bus name is absent (e.g. no BlueZ): for services the island keeps subscribed (K30) wait for NameOwnerChanged instead. | accepted |
| I18 | 2026-10-09 | lead (K30) | A key to turn the island's system transients off (`island.main.system_events`), which also drops the permanent svc.power/svc.bluetooth subscriptions (Ma for users who never want them). | accepted |
| I19 | 2026-10-09 | W13-island-daemon report | `svc.media` has no position/rate/timestamp, so the media peek and expanded view cannot show elapsed time or a live progress bar honestly. Add them (position read on change + rate, the view interpolates). | done (W13-media-position, K31) |
| I20 | 2026-10-09 | W13-island-daemon report | "Usual output" for the OSD device name is the first default the daemon saw; make it a config key or learn it. | new |
| I21 | 2026-10-09 | W11-mod-qml report | A test build of kurashid that links `kurashi-mod-hello`, so `frontend/test-modqml.sh` runs every enabled-state step against the real daemon and its stand-in proxy can retire. | done (W14-mods-live: `just mods-live`) |
| I22 | 2026-10-09 | W11-mod-qml report | Measure the Bar's per-output PSS after mod widgets moved to ModLoader (bench-gate on a quiet machine). | new |
| I23 | 2026-10-09 | W12-weather report (CONTRACT 37) | A supervised background-job API in `ModCtx` (start/stop with the mod, `running` + reason "rain alerts" on the mod page) — weather's rain watch and sysmon's trouble watch need it. | done (K33) |
| I24 | 2026-10-09 | W12-weather report (CONTRACT 38) | Mod-provided custom Settings controls (e.g. weather place search on its Settings page instead of only in the panel). | accepted |
| I25 | 2026-10-09 | W12-weather report (CONTRACT 39) | Action `settings.open {page?, key?}`: the daemon launches Settings at a row (weather's "Set place", inert rows' "Controlled by …" links). | done (W14-settings-daemon, K32) |
| I26 | 2026-10-09 | W12-sysmon report (CONTRACT 41) | Manifest `list` setting type (multi-select over fixed values → `pick_list`); sysmon's four `show_*` bools become one `show` list. | done (K33) |
| I27 | 2026-10-09 | W12-sysmon report (CONTRACT 43) | `color.status.warn` theme role (AA on surface) for activity levels (sysmon, battery low). | done (W14-wallpaper-ux: color.status.warn) |
| I28 | 2026-10-09 | W12-sysmon report (CONTRACT 40) | `KNOWN_CAPABILITIES` gains `fs:read`, `proc:signal`; sysmon declares them (Settings shows them). | done (K33) |
| I29 | 2026-10-09 | W12-sysmon report | AMD `Tctl` carries an offset on some Ryzen parts (machine B reads Tctl 89.9 °C with no Tdie) — the 85 °C critical default fires on Tctl alone; prefer Tdie/Tccd, or raise the Tctl default, and say which sensor is used. | done (W14-sysmon-ux, session 6) |
| I30 | 2026-10-09 | W12-sysmon report | Sysmon not yet to brief: bar tabular figures + sparkline + peek + middle/right click, Pause in Settings, "paths searched" for no sensor, VM/container "host values", Open in btop, battery power-use row, live loader screenshots. | mostly done (W14-sysmon-ux, session 6); open: visible peek (I55), undriven states (I56) |
| I31 | 2026-10-09 | W12-wallpaper report | Theme source `wallpaper` in kurashi-theme (palette from the current image, DESIGN-SYSTEM §2) so the picker's "Apply with theme" and theme diff work; favourites store the look. | done — K34 (session 6) |
| I32 | 2026-10-09 | W12-wallpaper report | Wallpaper not yet to brief: keyboard grid/search not exercised, grow origin from tile, drag-and-drop, folder breadcrumb, light/dark pair badges, lock screen, launcher "look:" provider, thumbnail cache size cap, duplicate first-page requests at picker open. | mostly done (W14-wallpaper-ux); open: Shift/Ctrl+Enter and `/` untested, drag-and-drop, lock screen, launcher looks |
| I33 | 2026-10-09 | lead (live mod check) | Weather panel draws its own framed card inside the Stage card (double border); mod panels should fill the Stage card, not nest a card (a `ModPanel` frame convention). | done (W14-weather-ux, session 6) |
| I34 | 2026-10-09 | lead (live mod check) | A test that loads every bundled mod's QML through the real shell (enable each mod, open its panel/face/slots, zero QML warnings) — the harness runs missed B16/B17. | done (W14-mods-live: `just mods-live`) |
| I35 | 2026-10-09 | W13-settings-ux report | Daemon `profile.export {name, path}` / `profile.import {path}` (export drops machine-local keys; import returns a review diff) and `profile.preview` listing Nix-held keys as "not applied". | done (W14-settings-daemon, K32) |
| I36 | 2026-10-09 | W13-settings-ux report | CLI `kurashi settings [<key>]` (starts Settings with `KURASHI_SETTINGS_KEY`, or `qs ipc call settings jump <key>` when running); pairs with `settings.open` (I25). | done (W14-settings-daemon, K32) |
| I37 | 2026-10-09 | W13-settings-ux report | Every island face has a label in the face picker/pick list: core faces (bluetooth, power, …) in the catalogue, mod faces from their manifest. | done (W14-settings-daemon, K32) |
| I38 | 2026-10-09 | W13-settings-ux report | `tools/bench/wl_keys.py`: modifiers (Alt, Shift, Ctrl) and Escape, so Alt+Up/Down and Esc paths get tested. | done (W14-settings-daemon, K32) |
| I39 | 2026-10-09 | W13-settings-ux report | Action ids in bindings are only checked syntactically (`foo` accepted for island.expand); validate against the action registry with an inert reason. | new |
| I40 | 2026-10-10 | W14-settings-daemon report | `settings.open {page}` and the Settings app reading a page deep link (today only `key`). | accepted |
| I41 | 2026-10-10 | W14-settings-daemon report | Profiles page UI for export/import (file picker or path field, review diff, apply) — daemon side exists (K32). | accepted |
| I42 | 2026-10-10 | W14-settings-daemon report | A `path` type in the schema so profile export drops machine-local paths by type, not by value heuristics. | new |
| I43 | 2026-10-10 | lead | Weather's "Set place" and inert rows' "Controlled by …" call `settings.open {key}` (K32). | accepted |
| I44 | 2026-10-10 | W13-island-views report | Expanded views for the K30 faces: `power` → quick settings Power page, `bluetooth` → Bluetooth page (Stage maps them; today the generic card). | accepted |
| I45 | 2026-10-10 | W13-island-views report | VolumeFace shows `detail.volume` ("Headphones · 40 %") when the daemon gives one — the OSD device-name DoD item. | accepted |
| I46 | 2026-10-10 | W13-island-views report | Calendar: event dots per day (needs a per-day slot contract), optional week numbers, week start by locale (ja often Sunday). | accepted |
| I47 | 2026-10-10 | W13-island-views report | Island peek as a Stage-hosted tooltip (B9) instead of the inline tail; screenshots for locked redaction, no-seek track, long titles, reduce-motion; ja shots for notifications/volume/brightness; idle-wakeup bench for the media 1 s timer. | accepted |
| I48 | 2026-10-10 | W14-mod-runtime report | Settings shows `running_reasons` ("Running now: rain alerts") instead of yes/no; a job-level `active` flag so a paused sysmon watch is not reported as running. | accepted — next wave: `JobCtx::set_active` (CONTRACT row 73), then sysmon calls it |
| B20 | 2026-10-10 | W14-mods-live (F1) | Wallpaper picker: a thumbnail answer after the panel closed hits a destroyed object (`ReferenceError: requestToken`). | done (W14-wallpaper-ux: callbacks gated on destruction) |
| B21 | 2026-10-10 | W14-mods-live (F4) | Weather without a place looks up `mod-weather.condition.undefined` and `mod-weather.uv.` (missing keys, not drawn). | fixed (W14-weather-ux, session 6: every key the code asks for exists) |
| I49 | 2026-10-10 | W14-mods-live report | The test mod `hello` has no i18n domain (`mods.hello.greeting`, `action.hello.*` would show raw); give it `mod-hello.toml` so the live test's raw-key scan covers the Mods page and launcher too. | new |
| I50 | 2026-10-10 | W13-quick-ux report | Mock parity for quick settings states: `brightness.set`, a `quick.tiles` contribution, a battery scenario (present:true), and a control to make a service unavailable/forced on demand (tile-level states). | accepted |
| I51 | 2026-10-10 | lead UX review | Quick settings tile on-state: tonal container (accent at low alpha) + accent icon instead of a solid crimson fill (several active tiles read as alarms); solid fill only for "needs attention". Token `quick.tile.on.*` in kurashi-theme. | accepted |
| I52 | 2026-10-10 | lead UX review | A size contract for `quick.tiles` contributions (same 160×56 tile, glyph/label/subtitle props) so mod tiles look native. | accepted |
| I53 | 2026-10-10 | W14-wallpaper-ux report | Stage: a mod panel may ask for a preferred width up to 720 px (the brief's picker), and the Stage tells panels its output origin (exact `grow` transition origin). | done (session 6: `cardWidth`, 360..720 px); output origin for `grow` still open |
| I54 | 2026-10-10 | W14-wallpaper-ux report | Free string-list settings (`type = "list"` without `choices`) for paths like wallpaper `folders` (today a colon string); Settings edits them with the existing list control. | accepted |
| B16 | 2026-10-09 | lead (live mod check) | Mod strings showed as raw keys and mod data was empty: mod QML imported `frontend/core` by relative path from a `file://` URL, creating a second, disconnected Store/I18n/Theme (the shell runs under `qs:@/qs/`). | done (session 5): mods import `qs.core` / `qs.components` (MODS.md) |
| B17 | 2026-10-09 | lead (live mod check) | ModLoader assigns `store/theme/i18n` to mod components that do not declare them (all three mods import the core singletons): QML warnings per load. | done (session 5): weather/wallpaper entry components declare the loader's required properties |
| B18 | 2026-10-09 | lead (live mod check) | Sysmon panel overflows the Stage card on the right ("Force quit", "Swap" clipped). | fixed (W14-sysmon-ux, session 6: 440 px card, one-line process rows) |
| B19 | 2026-10-09 | lead (live mod check) | Dates follow the system locale (German "Freitag, 9 Oktober") while the UI is en/ja: format with kurashi's locale (`i18n.locale`). | done (W13-island-views: dates in kurashi's language) |
| I55 | 2026-10-18 | lead (session 6 merges) | **Stage-hosted peek** for bar widgets (K35, lead design first): one shared surface (the Stage, K19) shows a widget's peek on hover/focus, anchored to it on its output; consumers sysmon (facts are its a11y description for now), weather (B22), tray tooltips (B9), island peek (I47). The daemon owns `runtime.ui.peek`, the mod supplies a `peek:<name>` component. | accepted |
| I56 | 2026-10-18 | W14-sysmon-ux report | Sysmon states not drawn live: bar activity/critical tint, no-sensor bar, bar sparkline, End/Force quit confirmation, trouble face, GPU-asleep tile, 328 / 720 px cards. Needs a fixture root for `/proc` + `/sys` (like weather's `KURASHI_WEATHER_API`) so the live test can drive them. | accepted |
| I57 | 2026-10-18 | W14-weather-ux report | Weather not verified in the real shell: places search/preview/save/move/remove click-through, stale aside in the real clock view, gear and "Set place" opening Settings, "Running now: rain alerts"; footer credit wraps at 368 px. | accepted |
| I58 | 2026-10-18 | lead (B23) | Sandboxed daemons in tests run without network (network namespace or a deny-by-default proxy), so no test can reach a real service even with a stale binary. | new |
| I59 | 2026-10-18 | lead (sysmon review) | Sysmon "Open in btop" spawns the terminal as a kurashid child; start it the way the launcher starts apps (own systemd scope), so it outlives a daemon restart cleanly and is accounted to the app. | new |
| I60 | 2026-10-18 | user (`INSPIRATION.md`) | Inspiration for look & feel: Vitreus, Capsule, pleamar (GitHub), a Project-Sekai-inspired Quickshell rice (r/unixporn). Feed into the next design pass (DESIGN-SYSTEM decor packs, motion) and the UX reviews. | new |
| I61 | 2026-10-18 | lead (sysmon screenshot review) | Sysmon names come from `comm` (15 chars): ".zen-twilight-w", ".quickshell-wra", "Isolated Web Co". Show the executable's basename (Nix wrappers: strip the leading "." and "-wrapped") or the app name from the desktop entry, with the full command line in the a11y description. | new |
| I62 | 2026-10-18 | lead (sysmon screenshot review) | Sysmon GPU tile on a hybrid shows the sleeping dGPU ("NVIDIA · no utilisation reported", value "–") while the active iGPU is a side line. The tile should follow the GPU that renders (the compositor's main device) and list the other as "asleep" (runtime PM), per the brief. | new |
| I63 | 2026-10-18 | lead (weather + sysmon screenshot review) | Colour roles: rain bars, the 7-day ranges and the hourly line all use the accent (crimson in wa-iro), which reads as alarm. Data marks need their own roles (e.g. `color.data.*`: rain/cool/warm) in kurashi-theme, like I51's tonal tiles. | new |

## Ideas (not planned)
| # | Date | Source | What | Status |
|---|---|---|---|---|
| D1 | 2026-10-09 | user | Bevy as a candidate in the next framework re-test (complex graphics, animations, minigame mechanics, complex surface merging). `docs/BAKEOFF.md`. | new |
| D2 | — | ROADMAP | Long idea pool: `docs/ROADMAP.md` "v0.2", "v0.3", "Later" (not duplicated here). | — |
| D3 | 2026-10-09 | lead | Wallhaven source for the wallpaper mod (network capability, API key via libsecret, thumbnail cache) — after the local-library v1 (K26, user: later). | new |

---

## Notes behind the bigger rows

### Island (I1, B1) — user proposal 2026-10-09, lead assessment
- **Faces = submodules.** Each face has a compact view (in the pill) and an **expanded view** (the card a
  click opens): media → transport + seek + art, notifications → the list, clock → calendar/agenda,
  volume/brightness → sliders + device picker. `island.expand` opens the expanded view of the face the
  daemon currently shows (latched at open, so the card doesn't switch under the pointer). Faces come from
  core and from mods (MODS.md "island faces" contribution); the user enables/orders them
  (`island.main.faces` exists in the schema).
- **Placements.** An island instance (`island.<id>`) is placed either as a *bar module* (today) or as a
  *standalone* surface (a floating pill, e.g. top-centre like a notch). Several instances are allowed
  (ARCHITECTURE §5 already arbitrates per instance). A standalone island is one more layer surface per
  output → it must fit the per-output budget (B7) or live on the focused output only.
- **"Island as a mod"** — agreed in effect, with one boundary: the *arbiter* (which face wins, relevance,
  TTL/OSD interrupts) stays in the daemon core, because relevance across mods is core business logic
  (rule 1) and the volume/brightness OSD relies on it. Everything the user sees — placement, faces,
  whether an island exists at all — becomes configurable/optional. With no island, transient OSD needs a
  fallback (a small Stage toast).
- Open questions for the K-decision: expanded views as Stage content (K19, one surface) vs. the island
  surface growing (standalone placement); how mod faces ship their expanded view (native QML component).

### Mods in Settings (I3) — user proposal 2026-10-09, lead assessment
- **Sidebar:** the **Mods** page stays (core: catalogue, install/load). Every *loaded* mod adds its page to
  the normal sidebar (alphabetical among the core pages, or a group after them) with a small indicator.
  A mod that is only *detected* (not loaded) has no sidebar page — only its Mods-page row.
- **States** (the daemon owns them; `mods` doc `state` today: available/enabled/disabled/invalid):
  `detected` (on disk, not loaded) → `loaded, off` (manifest + settings registered, contributions
  inactive; the page shows a native on/off switch) → `on` (contributions live) → `on, in use` (one of its
  services has a subscriber / its face is shown). Needs a contract change: a load/activate split and an
  `in_use` flag, plus a config key for the per-mod on/off (`mods.<id>.active` or similar; K22).
- **Indicator:** from theme tokens (e.g. a new `color.status.active` role, rule 4 — no hard-coded green),
  and never colour alone (shape/fill + accessible text: colour-blind modes are on the roadmap).
- Cost rule (Ma): `loaded, off` must cost ~0 — no services, no surfaces, no timers.

### Wallpaper (I7) — first native mod, design first
- Daemon side (Rust, the mod's service): wallpaper state per output (path/source, fit, rotation timer
  only while rotation is on), a library (folders), actions `wallpaper.set/next/prev`, and the hand-off to
  the theme pipeline (DESIGN-SYSTEM §2 stage 1 `source = wallpaper`, material-colors → palette).
- **Rendering — decided by the user (2026-10-09): an external wallpaper daemon draws it**, selectable in
  Settings from a dropdown (I9): **awww** (the renamed swww) and **swww**; if only one can be supported at
  first, awww/swww. Zero frontend cost (a full-output texture would be ~14 MiB per 2560×1440 output, far over
  the per-output budget). One small adapter per backend in the mod's Rust service (start/attach to its
  daemon, set image per output with fit/transition); the option list shows which backends are installed,
  a missing one is disabled with its reason. Others (wpaperd, swaybg) and an own renderer (video,
  animated) later.
- Frontend: a picker panel (Stage) with thumbnails (decoded at thumbnail size), a settings page (K22).
- Later: Wallhaven source (network capability, API key via libsecret), video wallpapers, per-workspace.
