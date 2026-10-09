# Card M5-notifications — `kurashi-notify` (notification server + history)

**Goal.** Implement `org.freedesktop.Notifications` (spec 1.2) in the daemon's process space as a
library: receive, store, expire, act, close — and expose it as documents. The frontend renders
toasts and the notification center from them.

**Owned paths:** `crates/kurashi-notify/`. Common rules: `docs/tasks/README.md`.

**Read:** `crates/kurashi-services/src/util.rs` (`DocSink`), `docs/PROTOCOL.md` §3,
`docs/VISION.md` (Ma, Shōjiki), the freedesktop notification spec (fetch it if needed).

**Build (zbus 5 server side):**
1. `Server::serve(conn, sink, cfg) -> (ServiceHandle, Commands)` exporting the interface at
   `/org/freedesktop/Notifications` and requesting the well-known name **only when told to**
   (`cfg.claim_name`). Capabilities: body, body-markup (sanitised subset), actions, icon-static,
   persistence, inline-reply (if cheap).
2. Model: id, app_name, app_icon, summary, body (sanitised), actions, urgency, category,
   desktop-entry, image (hint data → cached PNG path under a passed-in cache dir, never inline in
   the doc), timeout semantics (-1 default per urgency from cfg, 0 = never), replaces_id,
   transient, resident. History bounded (cfg), DND (cfg flag: store silently, critical still
   shows).
3. Documents: `svc.notifications` = `{dnd, unread, toasts:[ids currently showing], items:[…newest
   first, bounded]}`. Expiry via one timer at the next deadline (Ma), no ticking.
4. Commands: invoke_action, dismiss, dismiss_all, mark_read, set_dnd, reply.
   Emits `ActionInvoked` / `NotificationClosed` with correct reasons.

**Testing:** private `dbus-daemon` only (see `kurashi-services` tests). **Never** request
`org.freedesktop.Notifications` on the user's real bus — their running shell owns it.

**Acceptance (one command):** `cargo test -p kurashi-notify` green: Notify → doc; replaces_id;
expiry via deadline; critical ignores DND; actions round-trip with signals; close reasons; markup
sanitising (script/img stripped); image hint cached as file; GetCapabilities/GetServerInformation.
Clippy `-D warnings`.
