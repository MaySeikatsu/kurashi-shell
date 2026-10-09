# Decisions (K-ids)

Format: **K#** status — decision. *Why* (lesson / evidence). Status: 🟢 decided · 🟡 provisional
· 🔴 revoked. Cite K-ids in code comments where a decision explains non-obvious code.

**K1** 🟢 Mods are renderer-independent: `mod.toml` + daemon logic; native tier (v0.2) for
first-party, portable tier (declarative UI + Luau) in v0.3; WASM only on demand.
*Why:* noctalia v5 proved manifest + Luau + typed settings ([plugin docs](https://docs.noctalia.dev/noctalia/plugins/development/));
decoupling mods from the renderer keeps the framework choice reversible. shellseikatsu plugins
shared the main engine with no isolation.

**K2** 🟢 Daemon-first: `kurashid` (Rust) owns all state, config, theming, services, actions,
mods; frontends are thin views; Settings is a separate on-demand process.
*Why:* shellseikatsu had 109 Processes and logic spread over 60 QML singletons; WormShell D1/D2;
DMS's Go backend; services survive any renderer swap.

**K3** 🟢 Renderer = **Quickshell (Qt 6 / QML)** as the thin view over `kurashid` (decided by the M0
bake-off, 2026-10-09). Only candidate passing all hard gates (xdg_popup on layer surfaces, session
lock, ext-background-effect binding, IME); idle-silent (0 wakeups, ~0 commits); only one with hot
reload; ~4× cheaper per agent task (103k tokens / 7 min vs ~180k / 30 min). Score 8.7 vs gtk4 6.2,
slint 6.1, iced 5.2, gpui 2.5 (matrix in `BAKEOFF.md`).
*Why not the others:* gpui — `gpui_linux` re-arms `wl_surface.frame` and commits forever (61
commits/s idle), no session lock, KDE blur only ([zed gpui_linux](https://github.com/zed-industries/zed/tree/main/crates/gpui));
iced — no blur yet, 118 wakeups/s + 233 futex/s idle, no screencopy ([iced_layershell](https://github.com/waycrate/exwlshelleventloop));
slint — custom platform has no IME, no shader API, CPU-only (its 25 MiB is the software renderer);
gtk4 — no session-lock API, popups only as 2nd layer surface (+77 MiB), GskGLShader dead in 4.22.
*Re-evaluation clause (user, 2026-10-09):* reopen with a fresh bake-off if Quickshell restricts a
feature, the feel goal (quick, smooth, polished, snappy) or quick iteration, or a native stack
passes IME + blur + lock with hot reload. Mods stay renderer-independent (K1) and the probes stay in
`archive/bakeoff-probes/` as the re-run baseline. Known cost: memory over budget → K16.

**K4** 🟢 IPC framing is NDJSON (not length-prefixed).
*Why:* trivially parsed by every candidate frontend (QML `SplitParser`, GLib, tokio
`LinesCodec`); JSON escapes newlines so framing is unambiguous. Supersedes WormShell D42.

**K5** 🟢 Provenance everywhere: every resolved value is `{value, source, forced_by?, reason?}`;
resolution `default → theme → profile → user → forced`, per output.
*Why:* shellseikatsu sliders were silently overridden by presets; shaders ran with toggles off.

**K6** 🟢 One schema source: Rust types + `#[kurashi(...)]` derive generate defaults, validation,
settings pages, example config, docs.
*Why:* shellseikatsu kept ConfigService (330 props), SettingsSchema and docs in sync by hand.

**K7** 🟢 Profiles are full snapshots with section-level partial load as one transaction, diff
preview and undo. *Why:* user decision 2026-10-08.

**K8** 🟢 Decor pack = typed slots + recipe at layer `theme:<pack>`; no renderer branches on
theme names. *Why:* 14 preset-name branches in 6 shellseikatsu files.

**K9** 🟢 Island (島) arbitration is daemon-side and deterministic: pinned > transient(TTL) >
relevance > default. *Why:* testable, consistent across outputs and renderers.

**K10** 🟢 Universal input slots (left/right/middle/hover/scroll ±shift) bound to Actions with
schema defaults, user-overridable per type/instance. *Why:* user requirement; one model (Kanso).

**K11** 🟢 Nix-first: flake (devShell, packages, NixOS + HM modules, systemd user units) from
M0. *Why:* user requirement; reproducible agents and benches.

**K12** 🟢 License GPL-3.0-or-later. *Why:* compatible with Quickshell (LGPL), iced (MIT),
reference shells; keeps forks open.

**K13** 🟢 i18n (en, ja) from day one via string keys. *Why:* Japanese copy is part of the
identity; retrofitting i18n is expensive (WormShell D30 deferral rejected).

**K14** 🟢 Session handover: every session ends by updating `docs/HANDOVER.md` (state, next
steps, open decisions, pickup prompt). *Why:* user requirement; multi-session project.

**K15** 🟢 Nix-declared settings form their own provenance layer `nix`
(`default → nix → theme → profile → user → forced`), read from `~/.config/kurashi/managed.toml`
(Home-Manager `programs.kurashi.settings`); `enforce = true` turns them into `forced:nix`. The
daemon keeps writing the live `config.toml`. *Why:* HM files are read-only store symlinks, which
conflicts with a daemon-written config; users still see "set by Home-Manager" in Settings.

**K16** 🟡 PSS budget revised: v0.1 frontend PSS ≤ **150 MiB @ 1 output, +≤ 6 MiB per extra output**
(was "≤ 50 % of shellseikatsu" = 108 MiB). *Why:* every GPU-rendered candidate measured 144–156 MiB
at 1 output on NVIDIA (bake-off quiet run); the trivial Quickshell floor is already 110 MiB
(libnvidia 27 · Qt 21 · ICU/fonts/other libs 49 · heap 46). 108 MiB is unreachable without software
rendering, which costs shaders and smooth animation. The shellseikatsu comparison stays as a
reported ratio (probe = 67 % of 216 MiB). Kaizen targets: ICU data, unused Qt modules, lazy popups.


**K17** 🟢 Protocol v1 completed for the M1 freeze: typed `apply` ops (`set`/`reset`, optional
`output`, `dry_run` → `preview`), `cfg.why` layers with one `active`, typed `rejected` errors
(`code` = i18n key), `done.data`, server-pushed `snap` without `id`, `welcome.instance`, the
`config` / `schema.settings` / `i18n` documents, and **daemon patches = merge-patch diff of
old → new** (`kurashi_ipc::diff_patch`, documents contain no `null`). All additive for the probe
subset. *Why:* RFC 7396 can't delete a member without an explicit `null`; a hand-written patch
would leave stale `forced_by`/`reason` on screen — a Shōjiki violation. Diffing makes every
patch exact by construction (property-tested). Instance ids avoid trusting cached revisions
across daemon restarts.

**K18** 🟢 Loading a profile clears the user overrides in the loaded sections (all sections when
none are given), in the same undoable transaction. *Why:* a profile that loads "successfully" but
changes nothing visible because older user pins win would be dishonest (Shōjiki); the diff
preview shows the cleared pins and undo restores them. Forced values are never saved into or
cleared by profiles. (`kurashi-config`, M1.4.)

**K19** 🟢 The Stage is one content-sized overlay layer surface, permanently mapped but transparent,
input-less and rendering 0 frames while hidden, retargeted to the focused output. *Why:* unmapping
per open leaked ~5 MiB/cycle; per-output stages, PopupWindow and destroy/recreate all measured worse.
Popup-open PSS 221 → 112 MiB. **Budget:** an interim raise of the per-output budget to +10 MiB was
reverted the same day — the bench gate (M7.2) now measures the second output against the
popup-closed reading (popup memory stays resident after closing) and finds **+0.8 MiB**, so +6 stands.

**K20** 🟢 A locked session survives daemon restarts and crashes: `kurashid` writes a `locked`
marker next to its socket in `$XDG_RUNTIME_DIR/kurashi/` while locked and starts locked when it
finds one; the frontend stays locked while disconnected (and the compositor keeps the
ext-session-lock if the frontend dies). *Why:* the lock-UI work showed a restarted daemon reported
`locked:false` and the surface unlocked — killing a process must never unlock the screen. The
runtime dir is cleared on logout, so a stale marker can't outlive the session.

**K21** 🟢 The daemon reports *why a value has no effect*, not just who set it. `Provenanced` gains
an optional `inert_by` (config key). (1) `requires` couplings are evaluated in the daemon over
effective values: an inert dependent keeps its `value`/`source` and carries `reason` (the
coupling's key, e.g. `settings.inert.requires`) + `inert_by` (the required key); clients format
"{key} is {value}" from the schema coupling. (2) A `restart`-flagged key whose configured value
differs from the one its service started with carries `reason: "settings.pending.restart"`.
`forced_by` keeps meaning "the value was replaced"; `reason` without `forced_by` means "configured
but not in effect". Additive and optional, so protocol v1 stays compatible (K17).
*Why:* the M5 honesty test (wave 7) found 9 inert-by-requires cases where `cfg.get` reported no
reason; only the settings app evaluated `requires` client-side (business logic in a view, rule 1),
and restart keys showed new values as in effect before they were (rule 2).

**K22** 🟢 Mod settings are ordinary config keys under `mods.<id>.<key>`, declared by the mod's
`[[setting]]` entries and validated against that declaration. They get the same layers and
provenance as schema keys (default from the manifest → profile → user → forced), appear in
`schema.settings` as one page per enabled mod ("Mods › <name>"), and stay stored while the mod is
disabled (the Mods page promises "a mod that is off keeps its settings"). A disabled mod's keys are
reported inert with `reason: "mods.disabled"` (K21 semantics), never deleted.
*Why:* rule 3 (one schema) — mods must not grow a parallel settings system; M6 exit criterion
"settings pages appear".
*Addendum (session 4, C-mod-sections):* each mod is its own profile section `mods.<id>`; section filters
match whole segments (`mods` = every mod, `mods.med` = nothing). Two-segment keys (`mods.enabled`) stay
in `mods`. Relies on mod ids and setting keys containing no `.` (enforced by the kurashi-mods manifest).

**K23** 🟢 A tray item's menu is a Stage panel, not a window of its own. Action `tray.menu.open
{id}` sets `runtime.ui` to `{panel:"tray", tray:"<item id>"}` (the same item again closes it,
another item switches; every other panel and `ui.close` reset `tray` to `""`). The frontend fetches
the tree with `tray.menu` (action data, once per open) and renders it in the one Stage card, aligned
to where the tray sits; entries send `tray.menu_event`. Additive field + action (K17).
*Why:* K16/K19 — map/unmap cycles of a popup window leave ~5 MiB of heap behind per cycle, and the
per-output PSS budget is already at its limit; rule 1 — which menu is open is daemon-owned UI state
like every other panel, so keyboard bindings and mods can open it too.

**K24** 🟢 Island model (user + lead, session 5; BACKLOG I1, B1, I2). The **arbiter stays daemon core**
(which face wins, relevance, TTL/OSD interrupts — rule 1; the OSD depends on it). Everything the user
sees becomes configurable: island *instances* (`island.<id>`), their *placement* (bar module today;
standalone surface later), their faces (core + mod faces, user-ordered) and whether an island exists at
all; with no island, a transient OSD falls back to a small Stage toast. **Each face = compact view (pill)
+ expanded view.** `island.expand` opens the expanded view of the face shown at that moment, latched for
as long as it is open (`runtime.ui` carries the face), as Stage content (K19, one surface); first expanded
views: media, notifications, clock, volume/brightness. Bluetooth (later network, audio devices, power)
moves to a **quick-settings card** (bar widget → Stage panel). **Order (user):** expanded views first; the
standalone placement only after the per-output PSS work (B7) has freed budget, focused output first.
*Why:* DESIGN-SYSTEM §8 already promised "left click → expanded view"; the first live run showed a generic
card instead (B1). Relevance across core and mods is business logic and must not live in a view or a mod.

**K25** 🟢 Mods in Settings (user, session 5; BACKLOG I3). Each *loaded* mod gets its page in the normal
Settings sidebar, **sorted alphabetically among the core pages**, with a small state indicator:
hollow ring = loaded, off; filled dot = on (token colour `color.status.*`, never colour alone: shape +
accessible text). A mod that is only *detected* has no page, only its Mods-page row; the Mods page stays a
core page (catalogue, install/load). **No "in use" state in the sidebar** (user: its benefit did not
justify the noise of a dot that changes as panels open); instead the mod's own page and its Mods-page row
show a text line "Running now: …" (which of its services has a subscriber). Contract: `mods` document
gains the loaded/on split and a per-mod `running` flag; per-mod on/off is a config key under K22.
*Why:* mods are first-class settings citizens (rule 3: same generated pages); cost transparency (Ma) where
the user looks for it, without sidebar noise.
*Addendum (lead, session 5):* loaded/on are config lists `mods.loaded` / `mods.enabled` (enabled ⊆ loaded)
and the four `mod.*` actions are config writes; the daemon reconciles the registry to them. Found while
designing: enablement was not persisted at all (only startup policy), so a mod switched on was off again
after a restart (BACKLOG B11). As config it persists, has provenance, works with Nix/forced, undo and
profiles. `state` keeps its values (protocol v1 frozen, K17): `disabled` = loaded, off. Details: MODS.md
"States, persistence and Settings"; shapes: PROTOCOL §5, `fixtures/ipc/server/snap_mods.json`.

**K26** 🟢 Wallpaper = the first native mod; drives the native-mod mechanism (MODS.md "Lifecycle").
Rendering by an **external daemon, awww / swww** (user, session 4), selected from a dropdown (BACKLOG I9:
daemon-resolved choices; a backend that is not installed is shown disabled with its reason). v1 = local
library folders, per-output state, `wallpaper.set/next/prev`, optional rotation timer (only while on),
theme source `wallpaper` (DESIGN-SYSTEM §2), Stage picker panel. **Wallhaven later** (user, session 5).
Mechanism (lead, session 5; MODS.md "Native mods"): a native mod is a crate linked into kurashid
implementing `NativeMod`; on enable it registers through a `ModCtx` exactly what its manifest `provides`
(refcounted documents, `<id>.*` actions, faces, choice sources), and disable drops every registration;
its QML ships in `mods/<id>/qml/`, announced as file URLs in the `mods` document and loaded by the
frontend only where placed or opened. *Why:* zero frontend cost — a full-output texture would be
~14 MiB per 2560×1440 output, far over the per-output budget.

**K27** 🟢 Small additive contract changes (session 5; CONTRACT rows 20–22, all optional/additive, K17):
`svc.tray` items carry `item_is_menu: true` for SNI `ItemIsMenu` items (omitted otherwise); the `config`
document carries `history {can_undo, can_redo}` and `profiles [{name, bundled}]`, kept current by the
daemon (watcher for profile files); profile actions answer errors with i18n keys (`config.error.*`).
Pinned by `fixtures/ipc/server/snap_{tray,config}.json`. *Why:* Settings derived undo state from replies
and fetched profiles once per connection — client-side state the daemon already owns (rule 1, B6, row 21).

**K28** 🟢 Modules combine through **contribution slots**, mod **Island faces** and mod **choice sources** (lead,
session 5; user: "think what this can become", `docs/ux/COMPOSITION.md`). (1) Core views declare named slots
(`clock.expanded.aside`, `clock.expanded.day`, `clock.expanded.footer`, `media.expanded.below`,
`media.expanded.backdrop`, `notifications.expanded.header`, `quick.tiles`, `lock.aside`); a mod fills one by
declaring `slot:<name>` in `provides` and shipping `qml/slots/<name>.qml`. The daemon publishes `runtime.slots`
`{"<slot>": [{"mod", "qml", "ready"}]}` — enabled mods only, `ready` = the mod's primary document is `available`
— and the frontend instantiates contributions only while the hosting view is shown; a not-ready or absent
contribution takes no space. (2) A mod's `island-face:<name>` registers with the core arbiter through `ModCtx`
(transient or relevance-driven, with TTL); its components are `qml/Face.qml` (compact) and `qml/FaceExpanded.qml`
(the expanded view, K24). (3) `ModCtx::choices(source, fn)` offers a `choices_from` source (CONTRACT row 28).
(4) `mod.panel.open {id, panel}` opens a mod panel as Stage panel `mod:<id>:<panel>`. The core never names a mod
(rule 4); relevance stays in the core arbiter (K24). Per-slot user order/hide: later (BACKLOG).
*Why:* related modules must meet in one view (clock + calendar + weather, media + lyrics) without the core knowing
them, and mod features must reach the Island and dropdowns the same way core features do.

**K29** 🟢 Quick settings' daemon pages (lead, session 5; CONTRACT row 34, W13-quick-daemon). The Wi-Fi list is its own
refcounted document `svc.network.scan` (a scan every 15 s only while subscribed — GNOME scans only while its menu is
open), not a field of `svc.network`; `network.connect` joins saved networks only and refuses others honestly
(`error.network.needs_secret` secured, `error.network.not_saved` open) until password entry exists; `svc.audio` gains
sources/streams with their actions, `svc.power` the power-profiles-daemon profile (absent + `profile_reason` without
it), `svc.notifications` `dnd_until` (a daemon timer only while set). *Why:* `docs/ux/quick-settings.md`; Ma (no scan
while closed), Shōjiki (no claimed password need for open networks).

**K30** 🟢 Island outputs and core transient signals (lead, session 5; CONTRACT row 35, W13-island-daemon,
`docs/ux/island.md`). `runtime.island.main` adds `secondary?` (next live activity of another face), `overflow` (always
present), `detail?` (per-face peek line) and `stale_at?`, decided deterministically by the arbiter. Core transients:
charger in/out, battery low ≤ 10 % / critical ≤ 5 % (once per crossing), Bluetooth device connected, default output
moved (OSD names a non-usual device) — each once per state change, TTL from `island.main.ttl`. **Ma exception:** the
island keeps `svc.power` and `svc.bluetooth` subscribed for the daemon's lifetime (event-driven, no timers) — without
it the shell could not announce a plugged charger; follow-ups: absent bus names wait for NameOwnerChanged instead of
the ≤ 30 s retry, and a key to turn system transients off (BACKLOG I17, I18); measure laptop idle wakeups (bench).

**K31** 🟢 `svc.media` carries honest progress (lead, session 5; W13-media-position, BACKLOG I19). `position_us` +
`position_at_ms` (wall time of the read) + `rate`; Position is never polled — read on first subscriber, player change,
track change, play/pause, rate change and Seeked; the view interpolates `position_us + (now − position_at_ms) × rate`
while playing; no `length_us` (live streams) means no progress bar. `can {seek, next, prev, play, pause}` gates the
controls (replaces `can_next/can_prev/can_seek`), `players[].active` + `media.player.select {id}` drive the switcher,
`media.seek {offset_us}` / `media.set_position {us}` are refused with `error.media.cannot_seek` when not allowed.
*Why:* `docs/ux/island.md` media view; Ma (no polling) and Shōjiki (a frozen or guessed position would lie).
