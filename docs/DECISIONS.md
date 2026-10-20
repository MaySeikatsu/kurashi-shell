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
