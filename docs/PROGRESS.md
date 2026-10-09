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
| M3.1 | Stage sized to content, popup only on focused output (K16) | ✅ | popup 112 MiB (was 221); +8.9/output → K19 |
| M1.10 | Frontend core: generic on-demand docs + query API, real daemon (i18n, config, lock, notifications) | 🟡 | card M1.5-frontend-core (wave 4) |
| M6.1 | `kurashi-mods` manifest, discovery, lifecycle registry | ✅ | merged; not wired yet |
| M4.4 | `kurashi-audio` (svc.audio, PipeWire/Pulse) | 🟡 | card M4-audio (wave 3) |
| M7.1 | HM/NixOS modules: user services, managed layer, eval test | ✅ | merged; `just nix-eval-test` (impure, CONTRACT #3) |
| M5.2 | `kurashi-notify` notification server + history | ✅ | merged; 14 tests on private bus; not wired yet |
| M5.3 | `kurashi-launcher` index, fuzzy+frecency, launch | ✅ | merged; 35 tests, p99 0.82 ms/500 apps (release); not wired yet |
| M1.8 | CLI get/set/why/reset/undo/redo/profile | ✅ | merged; exit codes 0/1/2/3 |
| M1.9 | **M1 exit: protocol v1 frozen** | ✅ | PROTOCOL.md status, K17 |
| M5.4 | Settings app (schema-generated pages, provenance, profiles) | ✅ | merged; `settings/test.sh` + 4 shots; schema i18n en+ja |
| M5.5 | `kurashi-auth` PAM + lock state machine | ✅ | merged; PAM feature needs native inputs (CONTRACT #4a); not wired yet |
| M7.3 | `kurashi doctor` | ✅ | merged + registered with startup facts (bus probes n/a for now) |
| M7.2 | Budget gate: measure.py --daemon real + budget.py | 🟡 | card M7-bench (wave 4) |
| M5.1 | `kurashi-island` arbiter (K9) | ✅ | merged; wired in kurashid (`runtime.island.main`, island.next/prev/pin, one deadline timer) |
| M1.7 | `i18n` document (daemon + mock), nix package ships data | ✅ | contract row 1 |
| M4.3 | `svc.workspaces` provider from compositor (refcounted, `*` alias, workspace.focus) | ✅ | kurashid |
| M4.1 | `kurashi-compositor` trait + niri adapter + fake | ✅ | merged; niri 26.04 fixtures (read-only) |
| M4.2 | `kurashi-services` (MPRIS, UPower, logind, NM, brightness) | ✅ | merged + wired as refcounted providers; media → island signal |

