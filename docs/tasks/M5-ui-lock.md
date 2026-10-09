# Card M5-ui-lock — lock screen (ext-session-lock)

**Owned paths:** `frontend/surfaces/Lock.qml`, `frontend/components/Lock*.qml`,
`i18n/{en,ja}/lockui.toml`, one line in `frontend/shell.qml`. Common rules: `docs/tasks/README.md`.

**Common for wave-5 UI cards:** build on the frontend core API (`Store.watch/unwatch/docs/act/intent/query`, `Theme`, `I18n` — see `frontend/README.md`); token-only styling; strings via `I18n.tr` with keys in `i18n/{en,ja}/<your-domain>.toml` (you own your domain files); every animation visibility-gated; test only in `tools/bench/sandbox.sh` with a real `kurashid` (isolated XDG dirs, sandbox bus — see `frontend/test-real.sh`); add exactly one line to `frontend/shell.qml` to instantiate your surface (the lead resolves trivial conflicts); new QML types in the folder `qmldir`. Acceptance always includes: `just bench-gate` still green (idle 0 frames, budgets) and sandbox screenshots you verified.

**Build:** Quickshell `WlSessionLock` with one lock surface per output, active while
`runtime.lock.locked`; password field (echo off) → `intent lock.submit` (value = text,
`coalesce:false`; clear the field immediately after sending; never store it in a property longer than
needed), `runtime.lock` shows busy/failures/`message_key`/`retry_in_ms` (count down locally, no
daemon polling), follow-up PAM prompts (`prompt`, `prompt_echo`), clock + date (svc.clock), current
media (svc.media) small; unlock only when `locked` goes false. Lock trigger: `act session.lock`.
**Testing:** the daemon's PAM backend must never see real credentials — test the UI flow only with a
daemon built with a test hook or by observing `runtime.lock` transitions after `act session.lock`
and a wrong password; verify the lock surface covers every sandbox output; screenshot locked state +
wrong-password message. If headless sway lacks ext-session-lock, report it and screenshot the
fallback preview window instead.
