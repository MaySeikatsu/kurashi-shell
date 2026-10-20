# Progress

Status: ⬜ todo · 🟡 in progress · ✅ done · 🔵 blocked · 🔴 reverted.
Step ids `M{n}.{step}`. Update in the same branch as the work.

## M0 — Foundations + frontend bake-off
| Step | Description | Status | Branch / notes |
|---|---|---|---|
| M0.1 | Repo, LICENSE, CLAUDE.md, docs skeleton | ✅ | `main` initial commit |
| M0.2 | Nix flake (devShell, packages, NixOS + HM modules), justfile, Cargo workspace | ✅ | `feat/m0-foundations`; `nix build .#kurashi` ✔, `nix develop -c just check` ✔ |
| M0.3 | `kurashid` skeleton (tokio, tracing, socket, NDJSON hello/welcome) | ✅ | handshake + ping; rest answers `unavailable` |
| M0.4 | `kurashi-mock` serving the probe subset (PROTOCOL §8) | ✅ | + `kurashi` CLI (act/sub/intent/mock/raw/ping); golden fixtures |
| M0.5 | Bench harness (`tools/bench`: headless sway, PSS, idle frames, CPU, wakeups/syscalls) | ✅ | self-test ✔ (Quickshell floor 110 MiB, see BENCH.md) |
| M0.6 | Bake-off task card + 5 probes (Quickshell, iced, Slint, GPUI, GTK4/Relm4) | ✅ | all 5 merged into `feat/m0-bakeoff` (session 2); agent usage in HANDOVER |
| M0.7 | Measure, fill `BAKEOFF.md` + `BENCH.md`, decide K3 | ✅ | K3 = Quickshell/QML (8.7); K16 PSS budget revised; `feat/m0-bakeoff` |

## M1+ — wave 1 (parallel, session 2; cards in `docs/tasks/`)
| Step | Description | Status | Branch / notes |
|---|---|---|---|
| M1.1 | Protocol v1 completion (typed apply/why/preview, diff patches, pushed snaps, instance) | ✅ | lead, `feat/m1-protocol`; K17; fixtures 31 |
| M1.2 | Daemon core: hub (revs, refcounted providers), action registry, intent coalescing, server | ✅ | lead; 7 socket tests |
| M1.3 | `kurashi-schema` + derive (registry, validation, generators, v1 tree) | ✅ | merged; goldens + trybuild |
| M1.4 | `kurashi-config` (layers, provenance, sparse TOML, migrations, profiles, undo) | ✅ | merged; 23 tests incl. proptests; K18 |
| M1.5 | Wire config/schema into kurashid (`config`, `schema.settings`, cfg.*), CLI get/set/why/undo/profile | ✅ | daemon + CLI; smoke-tested end to end with isolated XDG dirs |
| M2.2 | Theme wiring: config → `kurashi-theme` → `theme` doc; v1 schema `theme.colors.*`; a11y `overridden_by` → `forced:accessibility` | ✅ | lead; test: reduce_motion zeroes motion tokens with provenance |
| M5.6 | Daemon wiring: launcher query + launch, notification server (non-stealing claim), mods registry + `mods` doc, `runtime.ui` + `island.expand`; schema `notifications.*`, `launcher.*`; island input defaults aligned | ✅ | lead |
| M1.6 | Frontend skeleton (Store, Theme, I18n, Bar, Stage, Island, ProvenanceChip, veil) | ✅ | merged; idle 0 commits, popup 2.1 ms; PSS popup/2-out 221 MiB ✘ K16 → M3.1 |
| M2.1 | `kurashi-theme` pipeline → token map | ✅ | merged; 14 tests, AA on all palettes × modes |
| M3.1 | Stage sized to content, popup only on focused output (K16) | ✅ | popup 112 MiB (was 221); per-output OK under corrected method (K19) |
| M1.10 | Frontend core: generic on-demand docs + query API, real daemon (i18n, config, lock, notifications) | ✅ | `frontend/test-real.sh`; reconnect bug fixed |
| M5.7 | UI: island faces | ✅ | clock/media/volume/notifications faces; notifications face via unread relevance |
| M5.8 | UI: notification toasts + center | ✅ | toasts top-right (max 3 + N), center via `notifications.center`; windows unmapped when idle |
| M5.9 | UI: launcher | ✅ | `launcher.toggle`; fuzzy results per keystroke; launch verified with fake entries |
| M5.10 | UI: lock screen | ✅ | WlSessionLock per output, wrong-password + rate limit verified in sandbox; K20 lock survives restart |
| M6.1 | `kurashi-mods` manifest, discovery, lifecycle registry | ✅ | merged; not wired yet |
| M4.4 | `kurashi-audio` (svc.audio, PipeWire/Pulse) | ✅ | merged + wired (refcounted, origin echo, audio.mute.toggle) |
| M7.1 | HM/NixOS modules: user services, managed layer, eval test | ✅ | merged; `just nix-eval-test` (impure, CONTRACT #3) |
| M5.2 | `kurashi-notify` notification server + history | ✅ | merged; 14 tests on private bus; not wired yet |
| M5.3 | `kurashi-launcher` index, fuzzy+frecency, launch | ✅ | merged; 35 tests, p99 0.82 ms/500 apps (release); not wired yet |
| M1.8 | CLI get/set/why/reset/undo/redo/profile | ✅ | merged; exit codes 0/1/2/3 |
| M1.9 | **M1 exit: protocol v1 frozen** | ✅ | PROTOCOL.md status, K17 |
| M5.4 | Settings app (schema-generated pages, provenance, profiles) | ✅ | merged; `settings/test.sh` + 4 shots; schema i18n en+ja |
| M5.5 | `kurashi-auth` PAM + lock state machine | ✅ | merged + wired (`runtime.lock`, lock.submit/cancel, session.lock; PAM feature on) |
| M7.3 | `kurashi doctor` | ✅ | merged + registered with startup facts (bus probes n/a for now) |
| M7.2 | Budget gate: measure.py --daemon real + budget.py | ✅ | `just bench-gate` green: daemon 8.5 MiB, frontend ≤120 MiB, +0.8/output, 0 idle frames |
| M5.1 | `kurashi-island` arbiter (K9) | ✅ | merged; wired in kurashid (`runtime.island.main`, island.next/prev/pin, one deadline timer) |
| M1.7 | `i18n` document (daemon + mock), nix package ships data | ✅ | contract row 1 |
| M4.3 | `svc.workspaces` provider from compositor (refcounted, `*` alias, workspace.focus) | ✅ | kurashid |
| M4.1 | `kurashi-compositor` trait + niri adapter + fake | ✅ | merged; niri 26.04 fixtures (read-only) |
| M4.2 | `kurashi-services` (MPRIS, UPower, logind, NM, brightness) | ✅ | merged + wired as refcounted providers; media → island signal |
| M3.2 | Memory headroom Kaizen + leak-cycle gate | ✅ | quiet gate 0470378: 104.3 MiB, +6.0/output (at limit), +0.63 MiB/20 cycles, 0 violations |
| M2.3 | Blur capability probe → `forced:capability` | ✅ | `compositor.caps` doc; probed at startup |
| M5.11 | Island from config, `bindings` doc, `input.dispatch` | ✅ | merged + wired; launcher watcher drop hang fixed (5e08eb5) |
| M5.12 | Launcher watcher refcount, async doctor facts, session actions | ✅ | confirm-required session actions; doctor bus/name facts live |
## Wave 7 (Haiku agents; cards in `docs/tasks/README.md`)
| Step | Description | Status | Branch / notes |
|---|---|---|---|
| M5.13 | Brightness/volume key actions + island OSD; lock refuses without PAM service | ✅ | merged; island timer spawn fixed (handle + poison-tolerant locks); volume keys need a standing svc.audio subscriber |
| M5.14 | UI: session menu + brightness face | ✅ | merged; island maps brightness face; menu opens on focused output (d9bdaf5) |
| M5.15 | UI: input via `bindings` / `input.dispatch` | ✅ | merged; `frontend/test-bindings.sh` (left click driven via virtual pointer; other slots unexercised) |
| M7.4 | `nix run` apps + README "Running" | ✅ | merged; `nix run .#sandbox` green; default/settings verified by eval only (never run on the display) |
| M4.5 | SNI tray crate | ✅ | merged, not wired; add `icon_theme_path` before frontend work |
| M4.6 | BlueZ service | ✅ | merged, not wired (system bus, refcounted start) |
| M5.16 | Settings search + Mods page | ✅ | merged; + forced-reason placeholder and bundled-mod version fixes; mod description = CONTRACT row 5 (open) |
| M0.8 | Mock parity (runtime.ui panels, bindings, brightness, session) | ✅ | merged; mock lacks svc.notifications/notify.* (later) |
| M5.17 | Honesty test over all keys | ✅ | merged; found requires-inert gap → K21 (case ignored until M1.11) |
| M1.11 | Daemon reports inert/pending-restart reasons (K21) | ✅ | merged; honesty test 7/7, none ignored; settings words daemon reasons |
| R.1 | Daemon concurrency / Ma review | ✅ | 14 findings (1 high: island timer spawn off-runtime → fixed in M5.13 branch); fixes F-* below; 3/10/13/14 later |
| F.1 | Hub lifecycle races, accept busy-loop, lag recovery, atomic update, bounded replies | ✅ | merged; each with a regression test that failed first |
| F.2 | Notify sanitiser linear + outside lock, body cap | ✅ | merged; 1 MiB hostile body 184 s → 0.1 s (debug); 2 more quadratic paths fixed |
| F.3 | Watcher spawn leak + debounce max-wait; services emit unavailable on stream end | ✅ | merged; media no longer stops when Commands drop |
| M6.2 | Mod descriptions; no nulls in `mods` doc (CONTRACT row 5 accepted) | ✅ | merged |
| M0.9 | Mock: notifications, launcher query, instance, fixed clock | ✅ | merged; `kurashi act mock.notify '{"summary":…}'` adds one |
| M3.3 | Golden screenshots (`just golden`) | ✅ | merged; 5 states incl. session menu, 0 px drift across runs; refs are per machine (fonts) |
| M4.7 | Wire tray + Bluetooth; shutdown timeout; PAM lockout doctor check | ✅ | merged; no frontend for tray/BT yet |
| M6.3 | Mod settings as config keys + pages (K22) | ✅ | merged + wired (a3a0443); profiles treat all mod keys as one `mods` section (per-mod sections = later) |
| F.4 | `available` on svc.session/svc.media; power no-UPower vs no-battery | ✅ | merged; placeholders unavailable; explicit logind session → M4.9 |
| R.2 | UX/visual review | ✅ | 25 findings → `docs/reviews/2026-10-09-ux-review.md` |
| U.1 | Components: AA contrast, focus/keys, hit targets, motion tokens, provenance chip | ✅ | merged ed847b0; island hit target 26 px still open |
| U.2 | Surfaces: bar.enabled/edge honoured, Stage scaffolding removed, launcher errors | ✅ | merged 0470378; golden refs re-recorded |
| B.1 | Quiet re-measure: archived probes + frontend + bench gate (machine A) | ✅ | BAKEOFF "Quiet re-measure", BENCH 13:25 row; K3 unchanged |
| B.2 | Quiet baseline machine B | ✅ | e72690f; iGPU gate 0 violations (123.5–126.9 MiB, +4.5–5.6/output); dGPU idle CPU fails only on NVIDIA runtime-PM resume; probes recorded, K3 unchanged |
## Wave 8 (session 4, machine B; Haiku agents; cards in `docs/tasks/README.md`)
| Step | Description | Status | Branch / notes |
|---|---|---|---|
| M4.8 | Tray menu as a Stage panel (K23): `tray.menu.open`, `runtime.ui.tray` (daemon + mock) | ✅ | lead; frontend in card B-tray-bluetooth |
| M6.4 | Per-mod profile sections (`mods.<id>`, K22 addendum) | ✅ | C-mod-sections 27374af; 5 new tests (3 fail on the old `section()`), gate 315/0 |
| M4.9 | svc.session resolves the graphical session explicitly (XDG_SESSION_ID → user Display → Sessions → auto) | ✅ | L-logind cbdb73f; 6 new tests on a fake logind; `user/self` alias checked read-only on machine B; brightness.rs still uses session/auto (follow-up) |
| M3.4 | Hybrid-aware EGL vendor pin in `launch.sh` (dmabuf main device → driver → vendor) | ✅ | K-hybrid-egl a04df65; 17-case `test-launch.sh` in `just check`; real niri session here → Mesa (renderD129); HM + `nix run` pass `KURASHI_WAYLAND_INFO`; bench after wave |
| M4.10 | One refcounted `ServiceProvider` (RefcountedService folded in) + restart with backoff after a bus loss | ✅ | C-services 76b7d1f; `tests/services_reconnect.rs` (bus killed → unavailable → back within 5 s); follow-up: tray start failure retries every 30 s while a bar is visible |
| M5.18 | UI: tray widget, tray menu in the Stage (K23), Bluetooth in the island panel, island hit area = bar thickness; mock serves svc.tray/svc.bluetooth | ✅ | B-tray-bluetooth dbe7ae3; `frontend/test-tray-bt.sh` (clicks via virtual pointer), golden unchanged (0 px), test-real isolates the system bus; bench after wave |
| M5.19 | Settings polish (review R.2 #3,4,5,7,8,9,11,13,17,18,23): keyboard + focus ring, a11y names, AA colours, 32 px hit areas, translated errors, page headers, undo/redo state | ✅ | S-settings-polish 5da9b4a; `settings/test.sh` incl. keyboard step (8 shots read); undo/redo reply-derived until CONTRACT row 21 |
| M7.5 | Live-start fix: QML clients use the protocol's default socket (`nix run .#` / HM showed "disconnected") | ✅ | found in the user's first live run; tests now run without KURASHI_SOCKET and assert the frontend's hello |
| D.1 | `docs/BACKLOG.md` (bugs/improvements/ideas, user feedback from the first live run) + CLAUDE.md rule | ✅ | island model, mods in Settings, wallpaper notes; handover "session 4 close" |
## Wave 9 (session 5, machine B; Haiku 5.5 agents at max effort; cards in `docs/tasks/README.md`)
| Step | Description | Status | Branch / notes |
|---|---|---|---|
| D.2 | Decisions with the user: K24 island model, K25 mods in Settings, K26 wallpaper (Wallhaven later); K27 contract rows 20–22 (fixtures, mock, PROTOCOL) | ✅ | lead, feat/m7-wave9-contracts |
| B.3 | Per-output PSS (B7): attribution on machine B iGPU, lazy island faces, gate = mean of two hotplugged outputs, sandbox on the boot_vga GPU (B10) | 🔄 | lead, feat/m7-per-output-pss |
| W9.1 | Bar volume slider honest when audio is unavailable/muted (B2) | ✅ functional · UX ⏳ (`docs/ux/quick-settings.md`) | W9-bar-volume c80c399; `frontend/test-volume.sh` (pixel checks: no level without audio, dim when muted); golden refs machine B re-recorded (697 px: ⊘ instead of a 0 % knob) — machine A refs need `just golden --update` there |
| W9.2 | Brightness writes on the resolved logind session (B3) | ✅ | W9-brightness-session fa478bc; resolver shared with svc.session, cached per bus GUID, one re-resolve when the session is gone; 3 fake-logind tests |
| W9.3 | `item_is_menu` (row 20); B4 not reproducible | ✅ | W9-tray 5ad6f95; a foreign watcher is *hosted* since 361276b (no retry exists) — the agent's first "waiting" version would have dropped that, rejected by the lead |
| W9.4 | `config.history` + `config.profiles` (rows 21–22), profile error keys (B5), Settings follows (B6, B8) | ✅ | W9-config-profiles 89702da; `tests/config_doc.rs`; settings/test.sh shows Undo on open and a profile file listed ~170 ms after it appears |
| W9.5 | Shared virtual keyboard/pointer in `tools/bench/` (I6) | ✅ | W9-test-helpers 75ff0dc + lead 4248bc4 (settings/test.sh switched, `settings/keys.py` removed); helpers refuse any socket outside `/tmp/kurashi-sb-*` |
| W9.6 | niri keybinding snippet + HM option (I8) | ✅ | W9-niri-binds a82f957; `docs/niri-binds.kdl`, `programs.kurashi.niri.binds.{enable,keys}`, eval test runs `niri validate`; lead: session menu on Mod+Shift+E (niri's Mod+Escape inhibit escape hatch kept) |
| D.3 | Wave 10 contracts: K24 `runtime.ui.face` + `quick.toggle` (daemon + mock + fixture), K25/K26/I9 in MODS.md/PROTOCOL + `snap_mods.json`, schema `choices_from`; wave 10 cards | ✅ | lead 27f60d2 |
## Wave 10 (session 5, machine B; Haiku 5.5 agents at max effort)
| Step | Description | Status | Branch / notes |
|---|---|---|---|
| W10.1 | Island click → expanded view of the shown face (clock calendar, media transport, notifications, volume, brightness; generic for others); quick settings card holds Bluetooth (K24, B1, I2) | ✅ functional · UX ⏳ (`docs/ux/island.md`, `quick-settings.md`) | W10-stage-panels 2d82bc0; `frontend/test-stage.sh`; golden machine B re-recorded; multi-output re-pick for quick → BACKLOG B14 |
| W10.2 | Quick-settings button in the bar (◐, bar-thick target) | ✅ functional · UX ⏳ (`docs/ux/quick-settings.md`) | W10-bar-quick; lead: Theme roles instead of hex fallbacks; `frontend/test-quick.sh` |
| W10.3 | Mods as config lists `mods.loaded`/`mods.enabled` (persisted, B11), page per loaded mod, `running` hook, `choices_from` resolved (palettes, island faces), `color.status.on/off` (K25, I9) | ✅ | W10-mods-daemon; `tests/mods_state.rs`; CONTRACT 23 deferred to K26, 24 decided (one transaction) |
| W10.4 | Settings: mod pages in the sidebar with state marks, Load/Unload, Select + PickList | ✅ functional · UX ⏳ (`docs/ux/settings.md`, W13-settings-ux) | W10-settings 187de92; pick list horizontal (fixed in the UX pass) |

Status key (from session 5, CLAUDE.md "UX bar"): user-facing steps are *functional* when they work and pass their
tests, *UX ✅* only after their brief in `docs/ux/` is met (lead review against screenshots).

## Wave 11–13 (session 5; native mods, K28, UX passes)
| Step | Description | Status | Branch / notes |
|---|---|---|---|
| W11.1 | Native mod mechanism: `kurashi-mod-api` (NativeMod, ModCtx), ledger, runtime unregister of docs/actions, `running`, hello test mod (K26) | ✅ | W11-native-mods 9bda795; CONTRACT 27–29 |
| W12.1 | Quick settings daemon: `audio.sink.default`, `network.wifi`, mock parity | ✅ | W12-quick-daemon 9a19dec |
| W12.2 | Quick settings sections: Wi-Fi, power, audio output, Bluetooth; ToggleSwitch focus ring; Slider clamp (B12) | ✅ functional · UX ⏳ (W13-quick-ux) | W12-quick-ui |
| B.3 | Per-output PSS (B7): lazy island faces, gate = mean of two hotplugs, sandbox boot_vga (B10) | 🔄 merged 673dca1; the +29.8 MiB cycle spike of one gate run still needs a quiet-machine repro | lead |
| D.4 | UX bar: `docs/ux/` composition map + 6 researched briefs (quick settings, island, settings, wallpaper, sysmon, weather); CLAUDE.md rule; card rule 10 | ✅ | lead 5b1dd41, e120863 |
| K28 | Contribution slots, mod Island faces, mod choice sources, `mod.panel.open` — contract + daemon | ✅ | lead 1068f6b; W12-mod-hooks 84bd67a (rows 30–33) |
| W11.2 | Frontend mod loading: ModLoader, SlotHost, mod panels/widgets/faces; Store.unwatch deferred (binding-loop root cause) | ✅ | W11-mod-qml 86e35e5; mods import `qs.core` (B16/B17 fix 63893ad) |
| W12.3–5 | Mods: weather, sysmon, wallpaper (brief-governed) | ✅ functional · UX ⏳ (W14-*-ux) | merged; live check through the real shell found B16–B19 |
| W13.1–5 | UX passes: settings, quick daemon pages, island daemon (secondary/overflow/stale, core transient signals); quick UI + island views queued | 🔄 | W13-* |
| F.5 | Nix build green again (config_doc test read the install prefix) | ✅ | 6754af0 |
| W13.2 | Quick settings daemon pages (scan doc, connect/airplane, sources/streams, power profiles, DND until) | ✅ | 3699371 (K29) |
| W13.3 | Island daemon: secondary/overflow/detail/stale_at, core transient signals | ✅ | K30 |
| W13.4 | svc.media position/rate/can/players, seek/select | ✅ | K31 |
| W13.5 | UX passes: settings (849c0ea), quick settings (1e63bfd), island views (4f49b0b) | ✅ functional · UX review 1 done, polish open (I44–I47, I50–I52) | lead reviews in docs/ux/*.md |
| W14 | Mod runtime (jobs, list settings, capabilities, unlinked refusal), live all-mods test, mod UX passes | 🔄 | W14-* (sysmon/weather UX after mod-runtime) |


## Wave 14 close + session 6
| Step | Description | Status | Branch / notes |
|---|---|---|---|
| W14.1 | Wallpaper to its brief (picker, looks, theme diff, pairs, breadcrumb) | ✅ functional · UX ⏳ (lead review) | W14-wallpaper-ux 9c6f1b2; open in I32 |
| W14.2 | Stage: a mod panel asks for its card width (`cardWidth`, 360..720 px) | ✅ | lead c511ac5 (row 66, I53) |
| W14.3 | K34: palette `wallpaper` follows `mod.wallpaper.theme.image`; daemon holds the mod's document while chosen; waiting note | ✅ | lead feat/k34-wallpaper-theme; kurashid test with a generated picture |
| W14.4 | Weather to its brief (400 px panel, places move/remove, loading, copy pass, fixture-backed live shots) | ✅ functional · UX ⏳ (lead review; I57) | W14-weather-ux 6e913ae |
| W14.5 | Sysmon to its brief (440 px panel, Tdie/Tctl honesty, paths searched, host values, battery, menu, btop, pause) | ✅ functional · UX ⏳ (peek I55, states I56, I48) | W14-sysmon-ux eeeb85e; PopupWindow peek removed at merge (K19, row 75) |
| W15.1 | K36 profile overlay + Profiles page review/export/import (B13, I41) | ✅ functional · UX ⏳ (I64) | W15-profiles dddef95; settings/test.sh P1–P4 |
| W15.2 | Honest "Running now": `JobCtx::set_active`, Settings shows reasons (I48) | ✅ | W15-job-active 4cfff62 |
| W15.3 | Quick/island polish: tonal tiles, tile contract, OSD device, power/bluetooth views, quick output re-pick (I51, I52, I45, I44, B14) | ✅ functional · UX ⏳ (two-output check: row 80) | W15-quick-island-polish 269c5da + lead fixes 38ac21f |
| W15.4 | Sysmon fixes: shell processes protected (B24), names (I61), GPU tile (I62), fixture states (I56) | ✅ functional · UX ⏳ (peek W16, I65) | W15-sysmon-fixes 188fc60 |
| K35 | Stage-hosted peeks: daemon, contract, mock (frontend = W16) | 🔄 daemon ✅ | lead cf27536 |
| W16.1 | K37 no-network sandboxes (I58), mock focus model + B14 two-output step (row 80), no nulls in mod.wallpaper (B25) | ✅ | W16-test-infra 31e7c74 |
| W16.2 | K35 frontend: Stage-hosted peeks (tray tooltips, island line, sysmon, weather), two outputs, measured | ✅ functional · UX ⏳ (I67) | W16-peek-frontend e16d52e + lead edge gap, mods-live clause |

## v0.2 — Web dock (session 7; K38, K39, `docs/ux/webdock.md`)
| Step | Description | Status | Branch / notes |
|---|---|---|---|
| W17.0 | Phase 0: QtWebEngine in a Quickshell PanelWindow, typed input (headless sway) | ✅ with the Quickshell patch (K39); niri run open | `archive/spikes/webengine-phase0/` |
| W17.1 | UX brief, K38/K39, contract rows 88–94, backlog I68–I76, B26–B27; scoped hello, `host:` provide, `qs-webengine`, netjoin (B26) | ✅ (hover/size details: user review open) | e077403 |
| W17.2 | Records setting type + Settings editor + Nix pins (rows 89, 96, 97) | ✅ functional · UX ⏳ (keyboard reorder/delete unverified, add by form untested: wl_keys has no `:`) | W17-records 1fcc775 |
| W17.3 | Host processes + scoped connections + mod `webdock` (document, actions, lifecycle, unload; rows 90–93) | ✅ functional (pins wait for W17.2; scope table → Daemon: I77) | W17-webdock-daemon 2ce2e14 (hover state machine: with W17.4) |
| W17.4 | Shell side: `surface:` provide, indicator, strip, card, view pins (row 88); hover machine, pin edits, new tabs in the dock (K40, rows 109–111) | ✅ functional (daemon + shell; cost per K41) · UX ⏳ (niri I80, I90, I91) · host: new tabs in the dock, home/forward, retarget, I78 polish (W20-webdock-host; I97–I100 open) | W20-webdock-daemon, W20-webdock-shell |
| W17.5 | Web host on patched Quickshell: profiles, mobile/desktop, privacy + net-log test, freeze, sheets, chips (B27) | ✅ functional · UX ⏳ (I78–I80; niri) | W17-webdock-host efd2e7d + lead fix B28 |
| W17.E2E | Pins in the config → `webdock.open` → the daemon starts the host → scoped hello → page loaded; view toggle via the settings writer (undo); forged scope refused; disable stops the host | ✅ | lead `mods/webdock/test/test-real.sh`, `just webdock` |
| W17.6 | Nix: `kurashi-webdock` package apart from the base closure, HM/NixOS options, `Mod+B` | ✅ (closure check, module eval; per-key enforce I95) | W20-webdock-nix |

## Wave 18 (session 7; contract rows 98–99)
| Step | Description | Status | Branch / notes |
|---|---|---|---|
| W18.0 | Contract: peek `edge`/`y`/`h` (row 98), diff `same_value` (row 99) | ✅ | lead |
| W18.1 | Quick tiles: 160×56 contributions, wallpaper/hello as QuickTile, mock parity (I52, I50) | ✅ functional · UX ⏳ (I86: forced_by from the daemon, tile tokens) | W18-quick-tiles 069e29e |
| W18.2 | Peeks on every bar edge, fade-out, state shots, `just peek`, mods-live kinds from manifests (I67) | ✅ functional · UX ⏳ (side-bar widget layout I85; keyboard path) | W18-peeks 1559737 + lead pill-peek crop |
| W18.3 | Sysmon: main GPU, localized/version-like names, undrawn states (I65) | ✅ functional · UX ⏳ (screen reader, cgroup limits: I84) | W18-sysmon e0879c5 |
| W18.4 | Profiles page follow-ups, records editor keyboard paths, wl_keys URL characters (I64, I81) | ✅ | W18-settings 584265b + lead row 101, two editor fixes |

## Wave 19 (session 7; rows 71–72, clock schema keys)
| Step | Description | Status | Branch / notes |
|---|---|---|---|
| W19.0 | Contract: `clock.expanded.daymark` slot (row 71), `runtime.slots` `reason` + `ModCtx::slot` (row 72), schema `clock.week_start`/`week_numbers` | ✅ | lead |
| W19.1 | Bar widgets on side bars (I85) | ✅ functional · UX ⏳ (hide priority, transient-face shots) | W19-side-bars 3292585 |
| W19.2 | Weather polish without colour: hourly rain, seven days, places preview forecast, no-place reason (I82, I57) | ✅ functional · UX ⏳ (preview unverified in the sandbox, hourly overflow: I88; colours) | W19-weather 59f84b5 |
| W19.3 | Wallpaper picker polish without colour: width, output chips, overflow menu, keys (I83, I32) | ✅ functional · UX ⏳ (colours, Stage Close: design pass, row 106) | W19-wallpaper 86c0518 |
| W19.4 | Calendar: day marks, week start/numbers, slot setup states (I46, rows 71–72) | ✅ functional · UX ⏳ (I89) | W19-calendar b6bda1d; lead deadlock fix B29 |


## Session 9 — the sekai look, morphing island, phone, desk (K42–K44; `INSPIRATION.md`)
| Step | Description | Status | Branch / notes |
|---|---|---|---|
| S9.0 | Chrome axis (flat/keycap), decor recipes (`theme.decor`), palettes sekai/sekai-night, spring/icon/tonal tokens, `Block`/`Icon`, fonts in HM + dev shell, `frontend/test-look.sh` (K42) | ✅ functional · UX ✅ (lead screenshots) | lead, merged 034e70a |
| S9.1 | Primitives (Button, IconButton, Chip, Slider, ToggleSwitch, NotificationCard) and surfaces (bar groups + numbered workspaces, launcher, notification centre, session keys, lock keycap clock) in keycap chrome | ✅ functional · UX ✅ first pass | feat/m8-sekai-surfaces |
| S9.2 | Desktop widgets: keycap clock, month, now playing, weather (K43, `docs/ux/desktop.md`) | ✅ functional · UX first pass (I101) | feat/m8-sekai-surfaces |
| S9.3 | Launcher calculator, `:` emoji, `;` clipboard (cliphist); bar window list + `window.focus` (K44) | ✅ functional · UX first pass (I102, I105) | feat/m8-sekai-surfaces |
| S9.4 | Settings app: tonal selection, keycap controls, sidebar pills with icons (I51 leftovers, I104) | ✅ functional · UX first pass | feat/m8-sekai-surfaces |
| W21.1 | Island morph: one shape pill → card (Capsule springs), liquid neck (flat chrome), keycap pill, flip clock, media level bars, OSD level meter, KeyButton views, ownChrome for the phone (card `W21-island-morph`) | ✅ functional · UX ✅ first pass (morph frames `frontend/shots/island/morph-*`; I111–I115, B32) | merged 6b749d6 |
| W21.2 | Phone: `PhoneFrame`, web dock phone card + keycap strip, quick settings as a SekaiPop phone (card `W21-phone`); row 118 `svc.clock` in host scopes (lead) | ✅ functional · UX ✅ first pass (I106–I110) | merged 22967bd |
| S9.5 | Glass decor (Vitreus/pleamar), `Theme.panel` | ✅ functional · UX first pass (I114) | main |
