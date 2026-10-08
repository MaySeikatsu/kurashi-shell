# Handover

Updated at the **end of every session** (K14). Newest entry on top; keep the last 5 entries.

## Pickup prompt (copy into a fresh session in `~/Projects/kurashi-shell`)
> Read `CLAUDE.md` and `docs/HANDOVER.md`, then continue with the "Next steps" of the latest
> handover entry. Follow the feature-branch workflow, update `docs/PROGRESS.md`, and write a new
> handover entry before ending the session.

---

## 2026-10-09 — session 1 (planning + bootstrap)
**State**
- Plan approved (source: `~/.claude/plans/i-think-this-shell-glimmering-otter.md`; content now
  lives in `docs/`). Repo initialised; docs skeleton committed on `main` (M0.1 ✅).

**Next steps**
1. `feat/m0-foundations`: flake + justfile + Cargo workspace (M0.2), `kurashid` skeleton (M0.3),
   `kurashi-mock` probe subset (M0.4), bench harness (M0.5).
2. Bake-off task card + 5 parallel probes (M0.6), measure + decide K3 (M0.7).

**Open decisions / risks**
- K3 renderer pending bake-off. GPUI/Slint layer-shell maturity may fail hard gates.
- NVIDIA GTX 1060 machine: wgpu/Vulkan and GL paths behave differently — record driver in BENCH.

**Context links**
- Predecessors: `~/Documents/projects/quickshell/shellseikatsu` (Quickshell, feature reference),
  `~/Projects/quickshell/WormShell` (design study, D1–D93).
- Reference shells: `~/Documents/projects/github-forks/quickshell/` (noctalia, DMS, caelestia, ii).
