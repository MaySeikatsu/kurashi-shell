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

**K32** 🟢 Settings reachable from anywhere, profiles portable (lead, session 5; W14-settings-daemon, CONTRACT row 54).
`settings.open {key?}` (registered with the config store: it validates the key) jumps a running Settings window or launches
one detached with `KURASHI_SETTINGS_KEY` (no shell); `kurashi settings [<key>]` goes through it. `profile.export {name, path}`
writes a profile without machine-local values (per-output, paths — value-based until the schema has a path type, BACKLOG),
`profile.import {path, apply?}` reviews (dry run) or loads as one transaction; `profile.preview`/`load` answer `not_applied`
for keys a forced layer holds (Nix, capability, accessibility). Face offers carry labels (`config.face.<id>` or the mod's name).
*Why:* `docs/ux/settings.md` DoD 4 and 7; weather's "Set place", inert rows' "Controlled by …" links.

**K33** 🟢 Mod runtime completed (lead, session 5; W14-mod-runtime, CONTRACT rows 55–60). Background jobs:
`ModCtx::background(name, reason, wanted_by, run)` declares `job:<name>` (manifest provide) and runs while the mod is on and
its bool setting is true; the `mods` doc reports `running_reasons` (`mods.running.subscribed` + job reasons), `running` =
non-empty. Manifest `type = "list"` settings (string lists over fixed choices → `pick_list`). Capabilities `fs:read`,
`proc:signal`, `exec:<binary>`. B15: a native mod whose manifest declares daemon kinds (service/action/island-face/choices/
job) but whose code is not linked is refused (`mods.error.not_built`); frontend-only mods enable as before. Consequence: no
bundled mod is on by default (easter-eggs has no code yet). *Why:* honest "Running now" (weather rain alerts, sysmon watch),
no "on" that does nothing (rule 2).

**K34** 🟢 Theme source `wallpaper` in the shell (lead, session 6; CONTRACT rows 65, 67; W14-wallpaper-ux). Palette
`wallpaper` takes the colours of `mod.wallpaper.theme.image` — the picture the mod last applied *with* its theme (the
picker's theme switch), not merely the current wallpaper, so "wallpaper only" keeps the theme. Offered in `palettes`
while the mod serves its document. The daemon holds a subscription to `mod.wallpaper` while the palette is chosen,
because a native mod's service fills the hub only for subscribers: an unwatched snapshot may be stale, so it counts as
no picture (Shōjiki). No picture → the default palette with the theme note `theme.note.wallpaper_waiting`, never a
half-applied theme; extraction runs on a blocking thread and is cached by path + mtime + size. Event-driven (hub
stream filtered to `mod.wallpaper`, `mods`, `config`): nothing runs while neither the picture nor the palette changes
(Ma). *Why:* DESIGN-SYSTEM §2 (wallpaper as a source), `docs/ux/wallpaper.md` (Apply with theme, theme diff);
matugen/DankMaterialShell/Caelestia derive the scheme from the wallpaper the same way, but on every wallpaper change —
here the user decides per picture.

**K35** 🟢 Accepted by the user (session 6; I55, B9, B22, I47): **the Stage hosts peeks.** A bar widget's or the island's peek
(hover / keyboard focus) is drawn by the one Stage surface, never by a popup surface per widget (K19 measured
PopupWindow worse; per-widget popups would multiply per output). Contract (PROTOCOL §8): `runtime.ui.peek` =
`{source, output, x, w}` or absent (no `null` in documents); action `ui.peek {source, output, x, w}` / `ui.peek {}` from the frontend
(hover enter / leave with a 250 ms grace; latest wins); `source` = `mod:<id>:<name>` (manifest provides
`peek:<name>`, a QML component) or a core source (`tray:<item>` tooltip, `island:<instance>`). A peek never shows while
a card is open, and opening a card clears it. The Stage anchors left with a margin of `x` for a peek (centred for
cards), sizes to the peek, and keeps 0 frames / no subscriptions while none shows (Ma). Open in the frontend step:
measure the retarget cost of a hover on another output (B7 budget, quiet machine), and whether the daemon round trip
(~ms) feels instant. **Measured (W16, machine B iGPU, two outputs, shared machine — re-measure quiet):** idle 0
Wayland commits / 10 s; first peek +1.8 MiB PSS (fade 20 commits, then 0 while held); first use of the second output
+2.7 MiB more; 20 warmed hover cycles −2.2 MiB, 20 retarget cycles −0.3 MiB (no growth). *Why:* one surface for every transient (K19); honest, daemon-owned UI state (rule 1); four
consumers waiting (sysmon, weather, tray tooltips, island peek).

**K36** 🟢 Profile load is an overlay (user decision, session 6; B13, CONTRACT row 81; W15-profiles). Loading a profile
replaces only the keys it sets (within its sections): the user's values for those keys on every output, and earlier
profiles' entries for them. Every other user change stays; "Reset to defaults" is a separate, explicit action. A key a
forced layer holds back keeps the user value (inert, shown as not applied). Previews list what changes ("your change
replaced") and `kept_user`. *Why:* loading "roomy" wiped an unrelated History size (B13); KDE global themes and
macOS focus profiles change only what they contain; a profile is a story about some settings, not a reset.

**K37** 🟢 Test sandboxes have no network (lead, session 6; I58, B23, CONTRACT row 84; W16-test-infra). `tools/bench/sandbox.sh`
holds a user + network namespace with loopback only (`netns-hold.py` execs sway inside it); every process started with
the sandbox's env lines joins it before `main()` through `LD_PRELOAD=netjoin.so`, and **fails closed** (exit 111) when
the holder is gone or the namespace is not the recorded one. `sandbox.sh start` runs `netcheck.py` (interfaces,
connect, HTTPS must fail) and refuses a sandbox that reaches a network; `KURASHI_SANDBOX_NET=1` opts out (no test does).
Known gaps: name lookups still go to the host nscd over its unix socket (no route exists); a shell that keeps the
eval'd env after `sandbox.sh stop` cannot start processes — unset `LD_PRELOAD KURASHI_SANDBOX_NETNS_PID
KURASHI_SANDBOX_NETNS_ID`. **Amended (session 7, row 94, B26):** a process already in a network namespace with loopback
only runs as it is — Chromium's sandboxed zygote and renderers start in an empty namespace of their own and cannot open
the holder's; the host namespace still fails closed. *Why:* a stale sandbox daemon fetched the real Open-Meteo forecast (B23); tests must be
hermetic by construction, not by every test remembering a fixture hook. Evidence: the `netcheck` lines in
`frontend/test-stage.sh` and `test-real.sh` logs.


**K38** 🟢 Web dock (user decisions, session 7; BACKLOG I68; `docs/ux/webdock.md`). A native mod `webdock` ("Web dock", off
by default): a dock at one screen edge (right by default; left/right/top/bottom) with hidden / compact / extended modes,
pinned open or hover-driven, whose pins are sites or kurashi views (mod panels). **Web content runs in its own
on-demand process** — the web host, a Quickshell config with QtWebEngine — that the daemon starts on the first web open
and stops after `unload_after` minutes (default 60) without a shown site; the indicator and the icon strip are drawn
by the shell (a mod surface), so a hover reveals at once while the engine is cold. The daemon owns the mode state
machine, the pins (config) and the host's lifecycle. **Engine = Chromium (QtWebEngine 6.11):** Gecko has no embedding
API on desktop Linux (Mozilla dropped embedding in 2011, GeckoView is Android-only:
[LWN](https://lwn.net/Articles/436456/)) and Zen removed its own web panels (April 2025), and ungoogled-chromium is a patch set for the
full browser, not for QtWebEngine. The engine is **ungoogled by configuration**: Qt strips Google's services (Safe
Browsing, sync, translation, Google geolocation: [wiki.qt.io](https://wiki.qt.io/QtWebEngine)), the host turns off
the rest (push service — it would use FCM —, DNS prefetch, `<a ping>`, WebRTC on public interfaces only, background
networking), and a test proves it: with local pages open for 45 s Chromium's net log recorded **zero requests** of the
engine's own (the same log records a page's request, so the method sees traffic). A QtWebEngine build with
ungoogled-chromium's patches would cost a multi-hour source build per Qt update and a rebase per release; only if the
test finds traffic (BACKLOG I76). **Browser bridge** = the user's default browser (`xdg-open`; Zen on the user's
machine, never hard-coded): "open in browser", new-tab links, clipboard, drag and drop; browser bookmarks and hybrid
pins (a pin in the browser's own window) later (I70, I75). Logins cannot cross engines: one profile per pin, or a named
profile shared by pins. **Mobile view** =
mobile user agent + phone width, a per-pin view the user flips — never a per-site workaround for sign-in checks;
Google may refuse sign-in in an embedded engine (documented, no spoofing). *Why:* Phase 0 (headless sway, machine B,
2026-10-19): one WebEngineView in a Quickshell PanelWindow costs **255–262 MiB PSS in the hosting process** plus two
zygotes (~79 MB RSS each) and the page and GPU processes — more than the whole frontend budget (K16, 150 MiB) — and
Chromium's browser process must not share a process with the lock screen (K20); in-process WebEngine cannot be
unloaded, a process can. Settings is such a process already (K2). Floorp's panel sidebar (container per panel, mobile
user agent option, open on hover, click to keep) is the closest model; Edge is removing its sidebar apps (Edge 149).

**K39** 🟢 The web host runs on a **patched Quickshell**; the shell keeps stock Quickshell (K3; user decision, session 7).
Stock 0.3.1 and upstream master create the application with `argc = 0`, and QtWebEngine aborts ("Argument list is
empty, the program name is not passed to QCoreApplication"). `nix/patches/quickshell-webengine.patch` passes `argv[0]`
and adds `//@ pragma ShareOpenGLContexts` (sets `Qt::AA_ShareOpenGLContexts` before the application exists, Qt's
documented requirement for QtWebEngine in QML). Phase 0 with the patch, with and without the pragma: the view renders in
a layer-shell PanelWindow (`keyboardFocus: OnDemand`), takes typed text (wtype), keeps a disk profile, and Chromium's
sandbox stays on (zygote in its own namespaces). The patch goes upstream; the override goes when a release carries it.
Open (host card): a nested-niri run, the first keystroke was lost, and the test sandbox's `netjoin.so` refuses
Chromium's sandboxed zygote (it runs in its own empty network namespace) — the spike cleared `LD_PRELOAD` for the host's
children (they inherit the namespace); the host card amends K37 instead (row 94). Spike files:
`archive/spikes/webengine-phase0/`. *Why:* the host reuses kurashi's QML kit, Store/Theme/I18n and IPC client; the
alternative (a C++ host) duplicates them for a two-line patch.

**K40** 🟢 Web dock hover, sizes and web rules (user review, session 8, 2026-10-20; `docs/ux/webdock.md` "User
decisions (session 8)", CONTRACT rows 88, 109–111). A rest on the edge reveals the strip **and the last page**
(`reopen_last`, on); a click on the shown pin's icon puts the page away; a click into the dock keeps it until keyboard
focus leaves. Reveal 250 ms (500 ms on an edge shared with another output), hide 400 ms with 24 px grace — **driven by a
daemon state machine** fed `webdock.hover`/`webdock.engage` by the shell and the host, never by raw enter/leave in a
view (Firefox bug 2054033: a hover sidebar stuck open after rapid enter/leave). Strip 56 px, phone 412 × ≤ 2× width,
large 90 %; pinned overlays, *reserve space* optional and strip-only; `Mod+B` via Home-Manager; kurashi views = mod
panels. **New tabs stay in the dock** (`new_tabs = dock`, the link loads in the pin's own view and Back returns), a
setting sends them to the default browser instead — the user's call over the brief's "new tabs to the browser"; the
header gains forward, a home button once the page left the pin's address, and "replace pin with this page"
(`webdock.retarget`, a settings write). The shell's parts come from a new provide kind `surface:<name>` (row 88). The
accent-colour design pass (I51/I63) stays separate.

**K41** 🟢 Opt-in mods carry their own measured cost, outside the base shell's budget (user decision, session 8,
2026-10-20; W20-webdock-shell). The K16/K19 budgets (≤ 150 MiB @ 1 output, ≤ +6 MiB per extra output, ≤ 4 mapped
surfaces per output) are for the **core profile with no mod on**; a mod that is off costs nothing (Ma). An enabled mod's
cost is measured (mod on vs off, same profile) and recorded in BENCH "Mods" and its manifest's `cost`, and Settings
shows it before the user turns the mod on (Shōjiki). First case: the web dock's per-output edge window costs about
**6.2 MiB USS per output** (gles2, machine B, median of three; runs swing by ~40 MiB) plus **3.8 MiB once** for the shared
dock window after the first reveal, 0 commits idle, no growth over 20 reveals. *Why:* the per-output edge window is
its own Qt layer window, so no QML change gets it near 1 MiB; the alternatives were hover only on the bar's edge
(reusing the bar window) or one edge window following focus (no hover on unfocused outputs) — both cut the feature the
user asked for (K40). The base budget's per-output headroom (+6.0 of +6) stays reserved for core surfaces.

**K42** 🟢 Chrome axis, decor recipes and a pop "sekai" look (user request, session 9: `INSPIRATION.md` — SekaiPop,
Capsule, Vitreus, pleamar). (1) A new theme axis `theme.chrome` = `flat | keycap`. Keycap is SekaiPop's "one block,
everywhere": an outline in palette role `line`, a ring in role `ring` between outline and fill, and a hard shadow
straight down that the block sinks into while pressed, springing back with overshoot
(<https://github.com/Blapples/SekaiPop> `modules/common/widgets/Pill.qml`). Renderers read only tokens
(`chrome.style/outline/ring/shadow/line/ring_color`) through `Block.qml`; no renderer branches on a theme name (rule 4).
`a11y.high_contrast` forces flat. (2) Palette roles `line` and `ring` join the role set, derived when a palette leaves
them out. (3) Decor packs get their recipe half (DESIGN-SYSTEM §4): `theme.decor` (`none | sekai`) puts the pack's
recommended axis values at the `theme:<pack>` layer, under the user's own values, so a pinned value still wins and
every recommended value's provenance says `theme:sekai` (Shōjiki). Recipes are code (`kurashi_theme::decor_recipe`)
until mods can ship them. (4) Springs as tokens: `motion.spring.{on,overshoot,spring,damping}` (calm settles, lively
bounces, keycap bounces most; `none` = off); morphs that retarget use them (Capsule's island morph, pleamar's "every
property is a spring"). (5) Icons: Material Symbols Rounded by ligature when installed (`font.icons`), else the
component's text glyph; HM installs it with Nunito (`programs.kurashi.fonts`). (6) Tonal `color.selected` and
`color.data.1..4` (I51, I63). *Why:* identity without forks of every component; one switch for the whole look, but
still the user's settings on top.

**K43** 🟢 Desktop widgets as a core surface, opt-in per output (session 9, SekaiPop's desk). `desktop.*` keys; one
content-sized bottom-layer window per output while on, none while off (Ma, K16); the `sekai` decor recommends it.
Cards read existing documents only (svc.clock, svc.media, mod.weather) — no new service. *Why:* the user asked for
SekaiPop's concepts and "almost feature complete"; a desk is the visible half of that look. Its per-output cost is
outside the base budget while off by default (as K41 for opt-in mods). UX brief `docs/ux/desktop.md`.

**K44** 🟢 Launcher modes and the bar's window list (session 9; Capsule's launcher, SekaiPop's dock). The launcher query
answers arithmetic with a first `calc` row (`kurashi_launcher::calc`), `:` with emoji (data from Vitreus, MIT,
`crates/kurashi-launcher/data/`), `;` with the cliphist history (HM `programs.kurashi.clipboardHistory`); launching
such a row copies it (`wl-copy`). A `note` row explains an empty or missing source instead of a blank list (Shōjiki).
`svc.workspaces` gains `tasks` (per output, the active workspace's windows, no titles) and `window.focus {id}`; the
top/bottom bar draws them as icons after the workspaces. *Why:* the user asked for "almost feature complete" and to
copy what works elsewhere; all of it is daemon data, the views stay thin (rule 1).

**K45** 🟢 A decor is a whole look, never a layout (user, session 10: "other styles should have/keep their distinct
look, just as sekai has its own"; "everything layout related should stay the same and looks/style wise should be able
to change with the themes"; WormShell `docs/05-surface-style.md`: a SurfaceStyle is not a palette and not a layout).
(1) Recipes name `theme.*` keys only (a test holds it): the K42 recipes lose `bar.height` and `desktop.enabled`. Layout
— bar edge and height, desk cards, island placement — is the user's and travels in profiles, which already store a
look and a layout together. (2) Chrome gains `soft` (Vitreus/pleamar: a faint light rim, a soft drop shadow, pressed
blocks shrink to `chrome.press_scale`) and `line` (ink outlines in the outline role, no shadow). New tokens
`chrome.soft/soft_dy/soft_color/soft_alpha/outline_color/outline_alpha/press_scale/groups`, `icon.fill/weight`, and
`font.icons` = Material Symbols Sharp under line chrome when installed. (3) Decors: `sekai` (keycap pop), `glass`
(soft, frosted, squircle, Inter), `terminal` (line, square, mono, quick calm motion), `washi` (line on wa-iro light,
small corners, Noto Serif). `none` keeps the user's own axes (the kurashi default: wa-iro, flat). HM installs the
families. *Why:* four distinct identities from one set of renderers, each a recipe (rule 4); the user's settings
still win (K42).

**K46** 🟢 Tasks and notes as a native mod over plain Markdown files, and desk cards from mods (v0.2 "notes, tasks";
I101). Mod `tasks`: a Markdown checklist (`- [ ] …`, Obsidian Tasks' `📅 YYYY-MM-DD` due dates and `⏫🔼🔽` priority
marks read and kept) and a Markdown note, both files the user may point into an Obsidian vault; default under
`$XDG_DATA_HOME/kurashi/`. The daemon reads and writes them (rule 1), watches them only while `mod.tasks` has a
subscriber (Ma), keeps every line it does not own untouched, and writes atomically. A new provide kind
`desk:<name>` → `qml/desk/<name>.qml` (row 120) puts a mod's card on the desk column after the core cards.
Todoist/TickTick are later backends of the same document. *Why:* a file is the most honest store — the user can read
it, sync it and edit it with any tool, and the vault already holds their notes.

**K47** 🟢 Daily-driver services, copied where others solved them (user, session 10: "get the desktop shell as complete
and usable as possible … don't reinvent it if they did it better already"). (1) **Idle** in the daemon over
`ext-idle-notify-v1` (one long-lived Wayland connection; the compositor applies apps' idle-inhibit itself): stages dim →
lock → screens off (`niri msg action power-off-monitors` through the adapter) → suspend (logind), each 0 = never;
inhibitors of our own: caffeine (DMS/ii idle inhibitor), media playing (DMS), logind `idle` locks. Replaces
swayidle/hypridle; HM stops recommending them. (2) **Night light** = a supervised `wlsunset` process (Noctalia
`NightLightService.qml`: the same flags), schedule always/manual/sun (sun takes the weather mod's place). (3)
**Keyboard layouts** from niri's event stream. (4) **Screen recorder** = a supervised `gpu-screen-recorder` (Noctalia
`ScreenRecorderService.qml`) or `wf-recorder`; screenshots are niri's own actions. (5) **Polkit**: the authentication
agent is Quickshell's `Quickshell.Services.Polkit` (as ii's `PolkitService.qml` and DMS) in a dedicated frontend
surface — an exception to rule 1 like the toolkit's own Wayland work: the agent must live in the process that draws
the dialog, the flow (libpolkit-agent, the setuid helper) is Quickshell's C++, no logic of ours. The daemon learns only
that a dialog is up (`ui.polkit {active}`) so the island stays out of its way. (6) **Rounded screen corners**
(`theme.shape.screen_corners`, Caelestia/shellseikatsu `ScreenCorners.qml`): one click-through overlay per output while
> 0. *Why:* these are what people miss first when they switch from Caelestia, Noctalia, DMS or ii.

**K48** 🟢 Media and desk polish (session 10, wave 24; Caelestia, DMS, Noctalia, shellseikatsu). (1) Live audio levels:
`svc.audio.spectrum` from a supervised `cava` process (Caelestia `Cava.qml`, DMS `CavaService.qml`), refcounted, ≤ 30
patches/s while watched, nothing otherwise — the island's media bars and the media card draw it (I111); without cava
the bars are a still "playing" mark, not a fake animation (Shōjiki). (2) Cover colours: `svc.media.art_colors` via the
theme crate's material-colors extraction (shellseikatsu `MediaColorService`, DMS `MediaAccentService`). (3) Wallhaven
in the wallpaper mod (shellseikatsu `WallhavenService`): search, preview, set; network capability, API key optional.
(4) Desk layout: `desktop.order` (layout, so the user's and profiles', never a decor's) and an edit mode on the desk
(SekaiPop "Edit Desktop"): reorder by drag or keys, then save. (5) Settings rows grouped as section cards (DMS/Noctalia
settings) with icons per section (I104 rest).

**K49** 🟢 App theme export (VISION "app theme export", roadmap M2 "exporter"; user, session 10: "theme integrations"
from shellseikatsu). The daemon renders the final palette through templates in **matugen's syntax**
(`{{colors.<role>.<mode>.<format>}}`) into files under `$XDG_CONFIG_HOME` for the targets in `theme.export`
(gtk3, gtk4, qt/qt5 via qt6ct/qt5ct, foot, kitty, alacritty, ghostty, niri), only when the content changes.
Templates: DankMaterialShell's GTK, qtct and niri ones (MIT), shellseikatsu's terminal ones; matugen role names map
onto ours (`primary` = `accent`, `background` = `surface`, containers derived), so users' matugen templates work too
(`~/.config/kurashi/templates/<name>` overrides). kurashid never edits an app's own config: `svc.theme_export`
reports the include line each app needs and whether it is there. *Why:* one theme for the whole desktop is what
matugen setups (DMS, Caelestia, ii, Noctalia) give; writing our own files and leaving the user's config alone keeps
it honest and reversible.

**K50** 🟢 Decor packs are files (WormShell `05-surface-style.md` "a SurfaceStyle is a folder pack"; shellseikatsu's
`Services/Modes/*.qml` preset manifests). `decors/<name>.toml` = `name`, `label` (i18n key or plain text), `[recipe]`
of `theme.*` values (anything else is dropped and reported). Bundled packs are compiled in (as palettes); a pack in
`$XDG_CONFIG_HOME/kurashi/decors/` replaces a bundled one of the same name or adds one; mods' `decor:` provides read
`<mod>/decors/<name>.toml` next (I103). `theme.decor` becomes a string with offers from source `decors` (`none` =
your own). *Why:* identity packs (v0.3) and the user's own looks without a Rust change; the K45 rule (looks, never
layout) is enforced by the loader, not by review.

**K51** 🟢 An app dock (roadmap v0.2 "dock/sidebar"; DMS `Modules/Dock`, Noctalia `Modules/Dock`, ii `modules/dock`).
`dock.*` is layout (the user's and profiles', never a decor's): per-output on/off and edge, autohide (a thin edge
window reveals it, as the web dock's strip, K40), pinned desktop-entry ids, icon size, running apps. Running windows
come from `svc.workspaces.windows` (every window: `{id, app_id, workspace, output, focused}`), grouped by app id;
click = focus (cycle on repeat) or launch, middle = new window, right = a menu (pin/unpin, close). Off by default:
its per-output cost is opt-in (K41).

**K52** 🟢 Compositor adapters (roadmap v0.3; WormShell `10-compositor-adapter.md`). One `AnyCompositor` (an enum, no
dyn: the trait is not object-safe), chosen at startup from `KURASHI_COMPOSITOR` (`niri|hyprland|sway|none|auto`), else
`NIRI_SOCKET` → niri, `HYPRLAND_INSTANCE_SIGNATURE` → Hyprland, `SWAYSOCK` → Sway, else none (documents say
unavailable). Sway: hand-framed i3-IPC (no new dependency); Hyprland: its request and event sockets. Events re-read
only the domain they touched; no polling. Hyprland's global workspaces are listed under the monitor that shows them.
Screens off on Sway/Hyprland need a wake guard (they stay off until told): kurashid turns them on at the next input
seen by `ext-idle-notify`; screenshots there use grim/slurp. `kurashi doctor` names the adapter and its gaps. *Why:*
CLAUDE.md's "designed for Hyprland / MangoWM / Sway adapters"; and the headless test sandbox (sway) now runs the real
adapter path instead of a fake.


**K53** 🟢 Style ⊃ Look + Palette (user, session 11: "a clear differentiation between what a Look, a Style, a Palette or
Chrome is"; "fixed Style presets that reset previous style related settings"; "If a Look just changes the color of an
already existing other look it should be a color Palette instead"). Three kinds of appearance pack, each a file
(`kurashi-theme::appearance`, bundled + `~/.config/kurashi/{looks,styles}/`):
- **Palette** (`palettes/*.toml`, `theme.colors.palette`): colours only, as before.
- **Look** (`looks/*.toml`, `theme.look`, default `kanso`): the form and feel without colour — `LOOK_KEYS` (chrome,
  corners, radius scale, material kind/opacity/blur, motion profile/speed, type family) and the `[slots] frame` art.
  A look naming a colour key is refused. The 18 decors split into 17 looks: the shared forms `kanso` (plain) and `soft`
  (rim + shadow) replace catppuccin/rose-pine/tokyo-night, whose difference was colour.
- **Style** (`styles/*.toml`, `theme.style`, **default `washi`** — user: "the paper like (Washi) look as a default on a
  fresh install"): `look` + `palette` + a recipe of the recommended scheme, density and tweaks of its own look's keys (`STYLE_KEYS` + scheme).
  Each pack has a `category` (`modern`, `inspired`, `retro`, `fiction`; user files without one: `custom`) for
  Settings' grouping; offers carry it as `group`.
- **Layering:** one `theme:` layer whose entries each name their pack (`Source::Theme("look:washi")`,
  `"style:washi"`): the look's recipe, then the style's look/palette/recipe — a style's look tweaks apply only while its
  own look is in effect (a look the user picks over the style is that look, not the style's version of it). The look in
  effect is the one set outside the theme layer, else the style's, else the schema default.
- **Reset semantics:** `theme.style.apply {name}` resets every user value of `STYLE_KEYS` and sets the style — one
  undoable transaction, so the style is recreated exactly; `theme.look.apply {name}` does the same for `LOOK_KEYS`.
  Light/dark (`theme.colors.scheme`) is the user's mode: a style recommends one until the user picks, and applying a
  style keeps it (user: "every theme should have a light / dark mode" — all 19 palettes now have both, a test holds
  it). Accessibility preferences (contrast, colour-blind shift, text scale, OLED), the seasonal tint, screen corners
  and app export are never reset either. The theme document's `appearance {style, look, palette, overrides}` lists the keys that differ
  from the style ("changed from the style · Reset").
- **Previews** move out of `theme` into their own document `theme.previews {styles, looks, palettes}` (looks drawn in
  the palette in effect, palettes in the look in effect), watched by Settings only — the shell's surfaces never receive
  them (Ma).
- **Migration:** schema v2; `theme.decor = X` → `theme.style = X` (every old decor is a style of that name; `none`
  stays `none`), in config.toml, profiles and managed.toml. Token `decor.frame` keeps its name (the look's art slot).
*Why:* a decor mixed form and colour, and its recipe sat under the user's values, so returning to a look meant resetting
settings by hand. Shellseikatsu's presets and WormShell's packs are both "whole aesthetic" presets; Noctalia/DMS/
Caelestia keep colour schemes apart from the shell's form — this keeps both, named.

**K54** 🟢 Sidebars, a core surface apart from the web dock (user, session 11: "a simple styled sidebar that goes from
one edge to another (if there is a bar it should go to the bar rather than the edge) just like … illogical-impulse";
"maybe the sidebar should be something separate from the webbar"). Left and right sidebars (`frontend/surfaces/Sidebar.qml`,
card W29-sidebar, docs/ux/sidebar.md): one layer window per open side, none while closed (Ma), anchored top+bottom+side
with exclusive zone 0 so the compositor stops it at the bar. `sidebar.style` `panel` (flush, ii) | `floating` (inset,
the look's chrome), `sidebar.width`, `sidebar.right` (sections from source `sidebar.sections`: header, toggles,
sliders, notifications, calendar, media, then mod panels), `sidebar.left` (tabs from `sidebar.tabs`: mod panels — the
AI chat by default), `sidebar.from_bar` (the bar's quick button opens the right sidebar). State in `runtime.ui`
(`sidebar`, `sidebar_output`), one at a time with the Stage and the launcher. The web dock stays its own mod; whether it
becomes a sidebar tab is open with the user (I116). Keys: Mod+Shift+N (right; Mod+N stays the notification centre),
Mod+A (left). *Why:* ii's sidebarLeft/Right (copied: the anchoring, sections, tabbed left pane) without
shellseikatsu's sizing and focus races.

**K55** 🟢 Light or dark has modes, and a style takes it over (user, session 12: "Light/Dark should have multiple Modes:
Follow OS/Auto (detects OS setting), Follow Wallpaper (Depending on the wallpapers color adjust the shells color to
dark/light), Dark, Light. When a Styles is toggled it should overwrite that settings and follow the Style by default.
Users can press reset to go back to their previous default then."). Supersedes the K53 amendment (light/dark as the
user's mode a style never touches). `theme.colors.scheme` = `auto` (default) | `wallpaper` | `dark` | `light`.
`auto` reads xdg-desktop-portal Settings `org.freedesktop.appearance color-scheme` (`ReadOne`, `Read` before portal
1.17) and follows `SettingChanged` — the value GTK 4, Qt 6.5+, Firefox and Chromium read too — watched only while the
mode is `auto` (`kurashid/src/os_scheme.rs`, Ma); no portal or "no preference" → dark, and the theme document says so.
`wallpaper` takes the mean CIE L* of the wallpaper mod's applied picture (`stages::mean_lightness`, light from 55) —
the same picture palette `wallpaper` reads (K34), held while either needs it; no picture yet → dark, said so. The
scheme joins `STYLE_KEYS`: applying a style resets it, so it follows the style (theme layer `style:<name>`); the
user's own mode from before is kept in `$XDG_STATE_HOME/kurashi/scheme-before` (a second style keeps the first
remembered mode) and `theme.scheme.restore {}` sets it back (one undo step). The theme document's `appearance` gains
`scheme_effective`, `scheme_detail` (`os`, `os_unknown`, `wallpaper`, `wallpaper_waiting`, `""`) and `scheme_before`.
The quick and sidebar Dark tiles show the scheme in effect and set dark or light outright. *Why:* GNOME/KDE/macOS
"Auto" follows the system; matugen/Caelestia/DMS derive the scheme from the wallpaper; a style is a whole aesthetic
(K53), so it owns light/dark until the user picks again, and "Back to Auto" undoes only that.

**K56** 🟢 The web dock in the sidebar fills it (user, session 12: "It should be able to be used in the sidebar but
inside of it it fills the whole sidebar instead of being phone shaped"; resolves I116; card W30-webdock-sidebar, rows
250–252). The web dock offers panel `panel:webdock` (tab value `mod:webdock:webdock`) for `sidebar.left` and
`sidebar.right`: a row of pin keys over the page, which fills the pane — no phone frame. One engine, one page per pin
(K38 kept): the web host maps a second layer window (`kurashi-webdock-side`, Overlay, anchored like the sidebar, exclusive
zone 0) only while the sidebar rests open on a site, at the place the panel reports (`webdock.sidebar`, panel property
`placement`), and moves that pin's page between its windows (QQuickItem reparent, no reload — spiked headless). The same
pin at the edge and in the sidebar: the sidebar shows it live, the edge card says "shown in the sidebar". Closing the
sidebar unmaps the window (0 frames) and freezes the page; it stays loaded under the dock's own unload rules, a page in
an open sidebar counting as shown. *Why:* Vivaldi/Edge/Opera web panels are a page beside the content at the panel's
full size — a phone bezel inside a sidebar wastes its width. Host memory with the window mapped: to measure (BENCH).

**K57** 🟢 The config document publishes its own revision (`history.rev`, the `rev` an `applied` answer carries).
Settings' preview takes back its own previous step before the next only while nobody committed after it (K27); it
compared the *document's* revision, but one apply patches the document several times (values, overrides, offers), so
a preview moved across several choices stacked undo steps instead of staying one (found when light/dark grew to four
choices, K55). *Why:* the transaction counter is the only honest "did anyone else commit" signal; fixture
`snap_config.json` and PROTOCOL updated.

**K58** 🟢 The sidebars open without a key (user, session 12: "The new sidebar doesn't toggle at the moment, or I don't
know how to open it at all"; I154). `sidebar.bar_buttons` (default on): a button at each end of the bar — the left
sidebar's at the start, the right one's at the end (none while `sidebar.from_bar` already makes the quick button open
it); the launcher's `>` commands `sidebar.right.toggle` / `sidebar.left.toggle` (argument-free actions on the focused
output); Settings › Sidebar "Open now" and the default keys. The HM default binds carry `Mod+Shift+N` / `Mod+A` (bind
entries may carry JSON arguments). *Why:* a surface reachable only by a key the user must first wire into niri is not
discoverable; ii puts its sidebars on the bar's ends, Windows 11 on the taskbar's corners.

**K59** 🟢 Material textures and their light (user, session 12; I163; `docs/ux/texture.md`). A texture is a colourless
relief — a seamless tile of normals, cavity and ink generated by the daemon (`crates/kurashi-texture`, deterministic,
cached by its parameters) — shaded by one formula (DESIGN-SYSTEM "Texture and light") on the GPU (`Relief`) and on the
CPU (wallpaper bake, Settings swatches). Config `theme.texture.{kind, scope, strength, scale, wrinkles, tint, text}` and
`theme.light.{mode, angle, elevation}`; tokens `texture.*`, `light.*`. Scope `shell` (default) | `wallpaper` (baked into
the picture the wallpaper mod hands its backend, through a host-provided picture filter) | `shell_wallpaper` |
`everything` (a click-through overlay layer per output). The sheet is continuous in output coordinates. Shade is black
at α (an exact multiply under a normal "over" blend), light is a screen blend, so even the overlay modulates apps.
Light: `static` (compass angle, elevation), `pointer` (a lamp at the pointer — only over the shell's own surfaces, a
Wayland client sees the pointer nowhere else; it glides back to the static light; the frontend tracks it, a view
concern like hover, never sent to the daemon), `daytime` (solar azimuth/elevation of the weather mod's place, NOAA
equations as the night light; a 5-minute daemon tick only in that mode). The kind, strength, scale, wrinkles and tint
are look keys (a look or style recreates its material; the user's own comes back with `theme.texture.restore`, as K55);
scope, text and light are the user's. High contrast and reduce transparency force the texture off. *Why:* a material
with baked light and colour (iOS 6 skeuomorphism) goes stale and clashes with palettes; one light for every surface and
no colour of its own keep it a quality of the shell, not a skin. Fluent's Acrylic noise and Reveal highlight are the
precedents for grain and a pointer light. Rejected: a shell-drawn wallpaper (a full-output buffer per output, BACKLOG
I7), true blend modes over apps (a layer surface cannot read what is under it; Hyprland's `screen_shader` can, I164),
screen filters in the same feature (I165).

**K60** 🟢 紙 kami, the text colour and a Japanese font chain (user, session 12). Style and look `kami` (category
`inspired`): palette `kami` (warm white paper / blue-black paper, a red correction pen as accent), `paper_dots` texture,
frame `sketch` (hand-drawn outlines: two seeded pen passes, never animated), Kalam + Klee One (both SIL OFL, installed by
the HM/NixOS modules via `google-fonts`), `theme.colors.ink = blue`. `theme.colors.ink` = `palette` (default) | a named
ink with a light- and dark-scheme shade (`blue`, `black`, `sepia`, `red`, `green`, `violet`) | `custom`
(`theme.colors.ink_custom`): a palette stage before `wcag` sets `on_surface` and thins `on_surface_variant` from it, so
legibility still wins. `theme.typography.family_jp` (a look key) makes the Japanese family a chain of its own — until
now it was fixed to Noto Sans CJK, so washi's serif never reached Japanese text. *Why:* the user asked for a
presentable paper style with a handwritten blue font and a general text colour option; an ink with two shades follows
light/dark the way a pen colour would.

**K59 amendment** (user, session 12) — light mode `wallpaper`: a lamp at the wallpaper picture's brightest region
(`kurashi_texture::light_spot`: smoothed-luminance peak, light-weighted centre of the bright pixels within a quarter of
the picture around it; none when the 97th percentile stands less than 0.12 above the median), its colour halfway to
white; token `light.lamp` `[x, y]` (fractions of the output), the shader's and the bake's lamp. The picture is the
theme's, else an output's (the wallpaper mod's document, held while this light is chosen); decoded once per picture on a
blocking thread. Material `paint`: oil paint on canvas with deep brush strokes (card W31-paint). The tile is two files
(rows 280–281): an opaque RGB relief and a white ink map with coverage in alpha, because Qt premultiplies textures.

**K61** 🟢 Deeper texture, relief shadows, the spotlight, controls, a carried sheet, cracks, brush strokes and a material
of the wallpaper's own (user, session 13). `theme.texture.depth` (0.5–3) steepens the normals; `strength` reaches 2 (the
legibility cap still holds — depth and shadows never pass `texture.amp`). `theme.texture.shadows` (auto | off | on):
self-shadowing from a height map (a third tile file, `<tile>-height.png` + its relief in px), 8 samples toward the light
over at most 24 px — longer for a flatter light, as the user asked ("angling the light flatter or higher to have
longer/shorter shadows"); auto = the material's own (`Material::shadow`: paint and brush on), the kami look sets on (user
choice "On for kami/paint"; a recipe value, never a renderer branch — rule 4). `theme.light.color` (natural | white |
warm | cool | custom). Light mode `spotlight` (user choice over a steered direction): a lamp pinned where a ray from the
output's middle in `theme.light.angle`'s direction meets the edge (`kurashi_texture::pin`, the square of fractions so
every aspect ratio agrees), at `elevation`'s height, its beam (`theme.light.beam`) aimed at the pointer — rests aimed at
the middle when the pointer is off the shell; outside the beam the relief keeps 30 %. `theme.texture.controls`: the relief
over buttons, sliders, switches, chips and icons; pictures (covers, thumbnails, avatars) opt out. `theme.texture.sheet`
(user choice: carried by default): a surface in motion takes its sheet along and lands exactly on the continuous sheet
at rest; `fixed` is K59's still sheet, `separate` a sheet per surface. `theme.texture.cracks` + `crack_style` (stone |
glass) and kind `brush` (long, continuous hairy strokes) are tile parameters (`Params`, the cache name). I169: token
`texture.lit` weighs the light half down to 0.6 on dark grounds. `theme.texture.wallpaper.{own,kind,strength,scale,
wrinkles,cracks}`: the bake's own material (no legibility cap on the wallpaper). The formula stays one function,
`kurashi_texture::shade_at` (CPU reference) mirrored by `relief.frag`. *Why:* the user asked for more depth, coloured
light, pinned vs follow lights, texture over every element, surfaces that own their texture, cracks, a second brush and
separate wallpaper/shell materials (session 13).

**K62** 🟢 The pen (user, session 13): `theme.pen` — `line` (solid | dotted | dashed | broken | rough) and four modifiers
for outlines (`pressure` = fountain-pen swell and thinning, `breaks` = skips, `fade` = ink flow, `wobble` = a hand that
wanders, straight lines and curves alike) and the same four for text and icons (`text_*`, through a layer effect over a
block's content — off by default, it costs one layer per block while on). Each modifier is separate and combinable, as
the user asked. Seeded per size, never animated (Ma); high contrast forces all of them off. Tokens `pen.*`; look keys, so
a look can carry a pen (kami: pressure 0.35). *Why:* "dotted lines or disconnected lines as an outline … or very uneven
lines" and "slightly thinning/thickening and slightly disconnected and slightly less in opacity, just like … a fountain
pen … Each of those should be a visual 'modifier'" (user, session 13).

**K63** 🟢 Settings as a sheet (user, session 13): `settings.window` = `window` (default: today's xdg toplevel the
compositor places and tiles) | `sheet` — the same on-demand process (K2: no cost while closed) maps a layer-shell surface
centred on the focused output over a softly dimmed backdrop, exclusive keyboard, Esc or a click on the backdrop closes
(user choice: a modal sheet). As a sheet it is a shell surface: material, light and (carried) sheet like the rest. *Why:*
the Settings window was the one surface the texture and light never reached, because it is a compositor window; the
user asked to toggle between "a normal compositor window" and "a quickshell hosted settings window that overlays in the
center of the screen".

**K49 amendment** (W34, session 13): `gsettings` is the one export target that writes settings instead of a file:
`org.gnome.desktop.interface` colour-scheme, font-name and icon-theme from `templates/gsettings.ini`, only where the value
differs; the values last applied are kept (an unchanged config patch runs nothing); a `gsettings` that does not answer
within 3 s is stopped; opt-in like every target. Qt (qt6ct/qt5ct) and KDE (kdeglobals) get the lines their own configs
need from `templates/lines/*.conf`, shown and never written; KDE apps get a colour scheme file (`Kurashi.colors` in
`$XDG_DATA_HOME/color-schemes`). niri writes `niri/kurashi.kdl` (focus ring, border, shadow, corner radius, animations
from the motion profile); the old `kurashi-colors.kdl` stays a stub while an include names it. A render that leaves a
placeholder unfilled is never written — the last good file stays (an unfilled value in niri's KDL would break its
whole config). Placeholders beyond colours: `templates/README.md`. *Why:* the user wants every app to follow the shell
"by default", icons and fonts included, and the compositor to match the shell's shape and motion (I175, I183, I184).

**K49 amendment 2** (session 20, user): more targets — zellij, fzf (noren's picker), Neovim, Helix, Zed, Firefox, Zen, Vesktop (Discord), Spicetify
(Spotify), Obsidian, and the compositors Hyprland, MangoWM and sway beside niri. Four switches under "Apps that follow"
reach every compositor that supports them, and each one off leaves the compositor's own setting (the line is empty):
`theme.window_frame` (border at the shell's outline width, accent/outline; niri: border in place of the focus ring),
`theme.inactive_transparent` + `theme.inactive_opacity` (niri, Hyprland, MangoWM; sway has none),
`theme.window_animations` (default on: niri's springs as before; Hyprland/MangoWM on the continuous curve and standard
duration, not a 1:1 copy; sway has none) and `theme.window_titlebars` (sway's own; Hyprland only through hyprbars;
niri/MangoWM draw none). An include line may name values (`{{paths.config}}`: Firefox's `@import` needs a file URL)
and a `~/` include file sits under `$HOME` (Zen's profile). Apps whose reader lives in a per-profile or per-vault
folder (Firefox, Zen, Obsidian) get our file under `$XDG_CONFIG_HOME/kurashi/apps/`; Vesktop and Obsidian are switched
on in the app. No reader without editing the app's config or installing something: VSCode, Anki, Steam, Signal,
Chromium-based browsers (BACKLOG). *Why:* the user wants their daily apps and every compositor kurashi targets to
follow the shell.

**K64** 🟢 Keyboard shortcuts are config (I72, user session 7 / 13): `keys.*` — one combo per shell action
(launcher, notification centre, sidebars, quick settings, session menu, lock, Settings, web dock, volume, mute,
brightness; `""` = none) and `keys.write` (default off). With `write` on, kurashid writes the compositor's binds file
from them (niri: `$XDG_CONFIG_HOME/niri/kurashi-binds.kdl`, `spawn kurashi act …`), only when the content changes, and
reports the include line (K49's pattern: our own file, never the user's config). A file Home-Manager manages (a store
symlink) is not overwritten: the row says so. Settings shows the page "Keys" with a shortcut recorder and flags two
actions on one combo. *Why:* the user wants to change shortcuts in Settings; until now only the HM module wrote them.

**K64 amendment** (W35-keys): a file at the path without kurashid's header (`foreign`, e.g. a pasted copy of the
snippet) is never written, nor a Home-Manager symlink (`managed`); with writing off kurashid's own file becomes an empty
`binds {}` stub, because niri refuses a config whose include is missing; a changed file is checked with `niri validate`
before it is written (a key niri refuses is left out with its reason, any other refusal writes nothing); `svc.keys`
reports per shortcut whether the user's own niri config binds the same combo before (`replaces`) or after
(`overridden`) the include. Settings records shortcuts with Quickshell's shortcut inhibitor active, so the compositor's
own binds reach the field.


## K65 — wave 36 contracts: island system events, hidden desk cards, Settings by page (2026-10-25, session 13)
Three small contract additions ahead of wave 36. (1) `island.main.system_events` (default on, refines K30): off, kurashid
drops the island's permanent `svc.power`/`svc.bluetooth`/volume/brightness subscriptions and their transients — Ma for
users who never want them (I18). (2) `desktop.hidden` (list, refines K48): the desk's edit mode hides a card instead of
the user disabling a whole mod; a hidden card keeps its place in `desktop.order` (I136, I119). (3) `settings.open {page}`
(refines I25): opens Settings on a page (`keys`, `mod:<id>`) for links that are not one key, e.g. "Set up shortcuts" or a
mod's tile menu (I40). *Why:* each was a frontend stand-in or a missing deep link reported by an earlier card; none
changes an existing shape.

## K66 — wave 37 contracts: island face, forced services, quick tile tokens, the agenda's day (2026-10-25, session 13)
Four rows deferred by earlier cards, accepted now. (1) `island.expand {face?}` (row 203, refines K24): the calendar's
bar widget opens the clock card on its agenda even while media is current. (2) Additive `forced_by` on the six service
documents the quick card shows (row 103, refines I50): a forced key that holds a service switch is now visible on its
tile (Shōjiki), not only in Settings. (3) `quick.tile.on.{bg,badge,fg}` component tokens (row 104, rule 4): a palette
tunes the on state without a frontend change. (4) The `clock.expanded.day` slot gets `extra: {date}` (row 200): the
agenda no longer walks up its parents to find the selected day. *Why:* each replaces a frontend stand-in; all four are
additive.

## K67 — drop shadows you can set, and shadows that follow the light (2026-10-25, session 13; I173b)
`theme.material.shadow` (strength 0–2, default 1 = the look's own), `shadow_angle` (degrees, default 180 = straight down,
today's look) and `shadow_follow` (default off; needs a material, since the light lives there). kurashi-theme resolves
one shadow vector for every block and surface — tokens `shadow.dx`, `shadow.dy` (unit direction × the look's length ×
strength; with `shadow_follow` the direction is away from `light.dir` and the length grows as `light.elevation` falls)
and `shadow.alpha_scale` — and the keycap's hard shadow, the soft shadow and the press sink all use it. A light that
moves with the pointer (pointer, spotlight) casts from its rest direction: shadows never repaint on pointer motion (Ma,
rule 5). *Why:* the user (session 13, item d): "static shadow by default but option to adjust it to the light source
dynamically"; the lead's review in I173: drop shadows from the light are cheap and coherent, true cast shadows across
windows need the compositor (out of scope).

*K67 amendment (wave 42, row 423):* `shadow`, `shadow_angle` and `shadow_follow` require `theme.chrome` not flat and not
line, so Settings shows them inert, with the reason, under the looks that draw no shadow.

**K64 amendment 2** (W38-keys, I189): Sway and Hyprland get binds files of their own (`sway/kurashi-binds.conf`,
`hypr/kurashi-binds.conf`) under the same header/foreign/managed/stub rules. Each is judged by the compositor's checker
before it is written (`sway -C` — which exits 0 for an error inside an included file, so its error text decides;
`hyprland --verify-config`; `niri validate`). Sandbox probes with real key presses showed single-quoted JSON is the only
`exec` argument form that reaches `kurashi act` intact under Sway. niri binds carry `hotkey-overlay-title` so niri's own
cheat sheet names kurashi's shortcuts.

## K68 — split memory budgets; the minute flip is the one idle commit; island faces restrict (2026-10-25, session 13)
User decisions after W35-perf. (1) **Memory:** the core budget stays ≤ 150 MiB PSS at one output (+6 per extra output)
for the bare shell (no material, no web dock); the material and the web dock get allowances of their own (BENCH
budgets: material + ≤ 55 / + ≤ 12 per output, overlay + ≤ 35; web dock + ≤ 10 USS / + ≤ 4 per output), sized just above
the W33/W35/W38 measurements (+18…53, +4…11, +30; +4.9…8). (2) **Idle:** the bar clock's minute flip is capped at 300 ms
and is the only idle commit the budget allows (B34, I193). (3) **Island faces:** `island.main.faces` restricts which faces
the island may show, as its label says; an unlisted face never shows and `island.expand {face}` for it is refused
(`island.error.unknown_face`; I209 — today the list only orders). Two limits: system transients (volume, brightness, power, Bluetooth) stay governed by
`island.main.system_events`, not by the list; and a user on the default list must not lose a face they see today — a
newly enabled mod's face joins the default list (the card decides how, without writing the user's config behind their back). *Why:* the user chose "raise and split", "shorter
flip" and "restricts" (session 13); placement stays as built (toasts/centre under the island, panels under their widget).

*K68 follow-ups (wave 42, rows 451, 452, 473):* a list that names no registered face falls back to the default face (else
the first registered one) alone; a card open on a face the island stops offering closes; `save_profile` keeps a value the
user or a profile set even when it equals the schema default (forced, Nix and the look's values keep the non-default
rule), so a saved list restricts again on load (K7).

## K69 — the shell ships its own icon subset; a missing name falls back to the full family (2026-10-25, session 13; I194)
The kurashi package installs "Kurashi Symbols Rounded" and "Kurashi Symbols Sharp" (`nix/icon-font.nix`: Material
Symbols cut to the ligatures in `nix/icon-names.txt`, every axis kept) under `share/fonts/truetype`; the Home-Manager and
NixOS `fonts` defaults and the devShell list the same derivation first, Material Symbols after it. `font.icons` prefers
the subset (line chrome: the sharp cut, then the full sharp family, before the rounded subset), else Material Symbols,
else ""; the new token `font.icons_fallback` names the full family of the same cut when `font.icons` is the subset.
`Icon.qml` moves a name that renders wider than 1.5 × size to the fallback family, and a name neither family draws to
its glyph or a bullet, so an icon never shows as a word. `nix/icon-names.txt` is the one list of names;
`tools/check-icon-names.sh` regenerates it from the sources in `just check`. Mods declare no icon list (MODS.md): their
names fall back at run time. *Evidence:* BENCH "2026-10-25 — W41 icons" — pixel identity 0 strong pixels (30 pairs);
icon font resident 22.5 → 13.9 MiB RSS (W39); with the washi grain memo, PSS @1 output 157.5/158.2 → 152.3/152.4 MiB and
the quick card 48–50 → 22 ms warm. The core budget (150, K68) is still 2.4 MiB away.

## K70 — the frontend loads the image formats it draws, and two allocator arenas (2026-10-25, session 13; I194)
`frontend/launch.sh` replaces every Qt plugin dir that has `imageformats/` — those on `QT_PLUGIN_PATH` and those
nixpkgs' Qt patch derives from each PATH entry (`<entry>/../lib/qt-6/plugins`) — by a symlink copy under
`$XDG_RUNTIME_DIR/kurashi/qt-plugins-<pid>` that keeps SVG, JPEG, WebP and GIF (the icon themes, the wallpaper library's
png/jpg/webp/gif/bmp, clipboard PNGs); PATH entries point at links to the same dirs, so commands resolve as before.
`KURASHI_IMAGE_FORMATS` names the kept formats, `all` disables the filter. It also sets `MALLOC_CONF=narenas:2` for
quickshell's jemalloc (48 arenas on 12 cores by default; an idle window's arena keeps its freed pages) unless the user
sets one. The launcher window stays persistent (K16): made on first open it cost +6…+17 ms on that open, and a window
re-made per open scattered the 20-cycle growth 3–4× wider. *Evidence:* BENCH "2026-10-25 — W42 memory": PSS @1 output
126.3/123.8 → 110.4/107.1 MiB in same-run pairs (−16, the arenas); the plugin filter −9.9 MiB RSS of libraries in every
run (PSS only where no other process shares them); idle frames 0; popup and launcher first open unchanged; start-up
+50 ms in launch.sh. The tests start `qs -p` directly and do not exercise this yet (row 462, I217).


## K71 — layout: one bar per edge, a screen frame, three draw modes, one reveal model (2026-10-26, session 14)
The user's draft (session 14, points 1–8, 11, 12, 14) asks for a screen frame, draw modes that apply to every
surface, floating bars, bars on several edges, modules pinned to edges, and bars/sidebars/dock that are always
shown, shown on hover or hidden. They are one concern — where the shell's surfaces stand and how they meet — so they
get one owner: the daemon's **layout step** (ARCHITECTURE §4 already gave it corner ownership) and one document,
`runtime.layout` (PROTOCOL §3.1, fixture `fixtures/ipc/server/snap_runtime_layout.json`). Layout is the user's, never
a look's (K53, COMPOSITION §6): no style or look sets these keys; looks give only the tokens the frame and the joins
draw with (rule 4). User decisions (session 14): preset **dynamic**; the frame **reserves space** by default and may
be set not to; sidebars **slide in from their screen edge** in every mode (replaces W34's grow-from-the-button
motion; the fillet to a bar stays); **one bar per edge**.

**Schema v3** (one bump, one migration `v2_to_v3`, run on `config.toml`, its `[outputs.<name>]` tables, user and
bundled profiles; `managed.toml` is written by Nix and is migrated in memory the same way):
- `layout.draw` = `floating | dynamic | connected` (default `dynamic`) — the preset every component follows.
- `layout.reveal_delay` (ms, 250, 0–1000) — the dwell for every hover reveal; an edge another output touches waits
  twice as long (the dock's I137 rule, now everyone's).
- `layout.frame.enabled` (per output, false) · `.thickness` (8 px, 2–32) · `.radius` (inner corners, 16 px, 0–48) ·
  `.reserve` (true).
- `edges.<top|bottom|left|right>` (all per output): `.bar` (top true, the others false) · `.visibility` ·
  `.reserve` · `.draw` · `.start` · `.center` · `.end` (module ids, `choices_from = "modules"`). An edge with a bar
  shows its zones in the bar; an edge without one shows each non-empty zone as an **edge module** (K72) pinned to the
  frame or the screen edge. Replaces `bar.enabled` and `bar.edge`; `bar.height` stays (one thickness for every bar;
  per-edge thickness is BACKLOG).
- `visibility` (bar, edge modules, dock, each sidebar) = `always | hover | empty_desktop | hidden`: always shown;
  shown after the pointer dwells on its edge (hidden again 400 ms after it leaves); shown while the output's active
  workspace has no window, else on hover (the dock's `emptyDesk` rule, I137); shown only when asked (key, CLI,
  `layout.toggle`). `reserve` = `auto | on | off`: auto keeps space only for `always`; `on` keeps it while hidden too;
  `hidden` never keeps space (`reserve` is inert there with the reason `layout.reserve.hidden`, Shōjiki).
- `draw` (bar, each edge, dock, each sidebar, the island) = `auto | floating | dynamic | connected`; `auto` follows
  `layout.draw`. The document carries the resolved value and `"source": "auto" | "set"` so Settings says
  "Auto (dynamic)".
- `dock.autohide` → `dock.visibility` (true → `empty_desktop`, the default, which is what autohide did; false →
  `always`) + `dock.reserve` + `dock.draw`.
- `sidebar.style` / `sidebar.width` / `sidebar.right` / `sidebar.left` → `sidebar.<right|left>.sections`,
  `.width` (resizable by dragging the inner edge, written on release), `.visibility` (default `hidden`: opened by
  key, button or `sidebar.toggle`; `hover` = point 14's edge dwell; `always` = pinned open), `.reserve`, `.draw`
  (`panel` → `auto`, `floating` → `floating`). `sidebar.bar_buttons` folds into the zones (the modules
  `sidebar_left` / `sidebar_right`); false removes them from the migrated zones.
- `desktop.order` → `desktop.right` and `desktop.left` (cards per side, top to bottom); `desktop.side` stays as the
  side for cards neither list names; `desktop.hidden` stays.

**Geometry rules** (computed in the pure crate `crates/kurashi-layout` — kurashid and kurashi-mock both use it, row
482 — from config, theme tokens and the outputs, unit-tested; PROTOCOL §3.1 lists the settled rules; rebuilt on config, theme and output changes, nothing polls). Every offset is measured from a screen
edge, so the daemon needs no output size. `band(e)` = the frame's thickness on `e` when the frame is on and no bar
sits flush there, else 0. A **dynamic** or **connected** component stands flush on what is under it (band, docked bar,
or screen edge) and joins it: dynamic with concave fillets of `join_radius` (token `radius.lg`), connected with straight
corners (radius 0); its free corners stay rounded. A **floating** component stands `gap` (token `space.sm`) away from
everything, every corner rounded, with the look's shadow. A docked bar *is* the frame's band on its edge (one sheet).
**Exactly one surface per edge holds that edge's exclusive zone** (`holder`): the frame's strip when the frame is on
and reserves, else the edge's bar, else the dock, else a sidebar, else an edge module; all others use
`ExclusionMode.Ignore` and the doc's insets. Caelestia's four 1×1 exclusion windows were not taken: a layer window
costs ~3.5 MiB (I11, B7), so the zone rides on a surface that exists anyway.

**Draw modes in brief:** bar — floating: inset by band + gap, rounded ends; dynamic/connected: flush, the frame's band
on that edge. Dock, edge modules, island — join the band or the bar on their edge. Sidebars — span from the bar (or
band) at one end to the band at the other, flush to their side, sliding in from it.

*Evidence:* user draft (session 14, images 1–13); Caelestia `modules/drawers/` (ContentWindow, Exclusions,
Interactions; research notes in `docs/ux/frame.md`); KDE Plasma 6 panels (floating, visibility "Always visible / Auto
hide / Dodge windows / Windows go below", panels on any edge); Waybar and HyprPanel (`modules-left/center/right` per
bar, one config per bar); the dock's own reveal rules (I137, B7).

*Amendments (W44 reviews, rows 510–531):* a docked bar carries its edge's frame strip and holds that edge's zone
(`holder: bar`; row 492 b measured cheaper than a strip window); a `hidden` bar is not the band (the frame bands the edge,
the bar comes out over it); a side bar's `span` comes from the daemon (the horizontal bars own the corners);
`layout.bar.move` keeps the destination edge's own modules after the bar's; a sidebar target of `layout.toggle` is
`sidebar.toggle` (one truth, no `shown` entry); `keys.bar_<edge>` and `keys.dock` bind `layout.toggle` (empty by
default); `"*"` in output maps is an alias views skip. A sidebar under a floating bar starts `gap` below it in every draw
mode (free rounded end, `joins: none`; user decision 2026-10-26, I253 (a)) — never over the bar's end.

## K72 — modules: one id, every variant (2026-10-26, session 14; user points 8–10)
A **module** is a placeable unit with one id: core ones (`workspaces`, `windows`, `island`, `volume`, `recorder`,
`keyboard`, `clock`, `quick`, `tray`, `sidebar_left`, `sidebar_right`) and mods' `widget:<name>` as
`mod:<id>:<name>`; the pseudo id `mods` stands for every enabled mod widget no zone names (where mod widgets went
before K71). The daemon's `modules` choice list offers them; `runtime.layout` carries zones resolved to entries
(`{id, kind, mod?, provide?}`), enabled modules no zone shows in `unplaced` and entries it cannot draw (unknown id,
mod off, no glance) in `problems`
— the faces pattern of W40 (offered back in Settings, row 450). A module may ship these variants, each optional and
each a provide the frontend already knows how to load: **glance** (`widget:` — the bar and the edge module),
**peek** (`peek:`), **expanded** (`panel:` or the face's `:expanded`), **desk card** (`desk:`), **sidebar** (a
`panel:` offered in `sidebar.*.sections`), **island face** (`island-face:`, whose expanded view is the face's
`:expanded`), **quick tile** (`slot:quick.tiles`). A variant a module lacks is not offered in that place (Settings
says why), never drawn empty. The timer mod (K73) is the first module to ship every variant; the existing ones' gaps
are BACKLOG rows (one per module). The rearranging edit mode ("redesign", SekaiPop) is deferred (BACKLOG).

## K73 — timer and pomodoro as a mod (2026-10-26, session 14; user point 16)
Mod `timer` (native tier, `crates/kurashi-mod-timer`, `mods/timer`): countdown timers and a pomodoro cycle (25 / 5 /
15 min, a long break after 4 rounds; all settings). The daemon owns the state (`mod.timer`: each timer's `{id, kind,
label, phase, round, duration_ms, ends_at_ms | remaining_ms, running}`) and fires the end (a notification and an
island transient, sound by the notification server's hint); the frontend interpolates the remaining time from
`ends_at_ms` like the media position and ticks at 1 Hz only while a countdown is visible (rule 5). No polling, no
timer in the daemon while nothing runs (one deadline). The deadline lives while a timer runs, not only while `mod.timer` has a subscriber: a timer ends with every view closed. A stopwatch is BACKLOG.

## K74 — one corner radius, concentric; the expressive motion (2026-10-28, session 15; user)
**Radius.** The user (session 15): "There should be a dedicated setting for the radius — this radius should influence the
radius of the frame, the joins, and also buttons, toggles etc. … if radius is set to 20, the screen edges might have the 20,
the outer frame 20 too, the inner frame 20 − x where x is the number of pixels between the outer and the inner frame side
… they should match visually if a radius is the inner side of another one." And: a square look squares the frame too.
- Schema v4: `theme.shape.radius` (px, 0–48, default 18) replaces `theme.shape.radius_scale` (migration `v3_to_v4`:
  `round(18 × scale)`, at the root and per output). Tokens: `radius.lg = R`, `radius.md = round(2R/3)`,
  `radius.sm = round(R/3)` — the old steps at 18 px, so the default is pixel-identical (theme goldens unchanged but for
  motion). `corners = none` still collapses every step to 0 (the control is inert with that reason).
- `layout.frame.radius` went. The window cut into the sheet has **one** corner radius: `R − thickness` on a framed output
  (the inner curve of a band `thickness` wide round an outer corner of `R`: concentric), `R` without a frame. The layout
  publishes it as `frame.radius`, the dock's and both sidebars' `radius` (PROTOCOL §3.1, fixture); the joined dock and
  columns take it for their free corners too, so every corner of the hole, concave or convex, is that one radius
  (Caelestia's border and panels share one rounding). Washi (R 9) and an 8 px band give 1 px: nearly square, as the
  look's own corners are small; a look or the user raises R for rounder holes.
- Not in this step (BACKLOG I269): the concentric rule for nested controls (`inner = outer − inset`: a button inside a card,
  the Settings nav), pixel and straight-line joins (I270).
- **Screen corners (session 16, user: "should follow the radius by default, but there should be a toggle for it").**
  Schema v5: `theme.shape.screen_corners_follow` (default on): the screen's outer corners are `radius.lg` — screen R,
  band round it, hole `R − thickness`: the whole chain concentric (0 under `corners = none`: a square look squares the
  screen too). Off, `theme.shape.screen_corners` (px, inert while following — `requires`) sizes them as before. The
  layout resolves it once and publishes the top-level `screen_radius` (PROTOCOL §3.1, fixture); `ScreenCorners` and the
  frame's and a docked bar's corner fillets all draw that number. Migration `v4_to_v5`: a file that set
  `screen_corners` (0 included) chose a size and gets `screen_corners_follow = false`; every other file follows.
**Motion.** The user: "in dynamic they should look and feel like they do in caelestia shell"; keep the springs as a
separate setting, adapt them where they conflict.
- `theme.motion.profile` gains `expressive`, the new default; looks that said `calm` say `expressive` (lively and none
  stay). Tokens `motion.kind` (`timed | spring | none`) and `motion.timed.{open,close,fast,effects}_ms` + `_curve`:
  Caelestia's M3 expressive values (caelestia-dots/shell `plugin/src/Caelestia/Config/tokens.hpp`, read 2026-10-28):
  open = expressive default spatial `[0.38, 1.21, 0.22, 1]` over 500 ms (overshoots ~1.4 %), close = emphasized
  (two segments) over 400 ms, effects `[0.34, 0.8, 0.34, 1]` over 200 ms; ×1/speed.
- Frontend: `core/Glide.qml` (one value on the curves, or the spring it had) moves the bar, the dock and edge modules;
  `MorphSprings` (Stage, launcher, notification centre, toasts) and the sidebar run the curves while timed. A docked
  bar's and a column's overshoot widens them inward (the body stays on its edge), as Caelestia's bar widens past its
  content.
- Grow out of the border: a docked hover bar keeps the frame's band on its edge while it is away; out, it is the band
  grown thick — the frame's fillets, arcs and rules follow its moving edge on any of the four edges (`IslandGeom.lifts`,
  FramePieces `lift*`), and a column joined to it follows it down to the band. The island keeps its own springs (its
  identity, K42).

## K75 — one sheet, honest switches: blur, popups, unbuilt mods, click-away, the seasons (2026-10-28, session 16; user)
The user's live check after session 15 (BACKLOG I276–I281).
- **Blur follows the material (I276).** The daemon overwrote the material-gated `blur` token with the raw switch and the
  frontend never read it: every bar, frame strip and sidebar asked for compositor blur whatever the material, as plain
  rectangles, so the blurred backdrop showed square past rounded corners (niri 26.04 implements
  `ext_background_effect_v1`). Now the token is the material's (`glass` and the switch on and the compositor able),
  `Theme.blur` gates every `BackgroundEffect.blurRegion`, and the regions take the corners as drawn (Quickshell 0.3.1's
  `Region` per-corner radii; `ColumnShape.sTL…sBR`, its canonical corners mirrored back to the screen). The fillets'
  wedges stay unblurred (a small gap in glass; noted, not a hard edge).
- **Popups are the sheet they grow out of (I277).** The Stage's, launcher's and notification centre's cards took the
  container colour and the hover peek and the dock's tooltip and menu the container colour without relief. They take the
  surface colour at the bar's opacity (the same token, `color.surface_alpha`), and the peek and the tooltip carry the
  relief. The container colour stays for tiles and controls inside a sheet.
- **A moving column or dock reads as at rest (I278).** Their rule openings are published on every frame they show, not
  only at rest; the dock's motion starts on its window's first presented frame (as the sidebar's and the Stage's).
- **A click elsewhere closes (I279).** No Close buttons on click popups. Layer surfaces see no click outside themselves
  and niri gives them no focus grab, so `ClickAway` maps one transparent top-layer window per output over the usable area
  while a card, the launcher, the notification centre or a tray menu is open; a press runs `ui.close`. Under the overlay
  popups, over apps, clear of the exclusive zones (a bar widget still takes its click).
- **A switch that cannot work is not shown (I281, amends B15).** A native mod whose daemon code this build does not link
  is dropped from the registry: no list entry, no page; its config entries stay. `media` stopped being a mod (core:
  `svc.media`, the island's face, the desktop card); its manifest went. `easter-eggs` waits for code (I286).
- **The seasons have colours (I281).** The tint swung only warm↔cool, ≤ 5 %, ≈ 0 in spring and autumn. Each solar
  term now leans toward its season's hue (anchors: 大寒 winter blue 215°, 清明 sakura 340°, 夏至 fresh green 120°, 霜降
  maple 18°, interpolated along the year through plum, rape-flower yellow, gold and crimson): hues 20 % toward it, then
  a 10 % blend toward it at the colour's own lightness (contrast stays; the wcag stage runs after). The theme document's
  `appearance.season` says today's term and lean; Settings shows it under the switch.
- **Squircles (I281, session 16, user: implement them).** `corners = squircle` draws every quarter corner as a squircle:
  one cubic between the circle's ends, its handles 0.88 of the way to the corner point (`core/corner.js`; the middle of
  the curve about where a superellipse of exponent ~3.5 has it). Same ends and tangents, so lines, fillets and ruled joins
  meet it as they met the arc. The path shapes (ColumnShape, MorphShape, Toasts) pass their SVG through
  `Corner.squircled` (quarter `A` → `C`; two quarter arcs of one radius with almost no straight piece between them are a
  pill's end and stay round); the frame's rule arcs and fillets, the screen corners and the pen's outlines follow; Block
  draws its shadow, rim and ring fill with `SquircleRect` (Loaders, nothing made in a round look). The theme scales the
  radius steps ×1.3 under squircle (`SQUIRCLE_SCALE`): a squircle with the circle's ends sits closer to the corner, so a
  longer one reads as round as the radius set — and K74's concentric chain (screen, band, hole) scales with it.
  Leftovers (Rectangle-drawn corners, the relief's box): I288.
- **Nested corners (I269, session 16).** `Theme.nested(outer, inset)` = `outer − inset` (≥ 0) is the radius of a corner
  that lies `inset` inside another: the Settings navigation's plates (inside the sheet's `radius.lg`, across the column's
  gap) and the sidebar's section plates (inside the column's corner — the look's radius floating, the hole's joined —
  across its padding; the sidebar window publishes it as `sectionR`). A joined column whose hole radius is no more than
  its padding gets square plates: the rule, not a bug; a rounder look raises R.
- **The dock on the top edge (I282, session 16).** `dock.edge` takes `top` (the schema's enum; the layout was edge-generic
  already): under the top bar it joins `bar:top` and grows out of it, the bottom's mirror (its joined frame unflipped, the
  tooltip and menu below, the hop downward). A dock joined to a bar that slides (hover, empty desktop) rides that bar's
  edge: it moves by the bar's published lift (`IslandGeom.liftOf`, K74) inside its own window — content and clip line,
  no resize per frame — so bar and dock never part while either moves, on the top and the bottom edge alike.
- **A layout per sidebar (I283, session 16).** `sidebar.<side>.mode`: `stack` (one column, every section stacked — the
  right's default) or `pages` (one section at a time under wrapping tabs — the left's). Either side takes either: in pages
  a core section (header, tiles, levels, notifications, calendar, media) is a page of its own, drawn as the one column
  draws it; in a stack a mod's panel is a section. A stack without a section that fills keeps its spare room below.
- **A style is more than a palette (session 16, user).** catppuccin, rose-pine and tokyo-night were styles that only
  named a palette, a stock look and a few values: they are palette choices now (their palettes were there already), and
  the styles list keeps what has a design of its own. Schema v6: `v5_to_v6` turns a file's `theme.style` of one of them
  into `none` (your own) and writes the style's look, palette and recipe where the file had none — nothing changes on
  screen. The deeper style rework (Windows, macOS and console looks; a lock screen per style) is
  `docs/tasks/W53-styles.md`.


## K76 — the package is split: cached deps (crane), a data copy, the data dir at run time, tests as a check (2026-10-29, session 17; user, I290–I293)
`nix/package.nix` was one `buildRustPackage` whose source held the workspace *and* every runtime file, with the data dir
baked into the binary (`env.KURASHI_DATA_DIR = $out/share/kurashi`) and the whole `cargo test` in its check phase: a QML
line or a Japanese string recompiled ~400 crates and ran the suite.
- **Deps cached (I292).** crane (`github:ipetkov/crane`, a flake input): `buildDepsOnly` builds the dependencies from
  a dummy of the Cargo manifests (crane launders them at eval time), so only Cargo.lock / Cargo.toml changes invalidate
  it. It also compiles the dev-dependencies, which the tests check reuses; its `cargo check` pass is skipped.
- **Rust from Rust sources only (I290).** `bin` (crane `buildPackage`) sees Cargo.toml/lock, `crates/`, `fixtures/` and
  what our crates embed with `include_str!`: `looks/`, `styles/`, `palettes/`, `i18n/{en,ja}/doctor.toml`. Edits to
  those four still rebuild our crates (not the deps); loading them at run time is I294. The whole workspace is built
  (no `-p`): a package subset changes feature unification and would miss the deps cache.
- **Data at run time (I291).** `data_dir()` (kurashid) and `i18n_root()` (mod-timer) read `$KURASHI_DATA_DIR`, else the
  source tree; the `option_env!` arm is gone. The package derivation copies the data into `$out/share/kurashi` and wraps
  the binaries (`makeBinaryWrapper`, `--set-default`, so the sandboxes' and the greeter's explicit value wins). The data
  is copied, not symlinked from a third derivation: frontend, mods' QML and the greeter import each other by relative
  paths, and one file reached through two store paths would be two QML types. The wrappers exec the real binaries, so
  process names stay `kurashid`/`kurashi`. The launcher already strips `KURASHI_*` from apps it starts.
- **Tests out of `nix build` (I293).** `passthru.cargoTests` (crane `cargoTest`, the old source set and pre-check
  hook) is `checks.<system>.tests`; `nix flake check` and `just check` run them. A binary cache stays the user's call.
- **Measured (machine A, 2026-10-29):** cold build 657 s (deps + dev-deps + our crates); a QML or i18n edit 4–6 s
  (`bin` untouched); a leaf `.rs` edit 305 s (deps reused; our 31 crates in release, plus bindgen/pam-sys). Fast Rust
  iteration stays `cargo` in `nix develop` (incremental); `nix build` is for the installed result.
- The devShell no longer takes `inputsFrom` the package (now a plain derivation); it lists the Rust build inputs from
  `passthru.rust{Native,}BuildInputs`.
- **Fix (same day):** the unwrapped binaries are `passthru.unwrapped`, never `bin` — `lib.getBin` (writeShellApplication's
  runtimeInputs) takes an attribute named `bin` for the bin output, so `nix run .` started the unwrapped daemon without
  its data (raw strings, no mods, the default look, no Settings). Flake check `apps-wrapped` guards it.

## K77 — schema v7: Solid/Translucent with blur, squircle curve, frame outline, sidebars keep space while out; blur and joins follow what is drawn (2026-10-29, session 17; user's niri review, I295–I303)
- **Material (I297).** `MaterialKind` is `solid | translucent`; `theme.material.blur` belongs to translucent (default
  now off: kanso, soft, ps2 and hallownest are translucent and must not start blurring). Migration `v6_to_v7`: glass →
  translucent with `blur = true` unless the file says otherwise; an inert `translucent` + `blur = true` becomes false.
  Looks glass, aqua and aero say translucent + blur (same pixels). "Glass" is free for a future liquid-glass / Aero
  material. A user look file saying glass still reads (appearance shim).
- **Squircle curve (I300).** `theme.shape.squircle` 0..1 (step 0.01, default 0.77) → token `shape.squircle_k`
  (0.5523 + v × 0.4277; 0.88 at the default). `Theme.squircle` carries the ratio itself (0 for round), so every path
  built with it redraws when the slider moves; corner.js, pen.js and framegeom draw with it.
- **Frame outline (I303).** `theme.frame_outline` auto|on|off → token `frame.outline` (auto: keycap and line on, flat and
  soft off — chrome data, not a renderer branch). It draws the frame's rule, a bar's inner edge and the joined shapes'
  ruled fillets in the chrome's ink, or a hairline where the chrome has none.
- **Sidebar space while out (I301).** `reserve = on` with `hover`/`empty_desktop`: `reserve` 0 at rest and
  `runtime.layout.sidebars.<side>.reserve_open` (absolute zone, CONTRACT-CHANGE 558). The frontend tracks which sidebars
  are out (SidebarGeom); the edge's zone holder keeps `max(zone, reserve_open)` meanwhile, the sidebar itself where
  nothing holds the edge.
- **Blur follows the drawn shape (I295, I296).** Regions are built from numbers, not `Region { item }`: Quickshell
  recomputed an item region only on a resize, so a slid dock kept its region where it had hidden (unblurred at rest), and
  morphing cards used their final box (blur ahead of the growing shape). BarMorph and the Stage expose the body as drawn;
  the dock, the sidebar, the dock's tooltip and menu and the task list's popups have regions.
- **Joins (I299, I302).** A joined dock's foot stays on the band while its reveal overshoots (the body stretches). The
  frame draws the part of a joined neighbour's fillet that lies on its rule's row at each opening (layer stacking on one
  layer follows map order, so the neighbour's own window may lie under the band); a docked bar carries the frame's rule
  over its body.
- **niri is the lead platform** for visual checks (`tools/bench/niri-sandbox.sh`, CLAUDE.md): sway has no
  ext-background-effect and stacks layers differently; these bugs were invisible there.

## K78 — elevation shadows: the shell draws them, one light for everything (2026-10-29, session 18; user, W57/I310)
- **The shell draws every elevation shadow** in its own windows: two layers (ambient all round + key along the light),
  the surfaces' true shapes (fillets, squircles, the frame's hole as one inset shadow in screen coordinates) and joined
  shapes as one silhouette. niri's `layer-rule { shadow {} }` was weighed and not taken: one rectangle with one radius
  per surface, one layer, static, niri-only (<https://github.com/YaLTeR/niri/blob/main/docs/wiki/Configuration:-Layer-Rules.md>).
- **The light is shell-wide:** `theme.light` stops depending on the material (amends K67's inertness of `follow` under
  flat and line for elevation and block shadows alike).
- **Following the pointer lamp / spotlight is an option** (off by default; amends K67's "shadows never move with the
  pointer" for that option only): eased, only while the pointer light repaints anyway (W58), off under reduced motion.
- The band and docked bars cast onto windows with the key layer only (short reach). Soft and keycap looks ship Static,
  flat and line Off. Separate strengths for block shadows and elevation; levels per surface role from decor packs.
- UX brief: `docs/ux/shadows.md` "Elevation". Idle stays 0 frames; the shadow margin stays outside input, blur region
  and exclusive zone.

## K79 — the pointer position: cursor sessions from niri main, the fallback stays (2026-10-29, session 18; user, W58/I311)
- Upstream niri implements ext-image-copy-capture-v1 for outputs and cursors (niri#4554, merged 2026-09-12, commit
  849c576; <https://github.com/niri-wm/niri/pull/4554>), on `main` only (no release after 26.04). smithay has the
  protocol (Smithay#1902). So **no niri patch**: the flake pins niri `main` (≥ 849c576) as an input, and the modules
  use it only while the pointer light is on (replaces the session-17 plan of a patch in `nix/patches/`).
- **The fallback stays first-class** (user): without the protocol (another niri, another compositor, the input not
  enabled) the light follows the pointer over the shell's own surfaces as before, and Settings says why.
- **Back to a release as soon as one has it** (user: the pin must not cost long compile times for good): check niri
  releases now and then (a HANDOVER "Risks" line and a BACKLOG row) and drop the pin for nixpkgs' niri once it ships.
- Client side: `wayland-protocols` (feature `staging`, already enabled) has the bindings; a refcounted `pointer.rs` in
  `kurashi-compositor` in the shape of `idle.rs`; cursor sessions report `enter/leave/position/hotspot` only (no frames);
  a resting pointer sends nothing. Each session shows in niri's event stream as a cast (filter our own pid).

Measured (session 18, nested sandboxes): niri 849c576 (main) — `svc.pointer` reports the pointer over windows and the bare
desktop (`winit` 300,400 → 700,650 → 1000,200, one patch per move, none at rest); niri 26.04 — `available: false,
reason: pointer.no_protocol` and the frontend keeps its sensors; sway (nixpkgs, wlroots 0.19) — both globals offered,
sessions not exercised (the headless seat has no pointer: `pointer.no_pointer`, the watcher waits for one); Hyprland,
KWin — not measured.

## K80 — styles that look like their inspiration: lock faces, dress-only, title bars, fonts, sounds (2026-10-29, session 18; user, W53)
- Brief: `docs/ux/styles.md` ("Decided" at its end). Lock faces follow the style (`lock.face`, default `follow`).
- Styles dress, they never move things: an OS-like layout is an optional companion profile (K45 stands).
- Stage cards may carry a title bar with the full button set behind a switch (`off | close only | full`); every
  button's action is configurable (close = close, maximize = full screen, minimize = the app's own bar menu where it
  fits, else hide). Shōjiki: no button that does nothing.
- Free font stand-ins installed by Home-Manager by default; the user's own originals win when present.
- Every style supports an original sound-cue set (off by default); styles with a direct reference ship their own files
  (original sounds, never the trademarked ones).
- **Amends K42:** under high contrast a style's bevel stays (in high-contrast colours) instead of being forced flat.
- macOS styles: `aqua` (Jaguar–Tiger) and a new `vibrancy` (Big Sur–Sonoma).
- (later the same session) **The design system is extended wherever it keeps a style from a 1:1 look**: per-style
  animation styles and motion curves, fonts, icon sets and sizes, textures, sounds, window and frame decorations, OS
  colours, material effects (blur, bloom, glow), buttons/sliders/menus — as decor-pack slots and tokens (rule 4).
  **Every style ships a Layout Preset** (opt-in); the Windows styles a **start button** opening the launcher in a
  start-menu skin. **Cursor personality** (a stylised cursor theme, a cursor trail/decoration on W58's effects sheet)
  per style, **off by default**.

## K81 — W53's decor keys are additive tokens; hosts own the parts; washi gains its paper (2026-11-01, session 18; lead, W53.0–W53.8)
- Every key the style families needed went into `[decor]` (`DECOR_KEYS`, DESIGN-SYSTEM §4) or a new `[slots]` entry;
  the `theme` document publishes them all (PROTOCOL §8, K81 note). They are additions only — each family's merge kept
  every older golden's existing values (CONTRACT-CHANGE rows 590–623, accepted).
- A slot only shows where a caller hosts it: TitleHost, WindowEdge, MenuStyle/MenuRowFace, ScrollHost (launcher list
  only, BACKLOG), TooltipStyle, TrayWell, StartHost, BarGround, DockGround, the button and toggle slots, Caret.
  A look without the slot is pixel-identical (kanso, checked by `test-styles.sh` against main's shots).
- `Elevation.qml` knocks the shape out of its shadows under translucent fills (row 608): a glass card no longer shows
  its own shadow through itself. Fluent, aero, glass and vibrancy shots changed with it; solid looks are unchanged.
- **washi gains K59's `paper` grain (0.35, tinted), ruled menus, paper slips, a brush focus mark and an ink-bleed
  motion.** washi is the default style (K53, the user's choice), so this changes the default look on every surface. Plan §9 asked only
  for ruled menu rows; the lead accepted the grain after review on niri (subtle, reads as paper). One key undoes it:
  `theme.texture.kind = "none"`. The user may overrule this.
- terminal sets `surface.join = false` (its cards stand apart, as a TUI's boxes do); `test-island-join` pins a square
  line look for its terminal cases.
- (later the same day, user) **A style or look applied over a loaded profile releases the keys of its kind that the
  profile holds** (`Op::Release`, engine-internal, in the same undoable change; the profile file is untouched, its
  other keys stay). Before, a profile saved with a `[theme]` (the user's `default-v1`) pinned the look, palette, chrome
  and font above every style, so switching styles changed only the ink. Test:
  `theme::tests::a_style_applied_over_a_profile_recreates_the_pack`.

## K82 — Depth reaches the whole sheet under one light; cards come out where they were opened (2026-11-01, session 18; user, lead)
Evidence: the user on their niri ("the elevation … applies almost nowhere … independent from the shell's light system";
the washi island card standing in the bar as a box; a floating sidebar not concentric with the frame; "spawn at the same
position … not sometimes in the middle"; Noctalia's panel position option). Measured live on the user's DP-2: the dock's
level-2 shadow differed in 1 % of its pixels; the band under the bar cast nothing at all (BACKLOG I337–I341).
- **The sheet casts too** (K78 decision 4, built now): the frame band and docked bars cast the key layer into the hole —
  `SheetShadow` (frontend/shaders/sheet_shadow.frag: the Gaussian-blurred rounded rect in Wallace's erf form, CC0,
  inverted inside the hole, ±½ LSB dither). Each strip and each docked bar grows by `Theme.sheetReach` on its inner side
  (outside input, blur region and zone, which stay explicit); `FG.shadowOwn` gives every hole pixel one owner (top and
  bottom windows to their depth plus the room, the sides the rest split down the middle) — no seam, no double darkness.
  Floating bars and desk cards cast at level 2 (their windows grow by the reach); a card grown out of a strip casts from
  the bar's edge down, never onto the bar.
- **One light.** Under `elevation.mode = follow` a lamp held on the output (the spotlight's pin, the wallpaper's lamp) is
  a point light for the shadows as for the relief: each surface's shadow falls away from it at the surface's own place,
  longer the lower it stands (`Light.heldLamp`, `Light.awayFrom`: tan 40° / tan elevation, 0.5…2). Static lights keep
  the daemon's `elevation.dir`. The pointer lamp follows the pointer screen-wide only where the compositor reports it
  (`svc.pointer`, niri main — I316); on niri 26.04 only over shell surfaces.
- **Per style.** `theme.material.elevation` is a look key (in `LOOK_KEYS` and `STYLE_KEYS`, so a style resets it): washi
  and kami follow the light, material is static (M3's levels), the rest keep auto (soft/keycap static, flat/line off).
  New decor keys: `elevation.blocks` (0–1, default 1: a block casts a small key shadow where the chrome has none of its
  own — flat, line, bevel — never under a see-through fill) and `elevation.icons` (0–1, default 0: a glyph's crisp
  print shadow; washi and kami 0.5). `STYLE_KEYS` now holds every look key (texture depth/shadows/cracks, the pen,
  scope) — before, a style left the user's pen and relief settings standing — plus `title_bar.buttons`, the one
  non-`theme.` key a pack may set (fluent ships with none).
- **washi's paper reaches the wallpaper** (`theme.texture.scope = shell_wallpaper` in the look): a style used to keep
  whatever scope was chosen before it.
- **Strip chromes hang cards from the bar.** On a strip (no block to join: line, flat, bevel) an open island card's head
  melts into the strip (its fill fades to nothing as it grows) and the card hangs from the bar's edge by its fillets;
  before, the head stayed a box with its own corners in the bar.
- **A floating sidebar on a framed output is concentric with the hole**: its radius is the hole's less its gap (K74,
  `Theme.nested`), so the gap is one width round the corner.
- **Cards come out where they were opened** (`bar.popups = module | centre`, default module; `bar.popups_other`: modules
  that open the other way — Noctalia's panel position, per module). Every bar module registers as an origin
  (`module:<id>`) and notes a press (a passive PointHandler, or Enter); an island view opened from a module hangs from it
  instead of growing out of the pill; under centre a panel comes out under the island. Keys and the CLI keep today's
  places.
- **niri blurs what is behind.** niri's layer surfaces blur in xray mode (the wallpaper alone) unless a rule says
  otherwise; the niri include kurashi already ships (`kurashi-binds.kdl`, Home-Manager or kurashid) now carries a
  `layer-rule` turning xray off for `^kurashi-` on the top and overlay layers (validated with `niri validate`, 26.04).
  Desk cards gained their blur region (they had none).

## K83 — The motion engine: timing × form × choreography × accents, per surface, bundled as motion packs (2026-11-02, session 19; user, lead)
Evidence: the user (session 19) asked to split motion into separately settable parts — curves, animation styles, profiles
per style — with a dedicated motion menu and custom curves and styles, keeping today's motion. Today the axes are fused:
`theme.motion.profile` picks kind + curves + springs together, and a look's `[decor] motion.*` (K80, W53.0a) overrides
form and curves out of the user's reach and without provenance. Prior art read for the brief (`docs/ux/motion-engine.md`
§2): Hyprland's named beziers + per-event style lines, Compiz's Animation plugin catalogue (Magic Lamp, Fold, Roll Up,
Burn), KWin's effect plugins and global speed, niri's springs/easings and custom window shaders
(https://github.com/YaLTeR/niri/wiki/Configuration:-Animations), SwiftUI's `duration + bounce` springs, Material 3
Expressive's spatial/effects spring split (https://m3.material.io/styles/motion/overview), cubic-bezier.com/easings.net.
- **Five axes.** *Timing* = a curve per role (open · close · fast · effects): cubic (segments) · spring(response, bounce)
  · steps(n) · linear; the kind is derived from the curve, never a separate control. *Form* = what progress does to the
  whole surface, per surface class and direction. *Choreography* = content timing (late · with · cascade), stagger,
  origin, retarget. *Accents* = squash, jelly, overshoot cap, shadow during motion. *Speed* stays.
- **Motion packs** (`motion/<id>.toml`, built-in and `$XDG_CONFIG_HOME/kurashi/motion/`) bundle all axes as a profile.
  `theme.motion.profile` becomes a pack id (today's four values stay valid ids — no rename, no schema bump); a style's
  recipe recommends one at its provenance layer (K53); per-axis user keys override (`theme.motion.timing.*`,
  `theme.motion.form[.<surface>].{open,close}`, `theme.motion.{content,stagger_ms,squash,jelly,shadow}`; `""`/`-1` =
  the profile's). Precedence: default < style's profile < user profile < user axis < a11y force.
- **Looks stop carrying motion.** fluent, aqua, material, snes, ps2 and kawaii's `[decor] motion.*` move into packs of
  the same names, referenced by their styles; the decor keys go (pack-side data, no user migration). Resolved tokens for
  every style stay identical — the legacy `motion.timed.*`, `motion.spring.*`, `motion.kind`, `motion.style` remain,
  derived from the new ones, until every surface reads the new tokens.
- **Two form families.** Shape forms keep the live vector shape (join, neck, shadow, carried material, blur follow every
  frame; retarget morphs). Sheet forms capture the card into one layer only while 0 < p < 1 and warp it (GridMesh vertex
  shaders, fragment passes); the hinge stays on the bar, the static shadow fades out and the warp shades itself, a
  translucent fill draws solid while warped and blur returns at rest; retarget finishes the form, then morphs.
- **Today's springs bit-exact:** calm and lively become the internal curve kind `spring_q` (K42's SpringAnimation-unit
  integrator), not re-fitted. User springs use the analytic `spring(response, bounce)` (mass 1, SwiftUI's mapping),
  which maps 1:1 onto niri's `damping-ratio`/`stiffness`.
- **Custom styles**: declarative recipes (tracks over progress, validated by the daemon, one generic evaluator) in user
  packs; code forms only through QML-tier mods with precompiled `.qsb`; no raw GLSL in config.
- **Ma and budget** as acceptance (brief §11): idle 0 frames/layers/timers; motion frame CPU p95 ≤ 8 ms; mesh GPU ≤ 4 ms;
  sheet-form PSS ≤ +12 MiB, back to baseline within 2 s.
- **The user's answers (session 19):** D1 reduce motion forces a `reduced` profile of short fades (≤ 150 ms, no movement,
  no flash) instead of cuts. D2 sheet forms keep the hinge joined to the bar. D3 the island takes **every** form and
  follows the default unless `theme.motion.form.island.follow` is off, then its own `form.island.*` (the form animates the
  pill → card opening; faces and peeks keep K42's springs). D4 kami → origami, terminal → phosphor (CRT), aqua and
  vibrancy → genie on the dock and toasts; washi unchanged; the other new packs ship as offers.
- **Not a mod** (user, session 19: "if possible make the advanced motion system a kurashi mod … if the result would be
  better with direct integration do it like this"): direct integration. Every surface, Settings, reduce motion and the
  daemon's tokens depend on the engine; as a mod it would be a core dependency that could be switched off, and mods may
  not change contracts or draw inside core surfaces. Mods can add forms later (I347).
- **W59.0 as built:** `theme.motion` is its own Settings page (`motion`); the island's switch is
  `theme.motion.form.island.follow`; value type `curve` (`MotionCurve` leaf, control `curve`) validated by
  `kurashi_motion::curve::parse` (errors `error.config.curve.*`); choice sources `motion.profiles` and `motion.forms`
  (W59.0 offers today's ids; W59.1 the packs and the forms meta); `reduced` cuts until W59.1 resolves it.
- **W59.1 as built (rows 640–646):** every look that carried `[decor] motion.*` (fifteen, washi included) is a pack of
  its name, bit-exact (the sweep golden: every style × expressive/calm/lively/none unchanged). Packs carry a `base` and
  their blocks layer over the style's pack, so picking calm on washi still bleeds, as before. Settings stays honest
  through a daemon inert pass: under `reduced` or a pack that does not move (win95) every other motion row reads inert,
  and a surface's form that cannot serve it reads inert.

## K84 — Sidebars alike, a pin, bar buttons as switches; the desk's two columns in Settings (session 20, user)

🟢 Both
sidebars offer every section (core and the mods' panels; `sidebar.left.sections` now names `sidebar.sections`,
`sidebar.tabs` stays as the same list for old configs): the only differences are the layout (`mode`) and each side's
defaults — the frontend was already side-agnostic. `sidebar.<side>.pinned` (default off): the daemon lays a pinned
sidebar out as "always shown" and leaves `visibility` as chosen, so unpinning returns to it (survives restarts, no
runtime state); a pin button sits in the column's outer top corner over a row of its own. `sidebar.from_bar` keeps its
key but is "Quick settings opens the right sidebar" and no longer hides the right sidebar's button (it read as "buttons
in the bar" and took one away); under it, a switch per side is the layout's own state (on = a zone of the bar's edge
lists `sidebar_<side>`, K71): on adds the module at that end, off removes it. The desk: `desktop.left`/`right` are no
longer advanced and pick from `desktop.cards` (core cards, then the mods' `desk:` cards); `desktop.side` is "Side for
other cards". Free placement stays I222. *Why:* the user found the left sidebar poorer than the right, the "Open from
the bar" switch misleading, wanted a pin and both desk columns from Settings.

## K85 — The launcher button's logo: the look's mark, the OS logo, or your own image (session 20, user)

🟢 `launcher.button_logo` (look · os · own; default look) in every look, `launcher.button_icon` the image for "own"
(a path on this machine, never in the repo). "os" draws the OS's logo (theme token `os.logo` from os-release, read once
by the daemon, rule 1), tinted as the look's `[decor] start.logo_tint` says: none (its own colours), ink, or console (a
conic sweep of four hard quarters, red · yellow · teal · blue — the PS2 look). The PS2 look gets its own start mark,
`start/Towers.qml`: four light towers rising on a floor line in those colours (after its boot screen), never Sony's logo,
letters or controller symbols. *Why:* the user wanted the retro PlayStation logo on the launcher button; it is a
trademark we cannot ship (BACKLOG I374), so the look ships an original mark and the user can show the OS logo in the
look's colours or any image of their own.

## K86 — Motion polish: every form everywhere, a form's pace, three tiers on the Motion page, a style's own animation (session 21, user)

🟢 The user's eight points after W59 (`docs/ux/motion-engine.md` §8, §12; card W64):
- **Every form but liquid serves every surface class** (`kurashi-motion/src/forms.rs`): the dock, the bar's reveal and
  the web dock host them (W64). liquid stays on the morphing surfaces (it needs the origin's live shape).
- **Pace:** the forms meta gains `pace` (a duration factor); `SurfaceForm`'s Driver and Settings' preview stretch the
  profile's curves by it (`curves.js` `stretch`). *Why:* drop and fold at a 240 ms curve cross their story in a few
  frames; a per-form factor keeps the profile's character and the speed setting honest (the preview says the stretched
  ms).
- **Three tiers:** Profiles = packs that name forms (offers grouped `full` / `timing` in `motion.profiles`); a new key
  `theme.motion.timing.preset` (offers `motion.timings`: the timing-only packs) swaps the profile's `[timing]` and base
  (spring family) under its forms, not under a still profile; the per-role curves are their own section "Advanced
  curves". Sections renamed `profiles`, `animation_style`, `timing`, `advanced_curves`. The speed row moved into the
  preview stage; the preview-only ½× · ¼× are gone.
- **A style's own animation:** the table in brief §12 (the user accepted the proposal); a `kanso` pack (expand).
- **Fixes:** a sheet close keeps its content on the pages until it lands (Stage, BarMorph); `MorphSprings.snap()` ends
  every axis's timed travel (a card jumped back to its origin's width once a form landed and another axis moved — the
  sysmon stutter); a sheet form draws nothing at p = 0 (the first-frame flash); BarMorph's non-morph reveal is the
  sheet form's alone, on the profile's paced curves (the launcher flash); drop gathers the module's shape into a bulge,
  falls from rest under gravity, squashes and ripples; genie's shadow and fillets follow the pour; maximize/restore of a
  captioned card moves on the profile's curve.

## K87 — Dynamic Media Color: the track's colours as a stage over the resolved theme (session 22, user)
**Decision.** `theme.colors.media.*`: a switch, a tone (`cover`, `keep`) and a change of colour (`fade`, `wheel_closest`,
`wheel_furthest`, `direct`; `blend_ms`). While on and a track has colours, `kurashi_theme::media_tint` rewrites the resolved
tokens: the cover's colours become the roles, and every other colour token follows the role it was nearest to in the user's
theme, lists included. `kurashid` holds `svc.media` only while the switch is on. `ColorBlend.qml` draws the way between two
sets of tokens through `Theme.liveColors`, only when the token `media.tint` changes; the daemon owns the colours.
**Why a stage over the tokens, not a palette.** The wallpaper's route (K34) makes muted Material surfaces; the user chose the
Now Playing card's saturated look on their live shell. Nearest-role keeps rule 4: a custom look's `decor.bar.fill` or inverted
tooltip comes along with no name in the code (the prototype's first miss was YoRHa's bar, a list read through `Theme.decor`).
It never touches the config, so off is exact and undo and profiles need no special case.
**Why the blend in the frontend.** It is drawing, not state (rule 1), and apps cannot blend anyway: they take the landing
colours once.
**Evidence.** Prototype, branch `feat/s22-media-theme-proto`; brief `docs/ux/dynamic-media-color.md`.

## K88 — Wallpaper Color Grade: a baked 3D LUT from the picture's and the theme's palettes (session 22, user)
**Decision.** `theme.colors.wallpaper_grade.*`: a switch, a mode (`auto`, `match`, `balance`, `gradient`, `palette`), strength and
lightness. `kurashi_theme::wallpaper_grade` reads the picture's six main colours (median cut in Oklab), pairs them with six
theme roles by chroma, and builds a 33-point 3D table; `auto` takes a gradient map under a mean chroma of 0.035. The K59 picture
filter applies it before the relief, at the output's size, cached by everything that changes the bytes. `update_bake` sees every
published theme, so palette, style and Dynamic Media Color changes all grade the wallpaper, through the backend's fade.
**Why a bake.** Measured on the prototype's live shader: +93 MiB PSS on one nested output, against the frontend's 150 MiB budget;
a bake costs nothing between changes. Why picture-aware: a palette-only LUT gives one result for every picture and flattens it;
pairing keeps the picture's structure (Chang et al. 2015). Palette-only stays as a choice, `palette`.
**Trade-off.** The wheel blend does not reach the wallpaper: I401 keeps a live shader as an idea.
**Evidence.** Brief `docs/ux/wallpaper-color-grade.md`. The prototype was never committed and its worktree is gone (session 23).

## K89 — A copy that is not live is drawn again when its window maps (session 23, I298)
**Decision.** Every `ShaderEffectSource` drawn once and left alone is a `StillCopy` (`frontend/components/StillCopy.qml`), which
redraws when its window maps; `TileSheet` fills its tiles again on a map. New still copies use it.
**Why.** A window's scene graph starts anew on each map, and a copy that is not live is not drawn again by itself, so it comes back
empty: the dock lost its material from the next reveal on. A window that never unmaps does not show it, which is why it looked
driver-specific for a while (I298) when the checks only changed `Sheet`.
**Trade-off.** One redraw per reveal, and the tiles run live for 250 ms: only while the window is mapped and animating anyway (rule 5).
**Evidence.** Reproduced on the user's session (GTX 1060, kami and washi; floating, connected and auto dock) and in the sandbox:
`frontend/test-dock.sh` reveals a papered dock three times and fails on the first reveal without the fix.

## K90 — A module's options live in its right-click menu, named by the schema; the launcher places itself (session 23, I407, I408)
**Decision.** (1) A bar key says which module offers it: `#[kurashi(module = "<id>")]`, in `schema.settings` as the row's
optional `modules` (additive). A module's right click opens `module:<id>` in the Stage's `tray` panel, through
`tray.menu.open` as it stands, so the daemon has no new state and the one-panel rule holds; `TrayMenu` draws a tree built
from the schema and the config. (2) `launcher.place` = opened (default), centre, island, fixed. A key and a click both send a bare
`launcher.toggle`; the click notes its place in the frontend first (`IslandGeom.noteOpener`), view geometry as K82's press
note is, so the action's shape stays. (3) `modules.workspaces.*`, `modules.windows.*`: the first options of their own.
**Why.** User, session 23: a menu "similar to" a tray item's that "should also expose configuration options for that specific
module", on every module on a bar or frame; a start menu "centered in middle" when opened by key, adjustable to the click
point, the island or a fixed place. Prototyped in QML against a hand table first, then the table became the attribute.
**Trade-off.** A launcher opened by key no longer grows out of the island by default on looks that did (W34): that morph is now
`launcher.place = island`. Amended (user, session 23): the island's right click opens its menu, which lists and takes back the pin; the pin moved to the middle click (`island.main.input.middle`), and `island.pin {face}` pins a named face.
**Evidence.** `frontend/test-module-menu.sh`; reviewed on nested niri on kami and aqua, on top, bottom and left bars.

## K91 — The shell's forms on niri's windows, as generated custom shaders (session 23, I410)
**Decision.** `theme.motion.windows` gains `forms`: kurashid writes the window's form into `kurashi.kdl` as `custom-shader` blocks on `window-open` and
`window-close`. `window` is a thirteenth surface class (`motion.form.window.*`, `theme.motion.form.window.*`, a pack's `[form.window]`), so it resolves
as the others do. Every form has a GLSL ES 1.00 port in `crates/kurashi-theme/src/niri_forms/`, with the theme and the form's parameters as constants. Mesh
forms are run backwards per pixel, since niri has a fragment stage only. Opt-in. `docs/ux/niri-motion.md`.
**Why.** User, session 23: "the animations should represent the same style selected by the shell". The repos they pointed at
([nirimation](https://github.com/Xansidev/nirimation), [niri-animation-collection](https://github.com/jgarza9788/niri-animation-collection),
[liixini/shaders](https://github.com/liixini/shaders); all MIT) proved the hook carries such effects; they are fixed pastes, so nothing is copied: the forms are the shell's.
**Trade-off.** niri states custom shaders have no compatibility guarantee, and a refused one only logs a warning the daemon cannot see. So it is opt-in, the help says it,
and the suite compiles every form in niri. A window hangs from its own top edge (I412). A user's recipe had no shader until K95.
**Evidence.** `frontend/test-niri-motion.sh`; `niri_forms` tests through glslang; contact sheets of every form at four progress values on nested niri on the GTX 1060 (NVIDIA's compiler).

## K92 — Hover previews are last-seen stills, cropped by reading the layout from the picture (session 23, I284, I285)
**Decision.** `svc.previews`, refcounted: while a module with previews on subscribes, kurashid takes a `wlr-screencopy` still of an output once it settled after a change, and when the pointer reaches the bar. The workspace keeps it; each window it shows wholly keeps its crop. The Stage's peek shows them (`window:<id>`, `workspace:<id>`). `docs/ux/hover-previews.md`.
**Why.** User, session 23: a last-seen capture is fine. niri's `screenshot-window` always overwrites the clipboard (measured), and 26.04 has no window capture protocol. A per-window PipeWire cast was the live alternative, not tried: heavier, and it would light screen-share indicators.
**Trade-off.** niri does not say where a tiled window stands: `tile_pos_in_workspace_view` is `None` for them (`src/layout/tile.rs`, set only in `floating.rs`). So `locate` infers scroll and gap from the still's edges, and gives no crop rather than a doubtful one. It can be fooled only by edges that repeat the whole pattern exactly, and a window behind a floating one shows what covered it. When niri tells the position, the inference can go.
**Evidence.** `frontend/test-previews.sh`: known colours in each crop's corners and middle on nested niri, the clipboard untouched, nothing left when off. `kurashi_compositor::locate` unit tests.

## K93 — The font mix is one generated font, not per-label spans (session 23, I176)
**Decision.** `theme.typography.mix.*` makes kurashid build one font holding several fonts' letters, with a `calt` feature that moves on a font per letter and starts over per word (`kurashi_theme::font_mix`, on `write-fonts`, `skrifa`, `kurbo`). Tokens `font.mix.{file,family,state,missing}`; `Theme.families` takes it through a `FontLoader`. `docs/ux/fonts.md`.
**Why.** User, session 23: mix any fonts, pick how many, presets that imitate handwriting, a future plugin for one's own handwriting. A prototype drew both routes side by side: rich-text spans and the generated font look the same (`docs/media/fonts/comparison.png`), but spans cost about ten times the layout per label, have no elide, and would touch the 180 files that set a family. The font needs none of it.
**Trade-off.** Kerning, ligatures and mark positioning of the sources are not carried, and a variable font gives its default instance. A word starts at phase 0, so repeats across words are possible; the gain is that a label never re-mixes. New dependencies, all fontations' and pure Rust; `harfrust` for tests only. Python and fontTools were the quick route and were not added to a Rust daemon's closure.
**Evidence.** `font_mix` tests through `harfrust`; `frontend/test-font-mix.sh`; shots on nested niri on kami.

## K94 — Your own font, drawn in the shell: a native mod that makes fonts for Font Mix (session 23, I415)
**Decision.** Mod `handwriting`: a Stage panel asks for letters one at a time in a box with the letter's shadow and lines for capitals, small letters, the baseline and tails; Cancel, Retry, Save and next; beside it the whole set, drawn letters as drawn and the rest as their shadow. Strokes are kept in `$XDG_DATA_HOME/kurashi/handwriting`, and each version with drawings becomes a plain font in the user's font folder, which Font Mix (K93) mixes. A letter nobody drew is not in the font, so the toolkit falls back for it. `docs/ux/handwriting.md`.
**Why.** User, session 23, in those words. Others either scan a printed sheet (Calligraphr, no imports wanted here) or ask for ink per letter in a frame with guides (Microsoft Font Maker, iFontMaker: the model). Calligraphr asks for three or four variants of a letter for a convincing hand, and Quentin Blake's font rotates four: so several versions, each a font, and Font Mix already rotates them.
**Trade-off.** The pen has one width per font: no pressure yet. Strokes are stroked by `kurbo` and marked as overlapping, not merged. The Stage's mod card may now be 1100 px wide, up from 720, for this board. `font.rs` repeats some table assembly from `kurashi_theme::font_mix` (I419).
**Evidence.** `mods/handwriting/test-handwriting.sh` draws with a real pointer on nested niri; the crate's tests read the fonts through `skrifa` and `harfrust`.

## K95 — A user's recipes on niri's windows, generated from their tracks (session 24, I418)
**Decision.** A recipe that resolves as `motion.form.window.*` gets a `custom-shader` written from its `motion.recipe.<id>` token: `niri_recipe.rs` generates one GLSL function per
prop over p and each track's curve as a polyline; `niri_forms/recipe.glsl` is the frame's math of `recipe.js`, inverted per pixel by the adjugate of its projective matrix. A base is its form's
file, renamed `ks_base`, run at the transformed coordinate.
**Why.** User, session 23: the forms on windows should be the shell's. A recipe is declarative, so no port by hand is needed and a test need not refuse one. The same frame math keeps it the same motion.
**Trade-off.** No origin in a shader (the top edge's middle); blur is a 16-sample disc per base call; the clip keeps the shadow only while that clip is at rest; a large turn or translate is cut at niri's 500 px.
**Evidence.** `niri_forms` tests compile every prop and every kind of curve on every base through glslang; `frontend/test-niri-motion.sh` compiles the brief's recipes in niri and reads pixels of a slow wipe and shrink; a contact sheet on nested niri.
## K96 — The radius you set is the radius you see; a surface can take its own (session 24, I426)
**Decision.** Amends K74. `frame.radius` is the frame's radius, no longer it less the thickness; the screen's outer corner is it plus the band (`frame.screen_radius`, per output), so they stay concentric the other way round. `rLg + 4` and `rLg / 2` go: `radius.frame`, `radius.join`, `radius.window`, `radius.widget`, `radius.dock` are `radius.lg` unless `theme.shape.radius_<surface>` gives one its own (−1: Auto).
**Why.** User, session 24: "THEY SHOULD MATCH". Under washi (radius 9, band 10) K74 gave the frame's corner 0, the windows 9, widgets 13, a card's fillet 4.5. Caelestia's `border.rounding` is the hole's own radius.
**Trade-off.** A framed screen's outer corner grows with the band, past what a panel's physical corner may be. Screen corners keep their own setting for that.
**Evidence.** `frontend/test-corners.sh`; `docs/ux/corners.md`.

## K97 — The sheet casts as the rest of the shell does; Inward as Caelestia's (session 24, I427)
**Decision.** Amends K78 decision 4. `theme.material.sheet_shadow` (auto, follow, static, inward, off; tokens `elevation.sheet`, `elevation.sheet_dir`) rules the frame, bars, sidebars and dock. The band keeps a key layer and adds a faint one all round; a joined dock casts, cut along the edge it stands on. Inward: one even layer with no direction.
**Why.** User, session 24, with Caelestia's screenshot beside ours. Caelestia's sheet shadow has offset 0 (`modules/drawers/ContentWindow.qml`), so it falls inward evenly: I read the user's "inwards" as that, not an inset drawn on the sheet itself. To confirm with the user.
**Trade-off.** The strips' room grows from 25 to 29 px at strength 1; the shadow darkens a window's edge a little more than K78's short reach.
**Evidence.** `frontend/test-sheet-shadow.sh`; `docs/ux/shadows.md`.

## K98 — What opens at a bar in dynamic stands on it, and merges near a corner (session 24, I428)
**Decision.** In `draw = dynamic`, a Stage card under a widget and a launcher at its button merge with a neighbour along their side when there is no room for a fillet: flush, no fillet to the bar there, a concave fillet from the foot into the neighbour. MorphShape gets `edgeL` and `edgeR`; `JoinedCard` wraps ColumnShape for the launcher, its material with it. Amends session 15's "a card keeps clear of the bands" for dynamic alone.
**Why.** User, session 24, with Caelestia's popout: "it should connect to its neighbour bar/frame fluently". Caelestia unions blobs in one window (`modules/drawers/Panels.qml`, K71's "not taken"); separate windows with paths give the same picture at 0 frames idle.
**Trade-off.** Under a translucent material the fill overlaps a band by the outline's width. The launcher's slide lets its fillets move with it for the entrance.
**Evidence.** `frontend/test-popover-joins.sh`; `docs/ux/layout.md`.

## K99 — Terminals: shader, faint tile, or colours, and Settings says which (session 24, I420)
**Decision.** `theme.texture.terminals` switches the material in terminals. Ghostty keeps its shader; Kitty and WezTerm take a tile baked at 45 % of the relief; Rio, Alacritty, Foot and Ratty colours. `svc.theme_export` reports `targets[].material` (closes CONTRACT-CHANGE row 401's request). New targets `wezterm`, `rio`, `ratty`. Ratty's `ratty.toml` is written whole while it is absent or the shell's, as it has no include: the one exception to K49's "never edits an app's config", and only for a file that is not the user's.
**Why.** User, session 24, I420. A picture cannot keep off text, so strength is what keeps it legible.
**Evidence.** Each tried through Nix on nested niri (`docs/ux/terminal-texture.md`). Rio 0.5.28's `background-image` draws over the text, so it is not used. Foot 1.28 rejects `[colors]`, so the theme's sections changed.

## K100 — Browsers: profiles from their ini, a Link button, Zen by its layers (session 24, I422)
**Decision.** Zen and Firefox's profiles come from `profiles.ini`, listed per machine in `svc.theme_export`. `theme.export.link` writes the import and a marked block of prefs into one profile on the user's click, and takes back exactly that: a narrow, explicit exception to K49's "never edits an app's config". Zen's background and tile go on `.zen-browser-generic-background`'s pseudo-elements. `theme.browser_material`, `theme.browser_translucent`, `theme.browser_translucent_pages`.
**Why.** User, session 24. Zen sets its background variable inline on those elements, so `:root` can never win: read in its source, seen in the sandbox.
**Not taken: live colours by an extension.** Tested in Zen Twilight: an unsigned `browser.theme.update` extension runs with `xpinstall.signatures.required = false`, and its colours do not reach Zen's sidebar or toolbar. So a restart it is, and Settings says so.
**Evidence.** `docs/ux/browsers.md`; `frontend/test-browsers.sh`.

## K103 — A handwritten font's outlines are simple polygons (session 24)
**Decision.** `kurashi-mod-handwriting` unites what was drawn into non-overlapping polygons (`i_overlay`, integer grid, non-zero) before it writes `glyf`, rather than writing the stroker's self-crossing outline. Letters are polygons at 0.5 font units, not curves. Fonts on disk with older outlines are made again at start (`Font.outlines`).
**Why.** User, session 24: a font they drew crash-looped the shell, and "that shouldn't happen even with very bad handwriting". Seen: a `3` whose pen doubled back segfaulted Qt in `PathSimplifier::fillIndices` while making its distance field, in the font and in every mix with it. A renderer's bug on valid-enough input, so the input has to be one no renderer can trip on. The rule is enforced by a test on every outline.
**Left.** Any other installed font with such outlines can still crash Qt, and the frontend restarts into it: I440.
## K101 — The light across monitors (session 24)
**Decision.** `theme.light.outputs`: The one with the pointer (default, as it was), or All monitors. With All there is still one lamp, where the pointer stands in the layout's logical coordinates: every other output takes it in its own (`Light.xOn`, `Light.yOn`). A lamp off an output lights it from that side and turns its shadows that way; the spotlight's pool leans to the edge nearest it and stays on the output. Under `elevation_pointer` the sheet's shadow follows the lamp too. Only Pointer and Spotlight use it; Settings shows it inert otherwise.
**Why.** User, session 24: "the dynamic shadowing by the light is not just per monitor … i'd like it to effect both". One lamp, not a copy per output, so two monitors side by side read as one desk.
**Cost.** All repaints every output's reliefs and shadows as the pointer moves, so it is opt-in and its help says so.

## K102 — Handwriting as a feature: a place, options, ways in (session 24)
**Decision.** The mod gets settings (`panel_place`, `letters`, `default_pen`, `spacing`, `guides`, `shadow`, `next_letter`) and is 1.0. A mod's panel may name a place on the screen by the setting `panel_place`, read by the Stage (from config, before the panel is made, so the card knows at once whether it morphs). Any mod with a panel gets Open in Settings and a launcher row; handwriting gets a widget and a line on Settings › Fonts.
**Why.** User, session 24: "I can activate it but couldn't create a font", then "build a real feature out of it … a button to open the font creation … it should be able to spawn also centered (or on other positions just as the launcher menu)". Named places, not the launcher's sliders: manifest settings have no `requires`, and a slider that does nothing under another place would break rule 2.
**Left.** Pen pressure, kerning from sample phrases, shared table assembly (I419).

## K104 — The shell's monospaced font, and the apps that take it (session 24)
**Decision.** `theme.typography.mono`, a chain like `family` (first installed wins; default `monospace`; kami: Monaspace Radon), resolves to `font.family_mono` (CONTRACT-CHANGE rows 221, 343). `theme.export_mono`, off by default, gives it to the terminals that follow (Ghostty through its theme file, so it comes first and a user's own font stays as the fallback; Kitty, WezTerm, Alacritty by family alone, keeping their size; Foot at its own `[main]` size, since its one line holds both) and to the desktop's monospaced font (gsettings `monospace-font-name`, qt5ct/qt6ct and kdeglobals `fixed`, at the shell's body size). Rio reads only colours from a theme file and Ratty's config has none of ours: Settings says so. The font mix never goes to an app.
**Why.** User, session 24: "add the fonts for terminals with opt-in setting … general system/terminal fonts etc should follow the shells if it's opted in", and the mix for GTK/Qt apps as an idea only (I442). A terminal needs one fixed width: a proportional hand or a mix would break its columns, so the shell names a monospaced font of its own.

## K105 — One switch for the shell's fonts in every app that can take them (session 24)
**Decision.** `theme.export_fonts` (Fonts in apps; replaces K104's `export_mono` the same night) sends the shell's font to GTK, Qt and KDE (`font-name`, `general`, `font`), Vesktop and Obsidian (their CSS variables) and the interface of Zen and Firefox (`font-family` on the chrome), with the pages' fall-back fonts (`font.name.*` in a linked profile); and the monospaced font as K104. Off, those lines are empty and every app keeps its own, GTK's font included (it was written always before). `theme.export_fonts_pages` (Websites too) also sets `browser.display.use_document_fonts = 0`, opt-in on its own, because icon fonts on sites then show as words or boxes. Spotify (spicetify's `user.css`) and Zed (its settings) keep theirs: their font lives in a file of the user's own, which the shell never writes (K49); Settings says so.
**Why.** User, session 24: "font should get inherited in general with the setting, also to vesktop, spotify etc etc", and "what about fonts on websites? … I think they use their own".

## K106 — Palettes carry their authors' terminal colours, and sit in categories (session 26, I451, I452)
**Decision.** A palette file may name `category` (`kurashi` | `common` | `inspired`; `custom` for the user's), `family` and `variant`, and per scheme a `[dark.terminal]` / `[light.terminal]` table: background, foreground, cursor, selection and the 16 ANSI colours, as the palette's authors publish them. The common palettes (Gruvbox ×3, Gruvbox Material, Catppuccin Macchiato/Frappé, Rosé Pine Moon, Tokyo Night Storm/Moon, Nord, Dracula/Alucard, Everforest, Kanagawa Wave/Dragon, Solarized, One, Monokai, Ayu Dark/Mirage, the five Nightfox) are generated by `tools/palettes/from_kitty.py` from `kovidgoyal/kitty-themes` (each file names its upstream and licence); Catppuccin Mocha, Rosé Pine and Tokyo Night keep their hand roles and gain the tables. Nord and Monokai publish no light scheme: one is written from their own colours (K53), without a terminal table. Settings groups palettes by `category` through the offers' `group` (PackCards, as styles and looks).
**Why.** User, session 26: "they should use the real palettes like the real official gruvbox, rose-pine, tokyo-night, catppuccin palettes … so that it keeps everything readable"; categories Kurashi, Common, Inspired, Custom. Terminal colours derived from roles (green = tertiary) are what made a "Gruvbox" terminal not Gruvbox.
**Left.** Apps following the real palettes (I454) uses the tables; Custom palettes and the editor (I453).

## K107 — Wallpaper extraction modes, and the palette spread over the controls (session 26, I455)
**Decision.** `theme.colors.extraction`: Tone-matched (default, Material's tonal spot from one seed: as before), Vibrant (Material's vibrant variant), Prominent (the picture's own colours: its most populous dark/light as ground and text, its strongest distinct hues as accents, each moved in lightness only, and only as far as contrast needs) and Mixed (the picture's prominent colours spread over the shell: the most prominent as accent, the next as secondary, tertiary and lines, cards leaning toward a second colour). Clusters keep their most populous member's colour (a mean greys a vivid red). `theme.colors.controls` (Automatic | One accent | Spread): Spread binds sliders to the secondary, switches and quick tiles to the tertiary, selections to the secondary, buttons to the accent, through their component tokens (rule 4; the controls read `slider.fill`, `toggle.track.on`, `button.primary.bg`, `quick.tile.on.*` now); Automatic spreads under Mixed. A colour that has to move for contrast moves the shorter way, lighter or darker (`extract::lift`).
**Why.** User, session 26: "if you have a picture with Blue, Yellow and Red as prominent colors I'd like them to be actually visible in the same tone and hue"; then for Mixed "one background color, but the picture's other prominent colors are clearly visible accents, as button colors, secondary colors, slider, widgets colors". Prototyped as swatch sheets over the user's wallpapers (`examples/extract_modes.rs`), then live.
**Left.** Controls coloured by the wallpaper under them (the user's "C").

## K108 — Chrome fill: neutral or the strong colour (session 26, I456, I459)
**Decision.** `theme.colors.chrome_fill` (Neutral | Strong colour). Strong is a pipeline stage before wcag (`stages::strong_chrome`): the grounds take the accent's hue at its own chroma; the text prefers the palette's light (its own white), the ground deepening for it as far as 6:1 when that is a small move (≤ 0.2 OKLab L), else the palette's dark (a soft sage keeps its lightness), else plain white or black; containers step away from the text only as far as 5.5:1; lines keep the palette's outline colour; the accent becomes the palette colour whose hue stands furthest from the ground; every colour moves the text's way to its contrast. The apps that follow take it too (their files are written from the theme's tokens).
**Why.** User, session 26: "the strong contrast color as the frame color instead of the blackish or whitish tone", then corrections seen live: a sage turned olive (chroma forced up, always darkened), text flipped to black (containers too light), and the texture capped to nothing (text at exactly 4.5:1 left no room for shading) — hence 6:1 / 5.5:1.

## K109 — The chrome's gradient is one continuous sheet (session 26, I460)
**Decision.** `theme.colors.gradient.*` (`on`, colours: tones | colours, pattern: linear | radial | watercolour | the wallpaper under it, auto angle, angle, range of tones, softness, pool size, across all screens), over either fill. The daemon publishes `chrome.wash.*` tokens (stops chosen so the text keeps 5.5:1 on each; darkest first with the auto angle, which runs from the picture's light to its dark, `stages::light_axis`). The frontend draws it as Relief draws the material: `Wash.qml` + `wash.frag`, registered in output coordinates (Light.originOf), so every ground — bar strip, frame pieces and fillets, sidebars, the joined dock, Blocks on a ground, the Stage's morph and card, the launcher's card, Settings' boxes and window — shows its part of one sheet; across outputs from their places in the layout. The wallpaper pattern samples the output's own picture (as the backend crops it, loaded small: softness is the blur) and moves each colour's lightness in linear light only as far as the text needs. No FBO, no timer: idle draws nothing (rule 5).
**Not taken.** A per-window recolour pass keyed on the ground colour: an output-sized layer per window (8–33 MiB per output against the ≤ +6 MiB budget), and the relief and translucency make ground pixels not flat.
**Why.** User, session 26: "shift the color tint from one prominent value to another across the whole screen or multiple screen", watercolour bleeds, "replicates the on-screen color … where pink is, is pink", and "draw one background color sheet that then will be used by all surfaces".
**Left.** Moving colour (I461), pictures as a pattern (I462); the floating bar pill and a translucent floating dock are not washed yet.

## K110 — App icons and the launcher logo in the theme's colours (session 26)
**Decision.** `theme.colors.app_icons` (Original | Text colour | Palette tones | Palette colours) for the dock, the bar's window list and the tray, and `launcher.logo_tint` (As the look draws it | Original | Text colour | Palette colours | Palette tones) for the OS logo or the user's image. One shader (`IconTint.qml`, `icon_tint.frag`) as the Image's `layer.effect`, only while a tint is on: tones map the icon's own lightness onto the palette's accent, secondary, tertiary and text colour (dark to light), so its drawing stays; colours are the PS2 look's sectors made from the palette.
**Why.** User, session 26: "options for tinting the OS logo of the launcher and the other app icons … plain white/dark, or matched to the color palette … the nixos logo already has a playstation recoloring and it would be nice to have that for the most prominent/used colors".
**Session 27, after seeing it on niri and on the live session.** Text colour made an opaque icon a block and hid the launcher's logo (a masked fill that drew nothing); Palette colours made every app icon the same four sectors. Now one shader does every tint, the logo's included: ink is solid on a flat glyph and lighter or denser over a picture's own range of lightness; tones stretch to that range; Palette colours on an app icon gives each part the stop its hue falls on, shaded by its lightness, and stays four quarters on a logo (the PS2 look's console colours go through the same path). The launcher's rows and grid and a notification's app icon take the tint too (user, session 27).

## K111 — Settings draws as the shell does (session 26)
**Decision.** In Settings (`Theme.hosted`) a RoundBox takes the look's pen for its outline (PenOutline) and the wash on a ground's fill; the window's ground and the header strip are washed. A page's header stays on top once scrolled away, showing the page and the section in view, as an outlined strip on the ground.
**Why.** User, session 26: the menu "doesn't get the proper outlines the shell and widgets have", "ignores" the gradient, and rows "scroll into nothing".

## K112 — One allocation per bar row (session 26, B48)
**Decision.** `frontend/components/bar/barfit.js`: fixed modules take their width, elastic ones (window list, the island's media title, lyrics) share the rest and elide; the centre keeps the middle, then moves the least; then text → icon → a per-zone "…" overflow whose card holds the hidden modules (keyboard reachable). Modules nearest the centre give way first; launcher, workspaces, sidebar buttons, quick settings and clock last; the island never. Brief: `docs/ux/bar-fit.md` (W66).
**Why.** User, session 26: crowded zones overlapped ("Zelda Ocarina of Time …" under the battery and sysmon).

## K113 — A bar module opens on hover; every peek joins the bar (session 27, I457, I458)
**Decision.** `bar.hover` (Preview | Card | Menu, default Preview) says what resting on a bar module opens, and `bar.hover_preview`, `bar.hover_card`, `bar.hover_menu` name the modules that take their own; each module's menu sets its own (On hover). The frontend decides (`core/Peeks.qml`, `modules/ModuleHost.qml`): intent 220 ms, a grace of 380 ms after the pointer has left the module and what it opened, then `ui.close`; a click-opened card is never touched, a press makes a hover's card the user's. No daemon state: the daemon already holds what is open. On a top or bottom bar every peek grows out of the bar with the cards' fillet (`Theme.rJoin`), also in a look with a tooltip part; the balloon stays for side bars and with springs off. Brief: `docs/ux/bar-hover.md`.
**Why.** User, sessions 26 and 27: previews "should also smoothly connect … like the extended widgets do", "an option for the other bar modules to open their extended surface, or options (right click) already on hover … just like caelestia", then live: "one shared option for the whole bar by default but with optional overwrite setting per module", "the island should also get the hover animation", the merge radius "should all be the same". Three lists rather than a map: the schema's generators have lists of modules (`bar.popups_other`) and no map type; a map would have needed a new control in Settings.

## K114 — Three paint forms: splat, brush, snake (session 27, I467)
**Decision.** `splat` (drops of ink land one after another and spread; the card shows where ink landed a moment before), `brush` (strokes laid forth and back, slightly diagonal, away from the bar, with bristle streaks and a head that runs dry) and `snake` (the card as a grid of cells drawn row by row, forth and back, by a snake with a head and a body) are sheet forms as `dissolve` is: one fragment pass over the captured card, a function of p that is the card itself at 1, in the surface's own frame (they start at the bar's edge and at the module the card came from). Each has its niri window shader (K91) and a glyph in Settings. Pace 1.6 (splat) and 1.9 (brush, snake): they tell a small story. Params: `drops`, `strokes`, `slope`, `cell`, `length`, and `ink` (accent, secondary, tertiary, text).
**Why.** User, session 27: "a splat animation like ink drops get splatted onto the surface, painting and revealing the new surface … (similar to how the splatting in splatoon looks)", "a brush stroke brushing forth and back slightly diagonally and slowly painting/revealing the surface", "a snake-like spawn animation, that draws windows like in the snake game". No flag: none of them flashes (the ink is one colour over a few px of travel per frame) or turns the surface.
