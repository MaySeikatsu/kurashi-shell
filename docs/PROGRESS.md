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
| M1.3 | `kurashi-schema` + derive (registry, validation, generators, v1 tree) | 🟡 | card M1-schema (opus) |
| M1.4 | `kurashi-config` (layers, provenance, sparse TOML, migrations, profiles, undo) | 🟡 | card M1-config (opus) |
| M1.5 | Wire config/schema into kurashid (`config`, `schema.settings`, cfg.*), CLI get/set/why/undo/profile | ⬜ | lead, after M1.3/M1.4 |
| M1.6 | Frontend skeleton (Store, Theme, I18n, Bar, Stage, Island, ProvenanceChip, veil) | ✅ | merged; idle 0 commits, popup 2.1 ms; PSS popup/2-out 221 MiB ✘ K16 → M3.1 |
| M2.1 | `kurashi-theme` pipeline → token map | ✅ | merged; 14 tests, AA on all palettes × modes |
| M3.1 | Stage sized to content, popup only on focused output (K16) | 🟡 | card M3-stage (sonnet, wave 2) |
| M5.1 | `kurashi-island` arbiter (K9) | ✅ | merged; wired in kurashid (`runtime.island.main`, island.next/prev/pin, one deadline timer) |
| M1.7 | `i18n` document (daemon + mock), nix package ships data | ✅ | contract row 1 |
| M4.3 | `svc.workspaces` provider from compositor (refcounted, `*` alias, workspace.focus) | ✅ | kurashid |
| M4.1 | `kurashi-compositor` trait + niri adapter + fake | ✅ | merged; niri 26.04 fixtures (read-only) |
| M4.2 | `kurashi-services` (MPRIS, UPower, logind, NM, brightness) | 🟡 | card M4-services (sonnet, wave 2) |

