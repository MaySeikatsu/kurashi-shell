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
