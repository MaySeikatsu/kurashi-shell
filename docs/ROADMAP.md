# Roadmap

## v0.1 — core desktop (daily driver)
| M | Milestone | Owner | Exit criteria |
|---|---|---|---|
| M0 | Foundations + frontend bake-off | Opus lead + 5 Sonnet probes | flake/devShell/CI-ish `just check` green; mock + bench harness; `BAKEOFF.md` filled; K3 decided |
| M1 | State core (protocol v1, schema derive, resolution/provenance, sparse TOML, migrations, profiles, transactions/undo, actions, CLI, mock v1) | Opus | property tests green; fixtures frozen; `kurashi set/get/why/undo/profile` work |
| M1.5 | Vertical slice: daemon + one bar + clock + one setting with provenance chip + reconnect veil | Opus | change via CLI reflects in bar with correct provenance; daemon restart → resync |
| M2 | Theming engine (palettes incl. wa-iro, material-colors, pipeline stages, WCAG, fonts, exporter) | Sonnet A (+Opus core) | token map golden tests; AA on all bundled palettes |
| M3 | Surfaces + design system (surface manager, stage, corner rules, focus model, motion, reveal, component kit) | Opus + Sonnet D | ≤ 4 surfaces/output idle; golden screenshots |
| M4 | Services (niri adapter, PipeWire, NM, BlueZ, UPower, MPRIS, notifications, SNI, logind, brightness) | Sonnet B/C + Opus (niri) | refcount tests; no polling when unsubscribed |
| M5 | Core UX: widgets + input bindings, Island + core faces, notifications + center, launcher, OSD, session menu, lock (PAM), Settings app (schema pages, search, Profiles, Mods) | mixed | honesty test green over all keys |
| M6 | Mod system + first native mods (media+lyrics, wallpaper+Wallhaven, sysmon, weather, clipboard, easter-eggs) | mixed | live enable/disable; settings pages appear |
| M7 | Hardening → v0.1 (budgets green, `kurashi doctor`, NixOS/HM modules, docs) | Opus | BENCH budgets met; user switches from shellseikatsu |

## v0.2 — productivity & media mods
dock/sidebar (multi-instance, pin/hover/compact; first: the web dock, K38 and `docs/ux/webdock.md`), media + lyrics (bar/wallpaper), visualizer +
audio ripple, wallpaper (+Wallhaven, video), clipboard, sysmon, weather, calendar, notes, tasks
(internal/obsidian/todoist/ticktick), emoji, pass, PWA, radio, news, links; Luau host API spec.

## v0.3 — identity & power-user
Console/command palette with providers; vim navigation + hint mode; LLM chat (multi-provider,
libsecret); translator; anki (reviewer + unlock challenge); identity packs (game/OS decor, themed
lockscreens incl. retro-TV CRT zoom, liquid glass via niri `xray false`); desktop FX shaders +
gamma filters; ringlight; pet; OpenRGB; ScreenFrame + corner merge; widget families;
colorblind modes; Hyprland / MangoWM / Sway adapters; portable mod tier (declarative UI + Luau).

## Later (idea pool from shellseikatsu ADDITIONAL_IDEAS + WormShell IDEAS)
workspace window previews, niri scroll-position widget, TTS/STT + live subtitles, palette sync
from apps/video, wallust backend, video-wallpaper sync/upscaler, media "jam" animations,
pet climbing the frame, podcast radio, per-workspace hover previews.
