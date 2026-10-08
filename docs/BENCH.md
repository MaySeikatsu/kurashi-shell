# Bench

Measured numbers per milestone. Method: `just bench …` (see `tools/bench/README.md`).
Always record: date, commit, machine, compositor, renderer, outputs, profile.

Machine A: 12 cores, 31 GiB RAM, NVIDIA GTX 1060 6 GB (driver 580.178), NixOS, niri 26.04.

## Budgets (v0.1)
| Metric | Budget |
|---|---|
| Idle frames, all windows, 30 s | ≤ 1 fps total |
| Idle CPU, daemon + frontend, 10 min | < 0.5 % |
| PSS, core profile, per output | ≤ 50 % of shellseikatsu baseline |
| Popup input → first frame | ≤ 1 frame after map |
| Mapped surfaces per output at idle | ≤ 4 |

## Baseline — shellseikatsu (2026-10-08, Quickshell 0.3.1, Qt 6.11.2, niri, 1 output)
| Metric | Value |
|---|---|
| RSS | 272–275 MB |
| PSS | 216 MB |
| Anonymous | 173 MB (QML JS heap 34 MB) |
| Avg CPU (1 h) | 3.5 % |
| Idle frames (after 2026-10-08 fixes, headless) | ~0.8 fps |

## Results
_(filled from M0.7 on)_
