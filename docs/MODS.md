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
Settings are ordinary config keys `mods.<id>.<key>` (K22): they live in the user config under
`[mods.<id>]`, travel with provenance like core keys, get one settings page per enabled mod
("Mods › <name>"), and profiles snapshot them in the `mods.<id>` section. A disabled mod keeps its
values; they are reported inert with `reason: "mods.disabled"`.

## States, persistence and Settings (K25)
A mod is in one of four states (`mods` document, `state`):
| state | meaning | Settings |
|---|---|---|
| `available` | detected on disk, not loaded | only its Mods-page row (Load) |
| `disabled` | **loaded, off**: manifest + settings registered, contributions inactive, costs nothing | sidebar page with an off switch (hollow ring) |
| `enabled` | **on**: contributions live | sidebar page with an on switch (filled dot) |
| `invalid` | manifest broken | Mods-page row with its errors |
Which mods are loaded and on are **ordinary config keys** — `mods.loaded` and `mods.enabled` (lists of
ids, `enabled ⊆ loaded`; default both `["easter-eggs"]`) — so they persist, travel with provenance,
can be set by Nix (`programs.kurashi.settings.mods.enabled`) and forced (`forced:nix` makes the
switch inert with its reason), take part in undo/redo and live in the profile section `mods`. The
actions `mod.load`, `mod.unload`, `mod.enable`, `mod.disable` `{id}` are config writes on these
lists (an action on a forced list answers `config.error.forced`); the daemon reconciles the registry
to the effective lists after every change (startup, apply, undo, profile load, file edit). `unload`
of an enabled mod disables it first; `enable` of an available mod loads it too.
Each entry also carries `running: bool` — one of the mod's services has a subscriber right now
(false for mods without services). Settings shows it as the text line "Running now: …" on the mod's
page and Mods-page row, **not** in the sidebar indicator (user decision, K25).
`schema.settings` has one page per **loaded** mod (also without settings: the page then holds the
on/off switch, description and running line), id `mods.<id>`, label = manifest name, plus
`"mod": "<id>"` so the sidebar can find its state. The sidebar sorts mod pages alphabetically among
the core pages (K25); the indicator uses `color.status.*` tokens and shape (ring/dot) + accessible text.

## Native mods (K26 mechanism)
A native mod is first-party code shipped with kurashi: Rust linked into `kurashid` (crate
`crates/kurashi-mod-<id>`) + QML components in `mods/<id>/qml/`. Nothing of it runs while it is not
`enabled`.
- **Daemon:** the crate implements `kurashi_mods::NativeMod { fn id(); fn enable(&self, ctx:
  &mut ModCtx); }`. `ModCtx` registers what the manifest `provides` (and nothing else — a
  registration the manifest does not declare is refused): documents behind a refcounted
  `ServiceProvider` (start on first subscriber, stop on last, rule 5), actions `<id>.*`, island
  faces, launcher providers, choice sources (`choices_from`, I9), a palette source. `ModCtx`
  remembers every registration; disable drops them all (documents answer `unknown_doc` again,
  their subscribers get a final `snap` with `{available:false}` first). Config is read through the
  same store (`mods.<id>.<key>`, K22).
- **Frontend:** the `mods` document gives each enabled native mod `qml: {"<provide>": "<file url>"}`
  for the components its manifest lists (`widget:x` → `qml/Widget.qml`, `panel:x` → `qml/Panel.qml`,
  `island-face:x` → `qml/Face.qml` with compact + expanded parts, K24). The frontend instantiates
  them with `Loader { source }` only where they are placed or opened (bar widget slot, Stage panel
  `mod:<id>:<panel>`, island face) — never preloaded. Components see `Store`, `Theme`, `I18n`
  like core components and talk to the daemon only through their mod's documents/actions.
- **i18n:** `mods/<id>/i18n/{en,ja}.toml`, merged into the `i18n` document while the mod is loaded.

### First native mod: wallpaper (K26)
Rendering by an external daemon — **awww** (or **swww**), chosen by `mods.wallpaper.backend`
(`choices_from = "wallpaper.backends"`: each installed backend enabled, a missing one disabled with its
reason, I9). The mod's service (document `mod.wallpaper`: per output `{path, fit}`, `library` count,
`backend {id, available, reason?}`) starts the backend daemon if needed, sets images per output
(`<backend> img <path> --outputs <name> --resize <fit> --transition-type …`), and owns
`wallpaper.set {path, output?}`, `wallpaper.next/prev {output?}`. Settings: `folders` (list), `fit`,
`transition`, `rotate` (minutes, 0 = off; the timer exists only while > 0 and the mod is on).
Theme source `wallpaper` (DESIGN-SYSTEM §2) takes the current image's palette — a later card. Picker: a
Stage panel with thumbnails decoded at thumbnail size. Wallhaven: later (BACKLOG D3).

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
