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
| B1 | 2026-10-09 | user, first live run | **Island click opens a generic card** (title, Bluetooth, Close) instead of the expanded view of the face it shows. Contradicts DESIGN-SYSTEM §8 ("left click → expanded view"). See I1. | accepted |
| B2 | 2026-10-09 | lead review | Bar volume slider shows 0 % when `svc.audio` is `available:false` (no audio server): a value that is not in effect (rule 2). Hide or mark the slider unavailable. | accepted |
| B3 | 2026-10-09 | L-logind report | `brightness.rs` still calls `SetBrightness` on `session/auto`: fails for a `systemd --user` daemon. Reuse the session resolver of `session.rs`. | accepted |
| B4 | 2026-10-09 | lead review (C-services) | A tray that cannot start (watcher name owned by another shell) retries every 30 s while a bar is visible: a small idle wakeup. Wait for `NameOwnerChanged` instead. | accepted |
| B5 | 2026-10-09 | S-settings report | Profile actions answer `kind: invalid` + English text, so Settings can only show "(code: invalid)". Send i18n codes like the mods actions do. | accepted |
| B6 | 2026-10-09 | S-settings report | Profiles page: "No profiles found" stays after a profile file appears (refreshes only on reconnect). | new |
| B7 | 2026-10-09 | bench (BENCH "after wave 8") | Per extra output PSS +4.7…+6.7 MiB on machine B iGPU (budget ≤ +6): at the limit on both machines. Attribute (A/B runs), then cut per-bar cost. | accepted (next step 1) |
| B8 | 2026-10-09 | lead review | Settings: an invalid mod reads "mod.toml is missing (mod.toml)"; a row's "Rejected" line stays after unrelated changes. Copy/lifetime polish. | new |
| B9 | 2026-10-09 | B-tray report | Tray tooltips are not shown on hover (a tooltip needs a surface outside the bar; K16/K19 forbid per-hover windows). Needs a design (Stage-hosted tooltip?). | new |
| B10 | 2026-10-09 | lead (machine B) | `sandbox.sh` defaults to the first render node, which is the dGPU on hybrids (runtime-PM stalls in tests). Default to the `boot_vga` GPU. | new |

## Improvements
| # | Date | Source | What | Status |
|---|---|---|---|---|
| I1 | 2026-10-09 | user | **Island model, three levels** (see "Island" below): island *placements* (a bar module as today, or a standalone island surface), island *faces* as submodules the user scrolls through and the UI reacts to (core faces + mod faces, user-ordered), and the island itself optional like a mod. Click = expanded card of the current face. | accepted — needs a K-decision |
| I2 | 2026-10-09 | lead (follows I1) | A home for Bluetooth (and later network, audio devices, power): a quick-settings card (bar widget → Stage panel), not the island. | accepted |
| I3 | 2026-10-09 | user | **Mods in the Settings sidebar** (user's preferred option): each loaded mod gets its page in the normal sidebar next to Launcher, Notifications…, with a small state indicator; the Mods page stays a core page (install/load). See "Mods in Settings" below. | accepted — needs a K-decision + contract |
| I4 | 2026-10-09 | B-tray report | CONTRACT row 20: `item_is_menu` on `svc.tray` items (frontend already reads it). | accepted |
| I5 | 2026-10-09 | S-settings report | CONTRACT row 21: `config.history {can_undo, can_redo}`; Settings drops its reply-derived flags. | accepted |
| I6 | 2026-10-09 | S-settings report | Move `settings/keys.py` and the virtual pointer of `frontend/test-bindings.sh` into `tools/bench/` (CONTRACT #6). | accepted |
| I7 | 2026-10-09 | user | **Wallpaper management** as the first native mod (see "Wallpaper" below). Rendering decided by the user: an external daemon, **awww / swww**, chosen from a dropdown (I9). | accepted — next |
| I8 | 2026-10-09 | lead (user's live test) | Compositor keybindings for kurashi actions (launcher, session menu, centre, volume/brightness keys): document a niri snippet (`spawn "kurashi" "act" "launcher.toggle"`) and/or let the HM module emit it. Without it the shell can only be driven by mouse and CLI. | accepted |
| I9 | 2026-10-09 | user | **Choices instead of freeform text** in Settings: string keys with a known option set get a dropdown (Segmented stays for ≤ 4 fixed options). Today freeform: `theme.colors.palette`, `island.main.default`, `island.main.faces` (should be an ordered pick-list). Options are often dynamic (palettes incl. mod palettes, island faces incl. mod faces, installed wallpaper backends), so the daemon resolves them into `schema.settings` rows (one schema, rule 3: e.g. `#[kurashi(choices_from = "palettes")]`); an option that cannot work right now (backend not installed) is shown disabled with its reason (rule 2). | accepted |

## Ideas (not planned)
| # | Date | Source | What | Status |
|---|---|---|---|---|
| D1 | 2026-10-09 | user | Bevy as a candidate in the next framework re-test (complex graphics, animations, minigame mechanics, complex surface merging). `docs/BAKEOFF.md`. | new |
| D2 | — | ROADMAP | Long idea pool: `docs/ROADMAP.md` "v0.2", "v0.3", "Later" (not duplicated here). | — |

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
