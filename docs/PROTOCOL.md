# IPC Protocol v1

Status: **draft** until M1 freeze (then changes require a DECISIONS entry + fixture update).
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
← {"t":"welcome","v":1,"server":"kurashid 0.1.0","caps":["undo","profiles","island"]}
```
Version mismatch → `{"t":"goodbye","reason":"version","supported":[1]}`.

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
  the last unsubscribe stops it (Ma).

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
// "forced_by" / "reason" appear only when set (crates/kurashi-core `Provenanced`).
→ {"t":"cfg.explain","id":"3","key":"theme.material.blur"}
← {"t":"cfg.why","id":"3","layers":[{"source":"default","value":true},
   {"source":"forced:capability","value":false,"reason":"compositor lacks ext-background-effect"}]}
→ {"t":"apply","id":"4","ops":[{"set":"bar.main.edge","value":"left"},{"reset":"theme.motion"}]}
← {"t":"applied","id":"4","rev":88,"undo":"tx-88"}            // or {"t":"rejected","id":"4","errors":[...]}
→ {"t":"undo","id":"5"}   /  {"t":"redo","id":"6"}
```

## 6. Actions & queries
```json
→ {"t":"act","id":"7","action":"island.next","args":{"island":"main"}}
← {"t":"done","id":"7"}                      // or {"t":"err","id":"7","kind":"...","msg":"..."}
→ {"t":"query","id":"8","kind":"launcher","q":"fire"}
← {"t":"results","id":"8","items":[...]}    // stale ids are dropped by the client
```

## 7. Errors & lifecycle
`{"t":"err","id"?, "kind":"invalid|unknown_doc|unknown_action|unavailable|internal","msg":"…"}`
Keepalive: `ping`/`pong`. Shutdown: `{"t":"bye","reason":"shutdown"}`; clients reconnect with
backoff (250 ms → 4 s) and show a veil after 2 s disconnected.

## 8. Probe subset (M0 bake-off, served by `kurashi-mock`)
| Document | Shape |
|---|---|
| `theme` | `{"tokens":{"color.surface":"#1c1b22","color.on_surface":"#e8e3d8","color.accent":"#c1323b","color.surface_alpha":0.82,"radius.md":12,"space.md":8,"font.family":"Inter","font.size.md":13,"motion.standard_ms":220,…}}` |
| `svc.clock` | `{"hh":"14","mm":"07","date":"2026-10-09","weekday":"Fri"}` (patch once per minute) |
| `svc.workspaces` | `{"outputs":{"<name>":[{"id":1,"idx":1,"focused":true,"occupied":true},…]}}` |
| `svc.audio` | `{"volume":0.5,"muted":false}`; accepts intent `audio.volume` |
| `runtime.island.main` | `{"face":"clock","faces":["clock","media"],"reason":"default"}`; actions `island.next`, `island.prev`, `island.pin` |
| `svc.media` | `{"title":"…","artist":"…","playing":true}` |
| `runtime.ui` | `{"popup":false}`; action `probe.popup.toggle` (daemon-owned "panel open" state) |
| `mods.probe` | `{"widgets":[{"id":"hello","ui":{"type":"row","children":[{"type":"icon","name":"leaf"},{"type":"text","bind":"text"}]},"state":{"text":"こんにちは"}}]}` |

Probe actions: `island.next`, `island.prev`, `island.pin`, `probe.popup.toggle`, `audio.mute.toggle`.
Mock control (bench/test only): `{"t":"mock.tick"}` advances the clock; `{"t":"mock.face","face":"media"}`
forces an island switch; `{"t":"mock.workspace","idx":2}` moves focus.
