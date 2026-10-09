# Mods

Everything beyond the core is a **mod** — first-party ones included. Core = daemon, surface
manager, theming, bars + core widgets, Island + core faces, notifications, launcher, OSD, lock,
session menu, Settings.

## Manifest (`mods/<id>/mod.toml`)
```toml
id = "media"
name = "Media"            # i18n key fallback
description = "mods.media.description"   # optional; i18n key or plain text, shown under the name
version = "0.1.0"
tier = "native"           # native (first-party, renderer components) | portable (v0.3)
kurashi = ">=0.1"
provides = ["widget:media", "island-face:media", "panel:media", "service:mpris", "action:media.*"]
capabilities = ["dbus:session", "network"]   # declared, shown in Settings
cost = "low"                                   # resource hint shown in the Mods page

[[setting]]
key = "show_art"
type = "bool"
default = true
label = "mods.media.show_art"   # i18n key

[[setting]]
key = "seek_step"
type = "int"
default = 5
range = [1, 60]
unit = "s"
```
Settings values live in the user config under `[mod.<id>]` and travel with provenance like core
keys; profiles snapshot them in the `mod.<id>` section.

## Lifecycle
- **Enable/disable is live.** Enabling: daemon validates manifest → registers services
  (refcounted, start on first subscriber), actions, island faces, settings page; frontend loads
  the mod's components on demand. Disabling reverses it; config is kept.
- Bundled mods default **off** except `easter-eggs` (subtle) — Ma.
- The Settings **Mods page**: catalog, toggle, description, capabilities, cost, "Configure" →
  generated page using the same control kit as core pages.

## Tiers
- **native** (v0.2, first-party): renderer components + daemon logic in Rust. Used for anything
  animated/shader-heavy (visualizer, desktop FX, decor packs).
- **portable** (v0.3): declarative UI vocabulary (row/column/stack/text/icon/button/toggle/
  slider/list/image + bindings + actions) + **Luau** logic (one sandboxed VM per mod, per-call
  time budget, capability-gated host API: timers, http, scoped fs, D-Bus, secrets via libsecret).
  WASM only if demand appears.

## Contributions a mod can make
widgets (bar placeable) · island faces · panels (stage) · settings · actions · launcher
providers · services · decor packs (slots + recipe) · lock scenes · palettes · app-theme
templates · i18n strings.
