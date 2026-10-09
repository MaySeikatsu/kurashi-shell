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

[[setting]]                    # options from a source (I9, K28): a core one or a mod's `choices:<source>`
key = "backend"
type = "string"
default = "awww"
choices_from = "wallpaper.backends"   # string settings only; exclusive with `choices`

[[setting]]                    # an ordered pick from fixed choices (I26): a list of members, each once
key = "show"
type = "list"
default = ["cpu", "mem"]
choices = ["cpu", "mem", "temp", "load"]   # required for a list; the Settings page shows a pick list
```
Settings are ordinary config keys `mods.<id>.<key>` (K22): they live in the user config under
`[mods.<id>]`, travel with provenance like core keys, get one settings page per enabled mod
("Mods › <name>"), and profiles snapshot them in the `mods.<id>` section. A disabled mod keeps its
values; they are reported inert with `reason: "mods.disabled"`.

**Setting types:** `bool`, `int` (`range`, `unit`), `float` (`range`), `string` (`choices_from` for a
dropdown from a source), `enum` (`choices`, one of them), `color` (`#rrggbb[aa]`), `list` (a string list
of `choices`, in the order picked; a default lists members once each, and a member outside the choices
is refused by the validator).

**Capabilities** (declared, shown in Settings, checked by the validator): `dbus:session`, `dbus:system`,
`network`, `audio`, `notifications`, `fs:scoped` (the mod's own state folders), `fs:read` (system files,
e.g. `/proc` and `/sys` for the figures), `proc:signal` (signals a process of the user), `exec:<binary>`
(runs one program, named by its file name: `exec:awww`), `secrets`. The bare `exec` predates the named
form and stays valid until the manifests move to `exec:<binary>`. Anything else is `capability_unknown`.

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
Each entry also carries `running_reasons: [<i18n key>]` — why the mod runs now: `mods.running.subscribed`
while one of its documents has a subscriber, and the reason of each background job that is started
(I23; e.g. `mods.running.rain_alerts`). `running` is true while the list is not empty. Settings shows the
reasons as the text line "Running now: …" on the mod's page and Mods-page row, **not** in the sidebar
indicator (user decision, K25).
`schema.settings` has one page per **loaded** mod (also without settings: the page then holds the
on/off switch, description and running line), id `mods.<id>`, label = manifest name, plus
`"mod": "<id>"` so the sidebar can find its state. The sidebar sorts mod pages alphabetically among
the core pages (K25); the indicator uses `color.status.*` tokens and shape (ring/dot) + accessible text.

## Native mods (K26 mechanism)
A native mod is first-party code shipped with kurashi: Rust linked into `kurashid` (crate
`crates/kurashi-mod-<id>`) + QML components in `mods/<id>/qml/`. Nothing of it runs while it is not
`enabled`.
- **Daemon:** the crate implements `kurashi_mod_api::NativeMod { fn id(); fn enable(&self, ctx:
  &mut ModCtx); }` (crate `kurashi-mod-api`: `NativeMod`, `ModCtx`, `Settings`, `ModError`). `ModCtx` registers what the manifest `provides` (and nothing else — a
  registration the manifest does not declare is refused): documents behind a refcounted
  `ServiceProvider` (start on first subscriber, stop on last, rule 5), actions `<id>.*`, island
  faces, launcher providers, choice sources (`choices_from`, I9), a palette source. `ModCtx`
  remembers every registration; disable drops them all (documents answer `unknown_doc` again,
  their subscribers get a final `snap` with `{available:false}` first). Config is read through the
  same store (`mods.<id>.<key>`, K22).
- **Background jobs (I23):** `ctx.background(name, reason, wanted_by, run)` declares `job:<name>`. The
  body is `Fn(JobCtx)` (the daemon starts it again when the setting turns it on), `JobCtx::settings()`
  is the mod's settings feed, and `wanted_by` names a bool setting of the same mod. The enable hands the
  job to the daemon with `ctx.take_jobs()` before `finish()`, which refuses a job left behind. The daemon
  runs a job while the mod is enabled and the setting is true, cancels it when either stops, and shows
  `reason` (an i18n key) in `running_reasons` while it runs. A job that returns by itself stops
  running. Weather's rain alerts and sysmon's trouble watch are jobs; a poll the user can see is never a
  bare task.
- **Refused without code (B15):** a native mod whose manifest declares daemon code (`service:`,
  `action:`, `island-face:`, `choices:`, `job:`) is refused with `mods.error.not_built` when this build
  links no `NativeMod` for it: it stays `disabled` with that reason in `errors`, and the config keeps
  its list entry. Frontend-only provides (`widget:`, `panel:`, `slot:`, `palette:`, `decor:`, `i18n`)
  need no code and switch on as before. In the shipped build the bundled `easter-eggs` (on by default,
  it declares `action:easter.*`) and `media` (`service:mpris`, `island-face:media`, `action:media.*`)
  are refused until their code is linked; the default `mods.enabled` list therefore shows
  easter-eggs as "not built" until its manifest or its code changes.
- **Frontend:** the `mods` document gives each enabled native mod `qml: {"<provide>": "<file url>"}`
  for the components its manifest lists (`widget:x` → `qml/Widget.qml`, `panel:x` → `qml/Panel.qml`,
  `island-face:x` → `qml/Face.qml` with compact + expanded parts, K24). The frontend instantiates
  them with `Loader { source }` only where they are placed or opened (bar widget slot, Stage panel
  or expanded view). Components import the shell by module URI —
  `import qs.core` (Store, Theme, I18n, Watch) and `import qs.components` (Button, Chip, …) — never by relative path
  (a mod file loads from `file://`, the shell from `qs:@/qs/`, so a relative import would make a second, disconnected
  Store/Theme/I18n; found in the session-5 live check). The loader also hands `store`, `theme`, `i18n` as required
  properties. Mods talk to the daemon only through their own documents/actions.
- **Slots, faces, choices (K28):** `slot:<name>` → `qml/slots/<name>.qml`, listed in `runtime.slots` while the mod
  is enabled; `island-face:<name>` → `ModCtx::face(name, spec)` registers it with the core arbiter (transient or
  relevance signals via `ModCtx` handle), components `qml/Face.qml` + `qml/FaceExpanded.qml`;
  `choices:<source>` → `ModCtx::choices(source, fn)`. See `docs/ux/COMPOSITION.md` for the slot list.
- **i18n:** `i18n/{en,ja}/mod-<id>.toml` (one domain file per mod, so parallel work never conflicts).

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
  (refcounted, start on first subscriber), actions, island faces, background jobs (started when their
  setting wants them), settings page; frontend loads the mod's components on demand. Disabling reverses
  it and cancels the jobs; config is kept.
- **Settings values are live too.** A change of a setting reaches the mod's services and jobs at once;
  a job whose `wanted_by` setting turns off stops, and turns on again starts.
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
