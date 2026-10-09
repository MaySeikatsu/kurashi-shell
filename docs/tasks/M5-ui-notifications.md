# Card M5-ui-notifications — toasts + notification center

**Owned paths:** `frontend/surfaces/Toasts.qml`, `frontend/surfaces/NotificationCenter.qml`,
`frontend/components/Notification*.qml`, `i18n/{en,ja}/notifications.toml`, one line in `frontend/shell.qml`.
Common rules: `docs/tasks/README.md`.

**Common for wave-5 UI cards:** build on the frontend core API (`Store.watch/unwatch/docs/act/intent/query`, `Theme`, `I18n` — see `frontend/README.md`); token-only styling; strings via `I18n.tr` with keys in `i18n/{en,ja}/<your-domain>.toml` (you own your domain files); every animation visibility-gated; test only in `tools/bench/sandbox.sh` with a real `kurashid` (isolated XDG dirs, sandbox bus — see `frontend/test-real.sh`); add exactly one line to `frontend/shell.qml` to instantiate your surface (the lead resolves trivial conflicts); new QML types in the folder `qmldir`. Acceptance always includes: `just bench-gate` still green (idle 0 frames, budgets) and sandbox screenshots you verified.

**Build:** watch `svc.notifications` (shape in `crates/kurashi-notify` docs / report:
`{dnd, unread, toasts:[ids], items:[{id, app_name, app_icon, summary, body (b/i/u/a only), actions:[{key,label}],
urgency, time, read, image?, expires_at?}]}`). Toasts: a content-sized top-right layer surface on the
focused output, stacked cards (max 3 + "+N"), reveal on first presented frame, swipe/close →
`act notify.dismiss {id}`, action buttons → `act notify.invoke {id,key}`, hover pauses nothing
(expiry is daemon-side). Center: list grouped by app, dismiss all, DND toggle (`notify.dnd`), mark read
on open (`notify.mark_read`), opened by the island `notifications` face (`act notifications.center` sets `runtime.ui.panel = "notifications"`; the Stage shows the
center while that holds — `panel` is exclusive with `"island"`). Test: send notifications with `gdbus call --session` on the **sandbox** bus.
