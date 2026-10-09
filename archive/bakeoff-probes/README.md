# Bake-off probes (archived, NOT used by the shell)

Throwaway prototypes from the M0 frontend bake-off (2026-10-09). **Nothing in the shell builds,
imports or ships these.** The real frontend is `frontend/` (Quickshell, decision K3); the
workspace (`crates/*`), the nix package and `just` recipes never look in here.

Kept on purpose as the **re-run baseline** for K3's re-evaluation clause: if Quickshell ever
restricts a feature, the feel goal or quick iteration, re-bench these against the current numbers
before choosing again.

| probe | stack | result (score / why it lost) |
|---|---|---|
| `quickshell/` | Qt 6 / QML | **winner, 8.7** — became `frontend/` |
| `gtk4/` | GTK 4 + Relm4 | 6.2 — no session-lock API, popup = 2nd layer surface (+77 MiB) |
| `slint/` | Slint + SCTK | 6.1 — no IME, no shader API; 25 MiB only with the CPU renderer |
| `iced/` | iced + layershell | 5.2 — no blur, 118 wakeups/s idle |
| `gpui/` | Zed's gpui | 2.5 — commits frames forever (61/s idle), no session lock |

Full matrix and method: `docs/BAKEOFF.md`; task card and candidates: `tools/bakeoff/`.
Each probe has its own `flake.nix`, `README.md` (build/run), `REPORT.md` and `bench*.json`.
The paths inside `bench*.json` are historical (recorded before the move from `probes/`).
