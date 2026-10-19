# IPC Protocol v1

Status: **v1 frozen** (end of M1, K17, 2026-10-09). Changes now require a DECISIONS entry + fixture update
(`fixtures/ipc/`) + this file. Additive optional fields are allowed without a version bump.
The M0 bake-off uses the **probe subset** (§8), served by `kurashi-mock`.

## 1. Transport
- Unix stream socket `$XDG_RUNTIME_DIR/kurashi/ipc.sock` (mode 0600).
  Override with env `KURASHI_SOCKET`.
- **Framing: NDJSON** — one JSON object per line, UTF-8, `\n` terminated. Max line 4 MiB (K4).
  JSON escapes newlines inside strings, so framing is unambiguous; every frontend toolkit
  (QML `SplitParser`, GLib, tokio `LinesCodec`) handles it natively.
- Every message has `"t"` (type). Requests carry `"id"` (client-chosen string); responses echo it.

## 2. Handshake
```json
→ {"t":"hello","v":1,"client":"frontend","caps":["intents","resync"]}
← {"t":"welcome","v":1,"server":"kurashid 0.1.0","caps":["undo","profiles","island"],"instance":"3f0c9a2e"}
```
`instance` changes on every daemon start. A client reconnecting to a different instance discards
cached revisions and re-subscribes everything.
Version mismatch → `{"t":"goodbye","reason":"version","supported":[1]}`.

**Scoped connections (K38, MODS.md "Host processes").** A mod's host process says who it is with the token the daemon
handed it when it started the process (`KURASHI_SCOPE_MOD`, `KURASHI_SCOPE_TOKEN`):
```json
→ {"t":"hello","v":1,"client":"webdock-host","caps":["intents"],"scope":{"mod":"webdock","token":"6f1c2a9e4b7d0835"}}
```
A token the daemon did not issue for that mod's running host (or one already used by another live connection) →
`{"t":"goodbye","reason":"scope","supported":[1]}`. A scoped connection may `sub`/`unsub`/`resync` the mod's own
documents (`mod.<id>` and `mod.<id>.*`), `theme` and `i18n`, and `act` the mod's own actions (`<id>.*`); `ping`
as usual. Everything else (other documents and actions, `cfg.*`, `apply`, `undo`, `intent`, `query`) answers
`{"t":"err","id"?, "kind":"forbidden","msg":"…"}` and the connection stays open. The daemon counts the host as
running from this hello until the connection closes. Pinned by `fixtures/ipc/client/hello_scope.json`.

## 3. State documents (subscribe / snapshot / patch)
State is exposed as named **documents** (`config`, `theme`, `runtime.island.main`,
`svc.audio`, `svc.workspaces`, …).
```json
→ {"t":"sub","id":"1","doc":"svc.audio"}
← {"t":"snap","id":"1","doc":"svc.audio","rev":41,"data":{...}}
← {"t":"patch","doc":"svc.audio","rev":42,"ops":{"volume":0.62}}      // JSON merge-patch (RFC 7396)
→ {"t":"unsub","doc":"svc.audio"}
```
- `rev` is monotonic per document. A client that sees `rev != last+1` sends
  `{"t":"resync","doc":"svc.audio"}` and receives a fresh `snap`.
- Subscriptions are refcounted daemon-side: the first subscriber starts the backing service,
  the last unsubscribe (or disconnect) stops it (Ma).
- A `snap` **without `id`** is pushed by the server when a document is rebuilt from scratch
  (backing service restarted, compositor `Resync`): replace local state, adopt its `rev`.
- Documents never contain `null` values (absence is the only "empty"); the daemon computes
  patches as the merge-patch diff of old → new, so removed fields arrive as `null` and stale
  optional members (e.g. `forced_by`) never survive.
- Several changes to one document within a tick may be coalesced into one `patch` (clients must
  not assume one patch per change).

## 4. Intents (high-frequency interaction)
```json
→ {"t":"intent","key":"audio.volume","value":0.6,"origin":"fe-1:slider-7","coalesce":true}
```
- `coalesce:true` → daemon keeps only the latest value per key per tick (≤ 1/frame).
- Patches caused by an intent carry `"origin"`; the originating control ignores its own echo
  while dragging and settles on the final value (optimistic UI, no round-trip lag).

## 5. Config (provenance)
```json
→ {"t":"cfg.get","id":"2","key":"bar.main.edge"}
← {"t":"cfg.val","id":"2","key":"bar.main.edge",
   "v":{"value":"top","source":{"kind":"profile","name":"kanso"}}}
// source kinds: default | theme(name) | profile(name) | nix | user | forced(name); optional
// "forced_by" / "reason" / "inert_by" appear only when set (crates/kurashi-core `Provenanced`).
// forced_by = value replaced; reason without forced_by = configured but not in effect
// (inert_by names the required key, or reason "settings.pending.restart") — K21.
→ {"t":"cfg.explain","id":"3","key":"theme.material.blur"}
← {"t":"cfg.why","id":"3","layers":[{"source":"default","value":true},
   {"source":"forced:capability","value":false,"reason":"compositor lacks ext-background-effect"}]}
→ {"t":"apply","id":"4","ops":[{"set":"bar.main.edge","value":"left"},
   {"set":"bar.main.height","value":40,"output":"DP-1"},{"reset":"theme.motion"}]}
← {"t":"applied","id":"4","rev":88,"undo":"tx-88"}
← {"t":"rejected","id":"4","errors":[{"key":"bar.main.height","code":"error.range","msg":"…"}]}
→ {"t":"apply","id":"10","ops":[…],"dry_run":true}
← {"t":"preview","id":"10","diff":[{"key":"theme.palette","before":{Provenanced},"after":{Provenanced}}]}
→ {"t":"undo","id":"5"}   /  {"t":"redo","id":"6"}     // → applied (new rev, tx id) or rejected
```
- `cfg.get` / `cfg.explain` accept `"output"` for per-output keys. `cfg.why` lists every layer
  that has the key (lowest first); exactly one entry is `"active":true`.
- `apply` is atomic: any invalid op rejects the whole batch (`code` is an i18n key). `reset` of a
  section prefix removes every user key below it. Profile loads are one transaction.
- **`config` document** (subscribe like any other):
  `{"values":{"<key>":Provenanced,…},"outputs":{"<name>":{"<per-output key>":Provenanced}},
  "history":{"can_undo":bool,"can_redo":bool},"profiles":[{"name":"kanso","bundled":true},…]}`.
  Patches carry only keys whose *effective* value or provenance changed. `history` follows every
  applied change, undo, redo and profile load (whoever sent it: settings, CLI, another client);
  `profiles` is what `profile.list` answers, kept current when profile files appear or go (file
  watcher). Both added in session 5 (K27, CONTRACT rows 21–22); pinned by
  `fixtures/ipc/server/snap_config.json`.
- Profile actions (`profile.list/preview/load/save`) answer errors with `msg` = an i18n key
  (`config.error.*`, like the mods actions), never English text (K27). `preview` and `load` also answer
  `not_applied` (§6, I35); the file actions and `settings.open` are in §6.
- **`schema.settings` document**: settings metadata generated from the schema (pages → sections →
  rows, control kinds, couplings). Shape owned by `kurashi-schema`, frozen with it.
  Mod settings (K22) add one page per enabled mod with settings: id `mods.<id>`, `label` = the
  manifest name (i18n key or plain text); a disabled mod's keys carry `reason: "mods.disabled"`.
- **`mods` document** (K25, session 5 — implemented in wave 10): entries gain `running: bool` and, for
  enabled native mods, `qml: {"<provide>": "<file url>"}` (K26); `state` `disabled` means *loaded, off*.
  Loaded/on are config lists `mods.loaded` / `mods.enabled` (MODS.md "States"); actions `mod.load`,
  `mod.unload`, `mod.enable`, `mod.disable` `{id}`. A refused native enable leaves the mod `disabled` with
  `errors: [{key, path: "enable", detail}]` (`mods.error.not_declared|duplicate|enable_failed`). Disabling a native mod
  sends each of its documents a last `snap` `{available:false}`, then the document is gone (`unknown_doc`): a client
  must `unsub` it before subscribing again. `schema.settings` mod pages carry `"mod": "<id>"`
  and exist for every loaded mod. Pinned by `fixtures/ipc/server/snap_mods.json`.
- **`runtime.slots` document** (K28): `{"<slot>": [{"mod": "weather", "qml": "file:///…/qml/slots/clock.expanded.aside.qml",
  "ready": true}]}` — enabled mods' contributions per slot, ordered by mod id; `ready` = the mod's primary document (its first registered service, `mod.<id>`) is
  `available === true`; an entry is listed only while its `qml/slots/<slot>.qml` file exists. Slots: `clock.expanded.aside|day|footer`, `media.expanded.below|backdrop`,
  `notifications.expanded.header`, `quick.tiles`, `lock.aside`. A mod face (`island-face:<name>`) appears in
  `runtime.island.main.faces` like a core face; the `mods` doc `qml` map names `island-face:<name>` →
  `qml/Face.qml` and `island-face:<name>:expanded` → `qml/FaceExpanded.qml`.
- **Choices from the daemon (I9)**: a `schema.settings` row whose key declares
  `#[kurashi(choices_from = "<source>")]` carries `choices_from` and the resolved
  `choices: [{value, label, enabled?, reason?}]` (`enabled:false` + `reason` (i18n key) for an option that
  cannot work now, e.g. a backend that is not installed). `control` is `select` for a string, `pick_list`
  (ordered subset) for a string list. The daemon re-publishes `schema.settings` when a source changes.
  A configured value outside the current set keeps its value and is reported inert (`reason`
  `settings.choice.unavailable`, K21) instead of being rejected.
- **Records (K38, MODS.md "Records", rows 96–97)**: a `schema.settings` row with `type`/`control` `records` carries
  `record: {fields: [{key, type, required, default?, label, pattern?, schemes?, choices?: [{value, label}],
  range?}], unique?, item_label}`; its `default` and every value (`cfg.get`, `cfg.explain`, the `config` document)
  are arrays of objects with every declared field present (absent optional fields take their defaults on read and
  write). A refused records value keeps the `rejected` shape; its `key` names the row and field,
  `mods.<id>.<key>[<n>].<field>` (`[<n>]` alone for a row that is not a table; a repeated `unique` value names the
  later row), and `code` is `error.config.record_<problem>`. One error per op (the first problem).
- **`i18n` document**: `{"locale":"ja","fallback":"en","strings":{"<key>":"<text>"}}` — the
  frontend never reads `i18n/*.toml` itself.

## 6. Actions & queries
```json
→ {"t":"act","id":"7","action":"island.next","args":{"island":"main"}}
← {"t":"done","id":"7"}                      // or {"t":"err","id":"7","kind":"...","msg":"..."}
← {"t":"done","id":"11","data":{…}}          // actions may return data (e.g. profile.preview)
→ {"t":"query","id":"8","kind":"launcher","q":"fire"}
← {"t":"results","id":"8","items":[...]}    // stale ids are dropped by the client
```

Profile and Settings actions (session 5, W14; I25, I35, I36):
- `profile.preview {name, sections?}` and `profile.load {name, sections?}` answer, besides the diff or
  `{rev, undo}`, `not_applied: [{key, output?, reason, forced_by?}]`: the entries the profile sets that a
  forced layer holds back (`_managed.enforce` Nix values, capability and accessibility pins). `reason` is
  an i18n key (`config.forced.nix_enforced`, `settings.inert.overridden_by`, else `config.error.forced`);
  `forced_by` names the pin when one is set. The value in effect stays the forced one. K36 (B13): a load is an
  **overlay** — it replaces only the keys the profile sets (within `sections`): their user values on every output
  and earlier profiles' entries for them; every other user change and profile entry stays. A key a forced layer
  holds back keeps its user value. The preview, the load and both `profile.import` replies also carry
  `kept_user` (how many user changes the load keeps). A diff entry whose value stays and only its source changes carries
  `same_value: true` (I64; absent otherwise — pinned by `fixtures/ipc/server/preview_same_value.json`).
- `profile.export {name, path}`: writes profile `name` (user or bundled) to the absolute `path` as a profile
  file, without its machine-local entries: a per-output value (`config.export.per_output`) and a value that
  names a place (an absolute or `~` path, a `:`-joined list of them, or a list holding one:
  `config.export.path`). Answers `{path, left_out: [{key, output?, reason}]}`.
- `profile.import {path, apply?}`: reads the profile file at the absolute `path` (its name is the file stem,
  checked like a profile name; a stem that names a saved or bundled profile is refused, `invalid`
  `config.error.profile_name_taken`, row 101). Without `apply` it changes nothing and answers the review
  `{name, diff, not_applied, diagnostics}` (`diagnostics`: the file's skipped entries, `file`, `key`, `reason`).
  `apply: true` loads it as one undoable transaction (`{name, rev, undo, not_applied, diagnostics}`); a file
  that is not there or not a file is `config.error.profile_unreadable`, a relative path `config.error.profile_path`.
- `settings.open {key?}`: opens Settings (the Quickshell window in `settings/`) on the setting `key`. A window
  that runs jumps to the row (`qs -p <dir> ipc call settings jump <key>`); otherwise one starts with
  `KURASHI_SETTINGS_KEY=<key>` (detached, no shell). Answers `{opened: "launched"|"jumped"|"open"}`; `open`
  is a running window and no key. An unknown key is `invalid` with `error.config.unknown_key` (the schema's
  message, `{key}` filled in). `unavailable` with `error.settings.not_installed` (no `shell.qml` in the
  package's `settings/`) or `error.settings.no_runtime` (no `qs` on the daemon's PATH). A `page` argument is
  refused (`error.args.invalid`): Settings cannot start on a page yet.
- Island face offers (`schema.settings`, `island.main.faces` and the like): each face carries a label, the
  catalogue key `config.face.<id>` for a core face and the providing mod's name for a mod's face (I37).

## 7. Errors & lifecycle
`{"t":"err","id"?, "kind":"invalid|unknown_doc|unknown_action|unavailable|forbidden|internal","msg":"…"}`
(`forbidden`: outside a scoped connection's scope, §2).
Keepalive: `ping`/`pong`. Shutdown: `{"t":"bye","reason":"shutdown"}`; clients reconnect with
backoff (250 ms → 4 s) and show a veil after 2 s disconnected.
A client that stops reading lets its reply queue fill (1024 messages): the daemon sends
`{"t":"bye","reason":"overflow"}` and closes; treat any `bye` as end of session and reconnect.
If a connection falls behind the broadcast ring, the daemon re-sends a full `snap` (no `id`) for
every document that connection subscribes; clients already resync by revision.

`svc.network` `{state, wifi_enabled, primary?:{kind, name, strength?}}` with action `network.wifi {on}` (sets NM `WirelessEnabled`; refusal → `unavailable` + i18n key; the document follows NM, never optimistically). `svc.power` `{available, present, on_battery, percent?, state?, time_to_empty_s?, time_to_full_s?}`.

Further kurashid documents (wave 7): `svc.tray` `{available, items:[{id, title, icon_name, status,
has_menu, item_is_menu?, icon_pixmap?, tooltip?, icon_theme_path?}]}` (`item_is_menu`: SNI `ItemIsMenu`,
present only when true — the item only offers its menu, so a left click opens it; row 20) with actions `tray.{activate,secondary,scroll,
menu,menu_event}`; `svc.bluetooth` `{available, powered?, discovering?, devices?:[…]}` with actions
`bluetooth.{power,connect,disconnect,scan}`. Both start on first subscriber; their actions never
start them (`error.service.not_running`). Shapes pinned by `fixtures/ipc/server/snap_{tray,bluetooth}.json`.

## 8. Probe subset (M0 bake-off, served by `kurashi-mock`)
| Document | Shape |
|---|---|
| `theme` | `{"tokens":{"color.surface":"#1c1b22","color.on_surface":"#e8e3d8","color.accent":"#c1323b","color.surface_alpha":0.82,"radius.md":12,"space.md":8,"font.family":"Inter","font.size.md":13,"motion.standard_ms":220,…}}` |
| `svc.clock` | `{"hh":"14","mm":"07","date":"2026-10-09","weekday":"Fri"}` (patch once per minute; kurashid sends `weekday` in its locale from i18n domain `clock`) |
| `svc.workspaces` | `{"outputs":{"<name>":[{"id":1,"idx":1,"focused":true,"occupied":true},…]}}` |
| `svc.audio` | `{"volume":0.5,"muted":false}`; accepts intent `audio.volume`. kurashid adds `available`, `sinks:[{id, name, description, default}]` and action `audio.sink.default {id}` (quick settings, K24). W13 adds `sources:[{id, name, description, default}]` (inputs, monitors left out), `source` (the default input, with `volume` and `muted`) and `streams:[{id, app, icon?, volume, muted}]` (playing applications, PulseAudio sink inputs); all three absent while audio is unavailable. Actions `audio.source.default {id}` (`error.audio.no_such_source`), `audio.stream.volume {id, value}` (`0..1.5`; `error.audio.no_such_stream`), `audio.stream.mute {id, on?}` (flips without `on`), `audio.mic.mute.toggle`. Unknown ids are refused by kurashid before the server is asked |
| `svc.network` | `{state, wifi_enabled, primary?:{kind, name, strength?}, airplane?}` (`svc.network` in §7). W13 adds `airplane` (true only while wifi and mobile broadband are both off; absent when mobile broadband's switch cannot be read). Actions `network.wifi {on}`, `network.airplane {on}`, `network.disconnect` (deactivates the primary; nothing connected is not an error), `network.connect {ssid}`: a saved network joins; any other is `unavailable` with `error.network.needs_secret` (secured, not saved), `error.network.not_saved` (open, not saved) or `error.network.not_found` (not in range). Refusals `error.network.refused`, failures `error.network.unavailable`. The document follows NetworkManager, never the call |
| `svc.network.scan` | `{available, networks?, reason?}`. `networks`: each SSID once (its strongest access point), `[{ssid, strength, secure, known, active}]`, the active one first, then by strength; `known` = a saved profile for it. Refcounted (K-card W13): the first subscriber starts a rescan at once and one every 15 s, the last unsubscribe stops them (Ma). Until the first answer the document is `{}`. `available:false` with `reason` (i18n key: `error.network.wifi_off`, `error.network.no_wifi_device`, `error.network.unavailable`) when nothing can be listed; `networks` is then absent |
| `svc.power` | `{available, present, on_battery, percent?, state?, time_to_empty_s?, time_to_full_s?, profile?, profiles?, profile_reason?}` (the UPower part as in §7). W13 adds the power-profiles-daemon part (`net.hadess.PowerProfiles`): `profile` (active) and `profiles` (offered, daemon order, e.g. `["power-saver","balanced","performance"]`). While the daemon is absent they are left out and `profile_reason` (`error.power.profiles_unavailable`) says why. Action `power.profile {name}`: a name the daemon does not offer is `invalid` (`error.power.no_such_profile`); `error.power.refused` and `error.power.unavailable` otherwise |
| `runtime.island.main` | `{"face":"clock","faces":["clock","media"],"reason":"default","pinned":false,"overflow":0}`; W13 adds `secondary?` (the next live activity of another face, minimal beside the pill), `until?`, `detail?` (`{face: peek line}`, composed by the daemon) and `stale_at?` (`{face: wall-clock ms}`: the face's content is only "as of" that time). `detail` and `stale_at` list the live faces and the shown face, and are absent when empty; `overflow` counts live activities beyond `face` and `secondary`. Core transient faces: `volume` (kind `volume`; `detail` names a moved or non-usual output), `brightness`, `power` (kinds `power`: charger in or out, with charge and time left or to full; `battery`: low at 10 %, critical at 5 %, once per crossing), `bluetooth` (a device connected, with its battery). Actions `island.next`, `island.prev`, `island.pin`. Pinned by `fixtures/ipc/server/snap_island.json` |
| `svc.media` | `{available, title, artist, playing, player, rate, can:{seek,next,prev,play,pause}, players:[{id,name,playing,active}], position_us?, position_at_ms?, album?, length_us?, art_url?}`. W13: `position_us` is the shown player's `Position` (µs) and `position_at_ms` the wall clock (ms since the epoch) of its read. MPRIS does not signal `Position`, so kurashid reads it only when the shown player changes, its track, play state or rate changes, it sends `Seeked`, and at the first subscription: never on a timer. The view interpolates from (`position_us`, `rate`, `position_at_ms`) while `playing`; no `length_us` (a live stream) means no progress. `rate` is 1.0 when the player does not report one. `can` follows the player's `CanSeek`, `CanGoNext`, `CanGoPrevious`, `CanPlay`, `CanPause`. Actions `media.play_pause`, `media.next`, `media.prev`; `media.seek {offset_us}` (relative) and `media.set_position {us}` (absolute, on the shown track, which needs its `mpris:trackid`): both refused with `unavailable` and `error.media.cannot_seek` while `can.seek` is false, and `unavailable` `error.media.no_player` while no player is shown; bad values are `invalid` `error.args.invalid`. `media.player.select {id}` shows a listed player (`invalid` `error.media.no_such_player` otherwise). Pinned by `fixtures/ipc/server/snap_media.json` |
| `runtime.ui` | `{"popup":false}`; action `probe.popup.toggle` (daemon-owned "panel open" state). kurashid adds `panel` (`""`/`"island"`/`"notifications"`/`"session"`/`"tray"`/`"quick"`), `launcher` (bool), `tray` (item id whose menu the `tray` panel shows, `""` otherwise, K23) and `face` (the island face whose expanded view the `island` panel shows, latched when `island.expand {island?}` opened it — default instance `main`; `""` otherwise or when the island has no document, K24); actions `island.expand`, `notifications.center`, `session.menu`, `quick.toggle` (quick settings, K24), `tray.menu.open {id}`, `mod.panel.open {id, panel}` (a native mod's Stage panel: `panel` = `"mod:<id>:<panel>"`, toggles like the others; refused unless mod `<id>` is enabled and its manifest provides `panel:<panel>`, K26), `launcher.toggle`, `ui.close`; K35: `peek` (absent, or `{source, output, x, w}` — the hover/focus peek the Stage shows under a bar widget while no panel is open; `source` = `mod:<id>:<name>` (manifest `peek:<name>`), `tray:<item>` or `island:<instance>`; `x`, `w` in the output's logical px), set by action `ui.peek {source, output, x, w, edge?, y?, h?}` and removed by `ui.peek {}` (I67: `edge` = the bar's edge, `top` when absent; a `left`/`right` bar also gives the widget's `y` and `h`, and the peek carries them) (refused with `ui.error.peek_under_card` while a panel is open, `mods.error.peek_unavailable` for a mod that is off or lacks it); opening any panel removes it, and so does disabling its mod. Pinned by `fixtures/ipc/server/snap_runtime_ui.json` and `snap_runtime_ui_peek.json` |
| `mods.probe` | `{"widgets":[{"id":"hello","ui":{"type":"row","children":[{"type":"icon","name":"leaf"},{"type":"text","bind":"text"}]},"state":{"text":"こんにちは"}}]}` |
| `bindings` | `{"island.main":{"left":{"action":"island.expand","source":"default"},…}}` (unbound slots absent); action `input.dispatch {component, slot, args?}` |
| `svc.brightness` | `{"present":true,"device":"…","value":500,"max":1000,"percent":50}`; actions `brightness.up`/`brightness.down` `{step?}` (fraction of full scale, default 0.05) |
| `svc.brightness` (kurashid) | same shape; intent `brightness.set` (0..1); actions `brightness.up`/`brightness.down` and `audio.volume.up`/`audio.volume.down` take optional `{step}` (0..1, default 0.05; volume keys stop at 100 %); each change shows the transient island face `brightness`/`volume` (TTL `island.main.ttl`) |
| `runtime.lock` | `{"locked":false,…}` (static in the mock; lock-surface results from the mock are not evidence) |

Probe actions: `island.next`, `island.prev`, `island.pin`, `probe.popup.toggle`, `audio.mute.toggle`.
Mock parity (M0.8): also `island.expand`, `notifications.center`, `session.menu`, `launcher.toggle`,
`ui.close`, `session.lock`, `session.{suspend,logout,reboot,poweroff}` (error msg
`session.confirm_required` unless `{confirm:true}`). Unknown docs/actions log `unknown_doc`/`unknown_action`.
M0.9: `svc.notifications` (seeded, kurashid shape) + `notify.{dismiss,invoke,mark_read,dnd}` (W13: `notify.dnd {on?, until?}`, `until` = ms since the epoch: do-not-disturb ends by itself then, and `svc.notifications` carries `dnd_until` only while such an end is set), `query launcher`
over a fake index + `launcher.launch` (logged, not spawned), random `welcome.instance`, and
`kurashi-mock --fixed-time HH:MM` (clock pinned to 2026-10-09 at that time, never ticks).
Action `mock.notify {summary, body?, app_name?, urgency?, actions?}` adds a notification. W13: action `mock.island {…}` merges fields into `runtime.island.main` (`secondary`, `overflow`, `detail`, `stale_at`; `null` removes one), so a frontend can show the island's secondary and overflow states. W16 (row 83): `svc.workspaces` marks `focused` only on the focused output's workspace, and action `mock.focus {output}` moves focus (`invalid` for an unknown output), so a frontend's per-output choice (B14: the Stage follows focus) can be tested with two outputs.
Mock control (bench/test only): `{"t":"mock.tick"}` advances the clock; `{"t":"mock.face","face":"media"}`
forces an island switch; `{"t":"mock.workspace","idx":2}` moves focus.
