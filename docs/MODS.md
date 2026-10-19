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
is refused by the validator), `records` (row 89, K38: a list of tables whose fields the manifest declares, below).

**Records** (`type = "records"`): `default` is an array of tables (usually `[]`); optional `unique = "<field>"` (no two
rows share that field's value) and `item_label = "<field>"` (what a row shows in Settings; the first string field
otherwise). Each `[[setting.field]]` has `key`, `type` (`string` · `url` · `enum` · `bool` · `int`), optional `label`
(i18n key), `required` (default false), `default` (required unless `required = true`), and per type: `pattern = "slug"`
(string: `[a-z0-9-]`, 1..32), `schemes = [...]` (url: absolute, one of these schemes), `choices` (enum), `range` (int).
The value is a TOML array of tables in the config and a JSON array of objects in documents and `cfg.*`, every field
present (absent optional fields take their defaults; unknown fields are refused). Errors name the row and field:
`mods.<id>.<key>[<n>].<field>`. Settings shows a records editor (rows with `item_label`; add, edit in a form of the
fields' controls, move up/down, remove), and every change is one `apply set` of the whole list. Nix sets the list like
any key (the `nix` layer, K15). Example (the web dock's pins):
```toml
[[setting]]
key = "pins"
type = "records"
default = []
unique = "id"
item_label = "title"
  [[setting.field]]
  key = "id"
  type = "string"
  required = true
  pattern = "slug"
  [[setting.field]]
  key = "target"
  type = "url"
  required = true
  schemes = ["https", "http", "file", "mod"]
  [[setting.field]]
  key = "view"
  type = "enum"
  choices = ["default", "mobile", "desktop"]
  default = "default"
```

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
ids, `enabled ⊆ loaded`; default both empty — no bundled mod is on by default) — so they persist, travel with provenance,
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
  `reason` (an i18n key) in `running_reasons` while it runs. A job with nothing to do says so with `JobCtx::set_active(false)` (I48): it keeps running, but its reason leaves `running_reasons` until it calls `set_active(true)` (sysmon's paused watch, weather's rain watch without a saved place). A job whose body returns or panics stops
  running; a `wanted_by` that is not a bool setting of the mod refuses the enable. Weather's rain alerts and sysmon's trouble watch are jobs; a poll the user can see is never a
  bare task.
- **Refused without code (B15):** a native mod whose manifest declares daemon code (`service:`,
  `action:`, `island-face:`, `choices:`, `job:`) is refused with `mods.error.not_built` when this build
  links no `NativeMod` for it: it stays `disabled` with that reason in `errors`, and the config keeps
  its list entry. Frontend-only provides (`widget:`, `panel:`, `peek:`, `slot:`, `palette:`, `decor:`, `i18n`)
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
  `choices:<source>` → `ModCtx::choices(source, fn)`; `ModCtx::slot(name)` → a `SlotHandle` whose `set_reason(Some(key))`
  marks the contribution as needing setup (row 72; `runtime.slots` `reason`). See `docs/ux/COMPOSITION.md` for the slot list.
- **i18n:** `i18n/{en,ja}/mod-<id>.toml` (one domain file per mod, so parallel work never conflicts).

### Host processes (K38)
A native mod can run a process of its own — the web dock's web engine — that the daemon starts, stops and supervises,
and that talks to the daemon over a **scoped connection** (PROTOCOL §2): only the mod's documents and actions, plus
`theme` and `i18n`. Nothing runs until the mod starts it.
- **Manifest:** `provides = ["host:<name>"]` and the program as a capability, `exec:<binary>` (a file name, looked up in
  the daemon's `PATH`). `host:` is daemon code (B15): an unlinked mod that declares one is refused.
- **API** (`kurashi-mod-api`): `ctx.host(name, HostSpec { binary, args, env }) -> HostHandle` (refused unless the
  manifest provides `host:<name>` and declares `exec:<binary>`). `args` and env values may name `{mod_dir}` (the mod's
  folder), `{data_dir}` (`$XDG_DATA_HOME/kurashi/<id>`), `{cache_dir}` (`$XDG_CACHE_HOME/kurashi/<id>`) and `{state_dir}`
  (`$XDG_STATE_HOME/kurashi/<id>`); the daemon expands them and creates the three directories. `HostHandle` is `Clone`:
  `start()` (idempotent), `stop()`, `state() -> watch::Receiver<HostState>`; `HostState` = `Off` · `Starting` · `Ready`
  · `Failed { reason, detail }` · `Missing` (reasons are i18n keys: `mods.host.missing`, `mods.host.failed`).
- **Start:** a binary not on `PATH` → `Missing`. Otherwise the daemon spawns it as a program (no shell) in its own process
  group, outside the daemon's, stdin closed, stdout and stderr appended to `{state_dir}/host-<name>.log` (cut to its last
  1 MiB at each start), with `KURASHI_SOCKET`, `KURASHI_SCOPE_MOD=<id>` and a fresh `KURASHI_SCOPE_TOKEN` (128 bits, hex)
  added to the spec's env. `Starting` until a scoped hello with that token arrives, then `Ready`; the connection closing
  while the process lives returns to `Starting` (the host reconnects with the same token).
- **Exit:** an exit the mod did not ask for restarts the host once; a second one within 10 minutes is `Failed` (`detail`:
  the exit status and the log path). `stop()` sends SIGTERM to the group and SIGKILL after 3 s, revokes the token and is
  `Off`. Disabling the mod and shutting the daemon down stop every host.
- **Settings writes:** `ctx.settings_writer() -> SettingsWriter` (`Clone`); `writer.set(key, value).await` writes
  `mods.<id>.<key>` to the user layer as one undoable transaction (the same path as `apply set`), refused with the
  config's error key when the key is forced or the value invalid. For a mod action that changes its own setting (the
  web dock's mobile/desktop toggle).

### First native mod: wallpaper (K26)
Rendering by an external daemon — **awww** (or **swww**), chosen by `mods.wallpaper.backend`
(`choices_from = "wallpaper.backends"`: each installed backend enabled, a missing one disabled with its
reason, I9). The mod's service (document `mod.wallpaper`: per output `{path, fit}`, `library` count,
`backend {id, available, reason?}`) starts the backend daemon if needed, sets images per output
(`<backend> img <path> --outputs <name> --resize <fit> --transition-type …`), and owns
`wallpaper.set {path, output?}`, `wallpaper.next/prev {output?}`. Settings: `folders` (list), `fit`,
`transition`, `rotate` (minutes, 0 = off; the timer exists only while > 0 and the mod is on).
Capabilities `exec:awww`, `exec:swww`, `fs:scoped` (K33).

Shapes (contract row 67): `mod.wallpaper` also carries `theme: {image?}` (the picture last applied *with*
its theme; `image` absent while there is none — documents carry no `null`, B25) and `favourites: [{image, scheme?, variant?}]` (a saved look). `wallpaper.set` takes
`{path, output?, origin?: {x, y}, theme?}` (`theme: true` makes the picture the theme's: the mod records
it in `theme.image`); `wallpaper.favourite {image, scheme?, variant?}`; `wallpaper.thumbs` rows carry
`pair: {role, partner}` (light/dark pairs) and a response names its `folder`, `root` and `children`; the first page (offset 0) also carries `cache: {bytes}` (the thumbnail cache's size; absent when unreadable, row 105);
`wallpaper.preview {path, scheme?}` is a dry run of the theme source (palette roles, mono, seed, axes).

**Theme source `wallpaper` (K34).** `theme.colors.palette = "wallpaper"` takes the colours of
`mod.wallpaper.theme.image` (kurashi-theme `Source::WallpaperFile`, extracted on a blocking thread and
cached by path + mtime + size). The choice is offered in `palettes` while the mod serves its document. While
the palette is chosen the daemon holds a subscription to `mod.wallpaper` (its service fills the hub only for
subscribers); without a picture — the mod off, or nothing applied with its theme yet — the default palette
is in effect and the theme document says so (note `theme.note.wallpaper_waiting`; the key's reason is
`settings.choice.unavailable` while the mod is off). Picker: a Stage panel (`cardWidth` up to 720 px,
contract row 66). Wallhaven: later (BACKLOG D3).

### Web dock (K38, `docs/ux/webdock.md`)
Mod `webdock` (native, off by default): pins at a screen edge, sites shown by the **web host** (`host:web`: the patched
Quickshell `qs-webengine` running `{mod_dir}/host/shell.qml`, K39), kurashi views drawn by the shell (later wave).
Capabilities `network`, `exec:qs-webengine`, `exec:xdg-open`, `fs:scoped`.

**Document `mod.webdock`** (fixture `fixtures/ipc/server/snap_mod_webdock.json`; absent keys, no `null`):
`{available, mode: hidden|compact|extended, shown?, size: phone|large, edge: right|left|top|bottom, output?,
geometry {strip, width, large}, keep: [pin id], pins: [pin], host {state: off|starting|ready|failed|missing, reason?,
detail?}, dirs {profiles, icons}}`. A **pin** is `{id, kind: web|view, title, target, view?, profile?, loaded?, icon?,
audible?, blocked?: [permission], error?}`: `kind` follows `target` (`mod:<id>:<panel>` → view, `https`, `http`,
`file` → web); for web pins `view` is the effective view (the pin's, or `default_view` when it says `default`) and
`profile` the effective profile (the pin's, or its id); `loaded`, `icon`, `audible`, `blocked`, `error` come from the
host's reports. QtWebEngine sets the user agent per profile, so **pins that share a profile share its view**: the first
of them in the list decides, and `webdock.view` writes the view to all of them. `geometry.strip` is the strip's width (56
until the shell's strip exists), `width` the phone width in px, `large` a percentage of the output.

**Actions:** `webdock.open {pin, output?}` (extended, `shown` = pin; starts the host for a web pin) ·
`webdock.collapse {}` (compact, `shown` cleared) · `webdock.hide {}` (hidden, `shown` kept) · `webdock.toggle
{output?}` (hidden → extended(`shown`) or compact; else hidden) · `webdock.size {size?}` (phone|large; no argument
toggles) · `webdock.view {pin, view: mobile|desktop}` (settings write, undoable) · `webdock.open_external {url}`
(`xdg-open`; http, https only). An unknown pin is `invalid` with `webdock.error.unknown_pin`. **Host reports**
(the host's scoped connection): `webdock.host.loaded {pin, icon?}` (icon: a file under `dirs.icons`) ·
`webdock.host.unloaded {pin}` · `webdock.host.audible {pin, on}` · `webdock.host.blocked {pin, permission}`
(`camera|microphone|location|notifications|screen|clipboard|download|other`; cleared by the next `loaded`) ·
`webdock.host.new_window {pin, url}` (→ `open_external`) · `webdock.host.crashed {pin}` (`error` =
`webdock.error.crashed` until the next `loaded`).

**Lifecycle (daemon):** the host starts when a web pin becomes `shown`. `keep` lists the web pins the host keeps
loaded, most recently shown first: the shown pin, then up to `max_loaded` in all; an audible pin is never dropped. The
idle clock runs while no web pin is shown and none is audible; after `unload_after` minutes (0 = never while the mod is
on) the daemon stops the host, empties `keep` and every `loaded`. A view pin never starts the host.

**Host (QML, `mods/webdock/host/`; row 95):** it imports the shell's core through a link in its own folder,
`host/core` → `../../../frontend/core` (Quickshell refuses imports that leave a config root; the link keeps one copy of
Store/Theme/I18n), and draws its own small controls (`frontend/components` would load a second set of singletons). One layer-shell card on `output` (else the first screen) at `edge`, margin
`geometry.strip`, while `mode` is `extended` and `shown` is a web pin: phone = `width` × min(2 × `width`, output height
− 2 gaps), large = `large` % of the output's width × the full height − 2 gaps. One `WebEngineView` per pin in `keep`,
created when first shown, destroyed when it leaves `keep` (→ `unloaded`); views not shown are hidden and `Frozen` unless
`recentlyAudible`. One profile per effective profile name (storage `dirs.profiles/<profile>`); mobile view = the
engine's user agent with an Android platform and `Mobile`, client hints `mobile` on; privacy settings per
`docs/ux/webdock.md` "Privacy" (Chromium switches via `//@ pragma DefaultEnv QTWEBENGINE_CHROMIUM_FLAGS = …`).

**Settings:** `pins` (records, W17-records: `id` slug unique, `title`, `target` url with schemes https, http, file, mod,
`view` default|mobile|desktop, `profile`, `icon`), `default_view` (mobile|desktop, mobile), `width` (360..720 px, 412),
`large` (50..95 %, 90), `edge` (right|left|top|bottom, right), `unload_after` (0..1440 min, 60), `max_loaded` (1..12, 4).

## Lifecycle
- **Enable/disable is live.** Enabling: daemon validates manifest → registers services
  (refcounted, start on first subscriber), actions, island faces, background jobs (started when their
  setting wants them), settings page; frontend loads the mod's components on demand. Disabling reverses
  it and cancels the jobs; config is kept.
- **Settings values are live too.** A change of a setting reaches the mod's services and jobs at once;
  a job whose `wanted_by` setting turns off stops, and turns on again starts.
- Bundled mods default **off** (Ma); `easter-eggs` joins the defaults once it has code (B15).
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
widgets (bar placeable; a widget or island face may declare `property bool vertical`, which the bar sets on a left
or right edge — the component then draws its vertical form within its own `implicitHeight`, never rotated text; one
that does not declare it is clipped to its slot, row 107) · peeks (`peek:<name>` → `qml/Peek.qml`, shown by the Stage under the widget on
hover/focus via `ui.peek {source: "mod:<id>:<name>", output, x, w}`, K35) · island faces · panels (stage) · settings · actions · launcher
providers · services · decor packs (slots + recipe) · lock scenes · palettes · app-theme
templates · i18n strings.
