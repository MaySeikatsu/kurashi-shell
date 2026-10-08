# Vision — 暮らしの道具 (tools for daily living)

Kurashi (暮らし, "way of living") is a Wayland desktop shell that should feel like a well-made
everyday object: quiet when not needed, precise when used, honest about what it does, and yours
to reshape. It is the successor in spirit to *shellseikatsu* (Quickshell) and *WormShell*
(design study), but its own project.

## Principles
| | Principle | In practice |
|---|---|---|
| 間 | **Ma** — meaningful empty space | Minimal default (`kanso` profile). Idle = 0 frames, 0 polling. Features are opt-in mods. |
| 簡素 | **Kanso** — simplicity | One concept per concern, one owner per value, one registry per id kind, one input-binding model for every component. |
| 正直 | **Shōjiki** — honesty | The UI never shows a value that isn't in effect. Every value shows its source; inert controls say why. |
| 改善 | **Kaizen** — continuous improvement | Performance budgets are measured every milestone (`BENCH.md`). Regressions block merges. |
| おもてなし | **Omotenashi** — anticipatory care | Sane defaults, previews before applying, undo for every change, profiles to return to. |
| 旬 | **Shun** — seasonality | Subtle seasonal touches (七十二候 micro-seasons, sakura, tsukimi) in the `easter-eggs` mod. |

## Goals
1. A daily-driver shell for niri with **lower resource use** than shellseikatsu (272 MB RSS,
   3.5 % CPU) — target ≤ 50 % PSS, < 0.5 % idle CPU.
2. **Minimal by default, broadly moddable**: every non-core feature is a first-party mod that
   integrates natively into Settings once enabled; third-party mods use the same system.
3. **Config and menus never disagree** with the real state (provenance model, one schema).
4. **Savable profiles**: snapshot the whole shell, load it back fully or section by section.
5. A **thoroughly designed theming system**: palette pipeline → semantic roles → component
   tokens; decor packs as slots + recipes; accessibility modes; app theme export.
6. **Dynamic components** (the Island 島) that show what's relevant and are fully user-controllable.
7. **Universal input bindings**: left/right/middle/hover/scroll on every component, sane
   defaults, user-overridable.
8. **Nix-first**: flake, NixOS + Home-Manager modules, reproducible dev shell.

## Non-goals (v0.1)
- X11; non-Linux platforms.
- Compositors other than niri (adapters for Hyprland/MangoWM/Sway come later).
- A plugin marketplace; third-party mod sandboxing beyond Luau VM limits (v0.3+).

## Easter eggs (mod `easter-eggs`, subtle, default on, one toggle off)
- Clock peek shows the current 七十二候 micro-season (e.g. 「桜始開」 — cherry blossoms begin to bloom).
- Hanami week: occasional sakura petals drift across the Island.
- Tsukimi (mid-autumn moon): the clock face gains a small moon.
- Konami code in the launcher: 招き猫 waves once.
- Logout/shutdown confirmation says 「お疲れ様でした」.
- The default profile is named `kanso`; the default palette `wa-iro` (和色) is built from
  traditional colours: 墨 sumi, 和紙 washi, 藍 ai, 紅 beni, 抹茶 matcha, 山吹 yamabuki.
