# Card M5-ui-island-faces — island faces (clock, media, volume, notifications)

**Owned paths:** `frontend/components/Island.qml`, `frontend/components/faces/` (new),
`i18n/{en,ja}/island.toml`. Common rules: `docs/tasks/README.md`.

**Common for wave-5 UI cards:** build on the frontend core API (`Store.watch/unwatch/docs/act/intent/query`, `Theme`, `I18n` — see `frontend/README.md`); token-only styling; strings via `I18n.tr` with keys in `i18n/{en,ja}/<your-domain>.toml` (you own your domain files); every animation visibility-gated; test only in `tools/bench/sandbox.sh` with a real `kurashid` (isolated XDG dirs, sandbox bus — see `frontend/test-real.sh`); add exactly one line to `frontend/shell.qml` to instantiate your surface (the lead resolves trivial conflicts); new QML types in the folder `qmldir`. Acceptance always includes: `just bench-gate` still green (idle 0 frames, budgets) and sandbox screenshots you verified.

**Build:** one face component per face id, chosen by `runtime.island.main.face`: `clock`
(`HH:MM · Fri`), `media` (title — artist, small art via `art_url` when present, play state glyph),
`volume` (transient OSD: icon + level bar from `svc.audio`, muted state), `notifications` (unread
count from `svc.notifications`). Morph between faces as today (width + crossfade, interruptible,
first-frame gated); faces watch only the docs they render (refcount via `Store.watch`). Hover peek
(DESIGN-SYSTEM §8) only if it costs no idle frames. Test: `kurashi act island.next`, change volume via
`kurashi intent audio.volume 0.4` against the sandbox daemon (a fake pulse server is not available —
if `svc.audio` is `available:false` in the sandbox, test the volume face by subscribing it to a
fixture doc in a QML test harness instead and say so).
