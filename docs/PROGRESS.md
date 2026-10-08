# Progress

Status: ⬜ todo · 🟡 in progress · ✅ done · 🔵 blocked · 🔴 reverted.
Step ids `M{n}.{step}`. Update in the same branch as the work.

## M0 — Foundations + frontend bake-off
| Step | Description | Status | Branch / notes |
|---|---|---|---|
| M0.1 | Repo, LICENSE, CLAUDE.md, docs skeleton | ✅ | `main` initial commit |
| M0.2 | Nix flake (devShell, packages, NixOS + HM module stubs), justfile, Cargo workspace | ⬜ | `feat/m0-foundations` |
| M0.3 | `kurashid` skeleton (tokio, tracing, socket, NDJSON hello/welcome) | ⬜ | |
| M0.4 | `kurashi-mock` serving the probe subset (PROTOCOL §8) | ⬜ | |
| M0.5 | Bench harness (`tools/bench`: headless sway, PSS, idle frames, CPU, wakeups/syscalls) | ⬜ | |
| M0.6 | Bake-off task card + 5 probes (Quickshell, iced, Slint, GPUI, GTK4/Relm4) | ⬜ | parallel worktrees |
| M0.7 | Measure, fill `BAKEOFF.md` + `BENCH.md`, decide K3 | ⬜ | |
