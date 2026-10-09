# frontend (Quickshell / QML, K3)

Thin view over the kurashid IPC socket: subscribes, renders, sends intents/actions. No business
logic, polling or `Process` here (CLAUDE.md rules 1, 5).

## Run (sandbox only, never the real display)
```sh
nix develop
cargo build --release -p kurashi-mock -p kurashi
eval "$(tools/bench/sandbox.sh start dev)"
target/release/kurashi-mock --outputs HEADLESS-1 &
qs -p frontend &            # grim frontend/shots/x.png to look
tools/bench/sandbox.sh stop dev
```
Acceptance: `python3 tools/bench/measure.py --name frontend --warmup 10 --idle 30 -- qs -p frontend`.

## Layout
- `shell.qml` one `Bar` per output (Variants over `Quickshell.screens`, hotplug-safe) + ONE `Stage`
  retargeted to the focused output (focused workspace's output, latched while open).
- `core/` singletons: `Store` (IPC, merge-patch, revision-gap resync, 250 ms to 4 s reconnect,
  `connected`/`live`), `Theme` (the only reader of `theme.tokens`), `I18n` (`tr(key)`).
- `components/` Button, IconButton, Slider, Chip, ProvenanceChip, Island, ModNode (mod UI tree).
- `surfaces/` `Bar`; `Stage` (content-sized overlay layer, top-centred under the Island; permanently mapped but
  transparent with empty input/blur regions while hidden: map/unmap cycles leaked heap, K16;
  reveal = slide on first presented frame, no group opacity).
- Strings: `i18n/{en,ja}/frontend.toml`. Until the daemon serves them, `tr` returns the key.

## Conventions
- Style only from `Theme` tokens; never branch on theme/profile names.
- Components are presentational: signals out, props in; surfaces turn signals into `Store.act/intent`.
- Every animation/timer is gated on visibility or on an active interaction; idle = zero frames.
- New QML types must be added to the folder's `qmldir`. Never assign `anchor.item` dynamically.
- Reconnect veil: `Store.live` false keeps last state, dims content (`opacity.stale`), shows a glyph.

## Core API (`core/`)
- `Store.watch(doc)` / `unwatch(doc)` refcounted; declaratively `Watch { doc: "svc.media"; active: cond }`.
  Surfaces watch only what they render. `Store.docs[doc]` is reactive; docs the daemon does not
  serve (`unknown_doc`) stay absent, with no retry.
- `Store.act(action, args, cb)` -> `cb(done, err)` (`done.data` for results); `Store.query(kind, q, cb)`
  -> `cb(items, err)`, only the newest query per kind is answered; `Store.intent(...)` unchanged.
- Reconnect: fresh Socket per attempt (a reused one stayed silent after the first failure), all
  watched docs re-subscribed on welcome; `instance` change drops cached docs.
- `I18n.tr` reads the daemon's `i18n` doc. Island `reason` `manual` counts as `user` (`byUser`).
- Real-daemon smoke test: `nix develop -c frontend/test-real.sh` (screenshots in `shots/real/`).
